extends Node2D
## Игровое поле «три в ряд»: логика (совпадения, особые фишки, препятствия, падение, перемешивание) и анимации.
##
## Особые фишки:
##   4 в ряд      → ракета (чистит ряд или столбец, по направлению совпадения);
##   квадрат 2×2  → пропеллер (бьёт крестом и улетает к цели уровня);
##   буква L / T  → бомба (3×3);
##   5 в ряд      → радужный шар (свап с фишкой убирает все фишки этого цвета).
## Свап двух особых фишек — комбо. Тап по особой фишке — активировать (тратит ход).
##
## Препятствия:
##   ящик  — ломается совпадением рядом или взрывом;
##   ваза  — ломается только взрывом;
##   цепь  — фишка не двигается; совпадение или взрыв снимает цепь;
##   трава — растёт: совпадение, задевшее траву, покрывает травой все свои клетки;
##   предмет — не взрывается, его надо довести до нижнего ряда.

signal move_made
signal gem_cleared(color: int, global_pos: Vector2)
signal goal_hit(kind: String, global_pos: Vector2)
signal settled
signal big_hit(power: float)
signal combo_made(size: int)

const Gem := preload("res://scripts/gem.gd")
const CELL := 84.0
enum { B_NONE, B_CRATE, B_VASE }

var W := 8
var H := 8
var colors := 5
var tiles: Array = []        # tiles[x][y] -> Gem | null
var block_kind: Array = []   # B_NONE / B_CRATE / B_VASE
var block_hp: Array = []
var chain: Array = []        # прочность цепи на фишке
var grass: Array = []        # bool
var grass_target: Array = [] # bool — клетки, которые надо покрыть травой
var block_nodes := {}        # Vector2i -> Node2D
var goal_colors: Array = []
var busy := false
var input_enabled := true
var rng := RandomNumberGenerator.new()
var fx: Node2D               # слой эффектов (не обрезается рамкой поля)

var _overlay: Node2D         # цепи поверх фишек
var _press_cell := Vector2i(-1, -1)
var _press_pos := Vector2.ZERO
var _selected := Vector2i(-1, -1)
var _dragging := false
var _touch_seen := false
var _idle := 0.0
var _hint_tweens: Array[Tween] = []
var _hits := {}


# ---------- создание поля ----------

func setup(level: Dictionary) -> void:
	colors = level.colors
	rng.seed = level.seed
	goal_colors.clear()
	for g in level.goals:
		if g.kind == "color":
			goal_colors.append(g.color)
	for c in get_children():
		c.queue_free()
	block_nodes.clear()
	tiles = []
	block_kind = []
	block_hp = []
	chain = []
	grass = []
	grass_target = []
	for x in W:
		tiles.append([])
		block_kind.append([])
		block_hp.append([])
		chain.append([])
		grass.append([])
		grass_target.append([])
		for y in H:
			var c := Vector2i(x, y)
			var b: Dictionary = level.blocks.get(c, {})
			tiles[x].append(null)
			block_kind[x].append(int(b.get("kind", B_NONE)))
			block_hp[x].append(int(b.get("hp", 0)))
			chain[x].append(int(level.chains.get(c, 0)))
			grass[x].append(c in level.grass_start)
			grass_target[x].append(c in level.grass_target)
	for c: Vector2i in level.blocks:
		_make_block_node(c)
	_overlay = Node2D.new()
	_overlay.z_index = 3
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_fill_initial(level.get("items", 0))
	queue_redraw()


func _fill_initial(items: int) -> void:
	for attempt in 50:
		for x in W:
			for y in H:
				if tiles[x][y]:
					tiles[x][y].free()
					tiles[x][y] = null
		var item_cols: Array = range(W)
		item_cols.shuffle()
		for i in items:
			var x: int = item_cols[i % W]
			var y := i / W
			if _fillable(Vector2i(x, y)):
				_place(_new_gem(-1, Gem.ITEM), Vector2i(x, y))
		for y in H:
			for x in W:
				if not _fillable(Vector2i(x, y)) or tiles[x][y] != null:
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
	if x >= 1 and y >= 1 and color_at(Vector2i(x - 1, y)) == c and color_at(Vector2i(x, y - 1)) == c and color_at(Vector2i(x - 1, y - 1)) == c:
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


