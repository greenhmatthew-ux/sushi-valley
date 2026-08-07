extends Node2D
## The Summit Cache Expedition room — the second handcrafted instance.
##
## Same contract as `expedition_forest.gd` (EXPEDITION_DESIGN.md: "literal,
## handcrafted instances using the regular Sushi Valley combat"): entry -> guard
## -> objective and its recall -> boss, with what exists at any moment decided by
## the saved stage, so a retreat resumes exactly where the save says.
##
## It is deliberately NOT that room with different trees. The forest instance is a
## west-to-east spine through woodland walled in by canopy; this is a south-to-north
## CLIMB walled in by rock, so it is taller than it is wide and the player reads
## progress as altitude. Reusing the forest's shape would be the same placeholder
## failure as reusing one interior layout for the second building.
##
## Ground is generated in code, matching every other region (this workflow has no
## interactive editor); only the props, enemies and the cache live in the .tscn.
##
## THE SNOW LINE IS THE POINT. The Mountain Pass below is bare warm stone, and its
## floor tile measures 0.00 detail deviation — a solid tan fill, recorded in
## `tests/test_ground_not_flat.gd`'s KNOWN_FLAT list because the relief sheet has no
## seamless textured floor to replace it with (every candidate is a wall stripe or a
## ledge course; they were rendered and looked at before that was written down).
##
## This room does not inherit that problem, because it is above the snow line and
## therefore is not drawn on that sheet at all. Ninja Adventure's interior-floor
## sheet carries a grey-green stone family with snow lying on it — (11,11) swept
## bare, (13,11) light snow, (12,11) drifted — all opaque, all seamless with each
## other, and the dominant tile measures ~32 rather than 0.00. Same pack, same 16px,
## no new import.
##
## And it earns its keep as design, not just as a test pass: the route through this
## room is the line where the snow has been TRODDEN OFF, so "the way" is legible as
## bare stone through white without needing a path tile that fights the ground it
## crosses — which is exactly the failure the pass below still has.

const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")

const EXPEDITION_ID := "pass_summit"
const TILE := 16
const W := 30   # tiles wide — narrow, because this is a climb, not a country
const H := 46   # tiles tall
const GEN_SEED := 20260806

# --- ninja_interior_floor atlas coords (source 0) -----------------------------
## The alpine floor family. BARE is the swept route, LIGHT the ordinary snowfield,
## DRIFT the deeper patches. All three share one base grey-green, so they read as
## one ground in three depths of snow rather than as three materials — the mistake
## `ground_cover.gd` records from mixing two sources' greens into a patchwork.
const BARE := Vector2i(11, 11)
const SNOW_LIGHT := Vector2i(13, 11)
const SNOW_DRIFT := Vector2i(12, 11)

# --- ninja_relief_detail atlas coords (source 1) -----------------------------
## The rock mass the climb is cut through.
##
## The Mountain Pass's own cliff band was tried here first and rejected on the
## screenshot. That band is three tiles deep at the top edge of a wide map, where
## its vertical striations read as strata; wrapped six tiles deep around a narrow
## ravine it repeats into vertical planks and the room reads as a wooden crate.
## `test_ground_not_flat.gd` already records that this sheet family "renders as
## vertical wood planks when tiled" — that was written about the floor, and it
## turns out to be just as true of the wall once there is enough of it on screen.
##
## This tile is rough mottled rock with no bar, notch or mortar line to repeat, and
## it shares the floor family's grey-green, so wall and snow read as one mountain.
const ROCK_WALL := Vector2i(1, 2)
const SCREE: Array[Vector2i] = [Vector2i(0, 3), Vector2i(4, 5)]
const BOULDERS: Array[Vector2i] = [Vector2i(4, 3), Vector2i(4, 4)]

const PROP_SCENE := preload("res://src/entities/prop.tscn")
const ROCK_TEXTURE: Texture2D = preload("res://assets/props/rock.png")
const ROCK_FOOT := Vector2(12, 6)
const PROP_FOOT_OFFSET := Vector2(0, -2)

