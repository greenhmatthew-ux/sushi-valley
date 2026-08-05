extends Node
## Owns the single active turn-based world encounter.
##
## Requesters receive an opaque token and may only react to the result carrying
## that token. Dispatch is deferred so a requester can begin awaiting before a
## combat panel resolves an invalid or immediately cancelled encounter.
##
## Bus.combat_started / combat_ended remain lifecycle notifications for existing
## HUD, audio, and learning listeners. New combat owners use the tokenized
## combat_requested / combat_resolved signals instead.

const BusType = preload("res://src/autoload/bus.gd")

var _next_token: int = 1
var _active_token: String = ""
var _active_enemy_id: String = ""
var _active_owner: WeakRef = null
@onready var _bus: BusType = get_node("/root/Bus")


## Reserve the only active encounter slot. An empty return means another fight
## already owns it, or the requested enemy id was invalid.
func request(enemy_id: String, owner: Node = null) -> String:
	var clean_enemy_id := enemy_id.strip_edges()
	if clean_enemy_id.is_empty() or is_busy():
		return ""

	var token := "encounter-%d" % _next_token
	_next_token += 1
	_active_token = token
	_active_enemy_id = clean_enemy_id
	_active_owner = weakref(owner) if owner != null else null
	call_deferred("_dispatch", token, clean_enemy_id)
	return token


## Wait for this request's result without consuming a different encounter's
## outcome. Call this immediately after request(); dispatch is deliberately
## deferred to make that ordering safe.
func wait_for_result(token: String) -> bool:
	if token.is_empty():
		return false
	while token == _active_token:
		var result: Array = await _bus.combat_resolved
		if result.size() >= 2 and String(result[0]) == token:
			return bool(result[1])
	return false


## Resolve only the active owner. A stale or guessed token cannot end the fight.
func resolve(token: String, victory: bool) -> bool:
	if token.is_empty() or token != _active_token:
		return false

	_clear_active()
	_bus.combat_resolved.emit(token, victory)
	_bus.combat_ended.emit(victory)
	return true


func is_busy() -> bool:
	return not _active_token.is_empty()


func active_token() -> String:
	return _active_token


## Lifecycle notification comes before the UI request so existing listeners
## hide the world HUD and record the sighting before the combat panel appears.
func _dispatch(token: String, enemy_id: String) -> void:
	if token != _active_token or enemy_id != _active_enemy_id:
		return
	if _active_owner != null and _active_owner.get_ref() == null:
		_clear_active()
		return

	_bus.combat_started.emit(enemy_id)
	# A lifecycle listener must not normally resolve encounters, but retain this
	# guard so an unexpected listener cannot dispatch a stale UI request.
	if token == _active_token:
		_bus.combat_requested.emit(token, enemy_id)


func _clear_active() -> void:
	_active_token = ""
	_active_enemy_id = ""
	_active_owner = null
