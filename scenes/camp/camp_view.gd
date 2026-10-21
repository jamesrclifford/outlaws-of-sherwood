## Major Oak Camp: the band gathers under the great tree with whatever they have built around it.
## Here they rest (and spend the evening round the fire), build, hire men, buy supplies, visit the
## armory and hear out anyone who has come looking for Robin Hood.
extends Control

## Emitted when the band leaves camp; rested is true when a night has passed.
signal closed(rested)

const BattleView = preload("res://scenes/battle/battle_view.gd")
const Style = preload("res://scenes/ui/style.gd")
const TipCard = preload("res://scenes/ui/tip_card.gd")

const BUTTON_ROWS := 4
const NIGHT := Color(0.38, 0.42, 0.72)

var db
var campaign
## Opens the armory (it belongs to the map screen); set before adding to the tree.
var armory: Callable

var scene_layer: Control
var backdrop: TextureRect
var title_label: Label
var text_label: Label
var buttons: GridContainer
var night := false
var scene_h := 300.0   # the scene grows on taller phones, up to the whole backdrop


func start(game_data, c) -> void:
	db = game_data
	campaign = c


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Style.theme()
	var h := Style.screen_height(self)
	scene_h = clampf(h - 6 - BUTTON_ROWS * 40 - Style.lines(5) - 12, 300.0, 400.0)
	var bg := ColorRect.new()
	bg.color = Color("1a140e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = Vector2(360, scene_h)
	add_child(clip)
	backdrop = TextureRect.new()
	backdrop.texture = BattleView.backdrop_for("major_oak")
	backdrop.size = Vector2(360, 440)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	clip.add_child(backdrop)
	scene_layer = Control.new()
	scene_layer.size = Vector2(360, scene_h)
	scene_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(scene_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.08, 0.06, 0.04, 0.6)
	shade.size = Vector2(360, 26)
	add_child(shade)
	title_label = _label(Vector2(8, 4), Vector2(344, 22))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color("f0d070"))
	add_child(Style.panel(Vector2(0, scene_h), Vector2(360, h - scene_h)))
	# Four rows of buttons at the foot of the panel; the text fills the space above them.
	buttons = GridContainer.new()
	buttons.columns = 2
	buttons.position = Vector2(8, h - 6 - BUTTON_ROWS * 40)
	buttons.size = Vector2(344, BUTTON_ROWS * 40)
	buttons.add_theme_constant_override("v_separation", 4)
	add_child(buttons)
	text_label = _label(Vector2(10, scene_h + 6), Vector2(340, buttons.position.y - 6 - scene_h - 6))
	_show_camp()
	TipCard.show_once(self, "camp")


