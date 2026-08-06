extends CanvasLayer
## The recall micro-review UI. Rebuild of LearnPrompt.ts as Godot Control nodes.
##
## A gentle multiple-choice review: no typing, no shame. A wrong answer reveals
## the reading/meaning as a hint, and repeated misses surface more scaffolding.
## Results feed the shared SRS through Learning.progression.
##
## Bus-driven so it is decoupled from whatever opened it (a gate, a bookshelf, a
## menu button): it listens for `learn_open` and answers with `learn_closed`.
## Sessions of size > 1 run a short Focus Session with a streak header and a
## perfect-run XP bonus.
##
## Built in code because the number of choice buttons varies per card, and because
## the whole panel is dynamic — authoring it as a static .tscn would fight that.

const PERFECT_BONUS := 15   # extra XP for clearing a whole session with no misses

# Palette carried over from the TS build so the feel is consistent.
const COL_DIM := UiTheme.SURFACE_BACKDROP
const COL_PANEL := UiTheme.SURFACE_BASE
const COL_BORDER := UiTheme.ACCENT_GOLD
const COL_HEADING := UiTheme.TEXT_MUTED
const COL_HINT := UiTheme.STATE_INFO
const COL_HINT_STRONG := UiTheme.ACCENT_GOLD
const COL_GOOD := UiTheme.STATE_SUCCESS
const COL_BTN := UiTheme.SURFACE_RAISED
const COL_BTN_BORDER := UiTheme.BORDER_STRONG
const COL_CORRECT := UiTheme.FILL_CORRECT
const COL_WRONG := UiTheme.FILL_WRONG

# --- session state (mirrors LearnPrompt fields) ---
var _active := false
var _total := 1
var _index := 0                # questions completed so far
var _correct_count := 0
var _streak := 0
var _consecutive_wrong := 0
var _seen := {}
var _focus_lesson := ""
var _allow_practice := false
var _answered := false
var _current: Dictionary = {}
## How often a card that has already been answered correctly is asked by ear
## instead of by sight. Kept well below half: the written form is still the
## primary thing being taught, and a session that is mostly audio would stop
## training recognition of the script.
const LISTENING_CHANCE := 0.35
var _listening := false
var _rng := RandomNumberGenerator.new()

## Vertical density rungs, roomiest first. Rung 0 is the authored look.
##
## This is the tightest panel in the game: its reveal state stacks a heading row,
## furigana, the prompt, a hint, the feedback line, two answer rows and Continue.
## Every rung below 0 spends the cheapest-looking pixels first — panel padding and
## row gaps go before the prompt font, because the Japanese has to stay clearly
## larger than the body text around it (UI_UX_GUIDE section 16). The prompt floors
## at 30, the guide's FONT_JAPANESE minimum; it is never taken down to body size
## just to make the arithmetic work, which is why the last two rungs hold it there
## and buy their pixels from spacing and width alone.
##
## `choice` is only the answer buttons' *minimum* height. Their real height still
## comes from UiTheme.wrapped_height, so no answer is ever clipped or scrolled —
## that is the one thing this panel exists to guarantee. 34 still clears the 24px
## minimum focus target.
##
## `width` is the other half of the trade, and the cheaper half. The canvas is 640
## wide and 360 tall: this panel has never had a width problem, only a height one,
## and every extra pixel of width is a line the prompt, the feedback, and the two
## answer columns each do not have to wrap onto. So the lower rungs spend width to
## buy height back. Rung 0 is 470 — what the panel has always measured, since the
## grid's two 200px columns plus 24px padding pushed it past its authored 460.
const DENSITY: Array[Dictionary] = [
	{"prompt": 40, "sep": 10, "pad": 24, "choice": 42.0, "grid": 10, "head": 26, "width": 470.0},
	{"prompt": 38, "sep": 8, "pad": 18, "choice": 40.0, "grid": 8, "head": 26, "width": 470.0},
	{"prompt": 36, "sep": 6, "pad": 14, "choice": 40.0, "grid": 8, "head": 26, "width": 470.0},
	{"prompt": 34, "sep": 6, "pad": 12, "choice": 38.0, "grid": 6, "head": 24, "width": 520.0},
	{"prompt": 32, "sep": 5, "pad": 10, "choice": 36.0, "grid": 5, "head": 22, "width": 545.0},
	{"prompt": 30, "sep": 4, "pad": 8, "choice": 34.0, "grid": 4, "head": 22, "width": 570.0},
	{"prompt": 30, "sep": 3, "pad": 6, "choice": 32.0, "grid": 3, "head": 22, "width": 620.0},
]

