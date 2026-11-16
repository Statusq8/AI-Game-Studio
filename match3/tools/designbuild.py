#!/usr/bin/env python3
"""Окно выбора дизайна 1:1 по референсу владельца (docs/games/match3/references/screen_08_design.webp, 852×1846).

python3 tools/designbuild.py REF.webp
Выход (assets/art):
  designref_window.webp — окно (рамка, малиновая лента, крестик), без карточек; правый низ (там стоит панда) —
                          зеркало левого. Левый верхний угол слоя = (0, DESIGN_Y0).
  designref_panda.png — панда с молотом (поверх всего), designref_card.png — пустая карточка,
  designref_ok.png — зелёная кнопка с галочкой, designref_cost.png — плашка цены со звездой (число стёрто).
Координаты продублированы в scripts/main.gd (DESIGN_*) — менять вместе.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winbuild import OUT, cut_button, fill_rows, hsv, window_mask  # noqa: E402
from shopbuild import erase_text, rgba  # noqa: E402

DESIGN_Y0, DESIGN_Y1 = 362, 1440
BODY = (50, 559, 801, 1428, 85)
ARCH = (425, 471, 178, 58)
PAW = (425, 419, 47)
CLOSE = (745, 475, 52)
CARD = (97, 773, 313, 1190)                 # первая карточка
CARD_STEP = 220.5
OK_BTN = (112, 1080, 302, 1172)
COST = (268, 628, 576, 738)
COST_TXT = (432, 646, 510, 716)
PANDA_BOX = (400, 1192, 762, 1604)


def flat_fill(a, box, color, feather, radius=0):
    """Заливает (скруглённый) прямоугольник одним цветом с мягким краем (feather px)."""
    x0, y0, x1, y1 = box
    m = np.zeros(a.shape[:2], np.float32)
    if radius:
        r = radius
        cv2.rectangle(m, (x0, y0 + r), (x1 - 1, y1 - r - 1), 1.0, -1)
        cv2.rectangle(m, (x0 + r, y0), (x1 - r - 1, y1 - 1), 1.0, -1)
        for cx, cy in ((x0 + r, y0 + r), (x1 - r - 1, y0 + r), (x0 + r, y1 - r - 1), (x1 - r - 1, y1 - r - 1)):
            cv2.circle(m, (cx, cy), r, 1.0, -1)
        m = cv2.GaussianBlur(m, (0, 0), feather / 2.5)
    else:
        m[y0:y1, x0:x1] = 1.0
        m = cv2.GaussianBlur(m, (0, 0), feather / 2.5)
        m[y0 + feather:y1 - feather, x0 + feather:x1 - feather] = 1.0
    a[:] = a * (1 - m[..., None]) + np.asarray(color, np.float32) * m[..., None]


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im0 = np.asarray(src).copy()
    H, W = im0.shape[:2]
    h0, s0, v0 = hsv(im0)
    meta = {}
    # ---- панда с молотом
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in (((640, 1300), 50), ((610, 1470), 60), ((470, 1290), 25)):
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    yy, xx = np.mgrid[0:H, 0:W]
    # кнопка с галочкой третьей карточки и кремовая карточка рядом — не панда
    panda &= ~((yy < 1196) & (xx < 760))
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    yel = (h0 > 0.11) & (h0 < 0.18) & (s0 > 0.7) & (v0 > 0.85) & (xx > 410) & (xx < 500) & (yy > 1195) & (yy < 1275)
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    ys, xs = np.where(panda)
    px0, py0, px1, py1 = max(0, xs.min() - 2), max(0, ys.min() - 2), xs.max() + 3, ys.max() + 3
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    rgba(im0[py0:py1, px0:px1], pa[py0:py1, px0:px1]).save(os.path.join(OUT, "designref_panda.png"))
    meta["panda"] = [int(px0), int(py0)]
    # ---- пустая карточка (из первой): внутри — гладкий крем (сияние рисует игра)
    cx0, cy0, cx1, cy1 = CARD
    cw, ch = cx1 - cx0, cy1 - cy0
    card = im0[cy0:cy1, cx0:cx1].copy()
    cf = card.astype(np.float32)
    flat_fill(cf, (9, 9, cw - 9, ch - 9), cf[ch - 22, cw // 2], 5, radius=24)
    rr = 30
    am = np.zeros((ch, cw), np.uint8)
    cv2.rectangle(am, (0, rr), (cw - 1, ch - rr - 1), 255, -1)
    cv2.rectangle(am, (rr, 0), (cw - rr - 1, ch - 1), 255, -1)
    for cxx, cyy in ((rr, rr), (cw - rr - 1, rr), (rr, ch - rr - 1), (cw - rr - 1, ch - rr - 1)):
        cv2.circle(am, (cxx, cyy), rr, 255, -1)
    rgba(cf.clip(0, 255).astype(np.uint8), cv2.GaussianBlur(am.astype(np.float32), (0, 0), 0.8)).save(os.path.join(OUT, "designref_card.png"))
    meta["card"] = [cx0, cy0, cw, ch]
    img, bb, _ = cut_button(im0, h0, s0, v0, OK_BTN)
    img.save(os.path.join(OUT, "designref_ok.png"))
    meta["ok"] = [int(c) for c in bb]
    img, bb, _ = cut_button(im0, h0, s0, v0, COST)
    erase_text(img, COST_TXT, bb[:2]).save(os.path.join(OUT, "designref_cost.png"))
    meta["cost"] = [int(c) for c in bb]
    # ---- окно: правый низ — зеркало левого (там панда), карточки стёрты
    im = im0.copy()
    xs_ = np.arange(W // 2, W)
    im[1180:, xs_] = im0[1180:, W - 1 - xs_]
    # середина (молот панды заходит левее центра): низ рамки — копия столбца x=300, выше — крем
    im[1395:, 380:472] = im0[1395:, 300:301]
    cream0 = np.median(im0[1215:1250, 120:380].reshape(-1, 3), axis=0)
    imf = im.astype(np.float32)
    flat_fill(imf, (380, 1180, 472, 1395), cream0, 6)
    im = imf.clip(0, 255).astype(np.uint8)
    h, s, v = hsv(im)
    work = im.astype(np.float32)
    cream = np.median(im0[1215:1250, 120:380].reshape(-1, 3), axis=0).astype(np.float32)
    flat_fill(work, (CARD[0] - 10, CARD[1] - 12, int(CARD[2] + 2 * CARD_STEP) + 10, CARD[3] + 14), cream, 8)
    mask = window_mask(im, h, s, v, y0=366, body=BODY, arch=ARCH, paw=PAW, rib_y=452, top_end=690,
                       leaf_y=(1260, 1425), side_y=(560, 1270), ribbon_hue=(0.8, 0.96))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[DESIGN_Y0:DESIGN_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "designref_window.webp"), quality=92, method=6)
    meta["window_y0"] = DESIGN_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
