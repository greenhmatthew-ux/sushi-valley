class_name Enemy
extends CharacterBody2D
const WorldBehavior = preload("res://src/systems/world_behavior_def.gd")
## A minimal combat target for the first-pass combat loop. It carries HP and the DEF
## stat the player's swing needs, takes damage through CombatLogic (the ported TS math),
## dies at 0 HP, and reports both per-hit and death through the Bus so HUD and
## persistence can react later without holding a reference to this node.
##
## Node origin = the feet (bottom-center), matching the player, so Y-sort and spawns key
## off the same point. The body uses enemy layer 4 and masks terrain layer 1, so it cannot
## body-block the player on layer 2. Hits land on
## the Hurtbox Area2D (layer 9), whose solid footprint — not the full art bounds — is what
## the player's attack must overlap.
##
## Art: an AnimatedSprite2D driven by the shared SpriteSheets helper (the same 4x4 layout as
## the player). It bounces in place via walk_down; swap `sprite_sheet` for a different foe.

## Authored per-instance in the editor. Stats mirror the EnemyDef fields the TS build feeds
## into the combat math (see CombatTypes.ts / CombatSystem.ts). No scaling is applied here
## yet — these are the effective values used directly by CombatLogic.
enum WorldState { IDLE, ROAM, ALERT, CHASE, ENGAGE, RETURN, FLEE }
enum AggroLevel { PASSIVE, PROVOKED, WARY, TERRITORIAL, HUNTER }

const DISPOSITION_LEVEL: Dictionary = {
	WorldBehavior.PASSIVE: AggroLevel.PASSIVE,
	WorldBehavior.PROVOKED: AggroLevel.PROVOKED,
	WorldBehavior.WARY: AggroLevel.WARY,
	WorldBehavior.TERRITORIAL: AggroLevel.TERRITORIAL,
	WorldBehavior.HUNTER: AggroLevel.HUNTER,
}
const ROAM_DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT,
	Vector2(0.70710678, 0.70710678),
	Vector2.DOWN,
	Vector2(-0.70710678, 0.70710678),
	Vector2.LEFT,
	Vector2(-0.70710678, -0.70710678),
	Vector2.UP,
	Vector2(0.70710678, -0.70710678),
]

## Readable definition-owned behavior values. Assigning enemy_id applies the matching
## WorldBehaviorDef immediately, including while a PackedScene is only being inspected.
## This keeps scene placements free of duplicated tuning while still exposing the values to
## debugging tools and deterministic tests.
var aggro_level: AggroLevel = AggroLevel.PASSIVE
var world_state: WorldState = WorldState.IDLE
var idle_duration: float = 1.25
var warning_seconds: float = 0.0
var memory_seconds: float = 0.0
var detect_radius: float = 0.0
var leash_radius: float = 48.0
var roam_radius: float = 32.0
var roam_speed: float = 18.0
var chase_speed: float = 48.0
var burst_speed: float = 0.0
var burst_duration: float = 0.0
var burst_recovery: float = 2.0
var post_flee_grace: float = 3.0
var uses_fallback_behavior: bool = false

@export var enemy_id: String = "slime":
	set(value):
		var requested := value.strip_edges().to_lower()
		enemy_id = String(WorldBehavior.profile(requested).get("id", requested))
		_apply_world_behavior(enemy_id)
@export var max_hp: int = 30
@export var enemy_def: int = 4   ## DEF: halved and subtracted in CombatLogic.ability_damage.
@export var enemy_atk: int = 6   ## ATK: reserved for when the enemy strikes back.
## Character walk sheet (4 dirs x N frames, 16x16). Swap per-instance for a different foe —
## enemy_mushroom.png, enemy_boar.png, … — they all share the project sheet layout.
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/enemy_slime.png")

## Safe-hub sparring is an interaction rule, not an aggro disposition. The Slime remains
## PASSIVE (never initiates), and this flag makes the authored practice actors selectable.
@export var sparring_partner: bool = false
@export var attack_cooldown: float = 1.0

