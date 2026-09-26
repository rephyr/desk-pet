class_name PolicyChooser
extends Chooser
## Stub: options picked by rules the player sets, like "always fight", "retreat if losses pass
## 60%" or "leave the wounded behind" (large swarms). For now it always takes the event's
## default option; the rules (and matching them against option tags) come later.


func choose(event: Dictionary, allowed: Array[int], _state: RunState, _now: float) -> int:
	return default_option(event, allowed)
