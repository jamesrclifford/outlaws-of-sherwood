## The persistent campaign: the strategic map, the calendar, the band's resources, and the Sheriff and
## Guy acting each day. Pure rules with no UI, saved as a plain dictionary.
extends RefCounted

const MissionGen = preload("res://core/mission_gen.gd")
const MissionRun = preload("res://core/mission_run.gd")

## The whole named band, for tests and sandbox play. A real campaign starts with data/stories.json's
## start_band and wins the others over through story missions.
const FULL_BAND := ["robin", "little_john", "will", "tuck", "alan"]
const MISSION_LIFETIME := 5        # days a job stays on the map
const RESCUE_DEADLINE := 6         # days before a prisoner is moved to Nottingham's dungeon
const DUNGEON := "nottingham"
const STORY_RETRY := 3             # days before a legend the band failed or lost at the butts comes back
const RESCUE_GRIP := 5           # how much a freed prisoner (or any other honest job) loosens the Sheriff's grip
const HEAL_AT_CAMP := 1.0          # fraction of max HP restored per day resting at camp
const HEAL_ON_ROAD := 0.15
const PARTY_SIZE := 5
const MAX_TALES := 2               # tales that recruit nobody posted at once, so ordinary jobs still appear
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
var band: Array = []               # named heroes who have joined, in order of joining
var heroes := {}                   # hero id -> Unit (HP persists)
var captured := {}                 # hero id -> {"node": id, "since": day}
var missions := {}                 # node id -> mission dictionary (with "expires")
var news: Array = []               # what happened, newest last
var merry_men := {}                # hired hero id -> name
var equipment := {}                # hero id -> {slot: item id}
var stories_done: Array = []       # story ids finished
var story_retry := {}              # story id -> the day a failed or lost legend comes round again
var posted_wanted := 0             # the wanted level on the posters the Sheriff has put up
var poster_news := 0               # a new poster for the screen to show (its level), 0 when none
var ambush := {}                   # bounty hunters waiting on the road, until the fight is played
var flags: Array = []              # story choices that later stories depend on (Sir Richard's loan)
var upgrades: Array = []           # camp improvements built (data/camp.json)
var visitor := ""                  # someone waiting at camp to speak with the band
var visitor_until := 0             # the last day they will wait
var evening := ""                  # tonight's campfire evening, told when the band rests
var evening_open := false          # tonight's evening still waits for the band's choice
var econ: Dictionary


## band: the named heroes to start with; empty means the story start (data/stories.json).
func _init(game_data, seed_value: int, start_band: Array = []) -> void:
	db = game_data
	map = db.map
	econ = db.economy
	rng.seed = seed_value
	gold = int(econ["starting_gold"])
	supplies = int(econ["supplies"]["start"])
	for r in map["regions"]:
		control[r] = int(map["regions"][r]["start_control"])
	for h in (start_band if not start_band.is_empty() else db.stories["start_band"]):
		_join(h)
	_post_stories()
	for _i in 3:
		_spawn_mission()


func _join(hero_id: String) -> void:
	if not band.has(hero_id):
		band.append(hero_id)
		heroes[hero_id] = db.make_hero(hero_id)


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
	var ids: Array = band + merry_men.keys()
	return ids.filter(func(h): return heroes.has(h) and not captured.has(h)).map(func(h): return heroes[h])


## Who goes on the next job: the first five free members. Merry Men fill gaps left by captured heroes.
func party() -> Array:
	return free_heroes().slice(0, PARTY_SIZE)


func hero_name(id: String) -> String:
	return merry_men[id] if merry_men.has(id) else db.heroes[id]["name"]


# --- Actions -----------------------------------------------------------------

## Moves the band one day at a time along the route. Returns the nodes visited, which stop short
## if bounty hunters waylay the band (see ambush).
func travel(to: String) -> Array:
	var path := route(to)
	var visited := []
	for step in path:
		location = step
		visited.append(step)
		_end_day(false)
		if not ambush.is_empty() or _maybe_ambush():
			break
	return visited


## Spend a day at camp: heal everyone fully. Lying low lets the band's infamy cool off a little,
## and once Marian lives there she keeps watch, setting Sir Guy's raid plot back.
## Each night brings a campfire evening (see evening); one with options waits for choose_evening.
func rest() -> void:
	if location == "camp":
		infamy = maxi(0, infamy - int(econ["wanted"]["lie_low"]) * (1 + int(upgrade_sum("lie_low"))))
		supplies += int(upgrade_sum("rest_supplies"))
		_tell_evening()
		if marian_home():
			plots["guy"] = maxi(0, plots["guy"] - int(db.marian["home"]["rest_guy_plot"]))
			_news(db.marian["home"]["text"])
		_update_wanted()
		_end_day(true)


