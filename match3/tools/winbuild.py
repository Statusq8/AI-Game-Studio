#!/usr/bin/env python3
"""Окно победы 1:1 по референсу владельца (docs/games/match3/references/screen_03_win.webp, 852×1846).

python3 tools/winbuild.py REF.webp
Выход (assets/art):
  winref_window.webp — окно целиком (рамка, лента, лапка, панда, плашка наград, сундук, «+1»), фон вокруг
                       прозрачный; стёрты: число монет «+150», зелёная заливка полоски сундука, обе кнопки.
                       Левый верхний угол слоя = (0, WIN_Y0) референса.
  winref_star_0/1/2.png — звёзды (левая, центральная, правая), появляются по одной.
  winref_go.png, winref_ad.png — кнопки «Дальше» (зелёная) и «реклама x2» (фиолетовая).
  winref_seg.png — одна зелёная клетка полоски сундука.
Координаты ниже продублированы в scripts/main.gd (WIN_*) — менять вместе.
"""
import json
import os
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "art")
WIN_Y0, WIN_Y1 = 355, 1662                 # слой окна по высоте
BODY = (59, 560, 793, 1647, 92)            # тело рамки: лево, верх, право, низ, радиус нижних углов
ARCH = (425, 472, 178, 58)                 # эллипс деревянной арки над лентой (центр, полуоси)
PAW = (425, 422, 49)                       # круг лапки на арке
COINS_TXT = (230, 1104, 396, 1192)         # «+150» — стирается
BAR = (150, 1250, 416, 1296)               # зелёная часть полоски (5 клеток) — заменяется пустыми
SEG_X0, SEG_P = 156.0, 51.3                # начало первой клетки и шаг клеток (8 клеток)
SEG_TILE = 464                             # пустая клетка-образец (6-я)
BTN_GO = (188, 1328, 664, 1482)
BTN_AD = (210, 1484, 642, 1610)
STARS = [(255, 320), (428, 290), (598, 320)]
STAR_BOX = [(165, 240, 345, 420), (320, 180, 540, 410), (510, 240, 690, 420)]


def hsv(a):
    q = cv2.cvtColor(a, cv2.COLOR_RGB2HSV).astype(np.float32)
    return q[..., 0] * 2 / 360, q[..., 1] / 255, q[..., 2] / 255


