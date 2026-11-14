"""Генератор звуков и музыки «Зоопарка мечты» (всё синтезируется кодом — свои звуки, без чужих лицензий).
Запуск: python3 tools/gen_audio.py  → assets/audio/*.ogg"""
import numpy as np, subprocess, os, wave
SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, a=0.005, r=0.2, shape=4.0):
    x = np.arange(n) / SR
    e = np.minimum(1, x / max(a, 1e-4)) * np.exp(-x * shape / max(r, 1e-3))
    return e


def bell(f, d=0.6, bright=1.0):
    x = t(d)
    s = (np.sin(2 * np.pi * f * x) + 0.5 * bright * np.sin(2 * np.pi * f * 2.76 * x) * np.exp(-x * 9)
         + 0.25 * bright * np.sin(2 * np.pi * f * 5.4 * x) * np.exp(-x * 16))
    return s * env(len(x), 0.002, d, 5)


def pluck(f, d=0.8, damp=0.996):
    """Карплус-Стронг: «укулеле»."""
    n = int(SR * d)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % p]
        buf[i % p] = damp * 0.5 * (buf[i % p] + buf[(i + 1) % p])
    return out * env(n, 0.001, d, 2.5)


def noise(d):
    return rng.uniform(-1, 1, int(SR * d))


def lowpass(x, k):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += k * (v - acc)
        y[i] = acc
    return y


def save(name, x, vol=0.8):
    x = x / (np.max(np.abs(x)) + 1e-9) * vol
    wav = os.path.join(OUT, name + ".wav")
    with wave.open(wav, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", os.path.join(OUT, name + ".ogg")], check=True)
    os.remove(wav)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def note(m):
    return 440.0 * 2 ** ((m - 69) / 12)


os.makedirs(OUT, exist_ok=True)
# фишки: пентатоника по нарастающей (каскад звучит всё выше)
penta = [72, 74, 76, 79, 81, 84, 86, 88]
for i, m in enumerate(penta):
    save(f"match_{i}", mix(bell(note(m), 0.45), 0.4 * bell(note(m + 12), 0.25, 0.5)), 0.6)
x = t(0.12); save("swap", np.sin(2 * np.pi * (500 + 900 * x / 0.12) * x) * env(len(x), 0.005, 0.1, 6), 0.35)
x = t(0.22); save("bad", np.sin(2 * np.pi * (300 - 120 * x / 0.22) * x) * env(len(x), 0.005, 0.2, 5), 0.45)
x = t(0.5); save("rocket", lowpass(noise(0.5), 0.3) * env(len(x), 0.02, 0.5, 3) + 0.3 * np.sin(2 * np.pi * (300 + 1500 * x) * x) * env(len(x), 0.01, 0.4, 5), 0.7)
x = t(0.9); save("bomb", (np.sin(2 * np.pi * (90 - 50 * x) * x) * 1.2 + lowpass(noise(0.9), 0.08)) * env(len(x), 0.003, 0.9, 4), 0.95)
orb = np.zeros(int(SR * 0.9))
for k, m in enumerate([76, 79, 83, 86, 88, 91, 95]):
    s = bell(note(m), 0.4); st = int(k * 0.07 * SR); orb[st:st + len(s)] += s[:len(orb) - st]
save("orb", orb, 0.7)
x = t(0.5); save("butterfly", noise(0.5) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * x)) * env(len(x), 0.05, 0.5, 4) * 0.5 + lowpass(noise(0.5), 0.05) * env(len(x), 0.05, 0.5, 4), 0.4)
x = t(0.25); save("wood", (lowpass(noise(0.25), 0.3) + 0.6 * np.sin(2 * np.pi * 180 * x)) * env(len(x), 0.001, 0.12, 8), 0.7)
x = t(0.3); save("glass", mix(bell(1800, 0.3), noise(0.3) * env(len(x), 0.001, 0.06, 10) * 0.6), 0.55)
spec = np.zeros(int(SR * 0.6))
for k, m in enumerate([72, 76, 79, 84]):
    s = bell(note(m), 0.35); st = int(k * 0.05 * SR); spec[st:st + len(s)] += s[:len(spec) - st]
