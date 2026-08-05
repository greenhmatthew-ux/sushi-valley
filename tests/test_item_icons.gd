extends SceneTree
## Every item has its own icon, and no two items look the same.
##
##   godot --headless --path . --script res://tests/test_item_icons.gd
##
## The inventory shipped for a long time with 172 items drawn by 116 pictures. Eight
## different monster drops — bear pelt, kitsune tail, spider silk, lizard hide, raccoon
## tail, and three more — were one white lump, and all six *coloured* dragon scales were
## the same green gem. Nothing errored, every other test stayed green, and the loot table
## simply read as noise: you could not tell what had dropped without opening the tooltip.
##
## That is the failure this guards. It is invisible to logic tests by construction, and it
## comes back the moment someone adds an item and points it at a neighbour's art to save a
## file — which is exactly how the 25 `iconAlias` entries accumulated. So the bar here is
## the whole point of an icon: distinct art per item, at the one size the UI draws.

const ITEMS_JSON := "res://data/game/items.json"
const ICON_DIR := "res://assets/icons/items/"
## 16px native art, rendered at zoom 2 — an icon off this size is a pack that was
## imported without being cut down, and it will not sit on the gear tiles.
const ICON_SIZE := Vector2i(16, 16)

var failures: int = 0


func _initialize() -> void:
	await process_frame
	var items := _load_items()
	check_true("items.json parsed and is non-empty", not items.is_empty())
	_every_item_has_its_own_icon(items)
	_no_two_items_share_a_picture(items)
	_icons_are_native_size(items)
	_finish()


func _load_items() -> Array:
	var text := FileAccess.get_file_as_string(ITEMS_JSON)
	if text.is_empty():
		return []
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Array else []


## An item that borrows another's file is one rename away from silently changing two
## icons at once, so each item is required to own the art it draws.
func _every_item_has_its_own_icon(items: Array) -> void:
	var missing: Array[String] = []
	var borrowed: Array[String] = []
	for item in items:
		var id := String(item.get("id", ""))
		if item.has("iconAlias"):
			borrowed.append(id)
		if not FileAccess.file_exists(ICON_DIR + id + ".png"):
			missing.append(id)
	check_true("every item has %s.png of its own (missing: %s)" % ["<id>", missing], missing.is_empty())
	check_true("no item borrows another item's icon (borrowing: %s)" % [borrowed], borrowed.is_empty())


## The check the whole slice exists for. Compares file digests rather than paths, because
## the old duplicates were byte-identical copies sitting under different names.
func _no_two_items_share_a_picture(items: Array) -> void:
	var by_digest := {}
	for item in items:
		var id := String(item.get("id", ""))
		var path := ICON_DIR + id + ".png"
		if not FileAccess.file_exists(path):
			continue
		var digest := FileAccess.get_md5(path)
		if not by_digest.has(digest):
			by_digest[digest] = [] as Array[String]
		by_digest[digest].append(id)
	var shared: Array = []
	for digest: String in by_digest:
		if by_digest[digest].size() > 1:
			shared.append(by_digest[digest])
	check_true("no two items draw the same picture (shared: %s)" % [shared], shared.is_empty())
	check_eq("distinct icons", by_digest.size(), items.size())


func _icons_are_native_size(items: Array) -> void:
	var wrong: Array[String] = []
	for item in items:
		var path := ICON_DIR + String(item.get("id", "")) + ".png"
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null or tex.get_size() != Vector2(ICON_SIZE):
			wrong.append(String(item.get("id", "")))
	check_true("every icon is %dx%d (wrong: %s)" % [ICON_SIZE.x, ICON_SIZE.y, wrong], wrong.is_empty())


func _finish() -> void:
	print("")
	print(("PASS — every item has its own 16x16 icon and no two are alike."
		if failures == 0 else "FAIL — %d item-icon check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1
