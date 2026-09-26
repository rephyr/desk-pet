class_name TimeoutChooser
extends Chooser
## Stub: the player is prompted, and the default option is taken if they don't answer in time
## (small parties, popups). Not used by any dungeon yet.

const TIMEOUT := 60.0  # seconds


func choose(event: Dictionary, allowed: Array[int], state: RunState, now: float) -> int:
	if state.answer in allowed:
		return state.answer
	if now - state.waiting_since >= TIMEOUT:
		return default_option(event, allowed)
	return PENDING
