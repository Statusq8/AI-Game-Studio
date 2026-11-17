extends RefCounted
## Генератор уровней: по номеру уровня всегда выдаёт одно и то же (сид = номер).
## Цели: фишки нужного цвета + одно-два препятствия (ящики, трава, предметы, цепи, вазы).

const W := 8
const H := 10
## Фигурные поля: клетки-дыры (поле не квадратное).
const SHAPES := [
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(7, 0), Vector2i(6, 0), Vector2i(7, 1)],
	[Vector2i(3, 3), Vector2i(4, 3), Vector2i(3, 4), Vector2i(4, 4)],
	[Vector2i(0, 3), Vector2i(0, 4), Vector2i(7, 3), Vector2i(7, 4)],
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(5, 0), Vector2i(6, 0), Vector2i(7, 0), Vector2i(0, 1), Vector2i(7, 1)],
	[Vector2i(3, 2), Vector2i(4, 2), Vector2i(3, 5), Vector2i(4, 5)],
	[Vector2i(0, 2), Vector2i(7, 2), Vector2i(0, 5), Vector2i(7, 5), Vector2i(0, 6), Vector2i(7, 6)],
	# ромб: срезаны все четыре угла лесенкой
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(6, 0), Vector2i(7, 0), Vector2i(7, 1), Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)],
	# сердце: вырез сверху посередине и срезанный низ
	[Vector2i(3, 0), Vector2i(4, 0), Vector2i(0, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(7, 6), Vector2i(7, 7), Vector2i(6, 7)],
	# крест
	[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(6, 0), Vector2i(7, 0), Vector2i(6, 1), Vector2i(7, 1), Vector2i(0, 6), Vector2i(1, 6), Vector2i(0, 7), Vector2i(1, 7), Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7)],
	# две колонны внутри
	[Vector2i(2, 2), Vector2i(2, 3), Vector2i(5, 2), Vector2i(5, 3)],
	# «песочные часы»: сужение в середине
	[Vector2i(0, 3), Vector2i(0, 4), Vector2i(1, 3), Vector2i(1, 4), Vector2i(6, 3), Vector2i(6, 4), Vector2i(7, 3), Vector2i(7, 4)],
	# лесенка слева
	[Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, 2), Vector2i(1, 1), Vector2i(2, 0)],
	# окно в центре + срезанные верхние углы
	[Vector2i(0, 0), Vector2i(7, 0), Vector2i(3, 4), Vector2i(4, 4)],
	# зубцы сверху (как башня)
	[Vector2i(1, 0), Vector2i(3, 0), Vector2i(5, 0), Vector2i(7, 0)],
]
## Прогрессия по зонам (разбор жанра, раздел 11): каждая зона добавляет свои препятствия к прежним.
const ZONE_POOLS := [
	[1, ["crate", "grass", "vase"]],                   # 1–50 Вход в зоопарк
	[51, ["chain", "bush", "flower"]],                 # 51–100 Тропические джунгли
	[101, ["shell", "item"]],                          # 101–150 Озёрная зона
	[151, ["ice", "stone"]],                           # 151–200 Ледяной вольер
	[201, ["honey", "cage"]],                          # 201–275 Сафари
	[276, ["birdhouse", "jar"]],                       # 276–375 Волшебный сад
	[376, ["safe", "colorbox"]],                       # 376–500 Королевский зоопарк
]
const ZONE_NAMES := ["Вход в зоопарк", "Тропические джунгли", "Озёрная зона", "Ледяной вольер", "Сафари", "Волшебный сад", "Королевский зоопарк"]


static func pool_for(n: int) -> Array:
	var out: Array = []
	for z in ZONE_POOLS:
		if n >= z[0]:
			out.append_array(z[1])
	return out


static func zone_of(n: int) -> int:
	var z := 0
	for i in ZONE_POOLS.size():
		if n >= ZONE_POOLS[i][0]:
			z = i
	return z


## Когда открывается каждое препятствие (плейтест: все 16 — до 60-го уровня).
const UNLOCKS := [[4, "crate"], [6, "grass"], [8, "vase"], [11, "chain"], [14, "ice"], [17, "bush"], [21, "flower"],
	[23, "item"], [26, "shell"], [31, "honey"], [34, "cage"], [38, "balloon"], [42, "jar"], [46, "can"], [51, "safe"], [61, "stone"],
	[71, "colorbox"], [101, "birdhouse"]]


static func unlocked(n: int) -> Array:
	var out: Array = []
	for u in UNLOCKS:
		if n >= u[0]:
			out.append(u[1])
	return out


## Препятствие, открытое на этом или 2 предыдущих уровнях (его показываем сразу).
static func fresh_obstacle(n: int) -> String:
	for u in UNLOCKS:
		if n >= u[0] and n - u[0] < 3:
			return u[1]
	return ""


const OBSTACLES := ["crate", "grass", "vase", "chain", "bush", "flower", "shell", "item", "ice", "stone", "honey", "cage", "birdhouse", "jar", "safe", "colorbox", "balloon", "can"]
## Блоки на поле: номер вида (как в board.gd) и прочность.
const BLOCK := {"crate": [1, 1], "vase": [2, 2], "safe": [3, 5], "jar": [4, 1], "cage": [5, 2], "balloon": [6, 1], "flower": [7, 2], "bush": [8, 2], "shell": [9, 2],
	"stone": [10, 3], "colorbox": [11, 1], "birdhouse": [12, 3], "can": [13, 3]}


