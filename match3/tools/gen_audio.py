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
