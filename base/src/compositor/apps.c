// apps.c — DevOS ke real apps: terminal (PTY), files, notes, monitor,
// settings, about, store, setup. Sab kuch system se live padhta hai.
#define _GNU_SOURCE
#include "devo.h"
#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <pty.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/sysinfo.h>
#include <sys/utsname.h>
#include <sys/wait.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>

extern Font *F_UI, *F_UI_B, *F_SM, *F_MONO, *F_HUGE;

static int S(OS *o, int v) { return (int)(v * o->scale + 0.5f); }
#define C_TEXT  RGB(235, 237, 242)
#define C_DIM   RGB(150, 152, 160)
#define C_DIM2  RGB(110, 112, 120)
#define C_MUTED RGB(80, 82, 90)
#define C_ACC   RGB(10, 132, 255)
#define C_LINE  RGB(40, 40, 46)
#define C_CARD  RGB(20, 20, 24)

// ---------------------------------------------------------------- helpers
uint64_t mono_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

const char *home_dir(void) {
    const char *h = getenv("HOME");
    if (h && h[0]) return h;
    return "/root";
}

void str_trunc(char *dst, int n, const char *src, int maxbytes) {
    int i = 0;
    if (maxbytes > n - 1) maxbytes = n - 1;
    while (src[i] && i < maxbytes) { dst[i] = src[i]; i++; }
    dst[i] = 0;
}

void fs_join(char *out, int n, const char *a, const char *b) {
    if (!b || !b[0]) { snprintf(out, n, "%s", a); return; }
    int la = (int)strlen(a);
    if (la && a[la - 1] == '/') snprintf(out, n, "%s%s", a, b);
    else snprintf(out, n, "%s/%s", a, b);
}

int fs_read(const char *path, char *buf, int n) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return -1;
    int total = 0;
    while (total < n - 1) {
        int r = (int)read(fd, buf + total, n - 1 - total);
        if (r <= 0) break;
        total += r;
    }
    close(fd);
    buf[total] = 0;
    return total;
}

bool fs_write(const char *path, const char *buf, int n) {
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) return false;
    int total = 0;
    while (total < n) {
        int r = (int)write(fd, buf + total, n - total);
        if (r <= 0) break;
        total += r;
    }
    close(fd);
    return total == n;
}

void human_kb(char *out, int n, unsigned long kb) {
    double v = kb;
    if (v >= 1024.0 * 1024) snprintf(out, n, "%.1f GB", v / 1024 / 1024);
    else if (v >= 1024) snprintf(out, n, "%.1f MB", v / 1024);
    else snprintf(out, n, "%lu KB", kb);
}

// ---------------------------------------------------------------- system
static int read_int(const char *path, int *out) {
    char b[64];
    if (fs_read(path, b, sizeof b) <= 0) return -1;
    *out = atoi(b);
    return 0;
}

void sys_refresh(SysInfo *s) {
    // brightness
    s->brightOk = 0;
    DIR *d = opendir("/sys/class/backlight");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            char p[256];
            int cur, mx;
            snprintf(p, sizeof p, "/sys/class/backlight/%s/brightness", e->d_name);
            if (read_int(p, &cur)) continue;
            snprintf(p, sizeof p, "/sys/class/backlight/%s/max_brightness", e->d_name);
            if (read_int(p, &mx) || mx <= 0) continue;
            s->brightMax = mx;
            s->bright = cur * 100 / mx;
            s->brightOk = 1;
            break;
        }
        closedir(d);
    }
    // volume (amixer)
    s->volOk = 0;
    FILE *fp = popen("amixer get Master 2>/dev/null | grep -o '\\[[0-9]*%\\]' | head -1", "r");
    if (fp) {
        char b[32] = {0};
        if (fgets(b, sizeof b, fp)) {
            int v = atoi(b + 1);
            if (v >= 0 && v <= 100) { s->vol = v; s->volOk = 1; }
        }
        pclose(fp);
    }
    // battery
    s->batOk = 0;
    const char *bats[] = {"/sys/class/power_supply/BAT0", "/sys/class/power_supply/BAT1",
                          "/sys/class/power_supply/battery"};
    for (int i = 0; i < 3; i++) {
        char p[256];
        int cap;
        snprintf(p, sizeof p, "%s/capacity", bats[i]);
        if (read_int(p, &cap) == 0) {
            s->batPct = cap;
            snprintf(p, sizeof p, "%s/status", bats[i]);
            char st[32] = "Unknown";
            fs_read(p, st, sizeof st);
            char *nl = strchr(st, '\n');
            if (nl) *nl = 0;
            snprintf(s->batState, sizeof s->batState, "%s", st);
            s->batOk = 1;
            break;
        }
    }
    // network
    s->net[0] = 0;
    d = opendir("/sys/class/net");
    if (d) {
        struct dirent *e;
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.' || strcmp(e->d_name, "lo") == 0) continue;
            char p[256], st[16] = {0};
            snprintf(p, sizeof p, "/sys/class/net/%s/operstate", e->d_name);
            fs_read(p, st, sizeof st);
            if (strncmp(st, "up", 2) == 0) {
                snprintf(s->net, sizeof s->net, "%s", e->d_name);
                break;
            }
        }
        closedir(d);
    }
    gethostname(s->host, sizeof s->host);
    struct utsname u;
    if (uname(&u) == 0) snprintf(s->kernel, sizeof s->kernel, "%s", u.release);
    // cpu
    FILE *cf = fopen("/proc/cpuinfo", "r");
    if (cf) {
        char line[256];
        while (fgets(line, sizeof line, cf)) {
            if (strncmp(line, "model name", 10) == 0) {
                char *c = strchr(line, ':');
                if (c) {
                    c++;
                    while (*c == ' ') c++;
                    char *nl = strchr(c, '\n');
                    if (nl) *nl = 0;
                    snprintf(s->cpu, sizeof s->cpu, "%s", c);
                    break;
                }
            }
        }
        fclose(cf);
    }
    // uptime
    char b[128];
    if (fs_read("/proc/uptime", b, sizeof b) > 0) s->uptime = atof(b);
    // mem
    if (fs_read("/proc/meminfo", b, sizeof b) > 0) {
        unsigned long t = 0, a = 0;
        sscanf(b, "MemTotal: %lu kB\nMemFree: %*u kB\nMemAvailable: %lu kB", &t, &a);
        s->memTotalKb = t;
        s->memAvailKb = a;
    }
    // load
    if (fs_read("/proc/loadavg", b, sizeof b) > 0) s->load1 = atof(b);
    // disk
    struct statvfs sv;
    if (statvfs("/", &sv) == 0) {
        s->diskTotalKb = (unsigned long)sv.f_blocks * sv.f_frsize / 1024;
        s->diskFreeKb = (unsigned long)sv.f_bavail * sv.f_frsize / 1024;
    }
    // packages
    FILE *pf = fopen("/var/lib/dpkg/status", "r");
    if (pf) {
        char line[256];
        int n = 0;
        while (fgets(line, sizeof line, pf))
            if (strncmp(line, "Package:", 8) == 0) n++;
        fclose(pf);
        s->pkgs = n;
    }
}

