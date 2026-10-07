class_name BoostsPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Hands out loot (see Rewards): coins to the wallet, boxes and parts to the bag, anything else
## into `items` until something uses it. Coins are boosted by the toys your pet is playing with,
## unless `boosted` is false (the loot was boosted already, to show the real amount).
func grant(loot: Dictionary, boosted := true) -> void:
	for key: String in loot:
		var amount := int(loot[key])
		var kind := key.get_slice(":", 0)
		var rest := key.substr(kind.length() + 1)
		match kind:
			"coins":
				# kept under int's top: a huge late payout must never wrap round to minus coins
				var add := amount * boost("coins") if boosted else float(amount)
				gs.coins = GameStateNode.COINS_MAX if add >= float(GameStateNode.COINS_MAX - gs.coins) else gs.coins + roundi(add)
			"box":
				gs.bag[rest] = gs.in_bag(rest) + amount
			"part":
				if not gs.feature_on("parts"):
					continue  # parts come much later in the game: nothing brings one home before that
				gs.parts[rest] = int(gs.parts.get(rest, 0)) + amount
				gs.parts_ever = true
			"find":
				gs.finds[rest] = true
				gs._globe_home(rest)
			"bit":
				if not _bit_home(rest):
					continue  # a later globe's bit before that globe is home: nothing brings one yet
				gs.bits[rest] = int(gs.bits.get(rest, 0)) + amount
			"wisps":
				grant_wisps(amount, true)
			"rumour":
				gs._hear_rumours(amount)
			_:
				gs.items[key] = int(gs.items.get(key, 0)) + amount
	gs.check_unlocks()
	gs.changed.emit()


## Whether a machine bit's globe is home (the sunset bits wait for the sunset globe).
func _bit_home(bit: String) -> bool:
	var info := Machine.bit_info(gs.catalog, bit)
	return info.is_empty() or Machine.has_globe(gs.machine, gs.catalog, str(info.get("globe", Machine.first_globe(gs.catalog))))


## Gives wisps, the darker currency: the one way into the purse (the dungeon's cleared floors, the
## plushie machine's misses, grant({ "wisps": n })). `quiet`: the caller emits changed itself.
func grant_wisps(n: int, quiet := false) -> void:
	if n <= 0:
		return
	gs.wisps += n
	if not quiet:
		gs.changed.emit()


## How much one boost kind (see data/boosts.json "kinds") is multiplied right now, every source
## together (1.0 when nothing is). Called every frame (errand meters, the machine), so the totals are
## kept until a source changes (_boosts_changed; a play running out emits toys_changed).
func boost(kind: String) -> float:
	if not gs._boosts.has(kind):
		gs._boosts[kind] = Boosts.total(boost_parts(kind))
	return gs._boosts[kind]


## What boosts a kind right now, one part per thing doing it: { source, id, x } (see Boosts). Every
## source is gathered here, since GameState holds their state; a new source appends its parts
## below. Sources: toys your pet is playing with and favourites, the collection book's open
## stickers, your active pet's knacks, the kitchen's cooks (errands only), the little school's classes
## (automation and errands) and care's buffs (only while the game is open). [] (and an error) for a kind that isn't in data/boosts.json.
func boost_parts(kind: String) -> Array[Dictionary]:
	if not Boosts.is_kind(gs.catalog, kind):
		push_error("unknown boost kind %s" % kind)
		return []
	var now := Time.get_unix_time_from_system()
	var out: Array[Dictionary] = []
	out.append_array(Toys.parts(gs.toys, gs.catalog, kind, now))
	out.append_array(Book.parts(gs.catalog, gs.stickers, kind))
	out.append_array(Knacks.parts(gs.catalog, gs.collection.active(), kind, knack_gate))
	if kind == "errands":
		var cooks := gs.kitchen_bonus()  # reads only the cooks' speeds, never boost()
		if cooks > 0.0:
			out.append(Boosts.part("kitchen", "kitchen", 1.0 + cooks))
	if (kind == "automation" or kind == "errands") and gs._school_x > 1.0:  # the little school's classes
		out.append(Boosts.part("school", "school", gs._school_x))
	if not (gs._loading or gs._away):  # the buffs only count while the game is open (see _without_care)
		out.append_array(Care.parts(gs.catalog, kind, gs.hunger, gs.happiness))
	out.append_array(Perks.parts(gs.catalog, gs.perks, kind))
	return out


