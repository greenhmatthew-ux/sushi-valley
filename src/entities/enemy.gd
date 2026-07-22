class_name Enemy
extends CharacterBody2D
## A minimal combat target for the first-pass combat loop. It carries HP and the DEF
## stat the player's swing needs, takes damage through CombatLogic (the ported TS math),
## dies at 0 HP, and reports both per-hit and death through the Bus so HUD and
## persistence can react later without holding a reference to this node.
##
## Node origin = the feet (bottom-center), matching the player, so Y-sort and spawns key
## off the same point. The body collides on layer 1 (solid, like the world). Hits land on
## the Hurtbox Area2D (layer 9), whose solid footprint — not the full art bounds — is what
## the player's attack must overlap.
##
## Placeholder art: a flat ColorRect stands in until a fitting enemy sprite is licensed and
## imported from the asset library. Swap the ColorRect for an AnimatedSprite2D later.

## Authored per-instance in the editor. Stats mirror the EnemyDef fields the TS build feeds
## into the combat math (see CombatTypes.ts / CombatSystem.ts). No scaling is applied here
## yet — these are the effective values used directly by CombatLogic.
@export var enemy_id: String = "slime"
@export var max_hp: int = 30
@export var enemy_def: int = 4   ## DEF: halved and subtracted in CombatLogic.ability_damage.
@export var enemy_atk: int = 6   ## ATK: reserved for when the enemy strikes back.

var hp: int

@onready var _flash: ColorRect = $Sprite


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")


## Take an already-resolved amount of damage (the player computes it via CombatLogic so it
## can factor in this enemy's DEF and the attacker's ATK). Clamps HP at 0, emits the per-hit
## and death signals, flashes, and frees itself on death. Ignores hits once already dead so a
## multi-overlap swing can't double-report a kill.
func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = CombatLogic.apply_damage(hp, amount)
	Bus.enemy_damaged.emit(enemy_id, amount, hp)
	_flash_hit()
	if CombatLogic.is_dead(hp):
		Bus.enemy_died.emit(enemy_id)
		queue_free()


## Brief white flash so a hit reads without art. Cheap placeholder feedback.
func _flash_hit() -> void:
	if _flash == null:
		return
	_flash.color = Color(1, 1, 1)
	var tween := create_tween()
	tween.tween_property(_flash, "color", Color(0.78, 0.22, 0.27), 0.18)
