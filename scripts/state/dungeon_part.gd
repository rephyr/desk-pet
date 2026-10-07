class_name DungeonPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## What the army's last run was like, for your pet to say (once), or {}.
func take_dungeon_news() -> Dictionary:
	var news := gs.dungeon_news
	gs.dungeon_news = {}
	return news


## Whether the dungeon is open (the rope find at the well).
func dungeon_open() -> bool:
	return gs.feature_on("dungeon")


## Whether the army is down the well right now.
func dungeon_running() -> bool:
	return not gs.dungeon.run.is_empty()


## Cards in the army: the picked ones, and the ones down there now. uid -> true.
func _army_uids() -> Dictionary:
	var out := {}
	for uid in gs.dungeon.cards:
		out[str(uid)] = true
	for uid in gs.dungeon.run.get("cards", []):
		out[str(uid)] = true
	return out


## Everyone busy elsewhere for good reason: away on a trip, or in the dungeon's army. uid -> true.
func _out() -> Dictionary:
	var out := gs.away()
	out.merge(_army_uids())
	return out


## The army's pets from the herd: the run's while it's down there, otherwise the shelves' picks spread
## over their counts (better finishes first), out of what's left once everyone else has theirs (`used`).
func _army_herd(used: Dictionary) -> Dictionary:
	if dungeon_running():
		return Herd.clean_counts(gs.catalog, gs.dungeon.run.get("herd", {}))
	var out := {}
	for rarity: String in gs.dungeon.herd:
		var left := int(gs.dungeon.herd[rarity])
		var keys: Array = gs.collection.herd.keys().filter(func(k): return Herd.rarity_of(k) == rarity and gs.may_go_finish(Herd.finish_of(k)))
		keys.sort_custom(func(a, b): return gs.catalog.finish_rank(Herd.finish_of(a)) > gs.catalog.finish_rank(Herd.finish_of(b)))
		for k in keys:
			if left <= 0:
				break
			var take := mini(left, gs.collection.herd_count(k) - int(used.get(k, 0)))
			if take > 0:
				out[k] = take
				left -= take
	return out


## The army's pets from the herd: count key -> how many.
func army_herd_keys() -> Dictionary:
	return gs._resting().get("army_herd", {})


## A pet's power in the dungeon (its own power knack counts, gear never does).
func army_power_of(pet: Pet) -> float:
	return Dungeon.pet_power(gs.catalog, pet, gs.knack_own(pet, "power"))


## The cards in the army, the strongest first (while it's down there: the ones that went).
func army_cards() -> Array[Pet]:
	var out: Array[Pet] = []
	var uids: Array = gs.dungeon.run.get("cards", []) if dungeon_running() else gs.dungeon.cards
	for uid in uids:
		var pet := gs.collection.get_pet(str(uid))
		if pet:
			out.append(pet)
	return _strongest_first(out)


## Cards that could go in the army (resting ones, ones on errands and machines, and the ones in it),
## the strongest first. Never the plushie machine's keeper: it stays home.
func army_choices() -> Array[Pet]:
	var out: Array[Pet] = []
	if not dungeon_running():
		for uid in gs.dungeon.cards:
			var pet := gs.collection.get_pet(str(uid))
			if pet:
				out.append(pet)
	var keeper := gs._plushie_keeper_uid()
	for pet in gs.resting_cards() + _working_cards():  # working ones come off their errands to join
		if pet.uid != keeper:
			out.append(pet)
	return _strongest_first(out)


## Pets sorted by their power in the dungeon, the strongest first (each pet's power worked out once).
func _strongest_first(pets: Array[Pet]) -> Array[Pet]:
	var pairs: Array = pets.map(func(p: Pet): return [army_power_of(p), p])
	pairs.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var out: Array[Pet] = []
	for pair in pairs:
		out.append(pair[1])
	return out


## The army as the page shows it: { cards: [Pet] strongest first, herd: { rarity: n }, sent, entrance }.
func army() -> Dictionary:
	var herd := {}
	var keys := army_herd_keys()
	for k in keys:
		herd[Herd.rarity_of(k)] = int(herd.get(Herd.rarity_of(k), 0)) + int(keys[k])
	var cards := army_cards()
	return { "cards": cards, "herd": herd, "keys": keys, "sent": cards.size() + Herd.total(keys),
		"entrance": Dungeon.entrance(gs.catalog, gs.perk_level("entrance")) }


