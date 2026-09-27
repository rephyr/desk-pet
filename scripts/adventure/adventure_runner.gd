class_name AdventureRunner
extends RefCounted
## The adventure rules, as pure functions: a RunState and the time go in, the moved-on RunState and
## what happened come out. No UI, no nodes, no GameState. Groups are handled with totals (the
## party's combined stat against the event's difficulty), never by simulating each pet, so the
## same code runs a single pet or thousands, and a run can be caught up in one call after the
## game was closed.

const MIN_CHANCE := 0.05  # even a great party can fail, and a hopeless one can get lucky
const MAX_CHANCE := 0.95
const CHANCE_SLOPE := 0.35  # how much doubling the party's stat over the difficulty helps
const SIZE_SCALING := 0.85  # difficulty grows a bit slower than the party: big parties do better
const STAT_TILT := 0.15  # most a pet's stat moves an option's own chance, either way
const HURT_PENALTY := 0.2  # a hurt pet does this much worse at anything risky
const FINISH_TEXT := "{who} made it all the way! a treat bag for the way home!"
const SAFE_MISS_TEXT := "oops! {who} didn't manage it. nothing this time, but no harm done!"  # a safe place's failure
const XP_EVENT := 2  # xp for getting through an event
const XP_BRAVE := 2  # extra when a risky option works out
const XP_FINISH := 5  # extra for going all the way
## Places with "go_home" offer this at every event: end the trip and keep the bag.
const HOME_OPTION := {
	"label": "go home", "tag": "retreat", "stat": "", "home": true,
	"success": { "text": "{who} headed home with the bag!", "progress": "end" },
}


## `found` lists special items already found: events that give them don't turn up any more.
static func start(location_id: String, pets: Array[Pet], now: float, rng_seed: int, catalog: Catalog, found := {}) -> RunState:
	var location := catalog.location(location_id)
	var s := RunState.new()
	s.location_id = location_id
	s.party = Party.make(pets, catalog)
	s.chooser = Chooser.kind_for(pets.size())
	s.rng_seed = rng_seed
	s.events = pick_events(location, rng_seed, found, catalog)
	s.started = now
	s.next_at = now + gap(location, s.party, s.events.size())
	return s


## The events a trip will meet: a place's fixed list, or a draw from its pool (weighted, no
## repeats), so trips to the same place go differently.
static func pick_events(location: Dictionary, rng_seed: int, found := {}, catalog: Catalog = null) -> Array[String]:
	var out: Array[String] = []
	var still := func(id) -> bool:
		return catalog == null or not found.has(str(catalog.events.get(id, {}).get("find", "")))
	if not location.has("pool"):
		out.assign(location.get("events", []).filter(still))
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([rng_seed, "pool"])
	var weights := {}
	for entry in location.pool:
		if still.call(entry.event):
			weights[entry.event] = float(entry.get("weight", 1.0))
	for i in mini(int(location.get("draws", 3)), weights.size()):
		var id: String = Weighted.pick(weights, rng)
		weights.erase(id)
		out.append(id)
	return out


## How many events a trip to this place meets.
static func event_count(location: Dictionary) -> int:
	return int(location.draws) if location.has("pool") else location.get("events", []).size()


## Seconds between events: the trip's time spread over its events plus the walk home. Faster
## parties go a bit quicker.
static func gap(location: Dictionary, party: Party, events: int) -> float:
	var need := Rewards.STAT_NEED * float(location.difficulty)
	var pace := clampf(1.0 - (party.average("speed") - need) * 0.01, 0.5, 1.25)
	return float(location.minutes) * 60.0 * pace / (events + 1)


## About how long a party would take, for showing before sending.
static func duration(location: Dictionary, party: Party) -> float:
	return gap(location, party, event_count(location)) * (event_count(location) + 1)


