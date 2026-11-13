extends Node2D
## Игровое поле «три в ряд»: логика (совпадения, особые фишки, падение, перемешивание) и анимации.
##
## Особые фишки:
##   4 в ряд      → ракета (чистит ряд или столбец, по направлению совпадения);
##   буква L / T  → бомба (3×3);
##   5 в ряд      → радужный шар (свап с фишкой убирает все фишки этого цвета).
## Свап двух особых фишек — комбо. Тап по особой фишке — активировать (тратит ход).

signal move_made
signal gem_cleared(color: int, global_pos: Vector2)
signal crate_broken(global_pos: Vector2)
signal settled
signal big_hit(power: float)

const Gem := preload("res://scripts/gem.gd")
const CELL := 84.0

var W := 8
var H := 8
var colors := 5
var tiles: Array = []   # tiles[x][y] -> Gem | null
var crates: Array = []  # crates[x][y] -> int (прочность, 0 = нет ящика)
var crate_nodes := {}   # Vector2i -> Node2D
var busy := false
var input_enabled := true
var rng := RandomNumberGenerator.new()
var fx: Node2D          # слой эффектов (не обрезается рамкой поля)

var _press_cell := Vector2i(-1, -1)
var _press_pos := Vector2.ZERO
var _selected := Vector2i(-1, -1)
var _dragging := false
var _idle := 0.0
var _hint_tweens: Array[Tween] = []
var _crate_hits := {}


# ---------- создание поля ----------

func setup(level: Dictionary) -> void:
	colors = level.colors
	rng.seed = level.seed
	for c in get_children():
		c.queue_free()
	crate_nodes.clear()
	tiles = []
	crates = []
	for x in W:
		tiles.append([])
		crates.append([])
		for y in H:
			tiles[x].append(null)
			crates[x].append(int(level.crates.get(Vector2i(x, y), 0)))
	for cell: Vector2i in level.crates:
		_make_crate_node(cell)
	_fill_initial()
	queue_redraw()


func _fill_initial() -> void:
	for attempt in 50:
		for x in W:
			for y in H:
				if tiles[x][y]:
					tiles[x][y].queue_free()
					tiles[x][y] = null
		for y in H:
			for x in W:
				if crates[x][y] > 0:
					continue
				var c := rng.randi_range(0, colors - 1)
				var guard := 0
				while _would_match(x, y, c) and guard < 20:
					c = rng.randi_range(0, colors - 1)
					guard += 1
				_place(_new_gem(c), Vector2i(x, y))
		if find_move().size() > 0:
			return


func _would_match(x: int, y: int, c: int) -> bool:
	if x >= 2 and color_at(Vector2i(x - 1, y)) == c and color_at(Vector2i(x - 2, y)) == c:
		return true
	if y >= 2 and color_at(Vector2i(x, y - 1)) == c and color_at(Vector2i(x, y - 2)) == c:
		return true
	return false


func _new_gem(c: int, kind: int = Gem.NONE) -> Node2D:
	var g: Node2D = Gem.new()
	g.color = c
	g.size = CELL
	add_child(g)
	if kind != Gem.NONE:
		g.set_special(kind)
	return g


func _place(g: Node2D, cell: Vector2i) -> void:
	tiles[cell.x][cell.y] = g
	g.cell = cell
	g.position = cell_pos(cell)


func _make_crate_node(cell: Vector2i) -> void:
	var n := Node2D.new()
	n.position = cell_pos(cell)
	n.z_index = 1
	n.draw.connect(_draw_crate.bind(n, cell))
	add_child(n)
	crate_nodes[cell] = n


func _draw_crate(n: Node2D, cell: Vector2i) -> void:
	var hp: int = crates[cell.x][cell.y]
	var s := CELL * 0.46
	var wood := Color("#c98a4b") if hp <= 1 else Color("#9a6337")
	n.draw_rect(Rect2(-s, -s + 4, s * 2, s * 2), Color(0, 0, 0, 0.25))
	n.draw_rect(Rect2(-s, -s, s * 2, s * 2), wood.darkened(0.35))
	n.draw_rect(Rect2(-s + 5, -s + 5, s * 2 - 10, s * 2 - 10), wood)
	for i in 3:
		var yy := -s + 5 + (s * 2 - 10) * (i + 0.5) / 3.0
		n.draw_line(Vector2(-s + 6, yy), Vector2(s - 6, yy), wood.darkened(0.2), 2.0)
	n.draw_line(Vector2(-s + 6, -s + 6), Vector2(s - 6, s - 6), wood.darkened(0.45), 6.0)
	if hp >= 2:
		n.draw_line(Vector2(s - 6, -s + 6), Vector2(-s + 6, s - 6), wood.darkened(0.45), 6.0)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		n.draw_circle(corner * (s - 9), 3.5, Color("#5b5b66"))


