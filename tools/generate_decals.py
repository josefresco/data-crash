"""Builds assets/decals/: road and street-grime decal textures (RGBA PNG).

  python tools/generate_decals.py

crack_<n>.png: branching dark cracks on transparency.
oil_<n>.png: soft, uneven dark stains with a faint rainbow sheen.
blood_<n>.png: wound splats for character models (a dark core, flecks).
manhole.png: a cast-iron cover with a grip pattern and a rusty rim.
drain.png: a curb storm drain grate with a "DRAINS TO RIVER" stencil.
tires_<n>.png: pairs of dark tire streaks.
grime_<n>.png: blotchy sidewalk stains and gum spots.
puddle_<n>.png: dark wet patches (glossy in the shader via roughness).
streak_<n>.png: dirty drip streaks for wall bases and facades.
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


def blood(seed):
    """A wound splat for character models: a dark red core, a torn edge, and
    a few flecks. White-ish alpha shape in deep red (tinted in the shader)."""
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(14):
        r = rng.uniform(14, 34)
        cx = SIZE / 2 + rng.uniform(-30, 30)
        cy = SIZE / 2 + rng.uniform(-30, 30)
        red = rng.randint(95, 135)
        draw.ellipse([cx - r, cy - r * rng.uniform(0.6, 1.0), cx + r, cy + r * rng.uniform(0.6, 1.0)],
                     fill=(red, rng.randint(6, 16), rng.randint(6, 14), rng.randint(200, 245)))
    # Flecks thrown outward.
    for _ in range(26):
        angle = rng.uniform(0, math.tau)
        dist = rng.uniform(55, 105)
        r = rng.uniform(2, 7)
        cx = SIZE / 2 + math.cos(angle) * dist
        cy = SIZE / 2 + math.sin(angle) * dist
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(110, 10, 10, rng.randint(150, 230)))
    # A darker, wetter center.
    draw.ellipse([SIZE / 2 - 22, SIZE / 2 - 18, SIZE / 2 + 22, SIZE / 2 + 18], fill=(60, 4, 6, 240))
    return img.filter(ImageFilter.GaussianBlur(1.2))


def manhole():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    c = SIZE / 2
    draw.ellipse([c - 120, c - 120, c + 120, c + 120], fill=(92, 58, 38, 235))  # rusty rim
    draw.ellipse([c - 108, c - 108, c + 108, c + 108], fill=(38, 37, 36, 255))
    # Raised grip pattern: concentric rings and radial bars.
    for r in (30, 55, 80):
        draw.ellipse([c - r, c - r, c + r, c + r], outline=(62, 60, 58, 255), width=6)
    for k in range(12):
        a = k * math.tau / 12
        draw.line([(c + math.cos(a) * 30, c + math.sin(a) * 30), (c + math.cos(a) * 104, c + math.sin(a) * 104)],
                  fill=(58, 56, 54, 255), width=5)
    return img.filter(ImageFilter.GaussianBlur(0.7))


def drain():
    from PIL import ImageFont
    w, h = SIZE, SIZE
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    # The grate in the top half.
    draw.rectangle([28, 20, w - 28, 110], fill=(30, 30, 30, 250))
    for x in range(40, w - 36, 16):
        draw.rectangle([x, 28, x + 7, 102], fill=(8, 8, 8, 255))
    # Stencil below: text and a little fish.
    try:
        font = ImageFont.truetype("C:/Windows/Fonts/impact.ttf", 34)
    except OSError:
        font = ImageFont.load_default()
    for line, y in (("DRAINS", 124), ("TO RIVER", 168)):
        box = draw.textbbox((0, 0), line, font=font)
        draw.text(((w - (box[2] - box[0])) / 2 - box[0], y), line, font=font, fill=(235, 235, 230, 210))
    draw.ellipse([w / 2 - 26, 214, w / 2 + 14, 236], fill=(235, 235, 230, 200))
    draw.polygon([(w / 2 + 12, 225), (w / 2 + 30, 212), (w / 2 + 30, 238)], fill=(235, 235, 230, 200))
    return img.filter(ImageFilter.GaussianBlur(0.8))


def tires(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    bend = rng.uniform(-40, 40)
    for offset in (-38, 38):
        points = []
        for k in range(21):
            t = k / 20
            x = SIZE / 2 + offset + bend * math.sin(t * math.pi)
            points.append((x, 8 + t * (SIZE - 16)))
        draw.line(points, fill=(12, 12, 12, rng.randint(120, 180)), width=rng.randint(14, 20))
    img = img.filter(ImageFilter.GaussianBlur(2.5))
    # Fade at both ends.
    mask = Image.new("L", (SIZE, SIZE), 0)
    for y in range(SIZE):
        v = int(255 * min(1.0, min(y, SIZE - y) / 50))
        ImageDraw.Draw(mask).line([(0, y), (SIZE, y)], fill=v)
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    return img


def grime(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(30):
        r = rng.uniform(8, 40)
        cx, cy = rng.uniform(40, SIZE - 40), rng.uniform(40, SIZE - 40)
        tone = rng.randint(30, 60)
        draw.ellipse([cx - r, cy - r * 0.7, cx + r, cy + r * 0.7], fill=(tone, tone - 4, tone - 10, rng.randint(30, 80)))
    for _ in range(14):  # gum
        cx, cy = rng.uniform(30, SIZE - 30), rng.uniform(30, SIZE - 30)
        r = rng.uniform(2.5, 5)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(40, 40, 42, 200))
    img = img.filter(ImageFilter.GaussianBlur(3))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).ellipse([16, 16, SIZE - 16, SIZE - 16], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(20))
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    return img


def puddle(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(9):
        r = rng.uniform(30, 70)
        cx, cy = SIZE / 2 + rng.uniform(-40, 40), SIZE / 2 + rng.uniform(-30, 30)
        draw.ellipse([cx - r, cy - r * 0.6, cx + r, cy + r * 0.6], fill=(18, 22, 26, 170))
    img = img.filter(ImageFilter.GaussianBlur(6))
    return img


def streak(seed):
    rng = random.Random(seed)
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for _ in range(40):
        x = rng.uniform(0, SIZE)
        top = rng.uniform(0, 40)
        length = rng.uniform(60, SIZE)
        tone = rng.randint(25, 50)
        draw.line([(x, top), (x + rng.uniform(-3, 3), top + length)], fill=(tone, tone - 3, tone - 8, rng.randint(40, 110)),
                  width=rng.randint(3, 10))
    img = img.filter(ImageFilter.GaussianBlur(3))
    # Heavier at the top (where the water runs off), fading down.
    mask = Image.new("L", (SIZE, SIZE), 0)
    for y in range(SIZE):
        ImageDraw.Draw(mask).line([(0, y), (SIZE, y)], fill=int(255 * (1.0 - y / SIZE) ** 1.2))
    img.putalpha(Image.composite(img.getchannel("A"), Image.new("L", (SIZE, SIZE), 0), mask))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for n in range(3):
        crack(100 + n).save(OUT / f"crack_{n}.png")
    for n in range(2):
        oil(200 + n).save(OUT / f"oil_{n}.png")
    for n in range(3):
        blood(300 + n).save(OUT / f"blood_{n}.png")
    manhole().save(OUT / "manhole.png")
    drain().save(OUT / "drain.png")
    for n in range(2):
        tires(400 + n).save(OUT / f"tires_{n}.png")
        grime(500 + n).save(OUT / f"grime_{n}.png")
        puddle(600 + n).save(OUT / f"puddle_{n}.png")
        streak(700 + n).save(OUT / f"streak_{n}.png")
    print(f"wrote 18 decals to {OUT}")


if __name__ == "__main__":
    main()
