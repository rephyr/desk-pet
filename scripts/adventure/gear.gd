class_name Gear
extends RefCounted
## Gear: upgrades to adventuring itself, bought with xp (data/gear.json). Pure rules: the catalog
## and the levels you own go in, numbers come out. A trip packs the levels it set off with
## (RunState.gear, see for_trip), and AdventureRunner, GameState and the trail read their values
## from that, so gear bought mid-trip helps the next trip, and a trip caught up after the game was
## closed goes the same way.


## Every gear entry, in path order.
static func all(catalog: Catalog) -> Array:
	return catalog.gear.get("gear", [])


## One gear entry by id, or {}.
static func info(catalog: Catalog, id: String) -> Dictionary:
	for g in all(catalog):
		if g.id == id:
			return g
	return {}


static func level(levels: Dictionary, id: String) -> int:
	return int(levels.get(id, 0))


## A value with every level of gear added: base + each x level (e.g. "walk", "treat_every").
static func value(catalog: Catalog, levels: Dictionary, key: String) -> float:
	var v := float(catalog.gear.get("base", {}).get(key, 0.0))
	if levels.is_empty():
		return v
	for g in all(catalog):
		var lv := level(levels, str(g.id))
		if lv > 0 and g.each.has(key):
			v += float(g.each[key]) * lv
	return v


## xp for the next level, when you have `have` levels.
static func price(catalog: Catalog, id: String, have: int) -> int:
	var g := info(catalog, id)
	if g.is_empty():
		return 0
	return roundi(float(g.xp) * pow(float(g.get("grow", 1.0)), have))


## What a gear does at a level, as the page shows it ("trips 16% shorter"); "as usual" at 0.
## `parts_on`: parts are open, so gear that also works on parts says so.
static func words(catalog: Catalog, id: String, at: int, parts_on := false) -> String:
	var g := info(catalog, id)
	if g.is_empty():
		return ""
	if at <= 0:
		return str(catalog.gear.get("zero_text", ""))
	var text := str(g.get("show_parts", g.show)) if parts_on else str(g.show)
	for key: String in g.each:
		var v := value(catalog, { id: at }, key)
		text = text.replace("{%s%%}" % key, _number(v * 100.0)).replace("{%s}" % key, _number(v))
	return text


## The stickers on the path right now, in path order: boots and the tote from the start, then each
## once the one it comes "after" has a level and what it "needs" is open (`is_open` takes an unlock
## or location id). The rest aren't shown at all.
static func shown(catalog: Catalog, levels: Dictionary, is_open: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for g in all(catalog):
		if g.has("after") and level(levels, str(g.after)) <= 0:
			continue
		if g.has("needs") and not is_open.call(str(g.needs)):
			continue
		out.append(g)
	return out


## The levels a trip to `location` packs: all of them, except at place types that say "gear": false
## in data/adventures.json (dungeons: losses are the cost there).
static func for_trip(catalog: Catalog, levels: Dictionary, location: Dictionary) -> Dictionary:
	if not catalog.adventure_type(str(location.get("type", ""))).get("gear", true):
		return {}
	var out := {}
	for id in levels:
		if int(levels[id]) > 0:
			out[str(id)] = int(levels[id])
	return out


## Saved levels made safe: unknown gear dropped, levels kept within 0..max.
static func clean(catalog: Catalog, saved: Dictionary) -> Dictionary:
	var out := {}
	for id in saved:
		var g := info(catalog, str(id))
		if not g.is_empty():
			var lv := clampi(int(saved[id]), 0, int(g.max))
			if lv > 0:
				out[str(id)] = lv
	return out


## What goes on a trip's line when the first-aid leaf saved someone.
static func leaf_text(catalog: Catalog) -> String:
	return str(catalog.gear.get("leaf_text", ""))


## 8 as "8", 1.75 as "1.75", 0.4 as "0.4".
static func _number(v: float) -> String:
	var r := snappedf(v, 0.01)
	if is_equal_approx(r, roundf(r)):
		return str(roundi(r))
	return str(r)
