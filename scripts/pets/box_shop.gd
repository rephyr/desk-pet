class_name BoxShop
extends RefCounted
## The rules for the box tiers (sunny, sunset, midnight: data/boxes.json), kept apart from
## GameState so tests can check them: which tiers the shop sells, which piles your pet or the
## workers open, and how old saves' lucky boxes turn into sunset boxes.

const RETIRED := { "lucky": "sunset" }  # boxes that are gone -> the box that took their place


## The tiers in the shop: the ones whose map page is open (`page_open` takes a page id), cheapest
## first. `all` (a dev switch) puts every tier in, pages or not.
static func open_tiers(catalog: Catalog, page_open: Callable, all := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in catalog.shop_boxes():
		if all or page_open.call(str(b.get("page", catalog.pages[0].id))):
			out.append(b)
	return out


## How to open `count` boxes from the pile: { box id: how many }, going through `order` (the
## kinds that may be opened, in turn) until there are enough. Counts boxes, not the pets in them.
static func split_open(bag: Dictionary, order: Array, count: int) -> Dictionary:
	var out := {}
	var left := count
	for id in order:
		if left <= 0:
			break
		var n := mini(left, int(bag.get(id, 0)))
		if n > 0:
			out[id] = n
			left -= n
	return out


## Rarest first, then by finish (the pet a box shows off first).
static func best_first(pets: Array[Pet], catalog: Catalog) -> Array[Pet]:
	var sorted := pets.duplicate()
	sorted.sort_custom(func(a: Pet, b: Pet):
		var ra := catalog.rank(a.rarity)
		var rb := catalog.rank(b.rarity)
		if ra != rb:
			return ra > rb
		return catalog.finish_rank(a.finish) > catalog.finish_rank(b.finish))
	return sorted


## The lucky box is retired. Runs on every load (whatever the save's version, and safe to run
## twice): boxes of it on the pile become sunset boxes (one for one), "save for me" carries over,
## and adventures still out bring sunset boxes instead (also old runs' pre-v5 `boxes` field).
## Saves from before the tiers (no `boxes_bought` yet) count the tiers already on the pile as
## bought, so they don't show up as new.
static func fix_retired(data: Dictionary) -> void:
	var bag: Dictionary = data.get("bag", {}) if data.get("bag", {}) is Dictionary else {}
	for old in RETIRED:
		if bag.has(old):
			bag[RETIRED[old]] = int(bag.get(RETIRED[old], 0)) + int(bag[old])
			bag.erase(old)
	data.bag = bag
	var saved: Array = []
	for id in data.get("saved_boxes", []):
		var now: String = RETIRED.get(str(id), str(id))
		if not now in saved:
			saved.append(now)
	data.saved_boxes = saved
	for run in data.get("runs", []):
		if run is Dictionary:
			if run.has("loot"):
				run["loot"] = _renamed_loot(run.loot)
			if run.get("boxes", null) is Dictionary:
				run["boxes"] = _renamed(run.boxes)
			for h in run.get("log", []):
				if h is Dictionary and h.has("loot"):
					h["loot"] = _renamed_loot(h.loot)
	if not data.has("boxes_bought"):
		var bought := {}
		for id in bag:
			if int(bag[id]) > 0:
				bought[id] = 1
		data.boxes_bought = bought
		if not data.has("boxes_greeted"):
			data.boxes_greeted = bought.keys()


static func _renamed(boxes: Dictionary) -> Dictionary:
	var out := {}
	for key in boxes:
		var k: String = RETIRED.get(str(key), str(key))
		out[k] = int(out.get(k, 0)) + int(boxes[key])
	return out


static func _renamed_loot(loot) -> Dictionary:
	var out := {}
	if not loot is Dictionary:
		return out
	for key: String in loot:
		var k := key
		if key.begins_with("box:") and RETIRED.has(key.substr(4)):
			k = "box:" + str(RETIRED[key.substr(4)])
		out[k] = int(out.get(k, 0)) + int(loot[key])
	return out
