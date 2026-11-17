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
signal bad_move
signal shuffled

const Gem := preload("res://scripts/gem.gd")
const CELL := 84.0
const PROPELLER_TIME := 0.9  # полёт бабочки к цели: 0.18 взлёт + 0.55 полёт + 0.13 нырок (было 1.5 — «висело»)
const PROPELLER_DELAY := 0.15  # сначала взрываются соседи, потом бабочка взлетает
const ROCKET_CELL_TIME := 0.07  # ракета пролетает клетку за столько секунд
enum { B_NONE, B_CRATE, B_VASE, B_SAFE, B_JAR, B_CAGE, B_BALLOON, B_FLOWER, B_BUSH, B_SHELL, B_STONE, B_COLORBOX, B_BIRDHOUSE }
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
	# камень — только усилителями; цветной ящик — совпадением своего цвета; скворечник выпускает птиц
	B_STONE: {"goal": "stone", "adj": false, "tex": ["ob_stone"], "fx": Color("#9aa3b5")},
	B_COLORBOX: {"goal": "colorbox", "adj": true, "tex": [], "fx": Color("#ffffff")},
	B_BIRDHOUSE: {"goal": "birdhouse", "adj": true, "tex": ["ob_birdhouse"], "fx": Color("#c98a4b")},
}

var W := 8
var H := 10
var colors := 5
var tiles: Array = []        # tiles[x][y] -> Gem | null
var block_kind: Array = []   # B_NONE / B_CRATE / B_VASE
var block_hp: Array = []
var block_max: Array = []
var block_color: Array = []  # цвет цветного ящика
var block_anchor: Array = [] # большой блок 2×2: левая верхняя клетка; у обычных — сама клетка
var ice: Array = []          # слой льда под фишкой
var hole: Array = []         # дыра в фигурном поле (клетки нет)
var honey: Array = []        # мёд на фишке (растекается)
var _honey_hit := false
var _player_move := false
## Ось хода игрока для ракеты (как в Royal Match): 0 — свайп влево/вправо, 1 — вверх/вниз, -1 — каскад.
var _swap_axis := -1
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
	block_color = []
	block_anchor = []
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
		block_color.append([])
		block_anchor.append([])
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
			block_color[x].append(int(b.get("color", -1)))
			block_anchor[x].append(b.get("anchor", c))
			ice[x].append(int(level.get("ice", {}).get(c, 0)))
			hole[x].append(c in level.get("holes", []))
			honey[x].append(c in level.get("honey", []))
			chain[x].append(int(level.chains.get(c, 0)))
			grass[x].append(c in level.grass_start)
			grass_target[x].append(c in level.grass_target)
	# слой сияния под особыми фишками: рисуется до фишек, поэтому соседние фишки его не закрывают
	_halos = preload("res://scripts/redraw_layer.gd").new()
	_halos.draw.connect(_draw_halos)
	add_child(_halos)
	for c: Vector2i in level.blocks:
		if level.blocks[c].get("anchor", c) == c:
			_make_block_node(c)
	_overlay = Node2D.new()
	_overlay.z_index = 3
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	if level.has("layout"):
		_fill_layout(level.layout)
	else:
		_fill_initial(level.get("items", 0))
	hint_move = level.get("first_move", [])
	queue_redraw()


var hint_move: Array = []  # ручная подсказка первого хода (уровень 1), сбрасывается после хода


## Ручная раскладка: строки цифр-цветов сверху вниз.
func _fill_layout(rows: Array) -> void:
	for y in mini(H, rows.size()):
		var row: String = rows[y]
		for x in mini(W, row.length()):
			var c := Vector2i(x, y)
			if _fillable(c) and tiles[x][y] == null:
				_place(_new_gem(int(row[x])), c)


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
	g.size = CELL * 0.9
	add_child(g)
	if kind != Gem.NONE:
		g.set_special(kind)
	return g


func _place(g: Node2D, cell: Vector2i) -> void:
	tiles[cell.x][cell.y] = g
	g.cell = cell
	g.position = cell_pos(cell)


func is_big(c: Vector2i) -> bool:
	return inside(c) and block_kind[c.x][c.y] != B_NONE and (block_anchor[c.x][c.y] != c or (inside(c + Vector2i.ONE) and block_anchor[c.x + 1][c.y + 1] == c))


func _make_block_node(cell: Vector2i) -> void:
	var n := Node2D.new()
	n.position = cell_pos(cell) + (Vector2(CELL, CELL) / 2.0 if is_big(cell) else Vector2.ZERO)
	n.z_index = 1
	n.draw.connect(_draw_block.bind(n, cell))
	add_child(n)
	block_nodes[cell] = n


