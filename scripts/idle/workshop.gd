class_name Workshop
extends RefCounted
## The shed workshop's rules (data/workshop.json, F3): drawings pinned on the shed's plank are built
## by crowds of helpers (plain pets, with a rarity need), and each built one takes an old chore
## away (GameState does the chores). Pure rules on the workshop's state from the save:
##   { pinned: [drawing ids, one per spot, "" for an empty spot], prog: { id: { sent, qual } },
##     built: [ids, in the order built], helpers: pets that ever stayed on to help,
##     vane: { "place:event": option index } (your last pick there, for the weather vane) }
## `sent` is every helper on a drawing, `qual` the ones at its tier or up.


static func data(catalog: Catalog) -> Dictionary:
	return catalog.workshop


static func drawings(catalog: Catalog) -> Array:
	return catalog.workshop.get("drawings", [])


static func drawing(catalog: Catalog, id: String) -> Dictionary:
	for d in drawings(catalog):
		if str(d.id) == id:
			return d
	return {}


## A new workshop: the first drawings pinned, nothing built.
static func fresh(catalog: Catalog) -> Dictionary:
	var state := { "pinned": [], "prog": {}, "built": [], "helpers": 0, "vane": {} }
	for d in drawings(catalog):
		if state.pinned.size() >= int(data(catalog).get("pinned", 3)):
			break
		state.pinned.append(str(d.id))
		state.prog[str(d.id)] = { "sent": 0, "qual": 0 }
	return state


## A workshop from a save, made safe: unknown drawings dropped, built ones never pinned, empty
## spots refilled from the list (a save from before a drawing was added), numbers never negative.
static func clean(catalog: Catalog, saved: Variant) -> Dictionary:
	if not saved is Dictionary or (saved as Dictionary).is_empty():
		return fresh(catalog)
	var s: Dictionary = saved
	var state := { "pinned": [], "prog": {}, "built": [], "helpers": maxi(0, int(s.get("helpers", 0))), "vane": {} }
	for raw in s.get("built", []):
		var id := str(raw)
		if not drawing(catalog, id).is_empty() and not id in state.built:
			state.built.append(id)
	var slots := int(data(catalog).get("pinned", 3))
	var saved_pins: Array = s.get("pinned", []) if s.get("pinned", []) is Array else []
	for i in slots:
		var id := str(saved_pins[i]) if i < saved_pins.size() else ""
		if drawing(catalog, id).is_empty() or id in state.built or id in state.pinned:
			id = ""
		state.pinned.append(id)
	var saved_prog: Dictionary = s.get("prog", {}) if s.get("prog", {}) is Dictionary else {}
	for id: String in state.pinned:
		if id == "":
			continue
		var p: Variant = saved_prog.get(id, {})
		var sent := maxi(0, int((p as Dictionary).get("sent", 0))) if p is Dictionary else 0
		var qual := clampi(int((p as Dictionary).get("qual", 0)), 0, sent) if p is Dictionary else 0
		state.prog[id] = { "sent": sent, "qual": qual }
	for i in state.pinned.size():
		if state.pinned[i] == "":
			_pin_next(catalog, state, i)
	var saved_vane: Dictionary = s.get("vane", {}) if s.get("vane", {}) is Dictionary else {}
	for k in saved_vane:
		state.vane[str(k)] = int(saved_vane[k])
	return state


## Pins the next drawing from the list nobody has pinned or built into spot `i` ("" if none left).
static func _pin_next(catalog: Catalog, state: Dictionary, i: int) -> String:
	for d in drawings(catalog):
		var id := str(d.id)
		if not id in state.built and not id in state.pinned:
			state.pinned[i] = id
			state.prog[id] = { "sent": 0, "qual": 0 }
			return id
	state.pinned[i] = ""
	return ""


## The drawings on the plank right now, in spot order (empty spots left out).
static func pinned(state: Dictionary) -> Array:
	return state.pinned.filter(func(id): return str(id) != "")