## Moves a run on to `now`: every event whose time has come is played, until the run is done
## or the chooser has no answer yet. Returns the new history entries.
static func resolve(state: RunState, chooser: Chooser, now: float, catalog: Catalog) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var location := catalog.location(state.location_id)
	while state.status != RunState.Status.DONE and now >= state.next_at:
		if state.step >= state.events.size() or state.party.size() == 0:
			if state.party.size() == 0:
				state.loot.clear()  # nobody came back to carry the bag
			elif not state.went_home:
				_finish_treat(state, location, catalog)
			state.status = RunState.Status.DONE
			break
		var event: Dictionary = catalog.events.get(state.events[state.step], {})
		if event.is_empty() or not applies(event, state.party):
			state.step += 1
			continue
		if state.status == RunState.Status.WALKING:
			state.status = RunState.Status.WAITING
			state.waiting_since = state.next_at
		var pick := chooser.choose(event, allowed_options(event, state.party, location), state, now)
		if pick == Chooser.PENDING:
			break
		var decided := maxf(state.next_at, chooser.decided_at(state, now))
		added.append(play(event, pick, state, catalog))
		state.answer = -1
		state.status = RunState.Status.WALKING
		state.next_at = decided + gap(location, state.party, state.events.size())
		if state.party.size() == 0:
			state.next_at = decided  # nobody left to walk on: it ends right here
	return added


## A trip that went all the way (not home early) gets a little treat bag on the way home.
static func _finish_treat(state: RunState, location: Dictionary, catalog: Catalog) -> void:
	var treat: Array = location.get("finish_rewards", [])
	if treat.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.rng_seed, "finish"])
	var loot := {}
	for reward in treat:
		Rewards.add(loot, Rewards.roll(reward, state.party, location, rng, catalog, Rewards.depth_boost(state.history.size())))
	Rewards.add(state.loot, loot)
	state.xp += roundi(XP_FINISH * float(location.get("xp", 1.0)))
	state.history.append({ "event": "finish", "title": "", "option": "", "success": true, "lost": 0, "injured": 0,
		"loot": loot, "text": FINISH_TEXT.replace("{who}", state.party.who()) })


## Whether this event happens for this party (some only happen if someone is injured).
static func applies(event: Dictionary, party: Party) -> bool:
	match str(event.get("only_if", "")):
		"injured":
			return party.injured_count() > 0
	return true


## An event's options at this place: its own, plus "go home" where the place offers it.
static func options_of(event: Dictionary, location: Dictionary) -> Array:
	var out: Array = event.options.duplicate()
	if location.get("go_home", false):
		out.append(HOME_OPTION)
	return out


