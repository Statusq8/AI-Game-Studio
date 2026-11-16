#!/usr/bin/env python3
"""Экран уровня 1:1 по референсу владельца (docs/games/match3/references/screen_02_level_v3.webp, 830×1895).

Из самого референса делается фон экрана уровня: плашки шапки, рамка панды, рамка поля, лоток —
пиксель в пиксель. Игровое (цели, ходы, фишки, кнопки) рисуется поверх в тех же местах.
python3 tools/refbuild.py REF.webp
Выход (assets/art): lvref_bg.webp — фон (из середины поля вырезано CUT строк, чтобы клетки были
квадратные), lvref_ring.png — рамка панды поверх панды, lvref_panda.png — панда из круга,
lvref_thumb.png — палец панды поверх рамки, lvref_count.png — маленькая плашка числа цели.
Координаты ниже продублированы в scripts/main.gd (LVW и рядом) — менять вместе.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "art")
CX, CY, RI = 417, 198, 104          # рамка панды: центр и внутренний радиус
RING_BOX = (250, 0, 590, 360)       # область слоя рамки
MOVES_IN = (577, 182, 788, 284)     # чистая внутренность плашки ходов
GOAL_IN = (44, 186, 291, 286)       # внутренность плашки целей (заливается чистой)
COUNT = (54, 253, 116, 283)         # маленькая плашка числа цели
BOARD = (100, 462, 730, 1298)       # внутренность рамки поля
CUT = (880, 928)                    # вырезаемые строки (48): клетки 78.75×78.8
TRAY_Y = (1669, 1845)               # зелёное поле лотка
CLEAN_X = 640                       # чистый столбец зелени лотка
CIRCLES = [(150, 1754, 94), (335, 1754, 94), (520, 1754, 94), (205, 1802, 38), (390, 1802, 38),
           (572, 1802, 38), (710, 1759, 72)]


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    orig = np.asarray(src).astype(np.float32)
    a = orig.copy()
    H, W = a.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - CX) ** 2 + (yy - CY) ** 2)
    # большой палец панды поверх правой части рамки — заменяем зеркальным куском рамки слева
    band = (d > RI - 4) & (d < RI + 13) & (xx > CX) & (yy > CY - 12) & (yy < CY + 70)
    fix = band & (orig.max(axis=2) < 110)
    fix = (np.asarray(Image.fromarray((fix * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0) & band
    mx = (2 * CX - xx).clip(0, W - 1)
    a[fix] = orig[yy[fix], mx[fix]]
    ring_src = a.copy()
    rx0, ry0, rx1, ry1 = RING_BOX
    # панда из референса: содержимое круга и палец поверх рамки (отдельным слоем)
    box = (CX - RI - 2, CY - RI - 2, CX + RI + 2, CY + RI + 2)
    pc = src.crop(box).convert("RGBA")
    pm = Image.new("L", pc.size, 0)
    ImageDraw.Draw(pm).ellipse((2, 2, 2 * RI + 2, 2 * RI + 2), fill=255)
    pc.putalpha(pm.filter(ImageFilter.GaussianBlur(0.8)))
    pc.save(os.path.join(OUT, "lvref_panda.png"))
    th = Image.fromarray(orig[ry0:ry1, rx0:rx1].astype(np.uint8)).convert("RGBA")
    th.putalpha(Image.fromarray((fix[ry0:ry1, rx0:rx1] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)))
    th.save(os.path.join(OUT, "lvref_thumb.png"))
    # плашка целей: нарисованные иконки и плашки чисел закрашиваем по соседнему кремовому цвету
    # цвет строки берём из чистой плашки ходов (она на 3 px выше), край области — мягкий
    gx0, gy0, gx1, gy1 = GOAL_IN
    rowcol = orig[gy0 - 3:gy1 - 3, 660:700].mean(axis=1)[:, None, :]
    gm = Image.new("L", (W, H), 0)
    ImageDraw.Draw(gm).rounded_rectangle((gx0, gy0, gx1, gy1), 16, fill=255)
    gma = (np.asarray(gm.filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0)[gy0 - 8:gy1 + 8, gx0 - 8:gx1 + 8, None]
    rc = np.pad(rowcol, ((8, 8), (0, 0), (0, 0)), mode="edge")
    reg0 = a[gy0 - 8:gy1 + 8, gx0 - 8:gx1 + 8]
    a[gy0 - 8:gy1 + 8, gx0 - 8:gx1 + 8] = reg0 * (1 - gma) + rc * gma
    src.crop(COUNT).save(os.path.join(OUT, "lvref_count.png"))
    # круг панды — мягкий зелёный фон
    inside = (d < RI + 3) & (yy < CY + 111)
    t = np.clip(d / RI, 0, 1)[..., None]
    fill = np.array([78, 150, 50]) * (1 - t) + np.array([36, 92, 28]) * t
    a = np.where(inside[..., None], fill, a)
    # слой рамки: только золотое кольцо и листья внизу внутри него (всё остальное — в фоне)
    reg = ring_src[ry0:ry1, rx0:rx1]
    ry, rx = np.mgrid[ry0:ry1, rx0:rx1]
    dd = np.sqrt((rx - CX) ** 2 + (ry - CY) ** 2)
    r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
    leaf = (g > 150) & (g > r * 1.05) & (b < 120) & (ry >= CY + 59) & ((rx < CX - 23) | (rx > CX + 49))
    A = np.zeros(reg.shape[:2])
    A[(dd >= RI - 1) & (dd <= RI + 10) & (ry < CY + 121)] = 255
    A[leaf & (dd < RI + 30)] = 255
    ring = Image.fromarray(reg.astype(np.uint8)).convert("RGBA")
    ring.putalpha(Image.fromarray(A.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)))
    ring.save(os.path.join(OUT, "lvref_ring.png"))
    # внутренность поля — ровная тёплая подложка (видна только в «дырах» фигурных полей)
    x0, y0, x1, y1 = BOARD
    a[y0:y1, x0:x1] = np.array([214, 190, 150])
    # лоток: убираем нарисованные кнопки (игра рисует свои на тех же местах) — только пиксели кругов;
    # зелень берётся из чистого столбца той же строки, листья сохраняются
    m = np.zeros((H, W), bool)
    for (ccx, ccy, cr) in CIRCLES:
        m |= (xx - ccx) ** 2 + (yy - ccy) ** 2 < cr * cr
    ty0, ty1 = TRAY_Y
    m[:ty0] = False
    m[ty1:] = False
    r, g, b = orig[..., 0], orig[..., 1], orig[..., 2]
    m &= ~((g > 165) & (g > r * 1.05) & (r > 80) & (b < 120) & (yy < ty0 + 40))
    col = orig[:, CLEAN_X]
    a[m] = col[yy[m]]
    a = np.concatenate([a[:CUT[0]], a[CUT[1]:]], axis=0)
    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(os.path.join(OUT, "lvref_bg.webp"), quality=92, method=6)
    print("ok", a.shape)


if __name__ == "__main__":
    main()
