extends RefCounted
## One pretend player through a fresh game, for tools/pace.gd. It plays the game's own GameState
## (scripts/game_state.gd, made here and never added to the tree, so its _process never runs) and
## calls the same functions the tabs call: pull_lever, buy_machine_upgrade, send_on_adventure,
## collect_run, put_on_job, buy_errand_tool, buy_gear, teach_job, buy_auto_tool, teach_others,
## buy_spots, put_workers, buy_boxes, open_boxes, rummage, feed. Unlocks, the tutorial, goals, tips,
## the kitchen, scout notes, gear on trips, pet boxes and the intel scrap all run through the game.
##
## Only the clock is the sim's: GameState reads the real time, so the sim keeps its own (1 s ticks)
## and moves timestamps onto it by hand (trips, fever, rummage), and runs errands with
## _work_for(seconds). A few rules ARE copied here and have to be kept in step with GameState by hand
## (if they change, the numbers drift without any error):
##   _automation: the lines of GameState._work_for_automation (so your pet and the workers count apart,
##     book stickers included)
##   _zoom: GameState._zoom_runs (treats on the trail)
##   _passive: the coin and hunger/happiness decay part of GameState._process
## Saving is off (a scratch save path), and the game starts fresh.
##
## Styles: "steady" pulls the lever nonstop, keeps a party out, answers every event and spends
## at once; "casual" pulls one pull in four and only checks in every 5 minutes.

const LEVER_SECONDS := 0.9  # a pull of the lever before the capsules drop (as tools/machine_pace.gd)
const SAVE_FOR_MINUTES := 10.0  # the player saves up for a gate buy this many minutes of income away
const PAYBACK_MAX := 60.0  # other buys only when they pay back within this many minutes
const BOXES_PER_MINUTE := 50  # how many boxes a player buys and rips open a minute (the boxes tab's "open 50")
const MAX_PETS := 3000  # the sim stops buying boxes here (keeps it quick; the report says so)
const REBALANCE_EVERY := 300.0  # seconds between moving every errand pet round again
const WINDOW := 600.0  # seconds per row of the coins-a-minute table
const GATE_NODES := ["chute2"]  # machine nodes off the repair/drops branches that still count as gates
const SOURCES := ["lever", "errands", "adventures", "auto trips", "pet crank", "workers", "rummage", "passive"]

var style := "steady"
var treats := false  # the player also tosses every treat on its own trips (GameState.toss_treat, the pouch counts)
var gs  # GameState
var catalog: Catalog
var t := 0.0  # sim seconds since the start
var epoch := 0.0  # the unix time sim second 0 stands for

var milestones := {}  # what -> sim minute it first happened
var windows: Array[Dictionary] = []  # one per WINDOW: { minute, per_min: { source: coins/min }, errands: { job: coins/min }, coins, pets, xp, bits, trips }
var spent := {}  # what coins went on: machine, errand tools, automation, boxes, food
var gates := {}  # gate name -> { seen, ready (bits in hand), bought } in sim seconds
var buys := {}  # what was bought -> times (for the report)

var _earned := {}  # source -> coins this window
var _errand_earned := {}  # job id -> coins this window
var _recent: Array[float] = []  # coins earned in each of the last 120 seconds (income estimate)
var _recent_i := 0
var _fever_end := 0.0  # sim second the machine's fever ends
var _rummage_at := {}  # spot id -> sim second it's full again
var _coin_timer := 0.0
var _next_pull := 0.0
var _next_decide := 0.0
var _next_rebalance := 0.0
var _next_care := 0.0
var _jobs_open := 0
var _boxes_left := 0.0  # boxes the player still has time for this minute
var _last_boxes := 0.0
var lost := 0  # pets that stayed behind on trips
var _party_minutes := 0.0  # auto party minutes seen, for guessing what one more party is worth
var _party_coins := 0.0
var _seen_unlocks := {}
var _seen_finds := {}
var _treat := {}  # RunState -> { zoom_until, ready_at } in sim seconds, as GameState._treats


