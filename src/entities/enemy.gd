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

## How this foe engages the player:
##   PASSIVE  — a stationary target; always fightable, dies when beaten.
##   SPARRING — a friendly practice partner for the safe starting area: it never aggros
##              and cannot be hit until the player CHOOSES to engage it (walk up + interact);
##              on defeat it yields (a small reward) rather than being "killed" hostilely.
##   AGGRO    — (expanded areas) chases and attacks on sight. Chase AI + player HP land with
##              the world expansion; the mode is defined here so foes can be authored now.
enum Behavior { PASSIVE, SPARRING, AGGRO }
@export var behavior: Behavior = Behavior.PASSIVE

## AGGRO tuning (PASSIVE/SPARRING ignore these): how close before it notices the player,
## how fast it chases, and the seconds between its contact hits.
@export var detect_radius: float = 96.0
@export var move_speed: float = 42.0
@export var attack_cooldown: float = 1.0

## Loot on a hostile kill (PASSIVE/AGGRO). Coins drop into the shared purse; the actual
## award is `coin_reward` jittered by ±`coin_variance` so a kill feels like loot, not a
## fixed payout. Sparring foes never drop coins — a bout yields the spar-won message instead.
@export var coin_reward: int = 0
@export var coin_variance: int = 0

const ATTACK_RANGE := 15.0

var hp: int
var _engaged: bool = false   ## a sparring bout is underway (PASSIVE/AGGRO are always "on")
var _attack_timer: float = 0.0
var _cur_anim: String = ""
var _in_combat: bool = false   ## guards against re-entering a fight already in progress

@onready var _sprite: AnimatedSprite2D = $Sprite


func _ready() -> void:
	hp = max_hp
	add_to_group("enemy")
	_sprite.sprite_frames = SpriteSheets.walk_frames(sprite_sheet, SpriteSheets.row_count(sprite_sheet))
	_set_anim("walk_down")   # idle bounce; AGGRO overrides this while chasing


## AGGRO chase + contact-attack. PASSIVE and SPARRING foes return early and never move, so
## only hostile enemies pursue the player and strike them on contact.
func _physics_process(delta: float) -> void:
	if behavior != Behavior.AGGRO or hp <= 0:
		return
	_attack_timer = maxf(0.0, _attack_timer - delta)
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var to_player: Vector2 = player.global_position - global_position
	var dist := to_player.length()
	if dist > detect_radius:
		velocity = Vector2.ZERO
		_set_anim("idle_down")
	elif dist > ATTACK_RANGE:
		velocity = to_player.normalized() * move_speed
		_set_anim("walk_" + _dir_name(to_player))
	else:
		velocity = Vector2.ZERO
		if _attack_timer <= 0.0:
			_engage()
			_attack_timer = attack_cooldown
	move_and_slide()


## Catching the player starts a turn-based recall fight rather than chipping HP in real
## time — combat is where the Japanese gets used, so it needs a UI turn to happen in.
## Deferred because this runs inside a physics callback.
func _engage() -> void:
	if _in_combat:
		return
	_in_combat = true
	Bus.combat_started.emit.call_deferred(enemy_id)
	var victory: bool = await Bus.combat_ended
	_in_combat = false
	if victory:
		_drop_loot()
		queue_free()
	else:
		# Survived or fled: back off so the player isn't instantly re-engaged.
		_attack_timer = maxf(attack_cooldown, 1.5)


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
	# A sparring partner shrugs off hits until the player has chosen to engage it.
	if behavior == Behavior.SPARRING and not _engaged:
		return
	hp = CombatLogic.apply_damage(hp, amount)
	Bus.enemy_damaged.emit(enemy_id, amount, hp)
	_flash_hit()
	if CombatLogic.is_dead(hp):
		Bus.enemy_died.emit(enemy_id)
		if behavior == Behavior.SPARRING:
			Bus.toast.emit("You won the spar with the %s!" % enemy_id)
		else:
			_drop_loot()
		queue_free()


## Reward a hostile kill: coins into the shared purse plus a toast so the drop reads. Called
## only on PASSIVE/AGGRO deaths — sparring bouts route to the spar-won message instead.
func _drop_loot() -> void:
	if coin_reward <= 0:
		return
	var amt := maxi(1, coin_reward + randi_range(-coin_variance, coin_variance))
	Inv.add_coins(amt)
	Bus.toast.emit("The %s dropped %d coins." % [enemy_id, amt])


## Begin a practice bout — called through the player's interact probe (see SparZone) when
## they walk up to a sparring foe and press interact. Non-aggro: nothing happens otherwise.
func begin_spar(_player: Node = null) -> void:
	if behavior != Behavior.SPARRING or _engaged:
		return
	_engaged = true
	Bus.toast.emit("You square up to spar with the %s." % enemy_id)


## Brief bright flash on hit so the strike reads.
func _flash_hit() -> void:
	if _sprite == null:
		return
	_sprite.modulate = Color(2.5, 2.5, 2.5)
	var tween := create_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, 0.18)
