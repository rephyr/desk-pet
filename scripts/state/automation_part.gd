class_name AutomationPart
extends RefCounted
## GameState's code for automation: what your pet does for you (one job, its tools, its own crank
## and auto adventures) and working through time (also away).
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## The jobs in the automation tab: the ones that are there yet (their "needs" is open), in order.
func auto_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not gs.tab_open("automation"):
		return out
	for j in gs.catalog.automation.get("jobs", []):
		if str(j.get("needs", "")) == "" or gs.is_open(str(j.needs)):
			out.append(j)
	return out


## Whether your pet has been taught a job (bought with coins).
func knows_job(id: String) -> bool:
	return Automation.taught(gs.automation, id)


## Teaches your pet a job for its coins. If it wasn't doing anything, it starts right away.
## Returns whether it worked.
func teach_job(id: String) -> bool:
	var j := Automation.job(gs.catalog, id)
	if j.is_empty() or knows_job(id) or not auto_jobs().any(func(x): return x.id == id) or gs.coins < int(j.coins):
		return false
	gs.coins -= int(j.coins)
	gs.automation.taught[id] = true
	if gs.automation.task == "":
		gs.automation.task = id
	gs.check_unlocks()
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Puts your pet on a job it knows ("" takes it off). It only ever does one: the old one stops.
func set_task(id: String) -> void:
	if (id != "" and not knows_job(id)) or id == gs.automation.task:
		return
	gs.automation.task = id
	gs._pack_timer = 0.0
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Why a tool can't take a level now ("max", "closed"), or "".
func auto_tool_block(id: String) -> String:
	return Automation.tool_block(gs.automation, Automation.tool(gs.catalog, id))


func auto_tool_cost(id: String) -> int:
	return Automation.tool_cost(gs.automation, Automation.tool(gs.catalog, id))


## Buys a level of a job's tool. Returns whether it worked.
func buy_auto_tool(id: String) -> bool:
	var cost := auto_tool_cost(id)
	if auto_tool_block(id) != "" or gs.coins < cost:
		return false
	gs.coins -= cost
	gs.automation.tools[id] = Automation.tool_level(gs.automation, id) + 1
	gs.automation_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Where a party of the adventures job goes and how many go: { place, n }. `slot` -1 is your pet's
## party, 0 and up the workers' parties. A place that isn't open (or none picked yet) is the first
## open one that takes a party (never a dungeon: see party_places).
func auto_party(slot := -1) -> Dictionary:
	var saved: Dictionary = gs.automation.party if slot < 0 else (gs.automation.parties[slot] if slot < gs.automation.parties.size() else {})
	var place := str(saved.get("place", ""))
	if not gs.location_open(gs.catalog.location(place)):
		place = ""
		var open := gs.party_places()
		for l in open:
			if int(l.get("max_party", 0)) != 1:
				place = str(l.id)
				break
		if place == "" and not open.is_empty():
			place = str(open[0].id)
	var n := int(saved.get("n", 0))
	if n <= 0:
		n = int(Automation.job(gs.catalog, "adventures").get("party", 3))
	return { "place": place, "n": clampi(n, 1, gs.max_party(place) if place != "" else 1) }


## Changes where a party goes (the next time it sets out) and how many go.
func set_auto_party(place: String, n: int, slot := -1) -> void:
	var party := { "place": place, "n": clampi(n, 1, gs.max_party(place)) }
	if slot < 0:
		gs.automation.party = party
	elif slot < gs.automation.parties.size():
		gs.automation.parties[slot] = party
	gs.automation_changed.emit()
	gs.save_game()


## Places the adventures job can send its party, in the data's order.
func auto_places() -> Array[Dictionary]:
	return gs.open_locations()


## A party the adventures job has out (`slot` -1: your pet's, 0 and up: the workers'), or null.
func auto_run(slot := -1) -> RunState:
	for run in gs.runs:
		if run.auto and run.slot == slot:
			return run
	return null


