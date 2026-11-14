#!/usr/bin/env python3
"""Нарезка ИИ-видео (одноцветный фон) на кадры с прозрачностью для анимаций панды и животных.

python3 tools/vidcut.py VIDEO NAME [--fps 10] [--rest 256] [--canvas 320x384] [--start 0] [--dur 0]

Кадры: assets/anim/NAME/NN.webp на общем холсте CANVAS. Персонаж масштабируется так, чтобы
в первом кадре (поза покоя) его высота была REST px, ноги стоят на нижней линии холста,
по горизонтали — по центру. Так все анимации одного персонажа совпадают по размеру и месту.

Фон: цвет берётся с левого и правого края кадра в каждой строке (переживает градиент и
«уплывший» цвет — PixVerse часто делает фон не чисто зелёным), ключ по расстоянию цвета.
Остаётся только самый большой кусок — водяной знак и соринки удаляются.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def key(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    h, w, _ = a.shape
    e = max(4, w // 40)
    left = np.median(a[:, :e], axis=1)  # (h, 3)
    right = np.median(a[:, -e:], axis=1)
    t = np.linspace(0.0, 1.0, w)[None, :, None]
    bg = left[:, None, :] * (1 - t) + right[:, None, :] * t
    bg = cv2.GaussianBlur(bg, (0, 0), 6)
    d = np.sqrt(((a - bg) ** 2).sum(axis=2))
    alpha = np.clip((d - 38.0) / (80.0 - 38.0), 0.0, 1.0)
    # тень на «полу» того же цвета, что фон (ярко-зелёная/бирюзовая) — тоже фон;
    # у персонажа таких насыщенных зелёных и бирюзовых цветов нет (жилет оливковый)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    bgish = np.maximum(g - np.maximum(r, b), np.minimum(g, b) - r - 20.0)
    alpha *= np.clip((75.0 - bgish) / 20.0, 0.0, 1.0)
    # самый большой связный кусок (+ крупные части рядом)
    m = (alpha > 0.5).astype(np.uint8)
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    if n > 1:
        big = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
        keep = np.zeros(n, bool)
        keep[big] = True
        for i in range(1, n):
            if st[i, cv2.CC_STAT_AREA] > st[big, cv2.CC_STAT_AREA] * 0.03:
                keep[i] = True
        mask = keep[lab].astype(np.uint8)
        mask = cv2.dilate(mask, np.ones((5, 5), np.uint8))
        # дырки внутри силуэта не трогаем — заливаем
        ff = mask.copy()
        cv2.floodFill(ff, np.zeros((h + 2, w + 2), np.uint8), (0, 0), 2)
        mask = np.where(ff == 2, 0, 1)
        alpha *= mask
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.6)
    # убираем подмес фона на полупрозрачных краях
    ae = np.maximum(alpha, 0.05)[..., None]
    col = np.clip((a - (1 - ae) * bg) / ae, 0, 255)
    col = np.where(alpha[..., None] > 0.98, a, col)
    out = np.dstack([col, alpha * 255.0]).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out, "RGBA")


def bbox(f: Image.Image):
    return f.getchannel("A").point(lambda v: 255 if v > 60 else 0).getbbox()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("video")
    ap.add_argument("name")
    ap.add_argument("--fps", type=float, default=10)
    ap.add_argument("--rest", type=int, default=256)
    ap.add_argument("--canvas", default="320x384")
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--dur", type=float, default=0)
    ap.add_argument("--quality", type=int, default=86)
    o = ap.parse_args()
    cw, ch = (int(v) for v in o.canvas.split("x"))
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
    b0 = bbox(frames[0])
    k = o.rest / (b0[3] - b0[1])
    cx = (b0[0] + b0[2]) / 2.0
    foot = b0[3]
    out = os.path.join(ROOT, "assets", "anim", o.name)
    shutil.rmtree(out, ignore_errors=True)
    os.makedirs(out)
    clipped = 0
    for i, f in enumerate(frames):
        s = f.resize((round(f.width * k), round(f.height * k)), Image.LANCZOS)
        canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        ox = round(cw / 2 - cx * k)
        oy = round((ch - 4) - foot * k)
        canvas.paste(s, (ox, oy), s)
        bb = bbox(s)
        if bb and (bb[0] + ox < 0 or bb[1] + oy < 0 or bb[2] + ox > cw):
            clipped += 1
        canvas.save(os.path.join(out, "%02d.webp" % i), quality=o.quality, method=6)
    shutil.rmtree(tmp)
    print(f"{o.name}: {len(frames)} кадров, холст {cw}x{ch}, обрезано кадров: {clipped} -> {out}")


if __name__ == "__main__":
    main()
