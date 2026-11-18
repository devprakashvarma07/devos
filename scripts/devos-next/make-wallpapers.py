#!/usr/bin/env python3
"""make-wallpapers.py — DevOS ke bundled wallpapers generate karta hai.

Hinglish: official DevOS-logo.svg ko rasterise karke (rsvg-convert ya pehle se
bana logo.png) dark gradients par compose karta hai. Output:
/usr/share/backgrounds/devos/ ke liye 4 PNG (1920x1080).

Usage:
    python3 make-wallpapers.py <logo.png> <out_dir>
"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont

W, H = 1920, 1080


def radial(w, h, cx, cy, r, color, strength):
    ys, xs = np.mgrid[0:h, 0:w]
    d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / r
    a = np.clip(1 - d, 0, 1) ** 2.2 * strength
    layer = np.zeros((h, w, 3), np.float32)
    for i in range(3):
        layer[..., i] = color[i] * a
    return layer


def make(logo, out_dir, name, base, blobs, logo_scale, logo_pos,
         caption=True, alpha=235):
    arr = np.zeros((H, W, 3), np.float32)
    for i in range(3):
        arr[..., i] = base[i]
    for (cx, cy, r, col, s) in blobs:
        arr += radial(W, H, cx, cy, r, col, s)
    arr = np.clip(arr, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr, "RGB").convert("RGBA")

    # halka vignette
    ys, xs = np.mgrid[0:H, 0:W]
    d = np.sqrt(((xs - W / 2) / (W / 2)) ** 2 + ((ys - H / 2) / (H / 2)) ** 2)
    vig = np.clip(1 - 0.35 * np.clip(d - 0.55, 0, 1) ** 1.5, 0, 1)
    vimg = Image.fromarray((np.stack([vig] * 3, -1) * 255).astype(np.uint8), "RGB")
    img = Image.composite(img, Image.new("RGBA", (W, H), (0, 0, 0, 255)), vimg.convert("L"))

    lw = int(W * logo_scale)
    lh = int(logo.height * lw / logo.width)
    lg = logo.resize((lw, lh), Image.LANCZOS)
    if alpha < 255:
        a = lg.getchannel("A").point(lambda p: p * alpha // 255)
        lg.putalpha(a)
    x, y = logo_pos
    if x < 0:
        x = (W - lw) // 2
    if y < 0:
        y = (H - lh) // 2
    img.alpha_composite(lg, (x, y))

    if caption:
        d = ImageDraw.Draw(img)
        f2 = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 22)
        txt = "DEVOS 2.0  ·  WHALE"
        tw = d.textlength(txt, font=f2)
        d.text(((W - tw) / 2, y + lh + 46), txt, font=f2, fill=(150, 175, 210, 170))

    path = f"{out_dir}/{name}.png"
    img.convert("RGB").save(path, optimize=True)
    print(name, img.size, "->", path)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    logo = Image.open(sys.argv[1]).convert("RGBA")
    out = sys.argv[2]
    make(logo, out, "whale", (6, 9, 18),
         [(W * 0.18, H * 0.15, H * 1.15, (18, 44, 92), 0.95),
          (W * 0.84, H * 0.30, H * 1.05, (52, 34, 130), 0.75),
          (W * 0.50, H * 0.95, H * 0.85, (10, 40, 84), 0.80)],
         0.42, (-1, int(H * 0.38)))
    make(logo, out, "aurora", (4, 6, 12),
         [(W * 0.25, H * 0.25, H * 1.25, (16, 78, 160), 1.00),
          (W * 0.78, H * 0.22, H * 1.10, (96, 42, 180), 0.80),
          (W * 0.55, H * 0.90, H * 0.95, (12, 96, 140), 0.70)],
         0.34, (-1, int(H * 0.30)))
    make(logo, out, "deep", (5, 8, 16),
         [(W * 0.80, H * 0.78, H * 1.30, (14, 52, 120), 0.95),
          (W * 0.15, H * 0.20, H * 0.90, (24, 20, 70), 0.65)],
         0.30, (int(W * 0.54), int(H * 0.60)), caption=False)
    make(logo, out, "mono", (7, 8, 11),
         [(W * 0.50, H * 0.45, H * 1.5, (28, 32, 46), 0.85)],
         0.46, (-1, int(H * 0.40)), alpha=70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
