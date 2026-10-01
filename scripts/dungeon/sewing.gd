class_name Sewing
extends RefCounted
## E3 the sewing room, off the well's floor 20 (data/sewing.json): rooms, each one fight for the
## dungeon's army (Dungeon's maths at the room's floor) behind a chalk lock of marks: a seat each, and
## every seat needs a pet that matches (GameState.sew_seat). After the fixed rooms, rolled rooms
## with button locks go on forever. Also the rules
## of the sorting card's keep lines, which the first room teaches. Pure rules, no game state:
## GameState keeps the state from the save. The state:
##   { cleared: rooms cleared so far, in order (the fixed ones, then rolled ones) }
## A MARK is a string: "part:<slot>:<id>", "trait:<id>", "finish:<id>", "tier:<id>" or "buttons:<n>".
## A keep line's PICK is "" (nothing), "trait:<id>" or "part:<slot>:<id>".


static func data(catalog: Catalog) -> Dictionary:
	return catalog.sewing


static func fresh() -> Dictionary:
	return { "cleared": 0 }


## A saved state made safe.
static func clean(raw) -> Dictionary:
	var out := fresh()
	if raw is Dictionary:
		var n = raw.get("cleared", 0)
		out.cleared = maxi(0, int(n)) if (n is int or n is float) else 0
	return out


## How many fixed rooms there are.
static func fixed_count(catalog: Catalog) -> int:
	return data(catalog).get("rooms", []).size()


## Room `i` (0 = the first): { i, id, name, pic, floor, marks: [mark], first: {}, rolled }. Past the
## fixed rooms a room is rolled from its number, so it's the same every time it's asked for.
static func room(catalog: Catalog, i: int) -> Dictionary:
	var d := data(catalog)
	var fixed: Array = d.get("rooms", [])
	if i < fixed.size():
		var r: Dictionary = fixed[maxi(i, 0)]
		return { "i": maxi(i, 0), "id": str(r.id), "name": str(r.name), "pic": str(r.get("pic", r.id)), "floor": int(r.floor),
			"marks": r.get("marks", []).map(func(m): return str(m)), "first": r.get("first", {}), "rolled": false }
	var rd: Dictionary = d.get("rolled", {})
	var k := i - fixed.size()
	var looks: Array = rd.get("rooms", [])
	var look: Dictionary = looks[k % looks.size()] if not looks.is_empty() else { "id": "room", "name": "a little room", "pic": "tin" }
	var b: Dictionary = rd.get("buttons", {})
	var buttons := mini(int(b.get("max", 25)), int(b.get("start", 1)) + k / maxi(1, int(b.get("every", 3))))
	var m: Dictionary = rd.get("marks", {})
	var count := mini(int(m.get("max", 5)), int(m.get("start", 3)) + k / maxi(1, int(m.get("every", 5))))
	var marks: Array = ["buttons:%d" % buttons]
	var pool: Array = rd.get("pool", []).map(func(p): return str(p))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (i + 1) + 104729
	while marks.size() < count and not pool.is_empty():
		var pick: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		# one mark of a kind per slot, one tier and one finish: a single pet can't be two tiers at once,
		# but different pets can, so this only keeps rooms from asking the same thing twice
		if marks.any(func(have): return _same_kind(have, pick)):
			continue
		marks.append(pick)
	return { "i": i, "id": "%s_%d" % [str(look.id), i], "name": str(look.name), "pic": str(look.get("pic", "tin")),
		"floor": int(rd.get("floor_start", 34)) + k * int(rd.get("floor_step", 1)), "marks": marks, "first": {}, "rolled": true }


static func _same_kind(a: String, b: String) -> bool:
	var pa := a.split(":")
	var pb := b.split(":")
	if pa[0] != pb[0]:
		return false
	match pa[0]:
		"part":
			return pa.size() > 1 and pb.size() > 1 and pa[1] == pb[1]
		"tier", "finish":
			return true
	return a == b


## The rooms shown: the ones cleared and the next one (0..cleared).
static func shown(state: Dictionary) -> int:
	return int(state.get("cleared", 0)) + 1


## A room's strength (never shown as a number: feeling words, see Dungeon.word).
static func strength(catalog: Catalog, r: Dictionary) -> float:
	var s: Dictionary = catalog.dungeon.strength
	return float(s.base) * pow(float(s.grow), int(r.floor)) * float(data(catalog).get("room_x", 1.0))


## What clearing a room pays: a well floor at the room's floor, for the pets sent (at most the
## entrance), x the lanterns boost (`boost`).
static func pay(catalog: Catalog, r: Dictionary, sent: int, entrance_level: int, boost := 1.0) -> int:
	return maxi(1, roundi(Dungeon.pay(catalog, int(r.floor), sent, entrance_level, boost) * float(data(catalog).get("pay_x", 1.0))))


## How long a room takes.
static func seconds(catalog: Catalog) -> float:
	return float(data(catalog).get("seconds", 60))


# ---- marks ------------------------------------------------------------------------

## Whether a pet matches a mark.
static func mark_matches(mark: String, pet: Pet) -> bool:
	if pet == null:
		return false
	var p := mark.split(":")
	match p[0]:
		"part":
			return p.size() == 3 and str(pet.parts.get(p[1], "")) == p[2]
		"trait":
			return p.size() == 2 and p[1] in pet.traits
		"finish":
			return p.size() == 2 and pet.finish == p[1]
		"tier":
			return p.size() == 2 and pet.rarity == p[1]
		"buttons":
			return p.size() == 2 and Plushie.total(pet) >= int(p[1])
	return false


