extends Control
## Главный экран «Охотника за Вратами». Интерфейс строится кодом; графика — заглушки.

const B := preload("res://scripts/game/balance.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const IC_STRIKE := preload("res://assets/art/ic_strike.png")
const IC_GOLD := preload("res://assets/art/ic_gold.png")
const IC_X2 := preload("res://assets/art/ic_x2.png")
const IC_HOURGLASS := preload("res://assets/art/ic_hourglass.png")
const IC_CHEST := preload("res://assets/art/ic_chest.png")
const IC_AD := preload("res://assets/art/ic_ad.png")

var _monster_hp := 1.0
var _monster_max := 1.0
var _boss_time := 0.0
var _boss_extra_used := false
var _paused := false
var _ui_timer := 0.0

var _bg: ColorRect
var _bg_art: TextureRect
var _squad: Array[TextureRect] = []
var _attack_timer := 0.0
var _gold_label: Label
var _rank_label: Label
var _rank_badge: TextureRect
var _gate_label: Label
var _area: Control
var _stage: Control
var _gold_icon: TextureRect
var _shake := 0.0
var _particles: Array[CPUParticles2D] = []
var _particle_index := 0
var _monster_name: Label
var _monster_body: Panel
var _monster_art: TextureRect
var _monster_style: StyleBoxFlat
var _hp_bar: ProgressBar
var _hp_back: ProgressBar
var _hp_label: Label
var _buff_button: Button
var _boss_button: Button
var _tap_row: Dictionary
var _hunter_rows: Array[Dictionary] = []
var _overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_build_ui()
	GameState.changed.connect(_refresh)
	GameState.rank_up.connect(_on_rank_up)
	GameState.offline_ready.connect(func(_g: float) -> void: _show_offline())
	Ads.ready_changed.connect(func(_r: bool) -> void: _refresh())
	_spawn_monster()
	_refresh()
	_start_idle_animations.call_deferred()
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
	if _hp_back.value > _hp_bar.value:
		_hp_back.value = move_toward(_hp_back.value, _hp_bar.value, _monster_max * 1.5 * delta)
	if _shake > 0.0:
		_stage.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, 70.0 * delta)
	elif _stage.position != Vector2.ZERO:
		_stage.position = Vector2.ZERO
	_attack_timer -= delta
	if _attack_timer <= 0.0 and not _paused:
		_attack_timer = 0.9
		_squad_attack()
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

func _squad_attack() -> void:
	for i in _squad.size():
		var sprite := _squad[i]
		if not sprite.visible:
			continue
		var t := create_tween()
		t.tween_interval(i * 0.15)
		t.tween_property(sprite, "rotation", 0.12, 0.08)
		t.tween_callback(_hunter_hit.bind(i))
		t.tween_property(sprite, "rotation", 0.0, 0.18)


func _hunter_hit(index: int) -> void:
	if _paused:
		return
	var center := _monster_center()
	var spot := center + Vector2(randf_range(-70, 70), randf_range(-90, 30))
	_burst(spot, B.HUNTERS[index]["color"], 10, 0.8)
	var dps := B.hunter_dps(index, GameState.hunters[index]) * GameState.dmg_mult() * 0.9
	if dps >= 1.0:
		_popup(spot, B.format_num(dps), Color(B.HUNTERS[index]["color"]).lightened(0.4), 24)