const char *sys_uptime_str(SysInfo *s, char *buf, int n) {
    int up = (int)s->uptime;
    int d = up / 86400, h = (up % 86400) / 3600, m = (up % 3600) / 60;
    if (d > 0) snprintf(buf, n, "%dd %dh", d, h);
    else if (h > 0) snprintf(buf, n, "%dh %dm", h, m);
    else snprintf(buf, n, "%dm", m);
    return buf;
}

void sys_set_bright(int pct) {
    if (pct < 1) pct = 1;
    if (pct > 100) pct = 100;
    DIR *d = opendir("/sys/class/backlight");
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (e->d_name[0] == '.') continue;
        char p[256];
        int mx = 0;
        snprintf(p, sizeof p, "/sys/class/backlight/%s/max_brightness", e->d_name);
        if (read_int(p, &mx) || mx <= 0) continue;
        int val = mx * pct / 100;
        if (val < 1) val = 1;
        snprintf(p, sizeof p, "/sys/class/backlight/%s/brightness", e->d_name);
        int fd = open(p, O_WRONLY);
        if (fd >= 0) {
            char b[32];
            int n = snprintf(b, sizeof b, "%d", val);
            if (write(fd, b, n) < 0) {}
            close(fd);
        }
        break;
    }
    closedir(d);
}

void sys_set_vol(int pct) {
    if (pct < 0) pct = 0;
    if (pct > 100) pct = 100;
    char cmd[128];
    snprintf(cmd, sizeof cmd, "amixer set Master %d%% >/dev/null 2>&1", pct);
    if (system(cmd) != 0) {}
}

// ---------------------------------------------------------------- terminal
#define COL_BG 0
static const Col TERM_FG[4] = {
    {210, 212, 218, 255}, {120, 160, 210, 255}, {110, 210, 140, 255}, {230, 120, 120, 255}
};

void term_resize(Term *t, int cols, int rows) {
    if (cols < 8) cols = 8;
    if (rows < 4) rows = 4;
    if (cols == t->cols && rows == t->rows && t->grid) return;
    Cell *g = calloc((size_t)cols * rows, sizeof(Cell));
    if (t->grid) {
        int rc = cols < t->cols ? cols : t->cols;
        int rr = rows < t->rows ? rows : t->rows;
        for (int y = 0; y < rr; y++)
            memcpy(g + (size_t)y * cols, t->grid + (size_t)y * t->cols, rc * sizeof(Cell));
        free(t->grid);
    }
    t->grid = g;
    t->cols = cols;
    t->rows = rows;
    if (t->cx >= cols) t->cx = cols - 1;
    if (t->cy >= rows) t->cy = rows - 1;
    if (t->master >= 0) {
        struct winsize ws = { (unsigned short)rows, (unsigned short)cols, 0, 0 };
        ioctl(t->master, TIOCSWINSZ, &ws);
        kill(t->pid, SIGWINCH);
    }
}

static void term_scroll(Term *t) {
    memmove(t->grid, t->grid + t->cols, (size_t)(t->rows - 1) * t->cols * sizeof(Cell));
    memset(t->grid + (size_t)(t->rows - 1) * t->cols, 0, t->cols * sizeof(Cell));
}

static void term_cr(Term *t) { t->cx = 0; }
static void term_lf(Term *t) {
    t->cy++;
    if (t->cy >= t->rows) { term_scroll(t); t->cy = t->rows - 1; }
}
static void term_put(Term *t, uint32_t ch, uint8_t fg) {
    if (t->cx >= t->cols) { t->cx = 0; term_lf(t); }
    Cell *c = &t->grid[(size_t)t->cy * t->cols + t->cx];
    c->ch = ch;
    c->fg = fg;
    t->cx++;
}

void term_write_str(Term *t, const char *s) {
    if (!t->grid) return;
    for (const char *p = s; *p; p++) term_put(t, (unsigned char)*p, 0);
    t->need_draw = true;
}

static void term_feed(Term *t, const char *data, int n) {
    static int st = 0;          // 0 ground, 1 esc, 2 csi, 3 osc
    static int params[8], np = 0, cur = -1;
    static int priv = 0;
    if (!t->grid) return;
    for (int i = 0; i < n; i++) {
        unsigned char ch = (unsigned char)data[i];
        switch (st) {
        case 0: {
            if (ch == 0x1b) { st = 1; break; }
            if (ch == '\r') { term_cr(t); break; }
            if (ch == '\n') { term_lf(t); break; }
            if (ch == '\b') { if (t->cx > 0) t->cx--; break; }
            if (ch == '\t') {
                int nx = (t->cx / 8 + 1) * 8;
                while (t->cx < nx && t->cx < t->cols) term_put(t, ' ', 0);
                break;
            }
            if (ch == 0x07) break;
            if (ch < 0x20) break;
            if (ch < 0x80) { term_put(t, ch, 0); break; }
            // UTF-8 sequence
            uint32_t cp = 0;
            int need = 0;
            if ((ch & 0xE0) == 0xC0) { cp = ch & 0x1F; need = 1; }
            else if ((ch & 0xF0) == 0xE0) { cp = ch & 0x0F; need = 2; }
            else if ((ch & 0xF8) == 0xF0) { cp = ch & 0x07; need = 3; }
            else break;
            int got = 0;
            while (got < need && i + 1 < n) {
                unsigned char c2 = (unsigned char)data[++i];
                if ((c2 & 0xC0) != 0x80) break;
                cp = (cp << 6) | (c2 & 0x3F);
                got++;
            }
            term_put(t, cp, 0);
            break;
        }
        case 1: {
            if (ch == '[') { st = 2; np = 0; cur = -1; priv = 0; break; }
            if (ch == ']') { st = 3; break; }
            if (ch == '(' || ch == ')') { st = 1; break; }
            st = 0;
            break;
        }
        case 2: {
            if (ch >= '0' && ch <= '9') {
                if (cur < 0) cur = 0;
                cur = cur * 10 + (ch - '0');
            } else if (ch == ';') {
                if (np < 8) params[np++] = cur < 0 ? 0 : cur;
                cur = -1;
            } else if (ch == '?') {
                priv = 1;
            } else if (ch >= 0x40 && ch <= 0x7e) {
                if (cur >= 0 && np < 8) params[np++] = cur;
                cur = -1;
                int p0 = np > 0 ? params[0] : 1;
                int p1 = np > 1 ? params[1] : 1;
                switch (ch) {
                case 'H': case 'f':
                    t->cy = p0 < 1 ? 0 : p0 - 1;
                    t->cx = p1 < 1 ? 0 : p1 - 1;
                    if (t->cy >= t->rows) t->cy = t->rows - 1;
                    if (t->cx >= t->cols) t->cx = t->cols - 1;
                    break;
                case 'A': t->cy -= p0; if (t->cy < 0) t->cy = 0; break;
                case 'B': t->cy += p0; if (t->cy >= t->rows) t->cy = t->rows - 1; break;
                case 'C': t->cx += p0; if (t->cx >= t->cols) t->cx = t->cols - 1; break;
                case 'D': t->cx -= p0; if (t->cx < 0) t->cx = 0; break;
                case 'G': t->cx = p0 < 1 ? 0 : p0 - 1; if (t->cx >= t->cols) t->cx = t->cols - 1; break;
                case 'd': t->cy = p0 < 1 ? 0 : p0 - 1; if (t->cy >= t->rows) t->cy = t->rows - 1; break;
                case 'J':
                    if (p0 == 0 || np == 0) {
                        for (int x = t->cx; x < t->cols; x++) t->grid[(size_t)t->cy * t->cols + x].ch = 0;
                        for (int y = t->cy + 1; y < t->rows; y++)
                            memset(t->grid + (size_t)y * t->cols, 0, t->cols * sizeof(Cell));
                    } else {
                        memset(t->grid, 0, (size_t)t->rows * t->cols * sizeof(Cell));
                    }
                    break;
                case 'K':
                    if (p0 == 0) for (int x = t->cx; x < t->cols; x++) t->grid[(size_t)t->cy * t->cols + x].ch = 0;
                    else if (p0 == 1) for (int x = 0; x <= t->cx && x < t->cols; x++) t->grid[(size_t)t->cy * t->cols + x].ch = 0;
                    else memset(t->grid + (size_t)t->cy * t->cols, 0, t->cols * sizeof(Cell));
                    break;
                case 'P': {
                    int l = p0;
                    if (l < 1) l = 1;
                    for (int x = t->cx; x < t->cols; x++) {
                        int src = x + l;
                        t->grid[(size_t)t->cy * t->cols + x] =
                            src < t->cols ? t->grid[(size_t)t->cy * t->cols + src] : (Cell){0, 0, 0};
                    }
                    break;
                }
                case 'X': {
                    int l = p0 < 1 ? 1 : p0;
                    for (int x = t->cx; x < t->cx + l && x < t->cols; x++)
                        t->grid[(size_t)t->cy * t->cols + x].ch = 0;
                    break;
                }
                case 'L': case 'M': {
                    int l = p0 < 1 ? 1 : p0;
                    if (ch == 'L') {
                        for (int k = 0; k < l; k++) {
                            memmove(t->grid + (size_t)(t->cy + 1) * t->cols,
                                    t->grid + (size_t)t->cy * t->cols,
                                    (size_t)(t->rows - t->cy - 1) * t->cols * sizeof(Cell));
                            memset(t->grid + (size_t)t->cy * t->cols, 0, t->cols * sizeof(Cell));
                        }
                    } else {
                        for (int k = 0; k < l; k++) {
                            memmove(t->grid + (size_t)t->cy * t->cols,
                                    t->grid + (size_t)(t->cy + 1) * t->cols,
                                    (size_t)(t->rows - t->cy - 1) * t->cols * sizeof(Cell));
                            memset(t->grid + (size_t)(t->rows - 1) * t->cols, 0, t->cols * sizeof(Cell));
                        }
                    }
                    break;
                }
                case 'm': {
                    // colors — simple palette mapping
                    int mode = np > 0 ? params[0] : 0;
                    (void)mode;   // 0 reset handled by next text default
                    break;
                }
                default: break;
                }
                (void)priv;
                st = 0;
                np = 0;
            }
            break;
        }
        case 3: {
            if (ch == 0x07) st = 0;
            else if (ch == 0x1b) st = 0;
            break;
        }
        }
    }
    t->need_draw = true;
}

