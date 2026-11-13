extends Node2D
## Одна фишка на поле. Рисуется кодом (заглушка до ИИ-графики): у каждого цвета своя форма,
## чтобы фишки различались и без цвета.

enum { NONE, ROCKET_H, ROCKET_V, BOMB, ORB }

const COLORS := [
	Color("#ff4f63"),  # 0 красный — рубин
	Color("#38a6ff"),  # 1 синий — капля
	Color("#3fd46a"),  # 2 зелёный — шестигранник
	Color("#ffcf2e"),  # 3 жёлтый — звезда
	Color("#b06bff"),  # 4 фиолетовый — ромб
	Color("#ff9a2a"),  # 5 оранжевый — квадрат
]

var color := 0
var special := NONE
var cell := Vector2i.ZERO
var size := 80.0
var _t := 0.0


func _ready() -> void:
	set_process(special != NONE)


func set_special(kind: int) -> void:
	special = kind
	if kind == ORB:
		color = -1
	set_process(kind != NONE)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var r := size * 0.41
	match special:
		NONE:
			_draw_gem(color, r)
		ROCKET_H, ROCKET_V:
			_draw_rocket(r, special == ROCKET_V)
		BOMB:
			_draw_bomb(r)
		ORB:
			_draw_orb(r)


static func shape(c: int, r: float) -> PackedVector2Array:
	var p := PackedVector2Array()
	match c:
		0:  # огранённый рубин (восьмиугольник)
			for i in 8:
				var a := TAU * (i + 0.5) / 8.0
				p.append(Vector2(cos(a), sin(a)) * r * 0.98)
		1:  # капля
			for i in 28:
				var a := TAU * i / 28.0
				var v := Vector2(cos(a), sin(a)) * r * 0.9
				var top := maxf(0.0, -sin(a))
				v.y -= top * top * r * 0.32
				v.y += r * 0.1
				v.x *= 1.0 - top * 0.35
				p.append(v)
		2:  # шестигранник
			for i in 6:
				var a := TAU * i / 6.0 + PI / 6.0
				p.append(Vector2(cos(a), sin(a)) * r)
		3:  # звезда
			for i in 10:
				var a := TAU * i / 10.0 - PI / 2.0
				var rr := r * (1.05 if i % 2 == 0 else 0.52)
				p.append(Vector2(cos(a), sin(a)) * rr + Vector2(0, r * 0.06))
		4:  # ромб
			p = PackedVector2Array([Vector2(0, -r * 1.05), Vector2(r * 0.86, 0), Vector2(0, r * 1.05), Vector2(-r * 0.86, 0)])
		_:  # квадрат со скруглением
			var s := r * 0.8
			for i in 24:
				var a := TAU * i / 24.0
				var v := Vector2(cos(a), sin(a))
				v = Vector2(signf(v.x) * pow(absf(v.x), 0.35), signf(v.y) * pow(absf(v.y), 0.35))
				p.append(v * s)
	return p