## Your pet's jobs and its workers work up to `until` (called every second): machines crank, boxes
## get opened, parties come home and go out again. (Your pet's boxes job runs with the pack
## opening, see _open_in_background.)
func _work_automation(until: float, part := "") -> void:
	gs._hold_saves = true
	if part != "boxes":
		gs._auto_at = _work_since(gs._auto_at, until, func(sec): _work_for_automation(sec, true, part == ""))
		_auto_adventures()
	if part == "boxes":
		gs._boxes_at = _work_since(gs._boxes_at, until, func(sec): _work_for_automation(sec, true, true, false))
	elif part == "":  # the boxes were done with the rest: their clock moves on too
		gs._boxes_at = maxf(gs._boxes_at, gs._auto_at)
	_release_saves()


## Has `work` (a func taking seconds) do the time from `at` to `until`; returns the new `at`. A gap
## over 5 s is the computer asleep: it counts like time with the game closed (a hitch still counts).
func _work_since(at: float, until: float, work: Callable) -> float:
	if at <= 0.0 or until <= at:
		return maxf(at, until)
	var gap := until - at
	if gap > 5.0:
		gap = maxf(Automation.away_seconds(gs.catalog, gs.automation, gap) * gs.boost("away"), minf(gap, 60.0))
		gs._without_care(func(): work.call(gap))
	else:
		work.call(gap)
	return until


## Lets saves through again. What automation asked to save during its tick waits for the autosave
## (every 30 s, and on quit): a big save written every second was a hitch every second.
func _release_saves() -> void:
	gs._hold_saves = false


## Everything automation does in `seconds` (also time spent away, when the game loads).
## `boxes` / `rest`: only the workers' box opening, or everything else (they can run on frames apart).
func _work_for_automation(seconds: float, show: bool, boxes := true, rest := true) -> void:
	seconds *= gs.boost("automation")  # quicker at the jobs, more done in the same time (your pet's and the workers')
	if rest and gs.automation.task == "machine":
		var pulls := Automation.crank(gs.catalog, gs.automation, seconds)
		if pulls > 0:
			_pet_cranks(pulls, show)
	if rest:
		var worker_pulls := Automation.work(gs.catalog, gs.automation, "machine", gs.workers_speed("machine"), seconds)
		if worker_pulls > 0:
			_pet_cranks(worker_pulls, false)
	if boxes:
		var worker_boxes := Automation.work(gs.catalog, gs.automation, "boxes", gs.workers_speed("boxes") * gs.boost("pets"), seconds)
		if worker_boxes > 0:
			gs._workers_open(worker_boxes)
	if rest and gs.automation.task == Automation.WHISTLE:  # after what the time brought in: then it spends
		var checks := Automation.checks(gs.catalog, gs.automation, seconds)
		if checks > 0:
			gs._whistle_checks(checks)


