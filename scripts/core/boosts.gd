class_name Boosts
extends RefCounted
## Boosts: how much one kind ("coins", "luck", "speed", ... see data/boosts.json) is multiplied right
## now, and by what. Every source (data/boosts.json "sources": toys, the book's stickers, your active
## pet's knacks, the kitchen's cooks) gives parts
##   { "source": "toys", "id": "acorn:holo", "x": 1.14 }
## and the total is every part's x multiplied together, so boosts from different sources multiply.
## This is only the kind table and the arithmetic: GameState.boost_parts gathers the parts from each
## source (it holds every source's state), so nothing here depends on a game system.


## The kind's row from data/boosts.json ({} when there's no such kind).
static func kind(catalog: Catalog, id: String) -> Dictionary:
	for k in catalog.boosts.kinds:
		if k.id == id:
			return k
	return {}


static func is_kind(catalog: Catalog, id: String) -> bool:
	return not kind(catalog, id).is_empty()


## Every kind's id, in order.
static func kinds(catalog: Catalog) -> Array[String]:
	var out: Array[String] = []
	for k in catalog.boosts.kinds:
		out.append(str(k.id))
	return out


## The kinds a trip packs when it sets off (marked "trip" in data/boosts.json; RunState.knacks).
static func trip_kinds(catalog: Catalog) -> Array[String]:
	var out: Array[String] = []
	for k in catalog.boosts.kinds:
		if bool(k.get("trip", false)):
			out.append(str(k.id))
	return out


## Whether an "all" bonus (a toy's) counts for this kind.
static func all_covers(catalog: Catalog, id: String) -> bool:
	return bool(kind(catalog, id).get("all", false))


## Every part's x multiplied together (1.0 with no parts).
static func total(list: Array) -> float:
	var m := 1.0
	for p in list:
		m *= float(p.x)
	return m


static func part(source: String, id: String, x: float) -> Dictionary:
	return { "source": source, "id": id, "x": x }

