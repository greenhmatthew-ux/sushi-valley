extends Control
## Compact render-only view of FishingLogic. All positions are meter-local, so
## this remains screen-centered and identical at every camera zoom.

const FISH_ICON := preload("res://assets/icons/items/river_fish.png")

var logic: RefCounted = null


func _ready() -> void:
	custom_minimum_size = Vector2(92, 132)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_logic(value: RefCounted) -> void:
	logic = value
	queue_redraw()


func _draw() -> void:
	if logic == null:
		return
	var center := size / 2.0
	var meter_height := minf(160.0, maxf(112.0, size.y - 4.0))
	var scale_y := meter_height / 160.0
	var top := center.y - meter_height / 2.0
	var track_x := center.x - 16.0
	draw_rect(Rect2(track_x - 2.0, top - 2.0, 36.0, meter_height + 4.0), UiTheme.BORDER_STRONG)
	draw_rect(Rect2(track_x, top, 32.0, meter_height), UiTheme.SURFACE_DEEP)

	var bar_center := Vector2(center.x, center.y + float(logic.bar_y) * scale_y)
	var bar_color := Color(UiTheme.STATE_SUCCESS, 0.48 if logic.is_overlapping() else 0.30)
	var bar_height := 44.0 * scale_y
	draw_rect(Rect2(bar_center.x - 15.0, bar_center.y - bar_height / 2.0, 30.0, bar_height), bar_color)
	draw_rect(Rect2(bar_center.x - 15.0, bar_center.y - bar_height / 2.0, 30.0, bar_height),
		UiTheme.STATE_SUCCESS, false, 2.0)

	var fish_center := Vector2(center.x, center.y + float(logic.fish_y) * scale_y)
	draw_texture_rect(FISH_ICON, Rect2(fish_center - Vector2(7, 7), Vector2(14, 14)), false)

	var progress_x := track_x + 40.0
	draw_rect(Rect2(progress_x, top, 8.0, meter_height), UiTheme.SURFACE_RAISED)
	var progress_h := clampf(float(logic.progress), 0.0, 100.0) / 100.0 * (meter_height - 4.0)
	var progress_color := UiTheme.STATE_SUCCESS if logic.progress >= 70.0 \
		else (UiTheme.ACCENT_GOLD if logic.progress >= 30.0 else UiTheme.STATE_DANGER)
	draw_rect(Rect2(progress_x + 2.0, top + meter_height - 2.0 - progress_h, 4.0, progress_h), progress_color)