save("special", spec, 0.6)
save("coin", mix(bell(note(93), 0.35), bell(note(100), 0.25)), 0.5)
x = t(0.08); save("click", np.sin(2 * np.pi * 900 * x) * env(len(x), 0.001, 0.04, 8), 0.35)
win = np.zeros(int(SR * 2.0))
for k, m in enumerate([72, 76, 79, 84, 79, 84, 88]):
    s = mix(pluck(note(m), 0.9), 0.6 * bell(note(m + 12), 0.5)); st = int([0, .12, .24, .36, .6, .72, .84][k] * SR); win[st:st + len(s)] += s[:len(win) - st]
save("win", win, 0.8)
lose = np.zeros(int(SR * 1.4))
for k, m in enumerate([67, 64, 60, 55]):
    s = pluck(note(m), 0.8); st = int(k * 0.22 * SR); lose[st:st + len(s)] += s[:len(lose) - st]
save("lose", lose, 0.7)


def music(name, bpm, chords, melody, bars_rep=2, swing=0.0, perc=True):
    """Простая своя мелодия: аккорды укулеле «бой» + мелодия колокольчиками + лёгкая перкуссия."""
    beat = 60 / bpm
    total = len(chords) * 4 * beat * bars_rep
    out = np.zeros(int(SR * total) + SR)
    pos = 0.0
    for rep in range(bars_rep):
        for ci, ch in enumerate(chords):
            for b in range(4):
                for half in range(2):
                    tt = pos + (b + half * (0.5 + swing)) * beat
                    for k, m in enumerate(ch):
                        s = pluck(note(m), 0.5, 0.993) * (0.5 if half else 0.7)
                        st = int((tt + k * 0.012) * SR); out[st:st + len(s)] += s[:len(out) - st]
                if perc:
                    s = lowpass(noise(0.06), 0.4) * env(int(0.06 * SR), 0.001, 0.03, 8) * (0.5 if b % 2 else 0.25)
                    st = int((pos + b * beat) * SR); out[st:st + len(s)] += s[:len(out) - st]
            pos += 4 * beat
    # мелодия
    pos = 0.0
    while pos < total - 0.01:
        for (m, dur) in melody:
            if pos >= total - 0.01:
                break
            if m:
                s = bell(note(m), min(1.2, dur * beat * 1.4), 0.6) * 0.55
                st = int(pos * SR); out[st:st + len(s)] += s[:len(out) - st]
            pos += dur * beat
    out = out[:int(SR * total)]
    # плавная склейка петли
    f = int(0.02 * SR); out[:f] *= np.linspace(0, 1, f); out[-f:] *= np.linspace(1, 0, f)
    save(name, out, 0.55)


C, G, Am, F, Dm, Em = [60, 64, 67, 72], [55, 62, 67, 71], [57, 64, 69, 72], [53, 60, 65, 69], [57, 62, 65, 69], [55, 59, 64, 67]
mel_menu = [(76, 1), (79, 1), (81, 1), (79, 1), (76, 2), (74, 2), (72, 1), (74, 1), (76, 1), (79, 1), (81, 2), (0, 2),
            (84, 1), (81, 1), (79, 1), (76, 1), (77, 2), (76, 2), (74, 1), (72, 1), (74, 1), (76, 1), (72, 2), (0, 2)]
# (старая укулеле-мелодия меню заменена вальсом ниже)
mel_level = [(72, 0.5), (76, 0.5), (79, 1), (76, 0.5), (79, 0.5), (81, 1), (79, 1), (76, 1), (74, 2),
             (72, 0.5), (74, 0.5), (76, 1), (79, 1), (77, 1), (76, 1), (74, 1), (72, 2), (0, 1),
             (76, 0.5), (79, 0.5), (84, 1), (81, 1), (79, 1), (77, 1), (76, 2), (74, 1), (72, 1), (74, 1), (76, 1), (72, 2), (0, 2)]
# (старая мелодия уровня заменена вальсом ниже)
print("ok")


# ---------- «волшебные» вальсы (решение 2026-11-14): своя мелодия, приём жанра — челеста, вальс 3/4, минор, арфа ----------
def celesta(f, d):
    x = t(d)
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.5 * x)
    s = (np.sin(2 * np.pi * f * vib * x) + 0.35 * np.sin(2 * np.pi * f * 2 * x) * np.exp(-x * 6)
         + 0.18 * np.sin(2 * np.pi * f * 3.01 * x) * np.exp(-x * 10) + 0.08 * np.sin(2 * np.pi * f * 4.2 * x) * np.exp(-x * 18))
    return s * env(len(x), 0.004, d, 3.2)


