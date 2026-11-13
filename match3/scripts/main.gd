extends Control
## Экраны игры: главный (кнопка «Уровень N»), уровень (поле, ходы, цели), окна победы / поражения / паузы.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Levels := preload("res://scripts/levels.gd")
const Board := preload("res://scripts/board.gd")
const Gem := preload("res://scripts/gem.gd")
const Zones := preload("res://scripts/zones.gd")
const Zoo := preload("res://scripts/zoo.gd")

const VERSION := "0.9.1"
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
var _pre_selected := {}
var _board_frame: Control
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
	if _shake > 0.0:
		_board_frame.position = _board_rest() + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, 50.0 * delta)
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
		icon.draw_circle(c, 19, Color("#c98a12"))
		icon.draw_circle(c, 15, Color("#ffd23f"))
		icon.draw_circle(c + Vector2(-5, -5), 4, Color(1, 1, 1, 0.8)))
	row.add_child(icon)
	var l := Label.new()
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 30)
	row.add_child(l)
	_coin_labels.append(l)
	return pill


func _hearts_pill() -> Control:
	var pill := PanelContainer.new()
	pill.theme_type_variation = "PillPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	pill.add_child(row)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.draw.connect(func() -> void: draw_heart(icon, icon.size / 2, 18.0))
	row.add_child(icon)
	_hearts_label = Label.new()
	_hearts_label.theme_type_variation = "TitleLabel"
	_hearts_label.add_theme_font_size_override("font_size", 30)
	row.add_child(_hearts_label)
	_hearts_timer = Label.new()
	_hearts_timer.add_theme_font_size_override("font_size", 22)
	row.add_child(_hearts_timer)
	return pill


