class_name PerksPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## A perk's level (0 = not bought).
func perk_level(id: String) -> int:
	return Perks.level(gs.perks, id)


## The perks on the wall now, in order: the chain's nails the army has been deep enough for (and
## whose needs is open), then the 2 tips once the chain is done. [] while the dungeon is closed.
func perks_shown() -> Array[String]:
	if not gs.dungeon_open():
		return []
	return Perks.shown(gs.catalog, gs.perks, int(gs.dungeon.deep), gs.is_open)


## What a perk's next level costs in wisps (-1 when maxed).
func perk_price(id: String) -> int:
	return Perks.price(gs.catalog, gs.perks, id)


## Whether a perk can be bought now, wisps aside: it shows, it isn't maxed, the one above has a level.
func perk_available(id: String) -> bool:
	return gs.dungeon_open() and Perks.available(gs.catalog, gs.perks, id, int(gs.dungeon.deep), gs.is_open)


## Whether a perk on the well wall can be bought right now with the wisps you hold (the perks
## button's gold dot).
func perks_affordable() -> bool:
	for id in perks_shown():
		if perk_available(id) and gs.wisps >= perk_price(id):
			return true
	return false


## The next perk down the chain the army hasn't been deep enough for yet (its "needs" open): the
## wall's carrot ({} when there's none).
func perk_carrot() -> Dictionary:
	if not gs.dungeon_open():
		return {}
	for p in Perks.chain(gs.catalog):
		if int(p.get("floor", 0)) > int(gs.dungeon.deep) and (str(p.get("needs", "")) == "" or gs.is_open(str(p.needs))):
			return p
	return {}


## Buys a perk's next level with wisps. False when it can't (not there yet, maxed, not enough wisps).
func buy_perk(id: String) -> bool:
	if not gs.dungeon_open():
		return false
	var cost := Perks.buy(gs.catalog, gs.perks, id, gs.wisps, int(gs.dungeon.deep), gs.is_open)
	if cost < 0:
		return false
	gs.wisps -= cost
	_perks_changed(id)
	return true


## Sets a perk's level for free (dev steps and tests).
func debug_perk(id: String, lv: int) -> void:
	if Perks.perk(gs.catalog, id).is_empty():
		return
	gs.perks[id] = lv
	gs.perks = Perks.clean(gs.catalog, gs.perks)
	_perks_changed(id)


func _perks_changed(id: String) -> void:
	gs._boosts_changed()
	if not gs.dungeon_running():
		gs._trim_army_herd()  # (a wider entrance never trims; kept for a save with a narrower one)
	gs.dungeon_changed.emit()  # (the well's nails and the nail card rebuild from this)
	gs.changed.emit()
	gs.save_game()


## The number a count gives now: its base plus its perk's step (see Perks.count).
func perk_count(name: String) -> float:
	return Perks.count(gs.catalog, gs.perks, name)


## Cards that fight in the dungeon's front row (data/dungeon.json front_row, the pinwheel perk adds).
func front_row_size() -> int:
	return int(perk_count("front_row"))


## Extra plushie holds from the perks (the thimble).
func perk_holds() -> int:
	return int(perk_count("holds"))


## Extra plushie nudges per pet that hops in (the ribbon).
func perk_nudges() -> int:
	return int(perk_count("nudges"))


## Hours your pet keeps leading the army while the game is closed (the music box; 0 without it).
func perk_away_hours() -> float:
	return perk_count("away_hours")
