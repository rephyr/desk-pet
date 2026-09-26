class_name PolicyChooser
extends Chooser
## Swarms: options are picked by rules the player sets, like "always fight", "go home if losses
## pass 60%" or "leave the wounded behind". Comes with the automation unlock. For now it always
## takes the event's default option; the rules (matched against option tags) come later.


func choose(event: Dictionary, allowed: Array[int], _state: RunState, _now: float) -> int:
	return default_option(event, allowed)


## Rules decide on the spot.
func decided_at(state: RunState, _now: float) -> float:
	return state.next_at
