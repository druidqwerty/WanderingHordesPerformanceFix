"""Poster / icon for Wandering Hordes Save Trim, in the style of the SmoothRide / ZombieSync / Tripping Zombies MP Fix
art (dark grid, Bahnschrift, white + teal title, badges, teal glow line): the explored wall map as a trail of cells,
kept bright around the base and the player, fading out everywhere else.

  python -I make_art.py      writes mod/.../42/poster.png, 42/icon.png and docs/preview.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(HERE)
FONT = r"C:\Windows\Fonts\bahnschrift.ttf"
TEAL = (34, 211, 197)
WHITE = (240, 244, 246)
BG0, BG1 = (13, 18, 22), (22, 30, 36)
FAINT = (52, 66, 76)
WALL = (232, 160, 70)


def font(size, style="Bold"):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_name(style)
    except Exception:
        pass
    return f


def background(w, h):
    im = Image.new("RGB", (w, h))
    px = im.load()
    for y in range(h):
        k = y / (h - 1)
        c = tuple(int(BG0[i] + (BG1[i] - BG0[i]) * k) for i in range(3))
        for x in range(w):
            px[x, y] = c
    d = ImageDraw.Draw(im)
    for x in range(0, w, 32):
        d.line([(x, 0), (x, h)], fill=(26, 35, 42))
    for y in range(0, h, 32):
        d.line([(0, y), (w, y)], fill=(26, 35, 42))
    return im


def spaced(d, xy, text, f, fill, spacing):
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + spacing
    return x


def text_width(d, text, f, spacing):
    return sum(d.textlength(ch, font=f) for ch in text) + spacing * (len(text) - 1)


def fit(d, text, size, width, style="Bold"):
    f = font(size, style)
    while d.textlength(text, font=f) > width and size > 10:
        size -= 2
        f = font(size, style)
    return f


def trail_cells(cols, rows, seed=7):
    """cells of a winding explored trail (like a long drive) plus blobs around the stops"""
    rnd = random.Random(seed)
    cells = set()
    pts = []
    for i in range(0, 200):
        t = i / 199
        x = t * (cols - 1)
        y = rows * 0.52 + rows * 0.30 * math.sin(t * 5.2 + 0.6) + rows * 0.08 * math.sin(t * 13.0)
        pts.append((x, y))
    for x, y in pts:
        r = 1.9 + 0.6 * math.sin(x * 0.7)
        for cx in range(int(x - r), int(x + r) + 1):
            for cy in range(int(y - r), int(y + r) + 1):
                if 0 <= cx < cols and 0 <= cy < rows and (cx - x) ** 2 + (cy - y) ** 2 <= r * r:
                    cells.add((cx, cy))
    for bx, by, br in ((cols * 0.30, rows * 0.45, 4.2), (cols * 0.78, rows * 0.30, 3.2), (cols * 0.08, rows * 0.70, 2.6)):
        for cx in range(int(bx - br), int(bx + br) + 1):
            for cy in range(int(by - br), int(by + br) + 1):
                if 0 <= cx < cols and 0 <= cy < rows and (cx - bx) ** 2 + (cy - by) ** 2 <= br * br + rnd.random() * 3:
                    cells.add((cx, cy))
    return cells


def house(d, cx, cy, s, fill):
    w, h = 18 * s, 12 * s
    d.polygon([(cx - w * 0.62, cy - h * 0.2), (cx, cy - h * 1.15), (cx + w * 0.62, cy - h * 0.2)], fill=fill)
    d.rectangle([cx - w * 0.45, cy - h * 0.25, cx + w * 0.45, cy + h * 0.65], fill=fill)
    d.rectangle([cx - w * 0.12, cy + h * 0.1, cx + w * 0.12, cy + h * 0.65], fill=BG0)


def map_layer(size, box, cell, keep, base, player, s):
    """the wall map: kept cells bright teal inside `keep` (cell rect), the rest fading out"""
    x0, y0, x1, y1 = box
    cols, rows = (x1 - x0) // cell, (y1 - y0) // cell
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rnd = random.Random(3)
    k0, k1, k2, k3 = keep
    for cx, cy in sorted(trail_cells(cols, rows)):
        px, py = x0 + cx * cell, y0 + cy * cell
        if k0 <= cx <= k1 and k2 <= cy <= k3:
            g = 0.55 + 0.45 * rnd.random()
            col = tuple(int(c * g + 20 * (1 - g)) for c in TEAL)
            d.rectangle([px + 1, py + 1, px + cell - 2, py + cell - 2], fill=col + (235,))
        else:
            # far away: forgotten, shown as fading outlines that shrink with the distance from the kept square
            dist = max(k0 - cx, cx - k1, k2 - cy, cy - k3, 0)
            if rnd.random() < min(0.6, 0.02 * dist):
                continue
            a = max(55, 170 - dist * 5)
            inset = min(cell // 2 - 1, 1 + dist // 9)
            d.rectangle([px + inset, py + inset, px + cell - 1 - inset, py + cell - 1 - inset],
                        outline=FAINT + (a,), width=1)
    # the kept square's border
    d.rectangle([x0 + k0 * cell - 2, y0 + k2 * cell - 2, x0 + (k1 + 1) * cell + 1, y0 + (k3 + 1) * cell + 1],
                outline=WHITE + (220,), width=max(1, int(2 * s)))
    # fences of the base (they must stay known)
    bx, by = x0 + base[0] * cell, y0 + base[1] * cell
    r = int(3.2 * cell)
    d.rectangle([bx - r, by - r, bx + r, by + r], outline=WALL + (255,), width=max(2, int(3 * s)))
    house(d, bx, by + 2 * s, s * 1.2, WHITE + (255,))
    # the player
    ppx, ppy = x0 + player[0] * cell, y0 + player[1] * cell
    pr = 5 * s
    d.ellipse([ppx - pr, ppy - pr, ppx + pr, ppy + pr], fill=(255, 255, 255, 255))
    return layer


def poster(size=512):
    s = size / 512
    im = background(size, size).convert("RGBA")
    d = ImageDraw.Draw(im)
    f1 = fit(d, "WANDERING HORDES", int(52 * s), int(452 * s))
    d.text((int(30 * s), int(22 * s)), "WANDERING HORDES", font=f1, fill=WHITE)
    f2 = fit(d, "SAVE TRIM", int(96 * s), int(452 * s))
    glow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((int(28 * s), int(76 * s)), "SAVE TRIM", font=f2, fill=TEAL + (200,))
    im.alpha_composite(glow.filter(ImageFilter.GaussianBlur(10 * s)))
    d = ImageDraw.Draw(im)
    d.text((int(28 * s), int(76 * s)), "SAVE TRIM", font=f2, fill=TEAL)
    # badges
    fb = font(int(24 * s), "SemiBold")
    bx, by, bh = int(30 * s), int(190 * s), int(38 * s)
    d.rounded_rectangle([bx, by, bx + int(74 * s), by + bh], radius=int(7 * s), fill=TEAL)
    d.text((bx + int(13 * s), by + int(5 * s)), "LUA", font=fb, fill=(10, 30, 32))
    bx2 = bx + int(86 * s)
    d.rounded_rectangle([bx2, by, bx2 + int(80 * s), by + bh], radius=int(7 * s), outline=(200, 208, 214),
                        width=max(1, int(2 * s)))
    d.text((bx2 + int(15 * s), by + int(5 * s)), "B42", font=fb, fill=(220, 226, 230))
    fs = font(int(20 * s), "SemiBold")
    d.text((bx2 + int(96 * s), by + int(8 * s)), "SP + MP", font=fs, fill=(190, 200, 210))
    # the map
    cell = max(4, int(12 * s))
    box = (int(16 * s), int(244 * s), int(496 * s), int(444 * s))
    cols = (box[2] - box[0]) // cell
    rows = (box[3] - box[1]) // cell
    keep = (int(cols * 0.18), int(cols * 0.44), int(rows * 0.08), int(rows * 0.86))
    layer = map_layer(size, box, cell, keep, (cols * 0.30, rows * 0.45), (cols * 0.37, rows * 0.60), s)
    im.alpha_composite(layer)
    d = ImageDraw.Draw(im)
    fc = font(int(19 * s), "SemiBold")
    cap = "NO MORE SAVE FREEZES"
    w = text_width(d, cap, fc, 3 * s)
    spaced(d, ((size - w) / 2, int(468 * s)), cap, fc, (190, 200, 210), 3 * s)
    return im.convert("RGB")


def icon(size=128):
    s = size / 128
    im = background(size, size).convert("RGBA")
    cell = max(4, int(8 * s))
    box = (0, int(10 * s), size, size - int(4 * s))
    cols = (box[2] - box[0]) // cell
    rows = (box[3] - box[1]) // cell
    keep = (int(cols * 0.10), int(cols * 0.62), int(rows * 0.12), int(rows * 0.88))
    layer = map_layer(size, box, cell, keep, (cols * 0.30, rows * 0.45), (cols * 0.47, rows * 0.66), s * 0.7)
    im.alpha_composite(layer)
    return im.convert("RGB")


if __name__ == "__main__":
    mod42 = os.path.join(PROJ, "mod", "WanderingHordesSaveTrim", "42")
    if not os.path.isdir(mod42):  # GitHub repo: 42/ at the root
        mod42 = os.path.join(PROJ, "42")
    docs = os.path.join(PROJ, "docs")
    os.makedirs(docs, exist_ok=True)
    p = poster(512)
    p.save(os.path.join(mod42, "poster.png"))
    p.save(os.path.join(docs, "preview.png"))
    icon(128).save(os.path.join(mod42, "icon.png"))
    print("written:", os.path.join(mod42, "poster.png"), os.path.join(mod42, "icon.png"), os.path.join(docs, "preview.png"))
