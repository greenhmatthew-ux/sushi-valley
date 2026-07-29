extends Area2D
## A villager who actually teaches you Japanese — the doc-specified starting loop
## ("Talk to Hana (first time): unlocks greetings + food words, then a micro-recall").
##
## Same interactable contract as Npc / LessonGate: an Area2D in group "interactable" on
## collision layer 8 exposing interact(player), so the player's InteractProbe drives it with
## no player.gd changes. Like Npc it is non-blocking (no StaticBody) — teachers add life
## without walling the player in.
##
## Two states, on purpose (LEARNING_PROGRESSION.md: "Prefer several encounters with a small
## high-value card set over one gate followed by permanent completion"):
##   FIRST MEETING — greet, unlock this teacher's lesson, run one micro-review.
##   RETURN VISITS — if cards from that lesson are due, offer a short review; if nothing is
##                   due, say so warmly and move on. Never a forced review wall.
##
## All scheduling goes through the ONE shared profile/SRS via Bus round-trips
## (emit learn_open, await learn_closed) — this node never touches the recall UI directly
## and never owns a card deck of its own (SITE_WIDE_LEARNING_ARCHITECTURE.md: "One SrsSystem
## everywhere; never fork it per surface").

## Authored per-instance in the editor.
@export var npc_id: String = "teacher"
@export var speaker: String = "Teacher"
## Lesson id from data/learning/lessons.json that this teacher owns.
@export var teaches_lesson: String = ""
## Said on the very first meeting, before the lesson unlocks.
@export var intro_lines: PackedStringArray = PackedStringArray(["Let me teach you a little Japanese."])
## Japanese the teacher greets you with. Spoken aloud when a Japanese voice is installed.
@export var greeting_ja: String = ""
@export var greeting_meaning: String = ""
## Micro-review size. Kept small by design — 1/3/5 only, never a review wall.
@export var session_size: int = 3
@export var sprite_sheet: Texture2D = preload("res://assets/sprites/npc_villager3.png")

var _busy := false


func _ready() -> void:
	add_to_group("interactable")
	_build_visual()


## Called by the player's interaction probe when they press interact nearby.
func interact(player: Node = null) -> void:
	if _busy:
		return
	_busy = true
	if player != null and player.has_method("face"):
		player.face(_facing_from(global_position - player.global_position))
	await _run_interaction()
	_busy = false


func _run_interaction() -> void:
	if teaches_lesson.is_empty():
		Bus.dialogue_open.emit(speaker, ["ごめんなさい。|Sorry, I have nothing to teach yet."])
		await Bus.dialogue_closed
		return

	Bus.npc_talked.emit(npc_id)
	if not Learning.get_flag(_met_flag()):
		await _first_meeting()
	else:
		await _return_visit()
	Bus.hud_refresh.emit()


## First meeting: greet in Japanese, unlock the lesson, then one micro-review so the words
## are used immediately rather than dumped and forgotten.
func _first_meeting() -> void:
	var lines: Array[String] = []
	for l in intro_lines:
		lines.append(String(l))
	# The word itself, with its meaning as the reveal-able translation.
	if not greeting_ja.is_empty():
		lines.append("%s|%s" % [greeting_ja, greeting_meaning])
	Bus.dialogue_open.emit(speaker, lines)
	await Bus.dialogue_closed

	Learning.profile.unlock_lesson(teaches_lesson)
	Learning.profile.save()
	var title := String(DB.lesson(teaches_lesson).get("title", teaches_lesson))
	Bus.toast.emit("Learning: %s" % title)

	await _run_session()
	Learning.set_flag(_met_flag())


## Return visit: review only what the SRS says is actually due for this teacher's lesson.
## Nothing due is a good outcome, not a dead end — say so and let the player go.
func _return_visit() -> void:
	if _due_in_lesson() == 0:
		Bus.dialogue_open.emit(speaker, [
			"%s|%s" % [greeting_ja, greeting_meaning],
			"きょうは だいじょうぶです。|You're all caught up today.",
			"またきてください。|Please come again.",
		])
		await Bus.dialogue_closed
		return

	Bus.dialogue_open.emit(speaker, [
		"%s|%s" % [greeting_ja, greeting_meaning],
		"すこし ふくしゅう しましょう。|Let's review a little.",
	])
	await Bus.dialogue_closed
	await _run_session()


## One micro-review against this teacher's lesson. Practice is allowed so a first meeting
## always has something to show, even before anything is scheduled as due.
func _run_session() -> void:
	Bus.learn_open.emit(teaches_lesson, session_size, true)
	var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
	var attempted: int = res[0]
	var correct: int = res[1]
	if attempted > 0 and not bool(res[2]):
		Bus.toast.emit("%s: %d/%d" % [speaker, correct, attempted])


## Cards from this lesson that the shared SRS says are due right now.
func _due_in_lesson() -> int:
	var lesson: Dictionary = DB.lesson(teaches_lesson)
	var pool: Array = []
	for id in lesson.get("cardIds", []):
		var c: Dictionary = Learning.profile.card(id)
		if not c.is_empty() and c.get("unlocked", false):
			pool.append(c)
	return Srs.due(pool).size()


func _met_flag() -> String:
	return "met_teacher_%s" % npc_id


func _facing_from(dir: Vector2) -> String:
	if absf(dir.x) > absf(dir.y):
		return "right" if dir.x > 0.0 else "left"
	return "down" if dir.y > 0.0 else "up"


## Standing sprite + a name label, built in code so the .tscn stays tiny (matches Npc).
func _build_visual() -> void:
	var body := Sprite2D.new()
	body.texture = sprite_sheet
	body.region_enabled = true
	body.region_rect = Rect2(0, 0, 16, 16)   # column 0, row 0 — standing, facing down
	body.offset = Vector2(0, -8)              # feet on the node origin
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(body)

	var label := Label.new()
	label.text = speaker
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color(0.624, 0.839, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 12)
	label.position = Vector2(-40, -30)
	add_child(label)
