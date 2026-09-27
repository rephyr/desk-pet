extends Node
## Autoload "GameState": the player's progress (coins, care stats, pets, the bag of boxes and
## parts, adventures, unlocks) and saving it.

signal changed  # coins, care stats, the bag, adventures or unlocks changed
signal run_ended(run: RunState)  # an adventure is back and waiting to be collected
signal new_game  # everything was reset to a fresh start
signal tutorial_changed  # the tutorial moved on a step (or finished)
signal job_paid(job_id: String, loot: Dictionary)  # an errand's meter filled up and paid this
signal jobs_changed  # pets were put on or taken off errands
signal unlocked(entry: Dictionary)  # something new opened up (see data/unlocks.json)
signal opened_in_background(pet: Pet)  # your pet opened a pack out of sight (the spine's moon shows it)
signal adventures_changed  # a trip was sent, moved on, answered or collected, or something unlocked

var save_path := DevProfile.path("save.json")  # user://save.json, or a test profile's (debug builds)
const SAVE_VERSION := 14
const STAT_FLOOR := 20.0
const HUNGER_DECAY := 100.0 / (4.0 * 3600.0)  # full to floor in about 4 h
const HAPPY_DECAY := 100.0 / (6.0 * 3600.0)
const COIN_INTERVAL := 10.0  # seconds per coin at full happiness
const OFFLINE_CAP := 12.0 * 3600.0
const FEED_COST := 3
const FIRST_PET_BOX := "starter"
const DEBUG_COINS := 1000
const BACKGROUND_PACK_EVERY := 8.0  # seconds per pack your pet opens out of sight (its animation takes about this)
const BACKGROUND_AFTER := 1.0  # out of sight this long before it switches to opening in the background
const TUTORIAL_BOX := "tutorial"  # hidden box the tutorial's pets come from, see data/boxes.json

var catalog := Catalog.shared()
var collection := Collection.new()
var coins := 100  # money: what gets spent on stuff (boxes, food, ...)
var xp := 0  # experience from adventures: buys upgrades to adventuring itself
var hunger := 80.0  # 100 = full
var happiness := 80.0
var pet_out := false
var bag := {}  # box id -> unopened boxes you own (found on adventures)
var parts := {}  # "slot:part id" -> how many you have (found on adventures, for grafting later)
var items := {}  # anything else adventures bring back that nothing uses yet, see Rewards
var unlocks := {}  # unlock id -> true, e.g. "automation", "parties", "location:meadow"
var trips_done := 0  # adventures welcomed back, ever (some types open after a few)
var heard := {}  # rumour id -> true, for every rumour ever heard
var rumours: Array[String] = []  # heard, and waiting for you to decide whether to go
## Places you've sent someone to at least once (new ones glow on the map until then): id -> true
var visited := {}
## Places a pet spotted on a trip, waiting for you: location id -> { by, from }
var spotted := {}
var spot_tries := {}  # location id -> trips that could have spotted it but didn't (the safety net)
var finds := {}  # special items pets have brought home, see data/unlocks.json
var packs_by_hand := 0  # packs you opened yourself (some unlocks wait for enough)
var parts_ever := false  # a pet has brought a part home at least once
var announcements: Array[String] = []  # news for your pet to tell you: finds, things that opened up

# ---- your pet at work (idle): opening packs
var packs_on := true  # your pet opens packs while the game sits small in the corner

# ---- errands: resting pets on safe jobs, see Jobs and data/errands.json
var jobs := {}  # job id -> { crew: Array of uids, fill: 0..1 }
var jobs_auto := false  # your pet shares out new pets, and pets back from adventures (you do it until you turn this on)
var jobs_away := {}  # what errands brought while the game was closed, for the tab's note (not saved)
var _job_of := {}  # uid -> job id, for every pet on an errand
var _job_speed := {}  # job id -> how fast its crew works on average (see Jobs.pet_speed)
var _jobs_at := 0.0  # unix time errands have worked up to
var _was_active := ""  # the active pet before it changed (it goes back to work)


## Turns one of your pet's jobs ("packs" or "buying") on or off, from settings or the corner panel.
func set_job(job: String, on: bool) -> void:
	match job:
		"packs": packs_on = on
		"buying": buying_on = on
	save_game()
	changed.emit()


var coin_reserve := 50  # coins your pet never spends on boxes (once it may buy them)
var saved_boxes := {}  # box id -> true: "save for me", your pet leaves these on the pile
var buying_on := true  # your pet buys more when the pile runs out (once it has the piggy bank)
var pinned: Array[String] = []  # good pulls your pet opened, waiting for you to see them
## What your pet did while you weren't looking, for the home screen to tell you:
## { coins, parts, boxes, packs, good: [pet names] }
var idle_log := {}
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
var _pack_timer := 0.0  # your pet opening the pile out of sight, see _open_in_background()
var _pack_seen := 0.0  # seconds since a view last showed your pet opening packs
var _treats := {}  # RunState -> { zoom_until, ready_at }: treats tossed on the trail (not saved)


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
	# your active pet never works an errand; lost pets leave theirs; new pets get one
	collection.active_changed.connect(func(p: Pet):
		if p and _job_of.has(p.uid):
			_take_off([p.uid])
		if jobs_auto and _was_active != "" and (p == null or p.uid != _was_active):
			_auto_place([_was_active])  # your old active pet goes back to work
		_was_active = p.uid if p else "")
	_was_active = collection.active_uid
	collection.pet_changed.connect(func(_p): _job_speed.clear())
	collection.pets_removed.connect(func(uids): _take_off(uids))
	collection.pets_added.connect(func(pets: Array[Pet]):
		if jobs_auto:
			_auto_place(pets.map(func(p): return p.uid)))


