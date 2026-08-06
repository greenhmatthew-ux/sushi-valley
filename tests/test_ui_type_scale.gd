extends SceneTree
## Guard: UI text sizes come from the scale, not from a number typed at the call site.
##
##   godot --headless --path . --script res://tests/test_ui_type_scale.gd
##
## UiTheme declared a four-step type scale (12/14/16/22) while the panels actually used
## ELEVEN different sizes -- 8, 9, 10, 11, 12, 13, 14, 15, 16, 20, 22 -- through 85 hardcoded
## overrides, six of those sizes existing nowhere in the scale. A scale nothing conforms to
## is not a scale; it is a comment. It is also why type did not respond to the UI-scale
## setting the way panel geometry does.
##
## HEADING and SMALL were added for the two tiers genuinely in use, and everything else was
## mapped to its nearest tier, preferring the smaller on a tie so adoption could not grow
## text into a panel it used to fit.
##
## Reads the sources as text: this is a rule about how the UI is written, and instantiating
## every panel to ask it would test something else.

const UI_DIR := "res://src/ui"
## ui_theme defines the scale, so it is the one file allowed to name raw sizes.
const EXEMPT: Array[String] = ["ui_theme.gd"]

var failures: int = 0


func _initialize() -> void:
	_run()


func _run() -> void:
	var dir := DirAccess.open(UI_DIR)
	check_true("can read the UI source directory", dir != null)
	if dir == null:
		_finish()
		return

	var raw := RegEx.create_from_string(
		'add_theme_font_size_override\\(\\s*"font_size"\\s*,\\s*(\\d+)\\s*\\)')
	var offenders: Array[String] = []
	var scanned := 0
	var tokenised := 0
	for file in dir.get_files():
		if not file.ends_with(".gd") or EXEMPT.has(file):
			continue
		scanned += 1
		var text := FileAccess.get_file_as_string("%s/%s" % [UI_DIR, file])
		tokenised += text.count("UiTheme.FONT_")
		for m in raw.search_all(text):
			offenders.append("%s:%s" % [file, m.get_string(1)])

	check_true("scanned the UI surfaces (%d files, %d tokenised sizes)" % [scanned, tokenised],
		scanned > 10 and tokenised > 0)
	check_true("no panel hardcodes a font size (%s)"
		% ("none" if offenders.is_empty() else ", ".join(PackedStringArray(offenders))),
		offenders.is_empty())

	# The scale itself must stay ordered and gap-free enough to be worth conforming to.
	var theme := load("res://src/ui/ui_theme.gd")
	var steps := [theme.FONT_SMALL, theme.FONT_META, theme.FONT_BODY,
		theme.FONT_SECTION, theme.FONT_HEADING, theme.FONT_TITLE]
	var ascending := true
	for i in range(1, steps.size()):
		if int(steps[i]) <= int(steps[i - 1]):
			ascending = false
	check_true("the type scale is strictly ascending %s" % str(steps), ascending)
	_finish()


func check_true(label: String, condition: bool) -> void:
	if condition:
		print("  ok   %s" % label)
	else:
		failures += 1
		print("  FAIL %s" % label)


func _finish() -> void:
	if failures == 0:
		print("PASS — UI type comes from the scale.")
		quit(0)
	else:
		print("FAIL — %d check(s) failed." % failures)
		quit(1)
