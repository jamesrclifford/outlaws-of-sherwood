## Battle screen: units stand on the location's painted backdrop, controls sit on a wooden panel below.
## Heroes stand on the left (back row outermost), enemies on the right.
extends Control

## Emitted when a battle set up with run_battle() ends and the player taps Continue.
signal finished(battle)

const GameData = preload("res://core/game_data.gd")
const Style = preload("res://scenes/ui/style.gd")

const PARTY := ["robin", "little_john", "will", "tuck"]
const COLUMN_X := {"heroes": {"back": 8, "front": 92}, "enemies": {"front": 188, "back": 272}}
const DEFAULT_BACKDROP := "sherwood_edge"
const SHADOW := preload("res://assets/ui/shadow.png")
const RING_TURN := preload("res://assets/ui/ring_turn.png")
const RING_TARGET := preload("res://assets/ui/ring_target.png")

var db
var battle
var encounter_ids: Array
var encounter_index := 0
var fight_number := 0
var selected_ability := ""
var unit_buttons := {}
var backdrop_id := ""
var _external := false

var backdrop: TextureRect
var timeline_label: Label
var field: Control
var log_label: Label
var actions_box: HBoxContainer
var commands_box: HBoxContainer


func _ready() -> void:
	if db == null:
		db = GameData.new()
	encounter_ids = db.encounters.keys()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	_build_layout()
	if battle == null:
		_start_battle()
	else:
		_begin()


## Fights a battle built elsewhere (e.g. by a mission). Call before adding to the tree.
## location picks the backdrop (an id from data/locations.json).
func run_battle(game_data, b, title: String, location := "") -> void:
	db = game_data
	battle = b
	backdrop_id = location
	_external = true
	battle.battle_log.append(title)


func _begin() -> void:
	backdrop.texture = backdrop_for(backdrop_id)
	battle.event.connect(func(_t): _refresh_log())
	_rebuild_units()
	_advance()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# The backdrop is 180x220 pixel art shown at 2x behind the turn order and the field.
	backdrop = TextureRect.new()
	backdrop.position = Vector2.ZERO
	backdrop.size = Vector2(360, 440)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.06, 0.04, 0.6)
	shade.position = Vector2.ZERO
	shade.size = Vector2(360, 52)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	add_child(Style.panel(Vector2(0, 436), Vector2(360, 204)))

	timeline_label = _label(Vector2(8, 6), Vector2(344, 40))
	field = Control.new()
	field.position = Vector2(0, 56)
	field.size = Vector2(360, 380)
	add_child(field)
	log_label = _label(Vector2(10, 442), Vector2(340, 110))
	log_label.add_theme_color_override("font_color", Color("e0d4ac"))

	actions_box = HBoxContainer.new()
	actions_box.position = Vector2(8, 556)
	actions_box.size = Vector2(344, 36)
	add_child(actions_box)
	commands_box = HBoxContainer.new()
	commands_box.position = Vector2(8, 598)
	commands_box.size = Vector2(344, 36)
	add_child(commands_box)


func _label(pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 10)
	add_child(l)
	return l


func _start_battle() -> void:
	var enc: String = encounter_ids[encounter_index % encounter_ids.size()]
	fight_number += 1
	battle = db.make_battle(PARTY, enc, Time.get_ticks_usec() + fight_number)
	backdrop_id = db.encounters[enc].get("location", "")
	battle.battle_log.append(db.encounters[enc]["name"])
	_begin()


