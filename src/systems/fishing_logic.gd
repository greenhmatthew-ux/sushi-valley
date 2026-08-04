class_name FishingLogic
extends RefCounted
## Pure port of the archived FishingMinigame.ts control model. Coordinates are
## local to a 160px meter, so UI scale and camera position cannot change play.

const METER_HEIGHT := 160.0
const CATCH_HEIGHT := 44.0
const FISH_SIZE := 16.0
const PROGRESS_MAX := 100.0
const GOLD_ACCURACY := 0.82
const SILVER_ACCURACY := 0.62
const GRACE_SECONDS := 1.2

var difficulty := 1.0
var elapsed := 0.0
var in_grace := true
var progress := 25.0
var bar_y := 56.0
var bar_velocity := 0.0
var fish_y := 68.0
var fish_velocity := 0.0
var fish_target_y := 0.0
var next_fish_move_time := GRACE_SECONDS
var control_seconds := 0.0
var overlap_seconds := 0.0
var finished := false
var success := false
var rng := RandomNumberGenerator.new()


func _init(difficulty_value: float = 1.0, seed_value: int = 0) -> void:
	difficulty = maxf(0.1, difficulty_value)
	if seed_value == 0:
		rng.randomize()
	else:
		rng.seed = seed_value


static func catch_quality(accuracy: float) -> String:
	var clamped := clampf(accuracy, 0.0, 1.0)
	if clamped >= GOLD_ACCURACY:
		return "gold"
	if clamped >= SILVER_ACCURACY:
		return "silver"
	return "normal"


func accuracy() -> float:
	return overlap_seconds / control_seconds if control_seconds > 0.0 else 0.0


func quality() -> String:
	return catch_quality(accuracy())


func is_overlapping() -> bool:
	return fish_y >= bar_y - CATCH_HEIGHT / 2.0 \
		and fish_y <= bar_y + CATCH_HEIGHT / 2.0


func step(delta: float, reeling: bool, stormy: bool = false) -> Dictionary:
	if finished or delta <= 0.0:
		return state()

	var was_in_grace := in_grace
	elapsed += delta
	if was_in_grace:
		in_grace = elapsed < GRACE_SECONDS
		# Match the archived delayed callback: the frame that ends grace still only
		# shows Cast; control begins on the following frame.
		return state()

	if reeling:
		bar_velocity -= 950.0 * delta
	else:
		bar_velocity += 620.0 * delta
	bar_velocity = clampf(bar_velocity, -280.0, 280.0)
	bar_y += bar_velocity * delta
	var bar_limit := METER_HEIGHT / 2.0 - CATCH_HEIGHT / 2.0 - 2.0
	if bar_y > bar_limit:
		bar_y = bar_limit
		bar_velocity = -bar_velocity * 0.38
		if absf(bar_velocity) < 15.0:
			bar_velocity = 0.0
	elif bar_y < -bar_limit:
		bar_y = -bar_limit
		bar_velocity = 0.0

	if elapsed >= next_fish_move_time:
		var movement_range := METER_HEIGHT - FISH_SIZE - 8.0
		if difficulty > 2.5 and rng.randf() < 0.45:
			var edge_percent := 0.15 if rng.randf() < 0.5 else 0.85
			fish_target_y = -METER_HEIGHT / 2.0 + 4.0 + FISH_SIZE / 2.0 \
				+ edge_percent * movement_range
			next_fish_move_time = elapsed + 0.3 + rng.randf() * 0.5
		else:
			fish_target_y = -METER_HEIGHT / 2.0 + 4.0 + FISH_SIZE / 2.0 \
				+ rng.randf() * movement_range
			next_fish_move_time = elapsed + 0.7 + rng.randf() * 1.1

	var fish_force := 120.0 + difficulty * 60.0
	var distance := fish_target_y - fish_y
	fish_velocity += signf(distance) * fish_force * delta
	fish_velocity *= 0.94
	var fish_limit := 260.0 if stormy else 200.0
	fish_velocity = clampf(fish_velocity, -fish_limit, fish_limit)
	fish_y += fish_velocity * delta
	var position_limit := METER_HEIGHT / 2.0 - FISH_SIZE / 2.0 - 4.0
	fish_y = clampf(fish_y, -position_limit, position_limit)

	var overlap := is_overlapping()
	control_seconds += delta
	if overlap:
		overlap_seconds += delta
	var change := (24.0 if stormy else 28.0) if overlap \
		else (-26.0 if stormy else -18.0)
	progress = clampf(progress + change * delta, 0.0, PROGRESS_MAX)
	if progress >= PROGRESS_MAX:
		finished = true
		success = true
	elif progress <= 0.0 and not overlap:
		finished = true
		success = false
	return state()


func state() -> Dictionary:
	return {
		"in_grace": in_grace,
		"progress": progress,
		"bar_y": bar_y,
		"fish_y": fish_y,
		"overlap": is_overlapping(),
		"finished": finished,
		"success": success,
		"accuracy": accuracy(),
		"quality": quality(),
	}