## The boost receipt (the x1.51 tag by the coin pill): every kind with a shared boost right now,
## by kind, each line named (see Boosts.receipt).
func boost_receipt() -> Array:
	var by_kind := {}
	for k in Boosts.kinds(gs.catalog):
		by_kind[k] = boost_parts(k)
	return Boosts.receipt(gs.catalog, by_kind, _boost_line_name)


## A receipt line's name: the toy ("holo acorn"), the book's sticker ("a paint set"), your pet's
## badges ("big ears + one big eye"), the kitchen, a care buff ("full tummy"), a wisps perk ("the lucky coin"). A new source names its lines here.
func _boost_line_name(part: Dictionary) -> String:
	match str(part.source):
		"toys": return Toys.edition_name(gs.catalog, str(part.id))
		"book": return str(Book.page(gs.catalog, str(part.id)).get("name", part.id))
		"knacks": return Knacks.part_names(gs.catalog, str(part.id))
		"kitchen": return "the kitchen"
		"school": return "the little school"
		"care": return str(Care.buff(gs.catalog, str(part.id)).get("name", part.id))
		"perks": return str(Perks.perk(gs.catalog, str(part.id)).get("name", part.id))
	return str(part.id)


## The machine's "why so much?": a capsule's plain coins, every upgrade that multiplies them, the
## shared boosts, and the "N coins a capsule" it all comes to.
func capsule_why() -> Dictionary:
	var lines := []
	for p in Machine.coin_parts(gs.machine, gs.catalog):
		lines.append({ "name": p.name, "x": p.x })
	lines.append({ "name": "our boosts", "x": boost("coins") })
	return Boosts.why("a capsule", float(gs.catalog.machine_tree.get("base_coins", 1)), lines,
		Machine.coin_value(gs.machine, gs.catalog) * boost("coins"))


## The errands pill's "why so much?": what the crews bring a minute on their own (no tools, goals or
## tips), then each layer as how much it multiplied the total (every job differs, so a layer is
## the ratio of the totals with and without it), the shared boosts, and the pill's number.
func errands_why() -> Dictionary:
	var crews := _errands_layered(false, false, false)
	var tips := _errands_layered(false, false, true)  # the plain tips (the fancy cups are a tool)
	var tools := _errands_layered(true, false, true)
	var all := _errands_layered(true, true, true)
	if crews <= 0.0:
		return Boosts.why("the crews", 0.0, [], 0.0)
	return Boosts.why("the crews", crews, [
		{ "name": "our tools", "x": tools / tips if tips > 0.0 else 1.0 },
		{ "name": "job levels", "x": all / tools if tools > 0.0 else 1.0 },
		{ "name": "tips", "x": tips / crews },
		{ "name": "our boosts", "x": gs.errands_per_minute() / all if all > 0.0 else 1.0 }], gs.errands_per_minute())


## Coins a minute from the coin errands before the shared boosts, with or without the tools, the
## job levels' goals and the tips (errands_per_minute is this with every layer on and the errands
## boost, times the coins boost). `with_boost`: each job's errands boost (see _job_errands_x).
func _errands_layered(with_tools: bool, with_goals: bool, with_tips: bool, with_boost := false) -> float:
	var total := 0.0
	for job in gs.open_jobs():
		var p: Dictionary = job.get("pay", {})
		if p.has("capsules") or p.has("coins"):
			var x := gs._job_errands_x(job.id) if with_boost else 1.0
			total += gs._job_plain_rate(job.id, with_tools) * x * 60.0 * Jobs.average_fill(job, gs.job_boost(job.id, with_tools, with_goals, with_tips))
	return total


## A boost source changed (toys found, played with, levelled, or a play ended; a new save): the
## kept totals are worked out again.
func _boosts_changed() -> void:
	gs._boosts.clear()


## Something every pet's knacks depend on changed (a pet's parts, a new save): the boosts, each
## pet's own knack share and the errand and worker speeds are worked out again.
func _knacks_changed() -> void:
	_boosts_changed()
	gs._knack_steps.clear()
	gs._knack_own.clear()
	gs.knack_version += 1
	gs._job_speed.clear()
	gs._crew_speeds.clear()
	gs._kitchen = -1.0  # the cooks' speeds hold their knacks
	gs._worker_speed.clear()


