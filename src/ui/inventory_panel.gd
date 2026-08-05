extends CanvasLayer
## The compact Player menu: a Character summary plus a card grid of what you're carrying.
## Toggled by the `open_menu` action, rebuilt on every `Bus.inventory_changed`
## so it never polls. Built in code to match recall_panel / toast_layer, and
## because the card count is dynamic.
##
## Kept as a card grid (not a long scroll) per the UX rules: items wrap into a
## fixed-height grid, and only overflow scrolls. Reads item names / icons / kinds
## from DB and quantities from the Inv autoload.
##
## Gear cards expose one clear Equip action. Equipped items sit in a compact strip
## above the bag and can be removed there, so equipment never becomes hidden state.

const AbilityRules = preload("res://src/systems/ability_logic.gd")
const Roles = preload("res://src/systems/role_logic.gd")
const ConsumableRules = preload("res://src/systems/consumable_logic.gd")
const Activities = preload("res://src/systems/activity_tracker.gd")
const WorldMapGraph = preload("res://src/ui/world_map_graph.gd")

# Palette shared with recall_panel for a consistent feel.
const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_CARD := UiTheme.SURFACE_RAISED
const COL_CARD_BORDER := UiTheme.BORDER_STRONG
const COL_COIN := UiTheme.ACCENT_GOLD
const COL_TEXT := UiTheme.TEXT_PRIMARY
const COL_WARN := UiTheme.STATE_DANGER

# Kind -> name colour, ported from itemColor() in ItemTypes.ts.
const KIND_COLORS := {
	"gear": Color(0.78, 0.808, 0.847),      # rarity handled by combat slice; common tint here
	"consumable": UiTheme.STATE_SUCCESS,
	"material": Color(0.788, 0.639, 0.42),
	"seed": UiTheme.STATE_SUCCESS,
	"tool": UiTheme.STATE_INFO,
}

## Bag category filters. The first six are real `kind` values the item table now
## uses. Fish/Food and Quest Items still have no dedicated data kind, so they are
## not offered as filters that would always come back empty. "favorites" is synthetic, backed
## by InventoryLogic's own favorites set rather than an item field.
const BAG_CATEGORIES := [
	["all", "All"], ["gear", "Equipment"], ["consumable", "Consumables"],
	["material", "Materials"], ["seed", "Seeds"], ["tool", "Tools"],
	["favorites", "Favorites"],
]

const ICON_DIR := "res://assets/icons/items/"
const ABILITY_ICON_DIR := "res://assets/icons/abilities/"
## These files were replaced with traced Ninja Adventure CC0 originals in the
## Talent-art slice. Do not render the remaining legacy ability icons until audited.
const VERIFIED_ABILITY_ICONS := [
	"sweep", "kunai", "kana_bolt", "brace", "ki_focus", "rune_ward", "riposte",
	"blood_blade", "iaido", "pinning_shot", "glyph_storm", "fortress",
]
## The 12 equipment slots grouped by type, so the Character tab reads as a real
## gear layout instead of one flat wrapping row. Every slot in
## InventoryLogic.EQUIPMENT_SLOTS must appear exactly once across these groups —
## test_player_menu.gd checks that, so a new slot added there cannot go missing here.
const EQUIPMENT_GROUPS := [
	["Weapon", ["weapon", "offhand"]],
	["Armor", ["head", "shoulders", "body", "cape", "belt", "hands", "legs", "feet"]],
	["Accessories", ["ring", "amulet"]],
]

## Gathering and crafting intentionally share these three progression tracks.
## Keeping their player-facing loop copy here avoids inventing parallel Mining /
## Foraging levels before those domains have authored tools and unlock tables.
const LIFE_SKILLS := [
	{
		"station": "forge", "name": "Forge",
		"loop": "Mine ore, refine metal, and craft weapons.",
		"weather": "Non-rain days can yield +1 ore.",
	},
	{
		"station": "workshop", "name": "Workshop",
		"loop": "Gather bamboo and build field gear.",
		"weather": "Bamboo yield is steady in any weather.",
	},
	{
		"station": "kitchen", "name": "Kitchen",
		"loop": "Forage herbs, fish, and cook recovery food.",
		"weather": "Rain can yield +1 herb.",
	},
]

const TAB_CHARACTER := "character"
const TAB_SKILLS := "skills"
const TAB_BAG := "bag"
const TAB_QUESTS := "quests"
const TAB_MAP := "map"
const TAB_LEARNING := "learning"
const TAB_SYSTEM := "system"
const TAB_BESTIARY := "bestiary"
const TAB_ORDER := [TAB_CHARACTER, TAB_SKILLS, TAB_BAG, TAB_QUESTS,
	TAB_MAP, TAB_LEARNING, TAB_SYSTEM, TAB_BESTIARY]

var _open := false
var _active_tab := TAB_BAG
var _root: Control
var _coins_label: Label
var _equipment_group_boxes: Dictionary = {}   # group name -> HFlowContainer
var _character_scroll: ScrollContainer
var _character_view: VBoxContainer
var _skills_view: VBoxContainer
var _skills_box: VBoxContainer
var _skills_summary: Label
var _bag_view: VBoxContainer
var _bag_category := "all"
var _bag_search := ""
var _bag_category_buttons: Dictionary = {}   # category key -> Button
var _bag_search_box: LineEdit
var _prepared_meal_box: HBoxContainer
var _stats_label: Label
var _attribute_points_label: Label
var _attribute_value_labels: Dictionary = {}
var _attribute_plus_buttons: Dictionary = {}
var _attribute_minus_buttons: Dictionary = {}
var _character_tab: Button
var _skills_tab: Button
var _bag_tab: Button
var _quests_tab: Button
var _quests_view: VBoxContainer
var _quests_box: VBoxContainer
var _quests_summary: Label
var _map_tab: Button
var _map_view: VBoxContainer
var _map_box: Control
var _map_summary: Label
var _map_detail: Label
var _learning_tab: Button
var _learning_view: VBoxContainer
var _learning_box: VBoxContainer
var _learning_summary: Label
var _system_tab: Button
var _system_view: VBoxContainer
var _system_box: VBoxContainer
var _system_summary: Label
var _bestiary_tab: Button
var _bestiary_view: VBoxContainer
var _bestiary_box: VBoxContainer
var _bestiary_summary: Label
var _grid: GridContainer
var _empty_label: Label
var _capacity_label: Label
var _input_hint: Label


func _ready() -> void:
	layer = 19   # under recall (20) and toast (21)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.inventory_changed.connect(_refresh)
	Bus.ability_loadout_changed.connect(_refresh)
	Bus.player_build_changed.connect(_refresh)
	Bus.crafting_changed.connect(func(_station): if _open: _refresh())
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	Bus.input_method_changed.connect(func(_method): _refresh_input_hint())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_menu"):
		# Never stack this menu over dialogue, combat, recall, shops, or another modal.
		if not _open and get_tree().paused:
			return
		_toggle()
		get_viewport().set_input_as_handled()
	# A domain key opens the hub straight onto that domain rather than making the
	# player land on the last tab and navigate — UI_UX_GUIDE section 4 puts opening
	# any domain at one layer. Pressing the same key again closes it, so the key is
	# a toggle for its own domain rather than a one-way trip.
	elif _domain_shortcut(event) != "":
		var domain := _domain_shortcut(event)
		if not _open and get_tree().paused:
			return
		if _open and _active_tab == domain:
			_set_open(false)
		else:
			open_at(domain)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("tab_previous"):
		_cycle_tab(-1)
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("tab_next"):
		_cycle_tab(1)
		get_viewport().set_input_as_handled()


## Which domain an input asks for, or "" when it is not a domain key. Journal is on
## L rather than the guide's J because J is this build's attack key.
func _domain_shortcut(event: InputEvent) -> String:
	if event.is_action_pressed("open_journal"):
		return TAB_QUESTS
	if event.is_action_pressed("open_map"):
		return TAB_MAP
	if event.is_action_pressed("open_skills"):
		return TAB_SKILLS
	if event.is_action_pressed("open_settings"):
		return TAB_SYSTEM
	return ""


func _cycle_tab(direction: int) -> void:
	var index := TAB_ORDER.find(_active_tab)
	if index < 0:
		index = TAB_ORDER.find(TAB_BAG)
	_set_tab(String(TAB_ORDER[posmod(index + signi(direction), TAB_ORDER.size())]))
	var button := _tab_button(_active_tab)
	if button != null:
		button.grab_focus()


func _refresh_input_hint() -> void:
	if _input_hint == null:
		return
	var close := InputHints.joined_labels(["open_menu", "ui_cancel"])
	_input_hint.text = "[%s]/[%s] tabs · [%s] close" % [
		InputHints.primary_label("tab_previous"), InputHints.primary_label("tab_next"), close] \
		if InputHints.is_gamepad() else "[%s] close" % close


## Open the hub with a specific domain already selected.
func open_at(tab: String) -> void:
	_active_tab = tab
	if _open:
		_refresh()
		_set_tab(tab)
	else:
		_set_open(true)


## The rail button for a domain, so focus can follow the domain the hub opened on
## rather than starting on Character and leaving the focus ring somewhere the player
## did not ask for.
func _tab_button(tab: String) -> Button:
	match tab:
		TAB_SKILLS: return _skills_tab
		TAB_BAG: return _bag_tab
		TAB_QUESTS: return _quests_tab
		TAB_MAP: return _map_tab
		TAB_LEARNING: return _learning_tab
		TAB_SYSTEM: return _system_tab
		TAB_BESTIARY: return _bestiary_tab
		_: return _character_tab


func _toggle() -> void:
	_set_open(not _open)


func _set_open(open: bool) -> void:
	_open = open
	if open:
		_refresh()
		_set_tab(_active_tab)
		_root.show()
		get_tree().paused = true
		_tab_button(_active_tab).grab_focus()
	else:
		_root.hide()
		get_tree().paused = false


# --- content ---------------------------------------------------------------

