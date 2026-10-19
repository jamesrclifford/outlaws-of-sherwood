## Loads the JSON content files and builds battles from them.
extends RefCounted

const Unit = preload("res://core/unit.gd")
const Battle = preload("res://core/battle.gd")

var abilities: Dictionary
var heroes: Dictionary
var enemies: Dictionary
var encounters: Dictionary


func _init() -> void:
	abilities = _load("res://data/abilities.json")
	heroes = _load("res://data/heroes.json")
	enemies = _load("res://data/enemies.json")
	encounters = _load("res://data/encounters.json")


static func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	assert(parsed is Dictionary, "Could not parse " + path)
	return parsed


func make_battle(hero_ids: Array, encounter_id: String, seed_value: int):
	var b = Battle.new(abilities, enemies, seed_value)
	for h in hero_ids:
		b.add_unit(Unit.from_data(h, heroes[h], "heroes"))
	for e in encounters[encounter_id]["enemies"]:
		b.add_unit(Unit.from_data(e, enemies[e], "enemies"))
	return b
