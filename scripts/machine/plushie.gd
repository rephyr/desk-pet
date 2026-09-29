class_name Plushie
extends RefCounted
## The plushie machine (F1/F2, data/plushie.json): buttons sewn onto the keeper's parts. You pick
## the keeper, feed pets into the hopper, and the best one in the hopper hops in: its rarity is how
## many spins it gives, its finish adds nudges, its traits tilt the reels. One reel per part (in
## Catalog.SLOTS order); each spin lands on a button, a blank or a crack. A button adds one to what
## that reel holds (two if the reel was on HOLD and already held one); a crack takes what it holds
## away; a blank keeps it. You BANK a reel (its held buttons are sewn on and it stops for this pet)
## or HOLD it for the next spin (a few at once). A reel holding buttons that isn't on hold banks by
## itself at the next spin, and whatever is held when the spins run out is banked too. Misses puff
## WISPS, the darker currency, which buy nudges, holds and a wild 6th reel (its button goes straight
## onto the part you pick). A part holds 0..max_buttons buttons; each makes its knack bigger (see
## Knacks) and they stay on the part when it's grafted (see Grafting).
## Pure rules: the machine's state is a plain dictionary (saved as it is, see fresh()), the keeper
## is a Pet, the dice come in. GameState keeps the state and does the rest (who can be fed, wisps).
## Design: design/mockups/screens/sacrifice-reels.html look A (the cabinet).

const BUTTON := "button"
const BLANK := "blank"
const CRACK := "crack"
const SYMBOLS: Array[String] = [BUTTON, BLANK, CRACK]
const SHOP: Array[String] = ["nudge", "hold", "wild"]


static func data(catalog: Catalog) -> Dictionary:
	return catalog.plushie


## A machine nobody has used yet:
##   keeper: the uid of the pet getting buttons ("" = the first one GameState offers)
##   hopper: pets fed in and waiting (small pet dicts, Pet.to_dict), nudges: the pool,
##   bought: { nudge, hold } bought with wisps (prices grow), try: see fresh_try().
static func fresh() -> Dictionary:
	return { "keeper": "", "hopper": [], "nudges": 0, "bought": { "nudge": 0, "hold": 0 }, "try": fresh_try() }


## The pet in the machine and its reels: fed (a pet dict, {} for nobody), spins left of spins_max,
## a reel per part (fresh_reel), wild: the wild reel for this pet ({} when not bought): { slot, strip }.
static func fresh_try() -> Dictionary:
	var reels := []
	for i in Catalog.SLOTS.size():
		reels.append(fresh_reel())
	return { "fed": {}, "spins": 0, "spins_max": 0, "reels": reels, "wild": {} }


## One reel: strip (above, the middle it landed on, below), held buttons, on hold, banked (stopped
## for this pet), fresh (just landed: a nudge can move it), and what it held before the last spin
## and whether it was on hold then (a nudge lands it again from there).
static func fresh_reel() -> Dictionary:
	return { "strip": [BLANK, BLANK, BLANK], "held": 0, "hold": false, "banked": false, "fresh": false, "before": 0, "was_hold": false }