func _refresh() -> void:
	if _coins_label == null:
		return
	_coins_label.text = "%d coins" % Inv.coins

	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	for group_box in _equipment_group_boxes.values():
		for child in (group_box as Control).get_children():
			(group_box as Control).remove_child(child)
			child.queue_free()
	for child in _skills_box.get_children():
		_skills_box.remove_child(child)
		child.queue_free()
	for child in _quests_box.get_children():
		_quests_box.remove_child(child)
		child.queue_free()
	for child in _map_box.get_children():
		_map_box.remove_child(child)
		child.queue_free()
	for child in _learning_box.get_children():
		_learning_box.remove_child(child)
		child.queue_free()
	for child in _system_box.get_children():
		_system_box.remove_child(child)
		child.queue_free()
	for child in _bestiary_box.get_children():
		_bestiary_box.remove_child(child)
		child.queue_free()
	_refresh_quests()
	_refresh_map()
	_refresh_learning()
	_refresh_system()
	_refresh_bestiary()

	var equipped: Dictionary = Inv.equipment()
	for group in EQUIPMENT_GROUPS:
		var group_box: Control = _equipment_group_boxes[String(group[0])]
		for slot in group[1]:
			group_box.add_child(_make_equipment_slot_button(
				String(slot), String(equipped.get(slot, ""))))

	var xp := 0
	if Learning.profile != null:
		xp = int(Learning.profile.data.get("stats", {}).get("xp", 0))
	var allocations: Dictionary = Learning.allocations()
	var weapon_type := String(Inv.equipped_def("weapon").get("weaponType", ""))
	var stats := PlayerStats.from_xp(xp, Inv.equipped_defs(), allocations, weapon_type)
	var gear := PlayerStats.gear_bonus(Inv.equipped_defs(), int(stats["level"]))
	var player := get_tree().get_first_node_in_group("player")
	var current_hp := int(player.hp) if player != null else int(stats["max_hp"])
	var xp_progress := "MAX LEVEL - %d total XP" % int(stats["total_xp"]) \
		if bool(stats["at_level_cap"]) else "%d / %d" % [
			int(stats["xp_into_level"]), int(stats["xp_per_level"])]
	var role_def: Dictionary = stats["role_def"]
	_stats_label.text = (
		"Level %d\nLearning XP  %s\n%s - %s\n\n"
		+ "HP   %d / %d\nATK  %d   DEF  %d   SPD  %d\n\n"
		+ "Gear bonus  %+d HP   %+d ATK   %+d DEF   %+d SPD\n"
		+ "Japanese study raises your base stats; equipped gear is included above."
	) % [
		stats["level"], xp_progress, role_def.get("name", "Adventurer"),
		role_def.get("passive", ""),
		current_hp, stats["max_hp"], stats["atk"], stats["def"], stats["speed"],
		gear["hp"], gear["atk"], gear["def"], gear["spd"],
	]
	_attribute_points_label.text = "Attribute Points  %d" % Learning.unspent_attribute_points()
	for key in PlayerStats.ALLOCATION_KEYS:
		var amount := int(allocations.get(key, 0))
		(_attribute_value_labels[key] as Label).text = str(amount)
		(_attribute_minus_buttons[key] as Button).disabled = amount <= 0
		var plus := _attribute_plus_buttons[key] as Button
		plus.disabled = key not in PlayerStats.ACTIVE_ALLOCATION_KEYS \
			or Learning.unspent_attribute_points() <= 0

	var equipped_skills := Learning.equipped_ability_ids()
	_skills_summary.text = (
		"Active loadout  %d / %d  ·  Talent Points  %d\n"
		+ "Basic Attack is always available. Talent unlocks are permanent."
	) % [equipped_skills.size(), AbilityRules.MAX_SKILLS, Learning.unspent_talent_points()]
	_skills_box.add_child(_section_label("Life Skills - gather, refine, and cook"))
	for definition in LIFE_SKILLS:
		_skills_box.add_child(_make_life_skill_card(definition))
	# Starter actions stay separate from the permanent role Talent board below.
	_skills_box.add_child(_section_label("Core Actions"))
	for ability in Learning.known_ability_defs():
		if not bool(ability.get("starter", false)):
			continue
		_skills_box.add_child(_make_skill_card(ability, weapon_type,
			String(ability.get("id", "")) in equipped_skills))
	var active_role := Roles.role_for_weapon_type(weapon_type)
	_skills_box.add_child(_section_label(
		"Talent Board - active role: %s" % Roles.definition(active_role).get("name", "Adventurer")))
	for group in Learning.talent_groups(weapon_type):
		var role_id := String(group["role"])
		var board_heading := _section_label("%s%s - %s" % [
			String(group["role_def"].get("name", role_id.capitalize())),
			" (Active)" if role_id == active_role else "",
			String(group["role_def"].get("passive", ""))])
		board_heading.name = "TalentRole_" + role_id
		_skills_box.add_child(board_heading)
		for band in group["bands"]:
			var band_heading := _section_label("Levels %d-%d" % [
				int(band["start_level"]), int(band["end_level"])])
			band_heading.name = "TalentBand_%s_%d" % [role_id, int(band["start_level"])]
			_skills_box.add_child(band_heading)
			for state in band["states"]:
				_skills_box.add_child(_make_talent_card(state["ability"], state))

	var all_items: Array = Inv.entries()
	_refresh_prepared_meal()
	var items: Array = all_items.filter(_matches_bag_filter)
	# Sort by display name for a stable, human-friendly order (TS bag() did this).
	items.sort_custom(func(a, b): return _name_of(a["id"]).naturalnocasecmp_to(_name_of(b["id"])) < 0)

	_empty_label.visible = items.is_empty()
	_grid.visible = not items.is_empty()
	if items.is_empty():
		_empty_label.text = _bag_empty_message(all_items.is_empty())
	for entry in items:
		_grid.add_child(_make_card(String(entry["id"]), int(entry["qty"])))

	_refresh_footer()


func _set_tab(tab: String) -> void:
	_active_tab = tab if tab in [TAB_CHARACTER, TAB_SKILLS, TAB_BAG, TAB_QUESTS,
		TAB_MAP, TAB_LEARNING, TAB_SYSTEM, TAB_BESTIARY] else TAB_BAG
	_character_scroll.visible = _active_tab == TAB_CHARACTER
	_character_view.visible = _active_tab == TAB_CHARACTER
	_skills_view.visible = _active_tab == TAB_SKILLS
	_bag_view.visible = _active_tab == TAB_BAG
	_quests_view.visible = _active_tab == TAB_QUESTS
	_map_view.visible = _active_tab == TAB_MAP
	_learning_view.visible = _active_tab == TAB_LEARNING
	_system_view.visible = _active_tab == TAB_SYSTEM
	_bestiary_view.visible = _active_tab == TAB_BESTIARY
	_character_tab.disabled = _active_tab == TAB_CHARACTER
	_skills_tab.disabled = _active_tab == TAB_SKILLS
	_bag_tab.disabled = _active_tab == TAB_BAG
	_quests_tab.disabled = _active_tab == TAB_QUESTS
	_map_tab.disabled = _active_tab == TAB_MAP
	_learning_tab.disabled = _active_tab == TAB_LEARNING
	_system_tab.disabled = _active_tab == TAB_SYSTEM
	_bestiary_tab.disabled = _active_tab == TAB_BESTIARY
	_refresh_footer()


## The quest log. Until now a quest existed only as the one objective line, read
## off whichever giver stood in the current scene: finish it and it vanished,
## walk to another map and it vanished. This is the record of the whole run.
func _refresh_quests() -> void:
	Activities.reconcile(Learning.profile, DB, Inv)
	var raw_entries: Array = QuestJournal.all_entries(Learning.profile, DB, Inv)
	var entries: Array = Activities.quest_entries(Learning.profile, DB, Inv)
	var counts: Dictionary = QuestJournal.counts(raw_entries)
	var activities := Activities.structured_entries(Learning.profile, DB)
	var known: int = int(counts["ready"]) + int(counts["active"]) + int(counts["done"])
	if known == 0 and activities.is_empty():
		_quests_summary.text = "No quests yet — the villagers have work to offer."
	elif known == 0:
		_quests_summary.text = "%d structured mission%s available" % [
			activities.size(), "" if activities.size() == 1 else "s"]
	else:
		_quests_summary.text = "%d done   ·   %d in progress   ·   %d ready to turn in" % [
			counts["done"], counts["active"], counts["ready"]]
		if not activities.is_empty():
			_quests_summary.text += "   ·   %d mission%s" % [
				activities.size(), "" if activities.size() == 1 else "s"]

	for entry in entries:
		_quests_box.add_child(_make_quest_card(entry))
	# Say that there is more out there without naming it — a journal is a record of
	# the player's own run, not a table of contents for content they have not found.
	if int(counts["unmet"]) > 0:
		var more := Label.new()
		more.name = "QuestsUndiscovered"
		more.text = "%d more waiting to be found in the world." % counts["unmet"]
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", COL_HEADING)
		_quests_box.add_child(more)

	if not activities.is_empty():
		var heading := Label.new()
		heading.name = "StructuredMissionsHeading"
		heading.text = "Raids & Expeditions"
		heading.add_theme_font_size_override("font_size", 13)
		heading.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		_quests_box.add_child(heading)
		for activity in activities:
			_quests_box.add_child(_make_activity_card(activity))


## The Map domain. UI_UX_GUIDE section 6 wants literal local maps over LDtk truth
## eventually; there is no LDtk here and no discovered-cell fog yet, so this is the
## World layer only: the region graph the game actually has, showing where you are,
## what connects to what, and what is genuinely built versus still planned. It says
## "not built yet" rather than drawing a route that goes nowhere.
func _refresh_map() -> void:
	var here := _current_region_id()
	var open_count := 0
	for region_id in DB.regions:
		if String(DB.regions[region_id].get("status", "")) == "playable":
			open_count += 1
	_map_summary.text = "%d regions open · Gold: here · Green: playable · ?: charted, not built" % open_count
	_map_box.call("configure", DB.regions, here)


func _on_map_region_focused(region_id: String) -> void:
	var region: Dictionary = DB.regions.get(region_id, {})
	if region.is_empty() or _map_detail == null:
		return
	var links: Array[String] = []
	for connected in region.get("connects", []):
		var other: Dictionary = DB.regions.get(String(connected), {})
		links.append(String(other.get("name", connected)))
	var state := "Open route" if String(region.get("status", "")) == "playable" \
		else "Charted · not built yet"
	if region_id == _current_region_id():
		state = "You are here"
	_map_detail.text = "%s · %s · Lv %d-%d\n%s · Connects to %s" % [
		region.get("name", region_id), state,
		int(region.get("minLevel", 1)), int(region.get("maxLevel", 1)),
		region.get("note", "No field notes yet."),
		", ".join(links) if not links.is_empty() else "nowhere yet"]


## Which region the player is standing in, matched by the running scene rather than
## stored state, so it cannot drift out of sync with where they actually are.
func _current_region_id() -> String:
	var scene := get_tree().current_scene
	return _region_for_scene(scene.scene_file_path) if scene != null else ""


