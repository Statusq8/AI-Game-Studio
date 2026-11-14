extends Control
## Экраны игры: главный (кнопка «Уровень N»), уровень (поле, ходы, цели), окна победы / поражения / паузы.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Levels := preload("res://scripts/levels.gd")
const Board := preload("res://scripts/board.gd")
const Gem := preload("res://scripts/gem.gd")
const Zones := preload("res://scripts/zones.gd")
const Zoo := preload("res://scripts/zoo.gd")

const VERSION := "2.14.0"
const WIN_COINS := 50
const COINS_PER_MOVE := 5
const EXTRA_MOVES := 5
const EXTRA_MOVES_PRICE := 300
const BOOSTER_PRICE := 250
const IN_BOOSTERS := [["hammer", "Молот"], ["arrow", "Ряд"], ["cannon", "Столбец"], ["shuffle", "Микс"]]
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
	icon.custom_minimum_size = Vector2(40, 40)
	icon.draw.connect(func() -> void:
		var c := icon.size / 2
		if Zoo.draw_art(icon, "ui_coin", c, 38.0):
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
	icon.custom_minimum_size = Vector2(40, 40)
	icon.draw.connect(func() -> void: draw_heart(icon, icon.size / 2, 15.0))
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
	side.add_theme_constant_override("separation", 12)
	side.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	side.position = Vector2(-110, -40)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(side)
	for b in [["mail", _show_soon.bind("Почта")], ["friends", _show_soon.bind("Друзья")], ["rating", _show_soon.bind("Рейтинг")], ["settings", _show_settings]]:
		var btn := _icon_button(b[0], 88.0, Color("#9b5cff"))
		btn.pressed.connect(b[1])
		side.add_child(btn)
	_home.resized.connect(func() -> void: side.position = Vector2(_home.size.x - 100, _home.size.y * 0.30))

	# панда в левом нижнем углу
	_home_panda = _make_panda(250.0)
	_home.add_child(_home_panda)

	# кнопки уровня и ремонта над нижней панелью
	_home_level_btn = Button.new()
	_home_level_btn.theme_type_variation = "GreenButton"
	_home_level_btn.custom_minimum_size = Vector2(330, 110)
	_home_level_btn.add_theme_font_size_override("font_size", 40)
	_home_level_btn.pressed.connect(_try_play)
	_home.add_child(_home_level_btn)
	var pulse := _home_level_btn.create_tween().set_loops()
	_home_level_btn.pivot_offset = Vector2(165, 55)
	pulse.tween_property(_home_level_btn, "scale", Vector2(1.09, 1.09), 0.45).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_home_level_btn, "modulate", Color(1.15, 1.15, 1.05), 0.45)
	pulse.tween_property(_home_level_btn, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	pulse.parallel().tween_property(_home_level_btn, "modulate", Color.WHITE, 0.45)
	pulse.tween_interval(0.4)

	_repair_btn = _icon_button("repair", 116.0, Color("#ff9a2a"))
	_repair_btn.pressed.connect(func() -> void: _transition(_set_repair_mode.bind(not _repair_mode)))
	_home.add_child(_repair_btn)

	# нижняя панель: 5 вкладок
	_tabbar = HBoxContainer.new()
	_tabbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tabbar.add_theme_constant_override("separation", 4)
	_home.add_child(_tabbar)
	for t in [["Магазин", _show_shop], ["События", _show_soon.bind("События")], ["Главная", func() -> void: _clear_overlay()], ["Команда", _show_soon.bind("Команда")], ["Коллекция", _show_collection]]:
		var btn := Button.new()
		btn.text = t[0]
		btn.theme_type_variation = "GreenButton" if t[0] == "Главная" else "Button"
		btn.custom_minimum_size = Vector2(136, 92)
		btn.clip_text = true
		var base := Color("#3fc25a") if t[0] == "Главная" else Color("#3f8cff")
		for st in [["normal", base, 8, 0], ["hover", base.lightened(0.08), 8, 0], ["pressed", base.darkened(0.1), 3, 5]]:
			var sb: StyleBoxFlat = UiTheme._button_box(st[1], st[2], st[3])
			sb.content_margin_left = 4
			sb.content_margin_right = 4
			btn.add_theme_stylebox_override(st[0], sb)
		btn.add_theme_font_size_override("font_size", 19 if t[0] != "Главная" else 21)
		btn.pressed.connect(t[1])
		_tabbar.add_child(btn)
	_home.resized.connect(_layout_home)

	var ver := Label.new()
	ver.text = "Зоопарк мечты · %s" % VERSION
	ver.add_theme_font_size_override("font_size", 16)
	ver.modulate = Color(1, 1, 1, 0.7)
	ver.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position = Vector2(10, -24)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_home.add_child(ver)
	_home.resized.connect(func() -> void: ver.position = Vector2(10, _home.size.y - 22))


func _layout_home() -> void:
	var w := _home.size.x if _home.size.x > 0 else size.x
	var h := _home.size.y if _home.size.y > 0 else size.y
	_tabbar.size = Vector2(w, 100)
	_tabbar.position = Vector2(0, h - 120)
	_home_level_btn.position = Vector2(w - 330 - 24, h - 250)
	_repair_btn.position = Vector2(24, h - 250)
	_home_panda.position = Vector2(4, h - 250 - _home_panda.custom_minimum_size.y + 10)


func _avatar() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(64, 64)
	c.draw.connect(func() -> void:
		var m := c.size / 2
		if not Zoo.draw_art(c, "ui_avatar", m, 68.0):
			c.draw_circle(m, 31, Color("#f0b34a"))
			c.draw_circle(m, 27, Color.WHITE)
		for dx in ([] if Zoo.art("ui_avatar") else [-14, 14]):
			c.draw_circle(m + Vector2(dx, -16), 8, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -2), 7, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -3), 2.5, Color.WHITE)
		if not Zoo.art("ui_avatar"):
			c.draw_circle(m + Vector2(0, 8), 4, Color("#2b2b33"))
		var f: Font = ThemeDB.fallback_font
		c.draw_circle(m + Vector2(22, 22), 13, Color("#3fb85a"))
		var lvl := str(Save.level)
		c.draw_string(f, m + Vector2(22 - 5 * lvl.length(), 29), lvl, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE))
	_avatar_node = c
	return c


