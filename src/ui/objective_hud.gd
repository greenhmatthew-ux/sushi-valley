extends CanvasLayer
## The tracked objective: one line under the top-right status group saying what to do next.
##
## UI_UX_GUIDE section 5 lists "Tracked objective/navigation cue — One objective,
## distance/region cue; no full checklist", and section 2 principle 9 wants a player returning
## after a break to be told where they were. This is the smallest honest version: the active
## quest's title and its live progress, or a nudge toward learning when no quest is running.
##
## Deliberately ONE line and no checklist — the guide explicitly rejects "a screen of pins".
##
## It reads quest state from the QuestGiver nodes in the scene rather than keeping a parallel
## quest registry, so the HUD can never disagree with the giver you are standing in front of.

var _panel: PanelContainer
var _title: Label
var _detail: Label


func _ready() -> void:
	layer = 17   # same band as the HUD, under the context prompt
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Bus.quest_accepted.connect(func(_id): _refresh())
	Bus.quest_completed.connect(func(_id): _refresh())
	Bus.inventory_changed.connect(_refresh)
	Bus.hud_refresh.connect(_refresh)
	Bus.card_reviewed.connect(func(_i, _g, _c): _refresh())
	# Scenes swap on travel, so re-read once the new tree is settled.
	get_tree().node_added.connect(_on_node_added)
	_refresh.call_deferred()


func _on_node_added(node: Node) -> void:
	if node.has_method("current_stage"):
		_refresh.call_deferred()


func _refresh() -> void:
	if _title == null:
		return
	var giver := _active_giver()
	if giver != null:
		var q: Dictionary = giver.quest()
		_title.text = String(q.get("title", "Quest"))
		var item := String(giver.goal_item())
		var item_name := String(DB.item(item).get("name", item))
		if giver.current_stage() == "turnin":
			_detail.text = "Return to %s" % String(q.get("giver", "the giver"))
			_detail.add_theme_color_override("font_color", UiTheme.STATE_SUCCESS)
		else:
			_detail.text = "%s  %d/%d" % [item_name, giver.progress(), giver.goal_qty()]
			_detail.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
		_panel.show()
		return

	# No quest running. Point at learning instead of showing an empty frame — but only when
	# there is genuinely something to review, so this never nags.
	var due := Learning.due_count() if Learning.progression != null else 0
	if due > 0:
		_title.text = "Study"
		_detail.text = "%d word%s ready to review" % [due, "" if due == 1 else "s"]
		_detail.add_theme_color_override("font_color", UiTheme.LEARNING_VIOLET)
		_panel.show()
	else:
		_panel.hide()


## The one quest to show: accepted, not yet turned in. Ready-to-hand-in wins over in-progress
## so a finished goal surfaces immediately.
func _active_giver() -> Node:
	var best: Node = null
	for node in get_tree().get_nodes_in_group("interactable"):
		if not node.has_method("current_stage") or not node.has_method("quest"):
			continue
		var stage: String = node.current_stage()
		if stage == "turnin":
			return node
		if stage == "active" and best == null:
			best = node
	return best


func _build() -> void:
	_panel = PanelContainer.new()
	var style := UiTheme.panel_style(UiTheme.BORDER_STRONG)
	style.bg_color = Color(UiTheme.SURFACE_DEEP, 0.88)
	style.content_margin_left = UiTheme.UNIT + 2
	style.content_margin_right = UiTheme.UNIT + 2
	style.content_margin_top = UiTheme.UNIT - 3
	style.content_margin_bottom = UiTheme.UNIT - 3
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Directly under the coins/review group.
	_panel.anchor_left = 1.0; _panel.anchor_right = 1.0
	_panel.anchor_top = 0.0; _panel.anchor_bottom = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_END
	_panel.offset_right = -UiTheme.UNIT
	_panel.offset_top = 84.0
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	_panel.add_child(rows)

	_title = UiTheme.label("", UiTheme.FONT_META, UiTheme.ACCENT_GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_title)

	_detail = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_detail)

	_panel.hide()
