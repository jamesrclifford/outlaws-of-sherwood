## Prototype battle screen. Placeholder pixel blocks stand in for sprites.
## Heroes stand on the left (back row outermost), enemies on the right.
extends Control

const GameData = preload("res://core/game_data.gd")

const PARTY := ["robin", "little_john", "will", "tuck"]
const COLUMN_X := {"heroes": {"back": 8, "front": 92}, "enemies": {"front": 188, "back": 272}}
const HERO_COLOR := Color("3f7d3a")
const ENEMY_COLOR := Color("8c2f2f")
const BOSS_COLOR := Color("4a2a5e")

var db
var battle
var encounter_ids: Array
var encounter_index := 0
var fight_number := 0
var selected_ability := ""
var unit_buttons := {}

var timeline_label: Label
var field: Control
var log_label: Label
var actions_box: HBoxContainer
var commands_box: HBoxContainer


func _ready() -> void:
	db = GameData.new()
	encounter_ids = db.encounters.keys()
	_build_layout()
	_start_battle()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1d2b1f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	timeline_label = _label(Vector2(8, 8), Vector2(344, 40))
	field = Control.new()
	field.position = Vector2(0, 56)
	field.size = Vector2(360, 380)
	add_child(field)
	log_label = _label(Vector2(8, 440), Vector2(344, 110))
	log_label.add_theme_color_override("font_color", Color("d8cfa8"))

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
	battle.event.connect(func(_t): _refresh_log())
	battle.battle_log.append(db.encounters[enc]["name"])
	_rebuild_units()
	_advance()


func _rebuild_units() -> void:
	for c in field.get_children():
		c.queue_free()
	unit_buttons.clear()
	for side in ["heroes", "enemies"]:
		var counts := {"front": 0, "back": 0}
		for u in battle.units.filter(func(x): return x.side == side):
			var b := Button.new()
			b.size = Vector2(80, 84)
			b.position = Vector2(COLUMN_X[side][u.row], 8 + counts[u.row] * 92)
			counts[u.row] += 1
			b.add_theme_font_size_override("font_size", 9)
			b.pressed.connect(_on_unit_pressed.bind(u))
			var block := ColorRect.new()
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.size = Vector2(32, 32)
			block.position = Vector2(24, 6)
			block.color = HERO_COLOR if side == "heroes" else (BOSS_COLOR if u.tags.has("boss") else ENEMY_COLOR)
			b.add_child(block)
			field.add_child(b)
			unit_buttons[u] = b


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
		b.text = "\n\n\n%s\n%s\n%s" % [u.name, state, marks]
		b.modulate = Color(1, 1, 1, 0.35) if not u.is_active() else Color.WHITE
		if u == cur:
			b.modulate = Color("ffe08a")
		elif targets.has(u):
			b.modulate = Color("9fe0ff")
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
