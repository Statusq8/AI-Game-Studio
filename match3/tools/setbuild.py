#!/usr/bin/env python3
"""Окно настроек 1:1 по референсу владельца (docs/games/match3/references/screen_11_settings.webp, 852×1846).

python3 tools/setbuild.py REF.webp
Выход (assets/art):
  setref_window.webp — окно (рамка, бирюзовая лента, крестик, 5 строк со значками, пустая плашка для строки
                       «Язык…», панда с ключом), переключатели стёрты. Левый верхний угол = (0, SET_Y0).
  setref_on.png, setref_off.png — переключатель «вкл» (строка 1) и «выкл» (строка 4).
Координаты продублированы в scripts/main.gd (SETREF_*) — менять вместе.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winbuild import OUT, hsv, window_mask  # noqa: E402
from shopbuild import rgba  # noqa: E402

SET_Y0, SET_Y1 = 186, 1690
BODY = (50, 404, 801, 1622, 85)
ARCH = (425, 316, 178, 58)
PAW = (425, 264, 47)
CLOSE = (747, 297, 52)
ROWS_Y = [504, 673, 843, 1012, 1181]        # верх переключателя в каждой строке
TOG_X = (528, 704)
TOG_H = 90
PANDA_BOX = (408, 1290, 830, 1690)


def toggle(im, h, s, v, x0, y0):
    sub = im[y0 - 2:y0 + TOG_H, x0:TOG_X[1]]
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    cream = (ss < 0.32) & (sv > 0.85) & (sh > 0.06) & (sh < 0.14)
    m = (~cream).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    m = ndi.binary_fill_holes(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    return sub, m


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im = np.asarray(src).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    yy, xx = np.mgrid[0:H, 0:W]
    meta = {}
    work = im.astype(np.float32)
    for name, row in (("on", 0), ("off", 3)):
        sub, m = toggle(im, h, s, v, TOG_X[0], ROWS_Y[row])
        rgba(sub, cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.8)).save(os.path.join(OUT, "setref_%s.png" % name))
    meta["toggle"] = [TOG_X[0], -2]
    # стираем переключатели: строки крема — копия того же ряда левее (x 330…500 — чистая середина строки)
    for y0 in ROWS_Y:
        sub, m = toggle(im, h, s, v, TOG_X[0], y0)
        mm = cv2.dilate(m.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool)
        ys, xs = np.where(mm)
        for y_, x_ in zip(ys, xs):
            Y, X = y0 - 2 + y_, TOG_X[0] + x_
            work[Y, X] = im[Y, 400 + (X % 60)]
    # панда с ключом
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in (((640, 1420), 50), ((640, 1560), 50), ((500, 1420), 20)):
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    yel = (h > 0.11) & (h < 0.18) & (s > 0.7) & (v > 0.85) & (xx > 405) & (xx < 480) & (yy > 1295) & (yy < 1370)
    panda = ndi.binary_fill_holes(cv2.morphologyEx((panda | yel).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    mask = window_mask(im, h, s, v, y0=190, body=BODY, arch=ARCH, paw=PAW, rib_y=262, top_end=520,
                       leaf_y=(1440, 1620), side_y=(404, 1450), ribbon_hue=(0.45, 0.56))
    mask = np.maximum(mask, cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[SET_Y0:SET_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "setref_window.webp"), quality=92, method=6)
    meta["window_y0"] = SET_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
