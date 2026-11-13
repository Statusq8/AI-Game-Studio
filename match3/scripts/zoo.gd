extends Control
## Вид текущей зоны зоопарка на главном экране: фон + предметы ремонта.
## Готовые предметы рисуются (заглушки до ИИ-графики), недостроенные — место со звёздами и молотком.

signal spot_pressed(index: int)

const Zones := preload("res://scripts/zones.gd")

var zone := 0
var done := {}  # index -> вариант дизайна
var _t := 0.0
var _pop := {}  # index -> 0..1 анимация появления


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(z: int, built: Dictionary) -> void:
	zone = z
	done = built
	queue_redraw()


func spot_center(i: int) -> Vector2:
	var p: Vector2 = Zones.ZONES[zone].tasks[i].pos
	# правый край занят боковыми кнопками — сжимаем места в левые ~80% экрана
	return Vector2((0.06 + p.x * 0.72) * size.x, p.y * size.y)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var tasks: Array = Zones.ZONES[zone].tasks
		for i in tasks.size():
			if not done.has(i) and (event.position - spot_center(i)).length() < 60:
				spot_pressed.emit(i)
				accept_event()
				return


## Анимация постройки: предмет падает сверху с отскоком.
func build(i: int, variant: int) -> void:
	done[i] = variant
	_pop[i] = 0.0
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _pop[i] = v, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _pop.erase(i))


func _draw() -> void:
	var tasks: Array = Zones.ZONES[zone].tasks
	for i in tasks.size():
		var c := spot_center(i)
		var task: Dictionary = tasks[i]
		if done.has(i):
			var k: float = _pop.get(i, 1.0)
			var off := Vector2(0, -(1.0 - k) * 220.0)
			draw_item(self, task.kind, Zones.DESIGNS[int(done[i])], c + off, 0.6 + 0.4 * k, int(done[i]))
		else:
			var pulse := 1.0 + sin(_t * 3.0 + i) * 0.06
			draw_circle(c + Vector2(0, 6), 46 * pulse, Color(0, 0, 0, 0.18))
			draw_circle(c, 46 * pulse, Color(1, 1, 1, 0.82))
			draw_arc(c, 46 * pulse, 0, TAU, 40, Color("#3fb85a"), 5.0, true)
			_draw_hammer(c + Vector2(0, -6))
			_draw_star_cost(c + Vector2(0, 30), int(task.cost))