## The climb, bottom to top, in tiles. Mirrors the data `placements` at 16px per
## tile: entry (248,664) -> guard (216,536) -> cache (296,360) -> king (248,136).
## The entry sits three tiles clear of the retreat door rather than beside it: the
## door's reach is 20px and `auto_enter` fires on touch, so a spawn any closer walks
## the player straight back out of the run before they have control.
## Waypoints sit close together on purpose — long diagonal runs rasterise into a
## hard staircase, short ones bend, which is the same lesson the forest spine
## records.
const ROUTE: Array[Vector2i] = [
	Vector2i(15, 45), Vector2i(15, 43), Vector2i(14, 40), Vector2i(13, 37),
	Vector2i(13, 33), Vector2i(14, 31), Vector2i(16, 29), Vector2i(18, 27),
	Vector2i(18, 22), Vector2i(17, 20), Vector2i(15, 18), Vector2i(13, 15),
	Vector2i(14, 12), Vector2i(15, 10), Vector2i(15, 6),
]
## A short spur west to a cairn shelf. §7.5: a dead end has to pay off, so this one
## ends at the ore seam the .tscn places rather than in empty snow.
const CAIRN_SPUR: Array[Vector2i] = [
	Vector2i(16, 29), Vector2i(11, 28), Vector2i(8, 27),
]

## Tiles kept clear of rock around each stage placement, so a fight has room and the
## cache is never buried in scatter.
const CLEARINGS: Array[Vector2i] = [
	Vector2i(15, 43), Vector2i(13, 33), Vector2i(18, 22), Vector2i(15, 8),
]
const CLEARING_RADIUS := 3

## Depth of the rock wall boxing the climb in. It wanders between these bounds per
## row so the ravine pinches and opens along its length — the composition rhythm
## the design guide asks for (open -> narrow -> reveal -> pocket) comes from this
## rather than from props. A constant depth would draw a ruler-straight corridor.
const WALL_MIN := 2
const WALL_MAX := 6
## Guaranteed clear width down the middle, so a wandering wall can never pinch the
## climb shut and strand the player.
const MIN_OPEN := 9

## How far down the rock is drawn from full daylight. Enough to separate cliff from
## snowfield at map zoom without turning the wall into a black silhouette.
const WALL_SHADE := Color(0.62, 0.66, 0.70)

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities

var walls: TileMapLayer
var detail: TileMapLayer
var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}
var _route_cells: Dictionary = {}
var _wall_cells: Dictionary = {}
var _returning := false


func _ready() -> void:
	Audio.play_music("mountain")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_walls()
	_build_ground()
	_build_bounds()
	_mark_occupied()
	_scatter_rock()
	_build_detail()
	_place_player()
	_clamp_camera()

	var cache := entities.get_node_or_null("SummitCache")
	if cache != null:
		cache.stage_advanced.connect(_refresh_stage)
	Bus.enemy_died.connect(_on_enemy_died)
	_refresh_stage()


## What the room contains right now, read straight off the save.
func _refresh_stage() -> void:
	var stage := String(ExpeditionLogic.progress(
		Learning.profile, EXPEDITION_ID).get("stage", ""))
	# The drake only holds the narrows while the run is at its first stage.
	_set_active(entities.get_node_or_null("TrailGuard"), stage == "active")
	# The king sleeps under the summit until the cache recall wakes him.
	_set_active(entities.get_node_or_null("MountainKing"), stage == "recall-cleared")
	var cache := entities.get_node_or_null("SummitCache")
	if cache != null and cache.has_method("refresh"):
		cache.refresh()


## Hidden AND out of the physics/interaction world — a dormant boss the player could
## still walk into or swing at would be a fight the stage does not allow.
func _set_active(node: Node, active: bool) -> void:
	if node == null:
		return
	(node as Node2D).visible = active
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CollisionObject2D:
		(node as CollisionObject2D).set_deferred("collision_layer", 4 if active else 0)
	# The melee sensor is a separate CollisionObject2D. Hiding only the root body
	# leaves a sleeping boss hittable through PlayerCombat's layer-9 overlap query.
	var hurtbox := node.get_node_or_null("Hurtbox") as Area2D
	if hurtbox != null:
		hurtbox.set_deferred("collision_layer", 256 if active else 0)
		hurtbox.set_deferred("monitorable", active)


