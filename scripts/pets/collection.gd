class_name Collection
extends RefCounted
## Every pet the player owns, which one is active, and the collection book
## (how many times each part and each body+finish combo has been pulled).

signal pets_added(pets: Array[Pet])
signal active_changed(pet: Pet)

var pets: Array[Pet] = []  # in pull order
var active_uid := ""
var _by_uid := {}
var _next_id := 1
var _seen := {}  # book key -> times pulled, see part_key() / finish_key()


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
	if active_uid == "" and not pets.is_empty():
		active_uid = pets[0].uid
	pets_added.emit(new_pets)


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


func _count(key: String) -> void:
	_seen[key] = _seen.get(key, 0) + 1


func to_dict() -> Dictionary:
	var list := []
	for pet in pets:
		list.append(pet.to_dict())
	return { "pets": list, "active": active_uid, "next_id": _next_id, "seen": _seen }


static func from_dict(d: Dictionary) -> Collection:
	var c := Collection.new()
	for raw in d.get("pets", []):
		var pet := Pet.from_dict(raw)
		c.pets.append(pet)
		c._by_uid[pet.uid] = pet
	c.active_uid = str(d.get("active", ""))
	c._next_id = int(d.get("next_id", c.pets.size() + 1))
	for key in d.get("seen", {}):
		c._seen[key] = int(d.seen[key])
	return c
