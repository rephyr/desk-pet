class_name PlayerChooser
extends Chooser
## The player picks every option (one pet, fully hands-on). The pick is stored on the run by
## GameState.answer_event(), so it survives a restart; until then the run waits.


func choose(_event: Dictionary, allowed: Array[int], state: RunState, _now: float) -> int:
	return state.answer if state.answer in allowed else PENDING
