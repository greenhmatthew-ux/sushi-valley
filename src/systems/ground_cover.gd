extends RefCounted
## Textured grass for every outdoor region.
##
## Serene Village's grass tile is, by design, a flat fill: measured across the sheet its
## per-channel detail deviation is 2.67, i.e. a near-solid green square. The pack builds
## interest with overlay decals and ground-type changes instead. That works for a hand-made
## RPG Maker map with props on every screen; it does not work for our open fields, where
## 76% of the village ground (1003 of 1320 authored cells) is that one tile and reads as a
## flat green sheet with confetti on it.
##
## Adding more decals does not fix it — the base is what looks flat. So the base is replaced
## with grass that has texture in the tile itself. The whole library was scanned for a 16px,
## fully opaque, self-tiling green tile close to Serene's own grass colour: Kenney's Tiny
## Town grass is the nearest match by a wide margin (palette distance 16.5 vs 58+ for the
## next candidate) and tiles seamlessly with itself. Serene's buildings, props and road edge
## tiles were checked against it side by side before it was adopted.
##
## Two variants alternate on a stable hash of the cell. One variant alone would repeat its
## tuft pattern into a visible grid; mixing Serene's grass with Kenney's was tried first and
## rejected — the slight colour difference between the two sources turned the field into a
## patchwork of squares, which looks worse than flat.
##
## Kenney assets are CC0. See CREDITS.md.

## Plain and tufted grass, sliced out of Tiny Town's packed tilemap. Both are the same base
## green, so they never read as two different materials — only as grass with growth in it.
const TEXTURE: Texture2D = preload("res://assets/tilesets/kenney_ground.png")
const PLAIN := Vector2i(0, 0)
const TUFT := Vector2i(1, 0)

## Kept clear of the source ids the regions already use (0 terrain, 1 decals).
const SOURCE_ID := 7
const TILE := 16


## Add the grass atlas to a region's TileSet. Safe to call repeatedly, and safe on a TileSet
## shared between layers (the village's EdgeGround underlay shares the Ground one).
static func register(tile_set: TileSet) -> void:
	if tile_set == null or tile_set.has_source(SOURCE_ID):
		return
	var source := TileSetAtlasSource.new()
	source.texture = TEXTURE
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(PLAIN)
	source.create_tile(TUFT)
	tile_set.add_source(source, SOURCE_ID)


## Swap every flat-grass cell on `layer` for a textured one, and report how many changed.
##
## Call this LAST, after a region has finished generating. Everything else keys off the flat
## grass coord to decide where it may plant — `_build_meadow`, `_plant_outskirts` and
## `_soften_path_edges` all test `get_cell_atlas_coords(cell) == GRASS`. Repaint before them
## and they find no grass left to decorate.
static func repaint(layer: TileMapLayer, flat_grass: Vector2i) -> int:
	if layer == null or layer.tile_set == null:
		return 0
	register(layer.tile_set)
	var changed := 0
	for cell in layer.get_used_cells():
		# Source 0 only: a region may legitimately reuse this atlas coord on another sheet.
		if layer.get_cell_source_id(cell) != 0:
			continue
		if layer.get_cell_atlas_coords(cell) != flat_grass:
			continue
		layer.set_cell(cell, SOURCE_ID, TUFT if _tufted(cell) else PLAIN)
		changed += 1
	return changed


## Share of cells that get the tufted tile rather than the plain one.
##
## Deliberately not 50/50. Kenney's plain grass measures 0.00 deviation — it is every bit as
## flat as the Serene tile being replaced, so an even split would leave half the map exactly
## as flat as before and the most common tile in the village would still be a solid fill.
## The tufted tile carries the texture, so it has to dominate. The plain one is kept as a
## minority so the tuft pattern does not repeat into a visible regular grid; at this ratio it
## reads as thinner, more worn ground rather than as a second material.
const TUFT_SHARE := 72


## Hashed from the coordinate rather than drawn from an RNG so the meadow is identical every
## run and every save reload, and so two layers that overlap (the village Ground and its
## EdgeGround underlay) agree on any shared cell.
static func _tufted(cell: Vector2i) -> bool:
	var h: int = cell.x * 374761393 + cell.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h >> 7) % 100 < TUFT_SHARE
