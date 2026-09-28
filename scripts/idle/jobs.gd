class_name Jobs
extends RefCounted
## Errands: safe idle jobs you put resting pets on (data/errands.json, the errands tab).
## One rule for every job: a meter fills once every `seconds` with one pet, faster with a bigger
## crew (crew ^ crew_power, so each extra pet helps a bit less), and pays each time it's full.
## A crew can be a couple of pets or thousands. Nobody is lost on an errand, and errands never
## bring rare parts or new places (those come from adventures).
## Pure rules; GameState keeps who is on which job and hands out what they bring.

const COMMON_BOX := "tutorial"  # scrapyard parts are commons, rolled with this box's odds
const MAX_ROLLS := 200  # past this many fills at once, parts are rolled this often and scaled up


## How fast one pet works at a job, about 0.75 to 1.25: its stat for the job (rarer pets have
## higher stats) and its traits.
static func pet_speed(pet: Pet, job: Dictionary) -> float:
	var stat := float(pet.stats.get(str(job.get("stat", "")), 10))
	var out := clampf(0.8 + stat / 50.0, 0.75, 1.25)
	var traits: Dictionary = job.get("traits", {})
	for t in pet.traits:
		out *= float(traits.get(t, 1.0))
	return out


## Fills per second for a crew of `size` whose pets work at `avg_speed` on average. A job with its
## own "crew_power" (the savings jar) uses that instead of `crew_power` (teamwork still adds to it:
## pass what the tools add as `extra_power`).
static func rate(job: Dictionary, size: int, avg_speed: float, crew_power: float, extra_power := 0.0) -> float:
	if size <= 0:
		return 0.0
	var power := float(job.get("crew_power", crew_power - extra_power)) + extra_power
	return pow(float(size), power) * avg_speed / float(job.seconds)


## The kitchen: how much faster every other job works, as a share (0.15 = 15% faster). `cooks` is
## the kitchen's crew times its average speed, `others` the pets on every other job. A soft curve
## (most x cooks / (cooks + half): a few cooks help most), capped at what those cooks would add on
## a real job with the others ((1 + cooks / others) ^ crew_power - 1), so it never beats one.
static func kitchen_bonus(job: Dictionary, cooks: float, others: int, crew_power: float) -> float:
	var k: Dictionary = job.get("kitchen", {})
	if cooks <= 0.0 or k.is_empty():
		return 0.0
	var soft := float(k.get("most", 0.3)) * cooks / (cooks + float(k.get("half", 2.0)))
	if others <= 0:
		return soft
	return minf(soft, pow(1.0 + cooks / float(others), crew_power) - 1.0)


## The kitchen's line: "every job 12% faster", one decimal under 1% (a big crew thins it out),
## "" when it rounds to nothing.
static func faster_words(bonus: float) -> String:
	var pct := bonus * 100.0
	if pct >= 0.995:
		return "every job %d%% faster" % roundi(pct)
	if pct >= 0.05:
		return "every job %.1f%% faster" % pct
	return ""


## The job that writes scout notes: whichever has a "scout" block ({} if none). Found once per
## catalog, so the job can be renamed in data.
static func scout_job(catalog: Catalog) -> Dictionary:
	if not catalog.has_meta("scout_job"):
		var found := {}
		for job in catalog.jobs:
			if job.has("scout"):
				found = job
				break
		catalog.set_meta("scout_job", found)
	return catalog.get_meta("scout_job")


## The scouting job's "scout" block: { hold, spot, rumour_x }.
static func scout_settings(catalog: Catalog) -> Dictionary:
	return scout_job(catalog).get("scout", {})


## What a trip that takes a scout note carries with it (kept on the RunState): { spot, rumour_x }.
static func scout_note(catalog: Catalog) -> Dictionary:
	var s := scout_settings(catalog)
	return { "spot": float(s.get("spot", 0.0)), "rumour_x": float(s.get("rumour_x", 1.0)) }


## Scout notes you can hold: the job's "scout" hold plus what the tools add ("hold").
static func scout_hold(catalog: Catalog, levels: Dictionary) -> int:
	var job := scout_job(catalog)
	if job.is_empty():
		return 0
	return int(job.scout.get("hold", 0)) + roundi(tool_sum(catalog, str(job.id), "hold", levels))


## What `meals` meals from the kitchen do to your pet: food goes up by the job's "meal" each, but
## only up to "meal_upto" (the kitchen keeps it from getting low; feeding it yourself fills it up),
## and mood by "meal_mood" for each meal it actually ate, up to the same line. Never lowers
## either. Returns { food, mood, eaten } (eaten: food it gained).
static func feed(job: Dictionary, food: float, mood: float, meals: int) -> Dictionary:
	var each := float(job.get("pay", {}).get("meal", 0))
	var upto := float(job.get("meal_upto", 100.0))
	var fed := maxf(food, minf(upto, food + each * meals))
	var eaten := fed - food
	var got_mood := float(job.get("meal_mood", 0)) * eaten / maxf(1.0, each)
	return { "food": fed, "mood": maxf(mood, minf(upto, mood + got_mood)), "eaten": eaten }


