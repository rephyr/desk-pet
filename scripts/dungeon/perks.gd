class_name Perks
extends RefCounted
## The wisps perk tree on the well wall (data/perks.json): coral things on nails down the left lane
## of the dungeon's column, one per landing. A CHAIN: a link can be bought once the one above it has
## at least 1 level (the bow on the roof post, the entrance, is the first). A nail shows once the
## army has been down to its floor and its 'needs' unlock is open; hidden ones stay fully hidden.
## Once every link has a level, the 2 endless TIPS at the bottom show. Only wisps buy perks.
## A link does a boost kind (a multiplier: parts() for GameState.boost_parts) or a count the game
## reads instead (count(): the entrance, the front row, hours away, plushie holds and nudges).
## Pure rules: the state is { perk id: level } (only levels > 0 are kept), GameState keeps it.


static func data(catalog: Catalog) -> Dictionary:
	return catalog.perks


static func chain(catalog: Catalog) -> Array:
	return data(catalog).get("chain", [])


static func tips(catalog: Catalog) -> Array:
	return data(catalog).get("tips", [])


## A link or a tip by id ({} when there's none).
static func perk(catalog: Catalog, id: String) -> Dictionary:
	for p in chain(catalog):
		if str(p.id) == id:
			return p
	for t in tips(catalog):
		if str(t.id) == id:
			return t
	return {}


static func is_tip(catalog: Catalog, id: String) -> bool:
	return tips(catalog).any(func(t): return str(t.id) == id)


## Where a link is in the chain (-1 for a tip or an unknown id).
static func index(catalog: Catalog, id: String) -> int:
	var links := chain(catalog)
	for i in links.size():
		if str(links[i].id) == id:
			return i
	return -1


static func level(state: Dictionary, id: String) -> int:
	return int(state.get(id, 0))


## A link's last level (its steps past nothing bought); -1 for a tip (endless).
static func max_level(p: Dictionary) -> int:
	if not p.has("steps"):
		return -1
	return p.steps.size() - 1


static func maxed(catalog: Catalog, state: Dictionary, id: String) -> bool:
	var p := perk(catalog, id)
	var top := max_level(p)
	return top >= 0 and level(state, id) >= top


## What a perk does at a level: a link's step, a tip's multiplier (1 + each x level).
static func value_at(p: Dictionary, lv: int) -> float:
	if p.has("steps"):
		return float(p.steps[clampi(lv, 0, p.steps.size() - 1)])
	return 1.0 + float(p.get("each", 0.04)) * maxi(lv, 0)


static func value(catalog: Catalog, state: Dictionary, id: String) -> float:
	return value_at(perk(catalog, id), level(state, id))


## What the next level costs in wisps (-1 when it's maxed or there's no such perk). Tips: base x
## grow ^ level, never past price_max (worked out in floats, so it never wraps).
static func price(catalog: Catalog, state: Dictionary, id: String) -> int:
	var p := perk(catalog, id)
	if p.is_empty() or maxed(catalog, state, id):
		return -1
	var cap := float(data(catalog).get("price_max", 4e18))
	var lv := level(state, id)
	if p.has("steps"):
		return int(minf(float(p.price[mini(lv, p.price.size() - 1)]), cap))
	return int(minf(float(p.get("base", 1)) * pow(float(p.get("grow", 3)), lv), cap))


## Whether every link of the chain has at least 1 level (the tips show then).
static func chain_done(catalog: Catalog, state: Dictionary) -> bool:
	return chain(catalog).all(func(p): return level(state, str(p.id)) > 0)


## Whether a link's nail shows: the army has been down to its floor and its needs is open
## (`is_open`: unlock id -> bool). Tips show once the chain is done.
static func nail_shown(catalog: Catalog, state: Dictionary, id: String, deep: int, is_open: Callable) -> bool:
	var p := perk(catalog, id)
	if p.is_empty():
		return false
	if not p.has("steps"):
		return chain_done(catalog, state)
	return int(p.get("floor", 0)) <= deep and (str(p.get("needs", "")) == "" or is_open.call(str(p.needs)))


