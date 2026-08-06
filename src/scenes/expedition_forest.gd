extends Node2D
## The Lost Lunchbox Expedition room — one handcrafted instance, not a
## generated run (EXPEDITION_DESIGN.md: "literal, handcrafted instances using
## the regular Sushi Valley combat").
##
## The room is a spine, walked west to east: entry -> trail guard -> lunchbox
## (and its recall) -> wraith grove. What exists at any moment is decided by the
## saved stage, so quitting and walking back in puts the player exactly where
## they left off, with nothing already-beaten standing back up.
##
## Every fight is the ordinary combat loop — the enemies here are plain Enemy
## nodes and the room only listens for `enemy_died` to advance the stage. It
## owns no combat rules and no card logic; ExpeditionLogic owns the transitions.
##
## Ground is generated in code (this workflow has no interactive editor),
## matching wilds.gd: a grass base with a dirt trail rasterized through the
## stage placements, so the route the player must walk is the route they see.

const ExpeditionLogic = preload("res://src/systems/expedition_logic.gd")
## Swaps Serene's flat grass fill for textured grass once the region has finished building.
const GroundCover = preload("res://src/systems/ground_cover.gd")

const EXPEDITION_ID := "forest_lunchbox"
const TILE := 16
const W := 44   # tiles wide
const H := 28   # tiles tall
const GEN_SEED := 20260803

const GRASS := Vector2i(4, 0)
const TRAIL_CENTER := Vector2i(10, 2)
const TRAIL_LEFT := Vector2i(9, 2)
const TRAIL_RIGHT := Vector2i(6, 2)
const TRAIL_TOP: Array[Vector2i] = [Vector2i(7, 3), Vector2i(8, 3)]
const TRAIL_BOTTOM: Array[Vector2i] = [Vector2i(7, 1), Vector2i(8, 1)]
const TRAIL_TOP_LEFT := Vector2i(5, 2)
const TRAIL_TOP_RIGHT := Vector2i(3, 2)
const TRAIL_BOTTOM_LEFT := Vector2i(5, 1)
const TRAIL_BOTTOM_RIGHT := Vector2i(3, 1)

const MEADOW_FLOWERS: Array[Vector2i] = [
	Vector2i(2, 13), Vector2i(17, 24), Vector2i(17, 25), Vector2i(18, 25)]
const SHRUB := Vector2i(7, 12)

## Two canopy species, mixed per tree. Sakura is deliberately absent: this is a
## wraith grove, and pink blossom would fight the biome the room is selling.
const TREE_ART: Array[Texture2D] = [
	preload("res://assets/props/tree_green.png"),
	preload("res://assets/props/tree_leafy.png"),
]

## The walked spine, in tiles: entry, guard, a climb to the lunchbox clearing,
## then back down into the wraith grove. Mirrors the TS `placements` (entry
## 64,224 · encounter 240,224 · objective 400,144 · boss 624,224) at 16px per
## tile. Waypoints are close together on purpose: long diagonal segments
## rasterize into a hard staircase, and short ones bend.
## Starts at (1, 14) rather than (3, 14) so the brush reaches the west map edge,
## through the RetreatDoor's own tile: the way back out has to be visible from
## inside the room, and a trail that stops two tiles short of it reads as a
## dead end rather than as the way you came in.
const ROUTE: Array[Vector2i] = [
	Vector2i(1, 14), Vector2i(7, 14), Vector2i(10, 15), Vector2i(13, 14),
	Vector2i(15, 14), Vector2i(18, 14), Vector2i(20, 13), Vector2i(22, 12),
	Vector2i(23, 11), Vector2i(24, 10), Vector2i(25, 9), Vector2i(28, 9),
	Vector2i(31, 10), Vector2i(33, 11), Vector2i(35, 12), Vector2i(37, 13),
	Vector2i(41, 14),
]

## Tiles kept clear of trees around each stage placement, so a fight has room
## and the objective is never buried in canopy.
const CLEARINGS: Array[Vector2i] = [
	Vector2i(4, 14), Vector2i(15, 14), Vector2i(25, 9), Vector2i(39, 14),
]
const CLEARING_RADIUS := 3
## The instance is enclosed: a band of trees walls the room in, so it reads as a
## route through forest rather than an open field with a strip of dirt. The
## depth wavers between these bounds per column/row — a constant depth draws a
## ruler-straight rectangle, which is the one thing a forest edge never is.
const WALL_MIN := 2
const WALL_MAX := 5

