class_name Automation
extends RefCounted
## Automation: your active pet does one job at a time for you (data/automation.json, the
## automation tab). Jobs are taught with coins; the machine job cranks your pet's own little
## capsule machine, the adventures job keeps a party going, the boxes job opens your pile.
## Pure rules on the state from the save:
##   { task: the job your pet is doing ("" = none), taught: { job id: true },
##     tools: { tool id: levels }, party: { place, n }, fill: 0..1 (the next crank),
##     others: { job id: true } (taught to the other pets: workers), spots: { job id: machines,
##     tables or parties bought }, workers: { job id: [uids] } (one per spot), parties: [{ place, n }]
##     (a party per bought party spot, led by the worker in the same place), wfill: { job id: 0..1 },
##     whistle: { ticks: { job id: { haul, fill } } (missing = on), keep: coins set aside (-1: the
##     data's), wait: 0..1 (the next check) },
##     wherd: { job id: { count key: pets from the herd working there } } (not adventures: a party's
##     leader keeps its slot, as a stand-in's uid), wjoin: { job id: true } (new pets start working
##     there while it has empty spots: "new pets join here"; never adventures) }
## The whistle (layer 2): managing is your pet's one job (task "whistle"). It checks on everyone
## every so often: hauls machines, tables and parties home (buys spots, never going under what's
## set aside) and keeps them full (puts resting pets on). How many exist grows with the map pages.
## GameState keeps the state and hands out what the jobs bring.


static func fresh() -> Dictionary:
	return { "task": "", "taught": {}, "tools": {}, "party": { "place": "", "n": 0 }, "fill": 0.0,
		"others": {}, "spots": {}, "workers": {}, "parties": [], "wfill": {}, "whistle": whistle_fresh(),
		"wherd": {}, "wjoin": {} }


static func whistle_fresh() -> Dictionary:
	return { "ticks": {}, "keep": -1, "wait": 0.0 }


## A job by id; "whistle" is the whistle (your pet's managing job, not a card on the your pet page).
static func job(catalog: Catalog, id: String) -> Dictionary:
	if id == WHISTLE:
		var w: Dictionary = catalog.automation.get("whistle", {})
		if w.is_empty():
			return {}
		if not w.has("id"):
			w.id = WHISTLE
		return w
	for j in catalog.automation.get("jobs", []):
		if j.id == id:
			return j
	return {}


const WHISTLE := "whistle"


static func taught(state: Dictionary, id: String) -> bool:
	return state.get("taught", {}).has(id)


# ---- tools: what coins buy for a job -------------------------------------------------

## Every tool, each with "job" (its job's id) and "workers" (true: it's for the workers) added.
static func all_tools(catalog: Catalog) -> Array[Dictionary]:
	if catalog.has_meta("auto_tools"):  # worked out once per catalog
		return catalog.get_meta("auto_tools")
	var out: Array[Dictionary] = []
	for j in catalog.automation.get("jobs", []) + [job(catalog, WHISTLE)]:
		for key in ["tools", "worker_tools"]:
			for t in j.get(key, []):
				var t2: Dictionary = t.duplicate()
				t2.job = str(j.id)
				t2.workers = key == "worker_tools"
				out.append(t2)
	catalog.set_meta("auto_tools", out)
	return out


static func tool(catalog: Catalog, id: String) -> Dictionary:
	for t in all_tools(catalog):
		if t.id == id:
			return t
	return {}


static func tool_level(state: Dictionary, id: String) -> int:
	return int(state.get("tools", {}).get(id, 0))


## What the next level of a tool costs.
static func tool_cost(state: Dictionary, t: Dictionary) -> int:
	return 0 if t.is_empty() else Jobs.tool_cost(t, tool_level(state, str(t.id)))


## Why a tool can't take a level now, or "" if it can (coins aside): "max", or "closed" (its job
## isn't taught).
static func tool_block(state: Dictionary, t: Dictionary) -> String:
	if t.is_empty() or not taught(state, str(t.job)) or (t.get("workers", false) and not others(state, str(t.job))):
		return "closed"
	if Jobs.tool_room(t, tool_level(state, str(t.id))) <= 0:
		return "max"
	return ""


## One effect of a job's tools, added up (e.g. speed, away_hours).
static func tool_sum(catalog: Catalog, state: Dictionary, job_id: String, key: String) -> float:
	var sum := 0.0
	for t in all_tools(catalog):
		if t.job == job_id and t.each.has(key):
			sum += float(t.each[key]) * tool_level(state, str(t.id))
	return sum


# ---- the machine job ------------------------------------------------------------------

## Seconds between two cranks of your pet's machine; `x` is how much faster other things make it
## (the book's automation stickers).
static func crank_seconds(catalog: Catalog, state: Dictionary, x := 1.0) -> float:
	return float(job(catalog, "machine").get("seconds", 60)) / (1.0 + tool_sum(catalog, state, "machine", "speed")) / x


## Hours your pet keeps cranking while the game is closed (the comfy stool).
static func away_hours(catalog: Catalog, state: Dictionary) -> float:
	return tool_sum(catalog, state, "machine", "away_hours")