static func _scaled(p: PackedVector2Array, k: float, offset: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in p:
		out.append(v * k + offset)
	return out


func _draw_gem(c: int, r: float) -> void:
	var base: Color = COLORS[clampi(c, 0, COLORS.size() - 1)]
	var p := shape(c, r)
	draw_colored_polygon(_scaled(p, 1.0, Vector2(0, r * 0.1)), Color(0, 0, 0, 0.22))
	draw_colored_polygon(p, base.darkened(0.28))
	draw_colored_polygon(_scaled(p, 0.86, Vector2(0, -r * 0.05)), base)
	draw_colored_polygon(_scaled(p, 0.5, Vector2(0, -r * 0.14)), base.lightened(0.35))
	var closed := p.duplicate()
	closed.append(p[0])
	draw_polyline(closed, base.darkened(0.5), 2.5, true)
	draw_circle(Vector2(-r * 0.3, -r * 0.38), r * 0.13, Color(1, 1, 1, 0.85))
	draw_circle(Vector2(-r * 0.12, -r * 0.5), r * 0.06, Color(1, 1, 1, 0.7))


func _draw_rocket(r: float, vertical: bool) -> void:
	draw_set_transform(Vector2.ZERO, PI / 2.0 if vertical else 0.0)
	var base: Color = COLORS[clampi(color, 0, COLORS.size() - 1)]
	var pulse := 1.0 + sin(_t * 6.0) * 0.04
	var w := r * 1.0 * pulse
	var h := r * 0.5
	var body := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		var v := Vector2(cos(a), sin(a))
		v = Vector2(signf(v.x) * pow(absf(v.x), 0.5), signf(v.y) * pow(absf(v.y), 0.5))
		body.append(Vector2(v.x * w, v.y * h))
	draw_colored_polygon(_scaled(body, 1.0, Vector2(0, r * 0.1)), Color(0, 0, 0, 0.22))
	draw_colored_polygon(body, base.darkened(0.3))
	draw_colored_polygon(_scaled(body, 0.82, Vector2.ZERO), base)
	draw_rect(Rect2(-w * 0.15, -h * 0.82, w * 0.3, h * 1.64), Color(1, 1, 1, 0.9))
	for s in [-1.0, 1.0]:
		var tip := Vector2(s * w * 1.18, 0)
		var tri := PackedVector2Array([tip, Vector2(s * w * 0.72, -h * 0.75), Vector2(s * w * 0.72, h * 0.75)])
		draw_colored_polygon(tri, Color(1, 1, 1))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), base.darkened(0.5), 2.0, true)
	draw_circle(Vector2(-w * 0.45, -h * 0.4), r * 0.1, Color(1, 1, 1, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0)


func _draw_bomb(r: float) -> void:
	var base: Color = COLORS[clampi(color, 0, COLORS.size() - 1)]
	var pulse := 1.0 + sin(_t * 5.0) * 0.05
	draw_circle(Vector2(0, r * 0.12), r * 0.88, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, r * 0.88 * pulse, Color("#2a2f4a"))
	draw_arc(Vector2.ZERO, r * 0.62 * pulse, 0, TAU, 32, base, r * 0.28, true)
	draw_circle(Vector2.ZERO, r * 0.42, Color("#3a4166"))
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.16, Color(1, 1, 1, 0.75))
	# фитиль с искрой
	draw_line(Vector2(r * 0.45, -r * 0.65), Vector2(r * 0.7, -r * 0.95), Color("#c9a36b"), 4.0, true)
	var spark := 0.12 + absf(sin(_t * 14.0)) * 0.1
	draw_circle(Vector2(r * 0.72, -r * 0.98), r * spark * 1.6, Color(1, 0.6, 0.1, 0.6))
	draw_circle(Vector2(r * 0.72, -r * 0.98), r * spark, Color(1, 0.95, 0.5))


func _draw_orb(r: float) -> void:
	draw_circle(Vector2(0, r * 0.12), r * 0.92, Color(0, 0, 0, 0.25))
	var n := COLORS.size()
	for i in n:
		var a0 := TAU * i / n + _t * 1.6
		var pts := PackedVector2Array([Vector2.ZERO])
		for k in 7:
			var a := a0 + TAU / n * k / 6.0
			pts.append(Vector2(cos(a), sin(a)) * r * 0.92)
		draw_colored_polygon(pts, COLORS[i])
	draw_circle(Vector2.ZERO, r * 0.5, Color(1, 1, 1, 0.55))
	draw_circle(Vector2.ZERO, r * 0.3, Color(1, 1, 1, 0.95))
	draw_arc(Vector2.ZERO, r * 0.92, 0, TAU, 40, Color(1, 1, 1, 0.9), 3.0, true)
	draw_circle(Vector2(-r * 0.35, -r * 0.4), r * 0.12, Color(1, 1, 1, 0.9))