## Pets of a rarity from the herd that could go: the ones in the army already, resting ones and the
## ones on errands and machines (they come off when they join), below the keep line. Never pets away.
func army_herd_room(rarity: String) -> int:
	var out_now := {}
	for uid: String in gs._stand_ins_out():
		Herd.put(out_now, Herd.key_of(uid), 1)
	var n := 0
	for k in gs.collection.herd:
		if Herd.rarity_of(k) == rarity and gs.may_go_finish(Herd.finish_of(k)):
			n += maxi(0, gs.collection.herd_count(k) - int(out_now.get(k, 0)))
	return n


## Cards on errands or machines (not away, not your pet): the army can take them off to join.
func _working_cards() -> Array[Pet]:
	var out: Array[Pet] = []
	var busy := gs._busy_uids()
	for uid in gs._job_of.keys() + gs._worker_of.keys():
		var pet := gs.collection.get_pet(str(uid))
		if pet and not busy.has(pet.uid) and not Herd.is_stand_in(pet.uid) and pet.uid != gs.collection.active_uid:
			out.append(pet)
	return out


## Adds a card to the army (while there's room at the entrance; off its errand or machine if it has
## one), or takes it out.
func set_army_card(uid: String, on: bool) -> bool:
	if dungeon_running() or on == (uid in gs.dungeon.cards):
		return false
	if on:
		var a := army()
		if int(a.sent) >= int(a.entrance) or uid == gs._plushie_keeper_uid():
			return false
		if not (gs.resting_cards() + _working_cards()).any(func(p): return p.uid == uid):
			return false
		_off_work([uid])
		gs.dungeon.cards.append(uid)
	else:
		gs.dungeon.cards.erase(uid)
	_army_changed()
	return true


## The best cards (by power) in the front row: the army's cards become the strongest front_row of
## the ones it has and the resting ones. The herd makes room if the entrance is full.
func army_best() -> void:
	if dungeon_running():
		return
	var best: Array = army_choices().slice(0, gs.front_row_size()).map(func(p): return p.uid)
	var room := Dungeon.entrance(gs.catalog, gs.perk_level("entrance"))
	gs.dungeon.cards = best.slice(0, room)
	_off_work(gs.dungeon.cards)
	gs._rest_changed()
	_trim_army_herd()
	_army_changed()


## Pets of a rarity from the herd in the army (as many as there are and the entrance lets through).
func set_army_herd(rarity: String, n: int) -> void:
	if dungeon_running():
		return
	var a := army()
	var others := int(a.sent) - int(a.herd.get(rarity, 0))
	n = clampi(n, 0, mini(army_herd_room(rarity), int(a.entrance) - others))
	_free_for_army(rarity, n - int(a.herd.get(rarity, 0)))
	if n > 0:
		gs.dungeon.herd[rarity] = n
	else:
		gs.dungeon.herd.erase(rarity)
	_army_changed()


## "fill up": pets from the shelves join the army until the entrance is full, the plainest shelf
## first (commons, then uncommons...), as many as each has that may go (army_herd_room: below the keep
## line, never pets away; the herd never holds favourites or your pet). The front row stays as it is.
func army_fill_up() -> void:
	if dungeon_running():
		return
	var a := army()
	var left := int(a.entrance) - int(a.sent)
	var tiers: Array = gs.catalog.tiers.duplicate()
	tiers.sort_custom(func(x, y): return gs.catalog.rank(str(x.id)) < gs.catalog.rank(str(y.id)))
	for tier in tiers:
		if left <= 0:
			break
		var have := int(a.herd.get(tier.id, 0))
		var more := mini(left, army_herd_room(str(tier.id)) - have)
		if more <= 0:
			continue
		_free_for_army(str(tier.id), more)
		gs.dungeon.herd[str(tier.id)] = have + more
		left -= more
		gs._rest_changed()
	_army_changed()


## "empty": nobody from the shelves walks behind any more (the front row stays).
func army_empty() -> void:
	if dungeon_running() or gs.dungeon.herd.is_empty():
		return
	gs.dungeon.herd = {}
	_army_changed()


