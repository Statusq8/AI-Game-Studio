extends Control
## Главный экран «Охотника за Вратами». Интерфейс строится кодом; графика — заглушки.

const B := preload("res://scripts/game/balance.gd")

var _monster_hp := 1.0
var _monster_max := 1.0
var _boss_time := 0.0
var _boss_extra_used := false
var _paused := false
var _ui_timer := 0.0

var _bg: ColorRect
var _gold_label: Label
var _rank_label: Label
var _gate_label: Label
var _area: Control
var _monster_name: Label
var _monster_body: Panel
var _monster_style: StyleBoxFlat
var _hp_bar: ProgressBar
var _hp_label: Label
var _timer_label: Label
var _dps_label: Label
var _buff_button: Button
var _boss_button: Button
var _tap_row: Dictionary
var _hunter_rows: Array[Dictionary] = []
var _overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	GameState.changed.connect(_refresh)
	GameState.rank_up.connect(_on_rank_up)
	GameState.offline_ready.connect(func(_g: float) -> void: _show_offline())
	Ads.ready_changed.connect(func(_r: bool) -> void: _refresh())
	_spawn_monster()
	_refresh()
	if GameState.pending_offline_gold > 0.0:
		_show_offline.call_deferred()


func _process(delta: float) -> void:
	if not _paused:
		var dps := GameState.total_dps()
		if dps > 0.0:
			_damage(dps * delta)
		if B.is_boss(GameState.wave):
			_boss_time -= delta
			if _boss_time <= 0.0:
				_on_boss_timeout()
	_update_monster_ui()
	_ui_timer -= delta
	if _ui_timer <= 0.0:
		_ui_timer = 0.25
		_refresh()


func _input(event: InputEvent) -> void:
	if _paused or _overlay != null:
		return
	var pos := Vector2.INF
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
			and not DisplayServer.is_touchscreen_available():
		pos = event.position
	if pos != Vector2.INF and _area.get_global_rect().has_point(pos):
		_tap(pos - _area.global_position)


# ---------- бой ----------

func _spawn_monster() -> void:
	_monster_max = B.monster_hp(GameState.gate, GameState.wave)
	_monster_hp = _monster_max
	var biome := B.biome(GameState.gate)
	var boss := B.is_boss(GameState.wave)
	_bg.color = biome["bg"]
	_monster_name.text = (biome["boss"] if boss else biome["monster"]) + (" (БОСС)" if boss else "")
	_monster_style.bg_color = biome["color"].darkened(0.25) if boss else biome["color"]
	_monster_body.custom_minimum_size = Vector2(380, 380) if boss else Vector2(290, 290)
	_monster_body.pivot_offset = _monster_body.custom_minimum_size / 2.0
	_boss_time = B.BOSS_TIME
	_boss_extra_used = false
	_update_monster_ui()


func _tap(local_pos: Vector2) -> void:
	var dmg := GameState.tap_damage()
	_popup(local_pos, B.format_num(dmg), Color(1, 1, 1))
	var t := create_tween()
	_monster_body.scale = Vector2(0.92, 0.92)
	t.tween_property(_monster_body, "scale", Vector2.ONE, 0.12)
	_damage(dmg)


func _damage(amount: float) -> void:
	_monster_hp -= amount
	if _monster_hp <= 0.0:
		var reward := GameState.monster_killed()
		_popup(_area.size / 2.0 + Vector2(0, -60), "+" + B.format_num(reward) + " золота", Color(1, 0.85, 0.3))
		_spawn_monster()


func _on_boss_timeout() -> void:
	_paused = true
	var box := _open_overlay("Время вышло!", "Босс оказался сильнее. Улучши отряд или попробуй ещё раз.")
	if not _boss_extra_used:
		var extra := _button("Ещё +15 сек (реклама)", 30, _on_boss_extra_pressed)
		extra.disabled = not Ads.is_ready()
		box.add_child(extra)
	box.add_child(_button("Отступить", 30, func() -> void:
		_close_overlay()
		GameState.boss_failed()
		_spawn_monster()
		_paused = false))


func _on_boss_extra_pressed() -> void:
	Ads.show_rewarded(_grant_boss_extra)


func _grant_boss_extra() -> void:
	_boss_extra_used = true
	_boss_time = B.BOSS_EXTRA_TIME
	_close_overlay()
	_paused = false


func _on_rank_up(rank: int) -> void:
	var box := _open_overlay("Новый ранг: %s!" % B.RANKS[rank],
		"Весь урон отряда и ударов x%s." % str(B.RANK_MULT[rank]))
	box.add_child(_button("Отлично", 30, _close_overlay))


func _show_offline() -> void:
	if _overlay != null or GameState.pending_offline_gold <= 0.0:
		return
	var amount := GameState.pending_offline_gold
	var box := _open_overlay("С возвращением!", "Пока тебя не было, отряд добыл %s золота." % B.format_num(amount))
	var double := _button("Забрать x2 (реклама)", 30, _on_offline_double_pressed)
	double.disabled = not Ads.is_ready()
	box.add_child(double)
	box.add_child(_button("Забрать", 30, func() -> void:
		GameState.claim_offline(1.0)
		_close_overlay()))


func _on_offline_double_pressed() -> void:
	Ads.show_rewarded(_grant_offline_double)


func _grant_offline_double() -> void:
	GameState.claim_offline(2.0)
	_close_overlay()


# ---------- обновление интерфейса ----------

func _update_monster_ui() -> void:
	_hp_bar.max_value = _monster_max
	_hp_bar.value = maxf(_monster_hp, 0.0)
	_hp_label.text = "%s / %s" % [B.format_num(maxf(_monster_hp, 0.0)), B.format_num(_monster_max)]
	if B.is_boss(GameState.wave):
		_timer_label.text = "Осталось: %.1f с" % maxf(_boss_time, 0.0)
	else:
		_timer_label.text = ""


