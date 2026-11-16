#!/usr/bin/env python3
"""Окно «Подарок дня» 1:1 по референсу владельца (docs/games/match3/references/screen_09_daily.webp, 852×1846).

python3 tools/dailybuild.py REF.webp
Выход (assets/art):
  dailyref_window.webp — окно (рамка, голубая лента, крестик, карточка 7-го дня с сундуком), без карточек 1–6 и
                         кнопки; левый низ (там панда) — зеркало правого. Левый верхний угол = (0, DAILY_Y0).
  dailyref_panda.png — панда с подарком (поверх всего), dailyref_card.png — пустая карточка дня с ярлычком
  (цифра стёрта), dailyref_coins.png — горка монет, dailyref_check.png — большая галочка,
  dailyref_ring.png — зелёная светящаяся рамка «сегодня», dailyref_take.png — кнопка «Забрать».
Значки бустеров — из магазина (shopref_ic_*). Координаты продублированы в scripts/main.gd (DAILYREF_*).
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

DAILY_Y0, DAILY_Y1 = 120, 1660
BODY = (52, 314, 799, 1648, 85)
ARCH = (425, 226, 178, 58)
PAW = (425, 174, 47)
CLOSE = (745, 216, 52)
CARD4 = (105, 713, 312, 968)               # тело карточки 4-го дня (образец пустой карточки)
TAB4 = (160, 694, 262, 752)                # ярлычок с номером дня
COINS5 = (340, 772, 512, 902)              # горка монет 5-го дня
CHECK1 = (168, 512, 278, 612)              # галочка 1-го дня
CARD3 = (526, 404, 760, 684)               # карточка «сегодня» с зелёной рамкой
TAKE = (258, 1380, 690, 1540)
PANDA_BOX = (0, 1296, 318, 1652)
CARDS_AREA = (100, 404, 757, 982)


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im0 = np.asarray(src).copy()
    H, W = im0.shape[:2]
    h0, s0, v0 = hsv(im0)
    yy, xx = np.mgrid[0:H, 0:W]
    meta = {}
    # ---- панда с подарком
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in (((140, 1450), 55), ((215, 1570), 50), ((95, 1385), 30)):
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    btn = (h0 > 0.2) & (h0 < 0.45) & (s0 > 0.5) & (xx > 255) & (yy < 1545)
    panda &= ~cv2.dilate(btn.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    panda &= ~((yy < 1362) & (xx > 255))       # край карточки 7-го дня
    panda &= ~((s0 < 0.35) & (v0 > 0.8) & (xx > 228) & (yy < 1445))   # крем окна правее головы
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    yel = (h0 > 0.11) & (h0 < 0.18) & (s0 > 0.7) & (v0 > 0.85) & (xx > 145) & (xx < 245) & (yy > 1300) & (yy < 1360)
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    ys, xs = np.where(panda)
    px0, py0, px1, py1 = max(0, xs.min() - 2), max(0, ys.min() - 2), xs.max() + 3, ys.max() + 3
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    rgba(im0[py0:py1, px0:px1], pa[py0:py1, px0:px1]).save(os.path.join(OUT, "dailyref_panda.png"))
    meta["panda"] = [int(px0), int(py0)]
    # ---- пустая карточка: тело (скруглённый прямоугольник) + ярлычок; внутри — ровный цвет, цифра стёрта
    bx0, by0, bx1, by1 = CARD4
    ox0, oy0 = bx0 - 4, TAB4[1] - 2
    ox1, oy1 = bx1 + 4, by1 + 6
    sub = im0[oy0:oy1, ox0:ox1].astype(np.float32)
    shp = sub.shape[:2]
    m = np.zeros(shp, np.float32)
    rr = 24
    L, T, R, B = bx0 - ox0, by0 - oy0, bx1 - ox0, by1 - oy0
    cv2.rectangle(m, (L, T + rr), (R, B - rr), 1.0, -1)
    cv2.rectangle(m, (L + rr, T), (R - rr, B), 1.0, -1)
    for cx, cy in ((L + rr, T + rr), (R - rr, T + rr), (L + rr, B - rr), (R - rr, B - rr)):
        cv2.circle(m, (cx, cy), rr, 1.0, -1)
    tx0, ty0, tx1, ty1 = TAB4
    tab = ((v0[ty0:ty1, tx0:tx1] < 0.62) | (s0[ty0:ty1, tx0:tx1] > 0.6)).astype(np.uint8)
    tab = ndi.binary_fill_holes(cv2.morphologyEx(tab, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(tab.astype(np.uint8))
    tab = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    tab = ndi.binary_fill_holes(tab)
    m[ty0 - oy0:ty1 - oy0, tx0 - ox0:tx1 - ox0] = np.maximum(m[ty0 - oy0:ty1 - oy0, tx0 - ox0:tx1 - ox0], tab)
    # цифра на ярлычке
    digit = np.zeros(shp, np.uint8)
    dg = (s0[ty0:ty1, tx0:tx1] < 0.3) & (v0[ty0:ty1, tx0:tx1] > 0.75)
    digit[ty0 - oy0:ty1 - oy0, tx0 - ox0:tx1 - ox0] = cv2.dilate(dg.astype(np.uint8), np.ones((5, 5), np.uint8))
    sub = cv2.inpaint(sub.clip(0, 255).astype(np.uint8), digit, 6, cv2.INPAINT_TELEA).astype(np.float32)
    inner = sub[ty1 - oy0 + 10:B - 14, L + 14:R - 14].reshape(-1, 3)
    ih, isat, iv = hsv(np.ascontiguousarray(inner.clip(0, 255).astype(np.uint8)[None]))
    pick = (isat[0] < 0.42) & (iv[0] > 0.8)
    base = np.median(inner[pick], axis=0)
    flat_fill(sub, (L + 12, ty1 - oy0 + 2, R - 12, B - 12), base, 10, radius=14)
    rgba(sub.clip(0, 255).astype(np.uint8), cv2.GaussianBlur(m * 255, (0, 0), 0.8)).save(os.path.join(OUT, "dailyref_card.png"))
    meta["card"] = [ox0, oy0, ox1 - ox0, oy1 - oy0, bx0, by0]
    # ---- горка монет
    cx0, cy0, cx1, cy1 = COINS5
    cm = ((s0[cy0:cy1, cx0:cx1] > 0.55) | (v0[cy0:cy1, cx0:cx1] < 0.6)).astype(np.uint8)
    cm = cv2.morphologyEx(cm, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(cm)
    cm = ndi.binary_fill_holes(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    rgba(im0[cy0:cy1, cx0:cx1], cv2.GaussianBlur(cm.astype(np.float32) * 255, (0, 0), 0.7)).save(os.path.join(OUT, "dailyref_coins.png"))
    meta["coins"] = [cx0, cy0]
    # ---- галочка
    kx0, ky0, kx1, ky1 = CHECK1
    km = ((h0[ky0:ky1, kx0:kx1] > 0.2) & (h0[ky0:ky1, kx0:kx1] < 0.45) & (s0[ky0:ky1, kx0:kx1] > 0.4)).astype(np.uint8)
    km = cv2.morphologyEx(km, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(km)
    km = ndi.binary_fill_holes(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    rgba(im0[ky0:ky1, kx0:kx1], cv2.GaussianBlur(km.astype(np.float32) * 255, (0, 0), 0.7)).save(os.path.join(OUT, "dailyref_check.png"))
    meta["check"] = [kx0, ky0]
    # ---- зелёная рамка «сегодня»
    rx0, ry0, rx1, ry1 = CARD3
    sub = im0[ry0:ry1, rx0:rx1]
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    g = np.clip((ss - 0.3) / 0.4, 0, 1) * ((sh > 0.18) & (sh < 0.42))
    rgba(sub, g * 255).save(os.path.join(OUT, "dailyref_ring.png"))
    meta["ring"] = [rx0, ry0]
    # ---- кнопка
    img, bb, _ = cut_button(im0, h0, s0, v0, TAKE)
    img.save(os.path.join(OUT, "dailyref_take.png"))
    meta["take"] = [int(c) for c in bb]
    # ---- окно
    im = im0.copy()
    xs_ = np.arange(0, 330)
    im[1290:, xs_] = im0[1290:, W - 1 - xs_]
    h, s, v = hsv(im)
    work = im.astype(np.float32)
    cream = np.median(im0[985:1000, 150:700].reshape(-1, 3), axis=0)
    flat_fill(work, CARDS_AREA, cream, 6)
    cream2 = np.median(im0[1562:1592, 330:560].reshape(-1, 3), axis=0)
    flat_fill(work, (W - 1 - bb[2] - 4, bb[1] - 4, bb[2] + 4, bb[3] + 6), cream2, 5)
    mask = window_mask(im, h, s, v, y0=125, body=BODY, arch=ARCH, paw=PAW, rib_y=201, top_end=440,
                       leaf_y=(1470, 1645), side_y=(314, 1480), ribbon_hue=(0.52, 0.64))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[DAILY_Y0:DAILY_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "dailyref_window.webp"), quality=92, method=6)
    meta["window_y0"] = DAILY_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