func _init(p_style: String, rng_seed: int) -> void:
	style = p_style
	catalog = Catalog.shared()
	for id in GATE_NODES:
		if Machine.node(catalog, id).is_empty():
			push_error("pace_player: gate node %s is not in data/machine_tree.json" % id)
	gs = load("res://scripts/game_state.gd").new()
	gs._can_save = false
	var scratch := DevProfile.path("pace-scratch.json")
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	gs.save_path = scratch
	gs.debug_new_game()  # copies the scratch file aside first (removed again by pace.gd)
	gs._rng.seed = rng_seed
	gs._roller = PetRoller.new(catalog, gs._rng)
	epoch = Time.get_unix_time_from_system()
	gs.job_paid.connect(func(job_id: String, loot: Dictionary):
		var c := int(loot.get("coins", 0))
		_errand_earned[job_id] = int(_errand_earned.get(job_id, 0)) + c
		_earn("errands", c))  # _work_for's grant adds these coins right after
	_recent.resize(120)
	_recent.fill(0.0)
	for s in catalog.rummage_spots:
		_rummage_at[s.id] = 0.0


func free_game() -> void:
	gs.free()


# ---- the loop ---------------------------------------------------------------------------

func play(minutes: float) -> void:
	var end := minutes * 60.0
	var checks_every := 5.0 if style == "steady" else 300.0  # steady: every 15 s after half an hour (crews get big)
	while t < end:
		t += 1.0
		_recent_i = (_recent_i + 1) % _recent.size()
		_recent[_recent_i] = 0.0
		_lever()
		_passive()
		gs._work_for(1.0)
		_automation()
		_trips(style == "steady" or t >= _next_decide)
		if t >= _next_decide:
			_next_decide = t + (checks_every if t < 1800.0 or style != "steady" else 15.0)
			_decide()
		_notice()
		if fmod(t, WINDOW) == 0.0:
			_close_window()
	_notice()


func _lever() -> void:
	var period: float = LEVER_SECONDS + gs.capsule_seconds()
	if style == "casual":
		period *= 4.0
	while _next_pull <= t:
		_next_pull += period
		var real := Time.get_unix_time_from_system()
		gs.fever_until = real + (_fever_end - t) if _fever_end > t else 0.0
		var c0: int = gs.coins
		var result: Dictionary = gs.pull_lever()
		_earn("lever", gs.coins - c0)
		if result.lucky:
			_fever_end = t + (gs.fever_until - real)


## The passive coin (GameState._process): one every COIN_INTERVAL at full care, slower when your
## pet is hungry or sad. The player feeds and pats it now and then.
func _passive() -> void:
	gs.hunger = maxf(gs.STAT_FLOOR, gs.hunger - gs.HUNGER_DECAY)
	gs.happiness = maxf(gs.STAT_FLOOR, gs.happiness - gs.HAPPY_DECAY)
	_coin_timer += lerpf(0.4, 1.0, (gs.happiness + gs.hunger) / 200.0)
	if _coin_timer >= gs.COIN_INTERVAL:
		_coin_timer -= gs.COIN_INTERVAL
		gs.coins += 1
		_earn("passive", 1)


## What GameState._work_for_automation does in a second, split so your pet's crank and the
## workers count apart; then the adventures job (its new parties moved onto the sim's clock).
func _automation() -> void:
	var a: Dictionary = gs.automation
	if a.task == "machine":
		var pulls := Automation.crank(catalog, a, gs.boost("automation"))  # automation speed: the book's stickers, toys, knacks
		if pulls > 0:
			var c0: int = gs.coins
			gs._pet_cranks(pulls, false)
			_earn("pet crank", gs.coins - c0)
	var wp := Automation.work(catalog, a, "machine", gs.workers_speed("machine"), gs.boost("automation"))
	if wp > 0:
		var c0: int = gs.coins
		gs._pet_cranks(wp, false)
		_earn("workers", gs.coins - c0)
	var wb := Automation.work(catalog, a, "boxes", gs.workers_speed("boxes"), gs.boost("automation"))
	if wb > 0:
		gs._workers_open(wb)
	if a.task == "boxes":
		gs._open_in_background(1.0)
	var real := Time.get_unix_time_from_system()
	var before: Array = gs.runs.duplicate()
	var c0: int = gs.coins
	gs._auto_adventures()
	_earn("auto trips", gs.coins - c0)
	for run in gs.runs:
		if not run in before:
			_shift(run, real)
	for run in gs.runs:
		if run.auto:
			_party_minutes += 1.0 / 60.0


## A trip set off on the real clock: move it onto the sim's.
func _shift(run: RunState, real: float) -> void:
	var d := epoch + t - real
	run.started += d
	run.next_at += d


