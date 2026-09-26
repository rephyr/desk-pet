class_name Chooser
extends RefCounted
## Who picks an option when a party reaches an event. The events are the same at every scale;
## only this changes, with the size of the party: one pet and the player picks every option
## (PlayerChooser), a small party gets a prompt that picks a default if ignored (TimeoutChooser),
## a swarm follows the player's standing rules (PolicyChooser).

const PENDING := -1  # no pick yet: the run waits at this event
const SMALL_PARTY := 10  # up to this many get prompts; more need rules (and the automation unlock)


## The index (into event.options) of the option to take, or PENDING. `allowed` lists the indices
## this party may take (some options need a bigger party).
func choose(_event: Dictionary, _allowed: Array[int], _state: RunState, _now: float) -> int:
	return PENDING


## When the pick that was just made counts as made (the next event comes a walk after that).
func decided_at(_state: RunState, now: float) -> float:
	return now


## Which chooser a party of this size gets.
static func kind_for(party_size: int) -> String:
	if party_size <= 1:
		return "player"
	return "timeout" if party_size <= SMALL_PARTY else "policy"


static func for_run(state: RunState) -> Chooser:
	match state.chooser:
		"timeout":
			return TimeoutChooser.new()
		"policy":
			return PolicyChooser.new()
	return PlayerChooser.new()


## The event's default option if this party may take it, otherwise the first one it may.
static func default_option(event: Dictionary, allowed: Array[int]) -> int:
	var d := int(event.get("default", 0))
	return d if d in allowed else allowed[0]