## A machine from a save: anything odd falls back to a fresh value.
static func clean(raw, catalog: Catalog) -> Dictionary:
	var out := fresh()
	if not raw is Dictionary:
		return out
	out.keeper = str(raw.get("keeper", ""))
	var hopper = raw.get("hopper", [])
	if hopper is Array:
		for p in hopper:
			if p is Dictionary and out.hopper.size() < hopper_max(catalog):
				out.hopper.append(Pet.from_dict(p, catalog).to_dict())
	out.nudges = maxi(0, int(raw.get("nudges", 0)))
	var bought = raw.get("bought", {})
	if bought is Dictionary:
		for k in ["nudge", "hold"]:
			out.bought[k] = maxi(0, int(bought.get(k, 0)))
	var t = raw.get("try", {})
	if t is Dictionary:
		var fed = t.get("fed", {})
		if fed is Dictionary and not fed.is_empty():
			out.try.fed = Pet.from_dict(fed, catalog).to_dict()
			out.try.spins_max = maxi(0, int(t.get("spins_max", 0)))
			out.try.spins = clampi(int(t.get("spins", 0)), 0, out.try.spins_max)
		var reels = t.get("reels", [])
		if reels is Array:
			for i in mini(reels.size(), Catalog.SLOTS.size()):
				var r = reels[i]
				if not r is Dictionary:
					continue
				var strip := [BLANK, BLANK, BLANK]
				var s = r.get("strip", [])
				if s is Array and s.size() == 3 and s.all(func(x): return str(x) in SYMBOLS):
					strip = s.map(func(x): return str(x))
				out.try.reels[i] = { "strip": strip, "held": clampi(int(r.get("held", 0)), 0, max_buttons(catalog)),
					"hold": bool(r.get("hold", false)), "banked": bool(r.get("banked", false)), "fresh": bool(r.get("fresh", false)),
					"before": clampi(int(r.get("before", 0)), 0, max_buttons(catalog)), "was_hold": bool(r.get("was_hold", false)) }
		var wild = t.get("wild", {})
		if wild is Dictionary and str(wild.get("slot", "")) in Catalog.SLOTS and not out.try.fed.is_empty():
			var ws = wild.get("strip", [])
			out.try.wild = { "slot": str(wild.slot), "strip": ws.map(func(x): return str(x)) if ws is Array and ws.size() == 3 and ws.all(func(x): return str(x) in SYMBOLS) else [BLANK, BLANK, BLANK] }
	return out


# ---- buttons on a pet ----------------------------------------------------------------------

static func max_buttons(catalog: Catalog) -> int:
	return int(data(catalog).get("max_buttons", 5))


## Buttons on one of a pet's parts.
static func buttons(pet: Pet, slot: String) -> int:
	return int(pet.buttons.get(slot, 0)) if pet != null else 0


## Every button on a pet.
static func total(pet: Pet) -> int:
	var n := 0
	if pet != null:
		for slot in pet.buttons:
			n += int(pet.buttons[slot])
	return n


static func full(catalog: Catalog, pet: Pet, slot: String) -> bool:
	return buttons(pet, slot) >= max_buttons(catalog)


## Sews up to n buttons onto a part (never past max_buttons). Returns how many went on.
static func sew(catalog: Catalog, pet: Pet, slot: String, n: int) -> int:
	if pet == null or n <= 0 or not slot in Catalog.SLOTS:
		return 0
	var got := mini(n, max_buttons(catalog) - buttons(pet, slot))
	if got > 0:
		pet.buttons[slot] = buttons(pet, slot) + got
	return maxi(got, 0)


## How much a part's knack grows with its buttons (x1 with none).
static func knack_x(catalog: Catalog, n: int) -> float:
	return 1.0 + float(data(catalog).get("knack_per_button", 0.5)) * n


# ---- the fed pet -----------------------------------------------------------------------------

static func fed(state: Dictionary) -> Dictionary:
	return state.try.fed


static func _traits(state: Dictionary) -> Array:
	return fed(state).get("traits", [])


## A trait tilt added up over the fed pet's traits (button, crack, spins).
static func _trait_sum(catalog: Catalog, traits: Array, key: String) -> float:
	var n := 0.0
	var tilts: Dictionary = data(catalog).get("traits", {})
	for t in traits:
		n += float(tilts.get(str(t), {}).get(key, 0.0))
	return n


## A trait tilt multiplied over the fed pet's traits (wisps).
static func _trait_x(catalog: Catalog, traits: Array, key: String) -> float:
	var x := 1.0
	var tilts: Dictionary = data(catalog).get("traits", {})
	for t in traits:
		x *= float(tilts.get(str(t), {}).get(key, 1.0))
	return x