func _make_block_node(cell: Vector2i) -> void:
	var n := Node2D.new()
	n.position = cell_pos(cell)
	n.z_index = 1
	n.draw.connect(_draw_block.bind(n, cell))
	add_child(n)
	block_nodes[cell] = n


func _draw_block(n: Node2D, cell: Vector2i) -> void:
	var hp: int = block_hp[cell.x][cell.y]
	if block_kind[cell.x][cell.y] == B_VASE:
		draw_vase(n, Vector2.ZERO, CELL * 0.44, hp)
	else:
		draw_crate(n, Vector2.ZERO, CELL * 0.46, hp)


static func draw_crate(n: CanvasItem, o: Vector2, s: float, hp: int) -> void:
	var wood := Color("#c98a4b") if hp <= 1 else Color("#9a6337")
	n.draw_rect(Rect2(o + Vector2(-s, -s + 4), Vector2(s, s) * 2), Color(0, 0, 0, 0.25))
	n.draw_rect(Rect2(o - Vector2(s, s), Vector2(s, s) * 2), wood.darkened(0.35))
	var m := s * 0.12
	n.draw_rect(Rect2(o - Vector2(s - m, s - m), Vector2(s - m, s - m) * 2), wood)
	for i in 3:
		var yy := -s + m + (s * 2 - m * 2) * (i + 0.5) / 3.0
		n.draw_line(o + Vector2(-s + m, yy), o + Vector2(s - m, yy), wood.darkened(0.2), 2.0)
	n.draw_line(o + Vector2(-s + m, -s + m), o + Vector2(s - m, s - m), wood.darkened(0.45), s * 0.14)
	if hp >= 2:
		n.draw_line(o + Vector2(s - m, -s + m), o + Vector2(-s + m, s - m), wood.darkened(0.45), s * 0.14)


static func draw_vase(n: CanvasItem, o: Vector2, s: float, hp: int) -> void:
	var col := Color("#4fb3d9") if hp <= 1 else Color("#2f7fb0")
	var body := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		body.append(o + Vector2(cos(a) * s * 0.78, sin(a) * s * 0.7 + s * 0.22))
	n.draw_colored_polygon(body, col.darkened(0.3))
	var inner := PackedVector2Array()
	for v in body:
		inner.append(o + (v - o) * 0.86 + Vector2(0, -s * 0.03))
	n.draw_colored_polygon(inner, col)
	n.draw_rect(Rect2(o + Vector2(-s * 0.32, -s * 0.78), Vector2(s * 0.64, s * 0.45)), col.darkened(0.15))
	n.draw_rect(Rect2(o + Vector2(-s * 0.45, -s * 0.9), Vector2(s * 0.9, s * 0.18)), col.darkened(0.35))
	n.draw_arc(o + Vector2(0, s * 0.22), s * 0.45, PI * 0.15, PI * 0.85, 12, Color(1, 1, 1, 0.55), 3.0)
	n.draw_circle(o + Vector2(-s * 0.35, -s * 0.05), s * 0.1, Color(1, 1, 1, 0.7))
	if hp >= 2:
		n.draw_line(o + Vector2(-s * 0.2, s * 0.0), o + Vector2(s * 0.25, s * 0.5), Color("#ffd23f"), 3.0)


static func draw_chain(n: CanvasItem, o: Vector2, s: float) -> void:
	var col := Color("#b8bcc8")
	for d in [Vector2(1, 1), Vector2(1, -1)]:
		for i in range(-2, 3):
			var p: Vector2 = o + d.normalized() * i * s * 0.36
			n.draw_arc(p, s * 0.16, 0, TAU, 12, col.darkened(0.45), 7.0, true)
			n.draw_arc(p, s * 0.16, 0, TAU, 12, col, 4.0, true)


func _draw_overlay() -> void:
	for x in W:
		for y in H:
			if chain[x][y] > 0:
				draw_chain(_overlay, cell_pos(Vector2i(x, y)), CELL * 0.5)
				if chain[x][y] >= 2:
					_overlay.draw_circle(cell_pos(Vector2i(x, y)), 9, Color("#ffd23f"))


func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * CELL