## Loot on a hostile kill (PASSIVE/AGGRO). Coins drop into the shared purse; the actual
## award is `coin_reward` jittered by ±`coin_variance` so a kill feels like loot, not a
## fixed payout. Sparring foes never drop coins — a bout yields the spar-won message instead.
@export var coin_reward: int = 0
@export var coin_variance: int = 0

const ATTACK_RANGE := 15.0

var hp: int
var _engaged: bool = false   ## a safe-hub sparring bout is underway
var _attack_timer: float = 0.0
var _cur_anim: String = ""
var _in_combat: bool = false   ## guards against re-entering a fight already in progress
var _home_position: Vector2 = Vector2.ZERO
var _roam_target: Vector2 = Vector2.ZERO
var _last_seen_position: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
var _memory_remaining: float = 0.0
var _grace_remaining: float = 0.0
var _burst_remaining: float = 0.0
var _burst_recovery_remaining: float = 0.0
var _stuck_seconds: float = 0.0
var _roam_step: int = 0

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	_apply_world_behavior(enemy_id)
	reset_world_state(global_position)
	_sprite.sprite_frames = SpriteSheets.walk_frames(sprite_sheet, SpriteSheets.row_count(sprite_sheet))
	_set_anim("idle_down")


## Decisions are advanced through a pure position/visibility seam, then applied through
## CharacterBody2D movement. That makes warning and leash behavior deterministic while the
## live actor still collides with terrain. Actors do not collide with one another.
func _physics_process(delta: float) -> void:
	if hp <= 0 or _in_combat:
		velocity = Vector2.ZERO
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		if world_state not in [WorldState.IDLE, WorldState.RETURN]:
			_begin_return()
		advance_world_state(delta, _home_position, false)
		_apply_world_motion(delta)
		return

	advance_world_state(delta, player.global_position, _has_line_of_sight(player))
	if world_state == WorldState.ENGAGE and _attack_timer <= 0.0:
		_engage()
		_attack_timer = attack_cooldown
	_apply_world_motion(delta)


## Reset is used at spawn and is also the deterministic test seam. Home never follows the
## player: RETURN always targets this captured point.
func reset_world_state(home: Vector2) -> void:
	_home_position = home
	_roam_target = home
	_last_seen_position = home
	world_state = WorldState.IDLE
	_state_timer = maxf(0.0, idle_duration)
	_memory_remaining = 0.0
	_grace_remaining = 0.0
	_burst_remaining = 0.0
	_burst_recovery_remaining = 0.0
	_stuck_seconds = 0.0
	_roam_step = absi(enemy_id.hash()) % ROAM_DIRECTIONS.size()
	velocity = Vector2.ZERO