## Spins a pet gives (by its rarity, and its traits).
static func spins_for(catalog: Catalog, pet: Dictionary) -> int:
	var by: Dictionary = data(catalog).get("spins", {})
	return maxi(1, int(by.get(str(pet.get("rarity", "common")), 1)) + roundi(_trait_sum(catalog, pet.get("traits", []), "spins")))


## Nudges a pet's finish adds to the pool.
static func nudges_for(catalog: Catalog, finish: String) -> int:
	return int(data(catalog).get("nudges", {}).get(finish, 0))


## The hopper's best pet (rarest, then best finish): its index, or -1 when the hopper's empty.
static func best_index(catalog: Catalog, hopper: Array) -> int:
	var best := -1
	for i in hopper.size():
		if best < 0 or _rank(catalog, hopper[i]) > _rank(catalog, hopper[best]):
			best = i
	return best


static func _rank(catalog: Catalog, pet: Dictionary) -> int:
	return catalog.rank(str(pet.get("rarity", "common"))) * 100 + catalog.finish_rank(str(pet.get("finish", "normal")))


static func hopper_max(catalog: Catalog) -> int:
	return int(data(catalog).get("hopper_max", 50))


## Puts a pet (a dict) in the hopper. False when it's full.
static func feed(catalog: Catalog, state: Dictionary, pet: Dictionary) -> bool:
	if state.hopper.size() >= hopper_max(catalog):
		return false
	state.hopper.append(pet)
	return true


# ---- the reels -------------------------------------------------------------------------------

## A reel's odds in whole %: { button, blank, crack } for a part with `n` buttons and the fed pet's
## traits ({} for a full part: it doesn't spin).
static func odds_for(catalog: Catalog, n: int, traits: Array) -> Dictionary:
	if n >= max_buttons(catalog):
		return {}
	var d := data(catalog)
	var ups: Array = d.get("button", [34])
	var cracks: Array = d.get("crack", [8])
	var up := clampi(int(ups[clampi(n, 0, ups.size() - 1)]) + roundi(_trait_sum(catalog, traits, "button")), 0, 100)
	var crack := clampi(int(cracks[clampi(n, 0, cracks.size() - 1)]) + roundi(_trait_sum(catalog, traits, "crack")), int(d.get("crack_min", 0)), 100 - up)
	return { "button": up, "blank": 100 - up - crack, "crack": crack }


## Reel i's odds for the keeper and the fed pet ({} when that part is full).
static func odds(catalog: Catalog, state: Dictionary, keeper: Pet, i: int) -> Dictionary:
	return odds_for(catalog, buttons(keeper, Catalog.SLOTS[i]), _traits(state))


static func roll(o: Dictionary, rng: RandomNumberGenerator) -> String:
	if o.is_empty():
		return BUTTON
	var r := rng.randi_range(0, 99)
	if r < int(o.button):
		return BUTTON
	if r < int(o.button) + int(o.crack):
		return CRACK
	return BLANK


## Whether reel i still spins for this pet: not banked, and its part isn't full.
static func active(catalog: Catalog, state: Dictionary, keeper: Pet, i: int) -> bool:
	return not state.try.reels[i].banked and not full(catalog, keeper, Catalog.SLOTS[i])


static func anything_held(state: Dictionary) -> bool:
	return state.try.reels.any(func(r): return int(r.held) > 0)


static func holds_max(catalog: Catalog, state: Dictionary) -> int:
	return int(data(catalog).get("holds", 2)) + int(state.bought.get("hold", 0))


static func holds_used(state: Dictionary) -> int:
	return state.try.reels.filter(func(r): return r.hold).size()


## Whether the next press brings the next pet in ("next!"): nobody's in, or its spins are used up.
static func needs_next(state: Dictionary) -> bool:
	return fed(state).is_empty() or int(state.try.spins) <= 0


