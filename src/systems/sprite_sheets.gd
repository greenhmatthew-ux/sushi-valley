class_name SpriteSheets
extends RefCounted
## Builds SpriteFrames from the project's character walk sheets.
##
## Port of PreloadScene.defineWalkAnims() from the Phaser build. Every character
## sheet in assets/sprites/ shares one layout, so this is defined once rather than
## authored as ~100 SpriteFrames resources by hand:
##
##   4 columns x 4 rows of 16x16.
##   Columns are facing directions, rows are the walk-cycle frames.
##   down = column 0, up = 1, left = 2, right = 3.
##
## Idle is row 0 of the facing's column — a stable contact frame, not a paused
## mid-stride pose.

const FRAME_SIZE := Vector2i(16, 16)
const COLUMNS := 4
const WALK_FPS := 8.0

## Facing -> column index in the sheet.
const DIR_COLUMN := {
	"down": 0,
	"up": 1,
	"left": 2,
	"right": 3,
}


## Build looping `walk_<dir>` animations plus single-frame `idle_<dir>` poses.
##
## `rows` is how many walk-cycle frames the sheet has. The 16x16 sheets in this
## project are 4x4 (rows = 4); the older 8-frame sheets are 4x2 (rows = 2), where
## row 0 is standing and row 1 is stepping.
static func walk_frames(texture: Texture2D, rows: int = 4) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")

	for dir: String in DIR_COLUMN:
		var column: int = DIR_COLUMN[dir]

		var walk := "walk_" + dir
		frames.add_animation(walk)
		frames.set_animation_speed(walk, WALK_FPS)
		frames.set_animation_loop(walk, true)
		for row in rows:
			frames.add_frame(walk, _atlas(texture, column, row))

		# Idle is its own animation rather than a paused walk, so stopping never
		# leaves the character frozen mid-stride.
		var idle := "idle_" + dir
		frames.add_animation(idle)
		frames.set_animation_loop(idle, false)
		frames.add_frame(idle, _atlas(texture, column, 0))

	return frames


static func _atlas(texture: Texture2D, column: int, row: int) -> AtlasTexture:
	var region := AtlasTexture.new()
	region.atlas = texture
	region.region = Rect2i(
		Vector2i(column, row) * FRAME_SIZE,
		FRAME_SIZE
	)
	return region


## How many walk-cycle rows a sheet has, from its pixel height. Guards against a
## sheet being swapped for a differently-sized one without the caller noticing.
static func row_count(texture: Texture2D) -> int:
	return texture.get_height() / FRAME_SIZE.y


## A single stable portrait crop: idle_down's frame, column 0 row 0. For anywhere
## that wants one still image from a walk sheet — the Bestiary card, currently —
## rather than the full SpriteFrames animation set.
static func portrait(texture: Texture2D) -> AtlasTexture:
	return _atlas(texture, DIR_COLUMN["down"], 0)
