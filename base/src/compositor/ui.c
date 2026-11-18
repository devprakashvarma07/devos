// ui.c — shell chrome: splash, lock, notch, panel, dock, start menu, windows.
#include "devo.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

Font *F_UI, *F_UI_B, *F_SM, *F_MONO, *F_HUGE;

// palette (mockup se)
#define C_BG       RGB(5, 7, 13)
#define C_TEXT     RGB(255, 255, 255)
#define C_DIM      RGB(160, 160, 170)
#define C_DIM2     RGB(122, 122, 132)
#define C_MUTED    RGB(90, 90, 100)
#define C_LINE     RGB(44, 44, 50)
#define C_ACCENT   RGB(10, 132, 255)
#define C_PANEL    col(9, 9, 12, 247)
#define C_CARD     RGB(28, 28, 31)
#define C_CARD2    RGB(16, 16, 19)

static int S(OS *o, int v) { return (int)(v * o->scale + 0.5f); }

void fonts_init(const char *dir) {
    char p[512];
    snprintf(p, sizeof p, "%s/DejaVuSans.ttf", dir);
    F_UI = font_load(p, 13);
    snprintf(p, sizeof p, "%s/DejaVuSans-Bold.ttf", dir);
    F_UI_B = font_load(p, 13);
    F_SM = font_load(p, 10);
    snprintf(p, sizeof p, "%s/DejaVuSansMono.ttf", dir);
    F_MONO = font_load(p, 13);
    F_HUGE = font_load(p, 110);
}

static const char *MONTHS[] = {"January","February","March","April","May","June",
                               "July","August","September","October","November","December"};
static const char *DAYS[] = {"Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"};

static void now_parts(int *hh, int *mm, int *sec, char *date, int dn) {
    time_t t = time(NULL);
    struct tm tm;
    localtime_r(&t, &tm);
    *hh = tm.tm_hour; *mm = tm.tm_min; *sec = tm.tm_sec;
    snprintf(date, dn, "%s, %d %s", DAYS[tm.tm_wday], tm.tm_mday, MONTHS[tm.tm_mon]);
}

// bottom-rounded rect (notch shape)
static void bottom_rrect(Canvas *c, int x, int y, int w, int h, int r, Col colv) {
    if (r < 1) { cv_fill(c, x, y, w, h, colv); return; }
    cv_fill(c, x, y, w, h - r, colv);
    int y0 = y + h - r, y1 = y + h;
    if (y0 < 0) y0 = 0;
    if (y1 > c->h) y1 = c->h;
    for (int yy = y0; yy < y1; yy++) {
        float py = yy + 0.5f;
        uint32_t *row = c->px + (size_t)yy * c->stride;
        for (int xx = x; xx < x + w; xx++) {
            if (xx < 0 || xx >= c->w) continue;
            float px = xx + 0.5f;
            float qx = fabsf(px - (x + w * 0.5f)) - (w * 0.5f - r);
            float qy = fabsf(py - (y1 - r));
            if (qx < 0) qx = 0;
            if (qy < 0) qy = 0;
            float d = sqrtf(qx * qx + qy * qy) - (r - 0.5f);
            int a = (int)((0.5f - d) * 255.f);
            if (a <= 0) continue;
            if (a > 255) a = 255;
            cv_blend_px(&row[xx], colv, a * colv.a / 255);
        }
    }
}

// ---------------------------------------------------------------- wallpaper
void os_draw_wallpaper(OS *o) {
    Canvas *c = &o->bg;
    // user ne wallpaper chuni hai to wahi (already screen-size me baked hai)
    if (o->wp.loaded && o->wp.px) {
        memcpy(c->px, o->wp.px, (size_t)o->W * o->H * 4);
        return;
    }
    cv_clear(c, C_BG);
    // neeche wali aur dono glows (mockup jaisa)
    cv_rgrad(c, (int)(o->W * 0.18), (int)(o->H * 0.1), (int)(o->H * 1.05),
             col(18, 35, 63, 190), col(5, 7, 13, 0));
    cv_rgrad(c, (int)(o->W * 0.86), (int)(o->H * 0.25), (int)(o->H * 0.95),
             col(26, 20, 64, 170), col(5, 7, 13, 0));
    cv_rgrad(c, (int)(o->W * 0.5), (int)(o->H * 0.95), (int)(o->H * 0.75),
             col(8, 18, 40, 150), col(5, 7, 13, 0));
    // giant DevOS watermark
    Font *wm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 150));
    text_center(c, wm, o->W / 2, (int)(o->H * 0.52), "DevOS", col(255, 255, 255, 11));
    Font *sm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 12));
    if (sm)
        text_center(c, sm, o->W / 2, (int)(o->H * 0.52) + S(o, 36),
                    "DEVOS 2.0  ·  WHALE", col(255, 255, 255, 36));
}

