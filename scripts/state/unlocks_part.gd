class_name UnlocksPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


func is_unlocked(id: String) -> bool:
	return gs.unlocks.has(id)


func unlock(id: String) -> void:
	if gs.unlocks.has(id):
		return
	gs.unlocks[id] = true
	gs._knack_gates_changed()
	_opened(id)
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## A place you can go: its map page is open, and it's the page's first place or one a pet spotted
## (or a rumour led to) and you said yes. Never a band of the dungeon (data/adventures.json "band").
func location_open(location: Dictionary) -> bool:
	if location.is_empty() or location.has("band") or not page_open(str(location.get("page", gs.catalog.pages[0].id))):
		return false  # a band of the old well's dungeon is never a trip
	return location.get("start", false) or is_unlocked("location:" + location.id)


func page_open(page_id: String) -> bool:
	for page in gs.catalog.pages:
		if page.id == page_id:
			return page.get("start", false) or is_unlocked("page:" + page_id)
	return false


## Whether a feature ("errands", "packs", "parties") has been unlocked on your adventures.
func feature_on(feature: String) -> bool:
	return is_unlocked("feature:" + feature)


## Whether a tab is there: nothing opens it (always there), or what opens it has been unlocked.
## A tab that isn't open is out of sight (hidden until earned, never shown locked).
func tab_open(tab_name: String) -> bool:
	for entry in gs.catalog.unlock_list:
		if ("tab:" + tab_name) in entry.opens and not is_unlocked("tab:" + tab_name):
			return false
	return true


## Opens whatever you've earned on your adventures (data/unlocks.json).
func check_unlocks() -> void:
	for entry in gs.catalog.unlock_list:
		if entry.opens.all(func(o): return is_unlocked(o)) or not _earned(entry.earn):
			continue
		_open_entry(entry)
	# a rumour of something that's open now has nothing left to lead to (the edge opened by itself)
	gs.rumours.assign(gs.rumours.filter(func(id): return not gs.catalog.rumour(id).get("unlocks", []).all(func(u): return is_open(str(u)))))


## The find events at a place that a party of `n` could meet now (see AdventureRunner.can_meet).
func find_events_at(location: Dictionary, n := 1 << 30) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ids: Array = location.get("events", []) + location.get("pool", []).map(func(p): return p.event)
	for id in ids:
		var e: Dictionary = gs.catalog.events.get(str(id), {})
		if e.has("find") and n >= int(e.get("min_party", 1)) and AdventureRunner.can_meet(e, gs.finds, gs.machine.bought,
				gs.workers_total(), is_ours(str(location.id)), sent_to(str(location.id))):
			out.append(e)
	return out


## A party of `n` sets off for this place: every find it could meet counts the try. Returns the
## events it meets for sure (their find has waited find_sure_by tries).
func _count_find_tries(location: Dictionary, n: int) -> Array:
	var sure := []
	for e in find_events_at(location, n):
		var f := str(e.find)
		gs.find_tries[f] = int(gs.find_tries.get(f, 0)) + 1
		if int(gs.find_tries[f]) >= gs.catalog.find_sure_by:
			sure.append(str(e.id))
	return sure


## Opens an unlock: what it opens, its pet, your pet's news, its popup (the unlocked signal).
func _open_entry(entry: Dictionary) -> void:
	for o in entry.opens:
		gs.unlocks[o] = true
		_opened(str(o))
	if str(entry.get("pet_job", "")) != "":
		_gift_pet(str(entry.pet_job))
	if int(entry.get("button_gift", 0)) > 0:
		_gift_buttons(int(entry.button_gift))
	if str(entry.get("learns", "")) != "":
		gs.automation.taught[str(entry.learns)] = true  # your pet knows this job straight away
		gs.automation_changed.emit()
	if str(entry.get("announce", "")) != "":
		gs.announcements.append(entry.announce)
	gs.unlocked.emit(entry)
	_milestone(str(entry.id))
	gs.adventures_changed.emit()
	gs.changed.emit()


