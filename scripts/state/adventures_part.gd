class_name AdventuresPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Debug: a handful of random parts, one of each rarity, to try sewing with.
func debug_give_parts() -> void:
	for tier in gs.catalog.tiers:
		var slots: Array = Catalog.SLOTS.filter(func(s): return not gs.catalog.parts_of_tier(s, tier.id).is_empty())
		var slot: String = slots[gs._rng.randi_range(0, slots.size() - 1)]
		var options := gs.catalog.parts_of_tier(slot, tier.id)
		var key := "%s:%s" % [slot, options[gs._rng.randi_range(0, options.size() - 1)].id]
		gs.parts[key] = int(gs.parts.get(key, 0)) + 1
	gs.changed.emit()
	gs.save_game()


## uid -> true for every pet that's out on a trip (including trips back but not welcomed yet, and
## pets that stayed there: they leave when the trip is welcomed back).
func away() -> Dictionary:
	var out := {}
	for run in gs.runs:
		for uid in run.party.uids:
			out[uid] = true
		for uid in run.party.lost:
			out[uid] = true
	return out


## Pets that can be sent: not your active pet or the plushie machine's keeper, and not already
## away or in the dungeon's army. Pets on errands can: going on an adventure takes them off their
## errand. From each count in the herd, up to data/herd.json "stand_ins" stand-ins (they come home
## into the count, or leave it).
func sendable_pets() -> Array[Pet]:
	var gone := gs._out()
	var keeper := gs._plushie_keeper_uid()  # the plushie machine's keeper stays home
	var out: Array[Pet] = []
	for pet in gs.collection.pets:
		if pet.uid != gs.collection.active_uid and pet.uid != keeper and not gone.has(pet.uid):
			out.append(pet)
	out.append_array(_sendable_stand_ins(gone))
	return out


## Up to data/herd.json "stand_ins" stand-ins from each count, leaving out ones away or leading.
func _sendable_stand_ins(gone: Dictionary) -> Array[Pet]:
	var out: Array[Pet] = []
	var skip := gs._stand_ins_out(gone)
	var out_of := {}  # count key -> stand-ins already away or leading
	for uid: String in skip:
		Herd.put(out_of, Herd.key_of(uid), 1)
	var per := int(gs.catalog.herd.get("stand_ins", 10))
	var army := gs.army_herd_keys()  # the dungeon's army keeps its pets
	for k in gs.collection.herd:
		var free := gs.collection.herd_count(k) - int(out_of.get(k, 0)) - int(army.get(k, 0))
		if free > 0:
			for uid in gs.collection.stand_in_uids(k, mini(per, free), skip):
				out.append(gs.collection.get_pet(uid))
	return out


## `by_you`: you sent it (not your pet's or the workers' auto parties): it may take a scout note.
func send_on_adventure(location_id: String, pets: Array[Pet], by_you := true) -> RunState:
	var location := gs.catalog.location(location_id)
	var gone := away()
	var going: Array[Pet] = []
	var picked := {}
	var herd_left := {}  # count key -> stand-ins of it that may still go
	var leading := {}
	if pets.any(func(p): return p != null and Herd.is_stand_in(p.uid)):
		leading = gs._stand_ins_out(gone)
		for uid: String in leading:
			Herd.put(herd_left, Herd.key_of(uid), -1)
	for pet in pets:  # the sendable ones (see sendable_pets), checked one by one: parties go out hundreds at a time
		if pet == null or picked.has(pet.uid) or pet.uid == gs.collection.active_uid or gone.has(pet.uid):
			continue
		if Herd.is_stand_in(pet.uid):
			var k := Herd.key_of(pet.uid)
			if leading.has(pet.uid) or gs.collection.herd_count(k) + int(herd_left.get(k, 0)) <= 0:
				continue
			Herd.put(herd_left, k, -1)
		elif gs.collection.get_pet(pet.uid) != pet:
			continue
		picked[pet.uid] = true
		going.append(pet)
	if not gs.location_open(location) or going.is_empty() or going.size() > gs.max_party(location_id):
		return null
	# stand-ins: resting ones first; past those they come off errands (then machines and tables)
	var need := {}
	for pet in going:
		if Herd.is_stand_in(pet.uid):
			Herd.put(need, Herd.key_of(pet.uid), 1)
	if not need.is_empty():  # (resting_herd goes over every pet: only when stand-ins go)
		var free := gs.resting_herd()
		for k in need:
			if int(need[k]) > int(free.get(k, 0)):
				gs._herd_off_places(k, int(need[k]) - int(free.get(k, 0)))
	# every trip packs the gear you have when it sets off (yours, your pet's and the workers' parties;
	# never dungeons, see Gear.for_trip)
	var run := AdventureRunner.start(location_id, going, Time.get_unix_time_from_system(), gs._rng.randi(), gs.catalog, gs.finds, gs.machine.bought,
		Gear.for_trip(gs.catalog, gs.gear, location), gs.trip_knacks(going), gs.workers_total(), gs.is_ours(location_id), gs.sent_to(location_id),
		gs._count_find_tries(location, going.size()))
	gs.sent[location_id] = gs.sent_to(location_id) + going.size()
	run.parts = gs.feature_on("parts")
	# auto parties (your pet's, the workers') never take a note: skip the looking around for them
	if by_you and gs.scout_notes > 0 and Jobs.takes_note(gs.catalog, location, by_you, gs.scout_notes,
			Intel.left_to_find(location, gs._place_known, not Rumours.hearable(gs.catalog, gs.heard, gs.is_open).is_empty(), gs.catalog)):
		gs.scout_notes -= 1
		run.scout = Jobs.scout_note(gs.catalog)
		gs.jobs_changed.emit()
	gs.runs.append(run)
	gs._rest_changed()
	gs._take_off(going.map(func(p): return p.uid))
	gs._take_off_workers(going.map(func(p): return p.uid))
	gs.visited[location_id] = true
	gs._check_tutorial()
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return run


