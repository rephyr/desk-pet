class_name TimeoutChooser
extends Chooser
## Small parties: the player gets a prompt, and if they don't answer in time the event's
## default option is taken. That also happens while the game is closed.

const TIMEOUT := 60.0  # seconds


func choose(event: Dictionary, allowed: Array[int], state: RunState, now: float) -> int:
	if state.answer in allowed:
		return state.answer
	if now >= deadline(state):
		return default_option(event, allowed)
	return PENDING


## Answered: when the player answered. Timed out: exactly at the deadline, so a run that went on
## while the game was closed comes out the same as if you'd watched it.
func decided_at(state: RunState, now: float) -> float:
	return now if state.answer >= 0 else deadline(state)


static func deadline(state: RunState) -> float:
	return state.waiting_since + TIMEOUT
