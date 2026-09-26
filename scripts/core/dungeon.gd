class_name Dungeon
extends RefCounted
## Pets sent down the dungeon floors (data/dungeons.json). A run takes real time, so it carries on
## while the game is closed. When it's collected, each pet either comes home with loot or doesn't.
## Plain data and rules, no UI; GameState owns one and saves it.

const RUN_KEYS := ["floor", "pets", "started", "ends"]

var catalog: Catalog
## Runs in the order they were sent: { floor: int, pets: Array of uids, started: float, ends: float }
var runs: Array[Dictionary] = []


func _init(p_catalog: Catalog = Catalog.shared()) -> void:
	catalog = p_catalog


## A pet's stat with its traits applied (e.g. brave = more power).
static func stat(pet: Pet, stat_name: String, p_catalog: Catalog) -> float:
	var value := float(pet.stats.get(stat_name, 0))
	for t in pet.traits:
		value *= float(p_catalog.trait_info(t).get("mods", {}).get(stat_name, 1.0))
	return value


## Chance (0..1) that this pet comes home from this floor. Power over the floor's need helps.
static func survive_chance(floor_info: Dictionary, pet: Pet, p_catalog: Catalog) -> float:
	var power := stat(pet, "power", p_catalog)
	return clampf(float(floor_info.survive) + (power - float(floor_info.need)) * 0.01, 0.05, 0.99)


## How long (seconds) a group takes on a floor: faster pets shorten it a little.
static func run_seconds(floor_info: Dictionary, pets: Array[Pet], p_catalog: Catalog) -> float:
	var speed := 0.0
	for pet in pets:
		speed += stat(pet, "speed", p_catalog)
	speed /= maxf(1.0, pets.size())
	return float(floor_info.minutes) * 60.0 * clampf(1.0 - (speed - float(floor_info.need)) * 0.01, 0.5, 1.25)


## Rolls how a run went: { home: [uids], lost: [uids], coins: int, boxes: { box id: count } }.
static func roll(floor_info: Dictionary, pets: Array[Pet], rng: RandomNumberGenerator, p_catalog: Catalog) -> Dictionary:
	var home: Array[String] = []
	var lost: Array[String] = []
	var coins := 0
	var boxes := {}
	for pet in pets:
		if rng.randf() >= survive_chance(floor_info, pet, p_catalog):
			lost.append(pet.uid)
			continue
		home.append(pet.uid)
		var luck := clampf(1.0 + (stat(pet, "luck", p_catalog) - float(floor_info.need)) * 0.02, 0.5, 3.0)
		coins += roundi(rng.randi_range(int(floor_info.coins[0]), int(floor_info.coins[1])) * luck)
		if rng.randf() < float(floor_info.box_chance) * luck:
			boxes[floor_info.box] = boxes.get(floor_info.box, 0) + 1
	return { "home": home, "lost": lost, "coins": coins, "boxes": boxes }


func floors() -> Array[Dictionary]:
	return catalog.floors


func floor_info(index: int) -> Dictionary:
	return catalog.floors[clampi(index, 0, catalog.floors.size() - 1)]


## Starts a run. `now` is unix time.
func send(floor_index: int, pets: Array[Pet], now: float) -> Dictionary:
	var uids: Array[String] = []
	for pet in pets:
		uids.append(pet.uid)
	var run := {
		"floor": floor_index,
		"pets": uids,
		"started": now,
		"ends": now + run_seconds(floor_info(floor_index), pets, catalog),
	}
	runs.append(run)
	return run


## uid -> true for every pet that's down there right now.
func away() -> Dictionary:
	var out := {}
	for run in runs:
		for uid in run.pets:
			out[uid] = true
	return out


static func is_done(run: Dictionary, now: float) -> bool:
	return now >= float(run.ends)


## 0..1 how far along a run is.
static func progress(run: Dictionary, now: float) -> float:
	var total := float(run.ends) - float(run.started)
	return 1.0 if total <= 0.0 else clampf((now - float(run.started)) / total, 0.0, 1.0)


func to_dict() -> Dictionary:
	return { "runs": runs }


func load_from(d: Dictionary) -> void:
	runs.clear()
	for raw in d.get("runs", []):
		if not RUN_KEYS.all(func(k): return raw.has(k)):
			continue
		var uids: Array[String] = []
		for uid in raw.pets:
			uids.append(str(uid))
		runs.append({
			"floor": clampi(int(raw.floor), 0, catalog.floors.size() - 1),
			"pets": uids,
			"started": float(raw.started),
			"ends": float(raw.ends),
		})
