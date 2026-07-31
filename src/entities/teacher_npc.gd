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
## Lesson id from data/learning/lessons.json that this teacher owns. Leave empty and set
## `teaches_category` instead to have this teacher walk a whole ladder.
@export var teaches_lesson: String = ""
## A lesson category (e.g. "kana-hiragana", "travel-dining"). A category teacher always
## works on the first lesson in that category the player has not yet finished, so one NPC
## can carry a 10-lesson ladder instead of needing ten NPCs standing in a row. The category
## order is the authored order in lessons.json.
@export var teaches_category: String = ""
## Said on the very first meeting, before the lesson unlocks. ENGLISH ONLY — a teacher's
## framing is narration, not curriculum. Every word of Japanese they utter comes from their
## lesson's sourced cards (see _greeting_line), because LEARNING_PROGRESSION.md forbids
## hardcoding lesson text into scenes and an earlier version of this file leaked invented
## Japanese into world.tscn through a free-text export.
@export var intro_lines: PackedStringArray = PackedStringArray(["Let me teach you a little Japanese."])
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


## The lesson this teacher is working on right now. For a single-lesson teacher that is
## fixed; for a category teacher it advances as the player finishes each rung.
func current_lesson() -> String:
	if not teaches_lesson.is_empty():
		return teaches_lesson
	if teaches_category.is_empty():
		return ""
	var first := ""
	for lid in DB.lesson_order:
		var l: Dictionary = DB.lessons[lid]
		if not _category_matches(String(l.get("category", ""))):
			continue
		if first.is_empty():
			first = lid
		if not _lesson_finished(lid):
			return lid
	# Whole ladder done — stay on the last rung so reviews still have somewhere to happen.
	return first


## "Finished" = every reviewable card unlocked and answered correctly at least once.
## Deliberately looser than LearningProgression's mastery check: this only decides when
## a teacher moves on to the next rung, not when the SRS considers a card learned.
## Non-recallable imported cards (page numbers, essays) can never be answered, so they
## must not hold the ladder hostage.
func _lesson_finished(lesson_id: String) -> bool:
	var ids: Array = DB.lesson(lesson_id).get("cardIds", [])
	if ids.is_empty():
		return true
	for id in ids:
		var c: Dictionary = Learning.profile.card(id)
		if not c.is_empty() and not LearningProgression.recall_eligible(c):
			continue
		if c.is_empty() or not c.get("unlocked", false) or int(c.get("correctCount", 0)) < 1:
			return false
	return true


## Prefix rule, mirroring LearningProgression's category pools: a "travel" teacher
## covers "travel" and every "travel-*" subcategory, so singleton travel lessons
## (Arrival, Dining, Transit, Stay & Payment) ride the same ladder instead of
## needing a dedicated NPC each.
func _category_matches(category: String) -> bool:
	return category == teaches_category or category.begins_with(teaches_category + "-")


func _run_interaction() -> void:
	# Pin the lesson for this whole interaction. current_lesson() is live, and a session can
	# FINISH the current rung mid-interaction — which used to advance it underneath us, so the
	# taught-flag landed on the next rung and the rung just taught was never marked.
	var lesson := current_lesson()
	if lesson.is_empty():
		Bus.dialogue_open.emit(speaker, ["Sorry, I have nothing to teach yet."])
		await Bus.dialogue_closed
		return

	Bus.npc_talked.emit(npc_id)
	# The flag is per-lesson, not per-NPC: a category teacher introduces each new rung of
	# the ladder the same way they introduced the first.
	if not Learning.get_flag(taught_flag(lesson)):
		await _first_meeting(lesson)
	else:
		await _return_visit(lesson)
	Bus.hud_refresh.emit()


## First meeting: greet in Japanese, unlock the lesson, then one micro-review so the words
## are used immediately rather than dumped and forgotten.
func _first_meeting(lesson: String) -> void:
	var lines: Array[String] = []
	for l in intro_lines:
		lines.append(String(l))
	# A real word from this teacher's own lesson, with its meaning as the reveal.
	var greeting := _greeting_line(lesson)
	if not greeting.is_empty():
		lines.append(greeting)
	Bus.dialogue_open.emit(speaker, lines)
	await Bus.dialogue_closed

	Learning.profile.unlock_lesson(lesson)
	Learning.profile.save()
	var title := String(DB.lesson(lesson).get("title", lesson))
	Bus.toast.emit("Learning: %s" % title)

	await _run_session(lesson)
	Learning.set_flag(taught_flag(lesson))


## Return visit: review only what the SRS says is actually due for this teacher's lesson.
## Nothing due is a good outcome, not a dead end — say so and let the player go.
func _return_visit(lesson: String) -> void:
	if _due_in_lesson(lesson) == 0:
		var lines_done: Array[String] = []
		var g := _greeting_line(lesson)
		if not g.is_empty():
			lines_done.append(g)
		lines_done.append("You're all caught up. Come back when these need review.")
		Bus.dialogue_open.emit(speaker, lines_done)
		await Bus.dialogue_closed
		return

	var lines_review: Array[String] = []
	var g2 := _greeting_line(lesson)
	if not g2.is_empty():
		lines_review.append(g2)
	lines_review.append("Let's review a little.")
	Bus.dialogue_open.emit(speaker, lines_review)
	await Bus.dialogue_closed
	await _run_session(lesson)


## One micro-review against this teacher's lesson. Practice is allowed so a first meeting
## always has something to show, even before anything is scheduled as due.
func _run_session(lesson: String) -> void:
	Bus.learn_open.emit(lesson, session_size, true)
	var res: Array = await Bus.learn_closed   # [attempted, correct, cancelled]
	var attempted: int = res[0]
	var correct: int = res[1]
	if attempted > 0 and not bool(res[2]):
		Bus.toast.emit("%s: %d/%d" % [speaker, correct, attempted])


## A greeting drawn from this teacher's OWN lesson, as "japanese|meaning". Prefers a
## phrase card (a real thing a person says) over a bare vocab word, and returns "" when the
## lesson has neither — never a fabricated line.
func _greeting_line(lesson_id: String) -> String:
	var lesson: Dictionary = DB.lesson(lesson_id)
	var fallback := ""
	for id in lesson.get("cardIds", []):
		var c: Dictionary = Learning.profile.card(id)
		if c.is_empty():
			continue
		var ja := String(c.get("prompt", ""))
		var meaning := String(c.get("meaning", ""))
		if meaning.is_empty():
			meaning = String(c.get("answer", ""))
		if ja.is_empty():
			continue
		var line := "%s|%s" % [ja, meaning]
		if String(c.get("type", "")) == "phrase":
			return line
		if fallback.is_empty():
			fallback = line
	return fallback


## Cards from this lesson that the shared SRS says are due right now.
func _due_in_lesson(lesson_id: String) -> int:
	var lesson: Dictionary = DB.lesson(lesson_id)
	var pool: Array = []
	for id in lesson.get("cardIds", []):
		var c: Dictionary = Learning.profile.card(id)
		if not c.is_empty() and c.get("unlocked", false):
			pool.append(c)
	return Srs.due(pool).size()


## Save flag marking that this teacher has introduced a given lesson. Public so tests and
## future quest logic can ask without recomputing the naming rule.
func taught_flag(lesson_id: String) -> String:
	return "taught_%s_%s" % [npc_id, lesson_id]


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
