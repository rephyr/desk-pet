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
##     (a party per bought party spot, led by the worker in the same place), wfill: { job id: 0..1 } }
## GameState keeps the state and hands out what the jobs bring.


static func fresh() -> Dictionary:
	return { "task": "", "taught": {}, "tools": {}, "party": { "place": "", "n": 0 }, "fill": 0.0,
		"others": {}, "spots": {}, "workers": {}, "parties": [], "wfill": {} }


static func job(catalog: Catalog, id: String) -> Dictionary:
	for j in catalog.automation.get("jobs", []):
		if j.id == id:
			return j
	return {}


static func taught(state: Dictionary, id: String) -> bool:
	return state.get("taught", {}).has(id)


# ---- tools: what coins buy for a job -------------------------------------------------

## Every tool, each with "job" (its job's id) and "workers" (true: it's for the workers) added.
static func all_tools(catalog: Catalog) -> Array[Dictionary]:
	if catalog.has_meta("auto_tools"):  # worked out once per catalog
		return catalog.get_meta("auto_tools")
	var out: Array[Dictionary] = []
	for j in catalog.automation.get("jobs", []):
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

## Seconds between two cranks of your pet's machine.
static func crank_seconds(catalog: Catalog, state: Dictionary) -> float:
	return float(job(catalog, "machine").get("seconds", 60)) / (1.0 + tool_sum(catalog, state, "machine", "speed"))


## Hours your pet keeps cranking while the game is closed (the comfy stool).
static func away_hours(catalog: Catalog, state: Dictionary) -> float:
	return tool_sum(catalog, state, "machine", "away_hours")


## Your pet cranks for `seconds`: returns how many pulls that makes (state.fill keeps the rest).
static func crank(catalog: Catalog, state: Dictionary, seconds: float) -> int:
	var fill := float(state.get("fill", 0.0)) + maxf(0.0, seconds) / crank_seconds(catalog, state)
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