## The adventures job: a party that's home is welcomed back quietly (what it found goes in the idle
## log), and while your pet is on the job, and for every worker leading a party, a new one sets out.
func _auto_adventures() -> void:
	for run in gs.runs.duplicate():
		if run.auto and run.status == RunState.Status.DONE:
			var stayed: Array = run.party.lost.map(func(uid): return gs.collection.get_pet(uid)).filter(func(p): return p != null) \
				.map(func(p): return p.display_name(gs.catalog))
			var trip := gs.collect_run(run)
			gs._log_idle({ "trips": 1, "coins": Rewards.total(trip.get("loot", {}), "coins") })
			if not stayed.is_empty():  # nobody goes missing without you hearing about it
				gs.announcements.append("%s stayed at %s! it must be lovely there." % [", ".join(stayed), trip.get("place", "the trip")])
	if gs.tutorial_active():
		return
	var leaders := gs.workers_of("adventures")
	var due: Array[int] = []
	if gs.automation.task == "adventures" and auto_run(-1) == null:
		due.append(-1)
	for slot in leaders.size():
		if str(leaders[slot]) != "" and auto_run(slot) == null:
			due.append(slot)
	if due.is_empty():
		return
	# who could go, worked out once: pets with nothing to do first, then ones on errands; workers
	# and good pulls you haven't seen yet stay home
	var unseen := {}
	for uid in gs.pinned:
		unseen[uid] = true
	var gone := gs.away()
	var cards: Array[Pet] = []
	for pet in gs.collection.pets:
		if pet.uid != gs.collection.active_uid and not gone.has(pet.uid):
			cards.append(pet)
	var pools: Array = [gs.resting_cards(), gs._resting_stand_ins(), cards, gs._sendable_stand_ins(gone)]
	var used := {}
	# a count only offers its first few stand-ins at a time: when the next party could run out of
	# them, fresh ones are looked up (the ones that left are away now). Looked up only then, not
	# after every party (that made hundreds of parties slow); once a look-up brings nothing new,
	# the herd has no more for this round.
	var dry := [false, false]  # resting stand-ins, sendable stand-ins
	var from := [0, 0, 0, 0]  # where each pool is looked through from (see _send_auto_party)
	for slot in due:
		var party := auto_party(slot)
		for i in 2:
			var k: int = 1 + i * 2
			if not dry[i] and _unused(pools[k], used) < int(party.n):
				var before := _unused(pools[k], used)
				pools[k] = gs._resting_stand_ins() if i == 0 else gs._sendable_stand_ins(gs.away())
				dry[i] = _unused(pools[k], used) <= before
				from[k] = 0
		_send_auto_party(slot, party, pools, from, unseen, used)


## How many pets of a pool haven't been `used` yet.
func _unused(pool: Array, used: Dictionary) -> int:
	var n := 0
	for pet: Pet in pool:
		if not used.has(pet.uid):
			n += 1
	return n


## Sends party `slot` out (from `pools` of pets, skipping `unseen` and ones `used` already; each
## pool is looked through from its place in `at`, so hundreds of parties don't go over the same
## pets again and again). Returns whether it left.
func _send_auto_party(slot: int, party: Dictionary, pools: Array, at: Array, unseen: Dictionary, used: Dictionary) -> bool:
	if str(party.place) == "":
		return false
	var party_pets: Array[Pet] = []
	for p in pools.size():
		var pool: Array = pools[p]
		var i: int = at[p]
		while i < pool.size() and party_pets.size() < int(party.n):
			var pet: Pet = pool[i]
			i += 1
			if not used.has(pet.uid) and not unseen.has(pet.uid) and not gs._worker_of.has(pet.uid):
				used[pet.uid] = true
				party_pets.append(pet)
		at[p] = i  # everyone before it is taken or stays home this round
	if party_pets.is_empty():
		return false
	var run := gs.send_on_adventure(str(party.place), party_pets, false)
	if run == null:
		return false
	run.auto = true
	run.slot = slot
	run.chooser = "policy"  # nobody waits for you: every event takes its usual pick
	gs.save_game()
	return true


## Your pet's machine gives `pulls` capsules. `show`: the tab plays the last one (not when it's
## catching up on time away). Returns everything they held.
func _pet_cranks(pulls: int, show := true) -> Dictionary:
	var total := {}
	var rolls := mini(pulls, GameStateNode.PET_CRANK_ROLLS)
	var last := {}
	var ctx := _crank_context()
	for i in rolls:
		last = _pet_capsule(ctx)
		Rewards.add(total, last.loot)
	if ctx.toys:  # once for the whole batch, not once a toy
		gs.toys_changed.emit()
		gs.check_unlocks()
	if pulls > rolls:  # the rest pay coins, xp and boxes like these (toys only come from the rolled ones)
		for key: String in total.keys():
			if key == "coins" or key == "xp" or key.begins_with("box:"):
				total[key] = GameStateNode.coins_int(float(total[key]) * (1.0 + float(pulls - rolls) / rolls))
	# everything is handed out at once: workers can pull hundreds of capsules a second
	if total.has("xp"):
		total.xp = gs.add_xp(int(total.xp))
	gs.grant(GameStateNode._without(total, "xp"), false)
	gs._log_idle({ "coins": int(total.get("coins", 0)), "boxes": Rewards.total(total, "box") })
	if show and not last.is_empty():
		gs.pet_cranked.emit(last)
	return total


