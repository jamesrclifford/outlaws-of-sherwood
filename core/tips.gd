## The tutorial: short tips, each shown once the first time a player meets something new.
## Which ones have been seen is kept in a small settings file, not in the campaign, so a new
## campaign does not repeat them. The text lives in data/tips.json.
extends RefCounted

const SAVE_PATH := "user://tips.cfg"

var path: String
var tips: Dictionary
var seen: Array = []
var enabled := true


func _init(save_path := SAVE_PATH) -> void:
	path = save_path
	var f := FileAccess.open("res://data/tips.json", FileAccess.READ)
	tips = JSON.parse_string(f.get_as_text())["tips"]
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		seen = cfg.get_value("tips", "seen", [])
		enabled = cfg.get_value("tips", "enabled", true)


## The tip to show for id, once: empty when it was seen, tips are off, or there is no such tip.
func take(id: String) -> Dictionary:
	if not enabled or seen.has(id) or not tips.has(id):
		return {}
	seen.append(id)
	_save()
	return tips[id]


## "No more tips": the rest of the tutorial is skipped.
func turn_off() -> void:
	enabled = false
	_save()


## Shows the whole tutorial again from the start.
func reset() -> void:
	seen.clear()
	enabled = true
	_save()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("tips", "seen", seen)
	cfg.set_value("tips", "enabled", enabled)
	cfg.save(path)