func _rebuild_units() -> void:
	for c in field.get_children():
		c.queue_free()
	unit_buttons.clear()
	for side in ["heroes", "enemies"]:
		var counts := {"front": 0, "back": 0}
		var side_units: Array = battle.units.filter(func(x): return x.side == side)
		var biggest_column: int = max(side_units.filter(func(x): return x.row == "front").size(), side_units.filter(func(x): return x.row == "back").size())
		var step: float = min(92.0, 368.0 / max(1, biggest_column))
		# Small groups stand in the middle of the ground rather than up against the horizon.
		var top: float = 4 + (368.0 - step * biggest_column) / 2
		for u in side_units:
			var card_h: float = min(88.0, step - 4)
			var b := Button.new()
			Style.flat(b)
			b.size = Vector2(80, card_h)
			b.position = Vector2(COLUMN_X[side][u.row], top + counts[u.row] * step)
			counts[u.row] += 1
			b.pressed.connect(_on_unit_pressed.bind(u))
			# Sprites are 32x32 drawn facing right; shown at 2x, or 1x when a column is crowded.
			var zoom: int = 2 if card_h >= 84.0 else 1
			# A shadow under the feet, swapped for a coloured ring on the unit whose turn it is or a target.
			var ring := TextureRect.new()
			ring.name = "Ring"
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ring.stretch_mode = TextureRect.STRETCH_SCALE
			ring.size = Vector2(28 * zoom, 8 * zoom)
			ring.position = Vector2((80 - ring.size.x) / 2, 32 * zoom - ring.size.y + 2 * zoom)
			ring.texture = SHADOW
			b.add_child(ring)
			var art := TextureRect.new()
			art.texture = sprite_for(u)
			art.mouse_filter = Control.MOUSE_FILTER_IGNORE
			art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			art.stretch_mode = TextureRect.STRETCH_SCALE
			art.size = Vector2(32 * zoom, 32 * zoom)
			art.position = Vector2((80 - 32 * zoom) / 2, 0)
			art.flip_h = side == "enemies"
			art.name = "Art"
			b.add_child(art)
			var plate := ColorRect.new()
			plate.color = Color(0.08, 0.06, 0.04, 0.72)
			plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
			plate.position = Vector2(2, 32 * zoom + 1)
			plate.size = Vector2(76, card_h - 32 * zoom - 1)
			b.add_child(plate)
			var bar := ColorRect.new()
			bar.name = "Bar"
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.position = Vector2(6, 32 * zoom + 2)
			bar.size = Vector2(68, 2)
			b.add_child(bar)
			var info := Label.new()
			info.name = "Info"
			info.mouse_filter = Control.MOUSE_FILTER_IGNORE
			info.add_theme_font_size_override("font_size", 8)
			info.add_theme_constant_override("line_spacing", -3)
			info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			info.position = Vector2(0, 32 * zoom - 1)
			info.size = Vector2(80, card_h - 32 * zoom + 1)
			b.add_child(info)
			field.add_child(b)
			unit_buttons[u] = b


## Backdrop art for a location id, falling back to the forest when there is none.
static func backdrop_for(location: String) -> Texture2D:
	var path := "res://assets/backdrops/%s.png" % location
	if location == "" or not ResourceLoader.exists(path):
		path = "res://assets/backdrops/%s.png" % DEFAULT_BACKDROP
	return load(path)


## The unit's sprite: heroes and enemies by id, hired Merry Men share one look.
static func sprite_for(u) -> Texture2D:
	var key: String = "merry_man" if u.id.begins_with("merry_man") else u.id
	var path := "res://assets/sprites/%s.png" % key
	return load(path) if ResourceLoader.exists(path) else null