## `more` pets of a rarity are joining the army's herd: past the resting ones, they come off their
## errands and machines (the finishes the army takes first, see _army_herd).
func _free_for_army(rarity: String, more: int) -> void:
	var resting := 0
	var rest := gs.resting_herd()
	for k in rest:
		if Herd.rarity_of(k) == rarity and gs.may_go_finish(Herd.finish_of(k)):
			resting += int(rest[k])
	var need := more - resting
	if need <= 0:
		return
	var keys: Array = gs.collection.herd.keys().filter(func(k): return Herd.rarity_of(k) == rarity and gs.may_go_finish(Herd.finish_of(k)))
	keys.sort_custom(func(a, b): return gs.catalog.finish_rank(Herd.finish_of(a)) > gs.catalog.finish_rank(Herd.finish_of(b)))
	for k in keys:
		if need <= 0:
			break
		need -= gs._herd_off_places(str(k), need)


## These cards come off their errands and machines (they're joining the army).
func _off_work(uids: Array) -> void:
	var on_jobs := uids.filter(func(uid): return gs._job_of.has(uid))
	var on_machines := uids.filter(func(uid): return gs._worker_of.has(uid))
	if not on_jobs.is_empty():
		gs._take_off(on_jobs)
	if not on_machines.is_empty():
		gs._take_off_workers(on_machines)


## The herd's picks make room for the cards: the plainest shelves give way first.
func _trim_army_herd() -> void:
	var over := int(army().sent) - Dungeon.entrance(gs.catalog, gs.perk_level("entrance"))
	for tier in gs.catalog.tiers:
		if over <= 0:
			break
		var have := int(gs.dungeon.herd.get(tier.id, 0))
		var cut := mini(have, over)
		if cut > 0:
			if have - cut > 0:
				gs.dungeon.herd[tier.id] = have - cut
			else:
				gs.dungeon.herd.erase(tier.id)
			over -= cut
			gs._rest_changed()


func _army_changed() -> void:
	gs._rest_changed()
	gs.dungeon_changed.emit()
	gs.save_game()


## Steps an order: "start" (start from the top or a fully held landing), "target" (go down to floor,
## at least the floor under the start), "home" (come home when X% are gone), "first" (who goes first,
## once earned).
func set_order(key: String, step: int) -> void:
	if dungeon_running():
		return
	var d: Dictionary = gs.catalog.dungeon
	match key:
		"start":
			var starts := Dungeon.starts(gs.catalog, gs.dungeon)
			set_start(starts[clampi(starts.find(int(gs.dungeon.start)) + step, 0, starts.size() - 1)])
			return
		"target":
			gs.dungeon.target = clampi(int(gs.dungeon.target) + step, int(gs.dungeon.start) + 1, Dungeon.target_max(gs.catalog, gs.dungeon))
		"home":
			var steps: Array = d.home_at.map(func(v): return int(v))
			var i := clampi(steps.find(int(gs.dungeon.home_at)) + step, 0, steps.size() - 1)
			gs.dungeon.home_at = steps[i]
		"first":
			if not Dungeon.first_earned(gs.catalog, gs.dungeon):
				return
			var lines: Array = d.first.lines
			var i := clampi(lines.find(str(gs.dungeon.first)) + step, 0, lines.size() - 1)
			gs.dungeon.first = str(lines[i])
	gs.dungeon_changed.emit()
	gs.save_game()


## Sets an order to a value (a row of choices on the orders card): "target" (a floor, kept between the
## floor under the start and target_max), "home" (a step of data home_at), "first" (a line of data
## first, once earned), "start" (see set_start). Returns whether it took.
func set_order_to(key: String, value) -> bool:
	if dungeon_running():
		return false
	gs.dungeon_report = {}  # (new orders: the page lines up the next run)
	var d: Dictionary = gs.catalog.dungeon
	match key:
		"start":
			return set_start(int(value))
		"target":
			gs.dungeon.target = clampi(int(value), int(gs.dungeon.start) + 1, Dungeon.target_max(gs.catalog, gs.dungeon))
		"home":
			if not int(value) in d.home_at.map(func(v): return int(v)):
				return false
			gs.dungeon.home_at = int(value)
		"first":
			if not Dungeon.first_earned(gs.catalog, gs.dungeon) or not str(value) in d.first.lines:
				return false
			gs.dungeon.first = str(value)
		_:
			return false
	gs.dungeon_changed.emit()
	gs.save_game()
	return true


## The orders start from landing `f` (0: the top, or a fully held landing); the target moves down
## under it if it has to. Returns whether it could (not while the army is out, not a landing that
## isn't held).
func set_start(f: int) -> bool:
	if dungeon_running() or not f in Dungeon.starts(gs.catalog, gs.dungeon):
		return false
	gs.dungeon.start = f
	gs.dungeon.target = clampi(maxi(int(gs.dungeon.target), f + 1), 1, Dungeon.target_max(gs.catalog, gs.dungeon))
	gs.dungeon_changed.emit()
	gs.save_game()
	return true