@onready var ground: TileMapLayer = $Ground
@onready var entities: Node2D = $Entities

var detail: TileMapLayer
var _rng := RandomNumberGenerator.new()
var _blocked: Dictionary = {}
var _route_cells: Dictionary = {}
var _returning := false


func _ready() -> void:
	Audio.play_music("forest")
	_rng.seed = GEN_SEED
	_build_tileset()
	_build_ground()
	_build_bounds()
	_mark_occupied()
	_build_forest()
	_build_detail()
	_texture_grass()
	_place_player()
	_clamp_camera()

	var lunchbox := entities.get_node_or_null("Lunchbox")
	if lunchbox != null:
		lunchbox.stage_advanced.connect(_refresh_stage)
	Bus.enemy_died.connect(_on_enemy_died)
	_refresh_stage()


## What the room contains right now, read straight off the save. Called on entry
## and after every stage change, so the room is never out of step with progress.
func _refresh_stage() -> void:
	var stage := String(ExpeditionLogic.progress(
		Learning.profile, EXPEDITION_ID).get("stage", ""))
	# The guard only stands while the run is at its first stage.
	_set_active(entities.get_node_or_null("TrailGuard"), stage == "active")
	# The wraith sleeps until the lunchbox recall breaks the seal on its grove.
	_set_active(entities.get_node_or_null("ForestWraith"), stage == "recall-cleared")
	var lunchbox := entities.get_node_or_null("Lunchbox")
	if lunchbox != null and lunchbox.has_method("refresh"):
		lunchbox.refresh()


## Hidden AND out of the physics/interaction world — a dormant boss the player
## could still walk into or swing at would be a fight the stage does not allow.
func _set_active(node: Node, active: bool) -> void:
	if node == null:
		return
	(node as Node2D).visible = active
	node.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	if node is CollisionObject2D:
		(node as CollisionObject2D).set_deferred("collision_layer", 4 if active else 0)
	# The melee sensor is a separate CollisionObject2D. Hiding only the root body leaves
	# a sleeping boss hittable through PlayerCombat's layer-9 overlap query.
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
			Bus.toast.emit("Trail guard cleared — recover the lunchbox.")
			Bus.hud_refresh.emit()
			_refresh_stage()
		return
	if enemy_id == String(expedition.get("bossEncounterId", "")):
		var summary := ExpeditionLogic.complete_boss(
			Learning.profile, DB, Inv, expedition)
		if not summary.is_empty():
			Bus.toast.emit(summary)
			_return_to_woods()


## The run closes itself: a finished instance is not a place to stand around in.
## Deferred a beat so the completion toast is readable before the scene swaps.
func _return_to_woods() -> void:
	if _returning:
		return
	_returning = true
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree():
		Transitions.travel("res://src/scenes/wilds.tscn", "expedition_return")


# --- ground ----------------------------------------------------------------

func _build_tileset() -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)

	var grass_src := TileSetAtlasSource.new()
	grass_src.texture = preload("res://assets/tilesets/serene_village.png")
	grass_src.texture_region_size = Vector2i(TILE, TILE)
	grass_src.create_tile(GRASS)
	for tile in [TRAIL_CENTER, TRAIL_LEFT, TRAIL_RIGHT,
			TRAIL_TOP[0], TRAIL_TOP[1], TRAIL_BOTTOM[0], TRAIL_BOTTOM[1],
			TRAIL_TOP_LEFT, TRAIL_TOP_RIGHT, TRAIL_BOTTOM_LEFT, TRAIL_BOTTOM_RIGHT]:
		grass_src.create_tile(tile)
	ts.add_source(grass_src, 0)

	var decal_src := TileSetAtlasSource.new()
	decal_src.texture = preload("res://assets/tilesets/serene_village.png")
	decal_src.texture_region_size = Vector2i(TILE, TILE)
	var coords: Array[Vector2i] = [SHRUB]
	coords.append_array(MEADOW_FLOWERS)
	for c in coords:
		decal_src.create_tile(c)
	ts.add_source(decal_src, 1)

	ground.tile_set = ts
	detail = TileMapLayer.new()
	detail.name = "Detail"
	detail.tile_set = ts
	detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(detail)
	move_child(detail, 1)   # Ground(0) < Detail(1) < Entities(2)


