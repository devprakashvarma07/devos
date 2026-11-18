// DevOS 2.0 — apna compositor + toolkit (zero Qt, zero third-party branding)
// Ye header poore OS shell ka structure deta hai: canvas, fonts, windows, state.
#ifndef DEVO_H
#define DEVO_H

#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>

// ---------------------------------------------------------------- canvas
// XRGB8888; alpha sirf blend ke waqt use hota hai.
typedef struct { uint32_t *px; int w, h, stride; } Canvas;

typedef struct { uint8_t r, g, b, a; } Col;

static inline Col col(int r, int g, int b, int a) {
    Col c; c.r = (uint8_t)r; c.g = (uint8_t)g; c.b = (uint8_t)b; c.a = (uint8_t)a;
    return c;
}
#define RGB(r, g, b) col(r, g, b, 255)

typedef struct { int x, y, w, h; } Rect;
static inline bool rin(Rect r, int x, int y) {
    return x >= r.x && y >= r.y && x < r.x + r.w && y < r.y + r.h;
}

void cv_init(Canvas *c, uint32_t *px, int w, int h, int stride);
void cv_clear(Canvas *c, Col col);
void cv_fill(Canvas *c, int x, int y, int w, int h, Col col);
void cv_vgrad(Canvas *c, int x, int y, int w, int h, Col top, Col bot);
void cv_rgrad(Canvas *c, int cx, int cy, int r, Col inner, Col outer);   // radial glow
void cv_rrect(Canvas *c, int x, int y, int w, int h, int r, Col col);
void cv_rrect_ex(Canvas *c, int x, int y, int w, int h, float r, Col col);
void cv_rrect_border(Canvas *c, int x, int y, int w, int h, int r, int bw, Col col);
void cv_circle(Canvas *c, int cx, int cy, float r, Col col);
void cv_line(Canvas *c, float x0, float y0, float x1, float y1, float width, Col col);
void cv_shadow(Canvas *c, int x, int y, int w, int h, int r, int spread, Col col);
void cv_blit(Canvas *dst, Canvas *src, int dx, int dy, int alpha);
void cv_image(Canvas *c, int x, int y, int w, int h, const uint32_t *px, int iw, int ih);
void cv_blend_px(uint32_t *p, Col c, int a);

// ---------------------------------------------------------------- fonts
typedef struct Font Font;
Font *font_load(const char *path, int px);
int font_ascent(Font *f);
int font_descent(Font *f);
int font_height(Font *f);
int text_w(Font *f, const char *s);
int text_w_n(Font *f, const char *s, int n);
// x = left edge, baseline = baseline y. Returns advance width.
int text_draw(Canvas *c, Font *f, int x, int baseline, const char *s, Col col);
int text_draw_tracked(Canvas *c, Font *f, int x, int baseline, const char *s, int track, Col col);
void text_center(Canvas *c, Font *f, int cx, int baseline, const char *s, Col col);
void text_right(Canvas *c, Font *f, int rx, int baseline, const char *s, Col col);
void text_elide(Canvas *c, Font *f, int x, int y, int w, int baseline, const char *s, Col col);
int text_fit(Font *f, const char *s, int maxw);   // bytes that fit

// ---------------------------------------------------------------- system
typedef struct {
    int bright, brightMax, brightOk;
    int vol, volOk;
    int batPct, batOk;
    char batState[24];
    char net[64];
    char host[64];
    char kernel[64];
    char cpu[96];
    double uptime;
    unsigned long memTotalKb, memAvailKb;
    double load1;
    unsigned long diskTotalKb, diskFreeKb;
    int pkgs;
} SysInfo;
void sys_refresh(SysInfo *s);
void sys_set_bright(int pct);
void sys_set_vol(int pct);
const char *sys_uptime_str(SysInfo *s, char *buf, int n);

// ---------------------------------------------------------------- apps
typedef enum {
    APP_TERM = 0, APP_FILES, APP_NOTES, APP_MONITOR, APP_SETTINGS,
    APP_ABOUT, APP_STORE, APP_SETUP, APP_INSTALL, APP_KIND_COUNT
} AppKind;

typedef struct { uint32_t ch; uint8_t fg, bg; } Cell;

typedef struct {
    int master;
    pid_t pid;
    int cols, rows;
    Cell *grid;
    int cx, cy;
    bool running;
    bool need_draw;
    char in[512];
    int inlen;
    char hist[8][256];
    int histn;
    int pending;
    uint8_t pending_bytes[4];
} Term;

typedef struct {
    char path[512];
    int scroll;
    int sel;
    int nent;
    char names[128][64];
    bool isdir[128];
    char preview[6000];
    int prevlen;
    char pvname[128];
} FilesState;

typedef struct {
    char buf[16384];
    int len, cur;
    bool loaded, dirty;
} NotesState;

typedef struct {
    AppKind kind;
    bool used, open, min, max;
    char title[64];
    int x, y, w, h;
    int sx, sy, sw, sh;
    Term *term;
    FilesState *files;
    NotesState *notes;
} Win;

#define MAX_WIN 10

// ---------------------------------------------------------------- wallpaper (R6)
enum { WP_COVER = 0, WP_FIT, WP_STRETCH, WP_CENTER, WP_TILE };

typedef struct {
    char path[512];
    int mode;
    uint32_t *px;      // screen ke liye scaled XRGB buffer (o->W * o->H)
    int loaded;
    long cfg_mtime;    // config file ki mtime — live reload detect ke liye
} Wallpaper;