func _process(delta: float) -> void:
	hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * delta)
	happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * delta)

	# happy, fed pets earn faster; an ignored one still earns a little
	_coin_timer += delta * lerpf(0.4, 1.0, (happiness + hunger) / 200.0)
	if _coin_timer >= COIN_INTERVAL:
		_coin_timer -= COIN_INTERVAL
		coins += 1
		changed.emit()

	_open_in_background(delta)
	_zoom_runs(delta)

	_run_timer -= delta
	if _run_timer <= 0.0:
		_run_timer = 1.0
		_advance_runs()
		_work_jobs(Time.get_unix_time_from_system())

	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()


# ---- boxes ----------------------------------------------------------------

func box_price(box_id: String, count := 1) -> int:
	return int(catalog.box(box_id).price) * count


## Buys boxes: they go on your pile (the bag) to open later, by you or your pet. Returns
## whether you could afford them.
func buy_boxes(box_id: String, count := 1) -> bool:
	var price := box_price(box_id, count)
	if count <= 0 or coins < price or catalog.box(box_id).is_empty():
		return false
	coins -= price
	bag[box_id] = in_bag(box_id) + count
	changed.emit()
	save_game()
	return true


## Debug: puts one box on your pile for free (the dev buttons open it straight away).
func debug_give_box(box_id: String) -> void:
	if OS.is_debug_build():
		bag[box_id] = in_bag(box_id) + 1


## How many more coins you'd need to buy `count` of a box, 0 if you can.
func coins_short(box_id: String, count := 1) -> int:
	return maxi(0, box_price(box_id, count) - coins)


## Opens boxes from your pile. Returns the new pets (empty if there aren't that many on the pile).
## `force_tier` only works in debug builds, for testing reveals.
## `by_pet`: your pet opened it (doesn't count toward packs you opened yourself).
func open_boxes(box_id: String, count := 1, force_tier := "", by_pet := false) -> Array[Pet]:
	var pulled: Array[Pet] = []
	if count <= 0 or in_bag(box_id) < count:
		return pulled
	bag[box_id] = in_bag(box_id) - count
	if bag[box_id] <= 0:
		bag.erase(box_id)
	# the tutorial's boxes are plain commons: your first pets shouldn't be a mythic by luck
	var roll_from := TUTORIAL_BOX if tutorial_active() else box_id
	var forced := force_tier if OS.is_debug_build() and not tutorial_active() else ""
	for i in count:
		pulled.append(_roller.roll(roll_from, forced))
	collection.add(pulled)
	if not by_pet:
		packs_by_hand += count
		check_unlocks()
	changed.emit()
	save_game()
	return pulled


func in_bag(box_id: String) -> int:
	return int(bag.get(box_id, 0))


## Debug: `count` more pets from starter boxes, straight into the collection.
func debug_give_pets(count: int) -> void:
	if not OS.is_debug_build():
		return
	var pulled: Array[Pet] = []
	for i in count:
		pulled.append(_roller.roll(FIRST_PET_BOX))
	collection.add(pulled)
	changed.emit()
	save_game()


func add_debug_coins() -> void:
	coins += DEBUG_COINS
	changed.emit()


func _give_first_pet() -> void:
	var first: Array[Pet] = [_roller.roll(FIRST_PET_BOX)]
	collection.add(first)


# ---- unlocks ---------------------------------------------------------------

const AUTOMATION := "automation"  # lets you send swarms that follow your rules
const PARTIES := "parties"  # feature: send small parties (see PARTY_SIZES)


func is_unlocked(id: String) -> bool:
	return unlocks.has(id)


func unlock(id: String) -> void:
	if unlocks.has(id):
		return
	unlocks[id] = true
	adventures_changed.emit()
	changed.emit()
	save_game()


## A place you can go: its map page is open, and it's the page's first place or one a pet spotted
## (or a rumour led to) and you said yes.
func location_open(location: Dictionary) -> bool:
	if location.is_empty() or not page_open(str(location.get("page", catalog.pages[0].id))):
		return false
	return location.get("start", false) or is_unlocked("location:" + location.id)


func page_open(page_id: String) -> bool:
	for page in catalog.pages:
		if page.id == page_id:
			return page.get("start", false) or is_unlocked("page:" + page_id)
	return false


