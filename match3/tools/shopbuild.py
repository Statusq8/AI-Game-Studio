#!/usr/bin/env python3
"""Магазин 1:1 по референсу владельца (docs/games/match3/references/screen_07_shop.webp, 852×1846).

python3 tools/shopbuild.py REF.webp
Выход (assets/art):
  shopref_window.webp — окно (рамка, бирюзовая лента, крестик), без карточек и плашки монет; левый низ
                        (там стоит панда) — зеркало правого. Левый верхний угол слоя = (0, SHOP_Y0).
  shopref_panda.png — панда с корзинкой (рисуется поверх всего).
  shopref_card.png — пустая карточка, shopref_price.png — зелёная кнопка цены (число стёрто),
  shopref_badge.png — зелёный кружок количества (цифра стёрта), shopref_coins.png — плашка монет (число стёрто),
  shopref_ic_0..5.png — значки: молот, ракеты, микс, ракета, бомба, шар.
Координаты продублированы в scripts/main.gd (SHOP_*) — менять вместе.
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

SHOP_Y0, SHOP_Y1 = 100, 1652
BODY = (53, 302, 798, 1642, 80)
ARCH = (425, 214, 178, 58)
PAW = (425, 162, 47)
CLOSE = (731, 213, 52)
CARD = (128, 470, 415, 765)                 # первая карточка (левая верхняя)
CARD_STEP = (309.0, 322.5)                  # шаг сетки 2×3
PRICE = (148, 664, 394, 750)                # кнопка цены первой карточки
PRICE_TXT = (262, 680, 362, 732)            # «250» — стирается
BADGE = (340, 452, 414, 528)                # кружок количества первой карточки
COINS = (242, 334, 610, 442)                # плашка монет
COINS_TXT = (392, 352, 560, 420)            # «1250» — стирается
ICONS = [(190, 492, 362, 664), (492, 492, 668, 664), (186, 815, 364, 980),
         (496, 810, 664, 988), (186, 1125, 378, 1306), (492, 1130, 668, 1306)]
PANDA_BOX = (0, 1316, 362, 1754)


def rgba(img, alpha):
    return Image.fromarray(np.dstack([img, np.asarray(alpha).clip(0, 255)]).astype(np.uint8), "RGBA")


def erase_text(img_rgba, box_abs, origin):
    """Стирает белые цифры с тёмной обводкой внутри box_abs (координаты референса) у вырезанной картинки."""
    a = np.asarray(img_rgba).copy()
    rgb = np.ascontiguousarray(a[..., :3])
    _, ts, tv = hsv(rgb)
    x0, y0, x1, y1 = box_abs
    ox, oy = origin
    reg = (slice(y0 - oy, y1 - oy), slice(x0 - ox, x1 - ox))
    tm = np.zeros(rgb.shape[:2], np.uint8)
    tm[reg] = (((ts[reg] < 0.3) & (tv[reg] > 0.6)) | (tv[reg] < 0.35)).astype(np.uint8)
    tm = cv2.dilate(tm, np.ones((5, 5), np.uint8))
    a[..., :3] = cv2.inpaint(rgb, tm, 6, cv2.INPAINT_TELEA)
    return Image.fromarray(a, "RGBA")


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im0 = np.asarray(src).copy()
    H, W = im0.shape[:2]
    h0, s0, v0 = hsv(im0)
    meta = {}
    # ---- панда (из оригинала)
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    cv2.circle(pm, (130, 1450), 60, cv2.GC_FGD, -1)
    cv2.circle(pm, (180, 1620), 50, cv2.GC_FGD, -1)
    cv2.ellipse(pm, (125, 1385), (85, 35), 0, 0, 360, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    yel = (h0 > 0.11) & (h0 < 0.18) & (s0 > 0.7) & (v0 > 0.85)
    yel[:1310] = False
    yel[1390:] = False
    yel[:, 52:] = False
    panda |= yel
    # кнопка цены нижней левой карточки (за пандой) — не панда
    yy, xx = np.mgrid[0:H, 0:W]
    btn = (xx >= 150) & (yy < 1394) & ((((h0 > 0.2) & (h0 < 0.45) & (s0 > 0.5))) | ((s0 < 0.25) & (v0 > 0.8) & (xx > 255)))
    hat = ((xx - 130) / 125.0) ** 2 + ((yy - 1388) / 62.0) ** 2 < 1.0
    panda &= ~(cv2.dilate(btn.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool) & ~hat)
    green = (h0 > 0.2) & (h0 < 0.45) & (s0 > 0.5) & (yy < 1405) & (xx >= 150)
    panda &= ~cv2.dilate(green.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    panda &= ~((xx < 70) & (yy < 1395))  # тёмный фон у края экрана (жёлтые чёрточки добавляются ниже)
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    ys, xs = np.where(panda)
    px0, py0, px1, py1 = max(0, xs.min() - 2), max(0, ys.min() - 2), xs.max() + 3, ys.max() + 3
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    rgba(im0[py0:py1, px0:px1], pa[py0:py1, px0:px1]).save(os.path.join(OUT, "shopref_panda.png"))
    meta["panda"] = [int(px0), int(py0)]
    # ---- значки
    for i, (bx0, by0, bx1, by1) in enumerate(ICONS):
        m = np.zeros((H, W), np.uint8)
        light = (v0 > 0.82) & (s0 < 0.5)
        m[by0:by1, bx0:bx1] = np.where(light[by0:by1, bx0:bx1], cv2.GC_PR_BGD, cv2.GC_PR_FGD)
        bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
        cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), m, None, bgm, fgm, 6, cv2.GC_INIT_WITH_MASK)
        fg = ((m == cv2.GC_FGD) | (m == cv2.GC_PR_FGD)).astype(np.uint8)
        fg = cv2.morphologyEx(fg, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(fg)
        big = st[1:, cv2.CC_STAT_AREA].max()
        keep = [j for j in range(1, n) if st[j, cv2.CC_STAT_AREA] > big * 0.15]
        fg = ndi.binary_fill_holes(np.isin(lab, keep))
        ys, xs = np.where(fg)
        ix0, iy0, ix1, iy1 = xs.min() - 2, ys.min() - 2, xs.max() + 3, ys.max() + 3
        a = cv2.GaussianBlur(fg.astype(np.float32) * 255, (0, 0), 0.7)
        rgba(im0[iy0:iy1, ix0:ix1], a[iy0:iy1, ix0:ix1]).save(os.path.join(OUT, "shopref_ic_%d.png" % i))
        meta["ic_%d" % i] = [int(ix0), int(iy0)]
    # ---- пустая карточка (из первой): правый верх — зеркало левого (там кружок), внутри — гладкий крем
    cx0, cy0, cx1, cy1 = CARD
    cw, ch = cx1 - cx0, cy1 - cy0
    card = im0[cy0:cy1, cx0:cx1].copy()
    card[:ch // 2, cw - cw // 2:] = card[:ch // 2, :cw // 2][:, ::-1]
    cf = card.astype(np.float32)
    fill_rows(cf, (20, 18, cw - 20, ch - 18))
    cf[18:ch - 18, 20:cw - 20] = cv2.GaussianBlur(cf[18:ch - 18, 20:cw - 20], (0, 0), sigmaX=0.1, sigmaY=5)
    am = np.zeros((ch, cw), np.uint8)
    cv2.rectangle(am, (0, 32), (cw - 1, ch - 33), 255, -1)
    cv2.rectangle(am, (32, 0), (cw - 33, ch - 1), 255, -1)
    for cxx, cyy in ((32, 32), (cw - 33, 32), (32, ch - 33), (cw - 33, ch - 33)):
        cv2.circle(am, (cxx, cyy), 32, 255, -1)
    rgba(cf.clip(0, 255).astype(np.uint8), cv2.GaussianBlur(am.astype(np.float32), (0, 0), 0.8)).save(os.path.join(OUT, "shopref_card.png"))
    meta["card"] = [cx0, cy0, cw, ch]
    # ---- кнопка цены, кружок количества, плашка монет
    img, bb, _ = cut_button(im0, h0, s0, v0, PRICE)
    erase_text(img, PRICE_TXT, bb[:2]).save(os.path.join(OUT, "shopref_price.png"))
    meta["price"] = [int(c) for c in bb]
    bx0, by0, bx1, by1 = BADGE
    gr = (h0 > 0.2) & (h0 < 0.45) & (s0 > 0.45)
    gm = gr[by0:by1, bx0:bx1].astype(np.uint8)
    gm = ndi.binary_fill_holes(cv2.morphologyEx(gm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    n, lab, st, cen = cv2.connectedComponentsWithStats(gm.astype(np.uint8))
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    gm = lab == k
    ys, xs = np.where(gm)
    gcx, gcy, gr_ = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2, (xs.max() - xs.min()) / 2
    sub = im0[by0:by1, bx0:bx1].copy()
    yy, xx = np.mgrid[0:by1 - by0, 0:bx1 - bx0]
    d = np.sqrt((xx - gcx) ** 2 + (yy - gcy) ** 2)
    inner = (d < gr_ - 7).astype(np.uint8)
    sub = cv2.inpaint(sub, inner, 7, cv2.INPAINT_TELEA)
    blur = cv2.GaussianBlur(sub, (0, 0), 5)
    w = cv2.GaussianBlur(inner.astype(np.float32), (0, 0), 2)[..., None]
    sub = (sub * (1 - w) + blur * w).astype(np.uint8)
    rgba(sub, np.clip((gr_ + 0.5 - d) * 255, 0, 255)).save(os.path.join(OUT, "shopref_badge.png"))
    meta["badge"] = [round(bx0 + gcx - cx0, 1), round(by0 + gcy - cy0, 1)]
    img, bb, _ = cut_button(im0, h0, s0, v0, COINS)
    erase_text(img, COINS_TXT, bb[:2]).save(os.path.join(OUT, "shopref_coins.png"))
    meta["coins"] = [int(c) for c in bb]
    # ---- окно: левый низ — зеркало правого (там была панда), карточки и плашка стёрты
    im = im0.copy()
    im[1290:, :W // 2] = im0[1290:, W - W // 2:][:, ::-1][:, :W // 2] if W % 2 == 0 else im0[1290:, ::-1][:, :W // 2]
    h, s, v = hsv(im)
    work = im.astype(np.float32)
    fill_rows(work, (CARD[0] - 12, CARD[1] - 26, int(CARD[2] + CARD_STEP[0]) + 12, int(CARD[3] + 2 * CARD_STEP[1]) + 14))
    mask = window_mask(im, h, s, v, y0=104, body=BODY, arch=ARCH, paw=PAW, rib_y=191, top_end=420,
                       leaf_y=(1470, 1640), side_y=(300, 1480), ribbon_hue=(0.45, 0.56))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[SHOP_Y0:SHOP_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "shopref_window.webp"), quality=92, method=6)
    meta["window_y0"] = SHOP_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
