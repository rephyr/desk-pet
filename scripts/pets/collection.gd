class_name Collection
extends RefCounted
## Every pet the player owns, which one is active, and the collection book
## (how many times each part and each body+finish combo has been pulled).
## Pets that didn't come back are kept only as `fallen` (for the night sky); the book keeps them.

signal pets_added(pets: Array[Pet])
signal active_changed(pet: Pet)
signal pets_removed(uids: Array[String])
signal pet_changed(pet: Pet)  # a pet's parts changed (sewn on)
signal seen_changed  # see() counted a book key without a pet (the book redraws, full pages open)

var pets: Array[Pet] = []  # in pull order
var active_uid := ""
## The first pet you get becomes active by itself; the tutorial turns this off so you choose.
var auto_active := true
var _by_uid := {}
var _next_id := 1
var _seen := {}  # book key -> times pulled, see part_key() / finish_key()
## One [uid, palette] per pet that didn't come back, in order. Never shown as a list.
var fallen: Array = []


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
		for slot in Catalog.SLOTS:
			_count(part_key(slot, pet.parts[slot]))
		_count(finish_key(pet.parts.body, pet.finish))
	var became_active := active_uid == "" and auto_active and not pets.is_empty()
	if became_active:
		active_uid = pets[0].uid
	pets_added.emit(new_pets)
	if became_active:
		active_changed.emit(active())  # your first pet: it sits on the moon and starts talking


## Takes pets out of the collection for good (they didn't come back).
func remove(uids: Array[String]) -> void:
	var gone: Array[String] = []
	for uid in uids:
		var pet: Pet = _by_uid.get(uid)
		if pet == null:
			continue
		pets.erase(pet)
		_by_uid.erase(uid)
		fallen.append([int(uid), pet.parts.palette])
		gone.append(uid)
	if gone.is_empty():
		return
	if not _by_uid.has(active_uid):
		active_uid = pets[0].uid if not pets.is_empty() else ""
		active_changed.emit(active())
	pets_removed.emit(gone)


func get_pet(uid: String) -> Pet:
	return _by_uid.get(uid)


func active() -> Pet:
	return get_pet(active_uid)


func set_active(uid: String) -> void:
	if uid == active_uid or not _by_uid.has(uid):
		return
	active_uid = uid
	active_changed.emit(active())


func times_seen(key: String) -> int:
	return _seen.get(key, 0)


## Counts a book key as pulled `n` more times without a pet (the dev driver's "book" step, tests).
func see(key: String, n := 1) -> void:
	_seen[key] = _seen.get(key, 0) + n
	seen_changed.emit()


func _count(key: String) -> void:
	_seen[key] = _seen.get(key, 0) + 1


func to_dict() -> Dictionary:
	var list := []
	for pet in pets:
		list.append(pet.to_dict())
	return { "pets": list, "active": active_uid, "next_id": _next_id, "seen": _seen, "fallen": fallen }


## Replaces the contents in place, so everything connected to this collection stays connected.
func load_from(d: Dictionary) -> void:
	pets.clear()
	_by_uid.clear()
	_seen.clear()
	for raw in d.get("pets", []):
		var pet := Pet.from_dict(raw)
		pets.append(pet)
		_by_uid[pet.uid] = pet
	active_uid = str(d.get("active", ""))
	if not _by_uid.has(active_uid):
		active_uid = pets[0].uid if auto_active and not pets.is_empty() else ""
	_next_id = int(d.get("next_id", pets.size() + 1))
	for key in d.get("seen", {}):
		_seen[key] = int(d.seen[key])
	fallen.clear()
	for f in d.get("fallen", []):
		if f is Array and f.size() == 2:
			fallen.append([int(f[0]), str(f[1])])
	pets_added.emit(pets)
	active_changed.emit(active())


static func from_dict(d: Dictionary) -> Collection:
	var c := Collection.new()
	c.load_from(d)
	return c