# --- Major Oak Camp ------------------------------------------------------------

## The total of one effect over every upgrade built (0 when none gives it).
func upgrade_sum(key: String) -> float:
	var total := 0.0
	for id in upgrades:
		total += float(db.camp["upgrades"][id].get(key, 0))
	return total


func can_build(id: String) -> bool:
	return location == "camp" and built(id) < int(db.camp["upgrades"][id].get("max", 1)) and gold >= int(db.camp["upgrades"][id]["cost"])


## How many of an upgrade the band has built (the Great Hall can be built more than once).
func built(id: String) -> int:
	return upgrades.count(id)


func build(id: String) -> bool:
	if not can_build(id) or not _spend(int(db.camp["upgrades"][id]["cost"])):
		return false
	upgrades.append(id)
	for h in heroes:
		_apply_gear(h)
	_news("The band builds %s at Major Oak Camp." % db.camp["upgrades"][id]["name"])
	return true


## Whether an evening or visitor can be told here: who it needs must be free in camp, and so on.
func _camp_ready(e: Dictionary) -> bool:
	var here: Array = free_heroes().map(func(h): return h.id)
	if not e.get("needs", []).all(func(h): return here.has(h)):
		return false
	if not e.get("flags", []).all(func(f): return flags.has(f)):
		return false
	if e.has("upgrade") and not upgrades.has(e["upgrade"]):
		return false
	if e.get("captured", false) and captured.is_empty():
		return false
	if e.get("marian", false) and (not marian_free() or marian_home()):
		return false
	return merry_men.size() >= int(e.get("merry_men", 0)) and plots["guy"] >= int(e.get("guy_plot", 0))


## Picks tonight's campfire evening, never the same as last night's. One without options happens at once.
func _tell_evening() -> void:
	var all: Dictionary = db.camp["evenings"]
	var ready: Array = all.keys().filter(func(id): return id != evening and _camp_ready(all[id]))
	if ready.is_empty():
		evening = ""
		evening_open = false
		return
	evening = ready[rng.randi_range(0, ready.size() - 1)]
	evening_open = all[evening].has("options")
	if not evening_open:
		_camp_effects(all[evening].get("effects", {}))


## Whether the band can take this option (it may cost gold).
func can_take(option: Dictionary) -> bool:
	return gold >= int(option.get("cost", 0))


## The band's choice for tonight's evening. Returns what happened, or "" if it can't be taken.
func choose_evening(i: int) -> String:
	if not evening_open:
		return ""
	var opt: Dictionary = db.camp["evenings"][evening]["options"][i]
	if not _take(opt):
		return ""
	evening_open = false
	return opt["log"]


## Now and then someone finds the way to camp, and waits a few days to be heard.
func _visitor_comes() -> void:
	if visitor != "" and day > visitor_until:
		visitor = ""
	if visitor != "" or rng.randf() >= float(db.camp["visitor_chance"]):
		return
	var all: Dictionary = db.camp["visitors"]
	var ready: Array = all.keys().filter(func(id): return _camp_ready(all[id]))
	if ready.is_empty():
		return
	visitor = ready[rng.randi_range(0, ready.size() - 1)]
	visitor_until = day + int(db.camp["visitor_days"])
	_news("%s has come to Major Oak Camp, asking for Robin Hood." % all[visitor]["name"])


## Answer the visitor waiting at camp. Returns what happened, or "" if the band can't do that.
func answer_visitor(i: int) -> String:
	if visitor == "" or location != "camp":
		return ""
	var opt: Dictionary = db.camp["visitors"][visitor]["options"][i]
	if not _take(opt):
		return ""
	visitor = ""
	return opt["log"]


func _take(opt: Dictionary) -> bool:
	var cost := int(opt.get("cost", 0))
	if cost > 0 and not _spend(cost):
		return false
	_camp_effects(opt.get("effects", {}))
	return true