void term_read(Term *t) {
    if (t->master < 0) return;
    char b[8192];
    for (;;) {
        int r = (int)read(t->master, b, sizeof b);
        if (r > 0) { term_feed(t, b, r); continue; }
        if (r == 0) { t->running = false; break; }
        if (errno == EAGAIN || errno == EWOULDBLOCK) break;
        if (errno == EINTR) continue;
        t->running = false;
        break;
    }
}

void term_spawn(Term *t);

void term_open(Win *w) {
    Term *t = calloc(1, sizeof(Term));
    t->master = -1;
    t->running = true;
    t->cols = 80;
    t->rows = 24;
    term_resize(t, t->cols, t->rows);
    w->term = t;
    term_spawn(t);
}

void term_spawn(Term *t) {
    if (t->master >= 0) return;
    if (!t->grid) term_resize(t, t->cols, t->rows);
    struct winsize ws = { (unsigned short)t->rows, (unsigned short)t->cols, 0, 0 };
    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &ws);
    if (pid == 0) {
        setenv("TERM", "xterm-256color", 1);
        setenv("LANG", "C.UTF-8", 1);
        setenv("PS1", "devos:\\w$ ", 1);
        setenv("HOME", home_dir(), 1);
        chdir(home_dir());
        execl("/bin/bash", "bash", "--noprofile", "--norc", "-i", (char *)NULL);
        _exit(1);
    }
    if (pid < 0) {
        term_write_str(t, "cannot start shell\r\n");
        t->running = false;
        return;
    }
    t->master = master;
    t->pid = pid;
    int fl = fcntl(master, F_GETFL);
    fcntl(master, F_SETFL, fl | O_NONBLOCK);
}

void term_key(Term *t, uint32_t cp, const char *utf8, int mods) {
    if (!t->grid || t->master < 0) return;
    char out[16];
    int n = 0;
    if (cp == '\r' || cp == '\n') out[n++] = '\r';
    else if (cp == 0x7f || cp == '\b') out[n++] = 0x7f;
    else if (cp == '\t') out[n++] = '\t';
    else if (cp == 27) out[n++] = 27;
    else if (cp == 0x100 || cp == 0x101 || cp == 0x102 || cp == 0x103) {
        const char *seq = cp == 0x100 ? "\x1b[A" : cp == 0x101 ? "\x1b[B" : cp == 0x102 ? "\x1b[C" : "\x1b[D";
        for (const char *p = seq; *p; p++) out[n++] = *p;
    } else if (cp == 0x104) {          // home
        const char *seq = "\x1b[H";
        for (const char *p = seq; *p; p++) out[n++] = *p;
    } else if (cp == 0x105) {          // end
        const char *seq = "\x1b[F";
        for (const char *p = seq; *p; p++) out[n++] = *p;
    } else if (cp == 0x106) out[n++] = 0x1b; // delete ~
    else if ((mods & MOD_CTRL) && cp >= 'a' && cp <= 'z') out[n++] = (char)(cp - 'a' + 1);
    else if ((mods & MOD_CTRL) && cp >= 'A' && cp <= 'Z') out[n++] = (char)(cp - 'A' + 1);
    else if (utf8 && utf8[0]) {
        for (int i = 0; utf8[i] && n < 15; i++) out[n++] = utf8[i];
    }
    if (n > 0) {
        if (write(t->master, out, n) < 0) {}
    }
}

