extends SceneTree
## Guard: two different people must not wear the same face.
##
##   godot --headless --path . --script res://tests/test_npc_faces_differ.gd
##
## The project standard is that reusing one NPC sprite for two characters is a placeholder
## failure, the same as reusing one room layout for a second building. It had already been
## applied inside single regions and then quietly broken across them: the mountain lookout
## "Tomas" and the wilds outpost "Keeper" shared npc_villager2, and the house "Host" shared
## npc_woman with the village teacher "Hana" -- four distinct, separately-named characters
## wearing two faces.
##
## Enemies are deliberately exempt. Six bats SHOULD be one bat sprite; that is a species,
## not a placeholder. This only looks at NPCs, which are individuals with names.
##
## Reads the .tscn files as text rather than instantiating regions, so it stays cheap and
## does not need autoloads or a save.

const SCENE_DIR := "res://src/scenes"

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# sheet path -> the set of distinct speakers using it
	var by_sheet: Dictionary = {}
	var scanned := 0
	for path in _scene_files():
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			continue
		scanned += 1
		var externals := _external_textures(text)
		for block in _node_blocks(text):
			var sheet_id := _field(block, "sprite_sheet_ext")
			if sheet_id.is_empty() or not externals.has(sheet_id):
				continue
			var sheet: String = externals[sheet_id]
			if not sheet.contains("npc_"):
				continue
			var who := _field(block, "speaker")
			if who.is_empty():
				who = _field(block, "node_name")
			var seen: Dictionary = by_sheet.get(sheet, {})
			seen[who] = true
			by_sheet[sheet] = seen

	check_true("found NPC scenes to check (%d scanned, %d sheets in use)"
		% [scanned, by_sheet.size()],
		scanned > 0 and by_sheet.size() > 0)

	for sheet in by_sheet:
		var speakers: Array = (by_sheet[sheet] as Dictionary).keys()
		speakers.sort()
		check_true("%s is worn by one character only (%s)"
			% [String(sheet).get_file(), ", ".join(PackedStringArray(speakers))],
			speakers.size() <= 1)
	_finish()


func _scene_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(SCENE_DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".tscn"):
			out.append("%s/%s" % [SCENE_DIR, file])
	return out


## id -> res:// path, for every Texture2D ext_resource in the file.
func _external_textures(text: String) -> Dictionary:
	var out: Dictionary = {}
	var re := RegEx.create_from_string(
		'\\[ext_resource type="Texture2D"[^\\]]*path="([^"]+)"[^\\]]*id="([^"]+)"\\]')
	for m in re.search_all(text):
		out[m.get_string(2)] = m.get_string(1)
	return out


func _node_blocks(text: String) -> Array[String]:
	var blocks: Array[String] = []
	var parts := text.split("[node ")
	for i in range(1, parts.size()):
		blocks.append("[node " + parts[i])
	return blocks


func _field(block: String, which: String) -> String:
	var pattern := ""
	match which:
		"sprite_sheet_ext":
			pattern = '\\n\\s*sprite_sheet = ExtResource\\("([^"]+)"\\)'
		"speaker":
			pattern = '\\n\\s*speaker = "([^"]+)"'
		"node_name":
			pattern = '^\\[node name="([^"]+)"'
		_:
			return ""
	var re := RegEx.create_from_string(pattern)
	var m := re.search(block)
	return m.get_string(1) if m != null else ""


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — every named NPC has a face of their own.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
