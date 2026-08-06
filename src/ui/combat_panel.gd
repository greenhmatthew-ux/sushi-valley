extends CanvasLayer
## Turn-based recall combat. The enemy raises a guard word; your four moves are Japanese
## runes and picking the matching one IS the attack — no quiz popup in front of the game.
##
## EncounterDirector-driven: opens only for its owned token and resolves that same token.
## Legacy combat_started/combat_ended remain lifecycle notifications for other UI/audio.
## All rules live in the pure CombatEncounter; this only renders it and feeds it choices.
##
## Every round's card comes from the ONE shared scheduler (Learning.build_prompt) and every
## answer goes back through Learning.answer(), so fighting IS reviewing — combat owns no
## deck and no schedule of its own (SITE_WIDE_LEARNING_ARCHITECTURE.md).

const ConsumableRules = preload("res://src/systems/consumable_logic.gd")
const Roles = preload("res://src/systems/role_logic.gd")
## Picks and plays an attack effect from the ability's own style/type/hits.
const CombatFx = preload("res://src/ui/combat_fx.gd")

const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_TEXT := UiTheme.TEXT_PRIMARY
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_EN := UiTheme.STATE_INFO
const COL_GOOD := UiTheme.STATE_SUCCESS
const COL_BAD := UiTheme.STATE_DANGER
const COL_BTN := UiTheme.SURFACE_RAISED
const COL_BTN_BORDER := UiTheme.BORDER_STRONG

var _active := false
var _encounter_token := ""
var _encounter: CombatEncounter
var _current_card: Dictionary = {}
var _challenge: Dictionary = {}
var _answered := false
var _rng := RandomNumberGenerator.new()
var _weapon_name := "Unarmed"

## Rendered at 3x the 16px sheet frame, so the foe reads at a glance without the panel
## having to give up a row to it.
const PORTRAIT_PX := 48
## How hard a struck target punches, and for how long. Short and small on purpose: the
## point is to make a hit register, not to hold up the round.
const HIT_PUNCH := 1.12
const HIT_SECONDS := 0.26
## How long the win/loss beat holds before the panel closes. Long enough to read the result,
## short enough that clearing a patrol of foes does not become a slideshow.
const OUTCOME_SECONDS := 0.85
## The wind-up pulse: a warm threat tint, slow enough to read as breathing rather than a
## strobe. Half a second each way.
const TELEGRAPH_TINT := Color(1.0, 0.55, 0.45)
const TELEGRAPH_SECONDS := 0.5
## Idle breathing for the foe. The portrait was one frozen frame of a walk sheet, so the
## enemy sat perfectly still through its own turn -- the single biggest reason combat did not
## read as a fight. This cycles the sheet's walk rows in place.
##
## Well below the 8fps walk cadence: at walking speed a foe standing in a menu looks like it
## is jogging on the spot. At 3 it reads as shifting its weight.
const IDLE_FPS := 3.0
## The attack cadence. Snapping to walk speed for the moment it strikes is what separates
## "the number changed" from "it lunged at me".
const STRIKE_FPS := 10.0
const STRIKE_SECONDS := 0.34

var _root: Control
var _hit_layer: Control
var _telegraph: Tween
var _enemy_portrait: TextureRect
## The foe's walk sheet, kept so the portrait can animate instead of holding one frame.
var _portrait_sheet: Texture2D
var _portrait_rows := 0
var _portrait_phase := 0.0
var _strike_left := 0.0
var _enemy_label: Label
var _enemy_hp_bar: ProgressBar
var _intent_label: Label
var _player_hp_bar: ProgressBar
var _flow_label: Label
var _energy_label: Label
var _guard_label: Label
var _guard_hint: Label
var _feedback: Label
var _action_box: HBoxContainer
var _action_buttons: Dictionary = {}
var _selected_ability: Dictionary = {}
var _choices_box: GridContainer
var _continue_btn: Button
var _end_turn_btn: Button
var _listen_btn: Button
var _flee_btn: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build()
	_root.hide()
	Bus.combat_requested.connect(_on_combat_requested)
	Bus.language_changed.connect(func(_v): if _active: _refresh_guard_hint())
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))


