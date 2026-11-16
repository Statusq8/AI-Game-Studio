#!/usr/bin/env python3
"""Окно «Сундук побед» 1:1 по референсу владельца (docs/games/match3/references/screen_10_chest.webp, 852×1846).

python3 tools/chestbuild.py REF.webp
Выход (assets/art):
  chestref_window.webp — окно (рамка, фиолетовая лента, крестик, большой сундук, плашка наград «150 и ? ?»),
                         полоска побед пустая (8 бежевых клеток), без кнопки; левый низ (там панда) — зеркало правого.
                         Левый верхний угол = (0, CHEST_Y0).
  chestref_panda.png — панда с кубком (поверх всего), chestref_seg.png — зелёная клетка полоски,
  chestref_btn.png — пустая зелёная кнопка (надпись пишет игра).
Координаты продублированы в scripts/main.gd (CHESTREF_*) — менять вместе.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winbuild import OUT, cut_button, hsv, window_mask  # noqa: E402
from shopbuild import rgba  # noqa: E402
from designbuild import flat_fill  # noqa: E402

CHEST_Y0, CHEST_Y1 = 286, 1596
BODY = (50, 479, 801, 1583, 85)
ARCH = (425, 391, 178, 58)
PAW = (425, 339, 47)
CLOSE = (747, 385, 52)
SEG_X0, SEG_P = 131.0, 59.6                # первая клетка полоски и шаг (8 клеток)
BAR = (128, 918, 428, 970)                 # зелёная часть полоски (5 клеток) → пустые
EMPTY_X = 430                              # начало 6-й (пустой) клетки — образец
BTN = (332, 1290, 728, 1436)
PANDA_BOX = (0, 1248, 348, 1652)


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im0 = np.asarray(src).copy()
    H, W = im0.shape[:2]
    h0, s0, v0 = hsv(im0)
    yy, xx = np.mgrid[0:H, 0:W]
    meta = {}
    # ---- панда с кубком
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in (((120, 1350), 50), ((130, 1560), 50), ((260, 1420), 35)):
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    cv2.ellipse(pm, (105, 1300), (75, 26), -15, 0, 360, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    panda &= ~((yy < 1240) & (xx > 0))
    btn = (h0 > 0.2) & (h0 < 0.45) & (s0 > 0.5) & (xx > 335) & (yy < 1440)
    panda &= ~cv2.dilate(btn.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    yel = (h0 > 0.11) & (h0 < 0.18) & (s0 > 0.7) & (v0 > 0.85) & (xx > 215) & (xx < 310) & (yy > 1255) & (yy < 1325)
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    ys, xs = np.where(panda)
    px0, py0, px1, py1 = max(0, xs.min() - 2), max(0, ys.min() - 2), xs.max() + 3, ys.max() + 3
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    rgba(im0[py0:py1, px0:px1], pa[py0:py1, px0:px1]).save(os.path.join(OUT, "chestref_panda.png"))
    meta["panda"] = [int(px0), int(py0)]
    # ---- зелёная клетка (3-я) с краями
    bx0, by0, bx1, by1 = BAR
    sx0 = int(SEG_X0 + 2 * SEG_P) - 3
    sx1 = int(SEG_X0 + 3 * SEG_P) + 2
    seg = im0[by0:by1, sx0:sx1].astype(int)
    gm = ((seg[..., 1] > seg[..., 0] + 25) & (seg[..., 1] > seg[..., 2] + 40)).astype(np.float32) * 255
    gm = cv2.GaussianBlur(gm, (0, 0), 0.6)
    rgba(seg.astype(np.uint8), gm).save(os.path.join(OUT, "chestref_seg.png"))
    meta["seg"] = [sx0, by0]
    # ---- кнопка
    img, bb, _ = cut_button(im0, h0, s0, v0, BTN)
    img.save(os.path.join(OUT, "chestref_btn.png"))
    meta["btn"] = [int(c) for c in bb]
    # ---- окно
    im = im0.copy()
    xs_ = np.arange(0, 348)
    im[1240:, xs_] = im0[1240:, W - 1 - xs_]
    for y in range(by0, by1):
        for x in range(bx0, bx1):
            off = (x - SEG_X0) % SEG_P
            im[y, x] = im0[y, int(round(EMPTY_X + off))]
    h, s, v = hsv(im)
    work = im.astype(np.float32)
    cream = np.median(im0[1450:1520, 380:680].reshape(-1, 3), axis=0)
    flat_fill(work, (W - 1 - bb[2] - 4, bb[1] - 5, bb[2] + 5, bb[3] + 7), cream, 6)
    mask = window_mask(im, h, s, v, y0=290, body=BODY, arch=ARCH, paw=PAW, rib_y=368, top_end=610,
                       leaf_y=(1400, 1580), side_y=(479, 1420), ribbon_hue=(0.72, 0.86))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[CHEST_Y0:CHEST_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "chestref_window.webp"), quality=92, method=6)
    meta["window_y0"] = CHEST_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
