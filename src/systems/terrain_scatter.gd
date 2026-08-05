class_name TerrainScatter
extends RefCounted
## Pure placement maths for code-generated regions: trail brushes and prop scatter.
##
## No nodes, no scene tree, no autoloads — regions hand it their size, their occupied
## tiles and a per-zone density table, and get back a list of "put a thing of this kind
## on this tile". What the art *is* stays with the region; only *where* is decided here.
##
## Extracted when the Mountain Pass needed the same lattice, clumping and clearance rules
## the Wilds had just grown. Two copies of this would have drifted the moment one region
## was tuned.

## Tiles between lattice candidates. The world props are 32px, so a one-tile lattice mats
## canopies into a wall and a three-tile one reads as a planted orchard.
const DEFAULT_LATTICE := 2
## Side of the coarse clump block, in tiles.
const DEFAULT_CLUMP_BLOCK := 5
const CLUMP_FLOOR := 0.15
const CLUMP_RANGE := 1.6


## The square brush stamped around one rasterised route cell. `width` 1 is single file,
## 2 a walked trail, 3 a road. The outer band is dropped on a hash of the cell so edges
## look walked rather than stamped — but the centreline is never dropped, so a route stays
## connected and a door sitting on a waypoint is always reached.
static func brush_cells(center: Vector2i, width: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var lo := -(width - 1) / 2
	var hi := width / 2
	for dx in range(lo, hi + 1):
		for dy in range(lo, hi + 1):
			var cell := center + Vector2i(dx, dy)
			var is_centerline := dx == 0 and dy == 0
			var on_edge := dx == lo or dx == hi or dy == lo or dy == hi
			if width > 1 and on_edge and not is_centerline \
					and ((cell.x * 7 + cell.y * 13) & 3) == 0:
				continue
			cells.append(cell)
	if cells.is_empty():
		cells.append(center)
	return cells


## Coarse per-block weight in [CLUMP_FLOOR, CLUMP_FLOOR + CLUMP_RANGE]. Multiplying a
## density by this turns a uniform roll into thickets and glades; without it, scatter comes
## out evenly spaced, which is the giveaway that nobody placed it.
static func clump_weight(cell: Vector2i, block: int = DEFAULT_CLUMP_BLOCK) -> float:
	var block_x := cell.x / maxi(block, 1)
	var block_y := cell.y / maxi(block, 1)
	var hashed := absi((block_x * 73856093) ^ (block_y * 19349663))
	return CLUMP_FLOOR + CLUMP_RANGE * (float(hashed % 997) / 997.0)


## Decide what goes where. `mix_for` is called with a tile and returns kind -> chance for
## that zone; kinds named in `clumped_kinds` have their chance clump-weighted, so incidental
## things (a rock) still show up inside a thicket. Returns [{cell, kind}], nothing else —
## `blocked` is only read, never written, so the caller stays in charge of its own map.
##
## A candidate must clear everything in `blocked` by a full tile, which is what keeps cover
## off trails, off doorways and out of authored landmarks. Placements also clear each other
## by a tile, so trunks stand at least two tiles apart.
static func plan_cover(size: Vector2i, blocked: Dictionary, mix_for: Callable,
		clumped_kinds: Array[String], rng_seed: int,
		lattice: int = DEFAULT_LATTICE,
		clump_block: int = DEFAULT_CLUMP_BLOCK) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var placed: Dictionary = {}
	var plan: Array[Dictionary] = []
	var step: int = maxi(lattice, 1)
	for lattice_x in range(step, size.x - step, step):
		for lattice_y in range(step, size.y - step, step):
			var cell := Vector2i(
				lattice_x + rng.randi_range(-1, 1),
				lattice_y + rng.randi_range(-1, 1))
			var roll := rng.randf()
			var kind := _kind_for(cell, roll, mix_for, clumped_kinds, clump_block)
			if kind.is_empty():
				continue
			if not is_clear(cell, size, blocked, placed):
				continue
			placed[cell] = true
			plan.append({"cell": cell, "kind": kind})
	return plan


## Inside the map with a one-tile margin, a clear tile ring around it, and nothing already
## planned within that ring.
static func is_clear(cell: Vector2i, size: Vector2i, blocked: Dictionary,
		placed: Dictionary) -> bool:
	if cell.x < 1 or cell.x >= size.x - 1 or cell.y < 1 or cell.y >= size.y - 1:
		return false
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var probe := cell + Vector2i(dx, dy)
			if blocked.has(probe) or placed.has(probe):
				return false
	return true


## Tiles that give a resource node a reason to be where it is — ore against stone, bamboo in
## a stand, herbs under cover.
##
## `plan_cover` deliberately holds a clear ring around everything in `blocked`, and resource
## nodes are blocked, so the ground beside a seam always came out bare and the node read as
## dropped wherever the scatter left a gap. This is the opposite job: pick tiles that *touch*
## the node.
##
## Only diagonals are ever used, so all four straight approaches stay walkable no matter how
## much cover is asked for — cover that seals a node off is a worse failure than cover that is
## missing. `reserved` (routes, doorways) is skipped outright.
##
## Gaps are measured in pixels against where the prop's feet will actually land, not in tiles.
## Props are drawn from their feet and nodes sit wherever they were authored inside their
## tile — often right on a grid corner — so "one tile diagonally" can put a boulder 8px from
## the seam it is meant to explain, drawn straight over it. Candidates are tried from the
## node outwards and anything closer than `MIN_ANCHOR_GAP` is skipped.
const MIN_ANCHOR_GAP := 26.0
## Diagonals only, nearest first. No offset has dx == 0, so the straight approaches stay open.
const ANCHOR_OFFSETS: Array[Vector2i] = [
	Vector2i(-1, -2), Vector2i(1, -2), Vector2i(-1, 1), Vector2i(1, 1),
	Vector2i(-2, -2), Vector2i(2, -2), Vector2i(-2, 2), Vector2i(2, 2),
	Vector2i(-2, -3), Vector2i(2, -3), Vector2i(-2, 3), Vector2i(2, 3),
]
static func anchor_cells(origin: Vector2, tile_px: int, wanted: int, size: Vector2i,
		blocked: Dictionary, reserved: Dictionary) -> Array[Vector2i]:
	var center := Vector2i((origin / float(tile_px)).floor())
	var out: Array[Vector2i] = []
	for offset in ANCHOR_OFFSETS:
		if out.size() >= wanted:
			break
		var cell: Vector2i = center + offset
		if cell.x < 1 or cell.x >= size.x - 1 or cell.y < 1 or cell.y >= size.y - 1:
			continue
		if blocked.has(cell) or reserved.has(cell):
			continue
		var feet := Vector2(cell.x * tile_px + tile_px / 2.0, (cell.y + 1) * tile_px)
		if feet.distance_to(origin) < MIN_ANCHOR_GAP:
			continue
		out.append(cell)
	return out


static func _kind_for(cell: Vector2i, roll: float, mix_for: Callable,
		clumped_kinds: Array[String], clump_block: int) -> String:
	var mix: Dictionary = mix_for.call(cell)
	if mix.is_empty():
		return ""
	var clump := clump_weight(cell, clump_block)
	var threshold := 0.0
	for raw_kind in mix:
		var kind := String(raw_kind)
		var chance := float(mix[raw_kind])
		if kind in clumped_kinds:
			chance *= clump
		threshold += chance
		if roll < threshold:
			return kind
	return ""
