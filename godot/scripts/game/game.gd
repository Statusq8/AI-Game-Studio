extends Control
## Главный экран «Охотника за Вратами».
## Композиция: отряд слева смотрит вправо, монстр справа смотрит влево, все стоят на одной линии земли.

const B := preload("res://scripts/game/balance.gd")
const UiTheme := preload("res://scripts/ui/ui_theme.gd")
const IC_STRIKE := preload("res://assets/art/ic_strike.png")
const IC_GOLD := preload("res://assets/art/ic_gold.png")
const IC_X2 := preload("res://assets/art/ic_x2.png")
const IC_HOURGLASS := preload("res://assets/art/ic_hourglass.png")
const IC_CHEST := preload("res://assets/art/ic_chest.png")
const IC_AD := preload("res://assets/art/ic_ad.png")

const HERO_SIZE := Vector2(170, 176)
## Расстановка отряда: смещение по x и подъём над линией земли (задний ряд выше).
const HERO_SLOTS := [Vector2(178, 0), Vector2(96, -30), Vector2(8, -58)]
const MONSTER_SIZE := Vector2(330, 300)
const BOSS_SIZE := Vector2(410, 380)
const MAX_POPUPS := 14

var _monster_hp := 1.0
var _monster_max := 1.0
var _boss_time := 0.0
var _boss_extra_used := false
var _paused := false
var _ui_timer := 0.0
var _attack_timer := 0.0
var _shake := 0.0
var _popups := 0
var _shown_gold := -1.0
var _fade: ColorRect
var _hud: Control
var _sheet: Control

var _glow: Texture2D
var _additive: CanvasItemMaterial
var _particles: Array[CPUParticles2D] = []
var _particle_index := 0

# Сцена
var _bg: ColorRect
var _bg_art: TextureRect
var _area: Control
var _stage: Control
var _squad: Array[TextureRect] = []
var _squad_base: Array[Vector2] = []
var _hero_shadows: Array[Panel] = []
var _monster_art: TextureRect
var _monster_body: Panel
var _monster_style: StyleBoxFlat
var _monster_shadow: Panel
var _monster_base := Vector2.ZERO
var _monster_info: VBoxContainer
var _monster_name: Label
var _hp_bar: ProgressBar
var _hp_back: ProgressBar
var _hp_label: Label
var _timer_label: Label

