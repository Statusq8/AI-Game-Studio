extends RefCounted
## Единый стиль интерфейса «Охотника за Вратами» (решение №23 A, заход 1).
## Шрифты: Rubik и Russo One — SIL Open Font License (см. assets/fonts/OFL-*.txt).

const GOLD := Color(0.95, 0.76, 0.32)
const PANEL_BG := Color(0.05, 0.06, 0.11, 0.9)

const BUTTONS := {
	"Button": Color(0.24, 0.38, 0.80),
	"BuyButton": Color(0.92, 0.62, 0.16),
	"AdButton": Color(0.56, 0.28, 0.88),
	"BossButton": Color(0.80, 0.20, 0.25),
}


static func build() -> Theme:
	var t := Theme.new()
	var body := FontVariation.new()
	body.base_font = load("res://assets/fonts/Rubik-Variable.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	var title: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	t.default_font = body
	t.default_font_size = 24

	# Заголовки и числа
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title)

	# Кнопки
	for type: String in BUTTONS:
		if type != "Button":
			t.set_type_variation(type, "Button")
		_button_styles(t, type, BUTTONS[type])
	t.set_constant("icon_max_width", "BuyButton", 34)

	# Панели
	t.set_type_variation("DialogPanel", "PanelContainer")
	t.set_stylebox("panel", "DialogPanel", _panel(PANEL_BG, GOLD, 3, 24, 28))
	t.set_type_variation("RowPanel", "PanelContainer")
	t.set_stylebox("panel", "RowPanel", _panel(Color(0.03, 0.04, 0.08, 0.72), Color(1, 1, 1, 0.14), 2, 16, 10))
	t.set_type_variation("SheetPanel", "PanelContainer")
	var sheet := _panel(Color(0.02, 0.03, 0.07, 0.82), Color(GOLD, 0.55), 2, 26, 14)
	t.set_stylebox("panel", "SheetPanel", sheet)
	t.set_type_variation("TopPanel", "PanelContainer")
	t.set_stylebox("panel", "TopPanel", _panel(Color(0.02, 0.03, 0.07, 0.7), Color(1, 1, 1, 0.1), 2, 20, 10))

	# Полоса здоровья: передний слой (красный) и задний «догоняющий» (светлый)
	var hp_bg := _panel(Color(0.05, 0.03, 0.04, 0.9), Color(0, 0, 0, 0.9), 3, 10, 0)
	t.set_type_variation("HpBack", "ProgressBar")
	t.set_stylebox("background", "HpBack", hp_bg)
	t.set_stylebox("fill", "HpBack", _flat(Color(1.0, 0.93, 0.7), 10))
	t.set_type_variation("HpFront", "ProgressBar")
	t.set_stylebox("background", "HpFront", StyleBoxEmpty.new())
	t.set_stylebox("fill", "HpFront", _flat(Color(0.86, 0.16, 0.22), 10))
	return t


static func _button_styles(t: Theme, type: String, base: Color) -> void:
	var title: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	t.set_font("font", type, title)
	t.set_stylebox("normal", type, _button_box(base, 6, 0))
	t.set_stylebox("hover", type, _button_box(base.lightened(0.1), 6, 0))
	t.set_stylebox("pressed", type, _button_box(base.darkened(0.12), 2, 4))
	t.set_stylebox("disabled", type, _button_box(base.lerp(Color(0.22, 0.24, 0.3), 0.7), 6, 0))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, Color(1, 1, 1))
	t.set_color("font_hover_color", type, Color(1, 1, 1))
	t.set_color("font_pressed_color", type, Color(0.92, 0.92, 0.92))
	t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.45))
	t.set_color("font_outline_color", type, Color(0, 0, 0, 0.6))
	t.set_constant("outline_size", type, 5)
	t.set_constant("h_separation", type, 10)
	t.set_constant("icon_max_width", type, 48)


## Объёмная кнопка: толстая нижняя кромка, при нажатии «проваливается».
static func _button_box(color: Color, bottom: int, push: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(18)
	sb.set_border_width_all(2)
	sb.border_width_bottom = bottom
	sb.border_color = color.darkened(0.5)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6 + push
	sb.content_margin_bottom = 8 + (bottom - 2) - push
	return sb


static func _panel(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	return sb


static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb
