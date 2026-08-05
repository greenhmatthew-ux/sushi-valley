class_name WorldArtCatalog
extends RefCounted
## Pure catalogue for the real 16px art used by interactive world objects.
##
## Keeping atlas coordinates out of entity scripts lets headless content tests load
## and validate them without compiling runtime scripts that depend on autoloads.

const SOIL_SHEET := preload("res://assets/tilesets/tilled_dirt.png")
const SOIL_REGION := Rect2(16, 80, 16, 16)

const CROP_SHEET := preload("res://assets/props/crop_stages.png")
const CROP_STAGE_COLUMNS := [1, 2, 4, 5]
const CROP_ROWS := {
	"rice": 3,
	"cucumber": 1,
	"mushroom": 5,
	"herb": 7,
}
const CROP_FALLBACK_ROW := 5

const RIPPLE_SHEET := preload("res://assets/tilesets/water_ripple.png")
const RIPPLE_FRAMES := 4

const NATURE_SHEET := preload("res://assets/tilesets/ninja_nature.png")
const ROCK_TAN := Rect2(18 * 16, 13 * 16, 16, 16)
const ROCK_GREY := Rect2(18 * 16, 17 * 16, 16, 16)
const PLANT_HERB := Rect2(4 * 16, 11 * 16, 16, 16)
const PLANT_BAMBOO := Rect2(7 * 16, 11 * 16, 16, 16)
const GREY_ORES := ["raw_iron_ore", "iron_ore", "stone"]
