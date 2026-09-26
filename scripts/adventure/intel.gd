class_name Intel
extends RefCounted
## Spotting new places: a pet that makes it home from a trip may have seen somewhere its place
## leads to (data/adventures.json "leads_to"). Each lead has its own chance; every trip that
## misses it raises the chance a little, so nobody waits forever for the next place to open.

const SAFETY_NET := 0.15  # extra chance per trip that could have spotted a place but didn't


## Which of this place's leads a trip spotted. `known` says whether a place is already open or
## spotted (those are skipped); `tries` counts misses per place and is updated.
static func roll(location: Dictionary, known: Callable, tries: Dictionary, rng: RandomNumberGenerator) -> Array[String]:
	var found: Array[String] = []
	for lead in location.get("leads_to", []):
		var id := str(lead.to)
		if known.call(id):
			continue
		var chance := float(lead.get("spot", 0.0)) + SAFETY_NET * int(tries.get(id, 0))
		if rng.randf() < chance:
			found.append(id)
			tries.erase(id)
		else:
			tries[id] = int(tries.get(id, 0)) + 1
	return found
