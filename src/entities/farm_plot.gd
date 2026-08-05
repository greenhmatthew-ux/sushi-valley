extends Area2D
## One visible, saved crop plot. Interaction stays context-first: empty plots
## open the seed picker, dry crops water, and mature crops harvest.
##
## Soil and crops used to be `draw_rect`/`draw_circle` primitives: a brown bar with a
## green blob on it, which is what a placeholder looks like. Both are now real 16px
## farm art, one tile per plot on the tile grid, so a field reads as tilled ground with
## a recognisable plant growing out of it instead of coloured boxes.
##
## Watering is a tint on the soil rather than a second sprite. The sheet has no authored
## wet variant, and darkening damp earth is what wet earth actually does — this is a
## state cue on real art, not art invented in code.

@export var plot_id := "valley_plot_1"

const Art := preload("res://src/systems/world_art_catalog.gd")

## Sprout Lands tilled dirt, tile (0,5): the sheet's solid fill. Plots are laid on the
## 16px grid one beside another, so four of them read as a single worked field rather
## than four separate spots — which is what the sheet's isolated single-tile patch gave,
## and at plot spacing it looked like scattered brown dots on the grass.
const SOIL_SHEET := Art.SOIL_SHEET
## Tile (1,5) rather than the plain fill beside it: it carries the sheet's clod texture,
## and four plain tiles together read as one flat painted rectangle.
const SOIL_REGION := Art.SOIL_REGION
const SOIL_DRY := Color(1, 1, 1, 1)
## Damp earth stays brown. An even grey multiply desaturated it to concrete, which is
## the one thing wet soil never looks like.
const SOIL_WET := Color(0.74, 0.63, 0.55, 1)

## Farm RPG "Spring Crops": each crop is a row, columns 1..5 are its growth stages.
## The game has four stages, so the four most distinct columns are used and the mature
## column is always last — a plot that looks finished must be harvestable.
const CROP_SHEET := Art.CROP_SHEET
const CROP_STAGE_COLUMNS := Art.CROP_STAGE_COLUMNS
## Chosen by silhouette, since the sheet's crops are not the valley's crops: stalks for
## rice, a fruiting vine for cucumber, a low earthy tuber for mushroom, leaf clusters
## for herb. One sheet keeps the field coherent.
const CROP_ROWS := Art.CROP_ROWS
const CROP_FALLBACK_ROW := Art.CROP_FALLBACK_ROW


var _soil: Sprite2D
var _crop: Sprite2D


func _ready() -> void:
	add_to_group("interactable")
	y_sort_enabled = true
	_build_sprites()
	Farm.register_plot(plot_id)
	Bus.farm_changed.connect(_refresh)
	_refresh()


func interact(_player: Node = null) -> void:
	var state := Farm.plot(plot_id)
	if String(state.get("cropId", "")).is_empty():
		Bus.farm_plot_open.emit(plot_id)
		return
	var crop: Dictionary = Farm.crop_def_for_plot(plot_id)
	if Farm.is_ready(plot_id):
		var result := Farm.harvest(plot_id)
		if result.get("ok", false):
			Bus.toast.emit("Harvested %s." % crop.get("name", "crop"))
		else:
			Bus.toast.emit(String(result.get("reason", "Could not harvest.")))
	elif not bool(state.get("watered", false)) and WeatherSystem.is_precipitation():
		Bus.toast.emit("%s is being watered by the %s. Rest when ready." % [
			crop.get("name", "Crop"), WeatherSystem.display_name().to_lower()])
	elif not bool(state.get("watered", false)):
		if Farm.water(plot_id):
			Bus.toast.emit("Watered the %s." % crop.get("name", "crop"))
	else:
		var remaining := Farm.days_remaining(plot_id)
		Bus.toast.emit("%s - %d day%s remaining. Rest at home when ready." % [
			crop.get("name", "Crop"), remaining, "" if remaining == 1 else "s"])


func interaction_label() -> String:
	var state := Farm.plot(plot_id)
	if String(state.get("cropId", "")).is_empty():
		return "Plant a seed"
	var crop: Dictionary = Farm.crop_def_for_plot(plot_id)
	var name := String(crop.get("name", "crop"))
	if Farm.is_ready(plot_id):
		return "Harvest %s" % name
	if not bool(state.get("watered", false)) and WeatherSystem.is_precipitation():
		return "%s waters %s" % [WeatherSystem.display_name(), name]
	if not bool(state.get("watered", false)):
		return "Water %s" % name
	return "Check %s" % name


## Soil is flat ground, so it takes no feet offset; the crop stands on that soil and
## does, which keeps a tall mature plant Y-sorting against the player like any prop.
func _build_sprites() -> void:
	_soil = _make_sprite("Soil", SOIL_SHEET, SOIL_REGION, Vector2.ZERO)
	_crop = _make_sprite("Crop", CROP_SHEET, Rect2(0, 0, 16, 16), Vector2(0, -8))
	_crop.visible = false


func _make_sprite(sprite_name: String, sheet: Texture2D, region: Rect2,
		offset: Vector2) -> Sprite2D:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = region
	atlas.filter_clip = true
	var sprite := Sprite2D.new()
	sprite.name = sprite_name
	sprite.texture = atlas
	sprite.offset = offset
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	return sprite


func _refresh() -> void:
	if _soil == null:
		return
	var state := Farm.plot(plot_id)
	var watered := bool(state.get("watered", false)) or WeatherSystem.is_precipitation()
	_soil.modulate = SOIL_WET if watered else SOIL_DRY

	var crop_id := String(state.get("cropId", ""))
	_crop.visible = not crop_id.is_empty()
	if not _crop.visible:
		return
	var row: int = int(CROP_ROWS.get(crop_id, CROP_FALLBACK_ROW))
	var stage := clampi(Farm.stage(plot_id), 0, CROP_STAGE_COLUMNS.size() - 1)
	var column: int = CROP_STAGE_COLUMNS[stage]
	(_crop.texture as AtlasTexture).region = Rect2(column * 16, row * 16, 16, 16)
