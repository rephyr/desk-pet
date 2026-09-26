class_name DungeonRunner
extends RefCounted
## The dungeon rules, as pure functions: a RunState and the time go in, the moved-on RunState and
## what happened come out. No UI, no nodes, no GameState. Groups are handled with totals (the
## party's combined stat against the event's difficulty), never by simulating each pet, so the
## same code runs a single pet or thousands, and a run can be caught up in one call after the
## game was closed.

const MIN_CHANCE := 0.05  # even a great party can fail, and a hopeless one can get lucky
const MAX_CHANCE := 0.95
const CHANCE_SLOPE := 0.35  # how much doubling the party's stat over the difficulty helps
const SIZE_SCALING := 0.85  # difficulty grows a bit slower than the party: big parties do better
const STAT_NEED := 10.0  # a pet stat that's "about right" for a difficulty 1 dungeon


static func start(dungeon_id: String, pets: Array[Pet], now: float, rng_seed: int, catalog: Catalog) -> RunState:
	var dungeon := catalog.dungeon(dungeon_id)
	var s := RunState.new()
	s.dungeon_id = dungeon_id
	s.chooser = dungeon.chooser
	s.party = Party.make(pets, catalog)
	s.rng_seed = rng_seed
	s.started = now
	s.next_at = now + gap(dungeon, s.party)
	return s


## Seconds between events: the run's time spread over its events plus the walk home. Faster
## parties go a bit quicker.
static func gap(dungeon: Dictionary, party: Party) -> float:
	var need := STAT_NEED * float(dungeon.difficulty)
	var pace := clampf(1.0 - (party.average("speed") - need) * 0.01, 0.5, 1.25)
	return float(dungeon.minutes) * 60.0 * pace / (dungeon.events.size() + 1)


## About how long a party would take, for showing before sending.
static func duration(dungeon: Dictionary, party: Party) -> float:
	return gap(dungeon, party) * (dungeon.events.size() + 1)


## Moves a run on to `now`: every event whose time has come is played, until the run is done
## or the chooser has no answer yet. Returns the new history entries.
static func resolve(state: RunState, chooser: Chooser, now: float, catalog: Catalog) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var dungeon := catalog.dungeon(state.dungeon_id)
	while state.status != RunState.Status.DONE and now >= state.next_at:
		if state.step >= dungeon.events.size() or state.party.size() == 0:
			state.status = RunState.Status.DONE
			break
		var event: Dictionary = catalog.events.get(dungeon.events[state.step], {})
		if event.is_empty() or not applies(event, state.party):
			state.step += 1
			continue
		if state.status == RunState.Status.WALKING:
			state.status = RunState.Status.WAITING
			state.waiting_since = state.next_at
		var pick := chooser.choose(event, allowed_options(event, state.party), state, now)
		if pick == Chooser.PENDING:
			break
		added.append(play(event, pick, state, catalog))
		state.answer = -1
		# rules decide on the spot; a player decides when they answer
		var decided := state.next_at if state.chooser == "policy" else maxf(state.next_at, now)
		state.status = RunState.Status.WALKING
		state.next_at = decided + gap(dungeon, state.party)
	return added


## Whether this event happens for this party (some only happen if someone is injured).
static func applies(event: Dictionary, party: Party) -> bool:
	match str(event.get("only_if", "")):
		"injured":
			return party.injured_count() > 0
	return true


## Indices of the options this party may take.
static func allowed_options(event: Dictionary, party: Party) -> Array[int]:
	var out: Array[int] = []
	for i in event.options.size():
		if party.size() >= int(event.options[i].get("min_party", 1)):
			out.append(i)
	return out


## Chance (0..1) that the party pulls an option off: its total stat against the difficulty.
static func success_chance(option: Dictionary, party: Party, dungeon: Dictionary) -> float:
	var stat_name := str(option.get("stat", ""))
	if stat_name == "":
		return 1.0
	var have := party.total(stat_name)
	var need := float(option.difficulty) * float(dungeon.difficulty) * pow(maxf(1.0, party.size()), SIZE_SCALING)
	if have <= 0.0:
		return MIN_CHANCE
	return clampf(0.5 + CHANCE_SLOPE * log(have / need) / log(2.0), MIN_CHANCE, MAX_CHANCE)


