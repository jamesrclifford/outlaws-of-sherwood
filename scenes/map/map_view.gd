## The strategic map: pick a place, the band walks there by itself, and the days pass.
## Placeholder parchment and blocks stand in for the pixel-art map.
extends Control

const GameData = preload("res://core/game_data.gd")
const Campaign = preload("res://core/campaign.gd")
const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")

const MAP_TOP := 64
const KIND_COLORS := {"camp": Color("3f7d3a"), "village": Color("a07a45"), "forest": Color("2f5a2a"), "road": Color("7a6a55"), "town": Color("6a5a7a")}
const STEP_SECONDS := 0.35

var db
var campaign
var selected := ""
var busy := false

var status_label: Label
var map_layer: Control
var band_token: ColorRect
var info_label: Label
var buttons: GridContainer
var news_label: Label


## Optionally hand in a loaded campaign before adding to the tree; otherwise a new one starts.
func start(game_data, c) -> void:
	db = game_data
	campaign = c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if campaign == null:
		db = GameData.new()
		campaign = Campaign.new(db, int(Time.get_ticks_usec()))
	_build_layout()
	_select(campaign.location)


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1d2b1f")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	status_label = _label(Vector2(8, 4), Vector2(344, 56), 10)

	var parchment := ColorRect.new()
	parchment.color = Color("c9b68a")
	parchment.position = Vector2(4, MAP_TOP)
	parchment.size = Vector2(352, 392)
	add_child(parchment)
	map_layer = Control.new()
	map_layer.position = Vector2(4, MAP_TOP)
	map_layer.size = Vector2(352, 392)
	add_child(map_layer)
	_draw_roads()
	for id in campaign.map["nodes"]:
		_add_node_button(id)
	band_token = ColorRect.new()
	band_token.color = Color("1a6b1a")
	band_token.size = Vector2(12, 12)
	band_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(band_token)
	_place_token(campaign.location)

	info_label = _label(Vector2(8, 460), Vector2(344, 64), 9)
	buttons = GridContainer.new()
	buttons.columns = 2
	buttons.position = Vector2(8, 528)
	buttons.size = Vector2(344, 108)
	add_child(buttons)
	news_label = _label(Vector2(8, 462), Vector2(344, 0), 9)
	news_label.visible = false


