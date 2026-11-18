// wallpaper.c — user-selectable wallpaper: PNG decode, mode scaling, config file.
//
// DevOS rule (R6): har user apna wallpaper badal sake, aur reboot ke baad bhi rahe.
// Config do jagah padhi jaati hai:
//   /etc/devos/desktop.conf          (system default)
//   $HOME/.config/devos/desktop.conf (user — isi me Settings se likha jaata hai)
// Keys: wallpaper=/path/to.png   wallpaper_mode=cover|fit|stretch|center|tile
//
// Image decode libpng se hota hai (rootfs me libpng16 maujood hai). JPEG abhi nahi —
// honest limitation, PNG hi support hai.
#define _GNU_SOURCE
#include "devo.h"
#include <dirent.h>
#include <math.h>
#include <png.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define WP_MAX_LIST 16
#define WP_THUMB_W 150
#define WP_THUMB_H 84

const char *wp_mode_name(int mode) {
    switch (mode) {
    case WP_FIT: return "fit";
    case WP_STRETCH: return "stretch";
    case WP_CENTER: return "center";
    case WP_TILE: return "tile";
    default: return "cover";
    }
}

int wp_mode_parse(const char *s) {
    if (!s) return WP_COVER;
    if (!strcmp(s, "fit")) return WP_FIT;
    if (!strcmp(s, "stretch")) return WP_STRETCH;
    if (!strcmp(s, "center")) return WP_CENTER;
    if (!strcmp(s, "tile")) return WP_TILE;
    return WP_COVER;
}

static void mkdirs(const char *path) {
    char tmp[600];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p != '/') continue;
        *p = 0;
        mkdir(tmp, 0755);
        *p = '/';
    }
    mkdir(tmp, 0755);
}

void wp_config_path(char *out, size_t n) {
    snprintf(out, n, "%s/.config/devos/desktop.conf", home_dir());
}

static void trim(char *s) {
    char *p = s;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t l = strlen(s);
    while (l && (s[l - 1] == ' ' || s[l - 1] == '\t' || s[l - 1] == '\r' || s[l - 1] == '\n'))
        s[--l] = 0;
}

static void parse_conf(const char *path, Wallpaper *wp) {
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[700];
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '#') continue;
        char *eq = strchr(line, '=');
        if (!eq) continue;
        *eq = 0;
        char *k = line, *v = eq + 1;
        trim(k); trim(v);
        if (!strcmp(k, "wallpaper"))
            snprintf(wp->path, sizeof wp->path, "%s", v);
        else if (!strcmp(k, "wallpaper_mode"))
            wp->mode = wp_mode_parse(v);
    }
    fclose(f);
}

// PNG -> XRGB8888 (DRM ka pack: b | g<<8 | r<<16)
static uint32_t *png_rgb(const char *path, int *ow, int *oh) {
    png_image img;
    memset(&img, 0, sizeof img);
    img.version = PNG_IMAGE_VERSION;
    if (!png_image_begin_read_from_file(&img, path)) return NULL;
    img.format = PNG_FORMAT_RGB;
    size_t sz = PNG_IMAGE_SIZE(img);
    unsigned char *buf = malloc(sz ? sz : 1);
    if (!buf) { png_image_free(&img); return NULL; }
    if (!png_image_finish_read(&img, NULL, buf, 0, NULL)) {
        free(buf);
        png_image_free(&img);
        return NULL;
    }
    int w = (int)img.width, h = (int)img.height;
    uint32_t *px = malloc((size_t)w * h * 4);
    if (!px) { free(buf); png_image_free(&img); return NULL; }
    for (size_t i = 0, n = (size_t)w * h; i < n; i++) {
        unsigned char r = buf[i * 3 + 0], g = buf[i * 3 + 1], b = buf[i * 3 + 2];
        px[i] = (uint32_t)b | ((uint32_t)g << 8) | ((uint32_t)r << 16);
    }
    free(buf);
    png_image_free(&img);
    *ow = w;
    *oh = h;
    return px;
}

// src ko screen (W x H) par mode ke hisaab se bake karo
static void scale_into(uint32_t *dst, int W, int H, const uint32_t *src,
                       int sw, int sh, int mode) {
    if (sw <= 0 || sh <= 0) return;
    uint32_t bg = 0x00100a06; // halka neela-black (XRGB)
    for (size_t i = 0, n = (size_t)W * H; i < n; i++) dst[i] = bg;

    if (mode == WP_TILE) {
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
                dst[(size_t)y * W + x] = src[(size_t)(y % sh) * sw + (x % sw)];
        return;
    }
    if (mode == WP_STRETCH) {
        for (int y = 0; y < H; y++) {
            int sy = (int)((long long)y * sh / H);
            if (sy >= sh) sy = sh - 1;
            for (int x = 0; x < W; x++) {
                int sx = (int)((long long)x * sw / W);
                if (sx >= sw) sx = sw - 1;
                dst[(size_t)y * W + x] = src[(size_t)sy * sw + sx];
            }
        }
        return;
    }

    double s;
    if (mode == WP_FIT) s = fmin((double)W / sw, (double)H / sh);
    else if (mode == WP_CENTER) s = 1.0;
    else s = fmax((double)W / sw, (double)H / sh); // cover
    int dw = (int)(sw * s + 0.5), dh = (int)(sh * s + 0.5);
    int ox = (W - dw) / 2, oy = (H - dh) / 2;
    for (int y = 0; y < H; y++) {
        int yy = y - oy;
        if (yy < 0 || yy >= dh) continue;
        int sy = (int)((long long)yy * sh / dh);
        if (sy >= sh) sy = sh - 1;
        for (int x = 0; x < W; x++) {
            int xx = x - ox;
            if (xx < 0 || xx >= dw) continue;
            int sx = (int)((long long)xx * sw / dw);
            if (sx >= sw) sx = sw - 1;
            dst[(size_t)y * W + x] = src[(size_t)sy * sw + sx];
        }
    }
}

