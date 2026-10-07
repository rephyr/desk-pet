class_name ErrandsPart
extends RefCounted
## GameState's code for errands: the jobs, their crews, meters, tools, levels and pay.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Errands work up to `until` (called every second).
func _work_jobs(until: float) -> void:
	if until > gs._jobs_at and gs._jobs_at > 0.0:
		var gap := until - gs._jobs_at
		if gap > 5.0:  # the computer slept: time away counts like time with the game closed
			var e: Dictionary = gs.catalog.errands
			gap = Jobs.offline_seconds(gap, errands_away_hours(), float(e.offline_after), GameStateNode.OFFLINE_CAP) * gs.boost("away")
			gs._without_care(_work_for.bind(gap))
		else:
			_work_for(gap)
	gs._jobs_at = maxf(gs._jobs_at, until)


## Every errand works for `seconds`: full meters pay (into your wallet and bag). Returns the loot.
func _work_for(seconds: float) -> Dictionary:
	var total := {}
	if not gs.feature_on("errands") or gs.tutorial_active():
		return total
	for job in open_jobs():
		var size := job_size(job.id)
		if size == 0 or (job.has("scout") and scout_full()):
			continue  # nobody on it, or the scouts' notes are all waiting for trips
		var got := Jobs.work(job, gs.jobs[job.id], size, job_rate(job.id), seconds, gs._rng, gs.catalog, job_boost(job.id))
		if got.fills > 0:
			if got.loot.has("coins"):
				got.loot.coins = GameStateNode.coins_int(int(got.loot.coins) * gs.boost("coins"))  # shown as it lands
			if got.loot.has("meal"):  # the kitchen fed your pet (up to its "meal_upto")
				var fed := Jobs.feed(job, gs.hunger, gs.happiness, int(got.loot.meal) / maxi(1, int(job.pay.meal)))
				gs.hunger = fed.food
				gs.happiness = fed.mood
				gs._check_care()
				got.loot.meal = roundi(fed.eaten)  # 0: it wasn't hungry enough, nothing to show
			if got.loot.has("note"):  # the scouts wrote notes, as many as fit
				got.loot.note = mini(int(got.loot.note), scout_hold() - gs.scout_notes)
				gs.scout_notes += int(got.loot.note)
			gs.job_paid.emit(job.id, got.loot)
			got.loot.erase("meal")
			got.loot.erase("note")
			Rewards.add(total, got.loot)
	if not total.is_empty():
		gs.grant(total, false)
		gs._log_idle({ "coins": Rewards.total(total, "coins"), "parts": Rewards.total(total, "part") })
	return total


## Scout notes you can hold (the scouting errand's hold, and a map case holds more).
func scout_hold() -> int:
	return Jobs.scout_hold(gs.catalog, gs.errand_tools)


## Whether you hold all the scout notes you can (the scouting meter waits, full).
func scout_full() -> bool:
	return gs.scout_notes >= scout_hold()


## Sets the scout notes you hold (the dev driver's "notes" step).
func set_scout_notes(n: int) -> void:
	gs.scout_notes = clampi(n, 0, scout_hold())
	gs.jobs_changed.emit()
	gs.changed.emit()


## The errands you can put pets on: every job whose "needs" is open (data/errands.json).
func open_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for job in gs.catalog.jobs:
		if str(job.get("needs", "")) == "" or gs.is_unlocked(str(job.needs)):
			out.append(job)
	return out


## The sum of `f(uid)` over a job's crew cards, kept in `cache` (job id -> { n, first, last, sum })
## and only added to while pets join the end of the crew: late in the game thousands of cards work
## an errand and new ones join every second (each pet's value is kept too, for when pets leave).
## Clear `cache` when what `f` gives changes.
func _crew_sum(cache: Dictionary, job_id: String, f: Callable) -> float:
	var crew := job_crew(job_id)
	var c: Dictionary = cache.get(job_id, {})
	var vals: Dictionary = c.get("vals", {})  # uid -> f(uid): pets leaving mid-crew only cost lookups
	var from := 0
	var sum := 0.0
	var n := int(c.get("n", 0))
	if n > 0 and crew.size() >= n and str(crew[0]) == c.first and str(crew[n - 1]) == c.last:
		from = n
		sum = float(c.sum)
	elif vals.size() > crew.size() * 2:
		vals.clear()  # mostly pets long gone
	for i in range(from, crew.size()):
		var uid := str(crew[i])
		var v: Variant = vals.get(uid)
		if v == null:
			v = f.call(uid)
			vals[uid] = v
		sum += v
	if crew.is_empty():
		cache.erase(job_id)
	else:
		cache[job_id] = { "n": crew.size(), "first": str(crew[0]), "last": str(crew[-1]), "sum": sum, "vals": vals }
	return sum


