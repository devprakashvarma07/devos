// draw.c — DevOS ka apna 2D rasteriser: fills, AA rounded rects, gradients,
// lines, shadows, aur FreeType se text. Koi pixman/cairo nahi.
#include "devo.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ft2build.h>
#include FT_FREETYPE_H

// ---------------------------------------------------------------- basics
void cv_init(Canvas *c, uint32_t *px, int w, int h, int stride) {
    c->px = px; c->w = w; c->h = h; c->stride = stride;
}

// XRGB8888: memory bytes B,G,R,X — DRM ka standard 32bpp format
static inline uint32_t pack(Col c) {
    return (uint32_t)c.b | ((uint32_t)c.g << 8) | ((uint32_t)c.r << 16);
}

void cv_blend_px(uint32_t *p, Col c, int a) {
    if (a <= 0) return;
    if (a >= 255) { *p = pack(c); return; }
    uint32_t d = *p;
    int ia = 255 - a;
    int b = (c.b * a + (int)(d & 255) * ia) / 255;
    int g = (c.g * a + (int)((d >> 8) & 255) * ia) / 255;
    int r = (c.r * a + (int)((d >> 16) & 255) * ia) / 255;
    *p = (uint32_t)b | ((uint32_t)g << 8) | ((uint32_t)r << 16);
}
static inline void blend_px(uint32_t *p, Col c, int a) { cv_blend_px(p, c, a); }

static inline void blend_span(uint32_t *p, int n, Col c, int a) {
    if (a <= 0 || n <= 0) return;
    if (a >= 255) {
        uint32_t v = pack(c);
        for (int i = 0; i < n; i++) p[i] = v;
        return;
    }
    int ia = 255 - a;
    int cr = c.r * a, cg = c.g * a, cb = c.b * a;
    for (int i = 0; i < n; i++) {
        uint32_t d = p[i];
        int b = (cb + (int)(d & 255) * ia) / 255;
        int g = (cg + (int)((d >> 8) & 255) * ia) / 255;
        int r = (cr + (int)((d >> 16) & 255) * ia) / 255;
        p[i] = (uint32_t)b | ((uint32_t)g << 8) | ((uint32_t)r << 16);
    }
}

void cv_clear(Canvas *c, Col col) {
    cv_fill(c, 0, 0, c->w, c->h, col);
}

void cv_fill(Canvas *c, int x, int y, int w, int h, Col col) {
    if (w <= 0 || h <= 0 || col.a == 0) return;
    int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
    int x1 = x + w > c->w ? c->w : x + w, y1 = y + h > c->h ? c->h : y + h;
    if (x0 >= x1 || y0 >= y1) return;
    for (int yy = y0; yy < y1; yy++)
        blend_span(c->px + (size_t)yy * c->stride + x0, x1 - x0, col, col.a);
}

void cv_vgrad(Canvas *c, int x, int y, int w, int h, Col top, Col bot) {
    if (w <= 0 || h <= 0) return;
    int x0 = x < 0 ? 0 : x, y0 = y < 0 ? 0 : y;
    int x1 = x + w > c->w ? c->w : x + w, y1 = y + h > c->h ? c->h : y + h;
    for (int yy = y0; yy < y1; yy++) {
        float f = h > 1 ? (float)(yy - y) / (h - 1) : 0.f;
        Col cc = col((int)(top.r + (bot.r - top.r) * f),
                     (int)(top.g + (bot.g - top.g) * f),
                     (int)(top.b + (bot.b - top.b) * f), 255);
        blend_span(c->px + (size_t)yy * c->stride + x0, x1 - x0, cc, 255);
    }
}

void cv_rgrad(Canvas *c, int cx, int cy, int r, Col inner, Col outer) {
    // concentric rings — wallpaper ke glows ke liye (cached, ek baar)
    int steps = 72;
    for (int i = steps; i >= 0; i--) {
        float f = (float)i / steps;
        float rr = r * f;
        Col cc = col((int)(inner.r + (outer.r - inner.r) * f),
                     (int)(inner.g + (outer.g - inner.g) * f),
                     (int)(inner.b + (outer.b - inner.b) * f),
                     (int)(inner.a * (1.f - f) * (1.f - f)));
        cv_circle(c, cx, cy, rr, cc);
    }
}

