extends SceneTree
## Player-menu UX contract: real Character/Bag domains, honest stats, modal safety,
## and controller routes through the InputMap.

var failures: int = 0


func _initialize() -> void:
	await process_frame
	# Earlier suites deliberately exercise persistence in the same isolated APPDATA root.
	# Pin this UI contract to an actual fresh build instead of inheriting their XP.
	var learning: Node = root.get_node("Learning")
	var db: Node = root.get_node("DB")
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
	var slots: Control = panel.find_child("EquipmentSlots", true, false)
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
	var viewport_rect := root.get_viewport().get_visible_rect()
	check_true("menu shell stays inside the 640x360 viewport",
		viewport_rect.encloses(shell.get_global_rect()))

	panel.call("_set_tab", "character")
	check_true("character tab replaces bag content", character.visible and not bag.visible)
	check_true("character explains learning-derived stats",
		stats.text.contains("Japanese study raises your base stats"))
	check_eq("all authored equipment slots are visible",
		slots.get_child_count(), InventoryLogic.EQUIPMENT_SLOTS.size())
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
	check_true("audited Talent art remains visible after learning the action",
		panel.find_child("AbilityIcon_sweep", true, false) != null)
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

	panel.queue_free()
	await process_frame
	check_true("Notebook also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/notebook_panel.gd", "open_notebook"))
	check_true("Settings also rejects paused modal stacking",
		await _panel_rejects_paused_open(
			"res://src/ui/settings_panel.gd", "open_settings"))
	_finish()


func _has_joy_button(action: String, button_index: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton \
				and (event as InputEventJoypadButton).button_index == button_index:
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
