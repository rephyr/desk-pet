class_name CarePart
extends RefCounted
## GameState's code for care (food, mood, pats and their buffs), presents and rummaging.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Presents in the pocket, waiting for you to open them.
func gifts_waiting() -> int:
	return int(gs.gifts.pocket)


## Whether presents come yet: from when the boxes tab opens (hidden until then).
func gifts_open() -> bool:
	return gs.tab_open("boxes")


## Moves the present clock on to `now` (every second while open, and once on load for the time
## closed: the same either way). `save`: save when one came in.
func _tick_gifts(now: float, save := true) -> void:
	var started := float(gs.gifts.next_at) > 0.0
	var added := Gifts.tick(gs.gifts, gs.catalog.gifts, now, gifts_open())
	if added > 0 or started != (float(gs.gifts.next_at) > 0.0):
		gs.gifts_changed.emit()
		if save:
			gs.save_game()


## Opens a present from the pocket: it's rolled now, so the box is your newest tier today. Boxes go
## on your pile; a toy capsule goes into your toys, the way the machine gives one. Never bits, never
## a pet. Returns { box, boxes, toy: { id, finish, new } or {} }, or {} when the pocket is empty.
func open_gift() -> Dictionary:
	if gifts_waiting() <= 0:
		return {}
	gs.gifts.pocket = gifts_waiting() - 1
	var toys_open := gs._machine_gives("toy")
	var got := Gifts.roll(gs.catalog.gifts, gs._rng, toys_open)
	if gs.debug_gift_roll != "" and OS.is_debug_build():
		got = { "boxes": 2 if gs.debug_gift_roll == "two" else 1, "toy": gs.debug_gift_roll == "toy" and toys_open }
		gs.debug_gift_roll = ""
	var box := gs.newest_box_id()
	var toy := {}
	if got.toy:
		var t := Toys.roll(gs.catalog, gs._rng, gs.boost("luck"), Machine.toy_sets(gs.machine, gs.catalog))  # only sets whose hatch is open
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(gs.toys, t.id, t.finish) }
		gs.toys_changed.emit()
	gs.grant({ "box:" + box: int(got.boxes) })  # checks unlocks (a first toy) and emits changed
	gs.gifts_changed.emit()
	gs.save_game()
	return { "box": box, "boxes": int(got.boxes), "toy": toy }


## Debug: n presents in the pocket now (up to the pocket's size), the clock started.
func debug_set_gifts(n: int) -> void:
	gs.gifts.pocket = clampi(n, 0, Gifts.cap(gs.catalog.gifts))
	if float(gs.gifts.next_at) <= 0.0:
		gs.gifts.next_at = Time.get_unix_time_from_system() + Gifts.every(gs.catalog.gifts)
	gs.gifts_changed.emit()


## Debug: the present clock moves `hours` on (to check the step and the pocket's size).
func debug_gift_clock(hours: float) -> void:
	if float(gs.gifts.next_at) > 0.0:
		gs.gifts.next_at = float(gs.gifts.next_at) - hours * 3600.0
	_tick_gifts(Time.get_unix_time_from_system())


## Coins a snack (the feed button) costs now: data/care.json "snack" capsules at what a plain capsule
## is worth, so it grows with the machine.
func snack_price() -> int:
	return Care.snack_price(gs.catalog, gs.capsule_value())


## Gives your pet a snack, if it has room for one and you can pay. Returns whether it ate.
func feed() -> bool:
	var price := snack_price()
	var snack: Dictionary = gs.catalog.care.get("snack", {})
	if gs.coins < price or gs.hunger >= float(snack.get("full_at", 99)):
		return false
	gs.coins -= price
	gs.hunger = minf(100.0, gs.hunger + float(snack.get("food", 30)))
	gs.happiness = minf(100.0, gs.happiness + float(snack.get("mood", 5)))
	_check_care()
	gs.changed.emit()
	return true


## A pat: mood goes up, at most once every data/care.json pat.every seconds (a pat in between is
## still a pat, just no mood).
func pat() -> void:
	var p: Dictionary = gs.catalog.care.get("pat", {})
	var now := Time.get_unix_time_from_system()
	if now - gs._pat_at < float(p.get("every", 0)):
		return
	gs._pat_at = now
	gs.happiness = minf(100.0, gs.happiness + float(p.get("mood", 8)))
	_check_care()
	gs.changed.emit()


## Sets food and mood (the dev step `care`), kept between the floor and 100.
func set_care(food: float, mood: float) -> void:
	gs.hunger = clampf(food, Care.floor_value(gs.catalog), 100.0)
	gs.happiness = clampf(mood, Care.floor_value(gs.catalog), 100.0)
	_check_care()
	gs.changed.emit()


## Food or mood moved: when a care buff turned on or off, the boosts it's on are worked out again.
func _check_care() -> void:
	var now := Care.on_ids(gs.catalog, gs.hunger, gs.happiness)
	if now == gs._care_on:
		return
	gs._care_on = now
	_forget_care_boosts()
	if not gs._loading:
		gs.changed.emit()


## The kept totals of the kinds care boosts go stale (a buff turned on or off, or time away began
## or ended).
func _forget_care_boosts() -> void:
	for b in gs.catalog.care.get("buffs", []):
		gs._boosts.erase(str(b.kind))


## Does `work` for time the computer slept without the care buffs: like food and mood, they only
## count while the game is open (time closed is the same: boost_parts leaves them out while loading).
func _without_care(work: Callable) -> void:
	gs._away = true
	_forget_care_boosts()
	work.call()
	gs._away = false
	_forget_care_boosts()


## Whether your pet can rummage in its room yet (once you have a pet).
func rummage_open() -> bool:
	return gs.collection.active() != null


## Whether this spot in your pet's room has something in it.
func rummage_ready(spot_id: String) -> bool:
	return rummage_open() and float(gs.rummaged.get(spot_id, 0.0)) <= Time.get_unix_time_from_system()


## Your pet dug through a spot in its room: coins, sometimes xp, now and then a common part. The
## spot refills after a while. Returns what it found, e.g. { "coins": 3, "xp": 1 } (empty if the
## spot wasn't ready).
func rummage(spot_id: String) -> Dictionary:
	var spot := gs.catalog.rummage_spot(spot_id)
	if spot.is_empty() or not rummage_ready(spot_id):
		return {}
	gs.rummaged[spot_id] = Time.get_unix_time_from_system() + float(spot.refill)
	var found := { "coins": roundi(gs._rng.randi_range(int(spot.coins[0]), int(spot.coins[1])) * gs.boost("rummage")) }
	if gs._rng.randf() < float(spot.get("xp_chance", 0.0)):
		found.xp = gs.add_xp(1)
	var loot := { "coins": found.coins }
	if gs.feature_on("parts") and gs._rng.randf() < float(spot.get("part_chance", 0.0)):
		var key := "part:%s:%s" % Rewards.roll_part(Jobs.COMMON_BOX, gs._rng, gs.catalog)
		loot[key] = 1
		found.part = key
	gs.grant(loot)
	return found


func set_pet_out(value: bool) -> void:
	gs.pet_out = value
	gs.changed.emit()