## The player picks an option at the event a run is waiting at.
func answer_event(run: RunState, option_index: int) -> void:
	if not run in gs.runs or run.status != RunState.Status.WAITING:
		return
	if not option_index in AdventureRunner.allowed_options(run.current_event(gs.catalog), run.party, gs.catalog.location(run.location_id)):
		return
	run.answer = option_index
	gs.workshop.vane[Workshop.vane_key(run.location_id, str(run.current_event(gs.catalog).get("id", "")))] = option_index  # the weather vane remembers
	_advance(run)
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Collects a run that's back: what it found is handed out, the pets that didn't come back leave
## the collection. Returns what goes on the trip's postcard (see Postcard), or {} if it isn't back yet:
## { place, doodle, photo: [{ pet, home }] in the order they set out, notes: [{ text, stayed }], loot,
## xp gained, spotted: [{ name, doodle }], finds: [names] }.
func collect_run(run: RunState) -> Dictionary:
	if not run in gs.runs or run.status != RunState.Status.DONE:
		return {}
	gs.runs.erase(run)
	gs._rest_changed()
	gs.trips_done += 1
	var location := gs.catalog.location(run.location_id)
	# a visit (somebody made it home): one of next door's lights goes out (your pet whispers about it
	# on trips you sent)
	if run.party.size() > 0 and gs.add_visits(run.location_id) == "dark" and not run.auto:
		gs.announcements.append(Ours.say(gs.catalog, "say_dark", location))
	var photo: Array[Dictionary] = []
	for uid: String in run.party.stats:  # everyone who set out, in order
		var pet := gs.collection.get_pet(uid)
		if pet:
			photo.append({ "pet": pet, "home": not uid in run.party.lost })
	var new_finds: Array[String] = []
	for key: String in run.loot:
		if key.begins_with("find:") and not gs.finds.has(key.substr(5)):
			var find_name := str(gs.catalog.finds.get(key.substr(5), {}).get("name", "something"))
			new_finds.append(find_name)
			gs.announcements.append("%s found %s!" % [run.party.who(), find_name])
	var coins_why := gs._boost_trip_loot(run.loot, run.gear, run.knacks)
	gs.grant(run.loot, false)
	gs.collection.remove(run.party.lost)
	gs._clamp_herd_places()
	# the pets that came home go where new pets join (nothing on: they rest)
	gs._place_new(photo.filter(func(p): return p.home).map(func(p): return p.pet.uid))
	gs.collection.refold()  # pets home again may fold into the herd
	var found := gs._spot_places(run)
	# experience: from the trip itself, and a lot for discovering things
	var gained := gs.add_xp(run.xp + GameStateNode.XP_SPOTTED * found.size() + GameStateNode.XP_FIND * new_finds.size())
	var spotted_names: Array[String] = []
	var spotted_places: Array[Dictionary] = []
	for id in found:
		var place := gs.catalog.location(id)
		spotted_names.append(str(place.name))
		spotted_places.append({ "name": place.name, "doodle": str(place.get("map", {}).get("doodle", "")) })
	gs.news = { "place": location.name, "home": run.party.size(),
		"sent": run.party.setting_out(), "parts": Rewards.total(run.loot, "part"),
		"spotted": spotted_names, "who": run.party.who() }
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()
	var notes: Array[Dictionary] = []
	for entry in run.history:
		if str(entry.get("text", "")) != "":
			notes.append({ "text": str(entry.text), "stayed": int(entry.get("lost", 0)) > 0 })
	return { "place": location.name, "doodle": str(location.get("map", {}).get("doodle", "")), "photo": photo,
		"notes": notes, "loot": run.loot.duplicate(), "xp": gained, "spotted": spotted_places, "finds": new_finds,
		"coins_why": coins_why }


## You tossed a treat on the trail: the pets chase it and walk TREAT_SPEED times as fast for
## treat_zoom() seconds. Then the next treat takes treat_every() seconds. Returns whether it worked.
func toss_treat(run: RunState) -> bool:
	if not run in gs.runs or run.status == RunState.Status.DONE or treat_ready_in(run) > 0.0:
		return false
	var now := Time.get_unix_time_from_system()
	gs._treats[run] = { "zoom_until": now + treat_zoom(run), "ready_at": now + treat_every(run) }
	return true