## The uids of the cards on an errand (its pets from the herd are counts, see job_herd).
func job_crew(job_id: String) -> Array:
	return gs.jobs.get(job_id, {}).get("crew", [])


## The pets from the herd on an errand: count key -> how many.
func job_herd(job_id: String) -> Dictionary:
	return gs.jobs.get(job_id, {}).get("herd", {})


## How many pets are on an errand: cards and counts.
func job_size(job_id: String) -> int:
	return job_crew(job_id).size() + Herd.total(job_herd(job_id))


## Up to `n` of an errand's pets to show (polaroids, piles, crowds): uids of its cards first,
## then stand-ins for its counts.
func job_faces(job_id: String, n: int) -> Array:
	return gs._faces(job_crew(job_id), job_herd(job_id), n, maxi(0, gs.catalog.jobs.find(gs.catalog.job(job_id))))


## An errand's state, made if it has none yet.
func _job_state(job_id: String) -> Dictionary:
	if not gs.jobs.has(job_id):
		gs.jobs[job_id] = { "crew": [], "herd": {}, "fill": 0.0, "join": false }
	if not gs.jobs[job_id].has("herd"):
		gs.jobs[job_id].herd = {}
	return gs.jobs[job_id]


## Which errand a pet is on, or "".
func job_of(uid: String) -> String:
	return str(gs._job_of.get(uid, ""))


## How full an errand's meter is, 0 to 1.
func job_fill(job_id: String) -> float:
	return float(gs.jobs.get(job_id, {}).get("fill", 0.0))


## How full an errand's meter is right now, between the once-a-second ticks (for drawing it).
func job_fill_now(job_id: String) -> float:
	if gs.catalog.job(job_id).has("scout") and scout_full() and job_size(job_id) > 0:
		return 1.0  # full, waiting for a trip to take a note
	var since := maxf(0.0, Time.get_unix_time_from_system() - gs._jobs_at) if gs._jobs_at > 0.0 else 0.0
	return fposmod(job_fill(job_id) + job_rate(job_id) * since, 1.0)


## How many times a second an errand's meter fills with its crew now.
func job_rate(job_id: String) -> float:
	return _job_plain_rate(job_id, true) * _job_errands_x(job_id)


## The shared "errands" boost on one job: the kitchen, the book's errands stickers, toys, knacks
## (the cooks don't speed up their own kitchen).
func _job_errands_x(job_id: String) -> float:
	var x := gs.boost("errands")
	if gs.catalog.job(job_id).has("kitchen"):
		x /= 1.0 + kitchen_bonus()
	return x


## How many times a second an errand's meter fills before the shared boosts, with or without the
## tools (for the errands' "why so much?").
func _job_plain_rate(job_id: String, with_tools: bool) -> float:
	var size := job_size(job_id)
	if size == 0:
		return 0.0
	var job := gs.catalog.job(job_id)
	if not gs._job_speed.has(job_id):
		var sum := _crew_sum(gs._crew_speeds, job_id, func(uid: String) -> float: return _speed_of(uid, job))
		var h := job_herd(job_id)
		for k in h:
			sum += Jobs.pet_speed(Herd.template(gs.catalog, k), job) * int(h[k])
		gs._job_speed[job_id] = sum / size
	var tools := _job_tool_numbers(job_id) if with_tools else [float(gs.catalog.errands.crew_power), 1.0, 0.0]
	return Jobs.rate(job, size, gs._job_speed[job_id], tools[0], tools[2]) * tools[1]


