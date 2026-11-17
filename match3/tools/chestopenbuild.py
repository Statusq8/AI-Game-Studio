#!/usr/bin/env python3
"""Окно «Сундук открыт!» 1:1 по референсу владельца (docs/games/match3/references/screen_14_chestopen.webp, 852×1846).
Рамка здесь другая (прямоугольная, без арки) — маска окна по GrabCut, а не window_mask().

python3 tools/nostarsbuild.py REF.webp
Выход (assets/art): coref_window.webp (окно со звёздами, плашкой и пандой, без кнопки; левый верх = (0, NS_Y0)),
  coref_btn.png — пустая зелёная кнопка. Координаты продублированы в scripts/main.gd (NSREF_*).
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winbuild import OUT, cut_button, hsv  # noqa: E402
from designbuild import flat_fill  # noqa: E402

NS_Y0, NS_Y1 = 362, 1402
OUTER = (6, 366, 846, 1400)
CORE = (60, 450, 790, 1380)
BTN = (116, 1216, 502, 1346)


def main() -> None:
    im = np.asarray(Image.open(sys.argv[1]).convert("RGB")).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    img, bb, _ = cut_button(im, h, s, v, BTN)
    img.save(os.path.join(OUT, "coref_btn.png"))
    m = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = OUTER
    m[y0:y1, x0:x1] = cv2.GC_PR_FGD
    cx0, cy0, cx1, cy1 = CORE
    m[cy0:cy1, cx0:cx1] = cv2.GC_FGD
    # фон наверняка: углы вне листьев
    # фон наверняка: над рамкой (лучи и конфетти) и под ней
    m[y0:405, 200:360] = cv2.GC_BGD
    m[y0:405, 500:640] = cv2.GC_BGD
    m[1392:y1, 200:640] = cv2.GC_BGD
    m[:, :40][m[:, :40] == cv2.GC_PR_FGD] = cv2.GC_PR_BGD
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), m, None, bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    fg = ((m == cv2.GC_FGD) | (m == cv2.GC_PR_FGD)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(fg)
    fg = ndi.binary_fill_holes(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    work = im.astype(np.float32)
    cream = np.median(im[1200:1212, 150:450].reshape(-1, 3), axis=0)
    flat_fill(work, (bb[0] - 4, bb[1] - 4, bb[2] + 4, bb[3] + 6), cream, 6)
    a = cv2.GaussianBlur(fg.astype(np.float32) * 255, (0, 0), 1.0)
    out = np.dstack([work.clip(0, 255), a]).astype(np.uint8)[NS_Y0:NS_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "coref_window.webp"), quality=92, method=6)
    print(json.dumps({"btn": [int(c) for c in bb], "window_y0": NS_Y0}))


if __name__ == "__main__":
    main()
