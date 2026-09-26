class_name Rewards
extends RefCounted
## What adventures bring back. A reward in the data is { "kind": ..., ... }. Rolling one turns it
## into loot: { key: amount }, where the key starts with the kind ("coins", "box:starter",
## "part:eyes:sparkle"). GameState.grant() puts loot where it belongs. A new kind of reward needs
## a case in roll() (if it's more than "a chance of one thing") and one in GameState.grant();
## until then it's rolled by chance and kept in GameState.items.

const STAT_NEED := 10.0  # a pet stat that's "about right" for a difficulty 1 location


## How much the party's luck helps with loot (0.5 .. 2).
static func luck(party: Party, location: Dictionary) -> float:
	return clampf(party.average("luck") / (STAT_NEED * float(location.difficulty)), 0.5, 2.0)


const DEEPER := 0.25  # each event further into a trip pays this much more (x1, x1.25, x1.5, ...)


## How much more an event pays for being further into the trip (0 = the first event).
static func depth_boost(events_done: int) -> float:
	return 1.0 + DEEPER * events_done


## Rolls one reward for the pets still in the party. `boost` makes it bigger (further into a trip):
## coins grow by it, chances of finding things by half as much.
static func roll(reward: Dictionary, party: Party, location: Dictionary, rng: RandomNumberGenerator, catalog: Catalog, boost := 1.0) -> Dictionary:
	var here := party.size()
	if here <= 0:
		return {}
	var lucky := luck(party, location)
	var items := sqrt(here) * lucky * (1.0 + (boost - 1.0) * 0.5)  # more pets find more, but not in proportion
	var kind := str(reward.get("kind", ""))
	match kind:
		"coins":
			var amount: Array = reward.get("amount", [0, 0])
			var coins := roundi(rng.randi_range(int(amount[0]), int(amount[1])) * float(location.loot) * here * lucky * boost)
			return { "coins": coins } if coins > 0 else {}
		"box":
			var n := count(float(reward.get("chance", 0.0)) * items, rng)
			return { "box:%s" % reward.get("id", location.box): n } if n > 0 else {}
		"part":
			var out := {}
			for i in count(float(reward.get("chance", 0.0)) * items, rng):
				# a place's parts lean toward its branch's slots (water: eyes and colours, ...)
				var slots: Array = reward.get("slots", location.get("part_slots", []))
				var part := roll_part(str(reward.get("box", location.box)), rng, catalog, slots)
				add(out, { "part:%s:%s" % part: 1 })
			return out
	# any other kind: a chance of one (or more, for big parties) of that thing
	var n := count(float(reward.get("chance", 1.0)) * items, rng)
	return { "%s:%s" % [kind, reward.get("id", "")]: n } if n > 0 else {}


## Adds loot into a running total.
static func add(into: Dictionary, loot: Dictionary) -> void:
	for key in loot:
		into[key] = int(into.get(key, 0)) + int(loot[key])


## How many things of a kind are in some loot (e.g. all the parts).
static func total(loot: Dictionary, kind: String) -> int:
	var n := 0
	for key in loot:
		if key == kind or key.begins_with(kind + ":"):
			n += int(loot[key])
	return n


## A random part at a rarity rolled with a box's odds, as [slot, part id]. With `slots`, mostly
## (3 in 4) from those slots, otherwise from any.
static func roll_part(box_id: String, rng: RandomNumberGenerator, catalog: Catalog, slots: Array = []) -> Array:
	var from: Array = Catalog.SLOTS
	if not slots.is_empty() and rng.randf() < 0.75:
		from = slots
	var slot: String = from[rng.randi_range(0, from.size() - 1)]
	var rank := catalog.rank(Weighted.pick(catalog.box(box_id).tiers, rng))
	for r in range(rank, -1, -1):
		var options := catalog.parts_of_tier(slot, catalog.tier_at(r).id)
		if not options.is_empty():
			return [slot, options[rng.randi_range(0, options.size() - 1)].id]
	return [slot, catalog.default_part(slot)]


## Turns an expected amount into a whole number that averages out to it (2.3 -> 2 or 3).
static func count(expected: float, rng: RandomNumberGenerator) -> int:
	var whole := floori(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)
