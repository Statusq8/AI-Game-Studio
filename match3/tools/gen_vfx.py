"""Покадровые эффекты «Зоопарка мечты» (рендер кодом, свои — без чужих ассетов).
Каждый эффект — лист кадров (сетка cols×rows) в assets/vfx/<name>.png. Запуск: python3 tools/gen_vfx.py"""
import numpy as np, os
from PIL import Image
from scipy.ndimage import map_coordinates, gaussian_filter, zoom

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "vfx")
rng = np.random.default_rng(11)


def noise_tex(n=512, octaves=6, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((n, n))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        g = 4 * 2 ** o
        grid = r.random((g + 1, g + 1))
        grid[-1, :] = grid[0, :]; grid[:, -1] = grid[:, 0]
        acc += amp * zoom(grid, n / (g + 1), order=3)[:n, :n]
        tot += amp; amp *= 0.5
    acc /= tot
    return (acc - acc.min()) / (acc.max() - acc.min())


NOISE = noise_tex(512, 6, 3)
NOISE2 = noise_tex(512, 5, 9)


def sample(tex, x, y):
    n = tex.shape[0]
    return map_coordinates(tex, [(y % 1.0) * (n - 1), (x % 1.0) * (n - 1)], order=1, mode="wrap")


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def grid(size):
    v = (np.arange(size) + 0.5) / size * 2 - 1
    x, y = np.meshgrid(v, v)
    return x, y, np.sqrt(x * x + y * y)


def shade(density, strength=0.9):
    gy, gx = np.gradient(gaussian_filter(density, 1.5))
    light = -(gx * -0.6 + gy * -0.8) * 18.0   # свет сверху-слева
    return np.clip(1.0 + strength * light, 0.45, 1.6)


def sheet(frames, cols):
    rows = (len(frames) + cols - 1) // cols
    h, w = frames[0].shape[:2]
    out = np.zeros((rows * h, cols * w, 4), np.float32)
    for i, f in enumerate(frames):
        r, c = divmod(i, cols)
        out[r * h:(r + 1) * h, c * w:(c + 1) * w] = f
    return out


def save(name, frames, cols):
    s = np.clip(sheet(frames, cols), 0, 1)
    Image.fromarray((s * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    print(name, len(frames), "frames")


def ramp(temp):
    """Цвет огня по «температуре»: белый → жёлтый → оранжевый → красный → бурый дым."""
    stops = [(0.0, (0.62, 0.58, 0.6)), (0.22, (0.78, 0.5, 0.36)), (0.4, (0.95, 0.35, 0.08)),
             (0.62, (1.0, 0.62, 0.12)), (0.82, (1.0, 0.88, 0.35)), (1.0, (1.0, 1.0, 0.9))]
    t = np.clip(temp, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (a, ca), (b, cb) in zip(stops[:-1], stops[1:]):
        m = (t >= a) & (t <= b)
        k = ((t - a) / (b - a))[m][:, None]
        out[m] = np.array(ca) * (1 - k) + np.array(cb) * k
    return out


def puffs_render(size, puffs, light=(-0.55, -0.7, 0.45)):
    """Рисует набор круглых «клубов» (сферы со светом). puffs: (cx, cy, rad, rgb, alpha, depth).
    Возвращает RGBA. Ближний клуб (больше z+depth) перекрывает дальний — читается объём."""
    x, y, r = grid(size)
    L = np.array(light); L = L / np.linalg.norm(L)
    best = np.full((size, size), -9.0)
    out = np.zeros((size, size, 4))
    px = 2.0 / size
    for (cx, cy, rad, rgb, al, depth) in puffs:
        if rad <= 0.005 or al <= 0.01:
            continue
        dx, dy = (x - cx) / rad, (y - cy) / rad
        d2 = dx * dx + dy * dy
        inside = d2 < 1.0
        z = np.sqrt(np.clip(1 - d2, 0, 1))
        score = z * rad + depth
        m = inside & (score > best)
        if not m.any():
            continue
        lam = np.clip(dx * L[0] + dy * L[1] + z * L[2], 0, 1)
        spec = np.clip(dx * -0.45 + dy * -0.6 + z * 0.66, 0, 1) ** 24
        rim = 1 - z
        c = np.array(rgb)[None, None, :] * (0.55 + 0.6 * lam[..., None]) + spec[..., None] * 0.35 - rim[..., None] * 0.12
        edge = np.clip((1 - np.sqrt(d2)) * rad / px, 0, 1)   # сглаженный край
        best[m] = score[m]
        out[m, :3] = c[m]
        out[m, 3] = np.maximum(out[m, 3], (edge * al)[m])
    out[..., :3] = np.clip(out[..., :3], 0, 1)
    return out


def fire_color(temp):
    return tuple(ramp(np.array([[temp]]))[0, 0])


def explosion(size=256, n=22):
    """Мультяшный взрыв из объёмных клубов: белое ядро → жёлто-оранжевый огонь → серый дым, искры-лучи."""
    x, y, r = grid(size)
    base = []
    for k in range(16):
        th = k / 16 * 2 * np.pi + rng.uniform(-0.2, 0.2)
        base.append((th, rng.uniform(0.45, 1.0), rng.uniform(0.75, 1.15), rng.uniform(0, 0.25)))
    inner = [(rng.uniform(0, 2 * np.pi), rng.uniform(0.0, 0.35), rng.uniform(0.9, 1.2)) for _ in range(7)]
    frames = []
    for i in range(n):
        t = i / (n - 1)
        grow = 1 - (1 - min(1.0, t / 0.55)) ** 3
        puffs = []
        for th, dist, rs, dl in base:
            d = dist * (0.12 + 0.55 * grow) + 0.06 * t
            rad = rs * (0.12 + 0.22 * grow) * (1 - 0.35 * max(0, t - 0.6) / 0.4)
            temp = (1.15 - 1.05 * t ** 0.9) * (1.1 - 0.35 * dist) - dl * t
            puffs.append((np.cos(th) * d, np.sin(th) * d - 0.08 * t, rad, fire_color(temp), 1 - smooth(0.5, 0.95, t), -dist * 0.2))
        for th, dist, rs in inner:
            d = dist * (0.1 + 0.35 * grow)
            rad = rs * (0.16 + 0.2 * grow) * (1 - 0.6 * t)
            temp = 1.3 - 1.1 * t ** 0.8
            puffs.append((np.cos(th) * d, np.sin(th) * d - 0.1 * t, rad, fire_color(temp), 1 - smooth(0.6, 0.95, t), 0.3))
        f = puffs_render(size, puffs)
        # искры-лучи
        if t < 0.5:
            for k in range(12):
                th = k / 12 * 2 * np.pi + 0.13
                d0, d1 = 0.2 + 1.2 * t, 0.36 + 1.4 * t
                pxx = np.cos(th) * x + np.sin(th) * y
                pyy = -np.sin(th) * x + np.cos(th) * y
                m = np.exp(-(pyy / (0.024 * (1 - t))) ** 2) * smooth(d0, d0 + 0.04, pxx) * smooth(d1 + 0.15, d1 - 0.1, pxx) * (1 - t / 0.5)
                f[..., :3] = f[..., :3] * (1 - m[..., None]) + np.array([1.0, 0.95, 0.65]) * m[..., None]
                f[..., 3] = np.maximum(f[..., 3], m)
        # белая вспышка в первых кадрах
        if t < 0.18:
            fl = np.exp(-(r / (0.3 + 0.8 * t)) ** 2) * (1 - t / 0.18)
            f[..., :3] = f[..., :3] * (1 - fl[..., None]) + fl[..., None]
            f[..., 3] = np.maximum(f[..., 3], fl)
        # мягкость: лёгкое размытие, чтобы клубы не выглядели пластиковыми
        for ch in range(4):
            f[..., ch] = gaussian_filter(f[..., ch], 1.1)
        frames.append(f)
    save("explosion", frames, 6)


def pop(size=192, n=12):
    """Лопание фишки: белая (тонируется цветом фишки) вспышка, кольцо, разлёт осколков-звёзд."""
    x, y, r = grid(size)
    frames = []
    shards = [(k / 9 * 2 * np.pi + rng.uniform(-0.2, 0.2), rng.uniform(0.75, 1.0)) for k in range(9)]
    for i in range(n):
        t = i / (n - 1)
        f = np.zeros((size, size, 4))
        core = np.exp(-(r / (0.18 + 0.25 * t)) ** 2) * (1 - t) ** 1.5
        ring_r = 0.2 + 0.65 * (1 - (1 - t) ** 2)
        ring = np.exp(-((r - ring_r) / (0.05 + 0.04 * t)) ** 2) * (1 - t) ** 1.2
        a = np.clip(core * 1.3 + ring * 0.8, 0, 1)
        for th, sp in shards:
            d = (0.15 + 0.75 * sp * (1 - (1 - t) ** 2.2))
            cx, cy = np.cos(th) * d, np.sin(th) * d
            dx, dy = x - cx, y - cy
            sz = 0.07 * (1 - t) + 0.01
            star = np.maximum(np.exp(-(dx / (sz * 0.25)) ** 2 - (dy / sz) ** 2), np.exp(-(dy / (sz * 0.25)) ** 2 - (dx / sz) ** 2))
            star = np.maximum(star, np.exp(-(dx * dx + dy * dy) / (sz * 0.5) ** 2))
            a = np.maximum(a, star * (1 - t ** 3))
        f[..., :3] = 1.0
        f[..., 3] = a
        frames.append(f)
    save("pop", frames, 4)


def birth(size=256, n=18):
    """Рождение бонуса: золотые струи закручиваются внутрь, затем вспышка и ударное кольцо."""
    x, y, r = grid(size)
    ang = np.arctan2(y, x)
    frames = []
    for i in range(n):
        t = i / (n - 1)
        f = np.zeros((size, size, 4))
        col = np.array([1.0, 0.86, 0.38])
        a = np.zeros((size, size))
        if t < 0.6:
            u = t / 0.6
            R = 1.0 - 0.85 * u
            spiral = np.sin(ang * 5 + r * 9 - u * 10) * 0.5 + 0.5
            band = np.exp(-((r - R) / 0.22) ** 2) * (r < R + 0.25)
            a = smooth(0.55, 0.95, spiral) * band * (0.4 + 0.6 * u)
            a += np.exp(-(r / (0.12 + 0.1 * u)) ** 2) * u * 0.9
        else:
            u = (t - 0.6) / 0.4
            flash = np.exp(-(r / (0.25 + 0.5 * u)) ** 2) * (1 - u) ** 1.3 * 1.4
            ring = np.exp(-((r - (0.15 + 0.8 * u)) / 0.06) ** 2) * (1 - u)
            rays = (np.cos(ang * 8) * 0.5 + 0.5) ** 6 * np.exp(-r / (0.4 + 0.5 * u)) * (1 - u)
            a = flash + ring * 0.9 + rays * 0.7
        a = np.clip(a, 0, 1)
        f[..., :3] = col * 0.6 + 0.4 * a[..., None] ** 0.5
        f[..., 3] = a
        frames.append(f)
    save("birth", frames, 6)


def smoke(size=160, n=16):
    """Клуб мультяшного дыма: 5 объёмных шариков, растут, поднимаются и тают."""
    parts = [(0, 0, 1.0), (-0.45, 0.15, 0.7), (0.45, 0.12, 0.75), (-0.2, -0.35, 0.65), (0.25, -0.3, 0.7)]
    frames = []
    for i in range(n):
        t = i / (n - 1)
        grow = 1 - (1 - t) ** 2
        puffs = []
        for (cx, cy, rs) in parts:
            rad = rs * (0.25 + 0.3 * grow)
            puffs.append((cx * (0.4 + 0.5 * grow), cy * (0.4 + 0.5 * grow) - 0.3 * t, rad, (0.98, 0.96, 0.92), 1 - t ** 1.7, rs * 0.1))
        frames.append(puffs_render(size, puffs))
    save("smoke", frames, 4)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    explosion(); pop(); birth(); smoke()