## Whether a feature ("errands", "packs", "parties") has been unlocked on your adventures.
func feature_on(feature: String) -> bool:
	return is_unlocked("feature:" + feature)


## Whether a tab can be opened: nothing locks it, or what locks it has been unlocked.
func tab_open(tab_name: String) -> bool:
	return tab_hint(tab_name) == ""


## The hint on a locked tab, or "" if it's open.
func tab_hint(tab_name: String) -> String:
	for entry in catalog.unlock_list:
		if ("tab:" + tab_name) in entry.opens and not is_unlocked("tab:" + tab_name):
			return str(entry.get("hint", "not yet"))
	return ""


## Whether a locked tab stays out of sight until it opens ("show": "hidden" in data/unlocks.json).
func tab_hidden(tab_name: String) -> bool:
	for entry in catalog.unlock_list:
		if ("tab:" + tab_name) in entry.opens and not is_unlocked("tab:" + tab_name):
			return entry.show == "hidden"
	return false


## Opens whatever you've earned on your adventures (data/unlocks.json).
func check_unlocks() -> void:
	for entry in catalog.unlock_list:
		if entry.opens.all(func(o): return is_unlocked(o)) or not _earned(entry.earn):
			continue
		for o in entry.opens:
			unlocks[o] = true
		if str(entry.get("announce", "")) != "":
			announcements.append(entry.announce)
		unlocked.emit(entry)
		adventures_changed.emit()
		changed.emit()


func _earned(earn: Dictionary) -> bool:
	if earn.has("find") and not finds.has(earn.find):
		return false
	if earn.get("first", "") == "part" and not parts_ever:
		return false
	if packs_by_hand < int(earn.get("packs_opened", 0)):
		return false
	return true


## The oldest news your pet hasn't told you yet, or "" (then forgotten).
func take_announcement() -> String:
	return announcements.pop_front() if not announcements.is_empty() else ""


## Whether an unlock id ("location:cellar", "automation", "parties") is open.
func is_open(id: String) -> bool:
	if id.begins_with("location:"):
		return location_open(catalog.location(id.substr(9)))
	return is_unlocked(id)


## You say yes to a place a pet spotted: it opens right away.
func follow_lead(location_id: String) -> void:
	if not spotted.has(location_id):
		return
	spotted.erase(location_id)
	unlocks["location:" + location_id] = true
	adventures_changed.emit()
	changed.emit()
	save_game()


## A pet that made it home may have spotted somewhere new on the way.
func _spot_places(run: RunState) -> Array[String]:
	if run.party.size() == 0:
		return []
	var location := catalog.location(run.location_id)
	var known := func(id): return location_open(catalog.location(id)) or spotted.has(id)
	var found := Intel.roll(location, known, spot_tries, _rng)
	for id in found:
		spotted[id] = { "by": run.party.who(), "from": run.location_id }
	return found


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
	if heard.is_empty() and count > 0 and not can.is_empty():
		announcements.append("a rumour is word of somewhere new! it's on the map now. tap it and say yes, and we can go there!")
	for i in mini(count, can.size()):
		var rumour: Dictionary = can.pop_at(_rng.randi_range(0, can.size() - 1))
		heard[rumour.id] = true
		rumours.append(rumour.id)


## Party sizes the finds open: the cart, the wheelbarrow, the hay wagon (data/unlocks.json).
const PARTY_SIZES := [["parties", 3], ["parties_5", 5], ["parties_10", 10]]


## The biggest party you may send here: one pet, then bigger parties as things are found, swarms
## with automation, and a location's own cap.
func max_party(location_id: String) -> int:
	var most := 1
	for step in PARTY_SIZES:
		if feature_on(step[0]):
			most = maxi(most, step[1])
	if is_unlocked(AUTOMATION):
		most = 1 << 30
	var cap := int(catalog.location(location_id).get("max_party", 0))
	return mini(most, cap) if cap > 0 else most


## Debug: a handful of random parts, one of each rarity, to try sewing with.
func debug_give_parts() -> void:
	for tier in catalog.tiers:
		var slots: Array = Catalog.SLOTS.filter(func(s): return not catalog.parts_of_tier(s, tier.id).is_empty())
		var slot: String = slots[_rng.randi_range(0, slots.size() - 1)]
		var options := catalog.parts_of_tier(slot, tier.id)
		var key := "%s:%s" % [slot, options[_rng.randi_range(0, options.size() - 1)].id]
		parts[key] = int(parts.get(key, 0)) + 1
	changed.emit()
	save_game()


func debug_unlock_all() -> void:
	unlock(AUTOMATION)
	for entry in catalog.unlock_list:
		for o in entry.opens:
			unlock(o)
	spotted.clear()
	for l in catalog.locations:
		unlock("location:" + l.id)