## Gap between the two answer columns. The columns never expand past their minimum,
## so the width each answer wraps into is exact, not an estimate — see _choice_width.
const CHOICE_GAP := 16.0
## The border the panel stylebox draws on each of the four sides. It counts against
## both budgets, so _content_height and _choice_width need it named.
const PANEL_BORDER := 3.0
## Breathing room kept between the panel and the edge of the canvas, so a wide rung
## can never make the frame the thing that overflows sideways.
const CANVAS_INSET := 8.0

var _root: Control
## Held so the density rungs can retune spacing, padding, and the frame check.
var _panel: PanelContainer
var _vbox: VBoxContainer
var _margin: MarginContainer
## Current rung in DENSITY. Reset from the canvas on every render, then pushed
## further by _fit_frame when the card in hand is taller than average.
var _density := 0
## Answer-row minimum height, and the exact width one answer wraps into, for the
## current rung. Both are set by _set_density; see DENSITY.
var _choice_height := 42.0
var _choice_width := 200.0
## The panel's width at the current rung, after the canvas clamp.
var _panel_width := 470.0
var _heading: Label
var _furigana: Label
var _question: Label
var _listen_spacer: Control
var _listen_btn: Button
var _hint: Label
var _feedback: Label
var _choices_box: GridContainer
var _continue_btn: Button


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS   # keep running while the world is paused
	_build_scaffold()
	_root.hide()
	Bus.learn_open.connect(_on_learn_open)
	Bus.ui_scale_changed.connect(func(_s):
		UiTheme.fit_layer(self, _root)
		_apply_metrics())


func _on_learn_open(focus_lesson: String, session_size: int, allow_practice: bool) -> void:
	if _active:
		return   # one session at a time
	_total = maxi(1, session_size)
	_index = 0
	_correct_count = 0
	_streak = 0
	_consecutive_wrong = 0
	_seen.clear()
	_focus_lesson = focus_lesson
	# Multi-card sessions fall back to practice once due cards run out, so the run
	# can still complete (matches LearnPrompt).
	_allow_practice = allow_practice or _total > 1
	_active = true
	get_tree().paused = true
	_run_next()


func _run_next() -> void:
	var prompt: Dictionary = Learning.progression.build_prompt({}, _allow_practice, _focus_lesson)
	# Stop early if nothing is left, or the pool is so small we'd just repeat a card.
	if prompt.is_empty() or (_index > 0 and _seen.has(prompt["card"].get("id", ""))):
		_finish()
		return
	_seen[prompt["card"].get("id", "")] = true
	_current = prompt
	_answered = false
	_render(prompt)
	_root.show()