func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * CELL


func board_size() -> Vector2:
	return Vector2(W, H) * CELL


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, board_size())
	for x in W:
		for y in H:
			var c := Color(1, 1, 1, 0.16) if (x + y) % 2 == 0 else Color(1, 1, 1, 0.08)
			draw_rect(Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL)), c)
	draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)


# ---------- запросы к полю ----------

func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func gem_at(c: Vector2i) -> Node2D:
	if not inside(c):
		return null
	return tiles[c.x][c.y]


func color_at(c: Vector2i) -> int:
	var g := gem_at(c)
	if g == null or g.special == Gem.ORB:
		return -1
	return g.color


func _open(c: Vector2i) -> bool:
	return inside(c) and crates[c.x][c.y] <= 0


func crates_left() -> int:
	var n := 0
	for x in W:
		for y in H:
			if crates[x][y] > 0:
				n += 1
	return n


## Группы совпадений: [{cells: Array[Vector2i], runs: Array[{cells, dir}]}]
func find_groups() -> Array:
	var runs: Array = []
	for y in H:
		var x := 0
		while x < W:
			var c := color_at(Vector2i(x, y))
			var e := x
			while c >= 0 and e + 1 < W and color_at(Vector2i(e + 1, y)) == c:
				e += 1
			if c >= 0 and e - x + 1 >= 3:
				var cells: Array = []
				for i in range(x, e + 1):
					cells.append(Vector2i(i, y))
				runs.append({"cells": cells, "dir": "h"})
			x = e + 1
	for x in W:
		var y := 0
		while y < H:
			var c := color_at(Vector2i(x, y))
			var e := y
			while c >= 0 and e + 1 < H and color_at(Vector2i(x, e + 1)) == c:
				e += 1
			if c >= 0 and e - y + 1 >= 3:
				var cells: Array = []
				for i in range(y, e + 1):
					cells.append(Vector2i(x, i))
				runs.append({"cells": cells, "dir": "v"})
			y = e + 1
	# объединяем пересекающиеся серии в группы
	var parent: Array = range(runs.size())
	var owner_of := {}
	for i in runs.size():
		for cell in runs[i].cells:
			if owner_of.has(cell):
				var a := _find(parent, i)
				var b := _find(parent, owner_of[cell])
				parent[a] = b
			else:
				owner_of[cell] = i
	var by_root := {}
	for i in runs.size():
		var root := _find(parent, i)
		if not by_root.has(root):
			by_root[root] = {"cells": [], "runs": []}
		by_root[root].runs.append(runs[i])
		for cell in runs[i].cells:
			if cell not in by_root[root].cells:
				by_root[root].cells.append(cell)
	return by_root.values()


func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _has_match_at(c: Vector2i) -> bool:
	var col := color_at(c)
	if col < 0:
		return false
	var n := 1
	var p := c + Vector2i.LEFT
	while color_at(p) == col:
		n += 1
		p += Vector2i.LEFT
	p = c + Vector2i.RIGHT
	while color_at(p) == col:
		n += 1
		p += Vector2i.RIGHT
	if n >= 3:
		return true
	n = 1
	p = c + Vector2i.UP
	while color_at(p) == col:
		n += 1
		p += Vector2i.UP
	p = c + Vector2i.DOWN
	while color_at(p) == col:
		n += 1
		p += Vector2i.DOWN
	return n >= 3


