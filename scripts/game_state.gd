extends Node
## Autoload "GameState": the player's progress (coins, care stats, pets, boxes in the bag,
## dungeon runs) and saving it.

signal changed  # coins, care stats, the bag or dungeon runs changed

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3
const STAT_FLOOR := 20.0
const HUNGER_DECAY := 100.0 / (4.0 * 3600.0)  # full to floor in about 4 h
const HAPPY_DECAY := 100.0 / (6.0 * 3600.0)
const COIN_INTERVAL := 10.0  # seconds per coin at full happiness
const OFFLINE_CAP := 12.0 * 3600.0
const FEED_COST := 3
const FIRST_PET_BOX := "starter"
const DEBUG_COINS := 1000

var catalog := Catalog.shared()
var collection := Collection.new()
var coins := 100
var hunger := 80.0  # 100 = full
var happiness := 80.0
var pet_out := false
var bag := {}  # box id -> unopened boxes you own (found in the dungeon)
var dungeon := Dungeon.new(catalog)

var _roller := PetRoller.new(catalog)
var _rng := RandomNumberGenerator.new()
var _can_save := true  # false if the save came from a newer version of the game
var _coin_timer := 0.0
var _save_timer := 0.0


# Loaded in _init, not _ready: the main scene is built before autoloads get _ready,
# and the UI reads the pets while it's being built.
func _init() -> void:
	_rng.randomize()
	load_game()
	if collection.pets.is_empty():
		_give_first_pet()


func _process(delta: float) -> void:
	hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * delta)
	happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * delta)

	# happy, fed pets earn faster; an ignored one still earns a little
	_coin_timer += delta * lerpf(0.4, 1.0, (happiness + hunger) / 200.0)
	if _coin_timer >= COIN_INTERVAL:
		_coin_timer -= COIN_INTERVAL
		coins += 1
		changed.emit()

	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()


# ---- boxes ----------------------------------------------------------------

func box_price(box_id: String, count := 1) -> int:
	return int(catalog.box(box_id).price) * count


## Opens boxes, using ones from the bag first and paying for the rest. Returns the new pets
## (empty if you can't afford them). `force_tier` only works in debug builds, for testing reveals.
func open_boxes(box_id: String, count := 1, force_tier := "") -> Array[Pet]:
	var pulled: Array[Pet] = []
	var from_bag := mini(count, in_bag(box_id))
	var price := box_price(box_id, count - from_bag)
	if count <= 0 or coins < price:
		return pulled
	coins -= price
	if from_bag > 0:
		bag[box_id] = in_bag(box_id) - from_bag
		if bag[box_id] <= 0:
			bag.erase(box_id)
	var forced := force_tier if OS.is_debug_build() else ""
	for i in count:
		pulled.append(_roller.roll(box_id, forced))
	collection.add(pulled)
	changed.emit()
	save_game()
	return pulled


## Most boxes of this type you can open right now (from the bag, then with coins).
func affordable(box_id: String) -> int:
	var price := box_price(box_id)
	return in_bag(box_id) + (coins / price if price > 0 else 0)


func in_bag(box_id: String) -> int:
	return int(bag.get(box_id, 0))


func add_debug_coins() -> void:
	coins += DEBUG_COINS
	changed.emit()


func _give_first_pet() -> void:
	var first: Array[Pet] = [_roller.roll(FIRST_PET_BOX)]
	collection.add(first)


# ---- dungeon --------------------------------------------------------------

## Pets that can be sent: not your active pet, and not already down there.
func sendable_pets() -> Array[Pet]:
	var away := dungeon.away()
	var out: Array[Pet] = []
	for pet in collection.pets:
		if pet.uid != collection.active_uid and not away.has(pet.uid):
			out.append(pet)
	return out


func send_to_dungeon(floor_index: int, pets: Array[Pet]) -> bool:
	var allowed := sendable_pets()
	var going: Array[Pet] = []
	for pet in pets:
		if pet in allowed:
			going.append(pet)
	if going.is_empty():
		return false
	dungeon.send(floor_index, going, Time.get_unix_time_from_system())
	changed.emit()
	save_game()
	return true


## Collects a finished run: the pets that come home bring loot, the rest are gone for good.
## Returns what happened (see Dungeon.roll, plus "floor"), or {} if it isn't done yet.
func collect_run(run: Dictionary) -> Dictionary:
	if not dungeon.runs.has(run) or not Dungeon.is_done(run, Time.get_unix_time_from_system()):
		return {}
	var pets: Array[Pet] = []
	for uid in run.pets:
		var pet := collection.get_pet(uid)
		if pet != null:
			pets.append(pet)
	var result := Dungeon.roll(dungeon.floor_info(run.floor), pets, _rng, catalog)
	result.floor = run.floor
	dungeon.runs.erase(run)
	coins += result.coins
	for box_id in result.boxes:
		bag[box_id] = in_bag(box_id) + result.boxes[box_id]
	collection.remove(result.lost)
	changed.emit()
	save_game()
	return result


func debug_finish_runs() -> void:
	var now := Time.get_unix_time_from_system()
	for run in dungeon.runs:
		run.ends = minf(run.ends, now)
	changed.emit()


# ---- care -----------------------------------------------------------------

func feed() -> bool:
	if coins < FEED_COST or hunger >= 99.0:
		return false
	coins -= FEED_COST
	hunger = minf(100.0, hunger + 30.0)
	happiness = minf(100.0, happiness + 5.0)
	changed.emit()
	return true


func pat() -> void:
	happiness = minf(100.0, happiness + 8.0)
	changed.emit()


func set_pet_out(value: bool) -> void:
	pet_out = value
	changed.emit()


# ---- saving ---------------------------------------------------------------

func save_game() -> void:
	if not _can_save:
		return
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"hunger": hunger,
		"happiness": happiness,
		"pet_out": pet_out,
		"collection": collection.to_dict(),
		"bag": bag,
		"dungeon": dungeon.to_dict(),
		"saved_at": Time.get_unix_time_from_system(),
	}
	SaveFile.write(SAVE_PATH, data)


func load_game() -> void:
	var data := SaveFile.read(SAVE_PATH)
	if data.is_empty():
		return
	if int(data.get("version", 1)) > SAVE_VERSION:
		# don't downgrade a save from a newer game: play with it, but never write over it
		push_warning("save is from a newer version of the game; it won't be overwritten")
		_can_save = false
	data = _migrate(data)
	coins = int(data.get("coins", coins))
	hunger = data.get("hunger", hunger)
	happiness = data.get("happiness", happiness)
	pet_out = data.get("pet_out", false)
	collection.load_from(data.get("collection", {}))
	bag.clear()
	var saved_bag: Dictionary = data.get("bag", {})
	for box_id in saved_bag:
		if not catalog.box(box_id).is_empty() and int(saved_bag[box_id]) > 0:
			bag[box_id] = int(saved_bag[box_id])
	dungeon.load_from(data.get("dungeon", {}))

	# catch up on time spent closed: coins at the slowest rate, stats to the floor at worst
	var away := Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))
	if away > 0.0:
		coins += int(minf(away, OFFLINE_CAP) * 0.4 / COIN_INTERVAL)
		hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * away)
		happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * away)


## Brings older save files up to the current format, one version at a time.
func _migrate(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", 1))
	if version >= SAVE_VERSION:
		return data
	if version < 2:
		data.collection = {}  # v1 had no pets yet; a first pet is given after loading
	# v3 added the bag and dungeon runs; missing ones load as empty
	data.version = SAVE_VERSION
	return data


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()
