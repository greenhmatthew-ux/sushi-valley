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
const ConsumableRules = preload("res://src/systems/consumable_logic.gd")

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
}

const ICON_DIR := "res://assets/icons/items/"
const ABILITY_ICON_DIR := "res://assets/icons/abilities/"
## These files were replaced with traced Ninja Adventure CC0 originals in the
## Talent-art slice. Do not render the remaining legacy ability icons until audited.
const VERIFIED_ABILITY_ICONS := [
	"sweep", "kunai", "kana_bolt", "brace", "ki_focus", "rune_ward", "riposte",
]
const TAB_CHARACTER := "character"
const TAB_SKILLS := "skills"
const TAB_BAG := "bag"

var _open := false
var _active_tab := TAB_BAG
var _root: Control
var _coins_label: Label
var _equipment_box: HFlowContainer
var _character_scroll: ScrollContainer
var _character_view: VBoxContainer
var _skills_view: VBoxContainer
var _skills_box: VBoxContainer
var _skills_summary: Label
var _bag_view: VBoxContainer
var _stats_label: Label
var _attribute_points_label: Label
var _attribute_value_labels: Dictionary = {}
var _attribute_plus_buttons: Dictionary = {}
var _attribute_minus_buttons: Dictionary = {}
var _character_tab: Button
var _skills_tab: Button
var _bag_tab: Button
var _grid: GridContainer
var _empty_label: Label
var _capacity_label: Label


