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
var box_rules := {}  # data/boxes.json around the boxes (the pet's coin reserve)
var reveal := {}  # how opening a box looks, see data/reveal.json
var sounds := {}  # what plays when, see data/sounds.json
var adventure_types: Array[Dictionary] = []  # see data/adventures.json
var locations: Array[Dictionary] = []  # in the order they're listed, safe to deadly
var events := {}  # event id -> event, shared by the locations
var rumours: Array[Dictionary] = []  # what exploration can bring back
var voice := {}  # what the active pet says, see data/voice.json
var tutorial := {}  # the first few minutes of a new game, see data/tutorial.json
var grafting := {}  # sewing parts onto your active pet, see data/grafting.json
var unlock_list: Array[Dictionary] = []  # what adventures open up, see data/unlocks.json
var finds := {}  # find id -> special item
var pages: Array[Dictionary] = []  # map pages, in order
var errands := {}  # the errands tab's rules, see data/errands.json
var jobs: Array[Dictionary] = []  # errands pets can be put on, in order
var _rummage_by_id := {}
var rummage_spots: Array[Dictionary] = []  # spots in your pet's room it digs through, see data/rummage.json
var machine := {}  # the capsule machine: prizes, lights, upgrades, see data/machine.json
var toys := {}  # capsule toys: sets, tiers, finishes, play, pixel art, see data/toys.json
var machine_tree := {}  # the machine's upgrade tree, see data/machine_tree.json
var automation := {}  # jobs your pet does for you (the automation tab), see data/automation.json
var gear := {}  # upgrades to adventuring bought with xp, see data/gear.json and Gear
var book := {}  # the collection book's reward stickers, see data/book.json and Book
var boosts := {}  # boost kinds and their sources, see data/boosts.json and Boosts
var knacks := {}  # every part's named knack, see data/knacks.json and Knacks
var herd := {}  # plain pets folded into counts, the room cap, see data/herd.json and Herd
var new_homes := {}  # the new homes stall and the sorting rule, see data/new_homes.json and NewHomes
var encounter_art := {}  # event id -> its pixel art on the trail, see data/encounter_art.json
var tier_overrides := {}  # tier id -> Color, set by the player's colour theme (see UiTheme.apply)

var _tier_rank := {}  # tier id -> index
var _parts_by_id := {}  # slot -> { part id -> part }
var _finish_by_id := {}
var _trait_by_id := {}
var _box_by_id := {}
var _type_by_id := {}
var _location_by_id := {}
var _rumour_by_id := {}
var _job_by_id := {}
var _box_rank := {}  # box id -> its place among the shop's boxes (see box_rank)
var _finish_box_rank := {}  # finish id -> the rank of the first shop box that has it (see finish_box_rank)
var _parts_in_cache := {}  # "slot|tier|box rank" -> parts_in's answer (catalog data never changes)


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
	box_rules = _load("boxes.json")
	boxes.assign(box_rules.boxes)
	_box_by_id = _index(boxes)
	for b in boxes:
		if not b.get("hidden", false):
			_box_rank[b.id] = _box_rank.size()
			for f in b.get("finishes", {}):
				if float(b.finishes[f]) > 0.0 and not _finish_box_rank.has(f):
					_finish_box_rank[f] = _box_rank[b.id]
	reveal = _load("reveal.json")
	sounds = _load("sounds.json")
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
	grafting = _load("grafting.json")
	var unlock_data := _load("unlocks.json")
	unlock_list.assign(unlock_data.unlocks)
	finds = _index(unlock_data.finds)
	pages.assign(unlock_data.pages)
	errands = _load("errands.json")
	jobs.assign(errands.jobs)
	_job_by_id = _index(jobs)
	rummage_spots.assign(_load("rummage.json").spots)
	encounter_art = _load("encounter_art.json").art
	machine = _load("machine.json")
	toys = _load("toys.json")
	machine_tree = _load("machine_tree.json")
	automation = _load("automation.json")
	gear = _load("gear.json")
	book = _load("book.json")
	boosts = _load("boosts.json")
	knacks = _load("knacks.json")
	herd = _load("herd.json")
	new_homes = _load("new_homes.json")
	_rummage_by_id = _index(rummage_spots)


# ---- rarity ---------------------------------------------------------------

func rank(tier_id: String) -> int:
	assert(_tier_rank.has(tier_id), "unknown rarity tier: " + tier_id)
	return _tier_rank.get(tier_id, 0)


func tier_at(rank_index: int) -> Dictionary:
	return tiers[clampi(rank_index, 0, tiers.size() - 1)]


func tier_color(tier_id: String) -> Color:
	var id: String = tier_at(rank(tier_id)).id
	return tier_overrides.get(id, Color(tier_at(rank(tier_id)).color))


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


## The parts of a tier that can come out of this box: parts with a "from" box only come out of
## that box tier or a later one (new looks to collect in the better boxes). Cached: don't change
## the array you get back.
func parts_in(slot: String, tier_id: String, box_id: String) -> Array[Dictionary]:
	var rank_here := box_rank(box_id)
	var key := "%s|%s|%d" % [slot, tier_id, rank_here]
	if not _parts_in_cache.has(key):
		var out: Array[Dictionary] = []
		out.assign(parts_of_tier(slot, tier_id).filter(func(p): return not p.has("from") or rank_here >= box_rank(str(p.from))))
		_parts_in_cache[key] = out
	return _parts_in_cache[key]


## Where a box sits among the boxes sold in the shop (0 = the first); hidden and unknown boxes
## count as the first.
func box_rank(box_id: String) -> int:
	return _box_rank.get(box_id, 0)


## The rank of the first box in the shop that can hold this finish (a finish no box has counts as
## the first).
func finish_box_rank(finish_id: String) -> int:
	return _finish_box_rank.get(finish_id, 0)


## The boxes the shop can sell, cheapest tier first (whether they're in the shop yet depends on
## their map page, see GameState.shop_boxes).
func shop_boxes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in boxes:
		if not b.get("hidden", false):
			out.append(b)
	return out


## The parts that only come out of this box or a later one, first come in this very box (its
## "new looks"), as { slot, id } in slot order.
func new_looks(box_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot in SLOTS:
		for p in slots[slot]:
			if str(p.get("from", "")) == box_id:
				out.append({ "slot": slot, "id": p.id })
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


func job(id: String) -> Dictionary:
	return _job_by_id.get(id, {})


func rummage_spot(id: String) -> Dictionary:
	return _rummage_by_id.get(id, {})


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