def pad(freqs, d):
    x = t(d)
    s = np.zeros(len(x))
    for f in freqs:
        s += np.sin(2 * np.pi * f * x) + 0.3 * np.sin(2 * np.pi * f * 2.003 * x)
    a = np.minimum(1, x / 0.25) * np.minimum(1, (d - x) / 0.3)
    return s * a / len(freqs)


def waltz(name, bpm, bars, melody):
    """bars: список аккордов (ноты MIDI), по такту 3/4. melody: (нота, доли)."""
    beat = 60 / bpm
    total = len(bars) * 3 * beat
    out = np.zeros(int(SR * total) + SR)

    def put(sig, at, g=1.0):
        st = int(at * SR)
        if st < len(out):
            out[st:st + len(sig)] += g * sig[:len(out) - st]

    for i, ch in enumerate(bars):
        t0 = i * 3 * beat
        put(pad([note(m) for m in ch[1:]], 3 * beat + 0.2), t0, 0.22)   # мягкие струнные
        put(pluck(note(ch[0] - 12), 1.4, 0.995), t0, 0.55)              # бас «раз»
        for b, k in [(1, 1), (2, 2)]:                                   # арфа «два-три»
            put(pluck(note(ch[k] ), 0.9, 0.994), t0 + b * beat, 0.32)
            put(pluck(note(ch[(k % 3) + 1] + 12), 0.7, 0.993), t0 + b * beat + 0.03, 0.2)
    pos = 0.0
    while pos < total - 0.01:
        for (m, dur) in melody:
            if pos >= total - 0.01:
                break
            if m:
                put(celesta(note(m), min(2.2, dur * beat + 0.8)), pos, 0.6)
                put(celesta(note(m + 12), min(1.0, dur * beat)), pos + 0.004, 0.12)  # искристый октавный призвук
            pos += dur * beat
    out = out[:int(SR * total)]
    # лёгкое «эхо зала»
    d = int(0.23 * SR)
    wet = np.zeros_like(out); wet[d:] = out[:-d] * 0.28; wet[2 * d:] += out[:-2 * d] * 0.12
    out = out + wet
    f = int(0.03 * SR); out[:f] *= np.linspace(0, 1, f); out[-f:] *= np.linspace(1, 0, f)
    save(name, out, 0.55)


Dm_, Gm_, A7_, Bb_, F_, C_, Edim_ = [50, 62, 65, 69], [55, 62, 67, 70], [57, 61, 64, 67], [58, 62, 65, 70], [53, 60, 65, 69], [48, 60, 64, 67], [52, 58, 64, 67]
menu_bars = [Dm_, Dm_, Gm_, Gm_, Bb_, F_, A7_, A7_, Dm_, Dm_, Gm_, C_, F_, Bb_, A7_, Dm_]
menu_mel = [(69, 1), (74, 1), (72, 1), (70, 2), (69, 1), (67, 1), (70, 1), (74, 1), (72, 3),
            (70, 1), (69, 1), (67, 1), (65, 2), (69, 1), (73, 2), (76, 1), (73, 3),
            (69, 1), (74, 1), (77, 1), (76, 2), (74, 1), (72, 1), (74, 1), (70, 1), (72, 3),
            (69, 1), (70, 1), (72, 1), (74, 2), (70, 1), (73, 1), (72, 1), (73, 1), (74, 3)]
waltz("music_menu", 84, menu_bars, menu_mel)
G_, Em_, Cmaj_, D7_, Am_, Bm_ = [55, 62, 67, 71], [52, 59, 64, 67], [48, 60, 64, 67], [50, 60, 62, 66], [57, 60, 64, 69], [59, 62, 66, 71]
lvl_bars = [G_, Em_, Cmaj_, D7_, G_, Bm_, Am_, D7_, Em_, Cmaj_, G_, D7_, Cmaj_, Am_, D7_, G_]
lvl_mel = [(74, 1), (79, 1), (78, 1), (76, 1), (74, 1), (71, 1), (72, 1), (76, 1), (79, 1), (78, 3),
           (74, 1), (76, 1), (78, 1), (79, 2), (83, 1), (81, 1), (79, 1), (76, 1), (78, 3),
           (79, 1), (76, 1), (71, 1), (72, 2), (76, 1), (74, 1), (71, 1), (67, 1), (69, 3),
           (72, 1), (76, 1), (74, 1), (72, 1), (69, 1), (66, 1), (67, 3), (0, 3)]
