class_name NewHomes
extends RefCounted
## New homes (data/new_homes.json): pets leave for good and pay points toward a box. The stall on
## the pets tab takes them by the shelf; the sorting rule sends new pets from box openings to new
## homes (or to work, or to school) as they arrive. Pure rules on the state from the save:
##   { points: toward the next box, by_hand: pets you sent from the stall ever, sorted: pets the
##     rule sorted ever, room_was_full: the room has been full at least once (the stall opens),
##     rule: { on, below: rarity id, to: "homes" | "work" | "school", keep: finish id },
##     today: { day: "YYYY-MM-DD", n: pets the rule sorted that day } }
## GameState keeps the state, takes the pets out of the collection and hands out the boxes.

const TO := ["homes", "work", "school"]  # school: only once it's open (GameState.rule_destinations)


static func fresh(catalog: Catalog) -> Dictionary:
	var d: Dictionary = catalog.new_homes.get("rule_default", {})
	return { "points": 0, "by_hand": 0, "sorted": 0, "room_was_full": false,
		"rule": { "on": false, "below": str(d.get("below", "rare")), "to": str(d.get("to", "homes")), "keep": str(d.get("keep", "holo")) },
		"today": { "day": "", "n": 0 } }


## A saved state, checked: unknown rarities or finishes fall back to the defaults.
static func clean(catalog: Catalog, raw) -> Dictionary:
	var out := fresh(catalog)
	if not raw is Dictionary:
		return out
	out.points = clampi(int(_num(raw.get("points", 0))), 0, box_at(catalog) - 1)
	out.by_hand = maxi(0, int(_num(raw.get("by_hand", 0))))
	out.sorted = maxi(0, int(_num(raw.get("sorted", 0))))
	out.room_was_full = bool(raw.get("room_was_full", false))
	var rule = raw.get("rule", {})
	if rule is Dictionary:
		out.rule.on = bool(rule.get("on", false))
		if catalog.tiers.any(func(t): return t.id == str(rule.get("below", ""))):
			out.rule.below = str(rule.below)
		if str(rule.get("to", "")) in TO:
			out.rule.to = str(rule.to)
		if catalog.finish(str(rule.get("keep", ""))).id == str(rule.get("keep", "")):
			out.rule.keep = str(rule.keep)
	var today = raw.get("today", {})
	if today is Dictionary:
		out.today = { "day": str(today.get("day", "")), "n": maxi(0, int(_num(today.get("n", 0)))) }
	return out


## Points per box.
static func box_at(catalog: Catalog) -> int:
	return maxi(1, int(catalog.new_homes.get("box_at", 25)))


## The box the points pay.
static func box_id(catalog: Catalog) -> String:
	var id := str(catalog.new_homes.get("box", "starter"))
	return id if not catalog.box(id).is_empty() else str(catalog.boxes[0].id)


## Points one pet of a rarity is worth.
static func worth(catalog: Catalog, rarity: String) -> int:
	return maxi(0, int(catalog.new_homes.get("worth", {}).get(rarity, 1)))


## Adds the points for `n` pets of a rarity to the jar. Returns how many boxes filled up (the
## leftover stays in the jar).
static func pay(state: Dictionary, catalog: Catalog, rarity: String, n: int) -> int:
	if n <= 0:
		return 0
	var at := box_at(catalog)
	var total := int(state.get("points", 0)) + worth(catalog, rarity) * n
	state.points = total % at
	return total / at


## Whether the rule sorts this new pet: below the line, below the keep finish, and not one that
## always stays (a part new to the book, a favourite).
static func sorts(catalog: Catalog, rule: Dictionary, pet: Pet) -> bool:
	if not rule.get("on", false) or pet.new_part or pet.fav:
		return false
	return catalog.rank(pet.rarity) < catalog.rank(str(rule.below)) and catalog.finish_rank(pet.finish) < catalog.finish_rank(str(rule.keep))


## Whether a shelf is under the rule's line (it shows "sorted today").
static func below_line(catalog: Catalog, rule: Dictionary, rarity: String) -> bool:
	return rule.get("on", false) and catalog.rank(rarity) < catalog.rank(str(rule.below))


## Today's date, local ("2026-09-29").
static func today() -> String:
	return Time.get_date_string_from_system()


## Pets the rule sorted on `day` (0 when the saved count is from another day).
static func sorted_on(state: Dictionary, day: String) -> int:
	var t: Dictionary = state.get("today", {})
	return int(t.get("n", 0)) if str(t.get("day", "")) == day else 0


## One more pet sorted on `day` (a new day starts the count over).
static func count_sorted(state: Dictionary, day: String, n := 1) -> void:
	state.today = { "day": day, "n": sorted_on(state, day) + n }
	state.sorted = int(state.get("sorted", 0)) + n


static func _num(v) -> float:
	return float(v) if (v is int or v is float) else 0.0