// ---------------------------------------------------------------- splash
void os_draw_splash(OS *o, Canvas *c) {
    cv_clear(c, RGB(0, 0, 0));
    Font *big = F_HUGE;
    int base = o->H / 2 + S(o, 10);
    text_center(c, big, o->W / 2, base, "DevOS", RGB(255, 255, 255));
    Font *sm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 12));
    text_center(c, sm, o->W / 2, base + S(o, 52), "WHALE  ·  2.0", RGB(85, 85, 85));
    int bw = S(o, 210), bh = S(o, 5);
    int bx = o->W / 2 - bw / 2, by = o->H - S(o, 70);
    cv_rrect(c, bx, by, bw, bh, bh / 2, RGB(26, 26, 26));
    int fw = (int)(bw * (o->bootT < 0 ? 0 : o->bootT > 1 ? 1 : o->bootT));
    if (fw > 2) cv_rrect(c, bx, by, fw, bh, bh / 2, RGB(255, 255, 255));
    // bottom hint
    Font *sm2 = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 10));
    text_center(c, sm2, o->W / 2, o->H - S(o, 34), "starting system services…", RGB(60, 60, 68));
}

// ---------------------------------------------------------------- lock
void os_draw_lock(OS *o, Canvas *c) {
    int w = o->W, h = o->H;
    cv_vgrad(c, 0, 0, w, h, RGB(22, 32, 61), RGB(6, 8, 16));
    cv_rgrad(c, w / 2, (int)(h * 0.34), (int)(h * 0.62), col(40, 62, 110, 120), col(10, 15, 34, 0));

    int hh, mm, ss;
    char date[64];
    now_parts(&hh, &mm, &ss, date, sizeof date);
    char ct[16];
    snprintf(ct, sizeof ct, "%02d:%02d", hh, mm);
    Font *clock = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 104));
    int cy = (int)(h * 0.34);
    text_center(c, clock, w / 2, cy, ct, RGB(255, 255, 255));
    Font *df = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 16));
    text_center(c, df, w / 2, cy + S(o, 42), date, col(255, 255, 255, 170));

    // avatar
    int av = S(o, 74);
    int ax = w / 2, ay = cy + S(o, 96);
    cv_circle(c, ax, ay + av / 2, av / 2.f, col(255, 255, 255, 26));
    cv_rrect_border(c, ax - av / 2, ay, av, av, av / 2, 1, col(255, 255, 255, 60));
    icon_draw(c, 11, ax - av / 3, ay + av / 6, (int)(av * 0.6f), col(235, 238, 245, 220));

    // password field
    int fw = S(o, 260), fh = S(o, 34);
    int fx = w / 2 - fw / 2;
    int fy = ay + av + S(o, 22);
    int shake = (int)(sin(o->lockShake * 45) * 6 * (o->lockShake > 0 ? 1 : 0));
    cv_rrect(c, fx + shake, fy, fw, fh, fh / 2, col(255, 255, 255, 22));
    cv_rrect_border(c, fx + shake, fy, fw, fh, fh / 2, 1,
                    o->lockErr ? RGB(255, 69, 58) : col(255, 255, 255, 55));
    if (o->lockLen == 0) {
        text_center(c, F_UI, w / 2 + shake, fy + fh / 2 + S(o, 4), "Enter Password", col(255, 255, 255, 120));
    } else {
        char dots[64];
        int n = o->lockLen > 20 ? 20 : o->lockLen;
        for (int i = 0; i < n; i++) dots[i] = '*';
        dots[n] = 0;
        char spaced[64]; int k = 0;
        for (int i = 0; i < n; i++) { spaced[k++] = '*'; spaced[k++] = ' '; }
        spaced[k ? k - 1 : 0] = 0;
        text_center(c, F_UI, w / 2 + shake, fy + fh / 2 + S(o, 5), spaced, RGB(255, 255, 255));
    }
    // caret
    if (o->lockLen >= 0 && fmod(o->t, 1.0) < 0.6) {
        int tw = text_w(F_UI, o->lockLen ? "" : "");
        (void)tw;
    }
    // arrow button
    int ab = S(o, 34);
    int abx = fx + fw + S(o, 10), aby = fy;
    cv_circle(c, abx + ab / 2, aby + ab / 2, ab / 2.f, col(255, 255, 255, 30));
    cv_line(c, abx + ab * 0.30f, aby + ab / 2.f, abx + ab * 0.66f, aby + ab / 2.f, 2.0f, RGB(255, 255, 255));
    cv_line(c, abx + ab * 0.52f, aby + ab * 0.32f, abx + ab * 0.70f, aby + ab / 2.f, 2.0f, RGB(255, 255, 255));
    cv_line(c, abx + ab * 0.52f, aby + ab * 0.68f, abx + ab * 0.70f, aby + ab / 2.f, 2.0f, RGB(255, 255, 255));

    Font *hint = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 11));
    text_center(c, hint, w / 2, o->H - S(o, 42),
                o->lockErr ? "Wrong password" :
        (access("/etc/devos-live", F_OK) == 0 ? "hint: devos" : "enter your password"),
                o->lockErr ? RGB(255, 110, 100) : col(255, 255, 255, 90));

    // bottom-right power + user chips
    int cx = w - S(o, 54), cyy = o->H - S(o, 54);
    cv_circle(c, cx, cyy, S(o, 17), col(255, 255, 255, 16));
    icon_draw(c, 17, cx - S(o, 9), cyy - S(o, 9), S(o, 18), col(255, 255, 255, 190));
}