## Debug: a completely fresh game, as a new player would start it. The old save is copied to
## user://save-before-new-game-<time>.json first, so it can be put back by hand.
func debug_new_game() -> void:
	save_game()
	var backup := DevProfile.path("save-before-new-game-%d.json" % int(Time.get_unix_time_from_system()))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup))
	coins = 100
	xp = 0
	hunger = 80.0
	happiness = 80.0
	bag.clear()
	parts.clear()
	items.clear()
	unlocks.clear()
	trips_done = 0
	heard.clear()
	rumours.clear()
	spotted.clear()
	spot_tries.clear()
	finds.clear()
	packs_by_hand = 0
	parts_ever = false
	announcements.clear()
	jobs.clear()
	jobs_auto = false
	jobs_away = {}
	_crews_changed()
	pinned.clear()
	visited.clear()
	saved_boxes.clear()
	buying_on = true
	idle_log = {}
	runs.clear()
	news = {}
	collection.load_from({})
	_start_tutorial()
	collection.active_changed.emit(collection.active())
	save_game()
	new_game.emit()
	adventures_changed.emit()
	changed.emit()


# ---- your pet at work ----------------------------------------------------------

## Errands work up to `until` (called every second).
func _work_jobs(until: float) -> void:
	if until > _jobs_at and _jobs_at > 0.0:
		var gap := until - _jobs_at
		if gap > 5.0:  # the computer slept: time away counts like time with the game closed
			var e: Dictionary = catalog.errands
			gap = Jobs.offline_seconds(gap, float(e.offline_full_hours), float(e.offline_after), OFFLINE_CAP)
		_work_for(gap)
	_jobs_at = maxf(_jobs_at, until)


## Every errand works for `seconds`: full meters pay (into your wallet and bag). Returns the loot.
func _work_for(seconds: float) -> Dictionary:
	var total := {}
	if not feature_on("errands") or tutorial_active():
		return total
	for job in catalog.jobs:
		var crew := job_crew(job.id)
		if crew.is_empty():
			continue
		var got := Jobs.work(job, jobs[job.id], crew.size(), job_rate(job.id), seconds, _rng, catalog)
		if got.fills > 0:
			Rewards.add(total, got.loot)
			job_paid.emit(job.id, got.loot)
	if not total.is_empty():
		grant(total)
		_log_idle({ "coins": Rewards.total(total, "coins"), "parts": Rewards.total(total, "part") })
	return total


## Pets resting: not your active pet, not away on an adventure, not on an errand.
func resting_pets() -> Array[Pet]:
	var out: Array[Pet] = []
	for pet in sendable_pets():
		if not _job_of.has(pet.uid):
			out.append(pet)
	return out


## The uids of the pets on an errand.
func job_crew(job_id: String) -> Array:
	return jobs.get(job_id, {}).get("crew", [])


## Which errand a pet is on, or "".
func job_of(uid: String) -> String:
	return str(_job_of.get(uid, ""))


## How full an errand's meter is, 0 to 1.
func job_fill(job_id: String) -> float:
	return float(jobs.get(job_id, {}).get("fill", 0.0))


## How full an errand's meter is right now, between the once-a-second ticks (for drawing it).
func job_fill_now(job_id: String) -> float:
	var since := maxf(0.0, Time.get_unix_time_from_system() - _jobs_at) if _jobs_at > 0.0 else 0.0
	return fposmod(job_fill(job_id) + job_rate(job_id) * since, 1.0)


## How many times a second an errand's meter fills with its crew now.
func job_rate(job_id: String) -> float:
	var crew := job_crew(job_id)
	if crew.is_empty():
		return 0.0
	if not _job_speed.has(job_id):
		var job := catalog.job(job_id)
		var sum := 0.0
		for uid in crew:
			sum += _speed_of(uid, job)
		_job_speed[job_id] = sum / crew.size()
	return Jobs.rate(catalog.job(job_id), crew.size(), _job_speed[job_id], float(catalog.errands.crew_power))


## Puts resting pets on an errand: these uids, or the `count` best at it (-1: everyone resting).
func put_on_job(job_id: String, count := 1, uids: Array = []) -> void:
	if catalog.job(job_id).is_empty() or not feature_on("errands"):
		return
	var resting := resting_pets()
	var going: Array = []
	if not uids.is_empty():
		var ok := {}
		for pet in resting:
			ok[pet.uid] = true
		going = uids.filter(func(uid): return ok.has(uid))
	elif count == 1:
		var job := catalog.job(job_id)
		var best: Pet = null
		for pet in resting:
			if best == null or Jobs.pet_speed(pet, job) > Jobs.pet_speed(best, job):
				best = pet
		if best:
			going.append(best.uid)
	else:
		var job := catalog.job(job_id)
		var speed := {}
		for pet in resting:
			speed[pet.uid] = Jobs.pet_speed(pet, job)
		var uids_by_speed: Array = speed.keys()
		uids_by_speed.sort_custom(func(a, b): return speed[a] > speed[b])
		going = uids_by_speed.slice(0, uids_by_speed.size() if count < 0 else count)
	if going.is_empty():
		return
	var state: Dictionary = jobs.get(job_id, { "crew": [], "fill": 0.0 })
	state.crew.append_array(going)
	jobs[job_id] = state
	_crews_changed()


