class_name Chooser
extends RefCounted
## Who picks an option when a party reaches an event. The events are the same at every scale;
## only this changes: the player picks every one (PlayerChooser), the player gets a prompt with a
## default if they don't answer (TimeoutChooser), or rules the player set pick (PolicyChooser).

const PENDING := -1  # no pick yet: the run waits at this event


## The index (into event.options) of the option to take, or PENDING. `allowed` lists the indices
## this party may take (some options need a bigger party).
func choose(_event: Dictionary, _allowed: Array[int], _state: RunState, _now: float) -> int:
	return PENDING


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