// ---------------------------------------------------------------- notch
Rect notch_rect(OS *o) {
    char t[16]; int hh, mm, ss; char d[64];
    now_parts(&hh, &mm, &ss, d, sizeof d);
    snprintf(t, sizeof t, "%02d:%02d", hh, mm);
    Font *f = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 13));
    int w = S(o, 40) + text_w(f, o->sceneOverride[0] ? o->sceneOverride : (o->activeApp[0] ? o->activeApp : "DevOS")) +
            S(o, 8) + S(o, 6) + S(o, 8) + text_w(f, t) + S(o, 8) +
            S(o, 15) + S(o, 8) + text_w(f, "100%");
    int h = S(o, 34);
    Rect r = { o->W / 2 - w / 2, 0, w, h };
    return r;
}

Rect panel_rect(OS *o) {
    int w = S(o, 400), h = S(o, 268);
    Rect r = { o->W / 2 - w / 2, 0, w, h };
    return r;
}

static void drive_wifi(Canvas *c, int x, int y, int sz, bool on) {
    icon_draw(c, 7, x, y, sz, on ? col(220, 224, 232, 230) : col(110, 110, 120, 160));
}

static void bat_text(OS *o, char *out, int n) {
    if (!o->sys.batOk) { snprintf(out, n, "AC"); return; }
    snprintf(out, n, "%d%%", o->sys.batPct);
}

void ui_draw_notch(OS *o, Canvas *c) {
    Rect r = notch_rect(o);
    int hh, mm, ss; char date[64];
    now_parts(&hh, &mm, &ss, date, sizeof date);
    char t[16]; snprintf(t, sizeof t, "%02d:%02d", hh, mm);

    bottom_rrect(c, r.x, 0, r.w, r.h, S(o, 20), col(0, 0, 0, 255));
    // hairline
    bottom_rrect(c, r.x, 0, r.w, 1, 0, C_LINE);

    Font *f = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 13));
    int pad = S(o, 20);
    int x = r.x + pad;
    int base = r.h / 2 + S(o, 5);
    text_draw(c, f, x, base, o->sceneOverride[0] ? o->sceneOverride : (o->activeApp[0] ? o->activeApp : "DevOS"), RGB(212, 212, 216));
    x += text_w(f, o->sceneOverride[0] ? o->sceneOverride : (o->activeApp[0] ? o->activeApp : "DevOS")) + S(o, 8);
    text_draw(c, f, x, base, "·", RGB(85, 85, 85));
    x += S(o, 6) + S(o, 8);
    text_draw(c, f, x, base, t, RGB(212, 212, 216));
    x += text_w(f, t) + S(o, 8);
    drive_wifi(c, x, r.h / 2 - S(o, 8), S(o, 16), o->sys.net[0] != 0);
    x += S(o, 15) + S(o, 8);
    char bt[16]; bat_text(o, bt, sizeof bt);
    Col bc = RGB(212, 212, 216);
    if (o->sys.batOk && o->sys.batPct <= 15) bc = RGB(255, 90, 80);
    text_draw(c, f, x, base, bt, bc);
}

// sliders inside panel
Rect panel_power_rect(OS *o) {
    Rect p = panel_rect(o);
    Rect r = { p.x + p.w - S(o, 38), p.y + p.h - S(o, 36), S(o, 26), S(o, 26) };
    return r;
}

Rect slider_rect(OS *o, int which) {
    Rect p = panel_rect(o);
    int x = p.x + S(o, 18);
    int w = p.w - S(o, 36);
    int y = p.y + S(o, 176) + which * S(o, 44);
    Rect r = { x, y, w, S(o, 6) };
    return r;
}

