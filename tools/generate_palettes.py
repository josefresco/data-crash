"""Roof-color variants of the Kenney City Kit (Suburban) palette texture.

The kit's houses sample their roofs from the green swatch at the top-left of
colormap.png. Each variant repaints that swatch (keeping its vertical shading)
so houses can get different roof colors from one set of models.

Output: assets/kenney/suburban/Textures/colormap_roof_<n>.png
Re-run after changing ROOFS:  python tools/generate_palettes.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TEXTURES = ROOT / "assets/kenney/suburban/Textures"
# Roof swatch (x0, y0, x1, y1) in the 512 px palette.
ROOF = (0, 128, 64, 256)
ROOFS = [
    (0.55, 0.27, 0.2),   # terracotta
    (0.32, 0.34, 0.38),  # slate
    (0.42, 0.3, 0.22),   # brown shingle
    (0.3, 0.38, 0.5),    # blue-gray
    (0.5, 0.45, 0.4),    # weathered gray
]


def main():
    base = np.asarray(Image.open(TEXTURES / "colormap.png").convert("RGBA"), dtype=np.float32)
    x0, y0, x1, y1 = ROOF
    swatch = base[y0:y1, x0:x1, :3]
    luma = swatch @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    shade = (luma / max(float(luma.max()), 1.0))[..., None]
    for index, color in enumerate(ROOFS):
        out = base.copy()
        out[y0:y1, x0:x1, :3] = np.clip(np.array(color, dtype=np.float32) * 255.0 * (0.55 + 0.6 * shade), 0, 255)
        Image.fromarray(out.astype(np.uint8)).save(TEXTURES / f"colormap_roof_{index}.png", optimize=True)
    print(f"wrote {len(ROOFS)} roof palettes to {TEXTURES}")


if __name__ == "__main__":
    main()