## What the tools do to a job's speed: [crew power, speed, the tools' own crew power] (per frame,
## so kept).
func _job_tool_numbers(job_id: String) -> Array:
	if not gs._job_tools.has(job_id):
		gs._job_tools[job_id] = [float(gs.catalog.errands.crew_power) + Jobs.tool_sum(gs.catalog, job_id, "crew_power", gs.errand_tools),
			1.0 + Jobs.tool_sum(gs.catalog, job_id, "speed", gs.errand_tools) + Jobs.tool_sum(gs.catalog, job_id, "all_speed", gs.errand_tools),
			Jobs.tool_sum(gs.catalog, job_id, "crew_power", gs.errand_tools)]
	return gs._job_tools[job_id]


## The kitchen's cooks or the other crews changed: its bonus (a boost source) is worked out again.
func _kitchen_changed() -> void:
	gs._kitchen = -1.0
	gs._boosts_changed()


## How much faster the kitchen's cooks make every other job (0.12 = 12% faster), see Jobs.kitchen_bonus.
## It's the `kitchen` source of the "errands" boost (see boost_parts).
func kitchen_bonus() -> float:
	if gs._kitchen >= 0.0:
		return gs._kitchen
	gs._kitchen = 0.0
	for job in open_jobs():
		if not job.has("kitchen") or job_size(job.id) == 0:
			continue
		var cooks := 0.0
		for uid in job_crew(job.id):
			cooks += _speed_of(uid, job)
		var h := job_herd(job.id)
		for k in h:
			cooks += Jobs.pet_speed(Herd.template(gs.catalog, k), job) * int(h[k])
		var others := 0
		for job_id in gs.jobs:
			if job_id != job.id:
				others += job_size(job_id)
		var power := float(gs.catalog.errands.crew_power) + Jobs.tool_sum(gs.catalog, "", "crew_power", gs.errand_tools)
		gs._kitchen = Jobs.kitchen_bonus(job, cooks, others, power)
	return gs._kitchen


## Coins in a plain capsule on the machine now, at the globe one step behind your hand (Machine.behind):
## what errands pay in, and what errand tools, boxes, the reserve and snacks are priced in.
func capsule_value() -> float:
	return Machine.coin_value(gs.machine, gs.catalog, Machine.behind(gs.machine, gs.catalog))


## What an errand's "capsules" pay is worth now (see Jobs.pay): a capsule's coins on the machine,
## the tools' extra capsules, its goals, its crew's tips, big finds and shiny ones.
## Without the tools, goals or tips: that layer left out (for the errands' "why so much?").
func job_boost(job_id: String, with_tools := true, with_goals := true, with_tips := true) -> Dictionary:
	var job := gs.catalog.job(job_id)
	var shiny := with_tools and Jobs.tool_sum(gs.catalog, job_id, "shiny", gs.errand_tools) > 0.0
	var g := Machine.behind(gs.machine, gs.catalog)  # errands pay at the globe one step behind your hand
	return { "coin_value": capsule_value(),
		"worth": Jobs.tool_sum(gs.catalog, job_id, "worth", gs.errand_tools) if with_tools else 0.0,
		"x": (Jobs.goal_x(job, job_level(job_id)) if with_goals else 1.0) * (job_tips(job_id, with_tools) if with_tips else 1.0),
		"big": Jobs.tool_sum(gs.catalog, job_id, "big", gs.errand_tools) if with_tools else 0.0, "big_x": float(gs.catalog.errands.get("big_x", 5)),
		"shiny": Machine.shiny_chance(gs.machine, gs.catalog, g) * gs.boost("shiny") if shiny else 0.0, "shiny_pay": Machine.shiny_pay(gs.machine, gs.catalog, g) }


## A job with "tips" pays by its crew's rarity: their average tip (1 for jobs without tips). Fancy
## cups make rare-or-better pets' tips count more (`with_tools` false: the tips without the cups).
func job_tips(job_id: String, with_tools := true) -> float:
	var job := gs.catalog.job(job_id)
	var size := job_size(job_id)
	if not job.has("tips") or size == 0:
		return 1.0
	var key := job_id if with_tools else job_id + "|plain"
	if not gs._job_tip.has(key):
		var rare_x := maxf(1.0, Jobs.tool_sum(gs.catalog, job_id, "rare_x", gs.errand_tools)) if with_tools else 1.0
		var tip := func(rarity: String) -> float:
			return float(job.tips.get(rarity, 1.0)) * (rare_x if gs.catalog.rank(rarity) >= 2 else 1.0)
		var tips: Dictionary = gs._crew_tips.get_or_add(key, {})
		var sum := _crew_sum(tips, job_id, func(uid: String) -> float:
			var pet := gs.collection.get_pet(uid)
			return tip.call(pet.rarity if pet else "common"))
		var h := job_herd(job_id)
		for k in h:
			sum += tip.call(Herd.rarity_of(k)) * int(h[k])
		gs._job_tip[key] = sum / size
	return gs._job_tip[key]