func _on_enemy_died(enemy_id: String) -> void:
	var expedition: Dictionary = DB.expedition(EXPEDITION_ID)
	if expedition.is_empty():
		return
	if enemy_id in expedition.get("encounterIds", []):
		if ExpeditionLogic.mark_encounter_cleared(Learning.profile, EXPEDITION_ID):
			Bus.toast.emit("The narrows are clear — climb to the cache.")
			Bus.hud_refresh.emit()
			_refresh_stage()
		return
	if enemy_id == String(expedition.get("bossEncounterId", "")):
		var summary := ExpeditionLogic.complete_boss(
			Learning.profile, DB, Inv, expedition)
		if not summary.is_empty():
			Bus.toast.emit(summary)
			_return_to_pass()


## The run closes itself: a finished instance is not a place to stand around in.
## Deferred a beat so the completion toast is readable before the scene swaps.
func _return_to_pass() -> void:
	if _returning:
		return
	_returning = true
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree():
		Transitions.travel("res://src/scenes/mountain_pass.tscn", "summit_return")


# --- ground ------------------------------------------------------------------

## Three sources, built in code so every coordinate painted below is registered —
## an unregistered coord silently draws nothing.
func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var floor_src := TileSetAtlasSource.new()
	floor_src.texture = preload("res://assets/tilesets/ninja_interior_floor.png")
	floor_src.texture_region_size = Vector2i(TILE, TILE)
	for c in [BARE, SNOW_LIGHT, SNOW_DRIFT]:
		floor_src.create_tile(c)
	ts.add_source(floor_src, 0)

	var rock_src := TileSetAtlasSource.new()
	rock_src.texture = preload("res://assets/tilesets/ninja_relief_detail.png")
	rock_src.texture_region_size = Vector2i(TILE, TILE)
	var rock_coords: Array[Vector2i] = [ROCK_WALL]
	rock_coords.append_array(SCREE)
	rock_coords.append_array(BOULDERS)
	for c in rock_coords:
		rock_src.create_tile(c)
	ts.add_source(rock_src, 1)

	ground.tile_set = ts

	# The rock gets its own layer so it can be shaded.
	#
	# On the screenshot, wall and snowfield share the sheet's grey-green and at map
	# zoom the boundary all but vanished — the player could not see where the ravine
	# stopped, which is a worse failure than the plank pattern this tile replaced.
	# The fix is not another tile (every alternative on both sheets is masonry brick,
	# a black void, or the planks again — they were rendered side by side against the
	# snow before this was settled): it is that rock in the lee of a cliff IS in
	# shadow, and drawing it at full daylight value was the actual mistake.
	walls = TileMapLayer.new()
	walls.name = "Walls"
	walls.tile_set = ts
	walls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	walls.modulate = WALL_SHADE
	add_child(walls)

	detail = TileMapLayer.new()
	detail.name = "Detail"
	detail.tile_set = ts
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(detail)
	# Ground(0) < Walls(1) < Detail(2) < Entities(3)
	move_child(walls, 1)
	move_child(detail, 2)


## Decide the rock walls first, because everything else — the snowfield, the route
## repair, the scatter — needs to know which cells are not floor at all.
func _build_walls() -> void:
	_wall_cells.clear()
	var left := _edge_depths(H)
	var right := _edge_depths(H)
	for y in H:
		# Never let the two sides meet: the climb has to stay walkable at its
		# narrowest, and a wandering wall with no floor under it is a sealed room.
		var l: int = left[y]
		var r: int = right[y]
		var overflow: int = (l + r + MIN_OPEN) - W
		if overflow > 0:
			l = maxi(WALL_MIN, l - (overflow + 1) / 2)
			r = maxi(WALL_MIN, r - overflow / 2)
		for x in range(0, l):
			_wall_cells[Vector2i(x, y)] = true
		for x in range(W - r, W):
			_wall_cells[Vector2i(x, y)] = true
	# Cap and floor the room so it is enclosed rather than fading into empty space.
	for x in W:
		for y in range(0, WALL_MIN):
			_wall_cells[Vector2i(x, y)] = true
		for y in range(H - 1, H):
			_wall_cells[Vector2i(x, y)] = true