func _render(prompt: Dictionary) -> void:
	# Back to the rung this canvas starts at; the card about to be laid out gets to
	# push it down again from there, rather than inheriting the last card's squeeze.
	_apply_metrics()
	var is_session := _total > 1
	if is_session:
		_heading.text = "Focus session — %d/%d%s" % [
			_index + 1, _total, ("     Streak %d" % _streak) if _streak > 1 else ""]
	else:
		_heading.text = "Quick recall" if prompt["mode"] == "due" else "Notebook practice"
	_heading.add_theme_color_override("font_color", COL_HEADING)

	_set_line(_hint, "")
	_set_line(_feedback, "")
	_continue_btn.hide()
	var card_id := String(prompt["card"].get("id", ""))
	var has_audio := Audio.has_pronunciation(card_id)
	_listen_spacer.visible = has_audio
	_listen_btn.visible = has_audio
	Audio.stop_pronunciation()
	if has_audio:
		Audio.play_pronunciation(card_id)

	# Listening round: the written form is withheld and only the recording is given.
	# Reading a word and catching it spoken are different skills, and the game only
	# ever trained the first. Withheld only after the card has been answered
	# correctly at least once, so a word is always seen before it is heard blind.
	_listening = has_audio \
		and int(prompt["card"].get("correctCount", 0)) >= 1 \
		and _rng.randf() < LISTENING_CHANCE
	_question.text = "Listen" if _listening else String(prompt["question"])

	# Furigana: the reading printed above the Japanese, per UI_UX_GUIDE section 15.
	# Withheld during a listening round — the whole point there is to identify the
	# word by ear, and spelling it out on screen would answer the question.
	var reading := String(prompt.get("reading", "")).strip_edges()
	var correct_count := int(prompt["card"].get("correctCount", 0))
	# A kana card's reading is its own prompt, so printing it above would just repeat
	# the same characters — the aid is only an aid when it says something new.
	var show_reading := not _listening and not reading.is_empty() \
		and reading != String(prompt["question"]) \
		and Settings.furigana_visible(correct_count)
	_furigana.text = reading if show_reading else ""
	_furigana.visible = show_reading
	if _listening:
		_set_line(_hint, "Which word did you hear?")
		_hint.add_theme_color_override("font_color", COL_HINT)

	# Adaptive scaffolding: struggling players get more context up front.
	var scaffold := _scaffold_level()
	if scaffold == 2 and prompt.get("reading", "") != "" and prompt.get("meaning", "") != "":
		_set_line(_hint, "%s — %s" % [prompt["reading"], prompt["meaning"]])
		_hint.add_theme_color_override("font_color", COL_HINT_STRONG)
	elif scaffold >= 1 and prompt.get("reading", "") != "":
		_set_line(_hint, String(prompt["reading"]))
		_hint.add_theme_color_override("font_color", COL_HINT)

	# Removed as well as freed: a queue_free'd child stays listed for the rest of the
	# frame, and the height measurement below would count the old card's answers on
	# top of the new one's.
	for child in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	var first_choice: Button = null
	for choice in prompt["choices"]:
		var choice_btn := _make_choice_button(String(choice))
		_choices_box.add_child(choice_btn)
		if first_choice == null:
			first_choice = choice_btn
	# Keyboard/controller: focus the first answer once the panel is shown, so arrows /
	# d-pad can move between choices right away. Deferred so it runs after _root.show().
	if first_choice != null:
		first_choice.grab_focus.call_deferred()
	_fit_frame()


