class_name Rumours
extends RefCounted
## Rumours are what exploration brings back (data/adventures.json): word of a place, which the
## player can then choose to go to. Pure rules: which rumours can still be heard.


## Rumours nobody has heard yet (and not retired), whose requirements are open and that would still open something
## new. `is_open` tells whether an unlock id ("location:well", "parties") is open.
static func hearable(catalog: Catalog, heard: Dictionary, is_open: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rumour in catalog.rumours:
		if heard.has(rumour.id) or rumour.get("retired", false):
			continue  # heard already, or its place is a dungeon band now
		if not rumour.get("requires", []).all(func(id): return is_open.call(id)):
			continue
		if rumour.unlocks.all(func(id): return is_open.call(id)):
			continue
		out.append(rumour)
	return out