void term_draw(Canvas *c, Term *t, Rect r) {
    if (!t->grid) return;
    Font *fm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
                         (int)(13 * (r.w > 700 ? 1.0 : 0.85)));
    int fh = font_height(fm);
    if (fh <= 0) fh = 16;
    int cellh = fh + 2;
    int cellw = text_w(fm, "M");
    if (cellw <= 0) cellw = 8;
    int cols = r.w / cellw, rows = (r.h - 8) / cellh;
    if (cols < 8) cols = 8;
    if (rows < 4) rows = 4;
    if (cols != t->cols || rows != t->rows) term_resize(t, cols, rows);

    int asc = font_ascent(fm);
    for (int y = 0; y < t->rows; y++) {
        int by = r.y + 4 + y * cellh + asc;
        if (by > r.y + r.h) break;
        for (int x = 0; x < t->cols; x++) {
            Cell *cell = &t->grid[(size_t)y * t->cols + x];
            if (!cell->ch || cell->ch == ' ') continue;
            char u[8];
            int n = 0;
            uint32_t cp = cell->ch;
            if (cp < 0x80) u[n++] = (char)cp;
            else if (cp < 0x800) { u[n++] = (char)(0xC0 | (cp >> 6)); u[n++] = (char)(0x80 | (cp & 0x3F)); }
            else if (cp < 0x10000) { u[n++] = (char)(0xE0 | (cp >> 12)); u[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); u[n++] = (char)(0x80 | (cp & 0x3F)); }
            else { u[n++] = (char)(0xF0 | (cp >> 18)); u[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); u[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); u[n++] = (char)(0x80 | (cp & 0x3F)); }
            u[n] = 0;
            text_draw(c, fm, r.x + 8 + x * cellw, by, u, TERM_FG[cell->fg < 4 ? cell->fg : 0]);
        }
    }
    // block cursor
    if (t->running && fmod((double)mono_ms() / 1000.0, 1.0) < 0.55) {
        int px = r.x + 8 + t->cx * cellw;
        int py = r.y + 4 + t->cy * cellh;
        if (px + cellw < r.x + r.w && py + cellh < r.y + r.h)
            cv_rrect(c, px, py + 1, cellw, cellh - 2, 1, col(200, 205, 215, 90));
    }
}

// ---------------------------------------------------------------- files
static int cmp_ent(const void *a, const void *b) {
    const char *x = a, *y = b;
    return strcasecmp(x, y);
}

void files_open(Win *w) {
    FilesState *f = calloc(1, sizeof(FilesState));
    w->files = f;
    files_nav(w, home_dir());
}

void files_nav(Win *w, const char *p) {
    FilesState *f = w->files;
    if (!f) return;
    if (p[0] == '~') snprintf(f->path, sizeof f->path, "%s%s", home_dir(), p + 1);
    else snprintf(f->path, sizeof f->path, "%s", p);
    f->nent = 0;
    f->scroll = 0;
    f->sel = -1;
    DIR *d = opendir(f->path);
    if (!d) { snprintf(f->preview, sizeof f->preview, "cannot open %s", f->path); f->prevlen = (int)strlen(f->preview); return; }
    char dirs[96][64];
    char files[160][64];
    int nd = 0, nf = 0;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (strcmp(e->d_name, ".") == 0) continue;
        if (e->d_name[0] == '.' && strcmp(e->d_name, "..") != 0) continue;
        if (strcmp(e->d_name, "..") == 0) { snprintf(dirs[nd++], 64, "%s", e->d_name); continue; }
        char full[600];
        fs_join(full, sizeof full, f->path, e->d_name);
        struct stat st;
        if (stat(full, &st) == 0 && S_ISDIR(st.st_mode)) {
            if (nd < 96) snprintf(dirs[nd++], 64, "%s", e->d_name);
        } else {
            if (nf < 160) snprintf(files[nf++], 64, "%s", e->d_name);
        }
    }
    closedir(d);
    qsort(dirs, nd, 64, cmp_ent);
    qsort(files, nf, 64, cmp_ent);
    // '..' sabse upar
    for (int i = 0; i < nd && f->nent < 128; i++) {
        if (strcmp(dirs[i], "..") != 0) continue;
        snprintf(f->names[f->nent], 64, "%s", dirs[i]);
        f->isdir[f->nent++] = true;
    }
    for (int i = 0; i < nd && f->nent < 128; i++) {
        if (strcmp(dirs[i], "..") == 0) continue;
        snprintf(f->names[f->nent], 64, "%s", dirs[i]);
        f->isdir[f->nent++] = true;
    }
    for (int i = 0; i < nf && f->nent < 128; i++) {
        snprintf(f->names[f->nent], 64, "%s", files[i]);
        f->isdir[f->nent++] = false;
    }
    snprintf(f->pvname, sizeof f->pvname, "%s", "");
    f->preview[0] = 0;
    f->prevlen = 0;
}

static void files_preview(Win *w, const char *name) {
    FilesState *f = w->files;
    char full[600];
    fs_join(full, sizeof full, f->path, name);
    struct stat st;
    if (stat(full, &st) != 0) return;
    snprintf(f->pvname, sizeof f->pvname, "%s", name);
    if (st.st_size > 200000 || !S_ISREG(st.st_mode)) {
        snprintf(f->preview, sizeof f->preview,
                 "%s\n\n%d bytes · %s", name, (int)st.st_size,
                 S_ISDIR(st.st_mode) ? "directory" : "binary or large file");
        f->prevlen = (int)strlen(f->preview);
        return;
    }
    int n = fs_read(full, f->preview, sizeof f->preview - 1);
    if (n < 0) n = 0;
    f->preview[n] = 0;
    // binary check
    for (int i = 0; i < n; i++) {
        if ((unsigned char)f->preview[i] < 9) {
            snprintf(f->preview, sizeof f->preview, "%s\n\nbinary file · %d bytes", name, (int)st.st_size);
            f->prevlen = (int)strlen(f->preview);
            return;
        }
    }
    f->prevlen = n;
}

void files_click(Win *w, int x, int y) {
    FilesState *f = w->files;
    if (!f) return;
    // up button
    if (y < 40 && x < 44) {
        char p[512];
        snprintf(p, sizeof p, "%s", f->path);
        char *slash = strrchr(p, '/');
        if (slash && slash != p) { *slash = 0; files_nav(w, p); }
        else if (slash == p) files_nav(w, "/");
        return;
    }
    int top = 44;
    int row = (y - top) / 28;
    int idx = row + f->scroll;
    if (y < top) return;
    if (idx >= 0 && idx < f->nent) {
        if (f->isdir[idx]) {
            if (strcmp(f->names[idx], "..") == 0) {
                char p[512];
                snprintf(p, sizeof p, "%s", f->path);
                char *slash = strrchr(p, '/');
                if (slash && slash != p) { *slash = 0; files_nav(w, p); }
                else files_nav(w, "/");
            } else {
                char p[600];
                fs_join(p, sizeof p, f->path, f->names[idx]);
                files_nav(w, p);
            }
        } else {
            f->sel = idx;
            files_preview(w, f->names[idx]);
        }
    }
}

void files_key(Win *w, uint32_t cp) {
    FilesState *f = w->files;
    if (!f) return;
    if (cp == 0x101) { if (f->sel < f->nent - 1) f->sel++; }
    else if (cp == 0x100) { if (f->sel > 0) f->sel--; }
    else if (cp == '\r' || cp == '\n') {
        if (f->sel >= 0 && f->sel < f->nent) {
            if (f->isdir[f->sel]) {
                char p[600];
                fs_join(p, sizeof p, f->path, f->names[f->sel]);
                files_nav(w, p);
            } else files_preview(w, f->names[f->sel]);
        }
    } else if (cp == 0x7f || cp == 0x08) {
        char p[512];
        snprintf(p, sizeof p, "%s", f->path);
        char *slash = strrchr(p, '/');
        if (slash && slash != p) { *slash = 0; files_nav(w, p); }
        else files_nav(w, "/");
    }
}