func _make_choice_button(choice: String) -> Button:
	var btn := Button.new()
	btn.text = choice
	# Never clip an answer: the player cannot choose between options they can only
	# half read. Long choices wrap and step down a size instead.
	btn.clip_text = false
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.custom_minimum_size = Vector2(_choice_width, _choice_height)
	# Focusable so arrows / d-pad move between answers and ui_accept selects — the panel
	# is no longer mouse-only (the project requires keyboard AND controller to work).
	btn.focus_mode = Control.FOCUS_ALL
	btn.add_theme_stylebox_override("normal", _button_style(COL_BTN, COL_BTN_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(COL_BTN.lightened(0.08), COL_BORDER))
	btn.add_theme_stylebox_override("pressed", _button_style(COL_BTN, COL_BORDER))
	btn.add_theme_font_size_override("font_size", UiTheme.fit_font_size(choice, 18))
	# The rung sets a floor; the text sets the real height. wrapped_height is what
	# keeps a two-line answer whole no matter how dense the panel has had to get.
	btn.custom_minimum_size.y = maxf(
		_choice_height, UiTheme.wrapped_height(btn, choice, _choice_width))
	btn.pressed.connect(_on_choice.bind(choice, btn))
	return btn


func _on_choice(choice: String, btn: Button) -> void:
	if _answered:
		return
	_answered = true
	var card: Dictionary = _current["card"]
	var correct: bool = Learning.progression.answer(card, choice)

	_index += 1
	if correct:
		_correct_count += 1
		_streak += 1
		_consecutive_wrong = 0
	else:
		_streak = 0
		_consecutive_wrong += 1

	Bus.card_reviewed.emit(String(card.get("id", "")), Srs.grade_from_correct(correct), correct)

	# Colour the chosen button, and on a miss also light up the right answer.
	btn.add_theme_stylebox_override("normal", _button_style(COL_CORRECT if correct else COL_WRONG, COL_BORDER))
	btn.add_theme_stylebox_override("hover", _button_style(COL_CORRECT if correct else COL_WRONG, COL_BORDER))
	if not correct:
		for other in _choices_box.get_children():
			if other is Button and (other as Button).text == String(_current["answer"]):
				other.add_theme_stylebox_override("normal", _button_style(COL_CORRECT, COL_BORDER))

	# A listening round withheld the writing; show it now, while the sound is still
	# in the player's head. That pairing is the whole point of asking by ear.
	if _listening:
		_question.text = String(card.get("prompt", ""))

	var reading := String(card.get("reading", ""))
	var answer_txt := reading if reading != "" else String(card.get("answer", ""))
	var meaning := String(card.get("meaning", ""))
	if correct:
		_feedback.add_theme_color_override("font_color", COL_GOOD)
		_set_line(_feedback, "Correct!   %s = %s" % [card.get("prompt", ""), answer_txt])
	else:
		_feedback.add_theme_color_override("font_color", COL_HINT_STRONG)
		_set_line(_feedback, "%s = %s%s" % [card.get("prompt", ""), answer_txt,
			("   (%s)" % meaning) if meaning != "" else ""])
	# Imported decks glue their usage notes onto the end of the answer, where they
	# are too long to sit on a rune button. Normalization moves them to `note`, and
	# the reveal is the one moment the player has room to read them.
	var note := String(card.get("note", ""))
	if not note.is_empty():
		_set_line(_feedback, _feedback.text + "\n%s" % note)

	# Replay the card's sourced recording after any answer, win or miss.
	Audio.play_pronunciation(String(card.get("id", "")))

	_continue_btn.show()
	_continue_btn.grab_focus()
	# The reveal is the tall state: Continue and the feedback line both arrive at
	# once, and on a listening or scaffolded card the hint row is still standing.
	_fit_frame()


func _on_continue() -> void:
	_root.hide()
	if _total > 1 and _index < _total:
		_run_next()
	else:
		_finish()


func _finish() -> void:
	_root.hide()
	if _total > 1:
		var perfect := _correct_count == _index and _index > 0
		if perfect:
			Learning.progression.award_xp(PERFECT_BONUS)
		var summary: String
		if _index == 0:
			summary = "Nothing to review right now."
		elif perfect:
			summary = "Perfect focus! %d/%d  +%d XP" % [_correct_count, _index, PERFECT_BONUS]
		else:
			summary = "Focus session: %d/%d correct" % [_correct_count, _index]
		Bus.toast.emit(summary)
	_close(false)


func _close(cancelled: bool) -> void:
	var attempted := _index
	var correct := _correct_count
	Audio.stop_pronunciation()
	_active = false
	_current = {}
	get_tree().paused = false
	Bus.learn_closed.emit(attempted, correct, cancelled)


func _input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed("ui_cancel"):
		# ESC cancels; a settled prompt (already answered) shouldn't be abandoned
		# mid-feedback, so require an unanswered prompt — matching LearnPrompt.
		if not _answered:
			_root.hide()
			_close(true)
			get_viewport().set_input_as_handled()
		return
	# Number-key quick-answer (1..N), mirroring the on-screen choice order — a fast path
	# alongside focus navigation. Guard on echo so a held key fires once.
	if not _answered and event is InputEventKey and event.pressed and not (event as InputEventKey).echo:
		var n := (event as InputEventKey).keycode - KEY_1
		if n >= 0 and n < _choices_box.get_child_count():
			var choice_btn := _choices_box.get_child(n) as Button
			_on_choice(choice_btn.text, choice_btn)
			get_viewport().set_input_as_handled()


## reading only after 2 consecutive misses; reading + meaning after 3.
func _scaffold_level() -> int:
	if _consecutive_wrong >= 3:
		return 2
	if _consecutive_wrong >= 2:
		return 1
	return 0


# --- static scaffold, built once ------------------------------------------

func _build_scaffold() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	UiTheme.fit_layer(self, _root)

	var dim := ColorRect.new()
	dim.color = COL_DIM
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	var panel := _panel
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(DENSITY[0]["width"], 0)   # rung sets the real width
	_root.add_child(panel)
	# Center it.
	panel.anchor_left = 0.5; panel.anchor_top = 0.5
	panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	_margin = MarginContainer.new()
	panel.add_child(_margin)
	var margin := _margin

	_vbox = VBoxContainer.new()
	margin.add_child(_vbox)
	var vbox := _vbox

	var heading_row := HBoxContainer.new()
	vbox.add_child(heading_row)

	_listen_spacer = Control.new()
	_listen_spacer.custom_minimum_size = Vector2(96, 0)
	heading_row.add_child(_listen_spacer)

	_heading = _label(14, COL_HEADING)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading_row.add_child(_heading)

	_listen_btn = Button.new()
	_listen_btn.text = "Listen"
	_listen_btn.tooltip_text = "Play the sourced Japanese recording"
	_listen_btn.custom_minimum_size = Vector2(96, 26)
	_listen_btn.focus_mode = Control.FOCUS_ALL
	_listen_btn.add_theme_font_size_override("font_size", UiTheme.FONT_META)
	_listen_btn.add_theme_stylebox_override("normal", _compact_button_style(COL_BTN, COL_BTN_BORDER))
	_listen_btn.add_theme_stylebox_override("hover", _compact_button_style(COL_BTN.lightened(0.08), COL_BORDER))
	_listen_btn.add_theme_stylebox_override("pressed", _compact_button_style(COL_BTN, COL_BORDER))
	_listen_btn.pressed.connect(_on_listen_pressed)
	heading_row.add_child(_listen_btn)

	# Above the prompt, small and quiet: it is a reading aid, not the question.
	_furigana = _label(13, COL_HINT)
	_furigana.name = "Furigana"
	_furigana.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_furigana.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_furigana)

	# Size comes from the density rung, never from here: see DENSITY. 40 is the
	# roomiest rung (48 would crowd the furigana row) and only the two largest
	# canvases actually get it.
	_question = _label(40, Color.WHITE)
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_question)

	_hint = _label(13, COL_HINT)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_hint)

	_feedback = _label(14, COL_GOOD)
	_feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_feedback)

	_choices_box = GridContainer.new()
	_choices_box.columns = 2
	_choices_box.add_theme_constant_override("h_separation", int(CHOICE_GAP))
	_choices_box.add_theme_constant_override("v_separation", 10)
	vbox.add_child(_choices_box)

	_continue_btn = Button.new()
	_continue_btn.text = "Continue"
	_continue_btn.custom_minimum_size = Vector2(0, 32)
	_continue_btn.add_theme_stylebox_override("normal", _button_style(COL_CORRECT, COL_CORRECT))
	_continue_btn.add_theme_stylebox_override("hover", _button_style(COL_CORRECT.lightened(0.1), COL_BORDER))
	_continue_btn.pressed.connect(_on_continue)
	vbox.add_child(_continue_btn)
	_apply_metrics()


