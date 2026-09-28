class_name Herd
extends RefCounted
## The herd: plain pets (below the card_from finish) folded into a count per rarity x finish, so
## millions fit in the save and on screen (data/herd.json). A count is keyed "rarity:finish", e.g.
## "common:normal". Where a whole pet is needed for a pet from a count (a face in a crowd, a pet on
## an adventure) a STAND-IN is made: a pet with a look rolled from a seed, its rarity's average
## stats and no traits, whose uid "h:<rarity>:<finish>:<n>" says which count it belongs to.
## Pure helpers; Collection keeps the counts.

const PREFIX := "h:"
const STAND_IN_CACHE := 4096  # stand-ins kept around; past this the cache starts over (they're rolled from a seed)
const MOUND_LOG_SPAN := 4.8  # a mound reaches its most pets at about 10^4.8 (~63k) in the count

static var _stand_ins := {}  # uid -> Pet
static var _templates := {}  # key -> Pet: average stats, for working out speeds


static func key(rarity: String, finish: String) -> String:
	return "%s:%s" % [rarity, finish]


static func rarity_of(k: String) -> String:
	return k.get_slice(":", 0)


static func finish_of(k: String) -> String:
	return k.get_slice(":", 1)


## Whether a uid is a stand-in for a pet from a count.
static func is_stand_in(uid: String) -> bool:
	return uid.begins_with(PREFIX)


static func uid(k: String, n: int) -> String:
	return "%s%s:%d" % [PREFIX, k, n]


## The count a stand-in's uid belongs to ("common:normal").
static func key_of(stand_in_uid: String) -> String:
	var bits := stand_in_uid.split(":")
	return "%s:%s" % [bits[1], bits[2]] if bits.size() >= 4 else ""


static func number_of(stand_in_uid: String) -> int:
	var bits := stand_in_uid.split(":")
	return int(bits[3]) if bits.size() >= 4 else 0


## Whether a count key names a rarity and a finish that exist.
static func valid_key(catalog: Catalog, k: String) -> bool:
	var rarity := rarity_of(k)
	return catalog.tiers.any(func(t): return t.id == rarity) and catalog.finish(finish_of(k)).id == finish_of(k)


## Counts from a save: known keys with a positive whole number only.
static func clean_counts(catalog: Catalog, raw) -> Dictionary:
	var out := {}
	if raw is Dictionary:
		for k in raw:
			var v = raw[k]
			if (v is int or v is float) and valid_key(catalog, str(k)) and int(v) > 0:
				out[str(k)] = int(v)
	return out


## Takes `n` off a count in `counts` (the key goes when it reaches 0).
static func take(counts: Dictionary, k: String, n: int) -> void:
	var left := int(counts.get(k, 0)) - n
	if left > 0:
		counts[k] = left
	else:
		counts.erase(k)


## Adds `n` to a count in `counts`.
static func put(counts: Dictionary, k: String, n: int) -> void:
	if n > 0:
		counts[k] = int(counts.get(k, 0)) + n


static func total(counts: Dictionary) -> int:
	var n := 0
	for k in counts:
		n += int(counts[k])
	return n


## Whether a finish is plain (folds into the herd) rather than always a card.
static func plain(catalog: Catalog, finish: String) -> bool:
	return catalog.finish_rank(finish) < catalog.finish_rank(str(catalog.herd.get("card_from", "holo")))


## A herd pet's stats: the middle of what PetRoller rolls for its rarity.
static func stats_for(catalog: Catalog, rarity: String) -> Dictionary:
	var base := PetRoller.STAT_BASE * (catalog.rank(rarity) + 1)
	var out := {}
	for stat in Pet.STATS:
		out[stat] = roundi(base * 1.5)
	return out


## A pet with a count's rarity, finish and average stats (no look): what speeds are worked out with.
static func template(catalog: Catalog, k: String) -> Pet:
	if not _templates.has(k):
		var p := Pet.new()
		p.rarity = rarity_of(k)
		p.finish = finish_of(k)
		p.stats = stats_for(catalog, p.rarity)
		p.parts = {}
		for slot in Catalog.SLOTS:
			p.parts[slot] = catalog.default_part(slot)
		_templates[k] = p
	return _templates[k]


## The stand-in pet for a uid "h:<rarity>:<finish>:<n>": the same look every time for the same uid.
static func stand_in(catalog: Catalog, stand_in_uid: String) -> Pet:
	if _stand_ins.has(stand_in_uid):
		return _stand_ins[stand_in_uid]
	var k := key_of(stand_in_uid)
	var rarity := rarity_of(k)
	if k == "" or not catalog.tiers.any(func(t): return t.id == rarity):
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(stand_in_uid)
	var roller := PetRoller.new(catalog, rng)
	var box := "starter" if not catalog.box("starter").is_empty() else str(catalog.boxes[0].id)
	var p := roller.roll(box, rarity)
	p.uid = stand_in_uid
	p.rarity = rarity
	p.finish = catalog.finish(finish_of(k)).id
	p.traits.clear()
	p.stats = stats_for(catalog, rarity)
	p.pulled_at = 0
	if _stand_ins.size() >= STAND_IN_CACHE:
		_stand_ins.clear()
	_stand_ins[stand_in_uid] = p
	return p


# ---- the room: one cap for every plain pet together, grown with coins ----------------------

## How many plain pets fit in the room at `level`.
static func room_cap(catalog: Catalog, level: int) -> int:
	var r: Dictionary = catalog.herd.get("room", {})
	var step := maxi(1, int(r.get("round", 50)))
	var raw := float(r.get("start", 500)) * pow(float(r.get("grow", 1.5)), maxi(0, level))
	return maxi(step, roundi(minf(raw, 1.0e15) / step) * step)


## The smallest room level that holds `n` plain pets.
static func room_level_for(catalog: Catalog, n: int) -> int:
	var level := 0
	while room_cap(catalog, level) < n and level < 200:
		level += 1
	return level


## What the next room upgrade costs, with `level` bought already.
static func room_cost(catalog: Catalog, level: int) -> int:
	var r: Dictionary = catalog.herd.get("room", {})
	return roundi(minf(float(r.get("coins", 500)) * pow(float(r.get("cost_grow", 1.8)), maxi(0, level)), Jobs.MAX_PRICE))


## How many tiny pets a mound shows for `count` pets: grows slowly (about log10), at most mound_max.
## `most` overrides mound_max (a smaller heap, such as a chip).
static func mound_size(catalog: Catalog, count: int, most := -1) -> int:
	if count <= 0:
		return 0
	if most < 0:
		most = int(catalog.herd.get("mound_max", 60))
	return mini(count, clampi(roundi(log(count + 1.0) / log(10.0) * most / MOUND_LOG_SPAN), 1, most))
