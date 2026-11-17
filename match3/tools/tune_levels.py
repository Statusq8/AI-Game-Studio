#!/usr/bin/env python3
"""Подбор ходов для ручных уровней ботом (--balance): сколько ходов нужно, чтобы бот выигрывал
с нужной долей. Цели: 2–15 — 90 %, обычные — 70 %, «Сложный» — 45 %, «Очень сложный» — 30 %.

python3 tools/tune_levels.py FIRST LAST TRIES [--apply]
Печатает таблицу; с --apply вписывает новые ходы в tools/levels100.py и scripts/levels.gd."""
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = "/tmp/Godot_v4.5.1-stable_linux.x86_64"
sys.path.insert(0, os.path.join(ROOT, "tools"))
import levels100  # noqa: E402


def run(first, last, tries):
    out = subprocess.run([G, "--headless", "--path", ROOT, "--", "--balance=%d:%d:%d" % (first, last, tries)],
                         capture_output=True, text=True, timeout=3600).stdout
    res = []
    for line in out.splitlines():
        m = re.match(r"BAL (\d+) (\d+) (\d+) (WIN|LOSE) (\d+) (-?\d+)", line)
        if m:
            res.append((int(m[1]), int(m[2]), m[4] == "WIN", int(m[5]), int(m[6])))
    return res


def target(n, hard):
    if n <= 15:
        return 0.9
    return [0.7, 0.45, 0.3][hard]


def main():
    if "," in sys.argv[1]:
        ns = [int(x) for x in sys.argv[1].split(",")]
        tries = int(sys.argv[2])
    else:
        first, last, tries = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
        ns = list(range(first, last + 1))
    # два потока: уровни через один, чтобы тяжёлые не скапливались в одном
    chunks = [ns[0::2], ns[1::2]]
    jobs = []
    with ThreadPoolExecutor(2) as ex:
        for ch in chunks:
            for n in ch:
                jobs.append(ex.submit(run, n, n, tries))
        res = [r for j in jobs for r in j.result()]
    by = {}
    for n, hard, win, left, pct in res:
        by.setdefault(n, []).append((hard, win, left, pct))
    newmoves = {}
    for n in sorted(by):
        rows = by[n]
        hard = rows[0][0]
        mv = levels100.L[n]["moves"]
        wins = sum(1 for r in rows if r[1])
        # «запас» хода: у победы — сколько ходов осталось, у поражения — сколько примерно не хватило
        sur = []
        for _, win, left, pct in rows:
            if win:
                sur.append(left)
            else:
                p = max(pct, 20) / 100.0
                sur.append(-mv * (1 - p) / p)
        sur.sort()
        t = target(n, hard)
        # нужно, чтобы доля t попыток имела запас ≥ 0: берём квантиль (1 - t)
        k = min(len(sur) - 1, max(0, int(round((1 - t) * (len(sur) - 1)))))
        delta = -sur[k]
        delta = max(-6, min(8, int(round(delta))))
        if abs(delta) <= 1:
            delta = 0
        nm = max(14, min(40, mv + delta))
        newmoves[n] = nm
        print("%3d hard=%d moves %2d  wins %d/%d  sur=%s  -> %d" % (n, hard, mv, wins, len(rows), [int(x) for x in sur], nm))
    if "--apply" in sys.argv:
        f = "/tmp/w/moves.json"
        json.dump({str(k): v for k, v in newmoves.items()}, open(f, "w"))
        subprocess.run([sys.executable, os.path.join(ROOT, "tools", "levels100.py"), "--moves", f], check=True)


if __name__ == "__main__":
    main()