void ui_draw_panel(OS *o, Canvas *c) {
    Rect p = panel_rect(o);
    int w = p.w;

    cv_shadow(c, p.x, p.y, p.w, p.h, S(o, 20), S(o, 10), col(0, 0, 0, 90));
    cv_rrect(c, p.x, p.y, p.w, p.h, S(o, 20), C_PANEL);
    cv_rrect_border(c, p.x, p.y, p.w, p.h, S(o, 20), 1, RGB(44, 44, 49));

    int x = p.x + S(o, 18), y = p.y + S(o, 16);

    // session card
    cv_rrect(c, x, y, S(o, 30), S(o, 30), S(o, 9), RGB(27, 43, 69));
    cv_rrect_border(c, x, y, S(o, 30), S(o, 30), S(o, 9), 1, C_ACCENT);
    text_center(c, F_UI_B, x + S(o, 15), y + S(o, 20), "D", C_ACCENT);

    char up[32]; sys_uptime_str(&o->sys, up, sizeof up);
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", S(o, 13));
    Font *fs = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 10));
    char line[160];
    snprintf(line, sizeof line, "%s  ·  up %s", o->sys.host, up);
    text_elide(c, fb, x + S(o, 42), y + S(o, 14), w - S(o, 80), y + S(o, 14), line, C_TEXT);
    snprintf(line, sizeof line, "kernel %s  ·  %s", o->sys.kernel,
             o->sys.net[0] ? o->sys.net : "no network");
    text_elide(c, fs, x + S(o, 42), y + S(o, 28), w - S(o, 80), y + S(o, 28), line, RGB(136, 136, 136));

    // divider
    y += S(o, 42);
    cv_fill(c, x, y, w - S(o, 36), 1, RGB(38, 38, 43));

    // 3 real status tiles
    y += S(o, 12);
    int tw = (w - S(o, 36) - S(o, 16)) / 3;
    const char *labels[3] = {"Network", "Battery", "Audio"};
    char vals[3][32];
    snprintf(vals[0], sizeof vals[0], "%s", o->sys.net[0] ? o->sys.net : "offline");
    bat_text(o, vals[1], sizeof vals[1]);
    if (o->sys.volOk) snprintf(vals[2], sizeof vals[2], "%d%%", o->sys.vol);
    else snprintf(vals[2], sizeof vals[2], "--");
    bool on[3] = { o->sys.net[0] != 0, o->sys.batOk, o->sys.volOk };
    for (int i = 0; i < 3; i++) {
        int tx = x + i * (tw + S(o, 8));
        cv_rrect(c, tx, y, tw, S(o, 46), S(o, 12),
                 on[i] ? col(10, 132, 255, 56) : C_CARD);
        cv_rrect_border(c, tx, y, tw, S(o, 46), S(o, 12), 1,
                        on[i] ? col(10, 132, 255, 255) : RGB(44, 44, 49));
        Font *tl = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 10));
        text_center(c, fb, tx + tw / 2, y + S(o, 19), labels[i], C_TEXT);
        text_elide(c, tl, tx + S(o, 6), y + S(o, 36), tw - S(o, 12), y + S(o, 36), vals[i], C_DIM);
    }

    // sliders (real)
    const char *sl[2] = {"Brightness", "Volume"};
    int sv[2] = { o->sys.brightOk ? o->sys.bright : 0, o->sys.volOk ? o->sys.vol : 0 };
    bool ok[2] = { o->sys.brightOk != 0, o->sys.volOk != 0 };
    for (int i = 0; i < 2; i++) {
        Rect tr = slider_rect(o, i);
        int ly = tr.y - S(o, 8);
        Font *tl = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 11));
        text_draw(c, tl, tr.x, ly, sl[i], RGB(136, 136, 136));
        char vb[8]; snprintf(vb, sizeof vb, "%d%%", sv[i]);
        text_right(c, tl, tr.x + tr.w, ly, ok[i] ? vb : "--", ok[i] ? C_TEXT : C_MUTED);
        icon_draw(c, i == 0 ? 10 : 9, tr.x, tr.y - S(o, 3), S(o, 13),
                  ok[i] ? RGB(212, 212, 216) : C_MUTED);
        cv_rrect(c, tr.x, tr.y, tr.w, tr.h, tr.h / 2, RGB(38, 38, 43));
        int fw = tr.w * (sv[i] < 0 ? 0 : sv[i] > 100 ? 100 : sv[i]) / 100;
        if (fw > 2) cv_rrect(c, tr.x, tr.y, fw, tr.h, tr.h / 2, ok[i] ? C_ACCENT : RGB(58, 58, 64));
        int kx = tr.x + fw, kr = S(o, 7);
        if (kx < tr.x + kr) kx = tr.x + kr;
        if (kx > tr.x + tr.w - kr) kx = tr.x + tr.w - kr;
        cv_circle(c, kx, tr.y + tr.h / 2, kr, ok[i] ? RGB(255, 255, 255) : RGB(90, 90, 95));
    }

    // footer: live-values note + real power chip
    Font *foot = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 9));
    text_draw(c, foot, p.x + S(o, 18), p.y + p.h - S(o, 12),
              "live values  ·  click outside to close", col(255, 255, 255, 60));
    Rect pr = panel_power_rect(o);
    icon_draw(c, 17, pr.x + S(o, 5), pr.y + S(o, 5), S(o, 16), col(255, 255, 255, 165));
}

