extends Node
## Состояние игрока, сохранение и офлайн-доход. Автозагрузка «GameState».

signal changed
signal rank_up(rank: int)
signal offline_ready(gold: float)

const B := preload("res://scripts/game/balance.gd")
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1

var gold := 0.0
var tap_level := 0
var hunters: Array[int] = [0, 0, 0]
var gate := 1
var wave := 1
var gates_cleared := 0
var farm := false
var dmg_buff_until := 0.0
var last_seen := 0.0
var pending_offline_gold := 0.0


func _ready() -> void:
	load_game()
	var timer := Timer.new()
	timer.wait_time = 10.0
	timer.autostart = true
	timer.timeout.connect(save_game)
	add_child(timer)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_WM_GO_BACK_REQUEST:
			save_game()
		NOTIFICATION_APPLICATION_RESUMED:
			_check_offline()


static func now() -> float:
	return Time.get_unix_time_from_system()


func rank() -> int:
	return B.rank_for(gates_cleared)


func buff_left() -> float:
	return maxf(0.0, dmg_buff_until - now())


func dmg_mult() -> float:
	var m := float(B.RANK_MULT[rank()])
	if buff_left() > 0.0:
		m *= 2.0
	return m


func tap_damage() -> float:
	return B.tap_damage(tap_level) * dmg_mult()


func raw_dps() -> float:
	var total := 0.0
	for i in hunters.size():
		total += B.hunter_dps(i, hunters[i])
	return total


func total_dps() -> float:
	return raw_dps() * dmg_mult()


## Золото в секунду от отряда на текущих Вратах (без временного бонуса).
func gold_per_second() -> float:
	var dps := raw_dps() * float(B.RANK_MULT[rank()])
	var mid := 5
	return dps / B.monster_hp(gate, mid) * B.gold_reward(gate, mid)


func try_buy_tap() -> bool:
	var cost := B.tap_cost(tap_level)
	if gold < cost:
		return false
	gold -= cost
	tap_level += 1
	changed.emit()
	return true


func try_buy_hunter(index: int) -> bool:
	var cost := B.hunter_cost(index, hunters[index])
	if gold < cost:
		return false
	gold -= cost
	hunters[index] += 1
	changed.emit()
	return true


func add_gold(amount: float) -> void:
	gold += amount
	changed.emit()


## Вызывается при убийстве текущего монстра. Возвращает награду.
func monster_killed() -> float:
	var reward := B.gold_reward(gate, wave)
	gold += reward
	if B.is_boss(wave):
		var old_rank := rank()
		gates_cleared = maxi(gates_cleared, gate)
		gate += 1
		wave = 1
		farm = false
		save_game()
		if rank() > old_rank:
			rank_up.emit(rank())
	elif not farm:
		wave += 1
	changed.emit()
	return reward


func start_boss() -> void:
	farm = false
	wave = B.WAVES_PER_GATE + 1
	changed.emit()


func boss_failed() -> void:
	farm = true
	wave = B.WAVES_PER_GATE
	changed.emit()


func activate_buff() -> void:
	dmg_buff_until = maxf(now(), dmg_buff_until) + B.BUFF_SECONDS
	changed.emit()


func claim_offline(multiplier: float) -> void:
	if pending_offline_gold <= 0.0:
		return
	gold += pending_offline_gold * multiplier
	pending_offline_gold = 0.0
	save_game()
	changed.emit()


func _check_offline() -> void:
	if last_seen <= 0.0:
		return
	var away: float = clampf(now() - last_seen, 0.0, B.OFFLINE_CAP_SECONDS)
	last_seen = now()
	if away < B.OFFLINE_MIN_SECONDS:
		return
	var earned := gold_per_second() * away
	if earned >= 1.0:
		pending_offline_gold += floorf(earned)
		offline_ready.emit(pending_offline_gold)


func save_game() -> void:
	last_seen = now()
	var data := {
		"version": SAVE_VERSION,
		"gold": gold,
		"tap_level": tap_level,
		"hunters": hunters,
		"gate": gate,
		"wave": wave,
		"gates_cleared": gates_cleared,
		"farm": farm,
		"dmg_buff_until": dmg_buff_until,
		"last_seen": last_seen,
		"pending_offline_gold": pending_offline_gold,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Save failed: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		last_seen = now()
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Save is corrupted, starting fresh")
		last_seen = now()
		return
	var d: Dictionary = parsed
	gold = float(d.get("gold", 0.0))
	tap_level = int(d.get("tap_level", 0))
	var h: Array = d.get("hunters", [0, 0, 0])
	for i in hunters.size():
		hunters[i] = int(h[i]) if i < h.size() else 0
	gate = maxi(1, int(d.get("gate", 1)))
	wave = clampi(int(d.get("wave", 1)), 1, B.WAVES_PER_GATE + 1)
	gates_cleared = int(d.get("gates_cleared", 0))
	farm = bool(d.get("farm", false))
	dmg_buff_until = float(d.get("dmg_buff_until", 0.0))
	last_seen = float(d.get("last_seen", now()))
	pending_offline_gold = float(d.get("pending_offline_gold", 0.0))
	_check_offline()
