#!/usr/bin/env python3
"""ИИ-видео эффекта на чёрном фоне -> лист кадров (flipbook) для board.gd (_flipbook).

python3 tools/fxcut.py VIDEO NAME --start 2.0 --end 4.6 [--frames 16] [--cols 4] [--cell 256]

Прозрачность — из яркости (чёрный = пусто): огонь и искры остаются, фон исчезает,
тёмный дым становится полупрозрачным. Края кадра гасятся круглой маской — водяной знак
и обрезанные краем видео клубы не видны. Результат: assets/vfx/NAME.png, сетка cols x rows.
Не забыть добавить NAME в FLIPBOOKS (board.gd): [cols, rows, frames].
"""
import argparse
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("name")
    ap.add_argument("--start", type=float, required=True)
    ap.add_argument("--end", type=float, required=True)
    ap.add_argument("--frames", type=int, default=16)
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--cell", type=int, default=256)
    ap.add_argument("--black", type=float, default=14.0, help="яркость, ниже которой — пусто")
    ap.add_argument("--full", type=float, default=140.0, help="яркость полной непрозрачности")
    ap.add_argument("--fadeout", type=float, default=0.0, help="доля последних кадров, которые плавно гаснут")
    ap.add_argument("--edge", type=float, default=0.12, help="ширина мягкого края круглой маски (доля кадра)")
    o = ap.parse_args()
    tmp = tempfile.mkdtemp()
    fps = o.frames / (o.end - o.start)
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(o.start), "-i", o.video, "-t", str(o.end - o.start),
                    "-vf", f"fps={fps}", os.path.join(tmp, "%03d.png")], check=True)
    names = sorted(os.listdir(tmp))[: o.frames]
    rows = (len(names) + o.cols - 1) // o.cols
    sheet = Image.new("RGBA", (o.cols * o.cell, rows * o.cell), (0, 0, 0, 0))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(tmp, n)).convert("RGB")
        s = min(im.size)
        im = im.crop(((im.width - s) // 2, (im.height - s) // 2, (im.width + s) // 2, (im.height + s) // 2))
        im = im.resize((o.cell, o.cell), Image.LANCZOS)
        a = np.asarray(im).astype(np.float32)
        lum = a.max(axis=2)
        alpha = np.clip((lum - o.black) / (o.full - o.black), 0, 1) ** 0.85
        yy, xx = np.mgrid[0:o.cell, 0:o.cell] / (o.cell - 1) - 0.5
        r = np.sqrt(xx ** 2 + yy ** 2)
        alpha *= np.clip((0.49 - r) / o.edge, 0, 1) ** 1.5
        if o.fadeout > 0:
            t = i / max(1, len(names) - 1)
            alpha *= np.clip((1.0 - t) / o.fadeout, 0, 1)
        col = np.clip(a / np.maximum(alpha, 0.04)[..., None], 0, 255)
        col = np.where(alpha[..., None] > 0.02, col, 0)
        out = np.dstack([col, alpha * 255]).astype(np.uint8)
        sheet.paste(Image.fromarray(out, "RGBA"), ((i % o.cols) * o.cell, (i // o.cols) * o.cell))
    path = os.path.join(ROOT, "assets", "vfx", o.name + ".png")
    sheet.save(path, optimize=True)
    print(f'{o.name}: {len(names)} кадров, сетка {o.cols}x{rows} -> {path}  FLIPBOOKS: "{o.name}": [{o.cols}, {rows}, {len(names)}]')


if __name__ == "__main__":
    main()