func _draw_block(n: Node2D, cell: Vector2i) -> void:
	var hp: int = block_hp[cell.x][cell.y]
	var kind: int = block_kind[cell.x][cell.y]
	var t := block_tex(kind, block_max[cell.x][cell.y] - hp)
	var big := is_big(cell)
	if t:
		var sz := t.get_size()
		var k := CELL * (2.05 if big else 1.06) / maxf(sz.x, sz.y)
		n.draw_set_transform(Vector2(0, 0), 0.0, Vector2(k, k))
		n.draw_texture(t, -sz / 2)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if hp >= 2 and (BLOCKS[kind].tex.size() == 1 or big):
			# прочность цифрой, если у картинки нет стадий (у больших блоков — всегда)
			var f: Font = load("res://scripts/ui_theme.gd").title_font()
			var bp := Vector2(CELL * (0.75 if big else 0.3), CELL * (0.75 if big else 0.3))
			var br := 17.0 if big else 13.0
			n.draw_circle(bp, br, Color("#2b2350"))
			n.draw_arc(bp, br, 0, TAU, 24, Color.WHITE, 2.5, true)
			var fs := 24 if big else 20
			var ts := f.get_string_size(str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			n.draw_string(f, bp + Vector2(-ts.x / 2, fs * 0.36), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		return
	var bk := 2.0 if big else 1.0
	match kind:
		B_VASE:
			draw_vase(n, Vector2.ZERO, CELL * 0.44 * bk, hp)
		B_STONE:
			draw_stone(n, Vector2.ZERO, CELL * 0.45 * bk, mini(hp, 3))
			if big and hp >= 1:
				var f: Font = load("res://scripts/ui_theme.gd").title_font()
				var bp := Vector2(CELL * 0.75, CELL * 0.75)
				n.draw_circle(bp, 17.0, Color("#2b2350"))
				n.draw_arc(bp, 17.0, 0, TAU, 24, Color.WHITE, 2.5, true)
				var ts := f.get_string_size(str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
				n.draw_string(f, bp + Vector2(-ts.x / 2, 8.6), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		B_COLORBOX:
			draw_colorbox(n, Vector2.ZERO, CELL * 0.46, block_color[cell.x][cell.y])
		B_BIRDHOUSE:
			draw_birdhouse(n, Vector2.ZERO, CELL * 0.46, hp)
		_:
			draw_crate(n, Vector2.ZERO, CELL * 0.46, hp)


## Заглушки до ИИ-картинок: камень, цветной ящик, скворечник.
static func draw_stone(n: CanvasItem, o: Vector2, s: float, hp: int) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0
		pts.append(o + Vector2(cos(a), sin(a) * 0.85) * s * (0.92 + 0.08 * sin(i * 2.3)))
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(0, 5))
	n.draw_colored_polygon(sh, Color(0, 0, 0, 0.3))
	n.draw_colored_polygon(pts, Color("#6f7787"))
	var top := PackedVector2Array()
	for p in pts:
		top.append(o + (p - o) * 0.82 + Vector2(-2, -4))
	n.draw_colored_polygon(top, Color("#a3abbb"))
	n.draw_circle(o + Vector2(-s * 0.35, -s * 0.35), s * 0.14, Color(1, 1, 1, 0.5))
	for i in 3 - hp:
		n.draw_line(o + Vector2(-s * 0.5 + i * 18, -s * 0.2), o + Vector2(-s * 0.1 + i * 18, s * 0.4), Color("#3a4050"), 4.0)


static func draw_colorbox(n: CanvasItem, o: Vector2, s: float, col: int) -> void:
	var c: Color = Gem.COLORS[clampi(col, 0, Gem.COLORS.size() - 1)]
	var sb := StyleBoxFlat.new()
	sb.bg_color = c.darkened(0.35)
	sb.set_corner_radius_all(12)
	n.draw_style_box(sb, Rect2(o - Vector2(s, s) + Vector2(0, 4), Vector2(s, s) * 2))
	sb.bg_color = c
	n.draw_style_box(sb, Rect2(o - Vector2(s, s), Vector2(s, s) * 2 - Vector2(0, 4)))
	sb.bg_color = c.lightened(0.35)
	n.draw_style_box(sb, Rect2(o - Vector2(s, s) * 0.62, Vector2(s, s) * 1.24))
	var t := Gem.tex("gem_%d" % col)
	if t:
		n.draw_texture_rect(t, Rect2(o - Vector2(s, s) * 0.55, Vector2(s, s) * 1.1), false)
	n.draw_rect(Rect2(o - Vector2(s, s), Vector2(s, s) * 2 - Vector2(0, 4)), Color("#ffcf3a"), false, 3.0)


static func draw_birdhouse(n: CanvasItem, o: Vector2, s: float, hp: int) -> void:
	n.draw_rect(Rect2(o + Vector2(-s * 0.75, -s * 0.2), Vector2(s * 1.5, s * 1.15)), Color("#c98a4b"))
	n.draw_rect(Rect2(o + Vector2(-s * 0.75, -s * 0.2), Vector2(s * 1.5, s * 0.12)), Color("#8a5326"))
	n.draw_colored_polygon(PackedVector2Array([o + Vector2(-s, -s * 0.15), o + Vector2(0, -s), o + Vector2(s, -s * 0.15)]), Color("#e0563a"))
	n.draw_circle(o + Vector2(0, s * 0.3), s * 0.28, Color("#3a2410"))
	n.draw_rect(Rect2(o + Vector2(-s * 0.1, s * 0.62), Vector2(s * 0.2, s * 0.1)), Color("#8a5326"))
	var f: Font = ThemeDB.fallback_font
	n.draw_circle(o + Vector2(s * 0.65, s * 0.7), 12, Color("#2b2350"))
	n.draw_string(f, o + Vector2(s * 0.65 - 6, s * 0.7 + 7), str(hp), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


static func block_tex(kind: int, stage: int) -> Texture2D:
	if not BLOCKS.has(kind):
		return null
	var names: Array = BLOCKS[kind].tex
	if names.is_empty():
		return null
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
	# обводка поля цельным контуром (как в Royal Match): каждый слой — форма поля, расширенная на N px
	# (каждая клетка — скруглённый прямоугольник, расширенный наружу; соседние сливаются без стыков),
	# слои от широкого к узкому, клетки поля рисуются сверху. Видна только полоса снаружи клеток.
	# [расширение, цвет, сдвиг вниз]: тень, тёмная кайма, золото, блик, золото, тонкая тёмная линия у клеток
	var layers := [[9.0, Color(0, 0, 0, 0.25), 3.0], [8.0, Color("#3b1f05"), 0.0], [6.5, Color("#f2a019"), 0.0],
		[4.3, Color("#ffe58a"), 0.0], [3.3, Color("#e8920f"), 0.0], [1.5, Color("#4a2806"), 0.0]]
	var cells: Array = []
	for x in W:
		for y in H:
			if not hole[x][y]:
				cells.append(Vector2(x, y) * CELL)
	for L in layers:
		var e: float = L[0]
		var tris := PackedVector2Array()
		for p: Vector2 in cells:
			var rr := Rect2(p - Vector2(e, e) + Vector2(0, L[2]), Vector2(CELL + 2.0 * e, CELL + 2.0 * e))
			tris.append_array(_round_rect_tris(rr, e))
		var cols := PackedColorArray()
		cols.resize(tris.size())
		cols.fill(L[1])
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), tris, cols)
	# клетки рисуются слоями (сначала все подложки, потом все плитки А, потом все плитки Б) —
	# одинаковые картинки подряд видеокарта склеивает в одну пачку (раньше вперемешку — ~160 вызовов)
	var tiles := [[], []]
	for x in W:
		for y in H:
			if hole[x][y]:
				continue
			var rect := Rect2(Vector2(x, y) * CELL, Vector2(CELL, CELL))
			var even := (x + y) % 2 == 0
			var col := Color("#dcecf8", 0.97) if even else Color("#c6dcef", 0.97)
			var tt: Texture2D = Gem.tex("lv_tile_a" if even else "lv_tile_b")
			if grass[x][y]:
				col = Color("#5cc24a") if even else Color("#4fb33f")
			elif grass_target[x][y]:
				col = Color("#8a6440") if even else Color("#7d5a39")
			elif tt:
				draw_rect(rect, Color("#e9d2ad"))
				tiles[0 if even else 1].append(rect)
				continue
			draw_rect(rect, col)
			draw_rect(Rect2(rect.position, Vector2(CELL, 4)), Color(0.2, 0.35, 0.55, 0.10))
	for i in 2:
		var tt: Texture2D = Gem.tex("lv_tile_a" if i == 0 else "lv_tile_b")
		for rect: Rect2 in tiles[i]:
			draw_texture_rect(tt, rect.grow(-1.0), false)
	for x in W:
		for y in H:
			if hole[x][y]:
				continue
			var rect := Rect2(Vector2(x, y) * CELL + Vector2(2, 2), Vector2(CELL, CELL) - Vector2(4, 4))
			var gt := Gem.tex("ob_tile_grass") if grass[x][y] else null
			if gt:
				draw_texture_rect(gt, rect.grow(1.0), false)
			if ice[x][y] > 0:
				var it := Gem.tex("ob_tile_ice")
				if it:
					draw_texture_rect(it, rect.grow(2.0), false, Color(1, 1, 1, 1.0))
				var ib := StyleBoxFlat.new()
				ib.draw_center = true
				ib.bg_color = Color("#bfeeff", 0.28)
				ib.set_border_width_all(4)
				ib.border_color = Color("#e8fbff", 0.95)
				ib.set_corner_radius_all(13)
				draw_style_box(ib, rect.grow(-1.0))
				draw_line(rect.position + Vector2(14, rect.size.y - 18), rect.position + Vector2(rect.size.x - 22, 12), Color(1, 1, 1, 0.6), 4.0, true)
			if grass[x][y] and gt == null:
				for k in 3:
					var bx := rect.position.x + 14 + k * 22
					var by := rect.position.y + rect.size.y - 10
					draw_line(Vector2(bx, by), Vector2(bx - 4, by - 12), Color("#2f8f2f"), 3.0)
					draw_line(Vector2(bx + 4, by), Vector2(bx + 8, by - 10), Color("#2f8f2f"), 3.0)


## Скруглённый прямоугольник треугольниками (радиус углов rad): крест из двух прямоугольников + 4 четверти круга.
func _round_rect_tris(r: Rect2, rad: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var add_rect := func(q: Rect2) -> void:
		var a := q.position
		var b := q.position + Vector2(q.size.x, 0)
		var c := q.end
		var d := q.position + Vector2(0, q.size.y)
		out.append_array([a, b, c, a, c, d])
	add_rect.call(Rect2(r.position + Vector2(rad, 0), Vector2(r.size.x - 2.0 * rad, r.size.y)))
	add_rect.call(Rect2(r.position + Vector2(0, rad), Vector2(r.size.x, r.size.y - 2.0 * rad)))
	out.append_array(_circle_tris([r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad),
		Vector2(r.position.x + rad, r.end.y - rad), r.end - Vector2(rad, rad)], rad))
	return out


## Кружки (для скругления углов обводки) — треугольниками, чтобы рисовать вместе со сторонами одним вызовом.
func _circle_tris(centers: Array, r: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var seg := 12
	for c: Vector2 in centers:
		for i in seg:
			var a0 := TAU * i / seg
			var a1 := TAU * (i + 1) / seg
			out.append_array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r])
	return out


# ---------- запросы к полю ----------

func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


var _halos: Node2D


## Сияние особых фишек: мягкий пульсирующий ореол и медленно вращающиеся лучи под фишкой.
func _draw_halos() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var cols := {Gem.ROCKET_H: Color(1.0, 0.55, 0.2), Gem.ROCKET_V: Color(1.0, 0.55, 0.2), Gem.BOMB: Color(1.0, 0.35, 0.25),
		Gem.PROPELLER: Color(1.0, 0.8, 0.3)}
	for x in W:
		for y in H:
			var g: Node2D = tiles[x][y]
			if g == null or not g.is_power() or g.modulate.a < 0.5:
				continue
			var col: Color = cols.get(g.special, Color.from_hsv(fmod(t * 0.25, 1.0), 0.55, 1.0))
			var c: Vector2 = g.position
			var ph := 0.5 + 0.5 * sin(t * 4.0 + x * 1.3 + y * 0.7)
			for i in 5:
				var rr := CELL * (0.78 - i * 0.07) * (0.92 + ph * 0.12)
				_halos.draw_circle(c, rr, Color(col, (0.12 + i * 0.07) * (0.6 + 0.4 * ph)))
			for i in 6:
				var a := t * 0.6 + i * TAU / 6.0
				var d := Vector2(cos(a), sin(a))
				var w := d.orthogonal() * CELL * 0.11
				_halos.draw_colored_polygon(PackedVector2Array([c + w, c + d * CELL * 0.95, c - w]), Color(col.lightened(0.3), 0.4 * (0.6 + 0.4 * ph)))


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
	if hint_move.size() == 2:
		m = hint_move
	if m.is_empty():
		return
	_stop_hint()
	for c: Vector2i in m:
		var g := gem_at(c)
		if g == null:
			continue
		var d := Vector2(m[1] - m[0]) * 14.0 * (1.0 if c == m[0] else -1.0)
		if d == Vector2.ZERO:
			d = Vector2(0, -14)
		var base := cell_pos(c)
		var t := create_tween()
		for i in 3:
			t.tween_property(g, "position", base + d, 0.16)
			t.parallel().tween_property(g, "scale", Vector2(1.16, 1.16), 0.16)
			t.tween_property(g, "position", base, 0.16)
			t.parallel().tween_property(g, "scale", Vector2.ONE, 0.16)
		if fx and c == m[0]:
			_pop_ring(fx.to_local(to_global(base)), Color("#fff3a0"))
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
	_swap_axis = 0 if a.y == b.y else 1
	_grass_carry = grass[a.x][a.y] or grass[b.x][b.y]
	Sfx.play("swap")
	await _animate_swap(ga, gb, a, b)
	_swap_data(a, b)
	# теперь ga стоит в b, gb — в a
	var pa: bool = ga.is_power()
	var pb: bool = gb.is_power()
	if pa and pb:
		hint_move = []
		move_made.emit()
		await _combo(ga, gb, b)
		await _cascade([])
		return
	if ga.special == Gem.ORB or gb.special == Gem.ORB:
		var orb := ga if ga.special == Gem.ORB else gb
		var other := gb if orb == ga else ga
		if other.special != Gem.ITEM:
			hint_move = []
			move_made.emit()
			await _orb_with_color(orb, other.color)
			await _cascade([])
			return
	if pa or pb:
		# особая фишка, сдвинутая свапом, всегда срабатывает
		hint_move = []
		move_made.emit()
		var sp := ga if pa else gb
		await _clear({sp.cell: true})
		await _cascade([])
		return
	if find_groups().is_empty():
		Sfx.play("bad")
		bad_move.emit()
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
	await _tool_anim(kind, cell)
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
		"rockets":
			# ракеты бьют крестом: весь ряд и весь столбец
			for x in W:
				area[Vector2i(x, cell.y)] = true
			for y in H:
				area[Vector2i(cell.x, y)] = true
			_beam_fx(cell, Gem.ROCKET_H, -1)
			_beam_fx(cell, Gem.ROCKET_V, -1)
	big_hit.emit(1.5)
	await _clear(area)
	await _cascade([])


## Крупная анимация бустера: молот замахивается и бьёт по клетке; стрела проносится через ряд/столбец.
func _tool_anim(kind: String, cell: Vector2i) -> void:
	if fx == null:
		return
	var gs := get_global_transform().get_scale().x
	var at := fx.to_local(to_global(cell_pos(cell)))
	if kind == "rockets":
		# две ракеты одновременно: по ряду и по столбцу
		_tool_anim("arrow", cell)
		await _tool_anim("cannon", cell)
		return
	var name := "ui_hammer" if kind == "hammer" else "ui_arrow"
	var tex: Texture2D = load("res://scripts/zoo.gd").art(name)
	if tex == null:
		return
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.z_index = 12
	var k := CELL * 2.4 * gs / maxf(tex.get_width(), tex.get_height())
	fx.add_child(sp)
	if kind == "hammer":
		# молот прилетает крупным сбоку-сверху, замахивается и с силой бьёт
		sp.scale = Vector2(k, k) * 0.3
		sp.position = at + Vector2(CELL * 1.6, -CELL * 2.6) * gs
		sp.rotation = 0.9
		var tw := sp.create_tween()
		tw.tween_property(sp, "scale", Vector2(k, k), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sp, "position", at + Vector2(CELL * 0.9, -CELL * 1.3) * gs, 0.2)
		tw.tween_property(sp, "rotation", 1.5, 0.16).set_trans(Tween.TRANS_SINE)
		tw.tween_property(sp, "rotation", -0.55, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(sp, "position", at + Vector2(CELL * 0.35, -CELL * 0.55) * gs, 0.1)
		await tw.finished
		Sfx.play("bomb", 1.25, -4.0)
		shake.emit(14.0)
		_glow_flash(at, Color(1, 0.9, 0.6), CELL * 2.4 * gs, 0.3)
		_pop_ring(at, Color("#ffe08a"))
		_sparkles(at, Color("#fff3b0"), 10)
		var ot := sp.create_tween()
		ot.tween_property(sp, "rotation", 0.2, 0.15).set_trans(Tween.TRANS_BACK)
		ot.parallel().tween_property(sp, "modulate:a", 0.0, 0.25).set_delay(0.08)
		ot.tween_callback(sp.queue_free)
	else:
		# стрела влетает с края поля и проносится через весь ряд/столбец
		var vertical := kind == "cannon"
		var a := fx.to_local(to_global(Vector2(-CELL, cell_pos(cell).y) if not vertical else Vector2(cell_pos(cell).x, board_size().y + CELL)))
		var b := fx.to_local(to_global(Vector2(board_size().x + CELL, cell_pos(cell).y) if not vertical else Vector2(cell_pos(cell).x, -CELL)))
		sp.scale = Vector2(k, k) * 0.8
		sp.rotation = -PI / 2.0 if vertical else 0.0
		sp.position = a
		Sfx.play("rocket", 1.2, -3.0)
		var last := [a]
		var tw := sp.create_tween()
		tw.tween_method(func(t: float) -> void:
			sp.position = a.lerp(b, t)
			if sp.position.distance_to(last[0]) > 30.0:
				last[0] = sp.position
				_sparkles(sp.position, Color("#ffe08a"), 2), 0.0, 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(sp.queue_free)
		shake.emit(8.0)
		await get_tree().create_timer(0.18).timeout


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
				creations.append({"cell": at, "kind": kind, "color": color_at(at), "cells": g.cells})
		# ящики рядом с совпадениями получают удар (цветной ящик — только от своего цвета)
		for c: Vector2i in to_clear:
			var mc := color_at(c)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if inside(n) and block_kind[n.x][n.y] != B_NONE and BLOCKS[block_kind[n.x][n.y]].adj:
					if block_kind[n.x][n.y] == B_COLORBOX and block_color[n.x][n.y] != mc:
						continue
					_hit_block(n)
		if wave >= 2:
			combo_made.emit(wave)
		# каскад звучит всё выше
		Sfx.play("match_%d" % mini(wave - 1, 7))
		if not creations.is_empty():
			Sfx.play("special", 1.0, -2.0)
			await _merge_into(creations)
		await _clear(to_clear, grassify)
		for cr in creations:
			var cell: Vector2i = cr.cell
			if gem_at(cell) == null and _fillable(cell):
				var ng := _new_gem(cr.color, cr.kind)
				_place(ng, cell)
				# бонус «выпрыгивает» из слившихся фишек: вспышка, кольцо, искры, крутанулся и подпрыгнул
				ng.z_index = 4
				ng.scale = Vector2.ZERO
				ng.modulate = Color(2.0, 2.0, 2.0)
				# твин живёт на самой фишке: если бонус сразу взорвётся, анимация просто остановится
				var ct := ng.create_tween().set_parallel(true)
				ct.tween_property(ng, "scale", Vector2(1.55, 1.55), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				ct.tween_property(ng, "modulate", Color.WHITE, 0.3)
				ct.chain().tween_property(ng, "scale", Vector2(0.9, 1.1), 0.08)
				ct.chain().tween_property(ng, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				ct.chain().tween_callback(func() -> void: ng.z_index = 0)
				if fx:
					var at := fx.to_local(to_global(cell_pos(cell)))
					var tint: Color = Gem.COLORS[cr.color] if cr.color >= 0 and cr.color < Gem.COLORS.size() else Color("#fff6b0")
					_glow_flash(at, tint.lerp(Color.WHITE, 0.4), CELL * 2.2, 0.35)
					_pop_ring(at, Color("#fff6b0"))
					_sparkles(at, Color("#fff6b0"), 12)

		await _gravity()
		prefer = []
		_swap_axis = -1
	if _player_move:
		_player_move = false
		if not _honey_hit:
			_spread_honey()
	_honey_hit = false
	# страховка: если что-то разрушилось с задержкой и осталась пустая клетка — досыпаем фишки
	if holes() > 0:
		await _gravity()
		if not find_groups().is_empty():
			await _cascade([])
			return
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
				if g and g.special == Gem.NONE and not _chained(n) and ice[n.x][n.y] <= 0:
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
		# ракета от хода игрока — по направлению свайпа (вверх/вниз → вертикальная), от каскада — вдоль линии
		if _swap_axis >= 0:
			return Gem.ROCKET_V if _swap_axis == 1 else Gem.ROCKET_H
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


func _hit_block(c0: Vector2i) -> void:
	if not inside(c0) or block_kind[c0.x][c0.y] == B_NONE:
		return
	# у большого блока все удары идут в его левую верхнюю клетку, один раз за волну
	var c: Vector2i = block_anchor[c0.x][c0.y]
	var big := is_big(c)
	if _hits.has(c):
		return
	_hits[c] = true
	var kind: int = block_kind[c.x][c.y]
	Sfx.play("glass" if kind in [B_VASE, B_JAR, B_SHELL] else "wood", randf_range(0.9, 1.1), -4.0)
	var stage_tex := block_tex(kind, block_max[c.x][c.y] - block_hp[c.x][c.y])
	block_hp[c.x][c.y] -= 1
	var n: Node2D = block_nodes.get(c)
	var center := cell_pos(c) + (Vector2(CELL, CELL) / 2.0 if big else Vector2.ZERO)
	var gone: bool = block_hp[c.x][c.y] <= 0
	# препятствие разлетается на куски из своего материала (щепки ящика, черепки горшка…)
	if stage_tex and fx:
		var pieces := (9 if big else 7) if gone else (4 if big else 3)
		_shatter(stage_tex, fx.to_local(to_global(center)), CELL * (2.0 if big else 1.0), pieces, 1.0 if gone else 0.6)
		_burst(center, BLOCKS[kind].fx if BLOCKS.has(kind) else Color.WHITE, 6 if big else 4)
	else:
		_burst(center, BLOCKS[kind].fx if BLOCKS.has(kind) else Color.WHITE, 20 if big else 12)
	if block_hp[c.x][c.y] <= 0:
		if big:
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
				block_kind[c.x + d.x][c.y + d.y] = B_NONE
				block_anchor[c.x + d.x][c.y + d.y] = c + d
			shake.emit(8.0)
		block_kind[c.x][c.y] = B_NONE
		block_nodes.erase(c)
		# разрушение заметное: вспышка, кольцо, препятствие «подпрыгивает» и лопается
		var col: Color = BLOCKS[kind].fx if BLOCKS.has(kind) else Color.WHITE
		_glow_flash(center, col.lerp(Color.WHITE, 0.5), CELL * (2.6 if big else 1.6), 0.25)
		_pop_ring(center, col.lerp(Color.WHITE, 0.3))
		if not big:
			shake.emit(2.5)
		if n:
			n.z_index = 3
			var tw := create_tween()
			tw.tween_property(n, "modulate", Color(2.2, 2.2, 2.2, 1.0), 0.05)
			tw.parallel().tween_property(n, "scale", Vector2(1.28, 1.28), 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(n, "scale", Vector2(0.3, 0.3), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(n, "modulate:a", 0.0, 0.12)
			tw.tween_callback(n.queue_free)
		goal_hit.emit(BLOCKS[kind].goal if BLOCKS.has(kind) else "crate", to_global(center))
		_on_block_destroyed(kind, c)
	elif n:
		# удар без разрушения: белая вспышка и упругое «сплющивание» — видно, что попали
		n.queue_redraw()
		var tw := create_tween()
		tw.tween_property(n, "modulate", Color(1.9, 1.9, 1.9, 1.0), 0.04)
		tw.parallel().tween_property(n, "scale", Vector2(1.22, 0.82), 0.06)
		tw.tween_property(n, "modulate", Color.WHITE, 0.14)
		tw.parallel().tween_property(n, "scale", Vector2(0.94, 1.08), 0.08)
		tw.tween_property(n, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_pop_ring(center, (BLOCKS[kind].fx if BLOCKS.has(kind) else Color.WHITE).lerp(Color.WHITE, 0.4))


## Особое поведение после разрушения: куст и горшок раскидывают газон, скворечник выпускает птиц.
func _on_block_destroyed(kind: int, c: Vector2i) -> void:
	var has_grass_goal := false
	for x in W:
		for y in H:
			if grass_target[x][y]:
				has_grass_goal = true
	if has_grass_goal and (kind == B_BUSH or kind == B_VASE):
		var r := 2 if kind == B_BUSH else 1
		var area := {}
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if r == 2 and absi(dx) == 2 and absi(dy) == 2:
					continue
				area[c + Vector2i(dx, dy)] = true
		_grow_grass(area)
	if kind == B_BIRDHOUSE:
		var pool: Array = []
		for x in W:
			for y in mini(4, H):
				var g := gem_at(Vector2i(x, y))
				if g and g.special == Gem.NONE and not _chained(Vector2i(x, y)):
					pool.append(g)
		pool.shuffle()
		# 3 птицы вылетают из скворечника и садятся на фишки сверху поля — их надо спустить вниз
		var home := cell_pos(c)
		for i in mini(3, pool.size()):
			var g: Node2D = pool[i]
			g.set_special(Gem.ITEM)
			g.bird = true
			var dest: Vector2 = cell_pos(g.cell)
			var mid := (home + dest) / 2.0 + Vector2(randf_range(-80, 80), -CELL * 1.5)
			g.position = home
			g.z_index = 5
			g.scale = Vector2(0.4, 0.4)
			var tw := g.create_tween()
			tw.tween_interval(i * 0.12)
			tw.tween_method(func(t: float) -> void:
				var d := cell_pos(g.cell)  # фишка могла сдвинуться — летим к её текущей клетке
				g.position = home.lerp(mid, t).lerp(mid.lerp(d, t), t)
				g.scale = Vector2.ONE * lerpf(0.4, 1.0, t), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_callback(func() -> void:
				g.z_index = 0
				g.position = cell_pos(g.cell)
				if fx:
					_sparkles(fx.to_local(to_global(g.position)), Color("#7fd0ff"), 5))


func _crack_ice(c: Vector2i) -> void:
	if ice[c.x][c.y] <= 0:
		return
	ice[c.x][c.y] -= 1
	_burst(cell_pos(c), Color("#bfe9ff"), 8)
	var it := Gem.tex("ob_tile_ice")
	if it and fx:
		var cc := fx.to_local(to_global(cell_pos(c)))
		_shatter(it, cc, CELL * 0.95, 6 if ice[c.x][c.y] <= 0 else 3, 0.8)
		_glow_flash(cc, Color(0.75, 0.95, 1.0), CELL * 1.4, 0.2)
		Sfx.play("glass", randf_range(1.0, 1.2), -6.0)
	if ice[c.x][c.y] <= 0:
		goal_hit.emit("ice", to_global(cell_pos(c)))
	queue_redraw()
	# корка льда рисуется на верхнем слое — его тоже перерисовать, иначе лёд «висит»
	_overlay.queue_redraw()


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
	_burst(cell_pos(c), Color("#5fbf3a"), 8)
	var vt := Gem.tex("ob_vines")
	if vt and fx:
		_shatter(vt, fx.to_local(to_global(cell_pos(c))), CELL * 0.95, 5, 0.75)
		Sfx.play("wood", randf_range(1.1, 1.3), -8.0)
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
func _clear(initial: Dictionary, grassify: Dictionary = {}, seed_delay: Dictionary = {}) -> void:
	var pending: Array = initial.keys()
	var cleared := {}
	var delay_of := seed_delay.duplicate()  # клетка -> задержка исчезновения (ракета долетает не сразу)
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
		var cdl: float = delay_of.get(c, 0.0)
		if _chained(c):
			# лианы/мёд под целью бабочки или ракеты ломаются, когда удар долетел, а не сразу
			if cdl > 0.05:
				get_tree().create_timer(cdl).timeout.connect(func() -> void:
					_hits.erase(c)
					_break_chain(c))
			else:
				_break_chain(c)
			continue
		cleared[c] = true
		if ice[c.x][c.y] > 0:
			if cdl > 0.05:
				get_tree().create_timer(cdl).timeout.connect(_crack_ice.bind(c))
			else:
				_crack_ice(c)
		if g.is_power():
			var area := _area(g.special, c)
			if g.special == Gem.ROCKET_H or g.special == Gem.ROCKET_V:
				var base_d: float = delay_of.get(c, 0.0)
				for a2 in area:
					var d: float = base_d + Vector2(a2 - c).length() * ROCKET_CELL_TIME
					if not delay_of.has(a2) or d < delay_of[a2]:
						delay_of[a2] = d
			elif g.special == Gem.BOMB or g.special == Gem.PROPELLER:
				# отложенный взрыв (бустеры от шара рвутся по очереди) — его область ждёт тоже
				var bd: float = delay_of.get(c, 0.0)
				if bd > 0.05:
					for a2 in area:
						if not delay_of.has(a2) or bd < delay_of[a2]:
							delay_of[a2] = bd
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
				var bdl: float = delay_of.get(e.cell, 0.0)
				if bdl > 0.05:
					get_tree().create_timer(bdl).timeout.connect(_bomb_fx.bind(e.cell, 1.5))
				else:
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
	# ждём самое позднее событие: и фишки, и препятствия, до которых долетает бабочка/ракета
	var max_dl := 0.0
	for c: Vector2i in delay_of:
		max_dl = maxf(max_dl, float(delay_of[c]))
	for c: Vector2i in cleared:
		var g := gem_at(c)
		if g == null:
			continue
		tiles[c.x][c.y] = null
		var col: int = g.color
		if col >= 0:
			# фишка-цель бабочки/ракеты засчитывается, когда удар долетел, а не в момент нажатия
			var edl: float = delay_of.get(c, 0.0)
			if edl > 0.05:
				get_tree().create_timer(edl).timeout.connect(func() -> void: gem_cleared.emit(col, to_global(cell_pos(c))))
			else:
				gem_cleared.emit(col, to_global(cell_pos(c)))
		if g.has_meta("merged"):
			# фишка уже слилась в бонус — без хлопка
			g.queue_free()
			continue
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
		# хлопок, как в Royal Match: фишка коротко вспыхивает и раздувается, затем быстро сжимается в точку
		# (раньше сплющивалась «ребром» — на поле это выглядело как полоска-блин)
		tw.tween_property(g, "scale", Vector2(1.28, 1.28), 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "modulate", Color(1.8, 1.8, 1.8), 0.07)
		tw.chain().tween_property(g, "scale", Vector2(0.05, 0.05), 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(g, "rotation", randf_range(-0.5, 0.5), 0.11)
		tw.tween_property(g, "modulate", Color(2.2, 2.2, 2.2, 0.0), 0.11).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(g.queue_free)
		last = tw
	if _grass_carry:
		for c2: Vector2i in cleared:
			grassify[c2] = true
		for c2: Vector2i in initial:
			grassify[c2] = true
	# трава под целью бабочки/ракеты вырастает, когда удар долетел
	var now := {}
	for c2: Vector2i in grassify:
		var gdl: float = delay_of.get(c2, 0.0)
		if gdl > 0.05:
			get_tree().create_timer(gdl).timeout.connect(_grow_grass.bind({c2: true}))
		else:
			now[c2] = true
	_grow_grass(now)
	if last:
		# фишки сверху начинают падать сразу, как исчезли эти (раньше пустота висела ~0.25 с)
		await get_tree().create_timer(max_dl + 0.15).timeout


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


func _best_rocket_dir(c: Vector2i) -> int:
	var h := 0
	var v := 0
	for x in W:
		if block_kind[x][c.y] != B_NONE or ice[x][c.y] > 0 or _chained(Vector2i(x, c.y)):
			h += 1
	for y in H:
		if block_kind[c.x][y] != B_NONE or ice[c.x][y] > 0 or _chained(Vector2i(c.x, y)):
			v += 1
	if h == v:
		return Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
	return Gem.ROCKET_H if h > v else Gem.ROCKET_V


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
			elif ice[x][y] > 0:
				score = 45.0
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
		for g in [g1, g2]:
			g.set_special(Gem.NONE)
			g.color = -1
		# радужная цепная молния: из точки обмена разом бегут цепи по фишкам каждого цвета
		var by_col := {}
		for x in W:
			for y in H:
				var c := Vector2i(x, y)
				var g := gem_at(c)
				if g and g != g1 and g != g2 and g.color >= 0:
					if not by_col.has(g.color):
						by_col[g.color] = []
					by_col[g.color].append(c)
		if fx:
			var at_fx := fx.to_local(to_global(cell_pos(at)))
			var gk := get_global_transform().get_scale().x
			_glow_flash(at_fx, Color(1, 1, 1), CELL * 4.0 * gk, 0.5)
			_flipbook("birth", at_fx, CELL * 4.0 * gk, 0.7, Color.WHITE, true, 8)
		var longest := 0.0
		for col in by_col:
			var n: int = by_col[col].size()
			longest = maxf(longest, n * clampf(0.75 / maxf(1.0, n), 0.04, 0.09))
			_chain_lightning(at, by_col[col], col)
		await get_tree().create_timer(longest + 0.25).timeout
		for x in W:
			for y in H:
				area[Vector2i(x, y)] = true
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
		big_hit.emit(2.0)
		# как в Royal Match: цепная молния прыгает по фишкам цвета, каждая от удара превращается в бустер,
		# потом короткая пауза — и бустеры взрываются один за другим по ходу молнии
		var targets: Array = []
		for x in W:
			for y in H:
				var g := gem_at(Vector2i(x, y))
				if g and g != other and g.special == Gem.NONE and g.color == col and not _chained(g.cell):
					targets.append(Vector2i(x, y))
		var order: Array = []
		var turn := func(c: Vector2i) -> void:
			var g := gem_at(c)
			if g == null:
				return
			var k := kind
			if kind == Gem.ROCKET_H or kind == Gem.ROCKET_V:
				k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
			g.set_special(k)
			order.append(c)
			if fx:
				var p := fx.to_local(to_global(cell_pos(c)))
				var gk := get_global_transform().get_scale().x
				_glow_flash(p, Color(1, 1, 0.85), CELL * 1.6 * gk, 0.25)
				_pop_ring(p, Gem.COLORS[col].lightened(0.5))
			g.scale = Vector2(1.6, 1.6)
			g.modulate = Color(2.2, 2.2, 2.2)
			var t := create_tween().set_parallel(true)
			t.tween_property(g, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			t.tween_property(g, "modulate", Color.WHITE, 0.25)
		await _chain_lightning(at, targets, col, turn)
		# напряжённая пауза: бустеры дрожат
		for c: Vector2i in order:
			var g := gem_at(c)
			if g:
				var t := create_tween().set_loops(3)
				t.tween_property(g, "rotation", 0.12, 0.05)
				t.tween_property(g, "rotation", -0.12, 0.05)
				t.chain().tween_property(g, "rotation", 0.0, 0.03)
		await get_tree().create_timer(0.4).timeout
		var seed := {}
		var step := clampf(0.9 / maxf(1.0, order.size()), 0.05, 0.11)
		for i in order.size():
			area[order[i]] = true
			seed[order[i]] = 0.12 + i * step
		area[other.cell] = true
		seed[other.cell] = 0.0
		await _clear(area, {}, seed)
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
		var kinds_at: Array = []
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
					# ракета летит вдоль ряда/столбца, где больше препятствий — и рисуется в ту же сторону
					k = _best_rocket_dir(target)
				kinds_at.append(k)
				for a in _area(k, target):
					area[a] = true
		await get_tree().create_timer(PROPELLER_TIME + 0.1).timeout
		if carried != Gem.PROPELLER:
			for i in targets.size():
				var t: Vector2i = targets[i]
				if carried == Gem.BOMB:
					_bomb_fx(t, 1.0)
				else:
					_rocket_fx(t, kinds_at[i] == Gem.ROCKET_V)
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
func _chain_lightning(start: Vector2i, targets: Array, col: int, on_hit := Callable()) -> void:
	Sfx.play("orb")
	var color: Color = Gem.COLORS[col].lightened(0.45) if col >= 0 else Color("#bfe9ff")
	var left := targets.duplicate()
	var cur := start
	if fx:
		var gk := get_global_transform().get_scale().x
		# радужная вспышка шара (ИИ-видео владельца); если листа нет — прежняя молния
		if _flipbook("orbburst", fx.to_local(to_global(cell_pos(start))), CELL * 5.0 * gk, 1.1, Color.WHITE, false, 9) == null:
			_flipbook("zap", fx.to_local(to_global(cell_pos(start))), CELL * 3.2 * gk, 0.5, Color.WHITE, true, 9)
		_glow_flash(fx.to_local(to_global(cell_pos(start))), color, CELL * 2.5 * gk, 0.35)
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
			_flipbook("zap", fx.to_local(to_global(cell_pos(nxt))), CELL * 1.7 * get_global_transform().get_scale().x, 0.35, color.lerp(Color.WHITE, 0.4), true, 8)
			_sparkles(fx.to_local(to_global(cell_pos(nxt))), color, 2)
		var g := gem_at(nxt)
		if on_hit.is_valid():
			on_hit.call(nxt)
		elif g:
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
				# над клеткой дыра: фишка (и яйцо) пролетает сквозь пустоту сверху
				if inside(up) and hole[up.x][up.y]:
					var sy := up.y
					while sy >= 0 and hole[x][sy]:
						sy -= 1
					var src_up := Vector2i(x, sy)
					if sy >= 0 and _fillable(src_up) and not _chained(src_up):
						if gem_at(src_up) != null:
							_move_gem(src_up, c)
							moved[gem_at(c)] = true
							changed = true
						continue
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
	# небольшой сдвиг старта по столбцам — фишки сыплются «волной», а не одной плитой
	var col_lag: Array[float] = []
	for x in W:
		col_lag.append(rng.randf_range(0.0, 0.03))
	for g: Node2D in moved:
		var target := cell_pos(g.cell)
		var dist := maxf((target - g.position).length() / CELL, 0.0)
		var t := 0.09 + sqrt(dist) * 0.065  # быстрее (было 0.12 + 0.09·√клеток)
		# нижние фишки трогаются чуть раньше верхних — между ними появляется зазор, как у сыплющихся конфет
		var dl := col_lag[g.cell.x] + float(H - 1 - g.cell.y) * 0.012
		longest = maxf(longest, dl + t)
		var k := clampf(dist / 4.0, 0.35, 1.0)
		if g.has_meta("fall_tw"):
			var old: Tween = g.get_meta("fall_tw")
			if old and old.is_valid():
				old.kill()
		var tw := create_tween()
		g.set_meta("fall_tw", tw)
		if dl > 0.0:
			tw.tween_interval(dl)
		tw.tween_property(g, "position", target, t).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		if dist >= 1.5:
			# в полёте чуть вытягивается по вертикали — ощущение скорости
			tw.parallel().tween_property(g, "scale", Vector2(0.93, 1.09), t * 0.6).set_delay(t * 0.25)
		# «желе»: сплющивается при приземлении (сильнее после долгого падения), подскакивает и пружинит
		# приземление мягче (было сплющивание до «блина»): лёгкий отскок, как в Royal Match
		tw.tween_property(g, "scale", Vector2(1.0 + 0.12 * k, 1.0 - 0.12 * k), 0.05)
		tw.tween_property(g, "scale", Vector2(1.0 - 0.05 * k, 1.0 + 0.06 * k), 0.08)
		tw.parallel().tween_property(g, "position:y", target.y - 5.0 * k, 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(g, "scale", Vector2(1.0 + 0.04 * k, 1.0 - 0.04 * k), 0.07)
		tw.parallel().tween_property(g, "position:y", target.y, 0.07).set_ease(Tween.EASE_IN)
		tw.tween_property(g, "scale", Vector2.ONE, 0.07)
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
	shuffled.emit()
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


## Бонусы на старте прилетают на поле снизу (от панели бустеров) по дуге, крутясь, с искрами,
## и «приземляются» в фишку со вспышкой. delay — когда стартует полёт.
func spawn_specials_animated(n: int, kind: int, delay: float) -> void:
	var pool: Array = []
	for x in W:
		for y in H:
			var g := gem_at(Vector2i(x, y))
			if g and g.special == Gem.NONE and not _chained(g.cell) and not g.has_meta("incoming"):
				pool.append(g)
	pool.shuffle()
	for i in mini(n, pool.size()):
		var g: Node2D = pool[i]
		var k := kind
		if k == Gem.ROCKET_H:
			k = Gem.ROCKET_H if rng.randf() < 0.5 else Gem.ROCKET_V
		g.set_meta("incoming", true)
		# фишку могут успеть убрать до срабатывания таймера — проверяем
		get_tree().create_timer(delay + i * 0.15).timeout.connect(func() -> void:
			if is_instance_valid(g):
				_fly_special_in(g, k))


func _fly_special_in(g: Node2D, k: int) -> void:
	if not is_instance_valid(g) or tiles[g.cell.x][g.cell.y] != g or g.special != Gem.NONE:
		# фишку уже собрали — бонус ляжет в любую другую обычную
		var alt: Array = []
		for x in W:
			for y in H:
				var o := gem_at(Vector2i(x, y))
				if o and o.special == Gem.NONE and not _chained(o.cell):
					alt.append(o)
		if alt.is_empty():
			return
		g = alt[rng.randi_range(0, alt.size() - 1)]
	g.remove_meta("incoming")
	if fx == null:
		g.set_special(k)
		return
	var gs := get_global_transform().get_scale()
	var s: Node2D = Gem.new()
	s.color = g.color
	s.size = CELL * 0.9
	s.set_special(k)
	s.z_index = 10
	fx.add_child(s)
	var p2 := fx.to_local(to_global(cell_pos(g.cell)))
	var p0 := p2 + Vector2(0, -CELL * 6.0 * gs.y)
	s.position = p0
	s.scale = gs * 2.6
	s.modulate.a = 0.0
	Sfx.play("swap", 0.7)
	# бонус крупно появляется над полем и с силой падает в свою клетку
	var tw := s.create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(s, "rotation", TAU, 0.45).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(s, "position", p2, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(s, "scale", gs * 1.1, 0.45).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		s.queue_free()
		if not is_instance_valid(g):
			return
		g.set_special(k)
		g.scale = Vector2(1.45, 0.65)
		var pt := g.create_tween()
		pt.tween_property(g, "scale", Vector2(0.85, 1.2), 0.1)
		pt.tween_property(g, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		shake.emit(12.0)
		_glow_flash(p2, Color(1, 0.92, 0.6), CELL * 3.0 * gs.x, 0.35)
		_pop_ring(p2, Color("#fff6b0"))
		_sparkles(p2, Color("#fff6b0"), 10)
		# соседние фишки подпрыгивают от удара
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var nb: Node2D = gem_at(g.cell + d)
			if nb and not nb.has_meta("incoming"):
				var base := cell_pos(nb.cell)
				var bt := nb.create_tween()
				bt.tween_property(nb, "position", base + Vector2(d) * 10.0 + Vector2(0, -8), 0.08).set_ease(Tween.EASE_OUT)
				bt.tween_property(nb, "position", base, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		Sfx.play("bomb", 1.4, -8.0)
		Sfx.play("special"))


## Фишки группы слетаются к клетке будущего бонуса: сжимаются, светлеют, с «втягиванием».
func _merge_into(creations: Array) -> void:
	var any := false
	for cr in creations:
		var target := cell_pos(cr.cell)
		for c: Vector2i in cr.cells:
			var g := gem_at(c)
			if g == null or g.special != Gem.NONE or g.color < 0 or g.has_meta("merged"):
				continue
			g.set_meta("merged", true)
			g.z_index = 3
			any = true
			var tw := create_tween().set_parallel(true)
			if c == cr.cell:
				tw.tween_property(g, "scale", Vector2(1.3, 1.3), 0.2).set_trans(Tween.TRANS_SINE)
				tw.tween_property(g, "modulate", Color(1.8, 1.8, 1.8), 0.2)
			else:
				# чуть отпрянуть назад и рвануть к центру
				var back := g.position + (g.position - target).normalized() * 6.0
				tw.tween_property(g, "position", back, 0.06)
				tw.chain().tween_property(g, "position", target, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
				tw.tween_property(g, "scale", Vector2(0.55, 0.55), 0.16).set_ease(Tween.EASE_IN)
				tw.tween_property(g, "modulate", Color(1.6, 1.6, 1.6, 0.85), 0.16)
	if any:
		await get_tree().create_timer(0.23).timeout


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

# ---------- объёмные эффекты: шарики со светом и тенью, свечение (аддитивно), искры ----------
static var _fx_tex := {}
static var _add_mat: CanvasItemMaterial


static func _additive() -> CanvasItemMaterial:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add_mat


## Процедурные текстуры: sphere — шарик с бликом и тенью (объём), glow — мягкое свечение,
## spark — четырёхлучевая искра, ring — мягкое кольцо ударной волны.
static func fx_tex(kind: String) -> Texture2D:
	if _fx_tex.has(kind):
		return _fx_tex[kind]
	var n := 64 if kind in ["sphere", "spark"] else 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n, n) / 2.0
	for y in n:
		for x in n:
			var p := (Vector2(x, y) + Vector2(0.5, 0.5) - c) / (n / 2.0)
			var d := p.length()
			var col := Color(0, 0, 0, 0)
			match kind:
				"sphere":
					if d < 1.0:
						# освещение сверху-слева: ламберт + блик + тёмный край
						var z := sqrt(maxf(0.0, 1.0 - d * d))
						var nrm := Vector3(p.x, p.y, z)
						var l := Vector3(-0.5, -0.6, 0.62).normalized()
						var diff := clampf(nrm.dot(l), 0.0, 1.0)
						var spec := pow(clampf(nrm.dot((l + Vector3(0, 0, 1)).normalized()), 0.0, 1.0), 28.0)
						var v := 0.38 + 0.62 * diff
						col = Color(v + spec, v + spec, v + spec, clampf((1.0 - d) * 18.0, 0.0, 1.0))
				"glow":
					col = Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 2.2))
				"ring":
					col = Color(1, 1, 1, exp(-pow((d - 0.78) / 0.09, 2.0)) * clampf((1.0 - d) * 8.0, 0.0, 1.0))
				"spark":
					var ax := absf(p.x)
					var ay := absf(p.y)
					var ray := maxf(exp(-ax * 14.0) * (1.0 - ay), exp(-ay * 14.0) * (1.0 - ax))
					col = Color(1, 1, 1, clampf(ray + pow(clampf(1.0 - d, 0.0, 1.0), 3.0), 0.0, 1.0))
			img.set_pixel(x, y, col)
	var t := ImageTexture.create_from_image(img)
	_fx_tex[kind] = t
	return t


## Бюджет эффектов: сколько спрайтов уже летает. Когда взрывов много сразу (финал уровня, комбо),
## мелкие украшения (осколки, капли, искры, огонь следа) пропускаются — главное (вспышки, взрывы)
## остаётся. Раньше в финале одновременно жило 1000+ спрайтов, и игра зависала.
const FX_SOFT := 40    # выше — без осколков и капель
const FX_HARD := 90   # выше — только крупные взрывы


## Заранее загрузить и «показать» видеокарте все текстуры эффектов (почти невидимо, один кадр) —
## иначе первая же ракета/взрыв грузит картинку в момент взрыва, и игра на миг замирает.
static var _warmed := false


func warm_fx() -> void:
	if _warmed or fx == null:
		return
	_warmed = true
	var texs: Array = []
	for n in FLIPBOOKS:
		var path := "res://assets/vfx/%s.png" % n
		if not _fb_tex.has(n):
			_fb_tex[n] = load(path) if ResourceLoader.exists(path) else null
		if _fb_tex[n]:
			texs.append(_fb_tex[n])
	for k in ["sphere", "spark", "glow", "ring"]:
		texs.append(fx_tex(k))
	for n in ["rocket", "bomb", "orb", "propeller"]:
		var t: Texture2D = Gem.tex(n)
		if t:
			texs.append(t)
	for t: Texture2D in texs:
		var sp := Sprite2D.new()
		sp.texture = t
		sp.scale = Vector2(2.0, 2.0) / maxf(t.get_width(), t.get_height())
		sp.modulate = Color(1, 1, 1, 0.01)
		fx.add_child(sp)
		get_tree().create_timer(0.2).timeout.connect(sp.queue_free)


func _fx_load() -> int:
	return fx.get_child_count() if fx else 0


func _fx_sprite(kind: String, at: Vector2, color: Color, px: float, additive := false) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = fx_tex(kind)
	sp.position = at
	sp.modulate = color
	var k := px / sp.texture.get_width()
	sp.scale = Vector2(k, k)
	if additive:
		sp.material = _additive()
	fx.add_child(sp)
	return sp


## Покадровые эффекты (заранее отрисованы tools/gen_vfx.py): имя → [колонки, ряды, кадров].
const FLIPBOOKS := {"boom": [4, 4, 16], "orbburst": [4, 4, 16], "explosion": [6, 4, 24], "fireball": [4, 4, 16], "zap": [4, 3, 12], "pop": [4, 3, 12], "birth": [6, 3, 18], "smoke": [4, 4, 16]}
static var _fb_tex := {}


## Проигрывает покадровый эффект в точке at (координаты слоя fx), размером px, за time секунд.
func _flipbook(name: String, at: Vector2, px: float, time: float, tint := Color.WHITE, additive := false, z := 7) -> Sprite2D:
	if fx == null or not FLIPBOOKS.has(name):
		return null
	if _fx_load() > FX_HARD and name in ["pop", "smoke", "fireball", "zap"]:
		return null
	if not _fb_tex.has(name):
		var path := "res://assets/vfx/%s.png" % name
		_fb_tex[name] = load(path) if ResourceLoader.exists(path) else null
	var tex: Texture2D = _fb_tex[name]
	if tex == null:
		return null
	var info: Array = FLIPBOOKS[name]
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.hframes = info[0]
	sp.vframes = info[1]
	sp.frame = 0
	sp.position = at
	sp.modulate = tint
	sp.z_index = z
	var k := px / (tex.get_width() / float(info[0]))
	sp.scale = Vector2(k, k)
	if additive:
		sp.material = _additive()
	fx.add_child(sp)
	var last: int = info[2] - 1
	var tw := sp.create_tween()
	tw.tween_method(func(v: float) -> void: sp.frame = clampi(int(v), 0, last), 0.0, float(last) + 0.99, time)
	tw.tween_callback(sp.queue_free)
	return sp


## Осколки из самой картинки препятствия: кусочки текстуры разлетаются вверх-в стороны,
## падают под гравитацией, крутятся (с «3D»-сплющиванием) и отбрасывают тень.
func _shatter(tex: Texture2D, at: Vector2, px: float, n: int, power := 1.0) -> void:
	# разлом, как в Royal Match: картинка препятствия раскалывается на клинья (от случайной точки у центра
	# к краям), каждый клин — кусок той же картинки; куски вылетают от центра, кувыркаются, падают и гаснут
	if fx == null or _fx_load() > FX_HARD:
		return
	if _fx_load() > FX_SOFT:
		n = mini(n, 3)
	n = clampi(n, 2, 9)
	var gs := get_global_transform().get_scale().x
	var ts := tex.get_size()
	var k := px * gs / maxf(ts.x, ts.y)
	var ctr := ts / 2.0 + Vector2(randf_range(-0.12, 0.12), randf_range(-0.12, 0.12)) * ts
	# точки на краю картинки по кругу (углы прямоугольника тоже попадают в нужный клин)
	var angs: Array = []
	var a0 := randf() * TAU
	for i in n:
		angs.append(a0 + TAU * (i + randf_range(-0.25, 0.25)) / n)
	angs.sort()
	var edge := func(a: float) -> Vector2:
		var d := Vector2(cos(a), sin(a))
		var tx := INF if absf(d.x) < 0.001 else ((ts.x if d.x > 0 else 0.0) - ctr.x) / d.x
		var ty := INF if absf(d.y) < 0.001 else ((ts.y if d.y > 0 else 0.0) - ctr.y) / d.y
		return ctr + d * minf(tx, ty)
	var corners := [Vector2(0, 0), Vector2(ts.x, 0), Vector2(ts.x, ts.y), Vector2(0, ts.y)]
	for i in n:
		var aa: float = angs[i]
		var ab: float = angs[(i + 1) % n] + (TAU if i == n - 1 else 0.0)
		var poly := PackedVector2Array([ctr, edge.call(aa)])
		for cn: Vector2 in corners:
			var ca := atan2(cn.y - ctr.y, cn.x - ctr.x)
			while ca < aa:
				ca += TAU
			if ca < ab:
				poly.append(cn)
		poly.append(edge.call(ab))
		# порядок углов по углу от центра
		var rest := Array(poly.slice(1))
		rest.sort_custom(func(p1: Vector2, p2: Vector2) -> bool:
			var x1 := atan2(p1.y - ctr.y, p1.x - ctr.x)
			var x2 := atan2(p2.y - ctr.y, p2.x - ctr.x)
			while x1 < aa:
				x1 += TAU
			while x2 < aa:
				x2 += TAU
			return x1 < x2)
		var pts := PackedVector2Array([ctr])
		for q: Vector2 in rest:
			pts.append(q)
		var mid := Vector2.ZERO
		for q: Vector2 in pts:
			mid += q
		mid /= pts.size()
		var pg := Polygon2D.new()
		pg.texture = tex
		var local := PackedVector2Array()
		for q: Vector2 in pts:
			local.append(q - mid)
		pg.polygon = local
		pg.uv = pts
		pg.position = at + (mid - ts / 2.0) * k
		pg.scale = Vector2(k, k)
		pg.z_index = 7
		fx.add_child(pg)
		var start := pg.position
		var out := (mid - ctr).normalized()
		if out == Vector2.ZERO:
			out = Vector2.UP
		var vel := (out * randf_range(220, 380) + Vector2(randf_range(-40, 40), -randf_range(220, 380))) * power * gs
		var spin := randf_range(5.0, 11.0) * (1.0 if out.x >= 0.0 else -1.0)
		var life := randf_range(0.5, 0.7)
		var tw := pg.create_tween()
		tw.tween_method(func(u: float) -> void:
			var tt := u * life
			pg.position = start + vel * tt + Vector2(0, 1700.0 * gs) * tt * tt * 0.5
			pg.rotation = tt * spin
			pg.scale = Vector2(k, k) * (1.0 + 0.15 * sin(u * PI))
			pg.modulate = Color(1, 1, 1, 1.0 - pow(u, 3.0)), 0.0, 1.0, life)
		tw.tween_callback(pg.queue_free)
	# пыль/облачко материала в центре
	if _fx_load() < FX_SOFT:
		var sp := _flipbook("smoke", at, px * gs * 1.25, 0.4, Color(1, 1, 1, 0.75), false, 6)
		if sp:
			sp.rotation = randf() * TAU


## Вспышка-свечение (аддитивная): светлое пятно, расширяется и гаснет.
func _glow_flash(at: Vector2, color: Color, size: float, time := 0.25) -> void:
	if fx == null or _fx_load() > FX_HARD:
		return
	var g := _fx_sprite("glow", at, color, size * 0.5, true)
	g.z_index = 6
	var k0 := g.scale
	var t := g.create_tween().set_parallel(true)
	t.tween_property(g, "scale", k0 * 2.0, time).set_ease(Tween.EASE_OUT)
	t.tween_property(g, "modulate:a", 0.0, time).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(g.queue_free)


## Объёмная капля/осколок: летит по дуге (вверх и падает), к «камере» растёт, у вершины — максимум,
## под ней бежит тень — читается глубина.
func _droplet(at: Vector2, color: Color, size: float, vel: Vector2, life: float) -> void:
	var sh := _fx_sprite("sphere", at, Color(0, 0, 0, 0.32), size * 0.9)
	sh.z_index = 4
	var b := _fx_sprite("sphere", at, color, size)
	b.z_index = 5
	var k := b.scale
	var ks := sh.scale
	var tw := b.create_tween()
	tw.tween_method(func(t: float) -> void:
		var tt := t * life
		var pos := at + vel * tt + Vector2(0, 900.0) * tt * tt * 0.5
		b.position = pos
		var lift := 4.0 * t * (1.0 - t)   # 0 → 1 → 0: «подлёт к камере»
		b.scale = k * (1.0 + 0.5 * lift) * (1.0 - 0.55 * t)
		b.modulate.a = 1.0 - pow(t, 3.0)
		sh.position = pos + Vector2(4, 6 + 18.0 * lift)
		sh.scale = ks * (1.0 - 0.3 * lift) * (1.0 - 0.55 * t)
		sh.modulate.a = 0.32 * (1.0 - t), 0.0, 1.0, life)
	tw.tween_callback(func() -> void:
		b.queue_free()
		sh.queue_free())


func _burst(pos: Vector2, color: Color, amount: int) -> void:
	if fx == null or _fx_load() > FX_SOFT:
		return
	var at := fx.to_local(to_global(pos))
	var n := amount if Save.particles else maxi(2, amount / 3)
	n = mini(n, 14)
	for i in n:
		var ang := randf_range(-PI * 0.95, -PI * 0.05) if i % 3 != 0 else randf() * TAU
		var sp := randf_range(160.0, 360.0)
		_droplet(at, color.lerp(Color.WHITE, randf() * 0.25), randf_range(9.0, 16.0), Vector2(cos(ang), sin(ang)) * sp, randf_range(0.45, 0.65))


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
	var gk := get_global_transform().get_scale().x
	var load := _fx_load()
	if load > FX_HARD:
		_flipbook("pop", at, CELL * 2.0 * gk, 0.36, color.lerp(Color.WHITE, 0.35), true, 6)
		return
	if load > FX_SOFT:
		shards = 0
	_flipbook("pop", at, CELL * 2.0 * gk, 0.36, color.lerp(Color.WHITE, 0.35), true, 6)
	_glow_flash(at, color.lerp(Color.WHITE, 0.35), CELL * 1.1 * gk, 0.2)
	var ring := _fx_sprite("ring", at, color.lerp(Color.WHITE, 0.3), CELL * 0.6, true)
	ring.z_index = 6
	var rk := ring.scale
	ring.scale = rk * 0.35
	var rt := ring.create_tween().set_parallel(true)
	rt.tween_property(ring, "scale", rk * 1.15, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rt.tween_property(ring, "modulate:a", 0.0, 0.24).set_ease(Tween.EASE_IN)
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
		sh.z_index = 5
		# осколок-мини-фишка летит по дуге вверх и падает, крутится «в 3D» (сплющивается по X) и отбрасывает тень
		var shadow := Sprite2D.new()
		shadow.texture = tex
		shadow.modulate = Color(0, 0, 0, 0.3)
		shadow.scale = sh.scale
		shadow.position = at
		shadow.z_index = 4
		fx.add_child(shadow)
		var ang := randf_range(-PI * 0.9, -PI * 0.1)
		var vel := Vector2(cos(ang), sin(ang)) * randf_range(220.0, 380.0)
		var spin := randf_range(10.0, 18.0) * (1.0 if randf() < 0.5 else -1.0)
		var life := randf_range(0.5, 0.65)
		var t := sh.create_tween()
		t.tween_method(func(u: float) -> void:
			var tt := u * life
			var pos := at + vel * tt + Vector2(0, 1000.0) * tt * tt * 0.5
			var lift := 4.0 * u * (1.0 - u)
			var flip := cos(tt * spin)
			sh.position = pos
			sh.scale = Vector2(k * flip, k) * (1.0 + 0.4 * lift) * (1.0 - 0.5 * u)
			sh.modulate = Color(1.0 + 0.4 * (1.0 - absf(flip)), 1.0 + 0.4 * (1.0 - absf(flip)), 1.0 + 0.4 * (1.0 - absf(flip)), 1.0 - pow(u, 3.0))
			shadow.position = pos + Vector2(5, 8 + 22.0 * lift)
			shadow.scale = Vector2(k * flip, k) * (1.0 - 0.5 * u) * 0.9
			shadow.modulate.a = 0.3 * (1.0 - u), 0.0, 1.0, life)
		t.tween_callback(func() -> void:
			sh.queue_free()
			shadow.queue_free())
	_sparkles(at, color.lightened(0.3), 6 if shards > 2 else 3)
	_burst(cell_pos(cell), color.lightened(0.15), 8)


func _sparkles(at: Vector2, color: Color, n: int) -> void:
	if fx == null or _fx_load() > FX_HARD:
		return
	if _fx_load() > FX_SOFT:
		n = mini(n, 2)
	for i in n:
		var st := _fx_sprite("spark", at, color.lerp(Color.WHITE, 0.5), randf_range(26.0, 42.0), true)
		st.z_index = 6
		var k := st.scale
		st.scale = k * 0.2
		var ang := randf() * TAU
		var t := st.create_tween().set_parallel(true)
		t.tween_property(st, "position", at + Vector2(cos(ang), sin(ang)) * CELL * randf_range(0.5, 1.0), 0.45).set_ease(Tween.EASE_OUT)
		t.tween_property(st, "scale", k, 0.12).set_trans(Tween.TRANS_BACK)
		t.tween_property(st, "rotation", randf_range(-1.5, 1.5), 0.45)
		t.tween_property(st, "modulate:a", 0.0, 0.3).set_delay(0.15)
		t.chain().tween_callback(st.queue_free)


## Ракета: две ракеты разлетаются в стороны с огненным следом, по линии бьёт молния.
func _rocket_fx(cell: Vector2i, vertical: bool, delay: float = 0.0) -> void:
	if fx == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	Sfx.play("rocket", 1.0, -3.0)
	var c := cell_pos(cell)
	var tex: Texture2D = Gem.tex("rocket")
	var rgs := get_global_transform().get_scale().x
	_flipbook("fireball", fx.to_local(to_global(c)), CELL * 2.2 * rgs, 0.5)
	var trail_i := [0]
	for sgn in [-1.0, 1.0]:
		var dir := Vector2(0, sgn) if vertical else Vector2(sgn, 0)
		var start := fx.to_local(to_global(c))
		var end := fx.to_local(to_global(c + dir * (H if vertical else W) * CELL))
		var r := Sprite2D.new()
		r.texture = tex
		var k := CELL * 1.75 / maxf(tex.get_width(), tex.get_height()) if tex else 1.0
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
		# огненный луч: от места взрыва до головы ракеты, светится (аддитивно), потом гаснет
		var beam := _fx_sprite("glow", start, Color(1.0, 0.62, 0.2), 10.0, true)
		var core := _fx_sprite("glow", start, Color(1.0, 0.95, 0.7), 10.0, true)
		beam.z_index = 4
		core.z_index = 4
		var gw := float(beam.texture.get_width())
		var thick := CELL * 0.55 * get_global_transform().get_scale().x
		for bs in [beam, core]:
			bs.rotation = PI / 2.0 if vertical else 0.0
		var tw := r.create_tween()
		tw.tween_method(func(t: float) -> void:
			var prev: Vector2 = r.position
			r.position = start.lerp(end, t)
			var len := start.distance_to(r.position) * 2.0 + thick
			beam.position = (start + r.position) / 2.0
			core.position = beam.position
			beam.scale = Vector2(len / gw, thick / gw)
			core.scale = Vector2(len / gw, thick * 0.35 / gw)
			# огненный след сразу за соплом + дымок дальше
			# при большой нагрузке (много взрывов разом) след ракеты упрощается — иначе кадр «проседает»
			var busy_fx := _fx_load() > FX_SOFT
			if r.position.distance_to(prev) > 0.0 and _fx_load() < FX_HARD:
				_flame(r.position - dir * 62.0)
			if not busy_fx and r.position.distance_to(last[0]) > 26.0:
				last[0] = r.position
				trail_i[0] += 1
				if trail_i[0] % 3 == 0:
					_flipbook("fireball", r.position - dir * 64.0, CELL * 1.1 * rgs, 0.42, Color.WHITE, false, 5)
				else:
					_puff(r.position - dir * 60.0)
				_sparkles(r.position - dir * 30.0, Color("#ffd27a"), 1), 0.0, 1.0, ROCKET_CELL_TIME * cells)
		tw.tween_callback(r.queue_free)
		for bs in [beam, core]:
			var ft: Tween = bs.create_tween()
			ft.tween_interval(ROCKET_CELL_TIME * cells)
			ft.tween_property(bs, "modulate:a", 0.0, 0.3)
			ft.parallel().tween_property(bs, "scale:y", 0.0, 0.3)
			ft.tween_callback(bs.queue_free)


## Язычок пламени за ракетой: жёлто-оранжевый, быстро гаснет и краснеет.
func _flame(at: Vector2) -> void:
	if _fx_load() > FX_SOFT:
		return
	var pos := at + Vector2(randf_range(-5, 5), randf_range(-5, 5))
	var g := _fx_sprite("glow", pos, Color(1.0, 0.5, 0.15), randf_range(40, 56), true)
	g.z_index = 4
	var core := _fx_sprite("sphere", pos, Color(1.0, 0.9, 0.5), randf_range(12, 18))
	core.z_index = 5
	for sp in [g, core]:
		var k: Vector2 = sp.scale
		var t: Tween = sp.create_tween().set_parallel(true)
		t.tween_property(sp, "scale", k * 0.2, 0.22).set_ease(Tween.EASE_IN)
		t.tween_property(sp, "modulate", Color(1, 0.3, 0.2, 0.0), 0.22)
		t.chain().tween_callback(sp.queue_free)


func _puff(at: Vector2) -> void:
	if _fx_load() > FX_SOFT:
		return
	# клуб мультяшного дыма (покадровый, объёмный)
	# след ракеты — тёплая искристая вспышка, а не серый дым
	var sp := _flipbook("smoke", at + Vector2(randf_range(-4, 4), randf_range(-4, 4)), randf_range(40, 50), 0.3, Color(1.0, 0.85, 0.55, 0.55), false, 4)
	if sp:
		sp.rotation = randf() * TAU


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
	var w := width * 3.2
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
	shake.emit(minf(10.0 * power, 14.0))
	Sfx.play("bomb", 1.0 / sqrt(power))
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
	var gsc := get_global_transform().get_scale().x
	# объёмный мультяшный взрыв (покадровый) + свечение
	# взрыв из ИИ-видео владельца (если листа нет — прежний)
	# взрыв короче и меньше — раньше жёлтое облако на полсекунды закрывало пол-поля
	if _flipbook("boom", at, CELL * 2.7 * power * gsc, 0.45) == null:
		_flipbook("explosion", at, CELL * 3.0 * power * gsc, 0.45)
	_glow_flash(at, Color(1.0, 0.75, 0.35), CELL * 3.0 * power * gsc, 0.3)
	var flash := Node2D.new()
	flash.position = at
	flash.z_index = 5
	var rad := CELL * 1.6 * power
	flash.draw.connect(func() -> void:
		flash.draw_arc(Vector2.ZERO, rad, 0, TAU, 48, Color(1, 0.85, 0.5, 0.7), 10.0, true))
	# вторая, широкая волна-кольцо, догоняет первую
	var wave := Node2D.new()
	wave.position = at
	wave.z_index = 5
	wave.draw.connect(func() -> void:
		wave.draw_arc(Vector2.ZERO, rad * 1.5, 0, TAU, 64, Color(1, 0.9, 0.6, 0.85), 12.0, true))
	wave.scale = Vector2(0.3, 0.3)
	fx.add_child(wave)
	var wt := wave.create_tween().set_parallel(true)
	wt.tween_property(wave, "scale", Vector2.ONE, 0.4).set_delay(0.06).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	wt.tween_property(wave, "modulate:a", 0.0, 0.4).set_delay(0.12)
	wt.chain().tween_callback(wave.queue_free)
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
	## Бабочка: вспорхнула (0.3 с) → летит плавной дугой к цели (1.0 с) → зависла и нырнула (0.2 с).
	## Удар по цели — ровно в конце нырка: delay + PROPELLER_TIME (совпадает с delay_of цели).
	if fx == null:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var gs := get_global_transform().get_scale().x
	var p: Node2D = Gem.new()
	p.color = col
	p.size = CELL * 1.1
	p.z_index = 9
	fx.add_child(p)
	p.set_special(Gem.PROPELLER)
	p.scale = Vector2.ONE * gs
	var a := fx.to_local(to_global(cell_pos(from)))
	var b := fx.to_local(to_global(cell_pos(to)))
	p.position = a
	Sfx.play("butterfly")
	_glow_flash(a, Color(1, 0.9, 0.5), CELL * 1.2 * gs, 0.25)
	var lift := a + Vector2(0, -CELL * 0.8 * gs)
	var hover := b + Vector2(0, -CELL * 0.9 * gs)
	var c1 := lift + Vector2((b.x - a.x) * 0.15, -CELL * 1.4 * gs)
	var c2 := hover + Vector2((a.x - b.x) * 0.15, -CELL * 1.2 * gs)
	var last := [lift]
	# тень на поле бежит под бабочкой
	var shadow := _fx_sprite("sphere", a, Color(0, 0, 0, 0.0), CELL * 0.55 * gs)
	shadow.z_index = 5
	var tw := p.create_tween()
	# 1. вспорхнула: присела и подпрыгнула вверх
	tw.tween_property(p, "scale", Vector2(1.15, 0.85) * gs, 0.05)
	tw.tween_property(p, "scale", Vector2(1.2, 1.2) * gs, 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(p, "position", lift, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. полёт: плавная дуга, наклон по ходу, искорки, тень на поле
	tw.tween_method(func(t: float) -> void:
		var q := lift.bezier_interpolate(c1, c2, hover, t)
		var dx := q.x - p.position.x
		p.rotation = lerpf(p.rotation, clampf(dx * 0.02, -0.28, 0.28), 0.12)
		p.position = q + Vector2(0, sin(t * TAU * 3.0) * 4.0)
		var ground := a.lerp(b, t)
		shadow.position = ground
		shadow.modulate.a = 0.22
		if q.distance_to(last[0]) > 22.0:
			last[0] = q
			_sparkles(q, Color("#ffcf5a"), 1), 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# 3. зависла над целью и нырнула в неё
	tw.tween_property(p, "rotation", 0.0, 0.04)
	tw.parallel().tween_property(p, "scale", Vector2(1.35, 1.35) * gs, 0.04)
	tw.tween_property(p, "position", b, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(p, "scale", Vector2(0.7, 0.7) * gs, 0.09)
	# по просьбе владельца без взрыва: бабочка просто ныряет в цель, фишка лопается обычным образом
	tw.tween_callback(shadow.queue_free)
	tw.tween_property(p, "modulate:a", 0.0, 0.08)
	tw.tween_callback(p.queue_free)


func _pop_ring(at: Vector2, color: Color) -> void:
	if fx == null:
		return
	var ring := _fx_sprite("ring", at, color.lerp(Color.WHITE, 0.4), CELL * 1.2, true)
	ring.z_index = 6
	var k := ring.scale
	ring.scale = k * 0.3
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", k * 1.3, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "modulate:a", 0.0, 0.28).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(ring.queue_free)
	_glow_flash(at, color.lerp(Color.WHITE, 0.5), CELL * 1.1, 0.2)


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