## Indices (into options_of) of the options this party may take.
static func allowed_options(event: Dictionary, party: Party, location: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var options := options_of(event, location)
	for i in options.size():
		if party.size() >= int(options[i].get("min_party", 1)):
			out.append(i)
	return out


## Chance (0..1) that the party pulls an option off. Options with their own "chance" start from
## it, tilted a little by the pet's stat and down if it's hurt; older options compare the party's
## total stat with a difficulty. No stat and no chance: it always works.
static func success_chance(option: Dictionary, party: Party, location: Dictionary) -> float:
	var stat_name := str(option.get("stat", ""))
	if option.has("chance"):
		var chance := float(option.chance)
		if stat_name != "":
			var need := Rewards.STAT_NEED * float(location.difficulty)
			chance += clampf((party.average(stat_name) - need) * 0.01, -STAT_TILT, STAT_TILT)
		chance -= HURT_PENALTY * party.injured_count() / maxf(1.0, party.size())
		return clampf(chance, MIN_CHANCE, MAX_CHANCE)
	if stat_name == "":
		return 1.0
	var have := party.total(stat_name)
	var need := float(option.difficulty) * float(location.difficulty) * pow(maxf(1.0, party.size()), SIZE_SCALING)
	if have <= 0.0:
		return MIN_CHANCE
	return clampf(0.5 + CHANCE_SLOPE * log(have / need) / log(2.0), MIN_CHANCE, MAX_CHANCE)


## Plays one option of an event on the run and returns what happened.
static func play(event: Dictionary, pick: int, state: RunState, catalog: Catalog) -> Dictionary:
	var location := catalog.location(state.location_id)
	var option: Dictionary = options_of(event, location)[pick]
	var party := state.party
	# each event has its own dice, so when it's resolved doesn't change how it goes
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.rng_seed, state.step])
	var ok := rng.randf() < success_chance(option, party, location)
	var outcome: Dictionary = option.success if ok else option.get("failure", option.success)
	var entry := {
		"event": event.id, "title": event.title, "option": option.label, "success": ok,
		"text": str(outcome.text).replace("{who}", party.who()),
		"lost": 0, "injured": 0, "loot": {},
	}
	var danger := float(location.danger)
	# a "safe" place (the garden, where you learn how adventures go): a failure costs nothing
	# but the reward, nobody gets hurt or lost there
	if location.get("safe", false) and not ok:
		outcome = { "text": SAFE_MISS_TEXT }
		entry.text = SAFE_MISS_TEXT.replace("{who}", party.who())
	if outcome.has("heal"):
		party.heal(Rewards.count(_between(outcome.heal, rng) * party.injured_count(), rng), rng)
	if outcome.get("leave_injured", false):
		entry.lost += party.leave_injured()
	if outcome.has("lost"):
		entry.lost += party.lose(Rewards.count(_between(outcome.lost, rng) * danger * party.size(), rng), rng).size()
	if outcome.has("injured"):
		entry.injured = party.injure(Rewards.count(_between(outcome.injured, rng) * danger * party.size(), rng), rng)
	if outcome.has("hurt"):
		# a hurt pet that's hurt again doesn't come back; some things cost both hearts at once
		var hurt := party.hurt(Rewards.count(_between(outcome.hurt, rng) * danger * party.size(), rng),
			int(outcome.get("hearts", 1)), rng)
		entry.injured += hurt.injured
		entry.lost += hurt.lost
	# loot comes from the pets still there
	for reward in outcome.get("rewards", []):
		Rewards.add(entry.loot, Rewards.roll(reward, party, location, rng, catalog, Rewards.depth_boost(state.history.size())))
	Rewards.add(state.loot, entry.loot)

	match str(outcome.get("progress", "continue")):
		"end":
			state.step = state.events.size()
			state.went_home = true
		"skip":
			state.step += 2
		_:
			state.step += 1
	# experience: for getting through it, more for a risk that paid off
	var risky: bool = option.get("failure", {}).has("hurt") or option.get("failure", {}).has("lost")
	entry.xp = roundi((XP_EVENT + (XP_BRAVE if ok and risky else 0)) * float(location.get("xp", 1.0)))
	state.xp += entry.xp
	state.history.append(entry)
	return entry


## "Expedition complete: 12 of 100 returned. New part found!"
static func summary(state: RunState) -> String:
	var text := "Expedition complete: %d of %d returned." % [state.party.size(), state.party.setting_out()]
	if state.xp > 0:
		text += " +%d xp!" % state.xp
	var parts := Rewards.total(state.loot, "part")
	var boxes := Rewards.total(state.loot, "box")
	if parts == 1:
		text += " New part found!"
	elif parts > 1:
		text += " %d new parts found!" % parts
	if boxes == 1:
		text += " Found a box!"
	elif boxes > 1:
		text += " Found %d boxes!" % boxes
	var heard := Rewards.total(state.loot, "rumour")
	if heard == 1:
		text += " Heard a rumour!"
	elif heard > 1:
		text += " Heard %d rumours!" % heard
	# kinds of reward added later get a plain mention without code changes here
	var others := {}
	for key: String in state.loot:
		var kind := key.get_slice(":", 0)
		if not kind in ["coins", "part", "box", "rumour"]:
			others[kind] = int(others.get(kind, 0)) + int(state.loot[key])
	for kind in others:
		text += " Found %d %s!" % [others[kind], kind]
	return text


## Roughly what share of these pets come home if the default option is taken at every event,
## from a few quick trial runs. For showing before sending.
static func estimate_return(location_id: String, pets: Array[Pet], catalog: Catalog, trials := 30) -> float:
	if pets.is_empty():
		return 1.0
	var home := 0.0
	for t in trials:
		var s := start(location_id, pets, 0.0, t, catalog)
		resolve(s, PolicyChooser.new(), INF, catalog)
		home += s.party.size()
	return home / (trials * pets.size())


static func _between(range_pair: Array, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(range_pair[0]), float(range_pair[1]))