## The perks on the wall, in order: the chain's nails that show, then the tips (once it's done).
static func shown(catalog: Catalog, state: Dictionary, deep: int, is_open: Callable) -> Array[String]:
	var out: Array[String] = []
	for p in chain(catalog):
		if nail_shown(catalog, state, str(p.id), deep, is_open):
			out.append(str(p.id))
	if chain_done(catalog, state):
		for t in tips(catalog):
			out.append(str(t.id))
	return out


## Whether a perk can be bought now (wisps aside): it shows, it isn't maxed, and the link above
## it has a level (the first link has none above it).
static func available(catalog: Catalog, state: Dictionary, id: String, deep: int, is_open: Callable) -> bool:
	if not nail_shown(catalog, state, id, deep, is_open) or maxed(catalog, state, id):
		return false
	var i := index(catalog, id)
	return i <= 0 or level(state, str(chain(catalog)[i - 1].id)) > 0


## Buys the next level of a perk with `wisps`: returns what it cost (the state has the new level),
## or -1 when it can't (not available, or not enough wisps).
static func buy(catalog: Catalog, state: Dictionary, id: String, wisps: int, deep: int, is_open: Callable) -> int:
	if not available(catalog, state, id, deep, is_open):
		return -1
	var cost := price(catalog, state, id)
	if cost < 0 or wisps < cost:
		return -1
	state[id] = level(state, id) + 1
	return cost


## What a count starts at with no link bought: the entrance's width and the front row live in
## data/dungeon.json (entrance.start, front_row), everything else starts at 0. A count link's steps
## are ADDED on top of this, so the base is tuned in one place.
static func count_base(catalog: Catalog, name: String) -> float:
	var d: Dictionary = catalog.dungeon
	match name:
		"entrance":
			return float(d.get("entrance", {}).get("start", 300))
		"front_row":
			return float(d.get("front_row", 20))
	return 0.0


## The count link for a count name ({} when none counts it).
static func count_link(catalog: Catalog, name: String) -> Dictionary:
	for p in chain(catalog):
		if str(p.get("count", "")) == name:
			return p
	return {}


## The number a count gives now (the entrance, front_row, away_hours, holds, nudges): its base plus
## its link's step (just the base when no link counts it).
static func count(catalog: Catalog, state: Dictionary, name: String) -> float:
	var p := count_link(catalog, name)
	return count_at(catalog, name, level(state, str(p.id)) if not p.is_empty() else 0)


## A count's number with its link at level `lv` (the entrance by its saved level).
static func count_at(catalog: Catalog, name: String, lv: int) -> float:
	var p := count_link(catalog, name)
	return count_base(catalog, name) + (value_at(p, lv) if not p.is_empty() else 0.0)


## What a perk's card shows at a level: a count link's whole count, else what it does (value_at).
static func card_value(catalog: Catalog, p: Dictionary, lv: int) -> float:
	if p.has("count"):
		return count_at(catalog, str(p.count), lv)
	return value_at(p, lv)


## What the perks do for a boost kind: a part per link or tip of that kind with a level.
static func parts(catalog: Catalog, state: Dictionary, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in chain(catalog) + tips(catalog):
		if str(p.get("kind", "")) == kind and level(state, str(p.id)) > 0:
			out.append(Boosts.part("perks", str(p.id), value_at(p, level(state, str(p.id)))))
	return out


## A saved state made safe: known ids only, links clamped to their max, tips any level; levels of 0 dropped.
static func clean(catalog: Catalog, raw) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for id in raw:
		var p := perk(catalog, str(id))
		var v = raw[id]
		if p.is_empty() or not (v is int or v is float):
			continue
		var lv := maxi(0, int(v))
		if max_level(p) >= 0:
			lv = mini(lv, max_level(p))
		if lv > 0:
			out[str(id)] = lv
	return out
