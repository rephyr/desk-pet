class_name Collection
extends RefCounted
## Every pet the player owns, which one is active, and the collection book (how many times each
## part and each body+finish combo has been pulled).
## Pets come in two kinds (see Herd, data/herd.json):
##   CARDS, whole Pet records in `pets`: favourites, the active pet, holo or better, a pet that
##   brought a part new to the book, a pet with buttons (the plushie machine), a pet a keep line keeps (the
##   sorting card, see Sewing), pets something needs whole right now (`busy`: away on an
##   adventure, a good pull waiting to be seen, leading a party), and each shelf's newest
##   keep_cards plain pets.
##   THE HERD, `herd`: every other plain pet, folded into a count per rarity x finish. When a shelf
##   gets more plain cards than keep_cards, the oldest one that may fold becomes a count.
## Totals (count, count_of, shiny_of, plain_count) are kept as running numbers: nothing ever loops
## over the herd, so a million pets cost the same as ten.
## Pets that didn't come back, or left for new homes, are kept only as stars (`fallen`, for the night
## sky); the book keeps them.

signal pets_added(pets: Array[Pet])
signal active_changed(pet: Pet)
signal pets_removed(uids: Array[String])
signal pet_changed(pet: Pet)  # a pet's parts changed (sewn on), or it became (or stopped being) a favourite
signal seen_changed  # see() counted a book key without a pet (the book redraws, full pages open)
signal pets_folded(uids: Array, keys: Array)  # these cards became counts in the herd (same order)
signal herd_changed(keys: Array)  # these counts in the herd went up or down
signal pets_left(n: int)  # n pets left for new homes (a star each)
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
## uid -> true: plain cards the sorting card's keep lines keep (GameState, from homes.kept): always cards
var keep_uids := {}

var _by_uid := {}
var _next_id := 1
var _seen := {}  # book key -> times pulled, see part_key() / finish_key()
var _finishes_seen := {}  # finish id -> true once any pet with it was pulled (from the finish: keys)
var _total := 0
var _of_rarity := {}  # rarity -> pets (cards and herd)
var _shiny_of := {}  # rarity -> shiny pets (cards and herd)
var _plain := 0  # pets with a plain finish (cards and herd): what the room holds
var _herd_total := 0
## The plain-finish cards, in pull order: all refold() ever needs to look at, so a pile of holo
## cards (always cards) costs it nothing.
var _plain_cards: Array[Pet] = []
var _plain_finish := {}  # finish id -> plain (Herd.plain, worked out once per finish)

const LEAVE_FACES := 16  # stand-in looks worked out for the stars of a count going (then cycled)


static func part_key(slot: String, id: String) -> String:
	return "part:%s:%s" % [slot, id]


static func finish_key(body: String, finish: String) -> String:
	return "finish:%s:%s" % [body, finish]


## A pet's part keys, plus its body+finish key when it has a finish (what "new" tags look at).
static func look_keys(pet: Pet) -> Array[String]:
	var out: Array[String] = []
	for slot in Catalog.SLOTS:
		out.append(part_key(slot, pet.parts[slot]))
	if pet.finish != "normal":
		out.append(finish_key(pet.parts.body, pet.finish))
	return out


## The look keys that came out of this box for the first time: call once the box's pets are in.
## A key is new when every time it was ever seen is a pet from this box (two pets in one box
## sharing a look you'd never had still count as new).
func new_keys(box_pets: Array[Pet]) -> Dictionary:
	var in_box := {}
	for p in box_pets:
		for key in look_keys(p):
			in_box[key] = int(in_box.get(key, 0)) + 1
	var out := {}
	for key in in_box:
		if times_seen(key) <= in_box[key]:
			out[key] = true
	return out