func _spawn_monster() -> void:
	_monster_max = B.monster_hp(GameState.gate, GameState.wave)
	_monster_hp = _monster_max
	var biome := B.biome(GameState.gate)
	var boss := B.is_boss(GameState.wave)
	_bg.color = biome["bg"]
	var art_path: String = biome.get("art", "")
	_bg_art.texture = load(art_path) if art_path != "" else null
	_monster_name.text = (biome["boss"] if boss else biome["monster"]) + (" (БОСС)" if boss else "")
	_monster_style.bg_color = biome["color"].darkened(0.25) if boss else biome["color"]
	_monster_body.custom_minimum_size = Vector2(300, 300) if boss else Vector2(230, 230)
	_monster_body.pivot_offset = _monster_body.custom_minimum_size / 2.0
	var mart: String = biome.get("boss_art" if boss else "monster_art", "")
	_monster_art.texture = load(mart) if mart != "" else null
	_monster_art.custom_minimum_size = Vector2(360, 320) if boss else Vector2(290, 260)
	_monster_art.pivot_offset = _monster_art.custom_minimum_size * Vector2(0.5, 1.0)
	_monster_art.visible = _monster_art.texture != null
	_monster_body.visible = not _monster_art.visible
	_monster_art.modulate = Color(1, 1, 1)
	_boss_time = B.BOSS_TIME
	_boss_extra_used = false
	_hp_back.max_value = _monster_max
	_hp_back.value = _monster_max
	_update_monster_ui()
	var target: Control = _monster_art if _monster_art.visible else _monster_body
	target.scale = Vector2(0.6, 0.6)
	target.rotation = 0.0
	create_tween().tween_property(target, "scale", Vector2.ONE, 0.3) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if boss:
		_boss_intro(biome["boss"])


func _tap(local_pos: Vector2) -> void:
	var dmg := GameState.tap_damage()
	var crit := randf() < B.CRIT_CHANCE
	if crit:
		dmg *= B.CRIT_MULT
		_popup(local_pos, "КРИТ! " + B.format_num(dmg), Color(1, 0.55, 0.15), 46)
		_burst(local_pos, Color(1, 0.6, 0.2), 22, 1.4)
		_shake = maxf(_shake, 9.0)
	else:
		_popup(local_pos, B.format_num(dmg), Color(1, 1, 1))
		_burst(local_pos, B.biome(GameState.gate)["color"].lightened(0.3), 12, 1.0)
		_shake = maxf(_shake, 3.0)
	var target: Control = _monster_art if _monster_art.visible else _monster_body
	var t := create_tween().set_parallel(true)
	target.scale = Vector2(0.94, 0.94)
	target.modulate = Color(1.6, 1.3, 1.3)
	t.tween_property(target, "scale", Vector2.ONE, 0.12)
	t.tween_property(target, "modulate", Color(1, 1, 1), 0.15)
	_damage(dmg)


func _damage(amount: float) -> void:
	_monster_hp -= amount
	if _monster_hp <= 0.0:
		var was_boss := B.is_boss(GameState.wave)
		var cleared_gate := GameState.gate
		var center := _monster_center()
		_death_ghost()
		var reward := GameState.monster_killed()
		_popup(center + Vector2(0, -60), "+" + B.format_num(reward), Color(1, 0.85, 0.3), 40)
		_burst(center, Color(1, 0.85, 0.35), 26, 1.6)
		_fly_coins(_area.global_position + center, 8 if was_boss else 4)
		_shake = maxf(_shake, 18.0 if was_boss else 7.0)
		if was_boss:
			_banner("Врата %d закрыты!" % cleared_gate, Color(1, 0.85, 0.3), 60)
		_spawn_monster()


func _on_boss_timeout() -> void:
	_paused = true
	var box := _open_overlay("Время вышло!", "Босс оказался сильнее. Улучши отряд или попробуй ещё раз.", IC_HOURGLASS)
	if not _boss_extra_used:
		var extra := _button("Ещё +15 сек", 30, _on_boss_extra_pressed)
		extra.icon = IC_AD
		extra.theme_type_variation = "AdButton"
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
	var big := _make_badge(rank, 170)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(big)
	box.move_child(big, 0)
	box.add_child(_button("Отлично", 30, _close_overlay))


func _show_offline() -> void:
	if _overlay != null or GameState.pending_offline_gold <= 0.0:
		return
	var amount := GameState.pending_offline_gold
	var box := _open_overlay("С возвращением!", "Пока тебя не было, отряд добыл %s золота." % B.format_num(amount), IC_CHEST)
	var double := _button("Забрать x2", 30, _on_offline_double_pressed)
	double.icon = IC_AD
	double.theme_type_variation = "AdButton"
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


# ---------- эффекты ----------

func _monster_center() -> Vector2:
	var target: Control = _monster_art if _monster_art.visible else _monster_body
	return target.get_global_rect().get_center() - _area.global_position