func _on_combat_requested(token: String, enemy_id: String) -> void:
	if _active:
		return
	_encounter_token = token
	var enemy: Dictionary = DB.enemy(enemy_id)
	if enemy.is_empty():
		push_warning("[Combat] unknown enemy '%s'" % enemy_id)
		_encounter_token = ""
		EncounterDirector.resolve(token, false)
		return

	# Stats come from the player, which derives them from learning level (PlayerStats) —
	# so studying is what makes a fight winnable. A simulation of the ported enemy numbers
	# against the old flat 12 HP showed the kappa and lantern were unwinnable at 0%.
	var player := get_tree().get_first_node_in_group("player")
	var hp: int = player.hp if player != null else PlayerStats.BASE_MAX_HP
	var max_hp: int = player.MAX_HP if player != null else PlayerStats.BASE_MAX_HP
	var p_atk: int = player.atk if player != null else PlayerStats.BASE_ATK
	var p_def: int = player.defense if player != null else PlayerStats.BASE_DEF
	var p_speed: int = player.speed if player != null else PlayerStats.BASE_SPEED
	var weapon: Dictionary = Inv.equipped_def("weapon")
	_weapon_name = String(weapon.get("name", "Unarmed"))
	var role_id := Roles.role_for_weapon_type(String(weapon.get("weaponType", "")))

	_encounter = CombatEncounter.new(enemy, hp, max_hp, p_atk, p_def, p_speed, role_id)
	_selected_ability = {}
	_active = true
	get_tree().paused = true
	_enemy_label.text = _encounter.enemy_name
	_set_enemy_portrait(enemy_id)
	_flee_btn.show()
	_root.show()
	if CombatEncounter.player_acts_first(_encounter.player_speed, _encounter.enemy_speed):
		_encounter.begin_player_round()
		_next_round()
	else:
		_show_enemy_opening()


func _show_enemy_opening() -> void:
	_answered = true
	_challenge = {}
	_build_actions()
	var result := _encounter.enemy_opening_turn()
	_guard_label.text = "%s strikes first" % _encounter.enemy_name
	_guard_hint.text = "Enemy SPD %d beats your SPD %d." % [
		_encounter.enemy_speed, _encounter.player_speed]
	_feedback.add_theme_color_override("font_color", COL_BAD)
	_feedback.text = "%s opens for %d damage." % [
		_encounter.enemy_name, result.enemy_damage_dealt]
	_show_hit(_player_hp_bar, result.enemy_damage_dealt, COL_BAD)
	_strike_portrait()
	if result.enemy_damage_dealt > 0:
		CombatFx.play(_hit_layer, _player_hp_bar, "claw", CombatFx.TINTS["enemy"])
	_render_bars()
	_end_turn_btn.hide()
	_continue_btn.text = "Continue" if _encounter.is_over() else "Your turn"
	_continue_btn.show()
	_continue_btn.grab_focus()


## Draw the next card from the shared scheduler and turn it into a rune challenge.
func _next_round() -> void:
	_answered = false
	_continue_btn.hide()
	_end_turn_btn.show()
	_listen_btn.hide()   # the answer is hidden again, so its recording must be too
	_feedback.text = ""
	_challenge = {}
	_build_actions()

	var prompt: Dictionary = Learning.build_prompt({}, true)
	if prompt.is_empty():
		# Nothing unlocked yet — end gracefully rather than stalling in a fight you
		# structurally cannot act in.
		_finish(false, "You have not learned any words yet.")
		return

	_current_card = prompt["card"]
	_challenge = CombatEncounter.build_challenge(_current_card, Learning.profile.unlocked_cards(), _rng, 4)
	_refresh_guard_hint()
	_render_bars()

	for child in _choices_box.get_children():
		child.queue_free()
	var first: Button = null
	for rune in _challenge["choices"]:
		var b := _rune_button(String(rune))
		_choices_box.add_child(b)
		if first == null:
			first = b
	if first != null:
		first.grab_focus.call_deferred()


func _refresh_guard_hint() -> void:
	# The guard word is the MEANING — the player must produce the Japanese for it.
	_guard_label.text = String(_challenge.get("guard", ""))
	var action_name := String(_selected_ability.get("name", "Basic Attack"))
	_guard_hint.text = "%s: choose the matching rune" % action_name if not Settings.english_visible() \
		else "%s: choose the rune meaning \"%s\"" % [action_name, _challenge.get("guard", "")]


## The foe's own walk-sheet still, honouring `spriteAlias` the way the Bestiary does — the
## JSON `sprite` field is inherited from the source pack's naming and does not resolve for
## most of the roster. Hidden rather than shown as a placeholder box when no art exists.
func _set_enemy_portrait(enemy_id: String) -> void:
	if _enemy_portrait == null:
		return
	var enemy: Dictionary = DB.enemy(enemy_id)
	var sprite_id := String(enemy.get("spriteAlias", enemy.get("sprite", "")))
	var path := "res://assets/sprites/%s.png" % sprite_id
	var texture: Texture2D = load(path) as Texture2D if \
		not sprite_id.is_empty() and ResourceLoader.exists(path) else null
	_enemy_portrait.texture = SpriteSheets.portrait(texture) if texture != null else null
	_enemy_portrait.visible = texture != null
	_enemy_portrait.modulate = Color.WHITE
	_enemy_portrait.position = Vector2.ZERO
	# Keep the sheet so the portrait can be animated in place. A one-row sheet has no walk
	# cycle to play, so it simply stays the still it already was.
	_portrait_sheet = texture
	_portrait_rows = SpriteSheets.row_count(texture) if texture != null else 0
	_portrait_phase = 0.0
	_strike_left = 0.0
	set_process(_portrait_rows > 1)


