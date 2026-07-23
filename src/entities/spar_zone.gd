extends Area2D
## Makes a SPARRING enemy engageable through the player's interact probe (same contract as
## gates/NPCs: group "interactable", layer 8, an interact(player) method). It only joins the
## group for sparring foes, and forwards interact() to the parent enemy's begin_spar(), so
## passive/aggro enemies are never "talked to".

func _ready() -> void:
	var enemy := get_parent()
	if enemy is Enemy and enemy.behavior == Enemy.Behavior.SPARRING:
		add_to_group("interactable")
	else:
		monitorable = false   # not a sparring foe: stay invisible to the interact probe


func interact(player: Node = null) -> void:
	var enemy := get_parent()
	if enemy != null and enemy.has_method("begin_spar"):
		enemy.begin_spar(player)