func _refresh() -> void:
	var gs := GameState
	_gold_label.text = "Золото: " + B.format_num(gs.gold)
	_rank_label.text = "Ранг " + B.RANKS[gs.rank()]
	var biome := B.biome(gs.gate)
	var wave_text := "БОСС" if B.is_boss(gs.wave) else "Волна %d/%d" % [gs.wave, B.WAVES_PER_GATE]
	if gs.farm:
		wave_text = "Охота (босс не побеждён)"
	_gate_label.text = "%s · Врата %d · %s" % [biome["name"], gs.gate, wave_text]
	_dps_label.text = "Отряд: %s урона/сек" % B.format_num(gs.total_dps())

	var left := gs.buff_left()
	if left > 0.0:
		_buff_button.text = "x2 урон: %d:%02d" % [int(left) / 60, int(left) % 60]
		_buff_button.disabled = true
	else:
		_buff_button.text = "x2 урон на 5 мин (реклама)"
		_buff_button.disabled = not Ads.is_ready()
	_boss_button.visible = gs.farm

	var tap_cost := B.tap_cost(gs.tap_level)
	_tap_row["info"].text = "Удар  ур. %d\n%s за тап" % [gs.tap_level, B.format_num(gs.tap_damage())]
	_tap_row["buy"].text = B.format_num(tap_cost)
	_tap_row["buy"].disabled = gs.gold < tap_cost
	for i in _hunter_rows.size():
		var row := _hunter_rows[i]
		var lvl: int = gs.hunters[i]
		var cost := B.hunter_cost(i, lvl)
		var hname: String = B.HUNTERS[i]["name"]
		if lvl == 0:
			row["info"].text = "%s\nне в отряде" % hname
			row["buy"].text = "Нанять " + B.format_num(cost)
		else:
			row["info"].text = "%s  ур. %d\n%s урона/сек" % [hname, lvl, B.format_num(B.hunter_dps(i, lvl))]
			row["buy"].text = B.format_num(cost)
		row["buy"].disabled = gs.gold < cost
		row["icon"].modulate.a = 1.0 if lvl > 0 else 0.3


# ---------- построение интерфейса ----------

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	_gold_label = _label("", 34, Color(1, 0.85, 0.3))
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_gold_label)
	_rank_label = _label("", 34, Color(0.7, 0.85, 1))
	top.add_child(_rank_label)

	_gate_label = _label("", 24, Color(0.85, 0.85, 0.9))
	_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gate_label)

	# Зона боя: тап по любой её точке бьёт монстра.
	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.custom_minimum_size = Vector2(0, 520)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.clip_contents = true
	root.add_child(_area)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(center)
	var mbox := VBoxContainer.new()
	mbox.add_theme_constant_override("separation", 12)
	mbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(mbox)

	_monster_name = _label("", 32)
	_monster_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mbox.add_child(_monster_name)

	_monster_body = Panel.new()
	_monster_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_body.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_monster_style = StyleBoxFlat.new()
	_monster_style.set_corner_radius_all(60)
	_monster_style.set_border_width_all(4)
	_monster_style.border_color = Color(0, 0, 0, 0.5)
	_monster_body.add_theme_stylebox_override("panel", _monster_style)
	mbox.add_child(_monster_body)

	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(440, 30)
	_hp_bar.show_percentage = false
	_hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mbox.add_child(_hp_bar)
	_hp_label = _label("", 22)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mbox.add_child(_hp_label)
	_timer_label = _label("", 28, Color(1, 0.45, 0.4))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mbox.add_child(_timer_label)

	_dps_label = _label("", 24, Color(0.8, 0.9, 1))
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_dps_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	root.add_child(actions)
	_buff_button = _button("", 26, _on_buff_pressed)
	_buff_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_buff_button)
	_boss_button = _button("Сразиться с боссом", 26, func() -> void:
		GameState.start_boss()
		_spawn_monster())
	_boss_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_boss_button)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	root.add_child(list)
	_tap_row = _upgrade_row(list, Color(0.95, 0.95, 1.0), func() -> void: GameState.try_buy_tap())
	for i in B.HUNTERS.size():
		var idx := i
		_hunter_rows.append(_upgrade_row(list, B.HUNTERS[i]["color"], func() -> void: GameState.try_buy_hunter(idx)))


func _upgrade_row(parent: Container, color: Color, on_buy: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	parent.add_child(row)
	var icon := ColorRect.new()
	icon.color = color
	icon.custom_minimum_size = Vector2(72, 72)
	row.add_child(icon)
	var info := _label("", 24)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var buy := _button("", 26, on_buy)
	buy.custom_minimum_size = Vector2(220, 76)
	row.add_child(buy)
	return {"icon": icon, "info": info, "buy": buy}


func _on_buff_pressed() -> void:
	Ads.show_rewarded(func() -> void: GameState.activate_buff())


func _label(text: String, size: int, color: Color = Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, size: int, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_press)
	return b


func _popup(pos: Vector2, text: String, color: Color) -> void:
	var l := _label(text, 34, color)
	l.position = pos - Vector2(40, 20)
	_area.add_child(l)
	var t := create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 120.0, 0.7)
	t.tween_property(l, "modulate:a", 0.0, 0.7)
	t.chain().tween_callback(l.queue_free)


func _open_overlay(title: String, text: String) -> VBoxContainer:
	_close_overlay()
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0, 0, 0, 0.7)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	var t := _label(title, 38, Color(1, 0.85, 0.3))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var body := _label(text, 26)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		_show_offline.call_deferred()
