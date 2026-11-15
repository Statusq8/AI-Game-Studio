extends Node2D
## Одна фишка на поле. Рисуется кодом (заглушка до ИИ-графики): у каждого цвета своя форма,
## чтобы фишки различались и без цвета.

enum { NONE, ROCKET_H, ROCKET_V, BOMB, ORB, PROPELLER, ITEM }

const COLORS := [
	Color("#e8202a"),  # 0 красное сердце
	Color("#1f7fe8"),  # 1 синяя капля
	Color("#4cc81e"),  # 2 зелёный листик
	Color("#ffc61a"),  # 3 жёлтая звезда
	Color("#b02ee0"),  # 4 фиолетовый цветок
	Color("#ff7a12"),  # 5 оранжевая лапка
]

## ИИ-графика (решение №26). Нет файла — рисуем заглушку кодом.
static var _tex := {}

var color := 0
var special := NONE
var cell := Vector2i.ZERO
var size := 80.0
var _t := 0.0
var _shine := randf() * 6.0
var bird := false  # предмет-птица из скворечника (рисуется птичкой, а не яйцом)


func _ready() -> void:
	set_process(true)


## Особая фишка, которая взрывается (предмет «спустить вниз» — не взрывается).
func is_power() -> bool:
	return special != NONE and special != ITEM


func set_special(kind: int) -> void:
	special = kind
	if kind == ORB or kind == ITEM:
		color = -1
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## Мягкое пульсирующее свечение под особой фишкой — чтобы её было видно на поле.
func _halo(col: Color, k: float) -> void:
	var p := 0.5 + 0.5 * sin(_t * 4.0 + _shine)
	for i in 5:
		var rr := size * (0.3 + i * 0.065) * k * (1.0 + p * 0.1)
		draw_circle(Vector2.ZERO, rr, Color(col, (0.3 - i * 0.05) * (0.65 + 0.35 * p)))
	# мягкие лучи, медленно вращаются
	for i in 6:
		var a := _t * 0.6 + i * TAU / 6.0
		var d := Vector2(cos(a), sin(a))
		var tip := d * size * 0.62 * k
		var w := d.orthogonal() * size * 0.07
		draw_colored_polygon(PackedVector2Array([w, tip, -w]), Color(col, 0.18 * (0.6 + 0.4 * p)))


## Искорки-блёстки, мигающие вокруг фишки.
func _glints(col: Color, n: int) -> void:
	for i in n:
		var ph := fmod(_t * 0.9 + i * 0.37 + _shine, 1.0)
		var a := i * 2.1 + floorf(_t * 0.9 + i * 0.37 + _shine) * 1.7
		var p := Vector2(cos(a), sin(a)) * size * (0.38 + 0.12 * ph)
		var r := size * 0.07 * sin(ph * PI)
		draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(col, 0.9), 2.0, true)
		draw_line(p - Vector2(0, r), p + Vector2(0, r), Color(col, 0.9), 2.0, true)


static func tex(name: String) -> Texture2D:
	if not _tex.has(name):
		var path := "res://assets/art/%s.png" % name
		_tex[name] = load(path) if ResourceLoader.exists(path) else null
	return _tex[name]


