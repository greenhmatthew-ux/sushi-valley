class_name WorldBehaviorDef
extends RefCounted
## Pure definitions and validation for enemy overworld movement and aggro.
##
## This model deliberately has no scene, save, or autoload dependencies. Enemy actors can
## consume a validated definition later without owning duplicated speed/timing constants.
## Burst speed is explicitly time-limited; all sustained roam and chase speeds avoid the
## player's 80 px/s movement band.

const PASSIVE := "passive"
const PROVOKED := "provoked"
const WARY := "wary"
const TERRITORIAL := "territorial"
const HUNTER := "hunter"

const DISPOSITION_ORDER: Array[String] = [
	PASSIVE,
	PROVOKED,
	WARY,
	TERRITORIAL,
	HUNTER,
]

enum State {
	IDLE,
	ROAM,
	ALERT,
	CHASE,
	ENGAGE,
	RETURN,
	FLEE,
}

const STATE_IDLE := State.IDLE
const STATE_ROAM := State.ROAM
const STATE_ALERT := State.ALERT
const STATE_CHASE := State.CHASE
const STATE_ENGAGE := State.ENGAGE
const STATE_RETURN := State.RETURN
const STATE_FLEE := State.FLEE
const STATE_NAMES: Array[String] = [
	"idle",
	"roam",
	"alert",
	"chase",
	"engage",
	"return",
	"flee",
]

const MIN_ROAM_SPEED := 18.0
const MAX_ROAM_SPEED := 36.0
const MIN_CHASE_SPEED := 48.0
const MAX_CHASE_SPEED := 68.0
const SUSTAINED_SPEED_BAN_MIN := 76.0
const SUSTAINED_SPEED_BAN_MAX := 84.0
const MAX_BURST_SPEED := 96.0
const MAX_BURST_SECONDS := 0.6
const MIN_BURST_RECOVERY_SECONDS := 2.0

const REQUIRED_FIELDS: Array[String] = [
	"id",
	"disposition",
	"detect_radius",
	"roam_radius",
	"leash_radius",
	"roam_speed",
	"chase_speed",
	"burst_speed",
	"burst_seconds",
	"warning_seconds",
	"memory_seconds",
	"recovery_seconds",
	"post_flee_grace_seconds",
]

const NUMERIC_FIELDS: Array[String] = [
	"detect_radius",
	"roam_radius",
	"leash_radius",
	"roam_speed",
	"chase_speed",
	"burst_speed",
	"burst_seconds",
	"warning_seconds",
	"memory_seconds",
	"recovery_seconds",
	"post_flee_grace_seconds",
]

## Semantic rules are separate from numeric tuning so a disposition keeps one meaning.
const DISPOSITION_RULES: Dictionary = {
	PASSIVE: {
		"initiates_combat": false,
		"engages_when_provoked": false,
		"warns_before_chase": false,
		"retreats_during_warning": false,
		"uses_burst": false,
	},
	PROVOKED: {
		"initiates_combat": false,
		"engages_when_provoked": true,
		"warns_before_chase": false,
		"retreats_during_warning": false,
		"uses_burst": false,
	},
	WARY: {
		"initiates_combat": true,
		"engages_when_provoked": true,
		"warns_before_chase": true,
		"retreats_during_warning": true,
		"uses_burst": false,
	},
	TERRITORIAL: {
		"initiates_combat": true,
		"engages_when_provoked": true,
		"warns_before_chase": true,
		"retreats_during_warning": false,
		"uses_burst": false,
	},
	HUNTER: {
		"initiates_combat": true,
		"engages_when_provoked": true,
		"warns_before_chase": true,
		"retreats_during_warning": false,
		"uses_burst": true,
	},
}