## Sends pets on an errand home to rest: these uids, or the `count` slowest at it (-1: all).
## Returns the uids that went home.
func take_off_job(job_id: String, count := 1, uids: Array = []) -> Array:
	var crew := job_crew(job_id)
	if crew.is_empty():
		return []
	if uids.is_empty():
		var job := catalog.job(job_id)
		var speed := {}
		for uid in crew:
			speed[uid] = _speed_of(uid, job)
		var sorted := crew.duplicate()
		sorted.sort_custom(func(a, b): return speed[a] < speed[b])
		uids = sorted.slice(0, crew.size() if count < 0 else count)
	return _take_off(uids)


## Spreads every resting pet over the errands: each goes where the crew is smallest.
func share_out() -> void:
	_auto_place(resting_pets().map(func(p): return p.uid))


## Your pet shares out new pets and pets back from adventures (if you let it, see jobs_auto).
func set_jobs_auto(on: bool) -> void:
	jobs_auto = on
	save_game()
	changed.emit()


## Puts these pets (the resting ones) on the errands with the smallest crews.
func _auto_place(uids: Array) -> void:
	if not feature_on("errands") or tutorial_active() or catalog.jobs.is_empty():
		return
	var resting := {}
	for pet in resting_pets():
		resting[pet.uid] = true
	var placed := false
	for uid in uids:
		if not resting.has(uid):
			continue
		var smallest: Dictionary = catalog.jobs[0]
		for job in catalog.jobs:
			if job_crew(job.id).size() < job_crew(smallest.id).size():
				smallest = job
		var state: Dictionary = jobs.get(smallest.id, { "crew": [], "fill": 0.0 })
		state.crew.append(uid)
		jobs[smallest.id] = state
		placed = true
	if placed:
		_crews_changed()


func _take_off(uids: Array) -> Array:
	var gone := {}
	for uid in uids:
		if _job_of.has(uid):
			gone[uid] = true
	if gone.is_empty():
		return []
	for job_id in jobs:
		jobs[job_id].crew = jobs[job_id].crew.filter(func(uid): return not gone.has(uid))
	_crews_changed()
	return gone.keys()


func _speed_of(uid: String, job: Dictionary) -> float:
	var pet := collection.get_pet(uid)
	return Jobs.pet_speed(pet, job) if pet else 1.0


## A crew changed: the lookups are worked out again, and the tab redraws.
func _crews_changed() -> void:
	_job_of.clear()
	for job_id in jobs:
		for uid in jobs[job_id].crew:
			_job_of[uid] = job_id
	_job_speed.clear()
	jobs_changed.emit()
	changed.emit()


## Whether your pet may open this kind of box (you didn't save it for yourself).
func pet_opens(box_id: String) -> bool:
	return not saved_boxes.has(box_id)


## "Save for me" on or off for a kind of box.
func save_for_me(box_id: String, on: bool) -> void:
	if on:
		saved_boxes[box_id] = true
	else:
		saved_boxes.erase(box_id)
	save_game()
	changed.emit()


## The box your pet would open next: one on the pile it's allowed to open, or, once it has the
## piggy bank, the cheapest one it may open that it can buy and still keep the reserve. "" if none.
func next_pet_box() -> String:
	for box in catalog.boxes:
		if not box.get("hidden", false) and pet_opens(box.id) and in_bag(box.id) > 0:
			return box.id
	if not (feature_on("shopping") and buying_on):
		return ""
	for box in catalog.boxes:
		if not box.get("hidden", false) and pet_opens(box.id) and coins - box_price(box.id) >= coin_reserve:
			return box.id
	return ""


## Whether your pet may open a pack now: it's allowed to, and there's one for it.
func can_auto_open() -> bool:
	return feature_on("packs") and packs_on and not tutorial_active() and next_pet_box() != ""


## A view is showing your pet at work (the home room or the corner panel), so it opens packs
## there, one by one, with its little animation. Called every frame it's on screen.
func pack_job_seen() -> void:
	_pack_seen = 0.0


## When nothing shows your pet at work (you're on another tab), it keeps opening packs anyway, at
## about the pace of its animation. What it opened goes in the idle log and good pulls get pinned,
## so the home screen tells you about them when you're back.
func _open_in_background(delta: float) -> void:
	_pack_seen += delta
	if _pack_seen < BACKGROUND_AFTER:
		_pack_timer = 0.0
		return
	_pack_timer += delta
	if _pack_timer >= BACKGROUND_PACK_EVERY:
		_pack_timer = 0.0
		var pet := auto_open_pack()
		if pet:
			opened_in_background.emit(pet)


## How far along the pack your pet is opening out of sight is, 0 to 1, or -1 if it isn't.
func background_packing() -> float:
	if _pack_seen < BACKGROUND_AFTER or not can_auto_open():
		return -1.0
	return _pack_timer / BACKGROUND_PACK_EVERY