## Вспышка частиц в координатах зоны боя (пул из 8 эмиттеров).
func _burst(pos: Vector2, color: Color, amount: int, power: float) -> void:
	if _particles.is_empty():
		for i in 8:
			var p := CPUParticles2D.new()
			p.one_shot = true
			p.emitting = false
			p.explosiveness = 1.0
			p.lifetime = 0.5
			p.spread = 180.0
			p.gravity = Vector2(0, 700)
			p.initial_velocity_min = 180.0
			p.initial_velocity_max = 420.0
			p.scale_amount_min = 5.0
			p.scale_amount_max = 11.0
			var ramp := Gradient.new()
			ramp.set_color(0, Color(1, 1, 1, 1))
			ramp.set_color(1, Color(1, 1, 1, 0))
			p.color_ramp = ramp
			_area.add_child(p)
			_particles.append(p)
	var e := _particles[_particle_index]
	_particle_index = (_particle_index + 1) % _particles.size()
	e.position = pos
	e.amount = amount
	e.color = color
	e.initial_velocity_max = 420.0 * power
	e.restart()


func _death_ghost() -> void:
	if not _monster_art.visible or _monster_art.texture == null:
		return
	var rect := _monster_art.get_global_rect()
	var ghost := TextureRect.new()
	ghost.texture = _monster_art.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = rect.position
	ghost.size = rect.size
	ghost.pivot_offset = rect.size / 2.0
	add_child(ghost)
	var t := create_tween().set_parallel(true)
	ghost.modulate = Color(3, 3, 3, 1)
	t.tween_property(ghost, "scale", Vector2(1.25, 1.25), 0.28)
	t.tween_property(ghost, "modulate", Color(3, 3, 3, 0), 0.28)
	t.chain().tween_callback(ghost.queue_free)


## Монеты летят от монстра к счётчику золота.
func _fly_coins(from_global: Vector2, count: int) -> void:
	var to := _gold_icon.get_global_rect().get_center()
	for i in count:
		var coin := _icon(IC_GOLD, 40)
		coin.pivot_offset = Vector2(20, 20)
		var start := from_global + Vector2(randf_range(-60, 60), randf_range(-60, 40)) - Vector2(20, 20)
		coin.position = start
		add_child(coin)
		var ctrl := start + Vector2(randf_range(-160, 160), -randf_range(80, 220))
		var end := to - Vector2(20, 20)
		var t := create_tween()
		t.tween_interval(i * 0.05)
		t.tween_method(_coin_step.bind(coin, start, ctrl, end), 0.0, 1.0, 0.55).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void:
			coin.queue_free()
			_pulse_gold())


func _coin_step(k: float, coin: Control, start: Vector2, ctrl: Vector2, end: Vector2) -> void:
	var a := start.lerp(ctrl, k)
	var b := ctrl.lerp(end, k)
	coin.position = a.lerp(b, k)
	coin.scale = Vector2.ONE * lerpf(1.0, 0.6, k)


func _pulse_gold() -> void:
	_gold_label.pivot_offset = _gold_label.size / 2.0
	_gold_icon.pivot_offset = _gold_icon.size / 2.0
	var t := create_tween().set_parallel(true)
	_gold_label.scale = Vector2(1.15, 1.15)
	_gold_icon.scale = Vector2(1.2, 1.2)
	t.tween_property(_gold_label, "scale", Vector2.ONE, 0.15)
	t.tween_property(_gold_icon, "scale", Vector2.ONE, 0.15)


## Крупная надпись по центру экрана.
func _banner(text: String, color: Color, size: int, hold: float = 0.7) -> void:
	var l := _label(text, size, color, true)
	l.add_theme_constant_override("outline_size", 14)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position.y = -140
	add_child(l)
	l.pivot_offset = get_viewport_rect().size / 2.0
	l.scale = Vector2(1.8, 1.8)
	l.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 1.0, 0.15)
	t.chain().tween_interval(hold)
	t.chain().tween_property(l, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(l.queue_free)


## Заставка босса: пауза, надпись, затем таймер стартует.
func _boss_intro(boss_name: String) -> void:
	_paused = true
	_banner("БОСС\n" + boss_name, Color(1, 0.35, 0.3), 64, 0.9)
	_shake = 12.0
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if _overlay == null:
			_paused = false)