## Cycle the foe's own walk rows in place: slow while it waits, briefly fast when it strikes.
##
## Only the AtlasTexture's region is touched. The portrait is a container child, and the same
## reason position tweens were rejected for the hit punch applies here -- the container owns
## its children's position and size, and fighting it parked a bar at the top of the panel.
## A region swap changes nothing the layout cares about.
func _process(delta: float) -> void:
	if _portrait_rows <= 1 or _enemy_portrait == null:
		return
	var atlas := _enemy_portrait.texture as AtlasTexture
	if atlas == null:
		return
	var fps := IDLE_FPS
	if _strike_left > 0.0:
		_strike_left -= delta
		fps = STRIKE_FPS
	_portrait_phase = fmod(_portrait_phase + delta * fps, float(_portrait_rows))
	var frame := int(_portrait_phase)
	atlas.region = Rect2i(Vector2i(0, frame) * SpriteSheets.FRAME_SIZE, SpriteSheets.FRAME_SIZE)


## Kick the portrait into its fast cadence for one beat, so the foe visibly moves on the turn
## it hits you rather than only the HP bar moving.
func _strike_portrait() -> void:
	_strike_left = STRIKE_SECONDS


## Make a hit look like one: the struck side flashes its colour and lurches, and the number
## floats off it. Combat reported damage only in a sentence, so a big hit and a scratch felt
## identical — the bar moved and the text changed, and nothing else happened.
func _show_hit(target: Control, amount: int, tint: Color) -> void:
	if target == null or amount <= 0 or not is_inside_tree():
		return
	_flash(target, tint)
	_float_damage(target, amount, tint)


