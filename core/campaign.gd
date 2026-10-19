## The persistent campaign: the strategic map, the calendar, the band's resources, and the Sheriff and
## Guy acting each day. Pure rules with no UI, saved as a plain dictionary.
extends RefCounted

const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")

const STARTING_HEROES := ["robin", "little_john", "will", "tuck"]
const MISSION_LIFETIME := 5        # days a job stays on the map
const RESCUE_DEADLINE := 6         # days before a prisoner is moved to Nottingham's dungeon
const DUNGEON := "nottingham"
const HEAL_AT_CAMP := 1.0          # fraction of max HP restored per day resting at camp
const HEAL_ON_ROAD := 0.15

var db
var map: Dictionary
var rng := RandomNumberGenerator.new()

var day := 1
var gold := 30
var reputation := 0
var infamy := 0
var location := "camp"
var control := {}                  # region -> Sheriff's control, 0-100
var plots := {"sheriff": 0, "guy": 0}   # villain plot meters, 0-100
var hunted_hero := ""
var heroes := {}                   # hero id -> Unit (HP persists)
var captured := {}                 # hero id -> {"node": id, "since": day}
var missions := {}                 # node id -> mission dictionary (with "expires")
var news: Array = []               # what happened, newest last


func _init(game_data, seed_value: int) -> void:
	db = game_data
	map = db.map
	rng.seed = seed_value
	for r in map["regions"]:
		control[r] = int(map["regions"][r]["start_control"])
	for h in STARTING_HEROES:
		heroes[h] = db.make_hero(h)
	for _i in 3:
		_spawn_mission()


func _news(text: String) -> void:
	news.append("Day %d: %s" % [day, text])


# --- Map queries -------------------------------------------------------------

func node(id: String) -> Dictionary:
	return map["nodes"][id]


## Threat of a place: the Sheriff's grip on its region, plus the band's infamy.
func threat(node_id: String) -> int:
	return clampi(int(control[node(node_id)["region"]]) + infamy / 2, 0, 100)


## Shortest route as a list of node ids, excluding the start. Empty if already there.
func route(to: String) -> Array:
	var prev := {location: ""}
	var queue := [location]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == to:
			break
		for n in node(cur)["links"]:
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	var path := []
	var step := to
	while step != location and prev.has(step):
		path.push_front(step)
		step = prev[step]
	return path


func free_heroes() -> Array:
	return STARTING_HEROES.filter(func(h): return heroes.has(h) and not captured.has(h)).map(func(h): return heroes[h])


# --- Actions -----------------------------------------------------------------

## Moves the band one day at a time along the route. Returns the nodes visited.
func travel(to: String) -> Array:
	var path := route(to)
	for step in path:
		location = step
		_end_day(false)
	return path


## Spend a day at camp: heal everyone fully.
func rest() -> void:
	if location == "camp":
		_end_day(true)


## Builds the mission waiting at the band's current location, ready to play.
func start_mission():
	if not missions.has(location) or free_heroes().is_empty():
		return null
	return MissionRun.new(db, missions[location], free_heroes())


## Applies a finished mission's results to the campaign.
func finish_mission(run) -> void:
	var m: Dictionary = run.mission
	var region: String = node(location)["region"]
	missions.erase(location)
	match run.result:
		"success":
			gold += run.gold
			reputation += run.reputation
			for h in m.get("rescue_heroes", []):
				captured.erase(h)
				_news("%s is free and back with the band!" % db.heroes[h]["name"])
			if m["type"] == "robbery" and not run.is_bait():
				infamy = mini(100, infamy + 6)
				control[region] = maxi(0, control[region] - 8)
			elif run.is_bait():
				infamy = mini(100, infamy + 3)
				plots[m["bait"]["by"]] = maxi(0, plots[m["bait"]["by"]] - 30)
				_news("The band escaped %s's trap." % db.baits[m["bait"]["by"]]["name"])
			else:
				control[region] = maxi(0, control[region] - 5)
		"failed":
			control[region] = mini(100, control[region] + 5)
			reputation = maxi(0, reputation - 2)
	for h in run.captured:
		captured[h] = {"node": location, "since": day}
		_news("%s was captured at %s." % [db.heroes[h]["name"], node(location)["name"]])
		_post_rescue(h, location)
	if free_heroes().is_empty():
		_news("The whole band is captured! Friends in Sherwood break them out by night.")
		for h in captured.keys():
			captured.erase(h)
		_remove_rescues()
		location = "camp"
		gold = gold / 2


# --- The day passes: villains act -------------------------------------------

func _end_day(resting: bool) -> void:
	day += 1
	for h in free_heroes():
		h.statuses.clear()
		h.heal(int(ceil(h.max_hp * (HEAL_AT_CAMP if resting else HEAL_ON_ROAD))))
	for id in missions.keys():
		if not missions[id].has("rescue_heroes") and missions[id]["expires"] < day:
			missions.erase(id)
	_sheriff_acts()
	_guy_acts()
	_move_prisoners()
	if rng.randf() < 0.6 or missions.size() < 2:
		_spawn_mission()