void files_draw(Canvas *c, Win *w, Rect r) {
    FilesState *f = w->files;
    if (!f) return;
    Font *fui = F_UI, *fsm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12);
    (void)fui;

    // sidebar
    int sw = 150;
    cv_fill(c, r.x, r.y, sw, r.h, RGB(12, 12, 15));
    cv_fill(c, r.x + sw, r.y, 1, r.h, C_LINE);
    const char *places[5] = {"Home", "Documents", "Downloads", "Pictures", "Root"};
    const char *paths[5] = {home_dir(), "/root/Documents", "/root/Downloads", "/root/Pictures", "/"};
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12);
    text_draw(c, fb, r.x + 14, r.y + 26, "PLACES", C_DIM2);
    for (int i = 0; i < 5; i++) {
        int py = r.y + 40 + i * 30;
        bool here = strcmp(f->path, paths[i]) == 0;
        if (here) cv_rrect(c, r.x + 8, py, sw - 16, 26, 7, col(10, 132, 255, 50));
        icon_draw(c, 1, r.x + 16, py + 5, 16, here ? RGB(120, 180, 255) : C_DIM);
        text_draw(c, fsm, r.x + 38, py + 18, places[i], here ? RGB(255, 255, 255) : C_DIM);
    }

    // top bar
    int bx = r.x + sw + 1;
    cv_fill(c, bx, r.y, r.w - sw - 1, 44, RGB(10, 10, 13));
    cv_fill(c, bx, r.y + 44, r.w - sw - 1, 1, C_LINE);
    cv_rrect(c, bx + 10, r.y + 10, 26, 24, 7, col(255, 255, 255, 18));
    icon_draw(c, 12, bx + 15, r.y + 16, 16, C_TEXT);
    text_elide(c, fsm, bx + 46, r.y + 0, r.w - sw - 60, r.y + 28, f->path, RGB(210, 212, 220));
    Font *cnt = fsm;
    char cb[48];
    snprintf(cb, sizeof cb, "%d items", f->nent);
    text_right(c, cnt, r.x + r.w - 14, r.y + 28, cb, C_DIM2);

    // list
    int listw = (int)((r.w - sw - 1) * 0.52f);
    int top = r.y + 46;
    int rowh = 28;
    int rows = (r.h - 46) / rowh;
    int maxscroll = f->nent - rows;
    if (maxscroll < 0) maxscroll = 0;
    if (f->scroll > maxscroll) f->scroll = maxscroll;
    for (int i = 0; i < rows; i++) {
        int idx = f->scroll + i;
        if (idx >= f->nent) break;
        int ry = top + i * rowh;
        if (f->sel == idx) cv_fill(c, bx, ry, listw, rowh, col(10, 132, 255, 45));
        icon_draw(c, f->isdir[idx] ? 14 : 15, bx + 12, ry + 6, 16,
                  f->isdir[idx] ? RGB(110, 170, 255) : C_DIM);
        text_elide(c, fsm, bx + 36, ry, listw - 46, ry + 19, f->names[idx],
                   f->isdir[idx] ? RGB(230, 233, 240) : C_DIM);
    }
    // scrollbar
    if (f->nent > rows && rows > 0) {
        int trackh = r.h - 46 - 12;
        int barh = trackh * rows / f->nent;
        if (barh < 24) barh = 24;
        int bary = top + 6 + (trackh - barh) * f->scroll / (f->nent - rows ? f->nent - rows : 1);
        cv_rrect(c, bx + listw - 6, bary, 3, barh, 1, col(255, 255, 255, 50));
    }

    // preview
    int px = bx + listw;
    cv_fill(c, px, r.y + 46, 1, r.h - 46, C_LINE);
    if (f->pvname[0]) {
        Font *pb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12);
        text_elide(c, pb, px + 14, r.y + 46, r.x + r.w - px - 28, r.y + 72, f->pvname, C_TEXT);
        // params + line scroll
        Font *mono = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 11);
        int lh = font_height(mono) + 2;
        int lines = (r.h - 90) / lh;
        int line = 0;
        int y = r.y + 84;
        const char *s = f->preview;
        while (*s && line < lines) {
            const char *nl = strchr(s, '\n');
            int len = nl ? (int)(nl - s) : (int)strlen(s);
            if (len > 0) {
                char buf[512];
                int k = len > 500 ? 500 : len;
                memcpy(buf, s, k);
                buf[k] = 0;
                text_elide(c, mono, px + 14, y + line * lh, r.x + r.w - px - 28, y + line * lh, buf, RGB(200, 204, 212));
            }
            line++;
            if (!nl) break;
            s = nl + 1;
        }
    } else {
        Font *ph = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12);
        text_center(c, ph, px + (r.x + r.w - px) / 2, r.y + r.h / 2,
                    "select a file to preview", C_DIM2);
    }
}

// ---------------------------------------------------------------- notes
void notes_open(Win *w) {
    NotesState *n = calloc(1, sizeof(NotesState));
    w->notes = n;
    char p[600];
    fs_join(p, sizeof p, home_dir(), "Documents/notes.txt");
    int r = fs_read(p, n->buf, sizeof n->buf - 1);
    if (r < 0) {
        snprintf(n->buf, sizeof n->buf, "DevOS notes\n\n- ye asli file hai: ~/Documents/notes.txt\n- Ctrl+S se save hota hai\n");
        r = (int)strlen(n->buf);
    }
    n->len = r;
    n->cur = r;
    n->loaded = true;
}

void notes_save(Win *w) {
    NotesState *n = w->notes;
    if (!n) return;
    char p[600], dir[600];
    fs_join(dir, sizeof dir, home_dir(), "Documents");
    mkdir(dir, 0755);
    fs_join(p, sizeof p, home_dir(), "Documents/notes.txt");
    if (fs_write(p, n->buf, n->len)) { n->dirty = false; }
}

void notes_key(Win *w, uint32_t cp, const char *utf8) {
    NotesState *n = w->notes;
    if (!n) return;
    if (cp == 0x7f || cp == 0x08) {
        if (n->cur > 0) {
            memmove(n->buf + n->cur - 1, n->buf + n->cur, n->len - n->cur);
            n->cur--; n->len--; n->dirty = true;
        }
        return;
    }
    if (cp == '\r' || cp == '\n') {
        if (n->len < (int)sizeof(n->buf) - 2) {
            memmove(n->buf + n->cur + 1, n->buf + n->cur, n->len - n->cur);
            n->buf[n->cur++] = '\n';
            n->len++;
            n->dirty = true;
        }
        return;
    }
    if (cp == 0x100) { if (n->cur > 0) n->cur--; return; }      // up (approx)
    if (cp == 0x101) { if (n->cur < n->len) n->cur++; return; } // down
    if (cp == 0x102) { if (n->cur < n->len) n->cur++; return; } // right
    if (cp == 0x103) { if (n->cur > 0) n->cur--; return; }      // left
    if (utf8 && utf8[0] && (unsigned char)utf8[0] >= 32) {
        int ul = (int)strlen(utf8);
        if (n->len + ul < (int)sizeof(n->buf) - 2) {
            memmove(n->buf + n->cur + ul, n->buf + n->cur, n->len - n->cur);
            memcpy(n->buf + n->cur, utf8, ul);
            n->cur += ul; n->len += ul; n->dirty = true;
        }
    }
}

void notes_click(Win *w, int x, int y) {
    NotesState *n = w->notes;
    if (!n) return;
    // line-based approx cursor
    int lh = 20;
    int line = (y - 12) / lh;
    if (line < 0) line = 0;
    int cnt = 0, pos = 0;
    while (pos < n->len && cnt < line) {
        if (n->buf[pos] == '\n') cnt++;
        pos++;
    }
    n->cur = pos;
    (void)x;
}

