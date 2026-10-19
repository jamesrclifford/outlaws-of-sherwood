## Shared look for the screens: wooden buttons, dark panels and parchment plaques,
## all 9-slice frames drawn by tools/make_scenery.py.
extends RefCounted

const UI := "res://assets/ui/%s.png"
const TEXT := Color("f0e6cc")
## Body text size everywhere: the 8px pixel font at 2x, readable on a phone.
const BODY := 16
## Body lines sit this far apart; the first line is a little taller (see lines()).
const LINE := 18


## Height of a label that shows n lines of body text.
static func lines(n: int) -> float:
	return LINE * n + 4


## The screen's height: 640 or more, as the game is always 360 wide and fills the phone's height.
static func screen_height(c: Control) -> float:
	return maxf(640.0, c.get_viewport_rect().size.y)


static func frame(name: String, margin := 4) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(UI % name)
	sb.set_texture_margin_all(margin)
	sb.set_content_margin_all(margin)
	return sb


## Sets a wrapped label's text without spilling past the box it was laid out in (anything below it,
## like buttons, would cover the overflow). keep_end shows the newest lines of a log; otherwise the
## first lines show and the rest are dropped.
static func fit_text(l: Label, text: String, keep_end := false) -> void:
	if not l.has_meta("box_height"):
		l.set_meta("box_height", l.size.y)
	var box: float = l.get_meta("box_height")
	l.text = text
	l.lines_skipped = 0
	l.max_lines_visible = -1
	var step: float = l.get_line_height() + l.get_theme_constant("line_spacing")
	var fits := maxi(1, int((box + l.get_theme_constant("line_spacing")) / step))
	var lines := l.get_line_count()
	l.max_lines_visible = fits
	l.lines_skipped = maxi(0, lines - fits) if keep_end else 0
	l.size.y = box


## A theme for a whole screen; children pick it up automatically.
static func theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal", "Button", frame("button"))
	t.set_stylebox("hover", "Button", frame("button_hover"))
	t.set_stylebox("pressed", "Button", frame("button_pressed"))
	t.set_stylebox("disabled", "Button", frame("button_disabled"))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color("fff4d8"))
	t.set_color("font_pressed_color", "Button", Color("d8c8a0"))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("8a7a60"))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	# Text is 16 (the 8px pixel font at 2x); lines of 22 drawn 18 apart, so descenders just clear.
	t.default_font_size = BODY
	t.set_constant("line_spacing", "Label", -4)
	t.set_stylebox("panel", "Panel", frame("panel"))
	return t


## A dark wooden panel covering the given rectangle.
static func panel(pos: Vector2, sz: Vector2) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A button with no frame, for things that are already pictures (units, places on the map).
static func flat(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
