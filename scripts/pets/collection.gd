class_name Collection
extends RefCounted
## Every pet the player owns, which one is active, and the collection book (how many times each
## part and each body+finish combo has been pulled).
## Pets come in two kinds (see Herd, data/herd.json):
##   CARDS, whole Pet records in `pets`: favourites, the active pet, holo or better, a pet that
##   brought a part new to the book, pets something needs whole right now (`busy`: away on an
##   adventure, a good pull waiting to be seen, leading a party), and each shelf's newest
##   keep_cards plain pets.
##   THE HERD, `herd`: every other plain pet, folded into a count per rarity x finish. When a shelf
##   gets more plain cards than keep_cards, the oldest one that may fold becomes a count.
## Totals (count, count_of, shiny_of, plain_count) are kept as running numbers: nothing ever loops
## over the herd, so a million pets cost the same as ten.
## Pets that didn't come back are kept only as stars (`fallen`, for the night sky); the book keeps them.

signal pets_added(pets: Array[Pet])
signal active_changed(pet: Pet)
signal pets_removed(uids: Array[String])
signal pet_changed(pet: Pet)  # a pet's parts changed (sewn on), or it became (or stopped being) a favourite
signal pets_folded(uids: Array, keys: Array)  # these cards became counts in the herd (same order)
signal herd_changed(keys: Array)  # these counts in the herd went up or down
signal stars_added(n: int)  # pets left for good without a uid of their own (past the edge, the school)

var pets: Array[Pet] = []  # the cards, in pull order
var herd := {}  # "rarity:finish" -> how many plain pets are folded into it
var active_uid := ""
## The first pet you get becomes active by itself; the tutorial turns this off so you choose.
var auto_active := true
var herd_ever := false  # a pet has folded into the herd at least once (the room pill shows from then)
## -> Dictionary of uids that must stay cards right now (GameState: away, pinned, leading a party).
var busy := Callable()
## Palettes of pets that didn't come back, in order (only the first fallen_keep). Never shown as a list.
var fallen: Array[String] = []
var fallen_n := 0  # every pet that ever left: a star each
## count key -> the first stand-in number not handed out yet (a lost stand-in's look never comes back)
var stand_next := {}

var _by_uid := {}
var _next_id := 1
var _seen := {}  # book key -> times pulled, see part_key() / finish_key()
var _total := 0
var _of_rarity := {}  # rarity -> pets (cards and herd)
var _shiny_of := {}  # rarity -> shiny pets (cards and herd)
var _plain := 0  # pets with a plain finish (cards and herd): what the room holds
var _herd_total := 0


static func part_key(slot: String, id: String) -> String:
	return "part:%s:%s" % [slot, id]


static func finish_key(body: String, finish: String) -> String:
	return "finish:%s:%s" % [body, finish]


func add(new_pets: Array[Pet]) -> void:
	for pet in new_pets:
		pet.uid = str(_next_id)
		_next_id += 1
		pets.append(pet)
		_by_uid[pet.uid] = pet
		var first := false
		for slot in Catalog.SLOTS:
			var key := part_key(slot, pet.parts[slot])
			first = first or not _seen.has(key)
			_see(key)
		_see(finish_key(pet.parts.body, pet.finish))
		pet.new_part = pet.new_part or first
		_tally(pet.rarity, pet.finish, 1)
	var became_active := active_uid == "" and auto_active and not pets.is_empty()
	if became_active:
		active_uid = pets[0].uid
	pets_added.emit(new_pets)
	if became_active:
		active_changed.emit(active())  # your first pet: it sits on the moon and starts talking
	refold()


## `n` plain pets straight into a count (debug and tests: they aren't rolled, so the book doesn't
## count them).
func add_plain(key: String, n: int) -> void:
	if n <= 0 or not _valid_key(key):
		return
	herd[key] = int(herd.get(key, 0)) + n
	_herd_total += n
	_tally(Herd.rarity_of(key), Herd.finish_of(key), n)
	herd_ever = true
	herd_changed.emit([key])


## Takes pets out of the collection for good (they didn't come back). A stand-in's uid takes one
## from its count. Every pet that leaves adds a star.
func remove(uids: Array[String]) -> void:
	var gone: Array[String] = []
	var from_herd := []  # count keys a stand-in left
	for uid in uids:
		var palette := ""
		if Herd.is_stand_in(uid):
			var key := Herd.key_of(uid)
			if int(herd.get(key, 0)) <= 0:
				continue
			var face := Herd.stand_in(_catalog(), uid)
			palette = str(face.parts.palette) if face else ""
			_herd_less(key, 1)
			stand_next[key] = maxi(int(stand_next.get(key, 0)), Herd.number_of(uid) + 1)
			from_herd.append(key)
		else:
			var pet: Pet = _by_uid.get(uid)
			if pet == null:
				continue
			pets.erase(pet)
			_by_uid.erase(uid)
			_tally(pet.rarity, pet.finish, -1)
			palette = str(pet.parts.palette)
		_star(palette)
		gone.append(uid)
	if gone.is_empty():
		return
	if not _by_uid.has(active_uid):
		active_uid = pets[0].uid if not pets.is_empty() else ""
		active_changed.emit(active())
	pets_removed.emit(gone)
	if not from_herd.is_empty():
		herd_changed.emit(from_herd)


