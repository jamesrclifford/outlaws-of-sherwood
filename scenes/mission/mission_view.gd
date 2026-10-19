## Mission screen: the band stands at the job's location, the path ahead runs along the top as
## medallions, and the story so far and the choices sit on the wooden panel below.
extends Control

## Emitted when a mission started with play() ends and the player heads back to the map.
signal done(run)

const GameData = preload("res://core/game_data.gd")
const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")
const Style = preload("res://scenes/ui/style.gd")

const PARTY := ["robin", "little_john", "will", "tuck"]
const TRAP_MARK := preload("res://assets/ui/trap_mark.png")
const RING_TURN := preload("res://assets/ui/ring_turn.png")

## Set by the menu before the scene is shown.
var mission_type := "robbery"
var threat := 40

var db
var run
var title_label: Label
var subtitle_label: Label
var path_box: HBoxContainer
var party_box: Control
var party_label: Label
var log_label: Label
var buttons: VBoxContainer
var backdrop: TextureRect


## Plays a mission prepared elsewhere (by the campaign). Call before adding to the tree.
func play(game_data, mission_run) -> void:
	db = game_data
	run = mission_run


func _ready() -> void:
	if run == null:
		db = GameData.new()
		var gen = MissionGen.new(db)
		var generated: Dictionary = gen.generate(mission_type, threat, int(Time.get_ticks_usec()), "", "little_john")
		run = MissionRun.new(db, generated, PARTY.map(func(h): return db.make_hero(h)))
	var mission: Dictionary = run.mission
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	_build_layout()
	backdrop.texture = BattleView.backdrop_for(mission["location"])
	_show_briefing()


## The scene keeps its size; the panel below grows with the phone, and the buttons sit at its foot.
func _build_layout() -> void:
	var h := Style.screen_height(self)
	var bg := ColorRect.new()
	bg.color = Color("1a140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# The location's battle backdrop, cropped to its top half, sets the scene.
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(360, 236)
	add_child(clip)
	backdrop = TextureRect.new()
	backdrop.size = Vector2(360, 440)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.modulate = Color(0.85, 0.85, 0.85)
	clip.add_child(backdrop)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.06, 0.04, 0.6)
	shade.size = Vector2(360, 96)
	add_child(shade)
	title_label = _label(Vector2(8, 4), Vector2(344, 22), 16)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color("f0d070"))
	subtitle_label = _label(Vector2(8, 24), Vector2(344, Style.lines(1)), 16)
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	path_box = HBoxContainer.new()
	path_box.position = Vector2(8, 46)
	path_box.size = Vector2(344, 48)
	path_box.alignment = BoxContainer.ALIGNMENT_CENTER
	path_box.add_theme_constant_override("separation", 4)
	add_child(path_box)
	party_box = Control.new()
	party_box.position = Vector2(0, 112)
	party_box.size = Vector2(360, 124)
	add_child(party_box)
	add_child(Style.panel(Vector2(0, 236), Vector2(360, h - 236)))
	party_label = _label(Vector2(10, 242), Vector2(340, Style.lines(1)), 16)
	party_label.add_theme_color_override("font_color", Color("f0d070"))
	# Room for three 40-tall choices; a fourth pushes into the log's last lines.
	buttons = VBoxContainer.new()
	buttons.position = Vector2(8, h - 6 - 3 * 44)
	buttons.size = Vector2(344, 3 * 44)
	buttons.add_theme_constant_override("separation", 4)
	add_child(buttons)
	log_label = _label(Vector2(10, 264), Vector2(340, buttons.position.y - 4 - 264), 16)
	log_label.add_theme_color_override("font_color", Color("e0d4ac"))


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
	title_label.text = m["name"]
	subtitle_label.text = "%s  -  threat %d" % [m["location_name"], m["threat"]]
	for c in path_box.get_children():
		c.queue_free()
	for i in m["nodes"].size():
		path_box.add_child(_path_medallion(m["nodes"][i], i))
	_refresh_party()
	party_label.text = "Gold carried: %d" % run.gold
	Style.fit_text(log_label, "\n".join(run.mission_log.slice(max(0, run.mission_log.size() - 15))), true)