func _trips(here: bool) -> void:
	var now := epoch + t
	for run: RunState in gs.runs.duplicate():
		if run.status == RunState.Status.DONE:
			continue
		if treats and not run.auto:
			_zoom(run, now)
		AdventureRunner.resolve(run, Chooser.for_run(run), now, catalog)
		for i in 10:
			if run.status != RunState.Status.WAITING or run.auto or not here:
				break
			run.answer = _sensible(run)
			AdventureRunner.resolve(run, Chooser.for_run(run), now, catalog)
	if not here:
		return
	for run: RunState in gs.runs.duplicate():
		if run.auto or run.status != RunState.Status.DONE:
			continue
		var c0: int = gs.coins
		lost += run.party.lost.size()
		_treat.erase(run)
		gs.collect_run(run)
		_earn("adventures", gs.coins - c0)
		for id in gs.spotted.keys():
			gs.follow_lead(id)
		for r in gs.rumours.duplicate():
			gs.follow_rumour(r)
	if gs.tutorial in ["send", "done"] and _hand_run() == null:
		_send_party()


## Treats on the trail, as GameState.toss_treat / _zoom_runs: a treat as soon as the last one allows,
## and zooming pets eat up TREAT_SPEED seconds of walk a second.
func _zoom(run: RunState, now: float) -> void:
	var tr: Dictionary = _treat.get(run, { "zoom_until": -1.0, "ready_at": 0.0 })
	if t >= float(tr.ready_at):
		tr = { "zoom_until": t + gs.treat_zoom(run), "ready_at": t + gs.treat_every(run) }
		_treat[run] = tr
	if t < float(tr.zoom_until) and run.status == RunState.Status.WALKING:
		run.next_at = maxf(now, run.next_at - (gs.TREAT_SPEED - 1.0))


func _hand_run() -> RunState:
	for run: RunState in gs.runs:
		if not run.auto:
			return run
	return null


# ---- adventures: where the party goes -----------------------------------------------------

## The biggest party allowed goes where the next thing is: a find that's there to be found, a
## bit the machine needs, somewhere new, else the best coins.
func _send_party() -> void:
	var pets: Array = gs.sendable_pets()
	if pets.is_empty():
		return
	var resting := {}
	for p in gs.resting_pets():
		resting[p.uid] = true
	pets.sort_custom(func(a, b):
		if resting.has(a.uid) != resting.has(b.uid):
			return resting.has(a.uid)
		return _stat_sum(a) > _stat_sum(b))
	var place := _pick_place(pets.size())
	if place == "":
		return
	var keep := 1 if gs.feature_on("errands") and pets.size() > 1 else 0  # one pet keeps earning at home
	var n := mini(pets.size() - keep, gs.max_party(place))
	var going: Array[Pet] = []
	for i in n:
		going.append(pets[i])
	var real := Time.get_unix_time_from_system()
	var run: RunState = gs.send_on_adventure(place, going)
	if run != null:
		_shift(run, real)
		_count("trip " + place)


func _stat_sum(pet: Pet) -> float:
	var s := 0.0
	for k in pet.stats:
		s += float(pet.stats[k])
	return s


func _places() -> Array[Dictionary]:
	return gs.open_locations().filter(func(l): return str(l.get("type", "")) != "dungeon")


func _pick_place(have: int) -> String:
	var open := _places()
	if open.is_empty():
		return ""
	for l in open:  # a find waiting there
		if _find_at(l, mini(have, gs.max_party(l.id))):
			return str(l.id)
	var bit := _wanted_bit()
	if bit != "":
		var near := ""
		var near_score := -1.0
		for l in open:
			for r in l.get("finish_rewards", []):
				if str(r.get("kind", "")) == "bit" and str(r.get("id", "")) == bit:
					var score := float(r.get("chance", 1.0)) * sqrt(mini(have, gs.max_party(l.id))) / float(l.minutes)
					if score > near_score:
						near_score = score
						near = str(l.id)
		if near != "":
			return near
		for l in open:  # nowhere open has it: go where it could be spotted
			for lead in l.get("leads_to", []):
				var to: Dictionary = catalog.location(str(lead.to))
				if not gs.location_open(to) and to.get("finish_rewards", []).any(func(r): return str(r.get("id", "")) == bit):
					return str(l.id)
	for l in open:  # somewhere new
		if not gs.visited.has(l.id):
			return str(l.id)
	for l in open:  # somewhere that could still spot a place nobody's found
		for lead in l.get("leads_to", []):
			if not gs.location_open(catalog.location(str(lead.to))):
				return str(l.id)
	var best := ""
	var best_score := -1.0
	for l in open:
		var score := float(l.loot) * sqrt(mini(have, gs.max_party(l.id))) / float(l.minutes)
		if score > best_score:
			best_score = score
			best = str(l.id)
	return best


