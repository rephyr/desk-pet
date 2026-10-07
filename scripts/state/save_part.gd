class_name SavePart
extends RefCounted
## GameState's code for saving, loading, old saves moved to the current version, and a new game.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Debug: a completely fresh game, as a new player would start it. The old save is copied to
## user://save-before-new-game-<time>.json first, so it can be put back by hand.
func debug_new_game() -> void:
	save_game(true)
	var backup := DevProfile.path("save-before-new-game-%d.json" % int(Time.get_unix_time_from_system()))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(gs.save_path), ProjectSettings.globalize_path(backup))
	gs.coins = 100
	gs.xp = 0
	gs.hunger = 70.0
	gs.happiness = 70.0
	gs.bag.clear()
	gs.parts.clear()
	gs.items.clear()
	gs.unlocks.clear()
	gs.trips_done = 0
	gs.heard.clear()
	gs.rumours.clear()
	gs.spotted.clear()
	gs.spot_tries.clear()
	gs.finds.clear()
	gs.packs_by_hand = 0
	gs.parts_ever = false
	gs.announcements.clear()
	gs.jobs.clear()
	gs.jobs_away = {}
	gs.homes = NewHomes.fresh(gs.catalog)
	gs.workshop = Workshop.fresh(gs.catalog)
	gs.postcards.clear()
	gs.watching = null
	gs._to_work.clear()
	gs.errand_tools = {}
	gs.scout_notes = 0
	gs.gear = {}
	gs.stickers.clear()
	gs._boosts_changed()
	gs.room = 0
	gs.edge = Edge.fresh()
	gs.school = School.fresh()
	gs.school_changed_boost()
	gs.wish = Wish.fresh()
	gs._roller.wish = {}
	gs._crews_changed()
	gs.pinned.clear()
	gs.join_up_to = ""
	gs.rummaged.clear()
	gs.machine = { "pulls": 0, "lit": 0, "bought": {}, "globes": [Machine.first_globe(gs.catalog)], "greeted": [Machine.first_globe(gs.catalog)] }
	gs.fever_until = 0.0
	gs.toys = Toys.fresh()
	gs._knacks_changed()
	gs.gifts = Gifts.fresh()
	gs.bits = {}
	gs.wisps = 0
	gs.plushie = Plushie.fresh()
	gs.automation = Automation.fresh()
	gs.dungeon = Dungeon.fresh(gs.catalog)
	gs.dungeon_news = {}
	gs.dungeon_report = {}
	gs.sewing = Sewing.fresh()
	gs.sew_seats = {}
	gs.sew_seats_room = -1
	gs.sew_last = {}
	gs.perks = {}
	gs.collection.keep_uids.clear()
	gs.whistle_seen()
	gs._auto_at = 0.0
	gs._boxes_at = 0.0
	gs._crew_speeds.clear()
	gs._crew_tips.clear()
	gs._worker_of.clear()
	gs._worker_speed.clear()
	gs.visited.clear()
	gs.visits.clear()
	gs.sent.clear()
	gs.find_tries.clear()
	gs.unshown_ours.clear()
	gs.saved_boxes.clear()
	gs.reserve_capsules = gs.default_reserve()
	gs.boxes_bought.clear()
	gs.boxes_greeted.clear()
	gs.buying_on = true
	gs.idle_log = {}
	gs.runs.clear()
	gs.news = {}
	gs.collection.load_from({})
	gs._start_tutorial()
	gs._check_care()
	gs._knacks_changed()  # after load_from: uids start over at 1
	gs.collection.active_changed.emit(gs.collection.active())
	save_game()
	gs.new_game.emit()
	gs.adventures_changed.emit()
	gs.changed.emit()


## `wait`: written before this returns (quitting); otherwise the running game writes it a moment
## later on a worker thread (late in the game copying it takes ~150 ms and the JSON ~300 ms: a few
## taps in a row write it once, and never wait for the last write).
func save_game(wait := false) -> void:
	if not gs._can_save:
		return
	if gs._hold_saves:  # automation is working through a tick (or loading): the next autosave has it
		return
	if not wait and gs.is_inside_tree():
		if gs._save_soon < 0.0:
			gs._save_soon = GameStateNode.SAVE_SOON
		return
	_write_save(wait)


## Whether the last save is still being written on its worker thread.
func _still_writing() -> bool:
	return gs._save_task >= 0 and not WorkerThreadPool.is_task_completed(gs._save_task)


