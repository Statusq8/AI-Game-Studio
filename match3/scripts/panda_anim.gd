extends Control
## Живая панда из кадров ИИ-видео (assets/anim/panda_<имя>/NN.webp, 10 кадров/с).
## idle крутится всегда; play("happy"|"win"|"sad"|"nervous") проигрывает реакцию один раз и
## плавно (короткой «перетечкой» кадров) возвращается к idle.
## Холст кадра 320x384: в позе покоя панда занимает нижние 2/3 высоты, сверху запас под прыжки.

const FPS := 10.0
const NAMES := ["idle", "happy", "win", "sad", "nervous"]
static var _cache := {}

var _cur: TextureRect
var _prev: TextureRect
var _anim := "idle"
var _frame := 0
var _t := 0.0
var _fade := 0.0


static func available() -> bool:
	return ResourceLoader.exists("res://assets/anim/panda_idle/00.webp")


static func frames(name: String) -> Array:
	if not _cache.has(name):
		var arr: Array = []
		var i := 0
		while true:
			var p := "res://assets/anim/panda_%s/%02d.webp" % [name, i]
			if not ResourceLoader.exists(p):
				break
			arr.append(load(p))
			i += 1
		_cache[name] = arr
	return _cache[name]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prev = _rect()
	_cur = _rect()
	_prev.modulate.a = 0.0
	_show()
	# реакции подгружаем заранее, чтобы при первом показе не было рывка
	for n in NAMES:
		frames(n)


func _rect() -> TextureRect:
	var r := TextureRect.new()
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func play(name: String) -> void:
	if frames(name).is_empty():
		return
	if name == _anim and name != "idle" and _frame < 4:
		return
	_switch(name)


func current() -> String:
	return _anim


func _switch(name: String) -> void:
	_prev.texture = _cur.texture
	_prev.modulate.a = 1.0
	_fade = 0.15
	_anim = name
	_frame = 0
	_t = 0.0
	_show()


func _show() -> void:
	var f := frames(_anim)
	if f.is_empty():
		return
	_cur.texture = f[mini(_frame, f.size() - 1)]


func _process(delta: float) -> void:
	if _fade > 0.0:
		_fade = maxf(0.0, _fade - delta)
		_prev.modulate.a = _fade / 0.15
	_t += delta
	if _t < 1.0 / FPS:
		return
	_t -= 1.0 / FPS
	var f := frames(_anim)
	_frame += 1
	if _frame >= f.size():
		if _anim == "idle":
			_frame = 0
		else:
			_switch("idle")
			return
	_show()
