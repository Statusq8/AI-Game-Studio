extends RefCounted
## Генератор уровней: по номеру уровня всегда выдаёт одно и то же (сид = номер).
## Цели: собрать фишки нужного цвета и разбить ящики. Ящики стоят в нижних рядах.

const W := 8
const H := 8


static func make(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919 + 17
	var colors := 5
	var moves := clampi(26 - n / 6, 18, 26)
	var goals: Array = []
	var crates := {}

	var color_goals := 1 if n <= 2 else (2 if n < 15 else 3)
	var picked: Array = []
	while picked.size() < color_goals:
		var c := rng.randi_range(0, colors - 1)
		if c not in picked:
			picked.append(c)
	for c in picked:
		var amount := mini(10 + n + rng.randi_range(0, 3), 16 + n / 4)
		if color_goals == 3:
			amount = int(amount * 0.8)
		goals.append({"kind": "color", "color": c, "left": amount})

	# Ящики — с 4-го уровня, через уровень.
	if n >= 4 and n % 2 == 0:
		var rows := 1 if n < 16 else 2
		var hp2 := n >= 12
		var width := mini(4 + n / 6, W)
		var x0 := (W - width) / 2
		for y in range(H - rows, H):
			for x in range(x0, x0 + width):
				crates[Vector2i(x, y)] = 2 if (hp2 and y == H - 1 and rng.randf() < 0.4) else 1
		goals.append({"kind": "crate", "left": crates.size()})
		moves += 4

	return {"n": n, "colors": colors, "moves": moves, "goals": goals, "crates": crates, "seed": rng.randi()}