# Интерфейс
var _gold_icon: TextureRect
var _gold_label: Label
var _gate_label: Label
var _pips: Array[Panel] = []
var _rank_badge: TextureRect
var _rank_label: Label
var _dps_label: Label
var _buff_button: Button
var _boss_button: Button
var _tap_row: Dictionary
var _hunter_rows: Array[Dictionary] = []
var _overlay: Control = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiTheme.build()
	_make_fx_resources()
	_build_ui()
	GameState.changed.connect(_refresh)
	GameState.rank_up.connect(_on_rank_up)
	GameState.offline_ready.connect(func(_g: float) -> void: _show_offline())
	Ads.ready_changed.connect(func(_r: bool) -> void: _refresh())
	_area.resized.connect(_layout_stage)
	_spawn_monster()
	_refresh()
	_start_idle_animations.call_deferred()
	_intro.call_deferred()
	if GameState.pending_offline_gold > 0.0:
		_show_offline.call_deferred()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_run_shots.call_deferred(arg.trim_prefix("--shots="))
		elif arg == "--demo":
			_run_demo.call_deferred()


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
		_hp_back.value = move_toward(_hp_back.value, _hp_bar.value, _monster_max * 1.2 * delta)
	if _shake > 0.0:
		_stage.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, 60.0 * delta)
	elif _stage.position != Vector2.ZERO:
		_stage.position = Vector2.ZERO
	_attack_timer -= delta
	if _attack_timer <= 0.0 and not _paused:
		_attack_timer = 1.0
		_squad_attack()
	if _shown_gold < 0.0:
		_shown_gold = GameState.gold
	_shown_gold = lerpf(_shown_gold, GameState.gold, 1.0 - exp(-9.0 * delta))
	if absf(_shown_gold - GameState.gold) < 1.0:
		_shown_gold = GameState.gold
	_gold_label.text = B.format_num(_shown_gold)
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
	var art_path: String = biome.get("art", "")
	_bg_art.texture = load(art_path) if art_path != "" else null
	_monster_name.text = biome["boss"] if boss else biome["monster"]
	_monster_name.add_theme_color_override("font_color", Color(1, 0.55, 0.5) if boss else Color(1, 1, 1))
	_monster_style.bg_color = biome["color"]
	var mart: String = biome.get("boss_art" if boss else "monster_art", "")
	_monster_art.texture = load(mart) if mart != "" else null
	_monster_art.visible = _monster_art.texture != null
	_monster_body.visible = not _monster_art.visible
	_monster_art.modulate = Color(1, 1, 1)
	_boss_time = B.BOSS_TIME
	_boss_extra_used = false
	_hp_bar.max_value = _monster_max
	_hp_back.max_value = _monster_max
	_hp_back.value = _monster_max
	_layout_stage()
	_update_monster_ui()
	var target := _monster_node()
	target.scale = Vector2(0.5, 0.5)
	target.modulate.a = 0.0
	var t := create_tween().set_parallel(true)
	t.tween_property(target, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(target, "modulate:a", 1.0, 0.15)
	if boss:
		_boss_intro(biome["boss"])


func _tap(local_pos: Vector2) -> void:
	var dmg := GameState.tap_damage()
	var crit := randf() < B.CRIT_CHANCE
	var hit := _monster_center() + Vector2(randf_range(-60, 60), randf_range(-70, 30))
	if crit:
		dmg *= B.CRIT_MULT
		_popup(hit, B.format_num(dmg) + "!", Color(1, 0.6, 0.15), 50)
		_slash(hit, Color(1, 0.7, 0.3), 1.6)
		_burst(hit, Color(1, 0.6, 0.2), 26, 1.3)
		_shake = maxf(_shake, 10.0)
	else:
		_popup(hit, B.format_num(dmg), Color(1, 1, 1), 34)
		_slash(hit, Color(0.75, 0.9, 1.0), 1.0)
		_burst(hit, Color(0.7, 0.85, 1.0), 10, 0.9)
		_shake = maxf(_shake, 3.0)
	_hit_react()
	_damage(dmg)


func _damage(amount: float) -> void:
	_monster_hp -= amount
	if _monster_hp <= 0.0:
		var was_boss := B.is_boss(GameState.wave)
		var cleared_gate := GameState.gate
		var center := _monster_center()
		_death_ghost()
		var reward := GameState.monster_killed()
		_popup(center + Vector2(0, -40), "+" + B.format_num(reward), Color(1, 0.84, 0.3), 42)
		_burst(center, Color(1, 0.8, 0.35), 30, 1.5)
		_fly_coins(_area.global_position + center, 7 if was_boss else 3)
		_shake = maxf(_shake, 18.0 if was_boss else 6.0)
		if was_boss:
			_banner("Врата %d закрыты!" % cleared_gate, Color(1, 0.85, 0.3), 60)
			_gate_transition()
		else:
			_spawn_monster()


func _squad_attack() -> void:
	var delay := 0.0
	for i in _squad.size():
		if GameState.hunters[i] <= 0:
			continue
		var sprite := _squad[i]
		var base := _squad_base[i]
		var t := create_tween()
		t.tween_interval(delay)
		t.tween_property(sprite, "position", base + Vector2(22, -4), 0.09).set_ease(Tween.EASE_OUT)
		t.tween_callback(_hero_strike.bind(i))
		t.tween_property(sprite, "position", base, 0.2).set_ease(Tween.EASE_IN_OUT)
		delay += 0.22


## Рэн рубит монстра, Мира и Сэй выпускают снаряд.
func _hero_strike(index: int) -> void:
	if _paused:
		return
	var color: Color = B.HUNTERS[index]["color"]
	var target := _monster_center() + Vector2(randf_range(-50, 50), randf_range(-60, 20))
	if index == 0:
		_on_hero_hit(index, target)
		return
	var from := _squad[index].position + Vector2(HERO_SIZE.x * 0.85, HERO_SIZE.y * 0.42)
	var orb := _glow_sprite(color.lightened(0.3), 0.55)
	orb.position = from
	_area.add_child(orb)
	var t := create_tween()
	t.tween_property(orb, "position", target, 0.22).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		orb.queue_free()
		_on_hero_hit(index, target))