## A wandering depth per row: each step moves at most one tile from the last, so the
## rock face reads as a continuous wall rather than as jitter.
func _edge_depths(count: int) -> Array[int]:
	var depths: Array[int] = []
	var depth := _rng.randi_range(WALL_MIN, WALL_MAX)
	for i in count:
		depth = clampi(depth + _rng.randi_range(-1, 1), WALL_MIN, WALL_MAX)
		depths.append(depth)
	return depths


func _build_ground() -> void:
	_build_route()
	for x in W:
		for y in H:
			var cell := Vector2i(x, y)
			if _wall_cells.has(cell):
				walls.set_cell(cell, 1, ROCK_WALL)
				_blocked[cell] = true
			elif _route_cells.has(cell):
				ground.set_cell(cell, 0, BARE)
			else:
				ground.set_cell(cell, 0, SNOW_DRIFT if _drifted(cell) else SNOW_LIGHT)


## Share of open ground carrying the deeper drift tile. Deliberately a minority: the
## drift is the busier art, and at an even split its clumps repeat into a visible
## regular grid, which is the failure `ground_cover.gd` documents for its own pair.
const DRIFT_SHARE := 24


## Hashed from the coordinate rather than drawn from the RNG, so the snowfield is
## identical every run and every reload and can be judged from a screenshot like an
## authored map.
static func _drifted(cell: Vector2i) -> bool:
	var h: int = cell.x * 374761393 + cell.y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h >> 7) % 100 < DRIFT_SHARE


## Rasterise the climb and the cairn spur, then widen by a brush that breathes
## between one and two tiles. The route is not painted with a path tile — it is the
## snow scraped off down to the stone, so `_build_ground` lays BARE on these cells.
func _build_route() -> void:
	_route_cells.clear()
	_add_route(ROUTE, 2)
	_add_route(CAIRN_SPUR, 1)
	# A wandering wall can eat the outer end of the spur. Drop any route cell the
	# rock claimed rather than painting bare stone inside a cliff.
	for raw_cell in _route_cells.keys():
		if _wall_cells.has(raw_cell):
			_route_cells.erase(raw_cell)


func _add_route(waypoints: Array, width: int) -> void:
	var step := 0
	for i in range(waypoints.size() - 1):
		for center in _raster_line(waypoints[i], waypoints[i + 1]):
			step += 1
			# Breathe between a narrow and a wide brush along the length. A constant
			# brush is what makes a generated path read as a stamped ribbon.
			var wide: bool = (step / 4) % 2 == 0
			var reach: int = width if wide else width - 1
			for dx in range(-reach, reach + 1):
				for dy in range(-reach, reach + 1):
					if absi(dx) == reach and absi(dy) == reach:
						continue   # trim corners so the verge wavers
					var cell: Vector2i = center + Vector2i(dx, dy)
					if cell.x >= 0 and cell.x < W and cell.y >= 0 and cell.y < H:
						_route_cells[cell] = true