## Возвращает пару клеток с ходом или пустой массив.
func find_move() -> Array:
	for x in W:
		for y in H:
			var a := Vector2i(x, y)
			var ga := gem_at(a)
			if ga == null:
				continue
			if ga.special != Gem.NONE:
				return [a, a]
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b: Vector2i = a + d
				var gb := gem_at(b)
				if gb == null:
					continue
				_swap_data(a, b)
				var ok := _has_match_at(a) or _has_match_at(b)
				_swap_data(a, b)
				if ok:
					return [a, b]
	return []


## Все возможные ходы (для бота-тестера).
func all_moves() -> Array:
	var out: Array = []
	for x in W:
		for y in H:
			var a := Vector2i(x, y)
			var ga := gem_at(a)
			if ga == null:
				continue
			if ga.special != Gem.NONE:
				out.append([a, a])
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b: Vector2i = a + d
				if gem_at(b) == null:
					continue
				_swap_data(a, b)
				var ok := _has_match_at(a) or _has_match_at(b)
				_swap_data(a, b)
				if ok:
					out.append([a, b])
	return out


func _swap_data(a: Vector2i, b: Vector2i) -> void:
	var t = tiles[a.x][a.y]
	tiles[a.x][a.y] = tiles[b.x][b.y]
	tiles[b.x][b.y] = t
	if tiles[a.x][a.y]:
		tiles[a.x][a.y].cell = a
	if tiles[b.x][b.y]:
		tiles[b.x][b.y].cell = b


