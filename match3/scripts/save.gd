extends Node
## Прогресс игрока: уровень и монеты. Автозагрузка «Save».

signal changed

const PATH := "user://match3_save.json"
const MAX_HEARTS := 5
const HEART_SECONDS := 30 * 60

var level := 1
var coins := 0
var sound := true
var hearts := MAX_HEARTS
var heart_at := 0.0
## Бустеры: на уровне (молот, ряд, столбец, перемешать) и до уровня (ракета, бомба, шар).
var boosters := {"hammer": 2, "arrow": 2, "cannon": 2, "shuffle": 2, "pre_rocket": 2, "pre_bomb": 2, "pre_orb": 1}  # unix-время, когда придёт следующее сердце (0 — сердца полные)


func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		level = maxi(1, int(data.get("level", 1)))
		coins = maxi(0, int(data.get("coins", 0)))
		sound = bool(data.get("sound", true))
		hearts = clampi(int(data.get("hearts", MAX_HEARTS)), 0, MAX_HEARTS)
		heart_at = float(data.get("heart_at", 0.0))
		var b: Variant = data.get("boosters", {})
		if b is Dictionary:
			for k in boosters:
				boosters[k] = int(b.get(k, boosters[k]))
	update_hearts()


func store() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"level": level, "coins": coins, "sound": sound, "hearts": hearts, "heart_at": heart_at, "boosters": boosters}))
	changed.emit()


func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)
	store()


func spend(n: int) -> bool:
	if coins < n:
		return false
	coins -= n
	store()
	return true


static func now() -> float:
	return Time.get_unix_time_from_system()


## Начисляет сердца, которые восстановились за время отсутствия.
func update_hearts() -> void:
	if hearts >= MAX_HEARTS:
		heart_at = 0.0
		return
	if heart_at <= 0.0:
		heart_at = now() + HEART_SECONDS
	while hearts < MAX_HEARTS and now() >= heart_at:
		hearts += 1
		heart_at += HEART_SECONDS
	if hearts >= MAX_HEARTS:
		heart_at = 0.0


func seconds_to_heart() -> int:
	update_hearts()
	return 0 if hearts >= MAX_HEARTS else int(ceil(heart_at - now()))


func lose_heart() -> void:
	update_hearts()
	if hearts >= MAX_HEARTS:
		heart_at = now() + HEART_SECONDS
	hearts = maxi(0, hearts - 1)
	store()


func add_heart() -> void:
	hearts = mini(MAX_HEARTS, hearts + 1)
	update_hearts()
	store()


func use_booster(kind: String) -> bool:
	if int(boosters.get(kind, 0)) <= 0:
		return false
	boosters[kind] -= 1
	store()
	return true


func add_booster(kind: String, n: int = 1) -> void:
	boosters[kind] = int(boosters.get(kind, 0)) + n
	store()
