extends Control
## Экраны игры: главный (кнопка «Уровень N»), уровень (поле, ходы, цели), окна победы / поражения / паузы.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Levels := preload("res://scripts/levels.gd")
const Board := preload("res://scripts/board.gd")
const Gem := preload("res://scripts/gem.gd")
const Zones := preload("res://scripts/zones.gd")
const Zoo := preload("res://scripts/zoo.gd")
const PandaAnim := preload("res://scripts/panda_anim.gd")

const VERSION := "2.29.0"
const WIN_COINS := 50
## Ежедневный подарок на 7 дней (предложение Claude, правится): монеты — число, бустеры — название: количество.
const DAILY := [{"coins": 100}, {"hammer": 2}, {"coins": 200}, {"pre_rocket": 1, "pre_bomb": 1},
	{"coins": 300}, {"rockets": 2, "shuffle": 1}, {"coins": 500, "pre_orb": 1, "pre_bomb": 1, "hammer": 1}]
## Сундук за победы: сколько побед нужно и что в нём.
const CHEST_WINS := 8
const CHEST_COINS := 150
const COINS_PER_MOVE := 5
const EXTRA_MOVES := 5
const EXTRA_MOVES_PRICE := 300
const BOOSTER_PRICE := 250
const IN_BOOSTERS := [["hammer", "Молот"], ["rockets", "Ракеты"], ["shuffle", "Микс"]]
const PRE_BOOSTERS := [["pre_rocket", "Ракета", 1], ["pre_bomb", "Бомба", 3], ["pre_orb", "Шар", 4]]

var _bg: TextureRect
var _home: Control
var _level_screen: Control
var _overlay: Control
var _fx: Node2D
var _home_level_btn: Button
var _zoo: Control
var _map: TextureRect
var _repair_btn: Button
var _repair_mode := false
var _zone_box: Control
var _zone_title: Label
var _zone_bar: ProgressBar
var _tabbar: HBoxContainer
var _stars_label: Label
var _avatar_node: Control
var _coin_labels: Array[Label] = []
var _hearts_label: Label
var _hearts_timer: Label
var _ui_tick := 0.0

var _board: Board
var _home_panda: Control
var _panda: Control
var _portrait_node: Control
var _booster_bar: HBoxContainer
var _booster_btns := {}
var _aiming := ""
var _fly_reward := {}  # награда победы — прилетит в счётчики на главном экране
var _pre_selected := {}
var _board_frame: Control
var _board_clip: Control
var _pause_btn: Control
var _bar_pause: Button
var _lv_goal_card: Control
var _lv_moves_card: Control
var _bands: Control
var _moves_label: Label
var _level_label: Label
var _goals_box: HBoxContainer
var _goal_views: Array = []  # [{goal, label, icon, check}]

var _level: Dictionary
var _moves := 0
var _state := "idle"  # idle | play | bonus | done
var _shake := 0.0
var _flying := 0
var _bot := false


func _ready() -> void:
	# прежний игрок, уже отремонтировавший последнюю из старых 5 зон, переходит в новую зону
	if Save.zone + 1 < Zones.ZONES.size() and Save.built.size() >= Zones.ZONES[Save.zone].tasks.size():
		Save.zone += 1
		Save.built = {}
		Save.store()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.build()
	_build_background()
	_build_home()
	_build_level_screen()
	_fx = Node2D.new()
	_fx.z_index = 10
	add_child(_fx)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.z_index = 20  # окна поверх препятствий и эффектов поля
	add_child(_overlay)
	Save.changed.connect(_refresh_coins)
	_show_home()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_run_shots.call_deferred(arg.trim_prefix("--shots="))
		elif arg.begins_with("--winshot="):
			_run_winshot.call_deferred(arg.trim_prefix("--winshot="))
		elif arg == "--finaletest":
			_run_finaletest.call_deferred()
		elif arg == "--fxdemo":
			_run_fxdemo.call_deferred()
		elif arg == "--inputtest":
			_run_input_test.call_deferred()
		elif arg.begins_with("--bot"):
			var spec := arg.trim_prefix("--bot=") if "=" in arg else "10"
			if ":" in spec:
				_run_bot.call_deferred(int(spec.split(":")[1]), int(spec.split(":")[0]))
			else:
				_run_bot.call_deferred(int(spec))


func _process(delta: float) -> void:
	_ui_tick -= delta
	if _ui_tick <= 0.0:
		_ui_tick = 1.0
		_refresh_hearts()
	if _board_frame == null:
		return
	if _aiming != "" and _booster_btns.has(_aiming):
		var ab: Button = _booster_btns[_aiming]
		ab.set_meta("glow", 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0))
		ab.queue_redraw()
	if _shake > 0.0:
		_board_frame.position = _board_rest() + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, 40.0 * delta)
	elif _board_frame.position != _board_rest():
		_board_frame.position = _board_rest()


# ---------- построение интерфейса ----------

func _build_background() -> void:
	var g := Gradient.new()
	g.set_color(0, Color("#4fc3ff"))
	g.set_color(1, Color("#b57bff"))
	g.add_point(0.55, Color("#7f9dff"))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	tex.width = 8
	tex.height = 256
	_bg = TextureRect.new()
	_bg.texture = load("res://assets/art/bg_zoo.webp") if ResourceLoader.exists("res://assets/art/bg_zoo.webp") else tex
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	# мягкие «облака»-круги для глубины
	var deco := Control.new()
	deco.set_anchors_preset(Control.PRESET_FULL_RECT)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.draw.connect(func() -> void:
		var s := deco.size
		deco.draw_circle(Vector2(s.x * 0.1, s.y * 0.12), 160, Color(1, 1, 1, 0.08))
		deco.draw_circle(Vector2(s.x * 0.95, s.y * 0.3), 220, Color(1, 1, 1, 0.07))
		deco.draw_circle(Vector2(s.x * 0.2, s.y * 0.85), 260, Color(1, 1, 1, 0.06))
		deco.draw_circle(Vector2(s.x * 0.85, s.y * 0.95), 180, Color(1, 1, 1, 0.08)))
	deco.resized.connect(deco.queue_redraw)
	add_child(deco)


func _coin_pill() -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.draw.connect(func() -> void:
		var c := icon.size / 2
		if Zoo.draw_art(icon, "ui_coin", c, 58.0):
			return
		icon.draw_circle(c, 19, Color("#c98a12"))
		icon.draw_circle(c, 15, Color("#ffd23f"))
		icon.draw_circle(c + Vector2(-5, -5), 4, Color(1, 1, 1, 0.8)))
	row.add_child(icon)
	var l := Label.new()
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 30)
	row.add_child(l)
	_coin_labels.append(l)
	row.add_child(_plus_button())
	return pill


func _hearts_pill() -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.draw.connect(func() -> void: draw_heart(icon, icon.size / 2, 23.0))
	row.add_child(icon)
	_hearts_label = Label.new()
	_hearts_label.theme_type_variation = "TitleLabel"
	_hearts_label.add_theme_font_size_override("font_size", 30)
	row.add_child(_hearts_label)
	_hearts_timer = Label.new()
	_hearts_timer.add_theme_font_size_override("font_size", 22)
	row.add_child(_hearts_timer)
	row.add_child(_plus_button())
	return pill


## Зелёный кружок «+» на плашке валюты — ведёт в магазин.
func _plus_button() -> Button:
	var b := Button.new()
	b.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(34, 34)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.draw.connect(func() -> void:
		var c := b.size / 2
		if Zoo.draw_art(b, "ui2_plus", c, 38.0):
			return
		b.draw_circle(c + Vector2(0, 2), 16, Color("#1e5a14"))
		b.draw_circle(c, 16, Color("#3fc25a"))
		b.draw_circle(c + Vector2(0, -4), 10, Color("#6fe07f"))
		b.draw_rect(Rect2(c - Vector2(9, 2.5), Vector2(18, 5)), Color.WHITE)
		b.draw_rect(Rect2(c - Vector2(2.5, 9), Vector2(5, 18)), Color.WHITE))
	b.pressed.connect(_show_shop)
	return b


static func draw_heart(ci: CanvasItem, c: Vector2, r: float) -> void:
	if Zoo.draw_art(ci, "ui_heart", c, r * 2.4):
		return
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * r / 16.0)
	ci.draw_colored_polygon(pts, Color("#c2183a"))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.8 + Vector2(0, -1))
	ci.draw_colored_polygon(inner, Color("#ff4f63"))
	ci.draw_circle(c + Vector2(-r * 0.4, -r * 0.35), r * 0.15, Color(1, 1, 1, 0.8))


func _refresh_hearts() -> void:
	if _hearts_label == null:
		return
	Save.update_hearts()
	_hearts_label.text = str(Save.hearts)
	var sec := Save.seconds_to_heart()
	_hearts_timer.text = "" if sec <= 0 else "%d:%02d" % [sec / 60, sec % 60]


func _build_home() -> void:
	_home = Control.new()
	_home.set_anchors_preset(Control.PRESET_FULL_RECT)
	_home.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_home)

	# карта всего зоопарка (вид сверху под углом); ремонт — отдельный экран
	_map = TextureRect.new()
	_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var map_path := "res://assets/art/zoo_map.webp"
	_map.texture = load(map_path) if ResourceLoader.exists(map_path) else null
	_home.add_child(_map)

	# текущая зона зоопарка с местами ремонта
	_zoo = Zoo.new()
	_zoo.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zoo.spot_pressed.connect(_on_spot)
	_home.add_child(_zoo)

	# верхняя панель: аватар + уровень игрока, жизни, монеты, звёзды
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 14)
	top.add_theme_constant_override("margin_top", 28)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	if Zoo.art("ui2_plate"):
		# верхняя панель 1:1 по референсу (screen_01_home): точные места и размеры
		_build_topbar_ref()
		top.add_theme_constant_override("margin_top", 128)
	else:
		row.add_child(_avatar())
		row.add_child(_hearts_pill())
		row.add_child(_coin_pill())
		row.add_child(_stars_pill())
	_zone_title = Label.new()
	_zone_title.theme_type_variation = "TitleLabel"
	_zone_title.add_theme_font_size_override("font_size", 30)
	_zone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_zone_title)
	_zone_bar = ProgressBar.new()
	_zone_bar.custom_minimum_size = Vector2(0, 22)
	_zone_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#3fb85a")
	fill.set_corner_radius_all(11)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.35)
	back.set_corner_radius_all(11)
	_zone_bar.add_theme_stylebox_override("fill", fill)
	_zone_bar.add_theme_stylebox_override("background", back)
	var bar_box := CenterContainer.new()
	bar_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_bar.custom_minimum_size = Vector2(360, 22)
	bar_box.add_child(_zone_bar)
	col.add_child(bar_box)
	_zone_box = bar_box

	# кнопки сбоку: почта, друзья, рейтинг, настройки
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", int(3.0 * REF_K))
	side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side.position = Vector2(-110, -40)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(side)
	for b in [["mail", _show_soon.bind("Почта")], ["friends", _show_soon.bind("Друзья")], ["rating", _show_soon.bind("Рейтинг")], ["settings", _show_settings]]:
		var btn := _icon_button(b[0], 124.0 * REF_K, Color("#9b5cff"))
		btn.pressed.connect(b[1])
		side.add_child(btn)
	_rside = side

	# слева: ежедневный подарок и сундук за победы
	var lside := VBoxContainer.new()
	lside.add_theme_constant_override("separation", int(6.0 * REF_K))
	lside.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(lside)
	_gift_btn = _icon_button("gift", 154.0 * REF_K, Color("#ff5a8a"))
	_gift_btn.pressed.connect(_show_daily)
	lside.add_child(_gift_btn)
	_chest_btn = _icon_button("chest", 158.0 * REF_K, Color("#2f9be0"))
	_chest_btn.pressed.connect(_show_chest)
	lside.add_child(_chest_btn)
	_lside = lside
	_every_frame(_gift_btn)
	_every_frame(_chest_btn)

	# панда в левом нижнем углу
	_home_panda = _make_panda(250.0)
	_home.add_child(_home_panda)

	# кнопки уровня и ремонта над нижней панелью
	_home_level_btn = Button.new()
	_home_level_btn.theme_type_variation = "GreenButton"
	_home_level_btn.custom_minimum_size = Vector2(330, 110)
	_home_level_btn.add_theme_font_size_override("font_size", 40)
	if Zoo.art("ui2_play"):
		# кнопка уровня из арта владельца: номер в кремовой плашке, стрелка «▶»
		_home_level_btn.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			_home_level_btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		_home_level_btn.custom_minimum_size = Vector2(445.0 * REF_K, 445.0 * REF_K * 322.0 / 617.0)
		_home_level_btn.draw.connect(func() -> void:
			var b := _home_level_btn
			var hard: bool = b.get_meta("hard", false)
			var pr := b.is_pressed()
			var tex := Zoo.art("ui2_play_down" if pr else "ui2_play")
			var sz := tex.get_size()
			var k := b.size.x / sz.x
			var r := Rect2(Vector2(0, b.size.y - sz.y * k), sz * k)
			b.draw_texture_rect(tex, r, false, Color(1.35, 0.62, 0.55) if hard else Color.WHITE)
			# номер уровня — в левой кремовой плашке (≈ 20–42% ширины, 47–68% высоты картинки)
			var font: Font = UiTheme.title_font()
			var t := str(Save.level)
			var fs := 70 if t.length() <= 2 else (60 if t.length() == 3 else 48)
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var pc := r.position + Vector2(r.size.x * 0.33, r.size.y * 0.58)
			var tp := pc + Vector2(-ts.x / 2, fs * 0.36)
			b.draw_string_outline(font, tp + Vector2(0, 4), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, Color(0, 0, 0, 0.35))
			b.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#2a2a2a") if not hard else Color("#5a0a04"))
			b.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
		_home_level_btn.button_down.connect(_home_level_btn.queue_redraw)
		_home_level_btn.button_up.connect(_home_level_btn.queue_redraw)
	_home_level_btn.pressed.connect(_try_play)
	_home.add_child(_home_level_btn)
	var pulse := _home_level_btn.create_tween().set_loops()
	_home_level_btn.pivot_offset = _home_level_btn.custom_minimum_size / 2
	pulse.tween_property(_home_level_btn, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_home_level_btn, "modulate", Color(1.15, 1.15, 1.05), 0.45)
	pulse.tween_property(_home_level_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_home_level_btn, "modulate", Color.WHITE, 0.45)
	pulse.tween_interval(0.4)

	_repair_btn = _icon_button("repair", 180.0 * REF_K, Color("#ff9a2a"))
	_repair_btn.pressed.connect(func() -> void: _transition(_set_repair_mode.bind(not _repair_mode)))
	_home.add_child(_repair_btn)

	# нижняя панель: 5 вкладок
	_tabbar = HBoxContainer.new()
	_tabbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabbar.add_theme_constant_override("separation", 0)
	# деревянная полоса под вкладками
	_tabbar.draw.connect(func() -> void:
		var r := Rect2(Vector2(-6, 0), Vector2(_tabbar.size.x + 12, _tabbar.size.y + 30))
		var bt := Zoo.art("ui2_bar")
		if bt:
			_tabbar.draw_texture_rect(bt, r, false)
		else:
			_tile(_tabbar, r, Color("#8a5326"), 24))
	_home.add_child(_tabbar)
	for t in [["Магазин", _show_shop, "ui2_tab_shop"], ["События", _show_soon.bind("События"), "ui2_tab_events"],
			["Главная", func() -> void: _clear_overlay(), "ui2_paw"], ["Команда", _show_soon.bind("Команда"), "ui2_tab_team"],
			["Коллекция", _show_collection, "ui2_tab_collection"]]:
		var btn := Button.new()
		var on: bool = t[0] == "Главная"
		var art: String = t[2]
		var name: String = t[0]
		btn.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		btn.custom_minimum_size = Vector2(156 if on else 138, 166)
		btn.tooltip_text = name
		btn.draw.connect(func() -> void:
			# плитки по референсу: обычная 155×125 (центр на 93 px ниже верха дерева), выбранная 185×190 (центр на 101)
			var pr := btn.is_pressed()
			var ks := 0.93 if pr else 1.0
			var c := Vector2(btn.size.x / 2, (88.0 if on else 100.0) * REF_K)
			if on:
				var tsz := Vector2(192, 200) * REF_K * ks
				var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 400.0)
				btn.draw_circle(c, tsz.x * 0.55 + p * 4, Color(1, 0.9, 0.4, 0.16))
				var to := Zoo.art("ui2_tab_on")
				if to:
					btn.draw_texture_rect(to, Rect2(c - tsz / 2, tsz), false)
				Zoo.draw_art(btn, art, c + Vector2(0, -10) * REF_K, 150.0 * REF_K * ks)
			else:
				var tsz := Vector2(165, 150) * REF_K * ks
				var tt := Zoo.art(art)
				if tt:
					btn.draw_texture_rect(tt, Rect2(c - tsz / 2, tsz), false)
			pass)
		btn.button_down.connect(btn.queue_redraw)
		btn.button_up.connect(btn.queue_redraw)
		btn.pressed.connect(t[1])
		_tabbar.add_child(btn)
	_home.resized.connect(_layout_home)

	var ver := Label.new()
	ver.text = "Зоопарк мечты · %s" % VERSION
	ver.add_theme_font_size_override("font_size", 13)
	ver.modulate = Color(1, 1, 1, 0.7)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ver.position = Vector2(530, 2)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(ver)
	_home.resized.connect(func() -> void: ver.position = Vector2(_home.size.x - 190, 2))


func _layout_home() -> void:
	var w := _home.size.x if _home.size.x > 0 else size.x
	var h := _home.size.y if _home.size.y > 0 else size.y
	# низ по референсу (высота 1752): дерево с y 1545, кнопка уровня 450–895 × 1280–1505, молоток Ø180 в (110, 1405)
	var ref_b := func(y: float) -> float: return h - (1752.0 - y) * REF_K
	_tabbar.size = Vector2(w, 207.0 * REF_K)
	_tabbar.position = Vector2(0, ref_b.call(1545.0))
	_home_level_btn.position = Vector2(672.0 * REF_K - _home_level_btn.custom_minimum_size.x / 2, ref_b.call(1392.0) - _home_level_btn.custom_minimum_size.y / 2)
	# колонки кнопок — по референсу: подарок (88, 283) Ø154, сундук ниже; справа почта (826, 258) Ø124, шаг 127
	if _lside:
		_lside.position = Vector2(88 - 77, 283 - 77) * REF_K
	if _rside:
		_rside.position = Vector2(826 - 62, 258 - 62) * REF_K
	_repair_btn.position = Vector2(110.0 * REF_K - _repair_btn.size.x / 2, ref_b.call(1405.0) - 90.0 * REF_K)
	_home_panda.position = Vector2(4, h - 250 - _home_panda.custom_minimum_size.y + 10)


## Плавная анимация рисованного элемента: перерисовка каждый кадр, пока он виден
## (раньше — 20 раз в секунду, это выглядело рывками).
func _every_frame(ci: CanvasItem) -> void:
	var cb := func() -> void:
		if is_instance_valid(ci) and ci.is_visible_in_tree():
			ci.queue_redraw()
	get_tree().process_frame.connect(cb)
	ci.tree_exiting.connect(func() -> void:
		if get_tree().process_frame.is_connected(cb):
			get_tree().process_frame.disconnect(cb))


## Коэффициент референса: референс 898 px в ширину, игра — 720.
const REF_K := 720.0 / 898.0


## Прямоугольник в координатах игры по прямоугольнику на референсе (x0, y0, x1, y1).
func _ref_rect(x0: float, y0: float, x1: float, y1: float) -> Rect2:
	return Rect2(Vector2(x0, y0) * REF_K, Vector2(x1 - x0, y1 - y0) * REF_K)


## Плашка ресурса с картинкой-иконкой, числом и плюсом; всё по координатам референса.
func _ref_plate(plate: Rect2, icon: String, icon_c: Vector2, icon_d: float, plus_c: Vector2, with_plus: bool) -> Label:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.position = plate.position
	c.size = plate.size
	var ic := icon_c * REF_K - plate.position
	var idd := icon_d * REF_K
	c.draw.connect(func() -> void:
		var t := Zoo.art("ui2_plate_s")
		if t:
			c.draw_texture_rect(t, Rect2(Vector2.ZERO, c.size), false)
		Zoo.draw_art(c, icon, ic, idd))
	_topbar.add_child(c)
	var l := Label.new()
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 34)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var lx := ic.x + idd * 0.42
	l.position = Vector2(lx, 0)
	l.size = Vector2(plate.size.x - lx - (22.0 if with_plus else 8.0), plate.size.y)
	c.add_child(l)
	if with_plus:
		var b := _plus_button()
		var pd := 46.0 * REF_K
		b.custom_minimum_size = Vector2(pd, pd)
		b.size = Vector2(pd, pd)
		b.position = plus_c * REF_K - Vector2(pd, pd) / 2
		_topbar.add_child(b)
	return l


var _topbar: Control


func _build_topbar_ref() -> void:
	_topbar = Control.new()
	_topbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_topbar.position = Vector2.ZERO
	_topbar.size = Vector2(720, 160)
	_home.add_child(_topbar)
	# аватар: кольцо с листьями по центру (95, 100), ширина с листьями ~190
	var av := Control.new()
	av.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av.position = Vector2.ZERO
	av.size = Vector2(200, 200) * REF_K
	var avc := Vector2(95, 100) * REF_K
	av.draw.connect(func() -> void:
		Zoo.draw_art(av, "ui2_avatar", avc + Vector2(0, 10) * REF_K, 226.0 * REF_K)
		Zoo.draw_art(av, "ui_avatar", avc, 150.0 * REF_K)
		var font: Font = UiTheme.title_font()
		var bo := avc + Vector2(58, 60) * REF_K
		av.draw_circle(bo, 18, Color.WHITE)
		av.draw_circle(bo, 15, Color("#3fb85a"))
		var lvl := str(Save.level)
		var lfs := 20 if lvl.length() < 3 else 15
		var lts := font.get_string_size(lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
		av.draw_string(font, bo + Vector2(-lts.x / 2, lfs * 0.36), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color.WHITE))
	_topbar.add_child(av)
	_avatar_node = av
	# жизни: плашка, сердце, под ней плашка таймера с будильником
	var hp := _ref_rect(191, 46, 408, 125)
	_hearts_label = _ref_plate(hp, "ui_heart", Vector2(232, 82), 80.0, Vector2(385, 112), true)
	var tm := Control.new()
	tm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := _ref_rect(220, 106, 362, 149)
	tm.position = tr.position
	tm.size = tr.size
	tm.draw.connect(func() -> void:
		var t := Zoo.art("ui2_plate_s")
		if t:
			tm.draw_texture_rect(t, Rect2(Vector2.ZERO, tm.size), false)
		Zoo.draw_art(tm, "ui2_clock", Vector2(246, 128) * REF_K - tm.position, 46.0 * REF_K))
	_topbar.add_child(tm)
	_hearts_timer = Label.new()
	_hearts_timer.theme_type_variation = "TitleLabel"
	_hearts_timer.add_theme_font_size_override("font_size", 20)
	_hearts_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hearts_timer.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hearts_timer.position = Vector2(30, 0) * REF_K
	_hearts_timer.size = tr.size - Vector2(30, 0) * REF_K
	tm.add_child(_hearts_timer)
	# монеты и звёзды
	_coin_labels.append(_ref_plate(_ref_rect(428, 46, 653, 125), "ui_coin", Vector2(472, 86), 86.0, Vector2(632, 113), true))
	_stars_label = _ref_plate(_ref_rect(674, 46, 886, 125), "ui_star", Vector2(716, 82), 86.0, Vector2(865, 113), false)


func _avatar() -> Control:
	var c := Control.new()
	var big := Zoo.art("ui2_avatar") != null
	c.custom_minimum_size = Vector2(104, 104) if big else Vector2(64, 64)
	c.draw.connect(func() -> void:
		var m := c.size / 2
		if big:
			Zoo.draw_art(c, "ui2_avatar", m + Vector2(0, 6), 156.0)
		if not Zoo.draw_art(c, "ui_avatar", m, 96.0 if big else 68.0):
			c.draw_circle(m, 31, Color("#f0b34a"))
			c.draw_circle(m, 27, Color.WHITE)
		for dx in ([] if Zoo.art("ui_avatar") else [-14, 14]):
			c.draw_circle(m + Vector2(dx, -16), 8, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -2), 7, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -3), 2.5, Color.WHITE)
		if not Zoo.art("ui_avatar"):
			c.draw_circle(m + Vector2(0, 8), 4, Color("#2b2b33"))
		var f: Font = ThemeDB.fallback_font
		var bo := Vector2(34, 34) if big else Vector2(22, 22)
		c.draw_circle(m + bo, 16 if big else 13, Color.WHITE)
		c.draw_circle(m + bo, 13 if big else 11, Color("#3fb85a"))
		var lvl := str(Save.level)
		var ff: Font = UiTheme.title_font()
		var lfs := 18 if lvl.length() < 3 else 14
		var lts := ff.get_string_size(lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs)
		c.draw_string(ff, m + bo + Vector2(-lts.x / 2, lfs * 0.36), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, lfs, Color.WHITE))
	_avatar_node = c
	return c


func _stars_pill() -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(46, 46)
	icon.draw.connect(func() -> void: Zoo.draw_star(icon, icon.size / 2, 24.0))
	row.add_child(icon)
	_stars_label = Label.new()
	_stars_label.theme_type_variation = "TitleLabel"
	_stars_label.add_theme_font_size_override("font_size", 30)
	row.add_child(_stars_label)
	return pill


## Главный экран — карта зоопарка; режим ремонта — текущая зона с местами под задания.
func _set_repair_mode(on: bool) -> void:
	_repair_mode = on
	_clear_overlay()
	_refresh_home()


func _refresh_home() -> void:
	_layout_home()
	_map.visible = not _repair_mode and _map.texture != null
	_zoo.visible = _repair_mode or _map.texture == null
	_zoo.mouse_filter = Control.MOUSE_FILTER_PASS if _zoo.visible else Control.MOUSE_FILTER_IGNORE
	if _repair_mode and not _home_panda.visible and _home_panda.get_node("Img").has_node("Anim"):
		_home_panda.get_node("Img/Anim").play("wave")
	_home_panda.visible = _repair_mode
	_zone_title.visible = _repair_mode
	_zone_box.visible = _repair_mode
	_repair_btn.queue_redraw()
	_refresh_coins()
	_refresh_hearts()
	if _stars_label:
		_stars_label.text = str(Save.stars)
	if _avatar_node:
		_avatar_node.queue_redraw()
	var z := mini(Save.zone, Zones.ZONES.size() - 1)
	var zone: Dictionary = Zones.ZONES[z]
	_zoo.setup(z, Save.built)
	_zone_title.text = "Зона %d: %s" % [z + 1, zone.name]
	_zone_bar.max_value = zone.tasks.size()
	_zone_bar.value = Save.built.size()
	var lv := Levels.make(Save.level)
	if Zoo.art("ui2_play"):
		_home_level_btn.text = ""
		_home_level_btn.set_meta("hard", lv.get("hard", 0) > 0)
		_home_level_btn.queue_redraw()
	else:
		_home_level_btn.text = "Уровень %d" % Save.level
		_home_level_btn.theme_type_variation = "RedButton" if lv.get("hard", 0) > 0 else "GreenButton"


# ---------- ремонт ----------

func _on_spot(i: int) -> void:
	var task: Dictionary = Zones.ZONES[Save.zone].tasks[i]
	if Save.stars < int(task.cost):
		_dialog(task.name, ["Нужно звёзд: %d (у тебя %d)" % [task.cost, Save.stars], "Проходи уровни — за каждый дают звезду!"], [
			["Играть", "GreenButton", _try_play],
			["Закрыть", "Button", _clear_overlay],
		])
		return
	# выбор дизайна из трёх вариантов
	var v := _dialog(task.name, ["Выбери дизайн (можно перекрасить потом)"], [["Отмена", "Button", _clear_overlay]])
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	v.move_child(row, v.get_child_count() - 2)
	for d in Zones.DESIGNS.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(150, 170)
		b.theme_type_variation = "Button"
		var kind: String = task.kind
		var col: Color = Zones.DESIGNS[d]
		var pic := Control.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.set_anchors_preset(Control.PRESET_FULL_RECT)
		pic.draw.connect(func() -> void: Zoo.draw_item(pic, kind, col, pic.size / 2 + Vector2(0, 40), 0.6, d))
		b.add_child(pic)
		b.pressed.connect(_build_task.bind(i, d))
		row.add_child(b)


func _build_task(i: int, design: int) -> void:
	var task: Dictionary = Zones.ZONES[Save.zone].tasks[i]
	_clear_overlay()
	Save.stars -= int(task.cost)
	Save.built[i] = design
	Save.store()
	# камера летит к месту, панда стучит молотком, предмет падает с пылью
	var c: Vector2 = _zoo.spot_center(i)
	_zoo.pivot_offset = c
	var tw := _zoo.create_tween()
	tw.tween_property(_zoo, "scale", Vector2(1.25, 1.25), 0.35).set_trans(Tween.TRANS_SINE)
	await tw.finished
	var img: Control = _home_panda.get_node("Img")
	if img.has_node("Anim"):
		# живая панда достаёт молоток и стучит; предмет появляется на втором ударе
		img.get_node("Anim").play("build")
		await get_tree().create_timer(2.2).timeout
	else:
		var hop := img.create_tween()
		for k in 3:
			hop.tween_property(img, "rotation", -0.18, 0.09)
			hop.tween_property(img, "rotation", 0.05, 0.09)
		hop.tween_property(img, "rotation", 0.0, 0.08)
		await get_tree().create_timer(0.3).timeout
	_zoo.build(i, design)
	_dust(_zoo.get_global_transform_with_canvas() * c)
	Save.vibrate(40)
	await get_tree().create_timer(0.8).timeout
	var back := _zoo.create_tween()
	back.tween_property(_zoo, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_SINE)
	await back.finished
	_refresh_home()
	_say(["Ух ты, как красиво!", "Вот это да!", "Зверям понравится!", "Ещё чуть-чуть — и будет как новенький!"].pick_random())
	if Save.built.size() >= Zones.ZONES[Save.zone].tasks.size():
		await get_tree().create_timer(0.8).timeout
		_zone_complete()


func _zone_complete() -> void:
	var zone: Dictionary = Zones.ZONES[Save.zone]
	Save.add_coins(300)
	for k in ["pre_rocket", "pre_bomb", "pre_orb"]:
		Save.add_booster(k)
	var next := Save.zone + 1
	var lines := ["Сундук: +300 монет и бустеры!",
		("В зоопарке поселились: %s" % zone.animal) if zone.animal != "" else "Зоопарк открыт для гостей!"]
	if next < Zones.ZONES.size():
		lines.append("Дальше: «%s»" % Zones.ZONES[next].name)
	else:
		lines.append("Новые зоны появятся в обновлениях!")
	_dialog("Зона готова!", lines, [["Ура!", "GreenButton", func() -> void:
		if next < Zones.ZONES.size():
			Save.zone = next
			Save.built = {}
			Save.store()
		_clear_overlay()
		_refresh_home()]])