func _write_save(wait := false) -> void:
	if not gs._can_save or gs._hold_saves:
		return
	gs._save_soon = -1.0
	var data := {
		"version": GameStateNode.SAVE_VERSION,
		"coins": gs.coins,
		"xp": gs.xp,
		"hunger": gs.hunger,
		"happiness": gs.happiness,
		"pet_out": gs.pet_out,
		"collection": gs.collection.to_dict(true),
		"bag": gs.bag,
		"parts": gs.parts,
		"items": gs.items,
		"unlocks": gs.unlocks.keys(),
		"trips_done": gs.trips_done,
		"heard": gs.heard.keys(),
		"rumours": gs.rumours,
		"tutorial": gs.tutorial,
		"spotted": gs.spotted,
		"spot_tries": gs.spot_tries,
		"finds": gs.finds.keys(),
		"packs_by_hand": gs.packs_by_hand,
		"parts_ever": gs.parts_ever,
		"announcements": gs.announcements,
		"jobs": gs.jobs,
		"new_homes": gs.homes,
		"workshop": gs.workshop,
		"errand_tools": gs.errand_tools,
		"scout_notes": gs.scout_notes,
		"gear": gs.gear,
		"stickers": gs.stickers,
		"room": gs.room,
		"edge": gs.edge,
		"school": gs.school,
		"wish": gs.wish,
		"automation": gs.automation,
		"dungeon": gs.dungeon,
		"wisps": gs.wisps,
		"reserve_capsules": gs.reserve_capsules,
		"sewing": gs.sewing,
		"perks": gs.perks,
		"saved_boxes": gs.saved_boxes.keys(),
		"boxes_bought": gs.boxes_bought,
		"boxes_greeted": gs.boxes_greeted.keys(),
		"visited": gs.visited.keys(),
		"visits": gs.visits,
		"sent": gs.sent,
		"find_tries": gs.find_tries,
		"buying_on": gs.buying_on,
		"pinned": gs.pinned,
		"join_up_to": gs.join_up_to,
		"rummaged": gs.rummaged,
		"machine": gs.machine,
		"toys": gs.toys,
		"gifts": gs.gifts,
		"bits": gs.bits,
		"plushie": gs.plushie,
		"started_at": gs.started_at,
		"milestones": gs.milestones,
		"idle_log": gs.idle_log,
		"runs": gs.runs.map(func(r): return r.to_dict()),
		"saved_at": Time.get_unix_time_from_system(),
	}
	_finish_save()  # one write at a time, in order
	if wait or not gs.is_inside_tree():  # GameStates made by tests and tools write straight away
		SaveFile.write(gs.save_path, data)
		return
	# the worker thread must not read anything the game keeps changing: everything but the
	# collection (already copies, see Collection.to_dict) is copied here
	var pets: Dictionary = data.collection
	data.erase("collection")
	data = data.duplicate(true)
	data.collection = pets
	var path := gs.save_path
	gs._save_task = WorkerThreadPool.add_task(func(): SaveFile.write(path, data), false, "save")


## Waits for a save still being written on its worker thread.
func _finish_save() -> void:
	if gs._save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(gs._save_task)
		gs._save_task = -1


## Loads the save. Returns false if there's none yet (a brand new player).
func load_game() -> bool:
	_finish_save()
	gs._loading = true
	var loaded := _load_save()
	gs._loading = false
	gs._forget_care_boosts()  # totals kept while loading left the care buffs out (time closed)
	return loaded