void notes_draw(Canvas *c, Win *w, Rect r) {
    NotesState *n = w->notes;
    if (!n) return;
    Font *mono = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf", 13);
    Font *sm = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10);
    int lh = 20;
    int maxcols = (r.w - 32) / text_w(mono, "M");

    // line numbers gutter
    cv_fill(c, r.x, r.y, 40, r.h, RGB(10, 10, 13));
    cv_fill(c, r.x + 40, r.y, 1, r.h, col(255, 255, 255, 16));

    int y = r.y + 18;
    int line = 1, pos = 0;
    int cx = -1, cy = -1;
    char linebuf[512];

    while (pos <= n->len) {
        int start = pos;
        while (pos < n->len && n->buf[pos] != '\n') pos++;
        int len = pos - start;
        if (len > (int)sizeof(linebuf) - 1) len = (int)sizeof(linebuf) - 1;
        memcpy(linebuf, n->buf + start, len);
        linebuf[len] = 0;
        if (n->cur >= start && n->cur <= start + len) {
            cx = r.x + 56 + text_w_n(mono, linebuf, (int)(n->cur - start));
            cy = y;
        }
        char num[8];
        snprintf(num, sizeof num, "%d", line);
        text_right(c, sm, r.x + 30, y + 6, num, C_MUTED);
        text_draw(c, mono, r.x + 56, y + 12, linebuf, RGB(220, 224, 232));
        line++;
        y += lh;
        if (y > r.y + r.h - 8) { /* next lines clipped */ }
        if (pos >= n->len) break;
        pos++;
    }
    (void)maxcols;
    if (cx >= 0 && cy >= 0 && fmod((double)mono_ms() / 1000.0, 1.0) < 0.6)
        cv_fill(c, cx, cy, 2, 16, RGB(10, 132, 255));
    // status
    char st[64];
    snprintf(st, sizeof st, "%d chars · %s", n->len, n->dirty ? "unsaved" : "saved");
    text_right(c, sm, r.x + r.w - 12, r.y + 14, st, n->dirty ? RGB(255, 190, 80) : C_MUTED);
}

// ---------------------------------------------------------------- monitor
static void bar(Canvas *c, int x, int y, int w, int h, float f, Col colr) {
    cv_rrect(c, x, y, w, h, h / 2, RGB(34, 34, 40));
    int fw = (int)(w * (f < 0 ? 0 : f > 1 ? 1 : f));
    if (fw > 2) cv_rrect(c, x, y, fw, h, h / 2, colr);
}

static void monitor_draw(Canvas *c, Win *w, Rect r) {
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12);
    Font *fs = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11);
    char b[128], b2[64];

    // header
    text_draw(c, fb, r.x + 16, r.y + 24, "SYSTEM MONITOR", C_DIM2);
    char up[32];

    int cardw = (r.w - 48) / 2;
    int cardh = 92;
    int x0 = r.x + 16, y0 = r.y + 38;

    // CPU
    cv_rrect(c, x0, y0, cardw, cardh, 10, C_CARD);
    text_draw(c, fb, x0 + 14, y0 + 22, "Processor", C_TEXT);
    OS *o = g_os;
    SysInfo *sy = &o->sys;
    text_elide(c, fs, x0 + 14, y0 + 40, cardw - 26, y0 + 40, sy->cpu, C_DIM2);
    snprintf(b, sizeof b, "load %.2f", sy->load1);
    text_draw(c, fs, x0 + 14, y0 + 60, b, RGB(180, 210, 255));
    int ncpu = (int)sysconf(_SC_NPROCESSORS_ONLN);
    bar(c, x0 + 14, y0 + 70, cardw - 28, 6, (float)(sy->load1 / (ncpu > 0 ? ncpu : 1)), RGB(10, 132, 255));

    // Memory
    cv_rrect(c, x0 + cardw + 16, y0, cardw, cardh, 10, C_CARD);
    text_draw(c, fb, x0 + cardw + 30, y0 + 22, "Memory", C_TEXT);
    unsigned long used = sy->memTotalKb > sy->memAvailKb ? sy->memTotalKb - sy->memAvailKb : 0;
    human_kb(b, sizeof b, used);
    human_kb(b2, sizeof b2, sy->memTotalKb);
    snprintf(b + strlen(b), sizeof b - strlen(b), " / %s", b2);
    text_draw(c, fs, x0 + cardw + 30, y0 + 42, b, C_DIM);
    bar(c, x0 + cardw + 30, y0 + 54, cardw - 32, 6,
        sy->memTotalKb ? (float)used / sy->memTotalKb : 0, RGB(48, 209, 88));

    // Disk
    int y1 = y0 + cardh + 16;
    cv_rrect(c, x0, y1, cardw, cardh, 10, C_CARD);
    text_draw(c, fb, x0 + 14, y1 + 22, "Storage (/ )", C_TEXT);
    unsigned long du = sy->diskTotalKb - sy->diskFreeKb;
    human_kb(b, sizeof b, du);
    human_kb(b2, sizeof b2, sy->diskTotalKb);
    snprintf(b + strlen(b), sizeof b - strlen(b), " used of %s", b2);
    text_draw(c, fs, x0 + 14, y1 + 44, b, C_DIM);
    bar(c, x0 + 14, y1 + 58, cardw - 28, 6,
        sy->diskTotalKb ? (float)du / sy->diskTotalKb : 0, RGB(255, 159, 10));

    // Uptime / kernel
    cv_rrect(c, x0 + cardw + 16, y1, cardw, cardh, 10, C_CARD);
    text_draw(c, fb, x0 + cardw + 30, y1 + 22, "System", C_TEXT);
    sys_uptime_str(sy, up, sizeof up);
    snprintf(b, sizeof b, "up %s", up);
    text_draw(c, fs, x0 + cardw + 30, y1 + 42, b, C_DIM);
    snprintf(b, sizeof b, "kernel %s", sy->kernel);
    text_elide(c, fs, x0 + cardw + 30, y1 + 60, cardw - 40, y1 + 60, b, C_DIM2);
    snprintf(b, sizeof b, "%d packages installed", sy->pkgs);
    text_draw(c, fs, x0 + cardw + 30, y1 + 78, b, RGB(150, 200, 150));

    text_draw(c, fs, r.x + 16, r.y + r.h - 12,
              "live values from /proc · refresh every 2s", C_MUTED);
}

