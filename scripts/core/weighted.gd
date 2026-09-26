class_name Weighted
extends RefCounted
## Weighted random picks. Weights don't need to add up to anything.


## Picks a key from { key: weight }.
static func pick(weights: Dictionary, rng: RandomNumberGenerator) -> Variant:
	assert(not weights.is_empty(), "Weighted.pick needs at least one option")
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := rng.randf() * total
	for key in weights:
		roll -= float(weights[key])
		if roll < 0.0:
			return key
	return weights.keys().back()  # float rounding: fall back to the last entry


## Picks an index from [weight, weight, ...].
static func pick_index(weights: Array, rng: RandomNumberGenerator) -> int:
	var as_dict := {}
	for i in weights.size():
		as_dict[i] = weights[i]
	return pick(as_dict, rng)


## Chance of each key as a 0..1 fraction, for showing odds.
static func chances(weights: Dictionary) -> Dictionary:
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var out := {}
	for key in weights:
		out[key] = float(weights[key]) / total if total > 0.0 else 0.0
	return out
