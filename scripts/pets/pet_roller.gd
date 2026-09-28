class_name PetRoller
extends RefCounted
## Rolls new pets out of a box, the way trading card packs work:
## the pet's rarity is rolled once with the box odds, one "signature" part gets that rarity,
## and the other parts roll at or below it. The finish (the foil) is its own separate roll.
## Parts are picked from what the box can hold (Catalog.parts_in: some looks only come out of
## the better boxes), and a box holds its "pets" [min, max] pets (roll_box).

const STAT_BASE := 5  # stats roll between base and 2x base, and base grows with rarity

var catalog: Catalog
var rng: RandomNumberGenerator
var _capped := {}  # "box|max rank" -> the box's rarity odds up to that rank (_roll_rank_up_to)
var _signature_options := {}  # "tier|box" -> the slots with a part at that tier in that box


func _init(p_catalog: Catalog = Catalog.shared(), p_rng: RandomNumberGenerator = null) -> void:
	catalog = p_catalog
	rng = p_rng if p_rng else RandomNumberGenerator.new()
	if p_rng == null:
		rng.randomize()


## Rolls one pet. `force_tier` fixes the rarity (for testing reveals); leave empty normally.
func roll(box_id: String, force_tier := "") -> Pet:
	var box := catalog.box(box_id)
	assert(not box.is_empty(), "unknown box: " + box_id)
	var pet := Pet.new()
	pet.box = box_id
	pet.pulled_at = int(Time.get_unix_time_from_system())
	var tier_rank := catalog.rank(force_tier if force_tier != "" else Weighted.pick(box.tiers, rng))
	var signature := _signature_slot(tier_rank, box_id)
	tier_rank = mini(tier_rank, _best_rank_in(signature, tier_rank, box_id))
	for slot in Catalog.SLOTS:
		var r := tier_rank if slot == signature else _roll_rank_up_to(box_id, box.tiers, tier_rank)
		pet.parts[slot] = _pick_part(slot, r, box_id)
	pet.finish = Weighted.pick(box.finishes, rng)
	pet.traits = _roll_traits(box.traits)
	pet.rarity = catalog.tier_at(tier_rank).id
	pet.stats = _roll_stats(catalog.rank(pet.rarity))
	return pet


## Everything in one box: its "pets" [min, max] pets. `force_tier` fixes the first one's rarity.
func roll_box(box_id: String, force_tier := "") -> Array[Pet]:
	var range_: Array = catalog.box(box_id).get("pets", [1, 1])
	var n := maxi(1, rng.randi_range(int(range_[0]), int(range_[range_.size() - 1])))
	var out: Array[Pet] = []
	for i in n:
		out.append(roll(box_id, force_tier if i == 0 else ""))
	return out


## A random slot this box has a part for at this tier.
func _signature_slot(tier_rank: int, box_id: String) -> String:
	var tier_id: String = catalog.tier_at(tier_rank).id
	var key := tier_id + "|" + box_id
	if not _signature_options.has(key):
		_signature_options[key] = Catalog.SLOTS.filter(func(slot): return not catalog.parts_in(slot, tier_id, box_id).is_empty())
	var options: Array = _signature_options[key]
	if options.is_empty():
		return "body"
	return options[rng.randi_range(0, options.size() - 1)]


## The highest tier at or below max_rank that this slot has parts for.
func _best_rank_in(slot: String, max_rank: int, box_id: String) -> int:
	for r in range(max_rank, -1, -1):
		if not catalog.parts_in(slot, catalog.tier_at(r).id, box_id).is_empty():
			return r
	return 0


## Rolls a tier with the box odds, but never above max_rank.
func _roll_rank_up_to(box_id: String, tier_weights: Dictionary, max_rank: int) -> int:
	var key := "%s|%d" % [box_id, max_rank]
	if not _capped.has(key):
		var capped := {}
		for tier_id in tier_weights:
			if catalog.rank(tier_id) <= max_rank:
				capped[tier_id] = tier_weights[tier_id]
		_capped[key] = capped
	return catalog.rank(Weighted.pick(_capped[key], rng))


## A random part of the given tier, stepping down if the slot has nothing at that tier.
func _pick_part(slot: String, tier_rank: int, box_id: String) -> String:
	var options := catalog.parts_in(slot, catalog.tier_at(_best_rank_in(slot, tier_rank, box_id)).id, box_id)
	return options[rng.randi_range(0, options.size() - 1)].id


func _roll_traits(count_weights: Array) -> Array[String]:
	var count := Weighted.pick_index(count_weights, rng)
	var pool: Array = catalog.traits.duplicate()
	var out: Array[String] = []
	for i in mini(count, pool.size()):
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)).id)
	return out


func _roll_stats(tier_rank: int) -> Dictionary:
	var base := STAT_BASE * (tier_rank + 1)
	var out := {}
	for stat in Pet.STATS:
		out[stat] = rng.randi_range(base, base * 2)
	return out