// ---------------------------------------------------------------- dock
static const int DOCK_KINDS[7] = {0, 1, 2, 3, 4, 5, 6};       // icon ids
static const int DOCK_APP[7] = {APP_TERM, APP_FILES, APP_TERM, APP_NOTES,
                                APP_MONITOR, APP_SETUP, APP_SETTINGS};
static const char *DOCK_NAMES[7] = {"Launch", "Files", "Terminal", "Notes",
                                   "Monitor", "Setup", "Settings"};
// dock me pehla tile launcher hai
static int dock_is_launch(int i) { return i == 0; }

Rect dock_rect(OS *o) {
    int w = S(o, 7 * 52 + 6 * 8 + 30);
    int h = S(o, 74);
    Rect r = { o->W / 2 - w / 2, o->H - h - S(o, 14), w, h };
    return r;
}

static Rect dock_tile(OS *o, int i) {
    Rect d = dock_rect(o);
    int x = d.x + S(o, 15) + i * S(o, 60);
    int y = d.y + (d.h - S(o, 52)) / 2;
    Rect r = { x, y, S(o, 52), S(o, 52) };
    return r;
}

int dock_hit(OS *o, int x, int y) {
    Rect d = dock_rect(o);
    if (!rin(d, x, y)) return -1;
    for (int i = 0; i < 7; i++) {
        Rect t = dock_tile(o, i);
        if (rin(t, x, y)) return i;
    }
    return -1;
}

void ui_draw_dock(OS *o, Canvas *c) {
    Rect d = dock_rect(o);
    cv_shadow(c, d.x, d.y, d.w, d.h, S(o, 26), S(o, 12), col(0, 0, 0, 120));
    cv_rrect(c, d.x, d.y, d.w, d.h, S(o, 26), col(18, 18, 21, 205));
    cv_rrect_border(c, d.x, d.y, d.w, d.h, S(o, 26), 1, col(255, 255, 255, 26));
    // subtle top sheen
    cv_rrect(c, d.x + S(o, 8), d.y + 1, d.w - S(o, 16), S(o, 18), S(o, 12), col(255, 255, 255, 8));

    for (int i = 0; i < 7; i++) {
        Rect t = dock_tile(o, i);
        bool hov = (o->dockHot == i);
        int active = -1;
        if (!dock_is_launch(i)) {
            for (int k = 0; k < o->nwin && k < MAX_WIN; k++)
                if (o->wins[k].used && o->wins[k].open && !o->wins[k].min &&
                    o->wins[k].kind == DOCK_APP[i] && o->wins[k].kind != APP_TERM)
                    active = k;
            if (DOCK_APP[i] == APP_TERM)
                for (int k = 0; k < MAX_WIN && k < o->nwin; k++)
                    if (o->wins[k].used && o->wins[k].open && !o->wins[k].min &&
                        o->wins[k].kind == APP_TERM) active = k;
        }
        if (hov || active >= 0)
            cv_rrect(c, t.x, t.y, t.w, t.h, S(o, 16), col(255, 255, 255, hov ? 40 : 22));
        cv_rrect_border(c, t.x, t.y, t.w, t.h, S(o, 16), 1, col(255, 255, 255, hov ? 40 : 20));
        icon_draw(c, DOCK_KINDS[i], t.x + t.w / 2 - S(o, 13), t.y + t.h / 2 - S(o, 13),
                  S(o, 26), hov ? RGB(255, 255, 255) : col(240, 242, 248, 235));
        if (active >= 0) cv_circle(c, t.x + t.w / 2, t.y + t.h + S(o, 5), S(o, 2), col(255, 255, 255, 210));
        // tooltip
        if (hov) {
            Font *tm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 11));
            const char *nm = DOCK_NAMES[i];
            int tw = text_w(tm, nm) + S(o, 22);
            int tx = t.x + t.w / 2 - tw / 2;
            int ty = d.y - S(o, 34);
            cv_rrect(c, tx, ty, tw, S(o, 24), S(o, 9), col(20, 20, 24, 235));
            cv_rrect_border(c, tx, ty, tw, S(o, 24), S(o, 9), 1, col(255, 255, 255, 40));
            text_center(c, tm, tx + tw / 2, ty + S(o, 16), nm, RGB(235, 235, 240));
        }
    }
}

