class_name SewingPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Whether the sewing room's door is there (the tiny key from floor 20).
func sewing_open() -> bool:
	return gs.feature_on("sewing")


## Room `i` of the sewing room (fixed, or rolled past them), see Sewing.room.
func sew_room(i: int) -> Dictionary:
	return Sewing.room(gs.catalog, i)


## The army's front row: its strongest front_row cards (your pet with the flag leads).
func sew_front() -> Array[Pet]:
	return gs.army_cards().slice(0, gs.front_row_size())


## Whether a pet can sit on a sewing room seat: any card that isn't away on an adventure, down the
## well with the army or leading a workers' party (ones on errands and machines come off when it
## goes in; your active pet and the plushie machine's keeper may go too).
func sew_can_sit(pet: Pet) -> bool:
	return pet != null and not Herd.is_stand_in(pet.uid) and gs.collection.get_pet(pet.uid) == pet and not _sew_gone().has(pet.uid)


## Pets that can't sit down now: away, down there with the army, leading a party. uid -> true.
func _sew_gone() -> Dictionary:
	var out := gs.away()
	for uid in gs.dungeon.run.get("cards", []):
		out[str(uid)] = true
	for uid in gs.workers_of("adventures"):
		out[str(uid)] = true
	return out


## The pets the seats can take, the strongest first.
func sew_pickable() -> Array[Pet]:
	var gone := _sew_gone()
	var out: Array[Pet] = []
	for pet in gs.collection.pets:
		if not gone.has(pet.uid) and not Herd.is_stand_in(pet.uid):
			out.append(pet)
	return gs._strongest_first(out)


## The seats are for room `i` now: lining up another room starts with empty seats.
func sew_pick_room(i: int) -> void:
	if i != gs.sew_seats_room and not (gs.dungeon_running() and gs.dungeon.run.has("room")):
		gs.sew_seats = {}
		gs.sew_seats_room = i


## Puts a pet on room `i`'s seat for `mark` (it has to fit it); it sits on every other empty seat
## it fits too. Returns whether it sat down.
func sew_seat(i: int, mark: String, uid: String) -> bool:
	var r := sew_room(i)
	var pet := gs.collection.get_pet(uid)
	if gs.dungeon_running() or not mark in r.marks or not sew_can_sit(pet) or not Sewing.mark_matches(mark, pet):
		return false
	sew_pick_room(i)
	gs.sew_seats[mark] = uid
	_sew_fill(r)
	return true


## The pet on `mark`'s seat gets up (off every seat it was on); other seated pets that fit take the
## empty seats.
func sew_unseat(i: int, mark: String) -> void:
	if gs.dungeon_running() or i != gs.sew_seats_room or not gs.sew_seats.has(mark):
		return
	var uid := str(gs.sew_seats[mark])
	for m in gs.sew_seats.keys():
		if str(gs.sew_seats[m]) == uid:
			gs.sew_seats.erase(m)
	_sew_fill(sew_room(i))


## Empty seats take a seated pet that fits them.
func _sew_fill(r: Dictionary) -> void:
	var seated := _sew_seated_pets(r)
	for mark in r.marks:
		if not gs.sew_seats.has(mark):
			for pet in seated:
				if Sewing.mark_matches(str(mark), pet):
					gs.sew_seats[mark] = pet.uid
					break


## Room `i`'s seats: mark -> the pet on it (only pets still here, free and fitting; during its run,
## the ones that went in).
func sew_seat_pets(i: int) -> Dictionary:
	var out := {}
	if i != gs.sew_seats_room:
		return out
	var running: bool = gs.dungeon_running() and gs.dungeon.run.has("room")
	var gone := {} if running else _sew_gone()
	for mark in sew_room(i).marks:
		var pet := gs.collection.get_pet(str(gs.sew_seats.get(mark, "")))
		if pet != null and Sewing.mark_matches(str(mark), pet) and (running or (not Herd.is_stand_in(pet.uid) and not gone.has(pet.uid))):
			out[mark] = pet
	return out


func _sew_seated_pets(r: Dictionary) -> Array[Pet]:
	var out: Array[Pet] = []
	var seats := sew_seat_pets(int(r.i))
	for mark in seats:
		if not out.has(seats[mark]):
			out.append(seats[mark])
	return out


## The pets sitting on room `i`'s seats (each once).
func sew_seated(i: int) -> Array[Pet]:
	return _sew_seated_pets(sew_room(i))


