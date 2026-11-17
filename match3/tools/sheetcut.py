#!/usr/bin/env python3
"""Единый набор графики (одна генерация владельца, docs/games/match3/references/art_sheet_v1.webp, сетка 5×4 на белом).

python3 tools/sheetcut.py SHEET → assets/art/<имя>.png для каждого предмета (имена — NAMES по рядам).
Фон убирается заливкой от краёв по «почти белому», предметы в клетке сетки склеиваются (искра у фитиля и т. п.),
края сглаживаются. Фишки и бонусы — большая сторона 192 px, препятствия и плитки — 160 px.
После: python3 tools/gem_atlas.py (атлас фишек).
"""
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
NAMES = [
    ["gem_0", "gem_1", "gem_2", "gem_3", "gem_4"],
    ["gem_5", "rocket", "bomb", "propeller", "orb"],
    ["ob_crate_0", "ob_crate_1", "ob_crate_2", "ob_pot_0", "ob_pot_1"],
    ["ob_vines", "ob_tile_ice", "ob_tile_grass", "lv_tile_a", "lv_tile_b"],
]
BIG = {"gem_0", "gem_1", "gem_2", "gem_3", "gem_4", "gem_5", "rocket", "bomb", "propeller", "orb"}


def main() -> None:
    im = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.int16)
    H, W = im.shape[:2]
    # фон: почти белый и связанный с краем картинки
    white = (np.abs(im - 255).max(axis=2) < 40).astype(np.uint8)
    lab, n = ndi.label(white)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    fg = ~bg
    fg = ndi.binary_opening(fg, iterations=1)
    lab2, n2 = ndi.label(fg)
    sizes = ndi.sum(fg, lab2, range(1, n2 + 1))
    rows, cols = len(NAMES), len(NAMES[0])
    groups = {}
    for i, s in enumerate(sizes, start=1):
        if s < 60:
            continue
        ys, xs = np.where(lab2 == i)
        r = min(rows - 1, int(ys.mean() / (H / rows)))
        c = min(cols - 1, int(xs.mean() / (W / cols)))
        groups.setdefault((r, c), []).append(i)
    rgb = im.astype(np.uint8)
    for (r, c), ids in sorted(groups.items()):
        m = np.isin(lab2, ids)
        m = ndi.binary_fill_holes(m)
        # срезаем 3 px края: там светлая кайма от белого фона
        m = ndi.binary_erosion(m, iterations=3)
        ys, xs = np.where(m)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        a = cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.8)
        # светлая кайма от белого фона на краю: слегка затемняем полупрозрачные пиксели
        crop = np.dstack([rgb[y0:y1, x0:x1], a[y0:y1, x0:x1].clip(0, 255).astype(np.uint8)])
        img = Image.fromarray(crop, "RGBA")
        name = NAMES[r][c]
        side = 192 if name in BIG else 160
        k = side / max(img.size)
        img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
        img.save(os.path.join(ART, name + ".png"))
        print(name, img.size)


if __name__ == "__main__":
    main()
