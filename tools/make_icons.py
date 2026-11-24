"""Generate legacy launcher PNGs (pre-API-26 launchers fall back to these)."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRAND = (30, 128, 255, 255)

# Same "J" glyph as app/res/drawable/ic_launcher_fg.xml, in a 0..108 space.
J_PATH = [(60, 30), (78, 30), (78, 70), (74, 82), (64, 90), (56, 90),
          (46, 86), (38, 75), (52, 70), (55, 78), (60, 78), (64, 72), (64, 30)]
FLAG = [(40, 38), (56, 26), (56, 36), (44, 45)]

for density, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                      ("xxhdpi", 144), ("xxxhdpi", 192)):
    scale = size / 108.0
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(size * 0.22)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=BRAND)
    draw.polygon([(x * scale, y * scale) for x, y in J_PATH], fill=(255, 255, 255, 255))
    draw.polygon([(x * scale, y * scale) for x, y in FLAG], fill=(255, 255, 255, 255))
    out_dir = os.path.join(ROOT, "app", "res", "mipmap-" + density)
    os.makedirs(out_dir, exist_ok=True)
    img.save(os.path.join(out_dir, "ic_launcher.png"))
print("icons written")