waltz("music_level", 112, lvl_bars, lvl_mel)
print("waltz ok")


# ---------- «волшебные» звуки (2026-11-14): челеста, искры, глиссандо арфы ----------
def sparkle(d=0.5, n=10, lo=84, hi=100):
    out = np.zeros(int(SR * d))
    for i in range(n):
        m = rng.integers(lo, hi)
        s_ = celesta(note(int(m)), 0.25) * rng.uniform(0.15, 0.4)
        st = int(rng.uniform(0, d * 0.7) * SR)
        out[st:st + len(s_)] += s_[:len(out) - st]
    return out


def gliss(ms, step, d_each=0.5, g=1.0, inst=None):
    inst = inst or (lambda f, d: pluck(f, d, 0.994))
    out = np.zeros(int(SR * (step * len(ms) + d_each)))
    for i, m in enumerate(ms):
        s_ = inst(note(m), d_each) * g
        st = int(i * step * SR)
        out[st:st + len(s_)] += s_
    return out


penta_m = [74, 77, 79, 81, 84, 86, 89, 91]
for i, m in enumerate(penta_m):
    save(f"match_{i}", mix(celesta(note(m), 0.5), 0.35 * celesta(note(m + 12), 0.3), sparkle(0.4, 3, m + 10, m + 20) * 0.6), 0.6)
x = t(0.18); save("swap", mix(lowpass(noise(0.18), 0.1) * env(len(x), 0.03, 0.15, 4) * 0.6, celesta(note(88), 0.18) * 0.25), 0.35)
save("bad", mix(celesta(note(62), 0.25), celesta(note(61), 0.25) * 0.8), 0.4)
x = t(0.7)
save("rocket", mix(lowpass(noise(0.7), 0.25) * env(len(x), 0.03, 0.6, 3) * 0.7, gliss([72, 76, 79, 84, 88, 91, 96], 0.05, 0.3, 0.7, celesta), sparkle(0.7, 8)), 0.65)
x = t(1.2)
save("bomb", mix((np.sin(2 * np.pi * (80 - 40 * x) * x) * 1.3 + lowpass(noise(1.2), 0.06)) * env(len(x), 0.003, 0.8, 4), sparkle(1.2, 18, 80, 100) * 1.2), 0.95)
save("orb", mix(gliss([62, 65, 69, 72, 74, 77, 81, 84, 86, 89, 93], 0.045, 0.6, 0.8), gliss([86, 89, 93, 98], 0.12, 0.5, 0.6, celesta), sparkle(1.0, 14)), 0.7)
x = t(0.7); save("butterfly", mix(noise(0.7) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * x)) * env(len(x), 0.08, 0.6, 4) * 0.25, gliss([84, 88, 91], 0.12, 0.4, 0.6, celesta)), 0.45)
x = t(0.3); save("wood", mix((lowpass(noise(0.3), 0.3) + 0.6 * np.sin(2 * np.pi * 170 * x)) * env(len(x), 0.001, 0.12, 8), sparkle(0.3, 3) * 0.6), 0.7)
save("glass", mix(celesta(1760, 0.4), noise(0.3) * env(int(0.3 * SR), 0.001, 0.05, 10) * 0.5, sparkle(0.4, 4)), 0.55)
save("special", mix(gliss([72, 76, 79, 84, 88], 0.06, 0.5, 1.0, celesta), sparkle(0.7, 8)), 0.6)
save("coin", mix(celesta(note(91), 0.4), celesta(note(96), 0.35)), 0.5)
save("click", celesta(note(84), 0.12), 0.3)
save("win", mix(gliss([62, 66, 69, 74, 78, 81, 86], 0.09, 1.2, 0.9, celesta), gliss([50, 57, 62], 0.0, 1.8, 0.6), sparkle(2.0, 20)), 0.8)
save("lose", gliss([74, 70, 67, 62], 0.24, 0.9, 1.0, celesta), 0.6)
print("magic sfx ok")


# ===================== v3: мультяшный стиль (плейтест 14.11) — перекрывает всё выше =====================
# Маримба, ксилофон, укулеле, пиццикато-бас, «боинги», лопающиеся пузыри, свистулька. Все мелодии свои.
from scipy.signal import lfilter