## Interiors and structured instances inherit the region whose route contains
## them, so opening the world map indoors never loses the "you are here" anchor.
func _region_for_scene(scene_path: String) -> String:
	match scene_path:
		"res://src/scenes/world.tscn": return "valley_crossroads"
		"res://src/scenes/interior_house.tscn": return "valley_crossroads"
		"res://src/scenes/wilds.tscn": return "whispering_woods"
		"res://src/scenes/expedition_forest.tscn": return "whispering_woods"
		"res://src/scenes/mountain_pass.tscn": return "mountain_pass"
	return ""


## The Learning domain. The notebook is the collection of everything known; this is
## the other half of UI_UX_GUIDE section 4 — daily review and weak areas, the "what
## should I study now" question, answered in one layer with a session you can start
## from here rather than having to find a teacher first.
func _refresh_learning() -> void:
	var due := Learning.due_count() if Learning.progression != null else 0
	var known := 0
	if Learning.profile != null:
		known = Learning.profile.unlocked_cards().size()
	_learning_summary.text = "%d word%s ready to review   ·   %d learned" % [
		due, "" if due == 1 else "s", known]

	var review := Button.new()
	review.name = "ReviewNow"
	review.text = "Review %d now" % due if due > 0 else "Nothing due — practise anyway"
	review.focus_mode = Control.FOCUS_ALL
	review.custom_minimum_size = Vector2(0, 30)
	review.pressed.connect(_on_review_pressed)
	_learning_box.add_child(review)

	# Weak areas, by category: where the schedule is actually behind.
	var by_category := _due_by_category()
	if by_category.is_empty():
		var none := Label.new()
		none.name = "LearningEmpty"
		none.text = "Nothing learned yet. The villagers teach the first words."
		none.add_theme_font_size_override("font_size", 11)
		none.add_theme_color_override("font_color", COL_HEADING)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_learning_box.add_child(none)
		return
	for category in by_category:
		_learning_box.add_child(_make_category_row(String(category), by_category[category]))


func _on_review_pressed() -> void:
	_set_open(false)
	# A prepared session, per the guide's "HUD due cue opens a prepared session".
	Bus.learn_open.emit("", 5, true)


## Due and known counts per lesson category, for the categories the player has
## actually started. Categories they have never touched are not weak areas.
func _due_by_category() -> Dictionary:
	var out := {}
	if Learning.profile == null:
		return out
	for lesson_id in DB.lesson_order:
		var lesson: Dictionary = DB.lessons[lesson_id]
		var category := String(lesson.get("category", ""))
		if category.is_empty():
			continue
		for card_id in lesson.get("cardIds", []):
			var card: Dictionary = Learning.profile.card(card_id)
			if card.is_empty() or not card.get("unlocked", false):
				continue
			if not LearningProgression.recall_eligible(card):
				continue
			if not out.has(category):
				out[category] = {"known": 0, "due": 0}
			out[category]["known"] += 1
			if Srs.is_due(card):
				out[category]["due"] += 1
	return out


func _make_category_row(category: String, counts: Dictionary) -> Control:
	var due := int(counts["due"])
	var row := PanelContainer.new()
	row.name = "Category_" + category
	row.add_theme_stylebox_override("panel",
		_card_style(UiTheme.ACCENT_GOLD if due > 0 else COL_CARD_BORDER))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)

	var title := Label.new()
	title.text = category.capitalize()
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", COL_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(title)

	var state := Label.new()
	state.name = "CategoryDue_" + category
	state.text = "%d due of %d" % [due, int(counts["known"])] if due > 0 		else "%d learned" % int(counts["known"])
	state.add_theme_font_size_override("font_size", 11)
	state.add_theme_color_override("font_color",
		UiTheme.ACCENT_GOLD if due > 0 else UiTheme.TEXT_MUTED)
	line.add_child(state)
	return row


## The System domain. UI_UX_GUIDE section 4 puts settings, help and save under
## System inside the hub; they used to live in a separate panel, which meant two
## places to look for the same four controls. Only settings that actually do
## something are shown here — the accessibility set in section 15 is real work,
## not a row of switches that lie.
func _refresh_system() -> void:
	_system_summary.text = "Display, language help, and sound"

	# Sits above camera zoom because the two are easy to confuse: this one resizes
	# text and menus only, that one moves the world camera.
	_system_box.add_child(_make_setting_choice(
		"UiScale", "UI size",
		Settings.UI_SCALES.map(func(s: float) -> String: return "%d%%" % int(round(s * 100.0))),
		maxi(0, Settings.UI_SCALES.find(Settings.ui_scale)),
		"Scales menus, HUD, and text. Larger sizes make text easier to read but fit "
		+ "less on screen at once. The world view is unaffected — use Camera zoom for that.",
		func(index: int) -> void: Settings.ui_scale = Settings.UI_SCALES[index]))

	_system_box.add_child(_make_setting_slider(
		"ZoomSlider", "Camera zoom", Settings.zoom,
		Settings.ZOOM_MIN, Settings.ZOOM_MAX, Settings.ZOOM_STEP,
		func(value: float) -> void: Settings.zoom = value,
		func(value: float) -> String:
			if is_equal_approx(value, Settings.ZOOM_DEFAULT):
				return "x%.1f  (default)" % value
			return "x%.1f  (%s)" % [value, "closer in" if value > Settings.ZOOM_DEFAULT
				else "further out"]))

	_system_box.add_child(_make_setting_choice(
		"TranslationMode", "English meanings",
		Settings.TRANSLATION_LABELS, Settings.translation_mode,
		"Hidden keeps English off entirely. On request reveals it while you hold the "
		+ "peek key. After attempt shows it once you have answered. Always keeps it on.",
		func(index: int) -> void: Settings.translation_mode = index))

	_system_box.add_child(_make_setting_choice(
		"FuriganaMode", "Reading over Japanese",
		Settings.FURIGANA_LABELS, Settings.furigana_mode,
		"While learning shows the reading only until a word is answered correctly "
		+ "%d times, so the help fades as you learn it." % Settings.FURIGANA_NEW_THRESHOLD,
		func(index: int) -> void: Settings.furigana_mode = index))

	_system_box.add_child(_make_setting_slider(
		"MusicVolumeSlider", "Music", Settings.music_volume, 0.0, 1.0, 0.05,
		func(value: float) -> void: Settings.music_volume = value,
		func(value: float) -> String: return "%d%%" % int(round(value * 100.0))))
	_system_box.add_child(_make_setting_slider(
		"VoiceVolumeSlider", "Pronunciation", Settings.voice_volume, 0.0, 1.0, 0.05,
		func(value: float) -> void: Settings.voice_volume = value,
		func(value: float) -> String: return "%d%%" % int(round(value * 100.0))))

	var save_now := Button.new()
	save_now.name = "SaveNow"
	save_now.text = "Save progress now"
	save_now.focus_mode = Control.FOCUS_ALL
	save_now.custom_minimum_size = Vector2(0, 28)
	save_now.pressed.connect(_on_save_now)
	_system_box.add_child(save_now)


## One cycling option row: a label and a button that steps through named choices.
## A cycler rather than a dropdown because it is one control to reach on a pad and
## the option lists here are short.
func _make_setting_choice(control_name: String, label: String, labels: Array,
		value: int, tooltip: String, apply: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var caption := Label.new()
	caption.text = label
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", COL_TEXT)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)

	var button := Button.new()
	button.name = control_name
	button.text = String(labels[clampi(value, 0, labels.size() - 1)])
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(120, 24)
	var index := {"value": clampi(value, 0, labels.size() - 1)}
	button.pressed.connect(func() -> void:
		index["value"] = (int(index["value"]) + 1) % labels.size()
		button.text = String(labels[index["value"]])
		apply.call(int(index["value"])))
	row.add_child(button)
	return row


func _on_save_now() -> void:
	if Learning.profile != null:
		Learning.profile.save()
	Bus.toast.emit("Progress saved.")


## One labelled slider row. `format` turns the value into the text beside the label,
## so a percentage and a zoom factor can share the same control.
func _make_setting_slider(slider_name: String, label: String, value: float,
		minimum: float, maximum: float, step: float,
		apply: Callable, format: Callable) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var caption := Label.new()
	caption.name = slider_name + "Label"
	caption.add_theme_font_size_override("font_size", 12)
	caption.add_theme_color_override("font_color", COL_TEXT)
	caption.text = "%s:  %s" % [label, format.call(value)]
	row.add_child(caption)

	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(0, 18)
	slider.focus_mode = Control.FOCUS_ALL
	slider.set_value_no_signal(value)
	slider.value_changed.connect(func(changed: float) -> void:
		apply.call(changed)
		caption.text = "%s:  %s" % [label, format.call(changed)])
	row.add_child(slider)
	return row


## The Bestiary. Mentioned in PORT_NOTES.md and COMBAT_DESIGN.md as a Compendium
## tab and "bestiary flags" from the legacy build, but neither ever made it into
## this port — there was no way to answer "what have I fought" at all. A foe
## appears the instant you fight it, win or lose; the rest of the 76-strong roster
## stays "???" rather than spoiling regions that are not built yet.
func _refresh_bestiary() -> void:
	var entries: Array = Bestiary.all_entries(Learning.profile, DB)
	var counts: Dictionary = Bestiary.counts(entries)
	var known: int = int(counts["seen"]) + int(counts["defeated"])
	if known == 0:
		_bestiary_summary.text = "Nothing fought yet. The world will not stay quiet."
	else:
		_bestiary_summary.text = "%d defeated   ·   %d encountered   ·   %d still unknown" % [
			counts["defeated"], counts["seen"], counts["unseen"]]

	for entry in entries:
		if Bestiary.is_spoiler(entry):
			continue
		_bestiary_box.add_child(_make_bestiary_card(entry))
	if int(counts["unseen"]) > 0:
		var more := Label.new()
		more.name = "BestiaryUndiscovered"
		more.text = "%d more creature%s out there, unfought." % [
			counts["unseen"], "" if int(counts["unseen"]) == 1 else "s"]
		more.add_theme_font_size_override("font_size", 11)
		more.add_theme_color_override("font_color", COL_HEADING)
		_bestiary_box.add_child(more)


func _make_bestiary_card(entry: Dictionary) -> Control:
	var stage: int = int(entry["stage"])
	var accent := UiTheme.STATE_SUCCESS if stage == Bestiary.Stage.DEFEATED else COL_HEADING

	var card := PanelContainer.new()
	card.name = "BestiaryCard_" + String(entry["id"])
	card.add_theme_stylebox_override("panel", _card_style(accent))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)

	var portrait := _bestiary_portrait(String(entry["id"]))
	if portrait != null:
		row.add_child(portrait)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)
	var title := Label.new()
	title.name = "BestiaryName_" + String(entry["id"])
	title.text = "%s  ·  Lv %d" % [String(entry["name"]), int(entry["level"])]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var state := Label.new()
	state.name = "BestiaryStage_" + String(entry["id"])
	var kills := int(entry["kills"])
	state.text = "%s x%d" % [Bestiary.stage_label(stage), kills] if kills > 0 \
		else Bestiary.stage_label(stage)
	state.add_theme_font_size_override("font_size", 11)
	state.add_theme_color_override("font_color", accent)
	header.add_child(state)

	# Drops are only listed once beaten. Combat already reveals what actually
	# rolled via a toast; this is the full authored table, which is real data —
	# not more than the player has effectively already been shown one roll of.
	if stage == Bestiary.Stage.DEFEATED:
		var names: Array[String] = []
		for drop in entry["drops"]:
			names.append(_name_of(String(drop.get("item", ""))))
		if not names.is_empty():
			var drops := Label.new()
			drops.name = "BestiaryDrops_" + String(entry["id"])
			drops.text = "Drops: " + ", ".join(names)
			drops.add_theme_font_size_override("font_size", 10)
			drops.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
			drops.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(drops)
	else:
		var stats := Label.new()
		stats.text = "HP %d   ATK %d   DEF %d" % [
			int(entry["max_hp"]), int(entry["atk"]), int(entry["def"])]
		stats.add_theme_font_size_override("font_size", 10)
		stats.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		box.add_child(stats)
	return card


