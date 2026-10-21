## The strategic map: pick a place, the band walks there by itself, and the days pass.
## The painted map (tools/make_scenery.py) shows roads and places; parchment plaques name them.
extends Control

const GameData = preload("res://core/game_data.gd")
const Campaign = preload("res://core/campaign.gd")
const MissionView = preload("res://scenes/mission/mission_view.gd")
const BattleView = preload("res://scenes/battle/battle_view.gd")
const Style = preload("res://scenes/ui/style.gd")
const TipCard = preload("res://scenes/ui/tip_card.gd")

const MAP_TOP := 80
## The bottom panel's least height: four lines of place info and five rows of buttons.
const PANEL_MIN := 300
const STEP_SECONDS := 0.35
## The map art draws each place's icon this far above its node point, leaving room for the name below.
const ICON_LIFT := 12
const TOKEN_OFFSET := Vector2(12, -44)
const INK := Color("3a2a1a")
## Map labels for jobs whose type name alone doesn't say what they are.
const TAGS := {"rescue": "FREE VILLAGERS"}

var db
var campaign
var selected := ""
var busy := false

var status_label: Label
var map_layer: Control
var marian_token: TextureRect   # Maid Marian at home in camp, after the wedding
var band_token: TextureRect
var info_label: Label
var buttons: GridContainer


## Optionally hand in a loaded campaign before adding to the tree; otherwise a new one starts.
func start(game_data, c) -> void:
	db = game_data
	campaign = c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Style.theme()
	if campaign == null:
		db = GameData.new()
		campaign = Campaign.new(db, int(Time.get_ticks_usec()))
	_build_layout()
	_after_day()


func _build_layout() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var h := Style.screen_height(self)
	add_child(Style.panel(Vector2(0, 0), Vector2(360, MAP_TOP - 2)))
	status_label = _label(Vector2(8, 4), Vector2(344, Style.lines(4)), 16)

	# 176x196 pixel art shown at 2x; roads, river, forest and place icons are all in the picture.
	# A phone too short for the map and the panel shrinks the map rather than the text.
	var panel_top: float = minf(MAP_TOP + 392 + 2, h - PANEL_MIN)
	var zoom: float = minf(1.0, (panel_top - 2 - MAP_TOP) / 392.0)
	var map_pos := Vector2((360 - 352 * zoom) / 2, MAP_TOP)
	var art := TextureRect.new()
	art.texture = preload("res://assets/map/map.png")
	art.position = map_pos
	art.size = Vector2(352, 392)
	art.scale = Vector2(zoom, zoom)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(art)
	map_layer = Control.new()
	map_layer.position = map_pos
	map_layer.size = Vector2(352, 392)
	map_layer.scale = Vector2(zoom, zoom)
	add_child(map_layer)
	for id in campaign.map["nodes"]:
		_add_node_button(id)
	marian_token = TextureRect.new()
	marian_token.texture = BattleView.sprite_by_id("marian")
	marian_token.size = Vector2(32, 32)
	marian_token.position = _node_pos("camp") + TOKEN_OFFSET + Vector2(-26, 0)
	marian_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(marian_token)
	band_token = TextureRect.new()
	band_token.texture = preload("res://assets/sprites/robin.png")
	band_token.size = Vector2(32, 32)
	band_token.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_layer.add_child(band_token)
	_place_token(campaign.location)

	add_child(Style.panel(Vector2(0, panel_top), Vector2(360, h - panel_top)))
	info_label = _label(Vector2(8, panel_top + 6), Vector2(344, Style.lines(4)), 16)
	buttons = GridContainer.new()
	buttons.columns = 2
	buttons.position = Vector2(8, panel_top + 8 + Style.lines(4))
	buttons.size = Vector2(344, h - buttons.position.y - 4)
	buttons.add_theme_constant_override("v_separation", 4)
	add_child(buttons)


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