## Whether a trip takes a scout note when it sets off: you sent it yourself (not an auto party), you
## hold a note, its kind of place takes notes (never dungeons) and there's still something to find
## there (see Intel.left_to_find).
static func takes_note(catalog: Catalog, location: Dictionary, by_you: bool, notes: int, left_to_find: bool) -> bool:
	if not by_you or notes <= 0 or not left_to_find:
		return false
	return bool(catalog.adventure_type(str(location.get("type", ""))).get("scout", true))


## Whether share out (and your pet's sharing) may put pets on a job ("share": false: you staff it).
static func shared_out(job: Dictionary) -> bool:
	return bool(job.get("share", true))


## Seconds away that count: full speed for the first `full_hours`, then `after` speed, up to `cap`.
static func offline_seconds(away: float, full_hours: float, after: float, cap: float) -> float:
	away = clampf(away, 0.0, cap)
	var full := full_hours * 3600.0
	return minf(away, full) + maxf(0.0, away - full) * after


## Runs a job's meter for `seconds`. `state` is { fill } and is updated in place. `boost` is what
## the tools and the machine add (see pay()). Returns { fills, loot } (loot as in Rewards).
static func work(job: Dictionary, state: Dictionary, crew: int, fills_per_second: float, seconds: float,
		rng: RandomNumberGenerator, catalog: Catalog, boost := {}) -> Dictionary:
	var fill := float(state.get("fill", 0.0)) + fills_per_second * seconds
	var fills := floori(fill)
	state.fill = fill - fills
	return { "fills": fills, "loot": pay(job, fills, crew, rng, catalog, boost) }


## What `fills` full meters pay ("meal": food for your pet, "note": scout notes). For "capsules" pay, `boost` says what a capsule is worth and what
## the tools add: { coin_value, worth (extra capsules a fill), x (goals and tips), big (chance of a
## big one), big_x, shiny (chance), shiny_pay }.
static func pay(job: Dictionary, fills: int, crew: int, rng: RandomNumberGenerator, catalog: Catalog, boost := {}) -> Dictionary:
	var loot := {}
	if fills <= 0:
		return loot
	var p: Dictionary = job.get("pay", {})
	if p.has("capsules"):
		var each := one_fill(job, boost)
		var big := float(boost.get("big", 0.0))
		var shiny := float(boost.get("shiny", 0.0))
		var big_x := float(boost.get("big_x", 5.0))
		var shiny_pay := float(boost.get("shiny_pay", 2.0))
		var total := 0.0
		if fills <= MAX_ROLLS:
			for i in fills:
				var got := each
				if rng.randf() < big:
					got *= big_x
				if rng.randf() < shiny:
					got *= shiny_pay
				total += got
		else:
			total = fills * each * (1.0 + big * (big_x - 1.0)) * (1.0 + shiny * (shiny_pay - 1.0))
		loot["coins"] = maxi(1, roundi(total))
	if p.has("coins"):
		var lo := int(p.coins[0])
		var hi := int(p.coins[1])
		var coins := 0
		if fills <= MAX_ROLLS:
			for i in fills:
				coins += rng.randi_range(lo, hi)
		else:
			coins = roundi(fills * (lo + hi) / 2.0)
		loot["coins"] = coins
	if p.has("meal"):
		loot["meal"] = fills * int(p.meal)
	if p.has("note"):
		loot["note"] = fills * int(p.note)
	if p.has("part"):
		var rolls := mini(fills, MAX_ROLLS)
		var scale := float(fills) / rolls
		var uncommon: Dictionary = job.get("uncommon", {})
		var rolled := {}
		for i in rolls * int(p.part):
			var part := _uncommon_part(rng, catalog) if crew >= int(uncommon.get("crew", 1 << 30)) and rng.randf() < float(uncommon.get("chance", 0.0)) \
				else Rewards.roll_part(COMMON_BOX, rng, catalog)
			var key := "part:%s:%s" % part
			rolled[key] = int(rolled.get(key, 0)) + 1
		for key in rolled:
			loot[key] = roundi(rolled[key] * scale)
	return loot


static func _uncommon_part(rng: RandomNumberGenerator, catalog: Catalog) -> Array:
	var slots: Array = Catalog.SLOTS.filter(func(s): return not catalog.parts_of_tier(s, "uncommon").is_empty())
	var slot: String = slots[rng.randi_range(0, slots.size() - 1)]
	var options := catalog.parts_of_tier(slot, "uncommon")
	return [slot, options[rng.randi_range(0, options.size() - 1)].id]


# ---- tools: what coins buy for errands (the upgrades page) ----------------------------------

## A plain fill of a "capsules" job, before big and shiny ones: its capsules plus the tools'
## extra ones, times what a capsule is worth, times goals and tips.
static func one_fill(job: Dictionary, boost: Dictionary) -> float:
	var capsules := float(job.get("pay", {}).get("capsules", 0)) + float(boost.get("worth", 0.0))
	return capsules * float(boost.get("coin_value", 1.0)) * float(boost.get("x", 1.0))


