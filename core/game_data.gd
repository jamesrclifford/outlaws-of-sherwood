## Loads the JSON content files and builds battles from them.
extends RefCounted

const Unit = preload("res://core/unit.gd")
const Battle = preload("res://core/battle.gd")

var abilities: Dictionary
var heroes: Dictionary
var enemies: Dictionary
var encounters: Dictionary
var locations: Dictionary
var mission_templates: Dictionary
var traps: Dictionary
var baits: Dictionary
var map: Dictionary
var items: Dictionary
var economy: Dictionary
var stories: Dictionary


func _init() -> void:
	abilities = _load("res://data/abilities.json")
	heroes = _load("res://data/heroes.json")
	enemies = _load("res://data/enemies.json")
	encounters = _load("res://data/encounters.json")
	locations = _load("res://data/locations.json")
	mission_templates = _load("res://data/mission_templates.json")
	traps = _load("res://data/traps.json")
	baits = _load("res://data/baits.json")
	map = _load("res://data/map.json")
	items = _load("res://data/items.json")
	economy = _load("res://data/economy.json")
	stories = _load("res://data/stories.json")
	# Tales from the legends (data/tales.json) are story missions that recruit nobody.
	var tales: Dictionary = _load("res://data/tales.json")["tales"]
	for id in tales:
		tales[id]["recruit"] = ""
		stories["stories"][id] = tales[id]


static func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	assert(parsed is Dictionary, "Could not parse " + path)
	return parsed


func make_hero(hero_id: String):
	return Unit.from_data(hero_id, heroes[hero_id], "heroes")


func make_battle(hero_ids: Array, encounter_id: String, seed_value: int):
	return make_custom_battle(hero_ids.map(func(h): return make_hero(h)), encounters[encounter_id]["enemies"], seed_value)


## Builds a battle around existing hero units, so HP and statuses carry over between mission nodes.
func make_custom_battle(hero_units: Array, enemy_ids: Array, seed_value: int):
	var b = Battle.new(abilities, enemies, seed_value)
	for h in hero_units:
		h.ap = 0
		h.statuses.erase("defending")
		h.statuses.erase("taunt")
		b.add_unit(h)
	for e in enemy_ids:
		b.add_unit(Unit.from_data(e, enemies[e], "enemies"))
	return b
