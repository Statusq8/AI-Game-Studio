"""Звуки «Зоопарка мечты» в духе Royal Match: сочные хлопки фишек, звонкие колокольчики каскада,
«фшух» ракеты, плотный бум бомбы, хруст ящика, звон горшка, треск льда. Всё синтезируется кодом —
свои звуки, без чужих записей и лицензий.

Запуск: python3 tools/gen_sfx.py  → assets/audio/*.ogg (музыку не трогает — её делает gen_audio.py)."""
import os
import subprocess
import wave

import numpy as np
from scipy import signal

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(11)


def T(d):
    return np.arange(int(SR * d)) / SR


def env(d, a=0.002, decay=8.0, hold=0.0):
    x = T(d)
    e = np.minimum(1.0, x / max(a, 1e-5))
    tail = np.where(x > a + hold, np.exp(-(x - a - hold) * decay), 1.0)
    return e * tail


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, hi], btype="band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="low", fs=SR, output="sos"), x)


def hp(x, f, order=2):
    return signal.sosfilt(signal.butter(order, f, btype="high", fs=SR, output="sos"), x)


def sweep_bp(x, f0, f1, q=4.0, steps=40):
    """Полосовой фильтр, частота которого едет f0→f1 (шорох «фшух»)."""
    out = np.zeros_like(x)
    n = len(x)
    seg = n // steps + 1
    win = np.hanning(seg * 2)
    for i in range(steps):
        fc = f0 * (f1 / f0) ** (i / max(1, steps - 1))
        lo, hi = fc / (1 + 1 / q), min(fc * (1 + 1 / q), SR / 2 - 100)
        y = bp(x, lo, hi)
        st = max(0, i * seg - seg // 2)
        en = min(n, st + seg * 2)
        out[st:en] += y[st:en] * win[: en - st]
    return out


def osc(f, d, kind="sin"):
    """f — число или массив частот по времени (глиссандо)."""
    x = T(d)
    fa = np.broadcast_to(np.asarray(f, dtype=float), x.shape) if np.ndim(f) == 0 else f[: len(x)]
    ph = 2 * np.pi * np.cumsum(fa) / SR
    if kind == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    if kind == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    return np.sin(ph)


def chime(f, d=0.6, bright=1.0):
    """Звонкий колокольчик (стеклянный, как в каскадах Royal Match)."""
    x = T(d)
    s = (np.sin(2 * np.pi * f * x) * np.exp(-x * 5)
         + 0.45 * bright * np.sin(2 * np.pi * f * 2.0 * x) * np.exp(-x * 9)
         + 0.28 * bright * np.sin(2 * np.pi * f * 3.01 * x) * np.exp(-x * 14)
         + 0.16 * bright * np.sin(2 * np.pi * f * 4.17 * x) * np.exp(-x * 22))
    return s * np.minimum(1, x / 0.0015)


def marimba(f, d=0.4):
    x = T(d)
    s = np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * f * 3.9 * x) * np.exp(-x * 40)
    return s * env(d, 0.001, 9)


def pop(f0=900, f1=180, d=0.09):
    """Сочный «чпок»: тон, падающий по высоте, и щелчок."""
    x = T(d)
    f = f1 + (f0 - f1) * np.exp(-x * 45)
    s = osc(f, d) * env(d, 0.0008, 30)
    click = hp(noise(0.006), 2500) * np.linspace(1, 0, int(0.006 * SR))
    s[: len(click)] += click * 0.6
    return s


def place(out, s, at, g=1.0):
    st = int(at * SR)
    if st >= len(out):
        return out
    n = min(len(s), len(out) - st)
    out[st:st + n] += s[:n] * g
    return out


def canvas(d):
    return np.zeros(int(SR * d))


_IR = None


