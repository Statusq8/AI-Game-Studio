#!/usr/bin/env python3
"""Обрезает пустые поля у кадров анимации (общая рамка на все кадры) и пишет meta.json со смещением.

python3 tools/animpack.py assets/anim/panda_idle [...]
Холст кадра (из vidcut) сохраняется в meta: {"cw", "ch", "ox", "oy"} — игра рисует кадр со смещением,
поэтому персонаж стоит на том же месте, а в памяти телефона кадры занимают меньше.
"""
import glob
import json
import os
import sys

from PIL import Image

for d in sys.argv[1:]:
    fs = sorted(glob.glob(os.path.join(d, "*.webp")))
    ims = [Image.open(f) for f in fs]
    cw, ch = ims[0].size
    box = None
    for im in ims:
        b = im.getchannel("A").getbbox()
        if b:
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    for f, im in zip(fs, ims):
        im.crop(box).save(f, quality=86, method=6)
    json.dump({"cw": cw, "ch": ch, "ox": box[0], "oy": box[1]}, open(os.path.join(d, "meta.json"), "w"))
    print(os.path.basename(d), len(fs), "кадров", f"{box[2]-box[0]}x{box[3]-box[1]} из {cw}x{ch}")