func _start_idle_animations() -> void:
	for i in _squad.size():
		var sprite := _squad[i]
		var t := create_tween().set_loops()
		t.tween_interval(i * 0.3)
		t.tween_property(sprite, "scale", Vector2(1.0, 1.025), 0.9).set_trans(Tween.TRANS_SINE)
		t.tween_property(sprite, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	var m := create_tween().set_loops()
	m.tween_property(_monster_art, "rotation", 0.025, 1.3).set_trans(Tween.TRANS_SINE)
	m.tween_property(_monster_art, "rotation", -0.025, 1.3).set_trans(Tween.TRANS_SINE)


# ---------- обновление интерфейса ----------

func _update_monster_ui() -> void:
	_hp_bar.max_value = _monster_max
	_hp_bar.value = maxf(_monster_hp, 0.0)
	_hp_label.text = "%s / %s" % [B.format_num(maxf(_monster_hp, 0.0)), B.format_num(_monster_max)]
	if B.is_boss(GameState.wave):
		_hp_label.text += "   ·   %.1f с" % maxf(_boss_time, 0.0)
		_hp_label.add_theme_color_override("font_color", Color(1, 0.55, 0.5))
	else:
		_hp_label.add_theme_color_override("font_color", Color(1, 1, 1))


func _refresh() -> void:
	var gs := GameState
	_gold_label.text = B.format_num(gs.gold)
	_rank_label.text = B.RANKS[gs.rank()]
	_rank_badge.texture = load(B.RANK_BADGES[gs.rank()])
	var biome := B.biome(gs.gate)
	var wave_text := "БОСС" if B.is_boss(gs.wave) else "Волна %d/%d" % [gs.wave, B.WAVES_PER_GATE]
	if gs.farm:
		wave_text = "Охота (босс не побеждён)"
	_gate_label.text = "%s · Врата %d · %s\nОтряд: %s урона/сек" % [biome["name"], gs.gate, wave_text, B.format_num(gs.total_dps())]

	var left := gs.buff_left()
	if left > 0.0:
		_buff_button.text = "x2 урон: %d:%02d" % [int(left) / 60, int(left) % 60]
		_buff_button.icon = IC_X2
		_buff_button.disabled = true
	else:
		_buff_button.text = "x2 урон · 5 мин"
		_buff_button.icon = IC_AD
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
		row["icon"].modulate.a = 1.0 if lvl > 0 else 0.35
		_squad[i].visible = lvl > 0


# ---------- построение интерфейса ----------

func _build_ui() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg_art = TextureRect.new()
	_bg_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_art)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.28)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)

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

	var top_panel := PanelContainer.new()
	top_panel.theme_type_variation = "TopPanel"
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top_panel)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top_panel.add_child(top)
	_gold_icon = _icon(IC_GOLD, 52)
	top.add_child(_gold_icon)
	_gold_label = _label("", 36, Color(1, 0.85, 0.3), true)
	_gold_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_gold_label)
	var badge := _make_badge(0, 76)
	_rank_badge = badge
	_rank_label = badge.get_child(0)
	top.add_child(badge)

	_gate_label = _label("", 24, Color(0.85, 0.85, 0.9))
	_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_gate_label)

	# Зона боя: тап по любой её точке бьёт монстра.
	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.custom_minimum_size = Vector2(0, 0)
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.clip_contents = true
	root.add_child(_area)

	var stage := VBoxContainer.new()
	_stage = stage
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(stage)
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(center)
	var squad_box := HBoxContainer.new()
	squad_box.alignment = BoxContainer.ALIGNMENT_CENTER
	squad_box.add_theme_constant_override("separation", -40)
	squad_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(squad_box)
	for h in B.HUNTERS:
		var sprite := TextureRect.new()
		sprite.texture = load(h["sprite"])
		sprite.custom_minimum_size = Vector2(160, 165)
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.pivot_offset = Vector2(80, 165)
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		squad_box.add_child(sprite)
		_squad.append(sprite)
	var mbox := VBoxContainer.new()
	mbox.add_theme_constant_override("separation", 12)
	mbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(mbox)

	_monster_name = _label("", 32, Color(1, 1, 1), true)
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
	_monster_art = TextureRect.new()
	_monster_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_monster_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_monster_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_monster_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mbox.add_child(_monster_art)

	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(460, 32)
	hp_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mbox.add_child(hp_holder)
	_hp_back = ProgressBar.new()
	_hp_bar = ProgressBar.new()
	for bar: ProgressBar in [_hp_back, _hp_bar]:
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_holder.add_child(bar)
	_hp_back.theme_type_variation = "HpBack"
	_hp_bar.theme_type_variation = "HpFront"
	_hp_label = _label("", 22)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mbox.add_child(_hp_label)


	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "SheetPanel"
	root.add_child(sheet)
	var sheet_box := VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 10)
	sheet.add_child(sheet_box)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	sheet_box.add_child(actions)
	_buff_button = _button("", 26, _on_buff_pressed)
	_buff_button.theme_type_variation = "AdButton"
	_buff_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_buff_button)
	_boss_button = _button("Сразиться с боссом", 26, func() -> void:
		GameState.start_boss()
		_spawn_monster())
	_boss_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_boss_button.theme_type_variation = "BossButton"
	actions.add_child(_boss_button)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	sheet_box.add_child(list)
	_tap_row = _upgrade_row(list, IC_STRIKE, func() -> void: GameState.try_buy_tap())
	for i in B.HUNTERS.size():
		var idx := i
		_hunter_rows.append(_upgrade_row(list, load(B.HUNTERS[i]["icon"]), func() -> void: GameState.try_buy_hunter(idx)))