func _stars_pill() -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(36, 40)
	icon.draw.connect(func() -> void: Zoo.draw_star(icon, icon.size / 2, 15.0))
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
	var lines := ["Сундук: +300 монет и бустеры!", "В зоопарке поселился: %s" % zone.animal]
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
	var buttons: Array = []
	for b in IN_BOOSTERS + PRE_BOOSTERS:
		var kind: String = b[0]
		buttons.append(["%s (×%d) — %d монет" % [b[1], int(Save.boosters.get(kind, 0)), BOOSTER_PRICE], "OrangeButton", func() -> void:
			if Save.spend(BOOSTER_PRICE):
				Save.add_booster(kind)
			_show_shop(), Save.coins < BOOSTER_PRICE])
	buttons.append(["Закрыть", "Button", func() -> void:
		_clear_overlay()
		_refresh_home()])
	var v := _dialog("Магазин", ["Монеты: %d" % Save.coins], buttons)
	for c in v.get_children():
		if c is Button:
			c.custom_minimum_size.y = 64
			c.add_theme_font_size_override("font_size", 22)


func _show_collection() -> void:
	var lines: Array = []
	for i in Zones.ZONES.size():
		var z: Dictionary = Zones.ZONES[i]
		var status: String = "✓ " + z.animal if i < Save.zone else ("ремонт: %d/%d" % [Save.built.size(), z.tasks.size()] if i == Save.zone else "закрыта")
		lines.append("%d. %s — %s" % [i + 1, z.name, status])
	_dialog("Коллекция", lines, [["Закрыть", "Button", _clear_overlay]])


func _show_settings() -> void:
	var v := _dialog("Настройки", ["Язык: русский"], [["Закрыть", "Button", _clear_overlay]])
	for it in [["Звук", "sound"], ["Музыка", "music"], ["Вибрация", "vibration"], ["Тряска экрана", "shake"], ["Много частиц", "particles"]]:
		var key: String = it[1]
		var name: String = it[0]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.add_theme_font_size_override("font_size", 24)
		var paint := func() -> void:
			var on := bool(Save.get(key))
			btn.text = "%s: %s" % [name, "вкл" if on else "выкл"]
			btn.theme_type_variation = "GreenButton" if on else "RedButton"
		paint.call()
		btn.pressed.connect(func() -> void:
			Save.set(key, not bool(Save.get(key)))
			Save.store()
			if key == "music":
				Sfx.refresh_music()
			paint.call())
		v.add_child(btn)
		v.move_child(btn, v.get_child_count() - 2)
	var pol := Label.new()
	pol.text = "Политика конфиденциальности — в описании игры"
	pol.theme_type_variation = "InkLabel"
	pol.add_theme_font_size_override("font_size", 18)
	pol.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pol)
	v.move_child(pol, v.get_child_count() - 2)


