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

## Facing is stored as a String to match the card/data vocabulary used by save
## files and the TS build ("down"/"up"/"left"/"right"), not an enum that would
## serialize as a meaningless integer.
var facing: String = "down"
var control_enabled: bool = true

var _current_anim: String = ""

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	var texture: Texture2D = preload("res://assets/sprites/player_walk.png")
	_sprite.sprite_frames = SpriteSheets.walk_frames(texture, SpriteSheets.row_count(texture))
	_show_idle()


func _physics_process(_delta: float) -> void:
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