def window_mask(im, h, s, v, y0=WIN_Y0, body=BODY, arch=ARCH, paw=PAW, rib_y=448, top_end=700,
                leaf_y=(1440, 1625), side_y=(540, 1440), blue_ribbon=False, ribbon_hue=None):
    """Маска рамки окна: верх (лента, арка, лапка, листья) по цвету + тело-прямоугольник + листья по углам."""
    H, W = v.shape
    gold = (h > 0.05) & (h < 0.17) & (s > 0.5) & (v > 0.55)
    red = ((h < 0.03) | (h > 0.95)) & (s > 0.5) & (v > 0.45)
    green = (h > 0.18) & (h < 0.42) & (s > 0.4) & (v > 0.45)
    top = gold | red | green
    if blue_ribbon:
        top |= (h > 0.6) & (h < 0.8) & (s > 0.45) & (v > 0.35)
    if ribbon_hue:
        top |= (h > ribbon_hue[0]) & (h < ribbon_hue[1]) & (s > 0.45) & (v > 0.3)
    top = top.astype(np.uint8)
    top[:y0 + 8] = 0
    top[top_end:] = 0
    top[:, :30] = 0
    top[:, W - 30:] = 0
    top = cv2.morphologyEx(top, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(top)
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    tm = ndi.binary_fill_holes(lab == big)
    # над лентой — только арка, лапка и листья (лучи звёзд не берём)
    yy, xx = np.mgrid[0:H, 0:W]
    cx, cy, a, b = arch
    allowed = (((xx - cx) / a) ** 2 + ((yy - cy) / b) ** 2 < 1.0)
    allowed |= (xx - paw[0]) ** 2 + (yy - paw[1]) ** 2 < paw[2] ** 2
    allowed |= yy > rib_y + ((xx - 425) / 275.0) ** 2 * 22
    allowed |= green
    tm &= ndi.binary_closing(allowed, np.ones((5, 5)))
    L, T, R, B, r = body
    body = np.zeros((H, W), np.uint8)
    cv2.rectangle(body, (L, T), (R, B - r), 1, -1)
    cv2.rectangle(body, (L + r, B - r), (R - r, B), 1, -1)
    cv2.circle(body, (L + r, B - r), r, 1, -1)
    cv2.circle(body, (R - r, B - r), r, 1, -1)
    # листья внизу по углам
    bl = green.astype(np.uint8)
    bl[:leaf_y[0]] = 0
    bl[leaf_y[1]:] = 0
    bl[:, 200:650] = 0
    bl[:, :30] = 0
    bl[:, W - 30:] = 0
    bl = cv2.morphologyEx(bl, cv2.MORPH_CLOSE, np.ones((9, 9), np.uint8))
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(bl)
    near = cv2.dilate(body, np.ones((5, 5), np.uint8)).astype(bool)
    leaves = np.zeros((H, W), bool)
    for i in range(1, n2):
        cm = lab2 == i
        if st2[i, cv2.CC_STAT_AREA] > 800 and (cm & near).any():
            leaves |= ndi.binary_fill_holes(cm)
    # листья по бокам рамки (торчат за край)
    side = green.astype(np.uint8)
    side[:side_y[0]] = 0
    side[side_y[1]:] = 0
    side[:, 140:710] = 0
    side = cv2.morphologyEx(side, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
    n3, lab3, st3, _ = cv2.connectedComponentsWithStats(side)
    for i in range(1, n3):
        cm = lab3 == i
        if st3[i, cv2.CC_STAT_AREA] > 500 and (cm & near).any():
            leaves |= ndi.binary_fill_holes(cm)
    m = (tm | body.astype(bool) | leaves).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    m = ndi.binary_fill_holes(m).astype(np.uint8)
    m = cv2.dilate(m, np.ones((3, 3), np.uint8))
    return cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 1.0)


def fill_rows(a, box):
    """Закрашивает прямоугольник построчно: линейно между пикселями слева и справа от него."""
    x0, y0, x1, y1 = box
    for y in range(y0, y1):
        lc = a[y, x0 - 3:x0].mean(axis=0)
        rc = a[y, x1:x1 + 3].mean(axis=0)
        t = np.linspace(0, 1, x1 - x0)[:, None]
        a[y, x0:x1] = lc * (1 - t) + rc * t


def cut_button(im, h, s, v, box):
    x0, y0, x1, y1 = box
    sub = im[y0:y1, x0:x1]
    hh, ss, vv = h[y0:y1, x0:x1], s[y0:y1, x0:x1], v[y0:y1, x0:x1]
    # кнопка — всё насыщенное или тёмное (кремовый фон — светлый и бледный)
    m = ((ss > 0.42) | (vv < 0.55)).astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    m = ndi.binary_fill_holes(lab == big).astype(np.uint8)
    m = cv2.dilate(m, np.ones((3, 3), np.uint8))
    al = cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.9)
    ys, xs = np.where(m > 0)
    bb = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    rgba = np.dstack([sub, al.clip(0, 255)]).astype(np.uint8)[bb[1]:bb[3], bb[0]:bb[2]]
    return Image.fromarray(rgba, "RGBA"), (x0 + bb[0], y0 + bb[1], x0 + bb[2], y0 + bb[3]), m


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im = np.asarray(src).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    meta = {}
    # звёзды
    warm = ((h > 0.02) & (h < 0.17) & (s > 0.6) & (v > 0.3)).astype(np.uint8)
    warm[:170] = 0
    warm[420:] = 0
    warm = cv2.morphologyEx(warm, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(warm)
    # тёмно-оранжевый контур звезды — замкнутое кольцо; его заливка и есть звезда целиком (с контуром).
    # Блики рвут кольцо — закрываем разрывы большим ядром, но только рядом с телом звезды (не цепляем соседей)
    ring = ((s > 0.78) & (h < 0.105) & (v < 0.88) & (v > 0.2)).astype(np.uint8)
    for i, (sx, sy) in enumerate(STARS):
        bx0, by0, bx1, by1 = STAR_BOX[i]
        core0 = (lab == lab[sy, sx]).astype(np.uint8)
        core = cv2.erode(core0, np.ones((5, 5), np.uint8))
        rr = np.zeros_like(ring)
        rr[by0:by1, bx0:bx1] = ring[by0:by1, bx0:bx1]
        rr &= cv2.dilate(core0, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (23, 23)))
        m = cv2.morphologyEx(rr | core, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (21, 21)))
        f = ndi.binary_fill_holes(m)
        fl, _ = ndi.label(f)
        m = (fl == fl[sy, sx]).astype(np.uint8)
        m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
        fl, _ = ndi.label(m)
        m = (fl == fl[sy, sx]).astype(np.uint8)
        al = cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.8)
        ys, xs = np.where(m > 0)
        x, y = xs.min() - 3, ys.min() - 3
        w, hh = xs.max() + 4 - x, ys.max() + 4 - y
        rgba = np.dstack([im, al.clip(0, 255)]).astype(np.uint8)[y:y + hh, x:x + w]
        Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "winref_star_%d.png" % i))
        meta["star_%d" % i] = [int(x), int(y), int(w), int(hh)]
    # кнопки (вырезаем из оригинала, место под ними закрашиваем кремом)
    work = im.astype(np.float32)
    for name, box in (("go", BTN_GO), ("ad", BTN_AD)):
        img, bb, _ = cut_button(im, h, s, v, box)
        img.save(os.path.join(OUT, "winref_%s.png" % name))
        meta[name] = [int(c) for c in bb]
        fill_rows(work, (bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2))
    # «+150»: белые буквы и тёмная обводка → восстановление по соседям
    x0, y0, x1, y1 = COINS_TXT
    sub = im[y0:y1, x0:x1]
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    tm = ((ss < 0.3) & (sv > 0.78)) | (sv < 0.5)
    tm[:, :3] = False
    tm = cv2.dilate(tm.astype(np.uint8), np.ones((7, 7), np.uint8))
    full = np.zeros((H, W), np.uint8)
    full[y0:y1, x0:x1] = tm
    work = cv2.inpaint(work.clip(0, 255).astype(np.uint8), full, 6, cv2.INPAINT_TELEA).astype(np.float32)
    # полоска сундука: зелёные клетки → пустые (по образцу пустой клетки)
    bx0, by0, bx1, by1 = BAR
    for y in range(by0 + 2, by1 - 2):
        for x in range(bx0 + 3, bx1 - 1):
            off = (x - SEG_X0) % SEG_P
            work[y, x] = im[y, int(round(SEG_TILE + off))]
    # одна зелёная клетка (3-я) с соседними перегородками
    sx0 = int(SEG_X0 + 2 * SEG_P) - 3
    sx1 = int(SEG_X0 + 3 * SEG_P) + 3
    seg = im[by0:by1, sx0:sx1].astype(int)
    gm = ((seg[..., 1] > seg[..., 0] + 25) & (seg[..., 1] > seg[..., 2] + 40)).astype(np.float32) * 255
    gm = cv2.GaussianBlur(gm, (0, 0), 0.6)
    Image.fromarray(np.dstack([seg, gm]).clip(0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "winref_seg.png"))
    meta["seg"] = [sx0, by0, sx1 - sx0, by1 - by0]
    # окно
    mask = window_mask(im, h, s, v)
    rgba = np.dstack([work.clip(0, 255), mask]).astype(np.uint8)[WIN_Y0:WIN_Y1]
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "winref_window.webp"), quality=92, method=6)
    meta["window_y0"] = WIN_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
