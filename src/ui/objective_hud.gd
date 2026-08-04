extends CanvasLayer
## The tracked objective: one line under the top-right status group saying what to do next.
##
## UI_UX_GUIDE section 5 lists "Tracked objective/navigation cue — One objective,
## distance/region cue; no full checklist", and section 2 principle 9 wants a player returning
## after a break to be told where they were. The saved Journal selection wins
## across scene changes; when it completes, the strongest remaining activity is
## the fallback.
##
## Deliberately ONE line and no checklist — the guide explicitly rejects "a screen of pins".
##
const Activities = preload("res://src/systems/activity_tracker.gd")

var _panel: PanelContainer
## Scaling root — the tracker anchors inside this, not the raw viewport.
var _root: Control
var _title: Label
var _detail: Label


func _ready() -> void:
	layer = 17   # same band as the HUD, under the context prompt
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Bus.ui_scale_changed.connect(func(_s): UiTheme.fit_layer(self, _root))
	Bus.quest_accepted.connect(func(_id): _refresh())
	Bus.quest_completed.connect(func(_id): _refresh())
	Bus.activity_tracking_changed.connect(func(_key): _refresh())
	Bus.flag_set.connect(func(_flag, _value): _refresh())
	Bus.inventory_changed.connect(_refresh)
	Bus.hud_refresh.connect(_refresh)
	Bus.card_reviewed.connect(func(_i, _g, _c): _refresh())
	# The fight panel owns the screen; a quest line bleeding through its dim reads as overlap.
	Bus.combat_started.connect(func(_id): hide())
	Bus.combat_ended.connect(func(_v): show())
	_refresh.call_deferred()


func _refresh() -> void:
	if _title == null:
		return
	var activity := Activities.reconcile(Learning.profile, DB, Inv)
	if not activity.is_empty():
		_title.text = "%s · %s" % [activity["kind"], activity["title"]]
		_detail.text = String(activity["hud_detail"])
		_detail.add_theme_color_override("font_color", UiTheme.STATE_SUCCESS \
			if int(activity.get("priority", 99)) == 0 else UiTheme.TEXT_MUTED)
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
		return

	# Nothing to say — and that is fine. A fresh player is deliberately NOT given a "talk to the
	# villagers" nudge here: direction should come from the world (a greeter standing at the
	# spawn, a signpost, a lit doorway), not from a panel telling you how to play.
	_panel.hide()


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	_panel = PanelContainer.new()
	_panel.name = "ObjectivePanel"
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
	_panel.offset_top = 84.0   # provisional; _track_status_panel replaces it with the real edge
	_root.add_child(_panel)
	_track_status_panel.call_deferred()

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 1)
	_panel.add_child(rows)

	_title = UiTheme.label("", UiTheme.FONT_META, UiTheme.ACCENT_GOLD)
	_title.name = "ObjectiveTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_title)

	_detail = UiTheme.label("", UiTheme.FONT_META, UiTheme.TEXT_MUTED)
	_detail.name = "ObjectiveDetail"
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_detail)

	_panel.hide()


## Stack directly under the HUD's coins/review panel, whatever height that panel
## settles at — a fixed offset overlapped it whenever the review cue was visible or
## the UI scale grew the fonts past the hardcoded 84px. Deferred so the HUD (a
## sibling layer built in the same frame) has its panel in the group first.
func _track_status_panel() -> void:
	var status := get_tree().get_first_node_in_group("hud_status_panel") as Control
	if status == null or _panel == null:
		return
	if not status.resized.is_connected(_dock_below_status):
		status.resized.connect(_dock_below_status)
	_dock_below_status()


func _dock_below_status() -> void:
	var status := get_tree().get_first_node_in_group("hud_status_panel") as Control
	if status == null or _panel == null:
		return
	_panel.offset_top = status.position.y + status.size.y + 4.0