func _build_ground() -> void:
	for x in W:
		for y in H:
			ground.set_cell(Vector2i(x, y), 0, GRASS)
	_build_route()


## Rasterize the spine, then widen it by a brush that breathes between two and
## three tiles along its length. A constant brush is what makes a generated path
## read as a stamped ribbon; the variation is what makes it read as walked.
func _build_route() -> void:
	_route_cells.clear()
	var step := 0
	for i in range(ROUTE.size() - 1):
		for center in _raster_line(ROUTE[i], ROUTE[i + 1]):
			step += 1
			var wide: bool = (step / 3) % 2 == 0
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					# Trim the corners on the narrow stretches so the edge wavers.
					if not wide and absi(dx) == 1 and absi(dy) == 1:
						continue
					var cell := center + Vector2i(dx, dy)
					if cell.x >= 0 and cell.x < W and cell.y >= 0 and cell.y < H:
						_route_cells[cell] = true
	for raw_cell in _route_cells:
		var cell: Vector2i = raw_cell
		ground.set_cell(cell, 0, _trail_tile(cell))
		_blocked[cell] = true


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


## Bit flags mean the route is open (missing) on that side: top=1, right=2,
## bottom=4, left=8 — same contract as wilds.gd, so both trails read alike.
func _trail_tile(cell: Vector2i) -> Vector2i:
	var open_mask := 0
	if not _route_cells.has(cell + Vector2i.UP):
		open_mask |= 1
	if not _route_cells.has(cell + Vector2i.RIGHT):
		open_mask |= 2
	if not _route_cells.has(cell + Vector2i.DOWN):
		open_mask |= 4
	if not _route_cells.has(cell + Vector2i.LEFT):
		open_mask |= 8
	match open_mask:
		1: return TRAIL_TOP[(cell.x + cell.y) & 1]
		2: return TRAIL_RIGHT
		3: return TRAIL_TOP_RIGHT
		4: return TRAIL_BOTTOM[(cell.x + cell.y) & 1]
		6: return TRAIL_BOTTOM_RIGHT
		8: return TRAIL_LEFT
		9: return TRAIL_TOP_LEFT
		12: return TRAIL_BOTTOM_LEFT
		_: return TRAIL_CENTER


func _build_bounds() -> void:
	var bounds := StaticBody2D.new()
	bounds.name = "Bounds"
	bounds.collision_layer = 1
	bounds.collision_mask = 0
	add_child(bounds)
	_add_bound(bounds, "Top", Vector2(W * TILE / 2.0, -4), Vector2(W * TILE, 8))
	_add_bound(bounds, "Bottom", Vector2(W * TILE / 2.0, H * TILE + 4), Vector2(W * TILE, 8))
	_add_bound(bounds, "Left", Vector2(-4, H * TILE / 2.0), Vector2(8, H * TILE))
	_add_bound(bounds, "Right", Vector2(W * TILE + 4, H * TILE / 2.0), Vector2(8, H * TILE))


func _add_bound(parent: StaticBody2D, shape_name: String,
		position: Vector2, size: Vector2) -> void:
	var collision := CollisionShape2D.new()
	collision.name = shape_name
	collision.position = position
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	parent.add_child(collision)


func _mark_occupied() -> void:
	for e in entities.get_children():
		if not (e is Node2D):
			continue
		var t := _to_tile((e as Node2D).position)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				_blocked[t + Vector2i(dx, dy)] = true