## A still portrait from the enemy's own walk sheet, honoring `spriteAlias` the
## same way item icons honor `iconAlias` — the JSON `sprite` field is inherited
## from the source asset pack's naming and does not resolve for most entries.
## Returns null rather than a placeholder when no real art exists for this foe,
## since most of the 76-strong roster belongs to a region that is not built yet.
func _bestiary_portrait(enemy_id: String) -> Control:
	var enemy: Dictionary = DB.enemy(enemy_id)
	var sprite_id := String(enemy.get("spriteAlias", enemy.get("sprite", "")))
	var path := "res://assets/sprites/%s.png" % sprite_id
	if sprite_id.is_empty() or not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	if texture == null:
		return null
	var portrait := TextureRect.new()
	portrait.name = "BestiaryPortrait_" + enemy_id
	portrait.texture = SpriteSheets.portrait(texture)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.custom_minimum_size = Vector2(40, 40)
	return portrait


func _make_quest_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "QuestCard_" + String(entry["id"])
	var stage: int = int(entry["stage_code"])
	var accent := COL_HEADING
	if stage == QuestJournal.Stage.READY:
		accent = UiTheme.STATE_SUCCESS
	elif stage == QuestJournal.Stage.DONE:
		accent = UiTheme.TEXT_MUTED
	card.add_theme_stylebox_override("panel", _card_style(accent))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title := Label.new()
	title.name = "QuestTitle_" + String(entry["id"])
	title.text = String(entry["title"])
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var state := Label.new()
	state.name = "QuestStage_" + String(entry["id"])
	state.text = String(entry["state"])
	state.add_theme_font_size_override("font_size", 11)
	state.add_theme_color_override("font_color", accent)
	header.add_child(state)
	var track_button := _make_track_button(entry)
	if track_button != null:
		header.add_child(track_button)

	# What to actually do next, which the title alone never says.
	var detail := Label.new()
	detail.name = "QuestDetail_" + String(entry["id"])
	detail.text = String(entry["detail"])
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	if not String(entry["reward"]).is_empty():
		var reward := Label.new()
		reward.name = "QuestReward_" + String(entry["id"])
		reward.text = String(entry["reward"])
		reward.add_theme_font_size_override("font_size", 11)
		reward.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
		reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(reward)
	return card


func _make_activity_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.name = "ActivityCard_" + String(entry["id"])
	var stage := String(entry["stage"])
	var accent := UiTheme.ACCENT_GOLD
	if stage == "available" or stage == "recall-cleared":
		accent = UiTheme.STATE_SUCCESS
	elif stage == "complete":
		accent = UiTheme.TEXT_MUTED
	card.add_theme_stylebox_override("panel", _card_style(accent))

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title := Label.new()
	title.name = "ActivityTitle_" + String(entry["id"])
	title.text = "%s · %s" % [entry["kind"], entry["title"]]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", accent)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var state := Label.new()
	state.name = "ActivityStage_" + String(entry["id"])
	state.text = String(entry["state"])
	state.add_theme_font_size_override("font_size", 11)
	state.add_theme_color_override("font_color", accent)
	header.add_child(state)
	var track_button := _make_track_button(entry)
	if track_button != null:
		header.add_child(track_button)

	var detail := Label.new()
	detail.name = "ActivityDetail_" + String(entry["id"])
	detail.text = String(entry["detail"])
	detail.add_theme_font_size_override("font_size", 11)
	detail.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)

	var reward := Label.new()
	reward.name = "ActivityReward_" + String(entry["id"])
	reward.text = String(entry["reward"])
	reward.add_theme_font_size_override("font_size", 11)
	reward.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(reward)
	return card


func _make_track_button(entry: Dictionary) -> Button:
	if not bool(entry.get("trackable", false)):
		return null
	var key := String(entry.get("key", ""))
	var selected := Activities.tracked_key(Learning.profile) == key
	var button := Button.new()
	button.name = "TrackActivity_" + key.replace(":", "_")
	button.text = "Tracked" if selected else "Track"
	button.tooltip_text = "This activity leads the world HUD." if selected \
		else "Show this activity on the world HUD."
	button.disabled = selected
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(58, 24)
	button.add_theme_font_size_override("font_size", 10)
	if not selected:
		button.pressed.connect(_track_activity.bind(key))
	return button


func _track_activity(key: String) -> void:
	if Activities.track(Learning.profile, DB, Inv, key):
		Bus.activity_tracking_changed.emit(key)
		Bus.hud_refresh.emit()
		_refresh()


func _refresh_footer() -> void:
	if _capacity_label == null:
		return
	if _active_tab == TAB_CHARACTER:
		_capacity_label.text = "SPD* is authored but not active in the current combat loop yet."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_SKILLS:
		_capacity_label.text = "Choose an action in combat, then answer with the matching rune."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_QUESTS:
		_capacity_label.text = "Choose Track to lead the world HUD. All activity progress saves here."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_MAP:
		_capacity_label.text = "Regions you have not reached yet are named but not detailed."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_LEARNING:
		_capacity_label.text = "Your notebook (N) lists every word; this is what to study next."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_SYSTEM:
		_capacity_label.text = "Settings save as you change them. Progress saves on its own."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_BESTIARY:
		_capacity_label.text = "A foe appears here the moment you fight it, win or lose."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	else:
		var enc: Dictionary = Inv.encumbrance()
		_capacity_label.text = "Carrying %d / %d" % [enc["units"], enc["cap"]]
		_capacity_label.add_theme_color_override("font_color",
			COL_WARN if enc["encumbered"] else COL_HEADING)