## Valid reference tuning for each disposition. Specific enemies may override these values,
## but must still pass validate().
const DISPOSITION_DEFAULTS: Dictionary = {
	PASSIVE: {
		"id": "default_passive",
		"disposition": PASSIVE,
		"detect_radius": 0.0,
		"roam_radius": 32.0,
		"leash_radius": 48.0,
		"roam_speed": 18.0,
		"chase_speed": 0.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.0,
		"memory_seconds": 0.0,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 3.0,
	},
	PROVOKED: {
		"id": "default_provoked",
		"disposition": PROVOKED,
		"detect_radius": 0.0,
		"roam_radius": 40.0,
		"leash_radius": 72.0,
		"roam_speed": 22.0,
		"chase_speed": 52.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.0,
		"memory_seconds": 1.5,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 3.0,
	},
	WARY: {
		"id": "default_wary",
		"disposition": WARY,
		"detect_radius": 56.0,
		"roam_radius": 40.0,
		"leash_radius": 80.0,
		"roam_speed": 22.0,
		"chase_speed": 50.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 1.0,
		"memory_seconds": 1.5,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 3.0,
	},
	TERRITORIAL: {
		"id": "default_territorial",
		"disposition": TERRITORIAL,
		"detect_radius": 72.0,
		"roam_radius": 56.0,
		"leash_radius": 112.0,
		"roam_speed": 28.0,
		"chase_speed": 60.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.7,
		"memory_seconds": 2.5,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 2.0,
	},
	HUNTER: {
		"id": "default_hunter",
		"disposition": HUNTER,
		"detect_radius": 104.0,
		"roam_radius": 64.0,
		"leash_radius": 160.0,
		"roam_speed": 34.0,
		"chase_speed": 68.0,
		"burst_speed": 96.0,
		"burst_seconds": 0.6,
		"warning_seconds": 0.35,
		"memory_seconds": 4.0,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 1.5,
	},
}