// paths dhoondo: system wallpapers pehle, phir user ke apne
int wp_scan(char paths[][512], int max) {
    const char *sysdir = "/usr/share/backgrounds/devos";
    char userdir[600];
    snprintf(userdir, sizeof userdir, "%s/Pictures/wallpapers", home_dir());
    mkdirs(userdir);

    int n = 0;
    const char *dirs[2] = { sysdir, userdir };
    for (int d = 0; d < 2 && n < max; d++) {
        DIR *dp = opendir(dirs[d]);
        if (!dp) continue;
        struct dirent *e;
        while ((e = readdir(dp)) && n < max) {
            size_t l = strlen(e->d_name);
            if (l < 5 || strcmp(e->d_name + l - 4, ".png")) continue;
            snprintf(paths[n], 512, "%s/%s", dirs[d], e->d_name);
            n++;
        }
        closedir(dp);
    }
    return n;
}

// thumbnail cache — Settings har frame redraw karta hai, PNG dobara decode karna
// bewakoofi hogi. Key: path + mtime.
typedef struct {
    char path[512];
    long mtime;
    uint32_t *px;
    int used;
} Thumb;
static Thumb g_thumbs[WP_MAX_LIST];

int wp_thumb(const char *path, uint32_t **out) {
    struct stat st;
    long mt = 0;
    if (stat(path, &st) == 0) mt = (long)st.st_mtime;

    for (int i = 0; i < WP_MAX_LIST; i++) {
        if (g_thumbs[i].used && !strcmp(g_thumbs[i].path, path) &&
            g_thumbs[i].mtime == mt && g_thumbs[i].px) {
            *out = g_thumbs[i].px;
            return 1;
        }
    }
    int sw = 0, sh = 0;
    uint32_t *src = png_rgb(path, &sw, &sh);
    if (!src) return 0;
    uint32_t *th = malloc((size_t)WP_THUMB_W * WP_THUMB_H * 4);
    if (!th) { free(src); return 0; }
    scale_into(th, WP_THUMB_W, WP_THUMB_H, src, sw, sh, WP_COVER);
    free(src);

    int slot = -1;
    for (int i = 0; i < WP_MAX_LIST; i++) {
        if (!g_thumbs[i].used) { slot = i; break; }
        if (g_thumbs[i].mtime != 0 && !g_thumbs[i].px) { slot = i; break; }
    }
    if (slot < 0) slot = 0;
    free(g_thumbs[slot].px);
    g_thumbs[slot].px = th;
    g_thumbs[slot].used = 1;
    g_thumbs[slot].mtime = mt;
    snprintf(g_thumbs[slot].path, sizeof g_thumbs[slot].path, "%s", path);
    *out = th;
    return 1;
}

void wp_reload(OS *o) {
    Wallpaper *wp = &o->wp;
    wp->path[0] = 0;
    wp->mode = WP_COVER;
    parse_conf("/etc/devos/desktop.conf", wp);
    char up[600];
    wp_config_path(up, sizeof up);
    parse_conf(up, wp);

    free(wp->px);
    wp->px = NULL;
    wp->loaded = 0;

    if (!wp->path[0]) { os_draw_wallpaper(o); return; }

    int iw = 0, ih = 0;
    uint32_t *src = png_rgb(wp->path, &iw, &ih);
    if (!src) {
        fprintf(stderr, "devos: wallpaper load fail: %s\n", wp->path);
        os_draw_wallpaper(o);
        return;
    }
    wp->px = calloc((size_t)o->W * o->H, 4);
    if (wp->px) {
        scale_into(wp->px, o->W, o->H, src, iw, ih, wp->mode);
        wp->loaded = 1;
    }
    free(src);
    struct stat st;
    if (stat(up, &st) == 0) wp->cfg_mtime = (long)st.st_mtime;
    os_draw_wallpaper(o);
}

void wp_apply(OS *o, const char *path, int mode) {
    const char *home = home_dir();
    char cfgdir[600], cfg[600];
    snprintf(cfgdir, sizeof cfgdir, "%s/.config/devos", home);
    mkdirs(cfgdir);
    wp_config_path(cfg, sizeof cfg);

    FILE *f = fopen(cfg, "w");
    if (f) {
        fprintf(f, "# DevOS desktop settings — user file (Settings app isi me likhta hai)\n");
        fprintf(f, "wallpaper=%s\n", path);
        fprintf(f, "wallpaper_mode=%s\n", wp_mode_name(mode));
        fclose(f);
    }
    wp_reload(o);
    if (o->toastT <= 0) {
        snprintf(o->toast, sizeof o->toast, "Wallpaper set: %s",
                 strrchr(path, '/') ? strrchr(path, '/') + 1 : path);
        o->toastT = 2.5;
    }
}

// config file doosri jagah se badla (user ne editor me khola) — detect karo
int wp_watch(OS *o) {
    char cfg[600];
    wp_config_path(cfg, sizeof cfg);
    struct stat st;
    if (stat(cfg, &st) != 0) return 0;
    long mt = (long)st.st_mtime;
    if (mt != o->wp.cfg_mtime) {
        o->wp.cfg_mtime = mt;
        return 1;
    }
    return 0;
}

void wp_init(OS *o) {
    char cfgdir[600];
    snprintf(cfgdir, sizeof cfgdir, "%s/.config", home_dir());
    mkdirs(cfgdir);
    snprintf(cfgdir, sizeof cfgdir, "%s/Pictures/wallpapers", home_dir());
    mkdirs(cfgdir);
    wp_reload(o);
}