// AA rounded rect — span-optimised (interior ek hi baar bhar jata hai)
void cv_rrect_ex(Canvas *c, int x, int y, int w, int h, float r, Col colf) {
    if (w <= 0 || h <= 0) return;
    float hw = w * 0.5f, hh = h * 0.5f;
    if (r > hw) r = hw;
    if (r > hh) r = hh;
    float cx = x + hw, cy = y + hh;
    int y0 = (int)floorf(y), y1 = (int)ceilf(y + h);
    if (y0 < 0) y0 = 0;
    if (y1 > c->h) y1 = c->h;
    int fullA = colf.a;
    if (r < 0.5f) { cv_fill(c, x, y, w, h, colf); return; }
    float rin = r - 0.5f;
    for (int yy = y0; yy < y1; yy++) {
        float py = yy + 0.5f;
        float qy = fabsf(py - cy) - (hh - r);
        if (qy < 0) qy = 0;
        int xL = (int)floorf(cx - hw + r), xR = (int)ceilf(cx + hw - r);
        if (xL < 0) xL = 0;
        if (xR > c->w) xR = c->w;
        uint32_t *row = c->px + (size_t)yy * c->stride;
        // middle span (sirf agar poori row ke andar ho)
        if (py >= y && py < y + h && xL < xR) {
            int a = 255;
            if (qy > 0.5f) {
                float d = qy - rin;          // d>0 => outside
                a = (int)((0.5f - d) * 255.f);
                if (a < 0) a = 0;
                if (a > 255) a = 255;
            }
            if (a > 0) blend_span(row + xL, xR - xL, colf, a * fullA / 255);
        }
        // left + right corners
        int xa = (int)floorf(cx - hw), xb = (int)ceilf(cx + hw);
        if (xa < 0) xa = 0;
        if (xb > c->w) xb = c->w;
        for (int xx = xa; xx < xL; xx++) {
            float px = xx + 0.5f;
            float qx = fabsf(px - cx) - (hw - r);
            if (qx < 0) qx = 0;
            float d = sqrtf(qx * qx + qy * qy) - rin;
            int a = (int)((0.5f - d) * 255.f);
            if (a <= 0) continue;
            if (a > 255) a = 255;
            blend_px(row + xx, colf, a * fullA / 255);
        }
        for (int xx = xR; xx < xb; xx++) {
            float px = xx + 0.5f;
            float qx = fabsf(px - cx) - (hw - r);
            if (qx < 0) qx = 0;
            float d = sqrtf(qx * qx + qy * qy) - rin;
            int a = (int)((0.5f - d) * 255.f);
            if (a <= 0) continue;
            if (a > 255) a = 255;
            blend_px(row + xx, colf, a * fullA / 255);
        }
    }
}

void cv_rrect(Canvas *c, int x, int y, int w, int h, int r, Col colv) {
    cv_rrect_ex(c, x, y, w, h, (float)r, colv);
}

