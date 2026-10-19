## Procedural mission generator. A mission is plain data: a linear list of nodes the band walks through.
## The Sheriff and Guy act as directors: some robberies are really bait they have set up, and the higher
## the threat, the more often that happens. Bait missions look normal until the band reaches the prize.
extends RefCounted

## Rough "threat points" per enemy, used to spend a node's difficulty budget.
const ENEMY_COST := {"man_at_arms": 3, "crossbowman": 3, "knight": 6, "forester": 3, "tax_collector": 1, "hound": 2, "guy": 12}

var db
var rng := RandomNumberGenerator.new()


func _init(game_data) -> void:
	db = game_data


## type: "robbery" or "rescue". threat: 0-100 (the region's Sheriff control plus infamy).
## hunted_hero: the hero Guy is currently hunting; his net traps target them.
func generate(type: String, threat: int, seed_value: int, location_id := "", hunted_hero := "") -> Dictionary:
	rng.seed = seed_value
	var tpl: Dictionary = db.mission_templates[type]
	if location_id == "":
		var options: Array = db.locations.keys().filter(func(l): return db.locations[l]["missions"].has(type))
		location_id = options[rng.randi_range(0, options.size() - 1)]
	var loc: Dictionary = db.locations[location_id]
	var names: Array = tpl["names"]

	var nodes := []
	for slot in tpl["nodes"]:
		var kinds: Array = slot.split("|")
		nodes.append(_make_node(kinds[rng.randi_range(0, kinds.size() - 1)], loc, threat, type))

	var bait := {}
	if type == "robbery" and rng.randf() < bait_chance(threat):
		bait = {"by": "guy" if rng.randf() < 0.5 else "sheriff", "revealed": false}
		_set_bait(nodes, bait["by"], hunted_hero)

	var gold := int(tpl["base_gold"] * (1.0 + threat / 100.0))
	return {
		"bait": bait,
		"seed": seed_value,
		"type": type,
		"name": names[rng.randi_range(0, names.size() - 1)],
		"location": location_id,
		"location_name": loc["name"],
		"threat": threat,
		"nodes": nodes,
		"rewards": {"gold": gold, "reputation": int(tpl.get("reputation", 0))},
	}


## Builds a hand-written story mission from data/stories.json. Story missions have no traps or bait.
func story(story_id: String, threat: int, seed_value: int) -> Dictionary:
	var st: Dictionary = db.stories["stories"][story_id]
	# JSON numbers load as floats; keep counts as ints so a saved mission reloads identically.
	var rewards := {}
	for k in st["rewards"]:
		rewards[k] = int(st["rewards"][k])
	var nodes: Array = st["nodes"].duplicate(true)
	for n in nodes:
		for opt in n.get("options", []):
			for k in ["gold", "reputation"]:
				if opt.has(k):
					opt[k] = int(opt[k])
	return {
		"bait": {},
		"seed": seed_value,
		"type": "story",
		"story": story_id,
		"name": st["name"],
		"intro": st["intro"],
		"recruit": st["recruit"],
		"location": st["backdrop"],
		"location_name": st["place"],
		"threat": threat,
		"nodes": nodes,
		"rewards": rewards,
	}


## Turns any generated robbery into bait set by the given villain (used when a villain's plot comes due).
func make_bait(mission: Dictionary, by: String, hunted_hero: String) -> void:
	for n in mission["nodes"]:
		n.erase("trap")
	mission["bait"] = {"by": by, "revealed": false}
	_set_bait(mission["nodes"], by, hunted_hero)


## Chance that a robbery is really a trap. Grows with the Sheriff's grip on the region.
static func bait_chance(threat: int) -> float:
	return 0.15 + threat / 250.0


## Turns a robbery into bait: the prize is a decoy guarding an ambush, the chase home is certain,
## and the villain plants their own traps along the way.
func _set_bait(nodes: Array, by: String, hunted_hero: String) -> void:
	var b: Dictionary = db.baits[by]
	for n in nodes:
		if n["kind"] == "objective":
			n["text"] = b["reveal"]
			n["enemies"] = b["ambush"].duplicate()
			n["loot"] = false
			n["ambush"] = true
		elif n.get("is_escape", false):
			n["kind"] = "combat"
			n["text"] = "They give chase!"
			n["enemies"] = b["pursuers"].duplicate()
	var owned: Array = db.traps.keys().filter(func(t): return db.traps[t]["owner"] == by)
	var count := 1 + rng.randi_range(0, 1)
	var candidates := []
	for i in nodes.size():
		if nodes[i]["kind"] != "approach":
			candidates.append(i)
	for _n in count:
		if candidates.is_empty():
			return
		var node: Dictionary = nodes[candidates.pop_at(rng.randi_range(0, candidates.size() - 1))]
		var options := owned.filter(func(t): return _trap_fits(t, node))
		if options.is_empty():
			continue
		var trap_id: String = options[rng.randi_range(0, options.size() - 1)]
		node["trap"] = {"id": trap_id, "revealed": false, "target": hunted_hero if db.traps[trap_id].get("targets", "") == "hunted" else ""}


func _make_node(kind: String, loc: Dictionary, threat: int, mission_type: String) -> Dictionary:
	match kind:
		"approach":
			return {"kind": "approach", "text": "The band creeps toward %s." % loc["name"]}
		"combat":
			return {"kind": "combat", "text": "Guards block the way.", "enemies": _buy_enemies(loc, 6 + threat / 10)}
		"choice":
			return {"kind": "choice", "text": "A lone sentry dozes by the road.",
				"options": [
					{"label": "Sneak past", "result": "sneak"},
					{"label": "Knock him out", "result": "fight", "enemies": _buy_enemies(loc, 3)},
				]}
		"hazard":
			return {"kind": "hazard", "text": "The path narrows between thick brambles."}
		"objective_loot":
			var guards := _buy_enemies(loc, 7 + threat / 8)
			if loc["enemy_pool"].has("tax_collector") and not guards.has("tax_collector") and guards.size() < 5:
				guards.append("tax_collector")
			return {"kind": "objective", "text": "The wagon, and its guards.", "enemies": guards, "loot": true}
		"objective_prisoner":
			return {"kind": "objective", "text": "The prisoner is under guard.", "enemies": _buy_enemies(loc, 8 + threat / 8), "prisoner": true}
		"escape":
			var pursuers := _buy_enemies(loc, 3 + threat / 15) if rng.randf() < 0.3 + threat / 200.0 else []
			return {"kind": "escape" if pursuers.is_empty() else "combat", "text": "Back to the greenwood!" if pursuers.is_empty() else "Riders give chase!", "enemies": pursuers, "is_escape": true}
	push_error("Unknown node kind " + kind)
	return {}


## Buys enemies from the location's pool until the threat budget is spent (always at least one, at most five).
func _buy_enemies(loc: Dictionary, budget: int) -> Array:
	var pool: Array = loc["enemy_pool"]
	var out := []
	while out.size() < 5:
		var affordable := pool.filter(func(e): return ENEMY_COST[e] <= budget)
		if affordable.is_empty():
			break
		var pick: String = affordable[rng.randi_range(0, affordable.size() - 1)]
		out.append(pick)
		budget -= ENEMY_COST[pick]
	if out.is_empty():
		out.append(pool[0])
	return out


func _trap_fits(trap_id: String, node: Dictionary) -> bool:
	match db.traps[trap_id]["effect"]:
		"ambush":
			return node.has("enemies") and not node["enemies"].is_empty()
	return true