// ---------------------------------------------------------------- menu
static const char *MENU_NAMES[9] = {"Files", "Terminal", "Notepad", "DevOS Setup",
                                    "Monitor", "Settings", "About", "Store", "Install"};
static const int MENU_ICON[9] = {1, 2, 3, 5, 4, 6, 19, 15, 20};
static const AppKind MENU_APP[9] = {APP_FILES, APP_TERM, APP_NOTES, APP_SETUP,
                                    APP_MONITOR, APP_SETTINGS, APP_ABOUT, APP_STORE,
                                    APP_INSTALL};
static const char *MENU_SEARCH = "";

Rect menu_rect(OS *o) {
    int w = S(o, 560), h = S(o, 356);
    Rect r = { o->W / 2 - w / 2, o->H - S(o, 74) - S(o, 14) - S(o, 10) - h, w, h };
    return r;
}

static Rect menu_cell(OS *o, int i) {
    Rect m = menu_rect(o);
    int gx = m.x + S(o, 20), gy = m.y + S(o, 20) + S(o, 44) + S(o, 10) + S(o, 16) + S(o, 6);
    int cols = 5;
    int cw = (m.w - S(o, 40) - S(o, 24)) / cols;
    int row = i / cols, colm = i % cols;
    Rect r = { gx + colm * (cw + S(o, 6)), gy + row * S(o, 84), cw, S(o, 84) };
    return r;
}

void ui_draw_menu(OS *o, Canvas *c) {
    Rect m = menu_rect(o);
    cv_shadow(c, m.x, m.y, m.w, m.h, S(o, 22), S(o, 14), col(0, 0, 0, 150));
    cv_rrect(c, m.x, m.y, m.w, m.h, S(o, 22), col(24, 24, 27, 250));
    cv_rrect_border(c, m.x, m.y, m.w, m.h, S(o, 22), 1, RGB(51, 51, 56));

    int p = S(o, 20);
    int x = m.x + p, y = m.y + p;
    // search box
    cv_rrect(c, x, y, m.w - p * 2, S(o, 44), S(o, 12),
             o->menuHot == 100 ? col(16, 16, 19, 255) : RGB(16, 16, 19));
    cv_rrect_border(c, x, y, m.w - p * 2, S(o, 44), S(o, 12), 1,
                    o->menuHot == 100 ? C_ACCENT : RGB(58, 58, 65));
    Font *f = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 13));
    const char *q = o->sceneOverride[0] ? o->sceneOverride
                  : (o->menuQ[0] ? o->menuQ : "Search apps, files, settings…");
    text_draw(c, f, x + S(o, 15), y + S(o, 27), q,
              (o->menuQ[0] || o->sceneOverride[0]) ? RGB(255, 255, 255) : RGB(119, 119, 119));
    if (o->menuQ[0] && fmod(o->t, 1.0) < 0.6) {
        int tw = text_w(f, o->menuQ);
        cv_fill(c, x + S(o, 16) + tw, y + S(o, 14), 1, S(o, 17), C_ACCENT);
    }
    // pinned label
    y += S(o, 44) + S(o, 10);
    Font *lab = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 10));
    text_draw_tracked(c, lab, x + S(o, 4), y + S(o, 12), "PINNED", S(o, 1), RGB(161, 161, 170));
    y += S(o, 16) + S(o, 6);

    Font *nm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 11));
    const Col grads[10][2] = {
        {RGB(74, 168, 255), RGB(10, 95, 224)}, {RGB(60, 60, 66), RGB(16, 16, 19)},
        {RGB(255, 159, 10), RGB(194, 94, 0)}, {RGB(10, 132, 255), RGB(0, 200, 255)},
        {RGB(48, 209, 88), RGB(10, 132, 255)}, {RGB(142, 142, 147), RGB(69, 69, 75)},
        {RGB(94, 92, 230), RGB(54, 52, 163)}, {RGB(191, 90, 242), RGB(125, 31, 196)},
        {RGB(52, 199, 89), RGB(0, 120, 60)}, {RGB(120, 144, 255), RGB(60, 70, 180)}
    };
    for (int i = 0; i < 9; i++) {
        Rect cellr = menu_cell(o, i);
        bool hov = (o->menuHot == i);
        if (hov) cv_rrect(c, cellr.x, cellr.y, cellr.w, cellr.h, S(o, 14), RGB(42, 42, 48));
        int isz = S(o, 48);
        int ix = cellr.x + cellr.w / 2 - isz / 2;
        int iy = cellr.y + S(o, 12);
        cv_rrect(c, ix, iy, isz, isz, S(o, 14), grads[i][1]);
        cv_rrect(c, ix, iy, isz, isz / 2, S(o, 14), col(grads[i][0].r, grads[i][0].g, grads[i][0].b, 150));
        cv_rrect_border(c, ix, iy, isz, isz, S(o, 14), 1, col(255, 255, 255, 20));
        icon_draw(c, MENU_ICON[i], ix + isz / 2 - S(o, 12), iy + isz / 2 - S(o, 12),
                  S(o, 24), col(255, 255, 255, 240));
        text_center(c, nm, cellr.x + cellr.w / 2, cellr.y + S(o, 76), MENU_NAMES[i],
                    hov ? RGB(255, 255, 255) : RGB(225, 227, 233));
    }

    // recent
    int ry = menu_cell(o, 5).y + S(o, 84) + S(o, 8);
    text_draw_tracked(c, lab, x + S(o, 4), ry + S(o, 10), "RECENT", S(o, 1), RGB(161, 161, 170));
    Font *rl = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 12));
    const char *an[APP_KIND_COUNT] = {"Terminal", "Files", "Notepad", "Monitor",
                                      "Settings", "About", "Store", "Setup", "Install DevOS"};
    char rec[128];
    if (o->nrecent == 0) snprintf(rec, sizeof rec, "no apps opened yet in this session");
    else {
        size_t k = 0; rec[0] = 0;
        for (int i = 0; i < o->nrecent; i++) {
            int id = (int)o->recent[i];
            if (id < 0 || id >= 8) continue;
            k += snprintf(rec + k, sizeof rec - k, "%s%s", k ? "   ·   " : "", an[id]);
        }
    }
    text_draw(c, rl, x + S(o, 4), ry + S(o, 30), rec, RGB(136, 136, 136));
}