void cv_rrect_border(Canvas *c, int x, int y, int w, int h, int r, int bw, Col colv) {
    if (w <= 0 || h <= 0) return;
    float hw = w * 0.5f, hh = h * 0.5f;
    if (r > hw) r = hw;
    if (r > hh) r = hh;
    float cx = x + hw, cy = y + hh;
    float rin = r - 0.5f;
    int y0 = y < 0 ? 0 : y, y1 = y + h > c->h ? c->h : y + h;
    int x0 = x < 0 ? 0 : x, x1 = x + w > c->w ? c->w : x + w;
    for (int yy = y0; yy < y1; yy++) {
        float py = yy + 0.5f;
        float qy = fabsf(py - cy) - (hh - r);
        if (qy < 0) qy = 0;
        uint32_t *row = c->px + (size_t)yy * c->stride;
        for (int xx = x0; xx < x1; xx++) {
            float px = xx + 0.5f;
            float qx = fabsf(px - cx) - (hw - r);
            if (qx < 0) qx = 0;
            float dout = sqrtf(qx * qx + qy * qy) - rin;
            float cov_out = 0.5f - dout;
            if (cov_out <= 0) continue;
            if (cov_out > 1) cov_out = 1;
            float ix = hw - bw, iy = hh - bw;
            float ir = r - bw;
            if (ir < 0) ir = 0;
            float qix = fabsf(px - cx) - (ix - ir);
            float qiy = fabsf(py - cy) - (iy - ir);
            if (qix < 0) qix = 0;
            if (qiy < 0) qiy = 0;
            float din = sqrtf(qix * qix + qiy * qiy) - (ir - 0.5f);
            float cov_in = 0.5f - din;
            if (cov_in > 1) cov_in = 1;
            if (cov_in < 0) cov_in = 0;
            float cov = cov_out - cov_in;
            if (cov <= 0) continue;
            blend_px(row + xx, colv, (int)(cov * 255.f) * colv.a / 255);
        }
    }
}

void cv_circle(Canvas *c, int cx, int cy, float r, Col colv) {
    if (r <= 0) return;
    int y0 = (int)floorf(cy - r - 1), y1 = (int)ceilf(cy + r + 1);
    int x0 = (int)floorf(cx - r - 1), x1 = (int)ceilf(cx + r + 1);
    if (y0 < 0) y0 = 0;
    if (x0 < 0) x0 = 0;
    if (y1 > c->h) y1 = c->h;
    if (x1 > c->w) x1 = c->w;
    float rr = r - 0.5f;
    for (int yy = y0; yy < y1; yy++) {
        float dy = yy + 0.5f - cy;
        uint32_t *row = c->px + (size_t)yy * c->stride;
        for (int xx = x0; xx < x1; xx++) {
            float dx = xx + 0.5f - cx;
            float d = sqrtf(dx * dx + dy * dy) - rr;
            int a = (int)((0.5f - d) * 255.f);
            if (a <= 0) continue;
            if (a > 255) a = 255;
            blend_px(row + xx, colv, a * colv.a / 255);
        }
    }
}

void cv_line(Canvas *c, float x0, float y0, float x1, float y1, float width, Col colv) {
    float hw = width * 0.5f;
    int bx0 = (int)floorf((x0 < x1 ? x0 : x1) - hw - 1);
    int by0 = (int)floorf((y0 < y1 ? y0 : y1) - hw - 1);
    int bx1 = (int)ceilf((x0 > x1 ? x0 : x1) + hw + 1);
    int by1 = (int)ceilf((y0 > y1 ? y0 : y1) + hw + 1);
    if (bx0 < 0) bx0 = 0;
    if (by0 < 0) by0 = 0;
    if (bx1 > c->w) bx1 = c->w;
    if (by1 > c->h) by1 = c->h;
    float dx = x1 - x0, dy = y1 - y0;
    float len2 = dx * dx + dy * dy;
    if (len2 < 0.0001f) { cv_circle(c, (int)x0, (int)y0, hw, colv); return; }
    for (int yy = by0; yy < by1; yy++) {
        uint32_t *row = c->px + (size_t)yy * c->stride;
        for (int xx = bx0; xx < bx1; xx++) {
            float px = xx + 0.5f - x0, py = yy + 0.5f - y0;
            float t = (px * dx + py * dy) / len2;
            if (t < 0) t = 0;
            if (t > 1) t = 1;
            float ex = px - dx * t, ey = py - dy * t;
            float d = sqrtf(ex * ex + ey * ey) - hw + 0.5f;
            int a = (int)((1.f - d) * 255.f);
            if (a <= 0) continue;
            if (a > 255) a = 255;
            blend_px(row + xx, colv, a * colv.a / 255);
        }
    }
}

void cv_shadow(Canvas *c, int x, int y, int w, int h, int r, int spread, Col colv) {
    for (int i = spread; i > 0; i--) {
        int a = colv.a * (spread - i + 1) / (spread * 3);
        Col cc = col(x, 0, 0, 0); (void)cc;
        cv_rrect(c, x - i, y - i + 2, w + i * 2, h + i * 2, r + i,
                 col(colv.r, colv.g, colv.b, a));
    }
}