def reverb(x, wet=0.18, size=0.5):
    global _IR
    n = int(SR * size)
    ir = rng.uniform(-1, 1, n) * np.exp(-np.arange(n) / SR * 7.0 / size)
    ir = lp(ir, 6000)
    ir /= np.sqrt(np.sum(ir ** 2))
    pad = np.concatenate([x, np.zeros(n)])
    y = signal.fftconvolve(pad, ir)[: len(pad)]
    return pad * (1 - wet * 0.5) + y * wet


def soft_clip(x, drive=1.5):
    return np.tanh(x * drive) / np.tanh(drive)


def save(name, x, vol=0.85, verb=0.15, size=0.45):
    if verb > 0:
        x = reverb(x, verb, size)
    x = x - np.mean(x)
    # мягкий хвост: без щелчка в конце
    fade = min(len(x), int(0.02 * SR))
    x[-fade:] *= np.linspace(1, 0, fade)
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "5",
                    os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12)


# ---------- фишки ----------
# каскад: каждый следующий — на ступень выше по мажорной пентатонике (как «лесенка» в Royal Match)
CASCADE = [84, 86, 88, 91, 93, 96, 98, 100]
for i, m in enumerate(CASCADE):
    o = canvas(0.6)
    place(o, pop(1100 + i * 60, 220 + i * 20, 0.08), 0.0, 1.0)
    place(o, hp(noise(0.05), 1800) * env(0.05, 0.0005, 70), 0.0, 0.35)       # хруст
    place(o, chime(midi(m), 0.55, 0.9), 0.012, 0.55)
    place(o, chime(midi(m + 7), 0.35, 0.5), 0.02, 0.18)
    save("match_%d" % i, o, 0.62, 0.16)

o = canvas(0.2)
place(o, sweep_bp(noise(0.16), 900, 3200, 3.0) * env(0.16, 0.03, 18), 0.0, 1.0)
place(o, pop(700, 400, 0.05), 0.0, 0.25)
save("swap", o, 0.32, 0.08)

o = canvas(0.45)
place(o, marimba(midi(55), 0.2), 0.0, 1.0)
place(o, marimba(midi(51), 0.25), 0.12, 0.9)
place(o, pop(400, 120, 0.06), 0.0, 0.5)
save("bad", o, 0.45, 0.08)

o = canvas(0.08)
place(o, pop(520, 160, 0.05), 0.0, 1.0)
place(o, lp(noise(0.03), 1500) * env(0.03, 0.0005, 80), 0.0, 0.5)
save("land", o, 0.22, 0.0)

# бонус родился: «вжух» вверх + блёстки
o = canvas(1.0)
f = 300 * (6.0 ** np.clip(T(0.35) / 0.35, 0, 1))
place(o, (osc(f, 0.35, "tri") * 0.5 + osc(f * 2.01, 0.35) * 0.25) * env(0.35, 0.02, 4), 0.0, 0.7)
place(o, sweep_bp(noise(0.4), 600, 6000, 4.0) * env(0.4, 0.05, 6), 0.0, 0.5)
for k, m in enumerate([91, 96, 100, 103]):
    place(o, chime(midi(m), 0.4, 0.8), 0.25 + k * 0.045, 0.45)
save("special", o, 0.6, 0.22)

# ---------- бустеры ----------
# ракета: «фшшух» + свист, улетающий вдаль
o = canvas(0.9)
place(o, sweep_bp(noise(0.7), 400, 5000, 2.5) * env(0.7, 0.01, 4.5), 0.0, 1.0)
whf = 1800 * (0.45 ** (T(0.6) / 0.6))
place(o, osc(whf, 0.6) * env(0.6, 0.01, 5) * 0.35, 0.02)
place(o, pop(1600, 200, 0.07), 0.0, 0.6)
for k in range(10):  # искры-треск
    place(o, hp(noise(0.008), 3000) * np.linspace(1, 0, int(0.008 * SR)), 0.05 + k * 0.045 + rng.uniform(0, 0.02), 0.3)
