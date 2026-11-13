extends Node
## Обёртка над плагином YandexAds (реклама с вознаграждением). Автозагрузка «Ads».
## Без плагина (редактор, ПК) работает имитация: награда выдаётся сразу.

signal ready_changed(is_ready: bool)

const AD_UNIT_ID := "demo-rewarded-yandex"
const RETRY_SECONDS := 30.0

var _plugin: Object = null
var _fake := false
var _loaded := false
var _loading := false
var _on_reward: Callable = Callable()


func _ready() -> void:
	if Engine.has_singleton("YandexAds"):
		_plugin = Engine.get_singleton("YandexAds")
		_plugin.connect("initialized", _on_initialized)
		_plugin.connect("rewarded_loaded", _on_loaded)
		_plugin.connect("rewarded_failed_to_load", _on_failed_to_load)
		_plugin.connect("rewarded_failed_to_show", _on_failed_to_show)
		_plugin.connect("rewarded_dismissed", _on_dismissed)
		_plugin.connect("rewarded_earned", _on_earned)
		_plugin.call("initialize", OS.is_debug_build())
	else:
		_fake = true
		_set_loaded(true)


func is_ready() -> bool:
	return _loaded


## Показать рекламу; on_reward вызывается, только если игрок досмотрел.
func show_rewarded(on_reward: Callable) -> bool:
	if not _loaded:
		return false
	_on_reward = on_reward
	_set_loaded(false)
	if _fake:
		_on_earned("fake", 1)
		_set_loaded(true)
		return true
	_plugin.call("showRewarded")
	return true


func _load() -> void:
	if _fake or _loaded or _loading:
		return
	_loading = true
	_plugin.call("loadRewarded", AD_UNIT_ID)


func _set_loaded(value: bool) -> void:
	_loaded = value
	ready_changed.emit(value)


func _on_initialized() -> void:
	_load()


func _on_loaded() -> void:
	_loading = false
	_set_loaded(true)


func _on_failed_to_load(error: String) -> void:
	_loading = false
	push_warning("Rewarded load failed: " + error)
	get_tree().create_timer(RETRY_SECONDS).timeout.connect(_load)


func _on_failed_to_show(error: String) -> void:
	push_warning("Rewarded show failed: " + error)
	_on_reward = Callable()
	_load()


func _on_earned(_type: String, _amount: int) -> void:
	if _on_reward.is_valid():
		_on_reward.call()
	_on_reward = Callable()


func _on_dismissed() -> void:
	_on_reward = Callable()
	_load()