## The army lined up now (or the one army() gave) for the rules, for floor_words.
func army_rules(a: Dictionary = {}) -> Dictionary:
	if a.is_empty():
		a = army()
	return _army_rules(a.cards, a.keys)


## The army for the rules (Dungeon.simulate): its cards with their power, its herd pets with their
## rarity's, the knock doors' chance from the front row's luck, the power boost.
func _army_rules(cards: Array, herd_keys: Dictionary) -> Dictionary:
	var list: Array = []
	for pet in cards:
		list.append({ "uid": pet.uid, "power": army_power_of(pet), "rank": gs.catalog.rank(pet.rarity) })
	list.sort_custom(func(a, b): return float(a.power) > float(b.power))
	var herd := {}
	for k in herd_keys:
		herd[k] = { "n": int(herd_keys[k]), "power": Dungeon.pet_power(gs.catalog, Herd.template(gs.catalog, k)), "rank": gs.catalog.rank(Herd.rarity_of(k)) }
	var front_n := gs.front_row_size()
	var front := cards.slice(0, front_n)
	var luck := 0.0
	for pet in front:
		luck += Party.stat_of(pet, "luck", gs.catalog)
	luck = luck / front.size() if not front.is_empty() else 0.0
	# the perks: the front row's size and power, pets walking behind, the cellar, the stairs (and rooms)
	return { "cards": list, "herd": herd, "luck": Dungeon.knock_chance(gs.catalog, luck, gs.boost("luck")), "boost": gs.boost("power"),
		"front_n": front_n, "front_x": gs.boost("front"), "behind_x": gs.boost("herd_power"),
		"band_x": { "doors": gs.boost("cellar"), "stairs": gs.boost("stairs"), "room": gs.boost("stairs") } }


## The feeling words for floors `from`..`to`: floor -> [word, heat] (strength is never a number).
## `rules` from army_rules() (worked out once per page), or the army lined up now.
func floor_words(from: int, to: int, rules: Dictionary = {}) -> Dictionary:
	var out := {}
	if rules.is_empty():
		rules = army_rules()
	var powers := {}
	var held := Dungeon.held_landings(gs.catalog, gs.dungeon)  # (a held landing's guard is gone)
	for f in range(maxi(1, from), to + 1):
		var kind := Dungeon.kind_at(gs.catalog, f, held)
		if not powers.has(kind):
			powers[kind] = Dungeon.army_power(gs.catalog, rules, kind)
		out[f] = Dungeon.word(gs.catalog, float(powers[kind]) / Dungeon.strength(gs.catalog, f, f in held))
	return out


## Sends the army down the well with its orders: the whole run is worked out now (Dungeon.simulate),
## its pets stay busy until it's home. Returns whether it went. `quiet` (the music box's runs while
## loading): no signals and no save, the caller does those once after.
## `away`: a music box run while the game is closed: it only goes as deep as floors it clears
## safely (data/dungeon.json away_safe), nobody is lost.
func send_army(quiet := false, away := false) -> bool:
	if not dungeon_open() or dungeon_running() or gs.tutorial_active():
		return false
	var cards := army_cards()
	var herd_keys := army_herd_keys()
	var room := Dungeon.entrance(gs.catalog, gs.perk_level("entrance"))
	if cards.size() > room:
		cards = cards.slice(0, room)
	var sent := cards.size() + Herd.total(herd_keys)
	if sent <= 0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = gs._rng.randi()
	var start := int(gs.dungeon.start) if int(gs.dungeon.start) in Dungeon.starts(gs.catalog, gs.dungeon) else 0
	var orders := { "target": int(gs.dungeon.target), "start": start, "held": Dungeon.held_landings(gs.catalog, gs.dungeon), "home_at": int(gs.dungeon.home_at), "entrance": gs.perk_level("entrance"),
		"pay_x": gs.boost("lanterns"), "first": str(gs.dungeon.first) if Dungeon.first_earned(gs.catalog, gs.dungeon) else "" }
	if away:
		orders.safe = float(Dungeon.data(gs.catalog).get("away_safe", 2.0))
	var result := Dungeon.simulate(gs.catalog, _army_rules(cards, herd_keys), orders, rng)
	gs.dungeon.run = { "at": Time.get_unix_time_from_system(), "floors": result.floors, "why": result.why, "turned": result.turned,
		"cards": cards.map(func(p): return p.uid), "herd": herd_keys.duplicate(), "sent": sent, "target": int(gs.dungeon.target), "start": start,
		"known": 0 if away else int(gs.dungeon.deep) }  # (floors cleared before go faster, see Dungeon.floor_seconds; the music box's away runs keep their old pace)
	if not quiet:
		gs.dungeon_report = {}
	gs._rest_changed()  # (only drops the busy-pets cache: the next army_cards() needs it fresh)
	if quiet:
		return true
	gs.dungeon_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Where the army is now: floors from the top (0 at the well mouth), or -1 when it's home.