func _load_save() -> bool:
	var data := SaveFile.read(gs.save_path)
	if data.is_empty():
		return false
	if int(data.get("version", 1)) > GameStateNode.SAVE_VERSION:
		# don't downgrade a save from a newer game: play with it, but never write over it
		push_warning("save is from a newer version of the game; it won't be overwritten")
		gs._can_save = false
	var from_version := int(data.get("version", 1))
	data = _migrate(data)
	BoxShop.fix_retired(data)  # not tied to a version: lucky boxes on the pile or on a trip turn into sunset boxes
	gs.coins = int(data.get("coins", gs.coins))
	gs.xp = int(data.get("xp", 0))
	gs.hunger = data.get("hunger", gs.hunger)
	gs.happiness = data.get("happiness", gs.happiness)
	gs.pet_out = data.get("pet_out", false)
	gs.tutorial = str(data.get("tutorial", "done"))  # saves from before the tutorial skip it
	# before the collection: its pets_added would open a page's sticker again otherwise
	gs.stickers = Book.clean(gs.catalog, data.get("stickers", []))  # v24: older saves open theirs after loading (check_book)
	gs._boosts_changed()
	gs.wish = Wish.clean(gs.catalog, data.get("wish", {}))  # v38: older saves start with an empty jar
	gs._roller.wish = Wish.weights(gs.catalog, gs.wish)
	gs.collection.auto_active = true  # your first pet is always your active pet (you can change it later)
	gs.collection.load_from(data.get("collection", {}))
	gs.bag.clear()
	var saved_bag: Dictionary = data.get("bag", {})
	for box_id in saved_bag:
		if not gs.catalog.box(box_id).is_empty() and int(saved_bag[box_id]) > 0:
			gs.bag[box_id] = int(saved_bag[box_id])
	gs.parts.clear()
	var saved_parts: Dictionary = data.get("parts", {})
	for key in saved_parts:
		if Grafting.valid_key(str(key), gs.catalog) and int(saved_parts[key]) > 0:  # "slot:id", or "slot:id@n" with buttons (v24)
			gs.parts[str(key)] = int(saved_parts[key])
	gs.items.clear()
	var saved_items: Dictionary = data.get("items", {})
	for key in saved_items:
		gs.items[key] = int(saved_items[key])
	gs.unlocks.clear()
	for id in data.get("unlocks", []):
		gs.unlocks[str(id)] = true
	gs.trips_done = int(data.get("trips_done", 0))
	gs.heard.clear()
	for id in data.get("heard", []):
		gs.heard[str(id)] = true
	gs.spotted.clear()
	var saved_spots: Dictionary = data.get("spotted", {})
	for id in saved_spots:
		if not gs.catalog.location(id).is_empty():
			gs.spotted[id] = { "by": str(saved_spots[id].get("by", "")), "from": str(saved_spots[id].get("from", "")) }
	gs.finds.clear()
	for id in data.get("finds", []):
		if gs.catalog.finds.has(str(id)):
			gs.finds[str(id)] = true
	gs.packs_by_hand = int(data.get("packs_by_hand", 0))
	gs.parts_ever = bool(data.get("parts_ever", false))
	gs.announcements.assign(data.get("announcements", []).map(func(a): return str(a)))
	gs.spot_tries.clear()
	var saved_tries: Dictionary = data.get("spot_tries", {})
	for id in saved_tries:
		gs.spot_tries[id] = int(saved_tries[id])
	gs.rumours.clear()
	for id in data.get("rumours", []):
		if not gs.catalog.rumour(str(id)).is_empty():
			gs.rumours.append(str(id))
	gs.runs.clear()
	for raw in data.get("runs", []):
		var run := RunState.from_dict(raw, gs.catalog)
		if run != null:
			if not raw.has("parts_on"):  # saved before runs kept it: parts are open or not right now
				run.parts = gs.feature_on("parts")
			gs.runs.append(run)

	# the dungeon before the jobs: its army's pets aren't on errands
	gs.wisps = maxi(0, int(data.get("wisps", 0)))  # v33 added the dungeon (and its wisps), v34 the plushie machine (same purse)
	gs.dungeon = Dungeon.clean(gs.catalog, data.get("dungeon", {}))
	gs.sewing = Sewing.clean(data.get("sewing", {}))  # v35 added the sewing room
	gs.perks = Perks.clean(gs.catalog, data.get("perks", {}))  # v36 added the wisps perks (the entrance moved in)
	if from_version < 35 and int(gs.dungeon.deep) >= int(gs.catalog.sewing.get("door_floor", 20)):
		gs.finds["little_key"] = true  # been past floor 20 already: the key was found there
	var trips := gs.away()
	gs.dungeon.cards = gs.dungeon.cards.filter(func(uid): return gs.collection.get_pet(uid) != null and uid != gs.collection.active_uid \
		and not Herd.is_stand_in(uid) and not trips.has(uid))
	gs._rest_changed()
	gs.jobs.clear()
	var on_trips := gs._out()
	var placed := {}
	var saved_jobs: Dictionary = data.get("jobs", {})
	for job_id in saved_jobs:
		if not gs.open_jobs().any(func(j): return j.id == job_id) or not saved_jobs[job_id] is Dictionary:
			continue  # a job that's gone, or not open (yet): its pets rest
		var crew: Array = []
		for raw_uid in saved_jobs[job_id].get("crew", []):
			var uid := str(raw_uid)
			if gs.collection.get_pet(uid) != null and uid != gs.collection.active_uid and not on_trips.has(uid) and not placed.has(uid):
				crew.append(uid)
				placed[uid] = true
		gs.jobs[job_id] = { "crew": crew, "herd": Herd.clean_counts(gs.catalog, saved_jobs[job_id].get("herd", {})),
			"fill": clampf(float(saved_jobs[job_id].get("fill", 0.0)), 0.0, 1.0), "join": bool(saved_jobs[job_id].get("join", false)) }
	if from_version < 28 and bool(data.get("jobs_auto", false)):
		# v28: "your pet shares out new pets" became "new pets join here" on each job: every open
		# errand it shared out to (not the kitchen or scouting: you staff those)
		for job in gs.open_jobs():
			if Jobs.shared_out(job):
				gs._job_state(job.id).join = true
	gs.homes = NewHomes.clean(gs.catalog, data.get("new_homes", {}))  # v28 added new homes (v35: its keep lines)
	gs._keep_lines_changed()
	gs.errand_tools = {}
	gs._tools_changed()
	var saved_tools: Dictionary = data.get("errand_tools", {})
	for id in saved_tools:
		if not Jobs.tool(gs.catalog, str(id)).is_empty():
			gs.errand_tools[str(id)] = maxi(0, int(saved_tools[id]))
	gs.scout_notes = clampi(int(data.get("scout_notes", 0)), 0, gs.scout_hold())  # v23
	gs._crews_changed()
	gs.gear = Gear.clean(gs.catalog, data.get("gear", {}))  # v22 added gear: older saves start with none
	gs.room = maxi(0, int(data.get("room", 0)))  # v28 added the room (v40: steps built on the house card)
	if from_version < 28:
		# a save from before the room that already had more pets gets room for them (and a bit more),
		# so boxes and box jobs keep opening (before the catch-up below: box workers open boxes there)
		var margin := float(gs.catalog.herd.get("room", {}).get("old_save_margin", 0.1))
		gs.room = maxi(gs.room, Herd.room_level_for(gs.catalog, ceili(gs.collection.plain_count() * (1.0 + margin))))
	gs.edge = Edge.clean(gs.catalog, data.get("edge", {}))  # v32 added the edge and the school
	gs.school = School.clean(gs.catalog, data.get("school", {}))
	gs.school_changed_boost()
	var stood := School.trim(gs.catalog, gs.school)  # never more in a class than its seats: the rest go back
	for k in stood:
		gs.collection.add_plain(k, int(stood[k]))
	gs._load_automation(data.get("automation", {}))
	gs.reserve_capsules = clampi(int(data.get("reserve_capsules", gs.default_reserve())), 0, gs.reserve_max())  # v25
	gs._hold_saves = true  # no saving halfway through loading
	_clamp_herd_places()
	gs._hold_saves = false
	gs.visited.clear()
	for id in data.get("visited", []):
		gs.visited[str(id)] = true
	if not data.has("visited"):
		# from before places glowed: everywhere already open counts as visited
		for location in gs.catalog.locations:
			if gs.location_open(location):
				gs.visited[location.id] = true
	gs.visits.clear()
	gs.unshown_ours.clear()
	var saved_visits: Dictionary = data.get("visits", {})
	for id in saved_visits:
		if not gs.catalog.location(str(id)).is_empty():
			gs.visits[str(id)] = maxi(0, int(saved_visits[id]))
	gs.sent.clear()
	if data.has("sent"):
		var saved_sent: Dictionary = data.sent
		for id in saved_sent:
			if not gs.catalog.location(str(id)).is_empty():
				gs.sent[str(id)] = maxi(0, int(saved_sent[id]))
	else:
		# from before pets sent were counted: every trip welcomed back had at least one pet, and the
		# parties still out count in full
		for id in gs.visits:
			gs.sent[id] = int(gs.visits[id])
		for run in gs.runs:
			gs.sent[run.location_id] = gs.sent_to(run.location_id) + run.party.setting_out()
	gs.find_tries.clear()
	var saved_find_tries: Dictionary = data.get("find_tries", {})  # v43 added them
	for id in saved_find_tries:
		if gs.catalog.finds.has(str(id)):
			gs.find_tries[str(id)] = maxi(0, int(saved_find_tries[id]))
	gs.saved_boxes.clear()
	for id in data.get("saved_boxes", []):
		gs.saved_boxes[str(id)] = true
	gs.boxes_bought.clear()
	var bought: Dictionary = data.get("boxes_bought", {})
	for id in bought:
		gs.boxes_bought[str(id)] = int(bought[id])
	gs.boxes_greeted.clear()
	for id in data.get("boxes_greeted", []):
		gs.boxes_greeted[str(id)] = true
	gs.buying_on = bool(data.get("buying_on", true))
	gs.pinned.assign(data.get("pinned", []).filter(func(uid): return gs.collection.get_pet(str(uid)) != null).map(func(uid): return str(uid)))
	gs.join_up_to = str(data.get("join_up_to", ""))
	if gs.join_up_to != "" and not gs.catalog.tiers.any(func(t): return t.id == gs.join_up_to):
		gs.join_up_to = ""
	if gs.pinned.size() > GameStateNode.PINNED_MAX:  # older saves kept every unseen good pull (the refold below folds the rest)
		gs.pinned = gs.pinned.slice(gs.pinned.size() - GameStateNode.PINNED_MAX)
	gs.idle_log = data.get("idle_log", {})
	gs.rummaged.clear()
	var saved_rummage: Dictionary = data.get("rummaged", {})
	for id in saved_rummage:
		if not gs.catalog.rummage_spot(str(id)).is_empty():
			gs.rummaged[str(id)] = float(saved_rummage[id])
	var saved_machine: Dictionary = data.get("machine", {})
	gs.machine = { "pulls": int(saved_machine.get("pulls", 0)), "lit": int(saved_machine.get("lit", 0)), "bought": {},
		"pet_wait": int(saved_machine.get("pet_wait", 0)), "globes": [], "greeted": [] }
	# globes you have (unknown ones dropped; the first is always there) and the ones already shown arriving
	var first := Machine.first_globe(gs.catalog)
	for g in [first] + Array(saved_machine.get("globes", [first])):
		if Machine.globe_rank(gs.catalog, str(g)) >= 0 and not gs.machine.globes.has(str(g)):
			gs.machine.globes.append(str(g))
	for g in saved_machine.get("greeted", gs.machine.globes):
		if gs.machine.globes.has(str(g)) and not gs.machine.greeted.has(str(g)):
			gs.machine.greeted.append(str(g))
	if not gs.machine.greeted.has(first):
		gs.machine.greeted.append(first)
	var saved_bought: Dictionary = saved_machine.get("bought", {})
	for id in saved_bought:
		if not Machine.node(gs.catalog, str(id)).is_empty():
			gs.machine.bought[str(id)] = int(saved_bought[id])
	for id in gs.finds:  # a globe's find that came home without it (any save): it's home now
		if Machine.globe_for_find(gs.catalog, str(id)) != "" and not gs.machine.globes.has(Machine.globe_for_find(gs.catalog, str(id))):
			gs.machine.globes.append(Machine.globe_for_find(gs.catalog, str(id)))
	gs.bits = {}
	var saved_bits: Dictionary = data.get("bits", {})
	for b in saved_bits:
		gs.bits[str(b)] = maxi(0, int(saved_bits[b]))
	gs.plushie = Plushie.clean(data.get("plushie", {}), gs.catalog)
	gs.started_at = float(data.get("started_at", 0.0))
	gs.milestones = data.get("milestones", {})
	gs.toys = Toys.fresh()
	var saved_toys: Dictionary = data.get("toys", {})
	var owned: Dictionary = saved_toys.get("owned", {})
	for k in owned:
		var bits := str(k).split(":")
		if bits.size() == 2 and not Toys.toy(gs.catalog, bits[0]).is_empty() and not Toys.finish(gs.catalog, bits[1]).is_empty():
			var e: Dictionary = owned[k]
			gs.toys.owned[str(k)] = { "level": clampi(int(e.get("level", 1)), 1, int(gs.catalog.toys.max_level)),
				"spares": maxi(0, int(e.get("spares", 0))), "wear": clampf(float(e.get("wear", 0.0)), 0.0, 1.0),
				"stars": maxi(0, int(e.get("stars", 0))) }  # v42 added stars (shining a favourite)
	for p in saved_toys.get("playing", []):
		if p is Dictionary and gs.toys.owned.has(str(p.get("key", ""))):
			gs.toys.playing.append({ "key": str(p.key), "until": float(p.get("until", 0.0)), "wear": float(p.get("wear", 0.0)),
				"play": str(p.get("play", "")), "again": bool(p.get("again", true)) })  # v39 added the play's length (the toy shelf)
	gs.workshop = Workshop.clean(gs.catalog, data.get("workshop", {}))  # v39 added the shed workshop
	gs.postcards.clear()
	gs.watching = null
	gs._finish_plays(Time.get_unix_time_from_system())  # plays that ended while the game was closed
	# the sewing basket kept stitching while the game was closed
	gs._mend_at = Time.get_unix_time_from_system()
	gs._mend_acc = 0.0
	if Workshop.has(gs.workshop, "basket"):
		var closed_for := minf(maxf(0.0, gs._mend_at - float(data.get("saved_at", gs._mend_at))), GameStateNode.OFFLINE_CAP)
		Toys.mend(gs.toys, float(gs.catalog.workshop.get("basket_mend_per_hour", 0.0)) * closed_for / 3600.0, gs._mend_at)
	gs.gifts = Gifts.clean(data.get("gifts", {}), gs.catalog.gifts)  # v29: older saves start the clock below
	gs._knacks_changed()
	if from_version >= 15 and from_version < 20:
		_regate()
		if gs.knows_job("boxes"):  # it had the cushion: opening boxes stays (now in the automation tab)
			gs.unlocks["feature:packs"] = true
			gs.unlocks["tab:automation"] = true
	# food and mood stay as they were while the game was closed (they only go down while it's open);
	# the kitchen's meals made while you were away top them up to its line from there. The buffs
	# don't count for time closed (boost_parts leaves them out while loading).
	gs._check_care()
	# errands kept going while the game was closed: full speed for a while, then slower
	var e: Dictionary = gs.catalog.errands
	var closed := Jobs.offline_seconds(Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0)),
		gs.errands_away_hours(), float(e.offline_after), GameStateNode.OFFLINE_CAP) * gs.boost("away")
	var brought := gs._work_for(closed)
	gs.jobs_away = { "coins": Rewards.total(brought, "coins"), "parts": Rewards.total(brought, "part") }
	gs._jobs_at = Time.get_unix_time_from_system()
	# your pet kept cranking its machine while the game was closed, as long as its stool lets it,
	# and workers too, as long as its stool lets them
	var cranked := Automation.away_seconds(gs.catalog, gs.automation, Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))) * gs.boost("away")
	if cranked > 0.0:
		gs._hold_saves = true  # no saving halfway through loading: the next autosave has it all
		gs._work_for_automation(cranked, false)
		gs._hold_saves = false
	gs._auto_at = Time.get_unix_time_from_system()
	gs._boxes_at = gs._auto_at
	# presents came while the game was closed, the same as if it had been open (only the clock counts)
	gs._tick_gifts(Time.get_unix_time_from_system(), false)
	# the music box: your pet kept leading the army while the game was closed, for up to its hours
	gs._hold_saves = true
	gs._army_while_away(float(data.get("saved_at", 0.0)), Time.get_unix_time_from_system())
	gs._hold_saves = false

	# v28: plain pets fold into the herd (old saves: crews and workers of uids become counts here)
	gs._rest_changed()
	gs.collection.refold()
	if from_version < 28 and gs.room_is_full() and not gs.homes.room_was_full:
		# new homes came in v28: a room that's full already has been full, the stall is there
		gs.homes.room_was_full = true
		gs.check_unlocks()
	if from_version < 35 and gs.finds.has("little_key") and not gs.is_unlocked("feature:sewing"):
		gs.check_unlocks()  # v35: the key found before the sewing room was built opens its door
	return true


