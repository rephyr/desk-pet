class_name Wish
extends RefCounted
## The wishing jar (data/wish.json): wish for a sticker you've found in the book (a part: body,
## palette, pattern, eyes or accessory; never a finish), then send pets into its jar. Every pet
## counts 1 and never comes back. The jar fills in steps (200, 600, 2k, 6k); every full step makes
## that look turn up more often INSIDE its own rarity in every box (PetRoller.wish). Rarity itself
## never moves. Switching the wish keeps every jar's filled steps (and their boost).
## Pure rules; the state lives in the save (GameState.wish):
##   { "on": book key or "", "jars": { book key: { "sent": n, "dots": [palette ids, the last ones in] } } }
## Book keys are Collection.part_key ("part:pattern:spots").


static func fresh() -> Dictionary:
	return { "on": "", "jars": {} }


static func steps(catalog: Catalog) -> Array:
	return catalog.wish.get("steps", [200, 600, 2000, 6000])


## How many pets fill a whole jar (every step).
static func total(catalog: Catalog) -> int:
	var n := 0
	for s in steps(catalog):
		n += int(s)
	return n


## Whether a book key can be wished for: a part that exists (finishes can't).
static func can_wish(catalog: Catalog, key: String) -> bool:
	var bits := key.split(":")
	return bits.size() == 3 and bits[0] == "part" and bits[1] in Catalog.SLOTS and not catalog.part(bits[1], bits[2]).is_empty()


## Pets sent into a look's jar so far.
static func sent(state: Dictionary, key: String) -> int:
	return int(state.get("jars", {}).get(key, {}).get("sent", 0))


## Where a jar with `n` pets in it is: full steps, whether it's done, how far into the step being
## filled (have / need) and that as 0..1 (f).
static func where(catalog: Catalog, n: int) -> Dictionary:
	var start := 0
	var list := steps(catalog)
	for i in list.size():
		var size := int(list[i])
		if n < start + size:
			return { "full": i, "done": false, "have": n - start, "need": size, "f": float(n - start) / size }
		start += size
	return { "full": list.size(), "done": true, "have": 0, "need": 0, "f": 1.0 }


## How many more pets fit in a look's jar.
static func room(catalog: Catalog, state: Dictionary, key: String) -> int:
	return maxi(0, total(catalog) - sent(state, key))


## What every look with a full step weighs inside its rarity: { book key: x } (PetRoller.wish).
static func weights(catalog: Catalog, state: Dictionary) -> Dictionary:
	var by_step: Array = catalog.wish.get("weight", [1.0])
	var out := {}
	var jars: Dictionary = state.get("jars", {})
	for key in jars:
		var full := int(where(catalog, sent(state, key)).full)
		var x := float(by_step[mini(full, by_step.size() - 1)])
		if full > 0 and x != 1.0:
			out[key] = x
	return out


## Puts `n` pets into a look's jar: they count, and the colours of the last ones in (`palettes`,
## palette ids) are its dots.
static func add(catalog: Catalog, state: Dictionary, key: String, n: int, palettes: Array) -> void:
	var jars: Dictionary = state.jars
	var jar: Dictionary = jars.get(key, { "sent": 0, "dots": [] })
	jar.sent = int(jar.sent) + n
	var keep := int(catalog.wish.get("dots", 90))
	var dots: Array = jar.dots
	for palette in palettes.slice(maxi(0, palettes.size() - keep)):
		dots.append(str(palette))
	if dots.size() > keep:
		jar.dots = dots.slice(dots.size() - keep)
	jars[key] = jar


## Only what's real (for loading a save): known looks, sent counts within a whole jar.
static func clean(catalog: Catalog, saved: Variant) -> Dictionary:
	var out := fresh()
	if not saved is Dictionary:
		return out
	var on := str(saved.get("on", ""))
	out.on = on if can_wish(catalog, on) else ""
	var jars: Variant = saved.get("jars", {})
	if jars is Dictionary:
		var keep := int(catalog.wish.get("dots", 90))
		for key in jars:
			var jar: Variant = jars[key]
			if not can_wish(catalog, str(key)) or not jar is Dictionary:
				continue
			var n := clampi(int(jar.get("sent", 0)), 0, total(catalog))
			var dots: Array = []
			var raw_dots: Variant = jar.get("dots", [])
			if raw_dots is Array:
				for d in raw_dots:
					if not catalog.part("palette", str(d)).is_empty():
						dots.append(str(d))
			if n > 0:
				out.jars[str(key)] = { "sent": n, "dots": dots.slice(maxi(0, dots.size() - keep)) }
	return out
