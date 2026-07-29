extends CanvasLayer
## The always-on HUD, built to the UI_UX_GUIDE visibility contract (section 5).
##
## Two small anchored groups rather than one wide bar, so the centre and top of the world stay
## visible ("The current 460x56 all-in-one bar should evolve into smaller anchored groups"):
##
##   top-left   hearts + level      — dims to 55% while full and safe, per the contract's
##                                    "Always, but dim when full and safe"
##   top-right  coins + due reviews — the learning cue the contract lists alongside the clock
##
## The due-review count is the one number that tells a player this is a learning game with
## something waiting for them; it was missing entirely. Time/date/season/weather are also in
## the contract but there is no day/season system yet, so that group is deliberately absent
## rather than faked — the guide's "honest status" principle.
##
## Bus-driven throughout: no polling, and nothing here holds a reference to Inv or Learning
## state beyond reading it on a signal.

const HEART_TEX := preload("res://assets/ui/hearts.png")
const HEART_COUNT := 3        ## Player.MAX_HP (12) / 4 HP per heart
const HP_PER_HEART := 4
const DIM_WHEN_SAFE := 0.55   ## alpha for the vitals group at full HP

var _coins_label: Label
var _due_label: Label
var _level_label: Label
var _vitals: Control
var _hearts: Array[TextureRect] = []
var _hp_full := true


func _ready() -> void:
	layer = 17   # under the context prompt (18), dialogue (19) and every modal
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_vitals()
	_build_status()
	Bus.coins_changed.connect(func(_c): _refresh())
	Bus.inventory_changed.connect(_refresh)
	Bus.player_hp_changed.connect(_on_hp)
	Bus.hud_refresh.connect(_refresh)
	# Learning progress moves the due count, so refresh on any review or unlock.
	Bus.card_reviewed.connect(func(_id, _g, _c): _refresh())
	Bus.xp_gained.connect(func(_a): _refresh())
	_refresh()


# --- top-left: hearts + level ---------------------------------------------

func _build_vitals() -> void:
	_vitals = VBoxContainer.new()
	_vitals.position = Vector2(UiTheme.UNIT + 2, UiTheme.UNIT)
	_vitals.add_theme_constant_override("separation", 2)
	add_child(_vitals)

	var hearts_box := HBoxContainer.new()
	hearts_box.add_theme_constant_override("separation", 1)
	_vitals.add_child(hearts_box)
	for i in HEART_COUNT:
		var tr := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = HEART_TEX
		at.region = Rect2(HP_PER_HEART * 16, 0, 16, 16)   # full to start
		tr.texture = at
		tr.custom_minimum_size = Vector2(28, 28)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hearts_box.add_child(tr)
		_hearts.append(tr)

	_level_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_level_label.add_theme_color_override("font_outline_color", UiTheme.SURFACE_DEEP)
	_level_label.add_theme_constant_override("outline_size", 4)
	_vitals.add_child(_level_label)
	_vitals.modulate.a = DIM_WHEN_SAFE


func _on_hp(hp: int, max_hp: int) -> void:
	for i in _hearts.size():
		var fill := clampi(hp - i * HP_PER_HEART, 0, HP_PER_HEART)
		(_hearts[i].texture as AtlasTexture).region = Rect2(fill * 16, 0, 16, 16)
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
	add_child(panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	panel.add_child(rows)

	_coins_label = UiTheme.label("", UiTheme.FONT_SECTION, UiTheme.ACCENT_GOLD)
	_coins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_coins_label)

	# Learning identity colour, so "words waiting" reads as a different kind of thing
	# from money at a glance.
	_due_label = UiTheme.label("", UiTheme.FONT_META, UiTheme.LEARNING_VIOLET)
	_due_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_due_label)


func _refresh() -> void:
	if _coins_label == null:
		return
	_coins_label.text = "%d coins" % Inv.coins

	# Hidden at zero rather than showing "0 due" — an empty queue is not information.
	var due := 0
	if Learning.progression != null:
		due = Learning.due_count()
	_due_label.text = "%d word%s to review" % [due, "" if due == 1 else "s"]
	_due_label.visible = due > 0

	if _level_label != null and Learning.profile != null:
		var xp := int(Learning.profile.data.get("stats", {}).get("xp", 0))
		_level_label.text = "Lv %d" % _level_from_xp(xp)


## Level curve: 100 XP per level, starting at 1. Kept here (presentation) rather than in the
## learning core, which deliberately tracks XP only — no save-schema change.
func _level_from_xp(xp: int) -> int:
	return 1 + int(floor(float(maxi(0, xp)) / 100.0))
