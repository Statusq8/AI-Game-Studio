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
music("music_menu", 104, [C, G, Am, F], mel_menu, 2, 0.08)
mel_level = [(72, 0.5), (76, 0.5), (79, 1), (76, 0.5), (79, 0.5), (81, 1), (79, 1), (76, 1), (74, 2),
             (72, 0.5), (74, 0.5), (76, 1), (79, 1), (77, 1), (76, 1), (74, 1), (72, 2), (0, 1),
             (76, 0.5), (79, 0.5), (84, 1), (81, 1), (79, 1), (77, 1), (76, 2), (74, 1), (72, 1), (74, 1), (76, 1), (72, 2), (0, 2)]
music("music_level", 116, [F, C, Dm, G], mel_level, 2, 0.06)
print("ok")
