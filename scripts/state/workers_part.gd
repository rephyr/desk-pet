class_name WorkersPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## The job a pet works at in automation, or "".
func worker_job(uid: String) -> String:
	return str(gs._worker_of.get(uid, ""))


## Whether a job has been taught to the other pets (it's on the workers page).
func knows_others(id: String) -> bool:
	return Automation.others(gs.automation, id)


## Jobs taught to the other pets, in order (the workers page).
func worker_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in gs.auto_jobs():
		if knows_others(j.id):
			out.append(j)
	return out


## Why "teach the others" can't be bought for a job ("" when it can, coins aside), see Automation.
func teach_others_block(id: String) -> String:
	return Automation.teach_block(gs.catalog, gs.automation, id)


func teach_others_cost(id: String) -> int:
	return int(Automation.job(gs.catalog, id).get("teach", {}).get("coins", 0))


## Your pet teaches the other pets a job: the workers page opens (or gets the job). Returns whether
## it worked.
func teach_others(id: String) -> bool:
	if teach_others_block(id) != "" or gs.coins < teach_others_cost(id):
		return false
	gs.coins -= teach_others_cost(id)
	gs.automation.others[id] = true
	gs.check_unlocks()  # the wishing jar waits for the box tables
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## A job's workers (uids). Adventure parties keep their slot: an empty one is "".
func workers_of(id: String) -> Array:
	return gs.automation.workers.get(id, [])


## A job's workers from the herd: count key -> how many (never adventures: a party's leader keeps its slot).
func workers_herd(id: String) -> Dictionary:
	return gs.automation.get("wherd", {}).get(id, {})


## How many pets work at a job: cards and counts.
func workers_count(id: String) -> int:
	return workers_of(id).filter(func(uid): return str(uid) != "").size() + Herd.total(workers_herd(id))


## Up to `n` of a job's workers to show (uids): cards first, then stand-ins for its counts.
func worker_faces(id: String, n: int) -> Array:
	var cards: Array = workers_of(id).filter(func(uid): return str(uid) != "").slice(0, n)
	return gs._faces(cards, workers_herd(id), n, 20 + gs.auto_jobs().map(func(j): return j.id).find(id))


## Machines, tables or parties for a job's workers: [how many a buy gets, coins]. `n` -1: as many as
## you can afford. Never more than are still out there (see spot_room).
func spot_plan(id: String, n := 1) -> Array:
	var spot: Dictionary = Automation.job(gs.catalog, id).get("spot", {})
	var room := spot_room(id)
	if spot.is_empty() or room <= 0:
		return [0, 0]
	var have := Automation.spots(gs.automation, id)
	if n < 0:
		n = maxi(1, Automation.affordable(gs.catalog, gs.automation, id, gs.coins, room))
	n = mini(n, room)
	return [n, Jobs.tool_cost(spot, have, n)]


## Buys machines (tables, parties) for a job's workers. Returns how many it bought.
func buy_spots(id: String, n := 1) -> int:
	var plan := spot_plan(id, n)
	if not knows_others(id) or int(plan[0]) <= 0 or gs.coins < int(plan[1]):
		return 0
	gs.coins -= int(plan[1])
	_add_spots(id, int(plan[0]))
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return int(plan[0])


## More spots for a job (paid for already). A new party goes to an open place that has none yet.
func _add_spots(id: String, n: int) -> void:
	gs.automation.spots[id] = Automation.spots(gs.automation, id) + n
	if id == "adventures":
		while gs.automation.parties.size() < Automation.spots(gs.automation, id):
			gs.automation.parties.append({ "place": _free_party_place(), "n": 0 })


## An open place none of the workers' parties goes to yet (one that takes a party first), or "".
func _free_party_place() -> String:
	var taken := {}
	for slot in gs.automation.parties.size():
		taken[str(gs.auto_party(slot).place)] = true
	var spare := ""
	for l in party_places():
		if taken.has(str(l.id)):
			continue
		if int(l.get("max_party", 0)) != 1:
			return str(l.id)
		if spare == "":
			spare = str(l.id)
	return spare


## Open places the workers' parties can take by themselves: no dungeons, nothing risky that
## isn't ours yet (pets get lost there only when you send them yourself).
func party_places() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for l in gs.open_locations():
		if str(l.get("type", "")) == "dungeon":
			continue
		if l.get("risky", false) and not gs.is_ours(str(l.id)):
			continue
		out.append(l)
	return out


## The map pages that are open (their ids).
func open_pages() -> Array:
	return gs.catalog.pages.filter(func(p): return gs.page_open(str(p.id))).map(func(p): return str(p.id))


