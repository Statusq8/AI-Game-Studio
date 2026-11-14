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


def fbm(x, y, t, tex=None):
    tex = NOISE if tex is None else tex
    return (sample(tex, x, y) * 0.55 + sample(NOISE2, x * 2.1 + 0.37 * t, y * 2.1 - 0.29 * t) * 0.3
            + sample(tex, x * 4.3 - 0.2 * t, y * 4.3 + 0.5) * 0.15)


def explosion(size=256, n=24, name="explosion", cols=6):
    """Мультяшный огненный взрыв: вспышка → клубящийся огненный шар с рваным краем и языками пламени
    (горячее ядро белое→жёлтое, край оранжево-красный) → остывает в тёмный дым и тает. Плюс искры."""
    x, y, r = grid(size)
    ang = np.arctan2(y, x)
    sparks = [(rng.uniform(0, 2 * np.pi), rng.uniform(0.9, 1.5), rng.uniform(0.6, 1.0)) for _ in range(18)]
    frames = []
    for i in range(n):
        t = i / (n - 1)
        grow = 1 - (1 - min(1.0, t / 0.45)) ** 3
        R = 0.18 + 0.62 * grow + 0.08 * t
        # искажение пространства — клубы «текут» наружу и вверх
        wx = (sample(NOISE, x * 0.3 + 0.1, y * 0.3 + 0.3 + 0.05 * t) - 0.5) * 0.3
        wy = (sample(NOISE, x * 0.3 + 0.6, y * 0.3 - 0.2 - 0.05 * t) - 0.5) * 0.3
        xx, yy = x + wx, y + wy + 0.12 * t * t
        rr = np.sqrt(xx * xx + yy * yy)
        billow = fbm(xx * 0.45 - 0.08 * t, yy * 0.45 + 0.15 * t, t * 3)
        tongues = (np.sin(ang * 9 + billow * 6) * 0.5 + 0.5) ** 3 * smooth(0.0, 0.5, t) * (1 - t)
        edge = rr / R + (billow - 0.5) * 0.7 - tongues * 0.22
        dens = smooth(1.08, 0.62, edge)
        # к концу середина выгорает
        dens *= 1 - 0.6 * smooth(0.45, 1.0, t) * smooth(0.55, 0.0, rr / R)
        heat = (1.0 - rr / R) * 1.25 + (billow - 0.5) * 0.7
        heat = heat * (1.15 - 1.05 * t ** 0.75) + 0.35 * (1 - t)
        col = ramp(heat)
        # мягкий объём: подсветка сверху-слева по градиенту плотности
        sh = shade(dens, 0.55)[..., None]
        # объём без смены оттенка: тень — темнее, свет — к белому (иначе край зеленит)
        col = np.where(sh < 1, col * (0.75 + 0.25 * sh), col + (1 - col) * np.clip(sh - 1, 0, 1) * 0.35)
        col = np.clip(col, 0, 1)
        # дым темнеет и сереет к концу
        smoke_k = smooth(0.35, 0.9, t) * smooth(0.55, 0.15, heat)
        col = col * (1 - smoke_k[..., None]) + np.array([0.33, 0.28, 0.34]) * smoke_k[..., None] * shade(dens, 0.9)[..., None]
        a = dens * (1 - smooth(0.7, 1.0, t))
        a = gaussian_filter(a, 0.8)
        f = np.zeros((size, size, 4))
        f[..., :3] = np.clip(col, 0, 1)
        f[..., 3] = np.clip(a, 0, 1)
        # свечение вокруг огня (пока горячо)
        glow = np.exp(-(r / (R * 1.25)) ** 2) * (1 - t) ** 2 * 0.55
        add = glow * (1 - f[..., 3])
        f[..., :3] = (f[..., :3] * f[..., 3:4] + np.array([1.0, 0.7, 0.3]) * add[..., None]) / np.maximum(f[..., 3:4] + add[..., None], 1e-4)
        f[..., 3] = np.clip(f[..., 3] + add, 0, 1)
        # искры с хвостами
        if t < 0.75:
            for th, sp, br in sparks:
                d1 = 0.15 + sp * (1 - (1 - t) ** 2) * 0.95
                d0 = max(0.1, d1 - 0.18 * (1 - t))
                px = np.cos(th) * x + np.sin(th) * y
                py = -np.sin(th) * x + np.cos(th) * y + 0.25 * t * t * np.cos(th - np.pi / 2)
                m = np.exp(-(py / 0.014) ** 2) * smooth(d0, d0 + 0.05, px) * smooth(d1 + 0.01, d1 - 0.02, px)
                m = m * br * (1 - t / 0.75)
                f[..., :3] = f[..., :3] * (1 - m[..., None]) + np.array([1.0, 0.92, 0.55]) * m[..., None]
                f[..., 3] = np.maximum(f[..., 3], m)
        # белая вспышка в начале
        if t < 0.15:
            fl = np.exp(-(r / (0.25 + 1.2 * t)) ** 2) * (1 - t / 0.15)
            f[..., :3] = f[..., :3] * (1 - fl[..., None]) + fl[..., None]
            f[..., 3] = np.maximum(f[..., 3], fl)
        frames.append(f)
    save(name, frames, cols)


def zap(size=192, n=12):
    """Электрическая вспышка: бело-голубое ядро, ломаные молнии-лучи во все стороны, кольцо, затухание."""
    x, y, r = grid(size)
    ang = np.arctan2(y, x)
    bolts = [(k / 7 * 2 * np.pi + rng.uniform(-0.25, 0.25), rng.uniform(0.6, 0.95)) for k in range(7)]
    frames = []
    for i in range(n):
        t = i / (n - 1)
        a = np.exp(-(r / (0.2 + 0.25 * t)) ** 2) * (1 - t) ** 1.2 * 1.3
        ring = np.exp(-((r - (0.15 + 0.75 * (1 - (1 - t) ** 2))) / 0.05) ** 2) * (1 - t)
        a = a + ring * 0.7
        for th0, ln in bolts:
            # ломаная: угол дрожит с расстоянием (свой узор на каждом кадре)
            jag = (sample(NOISE, r * 1.8 + th0, np.full_like(r, 0.37 * i)) - 0.5) * 0.9
            th = th0 + jag * r
            d = np.abs(np.angle(np.exp(1j * (ang - th))))
            reach = ln * (0.35 + 0.65 * min(1.0, t / 0.35))
            w = 0.035 * (1 - r) + 0.01
            m = np.exp(-(d * r / w) ** 2) * smooth(reach, reach - 0.1, r) * (1 - smooth(0.4, 1.0, t))
            a = np.maximum(a, m)
        a = np.clip(a, 0, 1)
        f = np.zeros((size, size, 4))
        f[..., 0] = 0.75 + 0.25 * a
        f[..., 1] = 0.9 + 0.1 * a
        f[..., 2] = 1.0
        f[..., 3] = a
        frames.append(f)
    save("zap", frames, 4)


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
    explosion(); explosion(160, 16, "fireball", 4); zap(); pop(); birth(); smoke()
