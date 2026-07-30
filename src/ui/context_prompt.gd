extends CanvasLayer
## The context action prompt: "E — Talk to Hana", bottom-centre, only while something is in
## reach.
##
## UI_UX_GUIDE principle 2 is "One obvious action. Context prompts name the action and
## input." There was no prompt at all before this — a player standing next to a teacher had
## nothing telling them a teacher could be talked to, so the game's entire learning loop was
## discoverable only by pressing keys at random. This is the cheapest large UX win available.
##
## Reads the player's own InteractProbe rather than duplicating reach rules, so the thing the
## prompt names is exactly the thing `interact` will trigger. Polls on a timer instead of
## per-frame: the label only needs to keep up with walking, and the guide asks for a quiet HUD.

const POLL_INTERVAL := 0.1

var _label: Label
var _panel: PanelContainer
var _shown_target: Node = null
var _accum := 0.0


func _ready() -> void:
	layer = 18   # above the world, below dialogue (19) and every modal
	_build()
	_panel.hide()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < POLL_INTERVAL:
		return
	_accum = 0.0
	_refresh()


func _refresh() -> void:
	var target := _nearest_interactable()
	if target == _shown_target:
		return
	_shown_target = target
	if target == null:
		_panel.hide()
		return
	_label.text = "%s   %s" % [_input_glyph(), _verb_for(target)]
	_panel.show()


## Mirror of Player._try_interact's selection: nearest overlapping interactable.
func _nearest_interactable() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.get("control_enabled"):
		return null
	var probe := player.get_node_or_null("InteractProbe") as Area2D
	if probe == null:
		return null

	var nearest: Node = null
	var best := INF
	for area in probe.get_overlapping_areas():
		if not area.is_in_group("interactable") or not area.has_method("interact"):
			continue
		var d: float = player.global_position.distance_squared_to(area.global_position)
		if d < best:
			best = d
			nearest = area
	return nearest


## Name the action in player language — never an entity id or class name (guide principle 10:
## "Player-facing screens never expose entity IDs, internal flags... implementation
## terminology").
func _verb_for(target: Node) -> String:
	if target.has_method("begin_spar"):
		return "Spar"

	# A quest giver's display name comes from the quest data, not its `speaker` export (which
	# is usually left blank so the authored giver wins) — so ask it, and say what's waiting.
	if target.has_method("current_stage") and target.has_method("quest"):
		var giver_name := String(target.quest().get("giver", "them"))
		if not String(target.get("speaker")).is_empty():
			giver_name = String(target.get("speaker"))
		match target.current_stage():
			"turnin":
				return "Hand in to %s" % giver_name
			"intro":
				return "Ask %s for work" % giver_name
			"done":
				if target.get("shop_id") != null and not String(target.get("shop_id")).is_empty():
					return "Trade with %s" % giver_name
				return "Talk to %s" % giver_name
			_:
				return "Talk to %s" % giver_name

	var named := String(target.get("speaker") if target.get("speaker") != null else "")
	if not named.is_empty():
		return "Talk to %s" % named
	if target.get("shows_card") != null:
		return "Read the sign"
	if target.get("target_scene") != null:
		return "Enter"
	if target.get("required_lesson") != null:
		return "Study at the gate"
	if target.get("shop_id") != null:
		return "Trade"
	if target.get("item_id") != null:
		return "Pick up"
	return "Examine"


## The key actually bound to `interact`, so the glyph can't drift from the InputMap.
func _input_glyph() -> String:
	for event in InputMap.action_get_events("interact"):
		if event is InputEventKey:
			var key := event as InputEventKey
			var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
			var text := OS.get_keycode_string(code)
			if not text.is_empty():
				return "[%s]" % text
	return "[interact]"


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_style(UiTheme.BORDER_STRONG))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-centre, clear of the dialogue box's own band.
	_panel.anchor_left = 0.5; _panel.anchor_right = 0.5
	_panel.anchor_top = 1.0; _panel.anchor_bottom = 1.0
	_panel.offset_top = -96.0
	_panel.offset_bottom = -60.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", UiTheme.PAD_PANEL)
	margin.add_theme_constant_override("margin_right", UiTheme.PAD_PANEL)
	margin.add_theme_constant_override("margin_top", UiTheme.UNIT / 2)
	margin.add_theme_constant_override("margin_bottom", UiTheme.UNIT / 2)
	_panel.add_child(margin)

	_label = UiTheme.label("", UiTheme.FONT_SECTION, UiTheme.TEXT_PRIMARY)
	margin.add_child(_label)
