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


## Fills per second for a crew of `size` whose pets work at `avg_speed` on average.
static func rate(job: Dictionary, size: int, avg_speed: float, crew_power: float) -> float:
	if size <= 0:
		return 0.0
	return pow(float(size), crew_power) * avg_speed / float(job.seconds)


## Seconds away that count: full speed for the first `full_hours`, then `after` speed, up to `cap`.
static func offline_seconds(away: float, full_hours: float, after: float, cap: float) -> float:
	away = clampf(away, 0.0, cap)
	var full := full_hours * 3600.0
	return minf(away, full) + maxf(0.0, away - full) * after


## Runs a job's meter for `seconds`. `state` is { fill } and is updated in place.
## Returns { fills, loot } (loot as in Rewards).
static func work(job: Dictionary, state: Dictionary, crew: int, fills_per_second: float, seconds: float,
		rng: RandomNumberGenerator, catalog: Catalog) -> Dictionary:
	var fill := float(state.get("fill", 0.0)) + fills_per_second * seconds
	var fills := floori(fill)
	state.fill = fill - fills
	return { "fills": fills, "loot": pay(job, fills, crew, rng, catalog) }


## What `fills` full meters pay.
static func pay(job: Dictionary, fills: int, crew: int, rng: RandomNumberGenerator, catalog: Catalog) -> Dictionary:
	var loot := {}
	if fills <= 0:
		return loot
	var p: Dictionary = job.get("pay", {})
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