// ---------------------------------------------------------------- settings
static void settings_draw(Canvas *c, Win *w, Rect r) {
    (void)w;
    OS *o = g_os;
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 12);
    Font *fs = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11);
    text_draw(c, fb, r.x + 18, r.y + 26, "SETTINGS", C_DIM2);

    int y = r.y + 52;
    const char *names[2] = {"Brightness", "Volume"};
    int vals[2] = { o->sys.brightOk ? o->sys.bright : 0, o->sys.volOk ? o->sys.vol : 0 };
    bool ok[2] = { o->sys.brightOk != 0, o->sys.volOk != 0 };
    for (int i = 0; i < 2; i++) {
        cv_rrect(c, r.x + 16, y, r.w - 32, 66, 12, C_CARD);
        icon_draw(c, i == 0 ? 10 : 9, r.x + 30, y + 12, 18, ok[i] ? C_TEXT : C_MUTED);
        text_draw(c, fb, r.x + 58, y + 26, names[i], C_TEXT);
        char vb[16]; snprintf(vb, sizeof vb, "%d%%", vals[i]);
        text_right(c, fs, r.x + r.w - 30, y + 26, ok[i] ? vb : "unavailable",
                   ok[i] ? C_DIM : C_MUTED);
        int tx = r.x + 30, tw = r.w - 60;
        cv_rrect(c, tx, y + 42, tw, 6, 3, RGB(38, 38, 43));
        int fw = tw * vals[i] / 100;
        if (fw > 2) cv_rrect(c, tx, y + 42, fw, 6, 3, ok[i] ? C_ACC : RGB(58, 58, 64));
        cv_circle(c, tx + (fw < 7 ? 7 : fw > tw - 7 ? tw - 7 : fw), y + 45, 7,
                  ok[i] ? RGB(255, 255, 255) : RGB(90, 90, 95));
        y += 82;
    }
    // ---- wallpaper (R6): system + user PNGs, click se live apply ----
    text_draw(c, fb, r.x + 18, y + 14, "WALLPAPER", C_DIM2);
    char mb[32];
    snprintf(mb, sizeof mb, "%s", wp_mode_name(o->wp.mode));
    int mw = S(o, 104), mh = S(o, 24);
    int mbx = r.x + r.w - 18 - mw, mby = y + 1;
    cv_rrect(c, mbx, mby, mw, mh, mh / 2, RGB(30, 30, 38));
    text_center(c, fs, mbx + mw / 2, mby + mh / 2 + 4, mb, C_DIM);

    char paths[16][512];
    int n = wp_scan(paths, 16);
    if (n > 6) n = 6;   // do rows x teen columns
    int gy = y + 32;
    int gap = S(o, 10);
    int tw = (r.w - 32 - 2 * gap) / 3;
    int th = tw * WP_THUMB_H / WP_THUMB_W;
    if (n == 0)
        text_draw(c, fs, r.x + 18, gy + 18,
                  "koi wallpaper nahi mila — PNG ~/Pictures/wallpapers me rakho", C_MUTED);
    for (int i = 0; i < n; i++) {
        int tx = r.x + 16 + (i % 3) * (tw + gap);
        int ty = gy + (i / 3) * (th + gap);
        uint32_t *tp = NULL;
        if (wp_thumb(paths[i], &tp) && tp) {
            cv_image(c, tx, ty, tw, th, tp, WP_THUMB_W, WP_THUMB_H);
        } else {
            cv_rrect(c, tx, ty, tw, th, 10, RGB(22, 22, 28));
            text_center(c, fs, tx + tw / 2, ty + th / 2 + 4, "?", C_MUTED);
        }
        bool sel = !strcmp(paths[i], o->wp.path);
        cv_rrect_border(c, tx, ty, tw, th, 10, sel ? 2 : 1,
                        sel ? RGB(10, 132, 255) : RGB(44, 44, 52));
    }
}

// ---------------------------------------------------------------- about
static void about_draw(Canvas *c, Win *w, Rect r) {
    (void)w;
    OS *o = g_os;
    int cx = r.x + r.w / 2;
    int y = r.y + 34;
    cv_rrect(c, cx - 34, y, 68, 68, 18, RGB(16, 30, 52));
    cv_rrect_border(c, cx - 34, y, 68, 68, 18, 1, C_ACC);
    Font *big = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 30);
    text_center(c, big, cx, y + 47, "D", C_ACC);
    Font *t = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 20);
    text_center(c, t, cx, y + 100, "DevOS", RGB(255, 255, 255));
    Font *s = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12);
    text_center(c, s, cx, y + 122, "2.0 “Whale”  ·  our own compositor, no Qt, no third-party shell",
                C_DIM);
    char b[160];
    snprintf(b, sizeof b, "kernel %s", o->sys.kernel);
    text_center(c, s, cx, y + 148, b, C_DIM2);
    char up[32];
    snprintf(b, sizeof b, "up %s  ·  display %dx%d  ·  scale %.2f",
             sys_uptime_str(&o->sys, up, sizeof up), o->W, o->H, (double)o->scale);
    text_center(c, s, cx, y + 168, b, C_DIM2);
    text_center(c, s, cx, y + 194, "terminal · files · notes · monitor · dock · notch",
                RGB(120, 160, 210));
    Font *fine = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 10);
    text_center(c, fine, cx, r.y + r.h - 26,
                "built from scratch in C — libdrm + FreeType only. Linux underneath.",
                C_MUTED);
}

// ---------------------------------------------------------------- store / setup
static void store_draw(Canvas *c, Win *w, Rect r) {
    (void)w;
    OS *o = g_os;
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13);
    Font *fs = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 12);
    cv_rrect(c, r.x + 24, r.y + 28, r.w - 48, 96, 14, RGB(28, 22, 40));
    cv_rrect_border(c, r.x + 24, r.y + 28, r.w - 48, 96, 14, 1, RGB(150, 80, 240));
    text_draw(c, fb, r.x + 44, r.y + 62, "App Store", RGB(220, 200, 255));
    text_draw(c, fs, r.x + 44, r.y + 88, "repositories not enabled in 2.0 — honest, not fake", C_DIM);
    char b[128];
    snprintf(b, sizeof b, "%d packages already installed from base", o->sys.pkgs);
    text_draw(c, fs, r.x + 44, r.y + 110, b, C_DIM2);
    Font *ft = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11);
    text_draw(c, ft, r.x + 24, r.y + r.h - 20,
              "apt still works from the terminal. GUI store comes with the installer milestone.", C_MUTED);
}