func _ready() -> void:
	layer = 19   # under recall (20) and toast (21)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_scaffold()
	_root.hide()
	Bus.inventory_changed.connect(_refresh)
	Bus.ability_loadout_changed.connect(_refresh)
	Bus.player_build_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_menu"):
		# Never stack this menu over dialogue, combat, recall, shops, or another modal.
		if not _open and get_tree().paused:
			return
		_toggle()
		get_viewport().set_input_as_handled()
	elif _open and event.is_action_pressed("ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	_set_open(not _open)


func _set_open(open: bool) -> void:
	_open = open
	if open:
		_refresh()
		_set_tab(_active_tab)
		_root.show()
		get_tree().paused = true
		var active_button := _character_tab
		if _active_tab == TAB_SKILLS:
			active_button = _skills_tab
		elif _active_tab == TAB_BAG:
			active_button = _bag_tab
		active_button.grab_focus()
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
	for child in _equipment_box.get_children():
		_equipment_box.remove_child(child)
		child.queue_free()
	for child in _skills_box.get_children():
		_skills_box.remove_child(child)
		child.queue_free()

	var equipped: Dictionary = Inv.equipment()
	for slot in InventoryLogic.EQUIPMENT_SLOTS:
		_equipment_box.add_child(_make_equipment_slot_button(
			slot, String(equipped.get(slot, ""))))

	var xp := 0
	if Learning.profile != null:
		xp = int(Learning.profile.data.get("stats", {}).get("xp", 0))
	var allocations: Dictionary = Learning.allocations()
	var stats := PlayerStats.from_xp(xp, Inv.equipped_defs(), allocations)
	var gear := PlayerStats.gear_bonus(Inv.equipped_defs(), int(stats["level"]))
	var player := get_tree().get_first_node_in_group("player")
	var current_hp := int(player.hp) if player != null else int(stats["max_hp"])
	_stats_label.text = (
		"Level %d\nLearning XP  %d / %d\n\n"
		+ "HP   %d / %d\nATK  %d   DEF  %d   SPD  %d\n\n"
		+ "Gear bonus  %+d HP   %+d ATK   %+d DEF   %+d SPD\n"
		+ "Japanese study raises your base stats; equipped gear is included above."
	) % [
		stats["level"], stats["xp_into_level"], stats["xp_per_level"],
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
	var weapon_type := String(Inv.equipped_def("weapon").get("weaponType", ""))
	_skills_box.add_child(_section_label("Known Actions"))
	for ability in Learning.known_ability_defs():
		_skills_box.add_child(_make_skill_card(ability, weapon_type,
			String(ability.get("id", "")) in equipped_skills))
	var talents := Learning.next_talent_defs()
	if not talents.is_empty():
		_skills_box.add_child(_section_label("Next Talents — one honest action per style"))
		for ability in talents:
			_skills_box.add_child(_make_talent_card(ability))

	var items: Array = Inv.entries()
	# Sort by display name for a stable, human-friendly order (TS bag() did this).
	items.sort_custom(func(a, b): return _name_of(a["id"]).naturalnocasecmp_to(_name_of(b["id"])) < 0)

	_empty_label.visible = items.is_empty()
	_grid.visible = not items.is_empty()
	for entry in items:
		_grid.add_child(_make_card(String(entry["id"]), int(entry["qty"])))

	_refresh_footer()


func _set_tab(tab: String) -> void:
	_active_tab = tab if tab in [TAB_CHARACTER, TAB_SKILLS, TAB_BAG] else TAB_BAG
	_character_scroll.visible = _active_tab == TAB_CHARACTER
	_character_view.visible = _active_tab == TAB_CHARACTER
	_skills_view.visible = _active_tab == TAB_SKILLS
	_bag_view.visible = _active_tab == TAB_BAG
	_character_tab.disabled = _active_tab == TAB_CHARACTER
	_skills_tab.disabled = _active_tab == TAB_SKILLS
	_bag_tab.disabled = _active_tab == TAB_BAG
	_refresh_footer()


func _refresh_footer() -> void:
	if _capacity_label == null:
		return
	if _active_tab == TAB_CHARACTER:
		_capacity_label.text = "SPD* is authored but not active in the current combat loop yet."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	elif _active_tab == TAB_SKILLS:
		_capacity_label.text = "Choose an action in combat, then answer with the matching rune."
		_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	else:
		var enc: Dictionary = Inv.encumbrance()
		_capacity_label.text = "Carrying %d / %d" % [enc["units"], enc["cap"]]
		_capacity_label.add_theme_color_override("font_color",
			COL_WARN if enc["encumbered"] else COL_HEADING)


func _make_card(id: String, qty: int) -> Control:
	var def: Dictionary = DB.item(id)
	var card := PanelContainer.new()
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

	var qty_label := Label.new()
	qty_label.text = "x%d" % qty
	qty_label.add_theme_font_size_override("font_size", 12)
	qty_label.add_theme_color_override("font_color", COL_HEADING)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(qty_label)

	if def.get("kind", "") == "gear":
		var stats_label := Label.new()
		stats_label.text = _stats_line(PlayerStats.scaled_item_stats(def, _player_level()))
		stats_label.add_theme_font_size_override("font_size", 10)
		stats_label.add_theme_color_override("font_color", COL_TEXT)
		stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(stats_label)

		var equip_button := Button.new()
		var required_level := int(def.get("requiredLevel", 1))
		equip_button.text = "Equip" if required_level <= _player_level() \
			else "Lv %d" % required_level
		equip_button.disabled = required_level > _player_level()
		equip_button.focus_mode = Control.FOCUS_ALL
		equip_button.pressed.connect(_on_equip.bind(id))
		vbox.add_child(equip_button)
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
	elif def.get("kind", "") == "consumable":
		var later_label := Label.new()
		later_label.text = "Effect not active yet"
		later_label.tooltip_text = "Meals, timed buffs, shields, and attack items stay stored until their full effect is implemented."
		later_label.add_theme_font_size_override("font_size", 9)
		later_label.add_theme_color_override("font_color", COL_HEADING)
		later_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		later_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(later_label)

	return card


func _make_equipment_slot_button(slot: String, item_id: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 34)
	button.focus_mode = Control.FOCUS_ALL
	if item_id.is_empty():
		button.text = "%s: —" % slot.capitalize()
		button.tooltip_text = "Empty %s slot." % slot
		button.disabled = true
	else:
		var item: Dictionary = DB.item(item_id)
		button.text = "%s: %s" % [slot.capitalize(), item.get("name", item_id)]
		button.tooltip_text = "%s\n%s\nPress to unequip." % [
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


func _make_talent_card(ability: Dictionary) -> Control:
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
	button.name = "TalentUnlock_" + String(ability.get("id", ""))
	button.custom_minimum_size = Vector2(76, 32)
	button.focus_mode = Control.FOCUS_ALL
	var required_level := int(ability.get("requiredLevel", 1))
	var current_level := _player_level()
	var can_unlock := Learning.can_unlock_talent(String(ability.get("id", "")))
	button.disabled = not can_unlock
	if current_level < required_level:
		button.text = "Lv %d" % required_level
		button.tooltip_text = "Reach level %d to unlock this Talent." % required_level
	elif Learning.unspent_talent_points() < cost:
		button.text = "Need %d TP" % cost
		button.tooltip_text = "Earn Talent Points by gaining levels."
	else:
		button.text = "Unlock"
		button.tooltip_text = "Permanently learn this action."
	button.pressed.connect(_on_talent_unlock.bind(String(ability.get("id", ""))))
	row.add_child(button)
	return card


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
	var path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(path):
		var tex := TextureRect.new()
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


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
	_root = Control.new()
	_root.name = "PlayerMenuRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "PlayerMenuShell"
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.anchor_left = 0.08; panel.anchor_top = 0.06
	panel.anchor_right = 0.92; panel.anchor_bottom = 0.94
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

	var tabs := HBoxContainer.new()
	tabs.name = "DomainTabs"
	tabs.add_theme_constant_override("separation", 8)
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

	_equipment_box = HFlowContainer.new()
	_equipment_box.name = "EquipmentSlots"
	_equipment_box.add_theme_constant_override("h_separation", 6)
	_equipment_box.add_theme_constant_override("v_separation", 4)
	_character_view.add_child(_equipment_box)

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

	_bag_view = VBoxContainer.new()
	_bag_view.name = "BagView"
	_bag_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_bag_view)

	var bag_hint := Label.new()
	bag_hint.text = "Select gear to equip it. Level requirements explain locked choices."
	bag_hint.add_theme_font_size_override("font_size", 12)
	bag_hint.add_theme_color_override("font_color", COL_HEADING)
	_bag_view.add_child(bag_hint)

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
	bag_scroll.add_child(_empty_label)

	# Footer: capacity + how to close.
	var footer := HBoxContainer.new()
	vbox.add_child(footer)

	_capacity_label = Label.new()
	_capacity_label.add_theme_font_size_override("font_size", 12)
	_capacity_label.add_theme_color_override("font_color", COL_HEADING)
	_capacity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_capacity_label)

	var hint := Label.new()
	hint.text = "I / Esc close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", COL_HEADING)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	footer.add_child(hint)

	_set_tab(_active_tab)


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s


func _card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_CARD
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = COL_CARD_BORDER
	return s