## Wisps a miss puffs: by the fed pet's rarity, more for a crack, x perfection (the keeper's
## buttons) and x the fed pet's traits.
static func puff(catalog: Catalog, state: Dictionary, keeper: Pet, crack: bool) -> int:
	var d := data(catalog)
	var n := float(d.get("puff", {}).get(str(fed(state).get("rarity", "common")), 1))
	if crack:
		n *= float(d.get("crack_puff", 2))
	n *= perfection(catalog, keeper) * _trait_x(catalog, _traits(state), "wisps")
	return maxi(1, roundi(n))


## How much more misses puff for a keeper with buttons (x1 with none).
static func perfection(catalog: Catalog, keeper: Pet) -> float:
	return 1.0 + float(data(catalog).get("perfection", 0.0)) * total(keeper)


## One spin: reels holding buttons that aren't on hold bank first, then every reel still going
## lands (and the wild reel, if bought). `forced`: slot (or "wild") -> symbol, what those reels land
## on (the dev driver's "land"). Returns
##   { sewn: { slot: buttons sewn on }, landed: { reel index: symbol }, puffed: { reel index: wisps },
##     wisps: all puffed, wild: { slot, symbol, sewn, wisps } or {}, stopped: true when nothing could spin }
## or {} when it can't spin (no keeper, or the next pet has to come in first).
static func spin(catalog: Catalog, state: Dictionary, keeper: Pet, rng: RandomNumberGenerator, forced := {}) -> Dictionary:
	if keeper == null or needs_next(state):
		return {}
	var t: Dictionary = state.try
	var out := { "sewn": {}, "landed": {}, "puffed": {}, "wisps": 0, "wild": {} }
	for i in t.reels.size():
		var r: Dictionary = t.reels[i]
		if not r.banked and int(r.held) > 0 and not r.hold:
			_bank(catalog, state, keeper, i, out.sewn)
	var live: Array[int] = []
	for i in t.reels.size():
		if active(catalog, state, keeper, i):
			live.append(i)
	var wild: Dictionary = t.wild
	var wild_live := not wild.is_empty() and not full(catalog, keeper, str(wild.slot))
	if live.is_empty() and not wild_live:
		t.spins = 0  # everything's banked or full: on to the next pet
		out.stopped = true
		return out
	t.spins = int(t.spins) - 1
	for r in t.reels:
		r.fresh = false
	for i in live:
		var r: Dictionary = t.reels[i]
		r.before = int(r.held)
		r.was_hold = r.hold
		r.hold = false
		var o := odds(catalog, state, keeper, i)
		var mid := str(forced.get(Catalog.SLOTS[i], roll(o, rng)))
		r.strip = [roll(o, rng), mid, roll(o, rng)]
		r.fresh = true
		_resolve(catalog, state, keeper, i)
		out.landed[i] = mid
		if mid != BUTTON:
			var n := puff(catalog, state, keeper, mid == CRACK)
			out.puffed[i] = n
			out.wisps += n
	if wild_live:
		var slot := str(wild.slot)
		var o := odds_for(catalog, buttons(keeper, slot), _traits(state))
		var mid := str(forced.get("wild", roll(o, rng)))
		wild.strip = [roll(o, rng), mid, roll(o, rng)]
		out.wild = { "slot": slot, "symbol": mid, "sewn": 0, "wisps": 0 }
		if mid == BUTTON:
			var got := sew(catalog, keeper, slot, 1)
			out.wild.sewn = got
			if got > 0:
				out.sewn[slot] = int(out.sewn.get(slot, 0)) + got
			var r: Dictionary = t.reels[Catalog.SLOTS.find(slot)]
			r.held = mini(int(r.held), max_buttons(catalog) - buttons(keeper, slot))  # never more than still fits
			if int(r.held) == 0:
				r.hold = false
		else:
			var n := puff(catalog, state, keeper, mid == CRACK)
			out.wild.wisps = n
			out.wisps += n
	return out