def lp(x, k):
    return lfilter([k], [1, k - 1], x)


def hp(x, k):
    return x - lp(x, k)


def place(out, s, at):
    st = int(at * SR)
    if st >= len(out):
        return
    n = min(len(s), len(out) - st)
    out[st:st + n] += s[:n]


def marimba(f, d=0.5, v=1.0):
    x = t(d)
    s = np.sin(2 * np.pi * f * x) + 0.35 * np.sin(2 * np.pi * f * 4.0 * x) * np.exp(-x * 30) + 0.12 * np.sin(2 * np.pi * f * 9.9 * x) * np.exp(-x * 60)
    return s * env(len(x), 0.001, d, 6) * v


def xylo(f, d=0.35, v=1.0):
    x = t(d)
    s = np.sin(2 * np.pi * f * x) + 0.5 * np.sin(2 * np.pi * f * 3.0 * x) * np.exp(-x * 25) + 0.25 * np.sin(2 * np.pi * f * 6.3 * x) * np.exp(-x * 45)
    return s * env(len(x), 0.0008, d, 8) * v


def boing(f0, d=0.4, down=True):
    x = t(d)
    wob = 1 + 0.35 * np.sin(2 * np.pi * 14 * x) * np.exp(-x * 7)
    glide = (1 - 0.45 * x / d) if down else (1 + 0.6 * x / d)
    ph = 2 * np.pi * np.cumsum(f0 * wob * glide) / SR
    return (np.sin(ph) + 0.3 * np.sin(2 * ph)) * env(len(x), 0.003, d, 4)


def bubble(f0=380, f1=1500, d=0.07):
    x = t(d)
    ph = 2 * np.pi * np.cumsum(f0 + (f1 - f0) * (x / d) ** 0.6) / SR
    return np.sin(ph) * env(len(x), 0.001, d, 3)


def whistle(f0, f1, d, vib=6.0):
    x = t(d)
    f = f0 * (f1 / f0) ** (x / d) * (1 + 0.02 * np.sin(2 * np.pi * vib * x))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) + 0.15 * np.sin(2 * ph)) * env(len(x), 0.02, d, 2.5)


def woodblock(f=900, d=0.08):
    x = t(d)
    return (np.sin(2 * np.pi * f * x) + 0.4 * np.sin(2 * np.pi * f * 1.6 * x)) * env(len(x), 0.0005, d, 9)


def shaker(d=0.07):
    return hp(noise(d), 0.5) * env(int(SR * d), 0.01, d, 6)


def clap(d=0.12):
    n = noise(d)
    e = np.zeros(len(n))
    for k in range(3):
        st = int(k * 0.011 * SR)
        e[st:] += env(len(n) - st, 0.0005, 0.05, 6)
    return hp(lp(n, 0.5), 0.15) * e


def kick(d=0.25):
    x = t(d)
    ph = 2 * np.pi * np.cumsum(55 + 110 * np.exp(-x * 30)) / SR
    return np.sin(ph) * env(len(x), 0.001, d, 5)


def pizz(f, d=0.35):
    return pluck(f, d, 0.985) * 1.2


def uke(ch, d=0.35, v=0.6, strum=0.012):
    out = np.zeros(int(SR * (d + 0.1)))
    for k, m in enumerate(ch):
        place(out, pluck(note(m), d, 0.992) * v, k * strum)
    return out


# --- звуки ---
cpenta = [72, 74, 76, 79, 81, 84, 86, 88]
for i, m in enumerate(cpenta):
    save(f"match_{i}", mix(bubble(350 + i * 40, 1300 + i * 120), np.concatenate([np.zeros(int(0.02 * SR)), marimba(note(m), 0.35)]) * 0.8), 0.6)
save("swap", whistle(700, 1400, 0.12, 0) * 0.8, 0.3)
save("bad", mix(boing(320, 0.22), np.concatenate([np.zeros(int(0.16 * SR)), boing(240, 0.3)])), 0.45)
x = t(0.65)
save("rocket", mix(whistle(500, 2400, 0.55, 9), hp(noise(0.65), 0.3) * env(len(x), 0.02, 0.6, 3) * 0.35, np.concatenate([np.zeros(int(0.5 * SR)), bubble(600, 2000, 0.08)])), 0.6)
x = t(1.0)
boom = mix(kick(0.6) * 1.6, lp(noise(1.0), 0.07) * env(len(x), 0.002, 0.8, 4) * 1.4)
for k in range(5):
    boom = mix(boom, np.concatenate([np.zeros(int((0.18 + k * 0.07) * SR)), bubble(300 + rng.integers(0, 500), 1400 + rng.integers(0, 800), 0.06) * 0.35]))
