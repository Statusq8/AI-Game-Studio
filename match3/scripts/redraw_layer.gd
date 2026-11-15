extends Node2D
## Слой, который перерисовывается каждый кадр (сияние под особыми фишками).


func _process(_delta: float) -> void:
	queue_redraw()