## Wall the instance in with trees, then break up the interior with groves.
##
## Generated rather than hand-placed because an enclosing forest is ~150 trees
## and a .tscn holding them would be unreadable and unmaintainable; the seed is
## fixed, so the layout is identical every run and can be judged from a
## screenshot like an authored one. Groves cluster instead of scattering —
## evenly spread trees read as noise, clumps read as woodland.
func _build_forest() -> void:
	var trees := Node2D.new()
	trees.name = "Forest"
	trees.y_sort_enabled = true
	entities.add_child(trees)

	# Per-column/row wall depths, drawn once so the edge undulates smoothly along
	# its length instead of jittering tile to tile (which reads as static, not trees).
	var depth_top: Array[int] = _edge_depths(W)
	var depth_bottom: Array[int] = _edge_depths(W)
	var depth_left: Array[int] = _edge_depths(H)
	var depth_right: Array[int] = _edge_depths(H)
	for x in W:
		for y in H:
			if y < depth_top[x] or y >= H - depth_bottom[x] \
					or x < depth_left[y] or x >= W - depth_right[y]:
				_plant(trees, Vector2i(x, y))

	# Interior groves. Centres are drawn off the trail; each drops a small clump.
	for i in 44:
		var center := Vector2i(_rng.randi_range(3, W - 4), _rng.randi_range(3, H - 4))
		if _blocked.has(center) or _in_clearing(center):
			continue
		for j in _rng.randi_range(2, 5):
			_plant(trees, center + Vector2i(
				_rng.randi_range(-2, 2), _rng.randi_range(-1, 1)))


## A wandering depth per column (or row) of the tree wall: each step moves at
## most one tile from the last, so the treeline reads as a continuous edge.
func _edge_depths(count: int) -> Array[int]:
	var depths: Array[int] = []
	var depth := _rng.randi_range(WALL_MIN, WALL_MAX)
	for i in count:
		depth = clampi(depth + _rng.randi_range(-1, 1), WALL_MIN, WALL_MAX)
		depths.append(depth)
	return depths


## One tree, if the cell is free. Marks the cell blocked so ground detail and
## later trees never stack on it.
func _plant(parent: Node2D, cell: Vector2i) -> void:
	if cell.x < 0 or cell.x >= W or cell.y < 0 or cell.y >= H:
		return
	if _blocked.has(cell) or _in_clearing(cell):
		return
	var tree := Prop.new()
	tree.texture = TREE_ART[_rng.randi() % TREE_ART.size()]
	tree.solid = true
	# Trunk-only footprint, matching the authored trees: the player tucks behind
	# the canopy and only the base blocks (project art rule).
	tree.foot_size = Vector2(12, 6)
	tree.foot_offset = Vector2(0, -3)
	tree.position = Vector2(cell.x * TILE + TILE / 2.0, cell.y * TILE + TILE)
	parent.add_child(tree)
	_blocked[cell] = true


## Keep the stage placements walkable and fightable.
func _in_clearing(cell: Vector2i) -> bool:
	for spot in CLEARINGS:
		if absi(cell.x - spot.x) <= CLEARING_RADIUS \
				and absi(cell.y - spot.y) <= CLEARING_RADIUS:
			return true
	return false


## Denser than the open wilds: this is deep forest, so the off-trail ground is
## busier and the walked route stays visibly clear.
func _build_detail() -> void:
	for x in range(1, W - 1):
		for y in range(1, H - 1):
			var c := Vector2i(x, y)
			if _blocked.has(c):
				continue
			var roll := _rng.randf()
			if roll < 0.12:
				_set_detail(c, MEADOW_FLOWERS[_rng.randi() % MEADOW_FLOWERS.size()])
			elif roll < 0.15:
				_set_detail(c, SHRUB)


func _set_detail(c: Vector2i, tile: Vector2i) -> void:
	if c.x < 1 or c.x >= W - 1 or c.y < 1 or c.y >= H - 1:
		return
	if _blocked.has(c):
		return
	detail.set_cell(c, 1, tile)


func _to_tile(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE)), int(floor(p.y / TILE)))


## Last, so the forest and detail passes above still see the flat grass they key off.
func _texture_grass() -> void:
	GroundCover.repaint(ground, GRASS)


func _place_player() -> void:
	var player: Node2D = entities.get_node_or_null("Player")
	if player == null:
		return
	var marker := _find_marker(Transitions.take_pending_spawn())
	if marker != null:
		player.global_position = marker.global_position
	if player.has_method("face"):
		player.face("right")


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