func dungeon_floor_now() -> float:
	if not dungeon_running():
		return -1.0
	return Dungeon.run_floor(gs.catalog, gs.dungeon.run, Time.get_unix_time_from_system() - float(gs.dungeon.run.at))


## Seconds until the army is home (0 when it is).
func dungeon_left() -> float:
	if not dungeon_running():
		return 0.0
	return maxf(0.0, float(gs.dungeon.run.at) + Dungeon.run_seconds(gs.catalog, gs.dungeon.run) - Time.get_unix_time_from_system())


## Every second: an army that's done comes home; your pet leading the army takes it down again
## (unless the sewing room is open on screen: then it waits, so the army can go in there).
func _dungeon_tick() -> void:
	if dungeon_running() and dungeon_left() <= 0.0:
		_finish_dungeon_run()
	if gs.automation.task == "army" and gs.knows_job("army") and not dungeon_running() and not gs.army_held:
		send_army()


## The army is home: pets that didn't come back leave (a star each, never a word about them), the
## cleared floors pay their wisps, the landings stay lit, and a floor's first time gives its thing.
## `quiet` (the music box's runs while loading): no refold, unlock check or signals, the caller does
## those once after.
func _finish_dungeon_run(quiet := false) -> void:
	var run: Dictionary = gs.dungeon.run
	if run.has("room"):
		gs._finish_room_run(quiet)
		return
	var front: Array[Pet] = []
	if not quiet:
		front.assign(army_cards().slice(0, gs.front_row_size()))  # (before the lost ones leave)
	var tally := {} if quiet else Dungeon.run_tally(run, run.get("floors", []).size(), func(uid: String):
		var pet := gs.collection.get_pet(uid)
		return pet.rarity if pet else "")
	gs.dungeon.run = {}
	gs._rest_changed()
	var lost_n := _run_losses(run)
	var got := Dungeon.run_pay(run)
	var start := int(run.get("start", 0))  # from a held landing: they got at least that far
	var to := maxi(Dungeon.cleared_to(run), start)
	var deep_before := int(gs.dungeon.deep)
	var deepest := to > deep_before
	var nails := gs.perks_shown().size()
	gs.grant_wisps(got, true)
	gs.dungeon.deep = maxi(int(gs.dungeon.deep), to)
	for id in Dungeon.shown_bands(gs.catalog, gs.dungeon):
		if not id in gs.dungeon.bands:
			gs.dungeon.bands.append(id)
	gs.dungeon.last = { "floor": to, "got": got, "back": int(run.get("sent", 0)) - lost_n, "sent": int(run.get("sent", 0)) }
	var firsts: Array[int] = []  # what a floor gave the first time, on this run
	for f in range(start + 1, to + 1):  # (only floors walked: a skipped floor's thing waits)
		var first: Dictionary = gs.catalog.dungeon.get("firsts", {}).get(str(f), {})
		if not first.is_empty() and not gs.dungeon.firsts.has(str(f)):
			if first.has("part") and not gs.feature_on("parts"):
				continue  # parts come much later: this floor's part waits for a clear after that
			gs.dungeon.firsts[str(f)] = true
			firsts.append(f)
			_dungeon_first(first)
	if not quiet:
		gs.dungeon_report = { "run": run, "tally": tally, "front": front, "lead": gs.collection.active(), "deepest": to,
			"new_deep": deepest, "got": got, "best": _best_bit(run, firsts, deep_before, deepest, to) }
	gs.dungeon.cards = gs.dungeon.cards.filter(func(uid): return gs.collection.get_pet(str(uid)) != null)
	gs.dungeon.target = mini(int(gs.dungeon.target), Dungeon.target_max(gs.catalog, gs.dungeon))
	if not int(gs.dungeon.start) in Dungeon.starts(gs.catalog, gs.dungeon):
		gs.dungeon.start = 0
	gs.dungeon_news = { "got": got, "floor": to, "early": str(run.get("why", "")) != "target", "deepest": deepest,
		"nail": gs.perks_shown().size() > nails }  # a new nail showed on the wall down there
	if not quiet:
		_home_again()