func _refresh() -> void:
	# Re-layout if units were summoned or changed rows.
	var needs_rebuild: bool = battle.units.size() != unit_buttons.size()
	for u in unit_buttons:
		var col: int = COLUMN_X[u.side][u.row]
		if int(unit_buttons[u].position.x) != col:
			needs_rebuild = true
	if needs_rebuild:
		_rebuild_units()

	var cur = battle.current()
	var targets: Array = []
	if cur != null and selected_ability != "":
		targets = battle.legal_targets(cur, selected_ability)
	for u in unit_buttons:
		var b: Button = unit_buttons[u]
		var marks := ""
		for s in u.statuses:
			marks += s.substr(0, 3) + " "
		var state := "OUT" if u.is_down() else ("FLED" if u.fled else "%d/%d" % [u.hp, u.max_hp])
		var info: Label = b.get_node("Info")
		info.text = "%s\n%s %s" % [u.name, state, marks.strip_edges()]
		var bar: ColorRect = b.get_node("Bar")
		var frac: float = clamp(float(u.hp) / max(1, u.max_hp), 0.0, 1.0)
		bar.size.x = 68 * frac
		bar.color = Color("6ac04a") if frac > 0.5 else (Color("e0b040") if frac > 0.25 else Color("d04a3a"))
		var ring: TextureRect = b.get_node("Ring")
		ring.texture = RING_TURN if u == cur else (RING_TARGET if targets.has(u) else SHADOW)
		b.modulate = Color(1, 1, 1, 0.4) if not u.is_active() else Color.WHITE
		var art: TextureRect = b.get_node("Art")
		art.modulate = Color("b8e8ff") if targets.has(u) and u != cur else Color.WHITE
	var names: Array = battle.upcoming().map(func(x): return x.name.split(" ")[0])
	timeline_label.text = "Round %d   Turn order: %s" % [battle.round_number, " > ".join(names)]
	_refresh_log()
	_refresh_actions()


func _refresh_log() -> void:
	var lines: Array = battle.battle_log.slice(max(0, battle.battle_log.size() - 8))
	log_label.text = "\n".join(lines)


func _refresh_actions() -> void:
	for c in actions_box.get_children() + commands_box.get_children():
		c.queue_free()
	if battle.is_over() and _external:
		_add_button(commands_box, "Continue", func(): finished.emit(battle))
		return
	if battle.is_over():
		var label := "Next fight" if battle.result == "victory" else "Try again"
		_add_button(commands_box, label, func():
			if battle.result == "victory":
				encounter_index += 1
			_start_battle())
		return
	var cur = battle.current()
	if cur == null or cur.side != "heroes":
		return
	for a in cur.available_abilities():
		var ab: Dictionary = db.abilities[a]
		var btn := _add_button(actions_box, "%s (%d)" % [ab["name"], ab["ap"]], _on_ability_pressed.bind(a))
		btn.disabled = not battle.usable_abilities(cur).has(a)
		if a == selected_ability:
			btn.modulate = Color("9fe0ff")
	_add_button(commands_box, "End turn", _end_hero_turn)
	_add_button(commands_box, "Swap row", func():
		battle.swap_row(cur)
		_after_hero_action())
	_add_button(commands_box, "Retreat", func():
		battle.retreat(cur)
		_after_hero_action())
	timeline_label.text += "\n%s: %d AP" % [cur.name, cur.ap]


func _add_button(box: HBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 9)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	box.add_child(b)
	return b


func _on_ability_pressed(ability_id: String) -> void:
	var cur = battle.current()
	var target_type: String = db.abilities[ability_id]["target"]
	if target_type == "self" or target_type == "all_allies":
		battle.perform(cur, ability_id, cur)
		_after_hero_action()
		return
	selected_ability = ability_id
	_refresh()


func _on_unit_pressed(u) -> void:
	var cur = battle.current()
	if cur == null or cur.side != "heroes" or battle.is_over():
		return
	if selected_ability == "" and u.has_status("netted"):
		battle.free_ally(cur, u)
	elif selected_ability != "":
		battle.perform(cur, selected_ability, u)
	_after_hero_action()


func _after_hero_action() -> void:
	selected_ability = ""
	var cur = battle.current()
	if battle.is_over():
		_refresh()
	elif cur.ap <= 0:
		_end_hero_turn()
	else:
		_refresh()


func _end_hero_turn() -> void:
	selected_ability = ""
	battle.end_turn()
	_advance()


## Runs enemy turns (with a short pause each) until a hero can act or the fight ends.
func _advance() -> void:
	while not battle.is_over():
		var u = battle.next_turn()
		if u == null:
			break
		if u.side == "heroes":
			break
		_refresh()
		await get_tree().create_timer(0.5).timeout
		battle.run_ai_turn()
	_refresh()