func _on_hero_hit(index: int, at: Vector2) -> void:
	if _paused:
		return
	var color: Color = B.HUNTERS[index]["color"]
	_slash(at, color.lightened(0.3), 0.8)
	_burst(at, color.lightened(0.2), 8, 0.7)
	var dmg := B.hunter_dps(index, GameState.hunters[index]) * GameState.dmg_mult()
	if dmg >= 1.0:
		_popup(at, B.format_num(dmg), color.lightened(0.45), 24)


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


func _on_buff_pressed() -> void:
	Ads.show_rewarded(func() -> void: GameState.activate_buff())


# ---------- эффекты ----------

func _make_fx_resources() -> void:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.65))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_glow = tex
	_additive = CanvasItemMaterial.new()
	_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func _glow_sprite(color: Color, scale_k: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = _glow
	s.material = _additive
	s.modulate = color
	s.scale = Vector2.ONE * scale_k
	return s


func _monster_node() -> Control:
	return _monster_art if _monster_art.visible else _monster_body


func _monster_center() -> Vector2:
	var m := _monster_node()
	return m.position + m.size * Vector2(0.5, 0.55)


## Световой росчерк удара.
func _slash(pos: Vector2, color: Color, power: float) -> void:
	var s := _glow_sprite(color, 1.0)
	s.position = pos
	s.rotation = randf_range(-0.9, 0.9)
	s.scale = Vector2(0.6, 0.12) * power
	_area.add_child(s)
	var t := create_tween().set_parallel(true)
	t.tween_property(s, "scale", Vector2(3.6, 0.16) * power, 0.16).set_ease(Tween.EASE_OUT)
	t.tween_property(s, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(s.queue_free)


## Вспышка мягких частиц (пул из 8 эмиттеров).
func _burst(pos: Vector2, color: Color, amount: int, power: float) -> void:
	if _particles.is_empty():
		for i in 8:
			var p := CPUParticles2D.new()
			p.texture = _glow
			p.material = _additive
			p.one_shot = true
			p.emitting = false
			p.explosiveness = 1.0
			p.lifetime = 0.55
			p.spread = 180.0
			p.gravity = Vector2(0, 500)
			p.initial_velocity_min = 120.0
			p.damping_min = 80.0
			p.damping_max = 160.0
			p.scale_amount_min = 0.12
			p.scale_amount_max = 0.32
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
	e.initial_velocity_max = 380.0 * power
	e.restart()


func _hit_react() -> void:
	var m := _monster_node()
	var t := create_tween().set_parallel(true)
	m.modulate = Color(1.35, 1.25, 1.25)
	m.position = _monster_base + Vector2(10, 0)
	t.tween_property(m, "modulate", Color(1, 1, 1), 0.12)
	t.tween_property(m, "position", _monster_base, 0.12).set_ease(Tween.EASE_OUT)


func _death_ghost() -> void:
	var m := _monster_node()
	if m != _monster_art or _monster_art.texture == null:
		return
	var ghost := TextureRect.new()
	ghost.texture = _monster_art.texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.position = _monster_art.position
	ghost.size = _monster_art.size
	ghost.pivot_offset = _monster_art.size * Vector2(0.5, 1.0)
	_stage.add_child(ghost)
	ghost.modulate = Color(1.8, 1.8, 1.8, 0.75)
	var t := create_tween().set_parallel(true)
	t.tween_property(ghost, "scale", Vector2(1.15, 0.85), 0.25)
	t.tween_property(ghost, "modulate", Color(1.8, 1.8, 1.8, 0.0), 0.22)
	t.chain().tween_callback(ghost.queue_free)


## Монеты летят от монстра к счётчику золота.
func _fly_coins(from_global: Vector2, count: int) -> void:
	var to := _gold_icon.get_global_rect().get_center() - Vector2(18, 18)
	for i in count:
		var coin := _icon(IC_GOLD, 36)
		coin.pivot_offset = Vector2(18, 18)
		var start := from_global + Vector2(randf_range(-50, 50), randf_range(-50, 20)) - Vector2(18, 18)
		coin.position = start
		add_child(coin)
		var ctrl := start + Vector2(randf_range(-140, 60), -randf_range(120, 240))
		var t := create_tween()
		t.tween_interval(i * 0.06)
		t.tween_method(_coin_step.bind(coin, start, ctrl, to), 0.0, 1.0, 0.6).set_ease(Tween.EASE_IN)
		t.tween_callback(func() -> void:
			coin.queue_free()
			_pulse_gold())


func _coin_step(k: float, coin: Control, start: Vector2, ctrl: Vector2, end: Vector2) -> void:
	var a := start.lerp(ctrl, k)
	var b := ctrl.lerp(end, k)
	coin.position = a.lerp(b, k)
	coin.scale = Vector2.ONE * lerpf(1.0, 0.7, k)


func _pulse_gold() -> void:
	_gold_label.pivot_offset = Vector2(0, _gold_label.size.y / 2.0)
	_gold_icon.pivot_offset = _gold_icon.size / 2.0
	var t := create_tween().set_parallel(true)
	_gold_label.scale = Vector2(1.12, 1.12)
	_gold_icon.scale = Vector2(1.2, 1.2)
	t.tween_property(_gold_label, "scale", Vector2.ONE, 0.15)
	t.tween_property(_gold_icon, "scale", Vector2.ONE, 0.15)


func _popup(pos: Vector2, text: String, color: Color, size: int = 34) -> void:
	if _popups >= MAX_POPUPS:
		return
	_popups += 1
	var l := _label(text, size, color, true)
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(240, size * 1.4)
	l.position = pos + Vector2(randf_range(-20, 20), 0) - l.size / 2.0
	l.pivot_offset = l.size / 2.0
	_area.add_child(l)
	l.scale = Vector2(1.5, 1.5)
	var t := create_tween()
	t.tween_property(l, "scale", Vector2.ONE, 0.1)
	t.set_parallel(true)
	t.tween_property(l, "position:y", l.position.y - 90.0, 0.65).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.35)
	t.chain().tween_callback(func() -> void:
		_popups -= 1
		l.queue_free())


## Крупная надпись по центру сцены.
func _banner(text: String, color: Color, size: int, hold: float = 0.7) -> void:
	var l := _label(text, size, color, true)
	l.add_theme_constant_override("outline_size", 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size = Vector2(_area.size.x, 220)
	l.position = Vector2(0, _area.size.y * 0.35 - 110)
	l.pivot_offset = l.size / 2.0
	_area.add_child(l)
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
	_banner("БОСС\n" + boss_name, Color(1, 0.4, 0.35), 58, 0.9)
	_shake = 12.0
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if _overlay == null:
			_paused = false)


func _start_idle_animations() -> void:
	for i in _squad.size():
		var sprite := _squad[i]
		var t := create_tween().set_loops()
		t.tween_interval(i * 0.25)
		t.tween_property(sprite, "scale", Vector2(1.0, 1.02), 0.9).set_trans(Tween.TRANS_SINE)
		t.tween_property(sprite, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)
	var m := create_tween().set_loops()
	m.tween_property(_monster_art, "rotation", 0.018, 1.4).set_trans(Tween.TRANS_SINE)
	m.tween_property(_monster_art, "rotation", -0.018, 1.4).set_trans(Tween.TRANS_SINE)


## Кнопки сжимаются при нажатии и пружинят обратно; рекламные — мягко пульсируют.
func _animate_button(b: Button) -> void:
	b.resized.connect(func() -> void: b.pivot_offset = b.size / 2.0)
	b.button_down.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2(0.92, 0.92), 0.06))
	b.button_up.connect(func() -> void:
		create_tween().tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))


