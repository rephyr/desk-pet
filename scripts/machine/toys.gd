class_name Toys
extends RefCounted
## Capsule toys' rules (data/toys.json): rolling one out of a capsule, what a toy's boost is worth,
## playing with toys (the boost only works while your pet plays), wear, fixing, combining spares
## into levels and sacrificing them for a special finish. Works on the toys' state from the save:
##   { owned: { "snail:holo": { level, spares, wear } }, playing: [ { key, until, wear } ] }
## Every toy you own is an edition (toy + finish), keyed "toy id:finish id".

## A toy's bonus is a boost kind (data/boosts.json) or "all" (the kinds marked "all" there).


static func data(catalog: Catalog) -> Dictionary:
	return catalog.toys


## Every toy, from every set, in order.
static func all(catalog: Catalog) -> Array:
	var out: Array = []
	for s in catalog.toys.sets:
		out.append_array(s.toys)
	return out


static func toy(catalog: Catalog, id: String) -> Dictionary:
	for t in all(catalog):
		if t.id == id:
			return t
	return {}


static func finish(catalog: Catalog, id: String) -> Dictionary:
	for f in catalog.toys.finishes:
		if f.id == id:
			return f
	return {}


static func key(id: String, finish_id: String) -> String:
	return "%s:%s" % [id, finish_id]


static func split(edition: String) -> PackedStringArray:
	return edition.split(":")


## Rolls a toy out of a capsule: its tier (rarer tiers weigh more with luck), which toy of that
## tier, and its finish (special finishes weigh more with luck). Returns { id, finish }.
static func roll(catalog: Catalog, rng: RandomNumberGenerator, luck := 1.0) -> Dictionary:
	var d := data(catalog)
	var tiers := {}
	for tier_id in d.tiers:
		var w := float(d.tiers[tier_id].weight)
		tiers[tier_id] = w if tier_id == "common" else w * luck
	var tier: String = Weighted.pick(tiers, rng)
	var pool := all(catalog).filter(func(t): return t.tier == tier)
	var picked: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var finishes := {}
	for f in d.finish_odds:
		finishes[f] = float(d.finish_odds[f]) * (1.0 if f == "normal" else luck)
	return { "id": picked.id, "finish": Weighted.pick(finishes, rng) }


## Puts a toy into your collection: a new edition at level 1, or one more spare. Returns whether
## it was a new edition.
static func add(state: Dictionary, id: String, finish_id: String) -> bool:
	var k := key(id, finish_id)
	if state.owned.has(k):
		state.owned[k].spares = int(state.owned[k].spares) + 1
		return false
	state.owned[k] = { "level": 1, "spares": 0, "wear": 0.0 }
	return true


## Whether you have any edition of this toy.
static func has_toy(state: Dictionary, id: String) -> bool:
	return state.owned.keys().any(func(k): return split(k)[0] == id)


static func is_favourite(state: Dictionary, catalog: Catalog, edition: String) -> bool:
	var e: Dictionary = state.owned.get(edition, {})
	return not e.is_empty() and int(e.level) >= int(data(catalog).max_level)


## What an edition multiplies its bonus by right now, e.g. 1.1 (level, finish and wear).
static func boost(state: Dictionary, catalog: Catalog, edition: String) -> float:
	var e: Dictionary = state.owned.get(edition, {})
	if e.is_empty():
		return 1.0
	var bits := split(edition)
	var t := toy(catalog, bits[0])
	var tier: Dictionary = data(catalog).tiers[t.tier]
	var extra := float(tier.base) - 1.0 + float(tier.per_level) * (int(e.level) - 1)
	extra *= float(finish(catalog, bits[1]).get("boost", 1.0))
	if not is_favourite(state, catalog, edition):
		extra *= lerpf(1.0, float(data(catalog).worn_floor), clampf(float(e.wear), 0.0, 1.0))
	return 1.0 + extra


## Play slots: how many toys your pet can play with at once (one more for every finished set).
static func slots(state: Dictionary, catalog: Catalog) -> int:
	var n := int(data(catalog).slots)
	for s in catalog.toys.sets:
		if set_done(state, s):
			n += 1
	return n


static func set_done(state: Dictionary, set_data: Dictionary) -> bool:
	return set_data.toys.all(func(t): return has_toy(state, t.id))


## Editions working right now: the ones being played with, and favourites (always on).
static func active(state: Dictionary, catalog: Catalog, now: float) -> Array:
	var out: Array = []
	for p in state.playing:
		if float(p.until) > now:
			out.append(p.key)
	for k in state.owned:
		if is_favourite(state, catalog, k) and not k in out:
			out.append(k)
	return out