## Your pet cranks for `seconds`: returns how many pulls that makes (state.fill keeps the rest).
static func crank(catalog: Catalog, state: Dictionary, seconds: float, x := 1.0) -> int:
	var fill := float(state.get("fill", 0.0)) + maxf(0.0, seconds) / crank_seconds(catalog, state, x)
	var pulls := floori(fill)
	state.fill = fill - pulls
	return pulls


## Seconds the game was closed that count for the machine: up to the stool's hours.
static func away_seconds(catalog: Catalog, state: Dictionary, away: float) -> float:
	return clampf(away, 0.0, away_hours(catalog, state) * 3600.0)


# ---- workers: the other pets, once your pet has taught them -----------------------------

## Whether a job has been taught to the other pets (the workers page).
static func others(state: Dictionary, id: String) -> bool:
	return state.get("others", {}).has(id)


## Why "teach the others" can't be bought for a job yet, or "" (coins aside): "taught" (your pet
## doesn't know it yet), "done", "lv" (a tool of your pet's isn't far enough), "none" (the job has
## no workers).
static func teach_block(catalog: Catalog, state: Dictionary, id: String) -> String:
	var j := job(catalog, id)
	if not j.has("teach"):
		return "none"
	if not taught(state, id):
		return "taught"
	if others(state, id):
		return "done"
	var after: Dictionary = j.teach.get("after", {})
	for t in after:
		if tool_level(state, str(t)) < int(after[t]):
			return "lv"
	return ""


## Machines, tables or parties bought for a job's workers.
static func spots(state: Dictionary, id: String) -> int:
	return int(state.get("spots", {}).get(id, 0))


## What the next `n` spots for a job cost.
static func spot_cost(catalog: Catalog, state: Dictionary, id: String, n := 1) -> int:
	var spot: Dictionary = job(catalog, id).get("spot", {})
	return 0 if spot.is_empty() else Jobs.tool_cost(spot, spots(state, id), n)


## How fast a pet works as a worker, next to your own pet (1.0): a common at half speed, each
## rarity step 0.1 more (a legendary nearly keeps up, a mythic does).
static func worker_speed(catalog: Catalog, pet: Pet) -> float:
	return 0.5 + 0.1 * catalog.rank(pet.rarity)


## Seconds a worker at full speed (1.0) takes for one pull (machine) or one box (boxes).
static func worker_seconds(catalog: Catalog, state: Dictionary, id: String) -> float:
	var j := job(catalog, id)
	var base := float(j.get("worker_seconds", j.get("seconds", 60)))
	var speed := 0.0
	for t in all_tools(catalog):
		if t.job == id and t.each.has("worker_speed"):
			speed += float(t.each.worker_speed) * tool_level(state, str(t.id))
	return base / (1.0 + speed)


## A job's workers work for `seconds`: `speed_sum` is their speeds added up. Returns how many pulls
## (or boxes) that makes; state.wfill keeps the rest.
static func work(catalog: Catalog, state: Dictionary, id: String, speed_sum: float, seconds: float) -> int:
	if speed_sum <= 0.0:
		return 0
	var wfill: Dictionary = state.get("wfill", {})
	var fill := float(wfill.get(id, 0.0)) + speed_sum * maxf(0.0, seconds) / worker_seconds(catalog, state, id)
	var n := floori(fill)
	wfill[id] = fill - n
	state.wfill = wfill
	return n


# ---- spots: how many exist (old machines and tables in places you've taken) ---------------

## How many machines (tables, parties) there are for a job: each open map page adds its "exist",
## parties one per open place ("per_place"). A big number when the job has no cap.
static func exist(catalog: Catalog, id: String, pages: Array, places: int) -> int:
	var spot: Dictionary = job(catalog, id).get("spot", {})
	if spot.has("per_place"):
		return int(spot.per_place) * places
	if not spot.has("exist"):
		return 1 << 30
	var n := 0
	for page in pages:
		n += int(spot.exist.get(str(page), 0))
	return n


## How many are still out there to haul home (never below 0: old saves keep ones past the cap).
static func out_there(catalog: Catalog, state: Dictionary, id: String, pages: Array, places: int) -> int:
	return maxi(0, exist(catalog, id, pages, places) - spots(state, id))


## How many of the next spots fit in `coins` (up to `room`), found by halving: prices only go up.
static func affordable(catalog: Catalog, state: Dictionary, id: String, coins: int, room: int) -> int:
	var spot: Dictionary = job(catalog, id).get("spot", {})
	if spot.is_empty():
		return 0
	var have := spots(state, id)
	var lo := 0
	var hi := mini(room, 1 << 20)
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if Jobs.tool_cost(spot, have, mid) <= coins:
			lo = mid
		else:
			hi = mid - 1
	return lo


# ---- the whistle: your pet manages the workers ---------------------------------------------

## Whether a tick on the whistle's list is on (`key` "haul" or "fill"); everything starts on.
static func tick(state: Dictionary, id: String, key: String) -> bool:
	return bool(state.get("whistle", {}).get("ticks", {}).get(id, {}).get(key, true))