func _pulse_ad_buttons() -> void:
	var t := create_tween().set_loops()
	t.tween_interval(1.4)
	t.tween_callback(func() -> void:
		if not _buff_button.disabled and _buff_button.scale.is_equal_approx(Vector2.ONE):
			var p := create_tween()
			_buff_button.modulate = Color(1.35, 1.25, 1.5)
			p.tween_property(_buff_button, "scale", Vector2(1.06, 1.06), 0.12)
			p.parallel().tween_property(_buff_button, "modulate", Color(1, 1, 1), 0.4)
			p.tween_property(_buff_button, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK))


## Покупка с откликом: вспышка строки, «+1 ур.», прыжок героя. Нет денег — кнопка трясётся.
func _buy(index: int) -> void:
	var row: Dictionary = _tap_row if index < 0 else _hunter_rows[index]
	var was_level: int = GameState.tap_level if index < 0 else GameState.hunters[index]
	var ok: bool = GameState.try_buy_tap() if index < 0 else GameState.try_buy_hunter(index)
	var buy: Button = row["buy"]
	if not ok:
		var s := create_tween()
		var x := buy.position.x
		for k in 4:
			s.tween_property(buy, "position:x", x + (8.0 if k % 2 == 0 else -8.0), 0.04)
		s.tween_property(buy, "position:x", x, 0.04)
		return
	var panel: Control = row["panel"]
	panel.modulate = Color(1.5, 1.4, 1.1)
	create_tween().tween_property(panel, "modulate", Color(1, 1, 1), 0.35)
	var lvl_label: Label = row["level"]
	lvl_label.pivot_offset = lvl_label.size / 2.0
	lvl_label.scale = Vector2(1.6, 1.6)
	create_tween().tween_property(lvl_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	_pulse_gold()
	if index >= 0:
		var sprite := _squad[index]
		var base := _squad_base[index]
		var color: Color = B.HUNTERS[index]["color"]
		_burst(base + HERO_SIZE * Vector2(0.5, 0.6), color.lightened(0.3), 18 if was_level == 0 else 10, 0.9)
		var j := create_tween()
		if was_level == 0:
			sprite.position = base - Vector2(260, 0)
			j.tween_property(sprite, "position", base, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		else:
			j.tween_property(sprite, "position", base - Vector2(0, 28), 0.12).set_ease(Tween.EASE_OUT)
			j.tween_property(sprite, "position", base, 0.18).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BOUNCE)
		_popup(base + Vector2(HERO_SIZE.x * 0.5, 10), "+1 ур.", color.lightened(0.5), 26)
	else:
		_popup(_monster_center() + Vector2(0, -80), "Удар +1", Color(0.7, 0.9, 1.0), 28)


## Появление экрана: HUD и панель проявляются, отряд вбегает слева.
func _intro() -> void:
	for c: Control in [_hud, _sheet]:
		c.modulate.a = 0.0
		create_tween().tween_property(c, "modulate:a", 1.0, 0.45)
	_heroes_run_in()
	_pulse_ad_buttons()


func _heroes_run_in() -> void:
	for i in _squad.size():
		var sprite := _squad[i]
		var base := _squad_base[i]
		sprite.position = base - Vector2(320, 0)
		var t := create_tween()
		t.tween_interval(0.08 * (2 - i))
		t.tween_property(sprite, "position", base, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## Переход к следующим Вратам: затемнение, новая локация, титул.
func _gate_transition() -> void:
	_paused = true
	var t := create_tween()
	t.tween_interval(0.7)
	t.tween_property(_fade, "color:a", 1.0, 0.3)
	t.tween_callback(func() -> void:
		_spawn_monster()
		_paused = true
		_heroes_run_in())
	t.tween_property(_fade, "color:a", 0.0, 0.35)
	t.tween_callback(func() -> void:
		var biome := B.biome(GameState.gate)
		_banner("%s\nВрата %d" % [biome["name"], GameState.gate], Color(0.85, 0.92, 1.0), 50, 0.8)
		if _overlay == null:
			_paused = false)


# ---------- скриншоты для проверки в CI (запуск с аргументом -- --shots=DIR) ----------

func _run_shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var gs := GameState
	gs.gold = 12345.0
	gs.tap_level = 8
	gs.hunters[0] = 5
	gs.hunters[1] = 3
	gs.hunters[2] = 1
	gs.gate = 3
	gs.wave = 4
	gs.gates_cleared = 2
	gs.farm = false
	_spawn_monster()
	_refresh()
	await get_tree().create_timer(1.2).timeout
	await _shot(dir, "1_battle")
	for i in 4:
		_tap(_monster_center())
		await get_tree().create_timer(0.06).timeout
	await _shot(dir, "2_taps")
	await get_tree().create_timer(1.0).timeout
	gs.start_boss()
	_spawn_monster()
	await get_tree().create_timer(0.35).timeout
	await _shot(dir, "3_boss_intro")
	await get_tree().create_timer(1.6).timeout
	await _shot(dir, "4_boss")
	gs.pending_offline_gold = 5400.0
	_show_offline()
	await get_tree().create_timer(0.4).timeout
	await _shot(dir, "5_offline")
	get_tree().quit()


## Демо-бой для записи видео в CI (Movie Maker: --write-movie ... -- --demo).
func _run_demo() -> void:
	var gs := GameState
	gs.gold = 12345.0
	gs.tap_level = 8
	gs.hunters[0] = 5
	gs.hunters[1] = 3
	gs.hunters[2] = 1
	gs.gate = 3
	gs.wave = 6
	gs.gates_cleared = 2
	_spawn_monster()
	_refresh()
	_heroes_run_in()
	await get_tree().create_timer(1.0).timeout
	for i in 14:
		_tap(_monster_center())
		await get_tree().create_timer(0.16).timeout
	_buy(0)
	await get_tree().create_timer(0.8).timeout
	gs.start_boss()
	_spawn_monster()
	await get_tree().create_timer(1.6).timeout
	for i in 12:
		_tap(_monster_center())
		await get_tree().create_timer(0.14).timeout


func _shot(dir: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(shot_name + ".png"))
	print("Screenshot saved: ", shot_name)


# ---------- обновление интерфейса ----------

func _update_monster_ui() -> void:
	_hp_bar.value = maxf(_monster_hp, 0.0)
	_hp_label.text = "%s / %s" % [B.format_num(maxf(_monster_hp, 0.0)), B.format_num(_monster_max)]
	if B.is_boss(GameState.wave):
		_timer_label.visible = true
		_timer_label.text = "%.1f" % maxf(_boss_time, 0.0)
	else:
		_timer_label.visible = false


func _refresh() -> void:
	var gs := GameState
	_rank_label.text = B.RANKS[gs.rank()]
	_rank_badge.texture = load(B.RANK_BADGES[gs.rank()])
	_gate_label.text = "%s · %d" % [B.biome(gs.gate)["name"], gs.gate]
	for i in _pips.size():
		var pip := _pips[i]
		var done := i < gs.wave - 1 or gs.farm
		var current := i == gs.wave - 1 and not gs.farm
		var is_boss_pip := i == _pips.size() - 1
		var col := Color(1, 1, 1, 0.18)
		if done:
			col = Color(0.98, 0.76, 0.3)
		if current:
			col = Color(1, 0.4, 0.35) if is_boss_pip else Color(1, 1, 1)
		elif is_boss_pip and not done:
			col = Color(0.75, 0.2, 0.22, 0.6)
		(pip.get_theme_stylebox("panel") as StyleBoxFlat).bg_color = col
	_dps_label.text = "Отряд  %s/сек" % B.format_num(gs.total_dps())

	var left := gs.buff_left()
	if left > 0.0:
		_buff_button.text = "x2  %d:%02d" % [int(left) / 60, int(left) % 60]
		_buff_button.icon = IC_X2
		_buff_button.disabled = true
	else:
		_buff_button.text = "x2 урон"
		_buff_button.icon = IC_AD
		_buff_button.disabled = not Ads.is_ready()
	_boss_button.visible = gs.farm

	var tap_cost := B.tap_cost(gs.tap_level)
	_set_row(_tap_row, "Удар", gs.tap_level, "%s за тап" % B.format_num(gs.tap_damage()), tap_cost, gs.gold >= tap_cost, "")
	for i in _hunter_rows.size():
		var lvl: int = gs.hunters[i]
		var cost := B.hunter_cost(i, lvl)
		var stat := "%s урона/сек" % B.format_num(B.hunter_dps(i, lvl)) if lvl > 0 else "Ещё не в отряде"
		_set_row(_hunter_rows[i], B.HUNTERS[i]["name"], lvl, stat, cost, gs.gold >= cost, "Нанять" if lvl == 0 else "")
		_hunter_rows[i]["icon"].modulate = Color(1, 1, 1) if lvl > 0 else Color(0.45, 0.45, 0.5)
		_squad[i].visible = lvl > 0
		_hero_shadows[i].visible = lvl > 0


func _set_row(row: Dictionary, title: String, level: int, stat: String, cost: float, affordable: bool, verb: String) -> void:
	row["name"].text = title
	row["level"].text = "ур. %d" % level if level > 0 else ""
	row["stat"].text = stat
	var buy: Button = row["buy"]
	buy.text = (verb + "  " if verb != "" else "") + B.format_num(cost)
	buy.disabled = not affordable
	if affordable and not row["aff"]:
		buy.pivot_offset = buy.size / 2.0
		var t := create_tween()
		buy.modulate = Color(1.6, 1.5, 1.2)
		t.tween_property(buy, "scale", Vector2(1.08, 1.08), 0.1)
		t.parallel().tween_property(buy, "modulate", Color(1, 1, 1), 0.35)
		t.tween_property(buy, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	row["aff"] = affordable


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
	add_child(_vignette())

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	_hud = _build_hud()
	root.add_child(_hud)

	# Сцена боя: тап по любой её точке бьёт монстра.
	_area = Control.new()
	_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_area)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_area.add_child(_stage)
	_build_stage()

	_sheet = _build_sheet()
	root.add_child(_sheet)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _vignette() -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.7))
	g.set_color(1, Color(0, 0, 0, 0.85))
	g.add_point(0.16, Color(0, 0, 0, 0.05))
	g.add_point(0.5, Color(0, 0, 0, 0.0))
	g.add_point(0.62, Color(0, 0, 0, 0.25))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 4
	tex.height = 256
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_hud() -> Control:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "TopPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var gold_box := HBoxContainer.new()
	gold_box.add_theme_constant_override("separation", 6)
	gold_box.custom_minimum_size = Vector2(200, 0)
	row.add_child(gold_box)
	_gold_icon = _icon(IC_GOLD, 50)
	gold_box.add_child(_gold_icon)
	_gold_label = _label("", 34, Color(1, 0.86, 0.35), true)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold_box.add_child(_gold_label)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	row.add_child(mid)
	_gate_label = _label("", 20, Color(0.88, 0.9, 1.0), true)
	_gate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_gate_label)
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.add_theme_constant_override("separation", 4)
	mid.add_child(pips)
	for i in B.WAVES_PER_GATE + 1:
		var boss_pip := i == B.WAVES_PER_GATE
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(26, 12) if boss_pip else Vector2(16, 10)
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.border_color = Color(0, 0, 0, 0.6)
		sb.set_border_width_all(1)
		pip.add_theme_stylebox_override("panel", sb)
		pips.add_child(pip)
		_pips.append(pip)

	var badge := _make_badge(0, 72)
	_rank_badge = badge
	_rank_label = badge.get_child(0)
	row.add_child(badge)
	return panel