void cv_blit(Canvas *dst, Canvas *src, int dx, int dy, int alpha) {
    for (int y = 0; y < src->h; y++) {
        int ty = dy + y;
        if (ty < 0 || ty >= dst->h) continue;
        for (int x = 0; x < src->w; x++) {
            int tx = dx + x;
            if (tx < 0 || tx >= dst->w) continue;
            uint32_t s = src->px[(size_t)y * src->stride + x];
            Col cc = col((s >> 16) & 255, (s >> 8) & 255, s & 255, 255);
            blend_px(dst->px + (size_t)ty * dst->stride + tx, cc, alpha);
        }
    }
}

// ---------------------------------------------------------------- images
// XRGB source ko (x,y,w,h) par nearest-neighbour scale karke blit karta hai.
// Wallpaper thumbnails isi se bante hain — koi external blitter nahi.
void cv_image(Canvas *c, int x, int y, int w, int h, const uint32_t *px, int iw, int ih) {
    if (!px || w <= 0 || h <= 0 || iw <= 0 || ih <= 0) return;
    for (int yy = 0; yy < h; yy++) {
        int ty = y + yy;
        if (ty < 0 || ty >= c->h) continue;
        int sy = (int)((long long)yy * ih / h);
        if (sy >= ih) sy = ih - 1;
        uint32_t *drow = c->px + (size_t)ty * c->stride;
        const uint32_t *srow = px + (size_t)sy * iw;
        for (int xx = 0; xx < w; xx++) {
            int tx = x + xx;
            if (tx < 0 || tx >= c->w) continue;
            int sx = (int)((long long)xx * iw / w);
            if (sx >= iw) sx = iw - 1;
            drow[tx] = srow[sx];
        }
    }
}

// ---------------------------------------------------------------- fonts
static FT_Library g_ft;
static int g_ft_ok = 0;

typedef struct Glyph Glyph;

struct Font {
    FT_Face face;
    int px, ascent, descent, height;
    Glyph *glyphs;
    int nglyph, capglyph;
    char path[256];
};

struct Glyph {
    FT_UInt idx;
    uint8_t *bmp;
    int w, h, pitch, left, top, adv;
};

#define MAX_FONTS 128
static Font *g_fonts[MAX_FONTS];
static int g_nfonts = 0;

Font *font_load(const char *path, int px) {
    for (int i = 0; i < g_nfonts; i++)
        if (g_fonts[i]->px == px && strcmp(g_fonts[i]->path, path) == 0) return g_fonts[i];
    if (!g_ft_ok) {
        if (FT_Init_FreeType(&g_ft)) return NULL;
        g_ft_ok = 1;
    }
    if (g_nfonts >= MAX_FONTS) return g_fonts[0];
    FT_Face face;
    if (FT_New_Face(g_ft, path, 0, &face)) {
        fprintf(stderr, "devos: font fail %s\n", path);
        return NULL;
    }
    FT_Set_Pixel_Sizes(face, 0, px);
    Font *f = calloc(1, sizeof(Font));
    f->face = face;
    f->px = px;
    f->ascent = (int)(face->size->metrics.ascender >> 6);
    f->descent = (int)(-face->size->metrics.descender >> 6);
    f->height = (int)(face->size->metrics.height >> 6);
    f->capglyph = 128;
    f->glyphs = calloc(f->capglyph, sizeof(Glyph));
    snprintf(f->path, sizeof f->path, "%s", path);
    g_fonts[g_nfonts++] = f;
    return f;
}

int font_ascent(Font *f) { return f->ascent; }
int font_descent(Font *f) { return f->descent; }
int font_height(Font *f) { return f->height; }

