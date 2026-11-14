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
const UNLOCKS := [[4, "crate"], [6, "grass"], [8, "vase"], [11, "chain"], [14, "ice"], [17, "bush"], [20, "flower"],
	[23, "item"], [26, "shell"], [30, "honey"], [34, "cage"], [38, "stone"], [42, "jar"], [46, "birdhouse"], [50, "safe"], [55, "colorbox"]]


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


const OBSTACLES := ["crate", "grass", "vase", "chain", "bush", "flower", "shell", "item", "ice", "stone", "honey", "cage", "birdhouse", "jar", "safe", "colorbox"]
## Блоки на поле: номер вида (как в board.gd) и прочность.
const BLOCK := {"crate": [1, 1], "vase": [2, 2], "safe": [3, 5], "jar": [4, 1], "cage": [5, 2], "balloon": [6, 1], "flower": [7, 2], "bush": [8, 2], "shell": [9, 2],
	"stone": [10, 3], "colorbox": [11, 1], "birdhouse": [12, 3]}


static func make(n: int) -> Dictionary:
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
	if n % 15 == 0:
		lv["hard"] = 2
		lv.moves -= 4
	elif n % 5 == 0:
		lv["hard"] = 1
		lv.moves -= 2
	lv["seed"] = rng.randi()
	return lv


## Большие препятствия 2×2 (как в Royal Match): камень, цветок, клетка.
const BIG := {"stone": 4, "flower": 3, "cage": 3}


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
			if lv.blocks.has(c):
				free = false
		if not free:
			continue
		for c in cells:
			lv.blocks[c] = {"kind": BLOCK[kind][0], "hp": BIG[kind], "anchor": a, "color": 0}
		count += 1
		if count >= want:
			break
	lv.goals.append({"kind": kind, "left": count})
	lv.moves += 4 * count


static func _add_obstacle(lv: Dictionary, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	if BIG.has(kind):
		_add_big(lv, kind, n, rng)
		return
	match kind:
		"crate", "vase", "safe", "jar", "cage", "balloon", "flower", "bush", "shell", "stone", "colorbox", "birdhouse":
			var info: Array = BLOCK[kind]
			var width := mini(4 + n / 30, 6) if kind in ["crate", "vase", "balloon"] else (3 if kind in ["stone", "safe"] else mini(3 + n / 60, 5))
			var count := 0
			var want := 2 if kind == "birdhouse" else width + (2 if kind in ["crate", "vase"] and n > 20 else 0)
			for c: Vector2i in _pattern(n + kind.length(), want, rng):
				if lv.blocks.has(c):
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
			if kind == "birdhouse":
				lv["birdhouse"] = true
				# цель — птицы: каждый скворечник выпускает 3 птицы, их надо спустить вниз
				lv.goals.append({"kind": "item", "left": count * 3})
				lv.moves += 7
			else:
				lv.goals.append({"kind": kind, "left": count})
				lv.moves += 7 if kind in ["safe", "stone"] else (5 if kind == "vase" else 3)
		"ice":
			var count := 0
			for y in range(H - 3, H):
				for x in W:
					var c := Vector2i(x, y)
					if not lv.blocks.has(c):
						lv.ice[c] = 2 if (n >= 20 and rng.randf() < 0.3) else 1
						count += 1
			lv.goals.append({"kind": "ice", "left": count})
			lv.moves += 4
		"honey":
			while lv.honey.size() < 3:
				var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(2, 5))
				if c not in lv.honey and not lv.chains.has(c):
					lv.honey.append(c)
			lv.goals.append({"kind": "honey", "left": 3})
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
			lv.goals.append({"kind": "grass", "left": lv.grass_target.size() - lv.grass_start.size()})
			lv.moves += 6
		"item":
			lv.items = clampi(2 + n / 10, 2, 4)
			lv.goals.append({"kind": "item", "left": lv.items})
			lv.moves += 3 * lv.items + 2
		"chain":
			var count := clampi(5 + n / 4, 5, 12)
			var cells: Array = []
			while cells.size() < count:
				var c := Vector2i(rng.randi_range(0, W - 1), rng.randi_range(2, 5))
				if c in cells:
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
	var block_goal := {1: "crate", 2: "vase", 3: "safe", 4: "jar", 5: "cage", 6: "balloon", 7: "flower", 8: "bush", 9: "shell", 10: "stone", 11: "colorbox"}
	for g in lv.goals:
		match g.kind:
			"chain":
				g.left = lv.chains.size()
			"ice":
				g.left = lv.ice.size()
			"honey":
				g.left = lv.honey.size()
			"grass":
				g.left = lv.grass_target.size() - lv.grass_start.size()
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
