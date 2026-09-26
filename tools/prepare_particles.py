"""Alpha versions of the Kenney Particle Pack textures.

The pack ships white shapes on opaque black. Its "black" isn't fully black,
so even additive sprites show square edges, and smoke, dust, and scorch marks
need real transparency. This writes <name>_alpha.png with white color and
alpha taken from brightness; all effects use these.

Re-run after adding textures:  python tools/prepare_particles.py
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PARTICLES = ROOT / "assets/kenney/particles"
NAMES = ["smoke_01", "smoke_04", "smoke_07", "dirt_02", "scorch_01", "scorch_02", "scorch_03", "circle_05",
         "fire_01", "fire_02", "flame_03", "muzzle_02"]
SIZE = 256


def main():
    for name in NAMES:
        rgb = np.asarray(Image.open(PARTICLES / f"{name}.png").convert("RGB"), dtype=np.float32)
        alpha = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        out = np.zeros(rgb.shape[:2] + (4,), dtype=np.uint8)
        out[..., :3] = 255
        out[..., 3] = np.clip(alpha, 0, 255).astype(np.uint8)
        Image.fromarray(out).resize((SIZE, SIZE), Image.LANCZOS).save(PARTICLES / f"{name}_alpha.png", optimize=True)
    print(f"wrote {len(NAMES)} alpha textures to {PARTICLES}")


if __name__ == "__main__":
    main()
