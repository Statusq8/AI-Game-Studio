#!/usr/bin/env python3
"""Уровни 2–100 «Зоопарка мечты», нарисованные вручную (уровень 1 — обучающий, в levels.gd).

python3 tools/levels100.py            — проверить карты и вписать их в scripts/levels.gd (между маркерами HAND)
python3 tools/levels100.py --moves F  — сначала применить ходы из JSON-файла F ({"n": ходы}) — после подбора ботом

Легенда карты 8×10 (строки сверху вниз):
  .  клетка            #  дыра (фигурное поле)
  c C K  ящик 1/2/3 слоя          v  горшок (3 удара рядом)
  L M    лианы 1/2 слоя на фишке  i I  лёд 1/2 слоя (фишка во льду не двигается)
  _  газон под фишкой (совпадение на нём срезает газон, как в Royal Match)
  b  куст (3 удара)    s  ракушка (2)     j  банка с монетами (1)   h  мёд на фишке
  B  воздушный шарик (1)   w  лейка (3)    S  сейф (5)               t  камень (3, только бустерами)
  F  цветок 2×2 (3)    G  клетка с птичкой 2×2 (4)   T  камень 2×2 (3, только бустерами)
  0–4  цветной ящик (ломается совпадением своего цвета рядом)
Цвета фишек: 0 сердце, 1 капля, 2 листик, 3 звезда, 4 цветок.
Сложность: hard 1 — «Сложный» (красная плашка), 2 — «Очень сложный».
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEVELS_GD = os.path.join(ROOT, "scripts", "levels.gd")

E = "........"

# n: (ходы, цели по цвету [[цвет, сколько]], карта, доп. параметры)
L = {}


def lv(n, moves, colors, rows, **kw):
    assert n not in L, n
    L[n] = dict(moves=moves, colors=colors, map=rows, **kw)


# ---------- 2–15: знакомство ----------
lv(2, 15, [[0, 18], [3, 18]], ["##....##", "#......#", E, E, E, E, E, E, "#......#", "##....##"])
lv(3, 15, [[1, 14], [2, 14], [4, 14]], [E, E, ".#....#.", "##....##", "##....##", ".#....#.", E, E, E, E])
lv(4, 15, [[0, 15]], [E, E, E, E, "cccccccc", E, E, E, E, E])
lv(5, 16, [], [E, E, "..cccc..", "..c..c..", "..c..c..", "..cccc..", E, E, "cc....cc", "cc....cc"])
# газон: совпадения на нём его срезают
lv(6, 25, [], [E, E, E, E, E, E, E, E, "________", "________"])
lv(7, 15, [[3, 20], [1, 20]], ["#......#", E, E, E, E, E, E, E, E, "#......#"])
# горшки: 2 удара совпадениями рядом
lv(8, 15, [], [E, E, E, ".v....v.", E, "...vv...", E, ".v....v.", E, E])
lv(9, 20, [], [E, E, E, E, "...CC...", "..CccC..", ".CccccC.", "CccccccC", E, E])
lv(10, 18, [], ["##....##", "#......#", E, "cc....cc", "cc....cc", E, "________", "________", "#______#", "##____##"], hard=1)
# лианы держат фишку
lv(11, 20, [[2, 18]], [E, E, E, "..LLLL..", "..LLLL..", E, E, E, E, E])
lv(12, 15, [], ["L......L", ".L....L.", "..L..L..", "...cc...", "...cc...", "..L..L..", ".L....L.", "L......L", E, E])
lv(13, 15, [[0, 16], [2, 16], [4, 16]], [E, E, E, E, E, E, E, E, E, E])
# лёд: фишка во льду не двигается
lv(14, 15, [], [E, E, E, E, E, E, E, E, "iiiiiiii", "iiiiiiii"])
lv(15, 19, [], [E, E, "#.cccc.#", "##....##", "##....##", "#.cccc.#", E, "iiiiiiii", "iiiiiiii", E])

# ---------- 16–30: джунгли ----------
lv(16, 15, [], [E, E, "..____..", "._v__v_.", "._v__v_.", "..____..", E, E, E, E], hard=1)
# куст: 2 удара
lv(17, 15, [], [E, E, E, E, "b..bb..b", E, ".b....b.", E, E, E])
lv(18, 16, [], [E, E, E, E, E, "..b..b..", "._b__b_.", "________", "________", E])
lv(19, 15, [[2, 20], [4, 20]], ["#......#", E, E, "c......c", "cc....cc", E, E, E, E, "#......#"])
lv(20, 15, [], [E, E, "LLL..LLL", E, "..cCCc..", "..cCCc..", E, "iiiiiiii", "iiiiiiii", E], hard=1)
# цветок 2×2: 3 удара
lv(21, 15, [], [E, E, E, E, ".FF..FF.", ".FF..FF.", E, E, E, E])
lv(22, 15, [], [E, E, "...FF...", "...FF...", E, "FF....FF", "FF____FF", "________", "________", E])
# золотые яйца: доведи до низа
lv(23, 17, [], ["##....##", E, E, E, E, E, E, E, E, "##....##"], items=2)
lv(24, 26, [], [E, E, E, E, "cc.cc.cc", E, E, ".c.cc.c.", E, E], items=2)
lv(25, 17, [], [E, "..KKKK..", "..K..K..", E, "MM....MM", E, E, "IIIiiIII", "iiiiiiii", E], hard=2)
# ракушка: 2 удара
lv(26, 15, [], [E, E, E, ".s.ss.s.", E, E, "s.s..s.s", E, E, E])
lv(27, 16, [], [E, E, "..s..s..", E, "_s____s_", "________", "________", E, E, E], hard=1)
lv(28, 30, [], [E, E, E, "LL....LL", "..LLLL..", E, E, E, E, E], items=3)
lv(29, 15, [[0, 18], [1, 18], [3, 18]], ["#......#", "##....##", E, E, "c.c..c.c", E, "c.c..c.c", E, "##....##", "#......#"])
lv(30, 16, [], [E, "FF....FF", "FF....FF", E, "..cccc..", "..cCCc..", E, "iiiiiiii", "iIIiiIIi", E], hard=1)

# ---------- 31–50: озеро ----------
# мёд: склеивает фишку и растекается
lv(31, 15, [[1, 16]], [E, E, E, "..h..h..", E, "...h....", E, E, E, E])
lv(32, 15, [], [E, E, "cc....cc", "c..hh..c", "c......c", "cc....cc", E, E, E, E])
lv(33, 16, [], [E, E, "iiii____", "iiii____", E, E, "____iiii", "____iiii", E, E])
# клетка 2×2: 4 удара
lv(34, 15, [], [E, E, E, E, ".GG..GG.", ".GG..GG.", E, E, E, E])
lv(35, 15, [], [E, E, "L.L..L.L", E, "...GG...", "...GG...", E, "L.L..L.L", E, E], hard=1)
lv(36, 17, [[2, 22], [4, 22]], [E, E, E, E, "LL.LL.LL", E, E, E, E, E])
lv(37, 18, [], [E, E, ".v.bb.v.", E, "________", "__v__v__", "________", E, E, E])
# воздушный шарик: 1 удар рядом
lv(38, 15, [], [E, E, "B.B..B.B", E, ".B.BB.B.", E, "B.B..B.B", E, E, E])
lv(39, 15, [], [E, E, ".BBBBBB.", E, E, E, E, "iiiiiiii", "iiiiiiii", E])
lv(40, 18, [], [E, E, ".GG..GG.", ".GG..GG.", E, "KccccccK", E, E, E, E], hard=1)
lv(41, 29, [], [E, E, E, "s......s", ".s....s.", "..s..s..", E, E, E, E], items=2)
# банка: монеты
lv(42, 15, [[0, 18]], [E, E, E, "..j..j..", E, ".j....j.", E, E, E, E])
lv(43, 15, [], [E, E, "cjc..cjc", "ccc..ccc", E, E, "..cjjc..", "..cccc..", E, E])
lv(44, 15, [], [E, E, E, "..h..h..", "________", "________", "________", E, E, E])
lv(45, 15, [[3, 20]], [E, "B......B", E, "..B..B..", E, E, "..B..B..", E, "B......B", E], hard=1)
# лейка: 3 удара
lv(46, 15, [], [E, E, E, ".w....w.", E, E, "...ww...", E, E, E])
lv(47, 16, [], [E, E, "..w..w..", E, "________", "________", "________", E, E, E])
lv(48, 30, [], [E, "h......h", E, "..FF....", "..FF..FF", "......FF", E, E, "h......h", E])
lv(49, 15, [], [E, E, ".w.ww.w.", E, E, E, "IiiiiiiI", "iiiiiiii", E, E])
lv(50, 20, [], [E, "KKK..KKK", E, "MM.MM.MM", E, "..GG....", "..GG....", "IIIIIIII", "iiiiiiii", E], hard=2)

# ---------- 51–70: сафари ----------
# сейф: 5 ударов
lv(51, 15, [[2, 16]], [E, E, E, "..S..S..", E, E, E, E, E, E])
lv(52, 16, [], [E, E, "ccS..Scc", "cc....cc", E, E, "..cSSc..", "..cccc..", E, E], hard=1)
lv(53, 33, [], [E, E, E, ".w....w.", E, "..w..w..", E, E, E, E], items=2)
lv(54, 21, [], [E, "________", "________", "##____##", "##____##", "________", "________", E, E, E])
lv(55, 15, [], [E, E, "B.B..B.B", "LLLLLLLL", E, "..cccc..", E, E, E, E])
lv(56, 15, [[0, 22], [1, 22]], ["#......#", E, E, E, "##....##", "##....##", E, E, "iiiiiiii", "#iiiiii#"])
lv(57, 15, [], [E, E, "s.h..h.s", E, "s......s", E, "..s..s..", E, E, E], hard=1)
lv(58, 15, [], [E, "FF....GG", "FF....GG", E, E, "GG....FF", "GG....FF", E, E, E])
lv(59, 18, [], [E, E, E, E, "IIIIIIII", "IiiiiiiI", "IiiiiiiI", "IIIIIIII", E, E])
lv(60, 19, [], [E, E, "S..bb..S", E, "__b__b__", "________", "________", "________", E, E], hard=1)
# камень: только бустерами
lv(61, 19, [[3, 18]], [E, E, E, "..t..t..", E, E, E, E, E, E])
lv(62, 18, [], [E, E, "cccTTccc", "...TT...", E, "cc....cc", E, E, E, E])
lv(63, 22, [], [E, E, ".v....v.", E, E, "...vv...", E, E, E, E], items=2)
lv(64, 15, [], [E, E, "B.j..j.B", E, ".B.BB.B.", E, "..j..j..", E, E, E])
lv(65, 15, [[2, 20], [3, 20], [4, 20]], [E, E, E, "cc....cc", "cc....cc", E, E, E, E, E], hard=1)
lv(66, 16, [], [E, E, "__v__v__", "________", "v______v", "________", "__v__v__", E, E, E])
lv(67, 15, [], [E, E, "LLw..wLL", "LL....LL", E, E, "..w..w..", E, E, E])
lv(68, 18, [], [E, E, "..h..h..", E, E, E, "iiiiiiii", "iiiiiiii", "iiiiiiii", E])
lv(69, 15, [], [E, "#cc..cc#", "#c....c#", E, "...GG...", "...GG...", E, "#c....c#", "#cc..cc#", E])
lv(70, 26, [], [E, "KK.SS.KK", E, E, E, "..FF....", "..FF....", E, "IIIIIIII", E], hard=1)

# ---------- 71–100: королевский зоопарк ----------
# цветной ящик: только совпадение своего цвета рядом
lv(71, 15, [], [E, E, E, "..0..1..", E, ".2....3.", E, "...44...", E, E])
lv(72, 20, [], [E, E, "01234012", E, E, "________", "________", E, E, E])
lv(73, 33, [], [E, E, E, "iiiiiiii", E, E, E, E, E, E], items=3)
lv(74, 15, [], [E, "FF....FF", "FF....FF", E, "...GG...", "...GG...", E, "GG....GG", "GG....GG", E])
lv(75, 25, [], ["#KKKKKK#", E, "MM.SS.MM", E, E, E, "IIIIIIII", "IIIIIIII", E, E], hard=2)
lv(76, 16, [], [E, E, "B.w..w.B", E, "________", "________", E, E, E, E])
lv(77, 16, [], [E, "h......h", E, "..s..s..", E, "..s..s..", E, "h......h", E, E], hard=1)
lv(78, 21, [], ["##....##", "#......#", E, "cCKKKKCc", E, E, "LLLLLLLL", E, "#......#", "##....##"])
lv(79, 15, [[0, 20], [4, 20]], [E, "#......#", E, ".B....B.", E, E, ".B....B.", E, "#......#", E])
lv(80, 26, [], [E, E, "TT.jj.TT", "TT....TT", E, "________", "________", "________", E, E], hard=1)
lv(81, 15, [], [E, E, "0.1..2.3", E, "iiiiiiii", "iiiiiiii", E, E, E, E])
lv(82, 15, [], [E, E, "..S..S..", E, "s.s..s.s", E, E, E, E, E])
lv(83, 30, [], [E, E, ".w.GG.w.", "...GG...", E, E, "LLLLLLLL", "LLLLLLLL", E, E])
lv(84, 18, [], [E, "__h__h__", "________", "________", E, E, E, E, E, E])
lv(85, 26, [], [E, E, "B......B", ".B....B.", "..B..B..", "...BB...", E, "iiiiiiii", E, E], hard=1, items=2)
lv(86, 15, [], [E, "##.FF.##", "##.FF.##", E, "cc....cc", "cCC..CCc", E, E, E, E])
lv(87, 15, [[1, 20], [2, 20], [3, 20]], ["##....##", "#......#", E, "..h..h..", E, E, "...h....", E, "#......#", "##....##"])
lv(88, 18, [], [E, E, "vvvvvvvv", E, "________", "________", "________", E, E, E])
lv(89, 22, [], [E, E, "K......K", ".K....K.", E, E, ".C....C.", "C......C", E, E], items=2)
lv(90, 25, [], [E, "SS....SS", E, "..GG....", "..GG..FF", "......FF", E, "IIIIIIII", "IIIIIIII", E], hard=1)
lv(91, 29, [], [E, E, "w.0..1.w", E, "w.2..3.w", E, "________", "________", E, E])
lv(92, 31, [], [E, E, E, "MMMMMMMM", E, "..jjjj..", E, "MMMMMMMM", E, E])
lv(93, 15, [], [E, E, "..h..h..", E, "s.s..s.s", E, "IIIIIIII", E, E, E])
lv(94, 32, [], [E, "#KK..KK#", "#K....K#", E, E, E, "#K....K#", "#KK..KK#", E, E], items=2)
lv(95, 15, [], [E, E, "B.B.B.B.", ".B.B.B.B", E, "GG....GG", "GG....GG", E, E, E], hard=1)
lv(96, 30, [], [E, E, E, "..TT....", "..TT..TT", "......TT", E, "________", "________", E])
lv(97, 20, [[0, 22], [3, 22]], [E, E, "#......#", "##....##", "###bb###", "###..###", "##....##", "#......#", E, E])
lv(98, 19, [], [E, "w......w", E, "..FF....", "..FF....", E, "LLLLLLLL", "iiiiiiii", E, E])
lv(99, 32, [], [E, E, "01234012", E, "h......h", E, "IIIIIIII", "iiiiiiii", E, E])
lv(100, 31, [], [E, "KKK..KKK", E, "GG....GG", "GG....GG", E, "KccccccK", E, "IIIIIIII", "IIIIIIII"], hard=2, items=2)

BIG = {"F": "flower", "G": "cage", "T": "stone"}
OK_CH = set(".#cCKvLMiI_bsjhBwStFGT01234")


def check():
    for n in range(2, 101):
        assert n in L, "нет уровня %d" % n
        m = L[n]["map"]
        assert len(m) == 10, (n, len(m))
        for y, row in enumerate(m):
            assert len(row) == 8, (n, y, row)
            for ch in row:
                assert ch in OK_CH, (n, y, ch)
        # большие блоки 2×2 — ровными квадратами
        seen = set()
        for y in range(10):
            for x in range(8):
                ch = m[y][x]
                if ch in BIG and (x, y) not in seen:
                    for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                        assert x + dx < 8 and y + dy < 10 and m[y + dy][x + dx] == ch, ("2x2", n, x, y)
                        seen.add((x + dx, y + dy))
        has_goal = bool(L[n]["colors"]) or any(ch not in ".#" for row in m for ch in row) or L[n].get("items")
        assert has_goal, n


def gd_value(v):
    return json.dumps(v, ensure_ascii=False)


def emit():
    out = ["const HAND := {"]
    for n in range(2, 101):
        d = L[n]
        extra = ""
        if d.get("hard"):
            extra += ', "hard": %d' % d["hard"]
        if d.get("items"):
            extra += ', "items": %d' % d["items"]
        rows = ", ".join('"%s"' % r for r in d["map"])
        out.append('\t%d: {"moves": %d%s, "colors": %s, "map": [%s]},' % (n, d["moves"], extra, gd_value(d["colors"]), rows))
    out.append("}")
    return "\n".join(out)


def main():
    if "--moves" in sys.argv:
        mv = json.load(open(sys.argv[sys.argv.index("--moves") + 1]))
        for k, v in mv.items():
            L[int(k)]["moves"] = int(v)
        # переписать ходы в этом файле, чтобы правки не терялись
        src = open(__file__, encoding="utf-8").read()
        for k, v in mv.items():
            src = re.sub(r"^lv\(%d, \d+," % int(k), "lv(%d, %d," % (int(k), int(v)), src, flags=re.M)
        open(__file__, "w", encoding="utf-8").write(src)
    check()
    gd = open(LEVELS_GD, encoding="utf-8").read()
    a = gd.index("const HAND := {")
    b = gd.index("\n}\n", a) + 2
    gd = gd[:a] + emit() + gd[b:]
    open(LEVELS_GD, "w", encoding="utf-8").write(gd)
    print("ok: %d уровней" % len(L))


if __name__ == "__main__":
    main()
