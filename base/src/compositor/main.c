// main.c — DevOS compositor entry: DRM/KMS scanout, libinput, xkb, event loop,
// aur headless `--ppm` render mode (QEMU ke bina layout check ke liye).
#define _GNU_SOURCE
#include "devo.h"
#include <errno.h>
#include <fcntl.h>
#include <libinput.h>
#include <libudev.h>
#include <linux/input.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/timerfd.h>
#include <sys/utsname.h>
#include <time.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

static volatile sig_atomic_t g_stop = 0;
static void on_sig(int s) { (void)s; g_stop = 1; }

// ---------------------------------------------------------------- DRM
typedef struct {
    int fd;
    uint32_t crtc, conn, fb;
    uint32_t handle, pitch, size;
    uint32_t *map;
    int w, h;
} Drm;

static int drm_open_card(void) {
    const char *paths[] = {"/dev/dri/card0", "/dev/dri/card1", "/dev/dri/card2"};
    for (int i = 0; i < 3; i++) {
        int fd = open(paths[i], O_RDWR | O_CLOEXEC);
        if (fd >= 0) return fd;
    }
    return -1;
}

static int drm_setup(Drm *d) {
    memset(d, 0, sizeof *d);
    d->fd = drm_open_card();
    if (d->fd < 0) { fprintf(stderr, "devos: no /dev/dri/cardN\n"); return -1; }
    if (drmSetMaster(d->fd) != 0) fprintf(stderr, "devos: drmSetMaster failed (may still work)\n");

    drmModeRes *res = drmModeGetResources(d->fd);
    if (!res) { fprintf(stderr, "devos: drmModeGetResources failed\n"); return -1; }
    drmModeConnector *conn = NULL;
    for (int i = 0; i < res->count_connectors; i++) {
        drmModeConnector *c = drmModeGetConnector(d->fd, res->connectors[i]);
        if (!c) continue;
        if (c->connection == DRM_MODE_CONNECTED && c->count_modes > 0) {
            conn = c;
            break;
        }
        drmModeFreeConnector(c);
    }
    if (!conn) { fprintf(stderr, "devos: no connected connector\n"); drmModeFreeResources(res); return -1; }
    d->conn = conn->connector_id;
    drmModeModeInfo mode = conn->modes[0];   // preferred mode
    d->w = mode.hdisplay;
    d->h = mode.vdisplay;

    uint32_t enc_id = conn->encoder_id;
    drmModeEncoder *enc = enc_id ? drmModeGetEncoder(d->fd, enc_id) : NULL;
    if (!enc) {
        for (int i = 0; i < conn->count_encoders && !enc; i++)
            enc = drmModeGetEncoder(d->fd, conn->encoders[i]);
    }
    d->crtc = enc ? enc->crtc_id : (res->count_crtcs ? res->crtcs[0] : 0);
    if (enc) drmModeFreeEncoder(enc);
    if (!d->crtc) { fprintf(stderr, "devos: no CRTC\n"); return -1; }

    struct drm_mode_create_dumb creq;
    memset(&creq, 0, sizeof creq);
    creq.width = d->w;
    creq.height = d->h;
    creq.bpp = 32;
    if (drmIoctl(d->fd, DRM_IOCTL_MODE_CREATE_DUMB, &creq) < 0) {
        fprintf(stderr, "devos: create dumb failed: %s\n", strerror(errno));
        return -1;
    }
    d->handle = creq.handle;
    d->pitch = creq.pitch;
    d->size = creq.size;
    if (drmModeAddFB(d->fd, d->w, d->h, 24, 32, d->pitch, d->handle, &d->fb) != 0) {
        fprintf(stderr, "devos: addfb failed: %s\n", strerror(errno));
        return -1;
    }
    struct drm_mode_map_dumb mreq;
    memset(&mreq, 0, sizeof mreq);
    mreq.handle = d->handle;
    if (drmIoctl(d->fd, DRM_IOCTL_MODE_MAP_DUMB, &mreq) < 0) {
        fprintf(stderr, "devos: map dumb failed\n");
        return -1;
    }
    d->map = mmap(NULL, d->size, PROT_READ | PROT_WRITE, MAP_SHARED, d->fd, mreq.offset);
    if (d->map == MAP_FAILED) { fprintf(stderr, "devos: mmap failed\n"); return -1; }
    memset(d->map, 0, d->size);
    if (drmModeSetCrtc(d->fd, d->crtc, d->fb, 0, 0, &d->conn, 1, &mode) != 0) {
        fprintf(stderr, "devos: setcrtc failed: %s\n", strerror(errno));
        return -1;
    }
    drmModeFreeConnector(conn);
    drmModeFreeResources(res);
    fprintf(stderr, "devos: KMS %dx%d crtc=%u conn=%u\n", d->w, d->h, d->crtc, d->conn);
    return 0;
}

