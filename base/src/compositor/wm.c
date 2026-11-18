// wm.c — window manager + shell input routing (mouse, keyboard, shortcuts).
#include "devo.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <shadow.h>
#include <crypt.h>
#include <pwd.h>

OS *g_os;

extern Font *F_UI, *F_UI_B;

static int S(OS *o, int v) { return (int)(v * o->scale + 0.5f); }

// ---------------------------------------------------------------- wm
static void order_remove(OS *o, int idx) {
    int k = 0;
    for (int i = 0; i < o->nwin; i++)
        if (o->order[i] != idx) o->order[k++] = o->order[i];
    o->nwin = k;
}

void win_raise(OS *o, Win *w) {
    int idx = (int)(w - o->wins);
    order_remove(o, idx);
    if (o->nwin < MAX_WIN) o->order[o->nwin++] = idx;
    o->focus = idx;
    snprintf(o->activeApp, sizeof o->activeApp, "%s", w->title);
}

Win *win_new(OS *o, AppKind k) {
    Win *w = NULL;
    for (int i = 0; i < MAX_WIN; i++)
        if (!o->wins[i].used) { w = &o->wins[i]; break; }
    if (!w) return NULL;
    memset(w, 0, sizeof(Win));
    w->used = true;
    w->open = true;
    w->kind = k;
    int ww, hh;
    app_size(o, k, &ww, &hh);
    w->w = ww;
    w->h = hh;
    int n = o->nwin;
    w->x = o->W / 2 - ww / 2 + (n % 5 - 1) * S(o, 34);
    w->y = o->H / 2 - hh / 2 + (n % 5 - 1) * S(o, 26) - S(o, 40);
    if (w->y < S(o, 46)) w->y = S(o, 46);
    if (w->y + hh > o->H - S(o, 100)) w->y = o->H - S(o, 100) - hh;
    app_open(o, w);
    win_raise(o, w);
    return w;
}

void win_close(OS *o, Win *w) {
    int idx = (int)(w - o->wins);
    app_close(w);
    w->used = false;
    w->open = false;
    order_remove(o, idx);
    o->focus = o->nwin ? o->order[o->nwin - 1] : -1;
    if (o->focus >= 0) snprintf(o->activeApp, sizeof o->activeApp, "%s", o->wins[o->focus].title);
    else snprintf(o->activeApp, sizeof o->activeApp, "DevOS");
}

void win_toggle_max(OS *o, Win *w) {
    if (!w->max) {
        w->sx = w->x; w->sy = w->y; w->sw = w->w; w->sh = w->h;
        w->x = S(o, 0); w->y = S(o, 32);
        w->w = o->W; w->h = o->H - S(o, 32) - S(o, 100);
        w->max = true;
    } else {
        w->x = w->sx; w->y = w->sy; w->w = w->sw; w->h = w->sh;
        w->max = false;
    }
}

Win *win_at(OS *o, int x, int y) {
    for (int i = o->nwin - 1; i >= 0; i--) {
        Win *w = &o->wins[o->order[i]];
        if (!w->used || !w->open || w->min) continue;
        Rect r = win_rect(w);
        if (rin(r, x, y)) return w;
    }
    return NULL;
}

static Win *win_kind(OS *o, AppKind k) {
    for (int i = 0; i < o->nwin; i++) {
        Win *w = &o->wins[o->order[i]];
        if (w->used && w->open && w->kind == k) return w;
    }
    return NULL;
}

// asli auth — /etc/shadow ka hash (uid 1000, warna root)
static int check_login_password(const char *pw) {
    struct passwd *u = getpwuid(1000);
    const char *name = u ? u->pw_name : "root";
    struct spwd *sp = getspnam(name);
    if (!sp || !sp->sp_pwdp || !sp->sp_pwdp[0]) return 0;
    const char *h = sp->sp_pwdp;
    if (h[0] == '!' || h[0] == '*') return 0;
    struct crypt_data cd;
    memset(&cd, 0, sizeof cd);
    char *r = crypt_r(pw, h, &cd);
    return r && strcmp(r, h) == 0;
}