save("rocket", o, 0.7, 0.18)

# бомба: плотный низкий удар, хруст, обломки
o = canvas(1.4)
x = T(0.7)
kick = np.sin(2 * np.pi * np.cumsum(38 + 140 * np.exp(-x * 22)) / SR) * env(0.7, 0.001, 4.5)
place(o, soft_clip(kick * 1.6, 2.0), 0.0, 1.0)
place(o, lp(noise(0.9), 900) * env(0.9, 0.002, 5), 0.0, 0.9)
place(o, hp(noise(0.12), 1500) * env(0.12, 0.0005, 30), 0.0, 0.5)
for k in range(14):
    place(o, bp(noise(0.03), 900, 4000) * env(0.03, 0.0005, 90), 0.12 + rng.uniform(0, 0.6), rng.uniform(0.1, 0.3))
save("bomb", soft_clip(o, 1.3), 0.95, 0.25, 0.8)

# бабочка: трепет крыльев + милый щебет
o = canvas(0.8)
x = T(0.6)
flap = (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 16 * x))) * bp(noise(0.6), 500, 2500)
place(o, flap * env(0.6, 0.05, 4), 0.0, 0.5)
for k, (a, b) in enumerate([(2200, 3200), (2600, 3800)]):
    xf = a * (b / a) ** (T(0.07) / 0.07)
    place(o, osc(xf, 0.07) * env(0.07, 0.004, 30), 0.12 + k * 0.1, 0.35)
place(o, chime(midi(96), 0.35, 0.6), 0.45, 0.35)
save("butterfly", o, 0.45, 0.15)

# шар: заряд-гудение вверх + электрический разряд
o = canvas(1.4)
f = 120 * (8 ** (T(0.5) / 0.5))
place(o, (osc(f, 0.5, "saw") * 0.25 + osc(f * 1.5, 0.5) * 0.3) * env(0.5, 0.2, 1.0), 0.0, 0.6)
for k in range(12):
    place(o, chime(midi(84 + (k * 5) % 24), 0.4, 0.8), 0.05 + k * 0.04, 0.22)
zz = hp(noise(0.5), 1500) * (np.abs(osc(55, 0.5, "saw")) > 0.6) * env(0.5, 0.002, 5)
place(o, zz, 0.45, 0.5)
save("orb", o, 0.7, 0.25, 0.7)

# короткий «ззт» — один прыжок цепной молнии
o = canvas(0.2)
x = T(0.12)
place(o, hp(noise(0.12), 2000) * (np.abs(osc(70, 0.12, "saw")) > 0.5) * env(0.12, 0.001, 25), 0.0, 1.0)
place(o, chime(midi(100), 0.15, 0.5), 0.0, 0.3)
save("zap", o, 0.35, 0.08)

# ---------- препятствия ----------
# ящик: сухой треск досок
o = canvas(0.6)
place(o, hp(noise(0.02), 1500) * env(0.02, 0.0003, 120), 0.0, 1.0)
body = sum(bp(noise(0.35), f * 0.9, f * 1.1) * g for f, g in ((260, 1.0), (520, 0.7), (980, 0.4)))
place(o, body * env(0.35, 0.001, 14) * 3.0, 0.0, 1.0)
for k in range(6):
    place(o, bp(noise(0.04), 600, 3000) * env(0.04, 0.0005, 60), 0.03 + rng.uniform(0, 0.22), rng.uniform(0.3, 0.7))
save("wood", o, 0.7, 0.12)

# горшок/банка: звон и осколки
o = canvas(0.8)
place(o, hp(noise(0.05), 2000) * env(0.05, 0.0003, 50), 0.0, 1.0)
for k in range(9):
    place(o, chime(rng.uniform(2200, 5200), 0.25, 0.4) * env(0.25, 0.001, 18), rng.uniform(0, 0.2), rng.uniform(0.25, 0.5))