## One step of the path: done steps fade, the current one glows, a known trap gets a red net.
func _path_medallion(n: Dictionary, i: int) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(44, 48)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/ui/node_%s.png" % n["kind"])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.size = Vector2(44, 44)
	if i < run.node_index:
		icon.modulate = Color(0.55, 0.55, 0.55)
	elif i > run.node_index:
		icon.modulate = Color(0.85, 0.85, 0.85)
	slot.add_child(icon)
	if i == run.node_index:
		var ring := TextureRect.new()
		ring.texture = RING_TURN
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.size = Vector2(40, 10)
		ring.position = Vector2(2, 40)
		slot.add_child(ring)
	if n.has("trap") and n["trap"]["revealed"] and not n["trap"].get("done", false):
		var mark := TextureRect.new()
		mark.texture = TRAP_MARK
		mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mark.stretch_mode = TextureRect.STRETCH_SCALE
		mark.size = Vector2(20, 20)
		mark.position = Vector2(26, -2)
		slot.add_child(mark)
	return slot


## The band stands on the scene; captured heroes are missing from it, netted ones are tinted.
func _refresh_party() -> void:
	for c in party_box.get_children():
		c.queue_free()
	var x: float = (360 - 80 * run.heroes.size()) / 2.0
	for h in run.heroes:
		var card := Control.new()
		card.position = Vector2(x, 0)
		card.size = Vector2(80, 124)
		x += 80
		party_box.add_child(card)
		var captured: bool = run.captured.has(h.id)
		var shadow := TextureRect.new()
		shadow.texture = preload("res://assets/ui/shadow.png")
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_SCALE
		shadow.size = Vector2(56, 16)
		shadow.position = Vector2(12, 52)
		card.add_child(shadow)
		var art := TextureRect.new()
		art.texture = BattleView.sprite_for(h)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.size = Vector2(64, 64)
		art.position = Vector2(8, 0)
		if captured:
			art.modulate = Color(1, 1, 1, 0.25)
		elif h.has_status("netted"):
			art.modulate = Color("d8c8a0")
		card.add_child(art)
		var plate := ColorRect.new()
		plate.color = Color(0.08, 0.06, 0.04, 0.72)
		plate.position = Vector2(2, 66)
		plate.size = Vector2(76, Style.lines(2))
		card.add_child(plate)
		var info := Label.new()
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.position = Vector2(-2, 68)
		info.size = Vector2(84, Style.lines(2))
		var state := "Caught" if captured else ("Netted" if h.has_status("netted") else "%d/%d" % [h.hp, h.max_hp])
		info.text = "%s\n%s" % [h.short_name(), state]
		card.add_child(info)


func _set_buttons(options: Array) -> void:
	for c in buttons.get_children():
		c.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _show_briefing() -> void:
	if run.mission["type"] == "story":
		run.mission_log.append(run.mission["intro"])
		_refresh()
		_set_buttons([["Set out", _set_out]])
		return
	run.mission_log.append("Briefing: %s at %s. Reward: %d gold." % [run.mission["type"].capitalize(), run.mission["location_name"], run.mission["rewards"]["gold"]])
	if run.is_bait() and run.mission["bait"]["revealed"]:
		run.mission_log.append("You already know this job is %s's trap." % db.baits[run.mission["bait"]["by"]]["name"])
		_refresh()
		_set_buttons([
			["Call it off", func():
				run.call_off()
				_finish()],
			["Send scouts ahead (1 day)", _scout],
			["Go anyway", _set_out],
		])
		return
	_refresh()
	_set_buttons([
		["Send scouts ahead (1 day)", _scout],
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
	view.run_battle(db, run.make_battle(enemy_ids), run.current_node()["text"], run.mission["location"])
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
	if done.get_connections().is_empty():
		_set_buttons([["Back to camp", func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn")]])
	else:
		_set_buttons([["Back to the map", func(): done.emit(run)]])
