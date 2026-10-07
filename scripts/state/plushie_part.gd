class_name PlushiePart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Whether the plushie machine is open (the sewing room's last room brings it, data/unlocks.json).
func plushie_open() -> bool:
	return gs.feature_on("plushie")


## The keeper's uid while the machine is open ("" otherwise): it stays home (no adventures, no army).
func _plushie_keeper_uid() -> String:
	return str(gs.plushie.keeper) if plushie_open() else ""


## Pets that can be the keeper, in the order ‹ › goes through them: your active pet, pets with
## buttons (most first), favourites, then the other cards (rarest first). Not pets away on an
## adventure or in the dungeon's army, or good pulls waiting to be seen.
func plushie_keepers() -> Array[Pet]:
	var gone := gs._out()
	var ranked := []
	for pet in gs.collection.pets:
		if gone.has(pet.uid) or pet.uid in gs.pinned:
			continue
		var kind := 3 if pet.uid == gs.collection.active_uid else (2 if not pet.buttons.is_empty() else (1 if pet.fav else 0))
		ranked.append([kind, Plushie.total(pet), gs.catalog.rank(pet.rarity) * 10 + gs.catalog.finish_rank(pet.finish), int(pet.uid), pet])
	ranked.sort_custom(func(a, b):
		for k in 3:
			if a[k] != b[k]:
				return a[k] > b[k]
		return a[3] < b[3])
	var out: Array[Pet] = []
	for r in ranked:
		out.append(r[4])
	return out


## The keeper: the pet you picked (null while it's away: it can't be sent, but an old save may have
## it out). Only when there's none yet, or it's gone for good, the first pet on the list becomes the
## keeper, and whatever the reels held is sewn onto it (no button is ever dropped).
func plushie_keeper() -> Pet:
	var uid := str(gs.plushie.keeper)
	var pet := gs.collection.get_pet(uid) if uid != "" and not Herd.is_stand_in(uid) else null
	if pet != null:
		return null if gs._out().has(uid) else pet
	var keepers := plushie_keepers()
	if keepers.is_empty():
		return null
	var sewn := Plushie.set_keeper(gs.catalog, gs.plushie, keepers[0])
	if not sewn.is_empty():
		_plushie_sewn.call_deferred(keepers[0], sewn)
		_plushie_saved.call_deferred()
	return keepers[0]


## Whether ‹ › can pick another keeper: nothing held, and another pet could be the keeper (a cheap
## count, not the sorted list).
func plushie_can_swap() -> bool:
	if Plushie.anything_held(gs.plushie):
		return false
	var n := gs.collection.pets.size() - gs.pinned.size()
	for uid in gs._out():
		if not Herd.is_stand_in(str(uid)):
			n -= 1
	return n > 1


## The next (d = 1) or previous (d = -1) keeper. Not while any reel holds buttons. Banked reels
## stay banked for the fed pet (swapping there and back doesn't spin them again).
func plushie_swap(d: int) -> bool:
	if Plushie.anything_held(gs.plushie):
		return false
	var keepers := plushie_keepers()
	var now := plushie_keeper()
	if keepers.is_empty() or (now != null and keepers.size() < 2):
		return false
	var i := keepers.find(now) if now != null else (-1 if d > 0 else 0)
	Plushie.set_keeper(gs.catalog, gs.plushie, keepers[posmod(i + d, keepers.size())])
	gs.collection.refold()  # the old keeper may fold into the herd now
	_plushie_saved()
	return true


## Pets from the herd of one rarity that could go into the hopper, and are resting (the + takes one
## off a job only when none are).
func plushie_herd(rarity: String) -> int:
	var n := 0
	for k in _plushie_keys(rarity):
		n += gs.collection.herd_count(k)
	return n


func _plushie_keys(rarity: String) -> Array[String]:
	var out: Array[String] = []
	for f in gs.catalog.finishes:
		if Herd.plain(gs.catalog, f.id):
			out.append(Herd.key(rarity, f.id))
	return out


## One pet from the herd of a rarity goes into the hopper (plain first, then shiny; resting ones
## first, then off a job). It leaves your collection for good. False when none can.
func plushie_feed_herd(rarity: String) -> bool:
	if not plushie_open() or gs.plushie.hopper.size() >= Plushie.hopper_max(gs.catalog):
		return false
	var out := gs._stand_ins_out()
	var out_of := {}
	for uid: String in out:
		Herd.put(out_of, Herd.key_of(uid), 1)
	var resting := gs.resting_herd()
	var pick := ""
	var off_job := false  # the pet comes off an errand or a worker job (none of that count rest)
	for k in _plushie_keys(rarity):
		if int(resting.get(k, 0)) > 0:
			pick = k
			break
	if pick == "":
		for k in _plushie_keys(rarity):
			if gs.collection.herd_count(k) - int(out_of.get(k, 0)) > 0 and gs._herd_at_places(k) > 0:
				pick = k
				off_job = true
				break
	if pick == "":
		return false
	var uids := gs.collection.stand_in_uids(pick, 1, out)
	var pet := gs.collection.get_pet(uids[0]) if not uids.is_empty() else null
	if pet == null:
		return false
	if off_job and gs._herd_off_places(pick, 1) <= 0:
		return false
	var d := pet.to_dict()
	d.uid = ""
	gs.collection.remove([uids[0]])
	Plushie.feed(gs.catalog, gs.plushie, d)
	_plushie_saved()
	return true


## Cards that can go into the hopper: resting ones, never your active pet, the keeper, favourites,
## pets with buttons or good pulls waiting to be seen.
func plushie_cards() -> Array[Pet]:
	var keeper := str(gs.plushie.keeper)
	var out: Array[Pet] = []
	for pet in gs.resting_cards():
		if _plushie_card_ok(pet, keeper):
			out.append(pet)
	return out


## Whether any card could go into the hopper (stops at the first one).
func plushie_has_cards() -> bool:
	var keeper := str(gs.plushie.keeper)
	for pet in gs.resting_cards():
		if _plushie_card_ok(pet, keeper):
			return true
	return false


func _plushie_card_ok(pet: Pet, keeper: String) -> bool:
	return not pet.fav and pet.buttons.is_empty() and pet.uid != keeper and not pet.uid in gs.pinned


## A card goes into the hopper (it leaves your collection for good). False when it can't.
func plushie_feed_card(uid: String) -> bool:
	if not plushie_open() or gs.plushie.hopper.size() >= Plushie.hopper_max(gs.catalog) or not plushie_cards().any(func(p): return p.uid == uid):
		return false
	var d := gs.collection.get_pet(uid).to_dict()
	d.uid = ""
	gs.collection.remove([uid])
	Plushie.feed(gs.catalog, gs.plushie, d)
	_plushie_saved()
	return true


## Pulls the lever: one spin, or the next pet hops in when the fed pet's spins are used up.
## Returns what happened (see Plushie.spin; next_pet's { sewn, fed } with next = true), {} if nothing.
func plushie_spin() -> Dictionary:
	var keeper := plushie_keeper() if plushie_open() else null
	if keeper == null:
		return {}
	var result: Dictionary
	if Plushie.needs_next(gs.plushie):
		result = Plushie.next_pet(gs.catalog, gs.plushie, keeper, gs.perk_nudges())
		result.next = true
	else:
		result = Plushie.spin(gs.catalog, gs.plushie, keeper, gs._rng, gs.debug_land)
		gs.debug_land = {}
		if result.is_empty():
			return {}
		gs.grant_wisps(int(result.wisps), true)
		if not result.popped.is_empty() or int(result.wild.get("popped", 0)) > 0:
			_plushie_sewn(keeper, { "popped": true })  # a crack knocked buttons off: its knacks shrank
	_plushie_sewn(keeper, result.sewn)
	gs.plushie_spun.emit(result)
	_plushie_saved()
	return result


## Banks reel i (its held buttons are sewn on). Returns how many.
func plushie_bank(i: int) -> int:
	var keeper := plushie_keeper()
	var got := Plushie.bank(gs.catalog, gs.plushie, keeper, i)
	if got > 0:
		var sewn := { Catalog.SLOTS[i]: got }
		_plushie_sewn(keeper, sewn)
		gs.plushie_spun.emit({ "sewn": sewn, "banked": i })
		_plushie_saved()
	return got


## Holds reel i for the next spin (or lets go). False when it can't.
func plushie_hold(i: int) -> bool:
	if not Plushie.toggle_hold(gs.catalog, gs.plushie, i, gs.perk_holds()):
		return false
	_plushie_saved()
	return true


## Nudges reel i down one. Returns what it lands on now ("" when it can't).
func plushie_nudge(i: int) -> String:
	var keeper := plushie_keeper()
	var got := Plushie.nudge(gs.catalog, gs.plushie, keeper, i, gs._rng) if keeper != null else ""
	if got != "":
		_plushie_sewn(keeper, { "nudged": true })  # landing again can knock buttons off, or put them back
		gs.plushie_spun.emit({ "nudged": i, "landed": { i: got } })
		_plushie_saved()
	return got


## What the next nudge, hold or wild reel costs in wisps (-1: can't be bought now).
func plushie_price(what: String) -> int:
	return Plushie.price(gs.catalog, gs.plushie, plushie_keeper(), what)


## Buys a nudge, a hold or the wild reel with wisps. False when it can't.
func plushie_buy(what: String) -> bool:
	var price := plushie_price(what)
	if not plushie_open() or price < 0 or gs.wisps < price:
		return false
	gs.wisps -= price
	Plushie.buy(gs.catalog, gs.plushie, plushie_keeper(), what)
	_plushie_saved()
	return true


## Moves the wild reel to the next (1) or previous (-1) part.
func plushie_wild_step(d: int) -> void:
	Plushie.wild_step(gs.catalog, gs.plushie, plushie_keeper(), d)
	_plushie_saved()


## Reel i's odds in % for the keeper and the fed pet ({} when that part is full).
func plushie_odds(i: int) -> Dictionary:
	return Plushie.odds(gs.catalog, gs.plushie, plushie_keeper(), i)


func _plushie_sewn(keeper: Pet, sewn: Dictionary) -> void:
	if sewn.is_empty() or keeper == null:
		return
	gs.collection.pet_changed.emit(keeper)  # its knacks grew
	if keeper.uid == gs.collection.active_uid:
		gs.collection.active_changed.emit(keeper)  # everything showing your pet redraws it


func _plushie_saved() -> void:
	gs.plushie_changed.emit()
	gs.changed.emit()
	gs.save_game()