func _make_card(id: String, qty: int) -> Control:
	var def: Dictionary = DB.item(id)
	var card := PanelContainer.new()
	card.name = "ItemCard_" + id
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(104, 116)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	vbox.add_child(_icon_node(id))

	var name_label := Label.new()
	name_label.text = String(def.get("name", id))
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color",
		KIND_COLORS.get(String(def.get("kind", "")), COL_TEXT))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(88, 0)
	vbox.add_child(name_label)

	# Quantity and the favorite toggle share one row: every card here is already
	# tight on vertical space (gear cards also carry stats, a comparison line, and
	# an Equip button), and this is the one row with room to spare next to it.
	var qty_row := HBoxContainer.new()
	qty_row.alignment = BoxContainer.ALIGNMENT_CENTER
	qty_row.add_theme_constant_override("separation", 4)
	vbox.add_child(qty_row)

	var qty_label := Label.new()
	qty_label.text = "x%d" % qty
	qty_label.add_theme_font_size_override("font_size", 12)
	qty_label.add_theme_color_override("font_color", COL_HEADING)
	qty_row.add_child(qty_label)

	var favorited := Inv.is_favorite(id)
	var favorite_btn := Button.new()
	favorite_btn.name = "FavoriteToggle_" + id
	favorite_btn.text = "Unfav" if favorited else "Fav"
	favorite_btn.tooltip_text = "Remove from Favorites" if favorited \
		else "Add to Favorites — always easy to find, even filtered out."
	favorite_btn.toggle_mode = true
	favorite_btn.button_pressed = favorited
	favorite_btn.focus_mode = Control.FOCUS_ALL
	favorite_btn.add_theme_font_size_override("font_size", 9)
	favorite_btn.custom_minimum_size = Vector2(0, 18)
	if favorited:
		favorite_btn.add_theme_color_override("font_color", UiTheme.ACCENT_GOLD)
	favorite_btn.pressed.connect(_on_toggle_favorite.bind(id))
	qty_row.add_child(favorite_btn)

	if def.get("kind", "") == "gear":
		var stats_label := Label.new()
		stats_label.name = "ItemStats_" + id
		stats_label.text = _stats_line(PlayerStats.scaled_item_stats(def, _player_level()))
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.add_theme_color_override("font_color", COL_TEXT)
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stats_label)

		# What equipping this would actually change, against whatever is in that slot
		# now. UI_UX_GUIDE section 9: show the changed stats first, and never let
		# comparing alter state. Absent when nothing would change, so the card does
		# not carry a row that says nothing.
		var change_label := Label.new()
		change_label.name = "ItemCompare_" + id
		change_label.text = _comparison_line(def)
		# With an empty slot the delta is just the item's own stats, so the card would
		# print the same numbers twice. Cards are 88px wide and every row costs the
		# Equip button screen space; say it once.
		if change_label.text == stats_label.text:
			change_label.text = ""
		change_label.visible = not change_label.text.is_empty()
		change_label.add_theme_font_size_override("font_size", 10)
		change_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		change_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		change_label.add_theme_color_override("font_color", UiTheme.STATE_INFO)
		change_label.tooltip_text = _comparison_tooltip(def)
		vbox.add_child(change_label)

		var equip_button := Button.new()
		var required_level := int(def.get("requiredLevel", 1))
		equip_button.text = "Equip" if required_level <= _player_level() \
			else "Lv %d" % required_level
		equip_button.disabled = required_level > _player_level()
		equip_button.focus_mode = Control.FOCUS_ALL
		equip_button.pressed.connect(_on_equip.bind(id))
		vbox.add_child(equip_button)
	elif ConsumableRules.is_preparation_meal(def):
		var meal_label := Label.new()
		meal_label.text = "Prepare · Restores %d HP" % int(def.get("heal", 0))
		meal_label.tooltip_text = "Reserve one for battle. Only one meal can be prepared."
		meal_label.add_theme_font_size_override("font_size", 9)
		meal_label.add_theme_color_override("font_color", COL_TEXT)
		meal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(meal_label)

		var prepare_button := Button.new()
		prepare_button.name = "PrepareMeal_" + id
		prepare_button.text = "Prepared" if Inv.prepared_meal_id() == id else "Prepare"
		prepare_button.disabled = Inv.prepared_meal_id() == id
		prepare_button.tooltip_text = "Already reserved for the next fight." \
			if prepare_button.disabled else "Move one into your prepared-meal slot."
		prepare_button.focus_mode = Control.FOCUS_ALL
		prepare_button.pressed.connect(_on_prepare_meal.bind(id))
		vbox.add_child(prepare_button)
	elif ConsumableRules.is_supported_healing(def):
		var heal_label := Label.new()
		heal_label.text = "Restores %d HP" % int(def.get("heal", 0))
		heal_label.add_theme_font_size_override("font_size", 10)
		heal_label.add_theme_color_override("font_color", COL_TEXT)
		heal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(heal_label)

		var use_button := Button.new()
		use_button.text = "Use"
		use_button.focus_mode = Control.FOCUS_ALL
		var player := get_tree().get_first_node_in_group("player")
		use_button.disabled = player == null or int(player.hp) >= int(player.MAX_HP)
		use_button.tooltip_text = "HP is already full." if use_button.disabled \
			else "Consume one now."
		use_button.pressed.connect(_on_use_healing.bind(id))
		vbox.add_child(use_button)
	elif ConsumableRules.is_supported_energy(def):
		var energy_label := Label.new()
		energy_label.text = "Combat only · Restores %d Energy" % int(def.get("buffValue", 0))
		energy_label.tooltip_text = "Use during your turn after spending Energy."
		energy_label.add_theme_font_size_override("font_size", 9)
		energy_label.add_theme_color_override("font_color", COL_TEXT)
		energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		energy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(energy_label)
	elif ConsumableRules.is_supported_combat_item(def):
		var combat_label := Label.new()
		combat_label.text = "Combat only · %s" % ConsumableRules.effect_summary(def)
		combat_label.tooltip_text = "Use during your turn; limited to one item per turn."
		combat_label.add_theme_font_size_override("font_size", 9)
		combat_label.add_theme_color_override("font_color", COL_TEXT)
		combat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		combat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(combat_label)
	elif def.get("kind", "") == "consumable":
		var later_label := Label.new()
		later_label.text = "Effect not active yet"
		later_label.tooltip_text = "Attack items stay stored until their damage effect is implemented."
		later_label.add_theme_font_size_override("font_size", 9)
		later_label.add_theme_color_override("font_color", COL_HEADING)
		later_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		later_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(later_label)

	return card


## The stat delta from equipping `def` over whatever occupies its slot right now,
## written as "+2 ATK, -1 SPD". Empty when nothing would change or the item is
## already equipped, so a card only carries the line when it has something to say.
##
## Compared at the player's current level, because gear stats scale — an unscaled
## comparison would quietly promise the wrong numbers.
func _comparison_line(def: Dictionary) -> String:
	var slot := String(def.get("slot", ""))
	if slot.is_empty():
		return ""
	var equipped_id := String(Inv.equipment().get(slot, ""))
	if equipped_id == String(def.get("id", "")):
		return "Equipped"
	var level := _player_level()
	var incoming: Dictionary = PlayerStats.scaled_item_stats(def, level)
	var current: Dictionary = {}
	if not equipped_id.is_empty():
		current = PlayerStats.scaled_item_stats(DB.item(equipped_id), level)

	var parts: Array[String] = []
	for stat in ["hp", "atk", "def", "spd"]:
		var delta := int(incoming.get(stat, 0)) - int(current.get(stat, 0))
		if delta != 0:
			parts.append("%+d %s" % [delta, stat.to_upper()])
	if parts.is_empty():
		return "No change" if not equipped_id.is_empty() else ""
	# Deltas only. A bag card is 88px wide and "vs Wooden Katana" ran straight off
	# the edge; what is being compared against goes in the tooltip instead.
	return ", ".join(parts)


## The long form of the comparison, for the card's tooltip: which item the deltas
## are measured against, spelled out.
func _comparison_tooltip(def: Dictionary) -> String:
	var slot := String(def.get("slot", ""))
	if slot.is_empty():
		return ""
	var equipped_id := String(Inv.equipment().get(slot, ""))
	if equipped_id.is_empty():
		return "Nothing equipped in the %s slot." % slot
	if equipped_id == String(def.get("id", "")):
		return "You are already wearing one of these."
	return "Compared with %s, currently equipped." % String(
		DB.item(equipped_id).get("name", equipped_id))


func _make_equipment_slot_button(slot: String, item_id: String) -> Button:
	var button := Button.new()
	button.name = "EquipSlot_" + slot
	button.custom_minimum_size = Vector2(150, 34)
	button.focus_mode = Control.FOCUS_ALL
	if item_id.is_empty():
		button.text = "%s: —" % slot.capitalize()
		button.tooltip_text = "Empty %s slot." % slot
		button.disabled = true
	else:
		var item: Dictionary = DB.item(item_id)
		button.text = "%s: %s" % [slot.capitalize(), item.get("name", item_id)]
		# Weapon type/handedness is real, complete data for every one of the 36
		# weapons (it already gates which Talents work) — unlike armorType, which
		# only six pieces across the whole game bother to set, so showing it for
		# the rest would look like a broken field rather than an absent one.
		var kind_line := ""
		if slot == "weapon":
			var weapon_type := String(item.get("weaponType", ""))
			var handedness := String(item.get("handedness", ""))
			if not weapon_type.is_empty():
				kind_line = "%s · %s\n" % [
					weapon_type.capitalize(),
					"2-handed" if handedness == "2h" else "1-handed"]
		button.tooltip_text = "%s%s\n%s\nPress to unequip." % [
			kind_line,
			_stats_line(PlayerStats.scaled_item_stats(item, _player_level())),
			item.get("desc", "")]
		button.pressed.connect(_on_unequip.bind(slot, item_id))
	return button


func _make_skill_card(ability: Dictionary, weapon_type: String, equipped: bool) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(0, 58)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var text := VBoxContainer.new()
	var icon := _verified_ability_icon(String(ability.get("id", "")))
	if icon != null:
		row.add_child(icon)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	var required := String(ability.get("requiredWeaponType", ""))
	var weapon_ok := AbilityRules.weapon_matches(ability, weapon_type)
	var state := ""
	if equipped:
		state = "  ·  Equipped" if weapon_ok else "  ·  Equipped, inactive without %s" % required
	title.text = "%s  ·  %s  ·  %dE%s" % [
		ability.get("name", ability.get("id", "Skill")),
		_ability_effect_text(ability), CombatEncounter.action_cost(ability), state]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COL_TEXT)
	text.add_child(title)
	var detail := Label.new()
	detail.name = "SkillDetail_" + String(ability.get("id", ""))
	var requirement := "Any weapon" if required.is_empty() else "%s weapon" % required.capitalize()
	var cadence := _ability_cadence(ability)
	detail.text = "%s%s  ·  %s" % [requirement,
		"  ·  " + cadence if not cadence.is_empty() else "", ability.get("desc", "")]
	detail.add_theme_font_size_override("font_size", 10)
	detail.add_theme_color_override("font_color", COL_HEADING)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(0, 24)
	text.add_child(detail)

	var button := Button.new()
	button.custom_minimum_size = Vector2(82, 32)
	button.focus_mode = Control.FOCUS_ALL
	var supported := AbilityRules.is_runtime_supported(ability)
	if equipped:
		button.text = "Remove"
		button.pressed.connect(_on_skill_toggle.bind(String(ability.get("id", "")), false))
	elif not supported:
		button.text = "Later"
		button.disabled = true
		button.tooltip_text = "This effect is authored but is not resolved by the current combat engine."
	elif not weapon_ok:
		button.text = "Needs %s" % required.capitalize()
		button.disabled = true
	elif Learning.equipped_ability_ids().size() >= AbilityRules.MAX_SKILLS:
		button.text = "Full"
		button.disabled = true
	else:
		button.text = "Equip"
		button.pressed.connect(_on_skill_toggle.bind(String(ability.get("id", "")), true))
	row.add_child(button)
	return card


func _make_life_skill_card(definition: Dictionary) -> Control:
	var station := String(definition.get("station", ""))
	var state := CraftingLogic.ensure_state(Learning.profile.data)
	var total_xp := int(state["xp"].get(station, 0))
	var level := CraftingLogic.level_from_xp(total_xp)
	var at_cap := level >= CraftingLogic.MAX_LEVEL
	var level_start := CraftingLogic.xp_for_level(level)
	var next_total := CraftingLogic.xp_for_level(level + 1) if not at_cap else total_xp
	var into_level := maxi(0, total_xp - level_start)
	var level_span := maxi(1, next_total - level_start)

	var card := PanelContainer.new()
	card.name = "LifeSkill_" + station
	card.add_theme_stylebox_override("panel", _card_style(UiTheme.STATE_SUCCESS))
	card.custom_minimum_size = Vector2(0, 76)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)

	var title := Label.new()
	title.name = "LifeSkillTitle_" + station
	title.text = "%s  ·  Level %d" % [definition.get("name", station.capitalize()), level]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", UiTheme.STATE_SUCCESS)
	box.add_child(title)

	var progress_text := Label.new()
	progress_text.name = "LifeSkillDetail_" + station
	progress_text.text = "Mastery level reached." if at_cap else "%d / %d XP to Level %d" % [
		into_level, level_span, level + 1]
	progress_text.add_theme_font_size_override("font_size", 10)
	progress_text.add_theme_color_override("font_color", COL_TEXT)
	box.add_child(progress_text)

	var progress := ProgressBar.new()
	progress.name = "LifeSkillProgress_" + station
	progress.min_value = 0.0
	progress.max_value = float(level_span)
	progress.value = float(level_span if at_cap else into_level)
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 6)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var empty_style := StyleBoxFlat.new()
	empty_style.bg_color = UiTheme.SURFACE_DEEP
	empty_style.set_corner_radius_all(3)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = UiTheme.STATE_SUCCESS
	fill_style.set_corner_radius_all(3)
	progress.add_theme_stylebox_override("background", empty_style)
	progress.add_theme_stylebox_override("fill", fill_style)
	box.add_child(progress)

	var loop := Label.new()
	loop.name = "LifeSkillLoop_" + station
	loop.text = "%s  %s" % [definition.get("loop", ""), definition.get("weather", "")]
	loop.add_theme_font_size_override("font_size", 10)
	loop.add_theme_color_override("font_color", COL_HEADING)
	loop.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(loop)
	return card