## Coins a minute from every coin-bringing errand with its crew now, on average.
func errands_per_minute() -> float:
	return gs._errands_layered(true, true, true, true) * gs.boost("coins")


## The coins a minute if a tool had `n` more levels (the upgrades card's "before → after").
func errands_per_minute_with(id: String, n: int) -> float:
	var real := gs.errand_tools
	gs.errand_tools = real.duplicate()
	gs.errand_tools[id] = errand_tool_level(id) + n
	_tools_changed()
	var out := errands_per_minute()
	gs.errand_tools = real
	_tools_changed()
	return out


## How often a job would fill if a tool had `n` more levels (the upgrades card, for jobs that
## bring no coins).
func job_rate_with(job_id: String, id: String, n: int) -> float:
	var real := gs.errand_tools
	gs.errand_tools = real.duplicate()
	gs.errand_tools[id] = errand_tool_level(id) + n
	_tools_changed()
	var out := job_rate(job_id)
	gs.errand_tools = real
	_tools_changed()
	return out


## Sets a tool's level outright (the dev driver's "tool" step).
func set_errand_tool_level(id: String, level: int) -> void:
	gs.errand_tools[id] = maxi(0, level)
	_tools_changed()
	gs.check_unlocks()
	gs.jobs_changed.emit()
	gs.changed.emit()


## The tools changed: what they do to each job is worked out again.
func _tools_changed() -> void:
	gs._job_tools.clear()
	gs._job_tip.clear()
	gs._crew_tips.clear()
	_kitchen_changed()


## Hours errands work at full speed while you're away (comfy naps add more).
func errands_away_hours() -> float:
	return float(gs.catalog.errands.offline_full_hours) + Jobs.tool_sum(gs.catalog, "", "away_hours", gs.errand_tools)


## A job's level: all its tools' levels added up.
func job_level(job_id: String) -> int:
	return Jobs.level(gs.catalog.job(job_id), gs.errand_tools)


func errand_tool_level(id: String) -> int:
	return int(gs.errand_tools.get(id, 0))


## Why a tool can't take another level now ("" if it can, coins aside), see Jobs.tool_block.
func errand_tool_block(id: String) -> String:
	var tool := Jobs.tool(gs.catalog, id)
	if tool.is_empty():
		return "closed"
	var job_open: bool = tool.job == "" or open_jobs().any(func(j): return j.id == tool.job)
	return Jobs.tool_block(gs.catalog, tool, gs.errand_tools, gs.machine, job_open)


## How many levels of a tool `n` buys right now (n -1: as many as you can afford, at least 1)
## and what they cost: [levels, coins].
func errand_tool_plan(id: String, n: int) -> Array:
	var tool := Jobs.tool(gs.catalog, id)
	var have := errand_tool_level(id)
	var levels_left := Jobs.tool_room(tool, have)
	var value := capsule_value()
	if n < 0:
		var base := Jobs.tool_base(tool, value)
		var k := 0
		var cost := 0.0
		while k < mini(levels_left, 1000):
			cost += base * pow(float(tool.get("grow", 1.0)), have + k)
			if cost > gs.coins:
				break
			k += 1
		n = maxi(1, k)
	n = mini(n, levels_left)
	return [n, Jobs.tool_cost(tool, have, n, value)]


