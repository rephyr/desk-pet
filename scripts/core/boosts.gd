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



## A multiplier as the receipt writes it: "x1.25", "x12.5" from 10, "x123" from 100, then "x1.2k",
## "x34M" and so on (boosts can go big late in the game).
static func times(x: float) -> String:
	if x < 10.0:
		return "x%.2f" % x
	if x < 100.0:
		return "x%.1f" % x
	if x < 1000.0:
		return "x%d" % roundi(x)
	var v := x
	for u in ["k", "M", "B", "T"]:
		v /= 1000.0
		if v < 1000.0:
			return "x" + (("%.1f" % v).trim_suffix(".0") if v < 100.0 else str(roundi(v))) + u
	return "x%.1e" % x


## The boost receipt's rows: every kind with parts, in data/boosts.json order, each with its total
## and one line per part, the lines in the "sources" order (toys, book, knacks, kitchen; a source
## not listed goes last). `parts_by_kind` is kind -> its parts (GameState.boost_parts); `namer` is a
## Callable(part) -> String giving a line its name (this knows no game system). Kinds with no parts
## are left out:
##   [ { kind, name, total, lines: [ { source, name, x } ] } ]
static func receipt(catalog: Catalog, parts_by_kind: Dictionary, namer: Callable) -> Array:
	var out := []
	var order: Array = catalog.boosts.get("sources", [])
	for k in catalog.boosts.kinds:
		var parts: Array = parts_by_kind.get(str(k.id), [])
		if parts.is_empty():
			continue
		var lines := []
		for i in order.size() + 1:  # the last round: every source not in the list
			for p in parts:
				if (str(p.source) == str(order[i])) if i < order.size() else not str(p.source) in order:
					lines.append({ "source": str(p.source), "name": str(namer.call(p)), "x": float(p.x) })
		out.append({ "kind": str(k.id), "name": str(k.get("name", k.id)), "total": total(parts), "lines": lines })
	return out


## A "why so much?" slip: where the number starts, what multiplied it (lines at x1 are left out,
## they did nothing), and what it came to:
##   { start: { name, value }, lines: [ { name, x } ], total }
static func why(start_name: String, start_value: float, lines: Array, all_together: float) -> Dictionary:
	var kept := []
	for l in lines:
		if absf(float(l.x) - 1.0) >= 0.005:
			kept.append({ "name": str(l.name), "x": float(l.x) })
	return { "start": { "name": start_name, "value": start_value }, "lines": kept, "total": all_together }
