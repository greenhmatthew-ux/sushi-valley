class_name UiTheme
extends RefCounted
## The one source of truth for UI colour, spacing, and type — the "shared tokens" the
## UI_UX_GUIDE calls Next/Essential.
##
## Values are the guide's token table verbatim (section 16), written as hex so they can be
## diffed against the doc without decoding floats. Before this existed, seven panels each
## declared their own COL_* constants — 60 in total — and they had already drifted: the modal
## dim was 60% instead of 66%, and the danger red was #D97366 rather than #FF9B9B. One
## definition means a palette change lands everywhere at once.
##
## Also holds the small builders (panel/button/label) every panel was hand-rolling, so chrome
## stays consistent by default instead of by discipline.

# --- surfaces -------------------------------------------------------------
const SURFACE_BACKDROP := Color("05080c", 0.66)   ## modal dim
const SURFACE_BASE := Color("141b24")             ## panels
const SURFACE_RAISED := Color("1b2530")           ## cards / rows
const SURFACE_DEEP := Color("0e151d")             ## inset areas

# --- borders --------------------------------------------------------------
const BORDER_SUBTLE := Color("2a3744")
const BORDER_STRONG := Color("3c5168")

# --- text -----------------------------------------------------------------
const TEXT_PRIMARY := Color("eef1f5")
const TEXT_MUTED := Color("9fb0c3")

# --- accents and state ----------------------------------------------------
const ACCENT_GOLD := Color("ffd27d")              ## focus / headings
const STATE_SUCCESS := Color("9be7a3")
const STATE_INFO := Color("9fd6ff")
const STATE_DANGER := Color("ff9b9b")
const LEARNING_VIOLET := Color("c27ba0")          ## learning identity

# Derived fills, written out rather than computed: `const` cannot hold a call like
# `STATE_SUCCESS.darkened(0.45)`. These are the answer-feedback and disabled tones — the
# state colours are text-weight, too light to sit behind white button labels.
const FILL_CORRECT := Color("2e7d4f")             ## correct-answer button
const FILL_WRONG := Color("9e3b3b")               ## wrong-answer button
const TEXT_DISABLED := Color("6b7885")            ## unavailable / locked rows

# --- spacing: the guide's 8px unit ---------------------------------------
const UNIT := 8
const PAD_PANEL := UNIT * 2      # 16
const GAP_ROW := UNIT            # 8

# --- type scale (minimums at the 800x600 logical size) -------------------
## The type scale. It was 12/14/16/22 while the panels actually used ELEVEN different sizes
## (8,9,10,11,12,13,14,15,16,20,22) via 85 hardcoded overrides -- six of them not in the scale
## at all. A scale nothing conforms to is not a scale, and it is why type in this UI does not
## respond to the UI-scale setting the way panels do.
##
## HEADING and SMALL are added because both were genuinely in use and had nowhere to go.
## Everything else is mapped to its nearest tier, preferring the smaller one on a tie so
## adoption shrinks text rather than growing it into a panel it used to fit.
const FONT_TITLE := 22
const FONT_HEADING := 20
const FONT_SECTION := 16
const FONT_BODY := 14
const FONT_META := 12
const FONT_SMALL := 10
## Japanese needs to be bigger than body text to stay legible at 16px-art scale.
const FONT_JAPANESE := 30

## Answer text is content, not layout: a single kana rune and a nine-word English
## phrase both have to be fully readable in the same button. Rather than clipping
## the long one — which hides the very thing the player is being asked to choose —
## step the size down as the text grows, so it wraps into the same box instead of
## being cut off. Only the size changes; nothing is ever truncated.
## Height `control` needs to show `text` wrapped into `width`, including whatever
## padding its own stylebox adds.
##
## A wrapped Label or Button reports a *single* line as its minimum size, because
## it cannot know the width a container will finally give it. The container then
## hands it one line of space and everything after the first line is cut off. So
## anything that wraps has to measure itself up front and ask for the room.
static func wrapped_height(control: Control, text: String, width: float) -> float:
	var font := control.get_theme_font("font")
	if font == null or text.strip_edges().is_empty():
		return 0.0
	var pad_x := 0.0
	var pad_y := 0.0
	var box := control.get_theme_stylebox("normal")
	if box != null:
		pad_x = box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT)
		pad_y = box.get_margin(SIDE_TOP) + box.get_margin(SIDE_BOTTOM)
	var size := control.get_theme_font_size("font_size")
	var inner := maxf(width - pad_x, 1.0)
	return font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, inner, size).y + pad_y


