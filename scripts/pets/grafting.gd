class_name Grafting
extends RefCounted
## Sewing a part onto your active pet (data/grafting.json). Pure rules: a pet, a part from the
## inventory and the dice go in; the pet and the inventory come out changed. It can fail, more
## often the rarer the part: then the part is lost and the pet keeps what it had. Sewn slots are
## remembered on the pet, which shows them as little stitch marks.

const NOTHING := "none"  # parts like "no accessory" aren't worth keeping when taken off


## Chance (0..1) that sewing this part on fails.
static func fail_chance(slot: String, part_id: String, catalog: Catalog) -> float:
	var part := catalog.part(slot, part_id)
	return float(catalog.grafting.fail.get(str(part.get("rarity", "common")), 0.5))


## Whether this part can be sewn onto this pet: you have one, and it isn't already wearing it.
static func can_sew(pet: Pet, slot: String, part_id: String, inventory: Dictionary) -> bool:
	return pet != null and int(inventory.get("%s:%s" % [slot, part_id], 0)) > 0 and pet.parts.get(slot, "") != part_id


## Sews a part on. Uses up one from `inventory` ("slot:part id" -> count) either way. Returns
## { ok, old } (old = the part that came off, now back in the inventory), or {} if it can't.
static func sew(pet: Pet, slot: String, part_id: String, inventory: Dictionary, rng: RandomNumberGenerator, catalog: Catalog) -> Dictionary:
	if not can_sew(pet, slot, part_id, inventory):
		return {}
	var key := "%s:%s" % [slot, part_id]
	inventory[key] = int(inventory[key]) - 1
	if int(inventory[key]) <= 0:
		inventory.erase(key)
	if rng.randf() < fail_chance(slot, part_id, catalog):
		return { "ok": false, "old": "" }
	var old: String = pet.parts[slot]
	if old != NOTHING:
		var back := "%s:%s" % [slot, old]
		inventory[back] = int(inventory.get(back, 0)) + 1
	pet.parts[slot] = part_id
	if not slot in pet.sewn:
		pet.sewn.append(slot)
	# a pet is as rare as its rarest part
	var best := 0
	for s in Catalog.SLOTS:
		best = maxi(best, catalog.rank(catalog.part(s, pet.parts[s]).get("rarity", "common")))
	pet.rarity = catalog.tier_at(best).id
	return { "ok": true, "old": old }


## The pet as it would look with this part (for the before/after preview).
static func preview(pet: Pet, slot: String, part_id: String) -> Pet:
	var copy := Pet.from_dict(pet.to_dict())
	copy.parts[slot] = part_id
	if not slot in copy.sewn:
		copy.sewn.append(slot)
	return copy