## How many machines (tables, parties) there are for a job in the places you've taken.
func spot_exist(id: String) -> int:
	return Automation.exist(gs.catalog, id, open_pages(), party_places().size())


## How many are still out there to haul home: what a buy can get at most.
func spot_room(id: String) -> int:
	return Automation.out_there(gs.catalog, gs.automation, id, open_pages(), party_places().size())


## Every worker, all jobs added up (cards and the herd).
func workers_total() -> int:
	var n := gs._worker_of.size()
	for id in gs.automation.get("wherd", {}):
		n += Herd.total(workers_herd(str(id)))
	return n


## Puts resting pets on a job's empty machines (tables, parties), the best workers first: `count`
## of them, -1 as many as there's room for. Pets from the herd lead parties as stand-ins. Returns
## how many started.
func put_workers(id: String, count := 1) -> int:
	var free_spots := Automation.spots(gs.automation, id) - workers_count(id)
	if not knows_others(id) or free_spots <= 0:
		return 0
	var picked := gs._pick(gs.resting_cards(), gs.resting_herd(), mini(free_spots, count) if count >= 0 else free_spots,
		func(p: Pet): return Automation.worker_speed(gs.catalog, p), true)
	return _add_workers(id, picked[0], picked[1])


## Puts these resting cards (uids) and pets from the resting herd (`counts`) on a job's machines.
## Returns how many started. `quiet`: no _workers_changed (the caller does it once, e.g. the whistle).
func _add_workers(id: String, cards: Array, counts: Dictionary, quiet := false) -> int:
	cards = cards.duplicate()
	if id == "adventures":  # every party keeps its own slot: a pet from the herd leads it as a stand-in
		var skip := gs._stand_ins_out()
		for k in counts:
			for uid in gs.collection.stand_in_uids(k, int(counts[k]), skip):
				cards.append(uid)
				skip[uid] = true
		counts = {}
	var n := cards.size() + Herd.total(counts)
	if n == 0:
		return 0
	var list: Array = workers_of(id).duplicate()
	for uid in cards:  # empty party slots get a leader first
		var hole := list.find("")
		if hole >= 0:
			list[hole] = uid
		else:
			list.append(uid)
	gs.automation.workers[id] = list
	if not counts.is_empty():
		var wh: Dictionary = gs.automation.get("wherd", {})
		if not wh.has(id):
			wh[id] = {}
		for k in counts:
			Herd.put(wh[id], k, int(counts[k]))
		gs.automation.wherd = wh
	if not quiet:
		_workers_changed()
	return n


## Sends a job's workers home to rest: `count` of the slowest, -1 all. Returns how many.
func take_off_workers(id: String, count := 1) -> int:
	var list: Array = workers_of(id).filter(func(uid): return str(uid) != "")
	var wh := workers_herd(id)
	if list.is_empty() and wh.is_empty():
		return 0
	if id == "adventures":
		var going := list.slice(list.size() - (list.size() if count < 0 else mini(count, list.size())))  # the last parties stop
		_take_off_workers(going)
		gs.collection.refold()  # a leader that stopped may fold into the herd now
		return going.size()
	var pets: Array = []
	for uid in list:
		var pet := gs.collection.get_pet(str(uid))
		if pet:
			pets.append(pet)
	var picked := gs._pick(pets, wh, count, func(p: Pet): return Automation.worker_speed(gs.catalog, p), false)
	var n: int = picked[0].size()
	for k in picked[1]:
		Herd.take(wh, k, int(picked[1][k]))
		n += int(picked[1][k])
	if picked[0].is_empty():
		_workers_changed()
	else:
		_take_off_workers(picked[0])
	return n


## Takes these pets off whatever machine, table or party they work at.
func _take_off_workers(uids: Array) -> void:
	var gone := {}
	for uid in uids:
		if gs._worker_of.has(uid):
			gone[uid] = true
	if gone.is_empty():
		return
	for id in gs.automation.workers:
		if id == "adventures":  # a party keeps its place: its slot just waits for a new leader
			gs.automation.workers[id] = gs.automation.workers[id].map(func(uid): return "" if gone.has(uid) else uid)
		else:
			gs.automation.workers[id] = gs.automation.workers[id].filter(func(uid): return not gone.has(uid))
	_workers_changed()


func _workers_changed() -> void:
	gs._rest_changed()
	gs._worker_of.clear()
	gs._worker_speed.clear()
	for id in gs.automation.workers:
		for uid in gs.automation.workers[id]:
			if str(uid) != "":
				gs._worker_of[uid] = id
	gs.automation_changed.emit()
	gs.jobs_changed.emit()
	gs.changed.emit()
	gs.save_game()


