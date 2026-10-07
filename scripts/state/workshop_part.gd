class_name WorkshopPart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Whether the shed workshop is open (the old shed is ours and the whistle is found).
func workshop_open() -> bool:
	return gs.feature_on("workshop")


## Whether tapping the shed opens the workshop card: it's open and something's still pinned.
func workshop_shown() -> bool:
	return workshop_open() and not Workshop.pinned(gs.workshop).is_empty()


## Whether a drawing is built (its chore is taken away).
func built(id: String) -> bool:
	return Workshop.has(gs.workshop, id)


## How many pets of a rarity could go and help on a pinned drawing right now: plain pets the new
## homes stall may take (see spare_pick), as many as still help it (Workshop.useful).
func helpers_can_go(id: String, rarity: String) -> int:
	var useful := Workshop.useful(gs.catalog, gs.workshop, id, rarity)
	if useful <= 0:
		return 0
	return mini(useful, gs.homes_can_go(rarity))


## `n` pets of a rarity (-1: as many as help) go and help build a pinned drawing. They come off
## their errands and machines if they have to, and stay on for good: they leave the collection with
## no star. Returns how many went.
func send_helpers(id: String, rarity: String, n := 1) -> int:
	if not workshop_open() or not id in Workshop.pinned(gs.workshop):
		return 0
	var useful := Workshop.useful(gs.catalog, gs.workshop, id, rarity)
	if useful <= 0:
		return 0
	var gone := int(gs._take_spare(rarity, useful if n < 0 else mini(n, useful), 0, false).n)
	if gone <= 0:
		return 0
	Workshop.take(gs.catalog, gs.workshop, id, rarity, gone)
	gs.workshop_changed.emit("")
	gs.changed.emit()
	gs.save_game()
	return gone


## Builds a full drawing: the next one is pinned in its spot and the built thing stands on the map.
func build_drawing(id: String) -> bool:
	if not workshop_open() or Workshop.build(gs.catalog, gs.workshop, id) == null:
		return false
	_built(id)
	return true


## Dev: a pinned drawing is built for free, whatever its helpers.
func debug_build(id: String) -> bool:
	if Workshop.finish(gs.catalog, gs.workshop, id) == null:
		return false
	_built(id)
	return true


func _built(id: String) -> void:
	gs._milestone("built_" + id)
	if id == "chart":
		gs.jobs_changed.emit()  # every errand has "new pets join here" now
	gs.workshop_changed.emit(id)
	gs.adventures_changed.emit()
	gs.changed.emit()
	gs.save_game()


## The next postcard waiting (the bell rope welcomed its trip back), taken off the pile, or {}.
func take_postcard() -> Dictionary:
	return gs.postcards.pop_front() if not gs.postcards.is_empty() else {}


## The weather vane answers a trip waiting at a plain choice with your last pick there (see
## Workshop.vane_pick). Never the trip you're watching on the trail. Returns whether it answered.
func _vane(run: RunState) -> bool:
	if not built("vane") or run == gs.watching:
		return false
	var pick := Workshop.vane_pick(gs.catalog, gs.workshop, run)
	if pick < 0:
		return false
	run.answer = pick
	gs._advance(run)
	return true


## What the built things do every second: the bell rope welcomes trips back (their postcards wait),
## the garden spade digs the room's rummage spots, the sewing basket mends resting toys.
func _workshop_chores(now: float) -> void:
	var gap := clampf(now - gs._mend_at, 0.0, 60.0) if gs._mend_at > 0.0 else 0.0
	gs._mend_at = now
	if built("basket"):
		# quietly, once a minute (the toy views rebuild on toys_changed)
		gs._mend_acc += gap
		if gs._mend_acc >= 60.0:
			var per := float(gs.catalog.workshop.get("basket_mend_per_hour", 0.0)) * gs._mend_acc / 3600.0
			gs._mend_acc = 0.0
			if Toys.mend(gs.toys, per, now):
				gs.toys_changed.emit()
	if built("spade") and not gs.tutorial_active():
		for spot in gs.catalog.rummage_spots:
			if gs.rummage_ready(str(spot.id)):
				gs.rummage(str(spot.id))
	if built("bell"):
		_ring_bell()


## The bell rope: every trip you sent that's home is welcomed back by itself (not the one you're
## watching on the trail; your pet's own trips welcome themselves already). Its postcard waits.
func _ring_bell() -> void:
	var keep := int(gs.catalog.workshop.get("letterbox_keep", 30))
	for run in gs.runs.duplicate():
		if run.auto or run == gs.watching or run.status != RunState.Status.DONE:
			continue
		var told := gs.announcements.size()
		var trip := gs.collect_run(run)
		if trip.is_empty():
			continue
		# what your pet has to say about this trip goes with its postcard (told when it pops up)
		trip.news = gs.news
		trip.announce = gs.announcements.slice(told)
		gs.news = {}
		gs.announcements.resize(told)
		gs.postcards.append(trip)
		while gs.postcards.size() > keep:
			gs.postcards.pop_front()