## Colour flash plus a scale punch.
##
## Deliberately NOT a position shake: these are container children, and a container owns its
## children's position and size. Tweening `position` fought the layout and left the player's
## HP bar parked at the top of the panel. Scale is not managed by the container, so it is the
## one transform that can punch without moving anything.
func _flash(target: Control, tint: Color) -> void:
	if not target.visible:
		return
	target.pivot_offset = target.size * 0.5
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(target, "modulate", tint, HIT_SECONDS * 0.25)
	tween.chain().tween_property(target, "modulate", Color.WHITE, HIT_SECONDS * 0.75)
	var punch := create_tween()
	punch.tween_property(target, "scale", Vector2.ONE * HIT_PUNCH, HIT_SECONDS * 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch.tween_property(target, "scale", Vector2.ONE, HIT_SECONDS * 0.75) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _float_damage(anchor: Control, amount: int, tint: Color) -> void:
	# The opening hit lands in the same frame the shell is first shown, before anything has
	# a rect — anchoring then put the number in the screen corner. Wait for the layout.
	await get_tree().process_frame
	if _hit_layer == null or not is_instance_valid(anchor) or not is_inside_tree():
		return
	var number := Label.new()
	number.name = "HitNumber"
	number.text = "-%d" % amount
	number.add_theme_font_size_override("font_size", 20)
	number.add_theme_color_override("font_color", tint)
	number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	number.add_theme_constant_override("outline_size", 4)
	number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_layer.add_child(number)
	# Anchor in the overlay's own space: the whole layer is scaled by the UI-scale setting,
	# so a raw global position would drift at anything other than 100%.
	var to_local := _hit_layer.get_global_transform().affine_inverse()
	number.position = to_local * anchor.get_global_rect().get_center() - Vector2(8, 12)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(number, "position:y", number.position.y - 26.0, HIT_SECONDS * 3.0)
	tween.tween_property(number, "modulate:a", 0.0, HIT_SECONDS * 3.0).set_delay(HIT_SECONDS)
	tween.chain().tween_callback(number.queue_free)


func _render_bars() -> void:
	_enemy_hp_bar.max_value = _encounter.enemy_max_hp
	_enemy_hp_bar.value = _encounter.enemy_hp
	var enemy_status := _encounter.enemy_debuff_summary()
	_enemy_label.text = _encounter.enemy_name + (
		" · " + enemy_status if not enemy_status.is_empty() else "")
	_enemy_label.tooltip_text = "Active enemy effects: " + enemy_status \
		if not enemy_status.is_empty() else ""
	_player_hp_bar.max_value = _encounter.player_max_hp
	_player_hp_bar.value = _encounter.player_hp
	_render_enemy_intent()
	_flow_label.text = ("Flow x%d" % _encounter.flow) if _encounter.flow > 0 else ""
	var speed_note := " · Extra turn" if _encounter.bonus_turn else ""
	var buffs := _encounter.timed_buff_summary()
	_energy_label.text = "Energy %d/%d · SPD %d · %s%s%s" % [
		_encounter.energy, _encounter.max_energy, _encounter.effective_speed(),
		_weapon_name, speed_note, " · " + buffs if not buffs.is_empty() else ""]


func _render_enemy_intent() -> void:
	if _encounter.is_over():
		_intent_label.text = ""
		_intent_label.tooltip_text = ""
		_set_telegraph(false)
		return
	var damage := _encounter.enemy_damage_range()
	_intent_label.text = "[!] Attack %d-%d HP" % [damage.x, damage.y]
	var timing := "after %d End Turns" % _encounter.turns_left if _encounter.turns_left > 1 \
		else "after End Turn"
	var guard_note := " Full Parry blocks this hit." if _encounter.full_parry_ready \
		else (" Current Guard is included." if _encounter.shield > 0 else "")
	_intent_label.tooltip_text = "%s will use a basic attack %s. Damage varies by 15%%.%s" % [
		_encounter.enemy_name, timing, guard_note]
	_set_telegraph(_encounter.turns_left <= 1)


## The foe winds up when its blow lands on the next End Turn.
##
## "It will hit you this turn" was information the player could only get by reading a small
## line in the panel corner, so the difference between a safe turn and the dangerous one was
## invisible at a glance. The foe itself now shows it.
##
## Pulses `self_modulate`, deliberately not `modulate`: hits tween `modulate`, and a looping
## tween on the same property would fight every strike and leave the portrait stuck at
## whatever colour the loop was mid-way through.
func _set_telegraph(winding_up: bool) -> void:
	if _enemy_portrait == null:
		return
	if _telegraph != null and _telegraph.is_valid():
		_telegraph.kill()
	_telegraph = null
	_enemy_portrait.self_modulate = Color.WHITE
	if not winding_up or not _enemy_portrait.visible:
		return
	_telegraph = create_tween()
	_telegraph.set_loops()
	_telegraph.tween_property(_enemy_portrait, "self_modulate",
		TELEGRAPH_TINT, TELEGRAPH_SECONDS)
	_telegraph.tween_property(_enemy_portrait, "self_modulate",
		Color.WHITE, TELEGRAPH_SECONDS)


func _on_rune(rune: String, btn: Button) -> void:
	if _answered:
		return
	_answered = true

	var result: CombatEncounter.RoundResult = _encounter.spend_and_resolve(
		rune, _challenge["answer"], _selected_ability)
	if not result.action_resolved:
		_answered = false
		Bus.toast.emit("That action needs more Energy.")
		return
	# Feed the shared SRS — this is what makes fighting count as review.
	Learning.answer(_current_card, String(_current_card.get("answer", "")) if result.correct else "__wrong__")

	btn.add_theme_stylebox_override("normal", _button_style(
		UiTheme.FILL_CORRECT if result.correct else UiTheme.FILL_WRONG, COL_BORDER))
	if not result.correct:
		for other in _choices_box.get_children():
			if other is Button and (other as Button).text == String(_challenge["answer"]):
				other.add_theme_stylebox_override("normal", _button_style(UiTheme.FILL_CORRECT, COL_BORDER))

	# Hear the word at the moment it is revealed. Combat asks for the Japanese, so
	# this cannot play before the answer without giving it away — but the reveal is
	# where pronunciation actually sticks, win or lose, and it is the same beat the
	# notebook's recall panel uses.
	var card_id := String(_current_card.get("id", ""))
	Audio.play_pronunciation(card_id)
	_listen_btn.visible = Audio.has_pronunciation(card_id)

	_render_bars()
	_feedback.add_theme_color_override("font_color", COL_GOOD if result.correct else COL_BAD)
	var action_name := String(_selected_ability.get("name", "Basic Attack"))
	var outcome := ""
	if result.energy_restored > 0:
		outcome = "%s restored %d Energy." % [action_name, result.energy_restored]
	elif not result.buff_type.is_empty():
		outcome = "%s granted %s +%d for %d rounds." % [action_name,
			CombatEncounter.stat_label(result.buff_type), result.buff_value, result.buff_rounds]
	elif result.action_type == "heal":
		outcome = "%s restored %d HP." % [action_name, result.player_healed]
	elif result.action_type in ["counter", "parry"]:
		outcome = "%s armed %s and %d return damage." % [action_name,
			"a full parry" if result.parry_armed else "%d shield" % result.shield_gained,
			result.counter_damage_armed]
	elif result.action_type == "block" or result.shield_gained > 0:
		outcome = "%s raised %d shield." % [action_name, result.shield_gained]
	else:
		outcome = "%s hit for %d." % [action_name, result.player_damage_dealt]
	if float(_selected_ability.get("lifestealPct", 0.0)) > 0.0:
		outcome += " Drained %d HP." % result.player_healed
	if not result.debuff_type.is_empty():
		outcome += " Enemy %s -%d for %d rounds." % [
			CombatEncounter.stat_label(result.debuff_type),
			result.debuff_value, result.debuff_rounds]
	# A miss is the one moment the player is definitely paying attention to the
	# right answer, so spend it: show how the rune is actually read, not just what
	# it looked like. Silent when the card carries no reading rather than padding
	# the line with empty brackets.
	var reading := String(_current_card.get("reading", "")).strip_edges()
	var revealed := "%s (%s)" % [result.answer, reading] if not reading.is_empty() \
		else String(result.answer)
	_feedback.text = outcome if result.correct \
		else "%s was the rune. Weakened %s" % [revealed, outcome]
	_show_hit(_enemy_portrait, result.player_damage_dealt, COL_BAD)
	if result.player_damage_dealt > 0:
		CombatFx.play(_hit_layer, _enemy_portrait,
			CombatFx.effect_for(_selected_ability), CombatFx.tint_for(_selected_ability))
	if result.correct and result.flow_after > 1:
		_feedback.text += "   Flow x%d" % result.flow_after
	if _encounter.is_over():
		_flee_btn.hide()
		_end_turn_btn.hide()
		_continue_btn.text = "Continue"
	elif _encounter.energy <= 0:
		_resolve_end_turn()
	else:
		_continue_btn.text = "Act again"
	_continue_btn.show()
	_continue_btn.grab_focus()


func _on_continue() -> void:
	if _encounter.is_over():
		var won := _encounter.player_won()
		await _play_outcome(won)
		_finish(won, "")
	else:
		_next_round()


## A fight used to end by the panel simply vanishing on the frame you pressed Continue —
## no death, no result, nothing to register that you had won. This is the beat: the loser
## goes down, the outcome is named, and only then does the panel close.
##
## Only the natural end gets it. Fleeing and the no-cards bail exit immediately, because
## neither is an outcome worth dwelling on.
func _play_outcome(victory: bool) -> void:
	_continue_btn.hide()
	_end_turn_btn.hide()
	_flee_btn.hide()
	_listen_btn.hide()
	for choice in _choices_box.get_children():
		if choice is Button:
			(choice as Button).hide()
	_intent_label.text = ""
	_set_telegraph(false)
	_guard_label.add_theme_color_override("font_color", COL_GOOD if victory else COL_BAD)
	_guard_label.text = "%s defeated" % _encounter.enemy_name if victory else "You are down"
	_guard_hint.text = "" if victory else "You wake at the village, worse for wear."

	if victory and _enemy_portrait.visible:
		# The foe falls: it drops, greys out and fades rather than blinking off.
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(_enemy_portrait, "modulate",
			Color(0.4, 0.4, 0.4, 0.0), OUTCOME_SECONDS * 0.8)
		tween.tween_property(_enemy_portrait, "scale", Vector2(1.0, 0.25), OUTCOME_SECONDS * 0.8) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	elif not victory:
		_flash(_player_hp_bar, COL_BAD)

	# The tree is paused for the whole fight, so the timer has to run anyway.
	await get_tree().create_timer(OUTCOME_SECONDS, true, false, true).timeout
	_guard_label.remove_theme_color_override("font_color")
	_enemy_portrait.modulate = Color.WHITE
	_enemy_portrait.scale = Vector2.ONE


func _on_end_turn() -> void:
	if not _active or _encounter == null or _encounter.is_over() \
			or not _end_turn_btn.visible:
		return
	_resolve_end_turn()


func _on_flee() -> void:
	if not _active or _encounter == null or _encounter.is_over():
		return
	_finish(false, "You fled the fight.")


func _on_listen() -> void:
	Audio.stop_pronunciation()
	Audio.play_pronunciation(String(_current_card.get("id", "")))


func _resolve_end_turn() -> void:
	_answered = true
	_end_turn_btn.hide()
	for choice in _choices_box.get_children():
		if choice is Button:
			(choice as Button).disabled = true
	if _feedback.text.is_empty():
		_feedback.text = "Turn ended."
	var result := _encounter.end_player_turn()
	if result.bonus_turn_granted:
		_feedback.add_theme_color_override("font_color", COL_EN)
		_feedback.text += "   Speed grants another full turn."
	elif result.enemy_acted:
		if result.shield_absorbed > 0:
			_feedback.text += "   Blocked %d." % result.shield_absorbed
		if result.enemy_damage_dealt > 0:
			_feedback.text += "   %s hits for %d." % [
				_encounter.enemy_name, result.enemy_damage_dealt]
		if result.counter_damage_dealt > 0:
			_feedback.text += "   Returned %d damage." % result.counter_damage_dealt
		_show_hit(_player_hp_bar, result.enemy_damage_dealt, COL_BAD)
		_strike_portrait()
		if result.enemy_damage_dealt > 0:
			CombatFx.play(_hit_layer, _player_hp_bar, "claw", CombatFx.TINTS["enemy"])
		_show_hit(_enemy_portrait, result.counter_damage_dealt, COL_GOOD)
		if result.counter_damage_dealt > 0:
			CombatFx.play(_hit_layer, _enemy_portrait, "clawdouble", CombatFx.TINTS["counter"])
	_render_bars()
	_continue_btn.text = "Continue" if _encounter.is_over() \
		else ("Bonus turn" if result.bonus_turn_granted else "Next turn")
	_continue_btn.show()
	_continue_btn.grab_focus()


func _build_actions() -> void:
	for child in _action_box.get_children():
		_action_box.remove_child(child)
		child.queue_free()
	_action_buttons.clear()
	_add_action_button({}, "Basic", "Reliable light attack; repeat while Energy remains.")
	var weapon_type := String(Inv.equipped_def("weapon").get("weaponType", ""))
	for ability in Learning.usable_ability_defs(weapon_type):
		_add_action_button(ability, String(ability.get("name", ability.get("id", "Skill"))),
			String(ability.get("desc", "")))
	var combat_items: Array[Dictionary] = []
	for entry in Inv.entries():
		var item: Dictionary = DB.item(String(entry.get("id", "")))
		if ConsumableRules.is_supported_combat_item(item):
			combat_items.append({"item": item, "qty": int(entry.get("qty", 0)), "prepared": false})
	var prepared_item: Dictionary = Inv.prepared_meal_def()
	if ConsumableRules.is_preparation_meal(prepared_item):
		combat_items.append({"item": prepared_item, "qty": 1, "prepared": true})
	if not combat_items.is_empty():
		_add_items_menu(combat_items)
	var selected_id := String(_selected_ability.get("id", "basic_attack"))
	if not _action_buttons.has(selected_id) \
			or (_action_buttons[selected_id] as Button).disabled:
		selected_id = "basic_attack"
	_select_action(selected_id)


func _add_action_button(ability: Dictionary, label: String, tooltip: String) -> void:
	var button := Button.new()
	var id := String(ability.get("id", "basic_attack"))
	var cost := CombatEncounter.action_cost(ability)
	var status := _encounter.ability_status(ability)
	button.text = "%s · %dE%s" % [label, cost, " · " + status if not status.is_empty() else ""]
	var cadence: Array[String] = []
	var use_limit := maxi(0, int(ability.get("maxUsesPerTurn", 0)))
	var cooldown := maxi(0, int(ability.get("cooldownTurns", 0)))
	var buff_type := String(ability.get("buffType", ""))
	var buff_duration := maxi(0, int(ability.get("buffDuration", 0)))
	var debuff_type := String(ability.get("debuffType", ""))
	var debuff_duration := maxi(0, int(ability.get("debuffDuration", 0)))
	if use_limit > 0:
		cadence.append("Up to %d use%s per turn." % [use_limit, "" if use_limit == 1 else "s"])
	if cooldown > 0:
		cadence.append("Cooldown: %d full turn%s." % [cooldown, "" if cooldown == 1 else "s"])
	if buff_type in ["atk", "def", "speed"] and buff_duration > 0:
		cadence.append("Lasts %d enemy-response rounds." % buff_duration)
	if debuff_type in ["atk", "def", "speed"] and debuff_duration > 0:
		cadence.append("Debuff lasts %d enemy-response rounds." % debuff_duration)
	button.tooltip_text = "%s\nCosts %d Energy.%s" % [
		tooltip, cost, " " + " ".join(cadence) if not cadence.is_empty() else ""]
	button.custom_minimum_size = Vector2(72, 28)
	button.focus_mode = Control.FOCUS_ALL
	button.toggle_mode = true
	button.disabled = not _encounter.can_use_ability(ability)
	button.pressed.connect(_select_action.bind(id))
	button.set_meta("ability", ability)
	_action_box.add_child(button)
	_action_buttons[id] = button


func _add_items_menu(entries: Array[Dictionary]) -> void:
	var button := MenuButton.new()
	button.name = "CombatItems"
	button.text = "Items (%d)" % entries.size()
	button.tooltip_text = "Use one item per turn. Unhelpful items stay disabled."
	button.custom_minimum_size = Vector2(90, 28)
	button.focus_mode = Control.FOCUS_ALL
	var popup := button.get_popup()
	var any_usable := false
	for entry in entries:
		var item: Dictionary = entry.get("item", {})
		var item_id := String(item.get("id", ""))
		var prepared := bool(entry.get("prepared", false))
		var index := popup.item_count
		popup.add_item(("Prepared · %s" if prepared else "%s x%d") % (
			[item.get("name", item_id)] if prepared else [item.get("name", item_id), int(entry.get("qty", 0))]), index)
		popup.set_item_metadata(index, {"item_id": item_id, "prepared": prepared})
		popup.set_item_tooltip(index, "%s\n%s" % [
			item.get("desc", ""), ConsumableRules.effect_summary(item)])
		var usable := _encounter.can_use_prepared_meal(item) if prepared \
			else _encounter.can_use_combat_item(item)
		popup.set_item_disabled(index, not usable)
		any_usable = any_usable or usable
	popup.id_pressed.connect(_on_combat_item_menu.bind(popup))
	button.disabled = not any_usable
	_action_box.add_child(button)


func _on_combat_item_menu(id: int, popup: PopupMenu) -> void:
	var index := popup.get_item_index(id)
	if index >= 0:
		var metadata: Dictionary = popup.get_item_metadata(index)
		_on_combat_item(String(metadata.get("item_id", "")), bool(metadata.get("prepared", false)))


func _select_action(ability_id: String) -> void:
	if not _action_buttons.has(ability_id):
		ability_id = "basic_attack"
	var button: Button = _action_buttons[ability_id]
	_selected_ability = (button.get_meta("ability", {}) as Dictionary).duplicate(true)
	for id in _action_buttons:
		(_action_buttons[id] as Button).button_pressed = String(id) == ability_id
	if not _challenge.is_empty():
		_refresh_guard_hint()


func _on_combat_item(item_id: String, prepared: bool = false) -> void:
	if _answered or not _encounter.can_use_item():
		return
	var item: Dictionary = DB.item(item_id)
	var usable := _encounter.can_use_prepared_meal(item) if prepared \
		else _encounter.can_use_combat_item(item)
	if not usable:
		Bus.toast.emit("That item cannot be used right now.")
		return
	var result: CombatEncounter.RoundResult
	if prepared:
		result = _encounter.use_prepared_meal(item, false)
		if not result.action_resolved or Inv.consume_prepared_meal(item_id) != item_id:
			Bus.toast.emit("That prepared meal could not be consumed.")
			return
	else:
		if Inv.remove(item_id, 1) != 1:
			Bus.toast.emit("That item is no longer in the Bag.")
			return
		result = _encounter.use_combat_item(item, false)
	_answered = true
	for choice in _choices_box.get_children():
		if choice is Button:
			(choice as Button).disabled = true
	_render_bars()
	_feedback.add_theme_color_override("font_color", COL_GOOD)
	var effects: Array[String] = []
	if result.player_damage_dealt > 0:
		effects.append("dealt %d damage" % result.player_damage_dealt)
	if result.player_healed > 0:
		effects.append("restored %d HP" % result.player_healed)
	if result.energy_restored > 0:
		effects.append("restored %d Energy" % result.energy_restored)
	if result.shield_gained > 0:
		effects.append("gained %d Shield" % result.shield_gained)
	if not result.buff_type.is_empty():
		effects.append("gained +%d %s for %d rounds" % [result.buff_value,
			result.buff_type.to_upper(), result.buff_rounds])
	_feedback.text = "%s %s." % [item.get("name", item_id), " and ".join(effects)]
	_continue_btn.text = "Continue" if _encounter.is_over() else "Act again"
	_continue_btn.show()
	_continue_btn.grab_focus()


func _finish(victory: bool, message: String) -> void:
	_active = false
	_root.hide()
	get_tree().paused = false

	# Push the fight's outcome back onto the live player before anyone reads their HP.
	var player := get_tree().get_first_node_in_group("player")
	if player != null and _encounter != null:
		player.set_hp(_encounter.player_hp)

	if not message.is_empty():
		Bus.toast.emit(message)
	elif victory:
		Bus.enemy_died.emit(_encounter.enemy_id)
	var token := _encounter_token
	_encounter_token = ""
	EncounterDirector.resolve(token, victory)


func _exit_tree() -> void:
	if not _active and _encounter_token.is_empty():
		return
	_active = false
	if get_tree() != null:
		get_tree().paused = false
	var token := _encounter_token
	_encounter_token = ""
	var director := get_node_or_null("/root/EncounterDirector")
	if director != null:
		director.resolve(token, false)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	# Number keys 1..4 as a fast path alongside focus navigation, matching RecallPanel.
	if not _answered and event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var n := (event as InputEventKey).keycode - KEY_1
		if n >= 0 and n < _choices_box.get_child_count():
			var b := _choices_box.get_child(n) as Button
			_on_rune(b.text, b)
			get_viewport().set_input_as_handled()


# --- scaffold ---------------------------------------------------------------

func _rune_button(rune: String) -> Button:
	var b := Button.new()
	b.text = rune
	b.custom_minimum_size = Vector2(190, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# This used to clip, so a long answer was shown with its end cut off — the
	# player had to choose between runes they could not fully read. It now wraps
	# and steps its size down instead, which keeps the whole answer on screen
	# without stretching the panel past the viewport.
	b.clip_text = false
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", UiTheme.fit_font_size(rune, 30))
	b.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_BTN_BORDER))
	b.add_theme_stylebox_override("hover", _button_style(COL_BTN.lightened(0.08), COL_BORDER))
	b.add_theme_stylebox_override("pressed", _button_style(COL_BTN, COL_BORDER))
	# Styleboxes are set above, so the button can now measure how tall it has to be
	# to show the whole answer wrapped into its own width.
	b.custom_minimum_size.y = maxf(44.0, UiTheme.wrapped_height(b, rune, 190.0))
	b.pressed.connect(_on_rune.bind(rune, b))
	return b


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "CombatShell"
	panel.add_theme_stylebox_override("panel", _panel_style())
	# Combat used to cover 72%x92% of the screen. Its 2x2 answers lay out with
	# more room at the comfortable scale now, so the shell can reveal more world
	# without forcing the question back into the scroll region.
	UiTheme.fit_modal_shell(panel, 0.17, 0.05)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)

	# Round content scrolls; the player's own Energy/HP and the turn buttons are
	# pinned below the scroll so the green HP bar and the answer grid's result
	# never end up cut off below the fold.
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	margin.add_child(outer)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# Floating damage numbers live on their own overlay so a hit never reflows the round.
	_hit_layer = Control.new()
	_hit_layer.name = "HitLayer"
	_hit_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hit_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_hit_layer)

	# enemy
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 10)
	# The foe you are fighting was never on screen — combat was a name, two bars and a
	# line of text, which reads as a form rather than a fight. Its own walk sheet supplies
	# the portrait, the same still the Bestiary uses.
	_enemy_portrait = TextureRect.new()
	_enemy_portrait.name = "CombatEnemyPortrait"
	_enemy_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_enemy_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enemy_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_enemy_portrait.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	_enemy_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_enemy_portrait.pivot_offset = Vector2(PORTRAIT_PX, PORTRAIT_PX) * 0.5
	enemy_row.add_child(_enemy_portrait)
	_enemy_label = _label(17, COL_BORDER)
	_enemy_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# An enemy's name and its active effects are information the player is meant to
	# act on, so let the line wrap rather than truncating whatever runs long.
	_enemy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	enemy_row.add_child(_enemy_label)
	_flow_label = _label(13, COL_GOOD)
	enemy_row.add_child(_flow_label)
	_intent_label = _label(12, COL_BAD)
	_intent_label.name = "EnemyIntent"
	_intent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enemy_row.add_child(_intent_label)
	vbox.add_child(enemy_row)

	_enemy_hp_bar = _bar(Color(0.72, 0.28, 0.28))
	vbox.add_child(_enemy_hp_bar)

	# the guard word the player must answer
	_guard_label = _label(28, COL_TEXT)
	_guard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_guard_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_guard_label)

	_guard_hint = _label(12, COL_EN)
	_guard_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_guard_hint)

	# Equipped actions stay in one compact, horizontally scrollable row. Selection pauses
	# with the fight, so keyboard/controller users can inspect consequences before recall.
	var action_scroll := ScrollContainer.new()
	action_scroll.name = "ActionScroll"
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(action_scroll)
	_action_box = HBoxContainer.new()
	_action_box.name = "CombatActions"
	_action_box.add_theme_constant_override("separation", 6)
	action_scroll.add_child(_action_box)

	# 2x2 rather than a single row: four Japanese runes at a readable size do not fit
	# across one line on a 1280-wide window, and shrink-center keeps the grid from being
	# stretched past the panel by its parent.
	_choices_box = GridContainer.new()
	_choices_box.columns = 2
	_choices_box.add_theme_constant_override("h_separation", 10)
	_choices_box.add_theme_constant_override("v_separation", 8)
	_choices_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Pinned outside the scroll, alongside the HP bar and turn buttons. These four
	# runes are the question itself: inside the scroll area the bottom row fell below
	# the fold on a full-height round, so the player was choosing between answers
	# they could only see half of. Everything above them may scroll; these may not.
	outer.add_child(_choices_box)

	_feedback = _label(14, COL_GOOD)
	_feedback.name = "CombatFeedback"
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 28)
	outer.add_child(_feedback)

	# player footer — pinned outside the scroll area, always on screen
	_energy_label = _label(12, COL_EN)
	_energy_label.name = "CombatEnergy"
	_energy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outer.add_child(_energy_label)

	_player_hp_bar = _bar(Color(0.38, 0.66, 0.42))
	outer.add_child(_player_hp_bar)

	var turn_controls := HBoxContainer.new()
	turn_controls.name = "TurnControls"
	turn_controls.add_theme_constant_override("separation", 8)
	outer.add_child(turn_controls)
	_flee_btn = Button.new()
	_flee_btn.name = "Flee"
	_flee_btn.text = "Flee"
	_flee_btn.custom_minimum_size = Vector2(74, 30)
	_flee_btn.focus_mode = Control.FOCUS_ALL
	_flee_btn.tooltip_text = "Leave without victory rewards; current HP is kept."
	_flee_btn.pressed.connect(_on_flee)
	turn_controls.add_child(_flee_btn)
	_end_turn_btn = Button.new()
	_end_turn_btn.name = "EndTurn"
	_end_turn_btn.text = "End Turn"
	_end_turn_btn.custom_minimum_size = Vector2(110, 30)
	_end_turn_btn.focus_mode = Control.FOCUS_ALL
	_end_turn_btn.pressed.connect(_on_end_turn)
	turn_controls.add_child(_end_turn_btn)
	# Hearing the word once, mid-fight, is not enough to learn it. Sits with the turn
	# controls so it is reachable by keyboard and controller like every other action,
	# and only appears once the answer is on screen — before that it would be a hint
	# button that reads out the answer.
	_listen_btn = Button.new()
	_listen_btn.name = "Listen"
	_listen_btn.text = "Listen"
	_listen_btn.custom_minimum_size = Vector2(84, 30)
	_listen_btn.focus_mode = Control.FOCUS_ALL
	_listen_btn.tooltip_text = "Play the word's recording again"
	_listen_btn.pressed.connect(_on_listen)
	_listen_btn.hide()
	turn_controls.add_child(_listen_btn)
	_continue_btn = Button.new()
	_continue_btn.text = "Next"
	_continue_btn.custom_minimum_size = Vector2(0, 30)
	_continue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_continue_btn.focus_mode = Control.FOCUS_ALL
	_continue_btn.pressed.connect(_on_continue)
	turn_controls.add_child(_continue_btn)


func _bar(tint: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(0, 16)
	b.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	fill.set_corner_radius_all(4)
	b.add_theme_stylebox_override("fill", fill)
	return b


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(14)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = border
	return s