static void recent_push(OS *o, AppKind k) {
    int n = o->nrecent < 3 ? o->nrecent : 3;
    if (n > 0 && o->recent[0] == k) return;
    int top = n < 3 ? n : 2;
    for (int i = top; i > 0; i--) o->recent[i] = o->recent[i - 1];
    o->recent[0] = k;
    if (o->nrecent < 3) o->nrecent++;
}

void open_app(OS *o, AppKind k) {
    Win *w = win_kind(o, k);
    recent_push(o, k);
    if (w && !w->min) { win_raise(o, w); return; }
    if (w && w->min) { w->min = false; win_raise(o, w); return; }
    w = win_new(o, k);
    if (!w) { ui_toast(o, "too many windows"); return; }
    if (k == APP_INSTALL && w->term && w->term->master >= 0) {
        const char *cmd = "devos-install\n";
        if (write(w->term->master, cmd, strlen(cmd)) < 0) {}
    }
}

void close_focused(OS *o) {
    if (o->focus >= 0 && o->wins[o->focus].used) win_close(o, &o->wins[o->focus]);
}

void ui_toast(OS *o, const char *msg) {
    snprintf(o->toast, sizeof o->toast, "%s", msg);
    o->toastT = 3.0;
}

// ---------------------------------------------------------------- lock
static void try_unlock(OS *o) {
    if (check_login_password(o->lockBuf)) {
        o->locked = 0;
        o->lockErr = 0;
        o->lockLen = 0;
        o->lockBuf[0] = 0;
        ui_toast(o, "Welcome to DevOS");
    } else {
        o->lockErr = 1;
        o->lockShake = 1.0;
        o->lockLen = 0;
        o->lockBuf[0] = 0;
    }
}

// ---------------------------------------------------------------- input
static int clamp_i(int v, int lo, int hi) { return v < lo ? lo : v > hi ? hi : v; }

void ui_motion(OS *o, int x, int y, int dx, int dy) {
    o->pmx = o->mx; o->pmy = o->my;
    o->mx = x; o->my = y;

    if (o->dragWin >= 0 && o->dragWin < MAX_WIN) {
        Win *w = &o->wins[o->dragWin];
        if (w->used) {
            if (w->max) {          // max se nikalo, cursor ke relative
                w->max = false;
                w->w = w->sw; w->h = w->sh;
            }
            w->x = x - o->dragDX;
            w->y = y - o->dragDY;
            if (w->y < S(o, 30)) w->y = S(o, 30);
            if (w->x < -w->w + S(o, 80)) w->x = -w->w + S(o, 80);
            if (w->x > o->W - S(o, 80)) w->x = o->W - S(o, 80);
        }
        return;
    }

    if (o->resizing == 2 || o->resizing == 3) {
        Rect tr = slider_rect(o, o->resizing - 2);
        int pct = (x - tr.x) * 100 / (tr.w ? tr.w : 1);
        pct = clamp_i(pct, 0, 100);
        if (o->resizing == 2) {
            o->sys.bright = pct;
            if ((int)(o->t * 8) != (int)((o->t - 0.016) * 8) || pct == 0 || pct == 100)
                sys_set_bright(pct);
        } else {
            o->sys.vol = pct;
            if ((int)(o->t * 8) != (int)((o->t - 0.016) * 8) || pct == 0 || pct == 100)
                sys_set_vol(pct);
        }
        return;
    }

    if (!o->locked) {
        o->dockHot = dock_hit(o, x, y);
        if (o->menuOpen) {
            int mh = menu_hit(o, x, y);
            o->menuHot = mh >= 0 ? mh : -1;
        } else o->menuHot = -1;
    }
    (void)dx; (void)dy;
}