func _build_stage() -> void:
	# Тени (рисуются под фигурами)
	_monster_shadow = _shadow()
	_stage.add_child(_monster_shadow)
	for i in B.HUNTERS.size():
		_hero_shadows.append(_shadow())
	for i in [2, 1, 0]:
		_stage.add_child(_hero_shadows[i])
	# Отряд: задний ряд рисуется первым
	for i in B.HUNTERS.size():
		var sprite := TextureRect.new()
		sprite.texture = load(B.HUNTERS[i]["sprite"])
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.size = HERO_SIZE
		sprite.pivot_offset = Vector2(HERO_SIZE.x / 2.0, HERO_SIZE.y)
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_squad.append(sprite)
		_squad_base.append(Vector2.ZERO)
	for i in [2, 1, 0]:
		_stage.add_child(_squad[i])

	_monster_body = Panel.new()
	_monster_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_style = StyleBoxFlat.new()
	_monster_style.set_corner_radius_all(80)
	_monster_body.add_theme_stylebox_override("panel", _monster_style)
	_stage.add_child(_monster_body)
	_monster_art = TextureRect.new()
	_monster_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_monster_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_monster_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_monster_art)

	# Имя, здоровье и таймер над монстром
	_monster_info = VBoxContainer.new()
	_monster_info.add_theme_constant_override("separation", 4)
	_monster_info.custom_minimum_size = Vector2(320, 0)
	_monster_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_monster_info)
	_timer_label = _label("", 30, Color(1, 0.45, 0.4), true)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_monster_info.add_child(_timer_label)
	_monster_name = _label("", 26, Color(1, 1, 1), true)
	_monster_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_monster_info.add_child(_monster_name)
	var hp_holder := Control.new()
	hp_holder.custom_minimum_size = Vector2(300, 28)
	hp_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hp_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_monster_info.add_child(hp_holder)
	_hp_back = ProgressBar.new()
	_hp_bar = ProgressBar.new()
	for bar: ProgressBar in [_hp_back, _hp_bar]:
		bar.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hp_holder.add_child(bar)
	_hp_back.theme_type_variation = "HpBack"
	_hp_bar.theme_type_variation = "HpFront"
	_hp_label = _label("", 17, Color(1, 1, 1), true)
	_hp_label.add_theme_constant_override("outline_size", 6)
	_hp_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_holder.add_child(_hp_label)