## Reset to the rung this canvas starts at, then let the card in hand push it
## further. Called on build and whenever the UI scale changes the canvas.
func _apply_metrics() -> void:
	if _panel == null or _question == null or _vbox == null or _margin == null:
		return
	_set_density(_base_density(UiTheme.logical_size().y))
	_fit_frame()


## The rung a canvas this tall starts at, sized so an *ordinary* card fits with room
## to spare — _fit_frame only has to earn back the last few pixels on the long ones.
## The bands are set by the shipped UI scales, whose canvases are 450 (80%), 400
## (90%), 360 (100%) and 327 (110%). Bracketed numbers are the measured worst-case
## reveal slack over a 30-card sweep at that scale; before this, the same sweep was
## 43px *over* the canvas at 100% and 41px over at 110%.
static func _base_density(height: float) -> int:
	if height >= 430.0:
		return 0   # 450: the authored look, untouched  [77px]
	if height >= 380.0:
		return 1   # 400  [46px]
	if height >= 344.0:
		return 2   # 360, the default  [37px]
	if height >= 300.0:
		# The smallest canvas deliberately skips rung 3: starting a rung lower is what
		# keeps its headroom in the same range as every other scale, rather than
		# leaving it to just scrape in. A layout that only just fits is a layout the
		# next imported deck breaks. Rung 3 is still there for _fit_frame to land on.
		return 4   # [31px]
	return DENSITY.size() - 1


func _set_density(rung: int) -> void:
	_density = clampi(rung, 0, DENSITY.size() - 1)
	var d: Dictionary = DENSITY[_density]
	var canvas := UiTheme.logical_size()
	# A rung can ask for more width than the canvas has once the UI scale shrinks it.
	_panel_width = minf(float(d["width"]), canvas.x - 2.0 * CANVAS_INSET)
	_choice_width = (_inner_width() - CHOICE_GAP) * 0.5

	_panel.custom_minimum_size.x = _panel_width
	_question.add_theme_font_size_override("font_size", int(d["prompt"]))
	_vbox.add_theme_constant_override("separation", int(d["sep"]))
	_choices_box.add_theme_constant_override("v_separation", int(d["grid"]))
	_listen_btn.custom_minimum_size.y = float(d["head"])
	_choice_height = float(d["choice"])
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, int(d["pad"]))
	# Answers already on screen are re-measured against the new column width, then
	# floored. The floor only ever moves down; the measured text height is what
	# actually holds, so no rung can cut an answer short.
	for btn in _choice_buttons():
		btn.custom_minimum_size = Vector2(_choice_width, maxf(
			_choice_height, UiTheme.wrapped_height(btn, btn.text, _choice_width)))


