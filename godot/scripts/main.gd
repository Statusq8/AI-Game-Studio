extends Control

## Тест рекламы с вознаграждением (решение №18 C).
## Демо-блок Яндекса всегда отдаёт тестовую рекламу, деньги не начисляются.
const REWARDED_AD_UNIT_ID := "demo-rewarded-yandex"
const REWARD_COINS := 100

@onready var status_label: Label = $Center/Status
@onready var test_button: Button = $Center/TestButton
@onready var ad_button: Button = $Center/AdButton
@onready var coins_label: Label = $Center/Coins

var _ads: Object = null
var _coins := 0


func _ready() -> void:
	test_button.pressed.connect(_on_test_button_pressed)
	ad_button.pressed.connect(_on_ad_button_pressed)
	if Engine.has_singleton("YandexAds"):
		_ads = Engine.get_singleton("YandexAds")
		_ads.initialized.connect(_on_ads_initialized)
		_ads.rewarded_loaded.connect(_on_rewarded_loaded)
		_ads.rewarded_failed_to_load.connect(_on_rewarded_failed_to_load)
		_ads.rewarded_failed_to_show.connect(_on_rewarded_failed_to_show)
		_ads.rewarded_dismissed.connect(_on_rewarded_dismissed)
		_ads.rewarded_earned.connect(_on_rewarded_earned)
		status_label.text = "Ads: initializing..."
		_ads.initialize(true)
	else:
		status_label.text = "Ads plugin not found"


func _on_test_button_pressed() -> void:
	status_label.text = "Button works!"


func _on_ads_initialized() -> void:
	status_label.text = "Ads: loading..."
	_ads.loadRewarded(REWARDED_AD_UNIT_ID)


func _on_rewarded_loaded() -> void:
	status_label.text = "Ads: ready"
	ad_button.disabled = false


func _on_rewarded_failed_to_load(error: String) -> void:
	status_label.text = "Ad load error: " + error
	ad_button.disabled = true


func _on_ad_button_pressed() -> void:
	ad_button.disabled = true
	_ads.showRewarded()


func _on_rewarded_failed_to_show(error: String) -> void:
	status_label.text = "Ad show error: " + error
	_ads.loadRewarded(REWARDED_AD_UNIT_ID)


func _on_rewarded_earned(_type: String, _amount: int) -> void:
	_coins += REWARD_COINS
	coins_label.text = "Coins: %d" % _coins


func _on_rewarded_dismissed() -> void:
	status_label.text = "Ads: loading next..."
	_ads.loadRewarded(REWARDED_AD_UNIT_ID)