## Уровень 1 — ручной: продуманная раскладка, первый ход сразу даёт ракету,
## ещё один ход внизу — пятёрку (радужный шар). Цвета: 0 сердце, 1 капля, 2 листик, 3 звезда, 4 цветок.
const LEVEL1_LAYOUT := [
	"30301033",
	"00233200",
	"11431410",
	"20041401",
	"40342334",
	"34202314",
	"22420232",
	"11403103",
	"41211011",
	"22003234",
]


static func make_level1() -> Dictionary:
	return {
		"n": 1, "colors": 5, "moves": 20,
		"goals": [{"kind": "color", "color": 2, "left": 16}, {"kind": "color", "color": 1, "left": 12}],
		"blocks": {}, "chains": {}, "grass_start": [], "grass_target": [], "items": 0, "ice": {}, "honey": [],
		"layout": LEVEL1_LAYOUT, "first_move": [Vector2i(2, 5), Vector2i(2, 6)],
		"seed": 1001, "zone": 0,
	}


static func make(n: int) -> Dictionary:
	if n == 1:
		return make_level1()
	if HAND.has(n):
		return make_hand(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var lv := {
		"n": n, "colors": 5, "moves": clampi(21 - n / 25, 15, 21), "goals": [],
		"blocks": {}, "chains": {}, "grass_start": [], "grass_target": [], "items": 0, "ice": {}, "honey": [],
	}

	var kinds: Array = []
	# препятствия открываются быстро: к 55-му уровню — все 16; только что открытое — сразу на поле
	var pool := unlocked(n)
	var fresh := fresh_obstacle(n)
	if n >= 4:
		kinds.append(fresh if fresh != "" else pool[rng.randi_range(0, pool.size() - 1)])
	if n >= 12 and n % 2 == 0 and pool.size() > 1:
		for tries in 6:
			var extra: String = pool[rng.randi_range(0, pool.size() - 1)]
			if extra not in kinds:
				kinds.append(extra)
				break
	lv["zone"] = zone_of(n)

	var color_goals := 1 if n <= 2 else 2
	if n >= 15 and kinds.is_empty():
		color_goals = 3
	if kinds.size() >= 1 and n < 10:
		color_goals = 1
	var picked: Array = []
	while picked.size() < color_goals:
		var c := rng.randi_range(0, lv.colors - 1)
		if c not in picked:
			picked.append(c)
	for c in picked:
		# количество фишек в цели растёт до 26 и дальше не увеличивается
		var amount := mini(10 + mini(n, 40) / 2 + rng.randi_range(0, 4), 22)
		if color_goals == 3:
			amount = int(amount * 0.8)
		lv.goals.append({"kind": "color", "color": c, "left": amount})

	for k in kinds:
		_add_obstacle(lv, k, n, rng)
	# фигурное поле: с 4-го уровня на 5 уровнях из 6, форма случайная, иногда зеркально
	var holes: Array = []
	if n >= 4 and n % 6 != 1:
		for c: Vector2i in SHAPES[rng.randi_range(0, SHAPES.size() - 1)]:
			holes.append(c)
		if rng.randf() < 0.5:
			holes = holes.map(func(c: Vector2i) -> Vector2i: return Vector2i(W - 1 - c.x, c.y))
	# разный размер поля: 6 в ширину, 8×9 или 8×8 (крайние колонки/верхние ряды — дыры)
	if n >= 7:
		match n % 7:
			3:
				for y in H:
					holes.append(Vector2i(0, y))
					holes.append(Vector2i(W - 1, y))
			5:
				for x in W:
					holes.append(Vector2i(x, 0))
			6:
				if n >= 20:
					for x in W:
						holes.append(Vector2i(x, 0))
						holes.append(Vector2i(x, 1))
	if not holes.is_empty():
		var uniq := {}
		for c in holes:
			uniq[c] = true
		lv["holes"] = uniq.keys()
		_cut_holes(lv, lv.holes)
	# сложные уровни: каждый 5-й «Сложный», каждый 15-й «Очень сложный» (меньше ходов, больше монет)
	if n % 15 == 0 and n >= 30:
		lv["hard"] = 2
		lv.moves -= 4
	elif n % 5 == 0 and n >= 15:
		lv["hard"] = 1
		lv.moves -= 2
	_trim_goals(lv)
	# ходов — в разумных рамках: обычный уровень 18–26, сложный 16–24, очень сложный 15–22.
	# Если препятствия «просят» больше ходов, чем потолок (раньше лишнее просто срезалось и уровень
	# становился стеной — баланс 2026-11-17, ходы препятствий подобраны ботом --balance): потолок поднимается до +6, а цель по цвету уменьшается.
	var hard := int(lv.get("hard", 0))
	var cap: int = [26, 24, 22][hard]
	var over: int = lv.moves - cap
	if over > 0:
		var k := 1.0 - minf(0.5, over * 0.045)
		for g in lv.goals:
			if g.kind == "color":
				g.left = maxi(8, int(round(g.left * k)))
		cap += mini(over, 6)
	# первые уровни (до 15) — мягче: цель по цвету на 20 % меньше
	if n <= 15 and hard == 0:
		for g in lv.goals:
			if g.kind == "color":
				g.left = maxi(8, int(round(g.left * 0.8)))
	lv.moves = clampi(lv.moves, [18, 16, 15][hard], cap)
	lv["seed"] = rng.randi()
	return lv


## Не больше 3 целей (на сложных — 4). Лишние убираем, начиная с «собери цвет»:
## при препятствиях оставляем максимум одну цель по цвету.
static func _trim_goals(lv: Dictionary) -> void:
	var cap := 4 if int(lv.get("hard", 0)) > 0 else 3
	var colors: Array = lv.goals.filter(func(g: Dictionary) -> bool: return g.kind == "color")
	var others: Array = lv.goals.filter(func(g: Dictionary) -> bool: return g.kind != "color")
	if not others.is_empty() and colors.size() > 1:
		colors = colors.slice(0, 1)
	while colors.size() + others.size() > cap and not colors.is_empty():
		colors.pop_back()
	while others.size() > cap:
		others.pop_back()
	lv.goals = colors + others


## Большие препятствия 2×2 (как в Royal Match): камень, цветок, клетка.
const BIG := {"stone": 3, "flower": 3, "cage": 4}


static func _add_big(lv: Dictionary, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	var want := 2 if n < 60 else 3
	var count := 0
	for tries in 60:
		var a := Vector2i(rng.randi_range(0, W - 2), rng.randi_range(2, H - 3))
		var cells := [a, a + Vector2i(1, 0), a + Vector2i(0, 1), a + Vector2i(1, 1)]
		var free := true
		for c in cells:
			# не впритык к другому большому блоку — чтобы фишки обтекали
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					var nb: Vector2i = c + Vector2i(dx, dy)
					if lv.blocks.has(nb) and lv.blocks[nb].has("anchor"):
						free = false
			if not _free(lv, c):
				free = false
		if not free:
			continue
		for c in cells:
			lv.blocks[c] = {"kind": BLOCK[kind][0], "hp": BIG[kind], "anchor": a, "color": 0}
		count += 1
		if count >= want:
			break
	lv.goals.append({"kind": kind, "left": count})
	lv.moves += (6 if kind == "stone" else 4) * count


## Клетка свободна от любых препятствий — на одной клетке не больше одного препятствия.
static func _free(lv: Dictionary, c: Vector2i) -> bool:
	return not lv.blocks.has(c) and not lv.chains.has(c) and not lv.ice.has(c) and c not in lv.honey


static func _add_obstacle(lv: Dictionary, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	if BIG.has(kind):
		_add_big(lv, kind, n, rng)
		return
	match kind:
		"crate", "vase", "safe", "jar", "cage", "balloon", "flower", "bush", "shell", "stone", "colorbox", "birdhouse", "can":
			var info: Array = BLOCK[kind]
			var width := mini(4 + n / 30, 6) if kind in ["crate", "vase", "balloon"] else (3 if kind in ["stone", "safe"] else mini(3 + n / 60, 5))
			var count := 0
			var want := 2 if kind == "birdhouse" else width + (2 if kind in ["crate", "vase"] and n > 20 else 0)
			for c: Vector2i in _pattern(n + kind.length(), want, rng):
				if not _free(lv, c):
					continue
				var hp: int = info[1]
				if kind == "crate" and n >= 12:
					hp = rng.randi_range(1, 3)
				elif kind == "vase" and n >= 12 and rng.randf() < 0.4:
					hp = 2
				lv.blocks[c] = {"kind": info[0], "hp": hp, "color": rng.randi_range(0, lv.colors - 1)}
				count += 1
				if count >= want:
					break
			# куст раскидывает газон — значит, на уровне с кустами всегда есть цель «газон»
			if kind in ["bush", "vase"] and not lv.goals.any(func(gg: Dictionary) -> bool: return gg.kind == "grass"):
				_add_obstacle(lv, "grass", n, rng)
			if kind == "birdhouse":
				lv["birdhouse"] = true
				# цель — птицы: каждый скворечник выпускает 3 птицы, их надо спустить вниз
				lv.goals.append({"kind": "item", "left": count * 3})
				lv.moves += 8 + 6 * count
			else:
				lv.goals.append({"kind": kind, "left": count})
				lv.moves += 9 if kind in ["safe", "stone"] else (7 if kind == "vase" else 3)
		"ice":
			var count := 0
			for y in range(H - 3, H):
				for x in W:
					var c := Vector2i(x, y)
					if _free(lv, c):
						lv.ice[c] = 2 if (n >= 20 and rng.randf() < 0.3) else 1
						count += 1
			lv.goals.append({"kind": "ice", "left": count})
			lv.moves += 7
		"honey":
			for tries in 200:
				if lv.honey.size() >= 3:
					break
				var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(2, 6))
				if _free(lv, c):
					lv.honey.append(c)
			lv.goals.append({"kind": "honey", "left": lv.honey.size()})
			lv.moves += 3
		"grass":
			var rows := 3
			for y in range(H - rows, H):
				for x in W:
					var c := Vector2i(x, y)
					if not lv.blocks.has(c):
						lv.grass_target.append(c)
			while lv.grass_start.size() < 3:
				var c: Vector2i = lv.grass_target[rng.randi_range(0, lv.grass_target.size() - 1)]
				if c not in lv.grass_start:
					lv.grass_start.append(c)
			lv.goals.append({"kind": "grass", "left": lv.grass_target.size()})
			lv.moves += 6
		"item":
			lv.items = clampi(2 + n / 15, 2, 4)
			lv.goals.append({"kind": "item", "left": lv.items})
			lv.moves += 5 * lv.items + 2
		"chain":
			var count := clampi(5 + n / 4, 5, 12)
			var cells: Array = []
			for tries in 400:
				if cells.size() >= count:
					break
				var c := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(2, 5))
				if c in cells or not _free(lv, c):
					continue
				# не перекрываем целый ряд, чтобы фишки могли падать по диагонали
				var row := 0
				for o in cells:
					if o.y == c.y:
						row += 1
				if row >= W - 3:
					continue
				cells.append(c)
			for c in cells:
				lv.chains[c] = 2 if (n >= 20 and rng.randf() < 0.3) else 1
			lv.goals.append({"kind": "chain", "left": cells.size()})
			lv.moves += 2


## Убираем препятствия из дыр и пересчитываем цели.
static func _cut_holes(lv: Dictionary, holes: Array) -> void:
	# большой блок задет дырой — убираем его целиком
	for c in holes:
		if lv.blocks.has(c) and lv.blocks[c].has("anchor"):
			var a: Vector2i = lv.blocks[c].anchor
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				lv.blocks.erase(a + d)
	for c in holes:
		lv.blocks.erase(c)
		lv.chains.erase(c)
		lv.ice.erase(c)
		lv.honey.erase(c)
		lv.grass_target.erase(c)
		lv.grass_start.erase(c)
	var block_goal := {1: "crate", 2: "vase", 3: "safe", 4: "jar", 5: "cage", 6: "balloon", 7: "flower", 8: "bush", 9: "shell", 10: "stone", 11: "colorbox", 13: "can"}
	for g in lv.goals:
		match g.kind:
			"chain":
				g.left = lv.chains.size()
			"ice":
				g.left = lv.ice.size()
			"honey":
				g.left = lv.honey.size()
			"grass":
				g.left = lv.grass_target.size()
			"color", "item":
				pass
			_:
				var cnt := 0
				for c in lv.blocks:
					var bl: Dictionary = lv.blocks[c]
					if bl.has("anchor") and bl.anchor != c:
						continue
					if block_goal.get(bl.kind, "") == g.kind:
						cnt += 1
				g.left = cnt
	# лёд/трава могли закончиться — в цель ставим хотя бы что-то разумное
	lv.goals = lv.goals.filter(func(g: Dictionary) -> bool: return g.left > 0)


## Где стоят препятствия: разные раскладки по номеру уровня (не только нижний ряд).
## Ни один ряд не перекрывается целиком — фишки обтекают препятствия по диагонали.
static func _pattern(n: int, want: int, rng: RandomNumberGenerator) -> Array:
	var cells: Array = []
	var layout := rng.randi_range(0, 9)
	match layout:
		0:  # нижний ряд по центру
			for x in [3, 4, 2, 5, 1, 6]:
				cells.append(Vector2i(x, H - 1))
		1:  # полоса посередине с просветами
			for x in [1, 2, 5, 6, 3, 4]:
				cells.append(Vector2i(x, H / 2))
		2:  # две колонны
			for y in range(3, 3 + 4):
				cells.append(Vector2i(1, y))
				cells.append(Vector2i(6, y))
		3:  # группа в центре
			for p in [Vector2i(3, 4), Vector2i(4, 4), Vector2i(3, 5), Vector2i(4, 5), Vector2i(2, 4), Vector2i(5, 5), Vector2i(2, 5), Vector2i(5, 4)]:
				cells.append(p)
		4:  # нижние углы
			for p in [Vector2i(0, H - 1), Vector2i(7, H - 1), Vector2i(1, H - 1), Vector2i(6, H - 1), Vector2i(0, H - 2), Vector2i(7, H - 2), Vector2i(1, H - 2), Vector2i(6, H - 2)]:
				cells.append(p)
		5:  # ромб вокруг центра
			for p in [Vector2i(3, 3), Vector2i(4, 3), Vector2i(2, 4), Vector2i(5, 4), Vector2i(2, 5), Vector2i(5, 5), Vector2i(3, 6), Vector2i(4, 6)]:
				cells.append(p)
		6:  # диагональ-лесенка
			for i in 7:
				cells.append(Vector2i(i, 2 + i))
		8:  # уголок в случайном месте
			var ox := rng.randi_range(0, W - 4)
			var oy := rng.randi_range(3, H - 4)
			for p in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 0), Vector2i(3, 1)]:
				cells.append(Vector2i(ox, oy) + p)
		_:  # россыпь
			var used := {}
			while cells.size() < want + 4:
				var c := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(3, H - 1))
				if not used.has(c):
					used[c] = true
					cells.append(c)
	# случайный сдвиг раскладки по горизонтали — уровни не похожи друг на друга
	var shift := rng.randi_range(-1, 1) if layout <= 7 else 0
	cells = cells.map(func(c: Vector2i) -> Vector2i: return Vector2i(clampi(c.x + shift, 0, W - 1), c.y))
	cells.shuffle()
	# защита: не больше W-2 препятствий в одном ряду
	var per_row := {}
	var out: Array = []
	for c in cells:
		per_row[c.y] = per_row.get(c.y, 0) + 1
		if per_row[c.y] <= W - 2:
			out.append(c)
	return out


