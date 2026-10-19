## Renders the battle scene and saves a PNG: godot --path . -s tests/screenshot.gd -- out.png
extends SceneTree

func _init() -> void:
	var scene = load("res://scenes/battle/battle_scene.tscn").instantiate()
	root.add_child(scene)
	for i in 120:
		await process_frame
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://battle.png"
	root.get_viewport().get_texture().get_image().save_png(out)
	quit()