func _camp_effects(e: Dictionary) -> void:
	gold += int(e.get("gold", 0))
	supplies = maxi(0, supplies + int(e.get("supplies", 0)))
	reputation += int(e.get("reputation", 0))
	infamy = maxi(0, infamy + int(e.get("infamy", 0)))
	for p in e.get("plots", {}):
		plots[p] = clampi(plots[p] + int(e["plots"][p]), 0, 100)
	if e.has("control"):
		control["sherwood"] = clampi(control["sherwood"] + int(e["control"]), 0, 100)
	if e.get("reveal", false):
		for m in missions.values():
			for n in m["nodes"]:
				if n.has("trap"):
					n["trap"]["revealed"] = true
			if not m.get("bait", {}).is_empty():
				m["bait"]["revealed"] = true
	if e.has("spawn"):
		_spawn_mission(e["spawn"])
	if e.get("merry_man", false):
		# With no room in camp he goes home a friend, and tells everyone.
		var names: Array = econ["merry_men"]["names"].filter(func(n): return not merry_men.values().has(n))
		if merry_men.size() < men_max() and not names.is_empty():
			_add_merry_man()
		else:
			reputation += 2
	if e.has("infamy"):
		_update_wanted()


# --- Wanted ------------------------------------------------------------------

## How hard the Sheriff is hunting the band: 0 (not yet) to 3, set by infamy.
func wanted_level() -> int:
	var level := 0
	for at in econ["wanted"]["infamy"]:
		if infamy >= int(at):
			level += 1
	return level


## The reward on the posters, in gold.
func bounty() -> int:
	return int(econ["wanted"]["bounty"][wanted_level()])


## Puts up new posters when infamy crosses a threshold; old ones fade when the band lies low.
func _update_wanted() -> void:
	var level := wanted_level()
	if level > posted_wanted:
		posted_wanted = level
		poster_news = level
		_news("Wanted posters go up across the shire: %d gold for Robin Hood! Bounty hunters are on the roads." % bounty())
	elif level < posted_wanted:
		posted_wanted = level
		_news("With the band lying low, the wanted posters fade. The bounty is now %d gold." % bounty())


## On the road (never at camp), bounty hunters may jump the band. The fight waits in ambush.
func _maybe_ambush() -> bool:
	var level := wanted_level()
	if level == 0 or location == "camp" or not ambush.is_empty() or free_heroes().is_empty():
		return false
	if rng.randf() >= float(econ["wanted"]["ambush_chance_per_level"]) * level:
		return false
	var n: Dictionary = node(location)
	var backdrop: String = n.get("location", "sherwood_edge")
	ambush = MissionGen.new(db).ambush(econ["wanted"]["hunters"][level], n["name"], backdrop, bounty(), rng.randi())
	_news("Bounty hunters waylay the band near %s!" % n["name"])
	return true


## The bounty hunters' fight, ready to play. Finish it with finish_mission like any job.
func start_ambush():
	if ambush.is_empty():
		return null
	return MissionRun.new(db, ambush, party())


## Builds the mission waiting at the band's current location, ready to play.
func start_mission():
	if not missions.has(location) or free_heroes().is_empty():
		return null
	var run = MissionRun.new(db, missions[location], party())
	run.known_disguises = known_disguises()
	run.purse = gold
	run.flags = flags.duplicate()
	var region: String = node(location)["region"]
	run.grip = {"region": map["regions"][region]["name"], "control": int(control[region]), "drop": RESCUE_GRIP}
	return run


## Disguises the band has learned by playing their legends (the potter, the beggar...).
func known_disguises() -> Array:
	return db.disguises.keys().filter(func(id): return stories_done.has(db.disguises[id]["legend"]))