func board_size() -> Vector2:
	return Vector2(W, H) * CELL


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, board_size())
	for x in W:
		for y in H:
			var rect := Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL))
			var c := Color(1, 1, 1, 0.16) if (x + y) % 2 == 0 else Color(1, 1, 1, 0.08)
			if grass[x][y]:
				c = Color("#5fd35a") if (x + y) % 2 == 0 else Color("#4cc24c")
			elif grass_target[x][y]:
				c = Color("#a8794a", 0.75) if (x + y) % 2 == 0 else Color("#97693e", 0.75)
			draw_rect(rect, c)
			if grass[x][y]:
				for k in 3:
					var bx := rect.position.x + 14 + k * 26
					var by := rect.position.y + rect.size.y - 6
					draw_line(Vector2(bx, by), Vector2(bx - 4, by - 14), Color("#3a9a3a"), 3.0)
					draw_line(Vector2(bx + 4, by), Vector2(bx + 8, by - 12), Color("#3a9a3a"), 3.0)
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
	if g == null or g.special == Gem.ORB or g.special == Gem.ITEM:
		return -1
	return g.color


## Клетка, куда может встать фишка (нет ящика/вазы).
func _fillable(c: Vector2i) -> bool:
	return inside(c) and block_kind[c.x][c.y] == B_NONE


func _chained(c: Vector2i) -> bool:
	return inside(c) and chain[c.x][c.y] > 0


func _movable(c: Vector2i) -> bool:
	return gem_at(c) != null and not _chained(c)


## Группы совпадений: [{cells, runs: [{cells, dir}], square: bool}]
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
	var parent: Array = range(runs.size())
	var owner_of := {}
	for i in runs.size():
		for cell in runs[i].cells:
			if owner_of.has(cell):
				parent[_find(parent, i)] = _find(parent, owner_of[cell])
			else:
				owner_of[cell] = i
	var by_root := {}
	for i in runs.size():
		var root := _find(parent, i)
		if not by_root.has(root):
			by_root[root] = {"cells": [], "runs": [], "square": false}
		by_root[root].runs.append(runs[i])
		for cell in runs[i].cells:
			if cell not in by_root[root].cells:
				by_root[root].cells.append(cell)
	var groups: Array = by_root.values()
	# квадраты 2×2 → пропеллер
	var cell_group := {}
	for g in groups:
		for c in g.cells:
			cell_group[c] = g
	for x in W - 1:
		for y in H - 1:
			var c := color_at(Vector2i(x, y))
			if c < 0:
				continue
			var sq := [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x, y + 1), Vector2i(x + 1, y + 1)]
			var same := true
			for s in sq:
				if color_at(s) != c:
					same = false
			if not same:
				continue
			var touched: Array = []
			for s in sq:
				if cell_group.has(s) and cell_group[s] not in touched:
					touched.append(cell_group[s])
			if touched.is_empty():
				var ng := {"cells": sq.duplicate(), "runs": [], "square": true}
				groups.append(ng)
				for s in sq:
					cell_group[s] = ng
			elif touched.size() == 1 and not touched[0].square and _special_for(touched[0]) == Gem.NONE:
				var g: Dictionary = touched[0]
				g.square = true
				for s in sq:
					if s not in g.cells:
						g.cells.append(s)
					cell_group[s] = g
	return groups