## ---------- уровни 2–100 — ручные (2026-11-17) ----------
## Карты рисуются в tools/levels100.py (там же легенда); сюда HAND вписывает скрипт: python3 tools/levels100.py
const HAND := {
	2: {"moves": 20, "colors": [[0, 18], [3, 18]], "map": ["##....##", "#......#", "........", "........", "........", "........", "........", "........", "#......#", "##....##"]},
	3: {"moves": 20, "colors": [[1, 14], [2, 14], [4, 14]], "map": ["........", "........", ".#....#.", "##....##", "##....##", ".#....#.", "........", "........", "........", "........"]},
	4: {"moves": 20, "colors": [[0, 15]], "map": ["........", "........", "........", "........", "cccccccc", "........", "........", "........", "........", "........"]},
	5: {"moves": 24, "colors": [], "map": ["........", "........", "..cccc..", "..c..c..", "..c..c..", "..cccc..", "........", "........", "cc....cc", "cc....cc"]},
	6: {"moves": 24, "colors": [], "map": ["........", "........", "........", "........", "........", "........", "........", "........", "________", "________"]},
	7: {"moves": 20, "colors": [[3, 20], [1, 20]], "map": ["#......#", "........", "........", "........", "........", "........", "........", "........", "........", "#......#"]},
	8: {"moves": 20, "colors": [], "map": ["........", "........", "........", ".v....v.", "........", "...vv...", "........", ".v....v.", "........", "........"]},
	9: {"moves": 22, "colors": [], "map": ["........", "........", "........", "........", "...CC...", "..CccC..", ".CccccC.", "CccccccC", "........", "........"]},
	10: {"moves": 26, "hard": 1, "colors": [], "map": ["##....##", "#......#", "........", "cc....cc", "cc....cc", "........", "________", "________", "#______#", "##____##"]},
	11: {"moves": 26, "colors": [[2, 18]], "map": ["........", "........", "........", "..LLLL..", "..LLLL..", "........", "........", "........", "........", "........"]},
	12: {"moves": 20, "colors": [], "map": ["L......L", ".L....L.", "..L..L..", "...cc...", "...cc...", "..L..L..", ".L....L.", "L......L", "........", "........"]},
	13: {"moves": 20, "colors": [[0, 16], [2, 16], [4, 16]], "map": ["........", "........", "........", "........", "........", "........", "........", "........", "........", "........"]},
	14: {"moves": 20, "colors": [], "map": ["........", "........", "........", "........", "........", "........", "........", "........", "iiiiiiii", "iiiiiiii"]},
	15: {"moves": 22, "colors": [], "map": ["........", "........", "#.cccc.#", "##....##", "##....##", "#.cccc.#", "........", "iiiiiiii", "iiiiiiii", "........"]},
	16: {"moves": 18, "colors": [], "map": ["........", "........", "..____..", "._v__v_.", "._v__v_.", "..____..", "........", "........", "........", "........"]},
	17: {"moves": 18, "colors": [], "map": ["........", "........", "........", "........", "b..bb..b", "........", ".b....b.", "........", "........", "........"]},
	18: {"moves": 24, "colors": [], "map": ["........", "........", "........", "........", "........", "..b..b..", "._b__b_.", "________", "________", "........"]},
	19: {"moves": 18, "colors": [[2, 20], [4, 20]], "map": ["#......#", "........", "........", "c......c", "cc....cc", "........", "........", "........", "........", "#......#"]},
	20: {"moves": 18, "hard": 1, "colors": [], "map": ["........", "........", "LLL..LLL", "........", "..cCCc..", "..cCCc..", "........", "iiiiiiii", "iiiiiiii", "........"]},
	21: {"moves": 18, "colors": [], "map": ["........", "........", "........", "........", ".FF..FF.", ".FF..FF.", "........", "........", "........", "........"]},
	22: {"moves": 20, "colors": [], "map": ["........", "........", "...FF...", "...FF...", "........", "FF....FF", "FF____FF", "________", "________", "........"]},
	23: {"moves": 26, "items": 2, "colors": [], "map": ["##....##", "........", "........", "........", "........", "........", "........", "........", "........", "##....##"]},
	24: {"moves": 30, "items": 2, "colors": [], "map": ["........", "........", "........", "........", "cc.cc.cc", "........", "........", ".c.cc.c.", "........", "........"]},
	25: {"moves": 20, "hard": 2, "colors": [], "map": ["........", "..KKKK..", "..K..K..", "........", "MM....MM", "........", "........", "IIIiiIII", "iiiiiiii", "........"]},
	26: {"moves": 18, "colors": [], "map": ["........", "........", "........", ".s.ss.s.", "........", "........", "s.s..s.s", "........", "........", "........"]},
	27: {"moves": 24, "colors": [], "map": ["........", "........", "..s..s..", "........", "_s____s_", "________", "________", "........", "........", "........"]},
	28: {"moves": 34, "items": 3, "colors": [], "map": ["........", "........", "........", "LL....LL", "..LLLL..", "........", "........", "........", "........", "........"]},
	29: {"moves": 18, "colors": [[0, 18], [1, 18], [3, 18]], "map": ["#......#", "##....##", "........", "........", "........", "........", "........", "........", "##....##", "#......#"]},
	30: {"moves": 20, "hard": 1, "colors": [], "map": ["........", "FF....FF", "FF....FF", "........", "..cccc..", "..cCCc..", "........", "iiiiiiii", "iIIiiIIi", "........"]},
	31: {"moves": 18, "colors": [[1, 16]], "map": ["........", "........", "........", "..h..h..", "........", "...h....", "........", "........", "........", "........"]},
	32: {"moves": 18, "colors": [], "map": ["........", "........", "cc....cc", "c..hh..c", "c......c", "cc....cc", "........", "........", "........", "........"]},
	33: {"moves": 20, "colors": [], "map": ["........", "........", "iiii____", "iiii____", "........", "........", "____iiii", "____iiii", "........", "........"]},
	34: {"moves": 18, "colors": [], "map": ["........", "........", "........", "........", ".GG..GG.", ".GG..GG.", "........", "........", "........", "........"]},
	35: {"moves": 18, "colors": [], "map": ["........", "........", "L.L..L.L", "........", "...GG...", "...GG...", "........", "L.L..L.L", "........", "........"]},
	36: {"moves": 18, "colors": [[2, 22], [4, 22]], "map": ["........", "........", "........", "........", "........", "........", "........", "........", "........", "........"]},
	37: {"moves": 23, "colors": [], "map": ["........", "........", ".v.bb.v.", "........", "________", "__v__v__", "________", "........", "........", "........"]},
	38: {"moves": 18, "colors": [], "map": ["........", "........", "B.B..B.B", "........", ".B.BB.B.", "........", "B.B..B.B", "........", "........", "........"]},
	39: {"moves": 18, "colors": [], "map": ["........", "........", ".BBBBBB.", "........", "........", "........", "........", "iiiiiiii", "iiiiiiii", "........"]},
	40: {"moves": 20, "hard": 1, "colors": [], "map": ["........", "........", ".GG..GG.", ".GG..GG.", "........", "KccccccK", "........", "........", "........", "........"]},
	41: {"moves": 35, "items": 2, "colors": [], "map": ["........", "........", "........", "s......s", ".s....s.", "..s..s..", "........", "........", "........", "........"]},
	42: {"moves": 18, "colors": [[0, 18]], "map": ["........", "........", "........", "..j..j..", "........", ".j....j.", "........", "........", "........", "........"]},
	43: {"moves": 18, "colors": [], "map": ["........", "........", "cjc..cjc", "ccc..ccc", "........", "........", "..cjjc..", "..cccc..", "........", "........"]},
	44: {"moves": 18, "colors": [], "map": ["........", "........", "........", "..h..h..", "________", "________", "________", "........", "........", "........"]},
	45: {"moves": 18, "colors": [[3, 20]], "map": ["........", "B......B", "........", "..B..B..", "........", "........", "..B..B..", "........", "B......B", "........"]},
	46: {"moves": 18, "colors": [], "map": ["........", "........", "........", ".w....w.", "........", "........", "...ww...", "........", "........", "........"]},
	47: {"moves": 20, "colors": [], "map": ["........", "........", "..w..w..", "........", "________", "________", "________", "........", "........", "........"]},
	48: {"moves": 28, "colors": [], "map": ["........", "h......h", "........", "..FF....", "..FF..FF", "......FF", "........", "........", "h......h", "........"]},
	49: {"moves": 20, "colors": [], "map": ["........", "........", ".w.ww.w.", "........", "........", "........", "IiiiiiiI", "iiiiiiii", "........", "........"]},
	50: {"moves": 22, "hard": 2, "colors": [], "map": ["........", "KKK..KKK", "........", "MM.MM.MM", "........", "..GG....", "..GG....", "IIIIIIII", "iiiiiiii", "........"]},
	51: {"moves": 18, "colors": [[2, 16]], "map": ["........", "........", "........", "..S..S..", "........", "........", "........", "........", "........", "........"]},
	52: {"moves": 20, "colors": [], "map": ["........", "........", "ccS..Scc", "cc....cc", "........", "........", "..cSSc..", "..cccc..", "........", "........"]},
	53: {"moves": 34, "items": 2, "colors": [], "map": ["........", "........", "........", ".w....w.", "........", "..w..w..", "........", "........", "........", "........"]},
	54: {"moves": 23, "colors": [], "map": ["........", "________", "________", "##____##", "##____##", "________", "________", "........", "........", "........"]},
	55: {"moves": 20, "colors": [], "map": ["........", "........", "B.B..B.B", "LLLLLLLL", "........", "..cccc..", "........", "........", "........", "........"]},
	56: {"moves": 20, "colors": [[0, 22], [1, 22]], "map": ["#......#", "........", "........", "........", "##....##", "##....##", "........", "........", "........", "#......#"]},
	57: {"moves": 18, "colors": [], "map": ["........", "........", "s.h..h.s", "........", "s......s", "........", "..s..s..", "........", "........", "........"]},
	58: {"moves": 22, "colors": [], "map": ["........", "FF....GG", "FF....GG", "........", "........", "GG....FF", "GG....FF", "........", "........", "........"]},
	59: {"moves": 22, "colors": [], "map": ["........", "........", "........", "........", "IIIIIIII", "IiiiiiiI", "IiiiiiiI", "IIIIIIII", "........", "........"]},
	60: {"moves": 22, "hard": 1, "colors": [], "map": ["........", "........", "S..bb..S", "........", "__b__b__", "________", "________", "________", "........", "........"]},
	61: {"moves": 26, "colors": [[3, 18]], "map": ["........", "........", "........", "..t..t..", "........", "........", "........", "........", "........", "........"]},
	62: {"moves": 20, "colors": [], "map": ["........", "........", "cccTTccc", "...TT...", "........", "cc....cc", "........", "........", "........", "........"]},
	63: {"moves": 28, "items": 2, "colors": [], "map": ["........", "........", ".v....v.", "........", "........", "...vv...", "........", "........", "........", "........"]},
	64: {"moves": 18, "colors": [], "map": ["........", "........", "B.j..j.B", "........", ".B.BB.B.", "........", "..j..j..", "........", "........", "........"]},
	65: {"moves": 18, "colors": [[2, 20], [3, 20], [4, 20]], "map": ["........", "........", "........", "........", "........", "........", "........", "........", "........", "........"]},
	66: {"moves": 20, "colors": [], "map": ["........", "........", "__v__v__", "________", "v______v", "________", "__v__v__", "........", "........", "........"]},
	67: {"moves": 20, "colors": [], "map": ["........", "........", "LLw..wLL", "LL....LL", "........", "........", "..w..w..", "........", "........", "........"]},
	68: {"moves": 22, "colors": [], "map": ["........", "........", "..h..h..", "........", "........", "........", "iiiiiiii", "iiiiiiii", "iiiiiiii", "........"]},
	69: {"moves": 20, "colors": [], "map": ["........", "#cc..cc#", "#c....c#", "........", "...GG...", "...GG...", "........", "#c....c#", "#cc..cc#", "........"]},
	70: {"moves": 25, "hard": 1, "colors": [], "map": ["........", "KK.SS.KK", "........", "........", "........", "..FF....", "..FF....", "........", "IIIIIIII", "........"]},
	71: {"moves": 18, "colors": [], "map": ["........", "........", "........", "..0..1..", "........", ".2....3.", "........", "...44...", "........", "........"]},
	72: {"moves": 25, "colors": [], "map": ["........", "........", "01234012", "........", "........", "________", "________", "........", "........", "........"]},
	73: {"moves": 34, "items": 3, "colors": [], "map": ["........", "........", "........", "iiiiiiii", "........", "........", "........", "........", "........", "........"]},
	74: {"moves": 22, "colors": [], "map": ["........", "FF....FF", "FF....FF", "........", "...GG...", "...GG...", "........", "GG....GG", "GG....GG", "........"]},
	75: {"moves": 24, "hard": 2, "colors": [], "map": ["#KKKKKK#", "........", "MM.SS.MM", "........", "........", "........", "IIIIIIII", "IIIIIIII", "........", "........"]},
	76: {"moves": 20, "colors": [], "map": ["........", "........", "B.w..w.B", "........", "________", "________", "........", "........", "........", "........"]},
	77: {"moves": 28, "colors": [], "map": ["........", "h......h", "........", "..s..s..", "........", "..s..s..", "........", "h......h", "........", "........"]},
	78: {"moves": 22, "colors": [], "map": ["##....##", "#......#", "........", "cCKKKKCc", "........", "........", "LLLLLLLL", "........", "#......#", "##....##"]},
	79: {"moves": 18, "colors": [[0, 20], [4, 20]], "map": ["........", "#......#", "........", ".B....B.", "........", "........", ".B....B.", "........", "#......#", "........"]},
	80: {"moves": 28, "hard": 1, "colors": [], "map": ["........", "........", "TT.jj.TT", "TT....TT", "........", "________", "________", "________", "........", "........"]},
	81: {"moves": 20, "colors": [], "map": ["........", "........", "0.1..2.3", "........", "iiiiiiii", "iiiiiiii", "........", "........", "........", "........"]},
	82: {"moves": 20, "colors": [], "map": ["........", "........", "..S..S..", "........", "s.s..s.s", "........", "........", "........", "........", "........"]},
	83: {"moves": 35, "colors": [], "map": ["........", "........", ".w.GG.w.", "...GG...", "........", "........", "LLLLLLLL", "LLLLLLLL", "........", "........"]},
	84: {"moves": 18, "colors": [], "map": ["........", "__h__h__", "________", "________", "........", "........", "........", "........", "........", "........"]},
	85: {"moves": 30, "items": 2, "colors": [], "map": ["........", "........", "B......B", ".B....B.", "..B..B..", "...BB...", "........", "iiiiiiii", "........", "........"]},
	86: {"moves": 20, "colors": [], "map": ["........", "##.FF.##", "##.FF.##", "........", "cc....cc", "cCC..CCc", "........", "........", "........", "........"]},
	87: {"moves": 18, "colors": [[1, 20], [2, 20], [3, 20]], "map": ["##....##", "#......#", "........", "........", "........", "........", "........", "........", "#......#", "##....##"]},
	88: {"moves": 22, "colors": [], "map": ["........", "........", "vvvvvvvv", "........", "________", "________", "________", "........", "........", "........"]},
	89: {"moves": 28, "items": 2, "colors": [], "map": ["........", "........", "K......K", ".K....K.", "........", "........", ".C....C.", "C......C", "........", "........"]},
	90: {"moves": 32, "hard": 1, "colors": [], "map": ["........", "SS....SS", "........", "..GG....", "..GG..FF", "......FF", "........", "IIIIIIII", "IIIIIIII", "........"]},
	91: {"moves": 26, "colors": [], "map": ["........", "........", "w.0..1.w", "........", "w.2..3.w", "........", "________", "________", "........", "........"]},
	92: {"moves": 29, "colors": [], "map": ["........", "........", "........", "MMMMMMMM", "........", "..jjjj..", "........", "MMMMMMMM", "........", "........"]},
	93: {"moves": 18, "colors": [], "map": ["........", "........", "..h..h..", "........", "s.s..s.s", "........", "IIIIIIII", "........", "........", "........"]},
	94: {"moves": 36, "items": 2, "colors": [], "map": ["........", "#KK..KK#", "#K....K#", "........", "........", "........", "#K....K#", "#KK..KK#", "........", "........"]},
	95: {"moves": 22, "colors": [], "map": ["........", "........", "B.B.B.B.", ".B.B.B.B", "........", "GG....GG", "GG....GG", "........", "........", "........"]},
	96: {"moves": 32, "colors": [], "map": ["........", "........", "........", "..TT....", "..TT..TT", "......TT", "........", "________", "________", "........"]},
	97: {"moves": 18, "colors": [[0, 22], [3, 22]], "map": ["........", "........", "#......#", "##....##", "###..###", "###..###", "##....##", "#......#", "........", "........"]},
	98: {"moves": 24, "colors": [], "map": ["........", "w......w", "........", "..FF....", "..FF....", "........", "LLLLLLLL", "iiiiiiii", "........", "........"]},
	99: {"moves": 30, "colors": [], "map": ["........", "........", "01234012", "........", "h......h", "........", "IIIIIIII", "iiiiiiii", "........", "........"]},
	100: {"moves": 36, "hard": 2, "items": 2, "colors": [], "map": ["........", "KKK..KKK", "........", "GG....GG", "GG....GG", "........", "KccccccK", "........", "IIIIIIII", "IIIIIIII"]},
}


