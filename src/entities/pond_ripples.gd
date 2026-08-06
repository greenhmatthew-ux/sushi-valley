extends Node2D
## Animated ripples scattered across open water.
##
## The village pond's centre tile measures 0.00 deviation — a solid blue rectangle, the same
## flat-fill problem the grass had, and the pond is 66 cells of it. Water has no textured
## variant on the Serene sheet, but it is the one surface that is supposed to move, so the
## flatness is broken with motion instead of with a second tile.
##
## The art is Ninja Adventure's 4-frame ripple sheet, already used by the fishing spot — this
## is the same frames on the same cadence, so the pond reads as one body of water rather than
## as a still pond with one animated hotspot on it.
##
## Decorative only: no collision, no interaction. The pond's own water tiles keep blocking.

const Art := preload("res://src/systems/world_art_catalog.gd")
const RIPPLE_FPS := 6.0
const TILE := 16

var _phase := 0.0
var _ripples: Array[Sprite2D] = []
## Per-ripple frame offset. Without it every ripple on the pond pulses in unison, which reads
## as the whole surface blinking rather than as water moving.
var _offsets: PackedFloat32Array = PackedFloat32Array()


## `cells` are tile coordinates of open water; `origin` is the tile layer's own position, so
## the ripples land on the pond even though this node hangs off the region root.
func build(cells: Array[Vector2i], origin: Vector2) -> void:
	# The region root is y-sorted, so a plain Node2D at y=0 sorts behind the ground no matter
	# where it sits in the child list. Sorting on the node's own children makes each ripple
	# sort by its own y, which is both visible and correct against the bank props.
	y_sort_enabled = true
	for cell in cells:
		var atlas := AtlasTexture.new()
		atlas.atlas = Art.RIPPLE_SHEET
		atlas.region = Rect2(0, 0, TILE, TILE)
		# Without this a neighbouring frame bleeds in along the seam at some zoom levels.
		atlas.filter_clip = true
		var sprite := Sprite2D.new()
		sprite.texture = atlas
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = origin + Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE / 2.0)
		add_child(sprite)
		_ripples.append(sprite)
		_offsets.append(float(absi(cell.x * 7 + cell.y * 13) % Art.RIPPLE_FRAMES))
	set_process(not _ripples.is_empty())


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta * RIPPLE_FPS, float(Art.RIPPLE_FRAMES))
	for i in _ripples.size():
		var frame := int(fmod(_phase + _offsets[i], float(Art.RIPPLE_FRAMES)))
		var atlas := _ripples[i].texture as AtlasTexture
		atlas.region = Rect2(frame * TILE, 0, TILE, TILE)
