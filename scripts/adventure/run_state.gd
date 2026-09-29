class_name RunState
extends RefCounted
## One party's adventure: where it's got to, what's happened, what it's carrying.
## Plain data that AdventureRunner moves forward; saved as-is so runs carry on after a restart.

enum Status { WALKING, WAITING, DONE }

var location_id := ""
var chooser := "player"  # who picks options, see Chooser.for_run()
var party: Party
var rng_seed := 0  # each event rolls with seed + its step, so resolving later gives the same result
var events: Array[String] = []  # the events this trip meets, picked when it set off
var step := 0  # index of the next one
var started := 0.0
var next_at := 0.0  # unix time the next event (or the way home) arrives
var status := Status.WALKING
var waiting_since := 0.0
var answer := -1  # the option the player picked for the waiting event, -1 if none yet
var history: Array[Dictionary] = []  # { event, title, option, success, text, lost, injured, loot }
var loot := {}  # everything found so far, see Rewards
var went_home := false  # ended early by choice (no treat bag for finishing)
var xp := 0  # experience from this trip; unlike the bag, it isn't lost with the pet
var auto := false  # your pet sent it (the automation tab's adventures job): it comes home and goes again by itself
var slot := -1  # an auto party: -1 your pet's, 0 and up a worker's (automation.parties)
var gear := {}  # gear id -> level it set off with (see Gear.for_trip): buying more mid-trip helps the next trip
var saves_used := 0  # times the first-aid leaf saved this (solo) trip's pet
var scout := {}  # the scout note it took when it set off ({} if none, see Jobs.scout_note): { spot, rumour_x }
var scouted: bool:  # it took a scout note: better odds of spotting places and hearing rumours
	get:
		return not scout.is_empty()
var knacks := {}  # knack kind -> multiplier this trip set off with (GameState.trip_knacks: the kinds marked "trip" in data/boosts.json); missing = x1
var ours := false  # the place was ours when it set off (see Ours): safer, pays more, no locals
var parts := true  # parts were open when it set off: no part loot (and no "found a part!") before that
var met := {}  # an ours run's place with the ours danger and loot (AdventureRunner.place, worked out once, not saved)
var walk := 0.0  # share of the walking the gear's comfy boots and "trip" knacks take off (worked out once, not saved)


## The event the party is standing at, or {} while walking between them.
func current_event(catalog: Catalog) -> Dictionary:
	if status != Status.WAITING:
		return {}
	return catalog.events.get(events[step], {})


func to_dict() -> Dictionary:
	return {
		"location": location_id, "chooser": chooser, "party": party.to_dict(), "seed": rng_seed, "events": events, "step": step,
		"started": started, "next_at": next_at, "status": status, "waiting_since": waiting_since,
		"answer": answer, "log": history, "loot": loot, "went_home": went_home, "xp": xp, "auto": auto, "slot": slot,
		"gear": gear, "saves_used": saves_used, "scout": scout, "knacks": knacks, "ours": ours, "parts_on": parts,
	}


## What knacks do for this trip for one kind (1.0 when nothing does).
func knack(kind: String) -> float:
	return float(knacks.get(kind, 1.0))


## Returns null for runs that can't be loaded any more (e.g. the location was removed from data/).
static func from_dict(d: Dictionary, catalog: Catalog) -> RunState:
	var location := catalog.location(str(d.get("location", d.get("dungeon", ""))))  # "dungeon" before v5
	if location.is_empty() or not d.has("party"):
		return null
	var s := RunState.new()
	s.location_id = location.id
	s.party = Party.from_dict(d.party)
	s.chooser = str(d.get("chooser", Chooser.kind_for(s.party.setting_out())))
	s.rng_seed = int(d.get("seed", 0))
	s.events.assign(d.get("events", location.get("events", [])).filter(func(e): return catalog.events.has(e)))
	s.step = clampi(int(d.get("step", 0)), 0, s.events.size())
	s.started = float(d.get("started", 0.0))
	s.next_at = float(d.get("next_at", 0.0))
	s.status = clampi(int(d.get("status", Status.WALKING)), Status.WALKING, Status.DONE) as Status
	if s.status == Status.WAITING and s.step >= s.events.size():
		s.status = Status.WALKING  # the location lost events since this was saved: head home
	s.waiting_since = float(d.get("waiting_since", 0.0))
	s.answer = int(d.get("answer", -1))
	s.went_home = bool(d.get("went_home", false))
	s.xp = int(d.get("xp", 0))
	s.auto = bool(d.get("auto", false))
	s.slot = int(d.get("slot", -1))
	s.ours = bool(d.get("ours", false))  # v31
	s.parts = bool(d.get("parts_on", true))
	var packed: Dictionary = d.get("gear", {})
	for id in packed:
		s.gear[str(id)] = int(packed[id])
	var packed_knacks: Dictionary = d.get("knacks", {})
	for kind in packed_knacks:
		s.knacks[str(kind)] = float(packed_knacks[kind])
	s.walk = AdventureRunner.walk_of(catalog, s.gear, s.knacks)
	s.saves_used = int(d.get("saves_used", 0))
	var note: Dictionary = d.get("scout", {})
	for key in note:
		s.scout[str(key)] = float(note[key])
	s.history.assign(d.get("log", []))
	for key in d.get("loot", {}):
		s.loot[key] = int(d.loot[key])
	# before v5, loot was kept as coins / boxes / parts
	if d.has("coins"):
		Rewards.add(s.loot, { "coins": int(d.coins) })
	for box_id in d.get("boxes", {}):
		Rewards.add(s.loot, { "box:%s" % box_id: int(d.boxes[box_id]) })
	for p in d.get("parts", []):
		Rewards.add(s.loot, { "part:%s:%s" % [p[0], p[1]]: 1 })
	return s