## Whether a trip here could bring home a find nobody has yet.
func _find_at(l: Dictionary, party: int) -> bool:
	var ids: Array = l.get("events", []) + l.get("pool", []).map(func(p): return p.event)
	for id in ids:
		var e: Dictionary = catalog.events.get(id, {})
		if not e.has("find") or gs.finds.has(str(e.find)):
			continue
		if e.has("after") and not gs.finds.has(str(e.after)):
			continue
		if e.has("after_machine") and Machine.owned(gs.machine, str(e.after_machine)) <= 0:
			continue
		if party < int(e.get("min_party", 1)):
			continue
		return true
	return false


## The first bit the cheapest node you could work on is short of ("" if none).
func _wanted_bit() -> String:
	var want := ""
	var cheapest := INF
	for n in catalog.machine_tree.nodes:
		var look := Machine.look(gs.machine, catalog, n.id)
		if look not in ["next", "owned"] or Machine.maxed(gs.machine, catalog, n.id):
			continue
		var need := Machine.bits_cost(catalog, n.id)
		for b in need:
			if int(gs.bits.get(b, 0)) < int(need[b]) and Machine.cost(gs.machine, catalog, n.id) < cheapest:
				cheapest = Machine.cost(gs.machine, catalog, n.id)
				want = str(b)
	return want


## An answer like tools/balance.gd's "sensible" player, a bit more careful with its few pets: go
## for the best worth x chance while everyone's healthy, never bet both hearts, nothing risky once
## someone's hurt (go home if that's all there is).
func _sensible(run: RunState) -> int:
	var location := catalog.location(run.location_id)
	var event := run.current_event(catalog)
	var options := AdventureRunner.options_of(event, location)
	var allowed := AdventureRunner.allowed_options(event, run.party, location)
	var hurt := run.party.injured_count() > 0
	var best := -1
	var best_score := -INF
	var home := -1
	for i in allowed:
		var option: Dictionary = options[i]
		if option.get("home", false):
			home = i
			continue
		var risky := AdventureRunner.risky(option, location)
		if (hurt and risky) or int(option.get("failure", {}).get("hearts", 1)) >= 2:
			continue  # a pet hurt again, or both hearts at once, could stay behind
		var chance := AdventureRunner.success_chance(option, run.party, location, Gear.value(catalog, run.gear, "luck"))
		var score := PetVoice.reward_worth(option.success, location) * chance
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		return home if home >= 0 else Chooser.default_option(event, allowed)
	return best


# ---- the player's check-in: spend, staff, tidy up ------------------------------------------

func _decide() -> void:
	gs.pinned.clear()  # the player looked at the good pulls
	_rummage()
	_care()
	_boxes()
	_spend()
	while _buy_gear():
		pass
	_staff()


func _rummage() -> void:
	if not gs.rummage_open():
		return
	for s in catalog.rummage_spots:
		if t >= float(_rummage_at[s.id]):
			gs.rummaged[s.id] = 0.0
			var c0: int = gs.coins
			if not gs.rummage(s.id).is_empty():
				_earn("rummage", gs.coins - c0)
			_rummage_at[s.id] = t + float(s.refill)


func _care() -> void:
	if t < _next_care:
		return
	_next_care = t + 60.0
	while gs.hunger < 60.0 and gs.coins >= gs.FEED_COST:
		gs.feed()
		_spend_on("food", gs.FEED_COST)
	if gs.happiness < 80.0:
		gs.pat()


## Boxes (once the boxes tab is open): the ones on the pile get opened, and more are bought for
## more crew while there's room (a player only rips so many open a minute).
func _boxes() -> void:
	if not gs.tab_open("boxes"):
		return
	_boxes_left = minf(float(BOXES_PER_MINUTE), _boxes_left + BOXES_PER_MINUTE * (t - _last_boxes) / 60.0)
	_last_boxes = t
	for box in catalog.boxes:
		if box.get("hidden", false):
			continue
		var n := mini(gs.in_bag(box.id), int(_boxes_left))
		if n > 0:
			gs.open_boxes(box.id, n)
			_boxes_left -= n
	var room := mini(int(_boxes_left), MAX_PETS - gs.collection.pets.size())
	if room <= 0:
		return
	var price: int = gs.box_price("starter")
	var worth := _pet_worth()
	if worth <= 0.0 or price / worth > PAYBACK_MAX:
		return
	var n := mini(room, gs.coins / maxi(1, price))
	if n > 0 and not _saving_for_gate(n * price) and gs.buy_boxes("starter", n):
		_spend_on("boxes", n * price)
		gs.open_boxes("starter", n)
		_boxes_left -= n