func _draw_tex(t: Texture2D, box: float, angle: float = 0.0, k: float = 1.0) -> void:
	var sz := t.get_size()
	var s := box * k / maxf(sz.x, sz.y)
	draw_set_transform(Vector2.ZERO, angle, Vector2(s, s))
	draw_texture(t, -sz / 2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	var r := size * 0.41
	var box := size * 0.94
	var pulse := 1.0 + sin(_t * 5.0) * 0.05
	var t: Texture2D = null
	match special:
		NONE:
			if color < 0:
				# «использованная» особая фишка (шар после свапа) — рисуем шар, а не красный квадрат-заглушку
				t = tex("orb")
				if t:
					_draw_tex(t, box, _t * 3.0, 1.0 + sin(_t * 20.0) * 0.06)
				return
			t = tex("gem_%d" % color)
			if t:
				# мягкая тень под кристаллом + редкий блеск
				draw_set_transform(Vector2(size * 0.03, size * 0.38), 0.0, Vector2(1.0, 0.32))
				draw_circle(Vector2.ZERO, size * 0.36, Color(0.05, 0.12, 0.25, 0.28))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				_draw_tex(t, box)
				return
		ROCKET_H, ROCKET_V:
			t = tex("rocket")
			if t:
				# ракета «на взводе»: подрагивает, из сопла бьёт мерцающее пламя, вокруг тёплое свечение
				var vert := special == ROCKET_V
				var ang := -PI / 2.0 if vert else 0.0
				var fwd := Vector2(0, -1) if vert else Vector2(1, 0)
				var jit := Vector2(sin(_t * 47.0), cos(_t * 39.0)) * size * 0.012
				var noz := -fwd * size * 0.52 + jit
				var fl := 0.75 + 0.25 * sin(_t * 31.0) + 0.1 * sin(_t * 53.0)
				var side := fwd.orthogonal()
				for L in [[1.0, Color(1.0, 0.45, 0.1, 0.55)], [0.62, Color(1.0, 0.8, 0.25, 0.85)], [0.32, Color(1, 1, 0.85, 0.95)]]:
					var ln: float = size * 0.34 * fl * L[0]
					var wd: float = size * 0.13 * L[0]
					draw_colored_polygon(PackedVector2Array([noz + side * wd, noz - fwd * ln, noz - side * wd]), L[1])
					draw_circle(noz, wd, L[1])
				draw_set_transform(jit, 0.0, Vector2.ONE)
				var sz := t.get_size()
				var k := box * 1.5 * pulse / maxf(sz.x, sz.y)
				draw_set_transform(jit, ang, Vector2(k, k))
				draw_texture(t, -sz / 2)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				return
		BOMB, ORB, PROPELLER:
			t = tex({BOMB: "bomb", ORB: "orb", PROPELLER: "propeller"}[special])
			if t:
				if special == PROPELLER:
					# бабочка порхает: серия взмахов, пауза, снова взмахи; покачивается вверх-вниз и чуть наклоняется
					var sz := t.get_size()
					var k := box * 1.12 / maxf(sz.x, sz.y)
					var ph := fmod(_t + _shine, 2.2)
					var flap := 0.5 + 0.5 * cos(_t * 16.0) if ph < 1.1 else 0.92
					var bob := sin(_t * 3.0 + _shine) * size * 0.06
					draw_set_transform(Vector2(0, bob), sin(_t * 2.3) * 0.12, Vector2(k * (0.35 + 0.65 * flap), k))
					draw_texture(t, -sz / 2)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					_glints(Color(1.0, 0.9, 0.5), 3)
				elif special == BOMB:
					pulse = 1.0 + maxf(0.0, sin(_t * 7.0)) * 0.09
					# у бомбы фитиль справа сверху — сдвигаем картинку, чтобы шар стоял по центру клетки, и делаем крупнее
					draw_set_transform(Vector2(-size * 0.05, size * 0.06), 0.0, Vector2.ONE)
					_draw_tex(t, box * 1.25, 0.0, pulse)
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
					# искрящий фитиль
					var fz := Vector2(size * 0.33, -size * 0.43)
					var fl := 0.7 + 0.3 * sin(_t * 30.0)
					draw_circle(fz, size * 0.13 * fl, Color(1, 0.6, 0.1, 0.55))
					draw_circle(fz, size * 0.07 * fl, Color(1, 0.95, 0.4, 0.95))
					for k in 4:
						var a := _t * 9.0 + k * TAU / 4.0
						draw_line(fz, fz + Vector2(cos(a), sin(a)) * size * 0.16 * fl, Color(1, 1, 0.7, 0.9), 2.0, true)
				else:
					# шар: медленно вращается, переливается радужным ореолом, вокруг кружат искры
					var hue := fmod(_t * 0.25, 1.0)
					_draw_tex(t, box * 1.08, _t * 0.9, pulse)
					for i in 3:
						var a := _t * 2.4 + i * TAU / 3.0
						var p := Vector2(cos(a), sin(a) * 0.55) * size * 0.5
						var c := Color.from_hsv(fmod(hue + i / 3.0, 1.0), 0.5, 1.0)
						draw_circle(p, size * 0.07, Color(c, 0.35))
						draw_circle(p, size * 0.035, Color(1, 1, 1, 0.95))
				return
	match special:
		NONE:
			_draw_gem(color, r)
		ROCKET_H, ROCKET_V:
			_draw_rocket(r, special == ROCKET_V)
		BOMB:
			_draw_bomb(r)
		ORB:
			_draw_orb(r)
		PROPELLER:
			_draw_propeller(r)
		ITEM:
			_draw_item(r)


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
	draw_set_transform(Vector2.ZERO, -PI / 2.0 if vertical else 0.0)
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


func _draw_propeller(r: float) -> void:
	var base: Color = COLORS[clampi(color, 0, COLORS.size() - 1)]
	draw_circle(Vector2(0, r * 0.12), r * 0.8, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, r * 0.78, base.darkened(0.25))
	draw_circle(Vector2.ZERO, r * 0.66, base)
	var a0 := _t * 9.0
	for i in 3:
		var a := a0 + TAU * i / 3.0
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x)
		var blade := PackedVector2Array([
			dir * r * 0.12 + side * r * 0.1,
			dir * r * 0.95 + side * r * 0.2,
			dir * r * 1.02,
			dir * r * 0.95 - side * r * 0.08,
			dir * r * 0.12 - side * r * 0.08,
		])
		draw_colored_polygon(blade, Color("#ffe14d"))
		draw_polyline(PackedVector2Array([blade[0], blade[1], blade[2], blade[3], blade[4], blade[0]]), Color("#b8860b"), 2.0, true)
	draw_circle(Vector2.ZERO, r * 0.2, Color("#ff4f63"))
	draw_circle(Vector2(-r * 0.06, -r * 0.07), r * 0.07, Color(1, 1, 1, 0.8))


