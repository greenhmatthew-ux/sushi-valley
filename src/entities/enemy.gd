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
## Art: an AnimatedSprite2D driven by the shared SpriteSheets helper (the same 4x4 layout as
## the player). It bounces in place via walk_down; swap `sprite_sheet` for a different foe.

## Authored per-instance in the editor. Stats mirror the EnemyDef fields the TS build feeds
## into the combat math (see CombatTypes.ts / CombatSystem.ts). No scaling is applied here
## yet — these are the effective values used directly by CombatLogic.
@export var enemy_id: String = "slime"
@export var max_hp: int = 30
@export var enemy_def: int = 4   ## DEF: halved and subtracted in CombatLogic.ability_damage.
@export var enemy_atk: int = 6   ## ATK: reserved for when the enemy strikes back.
## Character walk sheet (4 dirs x N frames, 16x16). Swap per-instance for a different foe —
## enemy_mushroom.png, enemy_boar.png, … — they all share the project sheet layout.
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/enemy_slime.png")

var hp: int

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	_sprite.sprite_frames = SpriteSheets.walk_frames(sprite_sheet, SpriteSheets.row_count(sprite_sheet))
	_sprite.play("walk_down")   # bounce in place; the first-pass enemy is a stationary target


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


## Brief bright flash on hit so the strike reads.
func _flash_hit() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)
