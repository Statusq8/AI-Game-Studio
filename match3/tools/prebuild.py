#!/usr/bin/env python3
"""Окно перед уровнем 1:1 по референсу владельца (docs/games/match3/references/screen_05_prelevel.webp, 852×1846).

python3 tools/prebuild.py REF.webp
Выход (assets/art):
  preref_window.webp — окно (рамка, зелёная лента, крестик, выглядывающая панда, пустые плашки), фон прозрачный;
                       стёрты: цели с числами и перегородками, дорожка серии побед, плитки бустеров, кнопка.
                       Левый верхний угол слоя = (0, PRE_Y0) референса.
  preref_flame.png, preref_bar.png (кусок пустого жёлоба), preref_fill.png (кусок оранжевой заливки),
  preref_mark_on.png / preref_mark_off.png — кружки 3/5/8/10 без цифр (горит / не горит),
  preref_tile.png — пустая деревянная плитка бустера, preref_ic_rocket/bomb/orb.png — значки бустеров,
  preref_sel.png — зелёная светящаяся рамка выбранной плитки, preref_check.png — зелёный кружок с галочкой,
  preref_count.png — зелёный кружок количества без цифры, preref_play.png — кнопка «Играть».
Координаты продублированы в scripts/main.gd (PRE_*) — менять вместе.
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

PRE_Y0, PRE_Y1 = 180, 1608
BODY = (48, 617, 803, 1593, 90)
ARCH = (425, 529, 178, 58)
PAW = (425, 477, 47)
PANDA_BOX = (45, 185, 470, 545)
PANDA_KEEP = (452, 482)                    # от панды в окне остаётся низ: плавно с 452 до 482
PLATE_IN = (162, 724, 690, 938)            # внутренность плашки целей
INNER = (101, 948, 747, 1420)              # дорожка серии побед, плитки, кнопка — стирается целиком
FLAME = (100, 940, 200, 1076)
MARK_ON_C = (337.0, 1004.0, 33.0)        # кружок «3» (горит): центр, радиус
MARK_OFF_C = (455.0, 1003.5, 30.0)       # кружок «5» (не горит)
BAR_TILE = (495, 535)                      # x-кусок пустого жёлоба
FILL_TILE = (220, 280)                     # x-кусок оранжевой заливки
CAP_X = (368, 390)                         # скруглённый конец заливки
TILES = [(110, 1098, 322, 1312), (330, 1098, 530, 1312), (535, 1098, 735, 1312)]
TILE_PANEL = (102, 1086, 750, 1324)        # светлая подложка плиток (её не трогаем, стираем только плитки)
ICONS = [(145, 1135, 305, 1300), (355, 1125, 505, 1285), (555, 1140, 705, 1292)]
CHECK = (255, 1090, 325, 1160)
COUNT = (462, 1088, 535, 1160)
PLAY = (168, 1328, 684, 1494)
CLOSE = (760, 553, 57)                     # красный крестик (остаётся в окне, игра кладёт поверх кнопку)


def rgba(img, alpha):
    return Image.fromarray(np.dstack([img, alpha.clip(0, 255)]).astype(np.uint8), "RGBA")


def circle_cut(im, box, sel):
    """Кружок из box: маска sel (bool) → самая большая область, дыры залиты; возврат (картинка, центр, bbox)."""
    x0, y0, x1, y1 = box
    m = sel[y0:y1, x0:x1].astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, cen = cv2.connectedComponentsWithStats(m)
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    m = ndi.binary_fill_holes(lab == k).astype(np.uint8)
    return m


def inpaint_inner(sub, cx, cy, r):
    yy, xx = np.mgrid[0:sub.shape[0], 0:sub.shape[1]]
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    inner = (d < r).astype(np.uint8)
    out = cv2.inpaint(np.ascontiguousarray(sub), inner, 7, cv2.INPAINT_TELEA)
    blur = cv2.GaussianBlur(out, (0, 0), 5)
    w = cv2.GaussianBlur(inner.astype(np.float32), (0, 0), 2)[..., None]
    return (out * (1 - w) + blur * w).astype(np.uint8)


def grab(im, box, iters=6, smax=0.66):
    """Значок на деревянной плитке: дерево (рыже-бурое, неяркое) — фон, остальное — значок."""
    x0, y0, x1, y1 = box
    h, s, v = hsv(im)
    mask = np.zeros(im.shape[:2], np.uint8)
    wood = (h > 0.04) & (h < 0.13) & (s > 0.25) & (s < smax) & (v > 0.55)
    reg = np.where(wood, cv2.GC_PR_BGD, cv2.GC_PR_FGD).astype(np.uint8)
    mask[y0:y1, x0:x1] = reg[y0:y1, x0:x1]
    bg = np.zeros((1, 65)); fg = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), mask, None, bg, fg, iters, cv2.GC_INIT_WITH_MASK)
    return ((mask == cv2.GC_FGD) | (mask == cv2.GC_PR_FGD))


def save_cut(name, im, m, pad=2, blur=0.8):
    ys, xs = np.where(m)
    x0, y0, x1, y1 = xs.min() - pad, ys.min() - pad, xs.max() + 1 + pad, ys.max() + 1 + pad
    a = cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), blur)
    rgba(im[y0:y1, x0:x1], a[y0:y1, x0:x1]).save(os.path.join(OUT, name))
    return [int(x0), int(y0), int(x1 - x0), int(y1 - y0)]


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im = np.asarray(src).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    meta = {}
    work = im.copy()
    # ---- панда: GrabCut по подсказкам (голова, лапа — точно панда), + шляпная лапка, + жёлтые чёрточки
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_BGD
    cv2.ellipse(pm, (230, 370), (150, 150), 0, 0, 360, cv2.GC_PR_FGD, -1)
    cv2.ellipse(pm, (220, 330), (80, 60), 0, 0, 360, cv2.GC_FGD, -1)
    cv2.ellipse(pm, (395, 345), (30, 40), 0, 0, 360, cv2.GC_FGD, -1)
    cv2.circle(pm, (200, 220), 30, cv2.GC_FGD, -1)
    cv2.circle(pm, (380, 300), 16, cv2.GC_FGD, -1)
    bg = np.zeros((1, 65)); fg = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), pm, None, bg, fg, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    yel = (h > 0.11) & (h < 0.18) & (s > 0.7) & (v > 0.85)
    yel[:, :335] = False
    yel[:, 445:] = False
    yel[:195] = False
    yel[300:] = False
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    # ---- цели: плашка пустая
    px0, py0, px1, py1 = PLATE_IN
    for y in range(py0, py1):
        lc = im[y, px0 - 3:px0].astype(np.float32).mean(axis=0)
        rc = im[y, px1:px1 + 3].astype(np.float32).mean(axis=0)
        t = np.linspace(0, 1, px1 - px0)[:, None]
        work[y, px0:px1] = (lc * (1 - t) + rc * t).astype(np.uint8)
    # ---- дорожка серии побед
    fl = (s > 0.45) & (v > 0.35)
    fm = circle_cut(im, FLAME, fl)
    full = np.zeros((H, W), bool)
    full[FLAME[1]:FLAME[3], FLAME[0]:FLAME[2]] = fm
    meta["flame"] = save_cut("preref_flame.png", im, full)
    for name, (mx, my, mr) in (("mark_on", MARK_ON_C), ("mark_off", MARK_OFF_C)):
        x0, y0 = int(mx - mr - 3), int(my - mr - 3)
        sz = int(mr * 2 + 7)
        sub = im[y0:y0 + sz, x0:x0 + sz].copy()
        cx, cy = mx - x0, my - y0
        sub = inpaint_inner(sub, cx, cy, mr - 9)
        yy, xx = np.mgrid[0:sz, 0:sz]
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        a = np.clip((mr + 0.5 - d) * 255, 0, 255).astype(np.float32)
        rgba(sub, a).save(os.path.join(OUT, "preref_%s.png" % name))
        meta[name] = [x0, y0, sz]
    # жёлоб и заливка: столбец x=510 / 250 — высота по насыщенности
    def strip(name, xa, xb):
        col = (s[:, (xa + xb) // 2] > 0.4) & (v[:, (xa + xb) // 2] < 0.97)
        ys = np.where(col[985:1050])[0] + 985
        ya, yb = int(ys.min()) - 1, int(ys.max()) + 2
        a = np.zeros((yb - ya, xb - xa), np.float32) + 255
        a[0] = 128
        a[-1] = 128
        rgba(im[ya:yb, xa:xb], a).save(os.path.join(OUT, name))
        return [xa, ya, xb - xa, yb - ya]
    meta["bar"] = strip("preref_bar.png", *BAR_TILE)
    meta["fill"] = strip("preref_fill.png", *FILL_TILE)
    # скруглённый конец заливки (справа от «3»): только оранжевое, жёлоб под ним рисует игра
    fa, fb_ = meta["fill"][1], meta["fill"][1] + meta["fill"][3]
    cap = im[fa:fb_, CAP_X[0]:CAP_X[1]]
    ch, cs, cv = hsv(np.ascontiguousarray(cap))
    cm = ((ch > 0.02) & (ch < 0.13) & (cs > 0.6) & (cv > 0.75)).astype(np.float32) * 255
    rgba(cap, cv2.GaussianBlur(cm, (0, 0), 0.7)).save(os.path.join(OUT, "preref_fillcap.png"))
    meta["fillcap"] = [CAP_X[0], fa]
    # ---- бустеры
    tile_sel = []
    for i, box in enumerate(TILES):
        x0, y0, x1, y1 = box
        m = ((s[y0:y1, x0:x1] > 0.45) & (v[y0:y1, x0:x1] < 0.9)) | (v[y0:y1, x0:x1] < 0.6)
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(m)
        k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        tile_sel.append([int(x0 + st[k, 0]), int(y0 + st[k, 1]), int(st[k, 2]), int(st[k, 3])])
    meta["tiles_bbox"] = tile_sel
    # пустая плитка: из плитки радужного шара — правый верх (под кружком) — зеркало левого верха,
    # внутренность (шар) — построчно между чистыми краями
    bx, by, bw, bh = tile_sel[2]
    tile = im[by:by + bh, bx:bx + bw].copy()
    sv_ = s[by:by + bh, bx:bx + bw]
    vv_ = v[by:by + bh, bx:bx + bw]
    tmask = ndi.binary_fill_holes(cv2.morphologyEx((((sv_ > 0.45) & (vv_ < 0.9)) | (vv_ < 0.6)).astype(np.uint8),
                                                   cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8)))
    hw = bw // 2
    tile[:, bw - hw:] = tile[:, :hw][:, ::-1]
    tmask[:, bw - hw:] = tmask[:, :hw][:, ::-1]
    ix0, iy0, ix1, iy1 = 23, 20, bw - 23, bh - 19
    tf = tile.astype(np.float32)
    for y in range(iy0, iy1):
        lc = tf[y, ix0 - 3:ix0].mean(axis=0)
        rc = tf[y, ix1:ix1 + 3].mean(axis=0)
        t = np.linspace(0, 1, ix1 - ix0)[:, None]
        tf[y, ix0:ix1] = lc * (1 - t) + rc * t
    tf[iy0:iy1, ix0:ix1] = cv2.GaussianBlur(tf[iy0:iy1, ix0:ix1], (0, 0), sigmaX=0.1, sigmaY=4)
    tile = tf.clip(0, 255).astype(np.uint8)
    tmask = ndi.binary_fill_holes(tmask)
    rgba(tile, cv2.GaussianBlur(tmask.astype(np.float32) * 255, (0, 0), 0.8)).save(os.path.join(OUT, "preref_tile.png"))
    meta["tile"] = [bx, by, bw, bh]
    for name, box in zip(("rocket", "bomb", "orb"), ICONS):
        m = grab(im, box, smax=0.82 if name == "rocket" else 0.66)
        x0, y0, x1, y1 = box
        # у плитки ракеты (выбранной) дерево насыщеннее
        smax = 0.82 if name == "rocket" else 0.62
        wood = (h > 0.04) & (h < 0.115) & (s > 0.25) & (s < smax) & (v > 0.6) & (v < 0.97)
        m = m & ~wood
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
        n_, lab_, st_, _ = cv2.connectedComponentsWithStats(m)
        m = ndi.binary_fill_holes(lab_ == 1 + int(np.argmax(st_[1:, cv2.CC_STAT_AREA])))
        meta["ic_" + name] = save_cut("preref_ic_%s.png" % name, im, m, blur=0.7)
    # кружки: галочка и количество (цифра стёрта)
    gr = (h > 0.2) & (h < 0.45) & (s > 0.45)
    cm = circle_cut(im, CHECK, gr | ((s < 0.2) & (v > 0.9) & False))
    full = np.zeros((H, W), bool)
    full[CHECK[1]:CHECK[3], CHECK[0]:CHECK[2]] = cm
    meta["check"] = save_cut("preref_check.png", im, full)
    cm = circle_cut(im, COUNT, gr)
    sub = im[COUNT[1]:COUNT[3], COUNT[0]:COUNT[2]].copy()
    ys, xs = np.where(cm)
    cx, cy, r = xs.mean(), ys.mean(), (xs.max() - xs.min()) / 2.0
    sub = inpaint_inner(sub, cx, cy, r - 8)
    rgba(sub, cv2.GaussianBlur(cm.astype(np.float32) * 255, (0, 0), 0.8)).save(os.path.join(OUT, "preref_count.png"))
    meta["count"] = [COUNT[0], COUNT[1], round(float(cx), 1), round(float(cy), 1)]
    # зелёная рамка выбранной плитки (вокруг ракеты), без кружка с галочкой
    x0, y0, x1, y1 = TILES[0]
    sub = im[y0 - 12:y1 + 12, x0 - 12:x1 + 12].astype(np.float32)
    sh, ss, sv = hsv(np.ascontiguousarray(sub.astype(np.uint8)))
    green = np.clip((ss - 0.25) / 0.4, 0, 1) * ((sh > 0.18) & (sh < 0.42))
    gh, gw = green.shape
    sub = sub.copy()
    green[:gh // 2, gw - gw // 2:] = green[:gh // 2, :gw // 2][:, ::-1]
    sub[:gh // 2, gw - gw // 2:] = sub[:gh // 2, :gw // 2][:, ::-1]
    rgba(sub.astype(np.uint8), green * 255).save(os.path.join(OUT, "preref_sel.png"))
    meta["sel"] = [x0 - 12, y0 - 12]
    # кнопка «Играть»
    img, bb, _ = cut_button(im, h, s, v, PLAY)
    img.save(os.path.join(OUT, "preref_play.png"))
    meta["play"] = [int(c) for c in bb]
    # внутренность окна ниже целей — чистый крем: построчно между краями у рамки
    wf = work.astype(np.float32)
    fill_rows(wf, INNER)
    fill_rows(wf, (bb[0] - 4, INNER[3] - 2, bb[2] + 4, bb[3] + 5))
    work = wf.clip(0, 255).astype(np.uint8)
    # окно + панда
    mask = window_mask(im, h, s, v, y0=PRE_Y0 + 230, body=BODY, arch=ARCH, paw=PAW, rib_y=505, top_end=780,
                       leaf_y=(1420, 1585), side_y=(600, 1420))
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    # живая панда (assets/anim/win_prelevel, tools/winpanda.py) рисуется поверх окна; в самом окне от панды
    # остаётся только низ (лапы на ленте), голова и рука выше — убраны, иначе просвечивают под анимацией
    ramp = np.clip((np.arange(H, dtype=np.float32) - PANDA_KEEP[0]) / (PANDA_KEEP[1] - PANDA_KEEP[0]), 0, 1)[:, None]
    mask = np.maximum(mask, pa * ramp)
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work, mask.clip(0, 255)]).astype(np.uint8)[PRE_Y0:PRE_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "preref_window.webp"), quality=92, method=6)
    meta["window_y0"] = PRE_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