## Plays one option of an event on the run and returns what happened.
static func play(event: Dictionary, pick: int, state: RunState, catalog: Catalog) -> Dictionary:
	var dungeon := catalog.dungeon(state.dungeon_id)
	var option: Dictionary = event.options[pick]
	var party := state.party
	# each event has its own dice, so when it's resolved doesn't change how it goes
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.rng_seed, state.step])
	var ok := rng.randf() < success_chance(option, party, dungeon)
	var outcome: Dictionary = option.success if ok else option.get("failure", option.success)
	var entry := {
		"event": event.id, "title": event.title, "option": option.label, "success": ok,
		"text": str(outcome.text).replace("{who}", party.who()),
		"lost": 0, "injured": 0, "coins": 0, "boxes": {}, "parts": [],
	}
	var danger := float(dungeon.danger)
	if outcome.has("heal"):
		party.heal(_count(_between(outcome.heal, rng) * party.injured_count(), rng), rng)
	if outcome.get("leave_injured", false):
		entry.lost += party.leave_injured()
	if outcome.has("lost"):
		entry.lost += party.lose(_count(_between(outcome.lost, rng) * danger * party.size(), rng), rng).size()
	if outcome.has("injured"):
		entry.injured = party.injure(_count(_between(outcome.injured, rng) * danger * party.size(), rng), rng)

	# loot comes from the pets still standing; luck helps
	var here := party.size()
	if here > 0:
		var luck := clampf(party.average("luck") / (STAT_NEED * float(dungeon.difficulty)), 0.5, 2.0)
		if outcome.has("coins"):
			entry.coins = roundi(rng.randi_range(int(outcome.coins[0]), int(outcome.coins[1])) * float(dungeon.loot) * here * luck)
		var items := sqrt(here) * luck  # more pets find more, but not in proportion
		var found_boxes := _count(float(outcome.get("box_chance", 0.0)) * items, rng)
		if found_boxes > 0:
			entry.boxes[dungeon.box] = found_boxes
		for i in _count(float(outcome.get("part_chance", 0.0)) * items, rng):
			entry.parts.append(roll_part(dungeon.box, rng, catalog))
	state.coins += entry.coins
	for box_id in entry.boxes:
		state.boxes[box_id] = state.boxes.get(box_id, 0) + entry.boxes[box_id]
	state.parts.append_array(entry.parts)

	match str(outcome.get("progress", "continue")):
		"end":
			state.step = dungeon.events.size()
		"skip":
			state.step += 2
		_:
			state.step += 1
	state.history.append(entry)
	return entry


## A random part at a rarity rolled with a box's odds, as [slot, part id].
static func roll_part(box_id: String, rng: RandomNumberGenerator, catalog: Catalog) -> Array:
	var slot: String = Catalog.SLOTS[rng.randi_range(0, Catalog.SLOTS.size() - 1)]
	var rank := catalog.rank(Weighted.pick(catalog.box(box_id).tiers, rng))
	for r in range(rank, -1, -1):
		var options := catalog.parts_of_tier(slot, catalog.tier_at(r).id)
		if not options.is_empty():
			return [slot, options[rng.randi_range(0, options.size() - 1)].id]
	return [slot, catalog.default_part(slot)]


## "Expedition complete: 12 of 100 returned. New part found!"
static func summary(state: RunState) -> String:
	var text := "Expedition complete: %d of %d returned." % [state.party.size(), state.party.setting_out()]
	var box_count := 0
	for box_id in state.boxes:
		box_count += int(state.boxes[box_id])
	if state.parts.size() == 1:
		text += " New part found!"
	elif state.parts.size() > 1:
		text += " %d new parts found!" % state.parts.size()
	if box_count == 1:
		text += " Found a box!"
	elif box_count > 1:
		text += " Found %d boxes!" % box_count
	return text


## Roughly what share of these pets come home if the dungeon's rules pick every option, from a
## few quick trial runs. For showing before sending a swarm.
static func estimate_return(dungeon_id: String, pets: Array[Pet], catalog: Catalog, trials := 30) -> float:
	if pets.is_empty():
		return 1.0
	var home := 0.0
	for t in trials:
		var s := start(dungeon_id, pets, 0.0, t, catalog)
		resolve(s, PolicyChooser.new(), INF, catalog)
		home += s.party.size()
	return home / (trials * pets.size())


## Turns an expected amount into a whole number that averages out to it (2.3 -> 2 or 3).
static func _count(expected: float, rng: RandomNumberGenerator) -> int:
	var whole := floori(expected)
	return whole + (1 if rng.randf() < expected - whole else 0)


static func _between(range_pair: Array, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(float(range_pair[0]), float(range_pair[1]))
