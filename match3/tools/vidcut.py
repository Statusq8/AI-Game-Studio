#!/usr/bin/env python3
"""Нарезка ИИ-видео (зелёный фон) на кадры с прозрачностью для анимаций панды и животных.

python3 tools/vidcut.py VIDEO NAME [--fps 12] [--height 360] [--start 0] [--dur 0]

Кадры: assets/anim/NAME/NN.png (общая рамка для всех кадров, низ персонажа у нижнего края).
Зелёный фон вырезается по «зелёности» пикселя (g - max(r, b)), края смягчаются,
зелёная кайма на краях убирается (spill).
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def key(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    green = g - np.maximum(r, b)
    # 0 — точно фон, 1 — точно персонаж; между — мягкий край
    alpha = np.clip(1.0 - (green - 28.0) / (90.0 - 28.0), 0.0, 1.0)
    # убрать зелёный отсвет на краях: g не больше max(r, b) + немного
    lim = np.maximum(r, b) + 12.0
    g2 = np.where(g > lim, lim, g)
    out = np.dstack([r, g2, b, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("name")
    ap.add_argument("--fps", type=float, default=12)
    ap.add_argument("--height", type=int, default=360)
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--dur", type=float, default=0)
    o = ap.parse_args()
    tmp = tempfile.mkdtemp()
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-ss", str(o.start), "-i", o.video]
    if o.dur > 0:
        cmd += ["-t", str(o.dur)]
    cmd += ["-vf", f"fps={o.fps}", os.path.join(tmp, "%04d.png")]
    subprocess.run(cmd, check=True)
    names = sorted(f for f in os.listdir(tmp) if f.endswith(".png"))
    if not names:
        sys.exit("нет кадров")
    frames = [key(Image.open(os.path.join(tmp, n))) for n in names]
    # общая рамка по всем кадрам, чтобы персонаж не «прыгал»
    box = None
    for f in frames:
        bb = f.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
        if bb:
            box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    pad = 6
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(frames[0].width, box[2] + pad), min(frames[0].height, box[3] + pad))
    k = o.height / (box[3] - box[1])
    size = (max(1, round((box[2] - box[0]) * k)), o.height)
    out = os.path.join(ROOT, "assets", "anim", o.name)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    for i, f in enumerate(frames):
        f.crop(box).resize(size, Image.LANCZOS).save(os.path.join(out, "%02d.png" % i), optimize=True)
    shutil.rmtree(tmp)
    print(f"{o.name}: {len(frames)} кадров {size[0]}x{size[1]} -> {out}")


if __name__ == "__main__":
    main()