static func draw_heart(ci: CanvasItem, c: Vector2, r: float) -> void:
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
	for b in [["Почта", _show_soon.bind("Почта")], ["Друзья", _show_soon.bind("Друзья")], ["Рейтинг", _show_soon.bind("Рейтинг")], ["Опции", _show_settings]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.theme_type_variation = "PurpleButton"
		btn.custom_minimum_size = Vector2(96, 64)
		btn.add_theme_font_size_override("font_size", 18)
		btn.pressed.connect(b[1])
		side.add_child(btn)
	_home.resized.connect(func() -> void: side.position = Vector2(_home.size.x - 108, _home.size.y * 0.30))

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
	pulse.tween_property(_home_level_btn, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_home_level_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)

	_repair_btn = Button.new()
	_repair_btn.theme_type_variation = "OrangeButton"
	_repair_btn.custom_minimum_size = Vector2(250, 110)
	_repair_btn.add_theme_font_size_override("font_size", 34)
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
		c.draw_circle(m, 31, Color("#f0b34a"))
		c.draw_circle(m, 27, Color.WHITE)
		for dx in [-14, 14]:
			c.draw_circle(m + Vector2(dx, -16), 8, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -2), 7, Color("#2b2b33"))
			c.draw_circle(m + Vector2(dx * 0.6, -3), 2.5, Color.WHITE)
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
	icon.draw.connect(func() -> void: Zoo.draw_star(icon, icon.size / 2, 17.0))
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
	_repair_btn.text = "← Назад" if _repair_mode else "Ремонт ★%d" % Save.stars
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
			["▶ Играть", "GreenButton", _try_play],
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
	_portrait_node = _portrait()
	hud.add_child(_portrait_node)
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
	col.add_child(_level_label)

	_board_frame = PanelContainer.new()
	_board_frame.theme_type_variation = "BoardPanel"
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_screen.add_child(_board_frame)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(8, 8) * Board.CELL
	_board_frame.add_child(clip)
	# лианы на деревянной рамке
	var vines := Control.new()
	vines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vines.set_anchors_preset(Control.PRESET_FULL_RECT)
	vines.draw.connect(func() -> void:
		var w := vines.size.x
		var h := vines.size.y
		var pts := PackedVector2Array()
		for i in 41:
			var x := w * i / 40.0
			pts.append(Vector2(x, -4 + sin(i * 0.9) * 7))
		vines.draw_polyline(pts, Color("#2e7d32"), 5.0, true)
		for i in 20:
			var p := pts[i * 2 + 1]
			var a := 0.6 if i % 2 == 0 else -0.6
			vines.draw_set_transform(p, a, Vector2.ONE)
			vines.draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(9, -7), Vector2(20, 0), Vector2(9, 7)]), Color("#43a047") if i % 3 else Color("#66bb6a"))
		vines.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for c in [Vector2(-2, h * 0.3), Vector2(w + 2, h * 0.55)]:
			for k in 6:
				vines.draw_circle(c + Vector2(sin(k) * 5, k * 22), 7, Color("#43a047"))
		vines.draw_circle(Vector2(w * 0.18, -4), 9, Color("#ff6b9d"))
		vines.draw_circle(Vector2(w * 0.72, -2), 9, Color("#ffe14d")))
	_board_frame.add_child(vines)
	_board = Board.new()
	clip.add_child(_board)
	_board.move_made.connect(_on_move)
	_board.gem_cleared.connect(_on_gem_cleared)
	_board.goal_hit.connect(_on_goal_hit)
	_board.settled.connect(_on_settled)
	_board.big_hit.connect(func(p: float) -> void:
		if Save.shake:
			_shake = maxf(_shake, 6.0 + p * 4.0)
		if p >= 2.0:
			Save.vibrate(int(20 + p * 10))
			_flash(clampf(0.15 + p * 0.06, 0.2, 0.5))
		if p >= 3.0 and not _bot:
			_slowmo())
	_booster_bar = HBoxContainer.new()
	_booster_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_booster_bar.add_theme_constant_override("separation", 14)
	_level_screen.add_child(_booster_bar)
	for b in IN_BOOSTERS:
		var btn := _round_button(b[0], Color("#3fb85a"))
		btn.pressed.connect(_on_booster.bind(b[0]))
		_booster_bar.add_child(btn)
		_booster_btns[b[0]] = btn
	var pause := _round_button("pause", Color("#3f8cff"))
	pause.pressed.connect(_show_pause)
	_booster_bar.add_child(pause)
	_panda = _make_panda(200.0)
	_panda.visible = false  # на уровне панда — портрет в шапке
	_level_screen.add_child(_panda)
	_level_screen.move_child(_panda, _board_frame.get_index())
	_board.combo_made.connect(_on_combo)
	_level_screen.resized.connect(func() -> void:
		_board_frame.position = _board_rest()
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
	if _portrait_node:
		var p := _portrait_node
		p.pivot_offset = p.size / 2
		var pt := p.create_tween()
		match kind:
			"combo", "win":
				pt.tween_property(p, "scale", Vector2(1.15, 1.15), 0.12).set_trans(Tween.TRANS_BACK)
				pt.tween_property(p, "scale", Vector2.ONE, 0.2)
				if kind == "win":
					pt.tween_property(p, "rotation", 0.12, 0.1)
					pt.tween_property(p, "rotation", -0.12, 0.15)
					pt.tween_property(p, "rotation", 0.0, 0.1)
			"sad":
				pt.tween_property(p, "modulate", Color(0.7, 0.7, 0.8), 0.3)
			_:
				p.modulate = Color.WHITE
				pt.kill()
	if _panda == null:
		return
	var img: Control = _panda.get_node("Img")
	if kind == "reset":
		img.rotation = 0.0
		_panda.modulate = Color.WHITE
		return
	var tw := _panda.create_tween()
	match kind:
		"combo":
			tw.tween_property(_panda, "position:y", _panda_rest().y - 40, 0.15).set_ease(Tween.EASE_OUT)
			tw.tween_property(_panda, "position:y", _panda_rest().y, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
		"win":
			for i in 3:
				tw.tween_property(_panda, "position:y", _panda_rest().y - 60, 0.18).set_ease(Tween.EASE_OUT)
				tw.tween_property(_panda, "position:y", _panda_rest().y, 0.18).set_ease(Tween.EASE_IN)
		"sad":
			tw.tween_property(img, "rotation", -0.12, 0.3)
			tw.tween_property(_panda, "modulate", Color(0.75, 0.75, 0.85), 0.3)


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
	var o := StyleBoxFlat.new()
	o.bg_color = Color("#8a5326")
	o.set_corner_radius_all(22)
	o.border_color = Color("#5a3315")
	o.set_border_width_all(4)
	o.border_width_bottom = 10
	o.set_content_margin_all(8)
	o.content_margin_top = 34
	o.shadow_color = Color(0, 0, 0, 0.35)
	o.shadow_size = 8
	o.shadow_offset = Vector2(0, 5)
	outer.add_theme_stylebox_override("panel", o)
	outer.custom_minimum_size = Vector2(0, 178)
	var inner := PanelContainer.new()
	inner.name = "Body"
	var i := StyleBoxFlat.new()
	i.bg_color = Color("#fff4dc")
	i.set_corner_radius_all(14)
	i.border_color = Color("#e3c48f")
	i.border_width_top = 6
	i.set_content_margin_all(4)
	inner.add_theme_stylebox_override("panel", i)
	outer.add_child(inner)
	# лента-заголовок
	var ribbon := outer
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	ribbon.draw.connect(func() -> void:
		var w := outer.size.x
		var r := Rect2(Vector2(14, -8), Vector2(w - 28, 40))
		ribbon.draw_colored_polygon(PackedVector2Array([r.position + Vector2(-12, 8), r.position + Vector2(8, 8), r.position + Vector2(8, 38), r.position + Vector2(-12, 38), r.position + Vector2(-2, 23)]), Color("#2b7a3a"))
		ribbon.draw_colored_polygon(PackedVector2Array([r.end + Vector2(12, -32), r.end + Vector2(-8, -32), r.end + Vector2(-8, -2), r.end + Vector2(12, -2), r.end + Vector2(2, -17)]), Color("#2b7a3a"))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#3fb85a")
		sb.set_corner_radius_all(10)
		sb.border_color = Color("#ffcf5a")
		sb.set_border_width_all(3)
		sb.border_width_bottom = 6
		ribbon.draw_style_box(sb, r)
		ribbon.draw_rect(Rect2(r.position + Vector2(10, 6), Vector2(r.size.x - 20, 5)), Color(1, 1, 1, 0.35))
		var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
		var tp := Vector2(w / 2 - ts.x / 2, 21)
		ribbon.draw_string_outline(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, 6, Color("#1e5a2a"))
		ribbon.draw_string(font, tp, title, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.WHITE))
	return outer


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


## Круглая объёмная кнопка бустера: обод, глянец, иконка, красный кружок с количеством.
func _round_button(kind: String, base: Color) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(118, 118)
	btn.flat = true
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.set_meta("count", -1)
	btn.set_meta("active", false)
	btn.draw.connect(func() -> void:
		var c := btn.size / 2
		var pressed := btn.is_pressed()
		var off := Vector2(0, 4) if pressed else Vector2.ZERO
		var active: bool = btn.get_meta("active")
		var col := Color("#ffb020") if active else base
		btn.draw_circle(c + Vector2(0, 7), 54, Color(0, 0, 0, 0.3))
		btn.draw_circle(c + off, 54, Color("#ffcf5a"))
		btn.draw_circle(c + off, 49, col.darkened(0.45))
		btn.draw_circle(c + off + Vector2(0, -3), 45, col)
		btn.draw_circle(c + off + Vector2(0, -12), 34, col.lightened(0.22))
		btn.draw_set_transform(c + off + Vector2(-14, -26), -0.4, Vector2(1.0, 0.5))
		btn.draw_circle(Vector2.ZERO, 16, Color(1, 1, 1, 0.45))
		btn.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_tool_icon(btn, kind, c + off)
		var n: int = btn.get_meta("count")
		if n >= 0:
			var bc := c + Vector2(36, 38)
			btn.draw_circle(bc, 22, Color("#7a0f1c"))
			btn.draw_circle(bc + Vector2(0, -2), 19, Color("#e8283c"))
			var f: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
			var t := str(n) if n > 0 else "+"
			var ts := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
			btn.draw_string(f, bc + Vector2(-ts.x / 2, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE))
	btn.button_down.connect(btn.queue_redraw)
	btn.button_up.connect(btn.queue_redraw)
	return btn


func _draw_tool_icon(ci: CanvasItem, kind: String, c: Vector2) -> void:
	var ink := Color("#3a2a1a")
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
	var r := _board_rest()
	var bottom := r.y + _board_frame.get_combined_minimum_size().y
	_booster_bar.size = Vector2(_level_screen.size.x, 124)
	_booster_bar.position = Vector2(0, bottom + maxf(10.0, (_level_screen.size.y - bottom - 124.0) * 0.4))


func _refresh_boosters() -> void:
	for b in IN_BOOSTERS:
		var btn: Button = _booster_btns[b[0]]
		btn.set_meta("count", int(Save.boosters.get(b[0], 0)))
		btn.set_meta("active", _aiming == b[0])
		btn.queue_redraw()


func _on_booster(kind: String) -> void:
	if _state != "play" or _board.busy:
		return
	if _aiming == kind:
		_aiming = ""
		_board.target_cb = Callable()
		_refresh_boosters()
		return
	if int(Save.boosters.get(kind, 0)) <= 0:
		_board.input_enabled = false
		_dialog("Нет бустера", ["Купить 1 шт. за %d монет?" % BOOSTER_PRICE], [
			["%d монет" % BOOSTER_PRICE, "OrangeButton", func() -> void:
				if Save.spend(BOOSTER_PRICE):
					Save.add_booster(kind)
				_close_dialog(), Save.coins < BOOSTER_PRICE],
			["▶ Реклама: +1", "PurpleButton", func() -> void:
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
	_board.target_cb = func(cell: Vector2i) -> void:
		_aiming = ""
		Save.use_booster(kind)
		_refresh_boosters()
		_board.booster_hit(kind, cell)


func _close_dialog() -> void:
	_clear_overlay()
	_refresh_boosters()
	if _state == "play":
		_board.input_enabled = true


func _board_rest() -> Vector2:
	var s := _board_frame.get_combined_minimum_size()
	var free_top := 290.0
	var y := free_top + maxf(0.0, (_level_screen.size.y - free_top - 140.0 - s.y) * 0.5)
	return Vector2((_level_screen.size.x - s.x) / 2.0, y)


# ---------- экраны ----------

func _show_home() -> void:
	_state = "idle"
	_clear_overlay()
	_home.visible = true
	_level_screen.visible = false
	_board.input_enabled = false
	_refresh_home()


func _try_play() -> void:
	Save.update_hearts()
	if Save.hearts > 0:
		_show_prelevel(Save.level)
		return
	var sec := Save.seconds_to_heart()
	_dialog("Нет жизней", ["Новая жизнь через %d:%02d" % [sec / 60, sec % 60]], [
		["▶ Реклама: +1 жизнь", "PurpleButton", func() -> void:
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
	var goals: Array = []
	for g in lv.goals:
		goals.append(GOAL_NAMES.get(g.kind, g.kind) + " " + str(g.left))
	var diff: String = ["Обычный", "Сложный", "Очень сложный"][int(lv.get("hard", 0))]
	var streak_line := "Серия побед: %d — бонус на старте!" % Save.streak if Save.streak > 0 else "Серия побед: 0"
	var v := _dialog("Уровень %d" % n, ["Сложность: " + diff, "Цели: " + ", ".join(goals), streak_line, "Бустеры на старт:"], [
		["▶ Играть", "GreenButton", func() -> void: _transition(_start_level.bind(n))],
		["Закрыть", "Button", _show_home],
	])
	# ряд переключателей бустеров перед кнопкой «Играть»
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	v.move_child(row, v.get_child_count() - 3)
	for b in PRE_BOOSTERS:
		var kind: String = b[0]
		var t := Button.new()
		t.toggle_mode = true
		t.custom_minimum_size = Vector2(150, 110)
		t.add_theme_font_size_override("font_size", 24)
		var cnt := int(Save.boosters.get(kind, 0))
		t.text = "%s\n×%d" % [b[1], cnt]
		t.disabled = cnt <= 0
		t.theme_type_variation = "Button"
		t.toggled.connect(func(on: bool) -> void:
			_pre_selected[kind] = on
			t.theme_type_variation = "GreenButton" if on else "Button")
		row.add_child(t)


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
	_moves = _level.moves
	_level_label.text = "Уровень %d" % n
	_board.fx = _fx
	_board.setup(_level)
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
	for b in PRE_BOOSTERS:
		if _pre_selected.get(b[0], false) and Save.use_booster(b[0]):
			_board.spawn_specials(1, b[2])
	# серия побед: 1 — ракета, 2 — ракета и бомба, 3+ — ракета, бомба и шар
	var bonus := [1, 3, 4]
	for i in mini(Save.streak, 3):
		_board.spawn_specials(1, bonus[i])
	_pre_selected.clear()
	_refresh_boosters()
	_layout_bar()
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
		l.add_theme_font_size_override("font_size", 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text = str(goal.left)
		v.add_child(l)
		_goals_box.add_child(slot)
		_goal_views.append({"goal": goal, "label": l, "icon": icon, "shown": int(goal.left)})


func _draw_goal_icon(ci: CanvasItem, kind: String, c: Vector2) -> void:
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


# ---------- игровые события ----------

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
	Engine.time_scale = 0.45
	await get_tree().create_timer(0.35, true, false, true).timeout
	Engine.time_scale = 1.0


func _on_combo(n: int) -> void:
	if n < 2 or _state != "play":
		return
	_panda_react("combo")
	var l := Label.new()
	l.text = ["Отлично!", "Супер!", "Невероятно!"][mini(n - 2, 2)]
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 64 + mini(n, 5) * 6)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_color", [Color("#ffe14d"), Color("#7dff8a"), Color("#ff9ad5")][mini(n - 2, 2)])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(l)
	l.size = Vector2(size.x, 100)
	l.position = Vector2(0, _board_rest().y + 240)
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


const GOAL_NAMES := {"color": "фишки", "crate": "ящики", "vase": "горшки", "chain": "лианы", "grass": "газон", "item": "яйца",
	"ice": "лёд", "honey": "мёд", "safe": "сейфы", "jar": "банки", "cage": "клетки", "balloon": "шарики", "flower": "цветы", "bush": "кусты", "shell": "ракушки"}
const GOAL_TEX := {"crate": "ob_crate_0", "vase": "ob_pot_0", "chain": "ob_vines", "grass": "ob_tile_grass", "ice": "ob_tile_ice",
	"honey": "ob_honey", "safe": "ob_safe", "jar": "ob_jar", "cage": "ob_cage", "balloon": "ob_balloon", "flower": "ob_flower_0", "bush": "ob_bush", "shell": "ob_shell_0"}


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
		n.size = 70.0
	else:
		n = Node2D.new()
		n.draw.connect(func() -> void: _draw_goal_icon(n, kind, Vector2.ZERO))
	n.position = _fx.to_local(from)
	_fx.add_child(n)
	if kind == "item":
		n.set_special(Gem.ITEM)
	var mid := n.position.lerp(_fx.to_local(target), 0.5) + Vector2(randf_range(-120, 120), -80)
	var tw := n.create_tween()
	tw.tween_property(n, "position", mid, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(n, "position", _fx.to_local(target), 0.25).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(n, "scale", Vector2(0.7, 0.7), 0.25)
	tw.tween_callback(func() -> void:
		_flying -= 1
		n.queue_free()
		_goal_tick(gv))


func _goal_tick(gv: Dictionary) -> void:
	gv.shown = maxi(int(gv.goal.left), int(gv.shown) - 1)
	var l: Label = gv.label
	if not is_instance_valid(l):
		return
	l.text = "✓" if gv.shown <= 0 else str(gv.shown)
	if gv.shown <= 0:
		l.add_theme_color_override("font_color", Color("#7dff8a"))
	var icon: Control = gv.icon
	icon.pivot_offset = icon.size / 2
	var tw := icon.create_tween()
	tw.tween_property(icon, "scale", Vector2(1.25, 1.25), 0.06)
	tw.tween_property(icon, "scale", Vector2.ONE, 0.1)


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
	var l := Label.new()
	l.text = "Отлично!"
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", 96)
	l.add_theme_constant_override("outline_size", 16)
	l.add_theme_color_override("font_color", Color("#ffe14d"))
	_banner(l)
	await get_tree().create_timer(1.0).timeout
	var bonus := _moves
	_level["bonus_coins"] = bonus * COINS_PER_MOVE
	# праздник: каждый оставшийся ход вылетает ракетой из счётчика и превращает фишку в ракету
	var n := mini(bonus, 12)
	var from := _moves_label.get_global_rect().get_center()
	var rtex: Texture2D = Gem.tex("rocket")
	for i in n:
		var cells: Array = []
		for x in 8:
			for y in 8:
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
		spr.rotation = (to - spr.position).angle()
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", to, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			spr.queue_free()
			var g: Node2D = _board.gem_at(cell)
			if g and g.special == Gem.NONE:
				g.set_special(Gem.ROCKET_H if randf() < 0.5 else Gem.ROCKET_V)
				g.scale = Vector2(1.5, 1.5)
				g.create_tween().tween_property(g, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK))
		await get_tree().create_timer(0.09).timeout
	_moves = 0
	_update_moves()
	await get_tree().create_timer(0.35).timeout
	_board.detonate_all_specials()


# ---------- окна ----------

## Переход между экранами: шторка из листьев с отпечатком лапы.
func _transition(then: Callable) -> void:
	var cur := Control.new()
	cur.mouse_filter = Control.MOUSE_FILTER_STOP
	cur.size = size
	cur.position = Vector2(-size.x, 0)
	cur.draw.connect(func() -> void:
		cur.draw_rect(Rect2(Vector2.ZERO, cur.size), Color("#3fb85a"))
		for i in 18:
			var p := Vector2(fmod(i * 173.0, cur.size.x), fmod(i * 291.0, cur.size.y))
			cur.draw_circle(p, 70, Color("#56c96c"))
		var m := cur.size / 2
		cur.draw_circle(m + Vector2(0, 30), 60, Color("#2b8a41"))
		for d in [Vector2(-60, -40), Vector2(-22, -78), Vector2(22, -78), Vector2(60, -40)]:
			cur.draw_circle(m + d, 26, Color("#2b8a41")))
	add_child(cur)
	var tw := cur.create_tween()
	tw.tween_property(cur, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(then)
	tw.tween_interval(0.1)
	tw.tween_property(cur, "position:x", size.x, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(cur.queue_free)


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
	var panel := PanelContainer.new()
	panel.theme_type_variation = "DialogPanel"
	panel.custom_minimum_size = Vector2(560, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)
	var t := Label.new()
	t.text = title_text
	t.theme_type_variation = "TitleLabel"
	t.add_theme_font_size_override("font_size", 52)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_color", Color("#ffd23f"))
	v.add_child(t)
	for line in lines:
		var l := Label.new()
		l.text = line
		l.theme_type_variation = "InkLabel"
		l.add_theme_font_size_override("font_size", 30)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.theme_type_variation = b[1]
		btn.custom_minimum_size = Vector2(0, 96)
		btn.disabled = b.size() > 3 and b[3]
		btn.pressed.connect(b[2])
		v.add_child(btn)
	panel.pivot_offset = Vector2(280, 250)
	panel.scale = Vector2(0.6, 0.6)
	panel.create_tween().tween_property(panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return v


func _show_win() -> void:
	var mult := 1 + int(_level.get("hard", 0))
	var coins := WIN_COINS * mult + int(_level.get("bonus_coins", 0))
	Save.level = _level.n + 1
	Save.stars += 1
	Save.streak += 1
	Save.add_coins(coins)
	Save.vibrate(60)
	var v := _dialog("Уровень пройден!", ["+1 ★   +%d монет" % coins, "Серия побед: %d" % Save.streak], [
		["Дальше", "GreenButton", _next_level],
		["Домой", "Button", func() -> void: _transition(_show_home)],
		["▶ Удвоить монеты за рекламу", "PurpleButton", func() -> void:
			Ads.show_rewarded(func() -> void: Save.add_coins(coins))
			_next_level(), not Ads.is_ready()],
	])
	# звезда и монеты летят вверх, конфетти
	var c := size / 2
	for i in 24:
		var conf := ColorRect.new()
		conf.color = [Color("#ffe14d"), Color("#ff6b9d"), Color("#5fc4ff"), Color("#7dff8a")][i % 4]
		conf.size = Vector2(12, 18)
		conf.position = Vector2(randf() * size.x, -30)
		conf.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_overlay.add_child(conf)
		var tw := conf.create_tween().set_parallel(true)
		tw.tween_property(conf, "position:y", size.y + 40, randf_range(1.4, 2.4))
		tw.tween_property(conf, "rotation", randf_range(-8, 8), 2.0)
		tw.chain().tween_callback(conf.queue_free)
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
	_transition(_start_level.bind(Save.level))


func _show_lose() -> void:
	if _state != "done":
		return
	var left: Array = []
	for g in _level.goals:
		if g.left > 0:
			left.append(GOAL_NAMES.get(g.kind, g.kind) + " " + str(g.left))
	var warn := "Сдашься — потеряешь серию побед (%d)!" % Save.streak if Save.streak > 0 else "Ещё чуть-чуть!"
	_dialog("Ходы кончились", ["Осталось: " + ", ".join(left), warn, "+%d ходов, чтобы доиграть?" % EXTRA_MOVES], [
		["▶ Реклама: +%d ходов" % EXTRA_MOVES, "PurpleButton", func() -> void:
			Ads.show_rewarded(_add_moves), not Ads.is_ready()],
		["%d монет: +%d ходов" % [EXTRA_MOVES_PRICE, EXTRA_MOVES], "OrangeButton", func() -> void:
			if Save.spend(EXTRA_MOVES_PRICE):
				_add_moves(), Save.coins < EXTRA_MOVES_PRICE],
		["Сдаться (−1 жизнь)", "RedButton", func() -> void: _quit_level(_show_home)],
	])


func _add_moves() -> void:
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
		Save.hearts = Save.MAX_HEARTS
		_clear_overlay()
	print("BOT done: %d/%d wins" % [wins, levels - first + 1])
	get_tree().quit()


## Проверка настоящего ввода: свайп и два тапа через очередь событий, как палец на телефоне.
func _run_input_test() -> void:
	Save.hearts = Save.MAX_HEARTS
	_start_level(1)
	await get_tree().create_timer(1.5).timeout
	var ok := 0
	for mode in ["mouse", "swipe", "tap"]:
		var m: Array = []
		for cand in _board.all_moves():
			if cand[0] != cand[1]:
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
	for n in [4, 5, 7, 9, 21, 23, 24, 26, 27, 29, 31]:
		_start_level(n)
		await get_tree().create_timer(1.6).timeout
		await _snap(dir, "2_level_%d" % n)
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
	await get_tree().create_timer(0.12).timeout
	await _snap(dir, "4b_rocket")
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
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "6_win")
	_show_prelevel(9)
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