## A job's workers' speeds added up (how many of your pet they're worth).
func workers_speed(id: String) -> float:
	if not gs._worker_speed.has(id):
		var sum := 0.0
		for uid in workers_of(id):
			var pet := gs.collection.get_pet(str(uid)) if str(uid) != "" else null
			if pet:
				sum += Automation.worker_speed(gs.catalog, pet) * gs.knack_own(pet, "automation")
		var wh := workers_herd(id)
		for k in wh:
			sum += Automation.worker_speed(gs.catalog, Herd.template(gs.catalog, k)) * int(wh[k])
		gs._worker_speed[id] = sum
	return float(gs._worker_speed[id])


## The whistle checks on everyone `checks` times: hauls spots home (coins, never under set aside)
## and puts resting pets on the empty ones. Quiet: it all happens at once, one save at the end.
func _whistle_checks(checks: int) -> void:
	var jobs: Array = worker_jobs().map(func(j): return str(j.id))
	var rooms := {}
	for id in jobs:
		rooms[id] = spot_room(id)
	var out := 0  # the workers' parties that are out: their pets aren't resting
	var leaders := workers_of("adventures")
	for slot in leaders.size():
		if str(leaders[slot]) != "" and gs.auto_run(slot) != null:
			out += 1
	var plan := Automation.whistle_plan(gs.catalog, gs.automation, jobs, gs.coins, rooms, gs.resting_count(), checks, out)
	if plan.buys.is_empty() and plan.fill.is_empty():
		return
	gs.coins -= int(plan.spent)
	for id in plan.buys:
		_add_spots(id, int(plan.buys[id]))
		gs.whistle_since.hauled[id] = int(gs.whistle_since.hauled.get(id, 0)) + int(plan.buys[id])
	var at := 0
	if not plan.fill.is_empty():  # the best workers first, cards and pets from the herd alike
		var cards: Array = gs.resting_cards().duplicate()
		var counts: Dictionary = gs.resting_herd().duplicate()
		for id in plan.fill:
			var picked := gs._pick(cards, counts, int(plan.fill[id]), func(p: Pet): return Automation.worker_speed(gs.catalog, p), true)
			var taken := {}
			for uid in picked[0]:
				taken[uid] = true
			cards = cards.filter(func(p): return not taken.has(p.uid))
			for k in picked[1]:
				Herd.take(counts, k, int(picked[1][k]))
			var n := _add_workers(id, picked[0], picked[1], true)
			at += n
			gs.whistle_since.put = int(gs.whistle_since.put) + n
	if at > 0:
		_workers_changed()
	else:
		gs.automation_changed.emit()
		gs.changed.emit()
		gs.save_game()


## You looked at the whistle's list: "since you looked" starts again.
func whistle_seen() -> void:
	gs.whistle_since = { "hauled": {}, "put": 0 }


## Turns a tick on the whistle's list on or off (`key` "haul" or "fill").
func set_whistle_tick(id: String, key: String, on: bool) -> void:
	var ticks: Dictionary = gs.automation.whistle.ticks
	var t: Dictionary = ticks.get(id, {})
	t[key] = on
	ticks[id] = t
	gs.automation_changed.emit()
	gs.save_game()


## Set aside one step up (1) or down (-1).
func step_whistle_keep(d: int) -> void:
	gs.automation.whistle.keep = Automation.keep_step(gs.catalog, gs.automation, d)
	gs.automation_changed.emit()
	gs.save_game()


## Box workers open `count` boxes from your pile (the kinds your pet may open; they never buy any).
## It counts boxes, not pets: a sunset box is one box however many pets are in it. At most
## WORKER_BOXES_MAX at once (a long time away can't stall the load; the rest wait on the pile).
func _workers_open(count: int) -> void:
	if gs.room_left() <= 0 and gs.boxes_on_pile() > 0:
		gs._room_hit()
	count = mini(count, gs.room_left())  # a full room: the boxes wait on the pile
	var opened := 0
	var good: Array = []
	var pins: Array[String] = []
	var split := BoxShop.split_open(gs.bag, gs.pet_box_order(), mini(count, GameStateNode.WORKER_BOXES_MAX))
	for box_id in split:
		var before := gs.in_bag(box_id)
		var pulled := gs.open_boxes(box_id, int(split[box_id]), "", true)
		opened += before - gs.in_bag(box_id)  # a room filling up mid-way opens fewer
		for pet in pulled:
			if gs.is_good_pull(pet) and not gs._sent_home.has(pet.uid):  # not one the sorting rule sent off
				if gs.collection.get_pet(pet.uid) != null:  # a big batch may have folded it into the herd already
					pins.append(pet.uid)
				good.append(pet.display_name(gs.catalog))
	gs._pin(pins)
	if opened > 0:
		gs._log_idle({ "packs": opened, "good": good })