## Your pet opens a box from the pile, buying one first if it has to and may (the corner panel
## calls this when its little animation pops). Returns the new pet, or null. Good pulls get
## pinned for you to see.
func auto_open_pack() -> Pet:
	if not can_auto_open():
		return null
	var box_id := next_pet_box()
	if in_bag(box_id) == 0 and not buy_boxes(box_id, 1):
		return null
	var pulled := open_boxes(box_id, 1, "", true)
	if pulled.is_empty():
		return null
	var pet := pulled[0]
	var good: Array = []
	if is_good_pull(pet):
		pinned.append(pet.uid)
		good.append(pet.display_name(catalog))
	_log_idle({ "packs": 1, "good": good })
	return pet


## Rare or better, or a holo-or-better finish: worth showing you.
func is_good_pull(pet: Pet) -> bool:
	return catalog.rank(pet.rarity) >= 2 or catalog.finish_rank(pet.finish) >= 2


func dismiss_pinned() -> void:
	if not pinned.is_empty():
		pinned.remove_at(0)
		changed.emit()


## What your pet did while you weren't looking, then forgotten (the home screen tells you once).
func take_idle_log() -> Dictionary:
	var out := idle_log
	idle_log = {}
	return out


func _log_idle(add: Dictionary) -> void:
	for key in add:
		if add[key] is Array:
			var list: Array = idle_log.get(key, [])
			list.append_array(add[key])
			idle_log[key] = list
		else:
			idle_log[key] = int(idle_log.get(key, 0)) + int(add[key])


# ---- grafting ----------------------------------------------------------------

## Sews a part from the inventory onto your active pet (see Grafting). Returns { ok, old }, or {}.
func sew_part(slot: String, part_id: String) -> Dictionary:
	var pet := collection.active()
	var result := Grafting.sew(pet, slot, part_id, parts, _rng, catalog)
	if result.is_empty():
		return result
	collection.pet_changed.emit(pet)
	collection.active_changed.emit(pet)  # everything showing your pet redraws it
	changed.emit()
	save_game()
	return result


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
	coins = 0
	bag = { FIRST_PET_BOX: 2 }  # two starter boxes on the pile, a gift to open
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
	finds.clear()
	spotted.clear()
	spot_tries.clear()
	adventures_changed.emit()
	changed.emit()
	save_game()


# ---- adventures -------------------------------------------------------------

## uid -> true for every pet that's out on a trip (including trips back but not welcomed yet).
func away() -> Dictionary:
	var out := {}
	for run in runs:
		for uid in run.party.uids:
			out[uid] = true
	return out


## Pets that can be sent: not your active pet, and not already away. Pets on errands can: going
## on an adventure takes them off their errand.
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
	var run := AdventureRunner.start(location_id, going, Time.get_unix_time_from_system(), _rng.randi(), catalog, finds)
	runs.append(run)
	_take_off(going.map(func(p): return p.uid))
	visited[location_id] = true
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
## the collection. Returns what goes on the trip's postcard (see Postcard), or {} if it isn't back yet:
## { place, doodle, photo: [{ pet, home }] in the order they set out, notes: [{ text, stayed }], loot,
## xp gained, spotted: [{ name, doodle }], finds: [names] }.
func collect_run(run: RunState) -> Dictionary:
	if not run in runs or run.status != RunState.Status.DONE:
		return {}
	runs.erase(run)
	trips_done += 1
	var location := catalog.location(run.location_id)
	var photo: Array[Dictionary] = []
	for uid: String in run.party.stats:  # everyone who set out, in order
		var pet := collection.get_pet(uid)
		if pet:
			photo.append({ "pet": pet, "home": not uid in run.party.lost })
	var new_finds: Array[String] = []
	for key: String in run.loot:
		if key.begins_with("find:") and not finds.has(key.substr(5)):
			var find_name := str(catalog.finds.get(key.substr(5), {}).get("name", "something"))
			new_finds.append(find_name)
			announcements.append("%s found %s!" % [run.party.who(), find_name])
	grant(run.loot)
	collection.remove(run.party.lost)
	if jobs_auto:  # the pets that came home go back to work
		_auto_place(photo.filter(func(p): return p.home).map(func(p): return p.pet.uid))
	var found := _spot_places(run)
	# experience: from the trip itself, and a lot for discovering things
	var gained := run.xp + XP_SPOTTED * found.size() + XP_FIND * new_finds.size()
	xp += gained
	var spotted_names: Array[String] = []
	var spotted_places: Array[Dictionary] = []
	for id in found:
		var place := catalog.location(id)
		spotted_names.append(str(place.name))
		spotted_places.append({ "name": place.name, "doodle": str(place.get("map", {}).get("doodle", "")) })
	news = { "place": location.name, "home": run.party.size(),
		"sent": run.party.setting_out(), "parts": Rewards.total(run.loot, "part"),
		"spotted": spotted_names, "who": run.party.who() }
	adventures_changed.emit()
	changed.emit()
	save_game()
	var notes: Array[Dictionary] = []
	for entry in run.history:
		if str(entry.get("text", "")) != "":
			notes.append({ "text": str(entry.text), "stayed": int(entry.get("lost", 0)) > 0 })
	return { "place": location.name, "doodle": str(location.get("map", {}).get("doodle", "")), "photo": photo,
		"notes": notes, "loot": run.loot.duplicate(), "xp": gained, "spotted": spotted_places, "finds": new_finds }