## What reel i holds after landing, from what it held before the spin.
static func _resolve(catalog: Catalog, state: Dictionary, keeper: Pet, i: int) -> void:
	var r: Dictionary = state.try.reels[i]
	var h := int(r.before)
	match str(r.strip[1]):
		BUTTON:
			h += 2 if r.was_hold and int(r.before) > 0 else 1
		CRACK:
			h = 0
	r.held = clampi(h, 0, max_buttons(catalog) - buttons(keeper, Catalog.SLOTS[i]))
	if int(r.held) == 0:
		r.hold = false


## Banks reel i: its held buttons are sewn on and it stops for this pet. Returns how many.
static func bank(catalog: Catalog, state: Dictionary, keeper: Pet, i: int) -> int:
	var sewn := {}
	_bank(catalog, state, keeper, i, sewn)
	return int(sewn.get(Catalog.SLOTS[i], 0))


static func _bank(catalog: Catalog, state: Dictionary, keeper: Pet, i: int, sewn: Dictionary) -> void:
	var r: Dictionary = state.try.reels[i]
	if keeper == null or r.banked or int(r.held) <= 0:
		return
	var slot: String = Catalog.SLOTS[i]
	var got := sew(catalog, keeper, slot, int(r.held))
	if got > 0:
		sewn[slot] = int(sewn.get(slot, 0)) + got
	r.held = 0
	r.hold = false
	r.banked = true
	r.fresh = false


## Whether reel i's hold can be tapped now: it's on hold (tap to let go), or it holds buttons, isn't
## banked, spins are left and a hold is free.
static func can_hold(catalog: Catalog, state: Dictionary, i: int) -> bool:
	var r: Dictionary = state.try.reels[i]
	if r.hold:
		return true
	return int(r.held) > 0 and not r.banked and not needs_next(state) and holds_used(state) < holds_max(catalog, state)


## Holds reel i for the next spin, or lets go of it. False when it can't (see can_hold).
static func toggle_hold(catalog: Catalog, state: Dictionary, i: int) -> bool:
	if not can_hold(catalog, state, i):
		return false
	var r: Dictionary = state.try.reels[i]
	r.hold = not r.hold
	return true


## Whether reel i can be nudged: it just landed, it's still going, and there's a nudge in the pool.
static func can_nudge(catalog: Catalog, state: Dictionary, keeper: Pet, i: int) -> bool:
	var r: Dictionary = state.try.reels[i]
	return not fed(state).is_empty() and r.fresh and active(catalog, state, keeper, i) and int(state.nudges) > 0


## Nudges reel i down one: the cell above lands in the middle (a new one rolls in on top), and the
## reel lands again from what it held before the spin. Uses a nudge. Returns the new middle, or "".
static func nudge(catalog: Catalog, state: Dictionary, keeper: Pet, i: int, rng: RandomNumberGenerator) -> String:
	if not can_nudge(catalog, state, keeper, i):
		return ""
	state.nudges = int(state.nudges) - 1
	var r: Dictionary = state.try.reels[i]
	r.strip = [roll(odds(catalog, state, keeper, i), rng), r.strip[0], r.strip[1]]
	_resolve(catalog, state, keeper, i)
	return str(r.strip[1])


## The fed pet's spins are used up: everything still held is banked, and the best pet in the
## hopper hops in (its finish adds nudges). Returns { sewn: { slot: n }, fed: the new pet's dict or {} }.
static func next_pet(catalog: Catalog, state: Dictionary, keeper: Pet) -> Dictionary:
	var out := { "sewn": {}, "fed": {} }
	var t: Dictionary = state.try
	for i in t.reels.size():
		_bank(catalog, state, keeper, i, out.sewn)
	for r in t.reels:
		r.held = 0
		r.hold = false
		r.banked = false
		r.fresh = false
		r.before = 0
		r.was_hold = false
	t.wild = {}
	var best := best_index(catalog, state.hopper)
	if best < 0:
		t.fed = {}
		t.spins = 0
		t.spins_max = 0
		return out
	t.fed = state.hopper[best]
	state.hopper.remove_at(best)
	t.spins_max = spins_for(catalog, t.fed)
	t.spins = t.spins_max
	state.nudges = int(state.nudges) + nudges_for(catalog, str(t.fed.get("finish", "normal")))
	out.fed = t.fed
	return out


