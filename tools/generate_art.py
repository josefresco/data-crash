"""Builds assets/generated/: cracked-mud surface textures, protest posters,
and graffiti tags (PNG, deterministic).

  python tools/generate_art.py            # write the images
  python tools/generate_art.py --fix-imports   # after `--import`: mipmaps,
                                          # VRAM compression, normal-map flag

mud_color.png / mud_normal.png: tileable dry clay plates split by cracks
(toroidal Voronoi), for riverbeds. poster_<n>.png: protest posters (paper,
bold type, tape). graffiti_<n>.png: spray-painted slogans with drips, on
transparency (graffiti_<n>_glow.png: the same, premultiplied on black, for
decal emission). Fonts: Windows' Impact and Comic Sans Bold (the rendered
images are committed; rerunning needs those fonts).
"""
import math
import random
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "generated"
FONTS = Path("C:/Windows/Fonts")
IMPACT = str(FONTS / "impact.ttf")
HAND = str(FONTS / "comicbd.ttf")


def voronoi_f1_f2(size, points):
    """Distances to the nearest and second-nearest point, wrapping at the edges."""
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32)
    f1 = np.full((size, size), 1e9, np.float32)
    f2 = np.full((size, size), 1e9, np.float32)
    for px, py in points:
        dx = np.abs(xs - px)
        dy = np.abs(ys - py)
        dx = np.minimum(dx, size - dx)
        dy = np.minimum(dy, size - dy)
        d = np.sqrt(dx * dx + dy * dy)
        f2 = np.where(d < f1, f1, np.minimum(f2, d))
        f1 = np.minimum(f1, d)
    return f1, f2