static int contains_ci(const char *hay, const char *needle) {
    if (!*needle) return 0;
    for (; *hay; hay++) {
        const char *a = hay, *b = needle;
        while (*a && *b) {
            char ca = (*a >= 'A' && *a <= 'Z') ? *a + 32 : *a;
            char cb = (*b >= 'A' && *b <= 'Z') ? *b + 32 : *b;
            if (ca != cb) break;
            a++; b++;
        }
        if (!*b) return 1;
    }
    return 0;
}

int menu_match(OS *o) {
    if (!o->menuQ[0]) return -1;
    for (int i = 0; i < 9; i++)
        if (contains_ci(MENU_NAMES[i], o->menuQ)) return i;
    return -1;
}

int menu_hit(OS *o, int x, int y) {
    Rect m = menu_rect(o);
    if (!rin(m, x, y)) return -1;
    for (int i = 0; i < 9; i++) {
        Rect r = menu_cell(o, i);
        if (rin(r, x, y)) return i;
    }
    Rect sr = { m.x + S(o, 20), m.y + S(o, 20), m.w - S(o, 40), S(o, 44) };
    if (rin(sr, x, y)) return 100;
    return -2;   // menu ke andar, item nahi
}

// ---------------------------------------------------------------- windows
Rect win_rect(Win *w) { Rect r = { w->x, w->y, w->w, w->h }; return r; }

Rect win_client(Win *w) {
    int tb = 40;
    Rect r = { w->x + 1, w->y + tb, w->w - 2, w->h - tb - 1 };
    return r;
}

void ui_draw_window(OS *o, Canvas *c, Win *w) {
    Rect r = win_rect(w);
    int rad = S(o, 12);
    cv_shadow(c, r.x, r.y, r.w, r.h, rad, S(o, 12), col(0, 0, 0, 110));
    cv_rrect(c, r.x, r.y, r.w, r.h, rad, RGB(14, 14, 17));
    cv_rrect_border(c, r.x, r.y, r.w, r.h, rad, 1,
                    (o->focus >= 0 && &o->wins[o->focus] == w) ? RGB(70, 70, 78) : RGB(40, 40, 46));

    // titlebar
    int tb = S(o, 40);
    cv_fill(c, r.x + 1, r.y + tb - 1, r.w - 2, 1, RGB(34, 34, 39));
    // traffic lights
    int dot = S(o, 11);
    int dy = r.y + tb / 2 - dot / 2;
    cv_circle(c, r.x + S(o, 20), dy + dot / 2, dot / 2.f, RGB(255, 95, 87));
    cv_circle(c, r.x + S(o, 40), dy + dot / 2, dot / 2.f, RGB(254, 188, 46));
    cv_circle(c, r.x + S(o, 60), dy + dot / 2, dot / 2.f, RGB(40, 200, 64));

    Font *ftb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", S(o, 12));
    text_center(c, ftb, r.x + r.w / 2, r.y + tb / 2 + S(o, 4), w->title, RGB(210, 212, 220));

    // client
    Rect cl = win_client(w);
    cv_fill(c, cl.x, cl.y, cl.w, cl.h, RGB(6, 6, 9));
    app_draw(o, c, w);
}

