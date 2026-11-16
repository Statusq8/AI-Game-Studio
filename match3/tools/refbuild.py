#!/usr/bin/env python3
"""Экран уровня 1:1 по референсу владельца (docs/games/match3/references/screen_02_level_v2.webp).

Из самого референса делается фон экрана уровня: плашки шапки, рамка панды, рамка поля, лоток —
пиксель в пиксель. Игровое (цели, ходы, панда, фишки, кнопки) рисуется поверх в тех же местах.
python3 tools/refbuild.py REF.webp
Выход: assets/art/lvref_bg.webp (фон, 898 px в ширину; из середины поля вырезано 68 строк,
чтобы клетки были квадратные: 8×10 по 86 px), lvref_ring.png (рамка панды поверх панды),
lvref_count.png (маленькая плашка числа цели).
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "art")
CX, CY, RI = 451, 141, 110          # рамка панды: центр и внутренний радиус
BOARD = (105, 400, 793, 1328)       # внутренность рамки поля
CUT = (1150, 1218)                  # вырезаемые строки (68): клетки 86×86
TRAY_Y = (1500, 1702)               # зелёное поле лотка
TRAY_X = list(range(74, 674)) + list(range(688, 847))  # всё, кроме золотой черты перед паузой
CLEAN_X = 698                       # чистый столбец зелени лотка


def main() -> None:
    src = Image.open(sys.argv[1]).convert("RGB")
    orig = np.asarray(src).astype(np.float32)
    a = orig.copy()
    H, W = a.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W]
    d = np.sqrt((xx - CX) ** 2 + (yy - CY) ** 2)
    # большой палец панды поверх правой части рамки — заменяем зеркальным куском рамки слева
    band = (d > RI - 6) & (d < RI + 30) & (xx > CX) & (yy < 260)
    fix = band & (orig.max(axis=2) < 110)
    fix = (np.asarray(Image.fromarray((fix * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(7))) > 0) & band
    mx = (2 * CX - xx).clip(0, W - 1)
    a[fix] = orig[yy[fix], mx[fix]]
    ring_src = a.copy()
    # плашка целей: внутренность заменяем чистой внутренностью плашки ходов
    im = Image.fromarray(a.astype(np.uint8))
    mv = src.crop((628, 112, 848, 240)).resize((266, 140), Image.LANCZOS)
    mask = Image.new("L", (266, 140), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 265, 139), 26, fill=255)
    im.paste(mv, (52, 108), mask.filter(ImageFilter.GaussianBlur(3)))
    a = np.asarray(im).astype(np.float32).copy()
    src.crop((58, 197, 128, 234)).save(os.path.join(OUT, "lvref_count.png"))
    # круг панды — мягкий зелёный фон
    inside = (d < RI + 3) & (yy < 252)
    t = np.clip(d / RI, 0, 1)[..., None]
    fill = np.array([78, 150, 50]) * (1 - t) + np.array([36, 92, 28]) * t
    a = np.where(inside[..., None], fill, a)
    # рамка панды отдельным слоем: внутри прозрачно, листья снизу остаются
    reg = ring_src[0:300, 300:640]
    ry, rx = np.mgrid[0:300, 300:640]
    dd = np.sqrt((rx - CX) ** 2 + (ry - CY) ** 2)
    r, g, b = reg[..., 0], reg[..., 1], reg[..., 2]
    leaf = (g > 150) & (g > r * 1.05) & (b < 120) & (ry >= 200) & ((rx < 428) | (rx > 500))
    # слой рамки: только золотое кольцо и листья внизу внутри него (всё остальное — в фоне)
    A = np.zeros(reg.shape[:2])
    A[(dd >= RI - 1) & (dd <= RI + 20) & (ry < 262)] = 255
    A[leaf & (dd < RI + 30)] = 255
    ring = Image.fromarray(reg.astype(np.uint8)).convert("RGBA")
    ring.putalpha(Image.fromarray(A.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.0)))
    ring.save(os.path.join(OUT, "lvref_ring.png"))
    # внутренность поля — ровная тёплая подложка (видна только в «дырах» фигурных полей)
    x0, y0, x1, y1 = BOARD
    a[y0:y1, x0:x1] = np.array([214, 190, 150])
    # лоток: убираем нарисованные кнопки (игра рисует свои на тех же местах) — только пиксели кругов
    # кнопок и счётчиков; зелень лотка берётся из чистого столбца той же строки, листья сохраняются
    circles = [(165, 1602, 97), (364, 1602, 97), (562, 1602, 97), (220, 1655, 40), (418, 1655, 40),
               (617, 1655, 40), (775, 1600, 76)]
    m = np.zeros((H, W), bool)
    for (ccx, ccy, cr) in circles:
        m |= (xx - ccx) ** 2 + (yy - ccy) ** 2 < cr * cr
    ty0, ty1 = TRAY_Y
    m[:ty0] = False
    m[ty1:] = False
    r, g, b = orig[..., 0], orig[..., 1], orig[..., 2]
    leaf = (g > 165) & (g > r * 1.05) & (r > 80) & (b < 120) & (yy < 1550)
    m &= ~leaf
    col = orig[:, CLEAN_X]
    a[m] = col[yy[m]]
    a = np.concatenate([a[:CUT[0]], a[CUT[1]:]], axis=0)
    Image.fromarray(a.clip(0, 255).astype(np.uint8)).save(os.path.join(OUT, "lvref_bg.webp"), quality=92, method=6)
    print("ok", a.shape)


if __name__ == "__main__":
    main()
