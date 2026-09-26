class_name RunState
extends RefCounted
## One party's trip through a dungeon: where it's got to, what's happened, what it's carrying.
## Plain data that DungeonRunner moves forward; saved as-is so runs carry on after a restart.

enum Status { WALKING, WAITING, DONE }

var dungeon_id := ""
var chooser := "player"  # who picks options, see Chooser.for_run()
var party: Party
var rng_seed := 0  # each event rolls with seed + its step, so resolving later gives the same result
var step := 0  # index of the next event in the dungeon's list
var started := 0.0
var next_at := 0.0  # unix time the next event (or the way home) arrives
var status := Status.WALKING
var waiting_since := 0.0
var answer := -1  # the option the player picked for the waiting event, -1 if none yet
var history: Array[Dictionary] = []  # { event, option, text, lost, injured, coins, boxes, parts }
var coins := 0
var boxes := {}  # box id -> count
var parts: Array = []  # [slot, part id] pairs


## The event the party is standing at, or {} while walking between them.
func current_event(catalog: Catalog) -> Dictionary:
	if status != Status.WAITING:
		return {}
	return catalog.events.get(catalog.dungeon(dungeon_id).events[step], {})


func to_dict() -> Dictionary:
	return {
		"dungeon": dungeon_id, "chooser": chooser, "party": party.to_dict(), "seed": rng_seed, "step": step,
		"started": started, "next_at": next_at, "status": status, "waiting_since": waiting_since,
		"answer": answer, "log": history, "coins": coins, "boxes": boxes, "parts": parts,
	}


## Returns null for runs that can't be loaded any more (e.g. the dungeon was removed from data/).
static func from_dict(d: Dictionary, catalog: Catalog) -> RunState:
	var dungeon := catalog.dungeon(str(d.get("dungeon", "")))
	if dungeon.is_empty() or not d.has("party"):
		return null
	var s := RunState.new()
	s.dungeon_id = dungeon.id
	s.chooser = str(d.get("chooser", dungeon.chooser))
	s.party = Party.from_dict(d.party)
	s.rng_seed = int(d.get("seed", 0))
	s.step = clampi(int(d.get("step", 0)), 0, dungeon.events.size())
	s.started = float(d.get("started", 0.0))
	s.next_at = float(d.get("next_at", 0.0))
	s.status = clampi(int(d.get("status", Status.WALKING)), Status.WALKING, Status.DONE) as Status
	s.waiting_since = float(d.get("waiting_since", 0.0))
	s.answer = int(d.get("answer", -1))
	s.history.assign(d.get("log", []))
	s.coins = int(d.get("coins", 0))
	for box_id in d.get("boxes", {}):
		s.boxes[box_id] = int(d.boxes[box_id])
	s.parts = d.get("parts", [])
	return s