## Applies a finished mission's results to the campaign.
func finish_mission(run) -> void:
	var m: Dictionary = run.mission
	var region: String = node(location)["region"]
	if m["type"] == "ambush":
		ambush = {}
	else:
		missions.erase(location)
	# Gold handed over in a story choice is gone whatever happens next, and remembered.
	gold = maxi(0, gold - run.spent)
	for f in run.flags:
		if not flags.has(f):
			flags.append(f)
	match run.result:
		"success":
			gold += run.gold
			reputation += run.reputation
			if m["type"] == "story":
				stories_done.append(m["story"])
				for id in db.disguises:
					if db.disguises[id]["legend"] == m["story"]:
						_news("New disguise learned from the legend: %s." % db.disguises[id]["name"])
				_news("%s: the band's legend grows." % m["name"])
				if run.recruited != "":
					_join(run.recruited)
					_news("%s joins the band!" % hero_name(run.recruited))
				_story_effects(db.stories["stories"][m["story"]].get("effects", {}))
			for h in m.get("rescue_heroes", []):
				captured.erase(h)
				_news("%s is free and back with the band!" % hero_name(h))
			if m["type"] == "robbery" and not run.is_bait():
				infamy = mini(100, infamy + 6)
				control[region] = maxi(0, control[region] - 8)
			elif m["type"] == "ambush":
				if m.has("raid"):
					_news("Sir Guy's raid is beaten off! The whole shire is talking about it.")
				else:
					_news("The bounty hunters limp home with sore heads." if run.gold > 0 else "The band gives the bounty hunters the slip.")
			elif m["type"] == "contest":
				_news("%s: the band comes home with %d gold." % [m["name"], run.gold] if run.gold > 0 else "%s: Robin shot well, but the purse went to another." % m["name"])
			elif run.is_bait():
				infamy = mini(100, infamy + 3)
				plots[m["bait"]["by"]] = maxi(0, plots[m["bait"]["by"]] - 30)
				_news("The band escaped %s's trap." % db.baits[m["bait"]["by"]]["name"])
			else:
				control[region] = maxi(0, control[region] - RESCUE_GRIP)
		"failed":
			control[region] = mini(100, control[region] + 5)
			reputation = maxi(0, reputation - 2)
		"outshot":
			reputation += run.reputation
	if m["type"] == "story" and run.result != "success":
		story_retry[m["story"]] = day + STORY_RETRY
		_news("%s will come round again in a few days." % m["name"])
	_update_wanted()
	var held_at: String = m.get("prison", location)
	for h in run.captured:
		captured[h] = {"node": held_at, "since": day}
		_news("%s was captured and is held at %s." % [hero_name(h), node(held_at)["name"]])
		_post_rescue(h, held_at)
	if free_heroes().is_empty():
		_news("The whole band is captured! Friends in Sherwood break them out by night.")
		for h in captured.keys():
			captured.erase(h)
		_remove_rescues()
		location = "camp"
		gold = gold / 2
	_post_stories()
	if run.scouted:
		# Scouting cost a day: food eaten, villains plotting, other jobs moving on, and no time to rest.
		_news("Scouting the job cost the band a day.")
		_end_day(false, false)


## What a big story changes on the map: "control" shifts the Sheriff's grip everywhere and
## "region_control" in one region, "plots" sets the villains' schemes back, "flags" are remembered.
## The finale sets infamy back to nothing, opens every cell and wipes the villains' plots.
func _story_effects(effects: Dictionary) -> void:
	if effects.has("infamy"):
		infamy = int(effects["infamy"])
	for r in control:
		control[r] = clampi(control[r] + int(effects.get("control", 0)) + int(effects.get("region_control", {}).get(r, 0)), 0, 100)
	for p in effects.get("plots", {}):
		plots[p] = clampi(plots[p] + int(effects["plots"][p]), 0, 100)
	for f in effects.get("flags", []):
		if not flags.has(f):
			flags.append(f)
	if effects.get("free_captured", false):
		for h in captured.keys():
			captured.erase(h)
			_news("%s is free and back with the band!" % hero_name(h))
		_remove_rescues()
	if effects.get("reset_plots", false):
		plots = {"sheriff": 0, "guy": 0}
		hunted_hero = ""


## Maid Marian can visit the band's jobs once they have met, unless Sir Guy has her in the tower.
func marian_free() -> bool:
	return stories_done.has("marian_page") and not missions.values().any(func(m): return m.get("story", "") == "marian_taken")


## After the wedding Maid Marian lives at Major Oak Camp.
func marian_home() -> bool:
	return flags.has("marian_wed")


## Every legend in the book, the band's own story first, then the tales; each as [id, name, told].
func legends() -> Array:
	var out: Array = []
	for id in db.stories["stories"]:
		out.append([id, db.stories["stories"][id]["name"], stories_done.has(id)])
	return out


## True once the Sheriff has been driven out of Nottingham Castle.
func finale_won() -> bool:
	for id in stories_done:
		if db.stories["stories"][id].get("finale", false):
			return true
	return false


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
	stats["atk"] += upgrade_sum("atk")
	u.max_hp = int(stats["hp"])
	u.hp = maxi(1, u.max_hp - damage)
	u.atk = int(stats["atk"])
	u.def = int(stats["def"])
	u.spd = int(stats["spd"])
	u.crit = stats["crit"]


func can_hire() -> bool:
	var mm: Dictionary = econ["merry_men"]
	return location == "camp" and reputation >= int(mm["min_reputation"]) and merry_men.size() < men_max()