# ---- the trail (clicking along a trip yourself) -----------------------------------

const XP_SPOTTED := 10  # xp for a pet spotting a new place
const XP_FIND := 25  # xp for bringing home a special find
const TREAT_ZOOM := 8.0  # seconds pets zoom along after you toss them a treat
const TREAT_SPEED := 3.0  # how many times as fast they walk while they zoom
const TREAT_EVERY := 30.0  # seconds before you can toss the next treat
const TRAIL_COINS := [0.2, 0.5]  # a coin pickup is worth this times the place's loot (garden: about 1)


## You tossed a treat on the trail: the pets chase it and walk TREAT_SPEED times as fast for
## TREAT_ZOOM seconds. Then the next treat takes TREAT_EVERY seconds. Returns whether it worked.
func toss_treat(run: RunState) -> bool:
	if not run in runs or run.status == RunState.Status.DONE or treat_ready_in(run) > 0.0:
		return false
	var now := Time.get_unix_time_from_system()
	_treats[run] = { "zoom_until": now + TREAT_ZOOM, "ready_at": now + TREAT_EVERY }
	return true


## Seconds until you can toss this trip another treat (0: now).
func treat_ready_in(run: RunState) -> float:
	return maxf(0.0, float(_treats.get(run, {}).get("ready_at", 0.0)) - Time.get_unix_time_from_system())


## Whether this trip's pets are zooming after a treat.
func zooming(run: RunState) -> bool:
	return float(_treats.get(run, {}).get("zoom_until", 0.0)) > Time.get_unix_time_from_system()


## Zooming pets eat up the walk faster (while they're walking, not while they wait at an event).
func _zoom_runs(delta: float) -> void:
	if _treats.is_empty():
		return
	var now := Time.get_unix_time_from_system()
	var moved := false
	for run: RunState in _treats.keys():
		if not run in runs:
			_treats.erase(run)
			continue
		if zooming(run) and run.status == RunState.Status.WALKING:
			run.next_at = maxf(now, run.next_at - delta * (TREAT_SPEED - 1.0))
			if run.next_at <= now:
				moved = _advance(run) or moved
	if moved:
		adventures_changed.emit()
		changed.emit()


## You grabbed something on the trail. Coins go in the trip's bag (lost with the pet), a part waits
## for you to keep it (keep_trail_part), xp is yours straight away, a leaf heals a sore paw. `bonus` grows with a streak of grabs.
## Returns what it was worth, e.g. { "coins": 3 }, for the little "+3" that pops up.
func trail_pickup(run: RunState, kind: String, bonus := 1.0) -> Dictionary:
	if not run in runs or run.status == RunState.Status.DONE:
		return {}
	var location := catalog.location(run.location_id)
	match kind:
		"coins":
			var amount := maxi(1, roundi(_rng.randf_range(TRAIL_COINS[0], TRAIL_COINS[1]) * float(location.loot) * bonus))
			Rewards.add(run.loot, { "coins": amount })
			return { "coins": amount }
		"xp":
			var amount := maxi(1, roundi(bonus))
			xp += amount
			changed.emit()
			return { "xp": amount }
		"heal":
			return { "heal": run.party.heal(1, _rng) }
		"part":
			# not in the bag yet: you pick "add to bag" or "leave it" first (keep_trail_part)
			var part := Rewards.roll_part(str(location.box), _rng, catalog, location.get("part_slots", []))
			return { "part": "part:%s:%s" % part }
	return {}


## You kept a part the pet picked up on the trail: into the trip's bag, or straight into yours
## if the trip was already welcomed back while you were deciding.
func keep_trail_part(run: RunState, key: String) -> void:
	if run in runs:
		Rewards.add(run.loot, { key: 1 })
		changed.emit()
	else:
		grant({ key: 1 })


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
				parts_ever = true
			"find":
				finds[rest] = true
			"rumour":
				_hear_rumours(amount)
			_:
				items[key] = int(items.get(key, 0)) + amount
	check_unlocks()
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
		"xp": xp,
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
		"spotted": spotted,
		"spot_tries": spot_tries,
		"finds": finds.keys(),
		"packs_by_hand": packs_by_hand,
		"parts_ever": parts_ever,
		"announcements": announcements,
		"jobs": jobs,
		"jobs_auto": jobs_auto,
		"packs_on": packs_on,
		"coin_reserve": coin_reserve,
		"saved_boxes": saved_boxes.keys(),
		"visited": visited.keys(),
		"buying_on": buying_on,
		"pinned": pinned,
		"idle_log": idle_log,
		"runs": runs.map(func(r): return r.to_dict()),
		"saved_at": Time.get_unix_time_from_system(),
	}
	SaveFile.write(save_path, data)


