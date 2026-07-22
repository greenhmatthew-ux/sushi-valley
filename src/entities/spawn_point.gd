extends Marker2D
## A named arrival point. When a level loads, it matches Transitions' pending spawn
## id to one of these and drops the player here. Add to any scene the player can be
## sent to; give the entry point a stable `spawn_id` that doors elsewhere target.

@export var spawn_id: String = ""


func _ready() -> void:
	add_to_group("spawn_point")