save("bomb", mix(boom, np.concatenate([np.zeros(int(0.25 * SR)), boing(180, 0.45) * 0.5])), 0.95)
orb = np.zeros(int(1.1 * SR))
for k, m in enumerate([60, 64, 67, 72, 76, 79, 84, 88, 91, 96]):
    place(orb, xylo(note(m), 0.3, 0.8), k * 0.045)
for k in range(6):
    place(orb, bubble(800, 2400, 0.05) * 0.3, 0.5 + k * 0.07)
save("orb", orb, 0.65)
x = t(0.6)
flutter = np.sin(2 * np.pi * np.cumsum(1300 + 250 * np.sin(2 * np.pi * 24 * x)) / SR) * env(len(x), 0.03, 0.5, 3) * (0.6 + 0.4 * np.sin(2 * np.pi * 24 * x))
save("butterfly", mix(flutter * 0.5, np.concatenate([np.zeros(int(0.35 * SR)), xylo(note(88), 0.25), np.zeros(int(0.0 * SR))])), 0.4)
save("wood", mix(woodblock(520, 0.12), woodblock(780, 0.08) * 0.5), 0.6)
save("glass", mix(xylo(note(100), 0.3), hp(noise(0.12), 0.4) * env(int(0.12 * SR), 0.0005, 0.05, 8) * 0.5), 0.5)
save("special", mix(boing(300, 0.3, down=False), np.concatenate([np.zeros(int(0.12 * SR)), whistle(900, 1800, 0.18, 0) * 0.6, np.zeros(1)]), np.concatenate([np.zeros(int(0.3 * SR)), bubble(700, 2200, 0.06)])), 0.55)
save("coin", mix(xylo(note(88), 0.25), np.concatenate([np.zeros(int(0.07 * SR)), xylo(note(95), 0.35)])), 0.45)
save("click", mix(bubble(500, 1400, 0.05), woodblock(1200, 0.04) * 0.3), 0.3)
# победа: дробь ксилофона + своя весёлая фанфара маримбой + тарелка-шейкер
win = np.zeros(int(2.4 * SR))
for k in range(10):
    place(win, xylo(note(72 + (k % 2) * 7), 0.12, 0.5), k * 0.035)
fan = [(72, 0.0), (76, 0.15), (79, 0.3), (84, 0.45), (79, 0.7), (84, 0.85)]
for m, at in fan:
    place(win, marimba(note(m), 0.6), 0.4 + at)
    place(win, marimba(note(m - 12), 0.6, 0.5), 0.4 + at)
place(win, uke([60, 64, 67, 72], 1.2, 0.9), 1.25)
place(win, whistle(1000, 2100, 0.35, 8) * 0.5, 1.25)
place(win, hp(noise(1.0), 0.6) * env(int(1.0 * SR), 0.005, 1.0, 3) * 0.35, 1.25)
save("win", win, 0.8)
# проигрыш: мультяшное «уа-уа-уаа» вниз (приглушённые ноты с «вау»-фильтром)
lose = np.zeros(int(2.2 * SR))
for k, (m, d) in enumerate([(67, 0.35), (66, 0.35), (65, 0.35), (64, 1.0)]):
    x = t(d)
    f = note(m - 12) * (1 + 0.012 * np.sin(2 * np.pi * (5 if k == 3 else 0) * x))
    ph = 2 * np.pi * np.cumsum(np.full(len(x), f)) / SR
    saw = sum(np.sin(h * ph) / h for h in range(1, 9))
    wah = 0.15 + 0.35 * (1 - np.cos(2 * np.pi * min(1.0, 2.0 / d) * x / 2)) / 2
    y = np.zeros(len(x)); acc = 0.0
    for i in range(len(x)):
        acc += wah[i] * (saw[i] - acc); y[i] = acc
    place(lose, y * env(len(x), 0.03, d, 1.2), k * 0.4)
save("lose", lose, 0.6)