## Each place gets an invisible button over its painted icon and a parchment name plaque below it.
func _add_node_button(id: String) -> void:
	var icon := Button.new()
	Style.flat(icon)
	icon.size = Vector2(40, 30)
	icon.position = _node_pos(id) - Vector2(20, ICON_LIFT + 16)
	icon.pressed.connect(func(): _select(id))
	map_layer.add_child(icon)
	var b := Button.new()
	b.name = id
	b.add_theme_font_size_override("font_size", 8)
	b.add_theme_constant_override("line_spacing", -1)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, INK)
	b.pressed.connect(func(): _select(id))
	map_layer.add_child(b)


## Sizes a place's plaque to its text and centres it under the icon.
func _fit_plaque(id: String, selected_now: bool) -> void:
	var b: Button = map_layer.get_node(id)
	var style := Style.frame("plaque_selected" if selected_now else "plaque", 3)
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, style)
	b.reset_size()
	var pos := _node_pos(id) + Vector2(-b.size.x / 2, 2)
	b.position = Vector2(clamp(pos.x, 2, map_layer.size.x - b.size.x - 2), pos.y)


func _place_token(id: String) -> void:
	band_token.position = _node_pos(id) + TOKEN_OFFSET


func _refresh() -> void:
	var c = campaign
	marian_token.visible = c.marian_home()
	# The villains' plots fill up each day: at 100% the Sheriff baits a job; Guy may raid from 50%.
	status_label.text = "Day %d  Gold %d  Rep %d%s\nSupplies %d (%d days)  Infamy %d\nSheriff's trap %d%%  Guy's raid %d%%%s" % [
		c.day, c.gold, c.reputation, ("  Bounty %d" % c.bounty()) if c.wanted_level() > 0 else "", c.supplies, c.supply_days(), c.infamy, c.plots["sheriff"], c.plots["guy"],
		("\nGuy is hunting %s" % c.hero_name(c.hunted_hero)) if c.hunted_hero != "" else ""]
	for id in c.map["nodes"]:
		var b: Button = map_layer.get_node(id)
		var tag := ""
		if c.missions.has(id):
			var m: Dictionary = c.missions[id]
			if m.has("rescue_heroes"):
				tag = "\n[FREE FRIENDS]"
			elif m["type"] == "story":
				tag = "\n[LEGEND]"
			else:
				tag = "\n[%s]" % TAGS.get(m["type"], m["type"].to_upper())
			if m.has("marian"):
				tag += "\n+ Maid Marian"
		b.text = c.node(id)["name"] + tag
		_fit_plaque(id, id == selected)


