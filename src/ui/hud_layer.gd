extends CanvasLayer
## The always-on HUD, built to the UI_UX_GUIDE visibility contract (section 5).
##
## Two small anchored groups rather than one wide bar, so the centre and top of the world stay
## visible ("The current 460x56 all-in-one bar should evolve into smaller anchored groups"):
##
##   top-left   hearts + level      — dims to 55% while full and safe, per the contract's
##                                    "Always, but dim when full and safe"
##   top-right  day/season + coins + due reviews
##
## The day/season row is backed by the saved Farm calendar. The due-review count is the one
## number that tells a player this is a learning game with something waiting for them.
##
## Bus-driven throughout: no polling, and nothing here holds a reference to Inv or Learning
## state beyond reading it on a signal.
##
## Hidden wholesale during combat: the fight panel has its own dim backdrop, player HP bar,
## and reward flow, so hearts/coins bleeding through the dim read as overlap, not context.

const HEART_TEX := preload("res://assets/ui/hearts.png")
## A FIXED row of hearts, each worth a fifth of max HP and filled in quarters from the
## 5-frame sheet. Max HP grows with learning level (12 -> 60+), so one-heart-per-4-HP would
## have marched 15 hearts across half the screen by level 5 and 26 by level 20 — the guide
## asks for a "top-left compact group", and a row that grows without bound is not compact.
## A fixed row reads the same at every level: how full you are, not how many pips you own.
const HEART_COUNT := 5
const QUARTERS_PER_HEART := 4
const DIM_WHEN_SAFE := 0.55   ## alpha for the vitals group at full HP

var _coins_label: Label
var _clock_label: Label
var _weather_label: Label
var _due_button: Button
var _level_label: Label
var _hp_label: Label
var _vitals: Control
var _hearts_box: HBoxContainer
var _hearts: Array[TextureRect] = []
var _hp_full := true
## Everything hangs off this so the whole HUD scales as one (UiTheme.fit_layer).
## Without it the groups would anchor to the untouched viewport and drift off the
## corners as soon as the layer was scaled.
var _root: Control


func _ready() -> void:
	layer = 17   # under the context prompt (18), dialogue (19) and every modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiTheme.fit_layer(self, _root)
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	_build_vitals()
	_build_status()
	Bus.coins_changed.connect(func(_c): _refresh())
	Bus.inventory_changed.connect(_refresh)
	Bus.farm_changed.connect(_refresh)
	Bus.player_hp_changed.connect(_on_hp)
	Bus.hud_refresh.connect(_refresh)
	# Learning progress moves the due count, so refresh on any review or unlock.
	Bus.card_reviewed.connect(func(_id, _g, _c): _refresh())
	Bus.xp_gained.connect(func(_a): _refresh())
	Bus.combat_started.connect(func(_id): hide())
	Bus.combat_ended.connect(func(_v): show())
	_refresh()


# --- top-left: hearts + level ---------------------------------------------

func _build_vitals() -> void:
	_vitals = VBoxContainer.new()
	_vitals.position = Vector2(UiTheme.UNIT + 2, UiTheme.UNIT)
	_vitals.add_theme_constant_override("separation", 2)
	_root.add_child(_vitals)

	_hearts_box = HBoxContainer.new()
	_hearts_box.add_theme_constant_override("separation", 1)
	_vitals.add_child(_hearts_box)
	for i in HEART_COUNT:
		var tr := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = HEART_TEX
		at.region = Rect2(QUARTERS_PER_HEART * 16, 0, 16, 16)   # full to start
		tr.texture = at
		tr.custom_minimum_size = Vector2(28, 28)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_hearts_box.add_child(tr)
		_hearts.append(tr)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 6)
	_vitals.add_child(meta)

	_level_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_level_label.add_theme_color_override("font_outline_color", UiTheme.SURFACE_DEEP)
	_level_label.add_theme_constant_override("outline_size", 4)
	meta.add_child(_level_label)

	_hp_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_hp_label.add_theme_color_override("font_outline_color", UiTheme.SURFACE_DEEP)
	_hp_label.add_theme_constant_override("outline_size", 4)
	meta.add_child(_hp_label)
	_vitals.modulate.a = DIM_WHEN_SAFE