## Buys `n` levels of an errand tool (-1: as many as you can afford). Returns the levels bought.
func buy_errand_tool(id: String, n := 1) -> int:
	if Jobs.tool(gs.catalog, id).is_empty() or errand_tool_block(id) != "":
		return 0
	var plan := errand_tool_plan(id, n)
	if plan[0] <= 0 or gs.coins < plan[1]:
		return 0
	gs.coins -= plan[1]
	gs.errand_tools[id] = errand_tool_level(id) + plan[0]
	_tools_changed()
	gs.check_unlocks()  # a job's level may open something (the lemonade stand)
	gs.jobs_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return plan[0]


## Puts resting pets on an errand: these uids (a stand-in's uid means one from its count), or the
## `count` best at it (-1: everyone resting), cards and pets from the herd alike.
func put_on_job(job_id: String, count := 1, uids: Array = []) -> void:
	if not open_jobs().any(func(j): return j.id == job_id) or not gs.feature_on("errands"):
		return
	var cards: Array = []
	var counts := {}
	var named := ""  # the exact pet you tapped, for your pet to name
	if not uids.is_empty():
		var ok := {}
		for pet in gs.resting_cards():
			ok[pet.uid] = true
		var free := gs.resting_herd().duplicate()
		for raw in uids:
			var uid := str(raw)
			if Herd.is_stand_in(uid):
				var k := Herd.key_of(uid)
				if int(free.get(k, 0)) > 0:
					Herd.take(free, k, 1)
					Herd.put(counts, k, 1)
					named = uid
			elif ok.has(uid):
				ok.erase(uid)
				cards.append(uid)
				named = uid
	else:
		var job := gs.catalog.job(job_id)
		var picked := gs._pick(gs.resting_cards(), gs.resting_herd(), count, func(p: Pet): return _pet_speed(p, job), true)
		cards = picked[0]
		counts = picked[1]
	if cards.is_empty() and counts.is_empty():
		return
	var state := _job_state(job_id)
	state.crew.append_array(cards)
	for k in counts:
		Herd.put(state.herd, k, int(counts[k]))
	gs.last_moved = _moved_name(named, cards, counts)
	_crews_changed()


## Sends pets on an errand home to rest: these uids (a stand-in's uid: one from its count), or the
## `count` slowest at it (-1: all). Returns how many went home.
func take_off_job(job_id: String, count := 1, uids: Array = []) -> int:
	if job_size(job_id) == 0:
		return 0
	var state := _job_state(job_id)
	var cards: Array = []
	var counts := {}
	var named := ""  # the exact pet you tapped, for your pet to name
	if not uids.is_empty():
		var crew := {}
		for uid in state.crew:
			crew[uid] = true
		var h: Dictionary = state.herd.duplicate()
		for raw in uids:
			var uid := str(raw)
			if Herd.is_stand_in(uid):
				var k := Herd.key_of(uid)
				if int(h.get(k, 0)) > 0:
					Herd.take(h, k, 1)
					Herd.put(counts, k, 1)
					named = uid
			elif crew.has(uid):
				crew.erase(uid)
				cards.append(uid)
				named = uid
	else:
		var job := gs.catalog.job(job_id)
		var crew_pets: Array = []
		for uid in state.crew:
			var pet := gs.collection.get_pet(uid)
			if pet:
				crew_pets.append(pet)
		var picked := gs._pick(crew_pets, state.herd, count, func(p: Pet): return _pet_speed(p, job), false)
		cards = picked[0]
		counts = picked[1]
	var n := cards.size()
	for k in counts:
		Herd.take(state.herd, k, int(counts[k]))
		n += int(counts[k])
	if n == 0:
		return 0
	gs.last_moved = _moved_name(named, cards, counts)
	if cards.is_empty() or _take_off(cards).is_empty():
		_crews_changed()
	return n


## Who your pet names after a move: the pet you tapped, else the last card, else a face for the count.
func _moved_name(named: String, cards: Array, counts: Dictionary) -> String:
	if named != "":
		return named
	if not cards.is_empty():
		return str(cards[-1])
	return gs.collection.stand_in_uids(str(counts.keys()[-1]), 1)[0]


## Spreads every resting pet over the errands: the smallest crews fill up first.
func share_out() -> void:
	_auto_place(gs.resting_cards().map(func(p): return p.uid), gs.resting_herd().duplicate())


