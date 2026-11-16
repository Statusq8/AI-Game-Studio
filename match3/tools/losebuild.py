#!/usr/bin/env python3
"""Окно проигрыша 1:1 по референсу владельца (docs/games/match3/references/screen_04_lose.webp, 852×1846).

python3 tools/losebuild.py REF.webp
Рамка — та же, что у окна победы (tools/winbuild.py), только выше: верх сдвинут на −184 px, низ на +69.
Выход (assets/art):
  loseref_window.webp — окно (рамка, синяя лента, грустная панда, пустая плашка целей), фон вокруг прозрачный;
                        стёрты: иконки целей и разделитель, плашка серии побед, все три кнопки.
                        Левый верхний угол слоя = (0, LOSE_Y0) референса.
  loseref_streak.png — красная плашка серии побед с огоньком (без текста; есть только при серии > 0).
  loseref_badge.png  — красный кружок счётчика цели без цифры.
  loseref_buy.png, loseref_ad.png, loseref_quit.png — кнопки: «+5 за монеты» (цена стёрта), «+5 за рекламу», «сдаться».
Координаты продублированы в scripts/main.gd (LOSE_*) — менять вместе.
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

LOSE_Y0, LOSE_Y1 = 180, 1730
BODY = (58, 376, 793, 1716, 85)
ARCH = (425, 288, 178, 58)
PAW = (425, 236, 47)
PLATE_IN = (172, 885, 680, 1049)           # внутренность плашки целей (заливается чистой)
BADGE_C = (345, 997)                       # счётчик «5» — образец кружка
STREAK = (130, 1058, 722, 1190)            # плашка серии побед
BTN_BUY = (168, 1192, 680, 1390)
BTN_AD = (196, 1392, 656, 1526)
BTN_QUIT = (262, 1528, 592, 1652)
PRICE_TXT = (402, 1296, 528, 1358)         # «900» на зелёной кнопке — стирается


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    im = np.asarray(src).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    meta = {}
    work = im.astype(np.float32)
    # счётчик цели: красный круг с белой цифрой → без цифры
    red = (((h < 0.04) | (h > 0.95)) & (s > 0.5) & (v > 0.4)).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(red)
    k = lab[BADGE_C[1] - 25, BADGE_C[0]]
    x, y, w, hh = st[k, :4]
    cx, cy = x + w / 2.0, y + hh / 2.0
    rr = max(w, hh) / 2.0 + 5
    bx0, by0 = int(cx - rr), int(cy - rr)
    bsz = int(rr * 2) + 1
    sub = im[by0:by0 + bsz, bx0:bx0 + bsz].copy()
    sh, ss, sv = hsv(np.ascontiguousarray(sub))
    yy, xx = np.mgrid[0:bsz, 0:bsz]
    dd = np.sqrt((xx - bsz / 2.0) ** 2 + (yy - bsz / 2.0) ** 2)
    # вся внутренность кружка (цифра с обводкой) заполняется красным от края внутрь
    digit = (dd < rr - 13).astype(np.uint8)
    sub = cv2.inpaint(sub, digit, 7, cv2.INPAINT_TELEA)
    blur = cv2.GaussianBlur(sub, (0, 0), 6)
    inner = (cv2.GaussianBlur(digit.astype(np.float32), (0, 0), 2) )[..., None]
    sub = (sub * (1 - inner) + blur * inner).astype(np.uint8)
    # альфа круга: насыщенное (красный, золотой кант) или тёмное внутри радиуса
    _, s2, v2 = hsv(np.ascontiguousarray(sub))
    am = ((s2 > 0.4) & (dd < rr)).astype(np.uint8)
    am = ndi.binary_fill_holes(cv2.morphologyEx(am, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))).astype(np.uint8)
    n2, lab2, st2, _ = cv2.connectedComponentsWithStats(am)
    am = (lab2 == 1 + int(np.argmax(st2[1:, cv2.CC_STAT_AREA]))).astype(np.float32) * 255
    am = cv2.GaussianBlur(am, (0, 0), 0.8)
    Image.fromarray(np.dstack([sub, am]).clip(0, 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "loseref_badge.png"))
    meta["badge"] = [round(cx - bx0, 1), round(cy - by0, 1), bsz]
    # плашка целей — пустая
    fill_rows(work, PLATE_IN)
    meta["divider_color"] = [int(c) for c in im[960, 425]]
    # плашка серии побед — отдельный слой
    img, bb, m = cut_button(im, h, s, v, STREAK)
    img.save(os.path.join(OUT, "loseref_streak.png"))
    meta["streak"] = [int(c) for c in bb]
    fill_rows(work, (bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2))
    # кнопки
    for name, box in (("buy", BTN_BUY), ("ad", BTN_AD), ("quit", BTN_QUIT)):
        img, bb, _ = cut_button(im, h, s, v, box)
        if name == "buy":
            # цена «900» → стираем (цену пишет игра)
            a = np.asarray(img).copy()
            rgb = np.ascontiguousarray(a[..., :3])
            _, ts, tv = hsv(rgb)
            px0, py0, px1, py1 = PRICE_TXT
            tm = np.zeros(rgb.shape[:2], np.uint8)
            ox, oy = bb[0], bb[1]
            reg = (slice(py0 - oy, py1 - oy), slice(px0 - ox, px1 - ox))
            tm[reg] = (((ts[reg] < 0.3) & (tv[reg] > 0.6)) | (tv[reg] < 0.3)).astype(np.uint8)
            tm = cv2.dilate(tm, np.ones((5, 5), np.uint8))
            a[..., :3] = cv2.inpaint(rgb, tm, 6, cv2.INPAINT_TELEA)
            img = Image.fromarray(a, "RGBA")
        img.save(os.path.join(OUT, "loseref_%s.png" % name))
        meta[name] = [int(c) for c in bb]
        fill_rows(work, (bb[0] - 2, bb[1] - 2, bb[2] + 2, bb[3] + 2))
    mask = window_mask(im, h, s, v, y0=LOSE_Y0, body=BODY, arch=ARCH, paw=PAW, rib_y=264, top_end=520,
                       leaf_y=(1500, 1700), side_y=(356, 1500), blue_ribbon=True)
    rgba = np.dstack([work.clip(0, 255), mask]).astype(np.uint8)[LOSE_Y0:LOSE_Y1]
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "loseref_window.webp"), quality=92, method=6)
    meta["window_y0"] = LOSE_Y0
    print(json.dumps(meta))


if __name__ == "__main__":
    main()