// UTF-8 decode — ek codepoint
static uint32_t u8_next(const char **pp) {
    const unsigned char *p = (const unsigned char *)*pp;
    uint32_t c = *p;
    if (!c) return 0;
    int n = 1;
    if (c >= 0xF0) { c &= 0x07; n = 4; }
    else if (c >= 0xE0) { c &= 0x0F; n = 3; }
    else if (c >= 0xC0) { c &= 0x1F; n = 2; }
    for (int i = 1; i < n; i++) {
        if ((p[i] & 0xC0) != 0x80) { *pp += i; return 0xFFFD; }
        c = (c << 6) | (p[i] & 0x3F);
    }
    *pp += n;
    return c;
}

static Glyph *glyph_get(Font *f, uint32_t cp) {
    if (f->nglyph >= f->capglyph) {
        f->capglyph *= 2;
        f->glyphs = realloc(f->glyphs, f->capglyph * sizeof(Glyph));
        memset(f->glyphs + f->nglyph, 0, (f->capglyph - f->nglyph) * sizeof(Glyph));
    }
    for (int i = 0; i < f->nglyph; i++)
        if (f->glyphs[i].idx == cp) return &f->glyphs[i];
    FT_UInt gi = FT_Get_Char_Index(f->face, cp);
    Glyph *g = &f->glyphs[f->nglyph];
    g->idx = cp;
    if (FT_Load_Glyph(f->face, gi, FT_LOAD_RENDER | FT_LOAD_TARGET_NORMAL)) {
        g->w = g->h = 0;
        f->nglyph++;
        return g;
    }
    FT_GlyphSlot s = f->face->glyph;
    g->w = (int)s->bitmap.width;
    g->h = (int)s->bitmap.rows;
    g->pitch = g->w;
    g->left = s->bitmap_left;
    g->top = s->bitmap_top;
    g->adv = (int)(s->advance.x >> 6);
    if (g->w > 0 && g->h > 0) {
        g->bmp = malloc((size_t)g->w * g->h);
        for (int y = 0; y < g->h; y++)
            memcpy(g->bmp + y * g->w,
                   s->bitmap.buffer + y * s->bitmap.pitch, g->w);
    }
    f->nglyph++;
    return g;
}

static int glyph_draw(Canvas *c, Font *f, int x, int baseline, uint32_t cp, Col colv) {
    Glyph *g = glyph_get(f, cp);
    int ox = x + g->left, oy = baseline - g->top;
    int alpha = colv.a;
    if (g->bmp) {
        for (int yy = 0; yy < g->h; yy++) {
            int ty = oy + yy;
            if (ty < 0 || ty >= c->h) continue;
            uint32_t *row = c->px + (size_t)ty * c->stride;
            const uint8_t *src = g->bmp + yy * g->pitch;
            for (int xx = 0; xx < g->w; xx++) {
                int tx = ox + xx;
                if (tx < 0 || tx >= c->w) continue;
                int a = src[xx] * alpha / 255;
                if (a) blend_px(row + tx, colv, a);
            }
        }
    }
    return g->adv;
}

int text_w_n(Font *f, const char *s, int n) {
    int w = 0;
    const char *p = s, *end = s + n;
    while (p < end && *p) {
        uint32_t cp = u8_next(&p);
        if (!cp) break;
        Glyph *g = glyph_get(f, cp);
        w += g->adv;
    }
    return w;
}

int text_w(Font *f, const char *s) { return text_w_n(f, s, (int)strlen(s)); }

int text_draw(Canvas *c, Font *f, int x, int baseline, const char *s, Col colv) {
    int cx = x;
    const char *p = s;
    while (*p) {
        uint32_t cp = u8_next(&p);
        if (!cp) break;
        cx += glyph_draw(c, f, cx, baseline, cp, colv);
    }
    return cx - x;
}

int text_draw_tracked(Canvas *c, Font *f, int x, int baseline, const char *s, int track, Col colv) {
    int cx = x;
    const char *p = s;
    while (*p) {
        uint32_t cp = u8_next(&p);
        if (!cp) break;
        cx += glyph_draw(c, f, cx, baseline, cp, colv) + track;
    }
    return cx - x;
}

void text_center(Canvas *c, Font *f, int cx, int baseline, const char *s, Col colv) {
    text_draw(c, f, cx - text_w(f, s) / 2, baseline, s, colv);
}

