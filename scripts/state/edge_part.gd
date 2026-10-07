class_name EdgePart
extends RefCounted
## A part of GameState (see tools/state_parts.py): its code for one area, on GameState's state
## (gs). GameState forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Whether the beyond map has the signpost to send pets past: the edge is open and a page in
## data/edge.json still needs pets.
func edge_open() -> bool:
	return gs.feature_on("edge") and not Edge.done(gs.catalog, gs.edge)


## Whether the beyond map is torn at the edge (it stays torn once every page is full).
func edge_torn() -> bool:
	return gs.feature_on("edge")


## Pets still to go before the page tucked under the edge opens.
func edge_to_go() -> int:
	return Edge.to_go(gs.catalog, gs.edge)


## Whether the page past the edge `page_id` is full (the unlock earn key "edge").
func edge_done(page_id: String) -> bool:
	return Edge.page_full(gs.catalog, gs.edge, page_id)


## Resting pets from the herd by rarity: rarity -> how many (rarities with none are left out).
func resting_shelves() -> Dictionary:
	var out := {}
	var h := gs.resting_herd()
	for tier in gs.catalog.tiers:
		var n := 0
		for k in h:
			if Herd.rarity_of(k) == tier.id:
				n += int(h[k])
		if n > 0:
			out[tier.id] = n
	return out


## Sends `n` pets of a rarity past the edge (-1: as many as are still to go): the ones that may go
## (spare_pick), off their errands if they have to. They never come back: a star each, a scribble
## on the page; a full page opens (_open_edge_pages). Returns how many went.
func send_past_edge(rarity: String, n: int) -> int:
	if not edge_open():
		return 0
	n = edge_to_go() if n < 0 else mini(n, edge_to_go())
	if n <= 0:
		return 0
	var got := gs._take_spare(rarity, n, int(gs.catalog.edge.get("stars_kept_per_send", 64)), true)  # a star each
	var sent := int(got.n)
	if sent <= 0:
		return 0
	Edge.add(gs.catalog, gs.edge, sent, got.palettes)
	gs.check_unlocks()
	_open_edge_pages()
	gs.edge_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return sent


## Every page past the edge that's full opens (next door: its unlock is `called`, see open_page).
## Also after a load: a later build may have lowered a page's need (Edge.clean fills it then).
func _open_edge_pages() -> void:
	for p in Edge.pages(gs.catalog):
		var id := str(p.get("id", ""))
		if edge_done(id) and not gs.catalog.page_info(id).is_empty() and not gs.page_open(id):
			gs.open_page(id)


## Whether the school page is there.
func school_open() -> bool:
	return gs.feature_on("school")


## Sits `n` pets of a rarity down in the class (-1: every seat left): the ones that may go
## (spare_pick), off their errands if they have to. Returns how many sat down.
func seat_in_school(rarity: String, n: int) -> int:
	if not school_open():
		return 0
	var left := School.seats_left(gs.catalog, gs.school)
	n = left if n < 0 else mini(n, left)
	if n <= 0:
		return 0
	var got := gs._take_spare(rarity, n, 0, false)  # they stay on as pupils: no stars
	var sat := School.seat(gs.catalog, gs.school, got.counts)  # (n is at most the seats left: everyone sits)
	gs.school_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return Herd.total(sat)


func class_full() -> bool:
	return School.full(gs.catalog, gs.school)


## You ring the bell: a full class stays on as teachers for good (no stars: they stay) and every worker gets
## quicker. Returns whether it rang.
func ring_bell() -> bool:
	if not class_full():
		return false
	var number: int = gs.school.classes.size()
	var faces := []
	var keys := School.desk_keys(gs.catalog, gs.school.seated, 3)
	for i in keys.size():
		faces.append(GameStateNode.school_face(keys[i], number * 8 + i))
	School.ring(gs.catalog, gs.school, faces)  # they stay on as teachers: no stars (only pets that leave or are lost)
	school_changed_boost()
	gs.school_changed.emit()
	gs.automation_changed.emit()
	gs.jobs_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## How much quicker every worker is from the school's classes: the `school` source of the
## "automation" and "errands" boosts (see boost_parts; machines, box tables, errand crews).
func school_boost() -> float:
	return gs._school_x


## Works the school's boost out again (after the classes changed: the bell, a load, a new game).
func school_changed_boost() -> void:
	gs._school_x = School.boost(gs.school)
	gs._boosts_changed()


## Pets a minute from box workers (a box holds one pet), or 0 when none are coming: no box workers,
## a full room, or no boxes on the pile they may open (_workers_open).
func pets_a_minute() -> float:
	if gs.workers_count("boxes") <= 0 or gs.room_left() <= 0:
		return 0.0
	if not gs.catalog.boxes.any(func(box): return not box.get("hidden", false) and gs.pet_opens(box.id) and gs.in_bag(box.id) > 0):
		return 0.0
	return gs.workers_speed("boxes") * gs.boost("automation") * 60.0 / Automation.worker_seconds(gs.catalog, gs.automation, "boxes")
