class_name ToysPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Plays whose time is up end (the toys wear a little); with the toy shelf built your pet takes
## the same toy back down for the same length (unless you tapped it: this one goes back on the
## shelf). Returns the editions that ended and weren't handed again.
func _finish_plays(now: float) -> Array:
	var again: Array = Toys.ending(gs.toys, now) if gs.built("shelf") else []
	var ended := Toys.finish_plays(gs.toys, now)
	var handed := false
	for p in again:
		if Toys.play(gs.toys, gs.catalog, str(p.key), str(p.play), now):
			ended.erase(p.key)
			handed = true
	if handed:
		gs.toys_changed.emit()
		gs.save_game()
	return ended


## With the toy shelf built, whether the shelf hands this play again when it ends (tapping the
## playing toy flips it). Returns the new setting, or false when there's nothing to flip.
func toy_again(edition: String) -> bool:
	if not gs.built("shelf"):
		return false
	var on := Toys.flip_again(gs.toys, edition, Time.get_unix_time_from_system())
	gs.toys_changed.emit()
	gs.save_game()
	return on


## Your pet starts playing with a toy (Toys.play). Returns whether it could.
func play_toy(edition: String, play_id: String) -> bool:
	if not Toys.play(gs.toys, gs.catalog, edition, play_id, Time.get_unix_time_from_system()):
		return false
	gs.toys_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Fixes a toy's wear on the workbench. Returns whether you could afford it.
func fix_toy(edition: String) -> bool:
	var price := Toys.fix_cost(gs.toys, gs.catalog, edition)
	if price <= 0 or gs.coins < price or Toys.playing(gs.toys, edition, Time.get_unix_time_from_system()):
		return false
	gs.coins -= price
	gs.toys.owned[edition].wear = 0.0
	gs.toys_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## Combines spares into the next level (Toys.combine). Returns whether it could.
func combine_toy(edition: String) -> bool:
	if not Toys.combine(gs.toys, gs.catalog, edition):
		return false
	gs.toys_changed.emit()
	gs.save_game()
	return true


## Sacrifices spares of a toy for a chance at a special finish. Returns the finish, or "".
func sacrifice_toy(id: String) -> String:
	if not Toys.can_sacrifice(gs.toys, gs.catalog, id):
		return ""
	var got := Toys.sacrifice(gs.toys, gs.catalog, id, gs._rng)
	gs.toys_changed.emit()
	gs.save_game()
	return got


## Up to `tries` sacrifices at once (Toys.sacrifice_many). Returns finish (or "nothing") -> how many.
func sacrifice_toys(id: String, tries: int) -> Dictionary:
	var got := Toys.sacrifice_many(gs.toys, gs.catalog, id, tries, gs._rng)
	if not got.is_empty():
		gs.toys_changed.emit()
		gs.save_game()
	return got


## Levels an edition up as far as its spares go (Toys.combine_all). Returns the levels.
func combine_toy_all(edition: String) -> int:
	var n := Toys.combine_all(gs.toys, gs.catalog, edition)
	if n > 0:
		gs.toys_changed.emit()
		gs.save_game()
	return n


## Shines a favourite one star (Toys.shine). Returns whether it could.
func shine_toy(edition: String) -> bool:
	if not Toys.shine(gs.toys, gs.catalog, edition):
		return false
	gs.toys_changed.emit()
	gs.save_game()
	return true