# ---------- ввод ----------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or busy:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
		if event.pressed:
			_stop_hint()
			if not inside(cell):
				_selected = Vector2i(-1, -1)
				return
			_press_cell = cell
			_press_pos = local
			_dragging = true
		elif _dragging:
			_dragging = false
			if cell == _press_cell:
				_on_tap(cell)
	elif event is InputEventMouseMotion and _dragging:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		var d := local - _press_pos
		if d.length() > CELL * 0.35:
			_dragging = false
			var dir := Vector2i(signi(roundi(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, signi(roundi(d.y)))
			_selected = Vector2i(-1, -1)
			_unselect_all()
			try_swap(_press_cell, _press_cell + dir)


func _on_tap(cell: Vector2i) -> void:
	var g := gem_at(cell)
	if _selected != Vector2i(-1, -1):
		var prev := _selected
		_selected = Vector2i(-1, -1)
		_unselect_all()
		if (prev - cell).abs().x + (prev - cell).abs().y == 1:
			try_swap(prev, cell)
			return
		if prev == cell and g and g.special != Gem.NONE:
			activate_single(cell)
			return
	if g == null:
		return
	if g.special != Gem.NONE:
		activate_single(cell)
		return
	_selected = cell
	var tw := create_tween()
	tw.tween_property(g, "scale", Vector2(1.15, 1.15), 0.1)


func _unselect_all() -> void:
	for x in W:
		for y in H:
			var g: Node2D = tiles[x][y]
			if g and g.scale != Vector2.ONE:
				create_tween().tween_property(g, "scale", Vector2.ONE, 0.1)


func _process(delta: float) -> void:
	if busy or not input_enabled:
		_idle = 0.0
		return
	_idle += delta
	if _idle > 5.0:
		_idle = -3.0
		show_hint()


func show_hint() -> void:
	var m := find_move()
	if m.is_empty():
		return
	_stop_hint()
	for c: Vector2i in m:
		var g := gem_at(c)
		if g == null:
			continue
		var d := Vector2(m[1] - m[0]) * 8.0 * (1.0 if c == m[0] else -1.0)
		if d == Vector2.ZERO:
			d = Vector2(0, -8)
		var base := cell_pos(c)
		var t := create_tween()
		for i in 2:
			t.tween_property(g, "position", base + d, 0.15)
			t.tween_property(g, "position", base, 0.15)
		_hint_tweens.append(t)


func _stop_hint() -> void:
	for t in _hint_tweens:
		if t.is_valid():
			t.kill()
	_hint_tweens.clear()
	if busy:
		return
	for x in W:
		for y in H:
			var g: Node2D = tiles[x][y]
			if g:
				g.position = cell_pos(Vector2i(x, y))


# ---------- ходы ----------

func try_swap(a: Vector2i, b: Vector2i) -> void:
	var ga := gem_at(a)
	var gb := gem_at(b)
	if busy or ga == null or gb == null or not _open(b):
		return
	_stop_hint()
	busy = true
	_idle = 0.0
	_crate_hits.clear()
	await _animate_swap(ga, gb, a, b)
	_swap_data(a, b)
	# теперь ga стоит в b, gb — в a
	var sa: int = ga.special
	var sb: int = gb.special
	if sa != Gem.NONE and sb != Gem.NONE:
		move_made.emit()
		await _combo(ga, gb, b)
		await _cascade([])
		return
	if sa == Gem.ORB or sb == Gem.ORB:
		move_made.emit()
		var orb := ga if sa == Gem.ORB else gb
		var other := gb if orb == ga else ga
		await _orb_with_color(orb, other.color)
		await _cascade([])
		return
	if find_groups().is_empty():
		if sa != Gem.NONE or sb != Gem.NONE:
			move_made.emit()
			var sp := ga if sa != Gem.NONE else gb
			await _clear({sp.cell: true}, false)
			await _cascade([])
			return
		await _animate_swap(ga, gb, b, a)
		_swap_data(a, b)
		busy = false
		return
	move_made.emit()
	await _cascade([a, b])


func activate_single(cell: Vector2i) -> void:
	var g := gem_at(cell)
	if busy or g == null or g.special == Gem.NONE:
		return
	_stop_hint()
	busy = true
	_crate_hits.clear()
	move_made.emit()
	await _clear({cell: true}, false)
	await _cascade([])


func _animate_swap(ga: Node2D, gb: Node2D, a: Vector2i, b: Vector2i) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ga, "position", cell_pos(b), 0.16)
	tw.tween_property(gb, "position", cell_pos(a), 0.16)
	ga.z_index = 2
	await tw.finished
	ga.z_index = 0


func _cascade(prefer: Array) -> void:
	var combo := 0
	while true:
		var groups := find_groups()
		if groups.is_empty():
			break
		combo += 1
		var to_clear := {}
		var creations: Array = []
		_crate_hits.clear()
		for g in groups:
			for c in g.cells:
				to_clear[c] = true
			var kind := _special_for(g)
			if kind != Gem.NONE:
				var at := _creation_cell(g, prefer, kind)
				creations.append({"cell": at, "kind": kind, "color": color_at(at)})
		# ящики рядом с совпадениями получают удар
		for c: Vector2i in to_clear:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				_hit_crate(c + d)
		await _clear(to_clear, true, creations)
		for cr in creations:
			var cell: Vector2i = cr.cell
			if gem_at(cell) == null and _open(cell):
				var ng := _new_gem(cr.color, cr.kind)
				_place(ng, cell)
				ng.scale = Vector2(0.2, 0.2)
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(ng, "scale", Vector2.ONE, 0.25)
		await _gravity()
		prefer = []
	if find_move().is_empty():
		await _shuffle()
	busy = false
	settled.emit()


func _special_for(group: Dictionary) -> int:
	var longest := 0
	var dir := "h"
	var has_h := false
	var has_v := false
	for r in group.runs:
		if r.cells.size() > longest:
			longest = r.cells.size()
			dir = r.dir
		if r.dir == "h":
			has_h = true
		else:
			has_v = true
	if longest >= 5:
		return Gem.ORB
	if has_h and has_v:
		return Gem.BOMB
	if longest == 4:
		return Gem.ROCKET_H if dir == "h" else Gem.ROCKET_V
	return Gem.NONE


func _creation_cell(group: Dictionary, prefer: Array, kind: int) -> Vector2i:
	for p in prefer:
		if p in group.cells:
			return p
	if kind == Gem.BOMB:
		var seen := {}
		for r in group.runs:
			for c in r.cells:
				if seen.has(c):
					return c
				seen[c] = true
	var longest: Array = group.runs[0].cells
	for r in group.runs:
		if r.cells.size() > longest.size():
			longest = r.cells
	return longest[longest.size() / 2]


func _hit_crate(c: Vector2i) -> void:
	if not inside(c) or crates[c.x][c.y] <= 0 or _crate_hits.has(c):
		return
	_crate_hits[c] = true
	crates[c.x][c.y] -= 1
	var n: Node2D = crate_nodes.get(c)
	_burst(cell_pos(c), Color("#c98a4b"), 10)
	if crates[c.x][c.y] <= 0:
		crate_nodes.erase(c)
		if n:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(n, "scale", Vector2(1.3, 1.3), 0.15)
			tw.tween_property(n, "modulate:a", 0.0, 0.15)
			tw.chain().tween_callback(n.queue_free)
		crate_broken.emit(to_global(cell_pos(c)))
	elif n:
		n.queue_redraw()
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2(1.12, 0.9), 0.06)
		tw.tween_property(n, "scale", Vector2.ONE, 0.1)