## Selects a readable state and desired velocity without querying physics or launching UI.
## Runtime supplies its real line-of-sight result; tests can supply the same fact directly.
func advance_world_state(delta: float, player_position: Vector2,
		has_line_of_sight: bool) -> void:
	var step := maxf(0.0, delta)
	_grace_remaining = maxf(0.0, _grace_remaining - step)
	_burst_recovery_remaining = maxf(0.0, _burst_recovery_remaining - step)
	var distance_home := global_position.distance_to(_home_position)
	var distance_player := global_position.distance_to(player_position)

	match world_state:
		WorldState.IDLE:
			velocity = Vector2.ZERO
			if _can_notice(distance_player, has_line_of_sight):
				_begin_alert(player_position)
				return
			_state_timer = maxf(0.0, _state_timer - step)
			if _state_timer <= 0.0 and roam_radius > 0.0:
				_begin_roam()
		WorldState.ROAM:
			if _can_notice(distance_player, has_line_of_sight):
				_begin_alert(player_position)
				return
			if global_position.distance_to(_roam_target) <= 3.0:
				_begin_idle()
			else:
				velocity = global_position.direction_to(_roam_target) * roam_speed
		WorldState.ALERT:
			velocity = Vector2.ZERO
			if distance_home > leash_radius or not has_line_of_sight \
					or distance_player > detect_radius:
				_begin_return()
				return
			_last_seen_position = player_position
			# Wary creatures yield ground during the warning. They only commit if the
			# player deliberately stays close; otherwise the warning ends in RETURN.
			if aggro_level == AggroLevel.WARY:
				velocity = player_position.direction_to(global_position) * roam_speed
			_state_timer = maxf(0.0, _state_timer - step)
			if _state_timer <= 0.0:
				var wary_commit_radius := maxf(ATTACK_RANGE * 2.0, detect_radius * 0.6)
				if aggro_level == AggroLevel.WARY and distance_player > wary_commit_radius:
					_begin_return()
				else:
					_begin_chase(player_position)
		WorldState.CHASE:
			if distance_home > leash_radius:
				_begin_return()
				return
			if has_line_of_sight:
				_last_seen_position = player_position
				_memory_remaining = memory_seconds
			else:
				_memory_remaining = maxf(0.0, _memory_remaining - step)
				if _memory_remaining <= 0.0:
					_begin_return()
					return
			if distance_player <= ATTACK_RANGE and has_line_of_sight:
				world_state = WorldState.ENGAGE
				velocity = Vector2.ZERO
				return
			_set_chase_velocity(step)
		WorldState.ENGAGE:
			velocity = Vector2.ZERO
		WorldState.RETURN:
			if distance_home <= 2.0:
				global_position = _home_position
				_begin_idle()
			else:
				velocity = global_position.direction_to(_home_position) * roam_speed
		WorldState.FLEE:
			if distance_home >= leash_radius or _state_timer <= 0.0:
				_begin_return()
			else:
				_state_timer = maxf(0.0, _state_timer - step)
				velocity = player_position.direction_to(global_position) * chase_speed


## Explicit provocation is the only way a PROVOKED enemy starts pursuit. PASSIVE enemies
## ignore it; the three proactive dispositions may also use it for quest/script triggers.
func provoke(source: Node2D = null) -> void:
	if aggro_level == AggroLevel.PASSIVE or _grace_remaining > 0.0:
		return
	var target := source
	if target == null and is_inside_tree():
		target = get_tree().get_first_node_in_group("player") as Node2D
	if target == null:
		return
	if warning_seconds > 0.0:
		_begin_alert(target.global_position)
	else:
		_begin_chase(target.global_position)


## Applies the same post-flee grace used by a resolved encounter without exposing token
## internals. This keeps the escape rule directly testable and reusable by scripted fights.
func retreat_after_encounter() -> void:
	_attack_timer = maxf(attack_cooldown, 1.5)
	_begin_return(post_flee_grace)


func world_state_name() -> String:
	return String(WorldState.keys()[world_state])


func _can_notice(distance_player: float, has_line_of_sight: bool) -> bool:
	return _grace_remaining <= 0.0 \
		and aggro_level in [AggroLevel.WARY, AggroLevel.TERRITORIAL, AggroLevel.HUNTER] \
		and has_line_of_sight and distance_player <= detect_radius


func _begin_idle() -> void:
	world_state = WorldState.IDLE
	_state_timer = maxf(0.0, idle_duration)
	velocity = Vector2.ZERO


func _begin_roam() -> void:
	world_state = WorldState.ROAM
	var direction := ROAM_DIRECTIONS[_roam_step % ROAM_DIRECTIONS.size()]
	_roam_step += 3
	_roam_target = _home_position + direction * roam_radius
	velocity = global_position.direction_to(_roam_target) * roam_speed


func _begin_alert(player_position: Vector2) -> void:
	world_state = WorldState.ALERT
	_last_seen_position = player_position
	_state_timer = maxf(0.0, warning_seconds)
	velocity = Vector2.ZERO
	if is_inside_tree():
		var display_name := enemy_id.replace("_", " ").capitalize()
		Bus.toast.emit("%s notices you!" % display_name)


