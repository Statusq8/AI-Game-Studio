#!/usr/bin/env python3
"""Нарезка листа UI-элементов на зелёном фоне на отдельные PNG.

python3 tools/sheetcut.py SHEET name1,name2,... [--out assets/art] [--min 2000]

Элементы находятся как связные куски (зелёный фон вырезается), упорядочиваются по рядам
(сверху вниз), в ряду — слева направо, и сохраняются под именами из списка (пропуск — «-»).
"""
import argparse
import os

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def key(a: np.ndarray) -> np.ndarray:
    # цвет фона — медиана по краям листа; ключ по расстоянию до него (тёмно-зелёные кнопки остаются)
    edge_px = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(edge_px, axis=0)
    d = np.sqrt(((a - bg) ** 2).sum(axis=2))
    alpha = np.clip((d - 30.0) / (75.0 - 30.0), 0.0, 1.0)
    # фон — только зелёное, связанное с краем листа: зелёные кнопки внутри элементов не трогаем
    bgm = (alpha < 0.5).astype(np.uint8)
    n, lab = cv2.connectedComponents(bgm, connectivity=4)
    edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    outside = np.isin(lab, list(edge))
    # мягкий край оставляем только у внешнего фона
    near = cv2.dilate(outside.astype(np.uint8), np.ones((5, 5), np.uint8)).astype(bool)
    return np.where(near, alpha, 1.0) * np.where(outside, 0.0, 1.0) + np.where(outside, alpha * 0, 0)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("names")
    ap.add_argument("--out", default="assets/art")
    ap.add_argument("--min", type=int, default=2000)
    ap.add_argument("--grow", type=int, default=9)
    o = ap.parse_args()
    a = np.asarray(Image.open(o.sheet).convert("RGB")).astype(np.float32)
    alpha = key(a)
    m = (alpha > 0.5).astype(np.uint8)
    m = cv2.dilate(m, np.ones((o.grow, o.grow), np.uint8))  # склеить листики и ленты с элементом
    n, lab_d, st, _ = cv2.connectedComponentsWithStats(m, 8)
    boxes = [tuple(st[i, :4]) + (i,) for i in range(1, n) if st[i, cv2.CC_STAT_AREA] >= o.min]
    # ряды: группируем по центру по вертикали
    boxes.sort(key=lambda b: b[1] + b[3] / 2)
    rows, cur = [], []
    for b in boxes:
        # новый ряд — если элемент начинается ниже середины всех элементов текущего ряда
        if cur and b[1] > max(c[1] + c[3] * 0.6 for c in cur):
            rows.append(cur)
            cur = []
        cur.append(b)
    if cur:
        rows.append(cur)
    ordered = [b for r in rows for b in sorted(r, key=lambda b: b[0])]
    names = o.names.split(",")
    # убираем зелёный отсвет на краях
    r, g, bch = a[..., 0], a[..., 1], a[..., 2]
    g2 = np.where(alpha < 0.99, np.minimum(g, np.maximum(r, bch) + 10.0), g)
    rgba = np.dstack([r, g2, bch, alpha * 255]).clip(0, 255).astype(np.uint8)
    out = os.path.join(ROOT, o.out)
    idx = [b[4] for b in ordered]
    for i, (x, y, w, h, _) in enumerate(ordered):
        nm = names[i] if i < len(names) else f"_extra{i}"
        if nm == "-":
            continue
        # рамка была расширена дилатацией — сужаем по реальной прозрачности
        sub = alpha[y:y + h, x:x + w]
        ys, xs = np.where(sub > 0.1)
        y0, y1, x0, x1 = y + ys.min(), y + ys.max() + 1, x + xs.min(), x + xs.max() + 1
        p = 2
        crop = rgba[max(0, y0 - p):y1 + p, max(0, x0 - p):x1 + p].copy()
        # чужие куски, попавшие в рамку, убираем
        lm = (lab_d[max(0, y0 - p):y1 + p, max(0, x0 - p):x1 + p] != idx[i])
        crop[lm, 3] = 0
        Image.fromarray(crop, "RGBA").save(os.path.join(out, nm + ".png"), optimize=True)
        print(f"{nm}: {w}x{h} at {x},{y}")
    if len(ordered) != len(names):
        print(f"ВНИМАНИЕ: найдено {len(ordered)}, имён {len(names)}")


if __name__ == "__main__":
    main()
