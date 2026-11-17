#!/usr/bin/env python3
"""Атлас обычных фишек (оптимизация отрисовки): gem_0..5 в одной картинке с мягкой тенью под каждой.

python3 tools/gem_atlas.py → assets/art/gems_atlas.png
Одна картинка на все фишки — видеокарта рисует всё поле одной пачкой (раньше: картинка+тень у каждой фишки
отдельно, ~160 вызовов отрисовки). Клетка атласа CELL×CELL, фишка по центру в исходном размере
(большая сторона 192 px), тень — как раньше рисовалась кодом (Gem._draw).
"""
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
CELL = 240
N = 6


def main() -> None:
    atlas = Image.new("RGBA", (CELL * N, CELL), (0, 0, 0, 0))
    S = 192 / 0.94  # «size» фишки в пикселях картинки (box = 0.94 * size = 192)
    for i in range(N):
        g = Image.open(os.path.join(ART, "gem_%d.png" % i)).convert("RGBA")
        k = 192.0 / max(g.size)
        if k != 1.0:
            g = g.resize((round(g.width * k), round(g.height * k)), Image.LANCZOS)
        cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        sh = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
        d = ImageDraw.Draw(sh)
        cx, cy = CELL / 2 + 0.03 * S, CELL / 2 + 0.38 * S
        rx, ry = 0.36 * S, 0.36 * S * 0.32
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=(13, 31, 64, 72))
        sh = sh.filter(ImageFilter.GaussianBlur(3))
        cell.alpha_composite(sh)
        cell.alpha_composite(g, ((CELL - g.width) // 2, (CELL - g.height) // 2))
        atlas.paste(cell, (i * CELL, 0))
    atlas.save(os.path.join(ART, "gems_atlas.png"))


if __name__ == "__main__":
    main()