## How many Merry Men the camp has room for.
func men_max() -> int:
	return int(econ["merry_men"]["max"]) + int(upgrade_sum("merry_men_max"))


func hire_merry_man() -> bool:
	if not can_hire() or not _spend(int(econ["merry_men"]["price"])):
		return false
	_add_merry_man()
	return true


func _add_merry_man() -> void:
	var names: Array = econ["merry_men"]["names"].filter(func(n): return not merry_men.values().has(n))
	var id := "merry_man_%d" % (merry_men.size() + 1)
	while heroes.has(id):
		id += "_"
	merry_men[id] = names[rng.randi_range(0, names.size() - 1)]
	heroes[id] = _make_merry_man(id)
	_news("%s joins the band." % merry_men[id])


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

func _end_day(resting: bool, heal := true) -> void:
	day += 1
	var band := free_heroes()
	var needed: int = band.size() * int(econ["supplies"]["per_member_per_day"])
	var fed := supplies >= needed
	supplies = maxi(0, supplies - needed)
	if not fed:
		_news("The band has run out of food and arrows. Everyone grows weak.")
	for h in band:
		h.statuses.clear()
		if fed and heal:
			h.heal(int(ceil(h.max_hp * (HEAL_AT_CAMP if resting else HEAL_ON_ROAD + upgrade_sum("road_heal")))))
		elif not fed:
			h.hp = maxi(1, h.hp - int(ceil(h.max_hp * float(econ["supplies"]["hunger_damage"]))))
	for id in missions.keys():
		if not missions[id].has("rescue_heroes") and missions[id]["type"] != "story" and missions[id]["expires"] < day:
			missions.erase(id)
	_sheriff_acts()
	_guy_acts()
	_move_prisoners()
	_post_stories()
	if rng.randf() < 0.6 or missions.size() < 2:
		_spawn_mission()
	_maybe_post_contest()
	_visitor_comes()


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


## The chance each day that Sir Guy raids before his plot is full: nothing below raid_from, then
## rising faster and faster toward 100, when he always comes.
func raid_chance() -> float:
	var g: Dictionary = db.baits["guy"]
	var from := float(g["raid_from"])
	if plots["guy"] >= 100:
		return 1.0
	var t := clampf((plots["guy"] - from) / (100.0 - from), 0.0, 1.0)
	return t * t * float(g["raid_chance_near_full"])


func _guy_acts() -> void:
	plots["guy"] = mini(100, plots["guy"] + maxi(0, 5 + infamy / 8 + int(upgrade_sum("guy_per_day"))))
	if plots["guy"] >= 100 or rng.randf() < raid_chance():
		plots["guy"] = 0
		var targets := free_heroes().filter(func(h): return band.has(h.id) and h.id != "robin")
		# He turns on someone new each time, when there is anyone else to hunt.
		if targets.size() > 1:
			targets = targets.filter(func(h): return h.id != hunted_hero)
		if not targets.is_empty():
			hunted_hero = targets[rng.randi_range(0, targets.size() - 1)].id
			_news("Sir Guy of Gisborne is hunting %s." % hero_name(hunted_hero))
		if ambush.is_empty() and not free_heroes().is_empty():
			var n: Dictionary = node(location)
			ambush = MissionGen.new(db).guy_raid(n["name"], n.get("location", "sherwood_edge"), rng.randi())
			ambush["hunted"] = hunted_hero
			_news("Sir Guy of Gisborne rides out to raid the band!")


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
		elif marian_free() and rng.randf() < float(db.marian["chance"]):
			var helps: bool = rng.randf() < float(db.marian["help_chance_wed" if flags.has("marian_wed") else "help_chance"])
			var visits: Array = MissionGen.marian_visits(db, m, "help" if helps else "trouble")
			if not visits.is_empty():
				gen.add_marian(m, visits[rng.randi_range(0, visits.size() - 1)], marian_home())
		m["expires"] = day + MISSION_LIFETIME
		missions[n] = m
		return


## Now and then a village or town holds an archery contest, never more than one at a time.
func _maybe_post_contest() -> void:
	if missions.values().any(func(m): return m["type"] == "contest"):
		return
	if rng.randf() >= float(db.contests["chance"]):
		return
	var places: Array = map["nodes"].keys().filter(func(n): return not missions.has(n) and node(n).has("location"))
	var options := []
	for n in places:
		for id in db.contests["contests"]:
			if db.contests["contests"][id]["places"].has(node(n)["kind"]):
				options.append([n, id])
	if options.is_empty():
		return
	var pick: Array = options[rng.randi_range(0, options.size() - 1)]
	var m: Dictionary = MissionGen.new(db).contest(pick[1], node(pick[0])["name"], rng.randi())
	m["expires"] = day + int(db.contests["lifetime"])
	missions[pick[0]] = m
	_news("Archers wanted! %s at %s." % [m["name"], node(pick[0])["name"]])