## Adds new pets (their uid is given here, and the book counts them). `sorter` (the sorting rule,
## see NewHomes) is asked about each pet once the book has counted it (so a part new to the book is
## known): "homes" and the pet leaves straight away (a star; it never takes room), "school" and it
## has sat down in the school's class (no star). Returns the pets that left.
func add(new_pets: Array[Pet], sorter := Callable()) -> Array[Pet]:
	var kept: Array[Pet] = []
	var left: Array[Pet] = []
	var homes_n := 0
	for pet in new_pets:
		pet.uid = str(_next_id)
		_next_id += 1
		var first := false
		for slot in Catalog.SLOTS:
			var key := part_key(slot, pet.parts[slot])
			first = first or not _seen.has(key)
			_see(key)
		_see(finish_key(pet.parts.body, pet.finish))
		pet.new_part = pet.new_part or first
		var to := str(sorter.call(pet)) if sorter.is_valid() else ""
		if to == "homes" or to == "school":  # it leaves straight away (new homes: a star; school: it stays on, no star)
			left.append(pet)
			if to == "homes":
				_star(str(pet.parts.palette))
				homes_n += 1
			continue
		pets.append(pet)
		_by_uid[pet.uid] = pet
		if _is_plain(pet.finish):
			_plain_cards.append(pet)
		_tally(pet.rarity, pet.finish, 1)
		kept.append(pet)
	var became_active := active_uid == "" and auto_active and not pets.is_empty()
	if became_active:
		active_uid = pets[0].uid
	if homes_n > 0:
		pets_left.emit(homes_n)
	if not kept.is_empty() or left.is_empty():
		pets_added.emit(kept)
	if became_active:
		active_changed.emit(active())  # your first pet: it sits on the moon and starts talking
	refold()
	return left


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
			_plain_cards.erase(pet)
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


## Takes `n` pets out of a count for good all at once (the dungeon's army lost them), a star each.
## Returns how many left (at most what the count has).
func lose_plain(key: String, n: int) -> int:
	n = _herd_to_stars(key, n)
	if n > 0:
		herd_changed.emit([key])
	return n


## Pets leave for new homes: `counts` (count key -> how many) come off the herd and `uids` are
## cards. Each one adds a star (a count's stars take the looks of the stand-ins that would have
## come next, and those looks never come back). Returns how many left. The active pet never leaves.
## `star` false: they stay on for good somewhere (landing holders): no star, and no pets_left.
func leave(counts: Dictionary, uids: Array, star := true) -> int:
	var n := 0
	var gone: Array[String] = []
	var drop := {}
	for raw in uids:
		var uid := str(raw)
		var pet: Pet = _by_uid.get(uid)
		if pet == null or uid == active_uid or drop.has(uid):
			continue
		drop[uid] = pet
		_by_uid.erase(uid)
		_tally(pet.rarity, pet.finish, -1)
		if star:
			_star(str(pet.parts.palette))
		gone.append(uid)
		n += 1
	if not drop.is_empty():
		if drop.size() <= 64:
			for uid in drop:
				pets.erase(drop[uid])
				_plain_cards.erase(drop[uid])
		else:
			var cards: Array[Pet] = []
			for pet in pets:
				if not drop.has(pet.uid):
					cards.append(pet)
			pets = cards
			var plain: Array[Pet] = []
			for pet in _plain_cards:
				if not drop.has(pet.uid):
					plain.append(pet)
			_plain_cards = plain
	var keys := []
	for key in counts:
		var k := str(key)
		var take := _herd_to_stars(k, int(counts[key])) if star else _herd_away(k, int(counts[key]))
		if take <= 0:
			continue
		keys.append(k)
		n += take
	if n == 0:
		return 0
	if star:
		pets_left.emit(n)
	if not gone.is_empty():
		pets_removed.emit(gone)
	if not keys.is_empty():
		herd_changed.emit(keys)
	return n


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


## Changes a card's finish (the dev `dress` step) and keeps the room count and the cards that may
## fold right.
func set_finish(pet: Pet, finish: String) -> void:
	if pet.finish == finish:
		return
	_tally(pet.rarity, pet.finish, -1)
	pet.finish = finish
	_tally(pet.rarity, pet.finish, 1)
	var plain := _is_plain(finish)
	if plain and not _plain_cards.has(pet):
		_plain_cards.append(pet)
	elif not plain:
		_plain_cards.erase(pet)
	pet_changed.emit(pet)


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


## Counts a book key as pulled `n` more times without a pet (the dev driver's "book" step, tests).
func see(key: String, n := 1) -> void:
	_seen[key] = _seen.get(key, 0) + n
	seen_changed.emit()


## Every book key pulled at least once (part_key / finish_key).
func seen_keys() -> Array:
	return _seen.keys()


## Whether any pet with this finish was ever pulled (the book has it).
func finish_seen(finish: String) -> bool:
	return _finishes_seen.has(finish)


## Whether a pet always stays a card, whatever else happens.
func always_card(pet: Pet) -> bool:
	return pet.fav or pet.new_part or not pet.buttons.is_empty() or pet.uid == active_uid or not _is_plain(pet.finish) or keep_uids.has(pet.uid)