## Width inside the panel's padding and border — what a full-width row wraps into.
func _inner_width() -> float:
	return _panel_width - 2.0 * (float(DENSITY[_density]["pad"]) + PANEL_BORDER)


## Last resort, run once the real card is in the panel. Roughly one eligible card
## in a hundred carries a prompt that wraps to two lines, and a hundred more carry
## an imported usage note that wraps the feedback line — no single fixed rung can
## be sized for those *and* for the ordinary card without making every card look
## cramped. So the ordinary card gets the roomy rung its canvas allows, and this
## steps down until the frame, gold border included, is inside the canvas.
##
## Only ever steps down, never back up: the panel must not grow its prompt between
## the question and the reveal of the same card.
func _fit_frame() -> void:
	if _panel == null:
		return
	var limit := UiTheme.logical_size().y
	while _density < DENSITY.size() - 1 and _content_height() > limit:
		_set_density(_density + 1)


## How tall the frame needs to be for what is in the panel right now.
##
## Measured from the fonts, deliberately, rather than read back off the containers:
## Godot settles container layout a frame later, and an autowrap control that has
## not been laid out yet measures its text against a zero width — one character per
## line. Asked in the same call that set the text, the PanelContainer reported 446px
## for a panel that settled to 214px one frame on. _fit_frame believed it and
## dropped every card to the tightest rung. Everything summed here is either font
## maths or a leaf control's own minimum, and neither needs a layout pass to be true.
func _content_height() -> float:
	var d: Dictionary = DENSITY[_density]
	var edge := float(d["pad"]) + PANEL_BORDER
	var inner := _inner_width()

	var rows: Array[float] = []
	rows.append(maxf(_heading.get_combined_minimum_size().y,
		_listen_btn.get_combined_minimum_size().y if _listen_btn.visible else 0.0))
	for wrapping in [_furigana, _question, _feedback]:
		if wrapping.visible:
			rows.append(UiTheme.wrapped_height(wrapping, wrapping.text, inner))
	if _hint.visible:
		rows.append(_hint.get_combined_minimum_size().y)   # one line: never wraps
	rows.append(_grid_height(float(d["grid"])))
	if _continue_btn.visible:
		rows.append(_continue_btn.get_combined_minimum_size().y)

	var total := 2.0 * edge + float(d["sep"]) * float(rows.size() - 1)
	for row in rows:
		total += row
	return total


## Two columns, so each answer row is as tall as the taller of its two buttons.
func _grid_height(gap: float) -> float:
	var heights: Array[float] = []
	var row := 0.0
	var filled := 0
	for btn in _choice_buttons():
		row = maxf(row, btn.custom_minimum_size.y)
		filled += 1
		if filled % _choices_box.columns == 0:
			heights.append(row)
			row = 0.0
	if row > 0.0:
		heights.append(row)
	var total := gap * maxf(0.0, float(heights.size() - 1))
	for height in heights:
		total += height
	return total


## The answers currently in the grid. Skips anything already freed: _render frees
## the previous card's buttons, and a freed child is still listed for the rest of
## the frame, which would double-count the grid.
func _choice_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for child in _choices_box.get_children():
		var btn := child as Button
		if btn != null and not btn.is_queued_for_deletion():
			out.append(btn)
	return out


func _on_listen_pressed() -> void:
	if _current.is_empty():
		return
	var card: Dictionary = _current.get("card", {})
	Audio.play_pronunciation(String(card.get("id", "")))


## Set a text row, and take it out of the layout when it has nothing to say.
##
## A blank Label still claims a full line of its font plus a row gap — 30px in the
## reveal state, in a panel that was overflowing its canvas by 43. The hint row is
## empty for most cards and the feedback row for the whole question state, so this
## is the cheapest height in the panel: nothing visible changes.
func _set_line(label: Label, text: String) -> void:
	label.text = text
	label.visible = not text.strip_edges().is_empty()


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_PANEL
	s.set_corner_radius_all(16)
	s.set_border_width_all(3)
	s.border_color = COL_BORDER
	return s


func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(10)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _compact_button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := _button_style(bg, border)
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s
