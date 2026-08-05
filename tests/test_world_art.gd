extends SceneTree
## World objects are made of real art, and every atlas region lands on its sheet.
##
##   godot --headless --path . --script res://tests/test_world_art.gd
##
## Farm plots, fishing spots and resource nodes used to draw themselves out of
## `draw_rect` / `draw_circle` primitives. Beside the tiled world that reads as
## placeholder geometry, and it was the first thing Matthew flagged on sight. They now
## use sheets from the project's art canon.
##
## The failure this guards is quiet and specific: an AtlasTexture whose region falls off
## its sheet renders as empty space or as a neighbouring tile. Nothing errors, no test
## fails, and the object simply looks wrong — which is exactly how the code-drawn
## versions survived so long. Every region is therefore checked against real sheet bounds.

## Atlas coordinates live in a pure catalogue so this entry script never has to preload
## runtime entities whose Farm/Fishing/Gathering autoloads register later in startup.
const Art := preload("res://src/systems/world_art_catalog.gd")

var failures: int = 0


func _initialize() -> void:
	await process_frame
	_regions_land_on_their_sheets()
	_every_crop_and_stage_resolves()
	_ore_kinds_are_told_apart()
	_state_cues_are_still_drawn()
	_people_in_a_region_look_different()
	_finish()


## Five of the village's NPCs were once drawn with the same sheet, and two people stood
## yards apart in the Wilds wearing the same face. Sharing a sheet across regions is fine —
## nobody sees both at once — but two characters in one scene must not.
func _people_in_a_region_look_different() -> void:
	for scene_path: String in [
		"res://src/scenes/world.tscn",
		"res://src/scenes/wilds.tscn",
		"res://src/scenes/mountain_pass.tscn",
	]:
		var scene: Node = load(scene_path).instantiate()
		var by_sheet: Dictionary = {}
		for node in _people(scene):
			var sheet := node.get("sprite_sheet") as Texture2D
			if sheet == null:
				continue
			var key := sheet.resource_path
			if not by_sheet.has(key):
				by_sheet[key] = []
			(by_sheet[key] as Array).append(String(node.name))
		var shared: Array[String] = []
		for raw_key in by_sheet:
			var users: Array = by_sheet[raw_key]
			if users.size() > 1:
				shared.append("%s: %s" % [String(raw_key).get_file(), ", ".join(users)])
		check_true("%s gives each of its people their own face%s"
			% [scene_path.get_file(), "" if shared.is_empty() else " — %s" % "; ".join(shared)],
			shared.is_empty())
		scene.free()


## Talking characters only. Enemies of the same species are meant to share a sheet.
func _people(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if node.get("sprite_sheet") != null and node.get("enemy_id") == null:
		found.append(node)
	for child in node.get_children():
		found.append_array(_people(child))
	return found


func _regions_land_on_their_sheets() -> void:
	var checks := [
		["farm soil", Art.SOIL_SHEET, Art.SOIL_REGION],
		["water ripple frame 0", Art.RIPPLE_SHEET, Rect2(0, 0, 16, 16)],
		["water ripple last frame", Art.RIPPLE_SHEET,
			Rect2((Art.RIPPLE_FRAMES - 1) * 16, 0, 16, 16)],
		["tan ore rock", Art.NATURE_SHEET, Art.ROCK_TAN],
		["grey ore rock", Art.NATURE_SHEET, Art.ROCK_GREY],
		["herb plant", Art.NATURE_SHEET, Art.PLANT_HERB],
		["bamboo plant", Art.NATURE_SHEET, Art.PLANT_BAMBOO],
	]
	for check in checks:
		_region_fits(String(check[0]), check[1], check[2])


func _region_fits(label: String, sheet: Texture2D, region: Rect2) -> void:
	var bounds := Rect2(Vector2.ZERO, sheet.get_size())
	check_true("%s sits inside %s (%s in %s)"
		% [label, sheet.resource_path.get_file(), region, bounds.size],
		bounds.encloses(region))
	# A region of nothing renders as an invisible object rather than an error.
	check_true("%s is not an empty region" % label, region.size.x > 0 and region.size.y > 0)


## Every crop the game can plant must resolve to a real tile at every growth stage,
## including a crop with no authored row, which falls back rather than drawing nothing.
func _every_crop_and_stage_resolves() -> void:
	var db: Node = root.get_node("DB")
	var sheet: Texture2D = Art.CROP_SHEET
	var bounds := Rect2(Vector2.ZERO, sheet.get_size())
	var missing: Array[String] = []
	for crop_id in db.crops:
		if not Art.CROP_ROWS.has(String(crop_id)):
			missing.append(String(crop_id))
	check_true("every authored crop has its own art row (%s)" % str(missing),
		missing.is_empty())

	var off_sheet: Array[String] = []
	var rows: Array = Art.CROP_ROWS.values() + [Art.CROP_FALLBACK_ROW]
	for row in rows:
		for column in Art.CROP_STAGE_COLUMNS:
			var region := Rect2(int(column) * 16, int(row) * 16, 16, 16)
			if not bounds.encloses(region):
				off_sheet.append(str(region))
	check_true("every crop stage lands on the sheet (%s)" % str(off_sheet),
		off_sheet.is_empty())
	check_eq("the four growth stages are distinct columns",
		Art.CROP_STAGE_COLUMNS.size(),
		_unique(Art.CROP_STAGE_COLUMNS).size())
	# A plot that looks finished has to be the harvestable one.
	check_eq("the last stage is the sheet's mature column",
		int(Art.CROP_STAGE_COLUMNS[-1]), 5)


## Copper and iron seams were the same grey blob with the same orange flecks, so the
## only way to tell them apart was to walk up and read the prompt.
## Asserted from the pure catalogue rather than by instantiating a runtime node.
func _ore_kinds_are_told_apart() -> void:
	check_true("a copper seam and an iron seam do not share one sprite",
		Art.ROCK_TAN != Art.ROCK_GREY)
	check_true("a herb patch and a bamboo stand do not share one sprite",
		Art.PLANT_HERB != Art.PLANT_BAMBOO)
	check_true("iron is routed to the grey rock",
		"raw_iron_ore" in Art.GREY_ORES)
	check_true("copper is left on the tan rock",
		"copper_ore" not in Art.GREY_ORES)
	# Which ores exist in shipped regions is asserted by test_smithing_chain.


## The art replaced the object, not the information. These cues have no sprite in any
## pack, so they stay drawn in code and must not have been deleted along with the blobs.
func _state_cues_are_still_drawn() -> void:
	var source := FileAccess.get_file_as_string("res://src/entities/resource_node.gd")
	for cue in ["_draw_tool_badge", "_draw_gather_burst"]:
		check_true("%s still exists" % cue, source.contains("func %s" % cue))
	check_true("the ready glint is still drawn", source.contains("glint_alpha"))
	check_true("the old code-drawn blobs are gone",
		not source.contains("func _draw_ore") and not source.contains("func _draw_herb"))
	var farm_source := FileAccess.get_file_as_string("res://src/entities/farm_plot.gd")
	check_true("the farm no longer draws crops as primitives",
		not farm_source.contains("func _draw_crop"))


func _unique(values: Array) -> Array:
	var seen := {}
	for v in values:
		seen[v] = true
	return seen.keys()


func _finish() -> void:
	print("")
	print(("PASS — world objects use real art and every region lands on its sheet."
		if failures == 0 else "FAIL — %d world-art check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