## One capsule from your pet's own machine (or a worker's): like a plain one from the globe one step
## behind your hand (worth the same, shiny as often, toys too), but no lucky lights, fever or pet
## boxes: those stay with your lever. Toys are yours right away; the rest is handed out by _pet_cranks.
## `ctx` (from _crank_context) holds what every capsule of a batch shares; `ctx.toys` turns true
## when one held a toy (_pet_cranks tells everyone once).
func _pet_capsule(ctx: Dictionary) -> Dictionary:
	var prize := Machine.pick(gs.catalog, ctx.weights, gs._rng)
	if not ctx.gives.get(str(prize.kind), true) or prize.kind in ["pet", "pet_box"]:
		prize = ctx.fallback
	var shiny: bool = prize.kind in ["coins", "golden", "box", "part"] and gs._rng.randf() < ctx.shiny
	var loot := Machine.loot(prize, gs.machine, gs.catalog, gs._rng, 1.0, ctx.g, ctx.value)
	if loot.has("coins"):
		loot.coins = GameStateNode.coins_int(int(loot.coins) * ctx.coins_x)
	if shiny:
		for k in loot:
			loot[k] = GameStateNode.coins_int(float(loot[k]) * ctx.shiny_pay)
	var toy := {}
	if prize.kind == "toy":
		var t := Toys.roll(gs.catalog, gs._rng, ctx.luck, ctx.sets)
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(gs.toys, t.id, t.finish) }
		ctx.toys = true
	return { "prize": prize, "loot": loot, "shiny": shiny, "toy": toy }  # _pet_cranks hands it out


## What every capsule of one batch from your pet's machine shares: the globe one step behind your
## hand, its odds, values and the boosts, worked out once (a new toy only adds spares, so no boost
## moves halfway through).
func _crank_context() -> Dictionary:
	var g := Machine.behind(gs.machine, gs.catalog)
	var luck := gs.boost("luck")
	var gives := {}
	for p: Dictionary in gs.catalog.machine.prizes:
		gives[str(p.kind)] = gs._machine_gives(str(p.kind))
	return {
		"g": g, "luck": luck, "gives": gives, "fallback": gs._machine_prize("coins"),
		"weights": Machine.weights(gs.machine, gs.catalog, false, luck, gs.boost("toys"), 1.0, g),
		"shiny": Machine.shiny_chance(gs.machine, gs.catalog, g) * gs.boost("shiny"),
		"shiny_pay": Machine.shiny_pay(gs.machine, gs.catalog, g),
		"value": Machine.coin_value(gs.machine, gs.catalog, g), "coins_x": gs.boost("coins"),
		"sets": Machine.toy_sets(gs.machine, gs.catalog, g), "toys": false,
	}