## Opens a map page from the game's code: the hook for pages nothing you find opens by itself
## (next door: "earn": { "called": true } in data/unlocks.json, opened by pets past the edge).
## Its unlock pops up and your pet tells you, as if it had been earned; a page with no unlock of
## its own just opens. Returns false if it was open already (or there's no such page).
func open_page(page_id: String) -> bool:
	if gs.catalog.page_info(page_id).is_empty() or page_open(page_id):
		return false
	var entry := UnlockRules.opening(gs.catalog.unlock_list, "page:" + page_id)
	if entry.is_empty():
		gs.unlocks["page:" + page_id] = true
		gs.adventures_changed.emit()
		gs.changed.emit()
	else:
		_open_entry(entry)
	if page_id == Ours.opens_with(gs.catalog):
		# places visited often enough already are ours now: the map colours them in next time you look
		for location in gs.catalog.locations:
			if is_ours(location.id) and not location.get("ours_at_start", false):
				gs.unshown_ours[location.id] = true
	gs.page_opened.emit(page_id)
	gs.save_game()
	return true


## Something just opened: the whistle is your pet's managing job, known from the moment it's found.
func _opened(id: String) -> void:
	if id == "feature:" + Automation.WHISTLE:
		gs.automation.taught[Automation.WHISTLE] = true
		gs.automation_changed.emit()


func _earned(earn: Dictionary) -> bool:
	if earn.get("called", false):
		return false  # only the game's code opens it (open_page)
	if earn.has("find") and not gs.finds.has(earn.find):
		return false
	if earn.get("first", "") == "part" and not gs.parts_ever:
		return false
	if earn.get("first", "") == "toy" and gs.toys.owned.is_empty():
		return false
	if gs.trips_done < int(earn.get("trips", 0)):
		return false
	if earn.has("machine") and Machine.owned(gs.machine, str(earn.machine)) <= 0:
		return false
	if gs.packs_by_hand < int(earn.get("packs_opened", 0)):
		return false
	if earn.has("open") and not is_unlocked(str(earn.open)):
		return false
	if earn.has("taught") and not gs.knows_job(str(earn.taught)):
		return false
	if earn.get("room", "") == "full" and not gs.homes.room_was_full:
		return false
	if earn.has("ours") and not is_ours(str(earn.ours)):
		return false
	if int(gs.homes.by_hand) < int(earn.get("homes_by_hand", 0)):
		return false
	if int(gs.dungeon.deep) < int(earn.get("floor", 0)):
		return false
	if int(gs.sewing.cleared) < int(earn.get("sewing", 0)):
		return false
	if earn.has("others") and not gs.knows_others(str(earn.others)):
		return false
	var levels: Dictionary = earn.get("job_level", {})
	for job_id in levels:
		if gs.job_level(str(job_id)) < int(levels[job_id]):
			return false
	if earn.has("all_places") and not all_places_open(str(earn.all_places)):
		return false
	if earn.has("edge") and not gs.edge_done(str(earn.edge)):
		return false
	if int(gs.edge.get("ever", 0)) < int(earn.get("edge_sent", 0)):
		return false
	return true


## Whether every place on a map page is open (and the page itself). Dungeon bands don't count.
func all_places_open(page_id: String) -> bool:
	if not page_open(page_id):
		return false
	for location in gs.catalog.locations:
		if str(location.get("page", "")) == page_id and not location.has("band") and not location_open(location):
			return false  # dungeon bands were places once: they never count
	return true


## A pet comes along with an unlock (the basket has one asleep in it) and starts on that errand, so
## there's someone to do it even when your only other pet is out on an adventure.
func _gift_pet(job_id: String) -> void:
	var got: Array[Pet] = [gs._roller.roll(GameStateNode.TUTORIAL_BOX)]
	gs.collection.add(got)
	gs.put_on_job(job_id, 1, [got[0].uid])


## Buttons come with an unlock (the plushie machine sews one onto your active pet): on the part with
## its best knack, else its body.
func _gift_buttons(n: int) -> void:
	var pet := gs.collection.active()
	if pet == null:
		return
	var slot := str(Knacks.best(gs.catalog, pet, gs.knack_gate).get("slot", "body"))
	if Plushie.full(gs.catalog, pet, slot):
		slot = Plushie.wild_default(gs.catalog, pet)
	if slot != "" and Plushie.sew(gs.catalog, pet, slot, n) > 0:
		gs.collection.pet_changed.emit(pet)
		gs.collection.active_changed.emit(pet)  # everything showing your pet redraws it


## The oldest news your pet hasn't told you yet, or "" (then forgotten).
func take_announcement() -> String:
	return gs.announcements.pop_front() if not gs.announcements.is_empty() else ""


## Whether an unlock id ("location:cellar", "automation", "parties") is open.
func is_open(id: String) -> bool:
	if id.begins_with("location:"):
		return location_open(gs.catalog.location(id.substr(9)))
	return is_unlocked(id)