## Убирает клетки; особые фишки в зоне взрыва срабатывают цепочкой.
func _clear(initial: Dictionary, _from_match: bool, _keep: Array = []) -> void:
	var pending: Array = initial.keys()
	var cleared := {}
	var power := 0.0
	var beams: Array = []
	while not pending.is_empty():
		var c: Vector2i = pending.pop_back()
		if cleared.has(c) or not inside(c):
			continue
		if crates[c.x][c.y] > 0:
			_hit_crate(c)
			continue
		var g := gem_at(c)
		if g == null:
			continue
		cleared[c] = true
		if g.special != Gem.NONE:
			var area := _special_area(g, c)
			pending.append_array(area)
			power += 1.0 if g.special != Gem.ORB else 1.5
			beams.append({"cell": c, "kind": g.special, "color": g.color})
	for b in beams:
		_beam_fx(b.cell, b.kind, b.color)
	if power > 0.0:
		big_hit.emit(power)
		await get_tree().create_timer(0.08).timeout
	var last: Tween = null
	for c: Vector2i in cleared:
		var g := gem_at(c)
		tiles[c.x][c.y] = null
		var col: int = g.color
		if col >= 0:
			gem_cleared.emit(col, to_global(cell_pos(c)))
		_burst(cell_pos(c), Gem.COLORS[col] if col >= 0 else Color.WHITE, 6)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(g, "scale", Vector2(1.25, 1.25), 0.07)
		tw.chain().tween_property(g, "scale", Vector2(0.0, 0.0), 0.13)
		tw.tween_property(g, "modulate:a", 0.0, 0.13)
		tw.chain().tween_callback(g.queue_free)
		last = tw
	if last:
		await last.finished


func _special_area(g: Node2D, c: Vector2i) -> Array:
	var out: Array = []
	match g.special:
		Gem.ROCKET_H:
			for x in W:
				out.append(Vector2i(x, c.y))
		Gem.ROCKET_V:
			for y in H:
				out.append(Vector2i(c.x, y))
		Gem.BOMB:
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					out.append(c + Vector2i(dx, dy))
		Gem.ORB:
			var col := _most_common_color()
			for x in W:
				for y in H:
					if color_at(Vector2i(x, y)) == col:
						out.append(Vector2i(x, y))
	return out


func _most_common_color() -> int:
	var counts := {}
	var best := 0
	var best_n := -1
	for x in W:
		for y in H:
			var c := color_at(Vector2i(x, y))
			if c >= 0:
				counts[c] = counts.get(c, 0) + 1
				if counts[c] > best_n:
					best_n = counts[c]
					best = c
	return best


