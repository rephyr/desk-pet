class_name Errands
extends RefCounted
## Errands: while you're busy, your active pet sends spare pets to places you know to fetch
## little things (data/adventures.json "errand" on a location). Just a timer and a small haul:
## coins, sometimes a common part or a starter box. Nobody is ever lost on an errand, and errands
## never find new places or rare parts; those only come from your own trips.
## Pure rules; GameState keeps the list of errands and hands out what comes back.

const SLOTS := 2  # errands your pet keeps going at once
const COMMON_BOX := "tutorial"  # errand parts are always commons: rolled with this box's odds


## Places your pet can send errands to (open places that have an errand).
static func places(open_locations: Array[Dictionary]) -> Array[Dictionary]:
	return open_locations.filter(func(l): return l.has("errand"))


## A new errand: one pet off to one place. { pet, place, started, ends, doing }
static func start(uid: String, place: Dictionary, now: float, rng: RandomNumberGenerator) -> Dictionary:
	var doing: Array = place.errand.get("doing", ["running an errand"])
	return {
		"pet": uid, "place": place.id, "started": now, "ends": now + float(place.errand.minutes) * 60.0,
		"doing": str(doing[rng.randi_range(0, doing.size() - 1)]),
	}


## What one errand brings back, as loot (see Rewards): coins, maybe a common part, maybe a box.
static func haul(place: Dictionary, rng: RandomNumberGenerator, catalog: Catalog) -> Dictionary:
	var e: Dictionary = place.errand
	var loot := { "coins": rng.randi_range(int(e.coins[0]), int(e.coins[1])) }
	if rng.randf() < float(e.get("part_chance", 0.0)):
		var part := Rewards.roll_part(COMMON_BOX, rng, catalog, place.get("part_slots", []))
		loot["part:%s:%s" % part] = 1
	if rng.randf() < float(e.get("box_chance", 0.0)):
		loot["box:starter"] = 1
	return loot


## Brings errands up to `until`: every errand that's done hands in its haul and its pet comes
## home; free slots get new errands (starting when the last one ended, so time away counts too),
## as long as there are pets and places. `next_pet` gives a spare pet's uid (or "") that isn't
## in `busy`. Returns { loot, done } and updates `errands` in place.
static func run(errands: Array, until: float, places_to_go: Array[Dictionary], next_pet: Callable,
		rng: RandomNumberGenerator, catalog: Catalog) -> Dictionary:
	var loot := {}
	var done := 0
	if places_to_go.is_empty():
		return { "loot": loot, "done": done }
	var by_id := {}
	for place in places_to_go:
		by_id[place.id] = place
	for guard in 2000:  # plenty for a long time away, and never an endless loop
		# the errand that finishes first
		var first := -1
		for i in errands.size():
			if float(errands[i].ends) <= until and (first < 0 or float(errands[i].ends) < float(errands[first].ends)):
				first = i
		if first < 0:
			break
		var errand: Dictionary = errands[first]
		errands.remove_at(first)
		var place: Dictionary = by_id.get(errand.place, catalog.location(errand.place))
		if place.has("errand"):
			Rewards.add(loot, haul(place, rng, catalog))
			done += 1
		_fill(errands, float(errand.ends), places_to_go, next_pet, rng)
	return { "loot": loot, "done": done }


## Starts errands in free slots at `now`, with spare pets.
static func fill(errands: Array, now: float, places_to_go: Array[Dictionary], next_pet: Callable, rng: RandomNumberGenerator) -> void:
	for i in SLOTS:
		_fill(errands, now, places_to_go, next_pet, rng)


static func _fill(errands: Array, now: float, places_to_go: Array[Dictionary], next_pet: Callable, rng: RandomNumberGenerator) -> void:
	if errands.size() >= SLOTS or places_to_go.is_empty():
		return
	var busy := {}
	for e in errands:
		busy[e.pet] = true
	var uid: String = next_pet.call(busy)
	if uid == "":
		return
	errands.append(start(uid, places_to_go[rng.randi_range(0, places_to_go.size() - 1)], now, rng))
