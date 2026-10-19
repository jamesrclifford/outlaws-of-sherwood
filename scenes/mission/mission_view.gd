## Prototype mission screen: the linear path of nodes, the party, and what to do at the current node.
extends Control

const GameData = preload("res://core/game_data.gd")
const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")

const PARTY := ["robin", "little_john", "will", "tuck"]
const NODE_ICONS := {"approach": "Go", "combat": "Fight", "choice": "?", "hazard": "Path", "objective": "Goal", "escape": "Home"}

## Set by the menu before the scene is shown.
var mission_type := "robbery"
var threat := 40

var db
var run
var title_label: Label
var path_box: HBoxContainer
var party_label: Label
var log_label: Label
var buttons: VBoxContainer
var bg: ColorRect


func _ready() -> void:
	db = GameData.new()
	var gen = MissionGen.new(db)
	var mission: Dictionary = gen.generate(mission_type, threat, int(Time.get_ticks_usec()), "", "little_john")
	run = MissionRun.new(db, mission, PARTY.map(func(h): return db.make_hero(h)))
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	bg.color = Color(db.locations[mission["location"]]["backdrop"]).darkened(0.45)
	_show_briefing()


func _build_layout() -> void:
	bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	title_label = _label(Vector2(8, 8), Vector2(344, 40), 12)
	path_box = HBoxContainer.new()
	path_box.position = Vector2(8, 56)
	path_box.size = Vector2(344, 48)
	add_child(path_box)
	party_label = _label(Vector2(8, 112), Vector2(344, 60), 10)
	log_label = _label(Vector2(8, 180), Vector2(344, 250), 10)
	log_label.add_theme_color_override("font_color", Color("d8cfa8"))
	buttons = VBoxContainer.new()
	buttons.position = Vector2(8, 440)
	buttons.size = Vector2(344, 190)
	add_child(buttons)


func _label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l


func _refresh() -> void:
	var m: Dictionary = run.mission
	title_label.text = "%s\n%s  (threat %d)" % [m["name"], m["location_name"], m["threat"]]
	for c in path_box.get_children():
		c.queue_free()
	for i in m["nodes"].size():
		var n: Dictionary = m["nodes"][i]
		var box := Label.new()
		box.custom_minimum_size = Vector2(52, 44)
		box.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_theme_font_size_override("font_size", 9)
		var known_trap: bool = n.has("trap") and n["trap"]["revealed"] and not n["trap"].get("done", false)
		box.text = NODE_ICONS[n["kind"]] + ("\nTRAP" if known_trap else "")
		var style := StyleBoxFlat.new()
		style.bg_color = Color("ffe08a") if i == run.node_index else (Color("3f7d3a") if i < run.node_index else Color("2a2a2a"))
		box.add_theme_color_override("font_color", Color.BLACK if i == run.node_index else Color.WHITE)
		box.add_theme_stylebox_override("normal", style)
		path_box.add_child(box)
	var lines := []
	for h in run.heroes:
		var state := "CAPTURED" if run.captured.has(h.id) else "%d/%d" % [h.hp, h.max_hp]
		lines.append("%s %s%s" % [h.name, state, "  (netted)" if h.has_status("netted") else ""])
	party_label.text = "  ".join(lines.slice(0, 2)) + "\n" + "  ".join(lines.slice(2)) + "\nGold carried: %d" % run.gold
	log_label.text = "\n".join(run.mission_log.slice(max(0, run.mission_log.size() - 14)))


func _set_buttons(options: Array) -> void:
	for c in buttons.get_children():
		c.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _show_briefing() -> void:
	run.mission_log.append("Briefing: %s at %s. Reward: %d gold." % [run.mission["type"].capitalize(), run.mission["location_name"], run.mission["rewards"]["gold"]])
	_refresh()
	_set_buttons([
		["Send scouts ahead", _scout],
		["Set out now", _set_out],
	])


func _scout() -> void:
	run.scout()
	_refresh()
	if run.is_bait() and run.mission["bait"]["revealed"]:
		_set_buttons([
			["Call it off", func():
				run.call_off()
				_finish()],
			["Go anyway", _set_out],
		])
	else:
		_set_out()


func _set_out() -> void:
	_handle(run.arrive())


func _handle(step: Dictionary) -> void:
	_refresh()
	if run.is_over():
		_finish()
		return
	match step["type"]:
		"trap_choice":
			var trap: Dictionary = step["trap"]
			run.mission_log.append("Your scouts warned of a trap here: %s." % trap["name"])
			_refresh()
			_set_buttons([
				["Go around it", func(): _handle(run.decide_trap(true))],
				["Walk into it anyway", func(): _handle(run.decide_trap(false))],
			])
		"choice":
			var opts := []
			for i in step["options"].size():
				opts.append([step["options"][i]["label"], func(): _handle(run.choose(i))])
			_set_buttons(opts)
		"battle":
			_fight(step["enemies"])
		"continue":
			_set_buttons([["Onward", _next]])


func _fight(enemy_ids: Array) -> void:
	var view := BattleView.new()
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.run_battle(db, run.make_battle(enemy_ids), run.current_node()["text"])
	view.finished.connect(func(b):
		view.queue_free()
		run.battle_finished(b)
		if run.is_over():
			_refresh()
			_finish()
		else:
			_refresh()
			_set_buttons([["Onward", _next]]))
	add_child(view)


func _next() -> void:
	run.advance()
	if run.is_over():
		_refresh()
		_finish()
	else:
		_handle(run.arrive())


func _finish() -> void:
	_refresh()
	_set_buttons([["Back to camp", func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")]])