## Takes up to `n` pets off a count for good (past the edge, into the school). Their looks never come
## back as stand-ins. Returns [how many, palettes of up to `keep` of them] (for scribbles and stars).
func take_plain(key: String, n: int, keep := 0) -> Array:
	var take := mini(n, herd_count(key))
	if take <= 0:
		return [0, []]
	var palettes := []
	for uid in stand_in_uids(key, mini(take, keep)):
		var face := Herd.stand_in(_catalog(), uid)
		if face:
			palettes.append(str(face.parts.palette))
	stand_next[key] = int(stand_next.get(key, 0)) + take
	_herd_less(key, take)
	herd_changed.emit([key])
	return [take, palettes]


## `n` pets left for good (not from the cards): a star each, tinted by `palettes` as far as they go
## (the night sky borrows colours for the rest).
func add_stars(palettes: Array, n: int) -> void:
	if n <= 0:
		return
	var keep := int(_catalog().herd.get("fallen_keep", 16384))
	for p in palettes.slice(0, n):
		if fallen.size() >= keep:
			break
		fallen.append(str(p))
	fallen_n += n
	stars_added.emit(n)


## A card by its uid, or a stand-in for a pet from a count ("h:common:normal:3", while that count
## has anyone in it). null if there's no such pet.
func get_pet(uid: String) -> Pet:
	if Herd.is_stand_in(uid):
		return Herd.stand_in(_catalog(), uid) if int(herd.get(Herd.key_of(uid), 0)) > 0 else null
	return _by_uid.get(uid)


func active() -> Pet:
	return get_pet(active_uid)


func set_active(uid: String) -> void:
	if uid == active_uid or not _by_uid.has(uid):
		return
	active_uid = uid
	active_changed.emit(active())
	refold()  # the old active pet may fold now


## Makes a card a favourite (on the cushion, never folds) or not (it may fold straight away if its
## shelf has keep_cards newer plain pets).
func set_fav(uid: String, on: bool) -> void:
	var pet: Pet = _by_uid.get(uid)
	if pet == null or pet.fav == on:
		return
	pet.fav = on
	pet_changed.emit(pet)
	if not on:
		refold()


func times_seen(key: String) -> int:
	return _seen.get(key, 0)


## Whether a pet always stays a card, whatever else happens.
func always_card(pet: Pet) -> bool:
	# F2: pets with buttons sewn on will stay cards too
	return pet.fav or pet.new_part or pet.uid == active_uid or not Herd.plain(_catalog(), pet.finish)


## Folds the oldest plain cards of every shelf that has more than keep_cards of them that may fold.
func refold() -> void:
	var keep := int(_catalog().herd.get("keep_cards", 20))
	var busy_now: Dictionary = busy.call() if busy.is_valid() else {}
	var free := {}  # rarity -> cards that may fold, oldest first
	for pet in pets:
		if not always_card(pet) and not busy_now.has(pet.uid):
			if not free.has(pet.rarity):
				free[pet.rarity] = []
			free[pet.rarity].append(pet)
	var gone := {}
	for rarity in free:
		var list: Array = free[rarity]
		for i in list.size() - keep:
			gone[list[i].uid] = list[i]
	if gone.is_empty():
		return
	var uids: Array = []
	var keys: Array = []
	var kept: Array[Pet] = []
	for pet in pets:
		if not gone.has(pet.uid):
			kept.append(pet)
			continue
		var key := Herd.key(pet.rarity, pet.finish)
		herd[key] = int(herd.get(key, 0)) + 1
		_herd_total += 1
		_by_uid.erase(pet.uid)
		uids.append(pet.uid)
		keys.append(key)
	pets = kept
	herd_ever = true
	pets_folded.emit(uids, keys)
	herd_changed.emit(keys)


# ---- totals (running numbers, never a loop over the herd) ----------------------------------

## Every pet you have: cards and the herd.
func count() -> int:
	return _total


func count_of(rarity: String) -> int:
	return int(_of_rarity.get(rarity, 0))


func shiny_of(rarity: String) -> int:
	return int(_shiny_of.get(rarity, 0))


## Pets with a plain finish, cards and herd together: what the room cap counts.
func plain_count() -> int:
	return _plain


func herd_total() -> int:
	return _herd_total


func herd_count(key: String) -> int:
	return int(herd.get(key, 0))


## The cards of one rarity, in pull order.
func cards_of(rarity: String) -> Array[Pet]:
	var out: Array[Pet] = []
	for pet in pets:
		if pet.rarity == rarity:
			out.append(pet)
	return out


