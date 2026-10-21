## The skill games: aiming an arrow at a target (archery contests and every arrow move in battle)
## and timing a blow on a swinging meter (Little John's sweep, Will's three-cut flourish).
## The rules live in core/archery.gd and core/timing.gd; this screen draws them and passes taps in.
## Set up with one of the start_* calls before adding to the tree; emits finished(round) when done.
extends Control

signal finished(round)

const Archery = preload("res://core/archery.gd")
const Timing = preload("res://core/timing.gd")
const Style = preload("res://scenes/ui/style.gd")
const TipCard = preload("res://scenes/ui/tip_card.gd")

## Target ring colours from the outside in: white, black, blue, red, gold, two rings each.
const RINGS := ["f0ece0", "f0ece0", "2a2a2a", "2a2a2a", "3a7ad0", "3a7ad0", "d04030", "d04030", "f0c030", "f0c030"]
const PAUSE := 0.8            # seconds to show where an arrow landed or how a blow went
const MIN_GAP := 0.15         # the shortest wait between fixing the aim and loosing the arrow

var round                     # an Archery or a Timing
var mode := "aim"             # "aim", "swing" or "rhythm"
var title := ""
var archer_name := "Robin"
var archer_sprite := "robin"
var full_screen := false      # contests take the whole screen; battle moves overlay the field
var t := 0.0
var _paused := 0.0
var _flash := ""              # the last tap's verdict, shown for a moment
var _over := false
var _tip_open := false        # the clock waits while a tutorial tip is on screen

var _board: Control           # where the target or the meter is drawn
var _late := false            # this tap was forced because time ran out
var _title_label: Label
var _hint_label: Label
var _score_label: Label
var _continue: Button


## A contest: three arrows against a rival, on the whole screen.
func start_contest(r, who: String, sprite: String, heading: String) -> void:
	round = r
	mode = "aim"
	archer_name = who
	archer_sprite = sprite
	title = heading
	full_screen = true


