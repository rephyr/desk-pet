class_name WishPart
extends RefCounted
## GameState's code for the wishing jar.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## Whether the wishing jar is out (beside the collection book).
func wish_open() -> bool:
	return gs.feature_on("wish")


## Wishes for a sticker you've found (a part's book key). Returns whether it worked.
func set_wish(key: String) -> bool:
	if not wish_open() or not Wish.can_wish(gs.catalog, key) or gs.collection.times_seen(key) <= 0 or gs.wish.on == key:
		return false
	gs.wish.on = key
	gs.wish_changed.emit(0)
	gs.save_game()
	return true


## The jar's shelves: rarity id -> { n: pets that may go (spare_pick), first: the face of the one
## that would go first }.
func wish_shelves() -> Dictionary:
	var out := {}
	var shelves := gs.spare_shelves()
	for r in shelves:
		out[r] = { "n": int(shelves[r].n), "first": gs.spare_face(str(r)) }
	return out


## Sends `n` pets of a rarity into the wished look's jar (-1: as many as fit): the ones that may go
## (spare_pick), plainest finish first. They never come back (a star each). Returns { sent, before, after } (full
## steps before and after).
func send_to_wish(rarity: String, n: int) -> Dictionary:
	var key: String = gs.wish.on
	var before := int(Wish.where(gs.catalog, Wish.sent(gs.wish, key)).full)
	var out := { "sent": 0, "before": before, "after": before }
	if not wish_open() or key == "" or n == 0:
		return out
	var room := Wish.room(gs.catalog, gs.wish, key)
	var take := room if n < 0 else mini(n, room)
	if take <= 0:
		return out
	var got := gs._take_spare(rarity, take, int(gs.catalog.wish.get("dots", 90)), true)  # each one is a star in the night sky now
	var sent := int(got.n)
	if sent <= 0:
		return out
	Wish.add(gs.catalog, gs.wish, key, sent, got.palettes)
	var after := int(Wish.where(gs.catalog, Wish.sent(gs.wish, key)).full)
	if after > before:
		gs._roller.wish = Wish.weights(gs.catalog, gs.wish)
	out.sent = sent
	out.after = after
	gs.wish_changed.emit(after if after > before else 0)
	gs.changed.emit()
	gs.save_game()
	return out


## Sets how many pets are in a look's jar and wishes for it (the dev driver's "wish" step).
func debug_wish(key: String, sent_n := -1) -> bool:
	if not Wish.can_wish(gs.catalog, key):
		return false
	if gs.collection.times_seen(key) <= 0:
		gs.collection.see(key)
	gs.wish.on = key
	if sent_n >= 0:
		var jar: Dictionary = gs.wish.jars.get(key, { "sent": 0, "dots": [] })
		jar.sent = clampi(sent_n, 0, Wish.total(gs.catalog))
		if (jar.dots as Array).is_empty():  # some colour to look at
			var pals: Array = gs.catalog.slots.palette.map(func(p): return str(p.id))
			for i in mini(jar.sent, int(gs.catalog.wish.get("dots", 90))):
				jar.dots.append(pals[(i * 3 + (i >> 2)) % mini(5, pals.size())])
		gs.wish.jars[key] = jar
	gs._roller.wish = Wish.weights(gs.catalog, gs.wish)
	gs.wish_changed.emit(0)
	gs.changed.emit()
	return true
