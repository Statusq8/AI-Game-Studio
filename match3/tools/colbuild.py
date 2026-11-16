#!/usr/bin/env python3
"""Коллекция 1:1 по референсу владельца (docs/games/match3/references/screen_12_collection.webp, 852×1846).

python3 tools/colbuild.py REF.webp
Выход (assets/art):
  colref_window.webp — окно (рамка, оранжевая лента, крестик) без строк; левый низ (там панда) — зеркало правого.
                       Левый верхний угол = (0, COL_Y0).
  colref_panda.png — панда с альбомом (поверх всего), colref_row_on.png / colref_row_off.png — строка (открыта / закрыта),
  colref_pic_0..7.png — круглые картинки зон (0–2 цветные, 3–7 силуэты), colref_check.png, colref_lock.png,
  colref_track.png (пустая полоска), colref_fill.png (зелёная заливка).
Координаты продублированы в scripts/main.gd (COLREF_*) — менять вместе.
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
from designbuild import flat_fill  # noqa: E402

COL_Y0, COL_Y1 = 58, 1750
BODY = (52, 280, 799, 1680, 85)
ARCH = (425, 148, 178, 58)
PAW = (425, 100, 47)
CLOSE = (742, 152, 52)
CIRCLES = [(206, 389, 89), (207, 554, 89), (207, 719, 89), (204, 875, 79), (204.5, 1013, 79), (204.5, 1153, 79),
           (206.5, 1292, 79), (206.5, 1432, 79)]
ROW_ON = (296, 486, 740, 622)               # образец открытой строки (правее круга), строка 2
ROW_OFF = (284, 1095, 740, 1215)            # образец закрытой строки, строка 6
CHECK = (610, 340, 714, 444)
LOCK = (618, 828, 702, 922)
TRACK = (458, 690, 712, 752)
PANDA_BOX = (0, 1460, 360, 1750)


def circ(im, cx, cy, r):
    x0, y0 = int(cx - r - 2), int(cy - r - 2)
    sz = int(2 * r + 5)
    sub = im[y0:y0 + sz, x0:x0 + sz]
    yy, xx = np.mgrid[0:sz, 0:sz]
    d = np.sqrt((xx - (cx - x0)) ** 2 + (yy - (cy - y0)) ** 2)
    return rgba(sub, np.clip((r + 0.5 - d) * 255, 0, 255).astype(np.float32))


def blob(im, box, sel):
    x0, y0, x1, y1 = box
    m = sel[y0:y1, x0:x1].astype(np.uint8)
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    m = ndi.binary_fill_holes(lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])))
    return rgba(im[y0:y1, x0:x1], cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.8))


def row_img(im, box, erase):
    """Строка: правая часть с закруглённым краем; значок справа (галочка / замок) стёрт."""
    x0, y0, x1, y1 = box
    sub = im[y0 - 6:y1 + 6, x0:x1 + 8].copy()
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    gold = (sh > 0.08) & (sh < 0.17) & (ss > 0.5) & (sv > 0.6)
    # внутренность строки — между золотым кантом сверху и снизу; справа — до скругления канта
    m = np.zeros(sub.shape[:2], np.uint8)
    H, W = m.shape
    for x in range(W):
        ys = np.where(gold[:, x])[0]
        if len(ys) >= 2 and ys.max() - ys.min() > H * 0.5:
            m[ys.min():ys.max() + 1, x] = 1
    m = ndi.binary_fill_holes(cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    # правая часть (галочка / замок с тенью): всё, кроме канта у края строки, — цветом чистого столбца
    dist = ndi.distance_transform_edt(m)
    edge = gold & (dist < 16)
    edge = cv2.dilate(edge.astype(np.uint8), np.ones((3, 3), np.uint8)).astype(bool) & (dist < 18)
    ref = sub[:, 200].copy()
    for x in range(erase[0] - x0 - 50, sub.shape[1]):
        rep = ~edge[:, x] & m[:, x]
        sub[rep, x] = ref[rep]
    return rgba(sub, cv2.GaussianBlur(m.astype(np.float32) * 255, (0, 0), 0.8))


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im0 = np.asarray(src).copy()
    H, W = im0.shape[:2]
    h0, s0, v0 = hsv(im0)
    yy, xx = np.mgrid[0:H, 0:W]
    meta = {}
    for i, (cx, cy, r) in enumerate(CIRCLES):
        circ(im0, cx, cy, r).save(os.path.join(OUT, "colref_pic_%d.png" % i))
    row_img(im0, ROW_ON, (608, 498, 716, 606)).save(os.path.join(OUT, "colref_row_on.png"))
    row_img(im0, ROW_OFF, (616, 1106, 704, 1198)).save(os.path.join(OUT, "colref_row_off.png"))
    blob(im0, CHECK, ((h0 > 0.2) & (h0 < 0.45) & (s0 > 0.4)) | ((s0 < 0.2) & (v0 > 0.85) & (xx > 630) & (xx < 695))).save(os.path.join(OUT, "colref_check.png"))
    blob(im0, LOCK, (s0 > 0.45) | (v0 < 0.35)).save(os.path.join(OUT, "colref_lock.png"))
    # полоска: целиком (с заливкой) → пустая (зелёное → цвет пустой части в той же строке) и кусок заливки
    tx0, ty0, tx1, ty1 = TRACK
    sub = im0[ty0:ty1, tx0:tx1].copy()
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    green = (sh > 0.2) & (sh < 0.45) & (ss > 0.35)
    tm = ((ss > 0.3) | (sv < 0.9)).astype(np.uint8)
    tm = ndi.binary_fill_holes(cv2.morphologyEx(tm, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(tm.astype(np.uint8))
    tm = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    gcols = np.where(green.any(axis=0))[0]
    gx1 = int(gcols.max())
    empty = sub.copy()
    for y in range(sub.shape[0]):
        if green[y].any():
            empty[y, green[y]] = sub[y, min(sub.shape[1] - 30, gx1 + 30)]
    gm = cv2.dilate(green.astype(np.uint8), np.ones((3, 3), np.uint8))
    empty = cv2.inpaint(empty, (cv2.dilate(gm, np.ones((3, 3), np.uint8)) - gm), 3, cv2.INPAINT_TELEA)
    rgba(empty, cv2.GaussianBlur(tm.astype(np.float32) * 255, (0, 0), 0.8)).save(os.path.join(OUT, "colref_track.png"))
    rgba(sub, cv2.GaussianBlur(green.astype(np.float32) * 255, (0, 0), 0.7)).save(os.path.join(OUT, "colref_fill.png"))
    ys, xs = np.where(green)
    meta["fill"] = [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]
    # панда с альбомом
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = PANDA_BOX
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in (((150, 1560), 50), ((250, 1660), 40), ((90, 1680), 30)):
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    bgm = np.zeros((1, 65)); fgm = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im0, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), bgm, fgm, 8, cv2.GC_INIT_WITH_MASK)
    panda = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    n, lab, st, _ = cv2.connectedComponentsWithStats(panda.astype(np.uint8))
    panda = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    yel = (h0 > 0.11) & (h0 < 0.18) & (s0 > 0.7) & (v0 > 0.85) & (xx > 250) & (xx < 330) & (yy > 1500) & (yy < 1580)
    panda = ndi.binary_fill_holes(cv2.morphologyEx((panda | yel).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    ys, xs = np.where(panda)
    px0, py0, px1, py1 = max(0, xs.min() - 2), max(0, ys.min() - 2), xs.max() + 3, min(H, ys.max() + 3)
    pa = cv2.GaussianBlur(panda.astype(np.float32) * 255, (0, 0), 0.9)
    rgba(im0[py0:py1, px0:px1], pa[py0:py1, px0:px1]).save(os.path.join(OUT, "colref_panda.png"))
    meta["panda"] = [int(px0), int(py0)]
    # окно
    im = im0.copy()
    xs_ = np.arange(0, 380)
    im[1450:, xs_] = im0[1450:, W - 1 - xs_]
    h, s, v = hsv(im)
    work = im.astype(np.float32)
    cream = np.median(im0[1515:1580, 420:640].reshape(-1, 3), axis=0)
    flat_fill(work, (100, 298, 748, 1508), cream, 8)
    mask = window_mask(im, h, s, v, y0=62, body=BODY, arch=ARCH, paw=PAW, rib_y=128, top_end=360,
                       leaf_y=(1500, 1678), side_y=(280, 1510), ribbon_hue=(0.03, 0.1))
    cm2 = np.zeros((H, W), np.uint8)
    cv2.circle(cm2, CLOSE[:2], CLOSE[2], 1, -1)
    mask = np.maximum(mask, cv2.GaussianBlur(cm2.astype(np.float32) * 255, (0, 0), 1.0))
    out = np.dstack([work.clip(0, 255), mask.clip(0, 255)]).astype(np.uint8)[COL_Y0:COL_Y1]
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, "colref_window.webp"), quality=92, method=6)
    meta["window_y0"] = COL_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