func _build_level_screen() -> void:
	_level_screen = Control.new()
	_level_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_level_screen)
	# фон уровня приглушён — внимание на поле
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.06, 0.12, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_screen.add_child(dim)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for side in ["left", "right"]:
		top.add_theme_constant_override("margin_" + side, 16)
	top.add_theme_constant_override("margin_top", 30)
	_level_screen.add_child(top)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	top.add_child(col)

	# объёмная шапка: «Цель» слева, портрет панды в арке по центру, «Ходы» справа
	var hud := HBoxContainer.new()
	hud.add_theme_constant_override("separation", 10)
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(hud)
	var goal_card := _hud_card("Цель")
	goal_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		pn.draw_set_transform(Vector2(pn.size.x / 2, pn.size.y - 6), 0.0, Vector2(1.0, 0.22))
		pn.draw_circle(Vector2.ZERO, pn.size.x * 0.36, Color(0, 0, 0, 0.35))
		pn.draw_circle(Vector2.ZERO, pn.size.x * 0.26, Color(0, 0, 0, 0.25))
		pn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE))
	var moves_card := _hud_card("Ходы")
	moves_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hud.add_child(moves_card)
	_moves_label = Label.new()
	_moves_label.theme_type_variation = "TitleLabel"
	_moves_label.add_theme_font_size_override("font_size", 66)
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
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.05, 0.12, 0.22, 0.72)
	psb.set_corner_radius_all(18)
	psb.border_color = Color("#bfe3ff", 0.6)
	psb.set_border_width_all(2)
	psb.content_margin_left = 22
	psb.content_margin_right = 22
	psb.content_margin_top = 2
	psb.content_margin_bottom = 4
	plaque.add_theme_stylebox_override("panel", psb)
	plaque.add_child(_level_label)
	var pc := CenterContainer.new()
	pc.add_child(plaque)
	col.add_child(pc)

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
	var ft: Texture2D = load("res://assets/art/ui_board_frame.png")
	var frame := NinePatchRect.new()
	frame.texture = ft
	frame.patch_margin_left = 72
	frame.patch_margin_right = 72
	frame.patch_margin_top = 72
	frame.patch_margin_bottom = 72
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.z_index = 2
	frame.visible = false  # деревянную рамку убрали: доску обводит тонкая золотая линия по форме
	var fk := 0.28
	frame.scale = Vector2(fk, fk)
	frame.top_level = false
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(frame)
	holder.resized.connect(func() -> void:
		var out := 40.0
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
	var pause := _round_button("pause", Color("#3f8cff"))
	pause.pressed.connect(_show_pause)
	_booster_bar.add_child(pause)
	# сплошные полосы: шапка сверху и подставка бустеров снизу, с золотой каймой
	var bands := Control.new()
	bands.set_anchors_preset(Control.PRESET_FULL_RECT)
	bands.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bands.draw.connect(func() -> void:
		var w := bands.size.x
		var top_h := 238.0
		_draw_band(bands, Rect2(0, 0, w, top_h), false)
		var by := _booster_bar.position.y + 4.0
		_draw_tray(bands, Rect2(12, by, w - 24, 132)))
	_level_screen.add_child(bands)
	_level_screen.move_child(bands, 1)
	_bands = bands
	_panda = _make_panda(200.0)
	_panda.visible = false  # на уровне панда — портрет в шапке
	_level_screen.add_child(_panda)
	_level_screen.move_child(_panda, _board_frame.get_index())
	_board.combo_made.connect(_on_combo)
	_board.idle_hint.connect(func() -> void: _panda_react("yawn"))
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
		_board_frame.position = _board_rest()
		_place_pause()
		_panda.position = _panda_rest()
		_layout_bar())


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
	var tw := img.create_tween().set_loops()
	tw.tween_property(img, "scale", Vector2(1.02, 0.975), 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(img, "scale", Vector2(0.99, 1.02), 0.9).set_trans(Tween.TRANS_SINE)
	return holder


## Реакция панды: "combo" — подпрыгнуть, "win" — прыгать от радости, "sad" — поникнуть.
func _panda_react(kind: String) -> void:
	if _portrait_node == null:
		return
	var img: Control = _portrait_node.get_node("Img")
	var body := _portrait_node
	if body.has_meta("react"):
		var old: Tween = body.get_meta("react")
		if old and old.is_valid():
			old.kill()
	img.rotation = 0.0
	img.position = Vector2(-10, -14)
	body.pivot_offset = Vector2(body.size.x / 2.0, body.size.y)
	body.scale = Vector2.ONE
	if kind == "reset":
		img.modulate = Color.WHITE
		return
	if kind != "sad":
		img.modulate = Color.WHITE
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
	e.z_index = 5
	e.draw.connect(_draw_emote.bind(e, kind))
	_portrait_node.add_child(e)
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
func _hud_card(title: String) -> PanelContainer:
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
	img.pivot_offset = Vector2(105, 240)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(img)
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


## Рисует круглую кнопку-иконку (см. _icon_button).
func _draw_icon_button(btn: Button, kind: String, d: float, base: Color) -> void:
	var font: Font = UiTheme.title_font()
	var c := btn.size / 2 + (Vector2(0, 3) if btn.is_pressed() else Vector2.ZERO)
	var r := d * 0.46
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
func _tile(ci: CanvasItem, r: Rect2, col: Color, radius: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	ci.draw_style_box(sb, r)


## Кружок с количеством бустера (зелёный) или «+» (оранжевый), если их нет.
func _draw_count(btn: Button, c: Vector2) -> void:
	var n: int = btn.get_meta("count")
	if n < 0:
		return
	var bc := c + Vector2(42, 42)
	var buy := n == 0
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
	var art := {"hammer": "ui_hammer", "arrow": "ui_arrow", "cannon": "ui_arrow", "shuffle": "ui_shuffle"}
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
	_booster_bar.size = Vector2(_level_screen.size.x, 140)
	_booster_bar.position = Vector2(0, _level_screen.size.y - 140.0 - 22.0)
	if _bands:
		_bands.queue_redraw()


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
	"cannon": ["Стрела", "Коснись клетки — очистит весь столбец!"]}


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
		var icon := "ui_hammer" if kind == "hammer" else "ui_arrow"
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
	var free_top := 264.0
	var free_bottom := 176.0
	var k := minf((_level_screen.size.x - 8.0) / s.x, (_level_screen.size.y - free_top - free_bottom) / s.y)
	var pad := s.x - _board_clip.custom_minimum_size.x
	var k8 := (_level_screen.size.x - 8.0) / (8.0 * Board.CELL + pad)
	return clampf(minf(k, k8), 0.6, 1.35)


func _board_rest() -> Vector2:
	var k := _board_scale()
	_board_frame.scale = Vector2(k, k)
	var s := _board_frame.get_combined_minimum_size() * k
	var free_top := 264.0
	var y := free_top + maxf(0.0, (_level_screen.size.y - free_top - 176.0 - s.y) * 0.5)
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
		var ft := hb.create_tween().set_loops()
		ft.tween_callback(hb.queue_redraw)
		ft.tween_interval(0.05)
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
		var sl := Label.new()
		var nxt := 3 if Save.streak < 3 else (5 if Save.streak < 5 else (8 if Save.streak < 8 else 10))
		sl.text = ("Серия побед: %d — бонус на старте!" % Save.streak) if Save.streak >= 3 else ("Серия побед: %d — бонус с %d побед" % [Save.streak, nxt])
		sl.theme_type_variation = "InkLabel"
		sl.add_theme_font_size_override("font_size", 24)
		sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(sl)
		v.move_child(sl, at)
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
		v.add_child(l)
		_goals_box.add_child(slot)
		_goal_views.append({"goal": goal, "label": l, "icon": icon, "shown": int(goal.left)})


func _draw_goal_icon(ci: CanvasItem, kind: String, c: Vector2) -> void:
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
			var k := 54.0 / maxf(sz.x, sz.y)
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
	Save.add_coins(coins)
	Save.vibrate(60)
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
	var pr := pile.create_tween().set_loops()
	pr.tween_callback(pile.queue_redraw)
	pr.tween_interval(0.04)
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
	var left: Array = []
	for g in _level.goals:
		if g.left > 0:
			left.append(GOAL_NAMES.get(g.kind, g.kind) + " " + str(g.left))
	var warn := "Сдашься — потеряешь серию побед (%d)!" % Save.streak if Save.streak > 0 else "Ещё чуть-чуть!"
	_dialog("Ходы кончились", ["Осталось: " + ", ".join(left), warn, "+%d ходов, чтобы доиграть?" % EXTRA_MOVES], [
		["Реклама: +%d ходов" % EXTRA_MOVES, "PurpleButton", func() -> void:
			Ads.show_rewarded(_add_moves), not Ads.is_ready()],
		["%d монет: +%d ходов" % [EXTRA_MOVES_PRICE, EXTRA_MOVES], "OrangeButton", func() -> void:
			if Save.spend(EXTRA_MOVES_PRICE):
				_add_moves(), Save.coins < EXTRA_MOVES_PRICE],
		["Сдаться (−1 жизнь)", "RedButton", func() -> void: _quit_level(_show_home)],
	])


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
				_board.booster_hit(["hammer", "arrow", "cannon"].pick_random(), Vector2i(randi() % 8, randi() % 8))
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
	_show_lose()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "5_lose")
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


func _snap(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("shot ", name)