func _on_hp(hp: int, max_hp: int) -> void:
	# Total quarters across the whole row, so the bar reads proportionally at any max HP.
	var total_q := HEART_COUNT * QUARTERS_PER_HEART
	var filled_q := 0 if max_hp <= 0 else int(ceil(float(hp) / float(max_hp) * total_q))
	# A living player never shows a fully empty row — that would read as dead.
	if hp > 0:
		filled_q = maxi(1, filled_q)
	filled_q = clampi(filled_q, 0, total_q)

	for i in _hearts.size():
		var fill := clampi(filled_q - i * QUARTERS_PER_HEART, 0, QUARTERS_PER_HEART)
		(_hearts[i].texture as AtlasTexture).region = Rect2(fill * 16, 0, 16, 16)
	if _hp_label != null:
		_hp_label.text = "%d/%d" % [hp, max_hp]
	# Full and safe -> recede; hurt -> come forward. Redundant with the hearts themselves,
	# which is the point: colour/alpha never carries meaning alone.
	var full := hp >= max_hp
	if full != _hp_full:
		_hp_full = full
		create_tween().tween_property(_vitals, "modulate:a",
			DIM_WHEN_SAFE if full else 1.0, UiTheme.MOTION_FOCUS)


# --- top-right: coins + due reviews ---------------------------------------

func _build_status() -> void:
	var panel := PanelContainer.new()
	var style := UiTheme.panel_style(Color(UiTheme.ACCENT_GOLD, 0.75))
	style.bg_color = Color(UiTheme.SURFACE_DEEP, 0.9)
	style.content_margin_left = UiTheme.UNIT + 4
	style.content_margin_right = UiTheme.UNIT + 4
	style.content_margin_top = UiTheme.UNIT - 2
	style.content_margin_bottom = UiTheme.UNIT - 2
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 1.0; panel.anchor_right = 1.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 0.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.offset_right = -UiTheme.UNIT
	panel.offset_top = UiTheme.UNIT
	_root.add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)

	_clock_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_PRIMARY)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_clock_label)

	_weather_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.STATE_INFO)
	_weather_label.name = "HudWeather"
	_weather_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_weather_label)

	_coins_label = UiTheme.label("", UiTheme.FONT_SECTION, UiTheme.ACCENT_GOLD)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_coins_label)

	# Learning identity colour, so "words waiting" reads as a different kind of thing
	# from money at a glance. A button, not a label: the guide's depth target for
	# "review due Japanese" is one layer — the cue itself starts the session.
	_due_button = Button.new()
	_due_button.name = "HudDueReview"
	_due_button.flat = true
	for state in ["normal", "hover", "pressed", "focus"]:
		_due_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_due_button.add_theme_font_size_override("font_size", UiTheme.FONT_META)
	_due_button.add_theme_color_override("font_color", UiTheme.LEARNING_VIOLET)
	_due_button.add_theme_color_override("font_hover_color", UiTheme.TEXT_PRIMARY)
	_due_button.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# No keyboard/controller focus: arrows double as movement, so the HUD must
	# never join the focus loop. Those inputs reach review via `open_review`.
	_due_button.focus_mode = Control.FOCUS_NONE
	_due_button.tooltip_text = "Start a review session (R)"
	_due_button.pressed.connect(_open_review)
	rows.add_child(_due_button)


func _refresh() -> void:
	if _coins_label == null:
		return
	_clock_label.text = Farm.clock_text()
	_weather_label.text = WeatherSystem.hud_text()
	_coins_label.text = "%d coins" % Inv.coins

	# Hidden at zero rather than showing "0 due" — an empty queue is not information.
	var due := 0
	if Learning.progression != null:
		due = Learning.due_count()
	_due_button.text = "%d word%s to review ▸" % [due, "" if due == 1 else "s"]
	_due_button.visible = due > 0

	if _level_label != null and Learning.profile != null:
		var xp := int(Learning.profile.data.get("stats", {}).get("xp", 0))
		_level_label.text = "Lv %d" % PlayerStats.level_from_xp(xp)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_review"):
		_open_review()
		get_viewport().set_input_as_handled()


## The prepared session behind the cue — the same one the Pause Hub's Learning
## tab starts, so the shortcut is a faster route to a known place, not a new mode.
func _open_review() -> void:
	# Anything that pauses (dialogue, menus, an open session) owns the screen, and
	# combat hides this HUD entirely; the cue must not fire under either.
	if not visible or get_tree().paused or Learning.progression == null:
		return
	Bus.learn_open.emit("", 5, true)