# --- музыка: своя бодрая мелодия, маримба + укулеле + пиццикато + перкуссия ---
def toon(name, bpm, chords, melody, bass_pat, swing=0.12, reps=2):
    beat = 60 / bpm
    bar = 4 * beat
    total = len(chords) * bar * reps
    out = np.zeros(int(SR * total) + SR)
    for r in range(reps):
        for ci, (root, ch) in enumerate(chords):
            b0 = (r * len(chords) + ci) * bar
            for b in range(4):
                place(out, kick(0.2) * 0.5, b0 + b * beat) if b in (0, 2) else place(out, clap() * 0.35, b0 + b * beat)
                place(out, shaker() * 0.25, b0 + (b + 0.5 + swing) * beat)
                # укулеле на «и»
                place(out, uke(ch, 0.28, 0.35), b0 + (b + 0.5 + swing) * beat)
            for (off, iv) in bass_pat:
                place(out, pizz(note(root - 12 + iv), 0.32) * 0.9, b0 + off * beat)
            if ci % 2 == 1:
                place(out, woodblock(1000) * 0.25, b0 + 3.75 * beat)
    pos = 0.0
    for r in range(reps):
        for (m, dur) in melody:
            if m:
                swing_off = swing * beat if (pos / beat) % 1 > 0.4 else 0
                place(out, marimba(note(m), min(0.7, dur * beat * 1.3), 0.75), pos + swing_off)
                place(out, xylo(note(m + 12), 0.15, 0.18), pos + swing_off)
            pos += dur * beat
    out = out[:int(SR * total)]
    f = int(0.02 * SR); out[:f] *= np.linspace(0, 1, f); out[-f:] *= np.linspace(1, 0, f)
    save(name, out, 0.5)


Fm = (53, [60, 65, 69, 72]); Bb = (58, [62, 65, 70, 74]); Cc = (48, [60, 64, 67, 70]); Dmn = (50, [62, 65, 69, 74])
# меню: F-дур, неторопливо-прыгучая (104 bpm)
menu_mel = [(72, 0.5), (74, 0.5), (77, 1), (77, 0.5), (79, 0.5), (81, 1),
            (79, 0.5), (77, 0.5), (74, 1), (72, 1), (0, 1),
            (70, 0.5), (72, 0.5), (74, 1), (76, 0.5), (77, 0.5), (79, 1),
            (76, 0.5), (74, 0.5), (72, 2), (0, 1),
            (77, 0.5), (81, 0.5), (84, 1), (82, 0.5), (81, 0.5), (79, 1),
            (77, 0.5), (79, 0.5), (81, 1), (74, 1), (0, 1),
            (72, 0.5), (74, 0.5), (76, 1), (79, 1), (77, 0.5), (76, 0.5),
            (74, 0.5), (76, 0.5), (77, 2), (0, 1)]
toon("music_menu", 104, [Fm, Bb, Cc, Fm, Dmn, Bb, Cc, Fm], menu_mel, [(0, 0), (2, 7)])
G_ = (55, [62, 67, 71, 74]); C_ = (48, [60, 64, 67, 72]); D_ = (50, [62, 66, 69, 74]); Em_ = (52, [59, 64, 67, 71])
# уровень: G-дур, бодрая (124 bpm)
lvl_mel = [(74, 0.5), (76, 0.5), (79, 0.5), (76, 0.5), (74, 1), (71, 1),
           (72, 0.5), (74, 0.5), (76, 0.5), (79, 0.5), (81, 1), (79, 1),
           (78, 0.5), (79, 0.5), (81, 0.5), (83, 0.5), (81, 1), (78, 1),
           (79, 0.5), (78, 0.5), (76, 0.5), (74, 0.5), (79, 2),
           (83, 0.5), (81, 0.5), (79, 0.5), (76, 0.5), (79, 1), (83, 1),
           (84, 0.5), (83, 0.5), (81, 0.5), (79, 0.5), (76, 1), (72, 1),
           (74, 0.5), (76, 0.5), (78, 0.5), (81, 0.5), (79, 0.5), (78, 0.5), (76, 0.5), (74, 0.5),
           (79, 1), (74, 0.5), (71, 0.5), (67, 2)]
toon("music_level", 124, [G_, C_, D_, G_, Em_, C_, D_, G_], lvl_mel, [(0, 0), (1.5, 7), (2, 12), (3, 7)])
