class_name PlayerCombat
extends Node2D
## The player's melee attack, as a component hung under the Player node. It never edits
## the Player: it reads the Player's public `facing` and `global_position` by walking up
## via get_parent(), and owns its own short-range hitbox.
##
## On the `attack` input it swings in the facing direction: a hitbox Area2D (built in code,
## so player.tscn gains just this one node) is kept positioned in front of the player, and a
## press samples whatever enemy hurtboxes it overlaps and applies CombatLogic damage to each.
## Every swing emits Bus.player_attacked(facing) whether or not it connects.
##
## Detection layers: the hitbox masks layer 9 (value 256), the enemy Hurtbox's layer.

## Fallback for isolated scene/test use. A live Player exposes its learning-and-gear-derived
## `atk`, which wins over this value when a swing resolves.
@export var player_atk: int = 6

## How far in front of the feet the hitbox centers, per facing. Enemy hurtboxes sit ~8px
## above their feet, so lateral swings ride at y = -8 and vertical swings reach a tile away.
const _FACING_OFFSETS := {
	"down": Vector2(0, 6),
	"up": Vector2(0, -20),
	"left": Vector2(-14, -8),
	"right": Vector2(14, -8),
}

var _player: Node = null
var _hitbox: Area2D = null


func _ready() -> void:
	_player = get_parent()
	_build_hitbox()
	_position_hitbox()


## Follow the current facing every physics frame so the hitbox is already in place when a
## press is sampled — no per-swing spawn/settle delay.
func _physics_process(_delta: float) -> void:
	_position_hitbox()


## Attack on unhandled input so any open UI (dialogue, recall) claims the key first, matching
## how Player handles `interact`.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack"):
		_swing()


func _swing() -> void:
	var facing := _facing()
	Bus.player_attacked.emit(facing)
	# One query per press: each enemy exposes a single Hurtbox, so it appears at most once.
	# A guard set still protects against any future multi-hurtbox enemy in a single swing.
	var struck := {}
	for area in _hitbox.get_overlapping_areas():
		var enemy := area.get_parent()
		if enemy == null or struck.has(enemy) or not enemy.has_method("take_damage"):
			continue
		struck[enemy] = true
		var attack_stat := int(_player.atk) if _player != null and "atk" in _player else player_atk
		var dmg := CombatLogic.ability_damage(
			CombatLogic.BASIC_ATTACK_POWER, attack_stat, enemy.enemy_def)
		enemy.take_damage(dmg)


func _position_hitbox() -> void:
	_hitbox.position = _FACING_OFFSETS.get(_facing(), _FACING_OFFSETS["down"])


func _facing() -> String:
	# Read the Player's public facing; default down if the parent isn't a Player.
	if _player != null and "facing" in _player:
		return _player.facing
	return "down"


## Build the hitbox in code: a 16x16 sensor that only watches enemy hurtboxes (layer 9).
func _build_hitbox() -> void:
	_hitbox = Area2D.new()
	_hitbox.name = "AttackHitbox"
	_hitbox.collision_layer = 0
	_hitbox.collision_mask = 256   # layer 9: enemy Hurtbox
	_hitbox.monitorable = false
	_hitbox.monitoring = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 16)
	shape.shape = rect
	_hitbox.add_child(shape)
	add_child(_hitbox)