func _dust(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = _fx.to_local(at)
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 40
	p.lifetime = 0.8
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 8.0
	p.scale_amount_max = 18.0
	p.color = Color(0.95, 0.88, 0.7, 0.9)
	_fx.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	var s := CPUParticles2D.new()
	s.position = p.position
	s.one_shot = true
	s.explosiveness = 1.0
	s.amount = 20
	s.lifetime = 0.7
	s.spread = 180.0
	s.initial_velocity_min = 150.0
	s.initial_velocity_max = 320.0
	s.scale_amount_min = 4.0
	s.scale_amount_max = 7.0
	s.color = Color("#ffe14d")
	_fx.add_child(s)
	s.emitting = true
	s.finished.connect(s.queue_free)


## Пузырь с текстом над пандой на главном экране.
func _say(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "InkLabel"
	l.add_theme_font_size_override("font_size", 24)
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color.WHITE
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(12)
	bubble.add_theme_stylebox_override("panel", sb)
	bubble.add_child(l)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(bubble)
	bubble.position = _home_panda.position + Vector2(120, -40)
	bubble.modulate.a = 0.0
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.2)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.3)
	tw.tween_callback(bubble.queue_free)


# ---------- вкладки ----------

func _show_soon(what: String) -> void:
	_dialog(what, ["Скоро!", "Панда уже работает над этим."], [["Закрыть", "Button", _clear_overlay]])


