class_name Knacks
extends RefCounted
## Knacks: every part has a named knack (data/knacks.json), e.g. the bunny body's "big ears"
## (+spotting). Its size n (a %) is the kind's step x the part's rarity x the pet's finish x the
## part's buttons (the plushie machine: x 1 + knack_per_button per button, see Plushie), and it
## multiplies by 1 + n/100. Nothing is saved: a pet's knacks come from its parts and finish.
## Your active pet's knacks are the "knacks" boost source (GameState.boost_parts); every card pet's
## count on its own work too (errands, worker jobs, the dungeon army's power, its trips) at the
## "own" share (1.0: in full). Pets from the herd have no parts of their own and count none.
## Pure rules: `open` is a Callable(gate: String) -> bool that says whether a gate is open
## ("feature:parts", "machine:wires", "adventures", ...), so this knows no game state.


static func data(catalog: Catalog) -> Dictionary:
	return catalog.knacks


## A kind's row ({} when there's no such kind).
static func kind_info(catalog: Catalog, kind: String) -> Dictionary:
	return data(catalog).get("kinds", {}).get(kind, {})


## A part's knack row: { name, kind }, or {} (no accessory has none).
static func of_part(catalog: Catalog, slot: String, part_id: String) -> Dictionary:
	return data(catalog).get("parts", {}).get("%s:%s" % [slot, part_id], {})


## A knack's size in % for a kind, a part rarity, a finish and the part's buttons (rounded to a
## whole %).
static func size(catalog: Catalog, kind: String, rarity: String, finish := "normal", buttons := 0) -> int:
	var d := data(catalog)
	var step := float(kind_info(catalog, kind).get("step", 0))
	return roundi(step * float(d.rarity_x.get(rarity, 1)) * float(d.finish_x.get(finish, 1)) * Plushie.knack_x(catalog, maxi(buttons, 0)))


## Whether the whole system is open (knacks show at all).
static func system_open(catalog: Catalog, open: Callable) -> bool:
	var gate := str(data(catalog).get("opens", ""))
	return gate == "" or open.call(gate)


## Whether knacks of this kind show and count: the kind does something now (a boost kind, or "all")
## and its own gate is open. The whole system's gate is checked by the caller (see of).
static func kind_open(catalog: Catalog, kind: String, open: Callable) -> bool:
	if kind_info(catalog, kind).is_empty():
		return false
	if kind != "all" and not Boosts.is_kind(catalog, kind):
		return false  # e.g. power: nothing uses it until fights
	var gate := str(kind_info(catalog, kind).get("opens", ""))
	return gate == "" or open.call(gate)


