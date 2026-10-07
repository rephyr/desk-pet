class_name RestPart
extends RefCounted
## GameState's code for who's resting (not active, away, on an errand or working), picking pets and
## placing new ones where new pets join.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Who's resting, worked out once until crews, workers, trips, the army or the herd change:
## { cards: [Pet], herd: { count key: n }, n: everyone, army_herd: { count key: n } (the dungeon's) }.
func _resting() -> Dictionary:
	if gs._rest.is_empty():
		var gone := gs._out()
		var cards: Array[Pet] = []
		for pet in gs.collection.pets:
			if pet.uid != gs.collection.active_uid and not gone.has(pet.uid) and not gs._job_of.has(pet.uid) and not gs._worker_of.has(pet.uid):
				cards.append(pet)
		var used := _herd_used(gone)
		var army := gs._army_herd(used)  # the dungeon's army takes its pets from the herd after everyone else
		for k in army:
			Herd.put(used, k, int(army[k]))
		var free := {}
		var n := cards.size()
		for k in gs.collection.herd:
			var left := gs.collection.herd_count(k) - int(used.get(k, 0))
			if left > 0:
				free[k] = left
				n += left
		gs._rest = { "cards": cards, "herd": free, "n": n, "army_herd": army }
	return gs._rest


## Something changed who's resting: it's worked out again when next asked.
func _rest_changed() -> void:
	gs._rest = {}
	gs._spare = {}


## Pets from the herd that are busy: count key -> on errands, working, away or leading a party.
func _herd_used(gone: Dictionary) -> Dictionary:
	var used := {}
	for job_id in gs.jobs:
		var h: Dictionary = gs.jobs[job_id].get("herd", {})
		for k in h:
			Herd.put(used, k, int(h[k]))
	var wh: Dictionary = gs.automation.get("wherd", {})
	for id in wh:
		for k in wh[id]:
			Herd.put(used, k, int(wh[id][k]))
	for uid: String in _stand_ins_out(gone):
		Herd.put(used, Herd.key_of(uid), 1)
	return used


## Stand-ins in use: away on an adventure or leading a workers' party. uid -> true.
func _stand_ins_out(gone := {}) -> Dictionary:
	var out := {}
	for uid: String in (gone if not gone.is_empty() else gs.away()):
		if Herd.is_stand_in(uid):
			out[uid] = true
	for uid in gs.workers_of("adventures"):
		if Herd.is_stand_in(str(uid)):
			out[str(uid)] = true
	return out


## Cards resting (whole pets), in pull order.
func resting_cards() -> Array[Pet]:
	return _resting().cards


## Pets from the herd resting: count key -> how many.
func resting_herd() -> Dictionary:
	return _resting().herd


## Everyone resting, cards and herd.
func resting_count() -> int:
	return int(_resting().n)


## Up to `n` resting pets to show (uids): cards first, then stand-ins for the counts.
func resting_faces(n: int) -> Array:
	var cards: Array = resting_cards().slice(0, n).map(func(p): return p.uid)
	return _faces(cards, resting_herd(), n, 7)


## Resting pets as whole pets: every resting card, and up to data/herd.json "stand_ins" stand-ins
## from each resting count (for parties).
func resting_pets() -> Array[Pet]:
	var out: Array[Pet] = resting_cards().duplicate()
	out.append_array(_resting_stand_ins())
	return out


## Up to data/herd.json "stand_ins" stand-ins from each resting count.
func _resting_stand_ins() -> Array[Pet]:
	var out: Array[Pet] = []
	var skip := _stand_ins_out()
	var per := int(gs.catalog.herd.get("stand_ins", 10))
	var h := resting_herd()
	for k in h:
		for uid in gs.collection.stand_in_uids(k, mini(per, int(h[k])), skip):
			out.append(gs.collection.get_pet(uid))
	return out


## Pets on your spare list: everyone but your active pet and pets away on adventures.
func spare_count() -> int:
	var gone := gs._out()
	return maxi(0, gs.collection.count() - (1 if gs.collection.active() != null else 0) - gone.size())


## Cards first, then stand-ins for `counts` (a different run of faces per `salt`), up to `n` uids.
func _faces(cards: Array, counts: Dictionary, n: int, salt := 0) -> Array:
	var out: Array = cards.slice(0, n)
	for k in counts:
		if out.size() >= n:
			break
		out.append_array(gs.collection.stand_in_uids(k, mini(n - out.size(), int(counts[k])), {}, 1000 + salt * 64))
	return out


## Up to `n` stand-ins (uids) for pets in `counts`, a different run of faces per `salt`.
func herd_faces(counts: Dictionary, n: int, salt := 0) -> Array:
	return _faces([], counts, n, salt)