func _begin_chase(player_position: Vector2) -> void:
	world_state = WorldState.CHASE
	_last_seen_position = player_position
	_memory_remaining = maxf(0.0, memory_seconds)
	if aggro_level == AggroLevel.HUNTER and burst_duration > 0.0 \
			and _burst_recovery_remaining <= 0.0:
		_burst_remaining = burst_duration


func _begin_return(grace: float = 0.0) -> void:
	world_state = WorldState.RETURN
	_grace_remaining = maxf(_grace_remaining, grace)
	_burst_remaining = 0.0
	velocity = global_position.direction_to(_home_position) * roam_speed


func _set_chase_velocity(delta: float) -> void:
	var speed := chase_speed
	if aggro_level == AggroLevel.HUNTER and burst_duration > 0.0:
		if _burst_remaining <= 0.0 and _burst_recovery_remaining <= 0.0:
			_burst_remaining = burst_duration
		if _burst_remaining > 0.0:
			speed = burst_speed
			_burst_remaining = maxf(0.0, _burst_remaining - delta)
			if _burst_remaining <= 0.0:
				_burst_recovery_remaining = maxf(2.0, burst_recovery)
	var target := _last_seen_position
	velocity = global_position.direction_to(target) * speed


func _apply_world_motion(delta: float) -> void:
	if velocity == Vector2.ZERO:
		_set_anim("idle_down")
		move_and_slide()
		return
	var before := global_position
	_set_anim("walk_" + _dir_name(velocity))
	move_and_slide()
	var expected := velocity.length() * delta
	var moved := global_position.distance_to(before)
	_stuck_seconds = (_stuck_seconds + delta) if moved < expected * 0.2 \
		else maxf(0.0, _stuck_seconds - delta * 2.0)
	if _stuck_seconds < 0.65:
		return
	_stuck_seconds = 0.0
	if world_state == WorldState.CHASE:
		_begin_return()
	elif world_state == WorldState.ROAM:
		_begin_idle()
	elif world_state == WorldState.RETURN:
		# A terrain snag must not strand the enemy in a corridor forever.
		global_position = _home_position
		_begin_idle()


