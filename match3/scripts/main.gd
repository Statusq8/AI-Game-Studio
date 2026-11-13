extends Control
## Экраны игры: главный (кнопка «Уровень N»), уровень (поле, ходы, цели), окна победы / поражения / паузы.

const UiTheme := preload("res://scripts/ui_theme.gd")
const Levels := preload("res://scripts/levels.gd")
const Board := preload("res://scripts/board.gd")
const Gem := preload("res://scripts/gem.gd")

const VERSION := "0.2.1"
const WIN_COINS := 50
const COINS_PER_MOVE := 5
const EXTRA_MOVES := 5
const EXTRA_MOVES_PRICE := 300

var _bg: TextureRect
var _home: Control
var _level_screen: Control
var _overlay: Control
var _fx: Node2D
var _home_level_btn: Button
var _coin_labels: Array[Label] = []
var _hearts_label: Label
var _hearts_timer: Label
var _ui_tick := 0.0

var _board: Board
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
			_run_bot.call_deferred(int(arg.trim_prefix("--bot=")) if "=" in arg else 10)


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
	_bg.texture = tex
	_bg.stretch_mode = TextureRect.STRETCH_SCALE
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
	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.add_theme_constant_override("margin_left", 24)
	top.add_theme_constant_override("margin_top", 36)
	top.add_theme_constant_override("margin_right", 24)
	_home.add_child(top)
	var row := HBoxContainer.new()
	top.add_child(row)
	row.add_theme_constant_override("separation", 16)
	row.add_child(_hearts_pill())
	row.add_child(_coin_pill())

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 30)
	_home.add_child(center)

	var gems := Control.new()
	gems.custom_minimum_size = Vector2(0, 150)
	center.add_child(gems)
	for i in 5:
		var g: Node2D = Gem.new()
		g.color = i
		g.size = 110.0
		g.position = Vector2(0, 75)
		gems.add_child(g)
		var tw := g.create_tween().set_loops()
		tw.tween_property(g, "position:y", 60.0, 0.9 + i * 0.13).set_trans(Tween.TRANS_SINE)
		tw.tween_property(g, "position:y", 90.0, 0.9 + i * 0.13).set_trans(Tween.TRANS_SINE)
	gems.resized.connect(func() -> void:
		var i := 0
		for g in gems.get_children():
			g.position.x = gems.size.x / 2 + (i - 2) * 120
			i += 1)

	var title := Label.new()
	title.text = "ТРИ В РЯД"
	title.theme_type_variation = "TitleLabel"
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_constant_override("outline_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)
	var sub := Label.new()
	sub.text = "рабочее название · версия %s" % VERSION
	sub.add_theme_font_size_override("font_size", 24)
	sub.modulate = Color(1, 1, 1, 0.8)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 120)
	center.add_child(spacer)

	var holder := CenterContainer.new()
	center.add_child(holder)
	_home_level_btn = Button.new()
	_home_level_btn.theme_type_variation = "GreenButton"
	_home_level_btn.custom_minimum_size = Vector2(420, 120)
	_home_level_btn.add_theme_font_size_override("font_size", 46)
	_home_level_btn.pressed.connect(_try_play)
	holder.add_child(_home_level_btn)
	var pulse := _home_level_btn.create_tween().set_loops()
	_home_level_btn.pivot_offset = Vector2(210, 60)
	pulse.tween_property(_home_level_btn, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_home_level_btn, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)


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

	var row1 := HBoxContainer.new()
	col.add_child(row1)
	_level_label = Label.new()
	_level_label.theme_type_variation = "TitleLabel"
	_level_label.add_theme_font_size_override("font_size", 34)
	_level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1.add_child(_level_label)
	var menu := Button.new()
	menu.text = "II"
	menu.theme_type_variation = "PurpleButton"
	menu.custom_minimum_size = Vector2(84, 76)
	menu.pressed.connect(_show_pause)
	row1.add_child(menu)

	var hud := PanelContainer.new()
	hud.theme_type_variation = "HudPanel"
	col.add_child(hud)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 14)
	hud.add_child(hrow)
	var moves_box := VBoxContainer.new()
	moves_box.custom_minimum_size = Vector2(150, 0)
	moves_box.add_theme_constant_override("separation", -6)
	hrow.add_child(moves_box)
	var ml := Label.new()
	ml.text = "ХОДЫ"
	ml.add_theme_font_size_override("font_size", 22)
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	moves_box.add_child(ml)
	_moves_label = Label.new()
	_moves_label.theme_type_variation = "TitleLabel"
	_moves_label.add_theme_font_size_override("font_size", 64)
	_moves_label.add_theme_constant_override("outline_size", 10)
	_moves_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_moves_label.pivot_offset = Vector2(75, 40)
	moves_box.add_child(_moves_label)
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.3)
	sep.custom_minimum_size = Vector2(3, 0)
	hrow.add_child(sep)
	_goals_box = HBoxContainer.new()
	_goals_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_goals_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_goals_box.add_theme_constant_override("separation", 12)
	hrow.add_child(_goals_box)

	_board_frame = PanelContainer.new()
	_board_frame.theme_type_variation = "BoardPanel"
	_board_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_screen.add_child(_board_frame)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.custom_minimum_size = Vector2(8, 8) * Board.CELL
	_board_frame.add_child(clip)
	_board = Board.new()
	clip.add_child(_board)
	_board.move_made.connect(_on_move)
	_board.gem_cleared.connect(_on_gem_cleared)
	_board.goal_hit.connect(_on_goal_hit)
	_board.settled.connect(_on_settled)
	_board.big_hit.connect(func(p: float) -> void: _shake = maxf(_shake, 6.0 + p * 4.0))
	_level_screen.resized.connect(func() -> void: _board_frame.position = _board_rest())