## The toys' parts of one boost kind (see Boosts): one for every edition working on it right now.
static func parts(state: Dictionary, catalog: Catalog, kind: String, now: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var covers_all := Boosts.all_covers(catalog, kind)
	for k in active(state, catalog, now):
		var bonus: String = toy(catalog, split(k)[0]).get("bonus", "")
		if bonus == kind or (bonus == "all" and covers_all):
			out.append(Boosts.part("toys", k, boost(state, catalog, k)))
	return out



static func play_info(catalog: Catalog, play_id: String) -> Dictionary:
	for p in data(catalog).play:
		if p.id == play_id:
			return p
	return {}


## Whether this edition is being played with right now.
static func playing(state: Dictionary, edition: String, now: float) -> bool:
	return state.playing.any(func(p): return p.key == edition and float(p.until) > now)


## Seconds left on a play (0 when it isn't being played with).
static func left(state: Dictionary, edition: String, now: float) -> float:
	for p in state.playing:
		if p.key == edition:
			return maxf(0.0, float(p.until) - now)
	return 0.0


## Your pet starts playing with a toy for one of the play lengths. Returns whether it could (you
## have it, it's not already being played with or a favourite, and there's a free slot).
static func play(state: Dictionary, catalog: Catalog, edition: String, play_id: String, now: float) -> bool:
	var info := play_info(catalog, play_id)
	if info.is_empty() or not state.owned.has(edition) or playing(state, edition, now) or is_favourite(state, catalog, edition):
		return false
	var busy: int = state.playing.filter(func(p): return float(p.until) > now).size()
	if busy >= slots(state, catalog):
		return false
	var e: Dictionary = state.owned[edition]
	var sturdy := maxf(0.2, 1.0 - float(data(catalog).sturdier) * (int(e.level) - 1))
	state.playing.append({ "key": edition, "until": now + float(info.minutes) * 60.0, "wear": float(info.wear) * sturdy })
	return true


## Ends plays whose time is up: the toy wears a little and goes back on the shelf. Returns the
## editions that just finished.
static func finish_plays(state: Dictionary, now: float) -> Array:
	var done: Array = []
	var still: Array = []
	for p in state.playing:
		if float(p.until) <= now:
			if state.owned.has(p.key):
				state.owned[p.key].wear = minf(1.0, float(state.owned[p.key].wear) + float(p.wear))
			done.append(p.key)
		else:
			still.append(p)
	state.playing = still
	return done


## Coins to fix a toy's wear on the workbench (0 when it's as good as new).
static func fix_cost(state: Dictionary, catalog: Catalog, edition: String) -> int:
	var e: Dictionary = state.owned.get(edition, {})
	if e.is_empty():
		return 0
	var t := toy(catalog, split(edition)[0])
	return ceili(float(data(catalog).tiers[t.tier].fix_cost) * float(e.wear))


## Spares needed to take this edition to its next level (0 when it's at the top).
static func combine_cost(state: Dictionary, catalog: Catalog, edition: String) -> int:
	var e: Dictionary = state.owned.get(edition, {})
	var costs: Array = data(catalog).combine
	if e.is_empty() or int(e.level) >= int(data(catalog).max_level):
		return 0
	return int(costs[mini(int(e.level) - 1, costs.size() - 1)])


static func can_combine(state: Dictionary, catalog: Catalog, edition: String) -> bool:
	var need := combine_cost(state, catalog, edition)
	return need > 0 and int(state.owned[edition].spares) >= need


## Spares go in, the edition comes out one level better. Always works.
static func combine(state: Dictionary, catalog: Catalog, edition: String) -> bool:
	if not can_combine(state, catalog, edition):
		return false
	var e: Dictionary = state.owned[edition]
	e.spares = int(e.spares) - combine_cost(state, catalog, edition)
	e.level = int(e.level) + 1
	return true


static func can_sacrifice(state: Dictionary, catalog: Catalog, id: String) -> bool:
	var e: Dictionary = state.owned.get(key(id, "normal"), {})
	return not e.is_empty() and int(e.spares) >= int(data(catalog).sacrifice.spares)


## Gives up spares of a toy's normal edition for a chance at a special finish of it. Returns the
## finish that came out, or "" for nothing (the spares are gone either way).
static func sacrifice(state: Dictionary, catalog: Catalog, id: String, rng: RandomNumberGenerator) -> String:
	if not can_sacrifice(state, catalog, id):
		return ""
	var e: Dictionary = state.owned[key(id, "normal")]
	e.spares = int(e.spares) - int(data(catalog).sacrifice.spares)
	var got: String = Weighted.pick(data(catalog).sacrifice.odds, rng)
	if got == "nothing":
		return ""
	add(state, id, got)
	return got


static func fresh() -> Dictionary:
	return { "owned": {}, "playing": [] }
