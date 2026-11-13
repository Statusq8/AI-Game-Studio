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
signal shake(amount: float)
signal idle_hint
signal special_fired

const Gem := preload("res://scripts/gem.gd")
const CELL := 84.0
const PROPELLER_TIME := 1.5  # полёт бабочки к цели
const PROPELLER_DELAY := 0.25  # сначала взрываются соседи, потом бабочка взлетает
const ROCKET_CELL_TIME := 0.045  # ракета пролетает клетку за столько секунд
enum { B_NONE, B_CRATE, B_VASE, B_SAFE, B_JAR, B_CAGE, B_BALLOON, B_FLOWER, B_BUSH, B_SHELL }
## Препятствия-блоки: цель уровня, бьёт ли совпадение рядом, картинки по стадиям поломки.
const BLOCKS := {
	B_CRATE: {"goal": "crate", "adj": true, "tex": ["ob_crate_0", "ob_crate_1", "ob_crate_2"], "fx": Color("#c98a4b")},
	B_VASE: {"goal": "vase", "adj": false, "tex": ["ob_pot_0", "ob_pot_1"], "fx": Color("#e0663a")},
	B_SAFE: {"goal": "safe", "adj": true, "tex": ["ob_safe"], "fx": Color("#8a96b0")},
	B_JAR: {"goal": "jar", "adj": true, "tex": ["ob_jar"], "fx": Color("#ffd23f")},
	B_CAGE: {"goal": "cage", "adj": true, "tex": ["ob_cage"], "fx": Color("#ffcf5a")},
	B_BALLOON: {"goal": "balloon", "adj": true, "tex": ["ob_balloon"], "fx": Color("#ff3b3b")},
	B_FLOWER: {"goal": "flower", "adj": true, "tex": ["ob_flower_0", "ob_flower_1"], "fx": Color("#ff6bb0")},
	B_BUSH: {"goal": "bush", "adj": true, "tex": ["ob_bush"], "fx": Color("#4cc81e")},
	B_SHELL: {"goal": "shell", "adj": true, "tex": ["ob_shell_0", "ob_shell_1"], "fx": Color("#ff6bb0")},
}