## Which of room `i`'s marks have a pet on their seat: [bool].
func sew_marks(i: int) -> Array:
	var seats := sew_seat_pets(i)
	return sew_room(i).marks.map(func(m): return seats.has(m))


## Who goes into room `i`: the seated pets first, then the army lined up (its cards, then its herd),
## up to the entrance: { cards: [Pet] strongest first, keys: { count key: n }, sent, more: how many
## walk in besides the seated ones }.
func sew_party(i: int) -> Dictionary:
	var seated := sew_seated(i)
	var entrance := Dungeon.entrance(gs.catalog, gs.perk_level("entrance"))
	var cards: Array[Pet] = seated.duplicate()
	for pet in gs.army_cards():
		if not cards.has(pet):
			cards.append(pet)
	if cards.size() > maxi(entrance, seated.size()):
		cards = cards.slice(0, maxi(entrance, seated.size()))
	cards = gs._strongest_first(cards)
	var keys := _cap_keys(gs.army_herd_keys(), maxi(0, entrance - cards.size()))
	var sent := cards.size() + Herd.total(keys)
	return { "cards": cards, "keys": keys, "sent": sent, "more": sent - seated.size() }


## Herd counts cut down to `n` pets, the rarer ones kept first.
func _cap_keys(keys: Dictionary, n: int) -> Dictionary:
	if Herd.total(keys) <= n:
		return keys.duplicate()
	var order := keys.keys()
	order.sort_custom(func(a, b): return gs.catalog.rank(Herd.rarity_of(a)) > gs.catalog.rank(Herd.rarity_of(b)))
	var out := {}
	for k in order:
		var take := mini(n, int(keys[k]))
		if take > 0:
			out[k] = take
			n -= take
	return out


## Whether the army can go into room `i` now: a room that shows, a pet on every seat, nobody down
## there already.
## `party`: sew_party(i) when it's at hand.
func sew_can_go(i: int, party := {}) -> bool:
	if not (sewing_open() and i >= 0 and i < Sewing.shown(gs.sewing) and not gs.dungeon_running() and not gs.tutorial_active()):
		return false
	return sew_marks(i).all(func(on): return on) and int((party if not party.is_empty() else sew_party(i)).sent) > 0


## The feeling word for room `i` against who'd go in now: [word, heat] ([] with nobody going).
## `party`: sew_party(i) when it's at hand.
func sew_word(i: int, party := {}) -> Array:
	if party.is_empty():
		party = sew_party(i)
	if int(party.sent) <= 0:
		return []
	return Dungeon.word(gs.catalog, Dungeon.army_power(gs.catalog, gs._army_rules(party.cards, party.keys), "room") / Sewing.strength(gs.catalog, sew_room(i)))


## The seated pets and the army go into room `i`: the fight is worked out now (Sewing.simulate), its
## pets stay busy (it's the dungeon's run) until it's back. Seated pets come off their errands and
## machines. Returns whether it went.
func send_to_room(i: int) -> bool:
	if not sew_can_go(i):
		return false
	gs.dungeon_report = {}  # (a well run's report never comes back after a room run)
	var party := sew_party(i)
	var cards: Array = party.cards
	var herd_keys: Dictionary = party.keys
	gs._off_work(cards.map(func(p): return p.uid).filter(func(uid): return uid != gs.collection.active_uid))
	var rng := RandomNumberGenerator.new()
	rng.seed = gs._rng.randi()
	var orders := { "entrance": gs.perk_level("entrance"), "pay_x": gs.boost("lanterns"),
		"first": str(gs.dungeon.first) if Dungeon.first_earned(gs.catalog, gs.dungeon) else "" }
	var result := Sewing.simulate(gs.catalog, gs._army_rules(cards, herd_keys), sew_room(i), orders, rng)
	gs.dungeon.run = { "at": Time.get_unix_time_from_system(), "floors": result.floors, "why": result.why, "turned": 0,
		"cards": cards.map(func(p): return p.uid), "herd": herd_keys.duplicate(), "sent": int(party.sent), "target": int(gs.dungeon.target),
		"room": i, "door": int(gs.catalog.sewing.get("door_floor", 20)), "seconds": Sewing.seconds(gs.catalog) }
	gs.sew_last = {}
	gs._rest_changed()
	gs.dungeon_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## The army is back from a room: losses as a well floor, a clear pays its wisps, and the first clear