## You say yes to a place a pet spotted: it opens right away.
func follow_lead(location_id: String) -> void:
	if not gs.spotted.has(location_id):
		return
	gs.spotted.erase(location_id)
	gs.unlocks["location:" + location_id] = true
	gs._knack_gates_changed()  # a knack kind may be gated on the place
	check_unlocks()  # the last place of a page may open something (the edge)
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## A pet that made it home may have spotted somewhere new on the way.
func _spot_places(run: RunState) -> Array[String]:
	if run.party.size() == 0:
		return []
	var location := gs.catalog.location(run.location_id)
	var bonus := float(run.scout.get("spot", 0.0))
	var found := Intel.roll(location, _place_known, gs.spot_tries, gs._rng, bonus, run.knack("spots"))
	for id in found:
		gs.spotted[id] = { "by": run.party.who(), "from": run.location_id }
	return found


## Whether you know a place: it's open, or a pet spotted it.
func _place_known(id: String) -> bool:
	return location_open(gs.catalog.location(id)) or gs.spotted.has(id)


## Places you can go, in the data's order.
func open_locations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for location in gs.catalog.locations:
		if location_open(location):
			out.append(location)
	return out


## Whether next door is open, so places can become ours (see Ours).
func next_door_open() -> bool:
	return page_open(Ours.opens_with(gs.catalog))


## Trips welcomed back from a place.
## Pets ever sent to a place, every party added up.
func sent_to(location_id: String) -> int:
	return int(gs.sent.get(location_id, 0))


func visits_at(location_id: String) -> int:
	return int(gs.visits.get(location_id, 0))


## Lights still on in the house behind a next-door place (0 once it's ours).
func lights_left(location_id: String) -> int:
	return Ours.lights_left(gs.catalog.location(location_id), visits_at(location_id))


## Whether a place is ours: coloured in by your pet, safer, pays a bit more, no locals (see Ours).
func is_ours(location_id: String) -> bool:
	return Ours.is_ours(gs.catalog, gs.catalog.location(location_id), visits_at(location_id), next_door_open())


## The map has started colouring in a place that just became ours (see unshown_ours).
func ours_shown(location_id: String) -> void:
	gs.unshown_ours.erase(location_id)


## Counts `n` more visits to a place. One light goes out each (next door); when the last goes out,
## or a backyard place has had its many visits, the place becomes ours: your pet tells you and the
## map colours it in. Returns "ours" if it just became ours, "dark" if a light went out, else "".
func add_visits(location_id: String, n := 1) -> String:
	var location := gs.catalog.location(location_id)
	if location.is_empty() or n <= 0:
		return ""
	var was_ours := is_ours(location_id)
	var lit := lights_left(location_id)
	gs.visits[location_id] = visits_at(location_id) + n
	if not was_ours and is_ours(location_id):
		gs.unshown_ours[location_id] = true
		gs.announcements.append(Ours.say(gs.catalog, "say_ours", location))
		return "ours"
	return "dark" if next_door_open() and lights_left(location_id) < lit else ""


## You decided to go where a rumour said: it opens what the rumour was about.
func follow_rumour(rumour_id: String) -> void:
	if not rumour_id in gs.rumours:
		return
	gs.rumours.erase(rumour_id)
	for id in gs.catalog.rumour(rumour_id).get("unlocks", []):
		gs.unlocks[id] = true
	gs._knack_gates_changed()  # a knack kind may be gated on what it opened
	check_unlocks()
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Pets came back with word of somewhere: hear up to `count` new rumours.
func _hear_rumours(count: int) -> void:
	var can := Rumours.hearable(gs.catalog, gs.heard, is_open)
	if gs.heard.is_empty() and count > 0 and not can.is_empty():
		gs.announcements.append("a rumour is word of somewhere new! it's on the map now. tap it and say yes, and we can go there!")
	for i in mini(count, can.size()):
		var rumour: Dictionary = can.pop_at(gs._rng.randi_range(0, can.size() - 1))
		gs.heard[rumour.id] = true
		gs.rumours.append(rumour.id)


## The biggest party you may send here: one pet, then bigger parties as things are found, swarms
## with automation, and a location's own cap.
func max_party(location_id: String) -> int:
	var most := 1
	for step in GameStateNode.PARTY_SIZES:
		if feature_on(step[0]):
			most = maxi(most, step[1])
	if is_unlocked(GameStateNode.AUTOMATION):
		most = 1 << 30
	var cap := int(gs.catalog.location(location_id).get("max_party", 0))
	return mini(most, cap) if cap > 0 else most


