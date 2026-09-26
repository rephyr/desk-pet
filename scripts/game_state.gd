extends Node
## Autoload "GameState": the player's progress (coins, care stats, pets, the bag of boxes and
## parts, adventures, unlocks) and saving it.

signal changed  # coins, care stats, the bag, adventures or unlocks changed
signal run_ended(run: RunState)  # an adventure is back and waiting to be collected
signal new_game  # everything was reset to a fresh start
signal tutorial_changed  # the tutorial moved on a step (or finished)
signal adventures_changed  # a trip was sent, moved on, answered or collected, or something unlocked

const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 8
const STAT_FLOOR := 20.0
const HUNGER_DECAY := 100.0 / (4.0 * 3600.0)  # full to floor in about 4 h
const HAPPY_DECAY := 100.0 / (6.0 * 3600.0)
const COIN_INTERVAL := 10.0  # seconds per coin at full happiness
const OFFLINE_CAP := 12.0 * 3600.0
const FEED_COST := 3
const FIRST_PET_BOX := "starter"
const DEBUG_COINS := 1000
const TUTORIAL_BOX := "tutorial"  # hidden box the tutorial's pets come from, see data/boxes.json

var catalog := Catalog.shared()
var collection := Collection.new()
var coins := 100
var hunger := 80.0  # 100 = full
var happiness := 80.0
var pet_out := false
var bag := {}  # box id -> unopened boxes you own (found on adventures)
var parts := {}  # "slot:part id" -> how many you have (found on adventures, for grafting later)
var items := {}  # anything else adventures bring back that nothing uses yet, see Rewards
var unlocks := {}  # unlock id -> true, e.g. "automation", "type:dungeon", "location:cellar"
var trips_done := 0  # adventures welcomed back, ever (some types open after a few)
var heard := {}  # rumour id -> true, for every rumour ever heard
var rumours: Array[String] = []  # heard, and waiting for you to decide whether to go
var runs: Array[RunState] = []
## The last trip you welcomed back, for the active pet to talk about: { place, home, sent, parts }.
## Not saved: it's small talk.
var news := {}
## Where the tutorial is ("open_first", "open_second", "make_active", "send"), or "done".
var tutorial := "done"

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
	if not load_game():
		_start_tutorial()  # a brand new player
	elif collection.pets.is_empty() and tutorial == "done":
		_give_first_pet()
	collection.active_changed.connect(func(_p): _check_tutorial())
	collection.pets_added.connect(func(_p): _check_tutorial())


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
	# the tutorial's boxes are plain commons: your first pets shouldn't be a mythic by luck
	var roll_from := TUTORIAL_BOX if tutorial_active() else box_id
	if from_bag > 0:
		bag[box_id] = in_bag(box_id) - from_bag
		if bag[box_id] <= 0:
			bag.erase(box_id)
	var forced := force_tier if OS.is_debug_build() and not tutorial_active() else ""
	for i in count:
		pulled.append(_roller.roll(roll_from, forced))
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


# ---- unlocks ---------------------------------------------------------------

const AUTOMATION := "automation"  # lets you send swarms that follow your rules


func is_unlocked(id: String) -> bool:
	return unlocks.has(id)


func unlock(id: String) -> void:
	if unlocks.has(id):
		return
	unlocks[id] = true
	adventures_changed.emit()
	changed.emit()
	save_game()


## Adventure types you can go on: open from the start, unlocked by a rumour, or after enough trips.
func adventure_type_open(type_id: String) -> bool:
	var t := catalog.adventure_type(type_id)
	return bool(t.get("unlocked", false)) or is_unlocked("type:" + type_id) or _enough_trips(t)


## A place you can go: its type is open, and it isn't waiting for a rumour or for more trips.
func location_open(location: Dictionary) -> bool:
	if location.is_empty() or not adventure_type_open(location.type):
		return false
	if is_unlocked("location:" + location.id):
		return true
	if location.get("locked", false):
		return false
	return not location.has("unlock") or _enough_trips(location)


## Whether a type or location with an { "after_trips": n } unlock rule has had enough trips.
func _enough_trips(thing: Dictionary) -> bool:
	var rule = thing.get("unlock", "")
	return rule is Dictionary and rule.has("after_trips") and trips_done >= int(rule.after_trips)


## Whether an unlock id ("type:dungeon", "location:cellar", "automation") is open.
func is_open(id: String) -> bool:
	if id.begins_with("type:"):
		return adventure_type_open(id.substr(5))
	if id.begins_with("location:"):
		return location_open(catalog.location(id.substr(9)))
	return is_unlocked(id)