## A pet's knacks that show right now, in slot order:
##   [ { slot, part, part_name, name, kind, tier, n, x, text, short, icon, buttons } ]
## [] when the system is shut.
static func of(catalog: Catalog, pet: Pet, open: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if pet == null or not system_open(catalog, open):
		return out
	for slot in Catalog.SLOTS:
		var k := row(catalog, slot, str(pet.parts.get(slot, "")), open, pet.finish, Plushie.buttons(pet, slot))
		if not k.is_empty():
			out.append(k)
	return out


## One part's knack as `of` shows it, on a pet of this finish, with `buttons` buttons on the part
## (a part in the bag: the finish of the pet it would go on). {} when it has none that shows (the
## whole system's gate is the caller's, as for kind_open).
static func row(catalog: Catalog, slot: String, id: String, open: Callable, finish := "normal", buttons := 0) -> Dictionary:
	var k := of_part(catalog, slot, id)
	var kind := str(k.get("kind", ""))
	if kind == "" or not kind_open(catalog, kind, open):
		return {}
	var p := catalog.part(slot, id)
	var tier := str(p.get("rarity", "common"))
	var n := size(catalog, kind, tier, finish, buttons)
	var info := kind_info(catalog, kind)
	return { "slot": slot, "part": id, "part_name": str(p.get("name", id)), "name": str(k.get("name", "")),
		"kind": kind, "tier": tier, "n": n, "x": 1.0 + n / 100.0, "buttons": buttons,
		"text": str(info.get("text", "")).replace("{n}", str(n)), "short": str(info.get("short", kind)),
		"icon": str(info.get("icon", "")) }


## The pet's best knack (highest part rarity, then biggest), or {} with none showing.
static func best(catalog: Catalog, pet: Pet, open: Callable) -> Dictionary:
	var top := {}
	for k in of(catalog, pet, open):
		if top.is_empty() or catalog.rank(k.tier) > catalog.rank(top.tier) \
				or (catalog.rank(k.tier) == catalog.rank(top.tier) and int(k.n) > int(top.n)):
			top = k
	return top


## Whether a knack counts for a boost kind: its own kind, or "all" for kinds marked all.
static func covers(catalog: Catalog, knack_kind: String, kind: String) -> bool:
	return knack_kind == kind or (knack_kind == "all" and Boosts.all_covers(catalog, kind))


## Which parts' knacks count for a boost kind right now, as a lookup table: slot -> { part id ->
## its knack's size in % before the finish } ({} while knacks are shut or none count). Worked out
## once per call so the lean totals below can walk big crews without building display rows.
static func counting(catalog: Catalog, kind: String, open: Callable) -> Dictionary:
	var out := {}
	if not system_open(catalog, open):
		return out
	var d := data(catalog)
	var steps := {}  # knack kind -> its step, for the kinds that count
	for kk: String in d.get("kinds", {}):
		if covers(catalog, kk, kind) and kind_open(catalog, kk, open):
			steps[kk] = float(kind_info(catalog, kk).get("step", 0))
	if steps.is_empty():
		return out
	var parts_data: Dictionary = d.get("parts", {})
	for key: String in parts_data:
		var kk := str(parts_data[key].get("kind", ""))
		if not steps.has(kk):
			continue
		var bits := key.split(":")
		var tier := str(catalog.part(bits[0], bits[1]).get("rarity", "common"))
		if not out.has(bits[0]):
			out[bits[0]] = {}
		out[bits[0]][bits[1]] = float(steps[kk]) * float(d.rarity_x.get(tier, 1))
	return out


## A pet's knacks added up in % for the table from counting, building no display rows: the lean
## path for totals over many pets. Same rounding as of (per knack).
static func sum_in(catalog: Catalog, pet: Pet, table: Dictionary) -> int:
	if pet == null or table.is_empty():
		return 0
	var fx := float(data(catalog).finish_x.get(pet.finish, 1))
	var n := 0
	for slot: String in table:
		var base = table[slot].get(pet.parts.get(slot, ""))
		if base != null:
			n += roundi(float(base) * fx * _button_x(catalog, pet, slot))
	return n


## A part's knack multiplier from its buttons (1.0 with none).
static func _button_x(catalog: Catalog, pet: Pet, slot: String) -> float:
	return 1.0 if pet.buttons.is_empty() else Plushie.knack_x(catalog, Plushie.buttons(pet, slot))


## `own` with the counting kinds already worked out (1.0 with none).
static func own_in(catalog: Catalog, pet: Pet, table: Dictionary) -> float:
	if pet == null or table.is_empty():
		return 1.0
	return 1.0 + float(data(catalog).get("own", 0.0)) * sum_in(catalog, pet, table) / 100.0


## A pet's knacks of one kind added up, in % (0 with none).
static func total(catalog: Catalog, pet: Pet, kind: String, open: Callable) -> int:
	return sum_in(catalog, pet, counting(catalog, kind, open))


## The boost parts (see Boosts) of one kind from a pet (your active pet): one part, its knacks of
## that kind added up, id like "body:bunny+eyes:cyclops". [] when none.
static func parts(catalog: Catalog, pet: Pet, kind: String, open: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var table := counting(catalog, kind, open)
	if pet == null or table.is_empty():
		return out
	var fx := float(data(catalog).finish_x.get(pet.finish, 1))
	var ids: Array[String] = []
	var n := 0
	for slot in Catalog.SLOTS:
		var id := str(pet.parts.get(slot, ""))
		var base = table.get(slot, {}).get(id)
		var bx := _button_x(catalog, pet, slot)
		if base != null and roundi(float(base) * fx * bx) > 0:
			ids.append("%s:%s" % [slot, id])
			n += roundi(float(base) * fx * bx)
	if n > 0:
		out.append(Boosts.part("knacks", "+".join(ids), 1.0 + n / 100.0))
	return out


## A knacks part's id as people read it: "body:bunny+eyes:cyclops" -> "big ears + one big eye".
static func part_names(catalog: Catalog, id: String) -> String:
	var names: Array[String] = []
	for bit in id.split("+"):
		var sp := bit.split(":")
		if sp.size() == 2:
			names.append(str(of_part(catalog, sp[0], sp[1]).get("name", sp[1])))
	return " + ".join(names)


## What a pet's own knacks of a kind do for its own work (errands, worker jobs, the army's power,
## its trips): the "own" share of their size (1.0 in data: in full). 1.0 with none.
static func own(catalog: Catalog, pet: Pet, kind: String, open: Callable) -> float:
	return own_in(catalog, pet, counting(catalog, kind, open))


## A party's average `own` for a kind (1.0 for nobody).
static func party(catalog: Catalog, pets: Array, kind: String, open: Callable) -> float:
	return float(party_all(catalog, pets, [kind], open)[kind])


## `party` for several kinds in one go over the pets: kind -> average own multiplier.
static func party_all(catalog: Catalog, pets: Array, kinds: Array, open: Callable) -> Dictionary:
	var out := {}
	for kind in kinds:
		var table := counting(catalog, kind, open)
		if pets.is_empty() or table.is_empty():
			out[kind] = 1.0
			continue
		var sum := 0.0
		for pet in pets:
			sum += own_in(catalog, pet, table)
		out[kind] = sum / pets.size()
	return out