## Puts each story whose requirements are met on the map at its place, taking over any ordinary
## job there (but never a rescue). Story jobs never expire; one that fails (or is lost at the butts) comes back STORY_RETRY days later.
## A story where someone joins the band may also bump a waiting tale; tales are capped at MAX_TALES.
func _post_stories() -> void:
	var gen = MissionGen.new(db)
	var tales := missions.values().filter(func(m): return _is_tale(m)).size()
	for id in db.stories["stories"]:
		var st: Dictionary = db.stories["stories"][id]
		var is_tale: bool = st["recruit"] == "" and not st.get("arc", false)
		var held: Dictionary = missions.get(st["node"], {})
		if stories_done.has(id) or held.has("rescue_heroes") or not story_ready(id) or day < int(story_retry.get(id, 0)):
			continue
		if is_tale and not held.is_empty():
			continue        # tales wait for a free spot; they never push out a job you may be heading to
		if held.get("type", "") == "story" and not _is_tale(held):
			continue
		if is_tale and tales >= MAX_TALES:
			continue
		if held.get("type", "") == "story":
			tales -= 1      # an origin or Sheriff story bumps the tale back into the queue
		tales += 1 if is_tale else 0
		var at: String = st["node"]
		missions[at] = gen.story(id, threat(at), rng.randi())
		missions[at]["expires"] = 0
		_news(st.get("posted_news", "A tale is told of %s. (%s)" % [st["name"], node(at)["name"]]))


## A tale from the legends: a story that recruits nobody and isn't part of the Sheriff's arc.
static func _is_tale(m: Dictionary) -> bool:
	return m["type"] == "story" and m["recruit"] == "" and not m.get("arc", false)


func story_ready(id: String) -> bool:
	var st: Dictionary = db.stories["stories"][id]
	if st["recruit"] != "" and band.has(st["recruit"]):
		return false
	var req: Dictionary = st["requires"]
	for h in req.get("band", []):
		if not band.has(h):
			return false
	for s in req.get("stories", []):
		if not stories_done.has(s):
			return false
	for f in req.get("flags", []):
		if not flags.has(f):
			return false
	return reputation >= int(req.get("reputation", 0)) and infamy >= int(req.get("infamy", 0))


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
		"supplies": supplies, "merry_men": merry_men, "equipment": equipment,
		"band": band, "stories_done": stories_done, "story_retry": story_retry, "posted_wanted": posted_wanted, "poster_news": poster_news,
		"ambush": ambush, "flags": flags, "upgrades": upgrades, "visitor": visitor, "visitor_until": visitor_until, "evening": evening}


static func from_dict(game_data, data: Dictionary):
	# Saves from before story missions had the whole band.
	var c = load("res://core/campaign.gd").new(game_data, 0, data.get("band", FULL_BAND.slice(0, 4)))
	c.stories_done = data.get("stories_done", [])
	for id in data.get("story_retry", {}):
		c.story_retry[id] = int(data["story_retry"][id])
	c.day = int(data["day"])
	c.gold = int(data["gold"])
	c.reputation = int(data["reputation"])
	c.infamy = int(data["infamy"])
	c.posted_wanted = int(data.get("posted_wanted", c.wanted_level()))
	c.poster_news = int(data.get("poster_news", 0))
	c.ambush = data.get("ambush", {})
	c.upgrades = data.get("upgrades", [])
	c.visitor = data.get("visitor", "")
	c.visitor_until = int(data.get("visitor_until", 0))
	c.evening = data.get("evening", "")
	# Saves from before the loan cost anything: the band lent the money back then.
	c.flags = data.get("flags", ["knight_loan"] if c.stories_done.has("poor_knight") else [])
	if not c.ambush.is_empty():
		_fix_ints(c.ambush)
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
	for k in ["seed", "threat", "expires", "toughness"]:
		if m.has(k):
			m[k] = int(m[k])
	for k in m["rewards"]:
		m["rewards"][k] = int(m["rewards"][k])
	for n in m["nodes"]:
		MissionGen.fix_node_ints(n)


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
