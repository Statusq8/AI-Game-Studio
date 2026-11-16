#!/usr/bin/env python3
"""Живые панды в окнах: исходная картинка для PixVerse и нарезка видео обратно в координаты референса окна.

python3 tools/winpanda.py src NAME OUT.jpg      — панда из референса окна на ровном синем фоне (1024×1024)
python3 tools/winpanda.py cut NAME VIDEO [--fps 10] [--start S] [--dur D]
    — кадры assets/anim/win_NAME/NN.webp + meta.json {"x","y","w","h","fps","n"}: (x, y) — левый верх кадра
      в пикселях референса окна. Камера PixVerse часто «наезжает» — каждый кадр выравнивается по первому
      (подобие по особым точкам), так что панда остаётся на месте и в своём размере.

NAME: prelevel (окно перед уровнем) или pause (окно паузы).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from winbuild import hsv  # noqa: E402
from vidcut import key  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFS = os.path.join(os.path.dirname(ROOT), "docs", "games", "match3", "references")
SIZE = 1024
BG = (30, 144, 255)


def _cut_prelevel(h, s, v, yy, xx):
    g = (h > 0.09) & (h < 0.17) & (s > 0.55) & (v > 0.6) & (yy > 440) & (xx > 250)
    return cv2.dilate(g.astype(np.uint8), np.ones((7, 7), np.uint8)).astype(bool) | (yy >= 532)


PANDAS = {
    "prelevel": dict(ref="screen_05_prelevel.webp", box=(45, 185, 470, 545),
                     fgd=[((220, 330), 60), ((395, 345), 30), ((200, 220), 30), ((380, 300), 16)],
                     yel=(335, 195, 445, 300), cut=_cut_prelevel),
    "pause": dict(ref="screen_06_pause.webp", box=(445, 285, 762, 616),
                  fgd=[((600, 470), 90), ((640, 360), 40)], yel=(465, 300, 540, 385),
                  cut=lambda h, s, v, yy, xx: yy >= 598),
}


def panda_mask(name):
    p = PANDAS[name]
    im = np.asarray(Image.open(os.path.join(REFS, p["ref"])).convert("RGB")).copy()
    H, W = im.shape[:2]
    h, s, v = hsv(im)
    pm = np.zeros((H, W), np.uint8)
    x0, y0, x1, y1 = p["box"]
    pm[y0:y1, x0:x1] = cv2.GC_PR_FGD
    for c, r in p["fgd"]:
        cv2.circle(pm, c, r, cv2.GC_FGD, -1)
    b = np.zeros((1, 65)); f = np.zeros((1, 65))
    cv2.grabCut(cv2.cvtColor(im, cv2.COLOR_RGB2BGR), pm, (x0, y0, x1 - x0, y1 - y0), b, f, 8, cv2.GC_INIT_WITH_MASK)
    m = (pm == cv2.GC_FGD) | (pm == cv2.GC_PR_FGD)
    yy, xx = np.mgrid[0:H, 0:W]
    m &= ~p["cut"](h, s, v, yy, xx)
    yx0, yy0, yx1, yy1 = p["yel"]
    yel = (h > 0.11) & (h < 0.18) & (s > 0.7) & (v > 0.85)
    z = np.zeros_like(yel)
    z[yy0:yy1, yx0:yx1] = yel[yy0:yy1, yx0:yx1]
    n, lab, st, _ = cv2.connectedComponentsWithStats(m.astype(np.uint8))
    m = lab == 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA]))
    m = ndi.binary_fill_holes(cv2.morphologyEx((m | z).astype(np.uint8), cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8)))
    return im, m


def placement(m):
    """Где панда из референса лежит на исходной картинке: (x0, y0) обрезки в референсе, масштаб, сдвиг на картинке."""
    ys, xs = np.where(m)
    x0, y0, x1, y1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    sc = min(SIZE * 0.7 / (x1 - x0), SIZE * 0.75 / (y1 - y0))
    w, h = int((x1 - x0) * sc), int((y1 - y0) * sc)
    ox, oy = (SIZE - w) // 2, SIZE - h - int(SIZE * 0.08)
    return (int(x0), int(y0), int(x1), int(y1)), sc, (ox, oy), (w, h)


def make_src(name, out):
    im, m = panda_mask(name)
    (x0, y0, x1, y1), sc, (ox, oy), (w, h) = placement(m)
    a = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 0.8)[y0:y1, x0:x1, None]
    comp = im[y0:y1, x0:x1].astype(np.float32) * a + np.array(BG, np.float32) * (1 - a)
    ci = Image.fromarray(comp.clip(0, 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    c = Image.new("RGB", (SIZE, SIZE), BG)
    c.paste(ci, (ox, oy))
    c.save(out, quality=95)


def similarity(src_rgba, dst_rgba):
    """Подобие (масштаб, поворот, сдвиг), переводящее src в dst — по особым точкам непрозрачной части."""
    g1 = cv2.cvtColor(src_rgba[..., :3], cv2.COLOR_RGB2GRAY)
    g2 = cv2.cvtColor(dst_rgba[..., :3], cv2.COLOR_RGB2GRAY)
    m1 = (src_rgba[..., 3] > 128).astype(np.uint8) * 255
    m2 = (dst_rgba[..., 3] > 128).astype(np.uint8) * 255
    orb = cv2.SIFT_create(3000)
    k1, d1 = orb.detectAndCompute(g1, m1)
    k2, d2 = orb.detectAndCompute(g2, m2)
    if d1 is None or d2 is None or len(k1) < 8 or len(k2) < 8:
        return None
    bf = cv2.BFMatcher()
    ms = bf.knnMatch(d1, d2, k=2)
    good = [a for a, b in ms if a.distance < 0.75 * b.distance]
    if len(good) < 8:
        return None
    p1 = np.float32([k1[g.queryIdx].pt for g in good])
    p2 = np.float32([k2[g.trainIdx].pt for g in good])
    M, inl = cv2.estimateAffinePartial2D(p1, p2, method=cv2.RANSAC, ransacReprojThreshold=4.0, maxIters=5000)
    return M


def cut(name, video, fps, start, dur):
    im, m = panda_mask(name)
    (x0, y0, x1, y1), sc, (ox, oy), _ = placement(m)
    tmp = tempfile.mkdtemp()
    cmd = ["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-i", video]
    if dur > 0:
        cmd += ["-t", str(dur)]
    cmd += ["-vf", "fps=%g" % fps, os.path.join(tmp, "%04d.png")]
    subprocess.run(cmd, check=True)
    names = sorted(f for f in os.listdir(tmp) if f.endswith(".png"))
    frames = [np.asarray(key(Image.open(os.path.join(tmp, n)))) for n in names]
    vw = frames[0].shape[1]
    # кадр видео → исходная картинка (1024) → референс: p_ref = (p_src - o) / sc + (x0, y0)
    to_src = SIZE / float(vw)
    A = np.array([[to_src / sc, 0, -ox / sc + x0], [0, to_src / sc, -oy / sc + y0]], np.float64)
    # первый кадр — к исходной картинке (PixVerse может чуть сдвинуть/увеличить с самого начала)
    src_img = Image.new("RGB", (SIZE, SIZE), BG)
    (sx0, sy0, sx1, sy1), _, (sox, soy), (sw, sh) = placement(m)
    a = cv2.GaussianBlur(m.astype(np.float32), (0, 0), 0.8)[sy0:sy1, sx0:sx1, None]
    comp = im[sy0:sy1, sx0:sx1].astype(np.float32) * a + np.array(BG, np.float32) * (1 - a)
    src_img.paste(Image.fromarray(comp.clip(0, 255).astype(np.uint8)).resize((sw, sh), Image.LANCZOS), (sox, soy))
    src_k = np.asarray(key(src_img.resize((vw, vw), Image.LANCZOS)))
    M0 = similarity(frames[0], src_k)
    if M0 is not None:
        A = (np.vstack([A, [0, 0, 1]]) @ np.vstack([M0, [0, 0, 1]]))[:2]
        print("frame0→src scale %.3f shift %.1f %.1f" % (np.hypot(M0[0, 0], M0[1, 0]), M0[0, 2], M0[1, 2]))
    # выравнивание по первому кадру
    Ms = [np.array([[1, 0, 0], [0, 1, 0]], np.float64)]
    for i in range(1, len(frames)):
        M = similarity(frames[i], frames[0])
        if M is None:
            M = Ms[-1]
        Ms.append(M)
    # сглаживание масштаба/сдвига по времени
    P = np.array([[np.hypot(M[0, 0], M[1, 0]), M[0, 2], M[1, 2]] for M in Ms])
    ker = np.ones(5) / 5.0
    for j in range(3):
        P[:, j] = np.convolve(np.pad(P[:, j], 2, mode="edge"), ker, mode="valid")
    out_frames = []
    for i, f in enumerate(frames):
        s_, tx, ty = P[i]
        M = np.array([[s_, 0, tx], [0, s_, ty]], np.float64)
        M3 = np.vstack([M, [0, 0, 1]])
        A3 = np.vstack([A, [0, 0, 1]])
        T = (A3 @ M3)[:2]
        out_frames.append(T)
    # общая рамка всех кадров в координатах референса
    boxes = []
    warped = []
    W_, H_ = 852, 1846
    for f, T in zip(frames, out_frames):
        w = cv2.warpAffine(f, T, (W_, H_), flags=cv2.INTER_AREA, borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0))
        warped.append(w)
        ys, xs = np.where(w[..., 3] > 20)
        if len(xs):
            boxes.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    bx0 = max(0, min(b[0] for b in boxes) - 2)
    by0 = max(0, min(b[1] for b in boxes) - 2)
    bx1 = min(W_, max(b[2] for b in boxes) + 2)
    by1 = min(H_, max(b[3] for b in boxes) + 2)
    outdir = os.path.join(ROOT, "assets", "anim", "win_" + name)
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)
    # кадры храним в 0.8 размера референса (на экране окно ≈ 0.85 референса) — меньше памяти видеокарты
    for i, w in enumerate(warped):
        fr = Image.fromarray(w[by0:by1, bx0:bx1], "RGBA")
        fr = fr.resize((round(fr.size[0] * 0.8), round(fr.size[1] * 0.8)), Image.LANCZOS)
        fr.save(os.path.join(outdir, "%02d.webp" % i), quality=88, method=6)
    meta = {"x": int(bx0), "y": int(by0), "w": int(bx1 - bx0), "h": int(by1 - by0), "fps": fps, "n": len(warped)}
    with open(os.path.join(outdir, "meta.json"), "w") as fh:
        json.dump(meta, fh)
    print(json.dumps(meta), "scales:", " ".join("%.2f" % p[0] for p in P))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["src", "cut"])
    ap.add_argument("name", choices=list(PANDAS))
    ap.add_argument("path")
    ap.add_argument("--fps", type=float, default=10)
    ap.add_argument("--start", type=float, default=0)
    ap.add_argument("--dur", type=float, default=0)
    o = ap.parse_args()
    if o.cmd == "src":
        make_src(o.name, o.path)
    else:
        cut(o.name, o.path, o.fps, o.start, o.dur)


if __name__ == "__main__":
    main()