## A rarity's cards split for its shelf: [always, newest]. Always: pets that stay cards (your active
## pet first, then favourites, better finishes, new parts) and pets busy right now; newest: the other
## plain cards, newest first.
func shelf_split(rarity: String) -> Array:
	var busy := _busy_uids()
	var cards := gs.collection.cards_of(rarity)
	# only a few different ranks: bucket by rank, newest first inside each (no sort over thousands)
	var by_rank := {}  # rank -> pets, newest first
	var newest: Array[Pet] = []
	var finish_ranks := {}
	for i in range(cards.size() - 1, -1, -1):
		var pet := cards[i]
		if gs.collection.always_card(pet) or busy.has(pet.uid):
			if not finish_ranks.has(pet.finish):
				finish_ranks[pet.finish] = gs.catalog.finish_rank(pet.finish)
			var r: int = (1000 if pet.uid == gs.collection.active_uid else 0) + (500 if pet.fav else 0) \
				+ int(finish_ranks[pet.finish]) * 10 + (1 if pet.new_part else 0)
			if not by_rank.has(r):
				by_rank[r] = []
			by_rank[r].append(pet)
		else:
			newest.append(pet)
	var ranks := by_rank.keys()
	ranks.sort()
	ranks.reverse()
	var always: Array[Pet] = []
	for r in ranks:
		always.append_array(by_rank[r])
	return [always, newest]


## Uids that must stay whole cards right now: away, in the army, good pulls waiting to be seen, party leaders.
func _busy_uids() -> Dictionary:
	var out := gs._out()
	for uid in gs.pinned:
		out[uid] = true
	for uid in gs.workers_of("adventures"):
		if str(uid) != "":
			out[str(uid)] = true
	if gs.feature_on("plushie") and str(gs.plushie.keeper) != "":
		out[str(gs.plushie.keeper)] = true  # the plushie machine's keeper stays a card while it's picked
	return out


## Cards folded into the herd: the errand or machine they were on keeps them, as a count.
func _on_folded(uids: Array, keys: Array) -> void:
	var from_jobs := {}  # job id -> { uid: true }
	var from_workers := {}
	var wh: Dictionary = gs.automation.get("wherd", {})
	for i in uids.size():
		var uid := str(uids[i])
		var k := str(keys[i])
		var job := str(gs._job_of.get(uid, ""))
		if job != "" and gs.jobs.has(job):
			if not from_jobs.has(job):
				from_jobs[job] = {}
			from_jobs[job][uid] = true
			Herd.put(gs._job_state(job).herd, k, 1)
		var w := str(gs._worker_of.get(uid, ""))
		if w != "" and w != "adventures":
			if not from_workers.has(w):
				from_workers[w] = {}
			from_workers[w][uid] = true
			if not wh.has(w):
				wh[w] = {}
			Herd.put(wh[w], k, 1)
	gs.automation.wherd = wh
	for job in from_jobs:
		gs.jobs[job].crew = gs.jobs[job].crew.filter(func(uid): return not from_jobs[job].has(uid))
	for w in from_workers:
		gs.automation.workers[w] = gs.automation.workers[w].filter(func(uid): return not from_workers[w].has(str(uid)))
	if not from_jobs.is_empty():
		gs._crews_changed()
	if not from_workers.is_empty():
		gs._workers_changed()
	_rest_changed()


## Picks pets out of `cards` and `counts` by `speed` (a Callable on a Pet): the fastest first, or
## the slowest with `best_first` false; `count` -1 takes everyone. Returns [card uids, { key: n }].
func _pick(cards: Array, counts: Dictionary, count: int, speed: Callable, best_first: bool) -> Array:
	var options := []  # [speed, card uid or "", count key or "", how many]
	for pet: Pet in cards:
		options.append([speed.call(pet), pet.uid, "", 1])
	for k in counts:
		options.append([speed.call(Herd.template(gs.catalog, k)), "", k, int(counts[k])])
	options.sort_custom(func(a, b): return a[0] > b[0] if best_first else a[0] < b[0])
	var left := count if count >= 0 else (1 << 62)
	var out_cards: Array = []
	var out_counts := {}
	for o in options:
		if left <= 0:
			break
		if o[1] != "":
			out_cards.append(o[1])
			left -= 1
		else:
			var take := mini(left, int(o[3]))
			out_counts[o[2]] = take
			left -= take
	return [out_cards, out_counts]


## "New pets join here" on a job's machines (tables): new pets start there while it has empty
## spots, the best workers first. Never adventures (parties keep their slots and "fill up").
func set_worker_join(id: String, on: bool) -> void:
	if id == "adventures" or not gs.knows_others(id):
		return
	var wj: Dictionary = gs.automation.get("wjoin", {})
	if on:
		wj[id] = true
	else:
		wj.erase(id)
	gs.automation.wjoin = wj
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()


