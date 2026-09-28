class_name Intel
extends RefCounted
## Spotting new places: a pet that makes it home from a trip may have seen somewhere its place
## leads to (data/adventures.json "leads_to"). Each lead has its own chance; every trip that
## misses it raises the chance a little, so nobody waits forever for the next place to open.

const SAFETY_NET := 0.15  # extra chance per trip that could have spotted a place but didn't


## Which of this place's leads a trip spotted. `known` says whether a place is already open or
## spotted (those are skipped); `tries` counts misses per place and is updated. `bonus` is added
## to every lead's chance (a trip that took a scout note, see data/errands.json "scout"); `x`
## multiplies each lead's own chance (spotting knacks).
static func roll(location: Dictionary, known: Callable, tries: Dictionary, rng: RandomNumberGenerator, bonus := 0.0, x := 1.0) -> Array[String]:
	var found: Array[String] = []
	for lead in location.get("leads_to", []):
		var id := str(lead.to)
		if known.call(id):
			continue
		var chance := float(lead.get("spot", 0.0)) * x + SAFETY_NET * int(tries.get(id, 0)) + bonus
		if rng.randf() < chance:
			found.append(id)
			tries.erase(id)
		else:
			tries[id] = int(tries.get(id, 0)) + 1
	return found


## Whether a trip here could still find something new: a lead not yet open or spotted, or (when
## rumours can still be heard) a rumour its events or treat bag can bring.
static func left_to_find(location: Dictionary, known: Callable, rumours_left: bool, catalog: Catalog) -> bool:
	for lead in location.get("leads_to", []):
		if not known.call(str(lead.to)):
			return true
	return rumours_left and brings_rumours(location, catalog)


## Whether anything on a trip here can bring a rumour (its treat bag or one of its events).
static func brings_rumours(location: Dictionary, catalog: Catalog) -> bool:
	var key := "rumours_at_" + str(location.get("id", ""))
	if catalog.has_meta(key):
		return catalog.get_meta(key)
	var found := _has_rumour(location.get("finish_rewards", []))
	for e in location.get("events", []) + location.get("pool", []).map(func(p): return p.event):
		found = found or _has_rumour(catalog.events.get(e, {}))
	catalog.set_meta(key, found)
	return found


static func _has_rumour(v: Variant) -> bool:
	if v is Dictionary:
		if str(v.get("kind", "")) == "rumour":
			return true
		return v.values().any(func(x): return _has_rumour(x))
	if v is Array:
		return v.any(func(x): return _has_rumour(x))
	return false
