extends Node
## Прогресс игрока: уровень и монеты. Автозагрузка «Save».

signal changed

const PATH := "user://match3_save.json"

var level := 1
var coins := 0
var sound := true


func _ready() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if data is Dictionary:
		level = maxi(1, int(data.get("level", 1)))
		coins = maxi(0, int(data.get("coins", 0)))
		sound = bool(data.get("sound", true))


func store() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"level": level, "coins": coins, "sound": sound}))
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
