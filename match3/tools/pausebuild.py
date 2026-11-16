#!/usr/bin/env python3
"""Окно паузы 1:1 по референсу владельца (docs/games/match3/references/screen_06_pause.webp, 852×1846).

python3 tools/pausebuild.py REF.webp
Выход (assets/art):
  pauseref_window.webp — окно (рамка, оранжевая лента, панда с соком на углу), фон прозрачный;
                         стёрты переключатели и кнопки. Левый верхний угол слоя = (0, PAUSE_Y0) референса.
  pauseref_music/sound/vibration.png — круглые переключатели (без галочки), pauseref_check.png — галочка,
  pauseref_go.png, pauseref_restart.png, pauseref_home.png — кнопки.
Координаты продублированы в scripts/main.gd (PAUSE_*) — менять вместе.
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

PAUSE_Y0, PAUSE_Y1 = 280, 1462
BODY = (78, 726, 774, 1449, 97)
ARCH = (425, 638, 178, 58)
PAW = (425, 586, 47)
PANDA_BOX = (445, 285, 762, 616)
TOGGLES = [("music", (163, 795, 323, 958)), ("sound", (345, 795, 505, 958)), ("vibration", (525, 795, 690, 958))]
CHECK_OFF = (52, -50, 30)                  # галочка от центра переключателя, радиус
BTN_GO = (175, 980, 674, 1125)
BTN_RESTART = (178, 1132, 670, 1274)
BTN_HOME = (240, 1280, 612, 1396)


def rgba(img, alpha):
    return Image.fromarray(np.dstack([img, alpha.clip(0, 255)]).astype(np.uint8), "RGBA")


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im = np.asarray(src).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    meta = {}
    work = im.astype(np.float32)
    # ---- панда на углу окна
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.ellipse(pm, (600, 470), (90, 90), 0, 0, 360, cv2.GC_FGD, -1)
    cv2.circle(pm, (640, 360), 40, cv2.GC_FGD, -1)
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    yel = (h > 0.11) & (h < 0.18) & (s > 0.7) & (v > 0.85)
    yel[:, :465] = False
    yel[:, 540:] = False
    yel[:300] = False
    yel[385:] = False
    panda |= yel
    panda = ndi.binary_fill_holes(cv2.morphologyEx(panda.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    # ---- галочка (с первого переключателя)
    t0 = TOGGLES[0][1]
    sel = ((s > 0.42) | (v < 0.55))
    m = sel[t0[1]:t0[3], t0[0]:t0[2]].astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    ys, xs = np.where(lab == k)
    gr = (h > 0.2) & (h < 0.45) & (s > 0.45)
    for name, box in TOGGLES:
        bx0, by0, bx1, by1 = box
        m = sel[by0:by1, bx0:bx1] & ~gr[by0:by1, bx0:bx1]
        m = cv2.morphologyEx(m.astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
        n, lab, st, _ = cv2.connectedComponentsWithStats(m)
        k = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        ys, xs = np.where(lab == k)
        cx, cy = (xs.min() + xs.max()) / 2.0, (ys.min() + ys.max()) / 2.0
        r = (xs.max() - xs.min()) / 2.0
        sub = im[by0:by1, bx0:bx1].copy()
        yy, xx = np.mgrid[0:by1 - by0, 0:bx1 - bx0]
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
        # галочка лежит на ободке справа сверху — ободок там берём зеркально слева
        mx = np.clip((2 * cx - xx).round().astype(int), 0, bx1 - bx0 - 1)
        sg = cv2.dilate((gr[by0:by1, bx0:bx1]).astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
        fix = (xx > cx - 2) & (yy < cy + 2) & ((d > r * 0.66) | sg)
        sub[fix] = sub[yy[fix], mx[fix]]
        a = np.clip((r + 1.0 - d) * 255, 0, 255).astype(np.float32)
        ox, oy = int(cx - r - 2), int(cy - r - 2)
        sz = int(2 * r + 5)
        rgba(sub[oy:oy + sz, ox:ox + sz], a[oy:oy + sz, ox:ox + sz]).save(os.path.join(OUT, "pauseref_%s.png" % name))
        meta[name] = [round(float(bx0 + cx), 1), round(float(by0 + cy), 1), sz]
        if name == "music":
            # галочка: зелёный кружок справа сверху
            gcx, gcy = bx0 + cx + CHECK_OFF[0], by0 + cy + CHECK_OFF[1]
            gx0, gy0 = int(gcx - CHECK_OFF[2] - 4), int(gcy - CHECK_OFF[2] - 4)
            gsz = CHECK_OFF[2] * 2 + 9
            gsub = gr[gy0:gy0 + gsz, gx0:gx0 + gsz] | ((s[gy0:gy0 + gsz, gx0:gx0 + gsz] < 0.2) & (v[gy0:gy0 + gsz, gx0:gx0 + gsz] > 0.85))
            gyy, gxx = np.mgrid[0:gsz, 0:gsz]
            gd = np.sqrt((gxx - gsz / 2.0) ** 2 + (gyy - gsz / 2.0) ** 2)
            gm = ndi.binary_fill_holes(cv2.morphologyEx((gsub & (gd < CHECK_OFF[2] + 3)).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
            rgba(im[gy0:gy0 + gsz, gx0:gx0 + gsz], cv2.GaussianBlur(gm.astype(np.float32) * 255, (0, 0), 0.8)).save(os.path.join(OUT, "pauseref_check.png"))
            meta["check"] = [round(gcx - (bx0 + cx), 1), round(gcy - (by0 + cy), 1)]
    # стираем переключатели (вместе с галочками) — построчно по крему
    fill_rows(work, (TOGGLES[0][1][0] - 4, 780, TOGGLES[2][1][2] + 6, 965))
    # кнопки
    for name, box in (("go", BTN_GO), ("restart", BTN_RESTART), ("home", BTN_HOME)):
        img, bb, _ = cut_button(im, h, s, v, box)
        img.save(os.path.join(OUT, "pauseref_%s.png" % name))
        meta[name] = [int(c) for c in bb]
        fill_rows(work, (bb[0] - 3, bb[1] - 3, bb[2] + 3, bb[3] + 4))
    mask = window_mask(im, h, s, v, y0=530, body=BODY, arch=ARCH, paw=PAW, rib_y=599, top_end=880,
                       leaf_y=(1290, 1445), side_y=(700, 1300))
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    mask = np.maximum(mask, pa)
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[PAUSE_Y0:PAUSE_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "pauseref_window.webp"), quality=92, method=6)
    meta["window_y0"] = PAUSE_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