## Pets from the herd on errands and machines never add up to more than the herd has (a save from
## elsewhere, or a count that shrank): the extra ones rest.
func _clamp_herd_places() -> void:
	var have := {}
	for k in gs.collection.herd:
		have[k] = gs.collection.herd_count(k)
	for uid: String in gs._stand_ins_out():
		Herd.take(have, Herd.key_of(uid), 1)
	var crews := false
	for job_id in gs.jobs:
		var h: Dictionary = gs._job_state(job_id).herd
		for k in h.keys():
			var ok := mini(int(h[k]), int(have.get(k, 0)))
			Herd.take(have, k, ok)
			if ok < int(h[k]):
				Herd.take(h, k, int(h[k]) - ok)
				crews = true
	var workers := false
	var wh: Dictionary = gs.automation.get("wherd", {})
	for id in wh:
		for k in wh[id].keys():
			var ok := mini(int(wh[id][k]), int(have.get(k, 0)))
			Herd.take(have, k, ok)
			if ok < int(wh[id][k]):
				Herd.take(wh[id], k, int(wh[id][k]) - ok)
				workers = true
	if crews:
		gs._crews_changed()
	if workers:
		gs._workers_changed()


## v20: saves from the capsule machine's time (v15 on) kept things old gates had opened: the
## second map page before the map scrap, the boxes tab before better drops, the workbench from
## parts that slipped in early. Everything data/unlocks.json opens closes again unless what earns
## it is really there (places you already found stay open). Older saves (and the test saves) keep
## what the migrations above gave them.
func _regate() -> void:
	if not gs.is_unlocked("feature:parts"):
		gs.parts_ever = false  # parts that slipped in early don't count as your first part
	for _pass in 2:  # twice: an unlock can wait for another one ("open")
		for o in UnlockRules.stale(gs.catalog.unlock_list, gs._earned):
			gs.unlocks.erase(o)
	gs._knacks_changed()