func _shadow() -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(200)
	sb.shadow_color = Color(0, 0, 0, 0.3)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Расставляет фигуры по размеру сцены: общая линия земли внизу.
func _layout_stage() -> void:
	if _area == null or _area.size.x <= 0.0:
		return
	var w := _area.size.x
	var ground := _area.size.y - 18.0
	for i in _squad.size():
		var slot: Vector2 = HERO_SLOTS[i]
		var pos := Vector2(slot.x, ground + slot.y - HERO_SIZE.y)
		_squad_base[i] = pos
		_squad[i].size = HERO_SIZE
		_squad[i].position = pos
		_place_shadow(_hero_shadows[i], pos.x + HERO_SIZE.x * 0.5, ground + slot.y, HERO_SIZE.x * 0.62)
	var boss := B.is_boss(GameState.wave)
	var msize := BOSS_SIZE if boss else MONSTER_SIZE
	var cx := minf(w * 0.7, w - msize.x * 0.5 - 4.0)
	_monster_base = Vector2(cx - msize.x * 0.5, ground - msize.y + 6.0)
	for m: Control in [_monster_art, _monster_body]:
		m.size = msize if m == _monster_art else msize * 0.75
		m.position = _monster_base if m == _monster_art else Vector2(cx - msize.x * 0.375, ground - msize.y * 0.75)
		m.pivot_offset = m.size * Vector2(0.5, 1.0)
	if _monster_body.visible:
		_monster_base = _monster_body.position
	_place_shadow(_monster_shadow, cx, ground + 4.0, msize.x * 0.7)
	_monster_info.reset_size()
	var info_x := clampf(cx - 160.0, 4.0, w - 324.0)
	_monster_info.position = Vector2(info_x, maxf(0.0, _monster_base.y - _monster_info.size.y - 2.0))