## Комбо двух особых фишек; g2 стоит в клетке at.
func _combo(g1: Node2D, g2: Node2D, at: Vector2i) -> void:
	var k1: int = g1.special
	var k2: int = g2.special
	var area := {}
	if k1 == Gem.ORB and k2 == Gem.ORB:
		big_hit.emit(4.0)
		for x in W:
			for y in H:
				area[Vector2i(x, y)] = true
		g1.set_special(Gem.NONE)
		g2.set_special(Gem.NONE)
		g1.color = -1
		g2.color = -1
		await _clear(area, false)
		return
	if k1 == Gem.ORB or k2 == Gem.ORB:
		var orb := g1 if k1 == Gem.ORB else g2
		var other := g2 if orb == g1 else g1
		var kind: int = other.special
		var col: int = other.color
		orb.set_special(Gem.NONE)
		orb.color = -1
		area[orb.cell] = true
		var targets: Array = []
		for x in W:
			for y in H:
				var g := gem_at(Vector2i(x, y))
				if g and g.special == Gem.NONE and g.color == col:
					targets.append(g)
		for g: Node2D in targets:
			var k := kind
			if kind == Gem.ROCKET_H or kind == Gem.ROCKET_V:
				k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
			g.set_special(k)
			g.scale = Vector2(1.3, 1.3)
			create_tween().tween_property(g, "scale", Vector2.ONE, 0.2)
			area[g.cell] = true
		area[other.cell] = true
		await get_tree().create_timer(0.35).timeout
		await _clear(area, false)
		return
	var rockets := int(k1 == Gem.ROCKET_H or k1 == Gem.ROCKET_V) + int(k2 == Gem.ROCKET_H or k2 == Gem.ROCKET_V)
	var bombs := int(k1 == Gem.BOMB) + int(k2 == Gem.BOMB)
	g1.set_special(Gem.NONE)
	g2.set_special(Gem.NONE)
	area[g1.cell] = true
	area[g2.cell] = true
	if rockets == 2:
		for x in W:
			area[Vector2i(x, at.y)] = true
		for y in H:
			area[Vector2i(at.x, y)] = true
		_beam_fx(at, Gem.ROCKET_H, g2.color)
		_beam_fx(at, Gem.ROCKET_V, g2.color)
		big_hit.emit(2.0)
	elif bombs == 2:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				area[at + Vector2i(dx, dy)] = true
		_beam_fx(at, Gem.BOMB, g2.color, 2.0)
		big_hit.emit(3.0)
	else:
		for d in range(-1, 2):
			for x in W:
				area[Vector2i(x, at.y + d)] = true
			for y in H:
				area[Vector2i(at.x + d, y)] = true
			_beam_fx(at + Vector2i(0, d), Gem.ROCKET_H, g2.color)
			_beam_fx(at + Vector2i(d, 0), Gem.ROCKET_V, g2.color)
		big_hit.emit(3.0)
	await _clear(area, false)


func _orb_with_color(orb: Node2D, col: int) -> void:
	var area := {orb.cell: true}
	orb.set_special(Gem.NONE)
	orb.color = -1
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g != orb and g.color == col:
				area[Vector2i(x, y)] = true
				_zap(cell_pos(orb.cell), cell_pos(Vector2i(x, y)), Gem.COLORS[col])
	big_hit.emit(1.5)
	await get_tree().create_timer(0.25).timeout
	await _clear(area, false)