func _show_shop() -> void:
	var font: Font = UiTheme.title_font()
	var v := _dialog("Магазин", [], [])
	(v.get_parent() as Control).custom_minimum_size.x = 660
	# сколько монет — плашка сверху
	var bal := Control.new()
	bal.custom_minimum_size = Vector2(0, 64)
	bal.draw.connect(func() -> void:
		var t := str(Save.coins)
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 36)
		var w := ts.x + 110.0
		var r := Rect2(Vector2((bal.size.x - w) / 2, 6), Vector2(w, 52))
		_tile(bal, r, Color("#5a3a08"), 26)
		_tile(bal, r.grow(-3), Color("#2b1a4a"), 23)
		Zoo.draw_art(bal, "ui_coin", r.position + Vector2(32, 26), 50.0)
		var tp := r.position + Vector2(66, 39)
		bal.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, 7, Color("#1a0e2a"))
		bal.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 36, Color("#ffe14d")))
	v.add_child(bal)
	# карточки бустеров: 4 на уровне + 3 до уровня, сетка по 4
	var all: Array = []
	for b in IN_BOOSTERS:
		all.append([b[0], b[1]])
	for b in PRE_BOOSTERS:
		all.append([b[0], b[1]])
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for b in all:
		var kind: String = b[0]
		var title: String = b[1]
		var card := Control.new()
		card.custom_minimum_size = Vector2(140, 236)
		card.draw.connect(func() -> void:
			var r := Rect2(Vector2.ZERO, Vector2(card.size.x, 172))
			_tile(card, Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.18), 20)
			_tile(card, r, Color("#b9824a"), 20)
			_tile(card, r.grow(-4), Color("#fff1d0"), 17)
			var tfs := 24 if title.length() < 7 else 20
			var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs)
			var tp := Vector2((r.size.x - ts.x) / 2, 32)
			card.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, 6, Color("#6a3a10"))
			card.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color.WHITE)
			var ic := Vector2(r.size.x / 2, 98)
			if kind.begins_with("pre_"):
				var t: Texture2D = Gem.tex({"pre_rocket": "rocket", "pre_bomb": "bomb", "pre_orb": "orb"}[kind])
				if t:
					var sz := t.get_size()
					var kk := 74.0 / maxf(sz.x, sz.y)
					card.draw_set_transform(ic, 0.0, Vector2(kk, kk))
					card.draw_texture(t, -sz / 2)
					card.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				_draw_tool_icon(card, kind, ic)
			# сколько уже есть
			var n := int(Save.boosters.get(kind, 0))
			var bc := Vector2(r.size.x - 28, 148)
			card.draw_circle(bc, 20, Color.WHITE)
			card.draw_circle(bc, 17, Color("#2f9e3a"))
			var nt := str(n)
			var nts := font.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
			card.draw_string(font, bc + Vector2(-nts.x / 2, 8), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
		var buy := Button.new()
		buy.theme_type_variation = "GreenButton"
		buy.custom_minimum_size = Vector2(140, 60)
		buy.position = Vector2(0, 176)
		buy.size = Vector2(140, 60)
		buy.text = "     %d" % BOOSTER_PRICE
		buy.add_theme_font_size_override("font_size", 24)
		buy.disabled = Save.coins < BOOSTER_PRICE
		buy.draw.connect(func() -> void:
			Zoo.draw_art(buy, "ui_coin", Vector2(30, buy.size.y / 2 - 3), 36.0))
		buy.pressed.connect(func() -> void:
			if Save.spend(BOOSTER_PRICE):
				Save.add_booster(kind)
				Sfx.play("coin")
				card.pivot_offset = card.size / 2
				var t := card.create_tween()
				t.tween_property(card, "scale", Vector2(1.08, 1.08), 0.08)
				t.tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
				for c in grid.get_children():
					c.queue_redraw()
					for bb in c.get_children():
						if bb is Button:
							bb.disabled = Save.coins < BOOSTER_PRICE
				bal.queue_redraw()
				_refresh_coins())
		card.add_child(buy)
		grid.add_child(card)
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(300, 80)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(func() -> void:
		_clear_overlay()
		_refresh_home())
	v.add_child(close)


## Подарочная коробка с бантом (для кнопки и окна подарков).
func _draw_gift(ci: CanvasItem, c: Vector2, k: float, col := Color("#ff4a7a")) -> void:
	var ink := Color("#2b1a4a")
	var body := Rect2(c + Vector2(-20, -6) * k, Vector2(40, 28) * k)
	var lid := Rect2(c + Vector2(-24, -16) * k, Vector2(48, 12) * k)
	ci.draw_rect(body.grow(2.5 * k), ink)
	ci.draw_rect(body, col)
	ci.draw_rect(lid.grow(2.5 * k), ink)
	ci.draw_rect(lid, col.lightened(0.2))
	var rib := Color("#ffd84a")
	ci.draw_rect(Rect2(c + Vector2(-4, -16) * k, Vector2(8, 38) * k), rib)
	for sx in [-1.0, 1.0]:
		var p := c + Vector2(9 * sx, -22) * k
		ci.draw_circle(p, 8.5 * k, ink)
		ci.draw_circle(p, 6 * k, rib)
	ci.draw_circle(c + Vector2(0, -19) * k, 5 * k, ink)
	ci.draw_circle(c + Vector2(0, -19) * k, 3.5 * k, rib)


## Сундук: деревянный, с золотыми уголками; открытый (full) — светится.
func _draw_chest(ci: CanvasItem, c: Vector2, k: float, full := false) -> void:
	var ink := Color("#3a1e08")
	var gold := Color("#ffcf3a")
	var gold_d := Color("#c98a12")
	if full:
		var p := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 180.0)
		for i in 4:
			ci.draw_circle(c, (40 - i * 6) * k, Color(1, 0.9, 0.4, (0.12 + i * 0.06) * p))
	# тень
	ci.draw_set_transform(c + Vector2(0, 24) * k, 0.0, Vector2(1.0, 0.25))
	ci.draw_circle(Vector2.ZERO, 30 * k, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# корпус
	var body := Rect2(c + Vector2(-26, -4) * k, Vector2(52, 28) * k)
	_tile(ci, body.grow(3 * k), ink, 5 * k)
	_tile(ci, body, Color("#9a5222"), 4 * k)
	_tile(ci, Rect2(body.position, Vector2(body.size.x, 8 * k)), Color("#b8692e"), 3 * k)
	# крышка-арка
	var lc := c + Vector2(0, -4) * k
	var pts := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		pts.append(lc + Vector2(cos(a) * 26, sin(a) * 18) * k)
	var out := PackedVector2Array()
	for i in 17:
		var a := PI + PI * i / 16.0
		out.append(lc + Vector2(cos(a) * 29, sin(a) * 21) * k)
	out.append(lc + Vector2(29, 1) * k)
	out.append(lc + Vector2(-29, 1) * k)
	ci.draw_colored_polygon(out, ink)
	pts.append(lc + Vector2(26, 0))
	pts.append(lc + Vector2(-26, 0))
	ci.draw_colored_polygon(pts, Color("#c97a36"))
	ci.draw_polyline(PackedVector2Array([lc + Vector2(-18, -10) * k, lc + Vector2(-6, -15) * k, lc + Vector2(6, -15) * k]), Color(1, 1, 1, 0.3), 3 * k, true)
	# золотые полосы и замок
	for x in [-20.0, 14.0]:
		ci.draw_rect(Rect2(c + Vector2(x, -20) * k, Vector2(6, 44) * k), gold_d)
		ci.draw_rect(Rect2(c + Vector2(x + 1, -20) * k, Vector2(3, 44) * k), gold)
	ci.draw_rect(Rect2(c + Vector2(-27, -5) * k, Vector2(54, 5) * k), gold_d)
	ci.draw_circle(c + Vector2(0, 4) * k, 8 * k, ink)
	ci.draw_circle(c + Vector2(0, 4) * k, 6.5 * k, gold)
	ci.draw_rect(Rect2(c + Vector2(-1.5, 3) * k, Vector2(3, 5) * k), ink)


## Красный кружок «!» на кнопке — есть что забрать.
func _dot_badge(ci: CanvasItem, c: Vector2, t: String) -> void:
	var font: Font = UiTheme.title_font()
	ci.draw_circle(c, 15, Color.WHITE)
	ci.draw_circle(c, 12.5, Color("#e8261c"))
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	ci.draw_string(font, c + Vector2(-ts.x / 2, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)


## Значок награды: монета или бустер, с количеством.
func _draw_reward(ci: CanvasItem, kind: String, n: int, c: Vector2, px: float) -> void:
	var font: Font = UiTheme.title_font()
	var art := {"coins": "ui_coin", "hammer": "ui_hammer", "arrow": "ui_arrow", "rockets": "lv_rockets", "shuffle": "ui_shuffle",
		"pre_rocket": "rocket", "pre_bomb": "bomb", "pre_orb": "orb"}
	var nm: String = art.get(kind, "ui_coin")
	if nm.begins_with("ui_"):
		if not Zoo.draw_art(ci, nm, c, px):
			ci.draw_circle(c, px * 0.35, Color("#ffd23f"))
	else:
		var t: Texture2D = Gem.tex(nm)
		if t:
			var sz := t.get_size()
			var kk := px * 0.85 / maxf(sz.x, sz.y)
			ci.draw_set_transform(c, 0.0, Vector2(kk, kk))
			ci.draw_texture(t, -sz / 2)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var txt := str(n) if kind == "coins" else "x%d" % n
	var fs := int(px * 0.34)
	var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := c + Vector2(-ts.x / 2, px * 0.5 + fs * 0.6)
	ci.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color("#2b1a4a"))
	ci.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _give(reward: Dictionary) -> void:
	for kind in reward:
		if kind == "coins":
			Save.add_coins(int(reward[kind]))
		else:
			Save.add_booster(kind, int(reward[kind]))


## Окно ежедневного подарка: 7 дней, сегодняшний подсвечен, полученные — с галочкой.
## Пропустил день — неделя начинается заново.
func _show_daily() -> void:
	var ready := Save.daily_ready()
	var cur := Save.daily_day
	var font: Font = UiTheme.title_font()
	var v := _dialog("Подарок дня", [], [])
	(v.get_parent() as Control).custom_minimum_size.x = 660
	var grid := Control.new()
	grid.custom_minimum_size = Vector2(0, 420)
	grid.draw.connect(func() -> void:
		var cw := 140.0
		var chh := 196.0
		var gap := 10.0
		var x0 := (grid.size.x - (4 * cw + 3 * gap)) / 2.0
		for d in 7:
			var r: Rect2
			if d < 4:
				r = Rect2(Vector2(x0 + d * (cw + gap), 0), Vector2(cw, chh))
			elif d < 6:
				r = Rect2(Vector2(x0 + (d - 4) * (cw + gap), chh + 16), Vector2(cw, chh))
			else:
				r = Rect2(Vector2(x0 + 2 * (cw + gap), chh + 16), Vector2(cw * 2 + gap, chh))
			var got := d < cur
			var today := d == cur and ready
			var base := Color("#ffe9b8") if not got else Color("#cfe9c0")
			if today:
				var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
				_tile(grid, r.grow(6 + 2 * p), Color(1.0, 0.85, 0.2, 0.55), 26)
			_tile(grid, Rect2(r.position + Vector2(0, 5), r.size), Color(0, 0, 0, 0.2), 20)
			_tile(grid, r, Color("#b9824a") if not today else Color("#ff8a00"), 20)
			_tile(grid, r.grow(-4 if not today else -7), base if not today else Color("#fff6c8"), 17)
			var dt := "День %d" % (d + 1)
			var dts := font.get_string_size(dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24)
			var dp := Vector2(r.get_center().x - dts.x / 2, r.position.y + 34)
			grid.draw_string_outline(font, dp, dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color("#6a3a10"))
			grid.draw_string(font, dp, dt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
			var rw: Dictionary = DAILY[d]
			var keys := rw.keys()
			var n := keys.size()
			var px := 70.0 if n == 1 else (58.0 if n == 2 else 52.0)
			var span := r.size.x - 20
			for i in n:
				var cx := r.position.x + 10 + span * (i + 0.5) / n
				_draw_reward(grid, keys[i], int(rw[keys[i]]), Vector2(cx, r.position.y + 96), px)
			if got:
				var cc := r.position + Vector2(r.size.x - 26, 26)
				grid.draw_circle(cc, 20, Color.WHITE)
				grid.draw_circle(cc, 17, Color("#2fae3a"))
				grid.draw_polyline(PackedVector2Array([cc + Vector2(-9, 0), cc + Vector2(-2, 7), cc + Vector2(10, -7)]), Color.WHITE, 5.0, true))
	v.add_child(grid)
	_every_frame(grid)
	var btn := Button.new()
	btn.theme_type_variation = "GreenButton" if ready else "Button"
	btn.custom_minimum_size = Vector2(360, 96)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 34)
	btn.text = "Забрать" if ready else "Приходи завтра!"
	btn.pressed.connect(func() -> void:
		if not Save.daily_ready():
			_clear_overlay()
			return
		_give(DAILY[Save.daily_day])
		Save.daily_last = Save.today()
		Save.daily_day = (Save.daily_day + 1) % 7
		Save.store()
		Sfx.play("coin")
		_dust(btn.get_global_rect().get_center())
		_clear_overlay()
		_refresh_home())
	v.add_child(btn)


## Сундук за победы: копится по победам; полный — открыть и забрать.
func _show_chest() -> void:
	var full := Save.chest_wins >= CHEST_WINS
	var v := _dialog("Сундук побед", [("Внутри: %d монет и 2 бустера!" % CHEST_COINS) if full else
		"Побед: %d из %d. Выигрывай уровни — сундук наполнится!" % [Save.chest_wins, CHEST_WINS]], [])
	var pic := Control.new()
	pic.custom_minimum_size = Vector2(0, 200)
	pic.draw.connect(func() -> void:
		_draw_chest(pic, pic.size / 2 + Vector2(0, 10), 3.4, full))
	v.add_child(pic)
	v.move_child(pic, 0)
	_every_frame(pic)
	var btn := Button.new()
	btn.theme_type_variation = "GreenButton" if full else "Button"
	btn.custom_minimum_size = Vector2(360, 96)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.add_theme_font_size_override("font_size", 34)
	btn.text = "Открыть" if full else "Закрыть"
	btn.pressed.connect(func() -> void:
		if Save.chest_wins >= CHEST_WINS:
			var pool := ["hammer", "rockets", "shuffle", "pre_rocket", "pre_bomb", "pre_orb"]
			pool.shuffle()
			var rw := {"coins": CHEST_COINS, pool[0]: 1, pool[1]: 1}
			_give(rw)
			Save.chest_wins = 0
			Save.store()
			Sfx.play("coin")
			_dust(btn.get_global_rect().get_center())
			_clear_overlay()
			var lines: Array = []
			var dv := _dialog("Сундук открыт!", lines, [["Ура!", "GreenButton", func() -> void:
				_clear_overlay()
				_refresh_home()]])
			var row := Control.new()
			row.custom_minimum_size = Vector2(0, 130)
			row.draw.connect(func() -> void:
				var ks := rw.keys()
				for i in ks.size():
					_draw_reward(row, ks[i], int(rw[ks[i]]), Vector2(row.size.x * (i + 0.5) / ks.size(), 50), 80.0))
			dv.add_child(row)
			dv.move_child(row, 1)
		else:
			_clear_overlay())
	v.add_child(btn)


func _show_collection() -> void:
	var font: Font = UiTheme.title_font()
	var v := _dialog("Коллекция", [], [])
	(v.get_parent() as Control).custom_minimum_size.x = 640
	var list := Control.new()
	var n := Zones.ZONES.size()
	var rh := 84.0
	list.custom_minimum_size = Vector2(0, n * (rh + 8))
	list.draw.connect(func() -> void:
		for i in n:
			var z: Dictionary = Zones.ZONES[i]
			var done := i < Save.zone
			var cur := i == Save.zone
			var r := Rect2(Vector2(0, i * (rh + 8)), Vector2(list.size.x, rh))
			_tile(list, Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.15), 18)
			_tile(list, r, Color("#b9824a") if not cur else Color("#ff8a00"), 18)
			_tile(list, r.grow(-3), Color("#cfeec0") if done else (Color("#fff6c8") if cur else Color("#e6dccb")), 15)
			# номер зоны в кружке
			var nc := r.position + Vector2(44, rh / 2)
			list.draw_circle(nc, 28, Color("#5a3a08"))
			list.draw_circle(nc, 25, Color("#2fae3a") if done else (Color("#ff9a1a") if cur else Color("#9a8f80")))
			var nt := str(i + 1)
			var nts := font.get_string_size(nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
			list.draw_string(font, nc + Vector2(-nts.x / 2, 11), nt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
			var tp := r.position + Vector2(86, 36)
			var col := Color("#6a3a10") if (done or cur) else Color("#8a8070")
			list.draw_string(font, tp, z.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, col)
			var sub: String
			if done:
				sub = ("Живут: %s" % z.animal) if z.animal != "" else "Открыт для гостей"
			elif cur:
				sub = "Ремонт: %d из %d" % [Save.built.size(), z.tasks.size()]
			else:
				sub = ("Скоро: %s" % z.animal) if z.animal != "" else "Закрыта"
			list.draw_string(font, r.position + Vector2(86, 68), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, col.lightened(0.15))
			if cur:
				var br := Rect2(r.position + Vector2(r.size.x - 170, rh / 2 - 10), Vector2(150, 20))
				_tile(list, br.grow(2), Color("#5a3a08"), 11)
				_tile(list, br, Color("#e6dccb"), 10)
				var f: float = float(Save.built.size()) / float(z.tasks.size())
				if f > 0:
					_tile(list, Rect2(br.position, Vector2(br.size.x * f, br.size.y)), Color("#5fd34a"), 10)
			elif done:
				var cc := r.position + Vector2(r.size.x - 40, rh / 2)
				list.draw_circle(cc, 20, Color.WHITE)
				list.draw_circle(cc, 17, Color("#2fae3a"))
				list.draw_polyline(PackedVector2Array([cc + Vector2(-9, 0), cc + Vector2(-2, 7), cc + Vector2(10, -7)]), Color.WHITE, 5.0, true)
			else:
				# замочек
				var lc := r.position + Vector2(r.size.x - 40, rh / 2 + 4)
				list.draw_arc(lc + Vector2(0, -12), 10, PI, TAU, 12, Color("#7a6e60"), 5.0)
				_tile(list, Rect2(lc + Vector2(-15, -12), Vector2(30, 24)), Color("#7a6e60"), 5)
				list.draw_circle(lc, 4, Color("#e6dccb")))
	v.add_child(list)
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(300, 80)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(_clear_overlay)
	v.add_child(close)


func _show_settings() -> void:
	var font: Font = UiTheme.title_font()
	var v := _dialog("Настройки", [], [])
	(v.get_parent() as Control).custom_minimum_size.x = 600
	var icons := {"sound": "♪", "music": "♫", "vibration": "≋", "shake": "↯", "particles": "✦"}
	for it in [["Звук", "sound"], ["Музыка", "music"], ["Вибрация", "vibration"], ["Тряска экрана", "shake"], ["Много частиц", "particles"]]:
		var key: String = it[1]
		var name: String = it[0]
		var row := Button.new()
		row.flat = true
		for st in ["normal", "hover", "pressed", "focus"]:
			row.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		row.custom_minimum_size = Vector2(0, 76)
		row.set_meta("k", 1.0 if bool(Save.get(key)) else 0.0)
		row.draw.connect(func() -> void:
			var r := Rect2(Vector2.ZERO, row.size)
			_tile(row, Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.12), 18)
			_tile(row, r, Color("#d9b47c"), 18)
			_tile(row, r.grow(-3), Color("#fff6e0"), 15)
			# значок в кружке
			var ic := Vector2(42, r.size.y / 2)
			row.draw_circle(ic, 24, Color("#9b5cff"))
			row.draw_circle(ic + Vector2(0, -2), 21, Color("#b583ff"))
			var gl: String = icons[key]
			var gs := font.get_string_size(gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
			row.draw_string(font, ic + Vector2(-gs.x / 2, 10), gl, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)
			row.draw_string(font, Vector2(80, r.size.y / 2 + 11), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("#6a3a10"))
			# переключатель: ползунок едет, цвет плавно меняется
			var k: float = row.get_meta("k")
			var sw := Rect2(Vector2(r.size.x - 118, r.size.y / 2 - 22), Vector2(100, 44))
			_tile(row, sw.grow(3), Color("#5a3a08"), 25)
			_tile(row, sw, Color("#c9bba5").lerp(Color("#3fbf3a"), k), 22)
			_tile(row, Rect2(sw.position + Vector2(8, 4), Vector2(sw.size.x - 16, 10)), Color(1, 1, 1, 0.25), 5)
			var kc := sw.position + Vector2(22 + k * 56, 22)
			row.draw_circle(kc + Vector2(0, 3), 19, Color(0, 0, 0, 0.25))
			row.draw_circle(kc, 19, Color.WHITE)
			row.draw_circle(kc + Vector2(0, 3), 14, Color("#ececec"))
			var lt := "ВКЛ" if k > 0.5 else "ВЫКЛ"
			var lts := font.get_string_size(lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
			var lx := sw.position.x + (18.0 if k > 0.5 else sw.size.x - lts.x - 14)
			row.draw_string(font, Vector2(lx, sw.position.y + 29), lt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE if k > 0.5 else Color("#6a5a48")))
		row.pressed.connect(func() -> void:
			var on := not bool(Save.get(key))
			Save.set(key, on)
			Save.store()
			if key == "music":
				Sfx.refresh_music()
			Sfx.play("click")
			var t := row.create_tween()
			t.tween_method(func(x: float) -> void:
				row.set_meta("k", x)
				row.queue_redraw(), float(row.get_meta("k")), 1.0 if on else 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		v.add_child(row)
	var info := Label.new()
	info.text = "Язык: русский · Политика конфиденциальности — в описании игры"
	info.theme_type_variation = "InkLabel"
	info.add_theme_font_size_override("font_size", 18)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(info)
	var close := Button.new()
	close.text = "Закрыть"
	close.custom_minimum_size = Vector2(300, 80)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(_clear_overlay)
	v.add_child(close)


func _build_level_screen() -> void:
	_level_screen = Control.new()
	_level_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_screen)
	# фон уровня приглушён — внимание на поле
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.06, 0.12, 0.12)  # по референсу фон светлый
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_screen.add_child(dim)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 16)
	top.add_theme_constant_override("margin_top", 46)
	_level_screen.add_child(top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	top.add_child(col)

	# объёмная шапка: «Цель» слева, портрет панды в арке по центру, «Ходы» справа
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 10)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(hud)
	var goal_card := _hud_card("Цель", "lv_goals")
	goal_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal_card.size_flags_stretch_ratio = 272.0 / 242.0
	hud.add_child(goal_card)
	_goals_box = HBoxContainer.new()
	_goals_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_goals_box.add_theme_constant_override("separation", 4)
	goal_card.get_node("Body").add_child(_goals_box)
	_portrait_node = _hud_panda()
	hud.add_child(_portrait_node)
	# мягкая тень под ногами панды — стоит, а не парит
	_portrait_node.draw.connect(func() -> void:
		var pn := _portrait_node
		if _lvref():
			# маска-круг: панда видна только внутри рамки (clip_children)
			pn.draw_circle(pn.size / 2.0, pn.size.x / 2.0, Color.WHITE)
			return
		var at := Zoo.art("lv_arch")  # панда в золотой арке с листьями
		if at:
			# золотая арка с листьями из листа элементов уровня — панда стоит в ней
			var w := pn.size.x * 1.12
			var h := w * at.get_height() / at.get_width()
			pn.draw_texture_rect(at, Rect2(Vector2((pn.size.x - w) / 2, pn.size.y - h), Vector2(w, h)), false)
			return
		pn.draw_set_transform(Vector2(pn.size.x / 2, pn.size.y - 6), 0.0, Vector2(1.0, 0.22))
		pn.draw_circle(Vector2.ZERO, pn.size.x * 0.36, Color(0, 0, 0, 0.35))
		pn.draw_circle(Vector2.ZERO, pn.size.x * 0.26, Color(0, 0, 0, 0.25))
		pn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	var moves_card := _hud_card("Ходы", "lv_moves")
	moves_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(moves_card)
	_moves_label = Label.new()
	_moves_label.theme_type_variation = "TitleLabel"
	_moves_label.add_theme_font_size_override("font_size", 72)
	_moves_label.add_theme_constant_override("outline_size", 12)
	_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_moves_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_moves_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_moves_label.pivot_offset = Vector2(90, 45)
	moves_card.get_node("Body").add_child(_moves_label)
	_level_label = Label.new()
	_level_label.theme_type_variation = "TitleLabel"
	_level_label.add_theme_font_size_override("font_size", 26)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# номер уровня — на тёмной плашке, а не «в воздухе»
	var plaque := PanelContainer.new()
	var psb: StyleBox
	if Zoo.art("lv_counter"):
		# плашка уровня — кремовая с деревянным кантом (лист элементов уровня)
		var tsb := StyleBoxTexture.new()
		tsb.texture = Zoo.art("lv_counter")
		tsb.texture_margin_left = 60
		tsb.texture_margin_right = 60
		tsb.texture_margin_top = 50
		tsb.texture_margin_bottom = 50
		tsb.content_margin_left = 26
		tsb.content_margin_right = 26
		tsb.content_margin_top = 4
		tsb.content_margin_bottom = 6
		psb = tsb
		_level_label.add_theme_color_override("font_color", Color("#7a3e10"))
		_level_label.add_theme_color_override("font_outline_color", Color("#fff6e0"))
		_level_label.add_theme_constant_override("outline_size", 4)
		_level_label.add_theme_font_size_override("font_size", 24)
	else:
		var fsb := StyleBoxFlat.new()
		fsb.bg_color = Color(0.05, 0.12, 0.22, 0.72)
		fsb.set_corner_radius_all(18)
		fsb.border_color = Color("#bfe3ff", 0.6)
		fsb.set_border_width_all(2)
		fsb.content_margin_left = 22
		fsb.content_margin_right = 22
		fsb.content_margin_top = 2
		fsb.content_margin_bottom = 4
		psb = fsb
	plaque.add_theme_stylebox_override("panel", psb)
	plaque.add_child(_level_label)
	var pc := CenterContainer.new()
	pc.add_child(plaque)
	col.add_child(pc)
	if _lvref():
		_portrait_node.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
		dim.color.a = 0.0
		for card in [goal_card, moves_card]:
			card.self_modulate.a = 0.0  # плашки нарисованы в фоне
			card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		_moves_label.add_theme_font_size_override("font_size", 60)
	if Zoo.art("lv_goals"):
		# шапка 1:1 по референсу экрана уровня: плашки и панда стоят по координатам референса
		for n in [goal_card, moves_card, _portrait_node]:
			n.get_parent().remove_child(n)
			_level_screen.add_child(n)
		_lv_goal_card = goal_card
		_lv_moves_card = moves_card
		top.visible = false

	_board_frame = PanelContainer.new()
	_board_frame.theme_type_variation = "BoardPanel"
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_screen.add_child(_board_frame)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(8, 10) * Board.CELL
	_board_frame.add_child(clip)
	_board_clip = clip
	# рамка поля — ИИ-картинка (дерево, лианы, золотой кант), растягивается по 9 частям поверх края поля
	var lvf := Zoo.art("lv_frame")
	var ft: Texture2D = lvf if lvf else load("res://assets/art/ui_board_frame.png")
	var frame := NinePatchRect.new()
	frame.texture = ft
	frame.patch_margin_left = 72
	frame.patch_margin_right = 72
	frame.patch_margin_top = 72
	frame.patch_margin_bottom = 72
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 2
	frame.visible = lvf != null and not _lvref()  # деревянная рамка с золотыми уголками (референс экрана уровня)
	if lvf:
		frame.patch_margin_left = 150
		frame.patch_margin_right = 150
		frame.patch_margin_top = 150
		frame.patch_margin_bottom = 150
	var fk := 0.56 if lvf else 0.28
	frame.scale = Vector2(fk, fk)
	frame.top_level = false
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	holder.resized.connect(func() -> void:
		var out := 44.0 if lvf else 40.0
		frame.position = Vector2(-out, -out)
		frame.size = (holder.size + Vector2(out, out) * 2) / fk)
	_board_frame.add_child(holder)
	_board = Board.new()
	clip.add_child(_board)
	_board.move_made.connect(_on_move)
	_board.gem_cleared.connect(_on_gem_cleared)
	_board.goal_hit.connect(_on_goal_hit)
	_board.settled.connect(_on_settled)
	_board.big_hit.connect(func(p: float) -> void:
		if Save.shake:
			_shake = maxf(_shake, 9.0 + p * 6.0)
		if p >= 2.0:
			Save.vibrate(int(35 + p * 15))
			_flash(clampf(0.22 + p * 0.09, 0.3, 0.7))
		if p >= 3.0 and not _bot:
			_slowmo())
	_booster_bar = HBoxContainer.new()
	_booster_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_booster_bar.add_theme_constant_override("separation", 0)
	_level_screen.add_child(_booster_bar)
	for b in IN_BOOSTERS:
		var btn := _round_button(b[0], Color("#3fb85a"))
		btn.pressed.connect(_on_booster.bind(b[0]))
		_booster_bar.add_child(btn)
		_booster_btns[b[0]] = btn
	# пауза — последней кнопкой в ряду бустеров
	if Zoo.art("lv_slot") and Zoo.art("lv_goals") and not _lvref():
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(44, 10)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_booster_bar.add_child(gap)
	var pause := _round_button("pause", Color("#3f8cff"))
	_bar_pause = pause
	pause.pressed.connect(_show_pause)
	_booster_bar.add_child(pause)
	# сплошные полосы: шапка сверху и подставка бустеров снизу, с золотой каймой
	var bands := Control.new()
	bands.set_anchors_preset(Control.PRESET_FULL_RECT)
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.draw.connect(func() -> void:
		var w := bands.size.x
		if _lvref():
			return  # лоток нарисован в фоне
		var tr := Zoo.art("lv_tray")
		if tr:
			# зелёный лоток с золотым кантом — по референсу: x 8…712, высота 188, низ в 22 px от края
			var h := bands.size.y
			var r := Rect2(Vector2(8, h - 22 - 188), Vector2(w - 16, 188))
			var sb := StyleBoxTexture.new()
			sb.texture = tr
			sb.texture_margin_left = 190
			sb.texture_margin_right = 190
			sb.texture_margin_top = 130
			sb.texture_margin_bottom = 130
			bands.draw_set_transform(r.position, 0.0, Vector2(0.5, 0.5))
			bands.draw_style_box(sb, Rect2(Vector2.ZERO, r.size * 2.0))
			bands.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# золотая черта перед паузой
			var dx := _pause_divider_x()
			bands.draw_rect(Rect2(Vector2(dx - 2, r.position.y + 58), Vector2(5, 76)), Color("#8a5a10"))
			bands.draw_rect(Rect2(Vector2(dx - 1, r.position.y + 58), Vector2(3, 76)), Color("#ffd23f"))
			return
		var top_h := 238.0
		_draw_band(bands, Rect2(0, 0, w, top_h), false)
		var by := _booster_bar.position.y + 4.0
		_draw_tray(bands, Rect2(12, by, w - 24, 132)))
	_level_screen.add_child(bands)
	_level_screen.move_child(bands, 1)
	if _lvref():
		_build_lvref_layers()
	_bands = bands
	_panda = _make_panda(200.0)
	_panda.visible = false  # на уровне панда — портрет в шапке
	_level_screen.add_child(_panda)
	_level_screen.move_child(_panda, _board_frame.get_index())
	_board.combo_made.connect(_on_combo)
	_board.idle_hint.connect(func() -> void: _panda_react("yawn"))
	_board.shuffled.connect(func() -> void:
		if _state == "play":
			_panda_react("think"))
	_board.bad_move.connect(func() -> void:
		if _state == "play":
			_panda_react("bad"))
	_board.special_fired.connect(func() -> void:
		if _state == "play":
			_panda_react("special"))
	_board.shake.connect(func(a: float) -> void:
		if Save.shake:
			_shake = maxf(_shake, a)
		Save.vibrate(40))
	_level_screen.resized.connect(func() -> void:
		_layout_level_ref()
		_board_frame.position = _board_rest()
		_place_pause()
		_panda.position = _panda_rest()
		_layout_bar())


## Расстановка шапки по референсу (px референса 898×1752 × REF_K): цели (10…350, 62…275),
## ходы (590…890), панда — между плашками, ноги на линии низа плашек.
func _layout_level_ref() -> void:
	if _lv_goal_card == null:
		return
	if _lvref():
		_layout_lvref()
		return
	var gr := _ref_rect(10, 62, 350, 275)
	_lv_goal_card.position = gr.position
	_lv_goal_card.size = gr.size
	_lv_goal_card.custom_minimum_size = gr.size
	var mr := _ref_rect(590, 62, 890, 275)
	_lv_moves_card.position = mr.position
	_lv_moves_card.size = mr.size
	_lv_moves_card.custom_minimum_size = mr.size
	var pn := _portrait_node
	pn.size = pn.custom_minimum_size
	pn.position = Vector2(470.0 * REF_K - pn.size.x / 2.0, 275.0 * REF_K - pn.size.y + 6.0)
	_lv_goal_card.queue_redraw()
	_lv_moves_card.queue_redraw()


# ---------- экран уровня 1:1 по референсу (фон собран из самого референса: tools/refbuild.py) ----------
## Референс: 898 px в ширину; фон lvref_bg — референс без 68 строк в середине поля (клетки 86×86).
## Верх (до строки 1314 фона) прижат к верху экрана, низ (с 1398) — к низу, плитка между ними растягивается.
## Ширина референса уровня (screen_02_level_v3, 830×1895). Координаты ниже — в его пикселях; те же числа в tools/refbuild.py.
const LVW := 830.0
const LVREF_SPLIT := 1296.0
## Сколько строк неба срезать сверху референса: шапка (цели, панда, ходы) поднимается ближе к верху экрана.
## Все y-координаты референса ниже переводятся в экранные через _lvy().
const LVREF_TOP := 64.0
const LVREF_BAND := Vector2(0.0, 1588.0)   # .y — начало нижней части (лоток); между SPLIT и ним — плитка, растягивается
var _lvref_bg: Control
var _lvref_ring: Control
var _lvref_thumb: Control
var _goals_ref_box: Control


func _lvref() -> bool:
	return Zoo.art("lvref_bg") != null


## Точка референса (px 830-ширины) с учётом срезанного неба сверху.
func _lvp(x: float, y: float) -> Vector2:
	return Vector2(x, y - LVREF_TOP)


func _build_lvref_layers() -> void:
	var tex := Zoo.art("lvref_bg")
	_lvref_bg = Control.new()
	_lvref_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lvref_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lvref_bg.draw.connect(func() -> void:
		var w := _lvref_bg.size.x
		var h := _lvref_bg.size.y
		var k := w / float(tex.get_width())
		var th := float(tex.get_height())
		# верх (до низа рамки поля) прижат к верху, низ (лоток) — к низу; плитка между ними растягивается
		var top_h := (LVREF_SPLIT - LVREF_TOP) * k
		var bot_src := Rect2(0, LVREF_BAND.y, tex.get_width(), th - LVREF_BAND.y)
		var bot_h := bot_src.size.y * k
		var mid_src := Rect2(0, LVREF_SPLIT, tex.get_width(), LVREF_BAND.y - LVREF_SPLIT)
		_lvref_bg.draw_texture_rect_region(tex, Rect2(0, top_h, w, maxf(1.0, h - bot_h - top_h)), mid_src)
		_lvref_bg.draw_texture_rect_region(tex, Rect2(0, 0, w, top_h), Rect2(0, LVREF_TOP, tex.get_width(), LVREF_SPLIT - LVREF_TOP))
		_lvref_bg.draw_texture_rect_region(tex, Rect2(0, h - bot_h, w, bot_h), bot_src))
	_level_screen.add_child(_lvref_bg)
	_level_screen.move_child(_lvref_bg, 0)
	_lvref_bg.resized.connect(_lvref_bg.queue_redraw)
	# рамка панды поверх панды
	_lvref_ring = Control.new()
	_lvref_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt := Zoo.art("lvref_ring")
	_lvref_ring.draw.connect(func() -> void:
		var k := _level_screen.size.x / LVW
		_lvref_ring.draw_texture_rect(rt, Rect2(_lvp(250, 0) * k, rt.get_size() * k), false))
	_level_screen.add_child(_lvref_ring)
	_lvref_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	# большой палец панды лежит поверх рамки — отдельный слой, двигается вместе с пандой
	var tt := Zoo.art("lvref_thumb")
	if tt:
		_lvref_thumb = Control.new()
		_lvref_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lvref_thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		_lvref_thumb.draw.connect(func() -> void:
			var k := _level_screen.size.x / LVW
			var img: Control = _portrait_node.get_node("Img")
			var piv: Vector2 = _portrait_node.position + img.get_meta("rest", img.position) + img.pivot_offset
			var off: Vector2 = img.position - img.get_meta("rest", img.position)
			var m := Transform2D(img.rotation, img.scale, 0.0, piv + off) * Transform2D(0.0, -piv)
			_lvref_thumb.draw_set_transform_matrix(m)
			_lvref_thumb.draw_texture_rect(tt, Rect2(_lvp(250, 0) * k, tt.get_size() * k), false)
			_lvref_thumb.draw_set_transform_matrix(Transform2D.IDENTITY))
		_level_screen.add_child(_lvref_thumb)
		_every_frame(_lvref_thumb)


func _layout_lvref() -> void:
	var k := _level_screen.size.x / LVW
	# плашки: только содержимое (сами плашки — в фоне)
	for cr in [[_lv_goal_card, _lvp(35, 175), Vector2(260, 120)], [_lv_moves_card, _lvp(565, 172), Vector2(235, 120)]]:
		var cd: Control = cr[0]
		cd.custom_minimum_size = cr[2] * k
		cd.position = cr[1] * k
		cd.size = cr[2] * k
	# панда — в круге рамки (центр 451,141, радиус 110), обрезана по кругу
	var pn := _portrait_node
	var r := 104.0 * k
	pn.custom_minimum_size = Vector2(r, r) * 2.0
	pn.size = pn.custom_minimum_size
	pn.position = _lvp(417, 198) * k - Vector2(r, r)
	var img: Control = pn.get_node("Img")
	# крупно, по пояс, как в референсе: верх шляпы у края круга, ниже груди — за рамкой
	var ps := (104.0 + 2.0) * 2.0 * k
	img.size = Vector2(ps, ps)
	img.position = Vector2(-2.0, -2.0) * k
	img.set_meta("rest", img.position)
	img.pivot_offset = Vector2(img.size.x / 2, img.size.y)
	if _lvref_ring:
		_level_screen.move_child(_lvref_ring, pn.get_index() + 1)
		if _lvref_thumb:
			_level_screen.move_child(_lvref_thumb, _lvref_ring.get_index() + 1)
		_lvref_ring.queue_redraw()
	if _lvref_bg:
		_lvref_bg.queue_redraw()


## Панда: картинка с «дыханием». Позже заменим на версию из частей (голова, лапы, тело).
func _make_panda(height: float) -> Control:
	var holder := Control.new()
	var t: Texture2D = load("res://assets/art/panda.png")
	var w := height * t.get_width() / t.get_height()
	holder.custom_minimum_size = Vector2(w, height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := TextureRect.new()
	img.texture = t
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img.size = Vector2(w, height)
	img.pivot_offset = Vector2(w / 2, height)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	img.name = "Img"
	holder.add_child(img)
	if _attach_panda_anim(img):
		return holder
	var tw := img.create_tween().set_loops()
	tw.tween_property(img, "scale", Vector2(1.02, 0.975), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(img, "scale", Vector2(0.99, 1.02), 0.9).set_trans(Tween.TRANS_SINE)
	return holder


## Живая панда из кадров видео вместо картинки (если кадры есть). Холст кадра выше картинки
## в 1.5 раза — запас сверху под прыжки; низ (ноги) совпадает с низом картинки.
func _attach_panda_anim(img: TextureRect) -> bool:
	if not PandaAnim.available():
		return false
	img.texture = null
	var a := PandaAnim.new()
	a.name = "Anim"
	# размер — от картинки-места панды; пересчитывается, если место меняется (раньше панда «подстраивалась»)
	var fit := func() -> void:
		var h := img.size.y * 1.5
		var w := h * 280.0 / 336.0
		a.size = Vector2(w, h)
		a.position = Vector2(img.size.x / 2.0 - w / 2.0, img.size.y - h)
	fit.call()
	img.resized.connect(fit)
	img.add_child(a)
	return true


## Реакция панды: "combo" — подпрыгнуть, "win" — прыгать от радости, "sad" — поникнуть.
func _panda_react(kind: String) -> void:
	if _portrait_node == null:
		return
	var img: Control = _portrait_node.get_node("Img")
	var body := _portrait_node
	if _lvref() and Zoo.art("lvref_panda"):
		_panda_react_ref(kind, img)
		return
	if body.has_meta("react"):
		var old: Tween = body.get_meta("react")
		if old and old.is_valid():
			old.kill()
	img.rotation = 0.0
	img.position = img.get_meta("rest", Vector2(-10, -14))
	body.pivot_offset = Vector2(body.size.x / 2.0, body.size.y)
	body.scale = Vector2.ONE
	if kind == "reset":
		img.modulate = Color.WHITE
		if img.has_node("Anim"):
			img.get_node("Anim").play("idle")
		return
	if kind != "sad":
		img.modulate = Color.WHITE
	if img.has_node("Anim"):
		# живая панда: реакцию играет само видео, код добавляет только облачко эмоции
		var anim: Control = img.get_node("Anim")
		var vid := {"combo": "happy", "bigcombo": "happy", "goal": "happy", "win": "win", "sad": "sad", "nervous": "nervous",
			"special": "wow", "hello": "wave", "yawn": "yawn", "think": "think"}
		if vid.has(kind):
			anim.play(vid[kind])
		elif kind == "bad":
			var bt := body.create_tween()
			body.set_meta("react", bt)
			for i in 2:
				bt.tween_property(img, "rotation", -0.08, 0.08)
				bt.tween_property(img, "rotation", 0.08, 0.1)
			bt.tween_property(img, "rotation", 0.0, 0.08)
		var emo := {"combo": "hearts", "bigcombo": "stars", "goal": "check", "win": "stars", "sad": "rain",
			"nervous": "sweat", "special": "wow", "yawn": "zzz"}
		if emo.has(kind):
			_panda_emote(emo[kind])
		return
	var t := body.create_tween()
	body.set_meta("react", t)
	var squash := func(tw: Tween, sx: float, sy: float, d: float) -> void:
		tw.tween_property(body, "scale", Vector2(sx, sy), d).set_trans(Tween.TRANS_SINE)
	match kind:
		"combo", "bigcombo":
			# подготовка-присед, прыжок с вытягиванием, приземление со сплющиванием
			var hgt := -64.0 if kind == "bigcombo" else -42.0
			squash.call(t, 1.12, 0.86, 0.07)
			t.tween_property(img, "position:y", hgt, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			t.parallel().tween_property(body, "scale", Vector2(0.92, 1.1), 0.12)
			if kind == "bigcombo":
				t.parallel().tween_property(img, "rotation", TAU, 0.34).from(0.0)
			t.tween_property(img, "position:y", -14.0, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			squash.call(t, 1.14, 0.84, 0.06)
			t.tween_property(body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(img, "rotation", 0.0, 0.01)
			_panda_emote("hearts" if kind == "combo" else "stars")
		"special":
			# удивление: вытягивается вверх и покачивается
			squash.call(t, 0.9, 1.12, 0.08)
			t.parallel().tween_property(img, "rotation", -0.15, 0.08)
			t.tween_property(img, "rotation", 0.15, 0.12)
			t.tween_property(img, "rotation", 0.0, 0.1)
			t.parallel().tween_property(body, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_panda_emote("wow")
		"goal":
			# цель выполнена: радостный прыжок с поворотом
			squash.call(t, 1.1, 0.88, 0.07)
			t.tween_property(img, "position:y", -50.0, 0.18).set_ease(Tween.EASE_OUT)
			t.parallel().tween_property(img, "rotation", 0.25, 0.18)
			t.tween_property(img, "position:y", -14.0, 0.16).set_ease(Tween.EASE_IN)
			t.parallel().tween_property(img, "rotation", 0.0, 0.16)
			t.tween_property(body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_panda_emote("check")
		"bad":
			# неверный ход: качает головой
			for i in 2:
				t.tween_property(img, "rotation", -0.12, 0.08)
				t.tween_property(img, "rotation", 0.12, 0.1)
			t.tween_property(img, "rotation", 0.0, 0.08)
		"nervous":
			# мало ходов: дрожит, капля пота
			for i in 6:
				t.tween_property(img, "position:x", -4.0, 0.04)
				t.tween_property(img, "position:x", -16.0, 0.04)
			t.tween_property(img, "position:x", -10.0, 0.04)
			_panda_emote("sweat")
		"win":
			# танец с прыжками
			for i in 3:
				squash.call(t, 1.08, 0.9, 0.06)
				t.tween_property(img, "rotation", 0.2, 0.12)
				t.parallel().tween_property(img, "position:y", -40.0, 0.12)
				t.parallel().tween_property(body, "scale", Vector2(0.94, 1.08), 0.12)
				t.tween_property(img, "rotation", -0.2, 0.12)
				t.parallel().tween_property(img, "position:y", -14.0, 0.12)
			t.tween_property(img, "rotation", 0.0, 0.1)
			t.parallel().tween_property(body, "scale", Vector2.ONE, 0.2)
			_panda_emote("stars")
		"sad":
			squash.call(t, 1.06, 0.92, 0.4)
			t.parallel().tween_property(img, "rotation", -0.1, 0.4)
			t.parallel().tween_property(img, "modulate", Color(0.7, 0.72, 0.85), 0.4)
			_panda_emote("rain")
		"yawn":
			t.tween_property(body, "scale", Vector2(1.08, 0.92), 0.4)
			t.tween_property(body, "scale", Vector2.ONE, 0.5)
			_panda_emote("zzz")


## Реакции панды-портрета из референса: движение внутри круга (подпрыгнуть, покачать головой) + облачко.
func _panda_react_ref(kind: String, img: Control) -> void:
	var rest: Vector2 = img.get_meta("rest", img.position)
	if img.has_meta("react"):
		var old: Tween = img.get_meta("react")
		if old and old.is_valid():
			old.kill()
	img.position = rest
	img.rotation = 0.0
	img.modulate = Color.WHITE
	if kind == "reset":
		return
	var t := img.create_tween()
	img.set_meta("react", t)
	var up := 14.0 * _level_screen.size.x / LVW
	match kind:
		"combo", "bigcombo", "goal", "hello", "special":
			var n := 2 if kind == "bigcombo" else 1
			for i in n:
				t.tween_property(img, "position:y", rest.y - up, 0.13).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				t.tween_property(img, "position:y", rest.y, 0.16).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		"win":
			for i in 3:
				t.tween_property(img, "rotation", 0.08, 0.14)
				t.parallel().tween_property(img, "position:y", rest.y - up, 0.14)
				t.tween_property(img, "rotation", -0.08, 0.14)
				t.parallel().tween_property(img, "position:y", rest.y, 0.14)
			t.tween_property(img, "rotation", 0.0, 0.1)
		"bad":
			for i in 2:
				t.tween_property(img, "rotation", -0.06, 0.08)
				t.tween_property(img, "rotation", 0.06, 0.1)
			t.tween_property(img, "rotation", 0.0, 0.08)
		"nervous":
			for i in 6:
				t.tween_property(img, "position:x", rest.x - 3.0, 0.04)
				t.tween_property(img, "position:x", rest.x + 3.0, 0.04)
			t.tween_property(img, "position:x", rest.x, 0.04)
		"sad":
			t.tween_property(img, "position:y", rest.y + up * 0.6, 0.4)
			t.parallel().tween_property(img, "modulate", Color(0.75, 0.78, 0.9), 0.4)
		"yawn", "think":
			t.tween_property(img, "rotation", 0.05, 0.4)
			t.tween_property(img, "rotation", 0.0, 0.5)
	var emo := {"combo": "hearts", "bigcombo": "stars", "goal": "check", "win": "stars", "sad": "rain",
		"nervous": "sweat", "special": "wow", "yawn": "zzz"}
	if emo.has(kind):
		_panda_emote(emo[kind])


## Эмоция над пандой: кружок-облачко с иконкой выпрыгивает, чуть всплывает и тает.
func _panda_emote(kind: String) -> void:
	if _portrait_node == null or _bot:
		return
	for old in _portrait_node.get_children():
		if old.has_meta("emote"):
			old.queue_free()
	var e := Control.new()
	e.set_meta("emote", true)
	e.mouse_filter = Control.MOUSE_FILTER_IGNORE
	e.size = Vector2(64, 64)
	e.pivot_offset = Vector2(32, 56)
	e.position = Vector2(_portrait_node.size.x - 46, 8)
	var host: Control = _portrait_node
	if _lvref():
		# панда обрезана по кругу — облачко рисуем поверх экрана, у правого края рамки
		host = _level_screen
		e.position += _portrait_node.position + Vector2(18, -10)
		for old2 in _level_screen.get_children():
			if old2.has_meta("emote"):
				old2.queue_free()
	e.z_index = 5
	e.draw.connect(_draw_emote.bind(e, kind))
	host.add_child(e)
	e.scale = Vector2(0.2, 0.2)
	e.modulate.a = 0.0
	var t := e.create_tween()
	t.tween_property(e, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(e, "modulate:a", 1.0, 0.12)
	t.tween_property(e, "position:y", e.position.y - 14.0, 0.9).set_trans(Tween.TRANS_SINE)
	t.tween_property(e, "modulate:a", 0.0, 0.25)
	t.tween_callback(e.queue_free)


## Рисует облачко эмоции панды.
func _draw_emote(e: Control, kind: String) -> void:
	var font: Font = UiTheme.title_font()
	var c := Vector2(32, 30)
	# облачко с хвостиком к панде
	e.draw_circle(c + Vector2(0, 4), 29, Color(0, 0, 0, 0.25))
	e.draw_colored_polygon(PackedVector2Array([c + Vector2(-18, 14), c + Vector2(-4, 22), c + Vector2(-30, 38)]), Color("#5a3a08"))
	e.draw_circle(c, 29, Color("#5a3a08"))
	e.draw_circle(c, 26, Color.WHITE)
	e.draw_colored_polygon(PackedVector2Array([c + Vector2(-16, 14), c + Vector2(-5, 20), c + Vector2(-26, 34)]), Color.WHITE)
	match kind:
		"hearts":
			_draw_heart(e, c + Vector2(-7, 2), 11.0, Color("#ff3d5a"))
			_draw_heart(e, c + Vector2(9, -6), 8.0, Color("#ff7aa0"))
		"stars":
			Zoo.draw_star(e, c + Vector2(-6, 3), 13.0)
			Zoo.draw_star(e, c + Vector2(10, -8), 9.0)
		"wow", "check", "zzz":
			var t: String = "!"
			if kind == "check":
				var pts := PackedVector2Array([c + Vector2(-12, 0), c + Vector2(-3, 10), c + Vector2(13, -10)])
				e.draw_polyline(pts, Color("#1e6b2a"), 10.0, true)
				e.draw_polyline(pts, Color("#3fc25a"), 6.0, true)
			elif kind == "zzz":
				for i in 3:
					var fs := 14 + i * 5
					e.draw_string(font, c + Vector2(-16 + i * 9, 12 - i * 9), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#4a6fd8"))
			else:
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40)
				var p := c + Vector2(-ts.x / 2, 14)
				e.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 6, Color("#7a1a08"))
				e.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("#ffb21e"))
		"sweat":
			var d := c + Vector2(2, 2)
			e.draw_colored_polygon(PackedVector2Array([d + Vector2(0, -18), d + Vector2(-10, 2), d + Vector2(10, 2)]), Color("#3aa6ff"))
			e.draw_circle(d + Vector2(0, 4), 10.5, Color("#3aa6ff"))
			e.draw_circle(d + Vector2(-3, 1), 3.5, Color(1, 1, 1, 0.8))
		"rain":
			e.draw_circle(c + Vector2(-8, -4), 9, Color("#8a94a8"))
			e.draw_circle(c + Vector2(4, -7), 11, Color("#8a94a8"))
			e.draw_circle(c + Vector2(13, -2), 8, Color("#8a94a8"))
			e.draw_rect(Rect2(c + Vector2(-16, -4), Vector2(36, 9)), Color("#8a94a8"))
			for i in 3:
				var dp := c + Vector2(-9 + i * 9, 12 + (i % 2) * 4)
				e.draw_line(dp, dp + Vector2(-2, 7), Color("#3aa6ff"), 3.0, true)


func _draw_heart(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.5, -r * 0.2), r * 0.58, col)
	ci.draw_circle(c + Vector2(r * 0.5, -r * 0.2), r * 0.58, col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.05, 0), c + Vector2(r * 1.05, 0), c + Vector2(0, r * 1.05)]), col)
	ci.draw_circle(c + Vector2(-r * 0.6, -r * 0.4), r * 0.2, Color(1, 1, 1, 0.6))


func _panda_rest() -> Vector2:
	var top := _board_rest().y
	var h := clampf(top - 225.0, 120.0, 260.0)
	_panda.custom_minimum_size = Vector2(h * 0.84, h)
	var img: Control = _panda.get_node("Img")
	img.size = _panda.custom_minimum_size
	img.pivot_offset = Vector2(img.size.x / 2, img.size.y)
	return Vector2(_level_screen.size.x - h * 0.84 - 10, top - h + 18)


## Объёмная карточка шапки: лента-заголовок сверху, кремовое «окно» внутри деревянной рамки.
func _hud_card(title: String, art := "") -> PanelContainer:
	var at := Zoo.art(art) if art != "" else null
	if at:
		# плашка из листа элементов уровня: без подписи, содержимое — в кремовом поле
		var o := PanelContainer.new()
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 26
		e.content_margin_right = 26
		e.content_margin_top = 48
		e.content_margin_bottom = 26
		o.add_theme_stylebox_override("panel", e)
		o.custom_minimum_size = Vector2(0, 168)
		var b := PanelContainer.new()
		b.name = "Body"
		b.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		o.add_child(b)
		# рисуем по 9 частям: углы с лапкой и листьями не растягиваются, тянется только середина
		var nsb := StyleBoxTexture.new()
		nsb.texture = at
		nsb.texture_margin_left = 150
		nsb.texture_margin_right = 150
		nsb.texture_margin_top = 170
		nsb.texture_margin_bottom = 110
		o.draw.connect(func() -> void:
			o.draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.5, 0.5))
			o.draw_style_box(nsb, Rect2(Vector2.ZERO, o.size * 2.0))
			o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
		o.resized.connect(o.queue_redraw)
		return o
	var outer := PanelContainer.new()
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 58
	sb.content_margin_bottom = 18
	outer.add_theme_stylebox_override("panel", sb)
	outer.custom_minimum_size = Vector2(0, 190)
	var inner := PanelContainer.new()
	inner.name = "Body"
	inner.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	outer.add_child(inner)
	var tex: Texture2D = load("res://assets/art/ui_card.png")
	var font: Font = UiTheme.title_font()
	outer.draw.connect(func() -> void:
		outer.draw_texture_rect(tex, Rect2(Vector2.ZERO, outer.size), false)
		var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var tp := Vector2(outer.size.x / 2 - ts.x / 2, outer.size.y * 0.165)
		outer.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 7, Color("#1e5a2a"))
		outer.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE))
	outer.resized.connect(outer.queue_redraw)
	return outer

## Живая панда в шапке (без рамки): дышит, моргает-подпрыгивает, реагирует на игру.
func _hud_panda() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(190, 200)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img := TextureRect.new()
	img.name = "Img"
	img.texture = load("res://assets/art/panda.png")
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img.size = Vector2(210, 240)
	img.position = Vector2(-10, -14)
	if Zoo.art("lv_arch") and Zoo.art("lv_goals"):
		# панда внутри арки: ноги на основании арки, голова под сводом
		img.size = Vector2(112, 132)
		img.position = Vector2(39, 50)
	img.set_meta("rest", img.position)
	img.pivot_offset = Vector2(img.size.x / 2, img.size.y)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(img)
	if Zoo.art("lvref_panda"):
		# панда из референса (по пояс, большой палец вверх): дышит и реагирует движением, кадров видео нет
		img.texture = Zoo.art("lvref_panda")
		img.stretch_mode = TextureRect.STRETCH_SCALE
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
				_panda_react("hello"))
		var br := img.create_tween().set_loops()
		br.tween_property(img, "scale", Vector2(1.012, 0.988), 1.1).set_trans(Tween.TRANS_SINE)
		br.tween_property(img, "scale", Vector2(0.995, 1.01), 1.1).set_trans(Tween.TRANS_SINE)
		return c
	if _attach_panda_anim(img):
		# нажатие на панду — машет «привет»
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		c.gui_input.connect(func(ev: InputEvent) -> void:
			if (ev is InputEventMouseButton or ev is InputEventScreenTouch) and ev.pressed:
				_panda_react("hello"))
		return c
	var idle := img.create_tween().set_loops()
	idle.tween_property(img, "scale", Vector2(1.03, 0.97), 0.8).set_trans(Tween.TRANS_SINE)
	idle.tween_property(img, "scale", Vector2(0.98, 1.03), 0.8).set_trans(Tween.TRANS_SINE)
	c.set_meta("idle", idle)
	return c


## Портрет панды в арке с золотой рамкой (вырезаем голову из общей картинки).
func _portrait() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(170, 178)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = load("res://assets/art/panda.png")
	var head := AtlasTexture.new()
	head.atlas = tex
	var tw := float(tex.get_width())
	head.region = Rect2(tw * 0.18, 0, tw * 0.64, tw * 0.6)
	c.draw.connect(func() -> void:
		var s := c.size
		var arch := PackedVector2Array()
		var r := s.x / 2 - 6
		for i in 25:
			var a := PI + PI * i / 24.0
			arch.append(Vector2(s.x / 2, r + 6) + Vector2(cos(a), sin(a)) * r)
		arch.append(Vector2(s.x - 6, s.y - 6))
		arch.append(Vector2(6, s.y - 6))
		var outer := PackedVector2Array()
		for v in arch:
			outer.append(Vector2(s.x / 2, s.y / 2) + (v - Vector2(s.x / 2, s.y / 2)) * 1.06)
		c.draw_colored_polygon(outer, Color("#5a3315"))
		c.draw_colored_polygon(arch, Color("#ffcf5a"))
		var inner := PackedVector2Array()
		for v in arch:
			inner.append(Vector2(s.x / 2, s.y / 2 + 4) + (v - Vector2(s.x / 2, s.y / 2)) * 0.88)
		c.draw_colored_polygon(inner, Color("#7fd0ff"))
		c.draw_texture_rect(head, Rect2(Vector2(14, 16), s - Vector2(28, 26)), false)
		c.draw_rect(Rect2(Vector2(10, s.y - 22), Vector2(s.x - 20, 16)), Color("#ffcf5a"))
		c.draw_rect(Rect2(Vector2(10, s.y - 10), Vector2(s.x - 20, 6)), Color("#c98a12")))
	return c


## Круглая кнопка-иконка главного экрана (почта, друзья, рейтинг, настройки, ремонт).
func _icon_button(kind: String, d: float, base: Color) -> Button:
	var btn := Button.new()
	btn.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.custom_minimum_size = Vector2(d, d)
	btn.size = Vector2(d, d)
	btn.draw.connect(_draw_icon_button.bind(btn, kind, d, base))
	btn.button_down.connect(btn.queue_redraw)
	btn.button_up.connect(btn.queue_redraw)
	return btn


var _gift_btn: Button
var _daily_auto := false
var _lside: VBoxContainer
var _rside: VBoxContainer
var _chest_btn: Button


## Рисует круглую кнопку-иконку (см. _icon_button).
func _draw_icon_button(btn: Button, kind: String, d: float, base: Color) -> void:
	var font: Font = UiTheme.title_font()
	var c := btn.size / 2 + (Vector2(0, 3) if btn.is_pressed() else Vector2.ZERO)
	var r := d * 0.46
	# готовые кнопки из арта владельца (лист UI главного экрана)
	var art_k := {"mail": "ui2_mail", "friends": "ui2_friends", "rating": "ui2_trophy", "settings": "ui2_settings",
		"gift": "ui2_gift", "chest": "ui2_chest", "repair": "ui2_hammer"}
	var akind := "back" if (kind == "repair" and _repair_mode) else kind
	if art_k.has(akind) and Zoo.art(art_k[akind]):
		btn.draw_set_transform(c + Vector2(0, 5), 0.0, Vector2(1.0, 0.3))
		btn.draw_circle(Vector2.ZERO, r * 0.95, Color(0, 0, 0, 0.0))
		btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var sc := 0.94 if btn.is_pressed() else 1.0
		Zoo.draw_art(btn, art_k[akind], c, d * sc)
		var k2 := r / 40.0
		match akind:
			"gift":
				if Save.daily_ready():
					_dot_badge(btn, c + Vector2(r * 0.72, -r * 0.72), "!")
			"chest":
				var bw := r * 1.5
				var br := Rect2(c + Vector2(-bw / 2, r * 0.82), Vector2(bw, 16 * k2))
				_tile(btn, br.grow(3), Color("#5a3a08"), 10 * k2)
				_tile(btn, br, Color("#fff1d0"), 8 * k2)
				var f := float(Save.chest_wins) / CHEST_WINS
				if f > 0:
					_tile(btn, Rect2(br.position, Vector2(br.size.x * f, br.size.y)), Color("#ffcf3a") if f >= 1.0 else Color("#5fd34a"), 8 * k2)
				if Save.chest_wins >= CHEST_WINS:
					_dot_badge(btn, c + Vector2(r * 0.72, -r * 0.72), "!")
			"repair":
				# плашка со звёздами под молотком — по референсу (x −100…+80, y +50…+95 от центра круга)
				var pr := Rect2(c + Vector2(-100, 52) * REF_K, Vector2(180, 44) * REF_K)
				var pt := Zoo.art("ui2_plate_s")
				if pt:
					btn.draw_texture_rect(pt, pr, false)
				else:
					_tile(btn, pr, Color("#fff1d0"), 14)
				Zoo.draw_star(btn, c + Vector2(-66, 74) * REF_K, 27.0 * REF_K)
				var t := str(Save.stars)
				var fs := 26
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var tp := Vector2(pr.position.x + pr.size.x * 0.62 - ts.x / 2, pr.get_center().y + fs * 0.36)
				btn.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color("#5a2a00"))
				btn.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		return
	btn.draw_circle(c + Vector2(0, 5), r, Color(0, 0, 0, 0.3))
	btn.draw_circle(c, r, Color("#ffcf5a"))
	btn.draw_circle(c, r * 0.88, base.darkened(0.4))
	btn.draw_circle(c + Vector2(0, -2), r * 0.82, base)
	btn.draw_circle(c + Vector2(0, -r * 0.2), r * 0.6, base.lightened(0.18))
	btn.draw_set_transform(c + Vector2(-r * 0.3, -r * 0.5), -0.4, Vector2(1.0, 0.5))
	btn.draw_circle(Vector2.ZERO, r * 0.3, Color(1, 1, 1, 0.4))
	btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var k := r / 40.0
	var ink := Color("#2b1a4a")
	var wh := Color.WHITE
	var mode := kind
	if kind == "repair" and _repair_mode:
		mode = "back"
	match mode:
		"mail":
			var rc := Rect2(c + Vector2(-20, -14) * k, Vector2(40, 28) * k)
			btn.draw_rect(rc.grow(2.5 * k), ink)
			btn.draw_rect(rc, wh)
			btn.draw_polyline(PackedVector2Array([rc.position, c + Vector2(0, 3) * k, rc.position + Vector2(rc.size.x, 0)]), ink, 3.0 * k, true)
		"friends":
			for dx in [-11.0, 11.0]:
				var hc := c + Vector2(dx, -7) * k
				btn.draw_circle(hc, 10 * k, ink)
				btn.draw_circle(hc, 8 * k, wh)
				btn.draw_circle(c + Vector2(dx, 17) * k, 13 * k, ink)
				btn.draw_circle(c + Vector2(dx, 17) * k, 11 * k, wh)
			btn.draw_rect(Rect2(c + Vector2(-26, 17) * k, Vector2(52, 14) * k), base)
		"rating":
			var cup := PackedVector2Array([c + Vector2(-17, -18) * k, c + Vector2(17, -18) * k, c + Vector2(11, 4) * k, c + Vector2(-11, 4) * k])
			btn.draw_colored_polygon(cup, Color("#ffd23f"))
			btn.draw_polyline(PackedVector2Array([cup[0], cup[1], cup[2], cup[3], cup[0]]), Color("#8a4a0a"), 3.0 * k, true)
			btn.draw_rect(Rect2(c + Vector2(-3, 4) * k, Vector2(6, 9) * k), Color("#ffd23f"))
			btn.draw_rect(Rect2(c + Vector2(-12, 13) * k, Vector2(24, 7) * k), Color("#ffd23f"))
			btn.draw_arc(c + Vector2(-17, -10) * k, 7 * k, PI / 2, PI * 1.5, 12, Color("#ffd23f"), 3.5 * k, true)
			btn.draw_arc(c + Vector2(17, -10) * k, 7 * k, -PI / 2, PI / 2, 12, Color("#ffd23f"), 3.5 * k, true)
		"gift":
			_draw_gift(btn, c + Vector2(0, 2) * k, 1.0 * k)
			if Save.daily_ready():
				_dot_badge(btn, c + Vector2(r * 0.72, -r * 0.72), "!")
		"chest":
			_draw_chest(btn, c + Vector2(0, 0) * k, 0.9 * k, Save.chest_wins >= CHEST_WINS)
			# полоска прогресса под кнопкой
			var bw := r * 1.7
			var br := Rect2(c + Vector2(-bw / 2, r * 0.78), Vector2(bw, 16 * k))
			_tile(btn, br.grow(2), Color("#2b1a4a"), 9 * k)
			var f := float(Save.chest_wins) / CHEST_WINS
			if f > 0:
				_tile(btn, Rect2(br.position, Vector2(br.size.x * f, br.size.y)), Color("#ffcf3a") if f >= 1.0 else Color("#5fd34a"), 8 * k)
			var bt := "%d/%d" % [Save.chest_wins, CHEST_WINS]
			var bts := font.get_string_size(bt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k))
			var bp := br.position + Vector2((br.size.x - bts.x) / 2, br.size.y - 2 * k)
			btn.draw_string_outline(font, bp, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), int(4 * k), ink)
			btn.draw_string(font, bp, bt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k), wh)
			if Save.chest_wins >= CHEST_WINS:
				_dot_badge(btn, c + Vector2(r * 0.72, -r * 0.72), "!")
		"settings":
			for i in 8:
				var a := TAU * i / 8.0
				btn.draw_set_transform(c + Vector2(cos(a), sin(a)) * 17 * k, a, Vector2.ONE)
				btn.draw_rect(Rect2(Vector2(-6, -5) * k, Vector2(12, 10) * k), wh)
				btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			btn.draw_circle(c, 17 * k, wh)
			btn.draw_circle(c, 7 * k, base.darkened(0.3))
		"repair":
			if not Zoo.draw_art(btn, "ui_hammer", c + Vector2(0, -6) * k, 52 * k):
				btn.draw_circle(c, 12 * k, wh)
			# звёзды на ремонт
			var t := str(Save.stars)
			var bc := c + Vector2(0, 24) * k
			Zoo.draw_star(btn, bc + Vector2(-14, 0) * k, 11 * k)
			btn.draw_string_outline(font, bc + Vector2(-2, 8) * k, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), int(7 * k), Color("#5a2a00"))
			btn.draw_string(font, bc + Vector2(-2, 8) * k, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(24 * k), Color.WHITE)
		"back":
			var pts := PackedVector2Array([c + Vector2(-20, 0) * k, c + Vector2(-2, -18) * k, c + Vector2(-2, -8) * k, c + Vector2(20, -8) * k,
				c + Vector2(20, 8) * k, c + Vector2(-2, 8) * k, c + Vector2(-2, 18) * k])
			btn.draw_colored_polygon(pts, wh)
			var cl := pts.duplicate()
			cl.append(pts[0])
			btn.draw_polyline(cl, ink, 3.0 * k, true)