static func fit_font_size(text: String, base: int) -> int:
	var length := text.strip_edges().length()
	if length <= 4:
		return base
	if length <= 8:
		return maxi(FONT_SECTION, int(round(base * 0.78)))
	if length <= 14:
		return maxi(FONT_BODY, int(round(base * 0.62)))
	if length <= 24:
		return maxi(FONT_META, int(round(base * 0.5)))
	return maxi(FONT_META - 1, int(round(base * 0.42)))

# --- UI scale (UI_UX_GUIDE section 15) ------------------------------------
##
## The game renders UI into a fixed 640x360 logical viewport, so "bigger UI"
## cannot mean bigger panels — it means bigger text inside the same panels, and
## therefore a smaller logical canvas to lay them out in.
##
## That is what these two do together: the CanvasLayer is scaled up, and its
## root Control is shrunk by the same factor. A panel anchored at 8%-92% of the
## root keeps the exact screen footprint it had at 100%, while its absolute font
## sizes now cover more of it. Scaling the layer (rather than every font size)
## also means padding, borders, and min-sizes scale in lockstep, so nothing can
## clip from a font growing inside a box that did not.
##
## The world is deliberately untouched: Settings.zoom stays on integer-friendly
## steps for the 16px art, per the project art rules.

## The logical UI canvas at the current scale — what a root Control must be
## sized to so that, once its layer is scaled, it covers exactly the screen.
static func logical_size() -> Vector2:
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 640)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 360)))
	return (base / maxf(Settings.ui_scale, 0.1)).floor()


## Fit one UI layer to the player's scale. Call right after building `root`, and
## again whenever `Bus.ui_scale_changed` fires. Anchors are dropped in favour of
## an explicit size because full-rect anchors resolve against the untouched
## viewport rect, which is exactly the thing that must no longer be the canvas.
static func fit_layer(layer: CanvasLayer, root: Control) -> void:
	if layer == null or root == null:
		return
	var scale := maxf(Settings.ui_scale, 0.1)
	layer.scale = Vector2(scale, scale)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.size = logical_size()


## Keep a full-screen backdrop, but give the actual modal breathing room around
## it. UI scale changes content density without changing anchor percentages, so
## shells need an authored inset of their own or they dominate the whole screen
## even at the compact setting.
static func fit_modal_shell(shell: Control, inset_x: float = 0.12,
		inset_y: float = 0.10) -> void:
	if shell == null:
		return
	shell.anchor_left = inset_x
	shell.anchor_right = 1.0 - inset_x
	shell.anchor_top = inset_y
	shell.anchor_bottom = 1.0 - inset_y


# --- motion (seconds) -----------------------------------------------------
const MOTION_PRESS := 0.07
const MOTION_FOCUS := 0.08
const MOTION_PANEL := 0.14
const MOTION_TOAST := 0.18


## A panel frame: integer-aligned, 2px inner border, restrained radius.
static func panel_style(border: Color = ACCENT_GOLD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE_BASE
	s.set_corner_radius_all(12)
	s.set_border_width_all(2)
	s.border_color = border
	return s


## An inset card/row inside a panel.
static func card_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE_RAISED
	s.set_corner_radius_all(8)
	s.set_border_width_all(1)
	s.border_color = BORDER_SUBTLE
	return s


static func button_style(bg: Color = SURFACE_RAISED, border: Color = BORDER_STRONG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(8)
	s.set_border_width_all(2)
	s.border_color = border
	s.content_margin_left = UNIT + 2
	s.content_margin_right = UNIT + 2
	s.content_margin_top = UNIT
	s.content_margin_bottom = UNIT
	return s


static func label(text: String, size: int = FONT_BODY, color: Color = TEXT_PRIMARY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


## Full-screen dim behind a modal.
static func backdrop() -> ColorRect:
	var d := ColorRect.new()
	d.color = SURFACE_BACKDROP
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	return d


## Outline so focus is readable without relying on colour alone (guide: "Focus uses
## outline/cursor shape as well as color").
static func focus_style() -> StyleBoxFlat:
	var s := button_style(SURFACE_RAISED.lightened(0.06), ACCENT_GOLD)
	s.set_border_width_all(3)
	return s