var W := 8
var H := 10
var colors := 5
var tiles: Array = []        # tiles[x][y] -> Gem | null
var block_kind: Array = []   # B_NONE / B_CRATE / B_VASE
var block_hp: Array = []
var block_max: Array = []
var ice: Array = []          # слой льда под фишкой
var hole: Array = []         # дыра в фигурном поле (клетки нет)
var honey: Array = []        # мёд на фишке (растекается)
var _honey_hit := false
var _player_move := false
var _grass_carry := false  # ход сделан с травы — всё, что убьёт этот бустер/комбо, тоже покрывается травой
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
var target_cb: Callable    # режим прицеливания бустером: следующий тап по клетке вызывает его


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
	block_max = []
	ice = []
	hole = []
	honey = []
	chain = []
	grass = []
	grass_target = []
	for x in W:
		tiles.append([])
		block_kind.append([])
		block_hp.append([])
		block_max.append([])
		ice.append([])
		hole.append([])
		honey.append([])
		chain.append([])
		grass.append([])
		grass_target.append([])
		for y in H:
			var c := Vector2i(x, y)
			var b: Dictionary = level.blocks.get(c, {})
			tiles[x].append(null)
			block_kind[x].append(int(b.get("kind", B_NONE)))
			block_hp[x].append(int(b.get("hp", 0)))
			block_max[x].append(int(b.get("hp", 0)))
			ice[x].append(int(level.get("ice", {}).get(c, 0)))
			hole[x].append(c in level.get("holes", []))
			honey[x].append(c in level.get("honey", []))
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
		var placed := 0
		for y in H:
			for x in item_cols:
				if placed >= items:
					break
				if _fillable(Vector2i(x, y)) and tiles[x][y] == null:
					_place(_new_gem(-1, Gem.ITEM), Vector2i(x, y))
					placed += 1
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
	var kind: int = block_kind[cell.x][cell.y]
	var t := block_tex(kind, block_max[cell.x][cell.y] - hp)
	if t:
		var sz := t.get_size()
		var k := CELL * 1.06 / maxf(sz.x, sz.y)
		n.draw_set_transform(Vector2(0, 0), 0.0, Vector2(k, k))
		n.draw_texture(t, -sz / 2)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if hp >= 2 and BLOCKS[kind].tex.size() == 1:
			# прочность цифрой, если у картинки нет стадий
			var f: Font = ThemeDB.fallback_font
			n.draw_circle(Vector2(CELL * 0.3, CELL * 0.3), 13, Color("#2b2350"))
			n.draw_string(f, Vector2(CELL * 0.3 - 6, CELL * 0.3 + 7), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
		return
	if kind == B_VASE:
		draw_vase(n, Vector2.ZERO, CELL * 0.44, hp)
	else:
		draw_crate(n, Vector2.ZERO, CELL * 0.46, hp)


static func block_tex(kind: int, stage: int) -> Texture2D:
	if not BLOCKS.has(kind):
		return null
	var names: Array = BLOCKS[kind].tex
	return Gem.tex(names[clampi(stage, 0, names.size() - 1)])


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
	var vt := Gem.tex("ob_vines")
	var ht := Gem.tex("ob_honey")
	var itx := Gem.tex("ob_tile_ice")
	for x in W:
		for y in H:
			var cp := cell_pos(Vector2i(x, y))
			if ice[x][y] > 0 and itx:
				var r := Rect2(cp - Vector2(CELL, CELL) * 0.47, Vector2(CELL, CELL) * 0.94)
				_overlay.draw_texture_rect(itx, r, false, Color(1, 1, 1, 0.42 if ice[x][y] == 1 else 0.62))
				var frost := StyleBoxFlat.new()
				frost.bg_color = Color(0, 0, 0, 0)
				frost.set_corner_radius_all(14)
				frost.set_border_width_all(4)
				frost.border_color = Color(0.85, 0.97, 1.0, 0.95)
				_overlay.draw_style_box(frost, r)
			if honey[x][y] and ht:
				var hs := ht.get_size()
				var hk := CELL * 0.98 / maxf(hs.x, hs.y)
				_overlay.draw_set_transform(cp, 0.0, Vector2(hk, hk))
				_overlay.draw_texture(ht, -hs / 2, Color(1, 1, 1, 0.82))
				_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if chain[x][y] > 0 and vt:
				var vs := vt.get_size()
				var vk := CELL * 0.95 / maxf(vs.x, vs.y)
				_overlay.draw_set_transform(cp, 0.0, Vector2(vk, vk))
				_overlay.draw_texture(vt, -vs / 2)
				_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				if chain[x][y] >= 2:
					_overlay.draw_circle(cp + Vector2(CELL * 0.3, CELL * 0.3), 11, Color("#2e7d32"))
				continue
			if chain[x][y] > 0:
				draw_chain(_overlay, cell_pos(Vector2i(x, y)), CELL * 0.5)
				if chain[x][y] >= 2:
					_overlay.draw_circle(cell_pos(Vector2i(x, y)), 9, Color("#ffd23f"))


func cell_pos(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + 0.5, cell.y + 0.5) * CELL


func board_size() -> Vector2:
	return Vector2(W, H) * CELL


func _tile_box(col: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(14)
	sb.border_width_bottom = 4
	sb.border_color = col.darkened(0.18)
	return sb


## Поле: объёмные плитки — тёмный обод, светлая середина с градиентом, блик сверху, тень снизу.
func _draw() -> void:
	var r := Rect2(Vector2.ZERO, board_size())
	var gap := 2.5
	for x in W:
		for y in H:
			if not hole[x][y]:
				draw_rect(Rect2(Vector2(x, y) * CELL - Vector2(1, 1), Vector2(CELL, CELL) + Vector2(2, 2)), Color("#123247", 0.6))
	for x in W:
		for y in H:
			if hole[x][y]:
				continue
			var rect := Rect2(Vector2(x, y) * CELL + Vector2(gap, gap), Vector2(CELL, CELL) - Vector2(gap, gap) * 2)
			var even := (x + y) % 2 == 0
			var top := Color("#e6f3fa") if even else Color("#d3e7f2")
			var bottom := Color("#b7d3e2") if even else Color("#a6c6d8")
			if grass[x][y]:
				top = Color("#8be36e") if even else Color("#7ad85e")
				bottom = Color("#4fb33c") if even else Color("#43a533")
			elif grass_target[x][y]:
				top = Color("#a07850") if even else Color("#96704a")
				bottom = Color("#6e4e30") if even else Color("#654729")
			var rim := StyleBoxFlat.new()
			rim.bg_color = bottom.darkened(0.25)
			rim.set_corner_radius_all(15)
			draw_style_box(rim, rect)
			var body := StyleBoxFlat.new()
			body.bg_color = bottom
			body.set_corner_radius_all(13)
			draw_style_box(body, rect.grow(-2.0))
			var face := StyleBoxFlat.new()
			face.bg_color = top
			face.set_corner_radius_all(12)
			draw_style_box(face, Rect2(rect.position + Vector2(3, 3), rect.size - Vector2(6, 11)))
			draw_rect(Rect2(rect.position + Vector2(12, 6), Vector2(rect.size.x - 24, 4)), Color(1, 1, 1, 0.55))
			var gt := Gem.tex("ob_tile_grass") if grass[x][y] else null
			if gt:
				draw_texture_rect(gt, rect.grow(1.0), false)
			if ice[x][y] > 0:
				var it := Gem.tex("ob_tile_ice")
				if it:
					draw_texture_rect(it, rect.grow(2.0), false, Color(1, 1, 1, 1.0))
			if grass[x][y] and gt == null:
				for k in 3:
					var bx := rect.position.x + 14 + k * 22
					var by := rect.position.y + rect.size.y - 10
					draw_line(Vector2(bx, by), Vector2(bx - 4, by - 12), Color("#2f8f2f"), 3.0)
					draw_line(Vector2(bx + 4, by), Vector2(bx + 8, by - 10), Color("#2f8f2f"), 3.0)


# ---------- запросы к полю ----------

func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


func gem_at(c: Vector2i) -> Node2D:
	if not inside(c):
		return null
	return tiles[c.x][c.y]


func color_at(c: Vector2i) -> int:
	var g := gem_at(c)
	if g == null or g.special != Gem.NONE:
		return -1
	return g.color


## Клетка, куда может встать фишка (нет ящика/вазы).
func _fillable(c: Vector2i) -> bool:
	return inside(c) and block_kind[c.x][c.y] == B_NONE and not hole[c.x][c.y]


## Над клеткой только дыры (или край) — сюда падают новые фишки.
func _spawn_cell(c: Vector2i) -> bool:
	for y in range(c.y - 1, -1, -1):
		if not hole[c.x][y]:
			return false
	return true


## Фишка не двигается: на ней лианы или мёд.
func _chained(c: Vector2i) -> bool:
	return inside(c) and (chain[c.x][c.y] > 0 or honey[c.x][c.y])


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
		if target_cb.is_valid():
			var cb := target_cb
			target_cb = Callable()
			cb.call(cell)
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
		idle_hint.emit()


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
	_player_move = true
	_grass_carry = grass[a.x][a.y] or grass[b.x][b.y]
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
	if pa or pb:
		# особая фишка, сдвинутая свапом, всегда срабатывает
		move_made.emit()
		var sp := ga if pa else gb
		await _clear({sp.cell: true})
		await _cascade([])
		return
	if find_groups().is_empty():
		await _animate_swap(ga, gb, b, a)
		_swap_data(a, b)
		var tw := create_tween()
		for k in 3:
			tw.tween_property(ga, "position:x", cell_pos(a).x + 7.0, 0.04)
			tw.tween_property(ga, "position:x", cell_pos(a).x - 7.0, 0.04)
		tw.tween_property(ga, "position:x", cell_pos(a).x, 0.04)
		Save.vibrate(25)
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
	_grass_carry = grass[cell.x][cell.y]
	move_made.emit()
	await _clear({cell: true})
	await _cascade([])


## Бустеры на уровне (ход не тратят): "hammer" — клетка, "arrow" — ряд, "cannon" — столбец.
func booster_hit(kind: String, cell: Vector2i) -> void:
	if busy or not inside(cell):
		return
	_stop_hint()
	busy = true
	_hits.clear()
	var area := {}
	match kind:
		"hammer":
			area[cell] = true
			_beam_fx(cell, Gem.BOMB, -1, 0.45)
		"arrow":
			for x in W:
				area[Vector2i(x, cell.y)] = true
			_beam_fx(cell, Gem.ROCKET_H, -1)
		"cannon":
			for y in H:
				area[Vector2i(cell.x, y)] = true
			_beam_fx(cell, Gem.ROCKET_V, -1)
	big_hit.emit(1.5)
	await _clear(area)
	await _cascade([])


func shuffle_now() -> void:
	if busy:
		return
	_stop_hint()
	busy = true
	await _shuffle()
	await _cascade([])


func _animate_swap(ga: Node2D, gb: Node2D, a: Vector2i, b: Vector2i) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(ga, "position", cell_pos(b), 0.16)
	tw.tween_property(gb, "position", cell_pos(a), 0.16)
	var horiz := a.y == b.y
	var squash := Vector2(1.18, 0.85) if horiz else Vector2(0.85, 1.18)
	for g in [ga, gb]:
		var st := create_tween()
		st.tween_property(g, "scale", squash, 0.08)
		st.tween_property(g, "scale", Vector2.ONE, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ga.z_index = 2
	await tw.finished
	ga.z_index = 0


func _cascade(prefer: Array) -> void:
	var wave := 0
	_grass_carry = false
	# после взрыва особой фишки дырки надо заполнить, даже если новых совпадений нет
	await _gravity()
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
				if inside(n) and block_kind[n.x][n.y] != B_NONE and BLOCKS[block_kind[n.x][n.y]].adj:
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
	if _player_move:
		_player_move = false
		if not _honey_hit:
			_spread_honey()
	_honey_hit = false
	if find_move().is_empty():
		await _shuffle()
	busy = false
	settled.emit()


## Мёд растекается на соседнюю фишку, если за ход его ни разу не задели.
func _spread_honey() -> void:
	var cand: Array = []
	for x in W:
		for y in H:
			if not honey[x][y]:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = Vector2i(x, y) + d
				var g := gem_at(n)
				if g and g.special == Gem.NONE and not _chained(n):
					cand.append(n)
	if cand.is_empty():
		return
	var c: Vector2i = cand[rng.randi_range(0, cand.size() - 1)]
	honey[c.x][c.y] = true
	goal_hit.emit("honey_more", to_global(cell_pos(c)))
	_overlay.queue_redraw()


## Пустые клетки, куда должна была упасть фишка (для проверок ботом).
func holes() -> int:
	var n := 0
	for x in W:
		for y in H:
			var bg := gem_at(Vector2i(x, y))
			if bg and bg.special == Gem.NONE and bg.color < 0:
				push_error("BADGEM at %s" % Vector2i(x, y))
			if _fillable(Vector2i(x, y)) and gem_at(Vector2i(x, y)) == null:
				n += 1
	return n


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
	_burst(cell_pos(c), BLOCKS[kind].fx if BLOCKS.has(kind) else Color.WHITE, 12)
	if block_hp[c.x][c.y] <= 0:
		block_kind[c.x][c.y] = B_NONE
		block_nodes.erase(c)
		if n:
			var tw := create_tween().set_parallel(true)
			tw.tween_property(n, "scale", Vector2(1.3, 1.3), 0.15)
			tw.tween_property(n, "modulate:a", 0.0, 0.15)
			tw.chain().tween_callback(n.queue_free)
		goal_hit.emit(BLOCKS[kind].goal if BLOCKS.has(kind) else "crate", to_global(cell_pos(c)))
	elif n:
		n.queue_redraw()
		var tw := create_tween()
		tw.tween_property(n, "scale", Vector2(1.12, 0.9), 0.06)
		tw.tween_property(n, "scale", Vector2.ONE, 0.1)


func _break_chain(c: Vector2i) -> void:
	if _hits.has(c):
		return
	_hits[c] = true
	if honey[c.x][c.y] and chain[c.x][c.y] <= 0:
		honey[c.x][c.y] = false
		_honey_hit = true
		_overlay.queue_redraw()
		_burst(cell_pos(c), Color("#ffb020"), 12)
		goal_hit.emit("honey", to_global(cell_pos(c)))
		return
	chain[c.x][c.y] -= 1
	_overlay.queue_redraw()
	_burst(cell_pos(c), Color("#b8bcc8"), 10)
	if chain[c.x][c.y] <= 0:
		goal_hit.emit("chain", to_global(cell_pos(c)))


func _grow_grass(cells: Dictionary) -> void:
	var changed := false
	for c: Vector2i in cells:
		if inside(c) and not grass[c.x][c.y] and block_kind[c.x][c.y] == B_NONE and not hole[c.x][c.y]:
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
	var delay_of := {}  # клетка -> задержка исчезновения (ракета долетает не сразу)
	var power := 0.0
	var effects: Array = []
	var flights: Array = []
	while not pending.is_empty():
		var c: Vector2i = pending.pop_back()
		if cleared.has(c) or not inside(c):
			continue
		if block_kind[c.x][c.y] != B_NONE:
			var bdl: float = delay_of.get(c, 0.0)
			if bdl > 0.05:
				get_tree().create_timer(bdl).timeout.connect(func() -> void:
					_hits.erase(c)
					_hit_block(c))
			else:
				_hit_block(c)
			continue
		var g := gem_at(c)
		if g == null or g.special == Gem.ITEM:
			continue
		if _chained(c):
			_break_chain(c)
			continue
		cleared[c] = true
		if ice[c.x][c.y] > 0:
			ice[c.x][c.y] -= 1
			_burst(cell_pos(c), Color("#bfe9ff"), 10)
			if ice[c.x][c.y] <= 0:
				goal_hit.emit("ice", to_global(cell_pos(c)))
			queue_redraw()
		if g.is_power():
			var area := _area(g.special, c)
			if g.special == Gem.ROCKET_H or g.special == Gem.ROCKET_V:
				var base_d: float = delay_of.get(c, 0.0)
				for a2 in area:
					var d: float = base_d + Vector2(a2 - c).length() * ROCKET_CELL_TIME
					if not delay_of.has(a2) or d < delay_of[a2]:
						delay_of[a2] = d
			if g.special == Gem.PROPELLER:
				var target := _pick_target(cleared, area)
				if target != Vector2i(-1, -1):
					area.append(target)
					flights.append({"from": c, "to": target, "color": g.color})
					var arrive: float = delay_of.get(c, 0.0) + PROPELLER_DELAY + PROPELLER_TIME
					if not delay_of.has(target) or delay_of[target] > arrive:
						delay_of[target] = arrive
			pending.append_array(area)
			if grass[c.x][c.y]:
				for a in area:
					grassify[a] = true
			power += 1.5 if g.special == Gem.ORB else 1.0
			effects.append({"cell": c, "kind": g.special, "color": g.color})
	var wait := 0.0
	for e in effects:
		match e.kind:
			Gem.ROCKET_H, Gem.ROCKET_V:
				_rocket_fx(e.cell, e.kind == Gem.ROCKET_V, delay_of.get(e.cell, 0.0))
				wait = maxf(wait, 0.05)
			Gem.BOMB:
				_bomb_fx(e.cell, 1.5)
				wait = maxf(wait, 0.16)
			Gem.ORB:
				_beam_fx(e.cell, e.kind, e.color)
				var orb_targets: Array = []
				for oc in _area(Gem.ORB, e.cell):
					orb_targets.append(oc)
				await _chain_lightning(e.cell, orb_targets, color_at(orb_targets[0]) if not orb_targets.is_empty() else -1)
	for f in flights:
		_propeller_fx(f.from, f.to, f.color, delay_of.get(f.from, 0.0) + PROPELLER_DELAY)
		wait = maxf(wait, 0.08)
	if power > 0.0:
		big_hit.emit(power)
		special_fired.emit()
		await get_tree().create_timer(maxf(wait, 0.08)).timeout
	var last: Tween = null
	var max_dl := 0.0
	for c: Vector2i in cleared:
		max_dl = maxf(max_dl, float(delay_of.get(c, 0.0)))
	for c: Vector2i in cleared:
		var g := gem_at(c)
		tiles[c.x][c.y] = null
		var col: int = g.color
		if col >= 0:
			gem_cleared.emit(col, to_global(cell_pos(c)))
		var dl: float = delay_of.get(c, 0.0)
		var sk: int = g.special
		if sk != Gem.NONE or col < 0:
			# особые фишки исчезают по-своему
			tiles[c.x][c.y] = null
			last = _special_vanish(g, sk, dl)
			continue
		if dl > 0.0:
			get_tree().create_timer(dl).timeout.connect(_pop_fx.bind(c, col, 3))
		else:
			_pop_fx(c, col, 5 if cleared.size() <= 12 else 2)
		g.z_index = 3
		var tw := create_tween().set_parallel(true)
		if dl > 0.0:
			tw.tween_interval(dl)
			tw.chain()
		tw.tween_property(g, "scale", Vector2(1.3, 1.3), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "modulate", Color(1.6, 1.6, 1.6), 0.08)
		tw.chain().tween_property(g, "scale", Vector2(0.0, 0.0), 0.14).set_ease(Tween.EASE_IN)
		tw.tween_property(g, "rotation", randf_range(-0.6, 0.6), 0.14)
		tw.tween_property(g, "modulate:a", 0.0, 0.14)
		tw.chain().tween_callback(g.queue_free)
		last = tw
	if _grass_carry:
		for c2: Vector2i in cleared:
			grassify[c2] = true
		for c2: Vector2i in initial:
			grassify[c2] = true
	_grow_grass(grassify)
	if last:
		await get_tree().create_timer(max_dl + 0.24).timeout


## Исчезновение особой фишки: у каждой своя анимация.
func _special_vanish(g: Node2D, kind: int, delay: float) -> Tween:
	g.z_index = 4
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	match kind:
		Gem.ROCKET_H, Gem.ROCKET_V:
			# корпус вздрагивает и «распадается» на две ракеты (их рисует _rocket_fx)
			tw.tween_property(g, "scale", Vector2(1.35, 0.75) if kind == Gem.ROCKET_H else Vector2(0.75, 1.35), 0.06)
			tw.tween_property(g, "modulate:a", 0.0, 0.05)
		Gem.BOMB:
			# раздувается, краснеет, дрожит и лопается
			tw.tween_property(g, "scale", Vector2(1.55, 1.55), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(g, "modulate", Color(1.8, 0.7, 0.6), 0.12)
			tw.tween_property(g, "rotation", 0.15, 0.03)
			tw.tween_property(g, "rotation", -0.15, 0.03)
			tw.tween_property(g, "scale", Vector2(0.1, 0.1), 0.07).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(g, "modulate:a", 0.0, 0.07)
		Gem.PROPELLER:
			# бабочка вспархивает вверх (летящую рисует _propeller_fx)
			tw.tween_property(g, "position:y", g.position.y - 30, 0.12).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(g, "modulate:a", 0.0, 0.12)
		_:
			# радужный шар: быстро крутится, вспыхивает радугой и схлопывается в точку
			tw.tween_property(g, "rotation", TAU * 1.5, 0.3).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(g, "scale", Vector2(1.4, 1.4), 0.15)
			tw.parallel().tween_property(g, "modulate", Color(2, 2, 2), 0.15)
			tw.tween_callback(func() -> void:
				if fx:
					var at := fx.to_local(to_global(g.position))
					for i in 6:
						_sparkles(at, Gem.COLORS[i], 1))
			tw.tween_property(g, "scale", Vector2(0.05, 0.05), 0.12).set_ease(Tween.EASE_IN)
	tw.tween_callback(g.queue_free)
	return tw


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
			for dx in range(-2, 3):
				for dy in range(-2, 3):
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
		await get_tree().create_timer(PROPELLER_TIME + 0.1).timeout
		if carried != Gem.PROPELLER:
			for t in targets:
				if carried == Gem.BOMB:
					_bomb_fx(t, 1.0)
				else:
					_rocket_fx(t, randf() < 0.5)
		big_hit.emit(2.0)
	elif rockets == 2:
		for x in W:
			area[Vector2i(x, at.y)] = true
		for y in H:
			area[Vector2i(at.x, y)] = true
		_rocket_fx(at, false)
		_rocket_fx(at, true)
		big_hit.emit(2.0)
	elif bombs == 2:
		for dx in range(-3, 4):
			for dy in range(-3, 4):
				area[at + Vector2i(dx, dy)] = true
		_bomb_fx(at, 2.0)
		big_hit.emit(3.0)
	else:
		for d in range(-1, 2):
			for x in W:
				area[Vector2i(x, at.y + d)] = true
			for y in H:
				area[Vector2i(at.x + d, y)] = true
			_rocket_fx(at + Vector2i(0, d), false)
			_rocket_fx(at + Vector2i(d, 0), true)
		big_hit.emit(3.0)
	await _clear(area)


func _orb_with_color(orb: Node2D, col: int) -> void:
	var area := {orb.cell: true}
	var start: Vector2i = orb.cell
	orb.set_special(Gem.NONE)
	orb.color = -1
	var targets: Array = []
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g != orb and g.color == col and g.special == Gem.NONE:
				area[Vector2i(x, y)] = true
				targets.append(Vector2i(x, y))
	big_hit.emit(1.5)
	await _chain_lightning(start, targets, col)
	await _clear(area)


## Цепная молния: прыгает от шара к ближайшей фишке нужного цвета, потом к следующей и т. д.
## Каждая задетая фишка вспыхивает; убираются все вместе в конце.
func _chain_lightning(start: Vector2i, targets: Array, col: int) -> void:
	var color: Color = Gem.COLORS[col].lightened(0.45) if col >= 0 else Color("#bfe9ff")
	var left := targets.duplicate()
	var cur := start
	var step := clampf(0.75 / maxf(1.0, left.size()), 0.04, 0.09)
	while not left.is_empty():
		var best := 0
		var bd := 1e9
		for i in left.size():
			var d := Vector2(left[i] - cur).length_squared()
			if d < bd:
				bd = d
				best = i
		var nxt: Vector2i = left[best]
		left.remove_at(best)
		if fx:
			_lightning(fx.to_local(to_global(cell_pos(cur))), fx.to_local(to_global(cell_pos(nxt))), color, 8)
			_sparkles(fx.to_local(to_global(cell_pos(nxt))), color, 2)
		var g := gem_at(nxt)
		if g:
			var t := create_tween().set_parallel(true)
			t.tween_property(g, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_BACK)
			t.tween_property(g, "modulate", Color(1.8, 1.8, 2.0), 0.08)
		cur = nxt
		await get_tree().create_timer(step).timeout
	await get_tree().create_timer(0.12).timeout


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
		# яйцо над дырой дальше не упадёт — тоже считаем «дошло до низа»
		for y2 in range(H - 1, -1, -1):
			var g2 := gem_at(Vector2i(x, y2))
			if g2 and g2.special == Gem.ITEM:
				var only_holes := true
				for y3 in range(y2 + 1, H):
					if not hole[x][y3]:
						only_holes = false
						break
				if only_holes:
					c = Vector2i(x, y2)
					g = g2
					bottom = y2
				break
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
				if _spawn_cell(c):
					var g := _new_gem(rng.randi_range(0, colors - 1))
					spawned[x] += 1
					g.position = cell_pos(Vector2i(x, y - spawned[x]))
					tiles[x][y] = g
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
	# клетки, до которых фишке не дотечь (под цепями без соседей) — фишка появляется на месте
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			if _fillable(c) and gem_at(c) == null:
				var g := _new_gem(rng.randi_range(0, colors - 1))
				_place(g, c)
				g.scale = Vector2(0.1, 0.1)
				create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).tween_property(g, "scale", Vector2.ONE, 0.25)
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
		# «желе»: сплющивается при приземлении и пружинит
		tw.tween_property(g, "scale", Vector2(1.18, 0.8), 0.06)
		tw.tween_property(g, "scale", Vector2(0.92, 1.1), 0.08)
		tw.tween_property(g, "scale", Vector2.ONE, 0.08)
	await get_tree().create_timer(longest + 0.12).timeout


## Начало уровня: фишки падают сверху ряд за рядом.
func drop_in() -> void:
	for x in W:
		for y in H:
			var g: Node2D = tiles[x][y]
			if g == null:
				continue
			var target := cell_pos(Vector2i(x, y))
			g.position = target - Vector2(0, (H + 1) * CELL)
			var tw := create_tween()
			tw.tween_interval(0.25 + (H - y) * 0.04 + x * 0.01)
			tw.tween_property(g, "position", target, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(g, "scale", Vector2(1.18, 0.8), 0.06)
			tw.tween_property(g, "scale", Vector2.ONE, 0.1)


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
	p.amount = amount if Save.particles else maxi(2, amount / 3)
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


## Лопнувшая фишка: вспышка-кольцо, осколки-копии фишки и искры.
func _pop_fx(cell: Vector2i, col: int, shards: int) -> void:
	if fx == null:
		return
	var at := fx.to_local(to_global(cell_pos(cell)))
	var color: Color = Gem.COLORS[col] if col >= 0 else Color.WHITE
	var ring := Node2D.new()
	ring.position = at
	ring.draw.connect(func() -> void:
		ring.draw_circle(Vector2.ZERO, CELL * 0.42, Color(1, 1, 1, 0.55))
		ring.draw_arc(Vector2.ZERO, CELL * 0.42, 0, TAU, 28, color.lightened(0.4), 5.0, true))
	ring.scale = Vector2(0.3, 0.3)
	fx.add_child(ring)
	var rt := ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", Vector2(1.15, 1.15), 0.22).set_ease(Tween.EASE_OUT)
	rt.tween_property(ring, "modulate:a", 0.0, 0.22)
	rt.chain().tween_callback(ring.queue_free)
	var tex: Texture2D = Gem.tex("gem_%d" % col) if col >= 0 else null
	for i in shards:
		var sh := Sprite2D.new()
		sh.texture = tex
		if tex == null:
			continue
		var k := CELL * 0.28 / maxf(tex.get_width(), tex.get_height())
		sh.scale = Vector2(k, k)
		sh.position = at
		fx.add_child(sh)
		var ang := TAU * i / shards + randf_range(-0.4, 0.4)
		var dist := CELL * randf_range(0.7, 1.2)
		var t := sh.create_tween().set_parallel(true)
		t.tween_property(sh, "position", at + Vector2(cos(ang), sin(ang)) * dist, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(sh, "rotation", randf_range(-4, 4), 0.38)
		t.tween_property(sh, "scale", Vector2(k * 0.2, k * 0.2), 0.38).set_ease(Tween.EASE_IN)
		t.tween_property(sh, "modulate:a", 0.0, 0.38).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(sh.queue_free)
	_sparkles(at, color, 4 if shards > 2 else 2)


func _sparkles(at: Vector2, color: Color, n: int) -> void:
	for i in n:
		var st := Node2D.new()
		st.position = at
		var r := randf_range(6, 11)
		st.draw.connect(func() -> void:
			var pts := PackedVector2Array()
			for k in 8:
				var a := TAU * k / 8.0
				pts.append(Vector2(cos(a), sin(a)) * (r if k % 2 == 0 else r * 0.35))
			st.draw_colored_polygon(pts, Color(1, 1, 0.85))
			st.draw_circle(Vector2.ZERO, r * 0.3, color.lightened(0.6)))
		fx.add_child(st)
		var ang := randf() * TAU
		var t := st.create_tween().set_parallel(true)
		t.tween_property(st, "position", at + Vector2(cos(ang), sin(ang)) * CELL * randf_range(0.5, 1.0), 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(st, "rotation", PI, 0.45)
		t.tween_property(st, "modulate:a", 0.0, 0.45).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(st.queue_free)


## Ракета: две ракеты разлетаются в стороны с огненным следом, по линии бьёт молния.
func _rocket_fx(cell: Vector2i, vertical: bool, delay: float = 0.0) -> void:
	if fx == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var c := cell_pos(cell)
	var tex: Texture2D = Gem.tex("rocket")
	for sgn in [-1.0, 1.0]:
		var dir := Vector2(0, sgn) if vertical else Vector2(sgn, 0)
		var start := fx.to_local(to_global(c))
		var end := fx.to_local(to_global(c + dir * (H if vertical else W) * CELL))
		var r := Sprite2D.new()
		r.texture = tex
		var k := CELL * 0.9 / maxf(tex.get_width(), tex.get_height()) if tex else 1.0
		# картинка смотрит вправо: влево — зеркалим, вверх/вниз — поворачиваем
		if vertical:
			r.rotation = PI / 2.0 * sgn
			r.scale = Vector2(k, k)
		else:
			r.scale = Vector2(k * sgn, k)
		r.position = start
		r.z_index = 5
		fx.add_child(r)
		var cells := float(H if vertical else W)
		var last := [start]
		var tw := r.create_tween()
		tw.tween_method(func(t: float) -> void:
			r.position = start.lerp(end, t)
			# дымок: круглые облачка позади ракеты
			if r.position.distance_to(last[0]) > 26.0:
				last[0] = r.position
				_puff(r.position - dir * 30.0), 0.0, 1.0, ROCKET_CELL_TIME * cells)
		tw.tween_callback(r.queue_free)


func _puff(at: Vector2) -> void:
	var p := Node2D.new()
	p.position = at
	p.z_index = 4
	var rad := randf_range(9, 14)
	p.draw.connect(func() -> void:
		p.draw_circle(Vector2.ZERO, rad, Color(1, 0.85, 0.5, 0.75))
		p.draw_circle(Vector2(-2, -2), rad * 0.55, Color(1, 1, 0.95, 0.9)))
	fx.add_child(p)
	var t := p.create_tween().set_parallel(true)
	t.tween_property(p, "scale", Vector2(1.8, 1.8), 0.35).set_ease(Tween.EASE_OUT)
	t.tween_property(p, "modulate", Color(0.9, 0.9, 0.95, 0.0), 0.35)
	t.chain().tween_callback(p.queue_free)


## Объёмная молния: широкое свечение, цветное тело, белая сердцевина, вспышки на изломах.
func _lightning(a: Vector2, b: Vector2, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	var n := maxi(6, int(a.distance_to(b) / 26.0))
	var nrm := (b - a).orthogonal().normalized()
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if i > 0 and i < n:
			p += nrm * randf_range(-16, 16)
		pts.append(p)
	var w := width * 2.2
	var layers := [[w * 2.6, Color(color, 0.28)], [w * 1.5, Color(color, 0.6)], [w, color], [w * 0.45, Color(1, 1, 1, 0.95)]]
	for L in layers:
		var line := Line2D.new()
		line.points = pts
		line.width = L[0]
		line.default_color = L[1]
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.z_index = 4
		fx.add_child(line)
		var t := line.create_tween()
		t.tween_property(line, "width", float(L[0]) * 0.3, 0.32).set_delay(0.05)
		t.parallel().tween_property(line, "modulate:a", 0.0, 0.32).set_delay(0.05)
		t.tween_callback(line.queue_free)
	# светящиеся «узлы» на концах
	for p in [a, b]:
		var dot := Node2D.new()
		dot.position = p
		dot.z_index = 5
		dot.draw.connect(func() -> void:
			dot.draw_circle(Vector2.ZERO, w * 1.6, Color(color, 0.35))
			dot.draw_circle(Vector2.ZERO, w * 0.8, Color(1, 1, 1, 0.9)))
		fx.add_child(dot)
		var dt := dot.create_tween()
		dt.tween_property(dot, "scale", Vector2(0.2, 0.2), 0.3)
		dt.parallel().tween_property(dot, "modulate:a", 0.0, 0.3)
		dt.tween_callback(dot.queue_free)


## Бомба: вспышка, ударная волна, огонь и обломки.
func _bomb_fx(cell: Vector2i, power: float) -> void:
	shake.emit(16.0 * power)
	# ударная волна отталкивает фишки вокруг
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var c := cell + Vector2i(dx, dy)
			var g := gem_at(c)
			if g == null or (dx == 0 and dy == 0):
				continue
			var dir := Vector2(dx, dy).normalized()
			var dist := Vector2(dx, dy).length()
			var base := cell_pos(c)
			var t := create_tween()
			t.tween_property(g, "position", base + dir * 14.0 / dist, 0.06).set_ease(Tween.EASE_OUT)
			t.tween_property(g, "position", base, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	if fx == null:
		return
	var at := fx.to_local(to_global(cell_pos(cell)))
	var flash := Node2D.new()
	flash.position = at
	flash.z_index = 5
	var rad := CELL * 1.6 * power
	flash.draw.connect(func() -> void:
		flash.draw_circle(Vector2.ZERO, rad, Color(1, 0.95, 0.7, 0.7))
		flash.draw_arc(Vector2.ZERO, rad, 0, TAU, 48, Color(1, 0.6, 0.2), 10.0, true)
		flash.draw_arc(Vector2.ZERO, rad * 0.8, 0, TAU, 48, Color(1, 1, 1, 0.9), 4.0, true))
	flash.scale = Vector2(0.15, 0.15)
	fx.add_child(flash)
	var t := flash.create_tween().set_parallel(true)
	t.tween_property(flash, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(flash, "modulate:a", 0.0, 0.35).set_delay(0.08)
	t.chain().tween_callback(flash.queue_free)
	for spec in [[Color("#ffcf3a"), 30, 380.0, 0.0], [Color("#ff6a1a"), 24, 260.0, 0.0], [Color("#7a5230"), 16, 320.0, 700.0]]:
		var p := CPUParticles2D.new()
		p.position = at
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = spec[1] if Save.particles else int(spec[1]) / 3
		p.lifetime = 0.6
		p.spread = 180.0
		p.initial_velocity_min = float(spec[2]) * 0.4
		p.initial_velocity_max = float(spec[2]) * power
		p.gravity = Vector2(0, spec[3])
		p.scale_amount_min = 5.0
		p.scale_amount_max = 13.0
		p.color = spec[0]
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0))
		p.scale_amount_curve = curve
		p.z_index = 4
		fx.add_child(p)
		p.emitting = true
		p.finished.connect(p.queue_free)


## Бабочка: вспархивает, плавно летит к цели с наклоном по ходу полёта и шлейфом искр, ныряет и лопается.
func _propeller_fx(from: Vector2i, to: Vector2i, col: int, delay: float = 0.0) -> void:
	if fx == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var p: Node2D = Gem.new()
	p.color = col
	p.size = CELL
	p.z_index = 6
	fx.add_child(p)
	p.set_special(Gem.PROPELLER)
	var a := fx.to_local(to_global(cell_pos(from)))
	var b := fx.to_local(to_global(cell_pos(to)))
	p.position = a
	var lift := a + Vector2(0, -CELL * 0.7)
	var c1 := lift + Vector2(0, -CELL * 1.2)
	var c2 := b + Vector2(0, -CELL * 1.6)
	var last := [lift]
	var tw := p.create_tween()
	# 1. вспорхнула
	tw.tween_property(p, "position", lift, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(p, "scale", Vector2(1.15, 1.15), 0.3)
	# 2. полёт по плавной кривой
	tw.tween_method(func(t: float) -> void:
		var q := lift.bezier_interpolate(c1, c2, b, t)
		var dx := q.x - p.position.x
		p.rotation = lerpf(p.rotation, clampf(dx * 0.03, -0.35, 0.35), 0.3)
		p.position = q
		if q.distance_to(last[0]) > 22.0:
			last[0] = q
			_sparkles(q, Color("#ffcf5a"), 1), 0.0, 1.0, PROPELLER_TIME - 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 3. у цели: зависла, ныряет и лопается
	tw.tween_property(p, "rotation", 0.0, 0.05)
	tw.tween_property(p, "scale", Vector2(1.35, 1.35), 0.14).set_trans(Tween.TRANS_BACK)
	tw.tween_callback(func() -> void:
		_burst(cell_pos(to), Color("#ffb020"), 14)
		_pop_ring(b, Color("#ffd23f")))
	tw.tween_property(p, "scale", Vector2(0.1, 0.1), 0.12).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.queue_free)


func _pop_ring(at: Vector2, color: Color) -> void:
	var ring := Node2D.new()
	ring.position = at
	ring.z_index = 5
	ring.draw.connect(func() -> void:
		ring.draw_circle(Vector2.ZERO, CELL * 0.5, Color(1, 1, 1, 0.5))
		ring.draw_arc(Vector2.ZERO, CELL * 0.5, 0, TAU, 32, color, 6.0, true))
	ring.scale = Vector2(0.3, 0.3)
	fx.add_child(ring)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector2(1.3, 1.3), 0.25).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.25)
	t.chain().tween_callback(ring.queue_free)


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
