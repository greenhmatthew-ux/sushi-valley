extends Area2D
## A doorway between levels. Same interactable contract as LessonGate / Npc:
## an Area2D in group "interactable", collision_layer 8, exposing interact(player) —
## the player's InteractProbe finds it and calls interact(), so no player.gd changes.
##
## On use it travels to `target_scene`, arriving at the marker named `target_spawn`
## in that scene. Set both per-instance in the editor.
##
## SIGNAGE — why a trigger volume draws anything at all:
## a Door used to be completely invisible, and most of them are `auto_enter`, so the
## patch of grass that dumps you into another region looked exactly like the patch of
## grass beside it. There was no way to see where the exits were, and no way to know
## where one went until it had already taken you. The four signage exports below build
## the cue in code (so the .tscn stays small, the same trick expedition_gate.gd uses)
## out of the picket post the lesson gate and expedition gate already stand on — a
## gated route and an open one then read as one visual system — plus the Serene
## Village arrow signpost pointing back at the gap, plus a nameplate in the same style
## as every NPC/pickup label in the world.
##
## Nothing built here is solid. A prop that could block the way into a transition is
## exactly the bug this is meant to prevent, so the posts frame the gap and never
## narrow it (matching the lesson gate, whose posts are decoration and whose barrier
## is a separate body).

const SIGN_SHEET := preload("res://assets/tilesets/serene_village.png")
## Picket post — the same tile lesson_gate.tscn and expedition_gate.gd use.
const POST_REGION := Rect2(80, 240, 16, 16)
## Wooden arrow signposts from the same sheet. Never mirrored: the sheet ships both
## facings, and the art rules forbid flipping an asset to fake one.
const ARROW_RIGHT_REGION := Rect2(128, 224, 16, 16)
const ARROW_LEFT_REGION := Rect2(128, 240, 16, 16)
## Plain board, used when the sign stands directly above or below the gap and an
## arrow would be pointing at nothing.
const BOARD_REGION := Rect2(128, 208, 16, 16)

@export_file("*.tscn") var target_scene: String = ""
## Must match a spawn marker's `spawn_id` in the destination scene ("" = its default).
@export var target_spawn: String = ""
## Set on a village door: the spawn in THIS scene to send the player back to, so the
## shared interior's exit can return them to the correct doorstep.
@export var return_spawn: String = ""
## Interior exit doors set this — travel to the recorded return spawn (which house the
## player entered from) instead of a fixed target_spawn.
@export var uses_return_spawn: bool = false
## When true, stepping onto the door travels immediately (no interact press needed).
@export var auto_enter: bool = false

## Where this door goes, in player words and phrased to follow a preposition:
## "the Whispering Woods", "the House". The world nameplate reads "To <destination>"
## and the context prompt reads "Enter <destination>", so one authored phrase keeps
## both surfaces in step. English only — this is signage, not lesson content (see
## sign_post.gd on why no field here ever takes Japanese).
@export var destination: String = ""
## Non-zero stands a picket post at +offset AND -offset, framing the walkable gap.
## Use (20, 0) for a gap walked north/south and (0, 20) for one walked east/west.
@export var post_offset: Vector2 = Vector2.ZERO
## Non-zero stands an arrow signpost here, relative to the door, pointing back at the
## gap. Keep it clear of the walked line — a sign standing in the doorway is the prop
## overlap the art rules forbid.
@export var sign_offset: Vector2 = Vector2.ZERO
## Where the nameplate floats, relative to the door. Authored per-instance because a
## door at the edge of a map needs its plate pushed inward to stay on screen.
@export var label_offset: Vector2 = Vector2(0, -30)

var _used := false


func _ready() -> void:
	add_to_group("interactable")
	if auto_enter:
		body_entered.connect(_on_body_entered)
	_build_signage()


## Called by the player's interaction probe when they press interact nearby.
func interact(_player: Node = null) -> void:
	_travel()


func _on_body_entered(body: Node) -> void:
	# Only the player triggers a door — not enemies (which are CharacterBody2D too and
	# could otherwise wander in and yank the scene out from under a fight). Deferred so the
	# scene swap doesn't run inside this physics callback (freeing bodies mid-callback errors).
	if body.is_in_group("player"):
		_travel.call_deferred()


func _travel() -> void:
	if _used:
		return   # guard against a double-fire during the scene change
	if target_scene.is_empty():
		push_warning("[Door] no target_scene set on %s" % name)
		return
	_used = true
	var spawn := Transitions.peek_return_spawn() if uses_return_spawn else target_spawn
	Transitions.travel(target_scene, spawn, return_spawn)


## Build whichever parts of the trailhead this instance authored. All three parts are
## optional so one contract covers a woodland gap, a house doorstep, and an interior
## exit without a mode enum: a doorway the building art already draws just leaves
## `post_offset` at zero.
func _build_signage() -> void:
	if post_offset != Vector2.ZERO:
		_add_marker("PostLeft", POST_REGION, -post_offset)
		_add_marker("PostRight", POST_REGION, post_offset)
	if sign_offset != Vector2.ZERO:
		_add_marker("Sign", _arrow_region(), sign_offset)
	# Only a walk-in door floats a permanent nameplate. An auto_enter door fires
	# without asking, so its destination has to be legible BEFORE you reach it; a
	# door you press interact at gets that same destination from the context prompt
	# instead, and hanging a second copy of it over a village doorstep only adds a
	# label to a screen that already carries one per NPC, station and cache.
	if auto_enter and not destination.is_empty():
		_add_nameplate()


## The arrow points from where the sign stands back toward the gap, so it always
## reads "the way is over there". A sign directly above or below the gap has no
## horizontal side to point from, so it falls back to the plain board.
func _arrow_region() -> Rect2:
	if sign_offset.x < 0.0:
		return ARROW_RIGHT_REGION
	if sign_offset.x > 0.0:
		return ARROW_LEFT_REGION
	return BOARD_REGION


## Feet on the node origin (offset -8 on a 16px tile), so a marker Y-sorts against the
## player like every other standing thing. filter_clip stops a neighbouring tile
## bleeding in at the sprite edge.
func _add_marker(marker_name: String, region: Rect2, offset: Vector2) -> void:
	var atlas := AtlasTexture.new()
	atlas.atlas = SIGN_SHEET
	atlas.region = region
	atlas.filter_clip = true
	var sprite := Sprite2D.new()
	sprite.name = marker_name
	sprite.texture = atlas
	sprite.position = offset
	sprite.offset = Vector2(0, -8)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)


## Same 8px outlined plate the NPCs, vendors and caches already float, so an exit
## label is read the same way as every other world label. Warm parchment rather than
## the NPC white or the vendor gold, matching the wooden signs it names.
func _add_nameplate() -> void:
	var label := Label.new()
	label.name = "Nameplate"
	label.text = "To %s" % destination
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.99, 0.91, 0.74))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(160, 12)
	label.position = label_offset - Vector2(80, 0)
	add_child(label)
