extends SceneTree
## Pure coverage for the shared region placement maths: trail brushes and prop scatter.
##
##   godot --headless --path . --script res://tests/test_terrain_scatter.gd
##
## These are the rules that keep a generated region playable: a trail that stays connected
## to its own waypoints, and cover that never lands on the trail, on a doorway, or on top
## of another prop.

const Scatter = preload("res://src/systems/terrain_scatter.gd")

const MAP := Vector2i(40, 30)

var failures: int = 0


func _initialize() -> void:
	_brush_widths_are_what_they_claim()
	_a_wide_brush_never_drops_its_centreline()
	_clumping_varies_by_block_and_is_deterministic()
	_cover_never_lands_on_blocked_ground()
	_cover_keeps_its_distance_from_other_cover()
	_zone_densities_are_respected()
	_a_zero_mix_builds_nothing()
	_finish()


func _brush_widths_are_what_they_claim() -> void:
	check_eq("a single-file track is one tile",
		Scatter.brush_cells(Vector2i(5, 5), 1), [Vector2i(5, 5)])
	var walked := Scatter.brush_cells(Vector2i(5, 5), 2)
	check_true("a walked trail is at most a 2x2 stamp (%d)" % walked.size(),
		walked.size() >= 1 and walked.size() <= 4)
	var road := Scatter.brush_cells(Vector2i(5, 5), 3)
	check_true("a road is at most a 3x3 stamp (%d)" % road.size(),
		road.size() >= 1 and road.size() <= 9)
	check_true("a road is wider than a walked trail", road.size() > walked.size())


## The ragged edge is cosmetic; dropping the centre would cut the path in half and could
## strand a door that sits on a waypoint.
func _a_wide_brush_never_drops_its_centreline() -> void:
	var missing := 0
	for x in 60:
		for y in 60:
			var center := Vector2i(x, y)
			for width in [1, 2, 3]:
				if not (center in Scatter.brush_cells(center, width)):
					missing += 1
	check_eq("every brush keeps the cell it was stamped on", missing, 0)

	var edges_dropped := 0
	for x in 60:
		var full := Scatter.brush_cells(Vector2i(x, 7), 3)
		if full.size() < 9:
			edges_dropped += 1
	check_true("wide brushes do drop some edge cells, so trails look walked (%d)"
		% edges_dropped, edges_dropped > 0)


func _clumping_varies_by_block_and_is_deterministic() -> void:
	check_eq("clumping is deterministic",
		Scatter.clump_weight(Vector2i(12, 9)), Scatter.clump_weight(Vector2i(12, 9)))
	check_eq("neighbours inside one block share a weight",
		Scatter.clump_weight(Vector2i(10, 10), 5), Scatter.clump_weight(Vector2i(12, 12), 5))

	var weights := {}
	var lowest := 99.0
	var highest := -99.0
	for x in range(0, 60, 5):
		for y in range(0, 60, 5):
			var w := Scatter.clump_weight(Vector2i(x, y), 5)
			weights[w] = true
			lowest = minf(lowest, w)
			highest = maxf(highest, w)
	check_true("blocks get many different weights (%d)" % weights.size(),
		weights.size() > 20)
	check_true("weights stay inside the declared band (%.2f-%.2f)" % [lowest, highest],
		lowest >= Scatter.CLUMP_FLOOR
		and highest <= Scatter.CLUMP_FLOOR + Scatter.CLUMP_RANGE)
	check_true("clumping both thins and thickens (%.2f-%.2f)" % [lowest, highest],
		lowest < 1.0 and highest > 1.0)


## Trails, doorways and authored landmarks all reach the planner as blocked tiles. Cover
## must clear them by a full tile, or a region can build a tree across its own way out.
func _cover_never_lands_on_blocked_ground() -> void:
	var blocked: Dictionary = {}
	for y in MAP.y:
		blocked[Vector2i(20, y)] = true   # a trail straight down the map
	var plan := Scatter.plan_cover(MAP, blocked, _dense_mix, ["tree"], 4242)
	check_true("a dense zone actually plans cover (%d)" % plan.size(), plan.size() > 20)

	var on_blocked := 0
	var crowding_blocked := 0
	for entry in plan:
		var cell: Vector2i = entry["cell"]
		if blocked.has(cell):
			on_blocked += 1
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				if blocked.has(cell + Vector2i(dx, dy)):
					crowding_blocked += 1
	check_eq("nothing is built on blocked ground", on_blocked, 0)
	check_eq("nothing is built within a tile of blocked ground", crowding_blocked, 0)

	var outside := 0
	for entry in plan:
		var cell: Vector2i = entry["cell"]
		if cell.x < 1 or cell.y < 1 or cell.x >= MAP.x - 1 or cell.y >= MAP.y - 1:
			outside += 1
	check_eq("nothing is built off the map or on its rim", outside, 0)

	check_true("planning does not mutate the caller's blocked map",
		blocked.size() == MAP.y)


func _cover_keeps_its_distance_from_other_cover() -> void:
	var plan := Scatter.plan_cover(MAP, {}, _dense_mix, ["tree"], 99)
	var too_close := 0
	for i in plan.size():
		for j in range(i + 1, plan.size()):
			var a: Vector2i = plan[i]["cell"]
			var b: Vector2i = plan[j]["cell"]
			if absi(a.x - b.x) <= 1 and absi(a.y - b.y) <= 1:
				too_close += 1
	check_eq("no two props stand within a tile of each other", too_close, 0)


func _zone_densities_are_respected() -> void:
	var plan := Scatter.plan_cover(MAP, {}, _split_mix, ["tree"], 7)
	var west := 0
	var east := 0
	for entry in plan:
		if int((entry["cell"] as Vector2i).x) < MAP.x / 2:
			west += 1
		else:
			east += 1
	check_true("the dense half is denser than the sparse half (%d vs %d)" % [west, east],
		west > east * 2)

	var kinds: Dictionary = {}
	for entry in plan:
		kinds[String(entry["kind"])] = true
	check_true("the planner reports the kind it chose", kinds.has("tree"))


func _a_zero_mix_builds_nothing() -> void:
	check_eq("a zone with no density stays empty",
		Scatter.plan_cover(MAP, {}, _empty_mix, ["tree"], 3).size(), 0)


func _dense_mix(_cell: Vector2i) -> Dictionary:
	return {"tree": 0.7, "rock": 0.1}


func _split_mix(cell: Vector2i) -> Dictionary:
	if cell.x < MAP.x / 2:
		return {"tree": 0.8, "rock": 0.05}
	return {"tree": 0.08, "rock": 0.02}


func _empty_mix(_cell: Vector2i) -> Dictionary:
	return {"tree": 0.0, "rock": 0.0}


func _finish() -> void:
	print("")
	print("PASS - generated regions place trails and cover on playable ground."
		if failures == 0 else "FAIL - %d terrain scatter check(s) failed." % failures)
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got: Variant, want: Variant) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