## Предмет, который нужно спустить на нижний ряд (заглушка: золотое яйцо).
## Птичка из скворечника: круглая голубая, белое брюшко, хохолок, машет крылом.
func _draw_bird(r: float) -> void:
	var gl := 0.5 + 0.5 * sin(_t * 4.0)
	draw_circle(Vector2.ZERO, size * 0.48, Color(0.6, 0.85, 1.0, 0.18 + 0.15 * gl))
	var hop := -absf(sin(_t * 5.0)) * r * 0.08
	var o := Vector2(0, hop)
	draw_set_transform(o + Vector2(0, r * 0.95), 0.0, Vector2(1.0, 0.25))
	draw_circle(Vector2.ZERO, r * 0.6, Color(0, 0, 0, 0.25))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# хвост
	draw_colored_polygon(PackedVector2Array([o + Vector2(r * 0.55, r * 0.15), o + Vector2(r * 1.05, -r * 0.2), o + Vector2(r * 0.95, r * 0.35)]), Color("#2f7fd6"))
	# тело
	draw_circle(o, r * 0.82, Color("#1f5fb0"))
	draw_circle(o + Vector2(0, -r * 0.04), r * 0.76, Color("#3f9cf0"))
	draw_circle(o + Vector2(-r * 0.2, -r * 0.3), r * 0.42, Color("#7cc4ff"))
	# брюшко
	draw_set_transform(o + Vector2(-r * 0.05, r * 0.3), 0.0, Vector2(1.0, 0.75))
	draw_circle(Vector2.ZERO, r * 0.48, Color("#fff4e0"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# крыло машет
	var flap := sin(_t * 14.0) * 0.5
	draw_set_transform(o + Vector2(r * 0.25, r * 0.05), flap, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(-r * 0.15, -r * 0.2), Vector2(r * 0.5, -r * 0.05), Vector2(r * 0.2, r * 0.35), Vector2(-r * 0.2, r * 0.2)]), Color("#1f5fb0"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# хохолок
	draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.15, -r * 0.7), o + Vector2(-r * 0.05, -r * 1.05), o + Vector2(r * 0.1, -r * 0.72)]), Color("#1f5fb0"))
	# глаза и клюв
	for ex in [-0.32, 0.08]:
		draw_circle(o + Vector2(ex * r, -r * 0.18), r * 0.16, Color.WHITE)
		draw_circle(o + Vector2(ex * r + r * 0.03, -r * 0.16), r * 0.09, Color("#1b1b2a"))
		draw_circle(o + Vector2(ex * r + r * 0.06, -r * 0.21), r * 0.035, Color.WHITE)
	draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 0.2, r * 0.02), o + Vector2(-r * 0.6, r * 0.1), o + Vector2(-r * 0.2, r * 0.2)]), Color("#ff9a1a"))


func _draw_item(r: float) -> void:
	if bird:
		_draw_bird(r)
		return
	var t := tex("item_egg")
	if t:
		var gl := 0.5 + 0.5 * sin(_t * 4.0)
		draw_circle(Vector2.ZERO, size * 0.48, Color(1, 0.85, 0.3, 0.22 + 0.18 * gl))
		draw_circle(Vector2.ZERO, size * 0.38, Color(1, 0.95, 0.6, 0.25 + 0.15 * gl))
		_draw_tex(t, r * 2.3)
		return
	var egg := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		var v := Vector2(cos(a) * 0.72, sin(a) * 0.92) * r
		if v.y < 0:
			v.x *= 1.0 - 0.25 * (-v.y / r)
		egg.append(v)
	draw_colored_polygon(_scaled(egg, 1.0, Vector2(0, r * 0.1)), Color(0, 0, 0, 0.22))
	draw_colored_polygon(egg, Color("#c98a12"))
	draw_colored_polygon(_scaled(egg, 0.86, Vector2(0, -r * 0.04)), Color("#ffd23f"))
	for d in [Vector2(-0.25, 0.1), Vector2(0.22, 0.32), Vector2(0.12, -0.3), Vector2(-0.1, 0.55)]:
		draw_circle(d * r, r * 0.09, Color("#fff3b0"))
	draw_circle(Vector2(-r * 0.25, -r * 0.4), r * 0.12, Color(1, 1, 1, 0.85))