func _make_talent_card(ability: Dictionary, talent_data: Dictionary = {}) -> Control:
	if talent_data.is_empty():
		var weapon_type := String(Inv.equipped_def("weapon").get("weaponType", ""))
		talent_data = AbilityRules.talent_state(
			ability, _player_level(), Learning.profile.build(), DB.abilities, weapon_type)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _card_style())
	card.custom_minimum_size = Vector2(0, 54)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 7)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var text := VBoxContainer.new()
	var icon := _verified_ability_icon(String(ability.get("id", "")))
	if icon != null:
		row.add_child(icon)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var title := Label.new()
	var role := String(ability.get("role", "adventurer")).capitalize()
	var cost := int(ability.get("spCost", 0))
	title.text = "%s  ·  %s  ·  %d TP" % [ability.get("name", "Talent"), role, cost]
	title.name = "TalentState_" + String(ability.get("id", ""))
	title.text += " - " + _talent_state_label(talent_data)
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COL_TEXT)
	text.add_child(title)
	var detail := Label.new()
	var required := String(ability.get("requiredWeaponType", ""))
	detail.name = "TalentDetail_" + String(ability.get("id", ""))
	var hits := maxi(1, int(ability.get("hits", 1)))
	var effect := _ability_effect_text(ability)
	if hits > 1:
		effect += " x%d hits" % hits
	effect += "  ·  %dE" % CombatEncounter.action_cost(ability)
	var cadence := _ability_cadence(ability)
	if not cadence.is_empty():
		effect += "  ·  " + cadence
	detail.text = "%s weapon  ·  %s  ·  %s" % [
		required.capitalize(), effect, ability.get("desc", "")]
	detail.add_theme_font_size_override("font_size", 10)
	detail.add_theme_color_override("font_color", COL_HEADING)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(detail)
	var button := Button.new()
	var ability_id := String(ability.get("id", ""))
	var known := bool(talent_data.get("known", false))
	var equipped := bool(talent_data.get("equipped", false))
	button.name = ("TalentToggle_" if known else "TalentUnlock_") + ability_id
	button.custom_minimum_size = Vector2(76, 32)
	button.focus_mode = Control.FOCUS_ALL
	var required_level := int(ability.get("requiredLevel", 1))
	var ownership_state := String(talent_data.get("ownership_state", "unsupported"))
	if known and equipped:
		button.text = "Remove"
		button.pressed.connect(_on_skill_toggle.bind(ability_id, false))
	elif known and not bool(talent_data.get("runtime_supported", false)):
		button.text = "Later"
		button.disabled = true
		button.tooltip_text = "This legacy Talent remains known but is not combat-ready yet."
	elif known and not bool(talent_data.get("weapon_ready", false)):
		var needed_weapon := required
		if needed_weapon.is_empty():
			needed_weapon = String(Roles.definition(String(talent_data.get("role", ""))).get(
				"weapon_type", ""))
		button.text = "Needs %s" % needed_weapon.capitalize()
		button.disabled = true
		button.tooltip_text = "Equip the matching role weapon to use this Talent."
	elif known and Learning.equipped_ability_ids().size() >= AbilityRules.MAX_SKILLS:
		button.text = "Full"
		button.disabled = true
	elif known:
		button.text = "Equip"
		button.pressed.connect(_on_skill_toggle.bind(ability_id, true))
	elif ownership_state == "level_locked":
		button.text = "Lv %d" % required_level
		button.disabled = true
		button.tooltip_text = "Reach level %d to unlock this Talent." % required_level
	elif ownership_state == "points_locked":
		button.text = "Need %d TP" % cost
		button.disabled = true
		button.tooltip_text = "Earn Talent Points by gaining levels."
	elif ownership_state == "available":
		button.text = "Unlock"
		button.tooltip_text = "Permanently learn this action."
		button.pressed.connect(_on_talent_unlock.bind(ability_id))
	else:
		button.text = "Later"
		button.disabled = true
	row.add_child(button)
	return card


func _talent_state_label(talent_data: Dictionary) -> String:
	match String(talent_data.get("state", "unsupported")):
		"known": return "Known"
		"available": return "Available"
		"level_locked": return "Level Locked"
		"points_locked": return "Talent Points Locked"
		"equipped": return "Equipped"
		"wrong_weapon": return "Wrong Weapon"
		_: return "Unavailable"


func _ability_cadence(ability: Dictionary) -> String:
	var parts: Array[String] = []
	var use_limit := maxi(0, int(ability.get("maxUsesPerTurn", 0)))
	var cooldown := maxi(0, int(ability.get("cooldownTurns", 0)))
	if use_limit > 0:
		parts.append("%d/turn" % use_limit)
	if cooldown > 0:
		parts.append("CD %d turn%s" % [cooldown, "" if cooldown == 1 else "s"])
	var buff_type := String(ability.get("buffType", ""))
	var buff_duration := maxi(0, int(ability.get("buffDuration", 0)))
	if buff_type in ["atk", "def", "speed"] and buff_duration > 0:
		parts.append("%d rounds" % buff_duration)
	var debuff_type := String(ability.get("debuffType", ""))
	var debuff_duration := maxi(0, int(ability.get("debuffDuration", 0)))
	if debuff_type in ["atk", "def", "speed"] and debuff_duration > 0:
		parts.append("%d rounds" % debuff_duration)
	return "  ·  ".join(parts)


func _ability_effect_text(ability: Dictionary) -> String:
	if String(ability.get("type", "")) == "buff":
		var buff_type := String(ability.get("buffType", "effect")).capitalize()
		return "%s +%d" % [buff_type, int(ability.get("buffValue", 0))]
	if String(ability.get("type", "")) in ["counter", "parry"]:
		var defense := "Full block" if String(ability.get("type", "")) == "parry" \
			else "Shield %d" % int(ability.get("power", 0))
		return "%s  ·  Return %d" % [defense, int(ability.get("counterDamage", 0))]
	var effect := "%s %d" % [String(ability.get("type", "action")).capitalize(),
		int(ability.get("power", 0))]
	var debuff_type := String(ability.get("debuffType", ""))
	if debuff_type in ["atk", "def", "speed"]:
		effect += "  ·  %s -%d" % [CombatEncounter.stat_label(debuff_type),
			int(ability.get("debuffValue", 0))]
	var lifesteal_pct := clampf(float(ability.get("lifestealPct", 0.0)), 0.0, 1.0)
	if lifesteal_pct > 0.0:
		effect += "  ·  Drain %d%%" % roundi(lifesteal_pct * 100.0)
	return effect


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COL_BORDER)
	return label


func _verified_ability_icon(ability_id: String) -> TextureRect:
	if ability_id not in VERIFIED_ABILITY_ICONS:
		return null
	var path := ABILITY_ICON_DIR + ability_id + ".png"
	if not ResourceLoader.exists(path):
		return null
	var icon := TextureRect.new()
	icon.name = "AbilityIcon_" + ability_id
	icon.texture = load(path) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(32, 32)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return icon


func _on_skill_toggle(ability_id: String, equip: bool) -> void:
	var weapon_type := String(Inv.equipped_def("weapon").get("weaponType", ""))
	if Learning.set_ability_equipped(ability_id, equip, weapon_type):
		var verb := "Equipped" if equip else "Removed"
		Bus.toast.emit("%s %s." % [verb, DB.ability(ability_id).get("name", ability_id)])
	else:
		Bus.toast.emit("That ability cannot be equipped right now.")


func _on_talent_unlock(ability_id: String) -> void:
	if Learning.unlock_talent(ability_id):
		Bus.toast.emit("Talent learned: %s." % DB.ability(ability_id).get("name", ability_id))
	else:
		Bus.toast.emit("That talent cannot be unlocked yet.")


func _on_attribute_change(attribute: String, delta: int) -> void:
	if Learning.adjust_allocation(attribute, delta):
		Bus.toast.emit("%s %s." % [attribute.capitalize(), "raised" if delta > 0 else "refunded"])
	else:
		Bus.toast.emit("That attribute cannot change right now.")


func _on_toggle_favorite(id: String) -> void:
	Inv.toggle_favorite(id)


func _on_bag_category_selected(key: String) -> void:
	_bag_category = key
	# toggle_mode buttons don't behave like a radio group on their own; keep
	# exactly one pressed, matching the tab bar's single-active-domain feel.
	for other_key in _bag_category_buttons:
		(_bag_category_buttons[other_key] as Button).button_pressed = other_key == key
	_refresh()


func _on_bag_search_changed(text: String) -> void:
	_bag_search = text
	_refresh()