func _sheriff_acts() -> void:
	var regions: Array = control.keys()
	var r: String = regions[rng.randi_range(0, regions.size() - 1)]
	if rng.randf() < 0.5:
		control[r] = mini(100, control[r] + 1)
	plots["sheriff"] = mini(100, plots["sheriff"] + 6 + infamy / 10)
	if plots["sheriff"] >= 100:
		plots["sheriff"] = 0
		control[r] = mini(100, control[r] + 10)
		_news("The Sheriff raises taxes in %s and sends a rich wagon down the road. Too rich, perhaps..." % map["regions"][r]["name"])
		_spawn_mission("robbery", "sheriff")


func _guy_acts() -> void:
	plots["guy"] = mini(100, plots["guy"] + 5 + infamy / 8)
	if plots["guy"] >= 100:
		plots["guy"] = 0
		var targets := free_heroes().filter(func(h): return h.id != "robin")
		if not targets.is_empty():
			hunted_hero = targets[rng.randi_range(0, targets.size() - 1)].id
			_news("Sir Guy of Gisborne is hunting %s." % db.heroes[hunted_hero]["name"])
		_spawn_mission("robbery", "guy")


## Prisoners left too long are taken to Nottingham's dungeon, which is much harder to break into.
func _move_prisoners() -> void:
	var due := {}
	for h in captured:
		var c: Dictionary = captured[h]
		if c["node"] != DUNGEON and day - int(c["since"]) >= RESCUE_DEADLINE:
			due[c["node"]] = true
	for at in due:
		missions.erase(at)
		for h in captured:
			if captured[h]["node"] == at:
				captured[h]["node"] = DUNGEON
				_news("%s has been taken to the dungeon in Nottingham." % db.heroes[h]["name"])
				_post_rescue(h, DUNGEON)


# --- Jobs on the map ---------------------------------------------------------

## Posts a new job at a random free place. forced_bait makes a robbery that is a trap set by that villain.
func _spawn_mission(force_type := "", forced_bait := "") -> void:
	var free_nodes: Array = map["nodes"].keys().filter(func(n): return n != "camp" and not missions.has(n) and node(n).has("location"))
	if free_nodes.is_empty():
		return
	var gen = MissionGen.new(db)
	for _attempt in 10:
		var n: String = free_nodes[rng.randi_range(0, free_nodes.size() - 1)]
		var loc: String = node(n)["location"]
		var types: Array = db.locations[loc]["missions"].filter(func(t): return force_type == "" or t == force_type)
		if types.is_empty():
			continue
		var t: String = types[rng.randi_range(0, types.size() - 1)]
		var m: Dictionary = gen.generate(t, threat(n), rng.randi(), loc, hunted_hero)
		if forced_bait != "":
			gen.make_bait(m, forced_bait, hunted_hero)
		m["expires"] = day + MISSION_LIFETIME
		missions[n] = m
		return


## Posts (or extends) a rescue job where a hero is held. One job frees everyone held there.
func _post_rescue(hero_id: String, at: String) -> void:
	if missions.has(at) and missions[at].has("rescue_heroes"):
		missions[at]["rescue_heroes"].append(hero_id)
		missions[at]["name"] = "Rescue the prisoners"
		return
	var gen = MissionGen.new(db)
	var extra := 25 if at == DUNGEON else 0
	var m: Dictionary = gen.generate("rescue", mini(100, threat(at) + extra), rng.randi(), node(at)["location"], hunted_hero)
	m["rescue_heroes"] = [hero_id]
	m["expires"] = 0
	m["name"] = "Rescue %s" % db.heroes[hero_id]["name"]
	missions[at] = m


func _remove_rescues() -> void:
	for n in missions.keys():
		if missions[n].has("rescue_heroes"):
			missions.erase(n)


# --- Save / load -------------------------------------------------------------

func to_dict() -> Dictionary:
	var hp := {}
	for h in heroes:
		hp[h] = heroes[h].hp
	return {"day": day, "gold": gold, "reputation": reputation, "infamy": infamy, "location": location,
		"control": control, "plots": plots, "hunted_hero": hunted_hero, "hero_hp": hp, "captured": captured,
		"missions": missions, "news": news, "rng_state": str(rng.state)}


static func from_dict(game_data, data: Dictionary):
	var c = load("res://core/campaign.gd").new(game_data, 0)
	c.day = int(data["day"])
	c.gold = int(data["gold"])
	c.reputation = int(data["reputation"])
	c.infamy = int(data["infamy"])
	c.location = data["location"]
	c.hunted_hero = data["hunted_hero"]
	for r in data["control"]:
		c.control[r] = int(data["control"][r])
	for p in data["plots"]:
		c.plots[p] = int(data["plots"][p])
	for h in data["hero_hp"]:
		c.heroes[h].hp = int(data["hero_hp"][h])
	c.captured = data["captured"]
	for h in c.captured:
		c.captured[h]["since"] = int(c.captured[h]["since"])
	c.missions = data["missions"]
	for n in c.missions:
		_fix_ints(c.missions[n])
	c.news = data["news"]
	c.rng.state = int(data["rng_state"])
	return c


## JSON turns every number into a float; mission code expects ints for these keys.
static func _fix_ints(m: Dictionary) -> void:
	for k in ["seed", "threat", "expires"]:
		if m.has(k):
			m[k] = int(m[k])
	for k in m["rewards"]:
		m["rewards"][k] = int(m["rewards"][k])


const SAVE_PATH := "user://campaign.json"


func save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_saved(game_data):
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return from_dict(game_data, data) if data is Dictionary else null
