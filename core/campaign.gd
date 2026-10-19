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
const PARTY_SIZE := 4
const STAT_KEYS := ["hp", "atk", "def", "spd", "crit"]

var db
var map: Dictionary
var rng := RandomNumberGenerator.new()

var day := 1
var gold := 0
var supplies := 0
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
var merry_men := {}                # hired hero id -> name
var equipment := {}                # hero id -> {slot: item id}
var econ: Dictionary


func _init(game_data, seed_value: int) -> void:
	db = game_data
	map = db.map
	econ = db.economy
	rng.seed = seed_value
	gold = int(econ["starting_gold"])
	supplies = int(econ["supplies"]["start"])
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


## Everyone in the band who isn't captured: the named heroes first, then hired Merry Men.
func free_heroes() -> Array:
	var ids: Array = STARTING_HEROES + merry_men.keys()
	return ids.filter(func(h): return heroes.has(h) and not captured.has(h)).map(func(h): return heroes[h])


## Who goes on the next job: the first four free members. Merry Men fill gaps left by captured heroes.
func party() -> Array:
	return free_heroes().slice(0, PARTY_SIZE)


func hero_name(id: String) -> String:
	return merry_men[id] if merry_men.has(id) else db.heroes[id]["name"]


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
	return MissionRun.new(db, missions[location], party())


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
				_news("%s is free and back with the band!" % hero_name(h))
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
		_news("%s was captured at %s." % [hero_name(h), node(location)["name"]])
		_post_rescue(h, location)
	if free_heroes().is_empty():
		_news("The whole band is captured! Friends in Sherwood break them out by night.")
		for h in captured.keys():
			captured.erase(h)
		_remove_rescues()
		location = "camp"
		gold = gold / 2


# --- Spending gold -----------------------------------------------------------

func _spend(cost: int) -> bool:
	if cost <= 0 or gold < cost:
		return false
	gold -= cost
	return true


func can_give() -> bool:
	return node(location)["kind"] in ["village", "town"]


## Robin's calling: hand gold to the poor here. Raises reputation and loosens the Sheriff's grip.
func give_to_poor(amount: int) -> bool:
	if not can_give() or not _spend(amount):
		return false
	var region: String = node(location)["region"]
	reputation += int(round(amount * float(econ["reputation_per_gold"])))
	control[region] = maxi(0, control[region] - int(round(amount * float(econ["control_per_gold"]))))
	_news("The band gives %d gold to the poor of %s." % [amount, node(location)["name"]])
	return true


func can_buy_supplies() -> bool:
	return location == "camp" or can_give()


func buy_supplies() -> bool:
	if not can_buy_supplies() or not _spend(int(econ["supplies"]["price"])):
		return false
	supplies += int(econ["supplies"]["bundle"])
	return true


## Days of food and arrows left for the whole band.
func supply_days() -> int:
	var per_day: int = maxi(1, free_heroes().size() * int(econ["supplies"]["per_member_per_day"]))
	return supplies / per_day


func items_for(hero_id: String) -> Array:
	var cls: String = heroes[hero_id].cls
	return db.items.keys().filter(func(i): return db.items[i]["classes"].is_empty() or db.items[i]["classes"].has(cls))


## Buys gear at camp and equips it at once, replacing whatever was in that slot.
func buy_item(hero_id: String, item_id: String) -> bool:
	if location != "camp" or not heroes.has(hero_id) or captured.has(hero_id) or not items_for(hero_id).has(item_id):
		return false
	var item: Dictionary = db.items[item_id]
	if equipment.get(hero_id, {}).get(item["slot"], "") == item_id or not _spend(int(item["price"])):
		return false
	if not equipment.has(hero_id):
		equipment[hero_id] = {}
	equipment[hero_id][item["slot"]] = item_id
	_apply_gear(hero_id)
	return true


## Recomputes a hero's stats from their base data plus equipped gear, keeping damage taken.
func _apply_gear(hero_id: String) -> void:
	var u = heroes[hero_id]
	var base: Dictionary = db.heroes["merry_man" if merry_men.has(hero_id) else hero_id]
	var stats := {}
	for k in STAT_KEYS:
		stats[k] = float(base[k])
	for slot in equipment.get(hero_id, {}):
		var bonus: Dictionary = db.items[equipment[hero_id][slot]]["bonus"]
		for k in bonus:
			stats[k] += float(bonus[k])
	var damage: int = u.max_hp - u.hp
	u.max_hp = int(stats["hp"])
	u.hp = maxi(1, u.max_hp - damage)
	u.atk = int(stats["atk"])
	u.def = int(stats["def"])
	u.spd = int(stats["spd"])
	u.crit = stats["crit"]