## Places you can go, in the data's order.
func open_locations() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for location in catalog.locations:
		if location_open(location):
			out.append(location)
	return out


## You decided to go where a rumour said: it opens what the rumour was about.
func follow_rumour(rumour_id: String) -> void:
	if not rumour_id in rumours:
		return
	rumours.erase(rumour_id)
	for id in catalog.rumour(rumour_id).get("unlocks", []):
		unlocks[id] = true
	adventures_changed.emit()
	changed.emit()
	save_game()


## Pets came back with word of somewhere: hear up to `count` new rumours.
func _hear_rumours(count: int) -> void:
	var can := Rumours.hearable(catalog, heard, is_open)
	for i in mini(count, can.size()):
		var rumour: Dictionary = can.pop_at(_rng.randi_range(0, can.size() - 1))
		heard[rumour.id] = true
		rumours.append(rumour.id)


## The biggest party you may send here: small parties until automation, and a location's own cap.
func max_party(location_id: String) -> int:
	var most := Chooser.SMALL_PARTY if not is_unlocked(AUTOMATION) else 1 << 30
	var cap := int(catalog.location(location_id).get("max_party", 0))
	return mini(most, cap) if cap > 0 else most


func debug_unlock_all() -> void:
	unlock(AUTOMATION)
	for t in catalog.adventure_types:
		unlock("type:" + t.id)
	for l in catalog.locations:
		unlock("location:" + l.id)


## Debug: a completely fresh game, as a new player would start it. The old save is copied to
## user://save-before-new-game-<time>.json first, so it can be put back by hand.
func debug_new_game() -> void:
	save_game()
	var backup := "user://save-before-new-game-%d.json" % int(Time.get_unix_time_from_system())
	DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(backup))
	coins = 100
	hunger = 80.0
	happiness = 80.0
	bag.clear()
	parts.clear()
	items.clear()
	unlocks.clear()
	trips_done = 0
	heard.clear()
	rumours.clear()
	runs.clear()
	news = {}
	collection.load_from({})
	_start_tutorial()
	collection.active_changed.emit(collection.active())
	save_game()
	new_game.emit()
	adventures_changed.emit()
	changed.emit()


# ---- tutorial ----------------------------------------------------------------

func tutorial_active() -> bool:
	return tutorial != "done"


## The current tutorial step's data (see data/tutorial.json), or {} when it's done.
func tutorial_info() -> Dictionary:
	for step in catalog.tutorial.steps:
		if step.id == tutorial:
			return step
	return {}


func _start_tutorial() -> void:
	coins = 100  # exactly two starter boxes
	tutorial = catalog.tutorial.steps[0].id
	collection.auto_active = false


## Moves the tutorial on once its step is done: two boxes opened, a pet made active, one sent.
func _check_tutorial() -> void:
	var before := tutorial
	for i in 4:
		match tutorial:
			"open_first":
				if collection.pets.size() >= 1:
					tutorial = "open_second"
			"open_second":
				if collection.pets.size() >= 2:
					tutorial = "make_active"
			"make_active":
				if collection.active() != null:
					tutorial = "send"
			"send":
				if not runs.is_empty():
					tutorial = "done"
					collection.auto_active = true
	if tutorial != before:
		tutorial_changed.emit()
		save_game()


## Debug: back to how a new game starts: only the first adventure type, no trips counted, no
## rumours heard. Trips already out still finish.
func debug_lock_all() -> void:
	unlocks.clear()
	trips_done = 0
	heard.clear()
	rumours.clear()
	adventures_changed.emit()
	changed.emit()
	save_game()


# ---- adventures -------------------------------------------------------------

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


func send_on_adventure(location_id: String, pets: Array[Pet]) -> RunState:
	var location := catalog.location(location_id)
	var allowed := sendable_pets()
	var going: Array[Pet] = []
	for pet in pets:
		if pet in allowed:
			going.append(pet)
	if not location_open(location) or going.is_empty() or going.size() > max_party(location_id):
		return null
	var run := AdventureRunner.start(location_id, going, Time.get_unix_time_from_system(), _rng.randi(), catalog)
	runs.append(run)
	_check_tutorial()
	adventures_changed.emit()
	changed.emit()
	save_game()
	return run