## Coins a minute one more pet on errands adds, roughly (the crews grow by crew ^ crew_power).
func _pet_worth() -> float:
	var on := 0
	for job in gs.open_jobs():
		on += gs.job_crew(job.id).size()
	var now: float = gs.errands_per_minute()
	if on == 0:
		return now + 1.0
	return now / on * float(catalog.errands.crew_power)


## Income a minute over the last two minutes.
func income() -> float:
	var s := 0.0
	for c in _recent:
		s += c
	return s / (_recent.size() / 60.0)


# ---- spending ---------------------------------------------------------------------------

## Gate buys first (the next repair, teaching a job, the first spot), saving for one that's close;
## then whatever pays back fastest.
func _spend() -> void:
	for i in 40:
		var gate := _gate()
		if not gate.is_empty():
			if gs.coins >= int(gate.cost):
				_buy(gate)
				continue
			if int(gate.cost) - gs.coins <= income() * SAVE_FOR_MINUTES:
				return  # saving up for it
		var best := {}
		for c in _candidates():
			if int(c.cost) > gs.coins or float(c.gain) <= 0.0:
				continue
			c.payback = float(c.cost) / float(c.gain)
			if c.payback <= PAYBACK_MAX and (best.is_empty() or c.payback < best.payback):
				best = c
		if best.is_empty():
			return
		_buy(best)


func _saving_for_gate(spend: int) -> bool:
	var gate := _gate()
	if gate.is_empty():
		return false
	return int(gate.cost) - (gs.coins - spend) <= income() * SAVE_FOR_MINUTES and gs.coins - spend < int(gate.cost)


## The gate the player wants next, { kind, id, cost, name }, or {}: the next repair on the trunk
## (and the second chute), teaching a job, the crank levels teaching the others waits for, teaching
## the others, the first spot of a job the others know. Also notes when each one showed up.
func _gate() -> Dictionary:
	var out: Array[Dictionary] = []
	for n in catalog.machine_tree.nodes:
		if not (str(n.branch) in ["repair", "drops"] or n.id in GATE_NODES):
			continue
		if Machine.look(gs.machine, catalog, n.id) != "next" or Machine.maxed(gs.machine, catalog, n.id):
			continue
		var name := "fix " + str(n.name)
		_seen_gate(name)
		var block := Machine.blocker(gs.machine, catalog, n.id, 1 << 60, gs.bits)
		if block == "":
			_ready_gate(name)
			out.append({ "kind": "machine", "id": n.id, "cost": Machine.cost(gs.machine, catalog, n.id), "name": name })
	for j in gs.auto_jobs():
		if not gs.knows_job(j.id):
			var name := "teach " + str(j.id)
			_seen_gate(name)
			_ready_gate(name)
			out.append({ "kind": "teach", "id": j.id, "cost": int(j.coins), "name": name })
			continue
		var after: Dictionary = j.get("teach", {}).get("after", {})
		for tid in after:
			if Automation.tool_level(gs.automation, tid) < int(after[tid]) and gs.auto_tool_block(tid) == "":
				var name := "%s lv %d" % [tid, Automation.tool_level(gs.automation, tid) + 1]
				_seen_gate(name)
				_ready_gate(name)
				out.append({ "kind": "auto_tool", "id": tid, "cost": gs.auto_tool_cost(tid), "name": name })
		if gs.teach_others_block(j.id) == "":
			var name := "teach the others " + str(j.id)
			_seen_gate(name)
			_ready_gate(name)
			out.append({ "kind": "others", "id": j.id, "cost": gs.teach_others_cost(j.id), "name": name })
		if gs.knows_others(j.id) and Automation.spots(gs.automation, j.id) == 0:
			var name := "first spot " + str(j.id)
			_seen_gate(name)
			_ready_gate(name)
			out.append({ "kind": "spot", "id": j.id, "cost": int(gs.spot_plan(j.id, 1)[1]), "name": name })
	var best := {}
	for g in out:
		if best.is_empty() or int(g.cost) < int(best.cost):
			best = g
	return best


func _seen_gate(name: String) -> void:
	if not gates.has(name):
		gates[name] = { "seen": t, "ready": -1.0, "bought": -1.0 }


func _ready_gate(name: String) -> void:
	if float(gates[name].ready) < 0.0:
		gates[name].ready = t