def mud(size=512, seed=11):
    rng = np.random.default_rng(seed)
    points = rng.uniform(0, size, (70, 2))
    f1, f2 = voronoi_f1_f2(size, points)
    edge = f2 - f1  # 0 on the cracks
    crack = np.clip(1.0 - edge / 5.0, 0.0, 1.0) ** 1.5
    # Plates bulge a little in the middle and curl up at the edges.
    height = np.clip(edge / 18.0, 0.0, 1.0) * 0.6 + np.clip(f1 / 60.0, 0.0, 1.0) * 0.15 - crack * 0.9
    grain = rng.normal(0.0, 1.0, (size, size)).astype(np.float32)
    grain_img = Image.fromarray(((grain * 0.5 + 0.5).clip(0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
    grain = np.asarray(grain_img, np.float32) / 255.0 - 0.5
    # Color: sun-bleached clay plates, darker cracks, a little blotching.
    plate = np.array([176, 146, 110], np.float32)
    dark = np.array([74, 58, 42], np.float32)
    blotch = Image.fromarray((rng.uniform(0, 255, (size // 16, size // 16))).astype(np.uint8)).resize((size, size), Image.BICUBIC)
    blotch = np.asarray(blotch, np.float32) / 255.0 - 0.5
    shade = 1.0 + blotch[..., None] * 0.18 + grain[..., None] * 0.1
    color = plate * shade * (1.0 - crack[..., None]) + dark * crack[..., None]
    Image.fromarray(color.clip(0, 255).astype(np.uint8)).save(OUT / "mud_color.png")
    # Normal map from the height (tileable gradient).
    h = height + grain * 0.04
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 2.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 2.5
    n = np.dstack([-dx, -dy, np.ones_like(h)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(OUT / "mud_normal.png")


POSTERS = [
    (["GIVE US", "OUR WATER", "BACK"], IMPACT, (250, 214, 60), (20, 20, 20)),
    (["NOT IN", "MY", "AQUIFER"], IMPACT, (244, 240, 230), (200, 30, 30)),
    (["YOUR CLOUD", "OUR", "DROUGHT"], IMPACT, (40, 90, 170), (245, 245, 240)),
    (["HANDS OFF", "OUR", "RIVER!"], HAND, (248, 246, 238), (30, 120, 50)),
    (["NO MORE", "SERVER", "FARMS"], IMPACT, (236, 236, 228), (25, 25, 25)),
    (["HONK IF", "YOU'RE", "THIRSTY"], IMPACT, (250, 140, 40), (25, 25, 25)),
]


def fit_font(path, text, width, start=120):
    size = start
    while size > 12:
        font = ImageFont.truetype(path, size)
        if font.getlength(text) <= width:
            return font
        size -= 2
    return ImageFont.truetype(path, 12)


def poster(index, lines, font_path, paper, ink):
    rng = random.Random(500 + index)
    w, h = 256, 360
    img = Image.new("RGBA", (w, h), paper + (255,))
    draw = ImageDraw.Draw(img)
    # Paper grain and a little sun fade.
    for _ in range(900):
        x, y = rng.randrange(w), rng.randrange(h)
        tone = rng.randint(-14, 14)
        draw.point((x, y), tuple(max(0, min(255, c + tone)) for c in paper) + (255,))
    y = 40
    for line in lines:
        font = fit_font(font_path, line, w - 40)
        box = draw.textbbox((0, 0), line, font=font)
        lw, lh = box[2] - box[0], box[3] - box[1]
        draw.text(((w - lw) / 2 - box[0], y - box[1]), line, font=font, fill=ink + (255,))
        y += lh + 26
    if index == 4:
        # A crossed-out server rack under the words.
        rack = (w / 2 - 34, h - 110, w / 2 + 34, h - 30)
        draw.rectangle(rack, outline=ink + (255,), width=5)
        for k in range(4):
            yy = rack[1] + 12 + k * 16
            draw.line((rack[0] + 8, yy, rack[2] - 8, yy), fill=ink + (255,), width=4)
        draw.line((rack[0] - 14, rack[3] + 10, rack[2] + 14, rack[1] - 10), fill=(210, 30, 30, 255), width=10)
    # Masking tape on the top corners.
    for cx in (22, w - 22):
        tape = Image.new("RGBA", (54, 18), (230, 222, 190, 210))
        tape = tape.rotate(rng.choice([-35, 35]), expand=True)
        img.alpha_composite(tape, (int(cx - tape.width / 2), 0))
    img.rotate(rng.uniform(-3, 3), resample=Image.BICUBIC, fillcolor=(0, 0, 0, 0)).save(OUT / f"poster_{index}.png")


GRAFFITI = [
    ("WATER NOT WATTS", (40, 170, 230)),
    ("UNPLUG THE GREED", (230, 60, 60)),
    ("OUR RIVER", (70, 200, 90)),
]


def graffiti(index, text, color):
    rng = random.Random(700 + index)
    w, h = 512, 192
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    font = fit_font(IMPACT, text, w - 40, 110)
    box = draw.textbbox((0, 0), text, font=font)
    x0 = (w - (box[2] - box[0])) / 2 - box[0]
    y0 = (h - (box[3] - box[1])) / 2 - box[1] - 10
    draw.text((x0, y0), text, font=font, fill=255)
    # Drips running down from the letters.
    arr = np.asarray(mask)
    for _ in range(26):
        x = rng.randrange(20, w - 20)
        col = np.nonzero(arr[:, x] > 128)[0]
        if col.size == 0:
            continue
        top = int(col.max())
        length = rng.randint(10, 46)
        draw.line((x, top, x, min(h - 2, top + length)), fill=230, width=rng.choice([2, 3]))
        draw.ellipse((x - 3, top + length - 3, x + 3, top + length + 3), fill=230)
    soft = mask.filter(ImageFilter.GaussianBlur(1.6))
    # Overspray speckle around the strokes.
    halo = mask.filter(ImageFilter.GaussianBlur(7))
    speck = Image.fromarray((np.random.default_rng(900 + index).uniform(0, 1, (h, w)) < 0.35).astype(np.uint8) * 255)
    halo = Image.fromarray((np.asarray(halo, np.float32) * np.asarray(speck, np.float32) / 255.0 * 0.35).astype(np.uint8))
    alpha = np.maximum(np.asarray(soft, np.float32), np.asarray(halo, np.float32))
    rgba = np.zeros((h, w, 4), np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = color
    rgba[..., 3] = alpha.clip(0, 255).astype(np.uint8)
    Image.fromarray(rgba).save(OUT / f"graffiti_{index}.png")
    # Glow version for decal emission: color premultiplied by alpha, opaque
    # black elsewhere (decal emission ignores the alpha channel).
    glow = np.zeros((h, w, 3), np.uint8)
    for c in range(3):
        glow[..., c] = (color[c] * alpha.clip(0, 255) / 255.0).astype(np.uint8)
    Image.fromarray(glow).save(OUT / f"graffiti_{index}_glow.png")


def fix_imports():
    """Mipmaps and VRAM compression for 3D use; mud_normal as a normal map."""
    for path in OUT.glob("*.png.import"):
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"compress/mode=\d", "compress/mode=2", text)
        text = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", text)
        text = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", text)
        if path.name == "mud_normal.png.import":
            text = re.sub(r"compress/normal_map=\d", "compress/normal_map=1", text)
        path.write_text(text, encoding="utf-8", newline="\n")
    print("patched import settings")


def main():
    if "--fix-imports" in sys.argv:
        fix_imports()
        return
    OUT.mkdir(parents=True, exist_ok=True)
    mud()
    for i, spec in enumerate(POSTERS):
        poster(i, *spec)
    for i, (text, color) in enumerate(GRAFFITI):
        graffiti(i, text, color)
    print(f"wrote mud textures, {len(POSTERS)} posters, {len(GRAFFITI)} graffiti tags to {OUT}")


if __name__ == "__main__":
    main()