func _has_line_of_sight(player: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = player.global_position
	query.collision_mask = 1   # authored terrain only; actor bodies are deliberately ignored
	query.exclude = [get_rid()]
	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()


func _apply_world_behavior(id: String) -> void:
	var profile := WorldBehavior.profile(id)
	uses_fallback_behavior = bool(profile.get("is_fallback", false))
	aggro_level = int(DISPOSITION_LEVEL.get(
		String(profile.get("disposition", WorldBehavior.PASSIVE)), AggroLevel.PASSIVE))
	detect_radius = float(profile.get("detect_radius", 0.0))
	roam_radius = float(profile.get("roam_radius", 32.0))
	leash_radius = float(profile.get("leash_radius", 48.0))
	roam_speed = float(profile.get("roam_speed", 18.0))
	chase_speed = float(profile.get("chase_speed", 48.0))
	burst_speed = float(profile.get("burst_speed", 0.0))
	burst_duration = float(profile.get("burst_seconds", 0.0))
	warning_seconds = float(profile.get("warning_seconds", 0.0))
	memory_seconds = float(profile.get("memory_seconds", 0.0))
	burst_recovery = float(profile.get("recovery_seconds", 2.0))
	post_flee_grace = float(profile.get("post_flee_grace_seconds", 3.0))


## Catching the player starts a turn-based recall fight rather than chipping HP in real
## time — combat is where the Japanese gets used, so it needs a UI turn to happen in.
## EncounterDirector reserves ownership synchronously, then dispatches the UI request
## deferred so this coroutine is already waiting before any immediate rejection resolves.
func _engage() -> void:
	if _in_combat:
		return
	var token := EncounterDirector.request(enemy_id, self)
	if token.is_empty():
		# Another enemy owns the active encounter. Back off instead of joining its result.
		_attack_timer = maxf(attack_cooldown, 1.5)
		_begin_return(1.5)
		return
	_in_combat = true
	var victory: bool = await EncounterDirector.wait_for_result(token)
	_in_combat = false
	if victory:
		_drop_loot()
		queue_free()
	else:
		# Survived or fled: return home with the definition-owned grace window so the
		# player can actually escape instead of being caught by the next physics frame.
		retreat_after_encounter()


func _dir_name(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "left" if v.x < 0.0 else "right"
	return "up" if v.y < 0.0 else "down"


func _set_anim(anim: String) -> void:
	if _cur_anim == anim:
		return
	_cur_anim = anim
	_sprite.play(anim)


## Take an already-resolved amount of damage (the player computes it via CombatLogic so it
## can factor in this enemy's DEF and the attacker's ATK). Clamps HP at 0, emits the per-hit
## and death signals, flashes, and frees itself on death. Ignores hits once already dead so a
## multi-overlap swing can't double-report a kill.
func take_damage(amount: int) -> void:
	if hp <= 0:
		return
	# A sparring partner is never damaged by contact. Its bout is the recall fight that
	# begin_spar() opens, the same one every hostile encounter uses.
	#
	# It used to take physical hits once engaged and die to them, which made sparring the one
	# route in the game where you won a fight by walking into something -- no card, no recall,
	# no Japanese. That is the opposite of what combat is for here.
	if sparring_partner:
		return
	# Hostile overworld HP is never a learning bypass. A swing is an explicit trigger for
	# PASSIVE/PROVOKED foes and opens the same recall encounter used by contact aggro; only
	# the safe-hub sparring partners retain the lightweight physical practice loop.
	if not sparring_partner:
		provoke()
		world_state = WorldState.ENGAGE
		_engage()
		return
	hp = CombatLogic.apply_damage(hp, amount)
	Bus.enemy_damaged.emit(enemy_id, amount, hp)
	_flash_hit()
	if CombatLogic.is_dead(hp):
		Bus.enemy_died.emit(enemy_id)
		_drop_loot()
		queue_free()


## Reward a hostile kill: coins plus this enemy's authored item drops. Sparring bouts route
## to the spar-won message instead.
##
## The item half reads the drop table straight from data/game/enemies.json. Before this,
## enemies paid coins and ignored their tables entirely, which quietly made every
## item-collection quest in quests.json impossible to finish.
func _drop_loot() -> void:
	var parts: Array[String] = []

	if coin_reward > 0:
		var amt := maxi(1, coin_reward + randi_range(-coin_variance, coin_variance))
		Inv.add_coins(amt)
		parts.append("%d coins" % amt)

	var table: Array = DB.enemy(enemy_id).get("drops", [])
	var drops := LootLogic.roll(table)
	for id in drops:
		Inv.add(id, 1)
	var items := LootLogic.describe(drops, func(id): return DB.item(id).get("name", id))
	if not items.is_empty():
		parts.append(items)

	if not parts.is_empty():
		var name := String(DB.enemy(enemy_id).get("name", enemy_id))
		Bus.toast.emit("%s dropped %s." % [name, " and ".join(parts)])


## Begin a practice bout — called through the player's interact probe (see SparZone) when
## they walk up to an authored sparring partner and press interact.
func begin_spar(_player: Node = null) -> void:
	if not sparring_partner or _engaged or _in_combat:
		return
	var token := EncounterDirector.request(enemy_id, self)
	if token.is_empty():
		# Another encounter owns the panel; do not queue a second bout behind it.
		return
	_engaged = true
	_in_combat = true
	Bus.toast.emit("You square up to spar with the %s." % enemy_id)
	var victory: bool = await EncounterDirector.wait_for_result(token)
	_in_combat = false
	_engaged = false
	# A sparring partner is practice: it is never destroyed and never drops loot, so the
	# village still has one tomorrow. Reset its HP either way.
	hp = max_hp
	if victory:
		Bus.toast.emit("You won the spar with the %s!" % enemy_id)


## Brief bright flash on hit so the strike reads.
func _flash_hit() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)
