## Drives the spending buttons on the real map screen: armory, giving, supplies, hiring, informant, jailer.
## godot --headless --path . -s tests/shop_smoke.gd   (pass a PNG path after -- to save screenshots)
extends SceneTree

const MapView = preload("res://scenes/map/map_view.gd")
const GameData = preload("res://core/game_data.gd")
const Campaign = preload("res://core/campaign.gd")

var shot := ""
var fails := 0


func _press(container: Node, prefix: String) -> bool:
	for b in container.find_children("*", "Button", true, false):
		if not b.is_queued_for_deletion() and b.text.begins_with(prefix):
			b.pressed.emit()
			return true
	printerr("SCRIPT ERROR: no button starting with '%s'" % prefix)
	fails += 1
	return false


func _snap(tag: String) -> void:
	await process_frame
	await process_frame
	if shot != "":
		root.get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_%s.png" % tag))


func _init() -> void:
	shot = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else ""
	var db = GameData.new()
	var c = Campaign.new(db, 99, ["robin", "little_john", "will", "tuck"])
	c.gold = 600
	c.reputation = 12
	var view := MapView.new()
	view.start(db, c)
	root.add_child(view)
	await _snap("camp")

	_press(view.buttons, "Armory")
	await _snap("armory_band")
	var armory: Node = view.get_node("Armory")
	_press(armory, "Robin Hood")
	await process_frame
	armory = view.get_node("Armory")
	_press(armory, "Yew Longbow")
	await process_frame
	await _snap("armory")
	_press(view.get_node("Armory"), "Leave the armory")
	await process_frame
	print("Robin's attack with a longbow: %d (base 9), gold %d" % [c.heroes["robin"].atk, c.gold])

	_press(view.buttons, "Hire a Merry Man")
	_press(view.buttons, "Buy 10 supplies")
	print("Merry Men: %s, supplies %d, gold %d" % [c.merry_men.values(), c.supplies, c.gold])

	view._select("edwinstowe")
	_press(view.buttons, "Travel here")
	while view.busy:
		await process_frame
	_press(view.buttons, "Give to the poor")
	_press(view.buttons, "Give 50 gold")
	print("After giving: reputation %d, gold %d" % [c.reputation, c.gold])

	c.captured["will"] = {"node": "edwinstowe", "since": c.day}
	c._post_rescue("will", "edwinstowe")
	view._select("edwinstowe")
	await _snap("village")
	_press(view.buttons, "Bribe the jailer")
	print("After bribe: captured %s, gold %d" % [c.captured.keys(), c.gold])
	if c.heroes["robin"].atk != 11 or c.merry_men.is_empty() or not c.captured.is_empty():
		printerr("SCRIPT ERROR: spending through the UI did not take effect")
	quit(1 if fails > 0 else 0)