func _select(id: String) -> void:
	if busy:
		return
	selected = id
	_refresh()
	var c = campaign
	var n: Dictionary = c.node(id)
	# Threat is the Sheriff's grip on the region plus half the band's infamy.
	var lines := ["%s  Threat %d" % [n["name"], c.threat(id)],
		"Sheriff's grip on %s: %d%%" % [c.map["regions"][n["region"]]["name"], c.control[n["region"]]]]
	if id == "camp" and c.marian_home():
		lines[1] = "Grip %d%%. Maid Marian lives here." % c.control[n["region"]]
	var heroes_line := []
	for h in c.free_heroes():
		heroes_line.append("%s %d/%d" % [h.short_name(), h.hp, h.max_hp])
	for h in c.captured:
		heroes_line.append("%s caught" % (c.heroes[h].short_name() if c.heroes.has(h) else c.hero_name(h).split(" ")[0]))
	lines.append(", ".join(heroes_line))
	if c.missions.has(id):
		var m: Dictionary = c.missions[id]
		if m["type"] == "contest":
			var prize: Dictionary = m["nodes"][1]["prize"]
			lines.append("Archery contest: %s. Purse %d gold, until day %d." % [m["name"], prize["gold"], m["expires"]])
		elif m["type"] == "story":
			var joins: String = " %s may join the band." % db.heroes[m["recruit"]]["name"] if m["recruit"] != "" else ""
			lines.append("Legend: %s.%s" % [m["name"], joins])
		else:
			var expiry: String = "" if m.has("rescue_heroes") else ", gone after day %d" % m["expires"]
			lines.append("Job: %s. Reward %d gold%s." % [m["name"], m["rewards"]["gold"], expiry])
	if not c.news.is_empty():
		lines.append(c.news.back())
	Style.fit_text(info_label, "\n".join(lines))

	var opts := []
	var days: int = c.route(id).size()
	if id == c.location:
		if c.missions.has(id):
			opts.append(["Enter contest" if c.missions[id]["type"] == "contest" else "Start the job", _start_job])
		if c.can_pay_informant():
			opts.append(["Informant (%dg)" % c.informant_cost(), _act.bind(c.pay_informant)])
		if not c.prisoners_here().is_empty():
			opts.append(["Bribe jailer (%dg)" % c.jailer_cost(), _act.bind(c.bribe_jailer)])
		if c.can_give():
			opts.append(["Give to the poor", _show_giving])
		if c.can_buy_supplies():
			var sup: Dictionary = c.econ["supplies"]
			opts.append(["Supplies %d (%dg)" % [sup["bundle"], sup["price"]], _act.bind(c.buy_supplies)])
		if id == "camp":
			opts.append(["Rest a day", func():
				c.rest()
				_after_day()])
			opts.append(["Armory", _show_armory])
			var mm: Dictionary = c.econ["merry_men"]
			if c.can_hire():
				opts.append(["Hire man (%dg)" % mm["price"], _act.bind(c.hire_merry_man)])
			elif c.merry_men.size() < int(mm["max"]):
				opts.append(["Men join: %d rep" % mm["min_reputation"], func(): pass])
	else:
		opts.append(["Travel (%d day%s)" % [days, "" if days == 1 else "s"], _travel.bind(id)])
	opts.append(["News", _show_news])
	opts.append(["Legends %d/%d" % [campaign.stories_done.size(), campaign.legends().size()], _show_legends])
	_set_buttons(opts)