func _raster_line(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var x := from_cell.x
	var y := from_cell.y
	var dx := absi(to_cell.x - from_cell.x)
	var sx := 1 if from_cell.x < to_cell.x else -1
	var dy := -absi(to_cell.y - from_cell.y)
	var sy := 1 if from_cell.y < to_cell.y else -1
	var error := dx + dy
	while true:
		cells.append(Vector2i(x, y))
		if x == to_cell.x and y == to_cell.y:
			break
		var twice_error := 2 * error
		if twice_error >= dy:
			error += dy
			x += sx
		if twice_error <= dx:
			error += dx
			y += sy
	return cells


## One collision rect per contiguous run of wall in a row. Per-cell bodies would be
## ~600 shapes for the same result; the runs are what the player actually touches.
func _build_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	var index := 0
	for y in H:
		var run_start := -1
		for x in range(W + 1):
			var solid: bool = x < W and _wall_cells.has(Vector2i(x, y))
			if solid and run_start < 0:
				run_start = x
			elif not solid and run_start >= 0:
				var span := x - run_start
				_add_bound(bounds, "Wall%d" % index,
					Vector2((run_start + span / 2.0) * TILE, (y + 0.5) * TILE),
					Vector2(span * TILE, TILE))
				index += 1
				run_start = -1


func _add_bound(parent: StaticBody2D, shape_name: String,
		position: Vector2, size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	collision.name = shape_name
	collision.position = position
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	parent.add_child(collision)


## Keep scatter off the tiles the authored entities stand on. Doors and markers take
## the widest pad: a boulder beside a walk-in door would hide the way out.
func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		var t := _to_tile((e as Node2D).position)
		var pad := 3 if (e is Marker2D or e is Area2D
			or String(e.name).ends_with("Door")) else 1
		for dx in range(-pad, pad + 1):
			for dy in range(-pad, pad + 1):
				_blocked[t + Vector2i(dx, dy)] = true


## Boulders fallen from the walls, clustered against them rather than sprinkled down
## the middle — evenly spread rock reads as noise, rock banked at the foot of a cliff
## reads as scree that came off it. Never on the route: the swept line stays walkable.
func _scatter_rock() -> void:
	var fallen := Node2D.new()
	fallen.name = "Fallen"
	fallen.y_sort_enabled = true
	entities.add_child(fallen)
	for y in range(WALL_MIN + 1, H - 2):
		for x in range(1, W - 1):
			var cell := Vector2i(x, y)
			if _blocked.has(cell) or _route_cells.has(cell) or _in_clearing(cell):
				continue
			# Chance falls off with distance from the nearest wall.
			var near := _wall_distance(cell)
			if near > 3:
				continue
			if _rng.randf() > [0.0, 0.22, 0.10, 0.04][near]:
				continue
			var rock := PROP_SCENE.instantiate() as Prop
			if rock == null:
				continue
			rock.texture = ROCK_TEXTURE
			rock.foot_size = ROCK_FOOT
			rock.foot_offset = PROP_FOOT_OFFSET
			# Origin is the feet, so sit the prop on the bottom-centre of its tile.
			rock.position = Vector2(cell.x * TILE + TILE / 2.0, (cell.y + 1) * TILE)
			fallen.add_child(rock)
			_blocked[cell] = true


## Tiles to the nearest wall cell, capped — only "how close to the rock" matters.
func _wall_distance(cell: Vector2i) -> int:
	for radius in range(1, 5):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				if _wall_cells.has(cell + Vector2i(dx, dy)):
					return radius
	return 5


## Keep the stage placements walkable and fightable.
func _in_clearing(cell: Vector2i) -> bool:
	for spot in CLEARINGS:
		if absi(cell.x - spot.x) <= CLEARING_RADIUS \
				and absi(cell.y - spot.y) <= CLEARING_RADIUS:
			return true
	return false


## Loose stone showing through the snow, and scree banked along the swept route so
## the walked line has verges. Sparse: this is a snowfield with rock under it, not a
## gravel carpet.
func _build_detail() -> void:
	for x in range(1, W - 1):
		for y in range(WALL_MIN + 1, H - 1):
			var cell := Vector2i(x, y)
			if _blocked.has(cell) or _route_cells.has(cell):
				continue
			var roll := _rng.randf()
			var verge := _touches_route(cell)
			if roll < (0.34 if verge else 0.07):
				detail.set_cell(cell, 1, SCREE[_rng.randi_range(0, SCREE.size() - 1)])
			elif roll < (0.38 if verge else 0.09):
				detail.set_cell(cell, 1, BOULDERS[_rng.randi_range(0, BOULDERS.size() - 1)])


func _touches_route(cell: Vector2i) -> bool:
	for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		if _route_cells.has(cell + step):
			return true
	return false


func _to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


func _place_player() -> void:
	var player: Node2D = entities.get_node_or_null("Player")
	if player == null:
		return
	var marker := _find_marker(Transitions.take_pending_spawn())
	if marker != null:
		player.global_position = marker.global_position
	if player.has_method("face"):
		player.face("up")


func _find_marker(spawn_id: String) -> Node2D:
	var fallback: Node2D = null
	for m in get_tree().get_nodes_in_group("spawn_point"):
		if fallback == null:
			fallback = m
		if not spawn_id.is_empty() and m.get("spawn_id") == spawn_id:
			return m
	return fallback


func _clamp_camera() -> void:
	var player: Node2D = entities.get_node_or_null("Player")
	if player == null:
		return
	var cam: Camera2D = player.get_node_or_null("Camera")
	if cam == null:
		return
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = W * TILE
	cam.limit_bottom = H * TILE
	cam.reset_smoothing()