## Brings older save files up to the current format, one version at a time.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version >= GameStateNode.SAVE_VERSION:
		return data
	if version < 2:
		data.collection = {}  # v1 had no pets yet; a first pet is given after loading
	# v3 added the bag and dungeon runs; missing ones load as empty
	if version < 4:
		data.erase("dungeon")  # v3's simple runs: those pets just come home
	if version < 6:
		# v5: dungeons became adventures that unlock over time; older saves already had the
		# dungeons and big parties, so they keep them (v6: also for saves the first v5 build
		# touched, which didn't do this yet). Old runs are read by RunState.from_dict.
		var had: Array = data.get("unlocks", [])
		data.unlocks = had + ["type:dungeon", GameStateNode.AUTOMATION]
	if version < 11:
		# v11: things open up through adventures now. Saves from before keep what they had
		# (the inventory, errands, parties if they had them, and the second map page if they'd
		# got there); pack opening by your pet is a later-game find now.
		var had: Array = data.get("unlocks", [])
		var keep: Array = ["tab:inventory", "feature:errands", "tab:errands"]
		if "parties" in had or GameStateNode.AUTOMATION in had:
			keep.append_array(["feature:parties", "page:beyond"])
		for id in ["fields", "orchard", "well", "cellar", "below"]:
			if ("location:" + id) in had:
				keep.append("page:beyond")
		data.unlocks = had + keep
		data.parts_ever = true
	if version < 9:
		# v9: places open when pets spot them, not after a number of trips; keep what was open
		var had: Array = data.get("unlocks", [])
		var trips := int(data.get("trips_done", 0))
		var keep: Array = []
		if "type:dungeon" in had:
			keep.append("location:well")
		if GameStateNode.AUTOMATION in had:
			keep.append(GameStateNode.PARTIES)
		for step in [[1, "meadow"], [3, "woods"], [5, "fields"]]:
			if trips >= step[0]:
				keep.append("location:" + step[1])
		data.unlocks = had + keep
	if version < 13:
		# v13: errands are a tab of jobs now; old errands just stop (their pets are home)
		data.erase("errands")
		data.erase("errands_on")
		var had: Array = data.get("unlocks", [])
		if "feature:errands" in had and not "tab:errands" in had:
			data.unlocks = had + ["tab:errands"]
	if version < 14:
		data.jobs_auto = false  # v14: you put pets on errands yourself until you turn sharing on
	# v15 added the capsule machine, v16 capsule toys; saves without them start fresh
	if version < 18:
		# v18: parts come later (a feature of their own); saves that already had parts keep them
		if bool(data.get("parts_ever", false)):
			var had: Array = data.get("unlocks", [])
			data.unlocks = had + ["feature:parts"]
	if version < 17:
		# v17: the boxes tab and toys open through adventures now; saves from before keep them
		if str(data.get("tutorial", "done")) == "done":
			var had: Array = data.get("unlocks", [])
			data.unlocks = had + ["tab:boxes", "feature:toys"]
	if version < 19:
		# v19: parts slipped in early (rummaging, the scrapyard), so v18 opened them for saves that
		# weren't there yet. They close again until the 40th trip; parts already found stay in the bag.
		if int(data.get("trips_done", 0)) < 40:
			data.unlocks = data.get("unlocks", []).filter(func(id): return str(id) != "feature:parts")
	if version < 21:
		# v21: your pet opening boxes is a job in the automation tab now (the cushion teaches it):
		# saves that had it keep it, doing it if it was on
		var had: Array = data.get("unlocks", [])
		if "feature:packs" in had:
			if not "tab:automation" in had:
				data.unlocks = had + ["tab:automation"]
			var a := Automation.fresh()
			a.taught["boxes"] = true
			a.task = "boxes" if bool(data.get("packs_on", true)) else ""
			data.automation = a
	if version < 25:
		# v25: your pet's reserve is kept in capsules, like box prices: the coins it kept become
		# capsules at what one is worth on that save's machine (at least 1 if it kept any)
		var kept := float(data.get("coin_reserve", gs.default_reserve()))
		var value := Machine.coin_value({ "bought": data.get("machine", {}).get("bought", {}) }, gs.catalog)
		data.reserve_capsules = maxi(1, roundi(kept / value)) if kept > 0.0 else 0
		data.erase("coin_reserve")
	# v26 added box tiers (boxes_bought, boxes_greeted) and retired the lucky box: BoxShop.fix_retired
	# (load_game) handles both for any save, whatever its version
	# v27 added the whistle (automation.whistle: ticks, set aside): older saves load with every tick
	# on and the default set aside (_load_automation)
	# v28: the herd, new homes and "new pets join here". Collection.load_from reads the old collection
	# (stars as [uid, palette], the first pet with each part marked), and load_game folds plain pets
	# into counts once everything that keeps pets busy has loaded: old crews and workers of uids turn
	# into counts by themselves. load_game also switches every shared-out errand's "new pets join
	# here" on where jobs_auto was on, and a room that's full already opens the stall.
	# v29 added presents (gifts): nothing to convert; saves with the boxes tab open start the clock
	# on load (built as v25 in the care lane)
	# v30 added machine globes (machine.globes, machine.greeted): load_game gives an older save just
	# the first globe, already seen (built as v24 in the globes lane)
	if version < 31 and not data.has("visits"):
		# v31 counts visits per place (next door's lights, places becoming ours): every place
		# already visited counts once (built as v24 in the nextdoor lane)
		data.visits = Ours.visits_from(data.get("visited", []))
	# v32: past the edge and the little school; older saves start with neither (Edge.clean,
	# School.clean in load_game; built as v24 in the edge lane)
	# v34 (built as v24 in the plushie lane): the plushie machine (its state, wisps, buttons on
	# pets, bag keys "slot:id@n"); older saves have none of it and load an empty machine. Wisps
	# the dungeon paid (v33) stay: it's the one purse.
	# v35 (built as v27 in the sewing lane): the sewing room (its state, keep lines on the sorting
	# rule, room runs in the dungeon's run); nothing moves: older saves start with none of it
	# (load_game: past floor 20 already = the key)
	if version < 7:
		# v7: dungeon places open one rumour at a time; saves that had the dungeons keep them all
		var had: Array = data.get("unlocks", [])
		if "type:dungeon" in had:
			data.unlocks = had + ["location:cellar", "location:below"]
			data.heard = ["well", "cellar", "below"]
	if version < 33:
		# v33 (built as v24 in the dungeon lane): the well line is one dungeon. The cellar and further down stop being trips and become
		# bands of it; a save that had them open has those bands already (the unlocks stay). Rumours
		# waiting about them go, and parties going there go to the well instead (trips already out
		# there come home as usual).
		var had: Array = data.get("unlocks", [])
		var dg: Dictionary = data.get("dungeon", {}) if data.get("dungeon", {}) is Dictionary else {}
		var bands: Array = [str(Catalog.shared().dungeon.bands[0].id)]
		var band_places: Array[String] = []
		for b in Catalog.shared().dungeon.bands:
			var place := str(b.get("place", ""))
			if place != "" and ("location:" + place) in had and not str(b.id) in bands:
				bands.append(str(b.id))
		for l in Catalog.shared().locations:
			if l.has("band"):
				band_places.append(str(l.id))
		dg["bands"] = bands
		data.dungeon = dg
		data.rumours = data.get("rumours", []).filter(func(id): return not str(id) in band_places)
		var a = data.get("automation", {})
		if a is Dictionary:
			var parties: Array = [a.get("party", {})] + a.get("parties", [])
			for p in parties:
				if p is Dictionary and str(p.get("place", "")) in band_places:
					p.place = str(Catalog.shared().dungeon.bands[0].get("place", "well"))
	if version < 36:
		# v36 (built as v28 in the sewing lane): the wisps perk tree. The entrance's level moves out
		# of the dungeon into the perks.
		var dg = data.get("dungeon", {})
		if dg is Dictionary and int(dg.get("entrance", 0)) > 0:
			var pk = data.get("perks", {})
			if not pk is Dictionary:
				pk = {}
			pk["entrance"] = int(dg.entrance)
			data.perks = pk
		if dg is Dictionary:
			dg.erase("entrance")
	if version < 37:
		# v37 (built as v29 in the sewing lane): held landings. Older saves hold none and start from
		# the top.
		var dg = data.get("dungeon", {})
		if dg is Dictionary:
			dg["held"] = {}
			dg["start"] = 0
	if version < 38:
		data.wish = Wish.fresh()  # v38 (built as v26 in the wish lane): the wishing jar; older saves start with nothing wished for
	# v39 (built as v27 in the workshop lane): the shed workshop. Nothing to convert here: load_game's
	# Workshop.clean gives older saves a fresh one (the first 3 drawings pinned, nothing built), and
	# toys being played with load without a play length (the toy shelf doesn't hand those again)
	if version >= 28 and version < 40 and data.has("room"):
		# v40 (built as v27 in the house lane): the room grows in named steps (the house card) instead
		# of levels of 500 x 1.5^L: an old level becomes the fewest steps that hold at least as much,
		# so nobody loses room (a big old room can land on a squeeze-in step: kept, for free)
		var level := maxi(0, int(data.get("room", 0)))
		var old_cap := maxi(50, roundi(minf(500.0 * pow(1.5, level), 1.0e15) / 50.0) * 50)
		data.room = Herd.room_level_for(gs.catalog, old_cap)
	data.version = GameStateNode.SAVE_VERSION
	return data
