"""Builds assets/decals/: road crack and oil-stain decal textures (RGBA PNG).

  python tools/generate_decals.py

crack_<n>.png: branching dark cracks on transparency.
oil_<n>.png: soft, uneven dark stains with a faint rainbow sheen.
Deterministic (seeded), so rerunning produces the same files.
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "assets" / "decals"
SIZE = 256


def crack(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    def branch(x, y, angle, length, width, depth):
        steps = int(length / 6)
        for _ in range(steps):
            angle += rng.uniform(-0.45, 0.45)
            nx = x + math.cos(angle) * 6
            ny = y + math.sin(angle) * 6
            draw.line([(x, y), (nx, ny)], fill=(10, 9, 8, 250), width=max(int(width), 2))
            x, y = nx, ny
            width *= 0.97
            if depth < 3 and rng.random() < 0.12:
                branch(x, y, angle + rng.choice([-1, 1]) * rng.uniform(0.5, 1.2), length * 0.45, width * 0.7, depth + 1)

    for _ in range(2):
        angle = rng.uniform(0, math.tau)
        branch(SIZE / 2, SIZE / 2, angle, rng.uniform(90, 125), rng.uniform(9.0, 12.0), 0)
    return img.filter(ImageFilter.GaussianBlur(0.6))


def oil(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(18):
        r = rng.uniform(20, 60)
        cx = SIZE / 2 + rng.uniform(-45, 45)
        cy = SIZE / 2 + rng.uniform(-45, 45)
        tone = rng.randint(8, 22)
        draw.ellipse([cx - r, cy - r * rng.uniform(0.6, 1.0), cx + r, cy + r * rng.uniform(0.6, 1.0)],
                     fill=(tone, tone, tone + 6, rng.randint(140, 200)))
    # A faint oily sheen ring.
    for i, color in enumerate([(90, 40, 120, 40), (40, 90, 110, 35), (110, 90, 40, 30)]):
        r = 38 + i * 6
        draw.ellipse([SIZE / 2 - r, SIZE / 2 - r * 0.8, SIZE / 2 + r, SIZE / 2 + r * 0.8], outline=color, width=3)
    img = img.filter(ImageFilter.GaussianBlur(5))
    # Fade to transparent at the edges.
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([12, 12, SIZE - 12, SIZE - 12], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(18))
    alpha = Image.eval(img.getchannel("A"), lambda a: a)
    img.putalpha(Image.composite(alpha, Image.new("L", (SIZE, SIZE), 0), mask))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for n in range(3):
        crack(100 + n).save(OUT / f"crack_{n}.png")
    for n in range(2):
        oil(200 + n).save(OUT / f"oil_{n}.png")
    print(f"wrote 5 decals to {OUT}")


if __name__ == "__main__":
    main()