func worker_joins(id: String) -> bool:
	return gs.automation.get("wjoin", {}).has(id)


## "New pets join here" takes new pets up to this rarity only ("" = every rarity).
func set_join_up_to(rarity: String) -> void:
	if rarity != "" and not gs.catalog.tiers.any(func(t): return t.id == rarity):
		return
	gs.join_up_to = rarity
	gs.jobs_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Whether any job has "new pets join here" on.
func any_join() -> bool:
	for job in gs.open_jobs():
		if gs.job_joins(job.id):
			return true
	for j in gs.worker_jobs():
		if worker_joins(j.id):
			return true
	return false


## New pets (resting ones; a stand-in's uid is one from its count) go where "new pets join here" is
## on: machines and tables with empty spots first (the best workers first), then the rest over the
## errands that have it, the smallest crews first. Nothing on: they rest. Pets the sorting rule
## sent to work (_to_work) that are still resting then go over every open errand.
func _place_new(uids: Array) -> void:
	var forced: Array = []
	if not gs._to_work.is_empty():
		forced = uids.filter(func(uid): return gs._to_work.has(str(uid)))
		gs._to_work.clear()
	if uids.is_empty() or gs.tutorial_active() or not (forced.size() > 0 or any_join()):
		return
	var resting := {}
	for pet in resting_cards():
		resting[pet.uid] = true
	var cards: Array = []
	var counts := {}
	var free := resting_herd()
	for raw in uids:
		var uid := str(raw)
		if Herd.is_stand_in(uid):
			var k := Herd.key_of(uid)
			if int(counts.get(k, 0)) < int(free.get(k, 0)):
				Herd.put(counts, k, 1)
		elif resting.has(uid):
			resting.erase(uid)
			cards.append(uid)
	# "up to" a rarity: rarer new pets stay resting (for the army, the edge...); the rule's pets still go
	if gs.join_up_to != "":
		var top := gs.catalog.rank(gs.join_up_to)
		cards = cards.filter(func(uid): return forced.has(uid) or gs.catalog.rank(gs.collection.get_pet(uid).rarity) <= top)
		for k in counts.keys():
			if gs.catalog.rank(Herd.rarity_of(k)) > top:
				counts.erase(k)
	# machines and tables first, while they have room
	for j in gs.worker_jobs():
		var id := str(j.id)
		if id == "adventures" or not worker_joins(id) or (cards.is_empty() and counts.is_empty()):
			continue
		var space := Automation.spots(gs.automation, id) - gs.workers_count(id)
		if space <= 0:
			continue
		var pets: Array = []
		for uid in cards:
			var pet := gs.collection.get_pet(uid)
			if pet:
				pets.append(pet)
		var picked := _pick(pets, counts, space, func(p: Pet): return Automation.worker_speed(gs.catalog, p), true)
		if picked[0].is_empty() and picked[1].is_empty():
			continue
		for uid in picked[0]:
			cards.erase(uid)
		for k in picked[1]:
			Herd.take(counts, k, int(picked[1][k]))
		gs._add_workers(id, picked[0], picked[1])
	if cards.is_empty() and counts.is_empty():
		return
	var joined: Array = gs.open_jobs().filter(func(j): return gs.job_joins(j.id)).map(func(j): return j.id)
	if not joined.is_empty():
		gs._auto_place(cards, counts, joined, true)
	# the rule's "go to work" pets nobody took: every open errand
	var left: Array = []
	var still := {}
	for pet in resting_cards():
		still[pet.uid] = true
	for uid in forced:
		if still.has(str(uid)):
			left.append(str(uid))
	if not left.is_empty():
		gs._auto_place(left, {}, [], true)


## How many pets of one count work somewhere (errands, machines and tables).
func _herd_at_places(k: String) -> int:
	var n := 0
	for job_id in gs.jobs:
		n += int(gs._job_state(job_id).herd.get(k, 0))
	var wh: Dictionary = gs.automation.get("wherd", {})
	for id in wh:
		n += int(wh[id].get(k, 0))
	return n


## Takes `n` pets of one count off wherever they work (errands first, then machines and tables), for
## an adventure that needs more of them than are resting. Returns how many it took.
func _herd_off_places(k: String, n: int) -> int:
	var want := n
	var crews := false
	for job_id in gs.jobs:
		var h: Dictionary = gs._job_state(job_id).herd
		var take := mini(n, int(h.get(k, 0)))
		if take > 0:
			Herd.take(h, k, take)
			n -= take
			crews = true
	var workers := false
	var wh: Dictionary = gs.automation.get("wherd", {})
	for id in wh:
		var take := mini(n, int(wh[id].get(k, 0)))
		if take > 0:
			Herd.take(wh[id], k, take)
			n -= take
			workers = true
	if crews:
		gs._crews_changed()
	if workers:
		gs._workers_changed()
	return want - n