func _find(parent: Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


func _has_match_at(c: Vector2i) -> bool:
	var col := color_at(c)
	if col < 0:
		return false
	for dir in [[Vector2i.LEFT, Vector2i.RIGHT], [Vector2i.UP, Vector2i.DOWN]]:
		var n := 1
		for d: Vector2i in dir:
			var p := c + d
			while color_at(p) == col:
				n += 1
				p += d
		if n >= 3:
			return true
	for dx in [-1, 0]:
		for dy in [-1, 0]:
			var o := c + Vector2i(dx, dy)
			if color_at(o) == col and color_at(o + Vector2i(1, 0)) == col and color_at(o + Vector2i(0, 1)) == col and color_at(o + Vector2i(1, 1)) == col:
				return true
	return false


## Все возможные ходы: [a, b] — свап, [a, a] — тап по особой фишке.
func all_moves(first_only: bool = false) -> Array:
	var out: Array = []
	for x in W:
		for y in H:
			var a := Vector2i(x, y)
			if not _movable(a):
				continue
			if gem_at(a).is_power():
				out.append([a, a])
				if first_only:
					return out
			for d in [Vector2i.RIGHT, Vector2i.DOWN]:
				var b: Vector2i = a + d
				if not _movable(b):
					continue
				_swap_data(a, b)
				var ok := _has_match_at(a) or _has_match_at(b)
				_swap_data(a, b)
				if ok:
					out.append([a, b])
					if first_only:
						return out
	return out


func find_move() -> Array:
	var m := all_moves(true)
	return m[0] if not m.is_empty() else []


func _swap_data(a: Vector2i, b: Vector2i) -> void:
	var t = tiles[a.x][a.y]
	tiles[a.x][a.y] = tiles[b.x][b.y]
	tiles[b.x][b.y] = t
	if tiles[a.x][a.y]:
		tiles[a.x][a.y].cell = a
	if tiles[b.x][b.y]:
		tiles[b.x][b.y].cell = b


# ---------- ввод ----------

## Пальцем (ScreenTouch/Drag) и мышью. Если пришло касание, мышиные события (эмуляция) игнорируем.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_seen = true
		if event.index == 0:
			_pointer(event.position, event.pressed, false)
	elif event is InputEventScreenDrag:
		if event.index == 0:
			_pointer(event.position, true, true)
	elif _touch_seen:
		return
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer(event.position, event.pressed, false)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_pointer(event.position, true, true)


func _pointer(screen_pos: Vector2, pressed: bool, motion: bool) -> void:
	if not input_enabled or busy:
		_dragging = false
		return
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_pos
	var cell := Vector2i(floori(local.x / CELL), floori(local.y / CELL))
	if motion:
		if not _dragging:
			return
		var d := local - _press_pos
		if d.length() > CELL * 0.35:
			_dragging = false
			var dir := Vector2i(signi(roundi(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, signi(roundi(d.y)))
			_selected = Vector2i(-1, -1)
			_unselect_all()
			try_swap(_press_cell, _press_cell + dir)
		return
	if pressed:
		_stop_hint()
		if not inside(cell):
			return
		_press_cell = cell
		_press_pos = local
		_dragging = true
	elif _dragging:
		_dragging = false
		if cell == _press_cell:
			_on_tap(cell)


func _on_tap(cell: Vector2i) -> void:
	var g := gem_at(cell)
	if _selected != Vector2i(-1, -1):
		var prev := _selected
		_selected = Vector2i(-1, -1)
		_unselect_all()
		if absi(prev.x - cell.x) + absi(prev.y - cell.y) == 1:
			try_swap(prev, cell)
			return
	if g == null or _chained(cell):
		return
	if g.is_power():
		activate_single(cell)
		return
	_selected = cell
	create_tween().tween_property(g, "scale", Vector2(1.15, 1.15), 0.1)


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
		if m[0] == m[1]:
			break


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
	if busy or not _movable(a) or not _movable(b):
		return
	var ga := gem_at(a)
	var gb := gem_at(b)
	_stop_hint()
	busy = true
	_idle = 0.0
	_hits.clear()
	await _animate_swap(ga, gb, a, b)
	_swap_data(a, b)
	# теперь ga стоит в b, gb — в a
	var pa: bool = ga.is_power()
	var pb: bool = gb.is_power()
	if pa and pb:
		move_made.emit()
		await _combo(ga, gb, b)
		await _cascade([])
		return
	if ga.special == Gem.ORB or gb.special == Gem.ORB:
		var orb := ga if ga.special == Gem.ORB else gb
		var other := gb if orb == ga else ga
		if other.special != Gem.ITEM:
			move_made.emit()
			await _orb_with_color(orb, other.color)
			await _cascade([])
			return
	if find_groups().is_empty():
		if pa or pb:
			move_made.emit()
			var sp := ga if pa else gb
			await _clear({sp.cell: true})
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
	if busy or g == null or not g.is_power() or _chained(cell):
		return
	_stop_hint()
	busy = true
	_hits.clear()
	move_made.emit()
	await _clear({cell: true})
	await _cascade([])


func _animate_swap(ga: Node2D, gb: Node2D, a: Vector2i, b: Vector2i) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ga, "position", cell_pos(b), 0.16)
	tw.tween_property(gb, "position", cell_pos(a), 0.16)
	ga.z_index = 2
	await tw.finished
	ga.z_index = 0


func _cascade(prefer: Array) -> void:
	var wave := 0
	while true:
		if await _collect_items():
			await _gravity()
			continue
		var groups := find_groups()
		if groups.is_empty():
			break
		wave += 1
		var to_clear := {}
		var creations: Array = []
		var grassify := {}
		_hits.clear()
		for g in groups:
			var on_grass := false
			for c in g.cells:
				to_clear[c] = true
				if grass[c.x][c.y]:
					on_grass = true
			if on_grass:
				for c in g.cells:
					grassify[c] = true
			var kind := _special_for(g)
			if kind != Gem.NONE:
				var at := _creation_cell(g, prefer, kind)
				creations.append({"cell": at, "kind": kind, "color": color_at(at)})
		# ящики рядом с совпадениями получают удар
		for c: Vector2i in to_clear:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if inside(n) and block_kind[n.x][n.y] == B_CRATE:
					_hit_block(n)
		if wave >= 2:
			combo_made.emit(wave)
		await _clear(to_clear, grassify)
		for cr in creations:
			var cell: Vector2i = cr.cell
			if gem_at(cell) == null and _fillable(cell):
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
	if group.get("square", false):
		return Gem.PROPELLER
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
	if group.runs.is_empty():
		return group.cells[0]
	var longest: Array = group.runs[0].cells
	for r in group.runs:
		if r.cells.size() > longest.size():
			longest = r.cells
	return longest[longest.size() / 2]


func _hit_block(c: Vector2i) -> void:
	if not inside(c) or block_kind[c.x][c.y] == B_NONE or _hits.has(c):
		return
	_hits[c] = true
	var kind: int = block_kind[c.x][c.y]
	block_hp[c.x][c.y] -= 1
	var n: Node2D = block_nodes.get(c)
	_burst(cell_pos(c), Color("#c98a4b") if kind == B_CRATE else Color("#4fb3d9"), 10)
	if block_hp[c.x][c.y] <= 0:
		block_kind[c.x][c.y] = B_NONE
		block_nodes.erase(c)
		if n:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(n, "scale", Vector2(1.3, 1.3), 0.15)
			tw.tween_property(n, "modulate:a", 0.0, 0.15)
			tw.chain().tween_callback(n.queue_free)
		goal_hit.emit("crate" if kind == B_CRATE else "vase", to_global(cell_pos(c)))
	elif n:
		n.queue_redraw()
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2(1.12, 0.9), 0.06)
		tw.tween_property(n, "scale", Vector2.ONE, 0.1)


func _break_chain(c: Vector2i) -> void:
	if _hits.has(c):
		return
	_hits[c] = true
	chain[c.x][c.y] -= 1
	_overlay.queue_redraw()
	_burst(cell_pos(c), Color("#b8bcc8"), 10)
	if chain[c.x][c.y] <= 0:
		goal_hit.emit("chain", to_global(cell_pos(c)))


func _grow_grass(cells: Dictionary) -> void:
	var changed := false
	for c: Vector2i in cells:
		if inside(c) and not grass[c.x][c.y] and block_kind[c.x][c.y] == B_NONE:
			grass[c.x][c.y] = true
			changed = true
			if grass_target[c.x][c.y]:
				goal_hit.emit("grass", to_global(cell_pos(c)))
	if changed:
		queue_redraw()


## Убирает клетки; особые фишки в зоне взрыва срабатывают цепочкой.
## grassify — клетки, которые после очистки покрываются травой.
func _clear(initial: Dictionary, grassify: Dictionary = {}) -> void:
	var pending: Array = initial.keys()
	var cleared := {}
	var power := 0.0
	var effects: Array = []
	var flights: Array = []
	while not pending.is_empty():
		var c: Vector2i = pending.pop_back()
		if cleared.has(c) or not inside(c):
			continue
		if block_kind[c.x][c.y] != B_NONE:
			_hit_block(c)
			continue
		var g := gem_at(c)
		if g == null or g.special == Gem.ITEM:
			continue
		if _chained(c):
			_break_chain(c)
			continue
		cleared[c] = true
		if g.is_power():
			var area := _area(g.special, c)
			if g.special == Gem.PROPELLER:
				var target := _pick_target(cleared, area)
				if target != Vector2i(-1, -1):
					area.append(target)
					flights.append({"from": c, "to": target, "color": g.color})
			pending.append_array(area)
			if grass[c.x][c.y]:
				for a in area:
					grassify[a] = true
			power += 1.5 if g.special == Gem.ORB else 1.0
			effects.append({"cell": c, "kind": g.special, "color": g.color})
	for e in effects:
		if e.kind != Gem.PROPELLER:
			_beam_fx(e.cell, e.kind, e.color)
	for f in flights:
		_propeller_fx(f.from, f.to, f.color)
	if power > 0.0:
		big_hit.emit(power)
		await get_tree().create_timer(0.38 if not flights.is_empty() else 0.08).timeout
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
	_grow_grass(grassify)
	if last:
		await last.finished


func _area(kind: int, c: Vector2i) -> Array:
	var out: Array = []
	match kind:
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
		Gem.PROPELLER:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				out.append(c + d)
		Gem.ORB:
			var col := _most_common_color()
			for x in W:
				for y in H:
					if color_at(Vector2i(x, y)) == col:
						out.append(Vector2i(x, y))
	return out


## Куда летит пропеллер: сначала препятствия-цели, потом трава, потом нужные цвета.
func _pick_target(exclude: Dictionary, also: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			if exclude.has(c) or c in also:
				continue
			var g := gem_at(c)
			var score := 0.0
			if block_kind[x][y] != B_NONE:
				score = 50.0
			elif _chained(c):
				score = 40.0
			elif grass_target[x][y] and not grass[x][y]:
				score = 30.0
			elif g and g.color in goal_colors:
				score = 10.0
			elif g and g.special != Gem.ITEM:
				score = 1.0
			else:
				continue
			score += rng.randf() * 5.0
			if score > best_score:
				best_score = score
				best = c
	return best


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
		for g in [g1, g2]:
			g.set_special(Gem.NONE)
			g.color = -1
		await _clear(area)
		return
	if k1 == Gem.ORB or k2 == Gem.ORB:
		var orb := g1 if k1 == Gem.ORB else g2
		var other := g2 if orb == g1 else g1
		var kind: int = other.special
		var col: int = other.color
		orb.set_special(Gem.NONE)
		orb.color = -1
		area[orb.cell] = true
		for x in W:
			for y in H:
				var g := gem_at(Vector2i(x, y))
				if g and g.special == Gem.NONE and g.color == col and not _chained(g.cell):
					var k := kind
					if kind == Gem.ROCKET_H or kind == Gem.ROCKET_V:
						k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
					g.set_special(k)
					g.scale = Vector2(1.3, 1.3)
					create_tween().tween_property(g, "scale", Vector2.ONE, 0.2)
					area[g.cell] = true
		area[other.cell] = true
		await get_tree().create_timer(0.35).timeout
		await _clear(area)
		return
	var kinds := [k1, k2]
	var rockets := kinds.count(Gem.ROCKET_H) + kinds.count(Gem.ROCKET_V)
	var bombs := kinds.count(Gem.BOMB)
	var props := kinds.count(Gem.PROPELLER)
	var col: int = g2.color
	g1.set_special(Gem.NONE)
	g2.set_special(Gem.NONE)
	area[g1.cell] = true
	area[g2.cell] = true
	if props >= 1:
		# пропеллер уносит вторую фишку к цели и взрывает её там
		var carried: int = k1 if k2 == Gem.PROPELLER else k2
		var count := 3 if props == 2 else 1
		var targets: Array = []
		var used := {at: true}
		for i in count:
			var target := _pick_target(used, [])
			if target == Vector2i(-1, -1):
				break
			used[target] = true
			targets.append(target)
			_propeller_fx(at, target, col)
			area[target] = true
			if carried == Gem.PROPELLER:
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					area[target + d] = true
			else:
				var k := carried
				if k == Gem.ROCKET_H or k == Gem.ROCKET_V:
					k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
				for a in _area(k, target):
					area[a] = true
		await get_tree().create_timer(0.4).timeout
		if carried != Gem.PROPELLER:
			for t in targets:
				_beam_fx(t, carried, col)
		big_hit.emit(2.0)
	elif rockets == 2:
		for x in W:
			area[Vector2i(x, at.y)] = true
		for y in H:
			area[Vector2i(at.x, y)] = true
		_beam_fx(at, Gem.ROCKET_H, col)
		_beam_fx(at, Gem.ROCKET_V, col)
		big_hit.emit(2.0)
	elif bombs == 2:
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				area[at + Vector2i(dx, dy)] = true
		_beam_fx(at, Gem.BOMB, col, 2.0)
		big_hit.emit(3.0)
	else:
		for d in range(-1, 2):
			for x in W:
				area[Vector2i(x, at.y + d)] = true
			for y in H:
				area[Vector2i(at.x + d, y)] = true
			_beam_fx(at + Vector2i(0, d), Gem.ROCKET_H, col)
			_beam_fx(at + Vector2i(d, 0), Gem.ROCKET_V, col)
		big_hit.emit(3.0)
	await _clear(area)


func _orb_with_color(orb: Node2D, col: int) -> void:
	var area := {orb.cell: true}
	orb.set_special(Gem.NONE)
	orb.color = -1
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g != orb and g.color == col and g.special != Gem.ITEM:
				area[Vector2i(x, y)] = true
				_zap(cell_pos(orb.cell), cell_pos(Vector2i(x, y)), Gem.COLORS[col])
	big_hit.emit(1.5)
	await get_tree().create_timer(0.25).timeout
	await _clear(area)


## Предметы на нижней доступной клетке столбца уходят с поля. true — если что-то собрано.
func _collect_items() -> bool:
	var got := false
	for x in W:
		var bottom := -1
		for y in range(H - 1, -1, -1):
			if _fillable(Vector2i(x, y)):
				bottom = y
				break
		if bottom < 0:
			continue
		var c := Vector2i(x, bottom)
		var g := gem_at(c)
		if g and g.special == Gem.ITEM:
			tiles[x][bottom] = null
			got = true
			goal_hit.emit("item", to_global(cell_pos(c)))
			_burst(cell_pos(c), Color("#ffd23f"), 16)
			var tw := create_tween().set_parallel(true)
			tw.tween_property(g, "position:y", g.position.y + CELL * 0.6, 0.25)
			tw.tween_property(g, "modulate:a", 0.0, 0.25)
			tw.chain().tween_callback(g.queue_free)
	if got:
		await get_tree().create_timer(0.25).timeout
	return got


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
				if not _fillable(c) or gem_at(c) != null:
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
				if _fillable(up) and not _chained(up):
					if gem_at(up) != null:
						_move_gem(up, c)
						moved[gem_at(c)] = true
						changed = true
					continue
				for dx in [-1, 1]:
					var src := Vector2i(x + dx, y - 1)
					if _fillable(src) and _movable(src):
						var below := src + Vector2i.DOWN
						if not (_fillable(below) and gem_at(below) == null):
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
	for x in W:
		for y in H:
			if tiles[x][y]:
				gems.append(tiles[x][y])
	for attempt in 100:
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


## Превратить случайные обычные фишки в особые (финал уровня).
func spawn_specials(n: int, kind: int) -> Array:
	var pool: Array = []
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g.special == Gem.NONE and not _chained(g.cell):
				pool.append(g)
	pool.shuffle()
	var out: Array = []
	for i in mini(n, pool.size()):
		var g: Node2D = pool[i]
		var k := kind
		if k == Gem.ROCKET_H:
			k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
		g.set_special(k)
		g.scale = Vector2(1.4, 1.4)
		create_tween().tween_property(g, "scale", Vector2.ONE, 0.2)
		out.append(g.cell)
	return out


func spawn_bonus_rockets(n: int) -> Array:
	return spawn_specials(n, Gem.ROCKET_H)


func detonate_all_specials() -> void:
	busy = true
	_hits.clear()
	var area := {}
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g.is_power() and not _chained(g.cell):
				area[Vector2i(x, y)] = true
	if not area.is_empty():
		await _clear(area)
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


func _propeller_fx(from: Vector2i, to: Vector2i, col: int) -> void:
	if fx == null:
		return
	var p: Node2D = Gem.new()
	p.color = col
	p.size = CELL
	fx.add_child(p)
	p.set_special(Gem.PROPELLER)
	var a := fx.to_local(to_global(cell_pos(from)))
	var b := fx.to_local(to_global(cell_pos(to)))
	p.position = a
	var mid := (a + b) / 2 + Vector2(0, -CELL * 1.5)
	var tw := p.create_tween()
	tw.tween_method(func(t: float) -> void:
		p.position = a.lerp(mid, t).lerp(mid.lerp(b, t), t), 0.0, 1.0, 0.36)
	tw.parallel().tween_property(p, "scale", Vector2(1.3, 1.3), 0.18)
	tw.tween_callback(func() -> void: _burst(cell_pos(to), Color("#ffe14d"), 14))
	tw.tween_property(p, "modulate:a", 0.0, 0.1)
	tw.tween_callback(p.queue_free)


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