## Loads the save. Returns false if there's none yet (a brand new player).
func load_game() -> bool:
	var data := SaveFile.read(save_path)
	if data.is_empty():
		return false
	if int(data.get("version", 1)) > SAVE_VERSION:
		# don't downgrade a save from a newer game: play with it, but never write over it
		push_warning("save is from a newer version of the game; it won't be overwritten")
		_can_save = false
	data = _migrate(data)
	coins = int(data.get("coins", coins))
	xp = int(data.get("xp", 0))
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
	spotted.clear()
	var saved_spots: Dictionary = data.get("spotted", {})
	for id in saved_spots:
		if not catalog.location(id).is_empty():
			spotted[id] = { "by": str(saved_spots[id].get("by", "")), "from": str(saved_spots[id].get("from", "")) }
	finds.clear()
	for id in data.get("finds", []):
		if catalog.finds.has(str(id)):
			finds[str(id)] = true
	packs_by_hand = int(data.get("packs_by_hand", 0))
	parts_ever = bool(data.get("parts_ever", false))
	announcements.assign(data.get("announcements", []).map(func(a): return str(a)))
	spot_tries.clear()
	var saved_tries: Dictionary = data.get("spot_tries", {})
	for id in saved_tries:
		spot_tries[id] = int(saved_tries[id])
	rumours.clear()
	for id in data.get("rumours", []):
		if not catalog.rumour(str(id)).is_empty():
			rumours.append(str(id))
	runs.clear()
	for raw in data.get("runs", []):
		var run := RunState.from_dict(raw, catalog)
		if run != null:
			runs.append(run)

	jobs.clear()
	var on_trips := away()
	var placed := {}
	var saved_jobs: Dictionary = data.get("jobs", {})
	for job_id in saved_jobs:
		if catalog.job(job_id).is_empty() or not saved_jobs[job_id] is Dictionary:
			continue
		var crew: Array = []
		for raw_uid in saved_jobs[job_id].get("crew", []):
			var uid := str(raw_uid)
			if collection.get_pet(uid) != null and uid != collection.active_uid and not on_trips.has(uid) and not placed.has(uid):
				crew.append(uid)
				placed[uid] = true
		jobs[job_id] = { "crew": crew, "fill": clampf(float(saved_jobs[job_id].get("fill", 0.0)), 0.0, 1.0) }
	jobs_auto = bool(data.get("jobs_auto", false))
	_crews_changed()
	packs_on = bool(data.get("packs_on", true))
	coin_reserve = int(data.get("coin_reserve", 50))
	visited.clear()
	for id in data.get("visited", []):
		visited[str(id)] = true
	if not data.has("visited"):
		# from before places glowed: everywhere already open counts as visited
		for location in catalog.locations:
			if location_open(location):
				visited[location.id] = true
	saved_boxes.clear()
	for id in data.get("saved_boxes", []):
		saved_boxes[str(id)] = true
	buying_on = bool(data.get("buying_on", true))
	pinned.assign(data.get("pinned", []).filter(func(uid): return collection.get_pet(str(uid)) != null).map(func(uid): return str(uid)))
	idle_log = data.get("idle_log", {})
	# errands kept going while the game was closed: full speed for a while, then slower
	var e: Dictionary = catalog.errands
	var closed := Jobs.offline_seconds(Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0)),
		float(e.offline_full_hours), float(e.offline_after), OFFLINE_CAP)
	var brought := _work_for(closed)
	jobs_away = { "coins": Rewards.total(brought, "coins"), "parts": Rewards.total(brought, "part") }
	_jobs_at = Time.get_unix_time_from_system()

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
	if version < 11:
		# v11: things open up through adventures now. Saves from before keep what they had
		# (the inventory, errands, parties if they had them, and the second map page if they'd
		# got there); pack opening by your pet is a later-game find now.
		var had: Array = data.get("unlocks", [])
		var keep: Array = ["tab:inventory", "feature:errands", "tab:errands"]
		if "parties" in had or AUTOMATION in had:
			keep.append_array(["feature:parties", "page:beyond"])
		for id in ["fields", "orchard", "well", "cellar", "below"]:
			if ("location:" + id) in had:
				keep.append("page:beyond")
		data.unlocks = had + keep
		data.parts_ever = true
	if version < 9:
		# v9: places open when pets spot them, not after a number of trips; keep what was open
		var had: Array = data.get("unlocks", [])
		var trips := int(data.get("trips_done", 0))
		var keep: Array = []
		if "type:dungeon" in had:
			keep.append("location:well")
		if AUTOMATION in had:
			keep.append(PARTIES)
		for step in [[1, "meadow"], [3, "woods"], [5, "fields"]]:
			if trips >= step[0]:
				keep.append("location:" + step[1])
		data.unlocks = had + keep
	if version < 13:
		# v13: errands are a tab of jobs now; old errands just stop (their pets are home)
		data.erase("errands")
		data.erase("errands_on")
		var had: Array = data.get("unlocks", [])
		if "feature:errands" in had and not "tab:errands" in had:
			data.unlocks = had + ["tab:errands"]
	if version < 14:
		data.jobs_auto = false  # v14: you put pets on errands yourself until you turn sharing on
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