## The player picks an option at the event a run is waiting at.
func answer_event(run: RunState, option_index: int) -> void:
	if not run in runs or run.status != RunState.Status.WAITING:
		return
	if not option_index in AdventureRunner.allowed_options(run.current_event(catalog), run.party, catalog.location(run.location_id)):
		return
	run.answer = option_index
	_advance(run)
	adventures_changed.emit()
	changed.emit()
	save_game()


## Collects a run that's back: what it found is handed out, the pets that didn't come back leave
## the collection. Returns the summary line, or "" if it isn't back yet.
func collect_run(run: RunState) -> String:
	if not run in runs or run.status != RunState.Status.DONE:
		return ""
	runs.erase(run)
	trips_done += 1
	grant(run.loot)
	collection.remove(run.party.lost)
	news = { "place": catalog.location(run.location_id).name, "home": run.party.size(),
		"sent": run.party.setting_out(), "parts": Rewards.total(run.loot, "part") }
	adventures_changed.emit()
	changed.emit()
	save_game()
	return AdventureRunner.summary(run)


## Hands out loot (see Rewards): coins to the wallet, boxes and parts to the bag, anything else
## into `items` until something uses it.
func grant(loot: Dictionary) -> void:
	for key: String in loot:
		var amount := int(loot[key])
		var kind := key.get_slice(":", 0)
		var rest := key.substr(kind.length() + 1)
		match kind:
			"coins":
				coins += amount
			"box":
				bag[rest] = in_bag(rest) + amount
			"part":
				parts[rest] = int(parts.get(rest, 0)) + amount
			"rumour":
				_hear_rumours(amount)
			_:
				items[key] = int(items.get(key, 0)) + amount
	changed.emit()


func _advance_runs() -> void:
	var moved := false
	for run in runs:
		moved = _advance(run) or moved
	if moved:
		changed.emit()
		adventures_changed.emit()


## Plays whatever has come due on a run. Returns true if anything happened.
func _advance(run: RunState) -> bool:
	var before := run.status
	var added := AdventureRunner.resolve(run, Chooser.for_run(run), Time.get_unix_time_from_system(), catalog)
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
	adventures_changed.emit()
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
		"items": items,
		"unlocks": unlocks.keys(),
		"trips_done": trips_done,
		"heard": heard.keys(),
		"rumours": rumours,
		"tutorial": tutorial,
		"runs": runs.map(func(r): return r.to_dict()),
		"saved_at": Time.get_unix_time_from_system(),
	}
	SaveFile.write(SAVE_PATH, data)


## Loads the save. Returns false if there's none yet (a brand new player).
func load_game() -> bool:
	var data := SaveFile.read(SAVE_PATH)
	if data.is_empty():
		return false
	if int(data.get("version", 1)) > SAVE_VERSION:
		# don't downgrade a save from a newer game: play with it, but never write over it
		push_warning("save is from a newer version of the game; it won't be overwritten")
		_can_save = false
	data = _migrate(data)
	coins = int(data.get("coins", coins))
	hunger = data.get("hunger", hunger)
	happiness = data.get("happiness", happiness)
	pet_out = data.get("pet_out", false)
	tutorial = str(data.get("tutorial", "done"))  # saves from before the tutorial skip it
	collection.auto_active = tutorial == "done"  # mid-tutorial, you still choose your active pet
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
	items.clear()
	var saved_items: Dictionary = data.get("items", {})
	for key in saved_items:
		items[key] = int(saved_items[key])
	unlocks.clear()
	for id in data.get("unlocks", []):
		unlocks[str(id)] = true
	trips_done = int(data.get("trips_done", 0))
	heard.clear()
	for id in data.get("heard", []):
		heard[str(id)] = true
	rumours.clear()
	for id in data.get("rumours", []):
		if not catalog.rumour(str(id)).is_empty():
			rumours.append(str(id))
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
	return true


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
	if version < 6:
		# v5: dungeons became adventures that unlock over time; older saves already had the
		# dungeons and big parties, so they keep them (v6: also for saves the first v5 build
		# touched, which didn't do this yet). Old runs are read by RunState.from_dict.
		var had: Array = data.get("unlocks", [])
		data.unlocks = had + ["type:dungeon", AUTOMATION]
	if version < 7:
		# v7: dungeon places open one rumour at a time; saves that had the dungeons keep them all
		var had: Array = data.get("unlocks", [])
		if "type:dungeon" in had:
			data.unlocks = had + ["location:cellar", "location:below"]
			data.heard = ["well", "cellar", "below"]
	data.version = SAVE_VERSION
	return data


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()