## The best bit of a run for its "came home" report: a first find (what a floor gave the first time),
## else the deepest floor yet, else the floor that brought the most wisps. { kind (find | part | deep |
## wisps), f (its floor), what (the find's name or the part's rarity), was (the deepest before), pay }.
func _best_bit(run: Dictionary, firsts: Array[int], deep_before: int, deepest: bool, to: int) -> Dictionary:
	for f in firsts:
		var first: Dictionary = gs.catalog.dungeon.get("firsts", {}).get(str(f), {})
		if first.has("find"):
			return { "kind": "find", "f": f, "what": str(gs.catalog.finds.get(str(first.find), {}).get("name", "something shiny")) }
		if first.has("part"):
			return { "kind": "part", "f": f, "what": str(gs.catalog.tier_at(gs.catalog.rank(str(first.part))).name) }
	if deepest:
		return { "kind": "deep", "f": to, "was": deep_before }
	var top := {}
	for fl in run.get("floors", []):
		if int(fl.get("pay", 0)) > int(top.get("pay", 0)):
			top = fl
	if top.is_empty():
		return {}
	return { "kind": "wisps", "f": int(top.f), "pay": int(top.pay) }


## The "came home" report is put away (you change the army): the page lines up the next one.
func drop_dungeon_report() -> void:
	if gs.dungeon_report.is_empty():
		return
	gs.dungeon_report = {}
	gs.dungeon_changed.emit()


## After an army is home: cards home again may fold into the herd, unlocks, the pages refresh.
func _home_again() -> void:
	gs.collection.refold()
	gs.check_unlocks()
	gs.dungeon_changed.emit()
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Pets a run lost leave the collection (a star each, never a word about them). Returns how many.
func _run_losses(run: Dictionary) -> int:
	var lost := Dungeon.run_lost(run)
	var lost_cards: Array[String] = []
	var keeper := gs._plushie_keeper_uid()
	for uid in lost[0]:
		# your pet and the plushie machine's keeper always come home
		if str(uid) != gs.collection.active_uid and str(uid) != keeper and gs.collection.get_pet(str(uid)) != null:
			lost_cards.append(str(uid))
	var lost_n := lost_cards.size()
	gs.collection.remove(lost_cards)
	for k in lost[1]:
		lost_n += gs.collection.lose_plain(str(k), int(lost[1][k]))
	gs._clamp_herd_places()
	return lost_n


## The landings a crowd can hold now (every 10th, down to the deepest floor cleared).
func hold_spots() -> Array[int]:
	return Dungeon.hold_spots(gs.catalog, gs.dungeon) if dungeon_open() else ([] as Array[int])


## How many pets of a rarity could go and hold landing `f`: the ones that may go (spare_pick: never
## favourites, your pet, the army, the keep line...), at most what the landing still needs.
func hold_can_go(f: int, rarity: String) -> int:
	var room := hold_room(f)
	if room <= 0:
		return 0
	return mini(room, gs.homes_can_go(rarity))


## How many more pets landing `f` needs to be fully held (0 when it is, or isn't a spot now).
func hold_room(f: int) -> int:
	if not f in hold_spots():
		return 0
	return maxi(0, Dungeon.hold_need(gs.catalog, f) - Dungeon.held_n(gs.dungeon, f))


## Faces for the crowd on landing `f` (stand-in looks of the pets holding it, they're gone from the
## collection): up to `n` Pets, each count in step with its size.
func hold_faces(f: int, n: int) -> Array:
	var counts: Dictionary = gs.dungeon.held.get(str(f), {})
	var out: Array = []
	var total := Herd.total(counts)
	if total <= 0 or n <= 0:
		return out
	var keys := counts.keys()
	keys.sort()
	for k in keys:
		var take := maxi(1, roundi(n * float(counts[k]) / total))
		for i in take:
			if out.size() >= n:
				break
			var face := Herd.stand_in(gs.catalog, Herd.uid(str(k), 700000 + f * 97 + i))
			if face:
				out.append(face)
	return out


