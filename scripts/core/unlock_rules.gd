class_name UnlockRules
extends RefCounted
## Pure rules about data/unlocks.json that don't need the running game (GameState uses them).


## What `unlock_list` opens that nothing earned opens: every "opens" of an entry `is_earned` says
## no to, unless an entry it says yes to opens it too. Places (location:...) never close again.
static func stale(unlock_list: Array, is_earned: Callable) -> Array[String]:
	var earned := {}
	for entry in unlock_list:
		if is_earned.call(entry.earn):
			for o in entry.opens:
				earned[str(o)] = true
	var out: Array[String] = []
	for entry in unlock_list:
		for o in entry.opens:
			if not earned.has(str(o)) and not str(o).begins_with("location:") and not str(o) in out:
				out.append(str(o))
	return out