## A knack gate may have opened (an unlock, a machine fix, the tutorial): the boosts are worked out
## again, and the errand or worker speeds only if the knack kinds counting for them changed (a
## machine fix only opens fever and shiny knacks, which neither uses).
func _knack_gates_changed() -> void:
	_boosts_changed()
	var was := { "errands": _knack_counting("errands"), "automation": _knack_counting("automation") }
	gs._knack_steps.clear()
	gs._knack_own.clear()
	gs.knack_version += 1
	if _knack_counting("errands") != was.errands:
		gs._job_speed.clear()
		gs._crew_speeds.clear()
		gs._kitchen = -1.0
	if _knack_counting("automation") != was.automation:
		gs._worker_speed.clear()
	gs.knacks_changed.emit()


## The knack kinds counting for a boost kind right now (see Knacks.counting), kept until a gate moves.
func _knack_counting(kind: String) -> Dictionary:
	if not gs._knack_steps.has(kind):
		gs._knack_steps[kind] = Knacks.counting(gs.catalog, kind, knack_gate)
	return gs._knack_steps[kind]


## What a card pet's own knacks of a kind do for its own work (see Knacks.own: in full, data
## "own"), kept per pet until its parts or a gate change, so big crews and parties stay quick. Herd
## counts work at their plain template's speed (no uid, no knacks); stand-ins are whole pets and
## count theirs.
func knack_own(pet: Pet, kind: String) -> float:
	if pet == null or pet.uid == "":  # a count's template (see Herd.template): pets from the herd have no knacks
		return 1.0
	var steps := _knack_counting(kind)
	if steps.is_empty():
		return 1.0
	if not gs._knack_own.has(kind):
		gs._knack_own[kind] = {}
	var per: Dictionary = gs._knack_own[kind]
	if not per.has(pet.uid):
		per[pet.uid] = Knacks.own_in(gs.catalog, pet, steps)
	return per[pet.uid]


## Whether a knack gate (data/knacks.json "opens") is open: "adventures" (the tutorial is past the
## machine), "machine:<node>" (that node on the machine's tree is fixed), or an unlock id.
func knack_gate(gate: String) -> bool:
	if gate == "adventures":
		return not gs.tutorial in ["pull", "machine"]
	if gate.begins_with("machine:"):
		return Machine.owned(gs.machine, gate.substr(8)) > 0
	return gs.is_open(gate)


## Your active pet's knacks that show right now (see Knacks.of), or another pet's.
func knacks_of(pet: Pet) -> Array[Dictionary]:
	return Knacks.of(gs.catalog, pet, knack_gate)


## What knacks do for a trip with these pets: your active pet's (the boost, which has the other
## sources too) times the party's own share, per kind; kinds at x1 are left out. `loot` is the
## party's share only (your active pet's loot boost is added when the trip is collected).
func trip_knacks(pets: Array) -> Dictionary:
	var out := {}
	for kind: String in Boosts.trip_kinds(gs.catalog):
		var share := 1.0
		if not pets.is_empty() and not _knack_counting(kind).is_empty():
			var sum := 0.0
			for pet in pets:
				sum += knack_own(pet, kind)
			share = sum / pets.size()
		var x := share * (1.0 if kind == "loot" else boost(kind))
		if not is_equal_approx(x, 1.0):
			out[kind] = x
	return out


## Opens the sticker of every book page that's full now (once each, for good): the popup shows it.
func check_book() -> void:
	if gs._loading:
		return
	var opened := Book.newly_full(gs.catalog, gs.collection, gs.stickers, gs.book_rank())
	if opened.is_empty():
		return
	for id in opened:
		gs.stickers.append(id)
	_boosts_changed()  # the book is a boost source
	for id in opened:
		gs.sticker_opened.emit(id)
	gs.jobs_changed.emit()
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Gives xp, boosted (the "xp" kind). Returns how much it really was.
func add_xp(amount: int) -> int:
	var real := roundi(amount * boost("xp"))
	gs.xp += real
	return real