## What one fill pays on average, big and shiny ones counted in.
static func average_fill(job: Dictionary, boost: Dictionary) -> float:
	var p: Dictionary = job.get("pay", {})
	if p.has("coins"):
		return (float(p.coins[0]) + float(p.coins[1])) / 2.0
	var big := float(boost.get("big", 0.0))
	var shiny := float(boost.get("shiny", 0.0))
	return one_fill(job, boost) * (1.0 + big * (float(boost.get("big_x", 5.0)) - 1.0)) * (1.0 + shiny * (float(boost.get("shiny_pay", 2.0)) - 1.0))


## Every tool: each job's own and the ones for everyone, each with "job" (a job id, or "" for
## everyone) added.
static func all_tools(catalog: Catalog) -> Array[Dictionary]:
	if catalog.has_meta("errand_tools"):  # worked out once per catalog
		return catalog.get_meta("errand_tools")
	var out: Array[Dictionary] = []
	for job in catalog.jobs:
		for t in job.get("tools", []):
			var tool: Dictionary = t.duplicate()
			tool.job = str(job.id)
			out.append(tool)
	for t in catalog.errands.get("tools", []):
		var tool: Dictionary = t.duplicate()
		tool.job = ""
		out.append(tool)
	var by_id := {}
	for t in out:
		by_id[t.id] = t
	catalog.set_meta("errand_tools", out)
	catalog.set_meta("errand_tools_by_id", by_id)
	return out


static func tool(catalog: Catalog, id: String) -> Dictionary:
	all_tools(catalog)
	return catalog.get_meta("errand_tools_by_id").get(id, {})


## What the next `n` levels of a tool cost, with `have` levels already.
static func tool_cost(tool: Dictionary, have: int, n := 1) -> int:
	var total := 0.0
	for i in n:
		total += float(tool.coins) * pow(float(tool.get("grow", 1.0)), have + i)
	return roundi(minf(total, MAX_PRICE))


const MAX_PRICE := 4.0e18  # prices stop here: past about 9.2e18 a whole number wraps round to negative


## How many more levels a tool can take (a big number when it has no end).
static func tool_room(tool: Dictionary, have: int) -> int:
	var most := int(tool.get("max", 0))
	return (1 << 30) if most <= 0 else maxi(0, most - have)


## A job's level: all its own tools' levels added up. `levels` is tool id -> level.
static func level(job: Dictionary, levels: Dictionary) -> int:
	var n := 0
	for t in job.get("tools", []):
		n += int(levels.get(t.id, 0))
	return n


## What a job's goals multiply its pay by at `lvl`.
static func goal_x(job: Dictionary, lvl: int) -> float:
	var x := 1.0
	for g in job.get("goals", []):
		if lvl >= int(g.at) and g.has("x"):
			x *= float(g.x)
	return x


## The next goal a job hasn't reached at `lvl`, or {}.
static func next_goal(job: Dictionary, lvl: int) -> Dictionary:
	for g in job.get("goals", []):
		if lvl < int(g.at):
			return g
	return {}


## What a goal gives, in words: "x2 coins", its text, or both ("x2 tips and a savings jar opens").
static func goal_words(job: Dictionary, goal: Dictionary) -> String:
	var words: Array[String] = []
	if goal.has("x"):
		words.append("x%s %s" % [str(goal.x).trim_suffix(".0"), str(job.brings)])
	if str(goal.get("text", "")) != "":
		words.append(str(goal.text))
	return " and ".join(words)


## One effect of the tools, added up: every level of every tool that has `key` in "each" (this
## job's own and the ones for everyone; job_id "" counts only the ones for everyone).
static func tool_sum(catalog: Catalog, job_id: String, key: String, levels: Dictionary) -> float:
	var sum := 0.0
	for t in all_tools(catalog):
		if (t.job == job_id or t.job == "") and t.each.has(key):
			sum += float(t.each[key]) * int(levels.get(t.id, 0))
	return sum


## Why a tool can't take a level now, or "" if it can (coins aside): "max", "at lv 10",
## "needs shiny balls" (a machine node), "closed" (its job isn't open).
static func tool_block(catalog: Catalog, tool: Dictionary, levels: Dictionary, machine: Dictionary, job_open: bool) -> String:
	if tool.is_empty():
		return "closed"
	if tool_room(tool, int(levels.get(tool.id, 0))) <= 0:
		return "max"
	if tool.job != "" and not job_open:
		return "closed"
	if tool.has("at") and tool.job != "" and level(catalog.job(tool.job), levels) < int(tool.at):
		return "at lv %d" % int(tool.at)
	if tool.has("machine") and Machine.owned(machine, str(tool.machine)) <= 0:
		return "needs " + str(Machine.node(catalog, str(tool.machine)).get("name", tool.machine))
	return ""