func _on_use_healing(item_id: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var restored := Inv.use_healing_item(item_id, int(player.hp), int(player.MAX_HP))
	if restored <= 0:
		Bus.toast.emit("That item cannot be used right now.")
		return
	player.set_hp(int(player.hp) + restored)
	_refresh()
	Bus.toast.emit("%s restored %d HP." % [DB.item(item_id).get("name", item_id), restored])


func _on_prepare_meal(item_id: String) -> void:
	var replacing := not Inv.prepared_meal_id().is_empty()
	if Inv.prepare_meal(item_id):
		Bus.toast.emit("%s %s for battle." % [
			DB.item(item_id).get("name", item_id), "replaced your meal" if replacing else "prepared"])
	else:
		Bus.toast.emit("Could not prepare that meal; its old stack may be full.")


func _on_unprepare_meal() -> void:
	var item_id := Inv.prepared_meal_id()
	if Inv.unprepare_meal():
		Bus.toast.emit("Returned %s to the Bag." % DB.item(item_id).get("name", item_id))
	else:
		Bus.toast.emit("That meal's Bag stack is full, so it stayed prepared.")


func _refresh_prepared_meal() -> void:
	if _prepared_meal_box == null:
		return
	for child in _prepared_meal_box.get_children():
		_prepared_meal_box.remove_child(child)
		child.queue_free()
	var item_id := Inv.prepared_meal_id()
	var label := Label.new()
	label.name = "PreparedMealLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	if item_id.is_empty():
		label.text = "Prepared meal · None — reserve a large meal for one battle heal."
		label.add_theme_color_override("font_color", COL_HEADING)
		_prepared_meal_box.add_child(label)
		return
	var item: Dictionary = DB.item(item_id)
	label.text = "Prepared · %s · Restores %d HP in battle" % [
		item.get("name", item_id), int(item.get("heal", 0))]
	label.add_theme_color_override("font_color", UiTheme.STATE_SUCCESS)
	_prepared_meal_box.add_child(label)
	var button := Button.new()
	button.name = "UnprepareMeal"
	button.text = "Return"
	button.tooltip_text = "Move this meal back into the Bag."
	button.custom_minimum_size = Vector2(60, 22)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(_on_unprepare_meal)
	_prepared_meal_box.add_child(button)


func _on_equip(item_id: String) -> void:
	var item: Dictionary = DB.item(item_id)
	if Inv.equip(item_id):
		Bus.toast.emit("Equipped %s." % item.get("name", item_id))
	else:
		Bus.toast.emit("Could not equip %s." % item.get("name", item_id))


func _on_unequip(slot: String, item_id: String) -> void:
	if Inv.unequip(slot):
		Bus.toast.emit("Unequipped %s." % DB.item(item_id).get("name", item_id))
	else:
		Bus.toast.emit("Bag stack is full; equipment was left in place.")


func _player_level() -> int:
	var xp := 0
	if Learning.profile != null:
		xp = int(Learning.profile.data.get("stats", {}).get("xp", 0))
	return PlayerStats.level_from_xp(xp)


func _stats_line(stats: Dictionary) -> String:
	var parts: Array[String] = []
	for stat in ["hp", "atk", "def", "spd"]:
		var value := int(stats.get(stat, 0))
		if value != 0:
			parts.append("%+d %s%s" % [value, stat.to_upper(), "*" if stat == "spd" else ""])
	return "  ".join(parts)


func _icon_node(id: String) -> Control:
	var def := DB.item(id)
	var icon_id := String(def.get("iconAlias", id))
	var path := ICON_DIR + icon_id + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
		tex.name = "ItemIcon_%s" % id
		tex.texture = load(path) as Texture2D
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(48, 48)
		return tex
	var placeholder := ColorRect.new()
	placeholder.color = COL_BORDER
	placeholder.custom_minimum_size = Vector2(48, 48)
	return placeholder


func _name_of(id: String) -> String:
	return String(DB.item(id).get("name", id))


## Whether one bag entry ({id, qty}) passes the current category + search state.
func _matches_bag_filter(entry: Dictionary) -> bool:
	var id := String(entry["id"])
	if _bag_category == "favorites":
		if not Inv.is_favorite(id):
			return false
	elif _bag_category != "all":
		if String(DB.item(id).get("kind", "")) != _bag_category:
			return false
	if not _bag_search.is_empty():
		if not _name_of(id).to_lower().contains(_bag_search.to_lower()):
			return false
	return true


## The empty-grid message has to distinguish three different situations, or a
## player who filters to nothing owned would think their bag itself was empty.
func _bag_empty_message(bag_is_truly_empty: bool) -> String:
	if bag_is_truly_empty:
		return "Your bag is empty."
	if not _bag_search.is_empty():
		return "No items match \"%s\"." % _bag_search
	if _bag_category == "favorites":
		return "Nothing favorited yet. Press Fav on any item to pin it here."
	return "Nothing in this category yet."


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
	_root = Control.new()
	_root.name = "PlayerMenuRoot"
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PlayerMenuShell"
	panel.add_theme_stylebox_override("panel", _panel_style())
	UiTheme.fit_modal_shell(panel)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Header row: title on the left, coins on the right.
	var header := HBoxContainer.new()
	vbox.add_child(header)

	var title := Label.new()
	title.text = "Player"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", COL_BORDER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 16)
	_coins_label.add_theme_color_override("font_color", COL_COIN)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_coins_label)

	# Flow, not a fixed row: eight domain tabs are wider than the shell once UI
	# scale shrinks the canvas, and an HBoxContainer would push the whole panel
	# past its anchors and off screen. Wrapping to a second row is the guide's
	# "narrow screens reflow instead of shrinking".
	var tabs := HFlowContainer.new()
	tabs.name = "DomainTabs"
	# A wrapped tab lines up under the first tab rather than floating centred,
	# so the second row reads as a continuation of the same list.
	tabs.alignment = FlowContainer.ALIGNMENT_BEGIN
	tabs.add_theme_constant_override("h_separation", 8)
	tabs.add_theme_constant_override("v_separation", 4)
	vbox.add_child(tabs)

	_character_tab = Button.new()
	_character_tab.name = "CharacterTab"
	_character_tab.text = "Character"
	_character_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_tab.focus_mode = Control.FOCUS_ALL
	_character_tab.pressed.connect(_set_tab.bind(TAB_CHARACTER))
	tabs.add_child(_character_tab)

	_skills_tab = Button.new()
	_skills_tab.name = "SkillsTab"
	_skills_tab.text = "Skills"
	_skills_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_skills_tab.focus_mode = Control.FOCUS_ALL
	_skills_tab.pressed.connect(_set_tab.bind(TAB_SKILLS))
	tabs.add_child(_skills_tab)

	_bag_tab = Button.new()
	_bag_tab.name = "BagTab"
	_bag_tab.text = "Bag"
	_bag_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_tab.focus_mode = Control.FOCUS_ALL
	_bag_tab.pressed.connect(_set_tab.bind(TAB_BAG))
	tabs.add_child(_bag_tab)

	_quests_tab = Button.new()
	_quests_tab.name = "QuestsTab"
	_quests_tab.text = "Journal"
	_quests_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_quests_tab.focus_mode = Control.FOCUS_ALL
	_quests_tab.pressed.connect(_set_tab.bind(TAB_QUESTS))
	tabs.add_child(_quests_tab)

	_map_tab = Button.new()
	_map_tab.name = "MapTab"
	_map_tab.text = "Map"
	_map_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map_tab.focus_mode = Control.FOCUS_ALL
	_map_tab.pressed.connect(_set_tab.bind(TAB_MAP))
	tabs.add_child(_map_tab)

	_learning_tab = Button.new()
	_learning_tab.name = "LearningTab"
	_learning_tab.text = "Learning"
	_learning_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_learning_tab.focus_mode = Control.FOCUS_ALL
	_learning_tab.pressed.connect(_set_tab.bind(TAB_LEARNING))
	tabs.add_child(_learning_tab)

	_system_tab = Button.new()
	_system_tab.name = "SystemTab"
	_system_tab.text = "System"
	_system_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_system_tab.focus_mode = Control.FOCUS_ALL
	_system_tab.pressed.connect(_set_tab.bind(TAB_SYSTEM))
	tabs.add_child(_system_tab)

	_bestiary_tab = Button.new()
	_bestiary_tab.name = "BestiaryTab"
	_bestiary_tab.text = "Bestiary"
	_bestiary_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bestiary_tab.focus_mode = Control.FOCUS_ALL
	_bestiary_tab.pressed.connect(_set_tab.bind(TAB_BESTIARY))
	tabs.add_child(_bestiary_tab)

	_character_scroll = ScrollContainer.new()
	_character_scroll.name = "CharacterScroll"
	_character_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_character_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_character_scroll)

	_character_view = VBoxContainer.new()
	_character_view.name = "CharacterView"
	_character_view.add_theme_constant_override("separation", 10)
	_character_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_character_scroll.add_child(_character_view)

	_stats_label = Label.new()
	_stats_label.name = "StatsSummary"
	_stats_label.add_theme_font_size_override("font_size", 14)
	_stats_label.add_theme_color_override("font_color", COL_TEXT)
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_character_view.add_child(_stats_label)

	var attribute_header := HBoxContainer.new()
	_character_view.add_child(attribute_header)
	var attribute_heading := Label.new()
	attribute_heading.text = "Attributes — freely refundable"
	attribute_heading.add_theme_font_size_override("font_size", 13)
	attribute_heading.add_theme_color_override("font_color", COL_HEADING)
	attribute_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attribute_header.add_child(attribute_heading)
	_attribute_points_label = Label.new()
	_attribute_points_label.name = "AttributePoints"
	_attribute_points_label.add_theme_font_size_override("font_size", 12)
	_attribute_points_label.add_theme_color_override("font_color", COL_BORDER)
	attribute_header.add_child(_attribute_points_label)

	var allocation_rows := [
		["vitality", "Vitality", "+6 max HP"],
		["power", "Power", "+1 ATK"],
		["agility", "Agility", "+1 SPD · 4 SPD lead grants +1 turn"],
	]
	for row_data in allocation_rows:
		var key := String(row_data[0])
		var row := HBoxContainer.new()
		row.name = key.capitalize() + "Attribute"
		row.add_theme_constant_override("separation", 6)
		_character_view.add_child(row)
		var name_label := Label.new()
		name_label.text = String(row_data[1])
		name_label.custom_minimum_size = Vector2(70, 0)
		name_label.add_theme_color_override("font_color", COL_TEXT)
		row.add_child(name_label)
		var value_label := Label.new()
		value_label.name = key.capitalize() + "Value"
		value_label.custom_minimum_size = Vector2(22, 0)
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_color_override("font_color", COL_BORDER)
		row.add_child(value_label)
		_attribute_value_labels[key] = value_label
		var effect_label := Label.new()
		effect_label.text = String(row_data[2])
		effect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		effect_label.add_theme_font_size_override("font_size", 10)
		effect_label.add_theme_color_override("font_color", COL_HEADING)
		row.add_child(effect_label)
		var minus := Button.new()
		minus.name = key.capitalize() + "Minus"
		minus.text = "−"
		minus.custom_minimum_size = Vector2(32, 26)
		minus.focus_mode = Control.FOCUS_ALL
		minus.tooltip_text = "Refund one Attribute Point."
		minus.pressed.connect(_on_attribute_change.bind(key, -1))
		row.add_child(minus)
		_attribute_minus_buttons[key] = minus
		var plus := Button.new()
		plus.name = key.capitalize() + "Plus"
		plus.text = "+"
		plus.custom_minimum_size = Vector2(32, 26)
		plus.focus_mode = Control.FOCUS_ALL
		plus.tooltip_text = "Spend one Attribute Point."
		plus.pressed.connect(_on_attribute_change.bind(key, 1))
		row.add_child(plus)
		_attribute_plus_buttons[key] = plus

	var equipment_heading := Label.new()
	equipment_heading.text = "Equipment — press a filled slot to remove it"
	equipment_heading.add_theme_font_size_override("font_size", 13)
	equipment_heading.add_theme_color_override("font_color", COL_HEADING)
	_character_view.add_child(equipment_heading)

	# Grouped by type (Weapon / Armor / Accessories) rather than one flat wrapping
	# row: "gear slots and types" is only readable if the types are visible.
	for group in EQUIPMENT_GROUPS:
		var group_name := String(group[0])
		var group_header := Label.new()
		group_header.name = "EquipmentGroup_" + group_name
		group_header.text = group_name
		group_header.add_theme_font_size_override("font_size", 11)
		group_header.add_theme_color_override("font_color", COL_BORDER)
		_character_view.add_child(group_header)

		var group_box := HFlowContainer.new()
		group_box.name = "EquipmentSlots_" + group_name
		group_box.add_theme_constant_override("h_separation", 6)
		group_box.add_theme_constant_override("v_separation", 4)
		_character_view.add_child(group_box)
		_equipment_group_boxes[group_name] = group_box

	_skills_view = VBoxContainer.new()
	_skills_view.name = "SkillsView"
	_skills_view.add_theme_constant_override("separation", 8)
	_skills_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_skills_view)

	_skills_summary = Label.new()
	_skills_summary.name = "SkillsSummary"
	_skills_summary.add_theme_font_size_override("font_size", 12)
	_skills_summary.add_theme_color_override("font_color", COL_HEADING)
	_skills_view.add_child(_skills_summary)

	var skills_scroll := ScrollContainer.new()
	skills_scroll.name = "SkillsScroll"
	skills_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	skills_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_skills_view.add_child(skills_scroll)

	_skills_box = VBoxContainer.new()
	_skills_box.name = "SkillCards"
	_skills_box.add_theme_constant_override("separation", 6)
	_skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_scroll.add_child(_skills_box)

	_quests_view = VBoxContainer.new()
	_quests_view.name = "QuestsView"
	_quests_view.add_theme_constant_override("separation", 8)
	_quests_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_quests_view)

	_quests_summary = Label.new()
	_quests_summary.name = "QuestsSummary"
	_quests_summary.add_theme_font_size_override("font_size", 12)
	_quests_summary.add_theme_color_override("font_color", COL_HEADING)
	_quests_view.add_child(_quests_summary)

	var quests_scroll := ScrollContainer.new()
	quests_scroll.name = "QuestsScroll"
	quests_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	quests_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_quests_view.add_child(quests_scroll)

	_quests_box = VBoxContainer.new()
	_quests_box.name = "QuestCards"
	_quests_box.add_theme_constant_override("separation", 6)
	_quests_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quests_scroll.add_child(_quests_box)

	_map_view = VBoxContainer.new()
	_map_view.name = "MapView"
	_map_view.add_theme_constant_override("separation", 8)
	_map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_map_view)

	_map_summary = Label.new()
	_map_summary.name = "MapSummary"
	_map_summary.add_theme_font_size_override("font_size", 12)
	_map_summary.add_theme_color_override("font_color", COL_HEADING)
	_map_view.add_child(_map_summary)

	_map_box = WorldMapGraph.new()
	_map_box.name = "WorldMapGraph"
	_map_box.region_focused.connect(_on_map_region_focused)
	_map_view.add_child(_map_box)

	_map_detail = Label.new()
	_map_detail.name = "MapRegionDetail"
	_map_detail.add_theme_font_size_override("font_size", 10)
	_map_detail.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_map_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_map_detail.custom_minimum_size = Vector2(0, 34)
	_map_view.add_child(_map_detail)

	_learning_view = VBoxContainer.new()
	_learning_view.name = "LearningView"
	_learning_view.add_theme_constant_override("separation", 8)
	_learning_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_learning_view)

	_learning_summary = Label.new()
	_learning_summary.name = "LearningSummary"
	_learning_summary.add_theme_font_size_override("font_size", 12)
	_learning_summary.add_theme_color_override("font_color", COL_HEADING)
	_learning_view.add_child(_learning_summary)

	var learning_scroll := ScrollContainer.new()
	learning_scroll.name = "LearningScroll"
	learning_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	learning_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_learning_view.add_child(learning_scroll)

	_learning_box = VBoxContainer.new()
	_learning_box.name = "LearningCards"
	_learning_box.add_theme_constant_override("separation", 6)
	_learning_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	learning_scroll.add_child(_learning_box)

	_system_view = VBoxContainer.new()
	_system_view.name = "SystemView"
	_system_view.add_theme_constant_override("separation", 8)
	_system_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_system_view)

	_system_summary = Label.new()
	_system_summary.name = "SystemSummary"
	_system_summary.add_theme_font_size_override("font_size", 12)
	_system_summary.add_theme_color_override("font_color", COL_HEADING)
	_system_view.add_child(_system_summary)

	var system_scroll := ScrollContainer.new()
	system_scroll.name = "SystemScroll"
	system_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	system_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_system_view.add_child(system_scroll)

	_system_box = VBoxContainer.new()
	_system_box.name = "SystemControls"
	_system_box.add_theme_constant_override("separation", 6)
	_system_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	system_scroll.add_child(_system_box)

	_bestiary_view = VBoxContainer.new()
	_bestiary_view.name = "BestiaryView"
	_bestiary_view.add_theme_constant_override("separation", 8)
	_bestiary_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_bestiary_view)

	_bestiary_summary = Label.new()
	_bestiary_summary.name = "BestiarySummary"
	_bestiary_summary.add_theme_font_size_override("font_size", 12)
	_bestiary_summary.add_theme_color_override("font_color", COL_HEADING)
	_bestiary_view.add_child(_bestiary_summary)

	var bestiary_scroll := ScrollContainer.new()
	bestiary_scroll.name = "BestiaryScroll"
	bestiary_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bestiary_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bestiary_view.add_child(bestiary_scroll)

	_bestiary_box = VBoxContainer.new()
	_bestiary_box.name = "BestiaryCards"
	_bestiary_box.add_theme_constant_override("separation", 6)
	_bestiary_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bestiary_scroll.add_child(_bestiary_box)

	_bag_view = VBoxContainer.new()
	_bag_view.name = "BagView"
	_bag_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_bag_view)

	# Category filter + search, one compact row so it costs the Bag tab's tight
	# fixed (non-scrolling) height budget only once. 171 items with no way to
	# narrow them was the largest remaining gap against UI_UX_GUIDE section 9's
	# bag model. Categories are the real `kind` values every item actually has,
	# plus the synthetic Favorites. Fish/Food and Quest Items remain future data
	# kinds rather than empty controls.
	var filter_row := HBoxContainer.new()
	filter_row.name = "BagFilterRow"
	filter_row.add_theme_constant_override("separation", 3)
	_bag_view.add_child(filter_row)
	var category_labels := {
		"all": "All", "gear": "Gear", "consumable": "Use",
		"material": "Mats", "seed": "Seeds", "tool": "Tools", "favorites": "Fav",
	}
	for pair in BAG_CATEGORIES:
		var key := String(pair[0])
		var btn := Button.new()
		btn.name = "BagCategory_" + key
		btn.text = String(category_labels.get(key, pair[1]))
		btn.tooltip_text = String(pair[1])
		btn.toggle_mode = true
		btn.button_pressed = key == _bag_category
		btn.focus_mode = Control.FOCUS_ALL
		btn.add_theme_font_size_override("font_size", 11)
		btn.custom_minimum_size = Vector2(0, 22)
		btn.pressed.connect(_on_bag_category_selected.bind(key))
		filter_row.add_child(btn)
		_bag_category_buttons[key] = btn

	_bag_search_box = LineEdit.new()
	_bag_search_box.name = "BagSearch"
	_bag_search_box.placeholder_text = "Search..."
	_bag_search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_search_box.custom_minimum_size = Vector2(60, 22)
	_bag_search_box.text_changed.connect(_on_bag_search_changed)
	filter_row.add_child(_bag_search_box)

	var bag_hint := Label.new()
	bag_hint.name = "BagHint"
	bag_hint.text = "Equip gear, use healing food, or inspect labeled combat-only items."
	bag_hint.add_theme_font_size_override("font_size", 12)
	bag_hint.add_theme_color_override("font_color", COL_HEADING)
	_bag_view.add_child(bag_hint)

	var prepared_panel := PanelContainer.new()
	prepared_panel.name = "PreparedMealPanel"
	prepared_panel.add_theme_stylebox_override("panel", _card_style(UiTheme.STATE_SUCCESS))
	_bag_view.add_child(prepared_panel)
	_prepared_meal_box = HBoxContainer.new()
	_prepared_meal_box.name = "PreparedMealSlot"
	_prepared_meal_box.add_theme_constant_override("separation", 6)
	prepared_panel.add_child(_prepared_meal_box)

	# Grid of cards, height-capped so overflow scrolls instead of the whole page.
	var bag_scroll := ScrollContainer.new()
	bag_scroll.name = "BagScroll"
	bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bag_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_view.add_child(bag_scroll)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(_grid)

	_empty_label = Label.new()
	_empty_label.text = "Your bag is empty."
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", COL_HEADING)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A search message can run longer than the static default text ever did.
	# autowrap alone (no forced minimum width) lets it wrap within whatever width
	# the scroll area actually has — a fixed width here is what pushed the whole
	# shell wider than the 640px viewport the one time this was tried.
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag_scroll.add_child(_empty_label)

	# Footer: capacity + how to close.
	var footer := HBoxContainer.new()
	vbox.add_child(footer)

	_capacity_label = Label.new()
	_capacity_label.add_theme_font_size_override("font_size", 12)
	_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_capacity_label)

	_input_hint = Label.new()
	_input_hint.name = "InputHint"
	_input_hint.add_theme_font_size_override("font_size", 12)
	_input_hint.add_theme_color_override("font_color", COL_HEADING)
	_input_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(_input_hint)
	_refresh_input_hint()

	_set_tab(_active_tab)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s


## `border` lets the quest log tint a card by its state — ready to turn in, still
## running, already done — without every other card having to care.
func _card_style(border: Color = COL_CARD_BORDER) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = border
	return s