const HAND_BLOCK := {"c": ["crate", 1], "C": ["crate", 2], "K": ["crate", 3], "v": ["vase", 2], "b": ["bush", 2], "s": ["shell", 2],
	"j": ["jar", 1], "B": ["balloon", 1], "w": ["can", 3], "S": ["safe", 5], "t": ["stone", 3]}
const HAND_BIG := {"F": ["flower", 3], "G": ["cage", 4], "T": ["stone", 3]}


static func make_hand(n: int) -> Dictionary:
	var h: Dictionary = HAND[n]
	var lv := {
		"n": n, "colors": 5, "moves": int(h.moves), "goals": [], "blocks": {}, "chains": {}, "grass_start": [],
		"grass_target": [], "items": int(h.get("items", 0)), "ice": {}, "honey": [], "zone": zone_of(n), "seed": n * 7919 + 17, "hand": true,
	}
	if h.has("hard"):
		lv["hard"] = int(h.hard)
	var holes: Array = []
	var counts := {}
	var order: Array = []  # порядок целей — как препятствия встречаются на карте
	var map: Array = h.map
	var add := func(k: String) -> void:
		counts[k] = counts.get(k, 0) + 1
		if k not in order:
			order.append(k)
	for y in H:
		var row: String = map[y]
		for x in W:
			var c := Vector2i(x, y)
			var ch := row[x]
			if HAND_BLOCK.has(ch):
				var hb: Array = HAND_BLOCK[ch]
				lv.blocks[c] = {"kind": BLOCK[hb[0]][0], "hp": int(hb[1]), "color": 0}
				add.call(hb[0])
			elif HAND_BIG.has(ch):
				if lv.blocks.has(c):
					continue
				var hb: Array = HAND_BIG[ch]
				for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					lv.blocks[c + d] = {"kind": BLOCK[hb[0]][0], "hp": int(hb[1]), "anchor": c, "color": 0}
				add.call(hb[0])
			elif "01234".contains(ch):
				lv.blocks[c] = {"kind": BLOCK.colorbox[0], "hp": 1, "color": int(ch)}
				add.call("colorbox")
			else:
				match ch:
					"#":
						holes.append(c)
					"L", "M":
						lv.chains[c] = 1 if ch == "L" else 2
						add.call("chain")
					"i", "I":
						lv.ice[c] = 1 if ch == "i" else 2
						add.call("ice")
					"h":
						lv.honey.append(c)
						add.call("honey")
					"_":
						lv.grass_target.append(c)
						add.call("grass")
	if not holes.is_empty():
		lv["holes"] = holes
	for cg in h.colors:
		lv.goals.append({"kind": "color", "color": int(cg[0]), "left": int(cg[1])})
	for k in order:
		lv.goals.append({"kind": k, "left": int(counts[k])})
	if lv.items > 0:
		lv.goals.append({"kind": "item", "left": lv.items})
	return lv
