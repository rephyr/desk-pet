class_name Book
extends RefCounted
## The collection book's reward stickers (data/book.json): filling a page opens its sticker for
## good, a small permanent boost of one kind (coins, luck, automation, errands; a Boosts part, see
## GameState.boost_parts). Pure rules; the stickers you've opened are a list of page ids kept in
## the save (GameState.stickers).
## A page is a part slot's page ("slot") or one body's finishes page ("finishes_of").


static func pages(catalog: Catalog) -> Array:
	return catalog.book.get("pages", [])


static func page(catalog: Catalog, id: String) -> Dictionary:
	for p in pages(catalog):
		if str(p.id) == id:
			return p
	return {}


## The sticker page for a part slot's page (body = "") or for a body's finishes page, or {}.
static func page_for(catalog: Catalog, slot: String, body := "") -> Dictionary:
	for p in pages(catalog):
		if body == "" and str(p.get("slot", "")) == slot and slot != "":
			return p
		if body != "" and str(p.get("finishes_of", "")) == body:
			return p
	return {}


## The book keys (Collection.part_key / finish_key) a page needs, in book order.
static func keys(catalog: Catalog, p: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if p.has("slot"):
		for part in catalog.slots.get(str(p.slot), []):
			out.append(Collection.part_key(str(p.slot), str(part.id)))
	elif p.has("finishes_of"):
		for f in catalog.finishes:
			out.append(Collection.finish_key(str(p.finishes_of), str(f.id)))
	return out


## Whether every sticker on a page has been found.
static func full(catalog: Catalog, collection: Collection, p: Dictionary) -> bool:
	var need := keys(catalog, p)
	return not need.is_empty() and need.all(func(k): return collection.times_seen(k) > 0)


## Pages that are full now but whose sticker isn't open yet (ids, in book order).
static func newly_full(catalog: Catalog, collection: Collection, stickers: Array) -> Array[String]:
	var out: Array[String] = []
	for p in pages(catalog):
		if not stickers.has(str(p.id)) and full(catalog, collection, p):
			out.append(str(p.id))
	return out


## The open stickers' parts of one boost kind (see Boosts): one per open sticker of that kind.
static func parts(catalog: Catalog, stickers: Array, kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pages(catalog):
		if stickers.has(str(p.id)) and str(p.kind) == kind:
			out.append(Boosts.part("book", str(p.id), float(p.x)))
	return out


## The line under a sticker's name, e.g. "+10% coins" (built from its x, so it always matches).
static func words(catalog: Catalog, p: Dictionary) -> String:
	var w := str(catalog.book.get("words", {}).get(str(p.get("kind", "")), ""))
	return w.replace("{p}", str(roundi((float(p.get("x", 1.0)) - 1.0) * 100.0)))


## Only the page ids that exist (for loading a save).
static func clean(catalog: Catalog, saved: Array) -> Array[String]:
	var out: Array[String] = []
	for id in saved:
		if not page(catalog, str(id)).is_empty() and not out.has(str(id)):
			out.append(str(id))
	return out