void text_right(Canvas *c, Font *f, int rx, int baseline, const char *s, Col colv) {
    text_draw(c, f, rx - text_w(f, s), baseline, s, colv);
}

int text_fit(Font *f, const char *s, int maxw) {
    int w = 0, i = 0;
    const char *p = s;
    while (*p) {
        const char *q = p;
        uint32_t cp = u8_next(&q);
        Glyph *g = glyph_get(f, cp);
        if (w + g->adv > maxw) break;
        w += g->adv;
        i += (int)(q - p);
        p = q;
    }
    return i;
}

void text_elide(Canvas *c, Font *f, int x, int y, int w, int baseline, const char *s, Col colv) {
    if (text_w(f, s) <= w) { text_draw(c, f, x, baseline, s, colv); return; }
    int n = text_fit(f, s, w - text_w(f, "…"));
    char buf[512];
    if (n > (int)sizeof(buf) - 4) n = (int)sizeof(buf) - 4;
    memcpy(buf, s, n);
    buf[n] = 0;
    strcat(buf, "…");
    text_draw(c, f, x, baseline, buf, colv);
}

// ---------------------------------------------------------------- icons
// Sab icons khud ke vector paths se — koi icon-font/package nahi.
void icon_draw(Canvas *c, int kind, int x, int y, int S, Col colv) {
    float s = S / 24.f;              // 24x24 grid
    float lw = 1.9f * s;
    Col c1 = colv;
    #define PX(v) (x + (v) * s)
    #define PY(v) (y + (v) * s)
    switch (kind) {
    case 0: // launch — 2x2 grid
        for (int i = 0; i < 2; i++)
            for (int j = 0; j < 2; j++)
                cv_rrect(c, (int)PX(4 + i * 9), (int)PY(4 + j * 9),
                         (int)(7 * s), (int)(7 * s), (int)(2 * s), c1);
        break;
    case 1: // files — folder
        cv_rrect(c, (int)PX(3), (int)PY(7), (int)(18 * s), (int)(13 * s), (int)(3 * s), c1);
        cv_rrect(c, (int)PX(3), (int)PY(4), (int)(8 * s), (int)(5 * s), (int)(2 * s), c1);
        break;
    case 2: // terminal — >_
        cv_line(c, PX(5), PY(7), PX(11), PY(12), lw, c1);
        cv_line(c, PX(11), PY(12), PX(5), PY(17), lw, c1);
        cv_line(c, PX(13), PY(17), PX(19), PY(17), lw, c1);
        break;
    case 3: // notes — pencil
        cv_line(c, PX(5), PY(19), PX(8), PY(18.4f), lw, c1);
        cv_line(c, PX(8), PY(18.4f), PX(18.5f), PY(7.6f), lw, c1);
        cv_line(c, PX(18.5f), PY(7.6f), PX(16.2f), PY(5.4f), lw, c1);
        cv_line(c, PX(16.2f), PY(5.4f), PX(5), PY(15), lw, c1);
        cv_line(c, PX(5), PY(15), PX(5), PY(19), lw, c1);
        break;
    case 4: // monitor — chart
        cv_rrect_border(c, (int)PX(3), (int)PY(4), (int)(18 * s), (int)(13 * s), (int)(2 * s), (int)lw, c1);
        cv_line(c, PX(7), PY(13), PX(10), PY(10), lw, c1);
        cv_line(c, PX(10), PY(10), PX(14), PY(12), lw, c1);
        cv_line(c, PX(14), PY(12), PX(17), PY(7.5f), lw, c1);
        cv_line(c, PX(9), PY(21), PX(15), PY(21), lw, c1);
        break;
    case 5: // setup — sliders
        cv_line(c, PX(4), PY(7), PX(20), PY(7), lw, c1);
        cv_line(c, PX(4), PY(17), PX(20), PY(17), lw, c1);
        cv_circle(c, (int)PX(9), (int)PY(7), 2.6f * s, c1);
        cv_circle(c, (int)PX(15), (int)PY(17), 2.6f * s, c1);
        break;
    case 6: // settings — gear (chunky body + teeth, no bg cutout)
        for (int i = 0; i < 8; i++) {
            float a = i * (float)M_PI / 4.f;
            cv_line(c, PX(12) + cosf(a) * 6.6f * s, PY(12) + sinf(a) * 6.6f * s,
                    PX(12) + cosf(a) * 9.6f * s, PY(12) + sinf(a) * 9.6f * s,
                    4.0f * s, c1);
        }
        cv_rrect_border(c, (int)PX(5.0f), (int)PY(5.0f), (int)(14.0f * s), (int)(14.0f * s),
                        (int)(7.0f * s), (int)(4.2f * s), c1);
        break;
    case 20: // install — disk + down arrow
        cv_rrect_border(c, (int)PX(3), (int)PY(13), (int)(18 * s), (int)(8 * s),
                        (int)(2.5f * s), (int)lw, c1);
        cv_line(c, PX(12), PY(3.5f), PX(12), PY(11.5f), 2.1f * s, c1);
        cv_line(c, PX(8.5f), PY(8.2f), PX(12), PY(11.8f), 2.1f * s, c1);
        cv_line(c, PX(15.5f), PY(8.2f), PX(12), PY(11.8f), 2.1f * s, c1);
        break;
    case 19: // info — used by About
        cv_rrect_border(c, (int)PX(3.4f), (int)PY(3.4f), (int)(17.2f * s), (int)(17.2f * s),
                        (int)(8.6f * s), (int)(1.9f * s), c1);
        cv_circle(c, (int)PX(12), (int)PY(7.6f), 1.35f * s, c1);
        cv_line(c, PX(12), PY(10.8f), PX(12), PY(16.6f), 2.2f * s, c1);
        break;
    case 7: // wifi
        for (int i = 0; i < 3; i++) {
            float r = (4 + i * 4) * s;
            // arc approximation — chhote segments
            for (int k = 0; k <= 10; k++) {
                float a0 = -2.36f + (k / 10.f) * 1.57f;
                float a1 = -2.36f + ((k + 1) / 10.f) * 1.57f;
                cv_line(c, PX(12) + cosf(a0) * r, PY(17) + sinf(a0) * r,
                        PX(12) + cosf(a1) * r, PY(17) + sinf(a1) * r, lw, c1);
            }
        }
        cv_circle(c, (int)PX(12), (int)PY(17.5f), 1.8f * s, c1);
        break;
    case 8: // battery
        cv_rrect_border(c, (int)PX(3), (int)PY(7), (int)(16 * s), (int)(10 * s), (int)(2.5f * s), (int)lw, c1);
        cv_rrect(c, (int)PX(20), (int)PY(10), (int)(2 * s), (int)(4 * s), (int)(1 * s), c1);
        break;
    case 9: // volume
        cv_line(c, PX(5), PY(9.5f), PX(9), PY(9.5f), lw, c1);
        cv_line(c, PX(9), PY(9.5f), PX(13), PY(5.5f), lw, c1);
        cv_line(c, PX(13), PY(5.5f), PX(13), PY(18.5f), lw, c1);
        cv_line(c, PX(13), PY(18.5f), PX(9), PY(14.5f), lw, c1);
        cv_line(c, PX(9), PY(14.5f), PX(5), PY(14.5f), lw, c1);
        cv_line(c, PX(16), PY(9), PX(18.5f), PY(12), lw, c1);
        cv_line(c, PX(18.5f), PY(12), PX(16), PY(15), lw, c1);
        break;
    case 10: // brightness (sun)
        cv_circle(c, (int)PX(12), (int)PY(12), 4.2f * s, c1);
        for (int i = 0; i < 8; i++) {
            float a = i * (float)M_PI / 4.f;
            cv_line(c, PX(12) + cosf(a) * 6.6f * s, PY(12) + sinf(a) * 6.6f * s,
                    PX(12) + cosf(a) * 9.f * s, PY(12) + sinf(a) * 9.f * s, lw, c1);
        }
        break;
    case 11: // user — head + shoulders
        cv_circle(c, (int)PX(12), (int)PY(8.4f), 4.5f * s, c1);
        for (int k = 0; k <= 16; k++) {
            float a0 = (float)M_PI + (k / 16.f) * (float)M_PI;
            float a1 = (float)M_PI + ((k + 1) / 16.f) * (float)M_PI;
            cv_line(c, PX(12) + cosf(a0) * 8.2f * s, PY(21.5f) + sinf(a0) * 5.0f * s,
                    PX(12) + cosf(a1) * 8.2f * s, PY(21.5f) + sinf(a1) * 5.0f * s,
                    4.2f * s, c1);
        }
        break;
    case 12: // arrow left (back)
        cv_line(c, PX(15), PY(6), PX(8), PY(12), lw, c1);
        cv_line(c, PX(8), PY(12), PX(15), PY(18), lw, c1);
        break;
    case 13: // arrow up
        cv_line(c, PX(6), PY(15), PX(12), PY(8), lw, c1);
        cv_line(c, PX(12), PY(8), PX(18), PY(15), lw, c1);
        break;
    case 14: // folder open (files list dirs)
        cv_line(c, PX(3), PY(8), PX(10), PY(8), lw, c1);
        cv_line(c, PX(10), PY(8), PX(12), PY(10), lw, c1);
        cv_line(c, PX(3), PY(8), PX(3), PY(19), lw, c1);
        cv_line(c, PX(3), PY(19), PX(21), PY(19), lw, c1);
        cv_line(c, PX(21), PY(19), PX(23), PY(11), lw, c1);
        cv_line(c, PX(23), PY(11), PX(7), PY(11), lw, c1);
        break;
    case 15: // file
        cv_line(c, PX(6), PY(3), PX(15), PY(3), lw, c1);
        cv_line(c, PX(15), PY(3), PX(19), PY(7), lw, c1);
        cv_line(c, PX(19), PY(7), PX(19), PY(21), lw, c1);
        cv_line(c, PX(19), PY(21), PX(6), PY(21), lw, c1);
        cv_line(c, PX(6), PY(21), PX(6), PY(3), lw, c1);
        cv_line(c, PX(15), PY(3), PX(15), PY(7), lw, c1);
        cv_line(c, PX(15), PY(7), PX(19), PY(7), lw, c1);
        break;
    case 16: // check
        cv_line(c, PX(5), PY(12), PX(10), PY(17), lw, c1);
        cv_line(c, PX(10), PY(17), PX(19), PY(7), lw, c1);
        break;
    case 17: // power — ring with a gap at top + stem
        {
            float a0 = -1.05f, a1 = 4.19f;   // gap ~60 deg centered at top
            for (int k = 0; k < 28; k++) {
                float t0 = a0 + (a1 - a0) * (k / 28.f);
                float t1 = a0 + (a1 - a0) * ((k + 1) / 28.f);
                cv_line(c, PX(12) + cosf(t0) * 7.4f * s, PY(13) + sinf(t0) * 7.4f * s,
                        PX(12) + cosf(t1) * 7.4f * s, PY(13) + sinf(t1) * 7.4f * s,
                        2.1f * s, c1);
            }
            cv_line(c, PX(12), PY(3.2f), PX(12), PY(11.8f), 2.1f * s, c1);
        }
        break;
    case 18: // trash
        cv_line(c, PX(4), PY(6), PX(20), PY(6), lw, c1);
        cv_line(c, PX(9), PY(6), PX(10), PY(3.5f), lw, c1);
        cv_line(c, PX(10), PY(3.5f), PX(14), PY(3.5f), lw, c1);
        cv_line(c, PX(14), PY(3.5f), PX(15), PY(6), lw, c1);
        cv_line(c, PX(6), PY(6), PX(7), PY(21), lw, c1);
        cv_line(c, PX(7), PY(21), PX(18), PY(21), lw, c1);
        cv_line(c, PX(18), PY(21), PX(19), PY(6), lw, c1);
        break;
    }
    #undef PX
    #undef PY
}