## One move in battle, drawn over the field. kind is the ability's "minigame".
func start_move(seed_value: int, kind: String, ability: Dictionary, who: String, sprite: String) -> void:
	mode = kind
	archer_name = who
	archer_sprite = sprite
	title = ability["name"]
	match kind:
		"aim":
			round = Archery.new(seed_value, 1)
		"rhythm":
			round = Timing.new(seed_value, int(ability.get("hits", 3)), 1.6)
		_:
			round = Timing.new(seed_value, 1, 1.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var h := Style.screen_height(self)
	var shade := ColorRect.new()
	shade.color = Color("1a140e") if full_screen else Color(0.06, 0.04, 0.03, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	if full_screen:
		var art := TextureRect.new()
		art.texture = preload("res://assets/backdrops/archery_contest.png")
		art.size = Vector2(360, 440)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.modulate = Color(0.55, 0.55, 0.55)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(art)
		add_child(Style.panel(Vector2(0, h - 170), Vector2(360, 170)))
	_title_label = _label(Vector2(8, 8), Vector2(344, Style.lines(1)), Color("f0d070"))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_board = Control.new()
	_board.position = Vector2(0, 40)
	_board.size = Vector2(360, 300)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	add_child(_board)
	var sprite := TextureRect.new()
	# (The battle screen preloads this one, so its sprite lookup is repeated here rather than shared.)
	var path := "res://assets/sprites/%s.png" % ("merry_man" if archer_sprite.begins_with("merry_man") else archer_sprite)
	sprite.texture = load(path) if ResourceLoader.exists(path) else null
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.size = Vector2(64, 64)
	sprite.position = Vector2(8, 280) if mode == "aim" else Vector2(148, 90)
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sprite)
	var below: float = h - 160 if full_screen else 360
	_hint_label = _label(Vector2(8, below), Vector2(344, Style.lines(2)), Style.TEXT)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label = _label(Vector2(8, below + 44), Vector2(344, Style.lines(2)), Color("e0d4ac"))
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_continue = Button.new()
	_continue.text = "Continue"
	_continue.position = Vector2(80, below + 96)
	_continue.size = Vector2(200, 40)
	_continue.visible = false
	_continue.pressed.connect(func(): finished.emit(round))
	add_child(_continue)
	_title_label.text = title
	_refresh_text()
	var card = TipCard.show_once(self, mode)
	if card:
		_tip_open = true
		card.closed.connect(func():
			_tip_open = false
			t = 0.0)


func _label(pos: Vector2, sz: Vector2, colour: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", colour)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _process(delta: float) -> void:
	if _over or _tip_open:
		return
	if _paused > 0.0:
		_paused -= delta
		if _paused <= 0.0:
			_flash = ""
			if round.done():
				_finish()
			_refresh_text()
	else:
		t += delta
		if t >= round.WINDOW:
			_late = true
			tap()
	_board.queue_redraw()


## A finger tap arrives as a mouse click (the project turns touches into clicks), so only clicks
## count. Listening for the touch as well made every tap count twice: the second one loosed the
## arrow the instant the aim was fixed, wherever the sight happened to start.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tap()
		accept_event()


## The player's tap: fixes the aim, looses an arrow, or judges a blow.
func tap() -> void:
	if _over or _paused > 0.0:
		return
	if mode == "aim":
		if round.locked_x != null and t < MIN_GAP:
			return    # a double tap: the sight has only just been fixed
		var s: int = round.tap(t)
		t = 0.0
		if s >= 0:
			_flash = "Gold! %d" % s if s >= 9 else ("%d points" % s if s > 0 else "Missed!")
			_paused = PAUSE
		if _late:
			_flash = ("Too slow! " + _flash).strip_edges()
			_paused = PAUSE
	else:
		var q: float = round.tap(t)
		t = 0.0
		_flash = "Perfect!" if q >= 0.9 else ("Good" if q >= 0.6 else ("Weak" if q > 0.0 else "Wild swing!"))
		if _late:
			_flash = "Too slow! " + _flash
		_paused = PAUSE * (0.5 if mode == "rhythm" and not round.done() else 1.0)
	_late = false
	_refresh_text()


func _finish() -> void:
	if round is Archery and round.rival_name != "":
		_over = true
		_continue.visible = true
		_refresh_text()
		return
	_over = true
	finished.emit(round)


## What this round's taps add up to, for the battle: one value from 0 to 1 per hit.
static func skill_of(r) -> Array:
	if r is Archery:
		return r.scores.map(func(s): return s / 10.0)
	return r.qualities.duplicate()


func _refresh_text() -> void:
	if _hint_label == null:
		return    # not on screen yet (tests tap before the screen is built)
	if mode == "aim":
		var w: float = round.wind
		var arrows := ""
		for i in int(ceil(absf(w) * 3)):
			arrows += "<" if w < 0 else ">"
		var wind_text := "Wind: calm" if absf(w) < 0.05 else "Wind: %s %s" % [arrows, "strong" if absf(w) > 0.6 else "light"]
		if _over:
			_hint_label.text = "%s wins!" % archer_name if round.won() else "%s wins this time." % round.rival_name
		elif _flash != "":
			_hint_label.text = _flash
		else:
			_hint_label.text = "%s\n%s" % [wind_text, "Tap to fix your aim" if round.locked_x == null else "Tap to shoot!"]
		if round.rival_name != "":
			var n: int = mini(round.shots.size() + (0 if round.done() else 1), round.arrows)
			_score_label.text = "Arrow %d of %d\n%s %d   %s %d" % [n, round.arrows, archer_name, round.total(), round.rival_name, round.rival_so_far()]
		else:
			_score_label.text = ""
	else:
		_hint_label.text = _flash if _flash != "" else "Tap when the marker is in the gold!"
		_score_label.text = "Cut %d of %d" % [mini(round.qualities.size() + 1, round.taps), round.taps] if round.taps > 1 else ""


# --- Drawing -------------------------------------------------------------------

func _draw_board() -> void:
	if mode == "aim":
		_draw_target()
	else:
		_draw_meter()
	# The time left for this tap, draining away under the board.
	if not _over and _paused <= 0.0:
		var left: float = clampf(1.0 - t / round.WINDOW, 0.0, 1.0)
		var x0 := 84.0 if mode == "aim" else 30.0    # clear of the archer in the corner
		_board.draw_rect(Rect2(x0, 288, 330 - x0, 8), Color("2a1a10"))
		_board.draw_rect(Rect2(x0, 288, (330 - x0) * left, 8), Color("5ac04a") if left > 0.35 else Color("d04a3a"))


func _draw_target() -> void:
	var c := Vector2(180, 130)
	var r := 110.0
	for i in RINGS.size():
		var rad := r * (1.0 - i / 10.0)
		_board.draw_circle(c, rad, Color(RINGS[i]))
		_board.draw_arc(c, rad, 0, TAU, 48, Color(0, 0, 0, 0.35), 1.0)
	for s in round.shots:
		_draw_arrow(c + s * r)
	# The wind, as a streak above the target: longer for a stronger wind.
	var w: float = round.wind
	if absf(w) >= 0.05 and not _over:
		var half := 10.0 + 50.0 * absf(w)
		var dir := signf(w)
		var y := 8.0
		var tip := Vector2(180 + half * dir, y)
		_board.draw_line(Vector2(180 - half * dir, y), tip, Color("e0f0ff"), 3.0)
		_board.draw_line(tip, tip + Vector2(-8 * dir, -6), Color("e0f0ff"), 3.0)
		_board.draw_line(tip, tip + Vector2(-8 * dir, 6), Color("e0f0ff"), 3.0)
	if _over or (_paused > 0.0 and round.done() and round.rival_name == ""):
		return
	if _paused > 0.0:
		return
	var at: Vector2 = c + round.aim_at(t) * r
	var ink := Color("40e0ff")
	if round.locked_x != null:
		_board.draw_line(Vector2(at.x, c.y - r - 6), Vector2(at.x, c.y + r + 6), Color(ink, 0.5), 2.0)
	_board.draw_arc(at, 9, 0, TAU, 20, ink, 2.0)
	_board.draw_line(at - Vector2(14, 0), at + Vector2(14, 0), ink, 2.0)
	_board.draw_line(at - Vector2(0, 14), at + Vector2(0, 14), ink, 2.0)


func _draw_arrow(p: Vector2) -> void:
	_board.draw_line(p + Vector2(-6, -6), p, Color("6a4a2c"), 3.0)
	_board.draw_line(p + Vector2(-9, -9), p + Vector2(-6, -6), Color("f0ece0"), 4.0)
	_board.draw_circle(p, 2.5, Color("2a1a10"))


func _draw_meter() -> void:
	var left := 30.0
	var width := 300.0
	var y := 200.0
	# Red at the ends, through yellow and green to a thin gold strip in the middle.
	var steps := 60
	for i in steps:
		var p := (i + 0.5) / steps
		var q := Timing.quality_at(p)
		var col := Color("c04030").lerp(Color("e0c040"), clampf(q * 2.0, 0, 1)).lerp(Color("5ac04a"), clampf(q * 2.0 - 1.0, 0, 1))
		if q >= 0.9:
			col = Color("f0d070")
		_board.draw_rect(Rect2(left + width * i / steps, y, width / steps + 1, 26), col)
	_board.draw_rect(Rect2(left, y, width, 26), Color("2a1a10"), false, 2.0)
	if not (_paused > 0.0 and round.done()):
		var x: float = left + width * round.pos(t)
		_board.draw_rect(Rect2(x - 2, y - 10, 4, 46), Color.WHITE)
		_board.draw_rect(Rect2(x - 2, y - 10, 4, 46), Color("2a1a10"), false, 1.0)
	# Pips for the cuts made so far, coloured by how well they went.
	for i in round.qualities.size():
		var q: float = round.qualities[i]
		_board.draw_circle(Vector2(180 + (i - (round.taps - 1) / 2.0) * 28, y + 50), 8, Color("f0d070") if q >= 0.9 else (Color("5ac04a") if q >= 0.6 else Color("c04030")))