## Круглая объёмная кнопка бустера: обод, глянец, иконка, красный кружок с количеством.
func _round_button(kind: String, base: Color) -> Button:
	var btn := Button.new()
	var is_pause := kind == "pause"
	if Zoo.art("lv_slot"):
		btn.custom_minimum_size = Vector2(104, 140) if is_pause else Vector2(120, 140)
	else:
		btn.custom_minimum_size = Vector2(104, 140) if is_pause else Vector2(134, 140)
	btn.flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.set_meta("count", -1)
	btn.set_meta("active", false)
	btn.set_meta("glow", 0.0)
	btn.draw.connect(func() -> void:
		var c := btn.size / 2 + Vector2(0, 2)
		var active: bool = btn.get_meta("active")
		var lift := Vector2(0, -12) if active else Vector2.ZERO
		# мягкая тень-«лужица» под слотом
		btn.draw_set_transform(c + Vector2(0, 54), 0.0, Vector2(1.0, 0.26))
		btn.draw_circle(Vector2.ZERO, 50.0 if not is_pause else 38.0, Color(0, 0, 0, 0.32 if not active else 0.2))
		btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if Zoo.art("lv_slot"):
			# слоты из листа элементов уровня (референс): деревянный круг с золотым ободком
			if is_pause:
				Zoo.draw_art(btn, "lv_pause", c, 120.0 * _level_screen.size.x / LVW if _lvref() else 100.0)
				return
			if active:
				var g2: float = btn.get_meta("glow")
				for i in 5:
					btn.draw_circle(c + lift, 72.0 - i * 5.0 + g2 * 6.0, Color(1.0, 0.86, 0.3, 0.07 + i * 0.03))
			var slot_art := {"hammer": "lv_hammer", "shuffle": "lv_shuffle", "rockets": "lv_rockets"}
			var sd := 174.0 * _level_screen.size.x / LVW if _lvref() else 124.0
			if slot_art.has(kind):
				Zoo.draw_art(btn, slot_art[kind], c + lift, sd)
			else:
				Zoo.draw_art(btn, "lv_slot", c + lift, sd)
				var ua := Zoo.art("ui_arrow")
				if ua:
					btn.draw_set_transform(c + lift, PI / 2.0 if kind == "cannon" else 0.0, Vector2.ONE)
					Zoo.draw_art(btn, "ui_arrow", Vector2.ZERO, 84.0)
					btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					_draw_tool_icon(btn, kind, c + lift)
			_draw_count(btn, c + lift)
			return
		if is_pause:
			if not Zoo.draw_art(btn, "ui_pause", c, 90.0):
				btn.draw_circle(c, 44, Color("#2f7fe0"))
			return
		# выбранный бустер: золотое сияние за слотом
		if active:
			var g: float = btn.get_meta("glow")
			for i in 5:
				btn.draw_circle(c + lift, 70.0 - i * 5.0 + g * 6.0, Color(1.0, 0.86, 0.3, 0.07 + i * 0.03))
		if not Zoo.draw_art(btn, "ui_slot_round", c + lift, 124.0):
			btn.draw_circle(c + lift, 58, Color("#8a5a2b"))
		_draw_tool_icon(btn, kind, c + lift + Vector2(0, -2))
		_draw_count(btn, c + lift))
	# отклик нажатия: кнопка вжимается и пружинит обратно
	btn.button_down.connect(func() -> void:
		btn.pivot_offset = btn.size / 2.0
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2(0.86, 0.86), 0.07).set_ease(Tween.EASE_OUT))
	btn.button_up.connect(func() -> void:
		btn.pivot_offset = btn.size / 2.0
		var t := btn.create_tween()
		t.tween_property(btn, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	return btn


## Скруглённый прямоугольник (StyleBoxFlat) — основа объёмных плиток.
## Скруглённые плашки рисуются очень часто (каждый кадр в анимированных окнах) —
## стиль кэшируется по цвету и радиусу, а не создаётся заново на каждый вызов.
static var _tile_cache := {}


func _tile(ci: CanvasItem, r: Rect2, col: Color, radius: float) -> void:
	var key := col.to_rgba32() * 64 + int(radius)
	var sb: StyleBoxFlat = _tile_cache.get(key)
	if sb == null:
		sb = StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(radius))
		sb.anti_aliasing = true
		if _tile_cache.size() > 2000:
			_tile_cache.clear()
		_tile_cache[key] = sb
	ci.draw_style_box(sb, r)


## Кружок с количеством бустера (зелёный) или «+» (оранжевый), если их нет.
func _draw_count(btn: Button, c: Vector2) -> void:
	var n: int = btn.get_meta("count")
	if n < 0:
		return
	var bc := c + Vector2(42, 42)
	var bsz := 50.0
	if _lvref():
		var kq := _level_screen.size.x / LVW
		bc = c + Vector2(55, 49) * kq
		bsz = 62.0 * kq
	var buy := n == 0
	if Zoo.art("lv_badge"):
		Zoo.draw_art(btn, "lv_plus" if buy else "lv_badge", bc, bsz)
		if not buy:
			var f2: Font = UiTheme.title_font()
			var t2 := str(n)
			var fs2 := 26 if n < 10 else 21
			var ts2 := f2.get_string_size(t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			var p2 := bc + Vector2(-ts2.x / 2, fs2 * 0.36)
			btn.draw_string_outline(f2, p2, t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, 6, Color("#14531c"))
			btn.draw_string(f2, p2, t2, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color.WHITE)
		return
	var rim := Color("#ffffff")
	var lo := Color("#c25a00") if buy else Color("#1f7a2c")
	var hi := Color("#ffb21e") if buy else Color("#5fd34a")
	btn.draw_circle(bc + Vector2(0, 4), 26, Color(0, 0, 0, 0.3))
	btn.draw_circle(bc, 26, Color("#5a3a08"))
	btn.draw_circle(bc, 24, rim)
	btn.draw_circle(bc, 20, lo)
	btn.draw_circle(bc + Vector2(0, -2), 18, hi)
	btn.draw_set_transform(bc + Vector2(-5, -9), -0.5, Vector2(1.0, 0.55))
	btn.draw_circle(Vector2.ZERO, 8, Color(1, 1, 1, 0.45))
	btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var f: Font = UiTheme.title_font()
	var t := "+" if buy else str(n)
	var fs := 30 if buy else (26 if n < 10 else 21)
	var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := bc + Vector2(-ts.x / 2, fs * 0.36)
	btn.draw_string_outline(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, lo.darkened(0.35))
	btn.draw_string(f, pos, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_tool_icon(ci: CanvasItem, kind: String, c: Vector2) -> void:
	var ink := Color("#3a2a1a")
	var art := {"hammer": "ui_hammer", "arrow": "ui_arrow", "cannon": "ui_arrow", "shuffle": "ui_shuffle", "rockets": "lv_rockets"}
	if art.has(kind) and Zoo.art(art[kind]):
		if kind == "cannon":
			ci.draw_set_transform(c, PI / 2.0, Vector2.ONE)
			Zoo.draw_art(ci, art[kind], Vector2.ZERO, 92.0)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			Zoo.draw_art(ci, art[kind], c, 92.0)
		return
	match kind:
		"hammer":
			ci.draw_set_transform(c, -0.6, Vector2.ONE)
			ci.draw_rect(Rect2(-6, -8, 12, 46), ink)
			ci.draw_rect(Rect2(-4, -6, 8, 42), Color("#c98a4b"))
			ci.draw_rect(Rect2(-24, -30, 48, 24), ink)
			ci.draw_rect(Rect2(-22, -28, 44, 20), Color("#b8c2d0"))
			ci.draw_rect(Rect2(-22, -28, 44, 6), Color("#e6edf5"))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"arrow", "cannon":
			var rot := 0.0 if kind == "arrow" else PI / 2.0
			ci.draw_set_transform(c, rot, Vector2.ONE)
			ci.draw_rect(Rect2(-24, -7, 48, 14), ink)
			ci.draw_rect(Rect2(-22, -5, 44, 10), Color("#ffe14d"))
			for sgn in [-1.0, 1.0]:
				var tip := PackedVector2Array([Vector2(sgn * 40, 0), Vector2(sgn * 20, -20), Vector2(sgn * 20, 20)])
				ci.draw_colored_polygon(tip, Color("#ff5a3c"))
				ci.draw_polyline(PackedVector2Array([tip[0], tip[1], tip[2], tip[0]]), ink, 3.0, true)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		"shuffle":
			for k in 2:
				var a0 := PI * k
				ci.draw_arc(c, 24, a0 + 0.3, a0 + PI - 0.2, 16, ink, 12.0, true)
				ci.draw_arc(c, 24, a0 + 0.3, a0 + PI - 0.2, 16, Color("#7fd0ff"), 7.0, true)
				var e := c + Vector2(cos(a0 + PI - 0.2), sin(a0 + PI - 0.2)) * 24
				var d := Vector2(cos(a0 + PI + 1.2), sin(a0 + PI + 1.2))
				ci.draw_colored_polygon(PackedVector2Array([e + d * 12, e + d.orthogonal() * 10, e - d.orthogonal() * 10]), Color("#7fd0ff"))
		"pause":
			for dx in [-12, 12]:
				ci.draw_rect(Rect2(c + Vector2(dx - 8, -22), Vector2(16, 44)), ink)
				ci.draw_rect(Rect2(c + Vector2(dx - 6, -20), Vector2(12, 40)), Color.WHITE)


func _layout_bar() -> void:
	if _lvref():
		# кнопки ровно на местах референса: центры 165, 364, 562 (слоты) и 775 (пауза), y = 150 px от низа
		var k := _level_screen.size.x / LVW
		_booster_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
		_booster_bar.add_theme_constant_override("separation", 0)
		var step := 185.0 * k
		for b in _booster_btns.values():
			b.custom_minimum_size = Vector2(step, 140)
		if _bar_pause:
			_bar_pause.custom_minimum_size = Vector2(2.0 * (710.0 * k - (150.0 * k - step / 2.0 + step * 3.0)), 140)
		_booster_bar.position = Vector2(150.0 * k - step / 2.0, _level_screen.size.y - 142.0 * k - 72.0)
		_booster_bar.size = Vector2(_level_screen.size.x, 140)
		return
	if Zoo.art("lv_tray") and _lv_goal_card:
		# 4 слота: центры 96, 216, 336, 456 px; пауза — 620 px (775 референса); лоток — центр 116 px от низа
		_booster_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
		_booster_bar.size = Vector2(_level_screen.size.x, 140)
		_booster_bar.position = Vector2(36, _level_screen.size.y - 116.0 - 70.0)
		if _bands:
			_bands.queue_redraw()
		return
	if Zoo.art("lv_tray"):
		# кнопки по центру лотка (центр лотка — 116 px от низа)
		_booster_bar.size = Vector2(_level_screen.size.x, 140)
		_booster_bar.position = Vector2(0, _level_screen.size.y - 116.0 - 70.0)
		if _bands:
			_bands.queue_redraw()
		return
	_booster_bar.size = Vector2(_level_screen.size.x, 140)
	_booster_bar.position = Vector2(0, _level_screen.size.y - 140.0 - 22.0)
	if _bands:
		_bands.queue_redraw()


func _pause_divider_x() -> float:
	if _bar_pause == null or not is_instance_valid(_bar_pause):
		return _level_screen.size.x - 150.0
	return _booster_bar.position.x + _bar_pause.position.x - 2.0


## Подставка бустеров: «парящий» лоток с закруглёнными углами, золотой кантом и бликом,
## а не сплошная полоса во всю ширину.
func _draw_tray(ci: CanvasItem, r: Rect2) -> void:
	_tile(ci, Rect2(r.position + Vector2(0, 8), r.size), Color(0, 0, 0, 0.38), 40.0)
	_tile(ci, r.grow(5.0), Color("#5a3a08"), 44.0)
	_tile(ci, r.grow(2.0), Color("#ffcf3a"), 42.0)
	_tile(ci, r.grow(0.0), Color("#fff1a8"), 40.0)
	var inner := r.grow(-3.0)
	var top_c := Color("#3aa152")
	var bot_c := Color("#14532a")
	var steps := 14
	for i in steps:
		var y0 := inner.position.y + inner.size.y * i / steps
		var band := Rect2(inner.position.x, y0, inner.size.x, inner.size.y / steps + 1.0)
		var rad := 37.0 if i == 0 or i == steps - 1 else 0.0
		_tile(ci, band, top_c.lerp(bot_c, float(i) / (steps - 1)), rad)
	# мягкий блик по верхнему краю и тёмная «ложбина» под кнопками
	_tile(ci, Rect2(inner.position + Vector2(26, 6), Vector2(inner.size.x - 52, 10)), Color(1, 1, 1, 0.22), 5.0)
	_tile(ci, Rect2(inner.position.x + 18, inner.end.y - 30, inner.size.x - 36, 18), Color(0, 0, 0, 0.16), 9.0)


## Полоса интерфейса: тёмно-зелёный градиент, золотая кайма со стороны поля.
func _draw_band(ci: CanvasItem, r: Rect2, bottom: bool) -> void:
	var top_c := Color("#1d6a35")
	var bot_c := Color("#0f4322")
	var steps := 12
	for i in steps:
		var y0 := r.position.y + r.size.y * i / steps
		ci.draw_rect(Rect2(r.position.x, y0, r.size.x, r.size.y / steps + 1), top_c.lerp(bot_c, float(i) / steps))
	# золотая кайма со стороны поля: тёмная линия, золото, тень на поле
	var gold_y := r.position.y if bottom else r.end.y - 6.0
	ci.draw_rect(Rect2(r.position.x, gold_y - 2.0, r.size.x, 10.0), Color("#5a3a08"))
	ci.draw_rect(Rect2(r.position.x, gold_y, r.size.x, 6.0), Color("#ffcf3a"))
	ci.draw_rect(Rect2(r.position.x, gold_y + 1.0, r.size.x, 2.0), Color("#fff1a8"))
	var sh_y := gold_y - 8.0 if bottom else gold_y + 8.0
	ci.draw_rect(Rect2(r.position.x, sh_y, r.size.x, 6.0), Color(0, 0, 0, 0.22))


func _refresh_boosters() -> void:
	for b in IN_BOOSTERS:
		var btn: Button = _booster_btns[b[0]]
		btn.set_meta("count", int(Save.boosters.get(b[0], 0)))
		btn.set_meta("active", _aiming == b[0])
		# пока целимся бустером — остальные кнопки приглушены
		var dim: bool = _aiming != "" and _aiming != b[0]
		btn.create_tween().tween_property(btn, "modulate", Color(1, 1, 1, 0.55) if dim else Color.WHITE, 0.15)
		btn.queue_redraw()


func _on_booster(kind: String) -> void:
	Sfx.play("click")
	if _state != "play" or _board.busy:
		return
	if _aiming == kind:
		_aiming = ""
		_board.target_cb = Callable()
		_hide_aim_banner()
		_refresh_boosters()
		return
	if _aiming != "":
		_hide_aim_banner()
	if int(Save.boosters.get(kind, 0)) <= 0:
		_board.input_enabled = false
		_dialog("Нет бустера", ["Купить 1 шт. за %d монет?" % BOOSTER_PRICE], [
			["%d монет" % BOOSTER_PRICE, "OrangeButton", func() -> void:
				if Save.spend(BOOSTER_PRICE):
					Save.add_booster(kind)
				_close_dialog(), Save.coins < BOOSTER_PRICE],
			["Реклама: +1", "PurpleButton", func() -> void:
				Ads.show_rewarded(func() -> void: Save.add_booster(kind))
				_close_dialog(), not Ads.is_ready()],
			["Закрыть", "Button", _close_dialog],
		])
		return
	if kind == "shuffle":
		Save.use_booster(kind)
		_refresh_boosters()
		_board.shuffle_now()
		return
	_aiming = kind
	_refresh_boosters()
	_show_aim_banner(kind)
	_board.target_cb = func(cell: Vector2i) -> void:
		_aiming = ""
		_hide_aim_banner()
		Save.use_booster(kind)
		_refresh_boosters()
		_board.booster_hit(kind, cell)


var _aim_banner: Control

const AIM_TEXT := {"hammer": ["Молот", "Коснись фишки или препятствия — разобьёт его!"],
	"arrow": ["Стрела", "Коснись клетки — очистит весь ряд!"],
	"cannon": ["Стрела", "Коснись клетки — очистит весь столбец!"],
	"rockets": ["Ракеты", "Коснись клетки — очистит весь ряд и столбец!"]}


## Монеты и звезда вылетают из центра экрана в счётчики; счётчики «набегают» с прошлых значений.
func _play_reward_fly(rw: Dictionary) -> void:
	if not _home.visible:
		return
	var coins: int = rw.get("coins", 0)
	var stars: int = rw.get("stars", 0)
	var from := size / 2.0
	var c_from := Save.coins - coins
	var s_from := Save.stars - stars
	for l in _coin_labels:
		l.text = str(c_from)
	if _stars_label:
		_stars_label.text = str(s_from)
	var targets := []
	if not _coin_labels.is_empty():
		targets.append(["ui_coin", _coin_labels[0], mini(12, maxi(4, coins / 15)), c_from, Save.coins])
	if _stars_label and stars > 0:
		targets.append(["ui_star", _stars_label, 1, s_from, Save.stars])
	for tg in targets:
		var tex := Zoo.art(tg[0])
		var lbl: Label = tg[1]
		var n: int = tg[2]
		var to := lbl.get_global_rect().position + Vector2(-20, lbl.size.y / 2)
		for i in n:
			var sp := Sprite2D.new()
			sp.texture = tex
			var k := (70.0 if tg[0] == "ui_star" else 48.0) / maxf(tex.get_width(), 1.0)
			sp.scale = Vector2(k, k) * 0.2
			sp.position = from
			sp.z_index = 70
			add_child(sp)
			var spread := from + Vector2(randf_range(-160, 160), randf_range(-140, 60))
			var tw := sp.create_tween()
			tw.tween_interval(i * 0.06)
			tw.tween_property(sp, "scale", Vector2(k, k) * 1.2, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(sp, "position", spread, 0.3).set_ease(Tween.EASE_OUT)
			tw.tween_property(sp, "position", to, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(sp, "scale", Vector2(k, k) * 0.7, 0.45)
			var idx := i
			tw.tween_callback(func() -> void:
				sp.queue_free()
				Sfx.play("coin", 1.0 + idx * 0.04, -8.0)
				var val := int(lerpf(tg[3], tg[4], float(idx + 1) / n))
				if lbl == _stars_label:
					lbl.text = str(val)
				else:
					for l in _coin_labels:
						l.text = str(val)
				lbl.pivot_offset = lbl.size / 2
				var bt := lbl.create_tween()
				bt.tween_property(lbl, "scale", Vector2(1.3, 1.3), 0.06)
				bt.tween_property(lbl, "scale", Vector2.ONE, 0.12))


## Плашка выбранного бустера: выезжает сверху на место шапки, крупная иконка + подсказка.
func _show_aim_banner(kind: String) -> void:
	_hide_aim_banner()
	if not AIM_TEXT.has(kind):
		return
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(_level_screen.size.x, 200)
	b.z_index = 15
	var font: Font = UiTheme.title_font()
	var info: Array = AIM_TEXT[kind]
	b.draw.connect(func() -> void:
		var w := b.size.x
		_draw_band(b, Rect2(0, 0, w, 196), false)
		var ic := Vector2(110, 100)
		b.draw_texture_rect(Board.fx_tex("glow"), Rect2(ic - Vector2(100, 100), Vector2(200, 200)), false, Color(1, 0.9, 0.5, 0.6))
		var icon := "ui_hammer" if kind == "hammer" else ("lv_rockets" if kind == "rockets" else "ui_arrow")
		if kind == "cannon":
			b.draw_set_transform(ic, -PI / 2.0, Vector2.ONE)
			Zoo.draw_art(b, icon, Vector2.ZERO, 130.0)
			b.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			Zoo.draw_art(b, icon, ic, 130.0)
		var tx := 210.0
		b.draw_string_outline(font, Vector2(tx, 78), info[0] + "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, 12, Color("#3a1a00"))
		b.draw_string(font, Vector2(tx, 78), info[0] + "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 48, Color("#ffe14d"))
		var words: PackedStringArray = (info[1] as String).split(" ")
		var line := ""
		var y := 122.0
		for wd in words:
			var test := (line + " " + wd).strip_edges()
			if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x > w - tx - 24 and line != "":
				b.draw_string_outline(font, Vector2(tx, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color("#0f3a1c"))
				b.draw_string(font, Vector2(tx, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
				line = wd
				y += 32
			else:
				line = test
		b.draw_string_outline(font, Vector2(tx, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 8, Color("#0f3a1c"))
		b.draw_string(font, Vector2(tx, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE))
	_level_screen.add_child(b)
	b.position = Vector2(0, -210)
	var t := b.create_tween()
	t.tween_property(b, "position:y", 0.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_aim_banner = b


func _hide_aim_banner() -> void:
	if _aim_banner and is_instance_valid(_aim_banner):
		var b := _aim_banner
		var t := b.create_tween()
		t.tween_property(b, "position:y", -210.0, 0.2).set_ease(Tween.EASE_IN)
		t.tween_callback(b.queue_free)
	_aim_banner = null


func _close_dialog() -> void:
	_clear_overlay()
	_refresh_boosters()
	if _state == "play":
		_board.input_enabled = true


## Рамка поля обнимает только занятые клетки (поле 6×10, 8×8 и т.п. — без пустых полос внутри рамки).
func _board_lo() -> Vector2i:
	if _board.hole.size() < Levels.W:
		return Vector2i.ZERO
	var lo := Vector2i(Levels.W, Levels.H)
	for x in Levels.W:
		for y in Levels.H:
			if not _board.hole[x][y]:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
	return lo if lo.x < Levels.W else Vector2i.ZERO


func _fit_board_to_shape() -> void:
	var lo := Vector2i(Levels.W, Levels.H)
	var hi := Vector2i(-1, -1)
	for x in Levels.W:
		for y in Levels.H:
			if not _board.hole[x][y]:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return
	# +10 px по краям — чтобы золотая обводка доски не обрезалась
	_board_clip.custom_minimum_size = Vector2(hi - lo + Vector2i.ONE) * Board.CELL + Vector2(20, 20)
	_board.position = -Vector2(lo) * Board.CELL + Vector2(10, 10)
	_board_clip.size = _board_clip.custom_minimum_size
	_board_frame.reset_size()
	_place_pause()


## Пауза — над левым верхним углом рамки поля, рядом с плашкой уровня.
func _place_pause() -> void:
	if _pause_btn == null:
		return
	var r := _board_rest()
	_pause_btn.position = Vector2(maxf(4.0, r.x - 4.0), r.y - 70.0)


## Поле масштабируется под экран: занимает всю ширину и свободную высоту между шапкой и бустерами.
## Клетки не крупнее, чем у полного поля 8 в ширину — узкое поле не раздувается.
func _board_scale() -> float:
	var s := _board_frame.get_combined_minimum_size()
	var free_top := 296.0
	var free_bottom := 222.0
	# с деревянной рамкой — поля по бокам, как в референсе (клетки поля занимают ~77% ширины экрана)
	var side := 84.0 if Zoo.art("lv_frame") else 4.0
	var k := minf((_level_screen.size.x - side * 2.0) / s.x, (_level_screen.size.y - free_top - free_bottom) / s.y)
	var pad := s.x - _board_clip.custom_minimum_size.x
	var k8 := (_level_screen.size.x - side * 2.0) / (8.0 * Board.CELL + pad)
	return clampf(minf(k, k8), 0.6, 1.35)


func _board_rest() -> Vector2:
	if _lv_goal_card and _lvref():
		_layout_level_ref()
		# клетки — ровно во внутренности рамки фона: (105, 400) px фона, клетка 86 px
		var kk := _level_screen.size.x / LVW
		var cellg := 78.75 * kk
		var ks := cellg / Board.CELL
		_board_frame.scale = Vector2(ks, ks)
		var lo := _board_lo()
		var clip_pos := _board_clip.position
		return _lvp(100, 462) * kk + Vector2(lo) * cellg - (clip_pos + Vector2(10, 10)) * ks
	if _lv_goal_card:
		_layout_level_ref()
		# поле по референсу: клетки 8 столбцов на 553 px (105…795 px референса), верх клеток на y=320
		# экран телефона выше референса — клетки чуть крупнее (8 столбцов на 600 px), поле по центру
		# между шапкой (низ плашек 220 px) и лотком (верх — 210 px от низа)
		var kr := 600.0 / (8.0 * Board.CELL)
		_board_frame.scale = Vector2(kr, kr)
		var sr := _board_frame.get_combined_minimum_size() * kr
		var top_y := 262.0
		var bot_y := _level_screen.size.y - 250.0
		return Vector2((_level_screen.size.x - sr.x) / 2.0, top_y + maxf(0.0, (bot_y - top_y - sr.y) * 0.5))
	var k := _board_scale()
	_board_frame.scale = Vector2(k, k)
	var s := _board_frame.get_combined_minimum_size() * k
	var free_top := 296.0
	# поле ближе к шапке, как в референсе (свободное место — больше снизу)
	var y := free_top + maxf(0.0, (_level_screen.size.y - free_top - 222.0 - s.y) * (0.3 if Zoo.art("lv_frame") else 0.5))
	return Vector2((_level_screen.size.x - s.x) / 2.0, y)


# ---------- экраны ----------

func _show_home() -> void:
	_state = "idle"
	Sfx.music("music_menu")
	Sfx.tense(false)
	_clear_overlay()
	_home.visible = true
	_level_screen.visible = false
	_board.input_enabled = false
	_refresh_home()
	if not _fly_reward.is_empty() and not _bot:
		var rw := _fly_reward
		_fly_reward = {}
		get_tree().create_timer(0.5).timeout.connect(_play_reward_fly.bind(rw))
	elif not _bot and Save.level >= 3 and Save.daily_ready() and not _daily_auto:
		# подарок дня сам открывается один раз за запуск (после обучающих уровней)
		_daily_auto = true
		get_tree().create_timer(0.6).timeout.connect(func() -> void:
			if _state == "idle" and _overlay.get_child_count() == 0:
				_show_daily())


func _try_play() -> void:
	Save.update_hearts()
	if Save.hearts > 0:
		_show_prelevel(Save.level)
		return
	var sec := Save.seconds_to_heart()
	_dialog("Нет жизней", ["Новая жизнь через %d:%02d" % [sec / 60, sec % 60]], [
		["Реклама: +1 жизнь", "PurpleButton", func() -> void:
			Ads.show_rewarded(func() -> void:
				Save.add_heart()
				_show_home()), not Ads.is_ready()],
		["Закрыть", "Button", _show_home],
	])


## Окно перед уровнем: цели и бустеры «до уровня» (ракета, бомба, шар появятся на поле в начале).
func _show_prelevel(n: int) -> void:
	_home.visible = true
	_level_screen.visible = false
	_pre_selected.clear()
	var lv := Levels.make(n)
	if Zoo.art("preref_window"):
		_show_prelevel_ref(n, lv)
		return
	var hard := int(lv.get("hard", 0))
	var v := _dialog("Уровень %d" % n, [], [
		["Играть", "GreenButton", func() -> void:
			_clear_overlay()
			_level_transition(n)],
	])
	_add_close_x(v, _show_home)
	var font: Font = UiTheme.title_font()
	var at := 0
	# плашка сложности
	if hard > 0:
		var hb := Control.new()
		hb.custom_minimum_size = Vector2(0, 90)
		var ht: Texture2D = load("res://assets/art/ui_hard.png")
		var htxt: String = ["", "Сложный уровень", "Очень сложный!"][hard]
		hb.draw.connect(func() -> void:
			var w := minf(hb.size.x, 420.0)
			var h := w * ht.get_height() / ht.get_width()
			var r := Rect2(Vector2(hb.size.x / 2 - w / 2, hb.size.y / 2 - h / 2), Vector2(w, h))
			hb.draw_texture_rect(ht, r, false)
			var ts := font.get_string_size(htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
			var p := Vector2(hb.size.x / 2 - ts.x / 2, hb.size.y / 2 + 11)
			hb.draw_string_outline(font, p, htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 9, Color("#5a0a0a"))
			hb.draw_string(font, p, htxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
			# пляшущие язычки огня по краям плашки и черепок-значок
			var tt := Time.get_ticks_msec() / 1000.0
			for side in [-1.0, 1.0]:
				var fc := Vector2(hb.size.x / 2 + side * (w / 2 - 6), hb.size.y / 2 + 6)
				for j in 3:
					var fh := 22.0 + 8.0 * sin(tt * 9.0 + j * 2.1 + side)
					var fx := fc + Vector2(side * (j - 1) * 9, 0)
					hb.draw_colored_polygon(PackedVector2Array([fx + Vector2(-9, 0), fx + Vector2(0, -fh), fx + Vector2(9, 0)]), Color(1, 0.4, 0.1, 0.9))
					hb.draw_colored_polygon(PackedVector2Array([fx + Vector2(-5, 0), fx + Vector2(0, -fh * 0.6), fx + Vector2(5, 0)]), Color(1, 0.9, 0.3))
			if hard >= 1:
				var sc := Vector2(hb.size.x / 2 - ts.x / 2 - 30, hb.size.y / 2)
				hb.draw_circle(sc, 15, Color("#3a0a0a"))
				hb.draw_circle(sc, 13, Color.WHITE)
				hb.draw_rect(Rect2(sc + Vector2(-8, 6), Vector2(16, 9)), Color.WHITE)
				for ex in [-5.0, 5.0]:
					hb.draw_circle(sc + Vector2(ex, -1), 4, Color("#3a0a0a"))
				for tx in [-4.0, 0.0, 4.0]:
					hb.draw_line(sc + Vector2(tx, 9), sc + Vector2(tx, 15), Color("#3a0a0a"), 1.5))
		_every_frame(hb)
		v.add_child(hb)
		v.move_child(hb, at)
		at += 1
	# цели — на кремовой карточке
	var gcard := _cream_card("Цель")
	v.add_child(gcard)
	v.move_child(gcard, at)
	at += 1
	var grow := HBoxContainer.new()
	grow.alignment = BoxContainer.ALIGNMENT_CENTER
	grow.add_theme_constant_override("separation", 16)
	gcard.get_child(0).add_child(grow)
	for g in lv.goals:
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(104, 108)
		var kind: String = g.kind
		var col: int = int(g.get("color", -1))
		var cnt := str(g.left)
		cell.draw.connect(func() -> void:
			cell.draw_texture_rect(Board.fx_tex("glow"), Rect2(Vector2(2, -6), Vector2(100, 100)), false, Color(1, 0.9, 0.6, 0.5))
			if kind == "color":
				var gt: Texture2D = Gem.tex("gem_%d" % col)
				if gt:
					cell.draw_texture_rect(gt, Rect2(Vector2(17, 6), Vector2(70, 70)), false)
			else:
				_draw_goal_icon(cell, "birdhouse" if kind == "item" and _level_has_birds(lv) else kind, Vector2(52, 42))
			var ts := font.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34)
			var p := Vector2(52 - ts.x / 2, 104)
			cell.draw_string_outline(font, p, cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, 10, Color("#2b2350"))
			cell.draw_string(font, p, cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE))
		grow.add_child(cell)
	if Save.streak > 0:
		# серия побед: дорожка с огоньками на 3, 5, 8 и 10 победах (бонус на старте)
		var sb := Control.new()
		sb.custom_minimum_size = Vector2(0, 92)
		var marks := [3, 5, 8, 10]
		sb.draw.connect(func() -> void:
			var st := mini(Save.streak, 10)
			var x0 := 70.0
			var x1 := sb.size.x - 40.0
			var y := 54.0
			var tt := "Серия побед: %d" % Save.streak
			sb.draw_string_outline(font, Vector2(x0 - 30, 22), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 6, Color("#6a3a10"))
			sb.draw_string(font, Vector2(x0 - 30, 22), tt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
			var br := Rect2(Vector2(x0, y - 9), Vector2(x1 - x0, 18))
			_tile(sb, br.grow(3), Color("#5a3a08"), 12)
			_tile(sb, br, Color("#e6dccb"), 9)
			var f := float(st) / 10.0
			_tile(sb, Rect2(br.position, Vector2(br.size.x * f, br.size.y)), Color("#ff8a1a"), 9)
			# огонёк-иконка слева
			var fc := Vector2(x0 - 34, y + 6)
			var fl := 1.0 + 0.1 * sin(Time.get_ticks_msec() / 110.0)
			sb.draw_colored_polygon(PackedVector2Array([fc + Vector2(-15, 4), fc + Vector2(0, -30 * fl), fc + Vector2(15, 4)]), Color("#ff5a1a"))
			sb.draw_circle(fc + Vector2(0, 4), 15, Color("#ff5a1a"))
			sb.draw_colored_polygon(PackedVector2Array([fc + Vector2(-8, 6), fc + Vector2(0, -14 * fl), fc + Vector2(8, 6)]), Color("#ffd23f"))
			sb.draw_circle(fc + Vector2(0, 6), 8, Color("#ffd23f"))
			for m in marks:
				var mx: float = x0 + (x1 - x0) * float(m) / 10.0
				var got: bool = st >= m
				var mc := Vector2(mx, y)
				sb.draw_circle(mc, 17, Color("#5a3a08"))
				sb.draw_circle(mc, 14, Color("#ffcf3a") if got else Color("#c9bba5"))
				var mt := str(m)
				var ms := font.get_string_size(mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
				sb.draw_string(font, mc + Vector2(-ms.x / 2, 7), mt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("#5a3a08") if got else Color.WHITE)
			var bonus := "бонус на старте!" if Save.streak >= 3 else "бонус с 3 побед"
			var bs := font.get_string_size(bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			sb.draw_string(font, Vector2(sb.size.x - bs.x - 20, 22), bonus, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#c25a00")))
		_every_frame(sb)
		v.add_child(sb)
		v.move_child(sb, at)
		at += 1
	# бустеры на старт — объёмные плитки на кремовой карточке, выбранный — с зелёной галочкой
	var bcard := _cream_card("Выбери бустеры")
	v.add_child(bcard)
	v.move_child(bcard, at)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	bcard.get_child(0).add_child(row)
	for b in PRE_BOOSTERS:
		var kind: String = b[0]
		var tex_name: String = {"pre_rocket": "rocket", "pre_bomb": "bomb", "pre_orb": "orb"}[kind]
		var t := Button.new()
		t.toggle_mode = true
		t.flat = true
		for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			t.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		t.custom_minimum_size = Vector2(124, 128)
		var cnt := int(Save.boosters.get(kind, 0))
		t.disabled = cnt <= 0
		t.draw.connect(func() -> void:
			var on := t.button_pressed
			var c := Vector2(62, 60)
			var r := Rect2(c - Vector2(54, 54), Vector2(108, 108))
			if on:
				t.draw_texture_rect(Board.fx_tex("glow"), r.grow(28), false, Color(0.6, 1.0, 0.5, 0.8))
			_tile(t, Rect2(r.position + Vector2(0, 7), r.size), Color(0, 0, 0, 0.3), 26.0)
			_tile(t, r.grow(4.0), Color("#1e6b2a") if on else Color("#5a3a08"), 28.0)
			_tile(t, r.grow(1.0), Color("#7dff8a") if on else Color("#ffcf3a"), 26.0)
			var inner := r.grow(-5.0)
			var top := Color("#eaffdd") if on else Color("#fff3d6")
			var bot := Color("#7fd86a") if on else Color("#f2b866")
			for i in 10:
				var y0 := inner.position.y + inner.size.y * i / 10.0
				_tile(t, Rect2(inner.position.x, y0, inner.size.x, inner.size.y / 10.0 + 1.0), top.lerp(bot, i / 9.0), 20.0 if i == 0 or i == 9 else 0.0)
			_tile(t, Rect2(inner.position + Vector2(10, 6), Vector2(inner.size.x - 20, 12)), Color(1, 1, 1, 0.55), 6.0)
			var it: Texture2D = Gem.tex(tex_name)
			var fade := Color(1, 1, 1, 0.45) if t.disabled else Color.WHITE
			if it:
				var k := 82.0 / maxf(it.get_width(), it.get_height())
				var sz := it.get_size() * k
				t.draw_texture_rect(it, Rect2(c - sz / 2, sz), false, fade)
			var bc := Vector2(104, 106)
			t.draw_circle(bc + Vector2(0, 3), 20, Color(0, 0, 0, 0.3))
			t.draw_circle(bc, 20, Color.WHITE)
			t.draw_circle(bc, 16, Color("#2f9e3a") if on else Color("#e8283c"))
			if on:
				t.draw_polyline(PackedVector2Array([bc + Vector2(-8, 0), bc + Vector2(-2, 7), bc + Vector2(9, -7)]), Color.WHITE, 4.5, true)
			else:
				var txt := str(cnt)
				var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
				t.draw_string(font, bc + Vector2(-ts.x / 2, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
		t.toggled.connect(func(on: bool) -> void:
			_pre_selected[kind] = on
			Sfx.play("special" if on else "click")
			t.queue_redraw()
			t.pivot_offset = t.size / 2
			var tw := t.create_tween()
			tw.tween_property(t, "scale", Vector2(1.18, 1.18), 0.08)
			tw.tween_property(t, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK))
		row.add_child(t)


## Кремовая карточка с заголовком (внутри окна): VBox — первый ребёнок.
func _cream_card(title: String) -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#fff6e3")
	sb.border_color = Color("#e6b45c")
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(22)
	sb.shadow_color = Color(0.35, 0.2, 0.05, 0.25)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color("#7a3d0a"))
	vb.add_child(l)
	return card


func _level_has_birds(lv: Dictionary) -> bool:
	return lv.get("birdhouse", false)


## Красный крестик в правом верхнем углу окна (над рамкой), появляется когда окно встало.
func _add_close_x(v: Control, on_press: Callable) -> void:
	var close := Button.new()
	close.flat = true
	for st in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	close.custom_minimum_size = Vector2(76, 76)
	close.z_index = 3
	close.size = Vector2(76, 76)
	close.draw.connect(func() -> void:
		var c := Vector2(38, 38)
		close.draw_circle(c + Vector2(0, 4), 27, Color(0, 0, 0, 0.3))
		if Zoo.draw_art(close, "ui_close", c, 60.0):
			return
		close.draw_circle(c, 34, Color("#ffcf3a"))
		close.draw_circle(c, 29, Color("#a0101c"))
		close.draw_circle(c + Vector2(0, -3), 25, Color("#e8283c"))
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			close.draw_line(c - d * 12, c + d * 12, Color("#5a0a12"), 11.0, true)
			close.draw_line(c - d * 12, c + d * 12, Color.WHITE, 7.0, true))
	close.pressed.connect(on_press)
	var box: Control = v.get_parent().get_parent()
	box.add_child(close)
	close.top_level = false
	var place := func() -> void: close.position = Vector2(box.size.x - 92, 112)
	box.resized.connect(place)
	place.call_deferred()
	get_tree().process_frame.connect(place, CONNECT_ONE_SHOT)
	# крестик показываем, когда окно уже встало на место (иначе мелькает в углу)
	close.modulate.a = 0.0
	var ct := close.create_tween()
	ct.tween_interval(0.45)
	ct.tween_callback(place)
	ct.tween_property(close, "modulate:a", 1.0, 0.15)


## Ряд наград: золотые ячейки с объёмными значками и числами (монеты «набегают»).
func _reward_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	var slot_t: Texture2D = load("res://assets/art/ui_slot_goal.png")
	var font: Font = UiTheme.title_font()
	var names := {"star": "звезда", "coin": "монеты", "streak": "серия"}
	for it in items:
		var kind: String = it[0]
		var target: int = it[1]
		var cell := Control.new()
		cell.custom_minimum_size = Vector2(128, 150)
		cell.set_meta("val", 0 if kind == "coin" else target)
		cell.draw.connect(func() -> void:
			cell.draw_texture_rect(slot_t, Rect2(Vector2(4, 0), Vector2(120, 120)), false)
			var c := Vector2(64, 50)
			match kind:
				"star":
					Zoo.draw_star(cell, c, 30.0)
				"coin":
					cell.draw_circle(c + Vector2(0, 3), 28, Color("#a86a08"))
					cell.draw_circle(c, 28, Color("#e09a12"))
					cell.draw_circle(c, 22, Color("#ffd23f"))
					cell.draw_circle(c + Vector2(-8, -8), 6, Color(1, 1, 1, 0.8))
				"streak":
					var flame := PackedVector2Array()
					for i in 24:
						var a := TAU * i / 24.0
						var r := 26.0 * (1.0 + 0.35 * maxf(0.0, -sin(a)))
						flame.append(c + Vector2(cos(a) * r * 0.75, sin(a) * r - 4))
					cell.draw_colored_polygon(flame, Color("#ff5a1a"))
					var inner := PackedVector2Array()
					for p in flame:
						inner.append(c + (p - c) * 0.55 + Vector2(0, 6))
					cell.draw_colored_polygon(inner, Color("#ffd23f"))
			var txt := ("+" if kind != "streak" else "") + str(int(cell.get_meta("val")))
			var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30)
			var p := Vector2(64 - ts.x / 2, 106)
			for d in range(4, 0, -1):
				cell.draw_string_outline(font, p + Vector2(0, d), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 9, Color("#2b2350"))
			cell.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 9, Color("#2b2350"))
			cell.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
			var ns: String = names[kind]
			var nts := font.get_string_size(ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
			cell.draw_string(font, Vector2(64 - nts.x / 2, 144), ns, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.INK))
		row.add_child(cell)
		# появление по очереди + счётчик монет
		cell.modulate.a = 0.0
		var tw := cell.create_tween()
		tw.tween_interval(0.25 + row.get_child_count() * 0.15)
		tw.tween_property(cell, "modulate:a", 1.0, 0.15)
		if kind == "coin":
			tw.tween_method(func(v: float) -> void:
				cell.set_meta("val", int(v))
				cell.queue_redraw(), 0.0, float(target), 0.6)
	return row


## Круглая золотая плашка «x2» (удвоение за рекламу), покачивается, чтобы её заметили.
func _x2_badge() -> Button:
	var b := Button.new()
	b.flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(62, 62)
	b.size = Vector2(62, 62)
	b.pivot_offset = Vector2(31, 31)
	b.scale = Vector2(0.78, 0.78)
	var font: Font = UiTheme.title_font()
	b.draw.connect(func() -> void:
		var c := Vector2(31, 31)
		b.draw_circle(c + Vector2(0, 4), 29, Color(0, 0, 0, 0.3))
		if not Zoo.draw_art(b, "ui_x2", c, 66.0):
			b.draw_circle(c, 29, Color("#8a2a9a"))
			b.draw_circle(c, 25, Color("#c04ad8"))
			b.draw_circle(c + Vector2(0, -5), 18, Color("#d97cec"))
			b.draw_arc(c, 28, 0, TAU, 32, Color("#ffcf3a"), 4.0, true)
		var t := "x2"
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var p := c + Vector2(-ts.x / 2, 9)
		b.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 7, Color("#3a0a48"))
		b.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE)
		# значок «видео» снизу
		var v := c + Vector2(0, 22)
		b.draw_colored_polygon(PackedVector2Array([v + Vector2(-5, -6), v + Vector2(7, 0), v + Vector2(-5, 6)]), Color.WHITE))
	var tw := b.create_tween().set_loops()
	tw.tween_property(b, "rotation", 0.15, 0.25)
	tw.tween_property(b, "rotation", -0.15, 0.25)
	tw.tween_property(b, "rotation", 0.0, 0.2)
	tw.tween_interval(0.8)
	return b


## Монеты вылетают из горки в окне победы и улетают вверх, к счётчику монет.
func _coin_rain() -> void:
	var tex := Zoo.art("ui_coin")
	if tex == null or _bot:
		return
	var from := size / 2 + Vector2(60, 0)
	var to := Vector2(size.x * 0.5, 40)
	for i in 14:
		var s := Sprite2D.new()
		s.texture = tex
		var k := 46.0 / tex.get_width()
		s.scale = Vector2(k, k) * 0.2
		s.position = from
		s.z_index = 30
		_overlay.add_child(s)
		var mid := from + Vector2(randf_range(-220, 220), randf_range(-200, -60))
		var tw := s.create_tween()
		tw.tween_interval(0.9 + i * 0.06)
		tw.tween_property(s, "scale", Vector2(k, k), 0.12).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(s, "position", mid, 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position", to, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(s, "scale", Vector2(k, k) * 0.6, 0.45)
		tw.tween_callback(func() -> void:
			Sfx.play("coin", 1.0 + i * 0.03, -10.0)
			s.queue_free())


## Выход из уровня без победы стоит жизнь.
func _quit_level(then: Callable) -> void:
	Save.lose_heart()
	Save.streak = 0
	Save.store()
	then.call()


func _refresh_coins() -> void:
	for l in _coin_labels:
		l.text = str(Save.coins)


func _start_level(n: int) -> void:
	if _board:
		_board.call_deferred("warm_fx")
	_clear_overlay()
	_home.visible = false
	_level_screen.visible = true
	_level = Levels.make(n)
	Sfx.music("music_level")
	Sfx.tense(false)
	_moves = _level.moves
	_level_label.text = "Уровень %d" % n
	_board.fx = _fx
	_board.setup(_level)
	_fit_board_to_shape()
	# уровень 1: сразу показать первый ход (он даёт ракету)
	if _level.n == 1 and not _bot:
		get_tree().create_timer(2.2).timeout.connect(func() -> void:
			if is_instance_valid(_board) and _board.hint_move.size() == 2:
				_board.show_hint())
	_board.input_enabled = true
	_board_frame.position = _board_rest() + Vector2(0, size.y)
	var fly := _board_frame.create_tween()
	fly.tween_property(_board_frame, "position", _board_rest(), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_board.drop_in()
	_panda.position = _panda_rest()
	_panda_react("reset")
	_build_goals()
	_update_moves()
	_aiming = ""
	_board.target_cb = Callable()
	# бонусы на старте прилетают на поле по очереди (после того как упадут фишки)
	var fly_kinds: Array = []
	for b in PRE_BOOSTERS:
		if _pre_selected.get(b[0], false) and Save.use_booster(b[0]):
			fly_kinds.append(b[2])
	# серия побед (ослаблено по плейтесту): 3 победы — ракета, 5 — ещё бомба, 8 — ещё шар
	var bonus := [[3, 1], [5, 3], [8, 4]]
	for b in bonus:
		if Save.streak >= b[0]:
			fly_kinds.append(b[1])
	# супер-бонус: 10 побед подряд — ещё один радужный шар и бабочка
	if Save.streak >= 10:
		fly_kinds.append(4)
		fly_kinds.append(5)
	for i in fly_kinds.size():
		if _bot:
			_board.spawn_specials(1, fly_kinds[i])
		else:
			_board.spawn_specials_animated(1, fly_kinds[i], 1.1 + i * 0.35)
	_pre_selected.clear()
	_refresh_boosters()
	_layout_bar()
	# кнопки бустеров выпрыгивают по очереди
	var bi := 0
	for btn: Control in _booster_bar.get_children():
		btn.pivot_offset = btn.custom_minimum_size / 2.0
		btn.scale = Vector2.ZERO
		var bt := btn.create_tween()
		bt.tween_interval(0.35 + bi * 0.09)
		bt.tween_property(btn, "scale", Vector2(1.15, 1.15), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		bt.tween_property(btn, "scale", Vector2.ONE, 0.1)
		bi += 1
	_state = "play"
	_intro_banner()


func _build_goals() -> void:
	for c in _goals_box.get_children():
		c.queue_free()
	_goal_views.clear()
	if _lvref():
		_build_goals_lvref()
		return
	for goal in _level.goals:
		var slot := PanelContainer.new()
		slot.theme_type_variation = "GoalSlot"
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		slot.add_child(v)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(66, 58)
		v.add_child(icon)
		if goal.kind == "color" or goal.kind == "item":
			var g: Node2D = Gem.new()
			g.color = goal.get("color", -1)
			g.size = 66.0
			g.position = Vector2(35, 31)
			icon.add_child(g)
			if goal.kind == "item":
				g.set_special(Gem.ITEM)
		else:
			var kind: String = goal.kind
			icon.draw.connect(func() -> void: _draw_goal_icon(icon, kind, Vector2(35, 31)))
		var l := Label.new()
		l.theme_type_variation = "TitleLabel"
		l.add_theme_font_size_override("font_size", 36)
		l.add_theme_constant_override("outline_size", 12)
		l.add_theme_color_override("font_outline_color", Color("#2a1440"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text = str(goal.left)
		if Zoo.art("lv_goals"):
			# число цели — крупно под иконкой, белое с тёмной обводкой (без плашки)
			l.add_theme_font_size_override("font_size", 30)
			l.add_theme_constant_override("outline_size", 10)
			l.add_theme_color_override("font_color", Color.WHITE)
			l.add_theme_color_override("font_outline_color", Color("#5a2a08"))
			l.custom_minimum_size = Vector2(66, 30)
			v.add_theme_constant_override("separation", -6)
			v.add_child(l)
		else:
			v.add_child(l)
		_goals_box.add_child(slot)
		_goal_views.append({"goal": goal, "label": l, "icon": icon, "shown": int(goal.left)})


## Цели как в референсе: иконки в ряд (шаг 91 px референса), под каждой — маленькая кремовая плашка с числом.
func _build_goals_lvref() -> void:
	# точно как в референсе: центры иконок x 92 / 183 / 273, y 165 (px референса), иконка ~86 px,
	# под ней число (без плашки). Меньше трёх целей — тот же шаг, по центру плашки.
	var k := _level_screen.size.x / LVW
	_goals_box.visible = false
	if _goals_ref_box == null:
		_goals_ref_box = Control.new()
		_goals_ref_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_level_screen.add_child(_goals_ref_box)
	var box := _goals_ref_box
	box.position = Vector2.ZERO
	for ch in box.get_children():
		ch.queue_free()
	var n: int = _level.goals.size()
	for i in n:
		var goal: Dictionary = _level.goals[i]
		var cx: float = 171.0 + (i - (n - 1) / 2.0) * 85.0
		var slot := Control.new()
		slot.set_meta("goal_ref", true)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.position = _lvp(cx - 40, 184) * k
		slot.size = Vector2(80, 100) * k
		box.add_child(slot)
		var icon := Control.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size = Vector2(80, 76) * k
		slot.add_child(icon)
		var ic := Vector2(40, 38) * k
		if goal.kind == "color" or goal.kind == "item":
			var g: Node2D = Gem.new()
			g.color = goal.get("color", -1)
			g.size = 74.0 * k
			g.position = ic
			icon.add_child(g)
			if goal.kind == "item":
				g.set_special(Gem.ITEM)
		else:
			var kind: String = goal.kind
			icon.draw.connect(func() -> void: _draw_goal_icon(icon, kind, ic, 70.0 * k))
		var pl := Control.new()
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pl.position = Vector2(9, 69) * k
		pl.size = Vector2(62, 30) * k
		# плашки под числом нет (указание владельца 2026-11-16): число прямо на креме, галочку ничто не закрывает
		slot.add_child(pl)
		var l := Label.new()
		l.theme_type_variation = "TitleLabel"
		l.add_theme_font_size_override("font_size", int(round(30.0 * k)))
		l.add_theme_constant_override("outline_size", maxi(4, int(round(8.0 * k))))
		l.add_theme_color_override("font_color", Color("#7a3e10"))
		l.add_theme_color_override("font_outline_color", Color("#fff6e0"))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.text = str(goal.left)
		pl.add_child(l)
		l.position = Vector2.ZERO
		l.size = pl.size
		l.pivot_offset = pl.size / 2
		_goal_views.append({"goal": goal, "label": l, "icon": icon, "shown": int(goal.left)})


func _draw_goal_icon(ci: CanvasItem, kind: String, c: Vector2, px := 54.0) -> void:
	match kind:
		"stone":
			if Gem.tex("ob_stone") == null:
				Board.draw_stone(ci, c, 24.0, 3)
				return
		"colorbox":
			Board.draw_colorbox(ci, c, 24.0, 0)
			return
		"birdhouse":
			if Gem.tex("ob_birdhouse") == null:
				Board.draw_birdhouse(ci, c, 24.0, 3)
				return
		"item":
			var et := Gem.tex("ob_item")
			if et == null:
				var g := Gem.new()
				g.size = 60.0
				g.position = c
				# рисуем яйцо-заглушку прямо в ci
				ci.draw_circle(c + Vector2(0, 3), 20, Color("#c98a12"))
				ci.draw_circle(c, 18, Color("#ffd23f"))
				g.free()
				return
	if GOAL_TEX.has(kind):
		var t: Texture2D = Gem.tex(GOAL_TEX[kind])
		if t:
			var sz := t.get_size()
			var k := px / maxf(sz.x, sz.y)
			ci.draw_set_transform(c, 0.0, Vector2(k, k))
			ci.draw_texture(t, -sz / 2)
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
	match kind:
		"crate":
			Board.draw_crate(ci, c, 24.0, 1)
		"vase":
			Board.draw_vase(ci, c, 26.0, 1)
		"chain":
			Board.draw_chain(ci, c, 30.0)
		"grass":
			ci.draw_rect(Rect2(c - Vector2(24, 24), Vector2(48, 48)), Color("#4cc24c"))
			for k in 3:
				var bx := c.x - 16 + k * 16
				ci.draw_line(Vector2(bx, c.y + 20), Vector2(bx - 5, c.y - 6), Color("#2e7d2e"), 4.0)
				ci.draw_line(Vector2(bx + 3, c.y + 20), Vector2(bx + 8, c.y - 2), Color("#2e7d2e"), 4.0)


func _update_moves() -> void:
	_moves_label.text = str(_moves)
	_moves_label.add_theme_color_override("font_color", Color("#ff6b6b") if _moves <= 5 else Color.WHITE)
	# последние 5 ходов: счётчик пульсирует и мигает красным
	if _moves <= 5 and _moves > 0 and not _moves_label.has_meta("blink"):
		var bt := _moves_label.create_tween().set_loops()
		bt.tween_property(_moves_label, "modulate", Color(1.4, 0.7, 0.7), 0.35)
		bt.parallel().tween_property(_moves_label, "scale", Vector2(1.12, 1.12), 0.35)
		bt.tween_property(_moves_label, "modulate", Color.WHITE, 0.35)
		bt.parallel().tween_property(_moves_label, "scale", Vector2.ONE, 0.35)
		_moves_label.set_meta("blink", bt)
	elif (_moves > 5 or _moves == 0) and _moves_label.has_meta("blink"):
		var old: Tween = _moves_label.get_meta("blink")
		if old and old.is_valid():
			old.kill()
		_moves_label.remove_meta("blink")
		_moves_label.modulate = Color.WHITE
		_moves_label.scale = Vector2.ONE


func _intro_banner() -> void:
	_board.input_enabled = false
	var l := Label.new()
	l.text = "Уровень %d" % _level.n
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 80)
	l.add_theme_constant_override("outline_size", 14)
	_banner(l)
	_panda_react("hello")
	await get_tree().create_timer(1.0).timeout
	if _state == "play":
		_board.input_enabled = true
		_show_tip()


const TIPS := {
	"crate": "Ящик ломается, когда рядом собираешь фишки. Бывает в несколько слоёв.",
	"grass": "Собирай фишки на газоне — газон расползается на соседние клетки. Покрой газоном все земляные клетки!",
	"vase": "Горшок трескается от совпадений рядом. Разбитый горшок раскидывает газон вокруг.",
	"chain": "Лианы держат фишку — её нельзя двигать. Собери её в ряд или взорви, чтобы освободить.",
	"bush": "Куст ломается от совпадений рядом и раскидывает много газона вокруг.",
	"flower": "Сначала бутон распускается, потом цветок собирается. Собирай фишки рядом.",
	"shell": "Ракушка открывается от совпадений рядом, второй удар забирает жемчужину.",
	"item": "Доведи золотые яйца и птиц до самого низа поля — убирай фишки под ними.",
	"ice": "Лёд под фишками. Убери фишку над льдом — лёд растает.",
	"stone": "Камень не боится обычных совпадений! Разбей его ракетой, бомбой, бабочкой или шаром.",
	"honey": "Мёд склеивает фишку и растекается, если его не трогать. Собирай фишки под мёдом каждый ход!",
	"cage": "В клетке птичка. Собирай фишки рядом, чтобы открыть клетку.",
	"jar": "Разбей банку — получишь монеты!",
	"safe": "Сейф прочный: нужно много ударов рядом или бустерами.",
	"colorbox": "Цветной ящик ломается только от совпадения своего цвета рядом (или от бустеров).",
	"birdhouse": "Скворечник: собирай фишки рядом. Сломаешь — вылетят 3 синие птички. Спусти их до низа поля!",
	"honey_more": "",
}


## Подсказка при первом появлении препятствия (запоминается, показывается один раз).
func _show_tip() -> void:
	if _bot:
		return
	var seen: Array = Save.seen_tips
	for g in _level.goals:
		var k: String = g.kind
		if _level.get("birdhouse", false) and k == "item":
			k = "birdhouse"
		if TIPS.has(k) and TIPS[k] != "" and k not in seen:
			seen.append(k)
			Save.seen_tips = seen
			Save.store()
			_board.input_enabled = false
			var v := _dialog("Новое: " + GOAL_NAMES.get(k, k), [TIPS[k]], [["Понятно", "GreenButton", func() -> void:
				_clear_overlay()
				_board.input_enabled = true]])
			var ic := Control.new()
			ic.custom_minimum_size = Vector2(0, 110)
			ic.draw.connect(func() -> void:
				_draw_goal_icon(ic, k, Vector2(ic.size.x / 2, 55)))
			ic.resized.connect(ic.queue_redraw)
			v.add_child(ic)
			v.move_child(ic, 0)
			return


func _banner(l: Label) -> void:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(l)
	l.pivot_offset = size / 2
	l.scale = Vector2(0.3, 0.3)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(0.6)
	tw.chain().tween_property(l, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(l.queue_free)


## «Осталось 5 ходов!» — красная плашка выезжает из-под шапки, держится и уезжает обратно (ввод не блокирует).
func _low_moves_banner() -> void:
	if _bot:
		return
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(440, 76)
	var y0 := 168.0
	b.position = Vector2((_level_screen.size.x - b.size.x) / 2.0, y0 - 90.0)
	b.modulate.a = 0.0
	var font: Font = UiTheme.title_font()
	b.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, b.size)
		_tile(b, Rect2(r.position + Vector2(0, 6), r.size), Color(0, 0, 0, 0.35), 38.0)
		_tile(b, r, Color("#5a1208"), 38.0)
		_tile(b, r.grow(-4), Color("#ffcf3a"), 34.0)
		_tile(b, r.grow(-7), Color("#c8261c"), 31.0)
		_tile(b, Rect2(r.position + Vector2(7, 7), Vector2(r.size.x - 14, r.size.y * 0.45)), Color("#ff6a4a"), 28.0)
		_tile(b, Rect2(r.position + Vector2(30, 11), Vector2(r.size.x - 60, 8)), Color(1, 1, 1, 0.35), 4.0)
		var t := "Осталось 5 ходов!"
		var fs := 36
		var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := Vector2((b.size.x - ts.x) / 2.0, b.size.y / 2.0 + fs * 0.36)
		b.draw_string_outline(font, p + Vector2(0, 3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color(0.25, 0.02, 0.0, 0.6))
		b.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 9, Color("#5a1208"))
		b.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	_level_screen.add_child(b)
	b.position.y = y0 + 84.0
	b.pivot_offset = b.size / 2.0
	b.scale = Vector2(0.3, 0.3)
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(b, "modulate:a", 1.0, 0.12)
	t.tween_interval(1.3)
	t.tween_property(b, "position:y", y0 + 40.0, 0.3).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(b, "modulate:a", 0.0, 0.3)
	t.tween_callback(b.queue_free)


# ---------- игровые события ----------

## Объёмная надпись: «выдавленная» тень вниз, толстый тёмный контур, светлая заливка сверху и тёмная снизу, блик.
func _big_text(text: String, fsize: int, top: Color, bottom: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = UiTheme.title_font()
	var banner: Texture2D = load("res://assets/art/ui_banner.png")
	c.draw.connect(func() -> void:
		if _draw_word_art(c, text, fsize, font):
			return
		var fs := fsize
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var cx := c.size.x / 2.0
		var cy := c.size.y / 2.0
		if banner and not c.has_meta("no_banner"):
			var bw := minf(c.size.x - 6.0, ts.x + 170.0)
			var bh := bw * banner.get_height() / banner.get_width()
			# надпись помещается в «окно» плашки (≈ 72% ширины)
			while ts.x > bw * 0.74 and fs > 30:
				fs -= 2
				ts = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			# центр окна плашки — на 37% её высоты
			c.draw_texture_rect(banner, Rect2(Vector2(cx - bw / 2.0, cy - bh * 0.37), Vector2(bw, bh)), false)
		var depth := int(fs * 0.16)
		# визуальный центр заглавных букв ~0.36 кегля над базовой линией; объём тянется вниз — сдвигаем вверх на половину
		var p := Vector2(cx - ts.x / 2.0, cy + fs * 0.36 - depth / 2.0)
		var ink := Color("#2a1440")
		var side := bottom.darkened(0.45)
		for d in range(depth, 0, -1):
			c.draw_string_outline(font, p + Vector2(0, d), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, ink)
		for d in range(depth, 0, -1):
			c.draw_string(font, p + Vector2(0, d), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, side.lerp(bottom.darkened(0.2), 1.0 - float(d) / depth))
		c.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, ink)
		c.draw_string_outline(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(1, 1, 1, 0.95))
		c.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, bottom)
		# градиент: верх светлее — несколько полупрозрачных слоёв со сдвигом вверх
		for k in 3:
			c.draw_string(font, p + Vector2(0, -1 - k), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(top, 0.35))
		c.draw_string(font, p + Vector2(-2, -5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.18)))
	c.resized.connect(c.queue_redraw)
	return c


## Надписи-картинки (ИИ-арт) вместо шрифта. «Уровень N» = слово-картинка + число.
const TXT_ART := {"Отлично!": "txt_otlichno", "Супер!": "txt_super", "Невероятно!": "txt_neveroyatno",
	"Потрясающе!": "txt_potryasayushche", "Здорово!": "txt_zdorovo", "Молодец!": "txt_molodec",
	"Уровень пройден!": "txt_uroven_proyden", "Уровень": "txt_uroven"}


func _draw_word_art(c: Control, text: String, fsize: int, font: Font) -> bool:
	var key := text
	var num := ""
	if text.begins_with("Уровень ") and not TXT_ART.has(text):
		key = "Уровень"
		num = text.substr(8)
	if not TXT_ART.has(key):
		return false
	var t := Zoo.art(TXT_ART[key])
	if t == null:
		return false
	var h := fsize * 1.75
	var w := t.get_width() * h / t.get_height()
	var nh := h * 0.62
	var nw := number_width(num, nh, font) if num != "" else 0.0
	var gap := nh * 0.12 if num != "" else 0.0
	var k := minf(1.0, (c.size.x - 10.0) / (w + gap + nw))
	h *= k; w *= k; nh *= k; nw *= k; gap *= k
	var x0 := c.size.x / 2.0 - (w + gap + nw) / 2.0
	c.draw_texture_rect(t, Rect2(Vector2(x0, c.size.y / 2.0 - h / 2.0), Vector2(w, h)), false)
	if num != "":
		draw_number(c, num, Vector2(x0 + w + gap, c.size.y / 2.0 + h * 0.04), nh, font)
	return true


## Все ли цифры 0–9 есть картинками (иначе числа рисуются шрифтом, чтобы стиль не смешивался).
static func digits_ready() -> bool:
	for i in 10:
		if Zoo.art("dig_%d" % i) == null:
			return false
	return true


static func number_width(s: String, h: float, font: Font) -> float:
	if digits_ready():
		var w := 0.0
		for ch in s:
			var t := Zoo.art("dig_" + ch)
			w += (t.get_width() * h / t.get_height() if t else h * 0.6) - h * 0.08
		return w + h * 0.08
	return font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, int(h * 1.25)).x


## Число по левому краю left_mid (центр по высоте) высотой h: картинки-цифры или объёмный шрифт.
static func draw_number(ci: CanvasItem, s: String, left_mid: Vector2, h: float, font: Font) -> void:
	if digits_ready():
		var x := left_mid.x
		for ch in s:
			var t := Zoo.art("dig_" + ch)
			if t == null:
				continue
			var w := t.get_width() * h / t.get_height()
			ci.draw_texture_rect(t, Rect2(Vector2(x, left_mid.y - h / 2.0), Vector2(w, h)), false)
			x += w - h * 0.08
		return
	var fs := int(h * 1.25)
	var p := left_mid + Vector2(0, fs * 0.36)
	for d in range(int(fs * 0.12), 0, -1):
		ci.draw_string_outline(font, p + Vector2(0, d), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#3a0a5a"))
	ci.draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#5a1a8a"))
	ci.draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff3dc"))


## Белая вспышка экрана на мощных взрывах.
func _flash(strength: float) -> void:
	var f := ColorRect.new()
	f.color = Color(1, 1, 0.92, strength)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(f)
	var t := f.create_tween()
	t.tween_property(f, "color:a", 0.0, 0.25)
	t.tween_callback(f.queue_free)


## Замедление на секунду для больших комбо.
func _slowmo() -> void:
	Engine.time_scale = 0.4
	await get_tree().create_timer(0.6, true, false, true).timeout
	Engine.time_scale = 1.0


func _on_combo(n: int) -> void:
	if n < 3 or _state != "play":
		return
	_panda_react("bigcombo" if n >= 5 else "combo")
	var i := mini(n - 3, 3)
	var l := _big_text(["Отлично!", "Супер!", "Невероятно!", "Потрясающе!"][i], 78 + mini(n, 6) * 5,
		[Color("#ffe14d"), Color("#8dff6a"), Color("#ff8ad8"), Color("#7fe3ff")][i],
		[Color("#ff9a1a"), Color("#21a83a"), Color("#c0359a"), Color("#2a7bd8")][i])
	_overlay.add_child(l)
	l.size = Vector2(size.x, 200)
	l.position = Vector2(0, _board_rest().y + 260)
	l.pivot_offset = l.size / 2
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2(1.1, 1.1), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2.ONE, 0.1)
	tw.tween_interval(0.35)
	tw.parallel().tween_property(l, "position:y", l.position.y - 40, 0.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


func _on_move() -> void:
	if _state != "play":
		return
	_moves = maxi(0, _moves - 1)
	_update_moves()
	if _moves == 5 or _moves == 3 or _moves == 1:
		_panda_react("nervous")
	if _moves == 5:
		Sfx.tense(true)
		_low_moves_banner()
	var tw := _moves_label.create_tween()
	tw.tween_property(_moves_label, "scale", Vector2(1.25, 1.25), 0.07)
	tw.tween_property(_moves_label, "scale", Vector2.ONE, 0.12)


func _on_gem_cleared(color: int, at: Vector2) -> void:
	for gv in _goal_views:
		var goal: Dictionary = gv.goal
		if goal.kind == "color" and goal.color == color and goal.left > 0:
			goal.left -= 1
			_fly_to_goal(gv, at, color)
			return


const GOAL_NAMES := {"stone": "камни", "colorbox": "цветные ящики", "birdhouse": "скворечник", "color": "фишки", "crate": "ящики", "vase": "горшки", "chain": "лианы", "grass": "газон", "item": "яйца",
	"ice": "лёд", "honey": "мёд", "safe": "сейфы", "jar": "банки", "cage": "клетки", "balloon": "шарики", "flower": "цветы", "bush": "кусты", "shell": "ракушки"}
const GOAL_TEX := {"crate": "ob_crate_0", "vase": "ob_pot_0", "chain": "ob_vines", "grass": "ob_tile_grass", "ice": "ob_tile_ice",
	"honey": "ob_honey", "safe": "ob_safe", "jar": "ob_jar", "cage": "ob_cage", "balloon": "ob_balloon", "flower": "ob_flower_0", "bush": "ob_bush", "shell": "ob_shell_0", "item": "item_egg"}


func _on_goal_hit(kind: String, at: Vector2) -> void:
	if kind == "honey_more":
		# мёд растёкся — цель «мёд» стала больше
		for gv in _goal_views:
			if gv.goal.kind == "honey":
				gv.goal.left += 1
				gv.shown = int(gv.shown) + 1
				(gv.label as Label).text = str(gv.shown)
		return
	if kind == "jar":
		Save.add_coins(25)
	for gv in _goal_views:
		var goal: Dictionary = gv.goal
		if goal.kind == kind and goal.left > 0:
			goal.left -= 1
			_fly_to_goal(gv, at, -1, kind)
			return


func _fly_to_goal(gv: Dictionary, from: Vector2, color: int, kind: String = "color") -> void:
	var icon: Control = gv.icon
	var target := icon.get_global_rect().get_center()
	if _flying > 14 or _bot:
		_goal_tick(gv)
		return
	_flying += 1
	var n: Node2D
	if color >= 0 or kind == "item":
		n = Gem.new()
		n.color = color
		n.size = 84.0
	else:
		n = Node2D.new()
		n.draw.connect(func() -> void: _draw_goal_icon(n, kind, Vector2.ZERO))
	n.position = _fx.to_local(from)
	_fx.add_child(n)
	if kind == "item":
		n.set_special(Gem.ITEM)
	var p0 := n.position
	var p2 := _fx.to_local(target)
	var p1 := p0.lerp(p2, 0.5) + Vector2(randf_range(-140, 140), -60)
	n.z_index = 8
	var last := [p0]
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2(1.25, 1.25), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(t: float) -> void:
		var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
		n.position = q
		n.scale = Vector2.ONE * lerpf(1.25, 0.65, t)
		if q.distance_to(last[0]) > 30.0 and _board:
			last[0] = q
			_board._sparkles(q, Color("#fff3b0"), 1), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_flying -= 1
		n.queue_free()
		_goal_tick(gv))


func _goal_tick(gv: Dictionary) -> void:
	gv.shown = maxi(int(gv.goal.left), int(gv.shown) - 1)
	var l: Label = gv.label
	if not is_instance_valid(l):
		return
	var icon: Control = gv.icon
	icon.pivot_offset = icon.size / 2
	if gv.shown <= 0 and not gv.get("done", false):
		gv["done"] = true
		l.text = " "
		_check_badge(icon)
		if _state == "play" and not _goals_done():
			_panda_react("goal")
		return
	if gv.shown > 0:
		l.text = str(gv.shown)
		# число цели «подпрыгивает» и вспыхивает золотом
		l.pivot_offset = l.size / 2
		var lt := l.create_tween()
		lt.tween_property(l, "scale", Vector2(1.3, 1.3), 0.06)
		lt.parallel().tween_property(l, "modulate", Color(1.5, 1.3, 0.6), 0.06)
		lt.tween_property(l, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		lt.parallel().tween_property(l, "modulate", Color.WHITE, 0.2)
	var tw := icon.create_tween()
	tw.tween_property(icon, "scale", Vector2(1.25, 1.25), 0.06)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.1)


## Объёмная зелёная галочка в круге поверх иконки выполненной цели (с «прыжком» и искрами).
func _check_badge(icon: Control) -> void:
	var b := Control.new()
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.size = Vector2(44, 44)
	b.position = Vector2(icon.size.x / 2.0 - 22, icon.size.y - 26)
	b.pivot_offset = Vector2(22, 22)
	b.draw.connect(func() -> void:
		var c := Vector2(22, 22)
		b.draw_circle(c + Vector2(0, 3), 21, Color(0, 0, 0, 0.3))
		if Zoo.draw_art(b, "ui_check", c, 46.0):
			return
		b.draw_circle(c, 21, Color("#1e6b2a"))
		b.draw_circle(c, 18, Color("#3fc25a"))
		b.draw_circle(c + Vector2(0, -4), 13, Color("#6fe07f"))
		var pts := PackedVector2Array([c + Vector2(-10, 0), c + Vector2(-3, 8), c + Vector2(11, -8)])
		b.draw_polyline(pts, Color("#1e5a2a"), 9.0, true)
		b.draw_polyline(pts, Color.WHITE, 5.5, true)
		b.draw_circle(c + Vector2(-8, -10), 3.5, Color(1, 1, 1, 0.75)))
	icon.add_child(b)
	b.scale = Vector2(0.1, 0.1)
	var t := b.create_tween()
	t.tween_property(b, "scale", Vector2(1.35, 1.35), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(b, "scale", Vector2.ONE, 0.12)
	_board._sparkles(_fx.to_local(icon.get_global_rect().get_center()), Color("#7dff8a"), 6) if _board else null


func _goals_done() -> bool:
	for goal in _level.goals:
		if goal.left > 0:
			return false
	return true


func _on_settled() -> void:
	if _board.holes() > 0:
		push_error("HOLES after settle: %d" % _board.holes())
	match _state:
		"play":
			if _goals_done():
				_begin_bonus()
			elif _moves <= 0:
				_board.input_enabled = false
				_state = "done"
				_panda_react("sad")
				await get_tree().create_timer(0.4).timeout
				_show_lose()
		"bonus":
			_state = "done"
			_show_win()


func _begin_bonus() -> void:
	_state = "bonus"
	_panda_react("win")
	_board.input_enabled = false
	var l := _big_text("Уровень пройден!", 76, Color("#ffe14d"), Color("#ff9a1a"))
	_overlay.add_child(l)
	l.size = size
	l.pivot_offset = size / 2
	l.scale = Vector2(0.3, 0.3)
	var bt := l.create_tween()
	bt.tween_property(l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	bt.tween_interval(0.6)
	bt.tween_property(l, "modulate:a", 0.0, 0.25)
	bt.tween_callback(l.queue_free)
	await get_tree().create_timer(1.0).timeout
	var bonus := _moves
	_level["bonus_coins"] = bonus * COINS_PER_MOVE
	# праздник: каждый оставшийся ход вылетает бабочкой из счётчика и превращает фишку в бабочку
	var n := mini(bonus, 12)
	var from := _moves_label.get_global_rect().get_center()
	var rtex: Texture2D = Gem.tex("propeller")
	for i in n:
		var cells: Array = []
		for x in _board.W:
			for y in _board.H:
				var g: Node2D = _board.gem_at(Vector2i(x, y))
				if g and g.special == Gem.NONE and not _board._chained(Vector2i(x, y)):
					cells.append(Vector2i(x, y))
		if cells.is_empty():
			break
		var cell: Vector2i = cells.pick_random()
		_moves -= 1
		_update_moves()
		var spr := Sprite2D.new()
		spr.texture = rtex
		if rtex:
			var k := 60.0 / maxf(rtex.get_width(), rtex.get_height())
			spr.scale = Vector2(k, k)
		spr.position = _fx.to_local(from)
		_fx.add_child(spr)
		var to := _fx.to_local(_board.get_global_transform_with_canvas() * _board.cell_pos(cell))
		var mid := (spr.position + to) / 2.0 + Vector2(randf_range(-120, 120), -90)
		var p0 := spr.position
		var tw := spr.create_tween()
		tw.tween_method(func(t: float) -> void:
			spr.position = p0.lerp(mid, t).lerp(mid.lerp(to, t), t)
			spr.rotation = sin(t * TAU * 2.0) * 0.25, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func() -> void:
			spr.queue_free()
			var g: Node2D = _board.gem_at(cell)
			if g and g.special == Gem.NONE:
				g.set_special(Gem.PROPELLER)
				g.scale = Vector2(1.5, 1.5)
				g.create_tween().tween_property(g, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK))
		await get_tree().create_timer(0.09).timeout
	_moves = 0
	_update_moves()
	await get_tree().create_timer(0.35).timeout
	_board.detonate_all_specials()


# ---------- окна ----------

## Переход между экранами: шторка из листьев с отпечатком лапы.
## Шторки из листьев: две половины съезжаются к центру, в середине — медальон с лапкой, потом расходятся.
func _transition(then: Callable) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.size = size
	root.z_index = 60
	add_child(root)
	var halves: Array = []
	for side in [-1, 1]:
		var h := _leaf_curtain(side)
		h.size = Vector2(size.x / 2.0 + 40.0, size.y)
		h.position = Vector2(-h.size.x if side < 0 else size.x, 0)
		root.add_child(h)
		halves.append(h)
	var medal := _paw_medal()
	medal.position = size / 2 - medal.size / 2
	medal.pivot_offset = medal.size / 2
	medal.scale = Vector2.ZERO
	root.add_child(medal)
	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(halves[0], "position:x", -40.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(halves[1], "position:x", size.x / 2.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(medal, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(medal, "rotation", TAU * 0.05, 0.08)
	tw.chain().tween_property(medal, "rotation", 0.0, 0.08)
	tw.chain().tween_callback(then)
	tw.chain().tween_interval(0.15)
	tw.chain().tween_property(medal, "scale", Vector2.ZERO, 0.14).set_ease(Tween.EASE_IN)
	tw.chain().tween_property(halves[0], "position:x", -halves[0].size.x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(halves[1], "position:x", size.x, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(root.queue_free)


## Половина шторки: тёмно-зелёная основа, ряды крупных объёмных листьев, золотой кант по внутреннему краю.
func _leaf_curtain(side: int) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + side
	var leaves: Array = []
	for row in 26:
		for col in 7:
			leaves.append([Vector2(col * 64.0 + rng.randf_range(-14, 14) + (32.0 if row % 2 else 0.0), row * 64.0 + rng.randf_range(-10, 10)),
				rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0), rng.randf_range(0.85, 1.25), rng.randi_range(0, 2)])
	var greens := [Color("#2f9e3a"), Color("#3fb84a"), Color("#56c95a")]
	var art := Zoo.art("ui_curtain")
	c.draw.connect(func() -> void:
		if art:
			# картинка: листья, золотой кант справа; для правой половины — зеркально
			var asz := art.get_size()
			var k := maxf(c.size.y / asz.y, c.size.x / asz.x)
			var w := asz.x * k
			# кант волнистый, за ним прозрачная полоска — сдвигаем к центру, чтобы половины сомкнулись
			var lap := w * 0.07
			if side < 0:
				c.draw_texture_rect(art, Rect2(Vector2(c.size.x - w + lap, 0), Vector2(w, asz.y * k)), false)
			else:
				c.draw_set_transform(Vector2(w - lap, 0), 0.0, Vector2(-1, 1))
				c.draw_texture_rect(art, Rect2(Vector2.ZERO, Vector2(w, asz.y * k)), false)
				c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			return
		c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("#1d6b2a"))
		for L in leaves:
			var p: Vector2 = L[0]
			if p.x > c.size.x + 40 or p.y > c.size.y + 40:
				continue
			c.draw_set_transform(p, L[1], Vector2(L[2], L[2]))
			var g: Color = greens[L[3]]
			var leaf := PackedVector2Array([Vector2(-46, 0), Vector2(-22, -24), Vector2(10, -26), Vector2(46, 0), Vector2(10, 26), Vector2(-22, 24)])
			c.draw_colored_polygon(leaf, g.darkened(0.35))
			var top := PackedVector2Array()
			for v in leaf:
				top.append(v * 0.9 + Vector2(-2, -3))
			c.draw_colored_polygon(top, g)
			c.draw_line(Vector2(-40, 0), Vector2(40, 0), g.darkened(0.3), 3.0)
			c.draw_line(Vector2(-14, -12), Vector2(14, -14), Color(1, 1, 1, 0.35), 4.0)
			c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# золотой кант по внутренней кромке
		var ex := c.size.x - 14.0 if side < 0 else 0.0
		c.draw_rect(Rect2(Vector2(ex, 0), Vector2(14, c.size.y)), Color("#a86a08"))
		c.draw_rect(Rect2(Vector2(ex + 3, 0), Vector2(8, c.size.y)), Color("#ffcf3a"))
		c.draw_rect(Rect2(Vector2(ex + 4, 0), Vector2(3, c.size.y)), Color(1, 1, 1, 0.5))
		# тень от канта внутрь шторки
		var sx := ex - 24.0 if side < 0 else 14.0
		c.draw_rect(Rect2(Vector2(sx, 0), Vector2(24, c.size.y)), Color(0, 0, 0, 0.18)))
	return c


## Круглый медальон с лапкой посередине закрытых шторок.
func _paw_medal() -> Control:
	var m := Control.new()
	m.size = Vector2(200, 200)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var slot: Texture2D = load("res://assets/art/ui_slot_round.png")
	m.draw.connect(func() -> void:
		var c := m.size / 2
		m.draw_circle(c + Vector2(0, 8), 96, Color(0, 0, 0, 0.3))
		if Zoo.draw_art(m, "ui_medallion", c, 200.0):
			return
		if slot:
			m.draw_texture_rect(slot, Rect2(Vector2.ZERO, m.size), false)
		var paw := Color("#ffd23f")
		var dark := Color("#8a4a0a")
		for k in 2:
			var col: Color = dark if k == 0 else paw
			var off := Vector2(0, 4) if k == 0 else Vector2.ZERO
			m.draw_circle(c + Vector2(0, 22) + off, 34, col)
			for d in [Vector2(-40, -14), Vector2(-15, -42), Vector2(15, -42), Vector2(40, -14)]:
				m.draw_circle(c + d + off, 15, col)
		m.draw_circle(c + Vector2(-10, 12), 9, Color(1, 1, 1, 0.55)))
	return m


func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()


func _dialog(title_text: String, lines: Array, buttons: Array) -> VBoxContainer:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.2, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(cc)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -38)
	cc.add_child(box)
	# лента-заголовок поверх окна
	var ribbon := Control.new()
	ribbon.custom_minimum_size = Vector2(480, 120)
	ribbon.z_index = 1
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rt: Texture2D = load("res://assets/art/ui_ribbon.png")
	var font: Font = UiTheme.title_font()
	ribbon.draw.connect(func() -> void:
		ribbon.draw_texture_rect(rt, Rect2(Vector2.ZERO, ribbon.size), false)
		var fs := 40
		var ts := font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		while ts.x > ribbon.size.x * 0.62 and fs > 26:
			fs -= 2
			ts = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		# центр полосы ленты — 32% её высоты; вычитаем половину объёма надписи
		var p := Vector2(ribbon.size.x / 2 - ts.x / 2, ribbon.size.y * 0.32 + fs * 0.36 - 2)
		for d in range(5, 0, -1):
			ribbon.draw_string_outline(font, p + Vector2(0, d), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#14451f"))
		ribbon.draw_string_outline(font, p, title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#14451f"))
		ribbon.draw_string(font, p, title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	box.add_child(ribbon)
	# окно: картинка растягивается по 9 частям
	var panel := PanelContainer.new()
	var sb := StyleBoxTexture.new()
	sb.texture = load("res://assets/art/ui_window.png")
	sb.texture_margin_left = 60
	sb.texture_margin_right = 60
	sb.texture_margin_top = 70
	sb.texture_margin_bottom = 60
	sb.content_margin_left = 54
	sb.content_margin_right = 54
	sb.content_margin_top = 70
	sb.content_margin_bottom = 48
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(580, 0)
	box.add_child(panel)
	box.move_child(ribbon, 1)
	box.move_child(panel, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	for line in lines:
		var l := Label.new()
		l.text = line
		l.theme_type_variation = "InkLabel"
		l.add_theme_font_size_override("font_size", 28)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.theme_type_variation = b[1]
		# все кнопки окна — одинаковые овалы
		btn.custom_minimum_size = Vector2(360, 80)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		btn.add_theme_font_size_override("font_size", 28)
		btn.disabled = b.size() > 3 and b[3]
		btn.pressed.connect(b[2])
		btn.pressed.connect(Sfx.play.bind("click"))
		v.add_child(btn)
	# лента сверху: переставляем — сначала лента, потом окно (окно уходит под ленту за счёт отрицательного отступа)
	box.move_child(ribbon, 0)
	box.pivot_offset = Vector2(300, 300)
	box.scale = Vector2(0.6, 0.6)
	box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return v


func _show_win() -> void:
	Sfx.tense(false)
	Sfx.play("win")
	var mult := 1 + int(_level.get("hard", 0))
	var coins := WIN_COINS * mult + int(_level.get("bonus_coins", 0))
	Save.level = _level.n + 1
	Save.stars += 1
	_fly_reward = {"coins": coins, "stars": 1}
	Save.streak += 1
	Save.chest_wins = mini(Save.chest_wins + 1, CHEST_WINS)
	Save.add_coins(coins)
	Save.vibrate(60)
	if Zoo.art("winref_window"):
		_show_win_ref(coins)
		return
	var v := _dialog("Уровень %d" % _level.n, [], [])
	# окно победы шире, лента выше — звезду на окне видно целиком
	var wpanel := v.get_parent() as Control
	wpanel.custom_minimum_size.x = 650
	(wpanel.get_parent() as Control).add_theme_constant_override("separation", -4)
	var font: Font = UiTheme.title_font()
	# крупная объёмная похвала
	var praise := _big_text(["Отлично!", "Здорово!", "Супер!", "Молодец!"][_level.n % 4], 88, Color("#ffe14d"), Color("#ff9a1a"))
	praise.custom_minimum_size = Vector2(0, 130)
	praise.set_meta("no_banner", true)
	# отступ сверху: звезда на окне не должна закрывать надпись
	var star_gap := Control.new()
	star_gap.custom_minimum_size = Vector2(0, 50)
	v.add_child(star_gap)
	v.add_child(praise)
	# большое число монет рядом с горкой монет на пеньке, число «набегает»
	var pile := Control.new()
	pile.custom_minimum_size = Vector2(0, 236)
	pile.set_meta("val", 0)
	pile.draw.connect(func() -> void:
		var cx := pile.size.x / 2
		var pile_art := Zoo.art("ui_coin_pile")
		# число + горка — одной группой строго по центру окна
		var txt0 := str(int(pile.get_meta("val")))
		var tw0 := font.get_string_size(str(coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 112).x
		if pile_art:
			var ps := pile_art.get_size() * (232.0 / pile_art.get_size().y)
			var group := tw0 + 16.0 + ps.x
			cx = pile.size.x / 2 - group / 2 + tw0 + 30.0
			# тёплое свечение и искры за монетами
			var glow := Board.fx_tex("glow")
			var gc := Vector2(cx - 14, 6) + ps / 2.0
			var pulse := 0.85 + 0.15 * sin(Time.get_ticks_msec() / 260.0)
			pile.draw_texture_rect(glow, Rect2(gc - Vector2(230, 170) * pulse, Vector2(460, 340) * pulse), false, Color(1.0, 0.92, 0.55, 0.85))
			var spk := Board.fx_tex("spark")
			for k in 7:
				var a := TAU * k / 7.0 + Time.get_ticks_msec() / 2400.0
				var sp := gc + Vector2(cos(a) * 170, sin(a) * 95)
				var sz := 18.0 + 10.0 * sin(Time.get_ticks_msec() / 300.0 + k)
				pile.draw_texture_rect(spk, Rect2(sp - Vector2(sz, sz) / 2, Vector2(sz, sz)), false, Color(1, 1, 0.85, 0.9))
			pile.draw_texture_rect(pile_art, Rect2(Vector2(cx - 14, 6), ps), false)
		# пенёк-подставка
		var base := Vector2(cx + 10, 168)
		if pile_art:
			base = Vector2(-9999, -9999)
		pile.draw_set_transform(base, 0.0, Vector2(1.0, 0.32))
		pile.draw_circle(Vector2(0, 30), 128, Color(0, 0, 0, 0.18))
		pile.draw_circle(Vector2.ZERO, 120, Color("#8a5326"))
		pile.draw_circle(Vector2(0, -10), 116, Color("#d9a066"))
		pile.draw_arc(Vector2(0, -10), 80, 0, TAU, 40, Color("#b07a47"), 6.0)
		pile.draw_arc(Vector2(0, -10), 40, 0, TAU, 32, Color("#b07a47"), 6.0)
		pile.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for leaf in [Vector2(-105, 4), Vector2(112, -2)]:
			pile.draw_set_transform(base + leaf, 0.5 * signf(leaf.x), Vector2.ONE)
			pile.draw_colored_polygon(PackedVector2Array([Vector2(-26, 0), Vector2(0, -14), Vector2(26, 0), Vector2(0, 14)]), Color("#4cc24c"))
			pile.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# горка монет
		var coins_at := [Vector2(40, 0), Vector2(80, 0), Vector2(120, 0), Vector2(60, -22), Vector2(100, -22), Vector2(80, -44), Vector2(40, -22), Vector2(120, -22), Vector2(80, -66)]
		for cp in coins_at:
			var c: Vector2 = base + Vector2(-40, -18) + cp
			pile.draw_set_transform(c, 0.0, Vector2(1.0, 0.55))
			pile.draw_circle(Vector2(0, 12), 26, Color("#a86a08"))
			pile.draw_circle(Vector2.ZERO, 26, Color("#e09a12"))
			pile.draw_circle(Vector2.ZERO, 20, Color("#ffd23f"))
			pile.draw_circle(Vector2(-8, -6), 5, Color(1, 1, 1, 0.8))
			pile.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# число
		var txt := txt0
		var fs := 112
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var p := Vector2(cx - 30 - tw0 + (tw0 - ts.x) / 2.0, 160)
		for d in range(12, 0, -1):
			pile.draw_string_outline(font, p + Vector2(0, d), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#2a1440"))
			pile.draw_string(font, p + Vector2(0, d), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#c98a12"))
		pile.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#2a1440"))
		pile.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff6d8"))
		# искры
		for k in 5:
			var sp := Vector2(cx - 120 + k * 60, 20 + (k % 2) * 30)
			pile.draw_circle(sp, 3.0, Color(1, 1, 0.8, 0.9)))
	v.add_child(pile)
	_every_frame(pile)
	var pt := pile.create_tween()
	pt.tween_interval(0.3)
	pt.tween_callback(Sfx.play.bind("coin"))
	pt.tween_method(func(val: float) -> void:
		pile.set_meta("val", int(val))
		pile.queue_redraw(), 0.0, float(coins), 0.7)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	v.add_child(gap)
	# две кнопки рядом: «Дальше» и «реклама x2»
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var go := Button.new()
	go.text = "Дальше"
	go.theme_type_variation = "GreenButton"
	go.custom_minimum_size = Vector2(230, 96)
	go.add_theme_font_size_override("font_size", 30)
	go.pressed.connect(_next_level)
	row.add_child(go)
	var ad := Button.new()
	ad.theme_type_variation = "OrangeButton"
	ad.custom_minimum_size = Vector2(230, 96)
	ad.text = "      %d" % (coins * 2)
	ad.add_theme_font_size_override("font_size", 30)
	ad.disabled = not Ads.is_ready()
	ad.draw.connect(func() -> void:
		# значок видео слева и «x2» справа
		var c := Vector2(44, ad.size.y / 2 - 4)
		if not Zoo.draw_art(ad, "ui_video", c, 50.0):
			ad.draw_rect(Rect2(c - Vector2(20, 14), Vector2(40, 28)), Color("#2b2350"))
			ad.draw_rect(Rect2(c - Vector2(17, 11), Vector2(34, 22)), Color("#5fa8ff"))
			ad.draw_colored_polygon(PackedVector2Array([c + Vector2(-6, -8), c + Vector2(9, 0), c + Vector2(-6, 8)]), Color.WHITE)
		var bc := Vector2(ad.size.x - 26, 18)
		if not Zoo.draw_art(ad, "ui_x2", bc, 38.0):
			ad.draw_circle(bc, 20, Color("#8a2a9a"))
			ad.draw_circle(bc, 16, Color("#c04ad8"))
		var ts := font.get_string_size("x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
		ad.draw_string_outline(font, bc + Vector2(-ts.x / 2, 8), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color("#3a0a48"))
		ad.draw_string(font, bc + Vector2(-ts.x / 2, 8), "x2", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
	ad.pressed.connect(func() -> void:
		ad.disabled = true
		Ads.show_rewarded(func() -> void:
			Save.add_coins(coins)
			var t := pile.create_tween()
			t.tween_method(func(val: float) -> void:
				pile.set_meta("val", int(val))
				pile.queue_redraw(), float(coins), float(coins * 2), 0.5)
			get_tree().create_timer(0.9).timeout.connect(_next_level)))
	row.add_child(ad)
	# красный крестик «домой» в углу окна
	_add_close_x(v, func() -> void: _transition(_show_home))
	# звезда и монеты летят вверх, конфетти
	var c := size / 2
	_confetti()
	_coin_rain()
	var star := Control.new()
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	star.draw.connect(func() -> void: Zoo.draw_star(star, Vector2.ZERO, 60.0))
	star.position = c - Vector2(0, 260)
	_overlay.add_child(star)
	star.scale = Vector2(0.2, 0.2)
	var st := star.create_tween()
	st.tween_property(star, "scale", Vector2(1.2, 1.2), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	st.tween_property(star, "rotation", TAU, 0.6)
	v.get_parent().get_parent().move_to_front()


## ---------- окно победы 1:1 по референсу (слои нарезаны из него: tools/winbuild.py) ----------
## Референс 852×1846 (references/screen_03_win.webp); координаты ниже — в его пикселях, те же в winbuild.py.
const WIN_W := 852.0
const WIN_Y0 := 380.0                       # верх слоя окна
const WIN_TOP := 196.0                      # верх центральной звезды — верх всей группы
const WIN_BOT := 1662.0                     # низ окна
const WIN_STARS := [Vector2(179, 263), Vector2(321, 196), Vector2(523, 263)]
const WIN_GO := Vector2(194, 1337)
const WIN_AD := Vector2(217, 1489)
const WIN_SEG := Vector2(255, 1250)         # 3-я зелёная клетка полоски сундука (с перегородками)
const WIN_SEG_P := 51.3                     # шаг клеток
const WIN_COINS_AT := Vector2(234, 1180)    # «+N» монет: левый край и базовая линия
const WIN_RAYS := Vector2(428, 300)         # центр лучей за звёздами


func _show_win_ref(coins: int) -> void:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.2, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	# вся группа (звёзды + окно) — в пикселях референса, масштаб k, по центру экрана
	var k := minf(size.x / WIN_W, (size.y - 16.0) / (WIN_BOT - WIN_TOP))
	var win := Control.new()
	win.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win.size = Vector2(WIN_W, 1846)
	win.position = Vector2(size.x / 2.0 - WIN_W / 2.0 * k, size.y / 2.0 - (WIN_TOP + WIN_BOT) / 2.0 * k)
	win.scale = Vector2(k, k)
	_overlay.add_child(win)
	var font: Font = UiTheme.title_font()
	# лучи и сияние за звёздами (медленно вращаются)
	var rays := Control.new()
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.modulate.a = 0.0
	rays.draw.connect(func() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		var glow := Board.fx_tex("glow")
		var pulse := 0.92 + 0.08 * sin(t * 2.2)
		rays.draw_texture_rect(glow, Rect2(WIN_RAYS - Vector2(330, 250) * pulse, Vector2(660, 500) * pulse), false, Color(1.0, 0.9, 0.45, 0.9))
		for i in 14:
			var a := TAU * i / 14.0 + t * 0.25
			var w := 0.11
			var poly := PackedVector2Array([WIN_RAYS, WIN_RAYS + Vector2(cos(a - w), sin(a - w)) * 420.0, WIN_RAYS + Vector2(cos(a + w), sin(a + w)) * 420.0])
			rays.draw_colored_polygon(poly, Color(1.0, 0.93, 0.55, 0.3)))
	win.add_child(rays)
	_every_frame(rays)
	# окно (рамка, лента, панда, плашка наград, сундук)
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2(0, WIN_Y0)
	body.size = Vector2(WIN_W, WIN_BOT - WIN_Y0)
	body.pivot_offset = Vector2(WIN_W / 2.0, 520.0)
	win.add_child(body)
	var wt := TextureRect.new()
	wt.texture = Zoo.art("winref_window")
	wt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(wt)
	# надпись на ленте
	var title := "Уровень %d пройден!" % _level.n
	var ribbon := Control.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size = body.size
	ribbon.draw.connect(func() -> void: _arc_text(ribbon, title, Vector2(425.0, 506.0 - WIN_Y0), 500.0, 58, Color("#6e0f12")))
	body.add_child(ribbon)
	# «+N» монет — набегает от 0
	var cn := Control.new()
	cn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cn.size = body.size
	cn.set_meta("val", 0)
	cn.draw.connect(func() -> void:
		var txt := "+%d" % int(cn.get_meta("val"))
		var fs := 84
		var p := WIN_COINS_AT - Vector2(0, WIN_Y0)
		for d in range(7, 0, -1):
			cn.draw_string_outline(font, p + Vector2(0, d), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#3d1a08"))
		cn.draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#3d1a08"))
		cn.draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	body.add_child(cn)
	var count_to := func(from: float, to: float, dur: float) -> void:
		var t := cn.create_tween()
		t.tween_method(func(val: float) -> void:
			cn.set_meta("val", int(val))
			cn.queue_redraw(), from, to, dur)
	# полоска сундука: зелёные клетки по числу побед, новая — вспыхивает
	var seg_t := Zoo.art("winref_seg")
	var segs := Control.new()
	segs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	segs.size = body.size
	segs.set_meta("flash", 0.0)
	var filled := Save.chest_wins
	segs.draw.connect(func() -> void:
		for i in filled:
			var p := WIN_SEG + Vector2((i - 2) * WIN_SEG_P, -WIN_Y0)
			var col := Color.WHITE
			if i == filled - 1:
				var f: float = segs.get_meta("flash")
				col = Color(1.0 + f, 1.0 + f, 1.0 + f * 0.5)
				if f > 0.0:
					var c := p + seg_t.get_size() / 2.0
					var sc := 1.0 + f * 0.25
					segs.draw_texture_rect(seg_t, Rect2(c - seg_t.get_size() * sc / 2.0, seg_t.get_size() * sc), false, col)
					continue
			segs.draw_texture_rect(seg_t, Rect2(p, seg_t.get_size()), false, col))
	body.add_child(segs)
	# кнопки
	var mk_btn := func(tex_name: String, at: Vector2) -> TextureButton:
		var b := TextureButton.new()
		b.texture_normal = Zoo.art(tex_name)
		b.position = at - Vector2(0, WIN_Y0)
		b.size = b.texture_normal.get_size()
		b.pivot_offset = b.size / 2.0
		b.button_down.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
		b.button_up.connect(func() -> void:
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		b.pressed.connect(Sfx.play.bind("click"))
		body.add_child(b)
		return b
	var go: TextureButton = mk_btn.call("winref_go", WIN_GO)
	go.pressed.connect(_next_level)
	var ad: TextureButton = mk_btn.call("winref_ad", WIN_AD)
	var ad_off := func() -> void:
		ad.disabled = true
		ad.modulate = Color(0.6, 0.6, 0.6, 0.85)
	if not Ads.is_ready():
		ad_off.call()
	ad.pressed.connect(func() -> void:
		ad_off.call()
		go.disabled = true
		Ads.show_rewarded(func() -> void:
			Save.add_coins(coins)
			Sfx.play("coin")
			count_to.call(float(coins), float(coins * 2), 0.5)
			get_tree().create_timer(0.9).timeout.connect(_next_level)))
	# звёзды
	var stars: Array = []
	for i in 3:
		var st := TextureRect.new()
		st.texture = Zoo.art("winref_star_%d" % i)
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.position = WIN_STARS[i]
		st.size = st.texture.get_size()
		st.pivot_offset = st.size / 2.0
		st.scale = Vector2.ZERO
		win.add_child(st)
		stars.append(st)
	# появление: окно «впрыгивает», потом по очереди звёзды, монеты набегают, клетка сундука вспыхивает
	body.scale = Vector2(0.6, 0.6)
	body.modulate.a = 0.0
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "modulate:a", 1.0, 0.15)
	tw.tween_property(rays, "modulate:a", 1.0, 0.3)
	for i in [0, 1, 2]:
		var st: TextureRect = stars[i]
		tw.tween_callback(func() -> void:
			Sfx.play("coin", 0.9 + 0.15 * i)
			_board._sparkles(_fx.to_local(st.get_global_rect().get_center()), Color("#fff3b0"), 8) if _board else null)
		tw.tween_property(st, "scale", Vector2(1.3, 1.3), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(st, "scale", Vector2.ONE, 0.1)
	tw.tween_callback(func() -> void:
		Sfx.play("coin")
		count_to.call(0.0, float(coins), 0.7))
	tw.tween_interval(0.5)
	tw.tween_method(func(f: float) -> void:
		segs.set_meta("flash", f)
		segs.queue_redraw(), 1.0, 0.0, 0.45)
	# звёзды слегка «дышат»
	for i in 3:
		var st: TextureRect = stars[i]
		var bt := st.create_tween().set_loops()
		bt.tween_interval(1.6 + i * 0.25)
		bt.tween_property(st, "rotation", 0.06, 0.25).set_trans(Tween.TRANS_SINE)
		bt.tween_property(st, "rotation", -0.04, 0.25).set_trans(Tween.TRANS_SINE)
		bt.tween_property(st, "rotation", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	_confetti()
	_coin_rain()

## Надпись по дуге ленты окна: c — верх средней линии ленты (дуга окружности радиуса ~1140 px референса),
## буквы ставятся по одной вдоль дуги и поворачиваются по ней. Не шире max_w.
func _arc_text(ci: CanvasItem, text: String, c: Vector2, max_w: float, fs0: int, outline: Color) -> void:
	var font: Font = UiTheme.title_font()
	var fs := fs0
	while font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > max_w and fs > 30:
		fs -= 2
	var rad := 1140.0
	var cen := c + Vector2(0, rad)
	var rb := rad - fs * 0.36  # базовая линия чуть ниже средней линии ленты
	var widths: Array = []
	var total := 0.0
	for ch in text:
		var cw := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(cw)
		total += cw
	for pass_i in 3:
		var acc := 0.0
		for i in text.length():
			var cw: float = widths[i]
			var ang := (acc + cw / 2.0 - total / 2.0) / rb
			acc += cw
			ci.draw_set_transform(cen + Vector2(sin(ang), -cos(ang)) * rb, ang, Vector2.ONE)
			var p := Vector2(-cw / 2.0, 0)
			var ch := text[i]
			if pass_i == 0:
				for d in range(6, 0, -1):
					ci.draw_string_outline(font, p + Vector2(0, d), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, outline)
			elif pass_i == 1:
				ci.draw_string_outline(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 14, outline)
			else:
				ci.draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff8e6"))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## ---------- окно проигрыша 1:1 по референсу (слои: tools/losebuild.py) ----------
## Референс 852×1846 (references/screen_04_lose.webp); координаты — в его пикселях, те же в losebuild.py.
const LOSE_Y0 := 180.0
const LOSE_TOP := 186.0
const LOSE_BOT := 1730.0
const LOSE_STREAK := Vector2(137, 1059)
const LOSE_BUY := Vector2(174, 1197)
const LOSE_AD := Vector2(203, 1397)
const LOSE_QUIT := Vector2(269, 1534)
const LOSE_PLATE_C := Vector2(426, 960)     # центр плашки целей
const LOSE_BADGE_OFF := Vector2(48, 42)     # кружок-счётчик относительно центра иконки цели


func _show_lose_ref() -> void:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.2, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var k := minf(size.x / WIN_W, (size.y - 16.0) / (LOSE_BOT - LOSE_TOP))
	# внешний слой — масштаб k и место на экране, внутренний (body) — «впрыгивание» вокруг своей середины
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(WIN_W, LOSE_BOT - LOSE_Y0)
	holder.position = Vector2(size.x / 2.0 - WIN_W / 2.0 * k, size.y / 2.0 - ((LOSE_TOP + LOSE_BOT) / 2.0 - LOSE_Y0) * k)
	holder.scale = Vector2(k, k)
	_overlay.add_child(holder)
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = holder.size
	body.pivot_offset = Vector2(WIN_W / 2.0, 500.0)
	holder.add_child(body)
	var font: Font = UiTheme.title_font()
	var wt := TextureRect.new()
	wt.texture = Zoo.art("loseref_window")
	wt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(wt)
	var at := func(p: Vector2) -> Vector2: return p - Vector2(0, LOSE_Y0)
	# надпись на ленте
	var ribbon := Control.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size = body.size
	ribbon.draw.connect(func() -> void: _arc_text(ribbon, "Ходы кончились!", at.call(Vector2(425.0, 322.0)), 500.0, 60, Color("#22146e")))
	body.add_child(ribbon)
	# несобранные цели: иконки в плашке, между ними тонкие перегородки, красный кружок-счётчик
	var left: Array = []
	for g in _level.goals:
		if g.left > 0:
			left.append(g)
	var n := left.size()
	var step := 255.0 if n <= 2 else 190.0
	var isz := 140.0 if n <= 2 else 118.0
	var goals := Control.new()
	goals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goals.size = body.size
	var centers: Array = []
	for i in n:
		centers.append(at.call(LOSE_PLATE_C + Vector2((i - (n - 1) / 2.0) * step, -4)))
	for i in n:
		var gd: Dictionary = left[i]
		if gd.kind == "color" or gd.kind == "item":
			var gm: Node2D = Gem.new()
			gm.color = gd.get("color", -1)
			gm.size = isz
			gm.position = centers[i]
			if gd.kind == "item":
				gm.set_special(Gem.ITEM)
			goals.add_child(gm)
	var badge := Zoo.art("loseref_badge")
	goals.draw.connect(func() -> void:
		for i in range(1, n):
			var x: float = (centers[i - 1].x + centers[i].x) / 2.0
			var y0: float = centers[i].y - 44.0
			goals.draw_rect(Rect2(x - 2, y0, 4, 92), Color8(220, 154, 92))
			goals.draw_rect(Rect2(x - 2, y0, 2, 92), Color8(236, 182, 122)))
	var badges := Control.new()
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges.size = body.size
	badges.draw.connect(func() -> void:
		for i in n:
			var gd: Dictionary = left[i]
			var c: Vector2 = centers[i]
			if gd.kind != "color" and gd.kind != "item":
				_draw_goal_icon(badges, gd.kind, c, isz * 0.85)
			var bc: Vector2 = c + LOSE_BADGE_OFF * (isz / 140.0)
			var bs := badge.get_size() * (isz / 140.0)
			badges.draw_texture_rect(badge, Rect2(bc - bs / 2.0, bs), false)
			var t := str(int(gd.left))
			var fs := int(46.0 * isz / 140.0) if t.length() < 3 else int(34.0 * isz / 140.0)
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var tp := bc + Vector2(-ts.x / 2.0, fs * 0.36)
			badges.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#6a0a04"))
			badges.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	body.add_child(goals)
	body.add_child(badges)
	# серия побед сгорит — красная плашка с огоньком (только если серия есть)
	if Save.streak > 0:
		var st := TextureRect.new()
		st.texture = Zoo.art("loseref_streak")
		st.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.position = at.call(LOSE_STREAK)
		body.add_child(st)
		var wtxt := "Серия побед (%d) сгорит!" % Save.streak
		st.draw.connect(func() -> void:
			var fs := 40
			while font.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > 430.0 and fs > 24:
				fs -= 2
			var ts := font.get_string_size(wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			# текст — по центру красной части справа от огонька (x 125…560 слоя), середина по высоте
			var tp := Vector2(125.0 + (435.0 - ts.x) / 2.0, 64.0 + fs * 0.36)
			st.draw_string_outline(font, tp + Vector2(0, 3), wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#4a0804"))
			st.draw_string_outline(font, tp, wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#5a0e06"))
			st.draw_string(font, tp, wtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	# кнопки
	var mk_btn := func(tex_name: String, pos: Vector2) -> TextureButton:
		var b := TextureButton.new()
		b.texture_normal = Zoo.art(tex_name)
		b.position = at.call(pos)
		b.size = b.texture_normal.get_size()
		b.pivot_offset = b.size / 2.0
		b.button_down.connect(func() -> void: b.create_tween().tween_property(b, "scale", Vector2(0.93, 0.93), 0.06))
		b.button_up.connect(func() -> void:
			b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		b.pressed.connect(Sfx.play.bind("click"))
		body.add_child(b)
		return b
	var buy: TextureButton = mk_btn.call("loseref_buy", LOSE_BUY)
	buy.draw.connect(func() -> void:
		var t := str(EXTRA_MOVES_PRICE)
		var fs := 56
		var tp := Vector2(236, 147)
		buy.draw_string_outline(font, tp + Vector2(0, 3), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#0e3a08"))
		buy.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 12, Color("#14450c"))
		buy.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	buy.pressed.connect(func() -> void:
		if Save.spend(EXTRA_MOVES_PRICE):
			_add_moves())
	if Save.coins < EXTRA_MOVES_PRICE:
		buy.disabled = true
		buy.modulate = Color(0.6, 0.6, 0.6, 0.85)
	var ad: TextureButton = mk_btn.call("loseref_ad", LOSE_AD)
	ad.pressed.connect(func() -> void: Ads.show_rewarded(_add_moves))
	if not Ads.is_ready():
		ad.disabled = true
		ad.modulate = Color(0.6, 0.6, 0.6, 0.85)
	var quit: TextureButton = mk_btn.call("loseref_quit", LOSE_QUIT)
	quit.pressed.connect(func() -> void: _quit_level(_show_home))
	# появление: окно «впрыгивает»; главная кнопка мягко «дышит» (только она и только если доступна)
	body.scale = Vector2(0.6, 0.6)
	body.modulate.a = 0.0
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "modulate:a", 1.0, 0.15)
	if not buy.disabled:
		var bt := buy.create_tween().set_loops()
		bt.tween_interval(0.4)
		bt.tween_property(buy, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE)
		bt.tween_property(buy, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

## ---------- окно перед уровнем 1:1 по референсу (слои: tools/prebuild.py) ----------
## Референс 852×1846 (references/screen_05_prelevel.webp); координаты — в его пикселях, те же в prebuild.py.
const PRE_Y0 := 180.0
const PRE_TOP := 188.0
const PRE_BOT := 1606.0
const PRE_CLOSE := Vector3(760, 553, 57)                         # крестик: центр, радиус
const PRE_GOAL_Y := 785.0                                         # центр иконок целей
const PRE_GOAL_NUM_Y := 905.0                                     # базовая линия чисел целей
const PRE_BAR := Vector4(180, 984, 712, 52)                       # жёлоб серии: x0, y, x1, высота
const PRE_MARKS := [[3, 337.0], [5, 455.0], [8, 575.0], [10, 698.0]]
const PRE_MARK_Y := 1004.0
const PRE_TILE_C := [Vector2(216, 1200), Vector2(432, 1200), Vector2(635, 1200)]
const PRE_ICON_AT := [Vector2(143, 1133), Vector2(353, 1135), Vector2(562, 1138)]
const PRE_SEL_AT := Vector2(98, 1086)                             # рамка выбора у первой плитки
const PRE_CHECK_OFF := Vector2(72, -75)                           # кружок с галочкой от центра плитки
const PRE_COUNT_OFF := Vector2(64, -78)                           # кружок количества от центра плитки
const PRE_PLAY := Vector2(176, 1332)


## x на дорожке серии для числа побед st (между отметками 3/5/8/10 — линейно).
func _pre_track_x(st: float) -> float:
	var px := 0.0
	var px_x := PRE_BAR.x
	for m in PRE_MARKS:
		if st <= m[0]:
			return lerpf(px_x, m[1], (st - px) / (m[0] - px))
		px = m[0]
		px_x = m[1]
	return PRE_BAR.z


func _show_prelevel_ref(n: int, lv: Dictionary) -> void:
	_clear_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.2, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var k := minf(size.x / WIN_W, (size.y - 16.0) / (PRE_BOT - PRE_TOP))
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size = Vector2(WIN_W, PRE_BOT - PRE_Y0)
	holder.position = Vector2(size.x / 2.0 - WIN_W / 2.0 * k, size.y / 2.0 - ((PRE_TOP + PRE_BOT) / 2.0 - PRE_Y0) * k)
	holder.scale = Vector2(k, k)
	_overlay.add_child(holder)
	var body := Control.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size = holder.size
	body.pivot_offset = Vector2(WIN_W / 2.0, 700.0)
	holder.add_child(body)
	var font: Font = UiTheme.title_font()
	var at := func(p: Vector2) -> Vector2: return p - Vector2(0, PRE_Y0)
	var wt := TextureRect.new()
	wt.texture = Zoo.art("preref_window")
	wt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(wt)
	# лента: «Уровень N» (на сложных — «Сложный уровень N» / «Очень сложный N»)
	var hard := int(lv.get("hard", 0))
	var title: String = ["Уровень %d", "Сложный уровень %d", "Очень сложный %d"][hard] % n
	var ribbon := Control.new()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.size = body.size
	ribbon.draw.connect(func() -> void: _arc_text(ribbon, title, at.call(Vector2(425.0, 566.0)), 500.0, 64, Color("#1d5a0c")))
	body.add_child(ribbon)
	# цели: иконки в плашке, под ними числа, между ними тонкие перегородки
	var goals_l: Array = lv.goals
	var gn := goals_l.size()
	var step := 189.0 if gn >= 3 else 255.0
	var isz := 128.0 if gn >= 3 else 138.0
	var gx: Array = []
	for i in gn:
		gx.append(428.0 + (i - (gn - 1) / 2.0) * step)
	var goals := Control.new()
	goals.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goals.size = body.size
	for i in gn:
		var g: Dictionary = goals_l[i]
		if g.kind == "color":
			var gm: Node2D = Gem.new()
			gm.color = int(g.get("color", -1))
			gm.size = isz
			gm.position = at.call(Vector2(gx[i], PRE_GOAL_Y))
			goals.add_child(gm)
	goals.draw.connect(func() -> void:
		for i in range(1, gn):
			var x: float = (gx[i - 1] + gx[i]) / 2.0
			var r := Rect2(at.call(Vector2(x - 2, 765)), Vector2(4, 122))
			goals.draw_rect(r, Color8(214, 168, 112))
			goals.draw_rect(Rect2(r.position + Vector2(2, 0), Vector2(2, r.size.y)), Color8(255, 238, 205))
		for i in gn:
			var g: Dictionary = goals_l[i]
			var c: Vector2 = at.call(Vector2(gx[i], PRE_GOAL_Y))
			if g.kind != "color":
				_draw_goal_icon(goals, "birdhouse" if g.kind == "item" and _level_has_birds(lv) else g.kind, c, isz * 0.92)
			var t := str(int(g.left))
			var fs := 64
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p: Vector2 = at.call(Vector2(gx[i] - ts.x / 2.0, PRE_GOAL_NUM_Y))
			for d in range(6, 0, -1):
				goals.draw_string_outline(font, p + Vector2(0, d), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#3d1a08"))
			goals.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 16, Color("#3d1a08"))
			goals.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	body.add_child(goals)
	# дорожка серии побед: жёлоб, оранжевая заливка до текущей серии, отметки 3/5/8/10, огонёк
	var track := Control.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.size = body.size
	var bar_t := Zoo.art("preref_bar")
	var fill_t := Zoo.art("preref_fill")
	var cap_t := Zoo.art("preref_fillcap")
	var on_t := Zoo.art("preref_mark_on")
	var off_t := Zoo.art("preref_mark_off")
	var flame_t := Zoo.art("preref_flame")
	var st := mini(Save.streak, 10)
	track.draw.connect(func() -> void:
		var y: float = at.call(Vector2(0, PRE_BAR.y)).y
		var h := PRE_BAR.w
		var x0 := PRE_BAR.x
		var x1 := PRE_BAR.z
		track.draw_texture_rect(bar_t, Rect2(Vector2(x0, y), Vector2(x1 - x0, h)), false)
		if st > 0:
			# заливка до отметки и скруглённый конец (как у «3» в референсе: конец на 22…45 px правее центра)
			var xe := minf(_pre_track_x(st) + 31.0, x1 - cap_t.get_width())
			track.draw_texture_rect(fill_t, Rect2(Vector2(x0, y), Vector2(xe - x0, h)), false)
			track.draw_texture_rect(cap_t, Rect2(Vector2(xe, y), cap_t.get_size()), false)
		var tt := Time.get_ticks_msec() / 1000.0
		for m in PRE_MARKS:
			var c: Vector2 = at.call(Vector2(m[1], PRE_MARK_Y))
			var lit: bool = st >= m[0]
			if lit:
				var gr := 64.0 * (1.0 + 0.06 * sin(tt * 3.0))
				track.draw_texture_rect(Board.fx_tex("glow"), Rect2(c - Vector2(gr, gr), Vector2(gr, gr) * 2.0), false, Color(1, 0.95, 0.6, 0.9))
				for j in 10:
					var a := TAU * j / 10.0 + tt * 0.5
					track.draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - 0.12), sin(a - 0.12)) * 70.0,
						c + Vector2(cos(a + 0.12), sin(a + 0.12)) * 70.0]), Color(1.0, 0.97, 0.7, 0.35))
			var tex: Texture2D = on_t if lit else off_t
			track.draw_texture_rect(tex, Rect2(c - tex.get_size() / 2.0, tex.get_size()), false)
			var t := str(m[0])
			var fs := 38 if t.length() < 2 else 32
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var p := c + Vector2(-ts.x / 2.0, fs * 0.36)
			track.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#4a220a"))
			track.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var fl := 1.0 + 0.05 * sin(tt * 9.0)
		var fs2 := flame_t.get_size()
		var fb: Vector2 = at.call(Vector2(102, 942)) + Vector2(fs2.x / 2.0, fs2.y)
		track.draw_set_transform(fb, 0.0, Vector2(1.0 / fl, fl))
		track.draw_texture_rect(flame_t, Rect2(Vector2(-fs2.x / 2.0, -fs2.y), fs2), false)
		track.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	body.add_child(track)
	_every_frame(track)
	# бустеры на старт: деревянные плитки, выбранная — с зелёной светящейся рамкой и галочкой
	var tile_t := Zoo.art("preref_tile")
	var sel_t := Zoo.art("preref_sel")
	var check_t := Zoo.art("preref_check")
	var count_t := Zoo.art("preref_count")
	for i in PRE_BOOSTERS.size():
		var kind: String = PRE_BOOSTERS[i][0]
		var ic_name: String = ["preref_ic_rocket", "preref_ic_bomb", "preref_ic_orb"][i]
		var ic_t := Zoo.art(ic_name)
		var tc: Vector2 = at.call(PRE_TILE_C[i])
		var cnt := int(Save.boosters.get(kind, 0))
		var b := Button.new()
		b.toggle_mode = true
		b.flat = true
		for stn in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			b.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
		b.size = Vector2(230, 240)
		b.position = tc - b.size / 2.0
		b.pivot_offset = b.size / 2.0
		b.disabled = cnt <= 0
		if cnt <= 0:
			b.modulate = Color(0.65, 0.65, 0.65, 0.9)
		var lc := b.size / 2.0  # центр плитки в координатах кнопки
		var ic_off: Vector2 = PRE_ICON_AT[i] - PRE_TILE_C[i]
		b.draw.connect(func() -> void:
			var on := b.button_pressed
			if on:
				var gl := Board.fx_tex("glow")
				b.draw_texture_rect(gl, Rect2(lc - Vector2(150, 150), Vector2(300, 300)), false, Color(0.55, 1.0, 0.4, 0.55))
			b.draw_texture_rect(tile_t, Rect2(lc - tile_t.get_size() / 2.0, tile_t.get_size()), false)
			b.draw_texture_rect(ic_t, Rect2(lc + ic_off, ic_t.get_size()), false)
			if on:
				b.draw_texture_rect(sel_t, Rect2(lc + PRE_SEL_AT - PRE_TILE_C[0], sel_t.get_size()), false)
				b.draw_texture_rect(check_t, Rect2(lc + PRE_CHECK_OFF - check_t.get_size() / 2.0, check_t.get_size()), false)
			elif cnt > 0:
				var bc := lc + PRE_COUNT_OFF
				b.draw_texture_rect(count_t, Rect2(bc - count_t.get_size() / 2.0, count_t.get_size()), false)
				var t := str(cnt)
				var fs := 40 if t.length() < 2 else 32
				var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				var p := bc + Vector2(-ts.x / 2.0, fs * 0.36)
				b.draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#0e4a08"))
				b.draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
		b.toggled.connect(func(on: bool) -> void:
			_pre_selected[kind] = on
			Sfx.play("special" if on else "click")
			b.queue_redraw()
			var tw := b.create_tween()
			tw.tween_property(b, "scale", Vector2(1.12, 1.12), 0.08)
			tw.tween_property(b, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK))
		body.add_child(b)
	# «Играть»
	var play := TextureButton.new()
	play.texture_normal = Zoo.art("preref_play")
	play.position = at.call(PRE_PLAY)
	play.size = play.texture_normal.get_size()
	play.pivot_offset = play.size / 2.0
	play.button_down.connect(func() -> void: play.create_tween().tween_property(play, "scale", Vector2(0.93, 0.93), 0.06))
	play.button_up.connect(func() -> void:
		play.create_tween().tween_property(play, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	play.pressed.connect(func() -> void:
		Sfx.play("click")
		_clear_overlay()
		_level_transition(n))
	body.add_child(play)
	# крестик нарисован в окне — сверху невидимая круглая кнопка
	var close := Button.new()
	close.flat = true
	for stn in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(stn, StyleBoxEmpty.new())
	close.size = Vector2(PRE_CLOSE.z, PRE_CLOSE.z) * 2.0
	close.position = at.call(Vector2(PRE_CLOSE.x, PRE_CLOSE.y)) - close.size / 2.0
	close.pressed.connect(func() -> void:
		Sfx.play("click")
		_show_home())
	body.add_child(close)
	body.scale = Vector2(0.6, 0.6)
	body.modulate.a = 0.0
	var tw := body.create_tween()
	tw.tween_property(body, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(body, "modulate:a", 1.0, 0.15)

## Конфетти: залп из двух нижних углов + дождь сверху.
func _confetti() -> void:
	for i in 70:
		var conf := ColorRect.new()
		conf.color = [Color("#ffe14d"), Color("#ff6b9d"), Color("#5fc4ff"), Color("#7dff8a"), Color("#c47dff"), Color("#ff9a3a")][i % 6]
		conf.size = Vector2(randf_range(9, 15), randf_range(14, 22))
		conf.pivot_offset = conf.size / 2
		# залп из двух нижних углов + дождь сверху
		var burst := i < 40
		var from := Vector2(0 if i % 2 == 0 else size.x, size.y * 0.75) if burst else Vector2(randf() * size.x, -30)
		conf.position = from
		conf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(conf)
		var tw := conf.create_tween().set_parallel(true)
		if burst:
			var peak := Vector2(size.x * randf_range(0.15, 0.85), size.y * randf_range(0.05, 0.4))
			tw.tween_property(conf, "position", peak, randf_range(0.45, 0.7)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			tw.chain().tween_property(conf, "position:y", size.y + 40, randf_range(1.4, 2.2)).set_ease(Tween.EASE_IN)
		else:
			tw.tween_property(conf, "position:y", size.y + 40, randf_range(1.6, 2.6)).set_delay(randf() * 0.6)
		tw.tween_property(conf, "rotation", randf_range(-10, 10), 2.4)
		tw.chain().tween_callback(conf.queue_free)


## «Дальше» после победы — сразу следующий уровень (если есть жизни).
func _next_level() -> void:
	Save.update_hearts()
	if Save.hearts <= 0:
		_transition(_show_home)
		return
	_level_transition(Save.level)


## Переход между уровнями: экран-заставка «Уровень N» на плашке, панда подпрыгивает, потом уровень проявляется.
func _level_transition(n: int) -> void:
	var cur := Control.new()
	cur.mouse_filter = Control.MOUSE_FILTER_STOP
	cur.set_anchors_preset(Control.PRESET_FULL_RECT)
	cur.size = size
	cur.z_index = 50
	var bg := TextureRect.new()
	bg.texture = load("res://assets/art/zoo_map.webp")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = size
	bg.modulate = Color(0.55, 0.65, 0.55)
	cur.add_child(bg)
	var title := _big_text("Уровень %d" % n, 84, Color("#ffe14d"), Color("#ff9a1a"))
	title.size = Vector2(size.x, 220)
	title.position = Vector2(0, size.y * 0.3)
	cur.add_child(title)
	var panda := _make_panda(330.0)
	panda.position = Vector2(size.x / 2 - panda.custom_minimum_size.x / 2, size.y * 0.5)
	cur.add_child(panda)
	add_child(cur)
	cur.modulate.a = 0.0
	title.pivot_offset = title.size / 2
	title.scale = Vector2(0.3, 0.3)
	var tw := cur.create_tween()
	tw.tween_property(cur, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(panda, "position:y", size.y * 0.47, 0.25).set_ease(Tween.EASE_OUT)
	tw.tween_property(panda, "position:y", size.y * 0.5, 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_callback(_start_level.bind(n))
	tw.tween_interval(0.45)
	tw.tween_property(cur, "modulate:a", 0.0, 0.35)
	tw.tween_callback(cur.queue_free)


func _show_lose() -> void:
	if _state != "done":
		return
	Sfx.play("lose")
	if Zoo.art("loseref_window"):
		_show_lose_ref()
		return
	var font: Font = UiTheme.title_font()
	var v := _dialog("Уровень %d" % _level.n, [], [])
	var lpanel := v.get_parent() as Control
	lpanel.custom_minimum_size.x = 650
	var top_gap := Control.new()
	top_gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(top_gap)
	var head := _big_text("Ходы кончились!", 58, Color("#ffd0b0"), Color("#ff5a3a"))
	head.custom_minimum_size = Vector2(0, 96)
	head.set_meta("no_banner", true)
	v.add_child(head)
	# что осталось собрать: иконки целей в круглых слотах с красным счётчиком
	var left: Array = []
	for g in _level.goals:
		if g.left > 0:
			left.append(g)
	var goals := Control.new()
	goals.custom_minimum_size = Vector2(0, 150 if not left.is_empty() else 0)
	goals.draw.connect(func() -> void:
		var n := left.size()
		var stepx := 150.0
		var x0 := goals.size.x / 2.0 - (n - 1) * stepx / 2.0
		for i in n:
			var g: Dictionary = left[i]
			var c := Vector2(x0 + i * stepx, 66)
			goals.draw_circle(c + Vector2(0, 6), 58, Color(0, 0, 0, 0.18))
			goals.draw_circle(c, 58, Color("#b9824a"))
			goals.draw_circle(c, 52, Color("#fff4dc"))
			if g.kind != "color" and g.kind != "item":
				_draw_goal_icon(goals, g.kind, c, 84.0)
			var bc := c + Vector2(40, 40)
			goals.draw_circle(bc + Vector2(0, 3), 27, Color(0, 0, 0, 0.3))
			goals.draw_circle(bc, 27, Color.WHITE)
			goals.draw_circle(bc, 23, Color("#d8261c"))
			goals.draw_circle(bc + Vector2(0, -3), 19, Color("#ff4a3a"))
			var t := str(int(g.left))
			var fs := 28 if t.length() < 3 else 21
			var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var tp := bc + Vector2(-ts.x / 2, fs * 0.36)
			goals.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color("#6a0a04"))
			goals.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE))
	v.add_child(goals)
	# фишки-цели (цвет, яйцо) — настоящие фишки поверх слотов
	goals.resized.connect(func() -> void:
		for ch in goals.get_children():
			ch.queue_free()
		var stepx := 150.0
		var x0 := goals.size.x / 2.0 - (left.size() - 1) * stepx / 2.0
		for i in left.size():
			var gd: Dictionary = left[i]
			if gd.kind == "color" or gd.kind == "item":
				var gm: Node2D = Gem.new()
				gm.color = gd.get("color", -1)
				gm.size = 86.0
				gm.position = Vector2(x0 + i * stepx, 66)
				if gd.kind == "item":
					gm.set_special(Gem.ITEM)
				goals.add_child(gm)
				goals.move_child(gm, 0)
		goals.queue_redraw())
	# предупреждение о серии побед — красная плашка с огоньком
	if Save.streak > 0:
		var warn := Control.new()
		warn.custom_minimum_size = Vector2(0, 62)
		var wt := "Серия побед (%d) сгорит!" % Save.streak
		warn.draw.connect(func() -> void:
			var ts := font.get_string_size(wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28)
			var w := ts.x + 100.0
			var r := Rect2(Vector2((warn.size.x - w) / 2.0, 4), Vector2(w, 52))
			_tile(warn, r, Color("#7a1a10"), 26.0)
			_tile(warn, r.grow(-3), Color("#e0452e"), 23.0)
			_tile(warn, Rect2(r.position + Vector2(8, 6), Vector2(r.size.x - 16, 16)), Color(1, 1, 1, 0.22), 8.0)
			var fc := r.position + Vector2(34, 27)
			var fl := 1.0 + 0.08 * sin(Time.get_ticks_msec() / 120.0)
			warn.draw_colored_polygon(PackedVector2Array([fc + Vector2(-12, 8), fc + Vector2(0, -20 * fl), fc + Vector2(12, 8)]), Color("#ffb21e"))
			warn.draw_circle(fc + Vector2(0, 6), 12, Color("#ffb21e"))
			warn.draw_circle(fc + Vector2(0, 8), 7, Color("#fff1a8"))
			var tp := r.position + Vector2(62, 37)
			warn.draw_string_outline(font, tp, wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, 7, Color("#5a0e06"))
			warn.draw_string(font, tp, wt, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE))
		v.add_child(warn)
		_every_frame(warn)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap)
	# главная кнопка: «+5 ходов» за монеты; цена с монеткой справа
	var buy := Button.new()
	buy.theme_type_variation = "GreenButton"
	buy.custom_minimum_size = Vector2(500, 104)
	buy.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	buy.text = ""
	buy.disabled = Save.coins < EXTRA_MOVES_PRICE
	buy.draw.connect(func() -> void:
		var t := "+%d ходов" % EXTRA_MOVES
		var fs := 40
		var tp := Vector2(34, buy.size.y / 2 + fs * 0.34 - 4)
		buy.draw_string_outline(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 10, Color("#1b5a12"))
		buy.draw_string(font, tp, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var pr := Rect2(Vector2(buy.size.x - 196, 18), Vector2(170, buy.size.y - 44))
		_tile(buy, pr, Color(0, 0, 0, 0.22), pr.size.y / 2)
		var cc := pr.position + Vector2(30, pr.size.y / 2)
		if not Zoo.draw_art(buy, "ui_coin", cc, 50.0):
			buy.draw_circle(cc, 20, Color("#ffd23f"))
		var pt := str(EXTRA_MOVES_PRICE)
		var pp := pr.position + Vector2(62, pr.size.y / 2 + 11)
		buy.draw_string_outline(font, pp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, 8, Color("#1b5a12"))
		buy.draw_string(font, pp, pt, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color("#fff6b0")))
	buy.pressed.connect(func() -> void:
		if Save.spend(EXTRA_MOVES_PRICE):
			_add_moves())
	v.add_child(buy)
	# «+5 ходов» за рекламу
	var ad := Button.new()
	ad.theme_type_variation = "PurpleButton"
	ad.custom_minimum_size = Vector2(500, 84)
	ad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ad.text = "       +%d ходов" % EXTRA_MOVES
	ad.add_theme_font_size_override("font_size", 30)
	ad.disabled = not Ads.is_ready()
	ad.draw.connect(func() -> void:
		var c := Vector2(150, ad.size.y / 2 - 3)
		if not Zoo.draw_art(ad, "ui_video", c, 50.0):
			ad.draw_rect(Rect2(c - Vector2(20, 14), Vector2(40, 28)), Color("#5fa8ff")))
	ad.pressed.connect(func() -> void: Ads.show_rewarded(_add_moves))
	v.add_child(ad)
	# «Сдаться» — маленькая, чтобы не нажать случайно
	var quit := Button.new()
	quit.theme_type_variation = "RedButton"
	quit.custom_minimum_size = Vector2(300, 66)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.text = "Сдаться (−1 жизнь)"
	quit.add_theme_font_size_override("font_size", 24)
	quit.pressed.connect(func() -> void: _quit_level(_show_home))
	v.add_child(quit)
	# главная кнопка мягко «дышит», привлекая внимание (только она)
	buy.pivot_offset = buy.custom_minimum_size / 2
	if not buy.disabled:
		var bt := buy.create_tween().set_loops()
		bt.tween_property(buy, "scale", Vector2(1.04, 1.04), 0.6).set_trans(Tween.TRANS_SINE)
		bt.tween_property(buy, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


func _add_moves() -> void:
	Sfx.play("coin")
	_clear_overlay()
	_moves += EXTRA_MOVES
	_update_moves()
	_panda_react("reset")
	_state = "play"
	_board.input_enabled = true


func _show_pause() -> void:
	if _state != "play" or _board.busy:
		return
	_board.input_enabled = false
	_dialog("Пауза", [], [
		["Продолжить", "GreenButton", func() -> void:
			_clear_overlay()
			_board.input_enabled = true],
		["Заново (−1 жизнь)", "OrangeButton", func() -> void: _quit_level(_try_play)],
		["Домой (−1 жизнь)", "Button", func() -> void: _quit_level(_show_home)],
	])


# ---------- проверки в CI ----------

## Бот: проходит N уровней случайными ходами на ускорении. Ловит ошибки логики.
func _run_bot(levels: int, first: int = 1) -> void:
	_bot = true
	Engine.time_scale = 8.0
	var wins := 0
	for n in range(first, levels + 1):
		_start_level(n)
		await get_tree().create_timer(1.2).timeout
		var guard := 0
		while _state == "play" and guard < 100:
			if _board.busy or not _board.input_enabled:
				await get_tree().process_frame
				continue
			var all: Array = _board.all_moves()
			if all.is_empty():
				await get_tree().process_frame
				continue
			var m: Array = all.pick_random()
			for cand in all:
				if cand[0] == cand[1]:
					m = cand
			guard += 1
			if guard % 7 == 3:
				_board.booster_hit(["hammer", "rockets"].pick_random(), Vector2i(randi() % 8, randi() % 8))
			elif guard % 11 == 5:
				_board.shuffle_now()
			elif m[0] == m[1]:
				_board.activate_single(m[0])
			else:
				_board.try_swap(m[0], m[1])
			await get_tree().process_frame
		while _state == "bonus" or _board.busy:
			await get_tree().process_frame
		await get_tree().create_timer(0.6).timeout
		var won := Save.level > n
		if won:
			wins += 1
		var rest: Array = []
		for goal in _level.goals:
			rest.append("%s:%d" % [goal.kind, goal.left])
		print("BOT level %d: %s, goals left %s" % [n, "WIN" if won else "LOSE", ", ".join(rest)])
		Save.level = 1
		Save.coins = 0
		Save.streak = 0
		Save.hearts = Save.MAX_HEARTS
		Save.streak = 0
		_clear_overlay()
	print("BOT done: %d/%d wins" % [wins, levels - first + 1])
	get_tree().quit()


## Проверка настоящего ввода: свайп и два тапа через очередь событий, как палец на телефоне.
func _run_input_test() -> void:
	Save.hearts = Save.MAX_HEARTS
	Save.streak = 0  # бот мог оставить серию побед — она добавляет особые фишки на старте
	_bot = true
	_start_level(1)
	await get_tree().create_timer(1.5).timeout
	var ok := 0
	for mode in ["mouse", "swipe", "tap"]:
		var m: Array = []
		for cand in _board.all_moves():
			if cand[0] != cand[1] and not _board.gem_at(cand[0]).is_power() and not _board.gem_at(cand[1]).is_power():
				m = cand
				break
		var before := _moves
		var a := _board.get_global_transform_with_canvas() * _board.cell_pos(m[0])
		var b := _board.get_global_transform_with_canvas() * _board.cell_pos(m[1])
		if mode == "mouse":
			_mouse(a, true)
			for i in 6:
				var mm := InputEventMouseMotion.new()
				mm.position = a.lerp(b, (i + 1) / 6.0)
				mm.button_mask = MOUSE_BUTTON_MASK_LEFT
				get_viewport().push_input(mm, true)
				await get_tree().process_frame
			_mouse(b, false)
		elif mode == "swipe":
			_touch(a, true)
			for i in 6:
				_drag(a.lerp(b, (i + 1) / 6.0))
				await get_tree().process_frame
			_touch(b, false)
		else:
			_touch(a, true)
			await get_tree().process_frame
			_touch(a, false)
			await get_tree().process_frame
			_touch(b, true)
			await get_tree().process_frame
			_touch(b, false)
		await get_tree().create_timer(0.3).timeout
		while _board.busy:
			await get_tree().process_frame
		await get_tree().create_timer(1.2).timeout
		print("INPUT %s: moves %d -> %d" % [mode, before, _moves])
		if _moves == before - 1:
			ok += 1
	print("INPUT TEST %s" % ("OK" if ok == 3 else "FAIL"))
	get_tree().quit()


func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = pos
	e.pressed = pressed
	get_viewport().push_input(e, true)


func _mouse(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	get_viewport().push_input(e, true)


func _drag(pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.position = pos
	get_viewport().push_input(e, true)


## Скриншоты окна победы (проверка 1:1 по референсу): -- --winshot=DIR
func _run_winshot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Save.streak = 3
	Save.boosters["pre_rocket"] = 1
	Save.boosters["pre_bomb"] = 2
	Save.boosters["pre_orb"] = 1
	_show_prelevel(12)
	await get_tree().create_timer(0.6).timeout
	await _snap(dir, "p1_pre")
	Save.streak = 6
	Save.boosters["pre_orb"] = 0
	_show_prelevel(3)
	await get_tree().create_timer(0.6).timeout
	for ch in _overlay.get_children():
		for b in ch.find_children("*", "Button", true, false):
			if b.toggle_mode and not b.disabled:
				b.button_pressed = true
				break
	await get_tree().create_timer(0.4).timeout
	await _snap(dir, "p2_pre")
	Save.chest_wins = 4
	_start_level(12)
	await get_tree().create_timer(1.6).timeout
	_clear_overlay()
	_show_win()
	await get_tree().create_timer(0.35).timeout
	await _snap(dir, "w1_appear")
	await get_tree().create_timer(2.6).timeout
	await _snap(dir, "w2_done")
	_clear_overlay()
	Save.streak = 4
	Save.coins = 1000
	_state = "done"
	_show_lose()
	await get_tree().create_timer(0.8).timeout
	await _snap(dir, "l1_lose")
	_level.goals = [_level.goals[0], _level.goals[1]]
	Save.streak = 0
	Save.coins = 0
	_show_lose()
	await get_tree().create_timer(0.8).timeout
	await _snap(dir, "l2_lose3")
	get_tree().quit()


func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	Save.hearts = 3
	Save.heart_at = Save.now() + 754
	Save.stars = 6
	Save.built = {2: 0, 3: 1, 4: 2}
	_show_home()
	await get_tree().create_timer(0.6).timeout
	await _snap(dir, "1_home")
	_set_repair_mode(true)
	await get_tree().create_timer(0.3).timeout
	await _snap(dir, "1a_repair")
	_on_spot(0)
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1b_design")
	_build_task(0, 2)
	await get_tree().create_timer(2.6).timeout
	await _snap(dir, "1c_built")
	Save.coins = 600
	_show_shop()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1g_shop")
	Save.zone = 2
	_show_collection()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1h_collection")
	Save.zone = 0
	Save.coins = 0
	_show_daily()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1e_daily")
	Save.chest_wins = CHEST_WINS
	_show_chest()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1f_chest")
	_clear_overlay()
	# новые зоны (решение №29): все предметы построены — проверяем раскладку
	var keep_zone := Save.zone
	var keep_built: Dictionary = Save.built
	for zi in [5, 6, 7]:
		Save.zone = zi
		Save.built = {}
		for ti in Zones.ZONES[zi].tasks.size():
			Save.built[ti] = ti % 3
		_refresh_home()
		await get_tree().create_timer(0.4).timeout
		await _snap(dir, "1z_zone%d" % zi)
	Save.zone = keep_zone
	Save.built = keep_built
	_refresh_home()
	_show_settings()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "1d_settings")
	_clear_overlay()
	# уровни с разными препятствиями: 4 ящики, 5 трава, 6 предметы, 7 цепи, 8 вазы
	for n in [8, 12, 21, 40, 55, 70]:
		_start_level(n)
		await get_tree().create_timer(1.6).timeout
		await _snap(dir, "2_level_%d" % n)
	_start_level(23)
	await get_tree().create_timer(1.6).timeout
	_clear_overlay()
	_board.input_enabled = true
	await get_tree().create_timer(0.3).timeout
	await _snap(dir, "2x_bar")
	_on_booster("hammer")
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "2y_aim")
	_on_booster("hammer")
	_moves = 6
	_on_move()
	await get_tree().create_timer(0.45).timeout
	await _snap(dir, "2w_low_moves")
	_on_combo(4)
	_goal_views[0].goal.left = 0
	_goal_views[0].shown = 1
	_goal_tick(_goal_views[0])
	await get_tree().create_timer(0.4).timeout
	await _snap(dir, "2z_combo")
	_start_level(5)
	await get_tree().create_timer(1.4).timeout
	for i in 4:
		var m: Array = _board.find_move()
		if m.size() == 2 and m[0] != m[1]:
			_board.try_swap(m[0], m[1])
		while _board.busy:
			await get_tree().process_frame
	await _snap(dir, "3_after_moves")
	var kinds := [Gem.ROCKET_H, Gem.ROCKET_V, Gem.BOMB, Gem.ORB, Gem.PROPELLER]
	for i in kinds.size():
		var g: Node2D = _board.gem_at(Vector2i(1 + i, 2))
		if g:
			g.set_special(kinds[i])
	await get_tree().create_timer(0.3).timeout
	await _snap(dir, "4_specials")
	_board.activate_single(Vector2i(1, 2))
	await get_tree().create_timer(0.2).timeout
	await _snap(dir, "4b_rocket")
	while _board.busy:
		await get_tree().process_frame
	var pg: Node2D = _board.gem_at(Vector2i(6, 2))
	if pg:
		pg.set_special(Gem.PROPELLER)
		_board.activate_single(Vector2i(6, 2))
		await get_tree().create_timer(0.45).timeout
		await _snap(dir, "4f_butterfly")
	while _board.busy:
		await get_tree().process_frame
	var bc := Vector2i(3, 2)
	var bg: Node2D = _board.gem_at(bc)
	if bg:
		bg.set_special(Gem.BOMB)
		_board.activate_single(bc)
		await get_tree().create_timer(0.1).timeout
		await _snap(dir, "4c_bomb")
	while _board.busy:
		await get_tree().process_frame
	var og: Node2D = _board.gem_at(Vector2i(3, 5))
	if og and _board.gem_at(Vector2i(4, 5)):
		og.set_special(Gem.ORB)
		_board.try_swap(Vector2i(3, 5), Vector2i(4, 5))
		await get_tree().create_timer(0.42).timeout
		await _snap(dir, "4e_orb")
	while _board.busy:
		await get_tree().process_frame
	var m: Array = _board.find_move()
	if m.size() == 2 and m[0] != m[1]:
		_board.try_swap(m[0], m[1])
		await get_tree().create_timer(0.26).timeout
		await _snap(dir, "4d_pop")
	while _board.busy:
		await get_tree().process_frame
	_state = "done"
	# для снимка: цели ещё не собраны, есть монеты и серия побед
	for gi in _level.goals.size():
		_level.goals[gi].left = [7, 12, 3][gi % 3]
	var keep_coins := Save.coins
	Save.coins = 500
	Save.streak = maxi(Save.streak, 4)
	_show_lose()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "5_lose")
	Save.coins = keep_coins
	_level["bonus_coins"] = 40
	_show_win()
	await get_tree().create_timer(1.4).timeout
	await _snap(dir, "6_win")
	_transition(func() -> void: pass)
	await get_tree().create_timer(0.62).timeout
	await _snap(dir, "6c_curtain")
	await get_tree().create_timer(0.8).timeout
	_level_transition(12)
	await get_tree().create_timer(0.6).timeout
	await _snap(dir, "6b_transition")
	await get_tree().create_timer(1.2).timeout
	_show_prelevel(10)
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "8_prelevel")
	Save.hearts = 0
	_show_home()
	_try_play()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "7_no_hearts")
	get_tree().quit()


## Проверка нагрузки финала: много особых фишек взрываются разом; печатает худший кадр и пик узлов.
func _run_finaletest() -> void:
	_bot = true
	_start_level(3)
	await get_tree().create_timer(1.8).timeout
	_clear_overlay()
	_state = "fxdemo"
	var kinds := [Gem.PROPELLER, Gem.PROPELLER, Gem.PROPELLER, Gem.BOMB, Gem.ROCKET_H, Gem.ROCKET_V]
	var i := 0
	for x in _board.W:
		for y in _board.H:
			var g: Node2D = _board.gem_at(Vector2i(x, y))
			if g and (x * 7 + y * 3) % 4 == 0 and i < 20:
				g.set_special(kinds[i % kinds.size()])
				i += 1
	await get_tree().create_timer(0.5).timeout
	var worst := 0.0
	var peak := 0
	var t0 := Time.get_ticks_msec()
	_board.detonate_all_specials()
	var last := Time.get_ticks_usec()
	while Time.get_ticks_msec() - t0 < 6000:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		peak = maxi(peak, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	print("FINALE worst_frame_ms=%.0f peak_nodes=%d" % [worst, peak])
	get_tree().quit()


## Показ особых фишек по очереди на чистом поле (для записи видео и проверки эффектов).
func _run_fxdemo() -> void:
	_bot = true
	_start_level(3)
	await get_tree().create_timer(1.8).timeout
	_clear_overlay()
	_moves = 99
	_state = "fxdemo"
	var shots := [[Vector2i(1, 4), Gem.ROCKET_H], [Vector2i(4, 2), Gem.ROCKET_V], [Vector2i(3, 4), Gem.BOMB],
		[Vector2i(5, 6), Gem.PROPELLER]]
	for sh in shots:
		var g: Node2D = _board.gem_at(sh[0])
		if g:
			g.set_special(sh[1])
			await get_tree().create_timer(0.5).timeout
			print("FX ", sh[1], " frame ", Engine.get_frames_drawn())
			_board.activate_single(sh[0])
		while _board.busy:
			await get_tree().process_frame
		await get_tree().create_timer(0.4).timeout
	var og: Node2D = _board.gem_at(Vector2i(3, 5))
	if og and _board.gem_at(Vector2i(4, 5)):
		og.set_special(Gem.ORB)
		await get_tree().create_timer(0.5).timeout
		print("FX orb frame ", Engine.get_frames_drawn())
		_board.try_swap(Vector2i(3, 5), Vector2i(4, 5))
	while _board.busy:
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	# комбо: ракета + бомба
	var a: Node2D = _board.gem_at(Vector2i(3, 3))
	var b: Node2D = _board.gem_at(Vector2i(4, 3))
	if a and b:
		a.set_special(Gem.ROCKET_H)
		b.set_special(Gem.BOMB)
		await get_tree().create_timer(0.5).timeout
		print("FX combo frame ", Engine.get_frames_drawn())
		_board.try_swap(Vector2i(3, 3), Vector2i(4, 3))
	while _board.busy:
		await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	print("FX end frame ", Engine.get_frames_drawn())
	get_tree().quit()


func _snap(dir: String, name: String) -> void:
	print("SNAP ", name, " frame ", Engine.get_frames_drawn())
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)