func _set_buttons(options: Array) -> void:
	for ch in buttons.get_children():
		ch.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.custom_minimum_size = Vector2(170, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _travel(to: String) -> void:
	busy = true
	# The walk is decided first: bounty hunters may stop the band partway.
	var path: Array = campaign.travel(to)
	for step in path:
		var tween := create_tween()
		tween.tween_property(band_token, "position", _node_pos(step) + TOKEN_OFFSET, STEP_SECONDS)
		await tween.finished
	busy = false
	_after_day()


## After anything that passes time: save, then show what the Sheriff did (a new poster, an ambush).
func _after_day() -> void:
	campaign.save()
	_select(campaign.location)
	if campaign.poster_news > 0:
		_show_poster()
	elif not campaign.ambush.is_empty():
		_play(campaign.start_ambush())
	else:
		_next_tip()


## The map's tutorial tips, one at a time, each when it first matters.
func _next_tip() -> void:
	var c = campaign
	var due := ["map"]
	if c.missions.values().any(func(m): return m["type"] == "story"):
		due.append("legends")
	if c.day >= 2:
		due.append("villains")
	if not c.captured.is_empty():
		due.append("captured")
	for id in due:
		var card = TipCard.show_once(self, id)
		if card:
			card.closed.connect(_next_tip)
			return


func _start_job() -> void:
	_play(campaign.start_mission())


func _play(run) -> void:
	if run == null:
		return
	var was_won: bool = campaign.finale_won()
	var view := MissionView.new()
	view.play(db, run)
	view.done.connect(func(r):
		campaign.finish_mission(r)
		view.queue_free()
		_place_token(campaign.location)
		if campaign.finale_won() and not was_won:
			campaign.save()
			_select(campaign.location)
			_show_finale()
		else:
			_after_day())
	add_child(view)


## A wanted poster, nailed up over the map when the bounty rises.
func _show_poster() -> void:
	var c = campaign
	c.poster_news = 0
	c.save()
	var lines := ["for robbing the Sheriff's wagons", "and making him look foolish.", "",
		"REWARD", "%d GOLD" % c.bounty(), "", "Bounty hunters are on the roads."]
	_notice("WANTED", "ROBIN HOOD", lines, "robin", "Let them try!")


## The end of the Sheriff's story. The campaign carries on afterwards.
func _show_finale() -> void:
	var lines := ["The Sheriff has fled Nottingham", "in his nightshirt, and the people", "of the shire are free.", "",
		"Your legend will be sung", "for a hundred years.", "", "(The greenwood still needs you.)"]
	_notice("VICTORY", "SHERWOOD IS FREE", lines, "robin", "Play on")


## The book of legends: how many the band has lived, the told ones by name, the rest still a mystery.
func _show_legends() -> void:
	busy = true
	var h := Style.screen_height(self)
	var all: Array = campaign.legends()
	var told: Array = all.filter(func(l): return l[2])
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var tall: float = minf(h - 32, 640)
	var top: float = (h - tall) / 2
	var edge := ColorRect.new()
	edge.color = Color("6a4a2c")
	edge.position = Vector2(26, top)
	edge.size = Vector2(308, tall)
	layer.add_child(edge)
	var paper := ColorRect.new()
	paper.color = Color("e8d8a8")
	paper.position = Vector2(30, top + 4)
	paper.size = Vector2(300, tall - 8)
	layer.add_child(paper)
	var y := top + 14
	for row in [["LEGENDS", 32, Color("8a1f1f")], ["%d of %d told" % [told.size(), all.size()], 16, INK]]:
		var l := Label.new()
		l.text = row[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", row[2])
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.position = Vector2(30, y)
		l.size = Vector2(300, row[1] + 4)
		layer.add_child(l)
		y += row[1] + 10
	# Told legends by name; the rest stay a mystery until the band lives them.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, y)
	scroll.size = Vector2(280, top + tall - 64 - y)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layer.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	var rows: Array = told.map(func(l): return [l[1], INK])
	if told.size() < all.size():
		rows.append(["%d more still to discover..." % (all.size() - told.size()), Color("8a7a5a")])
	for r in rows:
		var row := Label.new()
		row.text = r[0]
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size = Vector2(270, 0)
		row.add_theme_color_override("font_color", r[1])
		row.add_theme_constant_override("shadow_offset_x", 0)
		row.add_theme_constant_override("shadow_offset_y", 0)
		list.add_child(row)
	var close := Button.new()
	close.text = "Back"
	close.position = Vector2(80, top + tall - 52)
	close.size = Vector2(200, 40)
	close.pressed.connect(func():
		layer.queue_free()
		busy = false
		_select(selected))
	layer.add_child(close)


## A parchment notice over the map with a picture, closed with one button.
func _notice(heading: String, subheading: String, lines: Array, sprite_id: String, close_text: String) -> void:
	busy = true
	var h := Style.screen_height(self)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.03, 0.02, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var top: float = maxf(16, (h - 560) / 2)
	var edge := ColorRect.new()
	edge.color = Color("6a4a2c")
	edge.position = Vector2(26, top)
	edge.size = Vector2(308, 560)
	layer.add_child(edge)
	var paper := ColorRect.new()
	paper.color = Color("e8d8a8")
	paper.position = Vector2(30, top + 4)
	paper.size = Vector2(300, 552)
	layer.add_child(paper)
	var y := top + 14
	for row in [[heading, 32, Color("8a1f1f")], [subheading, 16, INK]]:
		var l := Label.new()
		l.text = row[0]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", row[1])
		l.add_theme_color_override("font_color", row[2])
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 0)
		l.position = Vector2(30, y)
		l.size = Vector2(300, row[1] + 4)
		layer.add_child(l)
		y += row[1] + 10
	var face := TextureRect.new()
	face.texture = BattleView.sprite_by_id(sprite_id)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_SCALE
	face.position = Vector2(116, y)
	face.size = Vector2(128, 128)
	layer.add_child(face)
	var frame := ReferenceRect.new()
	frame.border_color = INK
	frame.border_width = 2
	frame.editor_only = false
	frame.position = Vector2(108, y - 6)
	frame.size = Vector2(144, 140)
	layer.add_child(frame)
	y += 144
	var body := Label.new()
	body.text = "\n".join(lines)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_theme_color_override("font_color", INK)
	body.add_theme_constant_override("shadow_offset_x", 0)
	body.add_theme_constant_override("shadow_offset_y", 0)
	body.position = Vector2(34, y)
	body.size = Vector2(292, Style.lines(lines.size()))
	layer.add_child(body)
	var close := Button.new()
	close.text = close_text
	close.position = Vector2(80, top + 500)
	close.size = Vector2(200, 40)
	close.pressed.connect(func():
		layer.queue_free()
		busy = false
		_after_day())
	layer.add_child(close)


## Runs a spending action; on failure (usually too little gold) says so.
func _act(action: Callable) -> void:
	if action.call():
		campaign.save()
		_select(campaign.location)
	else:
		Style.fit_text(info_label, "You can't afford that right now.")


func _show_giving() -> void:
	var opts := []
	for amount in campaign.econ["give_amounts"]:
		opts.append(["Give %d gold" % amount, _act.bind(campaign.give_to_poor.bind(int(amount)))])
	opts.append(["Back", func(): _select(selected)])
	Style.fit_text(info_label, "Every 10 gold given raises reputation by 1, and the Sheriff's grip here loosens.")
	_set_buttons(opts)


## Full-screen armory: pick a hero, then buy gear for them.
func _show_armory(hero_id := "") -> void:
	var c = campaign
	var panel := ColorRect.new()
	panel.name = "Armory"
	panel.color = Color("1a140e")
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var screen_h := Style.screen_height(self)
	panel.add_child(Style.panel(Vector2(0, 0), Vector2(360, screen_h)))
	var title := Label.new()
	title.position = Vector2(8, 8)
	title.size = Vector2(344, Style.lines(2))
	panel.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(8, 52)
	scroll.size = Vector2(344, screen_h - 60)
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
			var row := _list_button(list, "%s (%s)\nATK %d DEF %d SPD %d HP %d\n%s" % [h.name, h.cls, h.atk, h.def, h.spd, h.max_hp, ", ".join(gear) if not gear.is_empty() else "No gear"], reopen.bind(h.id))
			row.icon = BattleView.sprite_for(h)
	else:
		var h = c.heroes[hero_id]
		title.text = "%s    Gold %d\nATK %d DEF %d SPD %d HP %d CRIT %d%%" % [h.name, c.gold, h.atk, h.def, h.spd, h.max_hp, int(h.crit * 100)]
		for item_id in c.items_for(hero_id):
			var it: Dictionary = db.items[item_id]
			var bonus := []
			for k in it["bonus"]:
				var v = it["bonus"][k]
				bonus.append("%s%s %s" % ["+" if v > 0 else "", str(int(v * 100)) + "%" if k == "crit" else str(int(v)), k.to_upper()])
			var worn: bool = c.equipment.get(hero_id, {}).get(it["slot"], "") == item_id
			var label := "%s\n%s, %s\n%s" % [it["name"], it["slot"].capitalize(), "worn" if worn else "%d gold" % it["price"], ", ".join(bonus)]
			var row := _list_button(list, label, func():
				if c.buy_item(hero_id, item_id):
					c.save()
				reopen.call(hero_id))
			row.icon = _item_icon(item_id)
			if worn:
				row.add_theme_color_override("font_color", Color("f0d070"))
		_list_button(list, "Back to the band", reopen.bind(""))
	_list_button(list, "Leave the armory", close)


## Gear icons are 16x16; shown at 2x in the armory rows.
func _item_icon(item_id: String) -> Texture2D:
	var path := "res://assets/items/%s.png" % item_id
	if not ResourceLoader.exists(path):
		return null
	var img: Image = load(path).get_image()
	img.resize(32, 32, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


func _list_button(list: VBoxContainer, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(330, 40)
	b.pressed.connect(cb)
	list.add_child(b)
	return b


func _show_news() -> void:
	var recent: Array = campaign.news.slice(max(0, campaign.news.size() - 6))
	Style.fit_text(info_label, "\n".join(recent) if not recent.is_empty() else "No news yet.", true)
	_set_buttons([["Back", func(): _select(selected)]])