## Everything else coins can buy that makes more coins, each with { cost, gain (coins a minute) }.
func _candidates() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var base_errands: float = gs.errands_per_minute()
	var inc := maxf(1.0, income())
	# the machine's other nodes
	var lever := _lever_per_min(gs.machine)
	var others := base_errands + _crank_per_min(gs.machine)
	var cv := Machine.coin_value(gs.machine, catalog)
	for n in catalog.machine_tree.nodes:
		if str(n.branch) in ["repair", "drops"] or n.id in GATE_NODES:
			continue
		if Machine.blocker(gs.machine, catalog, n.id, gs.coins, gs.bits) != "":
			continue
		var what: Dictionary = gs.machine.duplicate(true)
		what.bought[n.id] = Machine.owned(what, n.id) + 1
		var gain := _lever_per_min(what) - lever + others * (Machine.coin_value(what, catalog) / cv - 1.0)
		out.append({ "kind": "machine", "id": n.id, "cost": Machine.cost(gs.machine, catalog, n.id), "gain": gain, "name": "machine " + n.id })
	# errand tools
	for tool in Jobs.all_tools(catalog):
		if gs.errand_tool_block(tool.id) != "":
			continue
		var cost := int(gs.errand_tool_plan(tool.id, 1)[1])
		var gain: float = gs.errands_per_minute_with(tool.id, 1) - base_errands
		if gain <= 0.0 and (tool.each.has("hold") or tool.id == "glasses") and not gs.job_crew("scouting").is_empty():
			gain = inc * 0.2  # no coins, but more notes: bought when it's cheap next to income
		out.append({ "kind": "errand_tool", "id": tool.id, "cost": cost, "gain": gain, "name": "errand " + tool.id })
	# your pet's crank and the workers' grease
	if gs.knows_job("machine") and gs.auto_tool_block("crank") == "":
		var ev := _capsule_ev(gs.machine)
		var now := 60.0 / Automation.crank_seconds(catalog, gs.automation)
		var what: Dictionary = gs.automation.duplicate(true)
		what.tools["crank"] = Automation.tool_level(what, "crank") + 1
		var gain := (60.0 / Automation.crank_seconds(catalog, what) - now) * ev if gs.automation.task == "machine" else 0.0
		out.append({ "kind": "auto_tool", "id": "crank", "cost": gs.auto_tool_cost("crank"), "gain": gain, "name": "crank" })
	if gs.knows_others("machine") and gs.auto_tool_block("grease") == "":
		var ev := _capsule_ev(gs.machine)
		var speed: float = gs.workers_speed("machine") * gs.boost("automation")
		var what: Dictionary = gs.automation.duplicate(true)
		what.tools["grease"] = Automation.tool_level(what, "grease") + 1
		var gain := speed * 60.0 * (1.0 / Automation.worker_seconds(catalog, what, "machine") - 1.0 / Automation.worker_seconds(catalog, gs.automation, "machine")) * ev
		out.append({ "kind": "auto_tool", "id": "grease", "cost": gs.auto_tool_cost("grease"), "gain": gain, "name": "grease" })
	# more machines for workers: a common's pulls, less what it made on errands
	if gs.knows_others("machine") and Automation.spots(gs.automation, "machine") > 0:
		var gain := _new_worker_speed() * 60.0 / Automation.worker_seconds(catalog, gs.automation, "machine") * _capsule_ev(gs.machine) - _pet_worth()
		out.append({ "kind": "spot", "id": "machine", "cost": int(gs.spot_plan("machine", 1)[1]), "gain": gain, "name": "spot machine" })
	if gs.knows_others("adventures") and Automation.spots(gs.automation, "adventures") > 0 and _party_minutes > 30.0:
		var gain := _party_coins / _party_minutes - _pet_worth() * 3.0
		out.append({ "kind": "spot", "id": "adventures", "cost": int(gs.spot_plan("adventures", 1)[1]), "gain": gain, "name": "spot adventures" })
	return out


## Coins a minute the lever makes with this machine: chutes x balls x coins a capsule, shiny and
## fever counted in.
func _lever_per_min(m: Dictionary) -> float:
	var period: float = LEVER_SECONDS + Machine.reveal_seconds(m, catalog)
	if style == "casual":
		period *= 4.0
	var balls := 1.0 + Machine.add(m, catalog, "double") + 2.0 * Machine.add(m, catalog, "triple")
	var fever := 1.0
	if Machine.lights_on(m, catalog):
		var share := minf(1.0, Machine.fever_seconds(m, catalog) / period / Machine.lights_needed(m, catalog))
		fever = 1.0 + share * (float(catalog.machine.fever_pay) - 1.0)
	return Machine.chutes(m, catalog) * balls * _capsule_ev(m) * fever * 60.0 / period


