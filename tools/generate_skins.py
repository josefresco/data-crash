"""Generate faction outfit skins for the Kenney animated character.

Recolors the CC0 Kenney "skaterMaleA" skin atlas region by region (shirt,
sleeves, pants, hair, shoes, skin), preserving the original shading by scaling
each target color by the pixel's brightness relative to the base color.

Output: assets/kenney/characters/skins/<outfit>_<tone>.png (512 px).
Re-run after changing OUTFITS:  python tools/generate_skins.py
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "assets/kenney/characters/base_skins/skaterMaleA.png"
OUT = ROOT / "assets/kenney/characters/skins"
SIZE = 512

# Atlas regions of the Kenney character skin (x0, y0, x1, y1) at 1024 px.
HEAD = (0, 0, 640, 490)
SHOES = (640, 134, 824, 524)
PANTS = (610, 764, 1024, 1024)
SHIRT = (152, 490, 492, 1024)
SLEEVES = [(0, 490, 152, 1024), (492, 490, 610, 1024)]

# Chest badge replacing the base skin's skull logo (center, radius) at 1024 px.
BADGE = ((321, 842), 30)

# Base colors in skaterMaleA.
BASE_HAIR = (0x4D, 0x16, 0x0E)
BASE_SKIN = (0xF5, 0x91, 0x70)
BASE_SHIRT = (0xF2, 0x65, 0x4C)
BASE_SHIRT_DARK = (0xEA, 0x30, 0x31)
BASE_SLEEVE = (0xFF, 0xFF, 0xFF)
BASE_PANTS = (0x16, 0x52, 0x79)
BASE_SHOE = (0x38, 0xBB, 0x96)

# (skin, hair) pairs; index is the tone suffix.
TONES = [
    ((0.96, 0.78, 0.66), (0.35, 0.22, 0.12)),
    ((0.87, 0.64, 0.48), (0.12, 0.08, 0.06)),
    ((0.72, 0.5, 0.36), (0.08, 0.06, 0.05)),
    ((0.52, 0.35, 0.24), (0.06, 0.05, 0.04)),
    ((0.96, 0.8, 0.7), (0.78, 0.62, 0.34)),
]

# shirt, sleeves ("skin" = short sleeves), pants, shoes, logo (None = remove).
OUTFITS = {
    "player": ((0.92, 0.5, 0.15), "shirt", (0.2, 0.3, 0.5), (0.9, 0.9, 0.9), None),
    "guard": ((0.12, 0.12, 0.14), "shirt", (0.15, 0.15, 0.17), (0.08, 0.08, 0.08), (0.95, 0.8, 0.2)),
    "police": ((0.1, 0.18, 0.42), "shirt", (0.08, 0.12, 0.28), (0.06, 0.06, 0.06), (0.95, 0.8, 0.3)),
    "frost": ((0.2, 0.22, 0.27), "shirt", (0.16, 0.17, 0.2), (0.07, 0.07, 0.08), (0.4, 0.8, 1.0)),
    "orange_hat": ((0.9, 0.88, 0.84), "skin", (0.62, 0.54, 0.4), (0.45, 0.32, 0.2), (1.0, 0.45, 0.05)),
    "townsperson": ((0.96, 0.84, 0.12), "shirt", (0.22, 0.3, 0.48), (0.4, 0.28, 0.18), (1.0, 0.5, 0.1)),
    "elmo": ((0.09, 0.09, 0.1), "skin", (0.14, 0.17, 0.24), (0.9, 0.9, 0.9), (0.6, 0.6, 0.65)),
    "sham": ((0.94, 0.94, 0.96), "shirt", (0.92, 0.92, 0.94), (0.1, 0.1, 0.1), (0.4, 0.9, 1.0)),
    "fark": ((0.5, 0.52, 0.56), "shirt", (0.25, 0.3, 0.45), (0.9, 0.9, 0.9), (0.25, 0.45, 0.9)),
    "harry": ((0.12, 0.15, 0.3), "shirt", (0.1, 0.12, 0.25), (0.15, 0.08, 0.05), (0.95, 0.8, 0.25)),
    "crapya": ((0.1, 0.14, 0.26), "shirt", (0.08, 0.08, 0.1), (0.1, 0.1, 0.1), (0.3, 0.9, 0.6)),
    "vendor": ((0.36, 0.32, 0.2), "shirt", (0.3, 0.28, 0.22), (0.3, 0.2, 0.12), None),
    "foreman": ((1.0, 0.55, 0.1), "skin", (0.25, 0.3, 0.42), (0.35, 0.25, 0.15), (0.95, 0.95, 0.9)),
    # Elmo's Twatter reply guys: faded black fan tee, khakis, white sneakers.
    "reply_guy": ((0.16, 0.16, 0.18), "skin", (0.62, 0.56, 0.42), (0.95, 0.95, 0.95), (0.85, 0.85, 0.9)),
    # Neighborhood grandmas: lavender cardigan, gray slacks, sensible shoes.
    "old_lady": ((0.66, 0.55, 0.78), "shirt", (0.48, 0.47, 0.5), (0.72, 0.62, 0.5), None),
}

# Outfits that ignore TONES: reply guys are all very pale (basement tan).
TONE_OVERRIDES = {
    "old_lady": [((s[0], s[1], s[2]), (0.93, 0.93, 0.95)) for s, _hair in [
        ((0.96, 0.8, 0.7), None), ((0.87, 0.66, 0.52), None), ((0.72, 0.52, 0.38), None),
        ((0.55, 0.37, 0.26), None), ((0.98, 0.85, 0.78), None)]],
    "reply_guy": [
        ((1.0, 0.9, 0.86), (0.35, 0.25, 0.15)),
        ((0.99, 0.92, 0.9), (0.55, 0.4, 0.22)),
        ((1.0, 0.88, 0.84), (0.2, 0.15, 0.1)),
        ((0.98, 0.9, 0.87), (0.7, 0.55, 0.3)),
        ((1.0, 0.91, 0.88), (0.4, 0.3, 0.2)),
    ],
}


def luma(rgb):
    return rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114


def near(rgb, color, tolerance):
    diff = rgb - np.array(color, dtype=np.float32)
    return np.sqrt((diff ** 2).sum(axis=-1)) < tolerance


def recolor(rgb, mask, base, target):
    """Paint `target` (0..1 floats) where mask is set, keeping relative shading."""
    base_l = max(luma(np.array(base, dtype=np.float32)), 1.0)
    ratio = np.clip(luma(rgb) / base_l, 0.55, 1.35)[..., None]
    painted = np.clip(np.array(target, dtype=np.float32) * 255.0 * ratio, 0, 255)
    rgb[mask] = painted[mask]


def region_mask(shape, box):
    mask = np.zeros(shape[:2], dtype=bool)
    x0, y0, x1, y1 = box
    mask[y0:y1, x0:x1] = True
    return mask


def build(base_rgb, outfit, tone):
    shirt, sleeves, pants, shoes, logo = outfit
    skin, hair = tone
    rgb = base_rgb.copy()
    source = base_rgb  # match against the untouched colors

    skin_mask = near(source, BASE_SKIN, 40)
    hair_mask = near(source, BASE_HAIR, 45) & region_mask(rgb.shape, HEAD)

    shirt_region = region_mask(rgb.shape, SHIRT)
    shirt_mask = shirt_region & (near(source, BASE_SHIRT, 60) | near(source, BASE_SHIRT_DARK, 60))
    logo_mask = shirt_region & near(source, (255, 255, 255), 40)

    sleeve_region = np.zeros(rgb.shape[:2], dtype=bool)
    for box in SLEEVES:
        sleeve_region |= region_mask(rgb.shape, box)
    sleeve_mask = sleeve_region & (near(source, BASE_SLEEVE, 40) | near(source, (0xE5, 0xE5, 0xE5), 30))

    pants_mask = region_mask(rgb.shape, PANTS) & near(source, BASE_PANTS, 60)
    shoe_mask = region_mask(rgb.shape, SHOES) & near(source, BASE_SHOE, 60)

    recolor(rgb, skin_mask, BASE_SKIN, skin)
    recolor(rgb, hair_mask, BASE_HAIR, hair)
    recolor(rgb, shirt_mask, BASE_SHIRT, shirt)
    recolor(rgb, logo_mask, (255, 255, 255), shirt)  # erase the skull
    recolor(rgb, sleeve_mask, BASE_SLEEVE, skin if sleeves == "skin" else shirt)
    recolor(rgb, pants_mask, BASE_PANTS, pants)
    recolor(rgb, shoe_mask, BASE_SHOE, shoes)
    if logo:
        image = Image.fromarray(rgb.astype(np.uint8))
        (cx, cy), r = BADGE
        fill = tuple(int(c * 255) for c in logo)
        ImageDraw.Draw(image).ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
        rgb = np.asarray(image, dtype=np.float32).copy()
    return rgb


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    base_rgb = np.asarray(Image.open(BASE).convert("RGB"), dtype=np.float32)
    count = 0
    for name, outfit in OUTFITS.items():
        for index, tone in enumerate(TONE_OVERRIDES.get(name, TONES)):
            rgb = build(base_rgb, outfit, tone)
            image = Image.fromarray(rgb.astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)
            image.save(OUT / f"{name}_{index}.png", optimize=True)
            count += 1
    print(f"wrote {count} skins to {OUT}")


if __name__ == "__main__":
    main()
