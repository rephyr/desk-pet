class_name GearPart
extends RefCounted
## GameState's code for gear: the adventures' upgrades bought with xp, and what they do to a trip's
## loot.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


func gear_level(id: String) -> int:
	return Gear.level(gs.gear, id)


## The gear stickers on the path right now, in path order (see Gear.shown).
func shown_gear() -> Array[Dictionary]:
	return Gear.shown(gs.catalog, gs.gear, gs.is_open)


## Why a gear can't take another level ("" if it can, xp aside): "hidden" (not on the path yet) or "max".
func gear_block(id: String) -> String:
	var g := Gear.info(gs.catalog, id)
	if g.is_empty() or not shown_gear().any(func(s): return s.id == id):
		return "hidden"
	return "max" if gear_level(id) >= int(g.max) else ""


## xp for a gear's next level.
func gear_price(id: String) -> int:
	return Gear.price(gs.catalog, id, gear_level(id))


## Buys a gear's next level with xp. Returns whether it could.
func buy_gear(id: String) -> bool:
	if gear_block(id) != "" or gs.xp < gear_price(id):
		return false
	gs.xp -= gear_price(id)
	gs.gear[id] = gear_level(id) + 1
	gs.gear_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Sets a gear's level outright (the dev driver's "gear" step).
func set_gear_level(id: String, level: int) -> void:
	var g := Gear.info(gs.catalog, id)
	if g.is_empty():
		return
	gs.gear[id] = clampi(level, 0, int(g.max))
	gs.gear_changed.emit()
	gs.changed.emit()


## The upgrades page opens with the first xp (and stays open once something's bought).
func gear_page_open() -> bool:
	return gs.xp > 0 or gs.gear.values().any(func(lv): return int(lv) > 0)


## The gear a trip there would pack (for the place card's time and odds).
func trip_gear(location_id: String) -> Dictionary:
	return Gear.for_trip(gs.catalog, gs.gear, gs.catalog.location(location_id))


## A trip's haul, boosted as it's collected: the loot and coins boosts multiply its coins (and so
## does the tote bag in the trip's `packed` gear), and loot times luck gives a chance of an extra copy
## of every part and box. The trip's `knacks` (RunState.knacks): the party's own loot share, and
## "finds" gives a chance of an extra copy of every part and bit.
## Returns the coins' "why so much?" (see Boosts.why; {} when there were no coins).
func _boost_trip_loot(loot: Dictionary, packed := {}, knacks := {}) -> Dictionary:
	var tote := 1.0 + Gear.value(gs.catalog, packed, "coins")
	var more := gs.boost("loot") * float(knacks.get("loot", 1.0))  # the party's own knacks too
	var lucky := more * gs.boost("luck")
	var finds := float(knacks.get("finds", 1.0))  # knacks: more bits and parts
	var why := {}
	for key: String in loot.keys():
		if key.begins_with("part:") and not gs.feature_on("parts"):
			loot.erase(key)  # parts come much later in the game
			continue
		if key == "coins":
			var found := int(loot[key])
			loot[key] = GameStateNode.coins_int(int(loot[key]) * more * gs.boost("coins") * tote)
			why = Boosts.why("found on the way", found, [
				{ "name": _coin_gear_name(packed), "x": tote },
				{ "name": "the party's badges", "x": float(knacks.get("loot", 1.0)) },
				{ "name": "our boosts", "x": gs.boost("loot") * gs.boost("coins") }], int(loot[key]))
		elif key.begins_with("part:"):
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (lucky - 1.0 + finds - 1.0), gs._rng)
		elif key.begins_with("box:"):
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (lucky - 1.0), gs._rng)
		elif key.begins_with("bit:") and finds > 1.0:
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (finds - 1.0), gs._rng)
	return why


## The name of the gear that brings more trip coins ("a tote bag"), for the trip's "why so much?".
func _coin_gear_name(packed: Dictionary) -> String:
	for g in Gear.all(gs.catalog):
		if int(packed.get(str(g.id), 0)) > 0 and g.each.has("coins"):
			return str(g.name)
	return "our gear"