## "New pets join here" on an errand: new pets (from boxes, gifts, pets home from adventures) start
## on it (see _place_new).
func set_job_join(job_id: String, on: bool) -> void:
	if not open_jobs().any(func(j): return j.id == job_id and Jobs.shared_out(j)):  # you staff the kitchen and scouting
		return
	_job_state(job_id).join = on
	gs.jobs_changed.emit()
	gs.changed.emit()
	gs.save_game()


func job_joins(job_id: String) -> bool:
	if Workshop.has(gs.workshop, "chart"):
		return true  # the chore chart: every errand
	return bool(gs.jobs.get(job_id, {}).get("join", false))


## Puts these pets (the resting ones; a stand-in's uid is one from its count) and `counts` more from
## the resting herd on the errands with the smallest crews (only the errands in `only`, if given).
## `by_themselves`: new pets joining on their own (see crews_by_themselves).
func _auto_place(uids: Array, counts := {}, only: Array = [], by_themselves := false) -> void:
	var open := open_jobs().filter(func(j): return Jobs.shared_out(j))  # not the kitchen or scouting: you staff those
	if not only.is_empty():
		open = open.filter(func(j): return j.id in only)
	if not gs.feature_on("errands") or gs.tutorial_active() or open.is_empty():
		return
	var resting := {}
	for pet in gs.resting_cards():
		resting[pet.uid] = true
	var free := gs.resting_herd()
	var sizes := {}
	for job in open:
		sizes[job.id] = job_size(job.id)
	var more := counts.duplicate()
	var placed := false
	var joined := {}  # cards put on a crew: uid -> job id
	for raw in uids:
		var uid := str(raw)
		if Herd.is_stand_in(uid):
			Herd.put(more, Herd.key_of(uid), 1)
			continue
		if not resting.has(uid):
			continue
		resting.erase(uid)
		var smallest: String = sizes.keys()[0]
		for id in sizes:
			if int(sizes[id]) < int(sizes[smallest]):
				smallest = id
		_job_state(smallest).crew.append(uid)
		joined[uid] = smallest
		sizes[smallest] = int(sizes[smallest]) + 1
		placed = true
	for k in more:
		var adds := GameStateNode.water_fill(sizes, mini(int(more[k]), int(free.get(k, 0))))
		for id in adds:
			if int(adds[id]) > 0:
				Herd.put(_job_state(id).herd, k, int(adds[id]))
				sizes[id] = int(sizes[id]) + int(adds[id])
				placed = true
	if placed:
		gs.crews_by_themselves = by_themselves
		_crews_changed(joined)
		gs.crews_by_themselves = false


func _take_off(uids: Array) -> Array:
	var gone := {}
	for uid in uids:
		if gs._job_of.has(uid):
			gone[uid] = true
	if gone.is_empty():
		return []
	for job_id in gs.jobs:
		gs.jobs[job_id].crew = gs.jobs[job_id].crew.filter(func(uid): return not gone.has(uid))
	_crews_changed()
	return gone.keys()


func _speed_of(uid: String, job: Dictionary) -> float:
	return _pet_speed(gs.collection.get_pet(uid), job)


## How fast a pet works an errand: its own speed times its own errand knacks (1.0 for nobody).
func _pet_speed(pet: Pet, job: Dictionary) -> float:
	return Jobs.pet_speed(pet, job) * gs.knack_own(pet, "errands") if pet else 1.0


## A crew changed: the lookups are worked out again, and the tab redraws. `joined` (uid -> job id,
## or null): only these cards joined crews and nothing left, so only they are looked up (thousands
## of cards are on crews late on).
func _crews_changed(joined: Variant = null) -> void:
	gs._rest_changed()
	if joined == null:
		gs._job_of.clear()
		for job_id in gs.jobs:
			for uid in gs.jobs[job_id].crew:
				gs._job_of[uid] = job_id
		# pets may have left from anywhere in a crew: the crew sums count again (from their kept values)
		for c in gs._crew_speeds.values():
			c.n = 0
		for tips in gs._crew_tips.values():
			for c in tips.values():
				c.n = 0
	else:
		gs._job_of.merge(joined, true)
	gs._job_speed.clear()
	gs._job_tip.clear()
	gs._job_tools.clear()
	_kitchen_changed()  # the kitchen's bonus depends on the crews
	gs.jobs_changed.emit()
	gs.changed.emit()