func _label(pos: Vector2, sz: Vector2, font_size: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", font_size)
	add_child(l)
	return l


func _node_pos(id: String) -> Vector2:
	var n: Dictionary = campaign.node(id)
	return Vector2(n["x"], n["y"])


func _draw_roads() -> void:
	var drawn := {}
	for id in campaign.map["nodes"]:
		for other in campaign.node(id)["links"]:
			var key: String = id + other if id < other else other + id
			if drawn.has(key):
				continue
			drawn[key] = true
			var line := Line2D.new()
			line.width = 3
			line.default_color = Color("8a7350")
			line.add_point(_node_pos(id))
			line.add_point(_node_pos(other))
			map_layer.add_child(line)


func _add_node_button(id: String) -> void:
	var b := Button.new()
	b.name = id
	b.size = Vector2(76, 30)
	b.position = _node_pos(id) - Vector2(38, 15)
	b.add_theme_font_size_override("font_size", 8)
	var style := StyleBoxFlat.new()
	style.bg_color = KIND_COLORS[campaign.node(id)["kind"]]
	style.set_corner_radius_all(3)
	b.add_theme_stylebox_override("normal", style)
	b.pressed.connect(func(): _select(id))
	map_layer.add_child(b)


func _place_token(id: String) -> void:
	band_token.position = _node_pos(id) + Vector2(30, -20)


func _refresh() -> void:
	var c = campaign
	status_label.text = "Day %d   Gold %d   Supplies %d (%d days)\nReputation %d   Infamy %d   Sheriff's plot %d%%   Guy's plot %d%%%s" % [
		c.day, c.gold, c.supplies, c.supply_days(), c.reputation, c.infamy, c.plots["sheriff"], c.plots["guy"],
		("\nGuy is hunting %s" % c.hero_name(c.hunted_hero)) if c.hunted_hero != "" else ""]
	for id in c.map["nodes"]:
		var b: Button = map_layer.get_node(id)
		var tag := ""
		if c.missions.has(id):
			tag = "\n[FREE FRIENDS]" if c.missions[id].has("rescue_heroes") else "\n[%s]" % c.missions[id]["type"].to_upper()
		b.text = c.node(id)["name"] + tag
		b.modulate = Color("ffe08a") if id == selected else Color.WHITE


func _select(id: String) -> void:
	if busy:
		return
	selected = id
	_refresh()
	var c = campaign
	var n: Dictionary = c.node(id)
	var lines := ["%s  (%s, threat %d)" % [n["name"], c.map["regions"][n["region"]]["name"], c.threat(id)]]
	var heroes_line := []
	for h in c.free_heroes():
		heroes_line.append("%s %d/%d" % [h.name.split(" ")[0], h.hp, h.max_hp])
	for h in c.captured:
		heroes_line.append("%s CAPTURED" % c.hero_name(h).split(" ")[0])
	lines.append(", ".join(heroes_line))
	if c.missions.has(id):
		var m: Dictionary = c.missions[id]
		var expiry: String = "" if m.has("rescue_heroes") else ", gone after day %d" % m["expires"]
		lines.append("Job: %s. Reward %d gold%s." % [m["name"], m["rewards"]["gold"], expiry])
	if not c.news.is_empty():
		lines.append(c.news.back())
	info_label.text = "\n".join(lines)

	var opts := []
	var days: int = c.route(id).size()
	if id == c.location:
		if c.missions.has(id):
			opts.append(["Start the job", _start_job])
		if c.can_pay_informant():
			opts.append(["Ask an informant (%dg)" % c.informant_cost(), _act.bind(c.pay_informant)])
		if not c.prisoners_here().is_empty():
			opts.append(["Bribe the jailer (%dg)" % c.jailer_cost(), _act.bind(c.bribe_jailer)])
		if c.can_give():
			opts.append(["Give to the poor...", _show_giving])
		if c.can_buy_supplies():
			var sup: Dictionary = c.econ["supplies"]
			opts.append(["Buy %d supplies (%dg)" % [sup["bundle"], sup["price"]], _act.bind(c.buy_supplies)])
		if id == "camp":
			opts.append(["Rest a day", func():
				c.rest()
				_after_day()])
			opts.append(["Armory", _show_armory])
			var mm: Dictionary = c.econ["merry_men"]
			if c.can_hire():
				opts.append(["Hire a Merry Man (%dg)" % mm["price"], _act.bind(c.hire_merry_man)])
			elif c.merry_men.size() < int(mm["max"]):
				opts.append(["Merry Men join at %d rep" % mm["min_reputation"], func(): pass])
	else:
		opts.append(["Travel here (%d day%s)" % [days, "" if days == 1 else "s"], _travel.bind(id)])
	opts.append(["News", _show_news])
	_set_buttons(opts)


func _set_buttons(options: Array) -> void:
	for ch in buttons.get_children():
		ch.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.custom_minimum_size = Vector2(168, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 9)
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _travel(to: String) -> void:
	busy = true
	var path: Array = campaign.route(to)
	for step in path:
		var tween := create_tween()
		tween.tween_property(band_token, "position", _node_pos(step) + Vector2(30, -20), STEP_SECONDS)
		await tween.finished
	campaign.travel(to)
	busy = false
	_after_day()


func _after_day() -> void:
	campaign.save()
	_select(campaign.location)


func _start_job() -> void:
	var run = campaign.start_mission()
	if run == null:
		return
	var view := MissionView.new()
	view.play(db, run)
	view.done.connect(func(r):
		campaign.finish_mission(r)
		campaign.save()
		view.queue_free()
		_place_token(campaign.location)
		_select(campaign.location))
	add_child(view)


## Runs a spending action; on failure (usually too little gold) says so.
func _act(action: Callable) -> void:
	if action.call():
		campaign.save()
		_select(campaign.location)
	else:
		info_label.text = "You can't afford that right now."


func _show_giving() -> void:
	var opts := []
	for amount in campaign.econ["give_amounts"]:
		opts.append(["Give %d gold" % amount, _act.bind(campaign.give_to_poor.bind(int(amount)))])
	opts.append(["Back", func(): _select(selected)])
	info_label.text = "Every 10 gold given raises reputation by 1, and the Sheriff's grip here loosens."
	_set_buttons(opts)


## Full-screen armory: pick a hero, then buy gear for them.
func _show_armory(hero_id := "") -> void:
	var c = campaign
	var panel := ColorRect.new()
	panel.name = "Armory"
	panel.color = Color("241a12")
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var title := Label.new()
	title.position = Vector2(8, 8)
	title.size = Vector2(344, 40)
	title.add_theme_font_size_override("font_size", 11)
	panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 56)
	scroll.size = Vector2(344, 530)
	panel.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	# Detach before freeing so the next panel can take the name "Armory" straight away.
	var close := func():
		remove_child(panel)
		panel.queue_free()
		_select(c.location)
	var reopen := func(h: String):
		remove_child(panel)
		panel.queue_free()
		_show_armory(h)

	if hero_id == "":
		title.text = "Armory    Gold %d\nChoose who to equip." % c.gold
		for h in c.free_heroes():
			var gear: Array = c.equipment.get(h.id, {}).values().map(func(i): return db.items[i]["name"])
			var row := _list_button(list, "%s (%s)  ATK %d DEF %d SPD %d HP %d\n%s" % [h.name, h.cls, h.atk, h.def, h.spd, h.max_hp, ", ".join(gear) if not gear.is_empty() else "No gear"], reopen.bind(h.id))
			row.icon = BattleView.sprite_for(h)
	else:
		var h = c.heroes[hero_id]
		title.text = "%s    Gold %d\nATK %d  DEF %d  SPD %d  HP %d  CRIT %d%%" % [h.name, c.gold, h.atk, h.def, h.spd, h.max_hp, int(h.crit * 100)]
		for item_id in c.items_for(hero_id):
			var it: Dictionary = db.items[item_id]
			var bonus := []
			for k in it["bonus"]:
				var v = it["bonus"][k]
				bonus.append("%s%s %s" % ["+" if v > 0 else "", str(int(v * 100)) + "%" if k == "crit" else str(int(v)), k.to_upper()])
			var worn: bool = c.equipment.get(hero_id, {}).get(it["slot"], "") == item_id
			var label := "%s  [%s]  %s\n%s" % [it["name"], it["slot"], "EQUIPPED" if worn else "%d gold" % it["price"], ", ".join(bonus)]
			_list_button(list, label, func():
				if c.buy_item(hero_id, item_id):
					c.save()
				reopen.call(hero_id))
		_list_button(list, "Back to the band", reopen.bind(""))
	_list_button(list, "Leave the armory", close)


func _list_button(list: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(330, 38)
	b.add_theme_font_size_override("font_size", 9)
	b.pressed.connect(cb)
	list.add_child(b)
	return b


func _show_news() -> void:
	var recent: Array = campaign.news.slice(max(0, campaign.news.size() - 6))
	info_label.text = "\n".join(recent) if not recent.is_empty() else "No news yet."
	_set_buttons([["Back", func(): _select(selected)]])
