extends SceneTree
## Player-menu UX contract: real Character/Bag domains, honest stats, modal safety,
## and controller routes through the InputMap.

var failures: int = 0


## Controls report positions in their unscaled CanvasLayer space. At 80% UI size
## that canvas is 800x450, then the layer scales it back onto the 640x360 screen.
## Bounds checks must use that authored canvas, not the raw viewport pixels.
func _logical_ui_rect() -> Rect2:
	var settings: Node = root.get_node("Settings")
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	return Rect2(Vector2.ZERO, (base / maxf(settings.ui_scale, 0.1)).floor())


func _initialize() -> void:
	await process_frame
	# Earlier suites deliberately exercise persistence in the same isolated APPDATA root.
	# Pin this UI contract to an actual fresh build instead of inheriting their XP.
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
	var bus: Node = root.get_node("Bus")
	var inv: Node = root.get_node("Inv")
	learning.profile.data["stats"]["xp"] = 0
	learning.profile.build()["allocations"] = {"vitality": 0, "power": 0, "agility": 0}
	var panel := CanvasLayer.new()
	panel.set_script(load("res://src/ui/inventory_panel.gd"))
	root.add_child(panel)
	await process_frame

	var menu: Control = panel.find_child("PlayerMenuRoot", true, false)
	var shell: Control = panel.find_child("PlayerMenuShell", true, false)
	var character: Control = panel.find_child("CharacterView", true, false)
	var skills: Control = panel.find_child("SkillsView", true, false)
	var bag: Control = panel.find_child("BagView", true, false)
	var stats: Label = panel.find_child("StatsSummary", true, false)
	check_true("player menu builds", menu != null)
	check_true("menu starts closed", menu != null and not menu.visible)

	panel.call("_set_open", true)
	await process_frame
	check_true("opening pauses the world", paused)
	check_true("menu opens to a real domain", bag.visible and not character.visible)
	check_true("character, skills, and bag tabs exist",
		panel.find_child("CharacterTab", true, false) != null
		and panel.find_child("SkillsTab", true, false) != null
		and panel.find_child("BagTab", true, false) != null)
	var viewport_rect := _logical_ui_rect()
	check_true("menu shell stays inside the scaled UI canvas",
		viewport_rect.encloses(shell.get_global_rect()))
	var bag_hint: Label = panel.find_child("BagHint", true, false)
	check_true("Bag help describes its mixed item actions",
		bag_hint.text.contains("Equip gear")
		and bag_hint.text.contains("healing food")
		and bag_hint.text.contains("combat-only"))
	var alias_icon := panel.call("_icon_node", "spicy_curry") as TextureRect
	check_eq("Bag resolves authored item icon aliases",
		alias_icon.texture.resource_path, "res://assets/icons/items/noodle_bowl.png")
	alias_icon.free()
	var compost_icon := panel.call("_icon_node", "compost") as TextureRect
	check_eq("Garden Compost uses its audited sack art",
		compost_icon.texture.resource_path, "res://assets/icons/items/compost.png")
	compost_icon.free()

	# Bag categories, search, and favorites — UI_UX_GUIDE section 9's bag model.
	# 168 items with no way to narrow them was the largest remaining gap.
	inv.reset()
	inv.add("rice_ball", 1)
	inv.add("wooden_katana", 1)
	inv.add("wild_herb", 1)
	panel.call("_refresh")
	var all_btn: Button = panel.find_child("BagCategory_all", true, false)
	var gear_btn: Button = panel.find_child("BagCategory_gear", true, false)
	var fav_btn: Button = panel.find_child("BagCategory_favorites", true, false)
	var search_box: LineEdit = panel.find_child("BagSearch", true, false)
	check_true("the bag offers a category filter and a search box",
		all_btn != null and gear_btn != null and fav_btn != null and search_box != null)
	check_true("All is the default active category", all_btn.button_pressed)

	gear_btn.pressed.emit()
	panel.call("_refresh")
	check_true("Gear shows the equipment item",
		panel.find_child("ItemCard_wooden_katana", true, false) != null)
	check_true("Gear hides a non-gear item",
		panel.find_child("ItemCard_rice_ball", true, false) == null)
	check_true("selecting a category deselects the others",
		gear_btn.button_pressed and not all_btn.button_pressed)

	all_btn.pressed.emit()
	search_box.text = "rice"
	search_box.text_changed.emit("rice")
	panel.call("_refresh")
	check_true("search narrows to a matching name",
		panel.find_child("ItemCard_rice_ball", true, false) != null
		and panel.find_child("ItemCard_wooden_katana", true, false) == null)
	search_box.text = ""
	search_box.text_changed.emit("")

	var herb_favorite: Button = panel.find_child("FavoriteToggle_wild_herb", true, false)
	check_true("an unfavorited item offers a Fav control",
		herb_favorite != null and herb_favorite.text == "Fav")
	herb_favorite.pressed.emit()
	check_true("pressing it marks the item favorited",
		inv.is_favorite("wild_herb"))

	fav_btn.pressed.emit()
	panel.call("_refresh")
	check_true("Favorites shows only the favorited item",
		panel.find_child("ItemCard_wild_herb", true, false) != null
		and panel.find_child("ItemCard_rice_ball", true, false) == null)
	var herb_favorite_now: Button = panel.find_child("FavoriteToggle_wild_herb", true, false)
	check_eq("and its control now reads Unfav", herb_favorite_now.text, "Unfav")

	all_btn.pressed.emit()
	panel.call("_refresh")
	inv.reset()

	panel.call("_set_tab", "character")
	check_true("character tab replaces bag content", character.visible and not bag.visible)
	check_true("character explains learning-derived stats",
		stats.text.contains("Japanese study raises your base stats"))
	# Equipment is grouped by type (Weapon / Armor / Accessories) rather than one
	# flat wrapping row, so "all slots are visible" is checked by name, not by
	# counting one container's children.
	var missing_slots: Array[String] = []
	for slot in InventoryLogic.EQUIPMENT_SLOTS:
		if panel.find_child("EquipSlot_" + String(slot), true, false) == null:
			missing_slots.append(String(slot))
	check_true("every authored equipment slot is visible (%s)" % str(missing_slots),
		missing_slots.is_empty())
	check_true("equipment reads in named type groups",
		panel.find_child("EquipmentGroup_Weapon", true, false) != null
		and panel.find_child("EquipmentGroup_Armor", true, false) != null
		and panel.find_child("EquipmentGroup_Accessories", true, false) != null)
	var points: Label = panel.find_child("AttributePoints", true, false)
	var vitality_plus: Button = panel.find_child("VitalityPlus", true, false)
	var agility_plus: Button = panel.find_child("AgilityPlus", true, false)
	check_true("Character shows the honest Attribute Point budget", points != null)
	check_true("fresh level-1 profile cannot spend an unearned point", vitality_plus.disabled)
	check_true("fresh Agility is disabled only because no point is earned", agility_plus.disabled)
	learning.profile.data["stats"]["xp"] = PlayerStats.XP_PER_LEVEL
	panel.call("_refresh")
	check_true("levelling earns a spendable Attribute Point", not vitality_plus.disabled)
	check_true("levelling also enables the real Agility choice", not agility_plus.disabled)
	agility_plus.pressed.emit()
	check_eq("Character control raises saved Agility",
		learning.profile.build()["allocations"]["agility"], 1)
	check_true("Agility immediately appears in the effective Speed summary",
		stats.text.contains("SPD  6"))
	var agility_saved: Dictionary = root.get_node("SaveGame").load_profile()
	check_eq("Agility allocation is written to disk",
		agility_saved["build"]["allocations"]["agility"], 1)
	var agility_minus: Button = panel.find_child("AgilityMinus", true, false)
	agility_minus.pressed.emit()
	vitality_plus.pressed.emit()
	check_eq("Character control raises saved Vitality",
		learning.profile.build()["allocations"]["vitality"], 1)
	check_true("Vitality immediately appears in the effective HP summary",
		stats.text.contains("HP   24 / 24"))
	var saved: Dictionary = root.get_node("SaveGame").load_profile()
	check_eq("Attribute allocation is written to disk",
		saved["build"]["allocations"]["vitality"], 1)
	var vitality_minus: Button = panel.find_child("VitalityMinus", true, false)
	vitality_minus.pressed.emit()
	check_eq("Character control refunds Vitality for free",
		learning.profile.build()["allocations"]["vitality"], 0)
	learning.profile.data["stats"]["xp"] = 0
	learning.profile.save()

	panel.call("_set_tab", "skills")
	check_true("skills tab replaces character content", skills.visible and not character.visible)
	var summary: Label = panel.find_child("SkillsSummary", true, false)
	var skill_cards: Control = panel.find_child("SkillCards", true, false)
	check_true("skills tab states the six-slot loadout", summary.text.contains("/ 6"))
	check_true("skills tab shows the separate Talent Point budget",
		summary.text.contains("Talent Points"))
	check_true("fresh profile exposes the three real starter skills",
		learning.known_ability_defs().size() == 3)
	var focus_detail: Label = panel.find_child("SkillDetail_focus", true, false)
	check_true("skill cards expose authored use limits and cooldowns",
		focus_detail != null and focus_detail.text.contains("1/turn")
		and focus_detail.text.contains("CD 1 turn"))
	var mana_preview: Control = panel.call("_make_talent_card", db.ability("mana_tea"))
	var mana_detail: Label = mana_preview.find_child("TalentDetail_mana_tea", true, false)
	check_true("immediate buff Talents preview their real effect instead of Power 0",
		mana_detail != null and mana_detail.text.contains("Energy +3")
		and mana_detail.text.contains("1E"))
	mana_preview.free()
	var ward_preview: Control = panel.call("_make_talent_card", db.ability("rune_ward"))
	var ward_detail: Label = ward_preview.find_child("TalentDetail_rune_ward", true, false)
	check_true("timed buff Talents preview value, Energy, and duration",
		ward_detail != null and ward_detail.text.contains("Def +4")
		and ward_detail.text.contains("2E") and ward_detail.text.contains("3 rounds"))
	check_true("audited Rune Ward art renders on its Talent card",
		ward_preview.find_child("AbilityIcon_rune_ward", true, false) != null)
	ward_preview.free()
	var ki_preview: Control = panel.call("_make_talent_card", db.ability("ki_focus"))
	check_true("audited Ki Focus art renders on its Talent card",
		ki_preview.find_child("AbilityIcon_ki_focus", true, false) != null)
	ki_preview.free()
	var shear_preview: Control = panel.call("_make_talent_card", db.ability("spirit_shear"))
	var shear_detail: Label = shear_preview.find_child("TalentDetail_spirit_shear", true, false)
	check_true("debuff Talents preview damage, penalty, cost, and duration",
		shear_detail != null and shear_detail.text.contains("Attack 16")
		and shear_detail.text.contains("DEF -4") and shear_detail.text.contains("3E")
		and shear_detail.text.contains("3 rounds"))
	shear_preview.free()
	var counter_preview: Control = panel.call("_make_talent_card", db.ability("riposte"))
	var counter_detail: Label = counter_preview.find_child("TalentDetail_riposte", true, false)
	check_true("Counter Talents preview guard, return, and Energy",
		counter_detail != null and counter_detail.text.contains("Shield 12")
		and counter_detail.text.contains("Return 8") and counter_detail.text.contains("2E"))
	check_true("audited Riposte art renders on its Talent card",
		counter_preview.find_child("AbilityIcon_riposte", true, false) != null)
	counter_preview.free()
	var parry_preview: Control = panel.call("_make_talent_card", db.ability("perilous_parry"))
	var parry_detail: Label = parry_preview.find_child(
		"TalentDetail_perilous_parry", true, false)
	check_true("Parry Talents preview full block, return, and Energy",
		parry_detail != null and parry_detail.text.contains("Full block")
		and parry_detail.text.contains("Return 14") and parry_detail.text.contains("3E"))
	parry_preview.free()
	var drain_preview: Control = panel.call("_make_talent_card", db.ability("blood_blade"))
	var drain_detail: Label = drain_preview.find_child("TalentDetail_blood_blade", true, false)
	check_true("lifesteal Talents preview damage, drain percent, and Energy",
		drain_detail != null and drain_detail.text.contains("Attack 20")
		and drain_detail.text.contains("Drain 35%") and drain_detail.text.contains("3E"))
	check_true("audited Blood Blade art renders on its Talent card",
		drain_preview.find_child("AbilityIcon_blood_blade", true, false) != null)
	drain_preview.free()
	for ability_id in ["iaido", "pinning_shot", "glyph_storm", "fortress"]:
		var followup_preview: Control = panel.call("_make_talent_card", db.ability(ability_id))
		var followup_icon := followup_preview.find_child(
			"AbilityIcon_" + ability_id, true, false) as TextureRect
		check_true("audited %s follow-up art renders" % ability_id,
			followup_icon != null
			and followup_icon.texture.resource_path == (
				"res://assets/icons/abilities/%s.png" % ability_id))
		followup_preview.free()
	learning.profile.data["stats"]["xp"] = PlayerStats.XP_PER_LEVEL
	panel.call("_refresh")
	var sweep_unlock: Button = panel.find_child("TalentUnlock_sweep", true, false)
	check_true("level 2 exposes an affordable Blade Sweep Talent",
		sweep_unlock != null and not sweep_unlock.disabled)
	sweep_unlock.pressed.emit()
	check_true("Talent control permanently learns the action",
		"sweep" in learning.profile.build()["unlockedAbilities"])
	var iaido_unlock: Button = panel.find_child("TalentUnlock_iaido", true, false)
	var iaido_detail: Label = panel.find_child("TalentDetail_iaido", true, false)
	check_true("the next Samurai Talent remains visible", iaido_unlock != null)
	check_true("the unaffordable follow-up states its TP cost",
		iaido_unlock != null and iaido_unlock.disabled and iaido_unlock.text == "Need 2 TP")
	check_true("multi-hit Talent strength is visible before purchase",
		iaido_detail != null and iaido_detail.text.contains("Attack 11 x2 hits"))
	check_true("the next Samurai Talent now has audited art",
		panel.find_child("AbilityIcon_iaido", true, false) != null)
	check_true("audited Talent art remains visible after learning the action",
		panel.find_child("AbilityIcon_sweep", true, false) != null)
	# The quest log. A quest used to exist only as the objective line read off the
	# giver in the current scene, so finishing one erased it from the game entirely.
	var quest_id := "stock_the_stall"
	# Flags are written through to the saved profile, so a previous run would leave
	# this quest already finished and the "not yet met" case would never be tested.
	learning.profile.set_flag(QuestJournal.started_flag(quest_id), false)
	learning.profile.set_flag(QuestJournal.done_flag(quest_id), false)
	learning.profile.set_flag("hana_first_lesson", false)
	learning.profile.set_flag("expedition_forest_unlocked", false)
	learning.profile.data.erase("raids")
	learning.profile.data.erase("expeditions")
	learning.profile.data.erase("trackedActivity")
	inv.reset()
	var quest: Dictionary = db.quest(quest_id)
	var goal_item := String(quest["goal"]["item"])
	panel.call("_set_tab", "quests")
	panel.call("_refresh")
	check_true("the menu has a quests tab",
		panel.find_child("QuestsTab", true, false) != null)
	check_true("an unmet quest is not listed by name",
		panel.find_child("QuestCard_" + quest_id, true, false) == null)
	check_true("but the player is told there is more out there",
		panel.find_child("QuestsUndiscovered", true, false) != null)
	check_true("locked raids stay out of the Journal",
		panel.find_child("ActivityCard_raid_sushi_prep", true, false) == null)
	check_true("locked expeditions stay out of the Journal",
		panel.find_child("ActivityCard_expedition_forest_lunchbox", true, false) == null)

	learning.profile.set_flag(QuestJournal.started_flag(quest_id))
	inv.add(goal_item, 1)
	panel.call("_refresh")
	var detail: Label = panel.find_child("QuestDetail_" + quest_id, true, false)
	var stage_label: Label = panel.find_child("QuestStage_" + quest_id, true, false)
	var quest_reward: Label = panel.find_child("QuestReward_" + quest_id, true, false)
	var quest_track: Button = panel.find_child(
		"TrackActivity_quest_" + quest_id, true, false)
	check_true("an accepted quest appears in the log", detail != null)
	check_true("it shows collected against the goal",
		detail != null and detail.text.contains("1/%d" % int(quest["goal"]["qty"])))
	check_eq("it reads as in progress", stage_label.text, "In progress")
	check_true("ordinary quests preview their authored reward", quest_reward != null)
	check_true("an active quest can lead the world objective HUD", quest_track != null)
	quest_track.pressed.emit()
	check_eq("tracking a quest persists its typed activity key",
		learning.profile.data.get("trackedActivity"), "quest:" + quest_id)
	quest_track = panel.find_child("TrackActivity_quest_" + quest_id, true, false)
	check_true("the selected Journal action reads as tracked",
		quest_track != null and quest_track.text == "Tracked" and quest_track.disabled)

	inv.add(goal_item, int(quest["goal"]["qty"]) - 1)
	panel.call("_refresh")
	stage_label = panel.find_child("QuestStage_" + quest_id, true, false)
	detail = panel.find_child("QuestDetail_" + quest_id, true, false)
	check_eq("meeting the goal reads as ready", stage_label.text, "Ready to turn in")
	check_true("and says who to return to",
		detail != null and detail.text.contains(String(quest["giver"])))

	# The point of the whole tab: it survives turning the quest in.
	learning.profile.set_flag(QuestJournal.done_flag(quest_id))
	inv.remove(goal_item, int(quest["goal"]["qty"]))
	panel.call("_refresh")
	stage_label = panel.find_child("QuestStage_" + quest_id, true, false)
	check_true("a completed quest is still in the log", stage_label != null)
	check_eq("and is recorded as completed", stage_label.text, "Completed")

	# Structured missions share this Journal, but only after the player has met
	# their real unlock requirements. The card then gives one clear next action.
	learning.profile.set_flag("hana_first_lesson")
	panel.call("_refresh")
	var raid_stage: Label = panel.find_child(
		"ActivityStage_raid_sushi_prep", true, false)
	var raid_detail: Label = panel.find_child(
		"ActivityDetail_raid_sushi_prep", true, false)
	var raid_reward: Label = panel.find_child(
		"ActivityReward_raid_sushi_prep", true, false)
	check_true("an unlocked raid appears in the Journal", raid_stage != null)
	check_eq("a new raid is marked available", raid_stage.text, "Available")
	check_true("the raid card directs the player to its giver",
		raid_detail != null and raid_detail.text.contains("Hana"))
	check_true("the raid previews its real coins and item rewards",
		raid_reward != null and raid_reward.text.contains("80 coins")
		and raid_reward.text.contains("Recipe Stamp")
		and raid_reward.text.contains("2x Rice Ball"))
	check_true("the raid previews its discovered recipe",
		raid_reward != null and raid_reward.text.contains("Hana's Raid Platter recipe"))
	var raid_track: Button = panel.find_child(
		"TrackActivity_raid_sushi_prep", true, false)
	check_true("an available Raid can replace the tracked quest", raid_track != null)
	raid_track.pressed.emit()
	check_eq("the Raid selection persists with its activity type",
		learning.profile.data.get("trackedActivity"), "raid:sushi_prep")

	learning.profile.data["raids"] = {
		"sushi_prep": {"stage": "recall-cleared", "completions": 0},
	}
	panel.call("_refresh")
	raid_stage = panel.find_child("ActivityStage_raid_sushi_prep", true, false)
	raid_detail = panel.find_child("ActivityDetail_raid_sushi_prep", true, false)
	check_eq("a recall-cleared raid exposes its boss step", raid_stage.text, "Boss ready")
	check_true("the raid card names the real boss",
		raid_detail != null and raid_detail.text.contains("Pantry Oni"))

	learning.profile.data["raids"] = {
		"sushi_prep": {"stage": "complete", "completions": 1},
	}
	learning.profile.set_flag("expedition_forest_unlocked")
	panel.call("_refresh")
	var expedition_stage: Label = panel.find_child(
		"ActivityStage_expedition_forest_lunchbox", true, false)
	var expedition_reward: Label = panel.find_child(
		"ActivityReward_expedition_forest_lunchbox", true, false)
	check_true("an unlocked expedition appears in the same Journal",
		expedition_stage != null)
	check_eq("a new expedition is marked available", expedition_stage.text, "Available")
	check_true("the expedition previews its real payout",
		expedition_reward != null and expedition_reward.text.contains("80 coins")
		and expedition_reward.text.contains("3x Moonwood"))
	check_true("the expedition previews its discovered recipe",
		expedition_reward != null and expedition_reward.text.contains("Forest Lunchbox recipe"))
	var expedition_track: Button = panel.find_child(
		"TrackActivity_expedition_forest_lunchbox", true, false)
	check_eq("finishing a tracked Raid falls forward to its unlocked Expedition",
		learning.profile.data.get("trackedActivity"), "expedition:forest_lunchbox")
	check_true("the replacement is visibly selected in the Journal",
		expedition_track != null and expedition_track.text == "Tracked"
		and expedition_track.disabled)

	learning.profile.data["expeditions"] = {
		"forest_lunchbox": {"stage": "objective-recovered", "completions": 0},
	}
	panel.call("_refresh")
	expedition_stage = panel.find_child(
		"ActivityStage_expedition_forest_lunchbox", true, false)
	var expedition_detail: Label = panel.find_child(
		"ActivityDetail_expedition_forest_lunchbox", true, false)
	check_eq("the recovered objective points to recall", expedition_stage.text, "Recall")
	check_true("the expedition card states the next action",
		expedition_detail != null and expedition_detail.text.contains("focused recall"))

	learning.profile.data.erase("raids")
	learning.profile.data.erase("expeditions")
	learning.profile.set_flag("hana_first_lesson", false)
	learning.profile.set_flag("expedition_forest_unlocked", false)
	learning.profile.data.erase("trackedActivity")
	inv.reset()
	panel.call("_set_tab", "bag")

	# Gear comparison, UI_UX_GUIDE section 9: selecting gear shows what would change
	# against the slot's current occupant, and comparing never changes state.
	inv.reset()
	# Two katanas: equipping one leaves a spare in the bag, which is the only way a
	# bag card can be for gear you are already wearing — equipping moves the item
	# out of the bag, so a single copy simply disappears from the grid.
	inv.add("wooden_katana", 2)
	inv.add("bamboo_spear", 1)
	panel.call("_set_tab", "bag")
	panel.call("_refresh")
	var unequipped: Label = panel.find_child("ItemCompare_wooden_katana", true, false)
	var own_stats: Label = panel.find_child("ItemStats_wooden_katana", true, false)
	check_true("gear with an empty slot states its gain once, not twice",
		unequipped != null and own_stats != null
		and own_stats.text.contains("ATK") and not unequipped.visible)

	inv.equip("wooden_katana")
	panel.call("_refresh")
	var equipped_note: Label = panel.find_child("ItemCompare_wooden_katana", true, false)
	check_true("a spare of what you are wearing says so instead of comparing with itself",
		equipped_note != null and equipped_note.text == "Equipped")
	var rival: Label = panel.find_child("ItemCompare_bamboo_spear", true, false)
	check_true("a rival weapon names what it is compared against (%s)"
		% (rival.tooltip_text if rival != null else "missing"),
		rival != null and rival.tooltip_text.contains("Wooden Katana"))
	check_true("the comparison reports the real trade, not just the upside",
		rival != null and rival.text.contains("+1 ATK") and rival.text.contains("-1 SPD"))
	check_eq("comparing never equips anything",
		String(inv.equipment().get("weapon", "")), "wooden_katana")
	inv.reset()

	# The Map and Learning domains, added so the hub matches the six-domain shape in
	# UI_UX_GUIDE section 4 instead of being a bag with extras bolted on.
	panel.call("_set_tab", "map")
	panel.call("_refresh")
	check_true("the hub has a map domain",
		panel.find_child("MapTab", true, false) != null)
	var map_summary: Label = panel.find_child("MapSummary", true, false)
	check_true("the map says how much of the world is open",
		map_summary != null and map_summary.text.contains("regions open"))
	var world_graph: Control = panel.find_child("WorldMapGraph", true, false)
	check_true("the Map domain is a focusable route graph", world_graph != null)
	check_eq("a Valley interior keeps its world-map anchor",
		panel.call("_region_for_scene", "res://src/scenes/interior_house.tscn"),
		"valley_crossroads")
	check_eq("the Expedition keeps its Woods world-map anchor",
		panel.call("_region_for_scene", "res://src/scenes/expedition_forest.tscn"),
		"whispering_woods")
	var built_node: Button = panel.find_child("RegionNode_mountain_pass", true, false)
	check_true("a built region is a playable route node",
		built_node != null and built_node.get_meta("status") == "playable")
	var planned_node: Button = panel.find_child("RegionNode_north_reach", true, false)
	check_true("a region with no scene stays visibly unbuilt",
		planned_node != null and planned_node.text == "?"
		and planned_node.tooltip_text.contains("Not built yet"))
	world_graph.call("focus_region", "mountain_pass", false)
	await process_frame
	var map_detail: Label = panel.find_child("MapRegionDetail", true, false)
	check_true("focused routes show authored level, note, and connection truth",
		map_detail != null and map_detail.text.contains("Lv 10-36")
		and map_detail.text.contains("Rocky climb")
		and map_detail.text.contains("Whispering Woods"))

	panel.call("_set_tab", "learning")
	panel.call("_refresh")
	check_true("the hub has a learning domain",
		panel.find_child("LearningTab", true, false) != null)
	var review_btn: Button = panel.find_child("ReviewNow", true, false)
	check_true("review can be started from the hub, not only from a teacher",
		review_btn != null and review_btn.focus_mode == Control.FOCUS_ALL)
	var learn_summary: Label = panel.find_child("LearningSummary", true, false)
	check_true("the learning domain reports what is due",
		learn_summary != null and learn_summary.text.contains("ready to review"))

	# Pressing Review has to actually open a session, or the button is decoration.
	var opened := {"count": 0}
	bus.learn_open.connect(func(_l, _n, _p): opened["count"] += 1)
	review_btn.pressed.emit()
	await process_frame
	check_eq("Review opens a prepared session", int(opened["count"]), 1)
	check_true("and closes the hub so the session is not behind it",
		not bool(panel.get("_open")))

	# A domain key opens the hub straight onto that domain.
	panel.call("open_at", "map")
	check_eq("a domain shortcut lands on that domain",
		String(panel.get("_active_tab")), "map")
	var input_hints: Node = root.get_node("InputHints")
	input_hints.set_input_method(input_hints.GAMEPAD)
	await process_frame
	var input_hint: Label = panel.find_child("InputHint", true, false)
	check_true("controller Hub copy names shoulder tabs and both close routes",
		input_hint != null and input_hint.text.contains("LB")
		and input_hint.text.contains("RB") and input_hint.text.contains("Menu")
		and input_hint.text.contains("B"))
	var next_tab := InputEventAction.new()
	next_tab.action = "tab_next"
	next_tab.pressed = true
	panel.call("_unhandled_input", next_tab)
	check_eq("RB advances one Hub domain", String(panel.get("_active_tab")), "learning")
	var previous_tab := InputEventAction.new()
	previous_tab.action = "tab_previous"
	previous_tab.pressed = true
	panel.call("_unhandled_input", previous_tab)
	check_eq("LB returns one Hub domain", String(panel.get("_active_tab")), "map")
	input_hints.set_input_method(input_hints.KEYBOARD_MOUSE)
	await process_frame
	check_true("keyboard Hub copy returns to the actual I and Esc bindings",
		input_hint.text.contains("I") and input_hint.text.contains("Esc"))

	var talent_saved: Dictionary = root.get_node("SaveGame").load_profile()
	check_true("Talent unlock is written to disk",
		"sweep" in talent_saved["build"]["unlockedAbilities"])
	learning.profile.build()["unlockedAbilities"] = []
	learning.profile.data["stats"]["xp"] = 0
	learning.profile.save()

	panel.call("_set_open", false)
	paused = true
	var blocked_event := InputEventAction.new()
	blocked_event.action = "open_menu"
	blocked_event.pressed = true
	panel.call("_unhandled_input", blocked_event)
	check_true("menu cannot stack over another paused modal", not menu.visible)
	paused = false

	check_true("controller can interact", _has_joy_button("interact", 0))
	check_true("controller can open settings", _has_joy_button("open_settings", 4))
	check_true("controller can open the player menu", _has_joy_button("open_menu", 6))
	check_true("controller can open the notebook", _has_joy_button("open_notebook", 3))
	check_true("controller shoulders cycle Hub domains",
		_has_joy_button("tab_previous", 9) and _has_joy_button("tab_next", 10))
	check_true("controller X attacks without also opening Journal",
		_has_joy_button("attack", 2) and not _has_any_joy_button("open_journal"))
	check_true("controller Menu opens the Hub without also opening Skills",
		not _has_any_joy_button("open_skills"))

	panel.queue_free()
	await process_frame

	var settings: Node = root.get_node("Settings")
	check_eq("legacy crowded UI sizes migrate to the comfortable default",
		settings.call("_migrate_ui_scale", 1.1, 1), settings.UI_SCALE_DEFAULT)
	check_eq("an explicitly compact legacy UI size is preserved",
		settings.call("_migrate_ui_scale", 0.8, 1), 0.8)
	check_eq("the current format keeps its largest accessibility size",
		settings.call("_migrate_ui_scale", 1.0, settings.UI_SCALE_FORMAT), 1.0)
	check_eq("UI size defaults to the measured comfortable step",
		settings.UI_SCALE_DEFAULT, 0.8)
	check_eq("UI size offers compact through large without the cramped 110% step",
		settings.UI_SCALES, [0.7, 0.8, 0.9, 1.0])
	# Settings live in the hub's System domain now. They used to have their own
	# panel, which meant two places to look for the same four controls.
	var hub := CanvasLayer.new()
	hub.set_script(load("res://src/ui/inventory_panel.gd"))
	root.add_child(hub)
	await process_frame
	hub.call("open_at", "system")
	await process_frame
	check_true("the hub has a system domain",
		hub.find_child("SystemTab", true, false) != null)
	var hub_shell: Control = hub.find_child("MenuShell", true, false)
	if hub_shell == null:
		hub_shell = hub.get("_root") as Control
	check_true("the system domain stays inside the scaled UI canvas",
		hub_shell != null and viewport_rect.encloses(hub_shell.get_global_rect()))
	var music_slider := hub.find_child("MusicVolumeSlider", true, false) as HSlider
	var voice_slider := hub.find_child("VoiceVolumeSlider", true, false) as HSlider
	check_true("settings expose music and pronunciation volume",
		music_slider != null and voice_slider != null)
	music_slider.value = 0.5
	check_eq("music slider writes the setting", settings.music_volume, 0.5)
	voice_slider.value = 0.25
	check_eq("pronunciation slider writes the setting", settings.voice_volume, 0.25)
	settings.music_volume = 1.0
	settings.voice_volume = 1.0

	# The Bestiary. PORT_NOTES.md and COMBAT_DESIGN.md both mention a Compendium
	# tab and "bestiary flags" from the legacy build that never made it into this
	# port — there was no way to answer "what have I fought" at all.
	learning.profile.data.erase("bestiary")
	var bestiary_enemy_id := "mushroom"
	hub.call("open_at", "bestiary")
	hub.call("_refresh")
	await process_frame
	check_true("the hub has a bestiary domain",
		hub.find_child("BestiaryTab", true, false) != null)
	check_true("an unfought enemy is not named",
		hub.find_child("BestiaryCard_" + bestiary_enemy_id, true, false) == null)
	check_true("but the player is told there is more out there",
		hub.find_child("BestiaryUndiscovered", true, false) != null)

	bus.combat_started.emit(bestiary_enemy_id)
	hub.call("_refresh")
	await process_frame
	var bestiary_stage: Label = hub.find_child(
		"BestiaryStage_" + bestiary_enemy_id, true, false)
	check_true("fighting it reveals the card", bestiary_stage != null)
	check_eq("and reads as encountered, not defeated",
		bestiary_stage.text, "Encountered")

	bus.enemy_died.emit(bestiary_enemy_id)
	hub.call("_refresh")
	await process_frame
	bestiary_stage = hub.find_child("BestiaryStage_" + bestiary_enemy_id, true, false)
	var drops_label: Label = hub.find_child(
		"BestiaryDrops_" + bestiary_enemy_id, true, false)
	check_true("winning reads as defeated (%s)"
		% (bestiary_stage.text if bestiary_stage != null else "missing"),
		bestiary_stage != null and bestiary_stage.text.begins_with("Defeated"))
	check_true("and the card now lists what it actually drops",
		drops_label != null and drops_label.text.contains(
			String(db.item("spore_cap").get("name", "spore_cap"))))
	learning.profile.data.erase("bestiary")
	learning.profile.save()

	hub.call("_set_open", false)
	hub.queue_free()
	await process_frame
	check_true("Notebook also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/notebook_panel.gd", "open_notebook"))
	# open_settings now routes into the hub, so the hub's own modal guard is what
	# has to hold for it — the separate settings panel no longer exists.
	check_true("the settings key also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/inventory_panel.gd", "open_settings"))
	_finish()


func _has_joy_button(action: String, button_index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false


func _has_any_joy_button(action: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			return true
	return false


func _panel_rejects_paused_open(script_path: String, action: String) -> bool:
	var modal := CanvasLayer.new()
	modal.set_script(load(script_path))
	root.add_child(modal)
	await process_frame
	paused = true
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	modal.call("_unhandled_input", event)
	var rejected := not bool(modal.get("_open"))
	paused = false
	modal.queue_free()
	await process_frame
	return rejected


func _finish() -> void:
	print("")
	print(("PASS — Player menu domains, modal safety, and controller routes hold."
		if failures == 0 else "FAIL — %d player-menu check(s) failed." % failures))
	quit(1 if failures > 0 else 0)


func check_true(label: String, ok: bool) -> void:
	print(("  ok   " if ok else "  FAIL ") + label)
	if not ok:
		failures += 1


func check_eq(label: String, got, want) -> void:
	check_true("%s (got %s, want %s)" % [label, got, want], got == want)