const char *wp_mode_name(int mode);
int wp_mode_parse(const char *s);
void wp_config_path(char *out, size_t n);
int wp_scan(char paths[][512], int max);
int wp_thumb(const char *path, uint32_t **out);
#define WP_THUMB_W 150
#define WP_THUMB_H 84

typedef struct {
    int W, H;
    float scale;
    Canvas cv;
    Canvas bg;
    double bootT;            // 0..1
    double t;                // seconds since start
    int booting, locked;
    int panelOpen, menuOpen;
    char menuQ[40];                 // real search query (start menu)
    double panelAnim, menuAnim;
    int mx, my, pmx, pmy;
    int mdown;
    int shift;
    Win wins[MAX_WIN];
    int order[MAX_WIN];      // z order, last = top
    int nwin;
    int focus;               // win index or -1
    int dragWin, dragDX, dragDY;
    int resizing;
    char lockBuf[64];
    int lockLen, lockErr;
    double lockShake;
    char toast[160];
    double toastT;
    char activeApp[64];
    AppKind recent[3]; int nrecent; // real recently-opened apps
    bool cursorVisible;
    SysInfo sys;
    double sysT;
    double clockT;
    int menuHot;
    int dockHot;
    int notesFocus;
    int termFocus;
    bool autologin;
    bool showFps;
    double fps;
    char sceneOverride[32];
    Wallpaper wp;
} OS;

void wp_reload(OS *o);
void wp_apply(OS *o, const char *path, int mode);
int wp_watch(OS *o);
void wp_init(OS *o);

void os_draw(OS *o);
void os_draw_wallpaper(OS *o);
void os_draw_splash(OS *o, Canvas *c);
void os_draw_lock(OS *o, Canvas *c);
void os_draw_desktop(OS *o, Canvas *c);
void os_draw_cursor(OS *o, Canvas *c);

// window manager
Win *win_new(OS *o, AppKind k);
void win_close(OS *o, Win *w);
void win_raise(OS *o, Win *w);
Win *win_at(OS *o, int x, int y);
Rect win_rect(Win *w);
Rect win_client(Win *w);
void win_toggle_max(OS *o, Win *w);
void open_app(OS *o, AppKind k);
void close_focused(OS *o);

enum { MOD_SHIFT = 1, MOD_ALT = 2, MOD_CTRL = 4, MOD_LOGO = 8 };

// app layer
void app_open(OS *o, Win *w);
void app_close(Win *w);
void app_draw(OS *o, Canvas *c, Win *w);
void app_mouse(OS *o, Win *w, int lx, int ly, int button, int down, int wheel);
void app_key(OS *o, Win *w, uint32_t cp, const char *utf8, int mods);
void app_title(Win *w);
void app_size(OS *o, AppKind k, int *w, int *h);
void app_tick(OS *o, Win *w);

void term_open(Win *w);
void term_spawn(Term *t);
void term_read(Term *t);
void term_write_str(Term *t, const char *s);
void term_key(Term *t, uint32_t cp, const char *utf8, int mods);
void term_draw(Canvas *c, Term *t, Rect r);
void term_resize(Term *t, int cols, int rows);

void files_open(Win *w);
void files_nav(Win *w, const char *p);
void files_draw(Canvas *c, Win *w, Rect r);
void files_click(Win *w, int x, int y);
void files_key(Win *w, uint32_t cp);

void notes_open(Win *w);
void notes_draw(Canvas *c, Win *w, Rect r);
void notes_key(Win *w, uint32_t cp, const char *utf8);
void notes_click(Win *w, int x, int y);
void notes_save(Win *w);

// ---------------------------------------------------------------- helpers
void fs_join(char *out, int n, const char *a, const char *b);
int fs_read(const char *path, char *buf, int n);
bool fs_write(const char *path, const char *buf, int n);
void str_trunc(char *dst, int n, const char *src, int maxbytes);
const char *home_dir(void);
void human_kb(char *out, int n, unsigned long kb);
uint64_t mono_ms(void);

// ui pieces
void ui_draw_window(OS *o, Canvas *c, Win *w);
void ui_draw_notch(OS *o, Canvas *c);
void ui_draw_panel(OS *o, Canvas *c);
void ui_draw_dock(OS *o, Canvas *c);
void ui_draw_menu(OS *o, Canvas *c);
void ui_draw_toast(OS *o, Canvas *c);
Rect notch_rect(OS *o);
Rect panel_rect(OS *o);
Rect dock_rect(OS *o);
Rect menu_rect(OS *o);
int dock_hit(OS *o, int x, int y);        // -1 none, 0..6 item, 7 launch
int notch_hit(OS *o, int x, int y);
int menu_hit(OS *o, int x, int y);
int menu_match(OS *o);              // search query -> app index (-1 none)
Rect slider_rect(OS *o, int which);      // 0 brightness, 1 volume
Rect panel_power_rect(OS *o);            // footer power chip

void ui_click(OS *o, int x, int y, int button);
void ui_motion(OS *o, int x, int y, int dx, int dy);
void ui_key(OS *o, uint32_t cp, const char *utf8, int mods);
void ui_toast(OS *o, const char *msg);
void icon_draw(Canvas *c, int kind, int x, int y, int size, Col col);

extern OS *g_os;

// fonts handle
extern Font *F_UI, *F_UI_B, *F_SM, *F_MONO, *F_HUGE;
void fonts_init(const char *dir);

#endif