func can_hire() -> bool:
	var mm: Dictionary = econ["merry_men"]
	return location == "camp" and reputation >= int(mm["min_reputation"]) and merry_men.size() < int(mm["max"])


func hire_merry_man() -> bool:
	if not can_hire() or not _spend(int(econ["merry_men"]["price"])):
		return false
	var names: Array = econ["merry_men"]["names"].filter(func(n): return not merry_men.values().has(n))
	var id := "merry_man_%d" % (merry_men.size() + 1)
	while heroes.has(id):
		id += "_"
	merry_men[id] = names[rng.randi_range(0, names.size() - 1)]
	heroes[id] = _make_merry_man(id)
	_news("%s joins the band." % merry_men[id])
	return true


func _make_merry_man(id: String):
	var u = db.make_hero("merry_man")
	u.id = id
	u.name = merry_men[id]
	return u


func informant_cost() -> int:
	return int(econ["informant"]["base"] + threat(location) * float(econ["informant"]["per_threat"]))


func can_pay_informant() -> bool:
	return missions.has(location) and missions[location]["type"] == "robbery" and not missions[location].get("informed", false)


## Pays a local to say whether the job here is honest or bait.
func pay_informant() -> bool:
	if not can_pay_informant() or not _spend(informant_cost()):
		return false
	var m: Dictionary = missions[location]
	m["informed"] = true
	if m["bait"].is_empty():
		_news("An informant swears the %s job is honest." % node(location)["name"])
	else:
		m["bait"]["revealed"] = true
		_news("An informant whispers that the %s job is %s's trap!" % [node(location)["name"], db.baits[m["bait"]["by"]]["name"]])
	return true


func prisoners_here() -> Array:
	return captured.keys().filter(func(h): return captured[h]["node"] == location)


func jailer_cost() -> int:
	var j: Dictionary = econ["jailer"]
	var cost: int = int(j["base"]) + int(j["per_prisoner"]) * prisoners_here().size()
	return cost * int(j["dungeon_multiplier"]) if location == DUNGEON else cost


## Bribes the jailer to let everyone held here slip out, no fight needed.
func bribe_jailer() -> bool:
	var held := prisoners_here()
	if held.is_empty() or not _spend(jailer_cost()):
		return false
	for h in held:
		captured.erase(h)
		_news("A bribed jailer looks the other way. %s is free!" % hero_name(h))
	if missions.has(location) and missions[location].has("rescue_heroes"):
		missions.erase(location)
	return true


# --- The day passes: villains act -------------------------------------------

func _end_day(resting: bool) -> void:
	day += 1
	var band := free_heroes()
	var needed: int = band.size() * int(econ["supplies"]["per_member_per_day"])
	var fed := supplies >= needed
	supplies = maxi(0, supplies - needed)
	if not fed:
		_news("The band has run out of food and arrows. Everyone grows weak.")
	for h in band:
		h.statuses.clear()
		if fed:
			h.heal(int(ceil(h.max_hp * (HEAL_AT_CAMP if resting else HEAL_ON_ROAD))))
		else:
			h.hp = maxi(1, h.hp - int(ceil(h.max_hp * float(econ["supplies"]["hunger_damage"]))))
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
		var targets := free_heroes().filter(func(h): return STARTING_HEROES.has(h.id) and h.id != "robin")
		if not targets.is_empty():
			hunted_hero = targets[rng.randi_range(0, targets.size() - 1)].id
			_news("Sir Guy of Gisborne is hunting %s." % hero_name(hunted_hero))
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
				_news("%s has been taken to the dungeon in Nottingham." % hero_name(h))
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
	m["name"] = "Rescue %s" % hero_name(hero_id)
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
		"missions": missions, "news": news, "rng_state": str(rng.state),
		"supplies": supplies, "merry_men": merry_men, "equipment": equipment}


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
	c.supplies = int(data["supplies"])
	c.merry_men = data["merry_men"]
	for id in c.merry_men:
		c.heroes[id] = c._make_merry_man(id)
	c.equipment = data["equipment"]
	for h in c.heroes:
		c._apply_gear(h)
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