## Coins the whistle never spends.
static func keep(catalog: Catalog, state: Dictionary) -> int:
	var k := int(state.get("whistle", {}).get("keep", -1))
	return k if k >= 0 else int(job(catalog, WHISTLE).get("keep", 0))


## Set aside one step up (d 1) or down (d -1) the data's steps.
static func keep_step(catalog: Catalog, state: Dictionary, d: int) -> int:
	var steps: Array = job(catalog, WHISTLE).get("keep_steps", [0])
	var now := keep(catalog, state)
	var i := 0
	for s in steps.size():  # the step it's on, or the one just under it
		if int(steps[s]) <= now:
			i = s
	if d < 0 and int(steps[i]) < now:
		return int(steps[i])
	return int(steps[clampi(i + d, 0, steps.size() - 1)])


## Seconds between two checks (the pencil makes it quicker).
static func check_seconds(catalog: Catalog, state: Dictionary) -> float:
	return float(job(catalog, WHISTLE).get("check_seconds", 10)) / (1.0 + tool_sum(catalog, state, WHISTLE, "check_speed"))


## How many it hauls home a check (the wagon adds more).
static func haul_size(catalog: Catalog, state: Dictionary) -> int:
	return int(job(catalog, WHISTLE).get("haul", 1)) + roundi(tool_sum(catalog, state, WHISTLE, "haul"))


## Your pet manages for `seconds`: how many checks that makes (whistle.wait keeps the rest).
static func checks(catalog: Catalog, state: Dictionary, seconds: float) -> int:
	var w: Dictionary = state.get("whistle", whistle_fresh())
	var fill := float(w.get("wait", 0.0)) + maxf(0.0, seconds) / check_seconds(catalog, state)
	var n := floori(fill)
	w.wait = fill - n
	state.whistle = w
	return n


static func _working(state: Dictionary, id: String) -> int:
	var n := 0
	for uid in state.get("workers", {}).get(id, []):
		if str(uid) != "":
			n += 1
	return n


## What `checks` checks do, worked out without changing anything: { buys: { job id: spots },
## spent: coins, fill: { job id: pets to put on } }. `jobs` are the jobs taught to the others, in
## order; `rooms` { job id: how many are still out there }; `resting` pets free to work; `away` how
## many of the workers' parties are out right now (their pets aren't resting). Hauls go to the
## cheapest next spot among the ticked jobs and never take coins under what's set aside; a party is
## only hauled home while there's a resting pet to lead it and some to go with it. Parties are
## filled first and their pets set aside, then the other jobs get what's left. Nothing at all unless
## your pet is managing.
static func whistle_plan(catalog: Catalog, state: Dictionary, jobs: Array, coins: int, rooms: Dictionary, resting: int, checks_n: int, away := 0) -> Dictionary:
	var plan := { "buys": {}, "spent": 0, "fill": {} }
	if str(state.get("task", "")) != WHISTLE or checks_n <= 0:
		return plan
	var floor_coins := keep(catalog, state)
	var budget := checks_n * haul_size(catalog, state)
	var spent := 0
	var buys := {}
	while budget > 0:
		var best := ""
		var best_cost := 0
		for id in jobs:
			var spot: Dictionary = job(catalog, id).get("spot", {})
			if spot.is_empty() or not tick(state, id, "haul") or not others(state, id) or int(rooms.get(id, 0)) - int(buys.get(id, 0)) <= 0:
				continue
			if spot.has("per_place") and (_empty(state, id, buys) + 1) * (1 + _party_size(catalog, id)) > resting:
				continue  # nobody free to lead it (and go with it)
			var cost := Jobs.tool_cost(spot, spots(state, id) + int(buys.get(id, 0)), 1)
			if best == "" or cost < best_cost:
				best = id
				best_cost = cost
		if best == "" or coins - spent - best_cost < floor_coins:
			break
		spent += best_cost
		buys[best] = int(buys.get(best, 0)) + 1
		budget -= 1
	plan.buys = buys
	plan.spent = spent
	var free := resting
	var order := jobs.filter(func(j): return job(catalog, j).get("spot", {}).has("per_place")) \
		+ jobs.filter(func(j): return not job(catalog, j).get("spot", {}).has("per_place"))
	for id in order:
		if not others(state, id):
			continue
		var n := 0
		if tick(state, id, "fill"):
			n = mini(_empty(state, id, buys), free)
			if n > 0:
				plan.fill[id] = n
				free -= n
		if job(catalog, id).get("spot", {}).has("per_place"):  # the pets its parties take out stay free
			free -= mini(free, maxi(0, _working(state, id) + n - away) * _party_size(catalog, id))
	return plan


## A job's spots nobody works at, counting the ones `buys` brings home.
static func _empty(state: Dictionary, id: String, buys: Dictionary) -> int:
	return maxi(0, spots(state, id) + int(buys.get(id, 0)) - _working(state, id))


## How many pets a party of a per-place job takes out (besides its leader).
static func _party_size(catalog: Catalog, id: String) -> int:
	return int(job(catalog, id).get("party", 3))
