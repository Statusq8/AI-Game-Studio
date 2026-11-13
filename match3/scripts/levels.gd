extends RefCounted
## Генератор уровней: по номеру уровня всегда выдаёт одно и то же (сид = номер).
## Цели: фишки нужного цвета + одно-два препятствия (ящики, трава, предметы, цепи, вазы).

const W := 8
const H := 8
const B_CRATE := 1
const B_VASE := 2
const OBSTACLES := ["crate", "grass", "item", "chain", "vase"]


static func make(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var lv := {
		"n": n, "colors": 5, "moves": clampi(26 - n / 6, 18, 26), "goals": [],
		"blocks": {}, "chains": {}, "grass_start": [], "grass_target": [], "items": 0,
	}

	var kinds: Array = []
	if n >= 4:
		kinds.append(OBSTACLES[(n - 4) % OBSTACLES.size()])
	if n >= 14 and n % 3 == 0:
		var extra: String = OBSTACLES[(n + 1) % OBSTACLES.size()]
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
	lv["seed"] = rng.randi()
	return lv


static func _add_obstacle(lv: Dictionary, kind: String, n: int, rng: RandomNumberGenerator) -> void:
	match kind:
		"crate", "vase":
			var width := mini(4 + n / 8, W)
			var x0 := (W - width) / 2
			var hp2 := n >= 12
			var count := 0
			for x in range(x0, x0 + width):
				var c := Vector2i(x, H - 1)
				if lv.blocks.has(c):
					continue
				var hp := 2 if (hp2 and rng.randf() < 0.35) else 1
				lv.blocks[c] = {"kind": B_CRATE if kind == "crate" else B_VASE, "hp": hp}
				count += 1
			lv.goals.append({"kind": kind, "left": count})
			lv.moves += 4 if kind == "crate" else 8
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