static void setup_draw(Canvas *c, Win *w, Rect r) {
    (void)w;
    OS *o = g_os;
    Font *fb = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 13);
    Font *fs = font_load("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11);
    text_draw(c, fb, r.x + 24, r.y + 32, "DevOS Setup", C_TEXT);
    text_draw(c, fs, r.x + 24, r.y + 54, "detected on this machine:", C_DIM2);
    int y = r.y + 74;
    char b[180];
    const char *labels[6] = {"Hostname", "Kernel", "Processor", "Display", "Network", "Storage"};
    snprintf(b, sizeof b, "%s", o->sys.host);      text_draw(c, fs, r.x + 24, y, labels[0], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 30;
    snprintf(b, sizeof b, "%s", o->sys.kernel);    text_draw(c, fs, r.x + 24, y, labels[1], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 30;
    snprintf(b, sizeof b, "%s", o->sys.cpu);       text_draw(c, fs, r.x + 24, y, labels[2], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 30;
    snprintf(b, sizeof b, "%dx%d", o->W, o->H);    text_draw(c, fs, r.x + 24, y, labels[3], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 30;
    snprintf(b, sizeof b, "%s", o->sys.net[0] ? o->sys.net : "offline");
                                                    text_draw(c, fs, r.x + 24, y, labels[4], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 30;
    char hk[32], hk2[32];
    human_kb(hk, sizeof hk, o->sys.diskTotalKb);
    human_kb(hk2, sizeof hk2, o->sys.diskTotalKb - o->sys.diskFreeKb);
    snprintf(b, sizeof b, "%s total, %s used", hk, hk2);
                                                    text_draw(c, fs, r.x + 24, y, labels[5], C_DIM); text_elide(c, fs, r.x + 130, y, r.w - 160, y, b, C_TEXT); y += 34;

    cv_rrect(c, r.x + 24, y, r.w - 48, 78, 12, RGB(30, 24, 12));
    cv_rrect_border(c, r.x + 24, y, r.w - 48, 78, 12, 1, RGB(140, 100, 30));
    text_draw(c, fb, r.x + 42, y + 26, "Live mode", RGB(255, 200, 120));
    text_draw(c, fs, r.x + 42, y + 48,
              "no disk changes are made. The installer (disk, user, locale) ships next.", RGB(215, 190, 150));
    text_draw(c, fs, r.x + 42, y + 66,
              "Until then: everything runs from RAM + squashfs.", RGB(170, 150, 120));
}

// ---------------------------------------------------------------- dispatch
void app_size(OS *o, AppKind k, int *w, int *h) {
    switch (k) {
    case APP_TERM: *w = S(o, 760); *h = S(o, 460); break;
    case APP_FILES: *w = S(o, 820); *h = S(o, 520); break;
    case APP_NOTES: *w = S(o, 680); *h = S(o, 480); break;
    case APP_MONITOR: *w = S(o, 620); *h = S(o, 420); break;
    case APP_SETTINGS: *w = S(o, 560); *h = S(o, 520); break;
    case APP_ABOUT: *w = S(o, 480); *h = S(o, 330); break;
    case APP_STORE: *w = S(o, 560); *h = S(o, 300); break;
    case APP_SETUP: *w = S(o, 560); *h = S(o, 400); break;
    case APP_INSTALL: *w = S(o, 860); *h = S(o, 560); break;
    default: *w = S(o, 600); *h = S(o, 400); break;
    }
    if (*w > o->W - S(o, 40)) *w = o->W - S(o, 40);
    if (*h > o->H - S(o, 140)) *h = o->H - S(o, 140);
}

void app_open(OS *o, Win *w) {
    switch (w->kind) {
    case APP_TERM: case APP_INSTALL: term_open(w); break;
    case APP_FILES: files_open(w); break;
    case APP_NOTES: notes_open(w); break;
    default: break;
    }
    app_title(w);
    (void)o;
}

void app_close(Win *w) {
    if (w->term) {
        if (w->term->master >= 0) close(w->term->master);
        if (w->term->pid > 0) kill(w->term->pid, SIGHUP);
        free(w->term->grid);
        free(w->term);
        w->term = NULL;
    }
    if (w->files) { free(w->files); w->files = NULL; }
    if (w->notes) { free(w->notes); w->notes = NULL; }
}

void app_title(Win *w) {
    if (w->kind == APP_FILES && w->files && w->files->path[0]) {
        const char *slash = strrchr(w->files->path, '/');
        snprintf(w->title, sizeof w->title, "Files — %s",
                 slash && slash[1] ? slash + 1 : "Root");
        return;
    }
    const char *names[APP_KIND_COUNT] = {"Terminal", "Files", "Notes", "Monitor",
                                         "Settings", "About DevOS", "Store", "DevOS Setup"};
    snprintf(w->title, sizeof w->title, "%s", names[w->kind]);
}

void app_draw(OS *o, Canvas *c, Win *w) {
    Rect r = win_client(w);
    switch (w->kind) {
    case APP_TERM: case APP_INSTALL: term_draw(c, w->term, r); break;
    case APP_FILES: files_draw(c, w, r); break;
    case APP_NOTES: notes_draw(c, w, r); break;
    case APP_MONITOR: monitor_draw(c, w, r); break;
    case APP_SETTINGS: settings_draw(c, w, r); break;
    case APP_ABOUT: about_draw(c, w, r); break;
    case APP_STORE: store_draw(c, w, r); break;
    case APP_SETUP: setup_draw(c, w, r); break;
    default: break;
    }
    (void)o;
}

void app_mouse(OS *o, Win *w, int lx, int ly, int button, int down, int wheel) {
    (void)button;
    if (w->kind == APP_FILES) {
        if (down) files_click(w, lx, ly);
        else if (wheel) {
            w->files->scroll += wheel > 0 ? 2 : -2;
            if (w->files->scroll < 0) w->files->scroll = 0;
        }
    } else if (w->kind == APP_NOTES) {
        if (down) notes_click(w, lx, ly);
    } else if (w->kind == APP_SETTINGS) {
        if (down) {
            if (lx > 16 && lx < w->w - 32) {
                int y0 = 52, y1 = 134;
                if (ly >= y0 && ly < y0 + 66) {
                    int pct = (lx - 30) * 100 / (w->w - 60);
                    if (pct < 0) pct = 0;
                    if (pct > 100) pct = 100;
                    o->sys.bright = pct; o->sys.brightOk = o->sys.brightOk ? 1 : 1;
                    sys_set_bright(pct);
                } else if (ly >= y1 && ly < y1 + 66) {
                    int pct = (lx - 30) * 100 / (w->w - 60);
                    if (pct < 0) pct = 0;
                    if (pct > 100) pct = 100;
                    o->sys.vol = pct; o->sys.volOk = o->sys.volOk ? 1 : 1;
                    sys_set_vol(pct);
                }
            }
            // ---- wallpaper section (settings_draw ke layout se match) ----
            Rect cl = win_client(w);
            int ax = cl.x + lx, ay = cl.y + ly;
            int wy = cl.y + 216;
            int mw = S(o, 104), mh = S(o, 24);
            int mbx = cl.x + cl.w - 18 - mw, mby = wy + 1;
            if (ax >= mbx && ax < mbx + mw && ay >= mby && ay < mby + mh) {
                static const int modes[5] = {WP_COVER, WP_FIT, WP_STRETCH, WP_CENTER, WP_TILE};
                int cur = 0;
                for (int i = 0; i < 5; i++) if (modes[i] == o->wp.mode) cur = i;
                int nm = modes[(cur + 1) % 5];
                if (o->wp.path[0]) wp_apply(o, o->wp.path, nm);
                else o->wp.mode = nm;
            } else {
                char paths[16][512];
                int n = wp_scan(paths, 16);
                if (n > 6) n = 6;
                int gy = wy + 32;
                int gap = S(o, 10);
                int tw = (cl.w - 32 - 2 * gap) / 3;
                int th = tw * WP_THUMB_H / WP_THUMB_W;
                if (ax >= cl.x + 16 && ay >= gy) {
                    int col = (ax - (cl.x + 16)) / (tw + gap);
                    int row = (ay - gy) / (th + gap);
                    if (col >= 0 && col < 3 && row >= 0 && row < 2) {
                        int idx = row * 3 + col;
                        if (idx < n) wp_apply(o, paths[idx], o->wp.mode);
                    }
                }
            }
        }
    }
}

void app_key(OS *o, Win *w, uint32_t cp, const char *utf8, int mods) {
    (void)o;
    switch (w->kind) {
    case APP_TERM: case APP_INSTALL: term_key(w->term, cp, utf8, mods); break;
    case APP_FILES: files_key(w, cp); break;
    case APP_NOTES:
        if ((mods & 4) && (cp == 's' || cp == 'S')) { notes_save(w); }
        else notes_key(w, cp, utf8);
        break;
    default: break;
    }
}

void app_tick(OS *o, Win *w) {
    if ((w->kind == APP_TERM || w->kind == APP_INSTALL) && w->term) {
        term_read(w->term);
    }
    (void)o;
}