func _draw_hammer(c: Vector2) -> void:
	draw_set_transform(c, -0.6, Vector2.ONE)
	draw_rect(Rect2(-4, -6, 8, 34), Color("#9a6337"))
	draw_rect(Rect2(-16, -18, 32, 14), Color("#7a8494"))
	draw_rect(Rect2(-16, -18, 32, 4), Color("#a9b3c2"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_star_cost(c: Vector2, cost: int) -> void:
	draw_rect(Rect2(c - Vector2(26, 13), Vector2(52, 26)), Color("#2b2350"))
	draw_star(self, c + Vector2(-10, 0), 10.0)
	var f: Font = ThemeDB.fallback_font
	draw_string(f, c + Vector2(4, 8), str(cost), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)


static func draw_star(ci: CanvasItem, c: Vector2, r: float) -> void:
	var p := PackedVector2Array()
	for i in 10:
		var a := TAU * i / 10.0 - PI / 2.0
		p.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	ci.draw_colored_polygon(p, Color("#ffcf2e"))
	var closed := p.duplicate()
	closed.append(p[0])
	ci.draw_polyline(closed, Color("#c98a12"), 2.0, true)


## Предметы ремонта (заглушки): k — масштаб.
static var _tex := {}


## ИИ-картинка предмета (assets/art/item_<kind>_<вариант>.png), если есть.
static func item_tex(kind: String, variant: int) -> Texture2D:
	var key := "%s_%d" % [kind, variant]
	if not _tex.has(key):
		var path := "res://assets/art/item_%s.png" % key
		_tex[key] = load(path) if ResourceLoader.exists(path) else null
	return _tex[key]


const ITEM_SIZE := {"gate": 240.0, "booth": 190.0, "fence": 200.0, "lamp": 170.0, "flowers": 150.0}


static func draw_item(ci: CanvasItem, kind: String, col: Color, o: Vector2, k: float, variant: int = -1) -> void:
	if variant < 0:
		variant = maxi(0, Zones.DESIGNS.find(col))
	var t := item_tex(kind, variant)
	if t:
		var sz := t.get_size()
		var box: float = ITEM_SIZE.get(kind, 180.0) * k
		var sc := box / maxf(sz.x, sz.y)
		ci.draw_set_transform(o + Vector2(0, -sz.y * sc * 0.35), 0.0, Vector2(sc, sc))
		ci.draw_texture(t, -sz / 2)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var dark := col.darkened(0.35)
	var light := col.lightened(0.3)
	var sh := Color(0, 0, 0, 0.2)
	ci.draw_circle(o + Vector2(0, 48) * k, 40 * k, sh)
	match kind:
		"gate":
			ci.draw_rect(Rect2(o + Vector2(-70, -60) * k, Vector2(22, 110) * k), dark)
			ci.draw_rect(Rect2(o + Vector2(48, -60) * k, Vector2(22, 110) * k), dark)
			ci.draw_arc(o + Vector2(0, -50) * k, 60 * k, PI, TAU, 24, col, 22 * k)
			ci.draw_circle(o + Vector2(0, -95) * k, 18 * k, Color("#ffd23f"))
			ci.draw_circle(o + Vector2(0, -95) * k, 8 * k, Color("#9a6337"))
		"booth":
			ci.draw_rect(Rect2(o + Vector2(-45, -30) * k, Vector2(90, 80) * k), col)
			ci.draw_rect(Rect2(o + Vector2(-30, -15) * k, Vector2(60, 30) * k), Color("#bfe6ff"))
			ci.draw_colored_polygon(PackedVector2Array([o + Vector2(-58, -30) * k, o + Vector2(58, -30) * k, o + Vector2(0, -75) * k]), dark)
			ci.draw_rect(Rect2(o + Vector2(-50, 20) * k, Vector2(100, 10) * k), light)
		"fence":
			for i in 5:
				var x := -80 + i * 40
				ci.draw_rect(Rect2(o + Vector2(x - 6, -40) * k, Vector2(12, 80) * k), col)
				ci.draw_colored_polygon(PackedVector2Array([o + Vector2(x - 6, -40) * k, o + Vector2(x + 6, -40) * k, o + Vector2(x, -52) * k]), col)
			ci.draw_rect(Rect2(o + Vector2(-90, -20) * k, Vector2(180, 10) * k), dark)
			ci.draw_rect(Rect2(o + Vector2(-90, 15) * k, Vector2(180, 10) * k), dark)
		"lamp":
			for dx in [-30, 30]:
				ci.draw_rect(Rect2(o + Vector2(dx - 4, -50) * k, Vector2(8, 100) * k), dark)
				ci.draw_circle(o + Vector2(dx, -58) * k, 16 * k, Color("#fff3b0"))
				ci.draw_circle(o + Vector2(dx, -58) * k, 26 * k, Color(1, 0.95, 0.6, 0.3))
				ci.draw_rect(Rect2(o + Vector2(dx - 14, -76) * k, Vector2(28, 8) * k), col)
		"flowers":
			ci.draw_circle(o + Vector2(0, 20) * k, 55 * k, Color("#6b4a2b"))
			for i in 7:
				var a := TAU * i / 7.0
				var p: Vector2 = o + Vector2(cos(a) * 34, sin(a) * 18 + 10) * k
				ci.draw_circle(p, 13 * k, col if i % 2 == 0 else Color("#ffd23f"))
				ci.draw_circle(p, 5 * k, Color.WHITE)
		"tree":
			ci.draw_rect(Rect2(o + Vector2(-8, -10) * k, Vector2(16, 60) * k), Color("#8a5a2b"))
			for p in [Vector2(0, -50), Vector2(-28, -30), Vector2(28, -30), Vector2(0, -20)]:
				ci.draw_circle(o + p * k, 32 * k, Color("#3fb85a"))
			ci.draw_circle(o + Vector2(-10, -60) * k, 10 * k, light)
		"house":
			ci.draw_rect(Rect2(o + Vector2(-60, -30) * k, Vector2(120, 80) * k), Color("#f3e3c3"))
			ci.draw_colored_polygon(PackedVector2Array([o + Vector2(-75, -30) * k, o + Vector2(75, -30) * k, o + Vector2(0, -90) * k]), col)
			ci.draw_rect(Rect2(o + Vector2(-15, 5) * k, Vector2(30, 45) * k), dark)
			ci.draw_rect(Rect2(o + Vector2(25, -15) * k, Vector2(25, 22) * k), Color("#bfe6ff"))
		"bridge":
			ci.draw_arc(o + Vector2(0, 40) * k, 80 * k, PI * 1.15, PI * 1.85, 20, col, 18 * k)
			for i in 6:
				var a := PI * 1.15 + PI * 0.7 * i / 5.0
				var p: Vector2 = o + (Vector2(0, 40) + Vector2(cos(a), sin(a)) * 80) * k
				ci.draw_line(p, p + Vector2(0, -26) * k, dark, 5 * k)
		"pond":
			ci.draw_circle(o + Vector2(0, 10) * k, 70 * k, col.darkened(0.2))
			ci.draw_circle(o + Vector2(0, 8) * k, 62 * k, Color("#5fc4ff"))
			ci.draw_circle(o + Vector2(-20, 0) * k, 14 * k, Color("#3fb85a"))
			ci.draw_circle(o + Vector2(25, 20) * k, 11 * k, Color("#3fb85a"))
			ci.draw_arc(o + Vector2(10, -10) * k, 30 * k, PI * 1.1, PI * 1.6, 10, Color(1, 1, 1, 0.7), 4 * k)
		"bench":
			ci.draw_rect(Rect2(o + Vector2(-60, -20) * k, Vector2(120, 14) * k), col)
			ci.draw_rect(Rect2(o + Vector2(-60, 0) * k, Vector2(120, 14) * k), col)
			for dx in [-50, 42]:
				ci.draw_rect(Rect2(o + Vector2(dx, 14) * k, Vector2(8, 30) * k), dark)
		"sign":
			ci.draw_rect(Rect2(o + Vector2(-6, -10) * k, Vector2(12, 60) * k), dark)
			ci.draw_rect(Rect2(o + Vector2(-55, -60) * k, Vector2(110, 55) * k), col)
			ci.draw_rect(Rect2(o + Vector2(-48, -53) * k, Vector2(96, 41) * k), light)
			ci.draw_circle(o + Vector2(0, -32) * k, 12 * k, dark)
		"fountain":
			ci.draw_circle(o + Vector2(0, 20) * k, 60 * k, col)
			ci.draw_circle(o + Vector2(0, 18) * k, 50 * k, Color("#5fc4ff"))
			ci.draw_rect(Rect2(o + Vector2(-8, -40) * k, Vector2(16, 60) * k), col.lightened(0.2))
			for dx in [-1, 1]:
				ci.draw_arc(o + Vector2(dx * 22, -40) * k, 22 * k, PI if dx < 0 else -PI * 0.0 + PI, TAU if dx < 0 else PI * 2.0, 12, Color(0.8, 0.95, 1, 0.9), 4 * k)
			ci.draw_circle(o + Vector2(0, -48) * k, 10 * k, Color(0.8, 0.95, 1, 0.9))
