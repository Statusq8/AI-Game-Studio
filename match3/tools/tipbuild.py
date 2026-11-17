#!/usr/bin/env python3
"""Окно подсказки «Новое: …» в общем стиле окон — из окна «Не хватает звёзд» (assets/art/nsref_window.webp):
звёзды и плашка стёрты, остаются рамка, синяя лента, крестик и панда, чешущая голову.

python3 tools/tipbuild.py → assets/art/tipref_window.webp (координаты как у nsref: левый верх = (0, 510) референса)
"""
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "assets", "art")
Y0 = 510


def main() -> None:
    im = np.asarray(Image.open(os.path.join(ART, "nsref_window.webp")).convert("RGBA")).astype(np.float32)
    rgb, a = im[..., :3], im[..., 3:]
    cream = np.median(rgb[1100 - Y0:1112 - Y0, 330:680].reshape(-1, 3), axis=0)
    m = np.zeros(rgb.shape[:2], np.float32)
    # звёзды с сиянием (x 230…660, y 740…1000) и плашка (x 285…720, y 992…1086) — в референсных координатах
    cv2.rectangle(m, (225, 735 - Y0), (665, 992 - Y0), 1.0, -1)
    cv2.rectangle(m, (282, 990 - Y0), (722, 1088 - Y0), 1.0, -1)
    # панду не трогаем: всё левее x 290 ниже y 940 оставляем
    m[940 - Y0:, :292] = 0
    # хвостик «облачка» плашки у головы панды
    cv2.rectangle(m, (271, 1016 - Y0), (296, 1058 - Y0), 1.0, -1)
    m = cv2.GaussianBlur(m, (0, 0), 4)
    rgb = rgb * (1 - m[..., None]) + cream * m[..., None]
    out = np.dstack([rgb, a]).clip(0, 255).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(ART, "tipref_window.webp"), quality=92, method=6)


if __name__ == "__main__":
    main()