## Which of a room's marks some of `pets` fill: [bool] in the marks' order.
static func marks_on(r: Dictionary, front: Array) -> Array:
	var out: Array = []
	for mark in r.get("marks", []):
		out.append(front.any(func(pet): return mark_matches(str(mark), pet)))
	return out


## Which front row pets match any of a room's marks (a chalk tick on their card): [bool] per pet.
static func ticks(r: Dictionary, front: Array) -> Array:
	var out: Array = []
	for pet in front:
		out.append(r.get("marks", []).any(func(mark): return mark_matches(str(mark), pet)))
	return out


## Whether every mark of a room is filled.
static func unlocked(r: Dictionary, front: Array) -> bool:
	return marks_on(r, front).all(func(on): return on)


## A mark's word for many pets ("halos", "zoomy", "shiny", "rare"), for keep lines and hints.
static func many(catalog: Catalog, mark: String) -> String:
	var info: Dictionary = data(catalog).get("marks", {}).get(mark, {})
	if info.has("many"):
		return str(info.many)
	var p := mark.split(":")
	match p[0]:
		"trait":
			return p[1]
		"finish":
			return str(catalog.finish(p[1]).name) if p.size() > 1 else mark
		"tier":
			return str(catalog.tier_at(catalog.rank(p[1])).name) if p.size() > 1 else mark
		"part":
			return str(catalog.part(p[1], p[2]).get("name", p[2])) + "s" if p.size() > 2 else mark
	return mark


## A mark's word for one pet, on its seat ("a halo", "lazy", "rare", "2 buttons").
static func one(catalog: Catalog, mark: String) -> String:
	var info: Dictionary = data(catalog).get("marks", {}).get(mark, {})
	if info.has("one"):
		return str(info.one)
	var p := mark.split(":")
	match p[0]:
		"buttons":
			var n := int(p[1]) if p.size() > 1 else 1
			return "%d button%s" % [n, "" if n == 1 else "s"]
		"part":
			return str(catalog.part(p[1], p[2]).get("name", p[2])) if p.size() > 2 else mark
	return many(catalog, mark)


## A mark's word for the pets that fit it, over the pet picker ("halos", "lazy ones", "epic ones").
static func ones(catalog: Catalog, mark: String) -> String:
	match mark.get_slice(":", 0):
		"trait", "finish", "tier":
			return "%s ones" % many(catalog, mark)
		"buttons":
			return one(catalog, mark)
	return many(catalog, mark)


# ---- a run ------------------------------------------------------------------------

## Works a room run out when the army goes in: one fight, like a well floor (Dungeon._fight).
## Returns the usual run shape: { floors: [{ f: the door floor, cleared, lost_cards, lost_herd, pay }],
## why: target | stuck | gone, turned: 0 }.
static func simulate(catalog: Catalog, army: Dictionary, r: Dictionary, orders: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var sent: int = army.get("cards", []).size() + Herd.total(_counts(army))
	return Dungeon.simulate_room(catalog, army, strength(catalog, r), pay(catalog, r, sent, int(orders.get("entrance", 0)), float(orders.get("pay_x", 1.0))),
		int(data(catalog).get("door_floor", 20)), str(orders.get("first", "")), rng)


static func _counts(army: Dictionary) -> Dictionary:
	var out := {}
	var info: Dictionary = army.get("herd", {})
	for k in info:
		if int(info[k].n) > 0:
			out[k] = int(info[k].n)
	return out


# ---- keep lines (the sorting card) --------------------------------------------------

## How many keep lines the rooms cleared so far have earned.
static func keep_lines(catalog: Catalog, cleared: int) -> int:
	var n := 0
	var fixed: Array = data(catalog).get("rooms", [])
	for i in mini(cleared, fixed.size()):
		n += int(fixed[i].get("first", {}).get("keep_lines", 0))
	return n


## How many pets one keep line keeps.
static func keep_cap(catalog: Catalog) -> int:
	return maxi(1, int(data(catalog).get("keep", {}).get("cap", 50)))


## What keep lines can pick, in order: nothing, every trait, then the parts in 'marks' marked keep
## that the book has seen (`seen`: book key -> anything, see Collection.part_key).
static func keep_options(catalog: Catalog, seen: Dictionary) -> Array[String]:
	var out: Array[String] = [""]
	for t in catalog.traits:
		out.append("trait:" + str(t.id))
	var marks: Dictionary = data(catalog).get("marks", {})
	for mark in marks:
		if bool(marks[mark].get("keep", false)) and str(mark).begins_with("part:") and seen.has(str(mark)):
			out.append(str(mark))
	return out


## Whether a pick is one keep lines can ever have (a trait, or a keep part).
static func keep_valid(catalog: Catalog, pick: String) -> bool:
	if pick == "":
		return true
	if pick.begins_with("trait:"):
		return catalog.traits.any(func(t): return "trait:" + str(t.id) == pick)
	return bool(data(catalog).get("marks", {}).get(pick, {}).get("keep", false))


## What a keep line says for its pick: "zoomy ones", "halos", "nothing".
static func keep_word(catalog: Catalog, pick: String) -> String:
	if pick == "":
		return "nothing"
	if pick.begins_with("trait:"):
		return "%s ones" % pick.substr(6)
	return many(catalog, pick)


## Adds a new pet's uid to a pick's kept list (the newest last); the oldest past the cap drop off.
## Returns the uids that dropped off.
static func keep(catalog: Catalog, kept: Dictionary, pick: String, uid: String) -> Array:
	if not kept.has(pick):
		kept[pick] = []
	var list: Array = kept[pick]
	list.append(uid)
	var over := list.size() - keep_cap(catalog)
	var gone: Array = []
	if over > 0:
		gone = list.slice(0, over)
		kept[pick] = list.slice(over)
	return gone
