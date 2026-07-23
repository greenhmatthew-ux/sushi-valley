class_name Player
extends CharacterBody2D
## Top-down player controller. Port of src/game/entities/Player.ts from the
## Phaser build, keeping its correctness rules:
##
##   - velocity is set first, then the animation is derived from the resolved facing
##   - diagonals are normalized, so moving diagonally is not faster
##   - the animation changes ONLY when the animation name changes (no per-frame
##     restart, which showed up as flicker)
##   - idle stops on the contact frame of the last facing
##   - the origin is at the feet, and the collision box is the feet, not the whole
##     16x16 frame — so the player tucks behind things correctly and the footprint
##     matches what the art implies
##
## Node origin = bottom-center of the sprite frame (the feet). Everything that
## positions the player — spawn points, tile coords, Y-sort — keys off the feet.

const SPEED := 80.0   ## world px/sec. 16px tiles; camera zoom handles apparent speed.

const MAX_HP := 12              ## 3 hearts of 4 HP each (see hud_layer's heart display)
const INVULN_AFTER_HIT := 0.8   ## brief mercy window so one contact can't drain everything

## Facing is stored as a String to match the card/data vocabulary used by save
## files and the TS build ("down"/"up"/"left"/"right"), not an enum that would
## serialize as a meaningless integer.
var facing: String = "down"
var control_enabled: bool = true

var hp: int = MAX_HP
var _invuln: float = 0.0
var _spawn_pos: Vector2 = Vector2.ZERO   ## where a defeat sends you back to

var _current_anim: String = ""

@onready var _sprite: AnimatedSprite2D = $Sprite
@onready var _interact_probe: Area2D = $InteractProbe


func _ready() -> void:
	add_to_group("player")   # aggro enemies find the player by this group
	_spawn_pos = global_position
	var texture: Texture2D = preload("res://assets/sprites/player_walk.png")
	_sprite.sprite_frames = SpriteSheets.walk_frames(texture, SpriteSheets.row_count(texture))
	_show_idle()
	Bus.player_hp_changed.emit(hp, MAX_HP)


## Take a hit from an aggressive foe. Ignored during the post-hit mercy window; a defeat
## patches you up and returns you to where you entered this level.
func take_damage(amount: int) -> void:
	if _invuln > 0.0 or hp <= 0:
		return
	hp = maxi(0, hp - amount)
	Bus.player_hp_changed.emit(hp, MAX_HP)
	_flash_hurt()
	_invuln = INVULN_AFTER_HIT
	if hp <= 0:
		_die()


func _die() -> void:
	Bus.player_died.emit()
	Bus.toast.emit("You were defeated — patched up back home.")
	hp = MAX_HP
	global_position = _spawn_pos
	_invuln = 1.5
	Bus.player_hp_changed.emit(hp, MAX_HP)


func _flash_hurt() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_sprite, "modulate", Color.WHITE, 0.3)


func _physics_process(delta: float) -> void:
	if _invuln > 0.0:
		_invuln -= delta
	if not control_enabled:
		velocity = Vector2.ZERO
		_show_idle()
		move_and_slide()
		return

	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	if input == Vector2.ZERO:
		velocity = Vector2.ZERO
		_show_idle()
	else:
		# Normalized so diagonals do not grant free speed. get_vector() already
		# normalizes, but an explicit call keeps that guarantee if the deadzone
		# handling in the InputMap changes.
		velocity = input.normalized() * SPEED
		# Resolve facing from the dominant axis — stable while moving diagonally,
		# where naively taking either axis makes the sprite flip back and forth.
		facing = ("left" if input.x < 0.0 else "right") if absf(input.x) > absf(input.y) \
			else ("up" if input.y < 0.0 else "down")
		_play("walk_" + facing)

	move_and_slide()


## Interact is handled as unhandled input so any open UI (dialogue, recall) gets
## first claim on the key. Movement stays a polled read in _physics_process.
func _unhandled_input(event: InputEvent) -> void:
	if control_enabled and event.is_action_pressed("interact"):
		_try_interact()


## Trigger the nearest interactable in reach. Interactables are Area2Ds in the
## "interactable" group that expose an interact(player) method; the probe detects
## them by collision mask (layer 8), and nearest-by-distance breaks ties so
## standing between two objects picks the closer one.
func _try_interact() -> void:
	var nearest: Node = null
	var nearest_dist := INF
	for area in _interact_probe.get_overlapping_areas():
		if not area.is_in_group("interactable") or not area.has_method("interact"):
			continue
		var d := global_position.distance_squared_to(area.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = area
	if nearest != null:
		nearest.interact(self)


## Face a direction without moving — used by dialogue, cutscenes, and spawn points.
func face(direction: String) -> void:
	facing = direction
	_show_idle()


func disable_control() -> void:
	control_enabled = false
	velocity = Vector2.ZERO
	_show_idle()


func enable_control() -> void:
	control_enabled = true


func _play(anim: String) -> void:
	if _current_anim == anim:
		return   # change-only: replaying every frame restarts the cycle and flickers
	_current_anim = anim
	_sprite.play(anim)


func _show_idle() -> void:
	var anim := "idle_" + facing
	if _current_anim == anim:
		return
	_current_anim = anim
	_sprite.play(anim)