func debug_unlock_all() -> void:
	unlock(GameStateNode.AUTOMATION)
	for entry in gs.catalog.unlock_list:
		for o in entry.opens:
			unlock(o)
	gs.spotted.clear()
	for l in gs.catalog.locations:
		unlock("location:" + l.id)


func tutorial_active() -> bool:
	return gs.tutorial != "done"


## The current tutorial step's data (see data/tutorial.json), or {} when it's done.
func tutorial_info() -> Dictionary:
	for step in gs.catalog.tutorial.steps:
		if step.id == gs.tutorial:
			return step
	return {}


func _start_tutorial() -> void:
	gs.coins = 0
	gs.bag = {}
	gs.tutorial = gs.catalog.tutorial.steps[0].id
	gs.collection.auto_active = true  # your first pet (out of the machine) is your active pet
	gs.started_at = Time.get_unix_time_from_system()
	gs.milestones = {}


## Moves the tutorial on once its step is done: your first pet out of the machine, then (after a
## while of building the machine up) a second one with a map, and it's sent on an adventure.
func _check_tutorial() -> void:
	var before := gs.tutorial
	for i in 4:
		match gs.tutorial:
			"pull":
				if gs.collection.count() >= 1:
					gs.tutorial = "machine"
					_milestone("first pet")
			"machine":
				if gs.collection.count() >= 2:
					gs.tutorial = "send"
					_milestone("adventures")
			"send":
				if not gs.runs.is_empty():
					gs.tutorial = "done"
					gs.collection.auto_active = true
	if gs.tutorial != before:
		gs.tutorial_changed.emit()
		gs.save_game()


## Debug: back to how a new game starts: only the first adventure type, no trips counted, no
## rumours heard. Trips already out still finish.
func debug_lock_all() -> void:
	gs.unlocks.clear()
	gs._knack_gates_changed()
	gs.trips_done = 0
	gs.heard.clear()
	gs.rumours.clear()
	gs.finds.clear()
	gs.spotted.clear()
	gs.spot_tries.clear()
	gs.visits.clear()
	gs.sent.clear()
	gs.find_tries.clear()
	gs.unshown_ours.clear()
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Notes how long into the game something happened (for pacing tests, shown in settings' dev part).
func _milestone(what: String) -> void:
	if gs.started_at > 0.0 and not gs.milestones.has(what):
		gs.milestones[what] = (Time.get_unix_time_from_system() - gs.started_at) / 60.0


## What can be bought on a tab right now, each as "id:level it would take" (the tab's news dot:
## something you can afford that you haven't seen yet, see upgrade_news).
func buyable(tab_id: String) -> Array[String]:
	var out: Array[String] = []
	match tab_id:
		"machine":
			for n in gs.catalog.machine_tree.nodes:
				if Machine.blocker(gs.machine, gs.catalog, str(n.id), gs.coins, gs.bits) == "":
					out.append("%s:%d" % [n.id, Machine.owned(gs.machine, str(n.id))])
		"adventures":
			if gs.gear_page_open():
				for g in gs.shown_gear():
					if gs.gear_block(str(g.id)) == "" and gs.xp >= gs.gear_price(str(g.id)):
						out.append("%s:%d" % [g.id, gs.gear_level(str(g.id))])
		"errands":
			for t in Jobs.all_tools(gs.catalog):
				if gs.errand_tool_block(str(t.id)) == "" and gs.coins >= int(gs.errand_tool_plan(str(t.id), 1)[1]):
					out.append("%s:%d" % [t.id, gs.errand_tool_level(str(t.id))])
		"automation":
			for j in gs.auto_jobs():
				if not gs.knows_job(str(j.id)) and gs.coins >= int(j.coins):
					out.append("teach:" + str(j.id))
			for t in Automation.all_tools(gs.catalog):
				if gs.auto_tool_block(str(t.id)) == "" and gs.coins >= gs.auto_tool_cost(str(t.id)):
					out.append("%s:%d" % [t.id, Automation.tool_level(gs.automation, str(t.id))])
	return out


## Whether a tab has something new to buy: affordable, and not there yet the last time you looked.
func upgrade_news(tab_id: String) -> bool:
	var seen: Dictionary = gs._seen_buyable.get(tab_id, {})
	return buyable(tab_id).any(func(k): return not seen.has(k))


## You're looking at a tab: what it can buy now is seen (its dot goes out until something new).
func saw_upgrades(tab_id: String) -> void:
	var seen := {}
	for k in buyable(tab_id):
		seen[k] = true
	gs._seen_buyable[tab_id] = seen