## Seconds before you can toss this trip the next treat (a treat pouch makes it quicker).
func treat_every(run: RunState) -> float:
	return Gear.value(gs.catalog, run.gear, "treat_every")


## Seconds this trip's pets zoom along after a treat (a treat pouch makes it longer).
func treat_zoom(run: RunState) -> float:
	return Gear.value(gs.catalog, run.gear, "treat_zoom") * run.knack("treats")


## The most a streak of grabs on the trail multiplies what you grab (sticky paws raise it).
func streak_max(run: RunState) -> float:
	return Gear.value(gs.catalog, run.gear, "streak_max")


## How much more likely a part is on the trail (sharper eyes), once parts are open.
func trail_part_x(run: RunState) -> float:
	return Gear.value(gs.catalog, run.gear, "part_x")


## Seconds until you can toss this trip another treat (0: now).
func treat_ready_in(run: RunState) -> float:
	return maxf(0.0, float(gs._treats.get(run, {}).get("ready_at", 0.0)) - Time.get_unix_time_from_system())


## Whether this trip's pets are zooming after a treat.
func zooming(run: RunState) -> bool:
	return float(gs._treats.get(run, {}).get("zoom_until", 0.0)) > Time.get_unix_time_from_system()


## Zooming pets eat up the walk faster (while they're walking, not while they wait at an event).
func _zoom_runs(delta: float) -> void:
	if gs._treats.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var moved := false
	for run: RunState in gs._treats.keys():
		if not run in gs.runs:
			gs._treats.erase(run)
			continue
		if zooming(run) and run.status == RunState.Status.WALKING:
			run.next_at = maxf(now, run.next_at - delta * (GameStateNode.TREAT_SPEED - 1.0))
			if run.next_at <= now:
				moved = _advance(run) or moved
	if moved:
		gs.adventures_changed.emit()
		gs.changed.emit()


## You grabbed something on the trail. Coins go in the trip's bag (lost with the pet), a part waits
## for you to keep it (keep_trail_part), xp is yours straight away, a leaf heals a sore paw. `bonus` grows with a streak of grabs.
## Returns what it was worth, e.g. { "coins": 3 }, for the little "+3" that pops up.
func trail_pickup(run: RunState, kind: String, bonus := 1.0) -> Dictionary:
	if not run in gs.runs or run.status == RunState.Status.DONE:
		return {}
	var location := AdventureRunner.place(run, gs.catalog)
	var paws := (1.0 + Gear.value(gs.catalog, run.gear, "pickups")) * run.knack("pickups")  # sticky paws (and knacks): worth more
	match kind:
		"coins":
			var amount := maxi(1, roundi(gs._rng.randf_range(GameStateNode.TRAIL_COINS[0], GameStateNode.TRAIL_COINS[1]) * float(location.loot) * bonus * paws))
			Rewards.add(run.loot, { "coins": amount })
			return { "coins": amount }
		"xp":
			var amount := gs.add_xp(maxi(1, roundi(bonus)) if paws <= 1.0 else maxi(1, Rewards.count(bonus * paws, gs._rng)))
			gs.changed.emit()
			return { "xp": amount }
		"heal":
			return { "heal": run.party.heal(1, gs._rng) }
		"part":
			# not in the bag yet: you pick "add to bag" or "leave it" first (keep_trail_part)
			var part := Rewards.roll_part(str(location.box), gs._rng, gs.catalog, location.get("part_slots", []))
			return { "part": "part:%s:%s" % part }
	return {}


## You kept a part the pet picked up on the trail: into the trip's bag, or straight into yours
## if the trip was already welcomed back while you were deciding.
func keep_trail_part(run: RunState, key: String) -> void:
	if run in gs.runs:
		Rewards.add(run.loot, { key: 1 })
		gs.changed.emit()
	else:
		gs.grant({ key: 1 })


func _advance_runs() -> void:
	var moved := false
	for run in gs.runs:
		moved = _advance(run) or moved
		moved = gs._vane(run) or moved
	if moved:
		gs.changed.emit()
		gs.adventures_changed.emit()


## Plays whatever has come due on a run. Returns true if anything happened.
func _advance(run: RunState) -> bool:
	var before := run.status
	var added := AdventureRunner.resolve(run, Chooser.for_run(run), Time.get_unix_time_from_system(), gs.catalog, gs.finds)
	if run.status == RunState.Status.DONE and before != RunState.Status.DONE:
		gs.run_ended.emit(run)
	return not added.is_empty() or run.status != before


## Debug: everything that's walking arrives now (runs still wait for your answers).
func debug_finish_runs() -> void:
	var now := Time.get_unix_time_from_system()
	for run in gs.runs:
		for i in 50:
			if run.status != RunState.Status.WALKING:
				break
			run.next_at = minf(run.next_at, now)
			_advance(run)
	gs.adventures_changed.emit()
	gs.changed.emit()
