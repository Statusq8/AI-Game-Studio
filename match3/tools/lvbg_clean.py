#!/usr/bin/env python3
"""Фон экрана уровня без нарисованной рамки поля (поле крупнее и с обводкой по форме, как в Royal Match).

python3 tools/lvbg_clean.py  — assets/art/lvref_bg.webp → assets/art/lvref_bg_open.webp
Панель рамки (x 50…790, y 405…1305 и листья по углам) заменяется гладким продолжением сцены
(заливка по краям на уменьшенной копии + размытие); под полем её почти не видно, в дырах фигурного поля
видна мягко размытая сцена, как глубина резкости.
"""
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
PANEL = (44, 398, 796, 1312)


def main() -> None:
    im = np.asarray(Image.open(os.path.join(ART, "lvref_bg.webp")).convert("RGB")).copy()
    H, W = im.shape[:2]
    m = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANEL
    cv2.rectangle(m, (x0, y0), (x1, y1), 255, -1)
    # листья по углам рамки
    for cx, cy in ((x0 + 20, y0 + 10), (x1 - 20, y0 + 10), (x0 + 20, y1 - 10), (x1 - 20, y1 - 10)):
        cv2.circle(m, (cx, cy), 50, 255, -1)
    f = 4
    small = cv2.resize(im, (W // f, H // f), interpolation=cv2.INTER_AREA)
    ms = cv2.resize(m, (W // f, H // f), interpolation=cv2.INTER_NEAREST)
    fill = cv2.inpaint(small, ms, 12, cv2.INPAINT_TELEA)
    fill = cv2.GaussianBlur(fill, (0, 0), 6)
    fill = cv2.resize(fill, (W, H), interpolation=cv2.INTER_CUBIC)
    a = cv2.GaussianBlur(m.astype(np.float32) / 255.0, (0, 0), 6)[..., None]
    out = (im * (1 - a) + fill * a).clip(0, 255).astype(np.uint8)
    Image.fromarray(out).save(os.path.join(ART, "lvref_bg_open.webp"), quality=90, method=6)


if __name__ == "__main__":
    main()