static void drm_present(Drm *d) {
    drmModeDirtyFB(d->fd, d->fb, NULL, 0);
}

// ---------------------------------------------------------------- input
static struct libinput *g_li;
static struct udev *g_ud;
static struct xkb_context *g_xkb;
static struct xkb_keymap *g_km;
static struct xkb_state *g_ks;

static int li_open_restricted(const char *path, int flags, void *ud) {
    (void)ud;
    return open(path, flags | O_CLOEXEC);
}
static void li_close_restricted(int fd, void *ud) { (void)ud; close(fd); }
static const struct libinput_interface LI_IFACE = { li_open_restricted, li_close_restricted };

static void xkb_init(void) {
    g_xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_rule_names names = { "evdev", "pc105", "us", "", "" };
    g_km = xkb_keymap_new_from_names(g_xkb, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
    g_ks = xkb_state_new(g_km);
}

static void handle_key(OS *o, struct libinput_event_keyboard *kev) {
    uint32_t key = libinput_event_keyboard_get_key(kev);
    enum libinput_key_state st = libinput_event_keyboard_get_key_state(kev);
    xkb_keycode_t kc = key + 8;
    // release bhi xkb ko dena zaroori — warna Ctrl/Alt latched reh jaate hain
    xkb_state_update_key(g_ks, kc, st == LIBINPUT_KEY_STATE_PRESSED ? XKB_KEY_DOWN : XKB_KEY_UP);
    if (st != LIBINPUT_KEY_STATE_PRESSED) return;
    xkb_keysym_t sym = xkb_state_key_get_one_sym(g_ks, kc);

    // evdev keymap me Alt aksar Mod1 hota hai (naam "Alt" nahi) — dono check karo
    int mods = 0;
    if (xkb_state_mod_name_is_active(g_ks, XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_EFFECTIVE) > 0) mods |= MOD_SHIFT;
    if (xkb_state_mod_name_is_active(g_ks, XKB_MOD_NAME_ALT, XKB_STATE_MODS_EFFECTIVE) > 0 ||
        xkb_state_mod_name_is_active(g_ks, "Mod1", XKB_STATE_MODS_EFFECTIVE) > 0) mods |= MOD_ALT;
    if (xkb_state_mod_name_is_active(g_ks, XKB_MOD_NAME_CTRL, XKB_STATE_MODS_EFFECTIVE) > 0) mods |= MOD_CTRL;
    if (xkb_state_mod_name_is_active(g_ks, XKB_MOD_NAME_LOGO, XKB_STATE_MODS_EFFECTIVE) > 0 ||
        xkb_state_mod_name_is_active(g_ks, "Mod4", XKB_STATE_MODS_EFFECTIVE) > 0) mods |= MOD_LOGO;

    if (sym == XKB_KEY_Super_L || sym == XKB_KEY_Super_R) {
        if (!o->booting && !o->locked) {
            o->menuOpen = !o->menuOpen;
            o->panelOpen = 0;
            if (o->menuOpen) { o->menuQ[0] = 0; o->menuHot = -1; }
        }
        return;
    }
    if (sym == XKB_KEY_Control_L || sym == XKB_KEY_Control_R ||
        sym == XKB_KEY_Alt_L || sym == XKB_KEY_Alt_R ||
        sym == XKB_KEY_Shift_L || sym == XKB_KEY_Shift_R ||
        sym == XKB_KEY_Caps_Lock) return;

    uint32_t cp = 0;
    char utf8[16] = {0};
    int n = xkb_state_key_get_utf8(g_ks, kc, utf8, sizeof utf8);
    if (n > 0 && (unsigned char)utf8[0] >= 32) {
        unsigned char *p = (unsigned char *)utf8;
        if (p[0] < 0x80) cp = p[0];
        else if ((p[0] & 0xE0) == 0xC0) cp = ((p[0] & 0x1F) << 6) | (p[1] & 0x3F);
        else if ((p[0] & 0xF0) == 0xE0) cp = ((p[0] & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
        else cp = '?';
    }
    switch (sym) {
    case XKB_KEY_Return: case XKB_KEY_KP_Enter: cp = '\r'; utf8[0] = '\r'; utf8[1] = 0; break;
    case XKB_KEY_BackSpace: cp = 0x7f; utf8[0] = 0x7f; utf8[1] = 0; break;
    case XKB_KEY_Tab: cp = '\t'; utf8[0] = '\t'; utf8[1] = 0; break;
    case XKB_KEY_Escape: cp = 27; utf8[0] = 27; utf8[1] = 0; break;
    case XKB_KEY_Up: cp = 0x100; utf8[0] = 0; break;
    case XKB_KEY_Down: cp = 0x101; utf8[0] = 0; break;
    case XKB_KEY_Right: cp = 0x102; utf8[0] = 0; break;
    case XKB_KEY_Left: cp = 0x103; utf8[0] = 0; break;
    case XKB_KEY_Home: cp = 0x104; utf8[0] = 0; break;
    case XKB_KEY_End: cp = 0x105; utf8[0] = 0; break;
    case XKB_KEY_Delete: cp = 0x106; utf8[0] = 0; break;
    default: break;
    }
    if (!cp) {
        // Ctrl ke saath xkb utf8 control-code deta hai — base keysym se printable char lo
        if (sym >= XKB_KEY_space && sym <= XKB_KEY_asciitilde) {
            cp = (uint32_t)sym;
            utf8[0] = (char)sym;
            utf8[1] = 0;
        } else return;
    }
    if ((mods & MOD_CTRL) && !(mods & MOD_ALT) && cp >= 'a' && cp <= 'z' && (mods & MOD_CTRL)) {
        ui_key(o, cp, utf8, mods);
        return;
    }
    ui_key(o, cp, utf8, mods);
}

static int g_have_abs = 0;
static double g_acc_x = 0, g_acc_y = 0;

static void handle_pointer_motion(OS *o, double dx, double dy) {
    g_acc_x += dx * 1.35;
    g_acc_y += dy * 1.35;
    int x = o->mx + (int)g_acc_x;
    int y = o->my + (int)g_acc_y;
    g_acc_x -= (int)g_acc_x;
    g_acc_y -= (int)g_acc_y;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x > o->W - 1) x = o->W - 1;
    if (y > o->H - 1) y = o->H - 1;
    ui_motion(o, x, y, (int)dx, (int)dy);
}

static void li_event(OS *o, struct libinput_event *ev) {
    enum libinput_event_type t = libinput_event_get_type(ev);
    switch (t) {
    case LIBINPUT_EVENT_POINTER_MOTION: {
        struct libinput_event_pointer *p = libinput_event_get_pointer_event(ev);
        handle_pointer_motion(o, libinput_event_pointer_get_dx(p), libinput_event_pointer_get_dy(p));
        break;
    }
    case LIBINPUT_EVENT_POINTER_MOTION_ABSOLUTE: {
        struct libinput_event_pointer *p = libinput_event_get_pointer_event(ev);
        int x = (int)libinput_event_pointer_get_absolute_x_transformed(p, o->W);
        int y = (int)libinput_event_pointer_get_absolute_y_transformed(p, o->H);
        if (x < 0) x = 0;
        if (y < 0) y = 0;
        if (x > o->W - 1) x = o->W - 1;
        if (y > o->H - 1) y = o->H - 1;
        ui_motion(o, x, y, 0, 0);
        break;
    }
    case LIBINPUT_EVENT_POINTER_BUTTON: {
        struct libinput_event_pointer *p = libinput_event_get_pointer_event(ev);
        uint32_t b = libinput_event_pointer_get_button(p);
        enum libinput_button_state bs = libinput_event_pointer_get_button_state(p);
        if (b == BTN_LEFT) {
            if (bs == LIBINPUT_BUTTON_STATE_PRESSED) {
                o->mdown = 1;
                ui_click(o, o->mx, o->my, 1);
            } else {
                o->mdown = 0;
                o->dragWin = -1;
                o->resizing = 0;
            }
        }
        break;
    }
    case LIBINPUT_EVENT_POINTER_AXIS: {
        struct libinput_event_pointer *p = libinput_event_get_pointer_event(ev);
        if (libinput_event_pointer_has_axis(p, LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL)) {
            double v = libinput_event_pointer_get_scroll_value(p, LIBINPUT_POINTER_AXIS_SCROLL_VERTICAL);
            int wheel = v > 0 ? 1 : -1;
            Win *w = win_at(o, o->mx, o->my);
            if (w && o->mx > w->x && o->mx < w->x + w->w &&
                o->my > w->y + 40 && o->my < w->y + w->h) {
                Rect cl = win_client(w);
                app_mouse(o, w, o->mx - cl.x, o->my - cl.y, 1, 0, wheel);
            }
        }
        break;
    }
    case LIBINPUT_EVENT_TOUCH_DOWN:
    case LIBINPUT_EVENT_TOUCH_MOTION: {
        struct libinput_event_touch *te = libinput_event_get_touch_event(ev);
        int x = (int)libinput_event_touch_get_x_transformed(te, o->W);
        int y = (int)libinput_event_touch_get_y_transformed(te, o->H);
        ui_motion(o, x, y, 0, 0);
        if (t == LIBINPUT_EVENT_TOUCH_DOWN) { o->mdown = 1; ui_click(o, x, y, 1); }
        break;
    }
    case LIBINPUT_EVENT_TOUCH_UP:
        o->mdown = 0;
        o->dragWin = -1;
        o->resizing = 0;
        break;
    case LIBINPUT_EVENT_KEYBOARD_KEY: {
        struct libinput_event_keyboard *kev = libinput_event_get_keyboard_event(ev);
        handle_key(o, kev);
        break;
    }
    default: break;
    }
}

static int input_init(void) {
    g_ud = udev_new();
    if (!g_ud) { fprintf(stderr, "devos: udev_new failed\n"); return -1; }
    g_li = libinput_udev_create_context(&LI_IFACE, NULL, g_ud);
    if (!g_li) { fprintf(stderr, "devos: libinput context failed\n"); return -1; }
    if (libinput_udev_assign_seat(g_li, "seat0") != 0) {
        fprintf(stderr, "devos: assign seat0 failed\n");
        return -1;
    }
    xkb_init();
    return 0;
}

static void input_drain(OS *o) {
    libinput_dispatch(g_li);
    struct libinput_event *ev;
    while ((ev = libinput_get_event(g_li))) {
        li_event(o, ev);
        libinput_event_destroy(ev);
    }
}

// ---------------------------------------------------------------- render
static void render(OS *o, Drm *d) {
    os_draw(o);
    memcpy(d->map, o->cv.px, (size_t)o->W * o->H * 4);
    drm_present(d);
}

static double now_s(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}

// ---------------------------------------------------------------- ppm
static void write_ppm(OS *o, const char *path) {
    FILE *f = fopen(path, "wb");
    if (!f) { perror("ppm"); return; }
    fprintf(f, "P6\n%d %d\n255\n", o->W, o->H);
    for (int i = 0; i < o->W * o->H; i++) {
        uint32_t p = o->cv.px[i];
        unsigned char rgb[3] = { (unsigned char)((p >> 16) & 255),
                                 (unsigned char)((p >> 8) & 255),
                                 (unsigned char)(p & 255) };
        fwrite(rgb, 1, 3, f);
    }
    fclose(f);
    fprintf(stderr, "devos: wrote %s (%dx%d)\n", path, o->W, o->H);
}

static void os_init(OS *o, int w, int h) {
    memset(o, 0, sizeof *o);
    o->W = w;
    o->H = h;
    o->scale = (float)h / 800.0f;
    if (o->scale < 0.8f) o->scale = 0.8f;
    if (o->scale > 2.0f) o->scale = 2.0f;
    o->cv.px = calloc((size_t)w * h, 4);
    o->cv.w = w; o->cv.h = h; o->cv.stride = w;
    o->bg = o->cv;
    o->bg.px = calloc((size_t)w * h, 4);
    o->bootT = 0;
    o->booting = 1;
    o->locked = 0;
    o->mx = w / 2;
    o->my = h / 2;
    o->dragWin = -1;
    o->focus = -1;
    o->dockHot = -1;
    o->menuHot = -1;
    o->cursorVisible = true;
    snprintf(o->activeApp, sizeof o->activeApp, "DevOS");
    sys_refresh(&o->sys);
    fonts_init("/usr/share/fonts/truetype/dejavu");
    os_draw_wallpaper(o);
}

int main(int argc, char **argv) {
    const char *ppm = NULL, *scene = "desktop", *out = "/tmp/devos.ppm";
    int fw = 1024, fh = 768, wait_ms = 0, refresh_hz = 30;
    int autologin = 0, seconds = 0;
    int boot_ms = 2400;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--ppm")) { ppm = "1"; if (i + 1 < argc && argv[i + 1][0] != '-') scene = argv[++i]; }
        else if (!strcmp(argv[i], "--out") && i + 1 < argc) out = argv[++i];
        else if (!strcmp(argv[i], "--size") && i + 1 < argc) sscanf(argv[++i], "%dx%d", &fw, &fh);
        else if (!strcmp(argv[i], "--scene") && i + 1 < argc) scene = argv[++i];
        else if (!strcmp(argv[i], "--autologin")) autologin = 1;
        else if (!strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--boot-ms") && i + 1 < argc) boot_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--wait") && i + 1 < argc) wait_ms = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--hz") && i + 1 < argc) refresh_hz = atoi(argv[++i]);
    }
    signal(SIGINT, on_sig);
    signal(SIGTERM, on_sig);
    signal(SIGPIPE, SIG_IGN);

    if (ppm) {
        OS o;
        os_init(&o, fw, fh);
        g_os = &o;
        wp_init(&o);
        o.booting = 0;
        o.locked = 0;
        o.mx = fw / 2 + 40;
        o.my = fh / 2 + 10;
        if (!strcmp(scene, "splash")) { o.booting = 1; o.bootT = 0.55; o.mx = -10; o.my = -10; }
        else if (!strcmp(scene, "lock")) { o.locked = 1; o.lockLen = 0; }
        else if (!strcmp(scene, "menu")) {
            o.menuOpen = 1;
            o.dockHot = 0;
            o.menuHot = 2;
            o.mx = fw / 2 - 80; o.my = fh - 140;
        } else if (!strcmp(scene, "panel")) {
            o.panelOpen = 1;
            o.mx = fw / 2 + 60; o.my = 60;
        } else {
            Win *w = NULL;
            int open_term = !strcmp(scene, "desktop") || !strcmp(scene, "term") || !strcmp(scene, "multi");
            if (open_term) {
                w = win_new(&o, APP_TERM);
                if (w && w->term) {
                    // asli bash chalao aur ek command bhejo — demo nahi
                    usleep(700 * 1000);
                    term_read(w->term);
                    if (w->term->master >= 0) {
                        if (write(w->term->master, "ls -la\n", 7) < 0) {}
                        // asli output ka intezaar: naya prompt aaya to ho gaya
                        for (int k = 0; k < 80; k++) {
                            usleep(100 * 1000);
                            term_read(w->term);
                            Term *t = w->term;
                            int done = 0;
                            for (int y = 1; y < t->rows && t->grid; y++) {
                                Cell *c = &t->grid[(size_t)y * t->cols];
                                if (c[0].ch == 'd' && c[1].ch == 'e' && c[2].ch == 'v' &&
                                    c[3].ch == 'o' && c[4].ch == 's') { done = 1; break; }
                            }
                            if (done) break;
                        }
                        if (getenv("DEVO_DBG")) {
                            Term *t = w->term;
                            for (int y = 0; y < 10 && t->grid; y++) {
                                char ln[200]; int k2 = 0;
                                for (int x = 0; x < t->cols && k2 < 190; x++) {
                                    uint32_t ch = t->grid[(size_t)y * t->cols + x].ch;
                                    ln[k2++] = ch >= 32 && ch < 127 ? (char)ch : ch ? '?' : ' ';
                                }
                                ln[k2] = 0;
                                fprintf(stderr, "R%d[%s]\n", y, ln);
                            }
                        }
                    }
                }
            }
            if (!strcmp(scene, "files")) { Win *fw2 = win_new(&o, APP_FILES); if (fw2) win_raise(&o, fw2); }
            else if (!strcmp(scene, "notes")) { Win *nw = win_new(&o, APP_NOTES); if (nw) win_raise(&o, nw); }
            else if (!strcmp(scene, "monitor")) { Win *mw = win_new(&o, APP_MONITOR); if (mw) win_raise(&o, mw); }
            else if (!strcmp(scene, "settings")) { Win *sw = win_new(&o, APP_SETTINGS); if (sw) win_raise(&o, sw); }
            else if (!strcmp(scene, "about")) { Win *aw = win_new(&o, APP_ABOUT); if (aw) win_raise(&o, aw); }
            else if (!strcmp(scene, "store")) { Win *sw = win_new(&o, APP_STORE); if (sw) win_raise(&o, sw); }
            else if (!strcmp(scene, "setup")) { Win *sw = win_new(&o, APP_SETUP); if (sw) win_raise(&o, sw); }
            else if (!strcmp(scene, "multi")) {
                Win *a = win_new(&o, APP_FILES); if (a) { a->x -= 210; a->y -= 110; }
                Win *b = win_new(&o, APP_NOTES); if (b) { b->x += 190; b->y -= 150; }
                Win *c = win_new(&o, APP_MONITOR); if (c) { c->x += 220; c->y += 150; }
            }
        }
        if (wait_ms) usleep(wait_ms * 1000);
        o.t = 2.5;
        os_draw(&o);
        write_ppm(&o, out);
        return 0;
    }

    OS o;
    Drm d;
    if (drm_setup(&d) != 0) return 1;
    os_init(&o, d.w, d.h);
    g_os = &o;
    o.autologin = autologin;
    wp_init(&o);

    if (input_init() != 0) {
        fprintf(stderr, "devos: input unavailable — running display-only\n");
    }
    int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    struct itimerspec its = { { 0, 1000000000 / (refresh_hz > 0 ? refresh_hz : 30) },
                              { 0, 1000000000 / (refresh_hz > 0 ? refresh_hz : 30) } };
    timerfd_settime(tfd, 0, &its, NULL);

    double t0 = now_s();
    double boot_s = boot_ms / 1000.0;
    double last_sys = 0, last_draw = 0, last_sec = 0, last_wp = 0;
    int dirty = 1;
    uint64_t frames = 0;
    fprintf(stderr, "devos: compositor ready on KMS %dx%d\n", d.w, d.h);
    fflush(stderr);

    while (!g_stop) {
        struct pollfd fds[2];
        int nf = 0;
        fds[nf].fd = tfd; fds[nf].events = POLLIN; nf++;
        if (g_li) { fds[nf].fd = libinput_get_fd(g_li); fds[nf].events = POLLIN; nf++; }
        poll(fds, nf, 50);

        uint64_t ticks;
        while (read(tfd, &ticks, sizeof ticks) > 0) {}
        if (g_li) input_drain(&o);

        double now = now_s();
        o.t = now - t0;
        if (o.booting) {
            o.bootT = o.t / boot_s;
            if (o.bootT >= 1.0) {
                o.booting = 0;
                o.bootT = 1.0;
                o.locked = !o.autologin;
                dirty = 1;
            }
            dirty = 1;
        }
        if (o.lockShake > 0) o.lockShake -= 0.016;
        if (o.toastT > 0) { o.toastT -= 0.016; dirty = 1; }
        if (o.mdown || o.dragWin >= 0 || o.resizing) dirty = 1;

        if (now - last_sys > 2.0) {
            last_sys = now;
            sys_refresh(&o.sys);
            dirty = 1;
        }
        if (now - last_wp > 1.0) {
            last_wp = now;
            if (wp_watch(&o)) { wp_reload(&o); dirty = 1; }
        }
        for (int i = 0; i < o.nwin; i++) {
            Win *w = &o.wins[o.order[i]];
            if (!w->used || !w->open) continue;
            if (w->kind == APP_TERM && w->term) {
                term_read(w->term);
                if (w->term->need_draw) { dirty = 1; w->term->need_draw = false; }
            }
        }
        double sec = floor(now);
        if (sec != last_sec) { last_sec = sec; dirty = 1; }
        if (now - last_draw > 0.5) dirty = 1;

        if (dirty) {
            render(&o, &d);
            dirty = 0;
            last_draw = now;
            frames++;
        }
        if (seconds > 0 && o.t > seconds) break;
    }
    fprintf(stderr, "devos: exit after %.1fs, %llu frames\n", now_s() - t0,
            (unsigned long long)frames);
    drmDropMaster(d.fd);
    return 0;
}