## The 14 inspected live enemies each own explicit tuning. The values deliberately keep
## roads escapable: hunters alone receive short bursts, while slower territorial enemies
## rely on readable warnings and authored leashes.
const ENEMY_PRESETS: Dictionary = {
	"slime": {
		"id": "slime",
		"disposition": PASSIVE,
		"detect_radius": 0.0,
		"roam_radius": 24.0,
		"leash_radius": 40.0,
		"roam_speed": 18.0,
		"chase_speed": 0.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.0,
		"memory_seconds": 0.0,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 3.5,
	},
	"mushroom": {
		"id": "mushroom",
		"disposition": WARY,
		"detect_radius": 56.0,
		"roam_radius": 36.0,
		"leash_radius": 80.0,
		"roam_speed": 22.0,
		"chase_speed": 50.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 1.0,
		"memory_seconds": 1.5,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 3.0,
	},
	"kappa": {
		"id": "kappa",
		"disposition": TERRITORIAL,
		"detect_radius": 64.0,
		"roam_radius": 48.0,
		"leash_radius": 104.0,
		"roam_speed": 28.0,
		"chase_speed": 56.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.8,
		"memory_seconds": 2.5,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 2.5,
	},
	"lantern": {
		"id": "lantern",
		"disposition": HUNTER,
		"detect_radius": 104.0,
		"roam_radius": 56.0,
		"leash_radius": 152.0,
		"roam_speed": 32.0,
		"chase_speed": 66.0,
		"burst_speed": 92.0,
		"burst_seconds": 0.5,
		"warning_seconds": 0.4,
		"memory_seconds": 3.5,
		"recovery_seconds": 2.4,
		"post_flee_grace_seconds": 1.8,
	},
	"racoon": {
		"id": "racoon",
		"disposition": PROVOKED,
		"detect_radius": 0.0,
		"roam_radius": 48.0,
		"leash_radius": 96.0,
		"roam_speed": 26.0,
		"chase_speed": 58.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.0,
		"memory_seconds": 2.0,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 3.0,
	},
	"snake": {
		"id": "snake",
		"disposition": WARY,
		"detect_radius": 64.0,
		"roam_radius": 40.0,
		"leash_radius": 96.0,
		"roam_speed": 24.0,
		"chase_speed": 54.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.8,
		"memory_seconds": 2.0,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 2.5,
	},
	"owl": {
		"id": "owl",
		"disposition": WARY,
		"detect_radius": 80.0,
		"roam_radius": 56.0,
		"leash_radius": 120.0,
		"roam_speed": 30.0,
		"chase_speed": 62.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.65,
		"memory_seconds": 2.5,
		"recovery_seconds": 2.3,
		"post_flee_grace_seconds": 2.0,
	},
	"lizard": {
		"id": "lizard",
		"disposition": TERRITORIAL,
		"detect_radius": 68.0,
		"roam_radius": 48.0,
		"leash_radius": 112.0,
		"roam_speed": 24.0,
		"chase_speed": 56.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.8,
		"memory_seconds": 2.5,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 2.0,
	},
	"bat": {
		"id": "bat",
		"disposition": HUNTER,
		"detect_radius": 112.0,
		"roam_radius": 64.0,
		"leash_radius": 160.0,
		"roam_speed": 34.0,
		"chase_speed": 68.0,
		"burst_speed": 96.0,
		"burst_seconds": 0.6,
		"warning_seconds": 0.35,
		"memory_seconds": 4.0,
		"recovery_seconds": 2.0,
		"post_flee_grace_seconds": 1.5,
	},
	"mole": {
		"id": "mole",
		"disposition": TERRITORIAL,
		"detect_radius": 48.0,
		"roam_radius": 40.0,
		"leash_radius": 96.0,
		"roam_speed": 20.0,
		"chase_speed": 54.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.9,
		"memory_seconds": 2.0,
		"recovery_seconds": 2.6,
		"post_flee_grace_seconds": 2.4,
	},
	"bear": {
		"id": "bear",
		"disposition": TERRITORIAL,
		"detect_radius": 72.0,
		"roam_radius": 56.0,
		"leash_radius": 128.0,
		"roam_speed": 22.0,
		"chase_speed": 58.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 1.0,
		"memory_seconds": 3.0,
		"recovery_seconds": 3.0,
		"post_flee_grace_seconds": 2.5,
	},
	"tengu": {
		"id": "tengu",
		"disposition": HUNTER,
		"detect_radius": 120.0,
		"roam_radius": 72.0,
		"leash_radius": 176.0,
		"roam_speed": 36.0,
		"chase_speed": 68.0,
		"burst_speed": 96.0,
		"burst_seconds": 0.5,
		"warning_seconds": 0.3,
		"memory_seconds": 4.5,
		"recovery_seconds": 2.2,
		"post_flee_grace_seconds": 1.5,
	},
	"thornback": {
		"id": "thornback",
		"disposition": TERRITORIAL,
		"detect_radius": 80.0,
		"roam_radius": 64.0,
		"leash_radius": 144.0,
		"roam_speed": 20.0,
		"chase_speed": 60.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 1.1,
		"memory_seconds": 3.5,
		"recovery_seconds": 3.2,
		"post_flee_grace_seconds": 2.5,
	},
	"forest_wraith": {
		"id": "forest_wraith",
		"disposition": HUNTER,
		"detect_radius": 128.0,
		"roam_radius": 72.0,
		"leash_radius": 192.0,
		"roam_speed": 30.0,
		"chase_speed": 64.0,
		"burst_speed": 90.0,
		"burst_seconds": 0.6,
		"warning_seconds": 0.4,
		"memory_seconds": 5.0,
		"recovery_seconds": 2.5,
		"post_flee_grace_seconds": 1.8,
	},
	# The Summit Cache Expedition's pair. A guard that owns one place and a boss that
	# owns the whole top of the mountain — the contrast is the point, so they are not
	# two settings of the same aggressive profile.
	"cliff_drake": {
		"id": "cliff_drake",
		"disposition": TERRITORIAL,
		"detect_radius": 96.0,
		# It is guarding a narrows, so it holds ground rather than patrolling. It was
		# authored with a lunge first; the schema rejects that, because a pursuit burst
		# belongs to a HUNTER and a thing that defends one spot is not hunting you. The
		# rule is right, so the burst went rather than the disposition — the drake is a
		# wall across the route, and the fast top end of the territorial chase band is
		# what makes it feel like one.
		"roam_radius": 56.0,
		"leash_radius": 160.0,
		"roam_speed": 22.0,
		"chase_speed": 62.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 0.8,
		"memory_seconds": 4.0,
		"recovery_seconds": 2.8,
		"post_flee_grace_seconds": 2.0,
	},
	"mountain_king": {
		"id": "mountain_king",
		"disposition": TERRITORIAL,
		# Slowest thing in the roster (enemies.json speed 5) and the heaviest: no burst at
		# all, but the longest memory and reach of any authored profile. You do not
		# outrun him in a sprint, you outlast him — which is the fight "the summit itself
		# appears to stand and draw a weapon" should be.
		"detect_radius": 120.0,
		"roam_radius": 48.0,
		"leash_radius": 208.0,
		"roam_speed": 18.0,
		"chase_speed": 52.0,
		"burst_speed": 0.0,
		"burst_seconds": 0.0,
		"warning_seconds": 1.4,
		"memory_seconds": 5.5,
		"recovery_seconds": 3.5,
		"post_flee_grace_seconds": 2.5,
	},
}