## Sends `n` pets of a rarity to hold landing `f` (off their errands and machines if they have to,
## like the new homes stall). They stay on for good: they leave the collection with no star. Returns
## how many went.
func send_holders(f: int, rarity: String, n: int) -> int:
	var room := hold_room(f)
	if n <= 0 or room <= 0:  # (spare_pick reads a negative n as "all of them")
		return 0
	var got := gs._take_spare(rarity, mini(n, room), 0, false)
	var gone := int(got.n)
	if gone <= 0:
		return 0
	var held: Dictionary = gs.dungeon.held.get(str(f), {})
	for k in got.counts:  # (the plan never has your pet or a busy card, so everyone in it went)
		Herd.put(held, str(k), int(got.counts[k]))
	gs.dungeon.held[str(f)] = held
	gs._rest_changed()
	gs._clamp_herd_places()
	gs.dungeon_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return gone


## The game was closed `away` seconds (it was saved at `saved_at`): with the music box, your pet
## leading the army kept taking it down back to back for up to its hours. Real runs, worked out one
## after another from where the last one was, but safe ones: only as deep as floors it clears with
## no losses (send_army away; losses only happen while you're here). Firsts as usual, wisps only:
## nothing else counts closed time here. The run that was out finishes too; the last one sent may still be
## down there. What they brought goes in the idle log and the dungeon news. Returns the wisps.
## At most data/perks.json away_runs_max runs; each one runs quiet (the refold, unlocks and signals
## happen once after the loop).
func _army_while_away(saved_at: float, now: float) -> int:
	var hours := gs.perk_away_hours()
	if saved_at <= 0.0 or hours <= 0.0 or not dungeon_open() or gs.automation.task != "army" or not gs.knows_job("army") or gs.tutorial_active():
		return 0
	var until := minf(now, saved_at + hours * 3600.0)
	var t := saved_at
	var got := 0
	var runs_n := 0
	var deepest := false
	var nail := false
	var to := 0
	var wisps0 := gs.wisps
	var came_home := false
	var sent_any := false
	for i in int(gs.catalog.perks.get("away_runs_max", 500)):
		if dungeon_running():
			var ends := float(gs.dungeon.run.at) + Dungeon.run_seconds(gs.catalog, gs.dungeon.run)
			if ends > now:
				break  # still down there: it comes home on its own
			came_home = true
			if gs.dungeon.run.has("room"):
				_finish_dungeon_run(true)
				t = maxf(t, ends)
				continue
			_finish_dungeon_run(true)
			runs_n += 1
			deepest = deepest or bool(gs.dungeon_news.get("deepest", false))
			nail = nail or bool(gs.dungeon_news.get("nail", false))
			to = maxi(to, int(gs.dungeon_news.get("floor", 0)))
			t = maxf(t, ends)
		if t >= until or not send_army(true, true):
			break
		sent_any = true
		gs.dungeon.run.at = t  # it set off back then
		if gs.dungeon.run.floors.is_empty() and str(gs.dungeon.run.why) == "safe":
			gs.dungeon.run = {}  # not even the first floor is safe: it stays home till you're back
			gs._rest_changed()
			break
	if came_home or sent_any:
		_home_again()  # once for all of them
		gs.changed.emit()
	got = gs.wisps - wisps0
	if runs_n > 0:
		gs._log_idle({ "wisps": got })
		gs.dungeon_news = { "got": got, "floor": to, "early": false, "deepest": deepest, "nail": nail }
	return got


## What a floor gives the first time it's cleared: a part of its tier, or a find (with your pet's
## one quiet line).
func _dungeon_first(first: Dictionary) -> void:
	var loot := {}
	if first.has("part"):
		var tier := str(first.part)
		var slots: Array = Catalog.SLOTS.filter(func(s): return not gs.catalog.parts_of_tier(s, tier).is_empty())
		if not slots.is_empty():
			var slot: String = slots[gs._rng.randi_range(0, slots.size() - 1)]
			var options := gs.catalog.parts_of_tier(slot, tier)
			loot["part:%s:%s" % [slot, options[gs._rng.randi_range(0, options.size() - 1)].id]] = 1
	if first.has("find"):
		loot["find:" + str(first.find)] = 1
	if str(first.get("say", "")) != "":
		gs.announcements.append(str(first.say))
	if not loot.is_empty():
		gs.grant(loot, false)