## Folds the oldest plain cards of every shelf that has more than keep_cards of them that may fold.
func refold() -> void:
	var keep := int(_catalog().herd.get("keep_cards", 20))
	# a shelf with no more than keep plain cards has nothing to fold: skip the busy check then
	var plain_of := {}
	for pet in _plain_cards:
		plain_of[pet.rarity] = int(plain_of.get(pet.rarity, 0)) + 1
	if not plain_of.values().any(func(n): return n > keep):
		return
	var busy_now: Dictionary = busy.call() if busy.is_valid() else {}
	var free := {}  # rarity -> cards that may fold, oldest first
	for pet in _plain_cards:
		if int(plain_of[pet.rarity]) > keep and not always_card(pet) and not busy_now.has(pet.uid):
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
	for pet in _plain_cards:  # pull order, like pets
		if not gone.has(pet.uid):
			kept.append(pet)
			continue
		var key := Herd.key(pet.rarity, pet.finish)
		herd[key] = int(herd.get(key, 0)) + 1
		_herd_total += 1
		_by_uid.erase(pet.uid)
		uids.append(pet.uid)
		keys.append(key)
	_plain_cards = kept
	if gone.size() <= 64:
		for uid in uids:
			pets.erase(gone[uid])  # a few: erase is a native loop, quicker than a rebuild
	else:
		var cards: Array[Pet] = []
		for pet in pets:
			if not gone.has(pet.uid):
				cards.append(pet)
		pets = cards
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
	_plain_cards.clear()
	_by_uid.clear()
	_seen.clear()
	_finishes_seen.clear()
	herd.clear()
	for raw in d.get("pets", []):
		var pet := Pet.from_dict(raw)
		pets.append(pet)
		_by_uid[pet.uid] = pet
		if _is_plain(pet.finish):
			_plain_cards.append(pet)
	herd.merge(Herd.clean_counts(_catalog(), d.get("herd", {})))  # in place: the dictionary stays the same one
	active_uid = str(d.get("active", ""))
	if not _by_uid.has(active_uid):
		active_uid = pets[0].uid if auto_active and not pets.is_empty() else ""
	_next_id = int(d.get("next_id", pets.size() + 1))
	for key in d.get("seen", {}):
		_seen[key] = int(d.seen[key])
		if str(key).begins_with("finish:"):
			_finishes_seen[str(key).get_slice(":", 2)] = true
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
	if key.begins_with("finish:"):
		_finishes_seen[key.get_slice(":", 2)] = true


func _tally(rarity: String, finish: String, n: int) -> void:
	_total += n
	_of_rarity[rarity] = int(_of_rarity.get(rarity, 0)) + n
	if finish == "shiny":
		_shiny_of[rarity] = int(_shiny_of.get(rarity, 0)) + n
	if _is_plain(finish):
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


## Takes up to `n` pets off a count for good, a star each (the stars take the looks of the stand-ins
## that would have come next, and those looks never come back). Returns how many came off.
func _herd_to_stars(key: String, n: int) -> int:
	n = mini(n, herd_count(key))
	if n <= 0:
		return 0
	var palettes: Array[String] = []  # a few faces' colours for the stars, taken round and round
	for uid in stand_in_uids(key, mini(n, LEAVE_FACES)):
		var face := Herd.stand_in(_catalog(), uid)
		palettes.append(str(face.parts.palette) if face else "")
	_herd_less(key, n)
	stand_next[key] = int(stand_next.get(key, 0)) + n
	_stars(palettes, n)
	return n


## Takes up to `n` pets off a count for good with no star (they stay on somewhere); their looks go
## with them. Returns how many came off.
func _herd_away(key: String, n: int) -> int:
	n = mini(n, herd_count(key))
	if n <= 0:
		return 0
	_herd_less(key, n)
	stand_next[key] = int(stand_next.get(key, 0)) + n
	return n


## `n` stars at once, their colours taken round and round `palettes` (only up to fallen_keep kept).
func _stars(palettes: Array[String], n: int) -> void:
	fallen_n += n
	var room := mini(n, int(_catalog().herd.get("fallen_keep", 16384)) - fallen.size())
	for i in room:
		fallen.append(palettes[i % palettes.size()] if not palettes.is_empty() else "")


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


func _is_plain(finish: String) -> bool:
	if not _plain_finish.has(finish):
		_plain_finish[finish] = Herd.plain(_catalog(), finish)
	return _plain_finish[finish]


func _valid_key(key: String) -> bool:
	return Herd.valid_key(_catalog(), key)