place(o, bp(noise(0.3), 300, 900) * env(0.3, 0.001, 18), 0.0, 0.6)
save("glass", o, 0.6, 0.2)

# лёд: хрустальный треск
o = canvas(0.8)
place(o, hp(noise(0.03), 3000) * env(0.03, 0.0003, 90), 0.0, 1.0)
place(o, sweep_bp(noise(0.25), 5000, 1500, 5.0) * env(0.25, 0.001, 14), 0.0, 0.8)
for k, m in enumerate([100, 105, 108]):
    place(o, chime(midi(m), 0.4, 0.5), 0.02 + k * 0.03, 0.3)
save("ice", o, 0.55, 0.22)

# лиана: шорох листьев и «щёлк»
o = canvas(0.5)
place(o, pop(1400, 500, 0.04), 0.0, 0.8)
place(o, bp(noise(0.3), 1500, 6000) * env(0.3, 0.01, 12) * (0.6 + 0.4 * np.sin(2 * np.pi * 40 * T(0.3))), 0.01, 0.7)
save("vine", o, 0.5, 0.1)

# ---------- интерфейс ----------
o = canvas(0.2)
place(o, pop(1300, 600, 0.05), 0.0, 1.0)
place(o, chime(midi(91), 0.12, 0.3), 0.0, 0.25)
save("click", o, 0.38, 0.06)

o = canvas(0.6)
place(o, chime(midi(83), 0.12, 1.0), 0.0, 0.8)
place(o, chime(midi(88), 0.5, 1.0), 0.07, 1.0)
save("coin", o, 0.5, 0.15)

# цель собрана: короткий звонкий «плинк»
o = canvas(0.4)
place(o, chime(midi(96), 0.3, 0.9), 0.0, 1.0)
place(o, pop(1800, 900, 0.03), 0.0, 0.3)
save("goal", o, 0.4, 0.12)

# звезда в окне победы
o = canvas(1.0)
place(o, chime(midi(88), 0.8, 1.0), 0.0, 1.0)
place(o, chime(midi(95), 0.6, 0.7), 0.0, 0.5)
place(o, sweep_bp(noise(0.3), 2000, 8000, 4.0) * env(0.3, 0.01, 10), 0.0, 0.35)
save("star", o, 0.55, 0.3, 0.7)

# победа: фанфара (аккорд «духовых» + арпеджио колокольчиков)
o = canvas(2.6)
brass = lambda f, d: (osc(f, d, "saw") * 0.6 + osc(f * 2, d, "saw") * 0.2)
for k, (m, at, d) in enumerate([(67, 0.0, 0.16), (72, 0.16, 0.16), (76, 0.32, 0.16), (79, 0.48, 1.3)]):
    tone = lp(brass(midi(m), d), 2500) * env(d, 0.02, 2.0 if d > 1 else 6, 0.05)
    place(o, tone, at, 0.5)
for m in (60, 64, 67):
    place(o, lp(brass(midi(m), 1.3), 1800) * env(1.3, 0.03, 2.0, 0.1), 0.48, 0.25)
for k, m in enumerate([84, 88, 91, 96, 100, 103]):
    place(o, chime(midi(m), 0.8, 0.8), 0.5 + k * 0.07, 0.4)
save("win", o, 0.8, 0.3, 0.9)

# проигрыш: мягкое «уа-уа»
o = canvas(1.8)
for k, m in enumerate([67, 66, 65, 64]):
    d = 0.32 if k < 3 else 0.9
    f = midi(m) * (1 + 0.012 * np.sin(2 * np.pi * 5 * T(d)))
    tone = lp(osc(f, d, "saw") * 0.6 + osc(f * 2, d, "tri") * 0.2, 1400) * env(d, 0.03, 3 if k == 3 else 6, 0.05)
    place(o, tone, k * 0.3, 0.6)
save("lose", o, 0.6, 0.25, 0.8)
print("ok")