func _board_rest() -> Vector2:
	var s := _board_frame.get_combined_minimum_size()
	var free_top := 300.0
	var y := free_top + maxf(0.0, (_level_screen.size.y - free_top - s.y) * 0.45)
	return Vector2((_level_screen.size.x - s.x) / 2.0, y)


# ---------- экраны ----------

func _show_home() -> void:
	_state = "idle"
	_clear_overlay()
	_home.visible = true
	_level_screen.visible = false
	_board.input_enabled = false
	_home_level_btn.text = "Уровень %d" % Save.level
	_refresh_coins()
	_refresh_hearts()


func _try_play() -> void:
	Save.update_hearts()
	if Save.hearts > 0:
		_start_level(Save.level)
		return
	var sec := Save.seconds_to_heart()
	_dialog("Нет жизней", ["Новая жизнь через %d:%02d" % [sec / 60, sec % 60]], [
		["▶ Реклама: +1 жизнь", "PurpleButton", func() -> void:
			Ads.show_rewarded(func() -> void:
				Save.add_heart()
				_show_home()), not Ads.is_ready()],
		["Закрыть", "Button", _show_home],
	])


## Выход из уровня без победы стоит жизнь.
func _quit_level(then: Callable) -> void:
	Save.lose_heart()
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
	_board_frame.position = _board_rest()
	_build_goals()
	_update_moves()
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
		icon.custom_minimum_size = Vector2(70, 62)
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


func _on_goal_hit(kind: String, at: Vector2) -> void:
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
	match _state:
		"play":
			if _goals_done():
				_begin_bonus()
			elif _moves <= 0:
				_board.input_enabled = false
				_state = "done"
				await get_tree().create_timer(0.4).timeout
				_show_lose()
		"bonus":
			_state = "done"
			_show_win()


func _begin_bonus() -> void:
	_state = "bonus"
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
	if bonus > 0:
		var n := mini(bonus, 12)
		_moves = 0
		_update_moves()
		_board.spawn_bonus_rockets(n)
		await get_tree().create_timer(0.5).timeout
	_board.detonate_all_specials()


# ---------- окна ----------

func _clear_overlay() -> void:
	for c in _overlay.get_children():
		c.queue_free()


func _dialog(title_text: String, lines: Array, buttons: Array) -> void:
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


func _show_win() -> void:
	var coins := WIN_COINS + int(_level.get("bonus_coins", 0))
	Save.level = _level.n + 1
	Save.add_coins(coins)
	_dialog("Уровень пройден!", ["+%d монет" % coins], [
		["Дальше", "GreenButton", func() -> void: _start_level(Save.level)],
		["Домой", "Button", _show_home],
	])


func _show_lose() -> void:
	if _state != "done":
		return
	_dialog("Ходы кончились", ["Осталось собрать совсем немного!", "+%d ходов, чтобы доиграть?" % EXTRA_MOVES], [
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
func _run_bot(levels: int) -> void:
	_bot = true
	Engine.time_scale = 8.0
	var wins := 0
	for n in range(1, levels + 1):
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
			if m[0] == m[1]:
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
	print("BOT done: %d/%d wins" % [wins, levels])
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
	await _snap(dir, "1_home")
	# уровни с разными препятствиями: 4 ящики, 5 трава, 6 предметы, 7 цепи, 8 вазы
	for n in [4, 5, 6, 7, 8]:
		_start_level(n)
		await get_tree().create_timer(1.4).timeout
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
	_state = "done"
	_show_lose()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "5_lose")
	_level["bonus_coins"] = 40
	_show_win()
	await get_tree().create_timer(0.5).timeout
	await _snap(dir, "6_win")
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