const ENEMY_ID_ALIASES: Dictionary = {
	# The authored database and scenes retain this legacy save-compatible spelling.
	"raccoon": "racoon",
}


static func disposition_rules(disposition: String) -> Dictionary:
	var normalized := disposition.strip_edges().to_lower()
	if not DISPOSITION_RULES.has(normalized):
		return {}
	return (DISPOSITION_RULES[normalized] as Dictionary).duplicate(true)


static func state_name(state: int) -> String:
	if state < 0 or state >= STATE_NAMES.size():
		return "unknown"
	return STATE_NAMES[state]


static func default_for_disposition(disposition: String) -> Dictionary:
	var normalized := disposition.strip_edges().to_lower()
	if not DISPOSITION_DEFAULTS.has(normalized):
		return {}
	return (DISPOSITION_DEFAULTS[normalized] as Dictionary).duplicate(true)


static func preset_for_enemy(enemy_id: String) -> Dictionary:
	var normalized := _normalized_enemy_id(enemy_id)
	if not ENEMY_PRESETS.has(normalized):
		return {}
	return (ENEMY_PRESETS[normalized] as Dictionary).duplicate(true)


## Runtime-safe lookup. Unknown or dormant IDs get a non-initiating passive profile rather
## than inheriting a playable enemy's behavior. Content validation can still distinguish the
## fallback through is_fallback or by using preset_for_enemy(), which returns {} on a miss.
static func profile(enemy_id: String) -> Dictionary:
	var normalized := _normalized_enemy_id(enemy_id)
	var authored := preset_for_enemy(normalized)
	if not authored.is_empty():
		authored["is_fallback"] = false
		return authored
	var fallback := default_for_disposition(PASSIVE)
	fallback["id"] = normalized if not normalized.is_empty() else "unknown"
	fallback["is_fallback"] = true
	return fallback


static func is_valid(definition: Dictionary) -> bool:
	return validate(definition).is_empty()


static func is_sustained_speed_allowed(speed: float) -> bool:
	return speed < SUSTAINED_SPEED_BAN_MIN or speed > SUSTAINED_SPEED_BAN_MAX