static void click_titlebar(OS *o, Win *w, int x, int y) {
    int cy = w->y + S(o, 20);
    if (y >= w->y + S(o, 4) && y <= w->y + S(o, 36)) {
        int dx1 = abs(x - (w->x + S(o, 20)));
        int dx2 = abs(x - (w->x + S(o, 40)));
        int dx3 = abs(x - (w->x + S(o, 60)));
        if (dx1 <= S(o, 9)) { win_close(o, w); return; }
        if (dx2 <= S(o, 9)) { w->min = true; order_remove(o, (int)(w - o->wins));
                              o->focus = o->nwin ? o->order[o->nwin - 1] : -1; return; }
        if (dx3 <= S(o, 9)) { win_toggle_max(o, w); return; }
    }
    (void)cy;
    o->dragWin = (int)(w - o->wins);
    o->dragDX = x - w->x;
    o->dragDY = y - w->y;
}

static void poweroff_now(OS *o) {
    ui_toast(o, "shutting down…");
    pid_t p = fork();
    if (p == 0) {
        execl("/bin/systemctl", "systemctl", "poweroff", "--no-block", (char *)NULL);
        execl("/sbin/poweroff", "poweroff", (char *)NULL);
        _exit(127);
    }
}

void ui_click(OS *o, int x, int y, int button) {
    if (o->booting || button != 1) return;
    if (o->locked) {
        // arrow button / power chip
        int av = S(o, 74);
        int ay = (int)(o->H * 0.34) + S(o, 96);
        int fw = S(o, 260), fh = S(o, 34);
        int fx = o->W / 2 - fw / 2;
        int fy = ay + av + S(o, 22);
        int abx = fx + fw + S(o, 10);
        if (x >= abx && x <= abx + S(o, 34) && y >= fy && y <= fy + fh) try_unlock(o);
        // power chip
        int cx = o->W - S(o, 54), cyy = o->H - S(o, 54);
        if (abs(x - cx) < S(o, 22) && abs(y - cyy) < S(o, 22))
            poweroff_now(o);
        return;
    }

    // panel open?
    if (o->panelOpen) {
        Rect p = panel_rect(o);
        if (rin(p, x, y)) {
            Rect pr = panel_power_rect(o);
            if (rin(pr, x, y)) { poweroff_now(o); return; }
            for (int i = 0; i < 2; i++) {
                Rect tr = slider_rect(o, i);
                Rect hit = { tr.x, tr.y - S(o, 14), tr.w, tr.h + S(o, 28) };
                if (rin(hit, x, y)) {
                    int pct = clamp_i((x - tr.x) * 100 / (tr.w ? tr.w : 1), 0, 100);
                    if (i == 0) { o->sys.bright = pct; sys_set_bright(pct); }
                    else { o->sys.vol = pct; sys_set_vol(pct); }
                    o->resizing = 2 + i;
                    return;
                }
            }
            return;                 // panel ke andar click — ignore
        }
        o->panelOpen = 0;
    }

    // menu
    if (o->menuOpen) {
        int mh = menu_hit(o, x, y);
        if (mh >= 0 && mh < 8) {
            static const AppKind map[9] = {APP_FILES, APP_TERM, APP_NOTES, APP_SETUP,
                                           APP_MONITOR, APP_SETTINGS, APP_ABOUT, APP_STORE,
                                           APP_INSTALL};
            o->menuOpen = 0; o->menuQ[0] = 0;
            open_app(o, map[mh]);
            return;
        }
        if (mh == -2) return;
        o->menuOpen = 0; o->menuQ[0] = 0;
    }

    // dock
    int dh = dock_hit(o, x, y);
    if (dh >= 0) {
        if (dh == 0) {
            o->menuOpen = !o->menuOpen;
            o->panelOpen = 0;
            if (o->menuOpen) { o->menuQ[0] = 0; o->menuHot = -1; }
            return;
        }
        // dock order: launch, files, term, notes, monitor, setup, settings
        static const AppKind dock_map[7] = {APP_TERM, APP_FILES, APP_TERM, APP_NOTES,
                                            APP_MONITOR, APP_SETUP, APP_SETTINGS};
        open_app(o, dock_map[dh]);
        return;
    }

    // notch
    Rect nr = notch_rect(o);
    if (rin(nr, x, y)) {
        o->panelOpen = !o->panelOpen;
        o->menuOpen = 0; o->menuQ[0] = 0;
        return;
    }

    // windows
    Win *w = win_at(o, x, y);
    if (w) {
        win_raise(o, w);
        if (y < w->y + S(o, 40)) click_titlebar(o, w, x, y);
        else {
            Rect cl = win_client(w);
            app_mouse(o, w, x - cl.x, y - cl.y, button, 1, 0);
        }
        return;
    }

    o->panelOpen = 0;
    o->menuOpen = 0; o->menuQ[0] = 0;
}