func _place_shadow(p: Panel, cx: float, y: float, width: float) -> void:
	p.size = Vector2(width, width * 0.16)
	p.position = Vector2(cx - width * 0.5, y - p.size.y * 0.5)


func _build_sheet() -> Control:
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "SheetPanel"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	sheet.add_child(box)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	box.add_child(actions)
	_dps_label = _label("", 22, Color(0.75, 0.85, 1.0), true)
	_dps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	actions.add_child(_dps_label)
	_boss_button = _button("Босс", 22, func() -> void:
		GameState.start_boss()
		_spawn_monster())
	_boss_button.theme_type_variation = "BossButton"
	_boss_button.custom_minimum_size = Vector2(120, 58)
	actions.add_child(_boss_button)
	_buff_button = _button("", 22, _on_buff_pressed)
	_buff_button.theme_type_variation = "AdButton"
	_buff_button.custom_minimum_size = Vector2(190, 58)
	actions.add_child(_buff_button)

	_tap_row = _upgrade_row(box, IC_STRIKE, func() -> void: _buy(-1))
	for i in B.HUNTERS.size():
		var idx := i
		_hunter_rows.append(_upgrade_row(box, load(B.HUNTERS[i]["icon"]), func() -> void: _buy(idx)))
	return sheet


func _upgrade_row(parent: Container, icon_tex: Texture2D, on_buy: Callable) -> Dictionary:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "RowPanel"
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var icon := _icon(icon_tex, 64)
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	info.add_theme_constant_override("separation", 2)
	row.add_child(info)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	info.add_child(head)
	var title := _label("", 23, Color(1, 1, 1), true)
	head.add_child(title)
	var level := _label("", 19, Color(0.98, 0.78, 0.35), true)
	level.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(level)
	var stat := _label("", 19, Color(0.68, 0.76, 0.9))
	info.add_child(stat)
	var buy := _button("", 24, on_buy)
	buy.theme_type_variation = "BuyButton"
	buy.icon = IC_GOLD
	buy.custom_minimum_size = Vector2(200, 62)
	row.add_child(buy)
	return {"icon": icon, "name": title, "level": level, "stat": stat, "buy": buy, "panel": panel, "aff": false}


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
	b.custom_minimum_size = Vector2(0, 70)
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_press)
	_animate_button(b)
	return b


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
	panel.pivot_offset = Vector2(300, 200)
	panel.scale = Vector2(0.85, 0.85)
	create_tween().tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return box


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
		_show_offline.call_deferred()
