extends CanvasLayer
## Turn-based recall combat. The enemy raises a guard word; your four moves are Japanese
## runes and picking the matching one IS the attack — no quiz popup in front of the game.
##
## Bus-driven: opens on `combat_started(enemy_id)`, replies with `combat_ended(victory)`.
## All rules live in the pure CombatEncounter; this only renders it and feeds it choices.
##
## Every round's card comes from the ONE shared scheduler (Learning.build_prompt) and every
## answer goes back through Learning.answer(), so fighting IS reviewing — combat owns no
## deck and no schedule of its own (SITE_WIDE_LEARNING_ARCHITECTURE.md).

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
var _encounter: CombatEncounter
var _current_card: Dictionary = {}
var _challenge: Dictionary = {}
var _answered := false
var _rng := RandomNumberGenerator.new()

var _root: Control
var _enemy_label: Label
var _enemy_hp_bar: ProgressBar
var _player_hp_bar: ProgressBar
var _flow_label: Label
var _guard_label: Label
var _guard_hint: Label
var _feedback: Label
var _choices_box: GridContainer
var _continue_btn: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_build()
	_root.hide()
	Bus.combat_started.connect(_on_combat_started)
	Bus.language_changed.connect(func(_v): if _active: _refresh_guard_hint())


func _on_combat_started(enemy_id: String) -> void:
	if _active:
		return
	var enemy: Dictionary = DB.enemy(enemy_id)
	if enemy.is_empty():
		push_warning("[Combat] unknown enemy '%s'" % enemy_id)
		Bus.combat_ended.emit(false)
		return

	# Stats come from the player, which derives them from learning level (PlayerStats) —
	# so studying is what makes a fight winnable. A simulation of the ported enemy numbers
	# against the old flat 12 HP showed the kappa and lantern were unwinnable at 0%.
	var player := get_tree().get_first_node_in_group("player")
	var hp: int = player.hp if player != null else PlayerStats.BASE_MAX_HP
	var max_hp: int = player.MAX_HP if player != null else PlayerStats.BASE_MAX_HP
	var p_atk: int = player.atk if player != null else PlayerStats.BASE_ATK
	var p_def: int = player.defense if player != null else PlayerStats.BASE_DEF

	_encounter = CombatEncounter.new(enemy, hp, max_hp, p_atk, p_def)
	_active = true
	get_tree().paused = true
	_enemy_label.text = _encounter.enemy_name
	_root.show()
	_next_round()


## Draw the next card from the shared scheduler and turn it into a rune challenge.
func _next_round() -> void:
	_answered = false
	_continue_btn.hide()
	_feedback.text = ""

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
	_guard_hint.text = "Strike with the matching rune" if not Settings.english_visible() \
		else "Strike with the rune meaning \"%s\"" % _challenge.get("guard", "")


func _render_bars() -> void:
	_enemy_hp_bar.max_value = _encounter.enemy_max_hp
	_enemy_hp_bar.value = _encounter.enemy_hp
	_player_hp_bar.max_value = _encounter.player_max_hp
	_player_hp_bar.value = _encounter.player_hp
	_flow_label.text = ("Flow x%d" % _encounter.flow) if _encounter.flow > 0 else ""


func _on_rune(rune: String, btn: Button) -> void:
	if _answered:
		return
	_answered = true

	var result: CombatEncounter.RoundResult = _encounter.resolve(rune, _challenge["answer"])
	# Feed the shared SRS — this is what makes fighting count as review.
	Learning.answer(_current_card, String(_current_card.get("answer", "")) if result.correct else "__wrong__")

	btn.add_theme_stylebox_override("normal", _button_style(
		UiTheme.FILL_CORRECT if result.correct else UiTheme.FILL_WRONG, COL_BORDER))
	if not result.correct:
		for other in _choices_box.get_children():
			if other is Button and (other as Button).text == String(_challenge["answer"]):
				other.add_theme_stylebox_override("normal", _button_style(UiTheme.FILL_CORRECT, COL_BORDER))

	_render_bars()
	_feedback.add_theme_color_override("font_color", COL_GOOD if result.correct else COL_BAD)
	if result.correct:
		_feedback.text = "Hit for %d!%s" % [result.player_damage_dealt,
			("   Flow x%d" % result.flow_after) if result.flow_after > 1 else ""]
	else:
		_feedback.text = "%s was the rune. Glancing blow for %d." % [result.answer, result.player_damage_dealt]
	if result.enemy_damage_dealt > 0:
		_feedback.text += "   %s hits back for %d." % [_encounter.enemy_name, result.enemy_damage_dealt]

	if _encounter.is_over():
		_continue_btn.text = "Continue"
		_continue_btn.show()
		_continue_btn.grab_focus()
	else:
		_continue_btn.text = "Next"
		_continue_btn.show()
		_continue_btn.grab_focus()


func _on_continue() -> void:
	if _encounter.is_over():
		_finish(_encounter.player_won(), "")
	else:
		_next_round()


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
	Bus.combat_ended.emit(victory)


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
	b.custom_minimum_size = Vector2(200, 50)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_BTN_BORDER))
	b.add_theme_stylebox_override("hover", _button_style(COL_BTN.lightened(0.08), COL_BORDER))
	b.add_theme_stylebox_override("pressed", _button_style(COL_BTN, COL_BORDER))
	b.pressed.connect(_on_rune.bind(rune, b))
	return b


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.anchor_left = 0.22; panel.anchor_right = 0.78
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# enemy
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 10)
	_enemy_label = _label(17, COL_BORDER)
	enemy_row.add_child(_enemy_label)
	_flow_label = _label(13, COL_GOOD)
	enemy_row.add_child(_flow_label)
	vbox.add_child(enemy_row)

	_enemy_hp_bar = _bar(Color(0.72, 0.28, 0.28))
	vbox.add_child(_enemy_hp_bar)

	# the guard word the player must answer
	_guard_label = _label(32, COL_TEXT)
	_guard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_guard_label)

	_guard_hint = _label(12, COL_EN)
	_guard_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_guard_hint)

	# 2x2 rather than a single row: four Japanese runes at a readable size do not fit
	# across one line on a 1280-wide window, and shrink-center keeps the grid from being
	# stretched past the panel by its parent.
	_choices_box = GridContainer.new()
	_choices_box.columns = 2
	_choices_box.add_theme_constant_override("h_separation", 10)
	_choices_box.add_theme_constant_override("v_separation", 8)
	_choices_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_choices_box)

	_feedback = _label(14, COL_GOOD)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size = Vector2(0, 34)
	vbox.add_child(_feedback)

	# player
	_player_hp_bar = _bar(Color(0.38, 0.66, 0.42))
	vbox.add_child(_player_hp_bar)

	_continue_btn = Button.new()
	_continue_btn.text = "Next"
	_continue_btn.custom_minimum_size = Vector2(0, 30)
	_continue_btn.focus_mode = Control.FOCUS_ALL
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)


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
