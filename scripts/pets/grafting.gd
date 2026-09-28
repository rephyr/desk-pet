class_name Grafting
extends RefCounted
## Sewing a part onto your active pet (data/grafting.json). Pure rules: a pet, a part from the
## inventory and the dice go in; the pet and the inventory come out changed. It can fail, more
## often the rarer the part: then the part is lost and the pet keeps what it had. Sewn slots are
## remembered on the pet, which shows them as little stitch marks.
## Buttons from the plushie machine stay on their part (see Plushie): a part that comes off with
## buttons goes back in the bag as "slot:id@n" (n buttons), and sewing one of those on gives that
## slot its buttons. Plain parts are "slot:id" as always.

const NOTHING := "none"  # parts like "no accessory" aren't worth keeping when taken off


## The bag key for a part with `buttons` buttons on it: "slot:id", or "slot:id@n".
static func key(slot: String, part_id: String, buttons := 0) -> String:
	return "%s:%s" % [slot, part_id] if buttons <= 0 else "%s:%s@%d" % [slot, part_id, buttons]


## A bag key as [slot, part id, buttons] (["", "", 0] for something that isn't one).
static func split_key(bag_key: String) -> Array:
	var bits := bag_key.split(":")
	if bits.size() != 2:
		return ["", "", 0]
	var id := bits[1]
	var buttons := 0
	var at := id.find("@")
	if at >= 0:
		buttons = maxi(0, int(id.substr(at + 1)))
		id = id.substr(0, at)
	return [bits[0], id, buttons]


## Whether a bag key names a real part (with a sensible number of buttons).
static func valid_key(bag_key: String, catalog: Catalog) -> bool:
	var k := split_key(bag_key)
	return str(k[0]) in Catalog.SLOTS and not catalog.part(k[0], k[1]).is_empty() and int(k[2]) <= Plushie.max_buttons(catalog) \
		and key(k[0], k[1], k[2]) == bag_key


## Chance (0..1) that sewing this part on fails.
static func fail_chance(slot: String, part_id: String, catalog: Catalog) -> float:
	var part := catalog.part(slot, part_id)
	return float(catalog.grafting.fail.get(str(part.get("rarity", "common")), 0.5))


## Whether this part can be sewn onto this pet: you have one, and it isn't already wearing it.
static func can_sew(pet: Pet, slot: String, part_id: String, inventory: Dictionary, buttons := 0) -> bool:
	return pet != null and int(inventory.get(key(slot, part_id, buttons), 0)) > 0 and pet.parts.get(slot, "") != part_id


## Sews a part on (with `buttons` buttons on it). Uses up one from `inventory` ("slot:part id" or
## "slot:part id@n" -> count) either way. Returns { ok, old } (old = the part that came off, now
## back in the inventory with its buttons), or {} if it can't.
static func sew(pet: Pet, slot: String, part_id: String, inventory: Dictionary, rng: RandomNumberGenerator, catalog: Catalog, buttons := 0) -> Dictionary:
	if not can_sew(pet, slot, part_id, inventory, buttons):
		return {}
	var k := key(slot, part_id, buttons)
	inventory[k] = int(inventory[k]) - 1
	if int(inventory[k]) <= 0:
		inventory.erase(k)
	if rng.randf() < fail_chance(slot, part_id, catalog):
		return { "ok": false, "old": "" }
	var old: String = pet.parts[slot]
	if old != NOTHING:
		var back := key(slot, old, Plushie.buttons(pet, slot))
		inventory[back] = int(inventory.get(back, 0)) + 1
	pet.parts[slot] = part_id
	if buttons > 0:
		pet.buttons[slot] = buttons
	else:
		pet.buttons.erase(slot)
	if not slot in pet.sewn:
		pet.sewn.append(slot)
	# a pet is as rare as its rarest part
	var best := 0
	for s in Catalog.SLOTS:
		best = maxi(best, catalog.rank(catalog.part(s, pet.parts[s]).get("rarity", "common")))
	pet.rarity = catalog.tier_at(best).id
	return { "ok": true, "old": old }


## The pet as it would look with this part (for the before/after preview).
static func preview(pet: Pet, slot: String, part_id: String, buttons := 0) -> Pet:
	var copy := Pet.from_dict(pet.to_dict())
	copy.parts[slot] = part_id
	if buttons > 0:
		copy.buttons[slot] = buttons
	else:
		copy.buttons.erase(slot)
	if not slot in copy.sewn:
		copy.sewn.append(slot)
	return copy
