class_name UnlockRules
extends RefCounted
## Pure rules about data/unlocks.json that don't need the running game (GameState uses them).


## What `unlock_list` opens that nothing earned opens: every "opens" of an entry `is_earned` says
## no to, unless an entry it says yes to opens it too. Places (location:...) never close again, nor
## does what only the game's code opens ("called", see GameState.open_page).
static func stale(unlock_list: Array, is_earned: Callable) -> Array[String]:
	var earned := {}
	for entry in unlock_list:
		if called(entry) or is_earned.call(entry.earn):
			for o in entry.opens:
				earned[str(o)] = true
	var out: Array[String] = []
	for entry in unlock_list:
		for o in entry.opens:
			if not earned.has(str(o)) and not str(o).begins_with("location:") and not str(o) in out:
				out.append(str(o))
	return out


## Whether only the game's code opens this unlock ("earn": { "called": true }): nothing you earn
## opens it by itself (check_unlocks skips it), GameState.open_page does.
static func called(entry: Dictionary) -> bool:
	return bool(entry.get("earn", {}).get("called", false))


## The unlock that opens `what` (e.g. "page:next_door"), or {}.
static func opening(unlock_list: Array, what: String) -> Dictionary:
	for entry in unlock_list:
		if what in entry.opens:
			return entry
	return {}
