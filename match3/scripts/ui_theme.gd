extends RefCounted
## Стиль интерфейса «Три в ряд»: светлая яркая палитра, объёмные кнопки.
## Шрифты Rubik и Russo One — SIL Open Font License (assets/fonts/OFL-*.txt).

const INK := Color("#2b2350")
const CREAM := Color("#fff6e3")

const BUTTONS := {
	"Button": Color("#3f8cff"),
	"GreenButton": Color("#3fc25a"),
	"OrangeButton": Color("#ff9a2a"),
	"PurpleButton": Color("#9b5cff"),
	"RedButton": Color("#ff5468"),
}


static func build() -> Theme:
	var t := Theme.new()
	var body := FontVariation.new()
	body.base_font = load("res://assets/fonts/Rubik-Variable.ttf")
	body.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
	t.default_font = body
	t.default_font_size = 26
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Color(0.1, 0.08, 0.25, 0.85))
	t.set_constant("outline_size", "Label", 6)

	var title: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title)
	t.set_type_variation("InkLabel", "Label")
	t.set_color("font_color", "InkLabel", INK)
	t.set_constant("outline_size", "InkLabel", 0)

	for type: String in BUTTONS:
		if type != "Button":
			t.set_type_variation(type, "Button")
		_button_styles(t, type, BUTTONS[type], title)

	# кнопки — ИИ-картинка (зелёная) и её перекраски; растягиваются по 9 частям, концы-полукруги не искажаются
	for pair in [["GreenButton", "green", Color("#1e5a14")], ["Button", "blue", Color("#14305a")], ["OrangeButton", "orange", Color("#6a3208")],
			["RedButton", "red", Color("#5a0a12")], ["PurpleButton", "purple", Color("#3a1460")]]:
		var tex: Texture2D = load("res://assets/art/ui_btn_%s.png" % pair[1])
		for st in [["normal", Color.WHITE, 0], ["hover", Color(1.08, 1.08, 1.08), 0], ["pressed", Color(0.85, 0.85, 0.85), 3], ["disabled", Color(0.6, 0.6, 0.6, 0.7), 0]]:
			var sbt := StyleBoxTexture.new()
			sbt.texture = tex
			sbt.texture_margin_left = 50
			sbt.texture_margin_right = 50
			sbt.texture_margin_top = 30
			sbt.texture_margin_bottom = 36
			sbt.modulate_color = st[1]
			sbt.content_margin_left = 34
			sbt.content_margin_right = 34
			sbt.content_margin_top = 8 + st[2]
			sbt.content_margin_bottom = 16 - st[2]
			t.set_stylebox(st[0], pair[0], sbt)
		t.set_color("font_outline_color", pair[0], pair[2])
		t.set_constant("outline_size", pair[0], 10)

	t.set_type_variation("DialogPanel", "PanelContainer")
	t.set_stylebox("panel", "DialogPanel", _panel(CREAM, Color("#f0b34a"), 6, 34, 30))
	t.set_type_variation("HudPanel", "PanelContainer")
	t.set_stylebox("panel", "HudPanel", _panel(Color("#5b3fd1"), Color("#ffffff", 0.7), 4, 26, 12))
	t.set_type_variation("PillPanel", "PanelContainer")
	var pill := _panel(Color(0.12, 0.1, 0.32, 0.55), Color(1, 1, 1, 0.5), 3, 30, 8)
	pill.content_margin_left = 14
	pill.content_margin_right = 18
	t.set_stylebox("panel", "PillPanel", pill)
	t.set_type_variation("GoalSlot", "PanelContainer")
	t.set_stylebox("panel", "GoalSlot", StyleBoxEmpty.new())
	t.set_type_variation("BoardPanel", "PanelContainer")
	# рамка поля: дерево (лианы рисует main.gd поверх)
	# фон рамки прозрачный: в дырах фигурного поля виден фон уровня
	var wood := _panel(Color("#8a5326", 0.0), Color("#ffcf5a", 0.0), 0, 28, 38)
	wood.shadow_size = 0
	wood.shadow_size = 18
	wood.shadow_color = Color(0, 0, 0, 0.35)
	t.set_stylebox("panel", "BoardPanel", wood)
	return t


static func _button_styles(t: Theme, type: String, base: Color, font: Font) -> void:
	t.set_font("font", type, font)
	t.set_font_size("font_size", type, 32)
	t.set_stylebox("normal", type, _button_box(base, 8, 0))
	t.set_stylebox("hover", type, _button_box(base.lightened(0.08), 8, 0))
	t.set_stylebox("pressed", type, _button_box(base.darkened(0.1), 3, 5))
	t.set_stylebox("disabled", type, _button_box(base.lerp(Color(0.6, 0.6, 0.65), 0.7), 8, 0))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		t.set_color(k, type, Color.WHITE)
	t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.6))
	t.set_color("font_outline_color", type, base.darkened(0.55))
	t.set_constant("outline_size", type, 7)


static func _button_box(color: Color, bottom: int, push: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(26)
	sb.set_border_width_all(3)
	sb.border_width_bottom = bottom
	sb.border_color = color.darkened(0.42)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 4)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12 + push
	sb.content_margin_bottom = 14 + (bottom - 3) - push
	return sb


static func _panel(bg: Color, border: Color, border_w: int, radius: int, margin: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.25)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 5)
	return sb