static func has(state: Dictionary, id: String) -> bool:
	return id in state.built


static func all_built(catalog: Catalog, state: Dictionary) -> bool:
	return pinned(state).is_empty() and state.built.size() >= drawings(catalog).size()


static func prog(state: Dictionary, id: String) -> Dictionary:
	return state.prog.get(id, { "sent": 0, "qual": 0 })


## Whether a pinned drawing has every helper it needs (and enough of them at its tier or up).
static func full(catalog: Catalog, state: Dictionary, id: String) -> bool:
	var d := drawing(catalog, id)
	if d.is_empty() or not state.prog.has(id):
		return false
	var p := prog(state, id)
	return int(p.sent) >= int(d.need) and int(p.qual) >= int(d.count)


## How full a drawing is, 0..1 (its helpers; the plank's little bars).
static func fill(catalog: Catalog, state: Dictionary, id: String) -> float:
	var d := drawing(catalog, id)
	if d.is_empty():
		return 0.0
	return clampf(float(prog(state, id).sent) / maxf(1.0, float(d.need)), 0.0, 1.0)


## Whether a rarity counts toward a drawing's tier need.
static func meets(catalog: Catalog, d: Dictionary, rarity: String) -> bool:
	return catalog.rank(rarity) >= catalog.rank(str(d.tier))


## How many more pets of a rarity still help this drawing: pets below its tier leave room for the
## ones it still needs at its tier, so it can always be finished.
static func useful(catalog: Catalog, state: Dictionary, id: String, rarity: String) -> int:
	var d := drawing(catalog, id)
	if d.is_empty() or not state.prog.has(id):
		return 0
	var p := prog(state, id)
	var left := maxi(0, int(d.need) - int(p.sent))
	if meets(catalog, d, rarity):
		return left
	return maxi(0, left - maxi(0, int(d.count) - int(p.qual)))


## `n` helpers of a rarity join a drawing (never more than useful). Returns how many joined.
static func take(catalog: Catalog, state: Dictionary, id: String, rarity: String, n: int) -> int:
	var k := mini(n, useful(catalog, state, id, rarity))
	if k <= 0:
		return 0
	var p: Dictionary = state.prog[id]
	p.sent = int(p.sent) + k
	if meets(catalog, drawing(catalog, id), rarity):
		p.qual = int(p.qual) + k
	state.helpers = int(state.helpers) + k
	return k


## Builds a full drawing: it's built, and the next drawing from the list is pinned in its spot.
## Returns the drawing pinned in its place ("" if none left), or null if it couldn't be built.
static func build(catalog: Catalog, state: Dictionary, id: String) -> Variant:
	if not full(catalog, state, id):
		return null
	return finish(catalog, state, id)


## Marks a pinned drawing built whatever its helpers (the dev step `build`, and build()).
static func finish(catalog: Catalog, state: Dictionary, id: String) -> Variant:
	var i: int = state.pinned.find(id)
	if i < 0:
		return null
	state.built.append(id)
	state.prog.erase(id)
	return _pin_next(catalog, state, i)


## The weather vane's pick for a run waiting at an event, or -1 to leave it to you: only a plain
## event (no option at that place is risky), only your last pick for that event at that place, and
## only if this party may take it.
static func vane_pick(catalog: Catalog, state: Dictionary, run: RunState) -> int:
	if run.status != RunState.Status.WAITING or run.auto or run.chooser == "policy":
		return -1
	var event := run.current_event(catalog)
	if event.is_empty() or event.get("auto", false):
		return -1
	var location := AdventureRunner.place(run, catalog)
	var options := AdventureRunner.options_of(event, location)
	for option in options:
		if AdventureRunner.risky(option, location):
			return -1
	var pick := int(state.vane.get(vane_key(run.location_id, str(event.get("id", ""))), -1))
	return pick if pick in AdventureRunner.allowed_options(event, run.party, location) else -1


static func vane_key(location_id: String, event_id: String) -> String:
	return "%s:%s" % [location_id, event_id]
