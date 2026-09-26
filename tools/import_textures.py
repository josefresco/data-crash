"""Download CC0 PBR textures from ambientCG into assets/ambientcg/.

For each material ID this keeps the 1K color, OpenGL normal, and roughness
maps. If the set has an opacity map, it is merged into the color map's alpha
channel (color.png) for alpha-scissor cutouts like chain-link fences.

Re-run after changing MATERIALS:
  python tools/import_textures.py
  <godot> --headless --path . --import
  python tools/import_textures.py --fix-imports   # 3D flags a headless import can't detect
  <godot> --headless --path . --import
Source and license: https://ambientcg.com (CC0 1.0)
"""
import io
import re
import sys
import urllib.request
import zipfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/ambientcg"
MATERIALS = [
    "Grass004",            # lush lawn (restored)
    "Ground037",           # patchy dry grass and dirt (polluted)
    "Ground054",           # bare dirt (construction site)
    "Asphalt031",          # roads
    "Concrete034",         # sidewalks, barricades, pads
    "CorrugatedSteel005",  # datacenter cladding
    "MetalPlates006",      # turrets, turbines, industrial kit
    "SolarPanel003",       # solar arrays
    "Fence006",            # chain-link (has opacity)
]
MAPS = {"Color": "color", "NormalGL": "normal", "Roughness": "roughness"}


def fetch(material_id):
    url = f"https://ambientcg.com/get?file={material_id}_1K-JPG.zip"
    request = urllib.request.Request(url, headers={"User-Agent": "data-crash-texture-import"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return zipfile.ZipFile(io.BytesIO(response.read()))


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for material_id in MATERIALS:
        archive = fetch(material_id)
        folder = OUT / material_id
        folder.mkdir(exist_ok=True)
        names = archive.namelist()
        opacity = next((n for n in names if n.endswith("_Opacity.jpg")), None)
        for suffix, short in MAPS.items():
            source = next((n for n in names if n.endswith(f"_{suffix}.jpg")), None)
            if source is None:
                continue
            image = Image.open(io.BytesIO(archive.read(source)))
            if short == "color" and opacity:
                alpha = Image.open(io.BytesIO(archive.read(opacity))).convert("L")
                image = image.convert("RGB")
                image.putalpha(alpha)
                image.save(folder / "color.png", optimize=True)
            else:
                image.convert("RGB").save(folder / f"{short}.jpg", quality=90)
        print(f"{material_id}: {sorted(p.name for p in folder.iterdir())}")
    (OUT / "LICENSE.txt").write_text(
        "Textures from ambientCG (https://ambientcg.com), released under CC0 1.0 Universal.\n",
        encoding="utf-8")


def fix_imports():
    """Mipmaps + VRAM compression for 3D use, and flag normal maps as such."""
    for path in OUT.glob("*/*.import"):
        text = path.read_text(encoding="utf-8")
        text = re.sub(r"compress/mode=\d", "compress/mode=2", text)
        text = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", text)
        text = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", text)
        if path.name == "normal.jpg.import":
            text = re.sub(r"compress/normal_map=\d", "compress/normal_map=1", text)
        path.write_text(text, encoding="utf-8", newline="\n")
    print("patched import settings")


if __name__ == "__main__":
    if "--fix-imports" in sys.argv:
        fix_imports()
    else:
        main()