func _label(pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.position = pos
	l.size = sz
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(l)
	return l


func _sprite(tex: Texture2D, pos: Vector2, sz: Vector2, flip := false) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.position = pos
	r.size = sz
	r.flip_h = flip
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene_layer.add_child(r)
	return r


## The camp itself: what has been built, the band (and Marian, once she lives here) and any visitor.
func _draw_scene() -> void:
	for ch in scene_layer.get_children():
		ch.queue_free()
	var c = campaign
	var count := {}
	for id in c.upgrades:
		var u: Dictionary = db.camp["upgrades"][id]
		var tex: Texture2D = load("res://assets/camp/%s.png" % id)
		var nth: int = count.get(id, 0)
		count[id] = nth + 1
		var pos := Vector2(u["x"], scene_h - 6 - tex.get_size().y * 2 if u.get("ground", false) else u["y"])
		if nth > 0:
			pos = Vector2(u["more"][nth - 1][0], u["more"][nth - 1][1])
		_sprite(tex, pos, tex.get_size() * 2)
	var folk: Array = c.free_heroes().map(func(h): return BattleView.sprite_for(h))
	if c.marian_home():
		folk.insert(1, BattleView.sprite_by_id("marian"))
	var shown: Array = folk.slice(0, 7)
	# The band gathers between the fire and the archery butts.
	var step: float = minf(44.0, 180.0 / maxi(1, shown.size()))
	var feet := minf(scene_h - 40, 290.0)
	for i in shown.size():
		_sprite(shown[i], Vector2(84 + i * step, feet - 64 - (i % 2) * 12), Vector2(64, 64))
	if c.visitor != "" and not night:
		_sprite(BattleView.sprite_by_id(db.camp["visitors"][c.visitor]["sprite"]), Vector2(6, feet - 70), Vector2(64, 64), true)
	backdrop.modulate = NIGHT if night else Color.WHITE
	scene_layer.modulate = NIGHT if night else Color.WHITE
	if night:
		# Firelight on the band from the cooking fire.
		var glow := TextureRect.new()
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.gradient = Gradient.new()
		g.gradient.colors = PackedColorArray([Color(1.0, 0.6, 0.25, 0.45), Color(1.0, 0.5, 0.2, 0.0)])
		glow.texture = g
		glow.position = Vector2(-160, 20)
		glow.size = Vector2(440, 320)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		glow.name = "Glow"
		backdrop.get_parent().add_child(glow)
	elif backdrop.get_parent().has_node("Glow"):
		backdrop.get_parent().get_node("Glow").queue_free()


func _set_buttons(options: Array, columns := 2) -> void:
	buttons.columns = columns
	for ch in buttons.get_children():
		buttons.remove_child(ch)
		ch.queue_free()
	for o in options:
		var b := Button.new()
		b.text = o[0]
		b.custom_minimum_size = Vector2(170, 36)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if o.size() > 2:
			b.disabled = not o[2]
		b.pressed.connect(o[1])
		buttons.add_child(b)


func _show_camp(message := "") -> void:
	night = false
	var c = campaign
	_draw_scene()
	title_label.text = "Major Oak Camp  -  Day %d" % c.day
	var lines := ["Gold %d   Supplies %d   Men %d/%d" % [c.gold, c.supplies, c.merry_men.size(), c.men_max()]]
	if message != "":
		lines.append(message)
	elif c.visitor != "":
		lines.append("%s is waiting by the fire to speak with Robin Hood." % db.camp["visitors"][c.visitor]["name"])
	else:
		lines.append("The band is at home under the Major Oak.")
	Style.fit_text(text_label, "\n".join(lines))
	var opts := [["Rest the night", _rest], ["Build", _show_build.bind("")]]
	if c.visitor != "":
		opts.append(["Speak with visitor", _show_visitor])
	opts.append(["Armory", func(): armory.call()])
	var mm: Dictionary = c.econ["merry_men"]
	if c.can_hire():
		opts.append(["Hire man (%dg)" % mm["price"], _do.bind(c.hire_merry_man)])
	elif c.merry_men.size() < c.men_max():
		opts.append(["Men join: %d rep" % mm["min_reputation"], func(): pass, false])
	var sup: Dictionary = c.econ["supplies"]
	opts.append(["Supplies %d (%dg)" % [sup["bundle"], sup["price"]], _do.bind(c.buy_supplies)])
	opts.append(["Back to the map", func(): closed.emit(false)])
	_set_buttons(opts)


func _do(action: Callable) -> void:
	if action.call():
		campaign.save()
		_show_camp()
	else:
		_show_camp("You can't afford that right now.")


# --- Building --------------------------------------------------------------------

## The list of things to build; picking one shows what it does and its price.
func _show_build(picked: String) -> void:
	var c = campaign
	var ups: Dictionary = db.camp["upgrades"]
	if picked != "":
		var u: Dictionary = ups[picked]
		Style.fit_text(text_label, "%s\n%s" % [u["name"], u["text"]])
		_set_buttons([["Build (%dg)" % u["cost"], func():
			if c.build(picked):
				c.save()
				_show_camp("The band builds %s." % u["name"])
			else:
				_show_camp("You can't afford that right now."), c.can_build(picked)],
			["Back", _show_build.bind("")]])
		return
	var left: Array = ups.keys().filter(func(id): return c.built(id) < int(ups[id].get("max", 1)))
	Style.fit_text(text_label, "Gold %d. What shall the band build?" % c.gold if not left.is_empty() else "The camp has everything it could want!")
	var opts := []
	for id in left:
		opts.append(["%s %dg" % [ups[id]["short"], ups[id]["cost"]], _show_build.bind(id)])
	opts.append(["Back", _show_camp.bind("")])
	_set_buttons(opts)


# --- Visitors and evenings ---------------------------------------------------------

func _show_visitor() -> void:
	var v: Dictionary = db.camp["visitors"][campaign.visitor]
	Style.fit_text(text_label, v["text"])
	_show_options(v["options"], func(i): return campaign.answer_visitor(i), func(): _show_camp())


func _rest() -> void:
	var c = campaign
	c.rest()
	night = true
	_draw_scene()
	title_label.text = "Evening at the Major Oak"
	if c.evening == "":
		Style.fit_text(text_label, "The band sleeps soundly under the Major Oak.")
		_set_buttons([["Sleep", _sleep]])
		return
	var e: Dictionary = db.camp["evenings"][c.evening]
	Style.fit_text(text_label, e["text"])
	if c.evening_open:
		_show_options(e["options"], func(i): return c.choose_evening(i), _sleep)
	else:
		_set_buttons([["Sleep", _sleep]])


func _sleep() -> void:
	closed.emit(true)


## Choice buttons for a visitor or an evening; after one is taken, its story and a button to go on.
func _show_options(options: Array, take: Callable, after: Callable) -> void:
	var opts := []
	for i in options.size():
		var o: Dictionary = options[i]
		var label: String = o["label"]
		if o.has("cost") and not label.contains("g)"):
			label += " (%dg)" % o["cost"]
		opts.append([label, func():
			var told: String = take.call(i)
			if told == "":
				Style.fit_text(text_label, "You can't afford that right now.")
				return
			campaign.save()
			Style.fit_text(text_label, told)
			_set_buttons([["Sleep" if night else "Go on", after]]), campaign.can_take(o)])
	_set_buttons(opts, 1)