func _gravity() -> void:
	var spawned: Array[int] = []
	spawned.resize(W)
	spawned.fill(0)
	var moved := {}
	var changed := true
	while changed:
		changed = false
		for y in range(H - 1, -1, -1):
			for x in W:
				var c := Vector2i(x, y)
				if not _open(c) or gem_at(c) != null:
					continue
				if y == 0:
					var g := _new_gem(rng.randi_range(0, colors - 1))
					spawned[x] += 1
					g.position = cell_pos(Vector2i(x, -spawned[x]))
					tiles[x][0] = g
					g.cell = c
					moved[g] = true
					changed = true
					continue
				var up := Vector2i(x, y - 1)
				if _open(up):
					if gem_at(up) != null:
						_move_gem(up, c)
						moved[gem_at(c)] = true
						changed = true
					continue
				for dx in [-1, 1]:
					var src := Vector2i(x + dx, y - 1)
					if _open(src) and gem_at(src) != null:
						var below := src + Vector2i.DOWN
						if not (_open(below) and gem_at(below) == null):
							_move_gem(src, c)
							moved[gem_at(c)] = true
							changed = true
							break
	if moved.is_empty():
		return
	var longest := 0.0
	for g: Node2D in moved:
		var target := cell_pos(g.cell)
		var dist := (target - g.position).length() / CELL
		var t := 0.12 + sqrt(maxf(dist, 0.0)) * 0.09
		longest = maxf(longest, t)
		var tw := create_tween()
		tw.tween_property(g, "position", target, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(g, "scale", Vector2(1.08, 0.9), 0.05)
		tw.tween_property(g, "scale", Vector2.ONE, 0.07)
	await get_tree().create_timer(longest + 0.1).timeout


func _move_gem(from: Vector2i, to: Vector2i) -> void:
	var g: Node2D = tiles[from.x][from.y]
	tiles[from.x][from.y] = null
	tiles[to.x][to.y] = g
	g.cell = to


func _shuffle() -> void:
	var gems: Array = []
	var cells: Array = []
	for x in W:
		for y in H:
			if tiles[x][y]:
				gems.append(tiles[x][y])
				cells.append(Vector2i(x, y))
	for attempt in 100:
		# перекрашиваем обычные фишки случайно, пока не будет ходов и готовых совпадений
		for g: Node2D in gems:
			if g.special == Gem.NONE:
				g.color = rng.randi_range(0, colors - 1)
		if find_groups().is_empty() and not find_move().is_empty():
			break
	var tw := create_tween().set_parallel(true)
	for g: Node2D in gems:
		g.queue_redraw()
		tw.tween_property(g, "scale", Vector2(0.2, 0.2), 0.18)
	await tw.finished
	var tw2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for g: Node2D in gems:
		tw2.tween_property(g, "scale", Vector2.ONE, 0.25)
	await tw2.finished


## Превратить случайные обычные фишки в ракеты (финал уровня за оставшиеся ходы).
func spawn_bonus_rockets(n: int) -> Array:
	var pool: Array = []
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g.special == Gem.NONE:
				pool.append(g)
	pool.shuffle()
	var out: Array = []
	for i in mini(n, pool.size()):
		var g: Node2D = pool[i]
		g.set_special(Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V)
		g.scale = Vector2(1.4, 1.4)
		create_tween().tween_property(g, "scale", Vector2.ONE, 0.2)
		out.append(g.cell)
	return out


func detonate_all_specials() -> void:
	busy = true
	_crate_hits.clear()
	var area := {}
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g.special != Gem.NONE:
				area[Vector2i(x, y)] = true
	if not area.is_empty():
		await _clear(area, false)
		await _gravity()
	await _cascade([])


# ---------- эффекты ----------

func _burst(pos: Vector2, color: Color, amount: int) -> void:
	if fx == null:
		return
	var p := CPUParticles2D.new()
	p.position = fx.to_local(to_global(pos))
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.5
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 600)
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	p.color = color
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	fx.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _beam_fx(cell: Vector2i, kind: int, col: int, scale_k: float = 1.0) -> void:
	if fx == null:
		return
	var color: Color = Gem.COLORS[col] if col >= 0 else Color.WHITE
	var line := Line2D.new()
	line.width = CELL * 0.5
	line.default_color = color.lightened(0.5)
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	var c := cell_pos(cell)
	match kind:
		Gem.ROCKET_H:
			line.points = PackedVector2Array([fx.to_local(to_global(Vector2(0, c.y))), fx.to_local(to_global(Vector2(W * CELL, c.y)))])
		Gem.ROCKET_V:
			line.points = PackedVector2Array([fx.to_local(to_global(Vector2(c.x, 0))), fx.to_local(to_global(Vector2(c.x, H * CELL)))])
		_:
			var ring := Node2D.new()
			ring.position = fx.to_local(to_global(c))
			var rad := CELL * 1.5 * scale_k
			ring.draw.connect(func() -> void:
				ring.draw_circle(Vector2.ZERO, rad, Color(1, 0.95, 0.7, 0.55))
				ring.draw_arc(Vector2.ZERO, rad, 0, TAU, 40, Color(1, 1, 1, 0.9), 6.0, true))
			ring.scale = Vector2(0.3, 0.3)
			fx.add_child(ring)
			var rt := ring.create_tween().set_parallel(true)
			rt.tween_property(ring, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT)
			rt.tween_property(ring, "modulate:a", 0.0, 0.3)
			rt.chain().tween_callback(ring.queue_free)
			_burst(c, color, 24)
			return
	fx.add_child(line)
	var tw := line.create_tween().set_parallel(true)
	tw.tween_property(line, "width", 4.0, 0.3)
	tw.tween_property(line, "modulate:a", 0.0, 0.3)
	tw.chain().tween_callback(line.queue_free)


func _zap(from: Vector2, to: Vector2, color: Color) -> void:
	if fx == null:
		return
	var line := Line2D.new()
	line.width = 6.0
	line.default_color = color.lightened(0.4)
	line.points = PackedVector2Array([fx.to_local(to_global(from)), fx.to_local(to_global(to))])
	fx.add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.35)
	tw.tween_callback(line.queue_free)
