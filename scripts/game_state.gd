extends Node
## Autoload "GameState": the player's progress (coins, care stats, pets, the bag of boxes and
## parts, dungeon runs) and saving it.

signal changed  # coins, care stats, the bag or dungeon runs changed
signal run_ended(run: RunState)  # a dungeon run is back and waiting to be collected

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 4
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
var parts := {}  # "slot:part id" -> how many you have (found in the dungeon, for grafting later)
var runs: Array[RunState] = []

var _roller := PetRoller.new(catalog)
var _rng := RandomNumberGenerator.new()
var _can_save := true  # false if the save came from a newer version of the game
var _coin_timer := 0.0
var _save_timer := 0.0
var _run_timer := 0.0


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

	_run_timer -= delta
	if _run_timer <= 0.0:
		_run_timer = 1.0
		_advance_runs()

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

## uid -> true for every pet on a run (including runs back home but not collected yet).
func away() -> Dictionary:
	var out := {}
	for run in runs:
		for uid in run.party.uids:
			out[uid] = true
	return out


## Pets that can be sent: not your active pet, and not already away.
func sendable_pets() -> Array[Pet]:
	var gone := away()
	var out: Array[Pet] = []
	for pet in collection.pets:
		if pet.uid != collection.active_uid and not gone.has(pet.uid):
			out.append(pet)
	return out


func send_to_dungeon(dungeon_id: String, pets: Array[Pet]) -> RunState:
	var dungeon := catalog.dungeon(dungeon_id)
	var allowed := sendable_pets()
	var going: Array[Pet] = []
	for pet in pets:
		if pet in allowed:
			going.append(pet)
	var most := int(dungeon.get("max_party", 0))
	if dungeon.is_empty() or going.is_empty() or (most > 0 and going.size() > most):
		return null
	var run := DungeonRunner.start(dungeon_id, going, Time.get_unix_time_from_system(), _rng.randi(), catalog)
	runs.append(run)
	changed.emit()
	save_game()
	return run


## The player picks an option at the event a run is waiting at.
func answer_event(run: RunState, option_index: int) -> void:
	if not run in runs or run.status != RunState.Status.WAITING:
		return
	run.answer = option_index
	_advance(run)
	changed.emit()
	save_game()


## Collects a run that's back: coins, boxes and parts go in the bag, the pets that didn't come
## back leave the collection. Returns the summary line, or "" if it isn't back yet.
func collect_run(run: RunState) -> String:
	if not run in runs or run.status != RunState.Status.DONE:
		return ""
	runs.erase(run)
	coins += run.coins
	for box_id in run.boxes:
		bag[box_id] = in_bag(box_id) + int(run.boxes[box_id])
	for p in run.parts:
		var key := "%s:%s" % [p[0], p[1]]
		parts[key] = int(parts.get(key, 0)) + 1
	collection.remove(run.party.lost)
	changed.emit()
	save_game()
	return DungeonRunner.summary(run)


func _advance_runs() -> void:
	var moved := false
	for run in runs:
		moved = _advance(run) or moved
	if moved:
		changed.emit()


## Plays whatever has come due on a run. Returns true if anything happened.
func _advance(run: RunState) -> bool:
	var before := run.status
	var added := DungeonRunner.resolve(run, Chooser.for_run(run), Time.get_unix_time_from_system(), catalog)
	if run.status == RunState.Status.DONE and before != RunState.Status.DONE:
		run_ended.emit(run)
	return not added.is_empty() or run.status != before


## Debug: everything that's walking arrives now (runs still wait for your answers).
func debug_finish_runs() -> void:
	var now := Time.get_unix_time_from_system()
	for run in runs:
		for i in 50:
			if run.status != RunState.Status.WALKING:
				break
			run.next_at = minf(run.next_at, now)
			_advance(run)
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
		"parts": parts,
		"runs": runs.map(func(r): return r.to_dict()),
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
	parts.clear()
	var saved_parts: Dictionary = data.get("parts", {})
	for key in saved_parts:
		var bits: PackedStringArray = str(key).split(":")
		if bits.size() == 2 and bits[0] in Catalog.SLOTS and not catalog.part(bits[0], bits[1]).is_empty():
			parts[key] = int(saved_parts[key])
	runs.clear()
	for raw in data.get("runs", []):
		var run := RunState.from_dict(raw, catalog)
		if run != null:
			runs.append(run)

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
	if version < 4:
		data.erase("dungeon")  # v3's simple runs: those pets just come home
	data.version = SAVE_VERSION
	return data


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()