static func validate(definition: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field: String in REQUIRED_FIELDS:
		if not definition.has(field):
			errors.append("missing required field '%s'" % field)
	if not errors.is_empty():
		return errors

	if typeof(definition["id"]) != TYPE_STRING or String(definition["id"]).strip_edges().is_empty():
		errors.append("id must be a non-empty String")
	if typeof(definition["disposition"]) != TYPE_STRING:
		errors.append("disposition must be a String")
	for field: String in NUMERIC_FIELDS:
		if not _is_number(definition[field]):
			errors.append("%s must be numeric" % field)
	if not errors.is_empty():
		return errors

	var disposition := String(definition["disposition"]).strip_edges().to_lower()
	if not DISPOSITION_ORDER.has(disposition):
		errors.append("unknown disposition '%s'" % disposition)
		return errors

	var detect_radius := float(definition["detect_radius"])
	var roam_radius := float(definition["roam_radius"])
	var leash_radius := float(definition["leash_radius"])
	var roam_speed := float(definition["roam_speed"])
	var chase_speed := float(definition["chase_speed"])
	var burst_speed := float(definition["burst_speed"])
	var burst_seconds := float(definition["burst_seconds"])
	var warning_seconds := float(definition["warning_seconds"])
	var memory_seconds := float(definition["memory_seconds"])
	var recovery_seconds := float(definition["recovery_seconds"])
	var grace_seconds := float(definition["post_flee_grace_seconds"])

	for field: String in [
		"detect_radius",
		"roam_radius",
		"leash_radius",
		"burst_speed",
		"burst_seconds",
		"warning_seconds",
		"memory_seconds",
		"recovery_seconds",
		"post_flee_grace_seconds",
	]:
		if float(definition[field]) < 0.0:
			errors.append("%s cannot be negative" % field)

	if roam_speed < MIN_ROAM_SPEED or roam_speed > MAX_ROAM_SPEED:
		errors.append("roam_speed must stay within %.0f-%.0f px/s" % [MIN_ROAM_SPEED, MAX_ROAM_SPEED])
	if not is_sustained_speed_allowed(roam_speed):
		errors.append("roam_speed cannot use the sustained %.0f-%.0f px/s player band" % [
			SUSTAINED_SPEED_BAN_MIN, SUSTAINED_SPEED_BAN_MAX])

	if disposition == PASSIVE:
		if chase_speed != 0.0:
			errors.append("passive enemies cannot have chase_speed")
	else:
		if chase_speed < MIN_CHASE_SPEED or chase_speed > MAX_CHASE_SPEED:
			errors.append("chase_speed must stay within %.0f-%.0f px/s" % [
				MIN_CHASE_SPEED, MAX_CHASE_SPEED])
		if not is_sustained_speed_allowed(chase_speed):
			errors.append("chase_speed cannot use the sustained %.0f-%.0f px/s player band" % [
				SUSTAINED_SPEED_BAN_MIN, SUSTAINED_SPEED_BAN_MAX])

	if disposition == PASSIVE or disposition == PROVOKED:
		if detect_radius != 0.0:
			errors.append("%s enemies cannot initiate through detect_radius" % disposition)
		if warning_seconds != 0.0:
			errors.append("%s enemies do not use proactive warning time" % disposition)
	else:
		if detect_radius <= 0.0:
			errors.append("%s enemies require a positive detect_radius" % disposition)
		if warning_seconds <= 0.0:
			errors.append("%s enemies require a positive warning_seconds" % disposition)

	if roam_radius <= 0.0:
		errors.append("roam_radius must be positive")
	if leash_radius <= 0.0:
		errors.append("leash_radius must be positive")
	if leash_radius < roam_radius:
		errors.append("leash_radius cannot be smaller than roam_radius")
	if detect_radius > 0.0 and leash_radius < detect_radius:
		errors.append("leash_radius cannot be smaller than detect_radius")
	if disposition != PASSIVE and memory_seconds <= 0.0:
		errors.append("active enemies require positive memory_seconds")
	if recovery_seconds <= 0.0:
		errors.append("recovery_seconds must be positive")
	if grace_seconds <= 0.0:
		errors.append("post_flee_grace_seconds must be positive")

	if disposition == HUNTER:
		if burst_speed <= SUSTAINED_SPEED_BAN_MAX or burst_speed > MAX_BURST_SPEED:
			errors.append("hunter burst_speed must be above %.0f and at most %.0f px/s" % [
				SUSTAINED_SPEED_BAN_MAX, MAX_BURST_SPEED])
		if burst_seconds <= 0.0 or burst_seconds > MAX_BURST_SECONDS:
			errors.append("hunter burst_seconds must be positive and at most %.1f" % MAX_BURST_SECONDS)
		if recovery_seconds < MIN_BURST_RECOVERY_SECONDS:
			errors.append("hunter recovery_seconds must be at least %.1f" % MIN_BURST_RECOVERY_SECONDS)
	else:
		if burst_speed != 0.0 or burst_seconds != 0.0:
			errors.append("only hunter enemies may define a pursuit burst")

	return errors


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _normalized_enemy_id(enemy_id: String) -> String:
	var normalized := enemy_id.strip_edges().to_lower()
	return String(ENEMY_ID_ALIASES.get(normalized, normalized))
