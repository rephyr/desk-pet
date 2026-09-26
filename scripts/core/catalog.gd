class_name Catalog
extends RefCounted
## Read-only game data loaded from data/*.json: rarities, parts, finishes, traits, boxes and
## adventures (types, locations and their events).
## Use Catalog.shared() everywhere; tests can build their own with Catalog.new().

const SLOTS: Array[String] = ["body", "palette", "pattern", "eyes", "accessory"]
const DATA_DIR := "res://data/"

static var _shared: Catalog

var tiers: Array[Dictionary] = []  # lowest to highest
var slots := {}  # slot -> Array[Dictionary] of parts
var finishes: Array[Dictionary] = []  # lowest to highest
var traits: Array[Dictionary] = []
var boxes: Array[Dictionary] = []
var reveal := {}  # how opening a box looks, see data/reveal.json
var adventure_types: Array[Dictionary] = []  # see data/adventures.json
var locations: Array[Dictionary] = []  # in the order they're listed, safe to deadly
var events := {}  # event id -> event, shared by the locations
var rumours: Array[Dictionary] = []  # what exploration can bring back
var voice := {}  # what the active pet says, see data/voice.json
var tutorial := {}  # the first few minutes of a new game, see data/tutorial.json

var _tier_rank := {}  # tier id -> index
var _parts_by_id := {}  # slot -> { part id -> part }
var _finish_by_id := {}
var _trait_by_id := {}
var _box_by_id := {}
var _type_by_id := {}
var _location_by_id := {}
var _rumour_by_id := {}


static func shared() -> Catalog:
	if _shared == null:
		_shared = Catalog.new()
	return _shared


func _init() -> void:
	tiers.assign(_load("rarities.json").tiers)
	for i in tiers.size():
		_tier_rank[tiers[i].id] = i

	var raw_slots: Dictionary = _load("parts.json").slots
	for slot in SLOTS:
		var list: Array[Dictionary] = []
		list.assign(raw_slots[slot])
		slots[slot] = list
		_parts_by_id[slot] = _index(list)

	finishes.assign(_load("finishes.json").finishes)
	_finish_by_id = _index(finishes)
	traits.assign(_load("traits.json").traits)
	_trait_by_id = _index(traits)
	boxes.assign(_load("boxes.json").boxes)
	_box_by_id = _index(boxes)
	reveal = _load("reveal.json")
	var adventures := _load("adventures.json")
	adventure_types.assign(adventures.types)
	_type_by_id = _index(adventure_types)
	locations.assign(adventures.locations)
	_location_by_id = _index(locations)
	events = _index(adventures.events)
	rumours.assign(adventures.rumours)
	_rumour_by_id = _index(rumours)
	voice = _load("voice.json")
	tutorial = _load("tutorial.json")


# ---- rarity ---------------------------------------------------------------

func rank(tier_id: String) -> int:
	assert(_tier_rank.has(tier_id), "unknown rarity tier: " + tier_id)
	return _tier_rank.get(tier_id, 0)


func tier_at(rank_index: int) -> Dictionary:
	return tiers[clampi(rank_index, 0, tiers.size() - 1)]


func tier_color(tier_id: String) -> Color:
	return Color(tier_at(rank(tier_id)).color)


# ---- lookups --------------------------------------------------------------

func part(slot: String, id: String) -> Dictionary:
	return _parts_by_id[slot].get(id, {})


## What an old pet gets for a slot it doesn't have, or a part that no longer exists.
func default_part(slot: String) -> String:
	var commons := parts_of_tier(slot, tiers[0].id)
	return commons[0].id if not commons.is_empty() else slots[slot][0].id


func parts_of_tier(slot: String, tier_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in slots[slot]:
		if p.rarity == tier_id:
			out.append(p)
	return out


func finish(id: String) -> Dictionary:
	return _finish_by_id.get(id, finishes[0])


func finish_rank(id: String) -> int:
	return rank(finish(id).rarity)


func trait_info(id: String) -> Dictionary:
	return _trait_by_id.get(id, {})


func box(id: String) -> Dictionary:
	return _box_by_id.get(id, {})


func location(id: String) -> Dictionary:
	return _location_by_id.get(id, {})


func adventure_type(id: String) -> Dictionary:
	return _type_by_id.get(id, {})


func rumour(id: String) -> Dictionary:
	return _rumour_by_id.get(id, {})


## Chance (0..1) of pulling this rarity from this box.
func tier_chance(box_id: String, tier_id: String) -> float:
	return Weighted.chances(box(box_id).get("tiers", {})).get(tier_id, 0.0)


## Reveal settings for one tier (effects it adds, pause, celebration size).
func reveal_tier(tier_id: String) -> Dictionary:
	return reveal.tiers.get(tier_id, {})


# ---- loading --------------------------------------------------------------

func _load(file: String) -> Dictionary:
	var path := DATA_DIR + file
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(typeof(data) == TYPE_DICTIONARY, "bad or missing data file: " + path)
	return data


static func _index(list: Array) -> Dictionary:
	var out := {}
	for item in list:
		out[item.id] = item
	return out