func _load_automation(saved: Dictionary) -> void:
	gs.automation = Automation.fresh()
	for id in saved.get("taught", {}):
		if not Automation.job(gs.catalog, str(id)).is_empty():
			gs.automation.taught[str(id)] = true
	for id in saved.get("tools", {}):
		if not Automation.tool(gs.catalog, str(id)).is_empty():
			gs.automation.tools[str(id)] = maxi(0, int(saved.tools[id]))
	var task := str(saved.get("task", ""))  # set once the whistle is known too (below)
	var party: Dictionary = saved.get("party", {})
	gs.automation.party = { "place": str(party.get("place", "")), "n": int(party.get("n", 0)) }
	gs.automation.fill = clampf(float(saved.get("fill", 0.0)), 0.0, 1.0)
	for id in saved.get("others", {}):
		if gs.automation.taught.has(str(id)):
			gs.automation.others[str(id)] = true
	for id in saved.get("spots", {}):
		if not Automation.job(gs.catalog, str(id)).is_empty():
			gs.automation.spots[str(id)] = maxi(0, int(saved.spots[id]))
	for p in saved.get("parties", []):
		if p is Dictionary and gs.automation.parties.size() < Automation.spots(gs.automation, "adventures"):
			gs.automation.parties.append({ "place": str(p.get("place", "")), "n": int(p.get("n", 0)) })
	while gs.automation.parties.size() < Automation.spots(gs.automation, "adventures"):
		gs.automation.parties.append({ "place": "", "n": 0 })
	# workers: pets you still have, not your active pet, not away or in the army, one job each, one per spot
	var on_trips := gs._out()
	var placed := {}
	for id in saved.get("workers", {}):
		var list: Array = []
		for raw in saved.workers[id]:
			var uid := str(raw)
			if list.size() >= Automation.spots(gs.automation, str(id)):
				break
			if gs.collection.get_pet(uid) != null and uid != gs.collection.active_uid and not on_trips.has(uid) and not placed.has(uid) and not gs._job_of.has(uid):
				list.append(uid)
				placed[uid] = true
			elif str(id) == "adventures":
				list.append("")  # that party waits for a new leader
		gs.automation.workers[str(id)] = list
	for id in saved.get("wfill", {}):
		gs.automation.wfill[str(id)] = clampf(float(saved.wfill[id]), 0.0, 1.0)
	# the whistle (v27: older saves start with every tick on and the default set aside)
	var w = saved.get("whistle", {})
	if not w is Dictionary:  # a broken save ("whistle": null): the defaults
		w = {}
	var ticks := {}
	var saved_ticks = w.get("ticks", {})
	if not saved_ticks is Dictionary:
		saved_ticks = {}
	for id in saved_ticks:
		if saved_ticks[id] is Dictionary and not Automation.job(gs.catalog, str(id)).is_empty():
			var t := {}
			for key in ["haul", "fill"]:
				if saved_ticks[id].has(key):
					t[key] = bool(saved_ticks[id][key])
			ticks[str(id)] = t
	gs.automation.whistle = { "ticks": ticks, "keep": maxi(-1, int(w.get("keep", -1))), "wait": clampf(float(w.get("wait", 0.0)), 0.0, 1.0) }
	if gs.is_unlocked("feature:" + Automation.WHISTLE):
		gs.automation.taught[Automation.WHISTLE] = true
	gs.automation.task = task if gs.automation.taught.has(task) else ""
	var saved_wjoin = saved.get("wjoin", {})
	if saved_wjoin is Dictionary:
		for id in saved_wjoin:
			if str(id) != "adventures" and gs.automation.others.has(str(id)) and bool(saved_wjoin[id]):
				gs.automation.wjoin[str(id)] = true
	# workers from the herd: counts, as many as the spots still have room for (never adventures)
	var saved_wherd = saved.get("wherd", {})
	if not saved_wherd is Dictionary:
		saved_wherd = {}
	for id in saved_wherd:
		if str(id) == "adventures" or Automation.job(gs.catalog, str(id)).is_empty():
			continue
		var space: int = Automation.spots(gs.automation, str(id)) - gs.automation.workers.get(str(id), []).size()
		var counts := Herd.clean_counts(gs.catalog, saved_wherd[id])
		for k in counts.keys():
			counts[k] = mini(int(counts[k]), maxi(0, space))
			space -= int(counts[k])
			if int(counts[k]) <= 0:
				counts.erase(k)
		if not counts.is_empty():
			gs.automation.wherd[str(id)] = counts
	gs._worker_of.clear()
	gs._worker_speed.clear()
	for id in gs.automation.workers:
		for uid in gs.automation.workers[id]:
			if str(uid) != "":
				gs._worker_of[uid] = id