## Up to `n` stand-in uids for a count, skipping `skip` (ones already in use). `offset` starts
## further along (so different crowds don't all show the same faces).
func stand_in_uids(key: String, n: int, skip := {}, offset := 0) -> Array[String]:
	var out: Array[String] = []
	var i := int(stand_next.get(key, 0)) + offset
	var tries := 0
	while out.size() < n and tries < n + skip.size() + 1:
		var uid := Herd.uid(key, i)
		i += 1
		tries += 1
		if not skip.has(uid):
			out.append(uid)
	return out


func to_dict() -> Dictionary:
	var list := []
	for pet in pets:
		list.append(pet.to_dict())
	return { "pets": list, "herd": herd, "active": active_uid, "next_id": _next_id, "seen": _seen, "fallen": fallen,
		"fallen_n": fallen_n, "stand_next": stand_next, "herd_ever": herd_ever }


## Replaces the contents in place, so everything connected to this collection stays connected.
## Saves from before the herd (no "herd") load too: stars keep their palettes, and the first pet
## with each part is marked (it stays a card). Folding waits for refold() (GameState calls it once
## everything that keeps pets busy has loaded).
func load_from(d: Dictionary) -> void:
	pets.clear()
	_by_uid.clear()
	_seen.clear()
	herd.clear()
	for raw in d.get("pets", []):
		var pet := Pet.from_dict(raw)
		pets.append(pet)
		_by_uid[pet.uid] = pet
	herd.merge(Herd.clean_counts(_catalog(), d.get("herd", {})))  # in place: the dictionary stays the same one
	active_uid = str(d.get("active", ""))
	if not _by_uid.has(active_uid):
		active_uid = pets[0].uid if auto_active and not pets.is_empty() else ""
	_next_id = int(d.get("next_id", pets.size() + 1))
	for key in d.get("seen", {}):
		_seen[key] = int(d.seen[key])
	fallen.clear()
	var keep := int(_catalog().herd.get("fallen_keep", 16384))
	var saved_fallen = d.get("fallen", [])  # untyped: a broken save's odd value is dropped, not a crash
	if not saved_fallen is Array:
		saved_fallen = []
	for f in saved_fallen:
		if fallen.size() >= keep:
			break
		if f is Array and f.size() == 2:
			fallen.append(str(f[1]))  # before the herd: [uid, palette]
		elif f is String:
			fallen.append(f)
	fallen_n = maxi(int(d.get("fallen_n", saved_fallen.size())), fallen.size())
	stand_next.clear()
	var saved_next = d.get("stand_next", {})
	if saved_next is Dictionary:
		for key in saved_next:
			if saved_next[key] is int or saved_next[key] is float:
				stand_next[str(key)] = maxi(0, int(saved_next[key]))
	herd_ever = bool(d.get("herd_ever", not herd.is_empty()))
	if not d.has("herd"):
		_mark_new_parts()
	_recount()
	pets_added.emit(pets)
	active_changed.emit(active())


static func from_dict(d: Dictionary) -> Collection:
	var c := Collection.new()
	c.load_from(d)
	return c


# ---- inside --------------------------------------------------------------------------------

func _catalog() -> Catalog:
	return Catalog.shared()


func _see(key: String) -> void:
	_seen[key] = _seen.get(key, 0) + 1


func _tally(rarity: String, finish: String, n: int) -> void:
	_total += n
	_of_rarity[rarity] = int(_of_rarity.get(rarity, 0)) + n
	if finish == "shiny":
		_shiny_of[rarity] = int(_shiny_of.get(rarity, 0)) + n
	if Herd.plain(_catalog(), finish):
		_plain += n


func _herd_less(key: String, n: int) -> void:
	var left := int(herd.get(key, 0)) - n
	if left > 0:
		herd[key] = left
	else:
		herd.erase(key)
	_herd_total -= n
	_tally(Herd.rarity_of(key), Herd.finish_of(key), -n)


func _star(palette: String) -> void:
	fallen_n += 1
	if fallen.size() < int(_catalog().herd.get("fallen_keep", 16384)):
		fallen.append(palette)


func _recount() -> void:
	_total = 0
	_of_rarity.clear()
	_shiny_of.clear()
	_plain = 0
	_herd_total = 0
	for pet in pets:
		_tally(pet.rarity, pet.finish, 1)
	for key in herd:
		_herd_total += int(herd[key])
		_tally(Herd.rarity_of(key), Herd.finish_of(key), int(herd[key]))


## Saves from before the herd: the first pet (in pull order) with each part brought it to the book.
func _mark_new_parts() -> void:
	var seen := {}
	for pet in pets:
		for slot in Catalog.SLOTS:
			var key := part_key(slot, pet.parts[slot])
			if not seen.has(key):
				seen[key] = true
				pet.new_part = true


func _valid_key(key: String) -> bool:
	return Herd.valid_key(_catalog(), key)