void ui_key(OS *o, uint32_t cp, const char *utf8, int mods) {
    if (o->booting) return;
    if (o->locked) {
        if (cp == '\r' || cp == '\n') { try_unlock(o); return; }
        if (cp == 0x7f || cp == '\b') {
            if (o->lockLen > 0) o->lockBuf[--o->lockLen] = 0;
            o->lockErr = 0;
            return;
        }
        if (cp == 27) return;
        if (utf8 && utf8[0] && (unsigned char)utf8[0] >= 32) {
            int l = (int)strlen(utf8);
            if (o->lockLen + l < (int)sizeof(o->lockBuf) - 1) {
                memcpy(o->lockBuf + o->lockLen, utf8, l);
                o->lockLen += l;
                o->lockBuf[o->lockLen] = 0;
                o->lockErr = 0;
            }
        }
        return;
    }

    // shortcuts
    if ((mods & MOD_CTRL) && (mods & MOD_ALT)) {
        if (cp == 't' || cp == 'T') { open_app(o, APP_TERM); return; }
        if (cp == 'f' || cp == 'F') { open_app(o, APP_FILES); return; }
        if (cp == 'n' || cp == 'N') { open_app(o, APP_NOTES); return; }
        if (cp == 'm' || cp == 'M') { open_app(o, APP_MONITOR); return; }
        if (cp == 'l' || cp == 'L') { o->locked = 1; o->lockLen = 0; o->lockBuf[0] = 0;
                                      o->menuOpen = 0; o->panelOpen = 0; return; }
        if (cp == 'p' || cp == 'P') { o->panelOpen = !o->panelOpen; o->menuOpen = 0; return; }
    }
    if (cp == 27) {          // escape
        if (o->menuOpen) { o->menuOpen = 0; o->menuQ[0] = 0; return; }
        if (o->panelOpen) { o->panelOpen = 0; return; }
        close_focused(o);
        return;
    }
    if (o->menuOpen) {
        // asli search — type karo, Enter se pehla match khulta hai
        if (cp == '\r' || cp == '\n') {
            int m = menu_match(o);
            if (m >= 0) {
                static const AppKind map[9] = {APP_FILES, APP_TERM, APP_NOTES, APP_SETUP,
                                               APP_MONITOR, APP_SETTINGS, APP_ABOUT, APP_STORE,
                                               APP_INSTALL};
                o->menuOpen = 0; o->menuQ[0] = 0;
                open_app(o, map[m]);
            }
            return;
        }
        if (cp == 0x7f || cp == '\b') {
            size_t l = strlen(o->menuQ);
            if (l > 0) o->menuQ[l - 1] = 0;
            o->menuHot = menu_match(o);
            return;
        }
        if (cp >= 32 && cp < 127 && !(mods & (MOD_CTRL | MOD_ALT))) {
            size_t l = strlen(o->menuQ);
            if (l + 1 < sizeof o->menuQ) {
                o->menuQ[l] = (char)cp;
                o->menuQ[l + 1] = 0;
            }
            o->menuHot = menu_match(o);
            return;
        }
    }
    if (o->focus >= 0 && o->wins[o->focus].used && o->wins[o->focus].open &&
        !o->wins[o->focus].min)
        app_key(o, &o->wins[o->focus], cp, utf8, mods);
}