extends RefCounted
## Генератор уровней: по номеру уровня всегда выдаёт одно и то же (сид = номер).
## Цели: фишки нужного цвета + одно-два препятствия (ящики, трава, предметы, цепи, вазы).

const W := 8
const H := 8
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
const OBSTACLES := ["crate", "grass", "item", "chain", "vase", "ice", "honey", "jar", "flower", "cage", "bush", "shell", "safe"]
## Блоки на поле: номер вида (как в board.gd) и прочность.
const BLOCK := {"crate": [1, 1], "vase": [2, 1], "safe": [3, 3], "jar": [4, 1], "cage": [5, 2], "balloon": [6, 1], "flower": [7, 2], "bush": [8, 2], "shell": [9, 2]}


static func make(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var lv := {
		"n": n, "colors": 5, "moves": clampi(26 - n / 6, 18, 26), "goals": [],
		"blocks": {}, "chains": {}, "grass_start": [], "grass_target": [], "items": 0, "ice": {}, "honey": [],
	}

	var kinds: Array = []
	# новые препятствия открываются постепенно: к 31-му уровню — все 14
	var unlocked := clampi(5 + (n - 4) / 3, 5, OBSTACLES.size())
	if n >= 4:
		kinds.append(OBSTACLES[(n - 4) % unlocked])
	if n >= 14 and n % 3 == 0:
		var extra: String = OBSTACLES[(n + 1) % unlocked]
		if extra not in kinds:
			kinds.append(extra)

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
		var amount := mini(10 + n + rng.randi_range(0, 3), 16 + n / 4)
		if color_goals == 3:
			amount = int(amount * 0.8)
		lv.goals.append({"kind": "color", "color": c, "left": amount})

	for k in kinds:
		_add_obstacle(lv, k, n, rng)
	# фигурное поле с 6-го уровня, каждый 2-й уровень
	# фигурное поле: с 6-го уровня на 3 уровнях из 4, форма по номеру уровня
	if n >= 6 and n % 4 != 1:
		var holes: Array = SHAPES[(n * 7) % SHAPES.size()]
		lv["holes"] = holes
		_cut_holes(lv, holes)
	# сложные уровни: каждый 10-й «Сложный», каждый 30-й «Очень сложный» (меньше ходов, больше монет)
	if n % 30 == 0:
		lv["hard"] = 2
		lv.moves -= 5
	elif n % 10 == 0:
		lv["hard"] = 1
		lv.moves -= 3
	lv["seed"] = rng.randi()
	return lv


static func _add_obstacle(lv: Dictionary, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	match kind:
		"crate", "vase", "safe", "jar", "cage", "balloon", "flower", "bush", "shell":
			var info: Array = BLOCK[kind]
			var width := mini(4 + n / 10, W) if kind in ["crate", "vase", "balloon"] else mini(3 + n / 15, 6)
			var x0 := (W - width) / 2
			var count := 0
			for x in range(x0, x0 + width):
				var c := Vector2i(x, H - 1)
				if lv.blocks.has(c):
					continue
				var hp: int = info[1]
				if kind == "crate" and n >= 12:
					hp = rng.randi_range(1, 3)
				elif kind == "vase" and n >= 12 and rng.randf() < 0.4:
					hp = 2
				lv.blocks[c] = {"kind": info[0], "hp": hp}
				count += 1
			lv.goals.append({"kind": kind, "left": count})
			lv.moves += 8 if kind in ["vase", "safe"] else 5
		"ice":
			var count := 0
			for y in range(H - 3, H):
				for x in W:
					var c := Vector2i(x, y)
					if not lv.blocks.has(c):
						lv.ice[c] = 2 if (n >= 20 and rng.randf() < 0.3) else 1
						count += 1
			lv.goals.append({"kind": "ice", "left": count})
			lv.moves += 6
		"honey":
			while lv.honey.size() < 3:
				var c := Vector2i(rng.randi_range(1, W - 2), rng.randi_range(2, 5))
				if c not in lv.honey and not lv.chains.has(c):
					lv.honey.append(c)
			lv.goals.append({"kind": "honey", "left": 3})
			lv.moves += 4
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
			lv.moves += 8
		"item":
			lv.items = clampi(2 + n / 10, 2, 4)
			lv.goals.append({"kind": "item", "left": lv.items})
			lv.moves += 6
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
			lv.moves += 3


## Убираем препятствия из дыр и пересчитываем цели.
static func _cut_holes(lv: Dictionary, holes: Array) -> void:
	for c in holes:
		lv.blocks.erase(c)
		lv.chains.erase(c)
		lv.ice.erase(c)
		lv.honey.erase(c)
		lv.grass_target.erase(c)
		lv.grass_start.erase(c)
	var block_goal := {1: "crate", 2: "vase", 3: "safe", 4: "jar", 5: "cage", 6: "balloon", 7: "flower", 8: "bush", 9: "shell"}
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
					if block_goal.get(lv.blocks[c].kind, "") == g.kind:
						cnt += 1
				g.left = cnt
	# лёд/трава могли закончиться — в цель ставим хотя бы что-то разумное
	lv.goals = lv.goals.filter(func(g: Dictionary) -> bool: return g.left > 0)