## Coins in one plain capsule on average (the prizes that are coins, shiny ones counted in).
func _capsule_ev(m: Dictionary) -> float:
	var drops := Machine.add(m, catalog, "drops")
	var total := 0.0
	var coins := 0.0
	for p in catalog.machine.prizes:
		if drops < float(p.get("drops", 0)) or p.kind == "pet_box":
			continue
		total += float(p.weight)
		if p.kind in ["coins", "golden"]:
			coins += float(p.weight) * (float(p.coins[0]) + float(p.coins[1])) / 2.0
	var shiny := 1.0 + Machine.shiny_chance(m, catalog) * (Machine.shiny_pay(m, catalog) - 1.0)
	return coins / maxf(1.0, total) * Machine.coin_value(m, catalog) * shiny


func _crank_per_min(m: Dictionary) -> float:
	var pulls := 0.0
	if gs.automation.task == "machine":
		pulls += 60.0 / Automation.crank_seconds(catalog, gs.automation)
	pulls += gs.workers_speed("machine") * gs.boost("automation") * 60.0 / Automation.worker_seconds(catalog, gs.automation, "machine")
	return pulls * _capsule_ev(m)


func _buy(c: Dictionary) -> void:
	var c0: int = gs.coins
	var ok := false
	var kind := "machine"
	match str(c.kind):
		"machine":
			ok = gs.buy_machine_upgrade(c.id)
			if ok:
				var lv := Machine.owned(gs.machine, c.id)
				var n := Machine.node(catalog, c.id)
				if lv == 1 or lv == int(n.get("max", 1)):
					_mark("machine: %s%s" % [n.name, "" if int(n.get("max", 1)) == 1 else " lv %d" % lv])
		"errand_tool":
			ok = gs.buy_errand_tool(c.id, 1) > 0
			kind = "errand tools"
		"teach":
			ok = gs.teach_job(c.id)
			kind = "automation"
			if ok:
				_mark("automation: taught " + str(c.id))
		"auto_tool":
			ok = gs.buy_auto_tool(c.id)
			kind = "automation"
			if ok:
				var lv := Automation.tool_level(gs.automation, c.id)
				if lv in [1, 3, 5, 10, 20]:
					_mark("automation: %s lv %d" % [c.id, lv])
		"others":
			ok = gs.teach_others(c.id)
			kind = "automation"
			if ok:
				_mark("automation: taught the others " + str(c.id))
		"spot":
			ok = gs.buy_spots(c.id, 1) > 0
			kind = "automation"
			if ok:
				_fill_spots(c.id)
	if not ok:
		return
	_spend_on(kind, c0 - gs.coins)
	_count(str(c.name))
	if gates.has(str(c.get("name", ""))) and float(gates[c.name].bought) < 0.0:
		gates[c.name].bought = t


## How fast the pet _fill_spots would put on a new machine works: a resting pet, else the slowest
## machine worker (about who comes off an errand).
func _new_worker_speed() -> float:
	var resting: Array = gs.resting_pets()
	if not resting.is_empty():
		return Automation.worker_speed(catalog, resting[0])
	var slowest := INF
	for uid in gs.workers_of("machine"):
		var pet: Pet = gs.collection.get_pet(str(uid)) if str(uid) != "" else null
		if pet:
			slowest = minf(slowest, Automation.worker_speed(catalog, pet))
	return slowest if slowest < INF else 0.0


## A new machine (table, party) gets a worker: a resting pet, or the slowest one off an errand.
func _fill_spots(id: String) -> void:
	if gs.resting_pets().is_empty():
		var biggest := ""
		for job in gs.open_jobs():
			if biggest == "" or gs.job_crew(job.id).size() > gs.job_crew(biggest).size():
				biggest = job.id
		if biggest != "":
			gs.take_off_job(biggest, 1)
	if gs.put_workers(id, -1) > 0 and gs.workers_count(id) == 1:
		_mark("automation: first worker " + id)


func _buy_gear() -> bool:
	var best := ""
	for g in gs.shown_gear():
		if gs.gear_block(g.id) != "":
			continue
		if best == "" or gs.gear_price(g.id) < gs.gear_price(best):
			best = str(g.id)
	if best == "" or gs.xp < gs.gear_price(best):
		return false
	if not gs.buy_gear(best):
		return false
	var lv: int = gs.gear_level(best)
	if lv == 1 or lv == int(Gear.info(catalog, best).max):
		_mark("gear: %s lv %d" % [best, lv])
	return true


