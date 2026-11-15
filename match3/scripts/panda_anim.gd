extends Control
## Живая панда из кадров ИИ-видео (assets/anim/panda_<имя>/NN.webp, 12 кадров/с).
## idle крутится всегда; play("happy"|"win"|...) проигрывает реакцию один раз и возвращается к idle.
## Кадры обрезаны по общей рамке (meta.json: холст cw×ch и смещение ox, oy) — меньше памяти на телефоне.
## Холст кадра в позе покоя: панда занимает нижние 2/3 высоты, сверху запас под прыжки.
## Загрузка: idle — сразу, остальные анимации подгружаются по одному кадру за кадр игры (без рывков),
## и каждый кадр один раз «показывается» видеокарте заранее — чтобы первый показ не тормозил.

const FPS := 12.0
const NAMES := ["idle", "wave", "happy", "wow", "nervous", "yawn", "think", "build", "win", "sad"]
## важные реакции (победа, проигрыш) не перебиваются мелкими (комбо, «вау», привет)
const PRIORITY := {"idle": 0, "wave": 1, "wow": 1, "yawn": 1, "think": 1, "build": 2, "happy": 2, "nervous": 2, "sad": 3, "win": 3}
static var _cache := {}
static var _meta := {}
static var _queue: Array = []  # [имя, номер кадра] для фоновой подгрузки
static var _queued := false

var _anim := "idle"
var _frame := 0
var _t := 0.0
var _warm: Array = []  # кадры, которые нужно один раз нарисовать невидимо (прогрев видеокарты)


static func available() -> bool:
	return ResourceLoader.exists("res://assets/anim/panda_idle/00.webp")


static func _path(name: String, i: int) -> String:
	return "res://assets/anim/panda_%s/%02d.webp" % [name, i]


static func meta(name: String) -> Dictionary:
	if not _meta.has(name):
		var m := {"cw": 320.0, "ch": 384.0, "ox": 0.0, "oy": 0.0}
		var f := FileAccess.open("res://assets/anim/panda_%s/meta.json" % name, FileAccess.READ)
		if f:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary:
				m = j
		_meta[name] = m
	return _meta[name]


## Все кадры анимации (idle загружается сразу при первом обращении).
static func frames(name: String) -> Array:
	if not _cache.has(name):
		var arr: Array = []
		var i := 0
		while ResourceLoader.exists(_path(name, i)):
			arr.append(load(_path(name, i)))
			i += 1
		_cache[name] = arr
	return _cache[name]


static func ready_anim(name: String) -> bool:
	if not _cache.has(name) or (_cache[name] as Array).is_empty():
		return false
	for q: Array in _queue:
		if q[0] == name:
			return false
	return true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	frames("idle")
	meta("idle")
	# фоновая подгрузка остальных анимаций по кадру за кадр игры
	if not _queued:
		_queued = true
		for n in NAMES:
			if n == "idle" or _cache.has(n):
				continue
			meta(n)
			_cache[n] = []
			var i := 0
			while ResourceLoader.exists(_path(n, i)):
				_queue.append([n, i])
				i += 1


func play(name: String) -> void:
	if not ready_anim(name):
		return
	if name == _anim and name != "idle" and _frame < 4:
		return
	if name != "idle" and int(PRIORITY.get(name, 1)) < int(PRIORITY.get(_anim, 0)):
		return
	_anim = name
	_frame = 0
	_t = 0.0
	queue_redraw()


func current() -> String:
	return _anim


func _draw() -> void:
	var f := frames(_anim)
	if f.is_empty():
		return
	var tex: Texture2D = f[mini(_frame, f.size() - 1)]
	var m := meta(_anim)
	var cw := float(m.cw)
	var ch := float(m.ch)
	var k := minf(size.x / cw, size.y / ch)
	var org := Vector2((size.x - cw * k) / 2.0, size.y - ch * k)
	draw_texture_rect(tex, Rect2(org + Vector2(float(m.ox), float(m.oy)) * k, tex.get_size() * k), false)
	# прогрев: новые кадры рисуются почти прозрачными один раз — видеокарта получает их заранее
	for w: Texture2D in _warm:
		draw_texture_rect(w, Rect2(Vector2.ZERO, Vector2(2, 2)), false, Color(1, 1, 1, 0.01))
	_warm.clear()


func _process(delta: float) -> void:
	if not _queue.is_empty() and is_visible_in_tree():
		var q: Array = _queue.pop_front()
		var tex: Texture2D = load(_path(q[0], q[1]))
		(_cache[q[0]] as Array).append(tex)
		_warm.append(tex)
		queue_redraw()
	if not is_visible_in_tree():
		return
	_t += delta
	if _t < 1.0 / FPS:
		return
	_t -= 1.0 / FPS
	if _t > 1.0 / FPS:
		_t = 0.0  # после долгой паузы не «догоняем» кадрами
	var f := frames(_anim)
	_frame += 1
	if _frame >= f.size():
		_anim = "idle"
		_frame = 0
	queue_redraw()