func _upgrade_row(parent: Container, icon_tex: Texture2D, on_buy: Callable) -> Dictionary:
	var row_panel := PanelContainer.new()
	row_panel.theme_type_variation = "RowPanel"
	parent.add_child(row_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row_panel.add_child(row)
	var icon: Control
	if icon_tex != null:
		var tr := TextureRect.new()
		tr.texture = icon_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon = tr
	else:
		var cr := ColorRect.new()
		cr.color = Color(0.95, 0.95, 1.0, 0.85)
		icon = cr
	icon.custom_minimum_size = Vector2(60, 60)
	row.add_child(icon)
	var info := _label("", 22)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(info)
	var buy := _button("", 26, on_buy)
	buy.custom_minimum_size = Vector2(210, 64)
	buy.theme_type_variation = "BuyButton"
	row.add_child(buy)
	return {"icon": icon, "info": info, "buy": buy}


func _on_buff_pressed() -> void:
	Ads.show_rewarded(func() -> void: GameState.activate_buff())


func _label(text: String, size: int, color: Color = Color(1, 1, 1), title: bool = false) -> Label:
	var l := Label.new()
	if title:
		l.theme_type_variation = "TitleLabel"
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, size: int, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_constant_override("icon_max_width", 52)
	b.pressed.connect(on_press)
	return b


## Эмблема ранга с буквой поверх (буквы рисуем сами — нейросети их искажают).
func _make_badge(rank: int, size: int) -> TextureRect:
	var tr := _icon(load(B.RANK_BADGES[rank]), size)
	var letter := _label(B.RANKS[rank], int(size * 0.42), Color(1, 1, 1), true)
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.position.y = size * 0.03
	tr.add_child(letter)
	return tr


func _icon(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _popup(pos: Vector2, text: String, color: Color, size: int = 36) -> void:
	var l := _label(text, size, color, true)
	l.position = pos - Vector2(40, 20)
	_area.add_child(l)
	var t := create_tween().set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 120.0, 0.7)
	t.tween_property(l, "modulate:a", 0.0, 0.7)
	t.chain().tween_callback(l.queue_free)


func _open_overlay(title: String, text: String, image: Texture2D = null) -> VBoxContainer:
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
	panel.theme_type_variation = "DialogPanel"
	panel.custom_minimum_size = Vector2(600, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	if image != null:
		var pic := _icon(image, 150)
		pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		box.add_child(pic)
	var t := _label(title, 40, Color(1, 0.85, 0.3), true)
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
