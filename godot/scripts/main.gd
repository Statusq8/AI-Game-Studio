extends Control

@onready var status_label: Label = $Center/Status
@onready var test_button: Button = $Center/TestButton

func _ready() -> void:
    test_button.pressed.connect(_on_test_button_pressed)

func _on_test_button_pressed() -> void:
    status_label.text = "Button works!"