## A new keeper. Whatever a reel still holds is banked onto the new keeper first, so no button is
## ever dropped (a swap only happens with nothing held; this is for a keeper that's gone for good).
## Banked reels stay banked: they stopped for the fed pet, whoever the keeper is (only next_pet
## starts them again). Returns { slot: buttons sewn }.
static func set_keeper(catalog: Catalog, state: Dictionary, keeper: Pet) -> Dictionary:
	var sewn := {}
	state.keeper = keeper.uid if keeper != null else ""
	for i in state.try.reels.size():
		_bank(catalog, state, keeper, i, sewn)
	for r in state.try.reels:
		r.held = 0
		r.hold = false
		r.fresh = false
		r.before = 0
		r.was_hold = false
	return sewn


# ---- the wild reel and the shop --------------------------------------------------------------

## The part a new wild reel starts on: the one with the fewest buttons ("" when every part is full).
static func wild_default(catalog: Catalog, keeper: Pet) -> String:
	var best := ""
	for slot in Catalog.SLOTS:
		if not full(catalog, keeper, slot) and (best == "" or buttons(keeper, slot) < buttons(keeper, best)):
			best = slot
	return best


## Moves the wild reel to the next (d = 1) or previous (d = -1) part that isn't full.
static func wild_step(catalog: Catalog, state: Dictionary, keeper: Pet, d: int) -> void:
	var wild: Dictionary = state.try.wild
	if wild.is_empty():
		return
	var i := Catalog.SLOTS.find(str(wild.slot))
	for step in Catalog.SLOTS.size():
		i = posmod(i + d, Catalog.SLOTS.size())
		if not full(catalog, keeper, Catalog.SLOTS[i]):
			wild.slot = Catalog.SLOTS[i]
			return


## Whether a wild reel can be bought now: a pet has spins left, it has none yet, and a part has room.
static func wild_available(catalog: Catalog, state: Dictionary, keeper: Pet) -> bool:
	return keeper != null and not needs_next(state) and state.try.wild.is_empty() and wild_default(catalog, keeper) != ""


## What the next one costs in wisps, or -1 when it can't be bought now (the wild reel: see
## wild_available). Prices stop at shop.max.
static func price(catalog: Catalog, state: Dictionary, keeper: Pet, what: String) -> int:
	var shops: Dictionary = data(catalog).get("shop", {})
	var shop: Dictionary = shops.get(what, {})
	if shop.is_empty():
		return -1
	var most := float(shops.get("max", 4.0e18))
	match what:
		"nudge", "hold":
			return roundi(minf(float(shop.wisps) * pow(float(shop.get("grow", 1.0)), int(state.bought.get(what, 0))), most))
		"wild":
			if not wild_available(catalog, state, keeper):
				return -1
			return roundi(minf(float(shop.wisps) * (catalog.rank(str(fed(state).get("rarity", "common"))) + 1), most))
	return -1


## Buys one (the caller pays the price first). False when it can't be bought.
static func buy(catalog: Catalog, state: Dictionary, keeper: Pet, what: String) -> bool:
	if price(catalog, state, keeper, what) < 0:
		return false
	match what:
		"nudge":
			state.bought.nudge = int(state.bought.get("nudge", 0)) + 1
			state.nudges = int(state.nudges) + 1
		"hold":
			state.bought.hold = int(state.bought.get("hold", 0)) + 1
		"wild":
			state.try.wild = { "slot": wild_default(catalog, keeper), "strip": [BLANK, BLANK, BLANK] }
	return true
