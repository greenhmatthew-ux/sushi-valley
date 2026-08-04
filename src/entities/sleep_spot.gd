extends Area2D
## Invisible interaction footprint over the authored bed. The bed keeps its real
## prop art/collision; this node only opens the explicit day-advance preview.

@export var sleep_spot := true


func _ready() -> void:
	add_to_group("interactable")


func interact(_player: Node = null) -> void:
	Bus.sleep_requested.emit()


func interaction_label() -> String:
	return "Rest until %s" % Farm.next_clock_text()