## of the next room counts (its firsts: keep lines, the plushie machine).
func _finish_room_run(quiet := false) -> void:
	var run: Dictionary = gs.dungeon.run
	gs.dungeon.run = {}
	gs._rest_changed()
	var i := int(run.get("room", 0))
	var r := sew_room(i)
	var lost_n := gs._run_losses(run)
	var got := Dungeon.run_pay(run)
	var cleared: bool = not run.get("floors", []).is_empty() and bool(run.floors[0].get("cleared", false))
	gs.grant_wisps(got)
	var first := cleared and i == int(gs.sewing.cleared)
	if first:
		gs.sewing.cleared = i + 1
		var f: Dictionary = r.get("first", {})
		if int(f.get("keep_lines", 0)) > 0 and Sewing.keep_lines(gs.catalog, i) > 0 and gs.feature_on("keep_lines"):
			var lines: Array = gs.catalog.voice.get("ui", {}).get("sewing_more_lines", [])  # the first line comes with its popup
			if not lines.is_empty():
				gs.announcements.append(str(lines[gs._rng.randi_range(0, lines.size() - 1)]))
		if f.has("find"):
			gs.grant({ "find:" + str(f.find): 1 }, false)
		gs._keep_lines_changed()
	gs.dungeon.last = { "floor": int(run.get("door", gs.catalog.sewing.get("door_floor", 20))), "got": got,
		"back": int(run.get("sent", 0)) - lost_n, "room": i }
	gs.sew_last = { "room": i, "got": got, "sent": int(run.get("sent", 0)), "back": int(run.get("sent", 0)) - lost_n, "cleared": cleared, "first": first }
	gs.dungeon.cards = gs.dungeon.cards.filter(func(uid): return gs.collection.get_pet(str(uid)) != null)
	gs.dungeon_news = { "got": got, "room": str(r.name), "cleared": cleared, "again": cleared and not first }
	if not quiet:
		gs._home_again()


## Where a dashed mark comes from, in your pet's words (like bit_hint): parts from the tier that has
## them and the box with the most of it, traits and finishes from any box, buttons from the plushie
## machine. Keep lines, once open, get a word in for parts and traits.
func sew_hint(mark: String) -> String:
	var hints: Dictionary = gs.catalog.sewing.get("hints", {})
	var p := mark.split(":")
	var many := Sewing.many(gs.catalog, mark)
	var text := ""
	match p[0]:
		"part":
			var tier := str(gs.catalog.part(p[1], p[2]).get("rarity", "common")) if p.size() > 2 else "common"
			text = str(hints.get("part", "")).format({ "many": many, "tier": gs.catalog.tier_at(gs.catalog.rank(tier)).name, "box": _best_box("tiers", tier) })
		"trait":
			text = str(hints.get("trait", "")).format({ "many": many })
		"finish":
			text = str(hints.get("finish", "")).format({ "many": many, "box": _best_box("finishes", p[1] if p.size() > 1 else "") })
		"tier":
			text = str(hints.get("tier", "")).format({ "tier": many, "box": _best_box("tiers", p[1] if p.size() > 1 else "") })
		"buttons":
			text = str(hints.get("buttons", "")).format({ "n": int(p[1]) if p.size() > 1 else 1 })
	if gs.keep_lines_on() and (p[0] == "trait" or p[0] == "part") and mark in gs.keep_line_options():
		text += str(hints.get("keep", "")).format({ "many": Sewing.keep_word(gs.catalog, mark) })
	return text


## The name of the shop box with the best share of a tier (`key` "tiers") or finish ("finishes").
func _best_box(key: String, id: String) -> String:
	var best := ""
	var share := -1.0
	for box in gs.catalog.boxes:
		if box.get("hidden", false):
			continue
		var weights: Dictionary = box.get(key, {})
		var total := 0.0
		for w in weights.values():
			total += float(w)
		var s := float(weights.get(id, 0.0)) / total if total > 0.0 else 0.0
		if s > share:
			share = s
			best = str(box.get("name", box.id))
	return best


## Debug and tests: the first `n` rooms are cleared, with their real firsts.
func debug_sewn(n: int) -> void:
	while int(gs.sewing.cleared) < n:
		var r := sew_room(int(gs.sewing.cleared))
		gs.sewing.cleared = int(gs.sewing.cleared) + 1
		if r.get("first", {}).has("find"):
			gs.grant({ "find:" + str(r.first.find): 1 }, false)
	gs._keep_lines_changed()
	gs.check_unlocks()
	gs.dungeon_changed.emit()