# ---- errands: who works where ------------------------------------------------------------

## Every open job gets one pet to try it (one scout, once scouting is open), the other resting
## pets go where they add the most coins a minute (tried for real, a handful at a time), and every
## few minutes everyone is moved round again.
func _staff() -> void:
	if not gs.feature_on("errands") or gs.tutorial_active():
		return
	var open: Array = gs.open_jobs()
	var earners: Array = open.filter(func(j): return not j.has("scout") and (j.pay.has("capsules") or j.pay.has("coins") or j.has("kitchen")))
	var full := t >= _next_rebalance or open.size() != _jobs_open
	if full:
		_next_rebalance = t + REBALANCE_EVERY
		_jobs_open = open.size()
		for job in open:
			if not job.has("scout"):
				gs.take_off_job(job.id, -1)
	for job in open:  # every job gets a pet to try it (scouting: one, and only that one)
		if gs.job_crew(job.id).is_empty() and (job.has("scout") or job in earners) and gs.resting_pets().size() >= (2 if job.has("scout") else 1):
			gs.put_on_job(job.id, 1)
	var resting: Array = gs.resting_pets().map(func(p): return p.uid)
	if resting.is_empty() or earners.is_empty():
		return
	var chunk := maxi(1, resting.size() / 10)
	while not resting.is_empty():
		var batch := resting.slice(0, chunk)
		resting = resting.slice(chunk)
		var best := ""
		var best_v := -INF
		for job in earners:
			gs.put_on_job(job.id, 0, batch)
			var v: float = gs.errands_per_minute()
			gs.take_off_job(job.id, 0, batch)
			if v > best_v:
				best_v = v
				best = job.id
		gs.put_on_job(best, 0, batch)


# ---- bookkeeping ---------------------------------------------------------------------------

func _earn(source: String, c: int) -> void:
	if c <= 0:
		return
	_earned[source] = int(_earned.get(source, 0)) + c
	_recent[_recent_i] += c


func _spend_on(what: String, c: int) -> void:
	spent[what] = int(spent.get(what, 0)) + c


func _count(what: String) -> void:
	buys[what] = int(buys.get(what, 0)) + 1


func _mark(what: String) -> void:
	if not milestones.has(what):
		milestones[what] = t / 60.0


## Milestones the game shows by itself: unlocks, finds, the tutorial, trips, job levels, pets.
func _notice() -> void:
	for id in gs.unlocks:
		if not _seen_unlocks.has(id):
			_seen_unlocks[id] = true
			_mark("open: " + str(id))
	for id in gs.finds:
		if not _seen_finds.has(id):
			_seen_finds[id] = true
			_mark("find: " + str(id))
	if gs.collection.pets.size() >= 1:
		_mark("tutorial: first pet")
	if gs.tutorial in ["send", "done"] and gs.collection.pets.size() >= 2:
		_mark("tutorial: second pet (adventures)")
	if gs.tutorial == "done":
		_mark("tutorial: done")
	for n in [1, 10, 40, 60, 100]:
		if gs.trips_done >= n:
			_mark("trips: %d" % n)
	for n in [5, 10, 50, 100, 1000]:
		if gs.collection.pets.size() >= n:
			_mark("pets: %d" % n)
	for job in catalog.jobs:
		var lv: int = gs.job_level(job.id)
		for g in job.get("goals", []):
			if lv >= int(g.at):
				_mark("errands: %s lv %d" % [job.id, int(g.at)])


func _close_window() -> void:
	var per := {}
	for s in SOURCES:
		per[s] = float(_earned.get(s, 0)) / (WINDOW / 60.0)
	var errands := {}
	for j in _errand_earned:
		errands[j] = float(_errand_earned[j]) / (WINDOW / 60.0)
	var bits := 0
	for b in gs.bits:
		bits += int(gs.bits[b])
	windows.append({ "minute": t / 60.0, "per_min": per, "errands": errands, "coins": gs.coins, "pets": gs.collection.pets.size(),
		"xp": gs.xp, "bits": bits, "trips": gs.trips_done, "lost": lost, "cv": Machine.coin_value(gs.machine, catalog) })
	_party_coins += float(_earned.get("auto trips", 0))
	_earned = {}
	_errand_earned = {}