// ---------------------------------------------------------------- compose
void os_draw(OS *o) {
    Canvas *c = &o->cv;
    if (o->booting) {
        os_draw_splash(o, c);
        os_draw_cursor(o, c);
        return;
    }
    memcpy(c->px, o->bg.px, (size_t)o->W * o->H * 4);

    // windows (z order)
    for (int i = 0; i < o->nwin; i++) {
        Win *w = &o->wins[o->order[i]];
        if (!w->used || !w->open || w->min) continue;
        ui_draw_window(o, c, w);
    }

    ui_draw_dock(o, c);
    if (o->menuOpen) ui_draw_menu(o, c);
    ui_draw_notch(o, c);
    if (o->panelOpen) ui_draw_panel(o, c);
    ui_draw_toast(o, c);

    if (o->locked) os_draw_lock(o, c);
    os_draw_cursor(o, c);
}

void ui_draw_toast(OS *o, Canvas *c) {
    if (o->toastT <= 0 || !o->toast[0]) return;
    Font *f = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", S(o, 12));
    int tw = text_w(f, o->toast) + S(o, 32);
    int th = S(o, 34);
    int x = o->W / 2 - tw / 2;
    int y = o->H - S(o, 74) - S(o, 14) - S(o, 20) - th;
    int a = o->toastT > 2.6 ? (int)((3.0 - o->toastT) * 255) : o->toastT < 0.3 ? (int)(o->toastT / 0.3 * 255) : 255;
    if (a < 0) a = 0;
    if (a > 255) a = 255;
    cv_rrect(c, x, y, tw, th, S(o, 10), col(22, 22, 26, a * 235 / 255));
    cv_rrect_border(c, x, y, tw, th, S(o, 10), 1, col(255, 255, 255, a * 40 / 255));
    text_center(c, f, o->W / 2, y + th / 2 + S(o, 4), o->toast, col(240, 240, 245, a));
}

// ---------------------------------------------------------------- cursor
void os_draw_cursor(OS *o, Canvas *c) {
    int x = o->mx, y = o->my;
    if (x < 0 || y < 0 || x >= o->W || y >= o->H) return;
    // arrow polygon: (0,0) (0,17) (4.5,13) (8,20) (10.5,19) (7,12) (13,12)
    static const float px[7] = {0, 0, 4.5f, 8, 10.5f, 7, 13};
    static const float py[7] = {0, 17, 13, 20, 19, 12, 12};
    // fill (scanline, even-odd)
    for (int yy = 0; yy < 21; yy++) {
        float xs[8]; int n = 0;
        for (int i = 0; i < 7; i++) {
            int j = (i + 1) % 7;
            float y0 = py[i], y1 = py[j];
            if ((yy + 0.5f >= y0 && yy + 0.5f < y1) || (yy + 0.5f >= y1 && yy + 0.5f < y0)) {
                float t = ((yy + 0.5f) - y0) / (y1 - y0);
                xs[n++] = px[i] + (px[j] - px[i]) * t;
            }
        }
        for (int a = 0; a < n; a++)
            for (int b = a + 1; b < n; b++)
                if (xs[b] < xs[a]) { float t = xs[a]; xs[a] = xs[b]; xs[b] = t; }
        for (int a = 0; a + 1 < n; a += 2) {
            int x0 = x + (int)ceilf(xs[a] - 0.5f), x1 = x + (int)ceilf(xs[a + 1] - 0.5f);
            if (x1 <= x0) continue;
            int ty = y + yy;
            if (ty < 0 || ty >= c->h) continue;
            for (int xx = x0; xx < x1; xx++) {
                if (xx < 0 || xx >= c->w) continue;
                cv_blend_px(c->px + (size_t)ty * c->stride + xx, col(255, 255, 255, 255), 235);
            }
        }
    }
    // outline
    for (int i = 0; i < 7; i++) {
        int j = (i + 1) % 7;
        cv_line(c, x + px[i], y + py[i], x + px[j], y + py[j], 1.4f, col(17, 17, 17, 220));
    }
}