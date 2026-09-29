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
signal machine_pulled(result: Dictionary)  # the capsule machine gave a capsule, see pull_lever()
signal machine_upgraded(id: String)  # a node on the machine's tree was fixed or levelled up
signal toys_changed  # a toy was found, played with, fixed, combined or sacrificed, or a play ended
signal play_ended(editions: Array)  # your pet finished playing with these toys
signal automation_changed  # a job was taught, your pet moved to another job, or a tool was bought
signal pet_cranked(result: Dictionary)  # your pet's own little machine gave a capsule (see _pet_capsule)
signal gear_changed  # a gear upgrade was bought with xp (the adventures' upgrades page)
signal sticker_opened(page_id: String)  # a collection book page filled up: its reward sticker opened (see Book)
signal knacks_changed  # a knack gate may have opened (an unlock, a machine fix, the tutorial moved on)
signal room_full  # you tried to open a box but the room is full (it waits on the pile)
signal homes_paid(boxes: int)  # pets left for new homes and their points filled this many boxes

var save_path := DevProfile.path("save.json")  # user://save.json, or a test profile's (debug builds)
## Headless tests set this before making a GameState: it starts empty and never loads or saves
## (a test turns saving on with its own save_path).
static var testing := false
const SAVE_VERSION := 28
const WORKER_BOXES_MAX := 2000  # box workers open at most this many boxes in one go (every pet is rolled)
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
var gear := {}  # gear id -> level, bought with xp (the adventures tab's upgrades page, see Gear)
## The collection book's reward stickers you've opened (page ids, see Book and data/book.json).
## Kept for good: the boost reads this list, not how full the page is now.
var stickers: Array[String] = []
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
## Your pet opens packs while it's on the boxes job (the automation tab). The switches in the corner
## panel, settings and the boxes tab move it there or take it off.
var packs_on: bool:
	get: return automation.task == "boxes"

# ---- errands: resting pets on safe jobs, see Jobs and data/errands.json
## job id -> { crew: Array of card uids, herd: { count key: pets from the herd }, fill: 0..1,
## join: new pets start on it ("new pets join here", see _place_new) }
var jobs := {}
var jobs_away := {}  # what errands brought while the game was closed, for the tab's note (not saved)
var _job_of := {}  # uid -> job id, for every pet on an errand
var _job_speed := {}  # job id -> how fast its crew works on average (see Jobs.pet_speed)
var _job_tip := {}  # job id -> its crew's average tip (jobs with "tips")
var _job_tools := {}  # job id -> [crew power, speed, the tools' crew power] with the tools you have
var _boosts := {}  # boost kind -> its total right now (see boost(); cleared by _boosts_changed)
var _knack_steps := {}  # boost kind -> the knack kinds counting for it (see _knack_counting)
var _knack_own := {}  # boost kind -> { pet uid -> its own knack share } (see knack_own)
var knack_version := 0  # goes up whenever pets' knacks may have changed (views keep their totals by it)
var errand_tools := {}  # tool id -> levels bought with coins (the errands' upgrades page, see Jobs)
var scout_notes := 0  # notes the scouting errand has written: your next trips take them along (see Jobs.takes_note)
var _kitchen := -1.0  # how much faster the kitchen makes the other jobs (-1: work it out again)
var _jobs_at := 0.0  # unix time errands have worked up to
var _was_active := ""  # the active pet before it changed (it goes back to work)
var last_moved := ""  # the uid of the last pet put on or taken off an errand (for your pet to name it)
## Who's resting, worked out once until crews, workers, trips or the herd change (see _rest_changed)
var _rest := {}
var room := 0  # room upgrades bought: the room holds this many plain pets, see Herd.room_cap
## New homes: the stall's jar, the sorting rule and its count, see NewHomes and data/new_homes.json
var homes := NewHomes.fresh(Catalog.shared())
var _to_work := {}  # uid -> true: new pets the sorting rule sends to work (placed as they're added)
var _sent_home := {}  # uid -> true: pets from the last open_boxes the sorting rule sent to new homes


## Turns one of your pet's jobs ("packs" or "buying") on or off, from settings or the corner panel.
func set_job(job: String, on: bool) -> void:
	match job:
		"packs":
			if on:
				set_task("boxes")
			elif automation.task == "boxes":
				set_task("")
		"buying": buying_on = on
	save_game()
	changed.emit()


var reserve_capsules := 50  # what your pet never spends on boxes (once it may buy them), in plain capsules
var saved_boxes := {}  # box id -> true: "save for me", your pet leaves these on the pile
var boxes_bought := {}  # box id -> how many you've bought (a tier in the shop is "new!" until the first)
var boxes_greeted := {}  # box id -> true: the boxes tab has shown this tier arriving (your pet said so)
var debug_all_tiers := false  # debug builds: every box tier is in the shop (dev step "tiers all"), not saved
var buying_on := true  # your pet buys more when the pile runs out (once it has the piggy bank)
var pinned: Array[String] = []  # good pulls your pet opened, waiting for you to see them
var rummaged := {}  # rummage spot id -> unix time it has something in it again (see data/rummage.json)
## The capsule machine, see Machine and data/machine.json: { pulls, lit, bought: { upgrade id: n } }
var machine := { "pulls": 0, "lit": 0, "bought": {} }
var fever_until := 0.0  # unix time the machine's fever ends (not saved: it's ten seconds)
## Capsule toys you own and the ones your pet is playing with, see Toys and data/toys.json
var toys := Toys.fresh()
var bits := {}  # machine bits pets bring home from adventures: bit id (gear, spring, bolt, glass) -> how many
## What your pet does for you (the automation tab), see Automation and data/automation.json
var automation := Automation.fresh()
var _auto_at := 0.0  # unix time your pet's jobs have worked up to
var _hold_saves := false  # automation's tick is running: saves wait for the end of it
var _loading := false  # load_game is running: the book waits (collection signals fire halfway through)
var _save_held := false  # a save was asked for while they were held
var started_at := 0.0  # unix time this game was started (0 for saves from before it was noted)
var milestones := {}  # what -> minutes into the game it happened (first pet, adventures, ...)
var debug_next_prize := ""  # debug builds: the next capsule is this prize id (dev driver "next-prize")
## What your pet did while you weren't looking, for the home screen to tell you:
## { coins, parts, boxes, packs, good: [pet names] }
var idle_log := {}
var runs: Array[RunState] = []
## The last trip you welcomed back, for the active pet to talk about: { place, home, sent, parts }.
## Not saved: it's small talk.
var news := {}
## Where the tutorial is ("pull", "machine", "send"), or "done".
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
	# plain cards fold into the herd; whatever job or machine they were on keeps them, as a count
	collection.busy = _busy_uids
	collection.pets_folded.connect(_on_folded)
	collection.herd_changed.connect(func(_keys): _rest_changed())
	if testing:
		_can_save = false
	elif not load_game():
		_start_tutorial()  # a brand new player
	elif collection.count() == 0 and tutorial == "done":
		_give_first_pet()
	# pages already full in an old save open their stickers once the game (and its popups) is up
	check_book.call_deferred()
	collection.pets_added.connect(func(_p): check_book())
	collection.seen_changed.connect(check_book)
	toys_changed.connect(_boosts_changed)
	# knacks: your active pet's feed the boosts, everyone's their own work (see Knacks)
	collection.active_changed.connect(func(_p): _boosts_changed())  # your active pet never works an errand
	collection.pet_changed.connect(func(_p): _knacks_changed())
	unlocked.connect(func(_e): _knack_gates_changed())
	machine_upgraded.connect(func(_id): _knack_gates_changed())
	tutorial_changed.connect(_knack_gates_changed)
	collection.active_changed.connect(func(_p): _check_tutorial())
	collection.pets_added.connect(func(_p): _check_tutorial())
	# your active pet never works an errand; lost pets leave theirs; new pets get one
	collection.active_changed.connect(func(p: Pet):
		_rest_changed()  # first: the old active pet counts as resting before it's placed again
		if p and _job_of.has(p.uid):
			_take_off([p.uid])
		if p and _worker_of.has(p.uid):
			_take_off_workers([p.uid])
		if _was_active != "" and (p == null or p.uid != _was_active):
			_place_new([_was_active])  # your old active pet goes back to work (where new pets join)
		_was_active = p.uid if p else "")
	_was_active = collection.active_uid
	collection.pet_changed.connect(func(_p):
		_worker_speed.clear()
		_job_speed.clear()
		_job_tip.clear()
		_kitchen_changed())  # the kitchen's bonus depends on the cooks
	collection.pets_removed.connect(func(uids):
		_take_off(uids)
		_take_off_workers(uids)
		pinned = pinned.filter(func(uid): return not uid in uids)
		_rest_changed())
	collection.pets_added.connect(func(pets: Array[Pet]):
		_rest_changed()
		_place_new(pets.map(func(p): return p.uid)))


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
		_work_automation(Time.get_unix_time_from_system())
		_boosts_changed()  # a play may have just run out
		var ended := Toys.finish_plays(toys, Time.get_unix_time_from_system())
		if not ended.is_empty():
			toys_changed.emit()
			play_ended.emit(ended)
			save_game()

	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()


# ---- boxes ----------------------------------------------------------------

## The coins your pet keeps when it buys boxes itself: its reserve of capsules x what a capsule is
## worth now, so it keeps up with box prices.
func coin_reserve() -> int:
	return roundi(minf(float(reserve_capsules) * capsule_value(), Jobs.MAX_PRICE))


## Where the reserve starts, its step and its top, in capsules (data/boxes.json "reserve").
func default_reserve() -> int:
	return int(catalog.box_rules.get("reserve", {}).get("capsules", 50))


func reserve_step() -> int:
	return int(catalog.box_rules.get("reserve", {}).get("step", 50))


func reserve_max() -> int:
	return int(catalog.box_rules.get("reserve", {}).get("max", 2000))


## Sets the reserve to `capsules` (0 up to reserve_max) and saves.
func set_reserve(capsules: int) -> void:
	reserve_capsules = clampi(capsules, 0, reserve_max())
	save_game()


## What `count` of a box cost in coins now (see box_cost).
func box_price(box_id: String, count := 1) -> int:
	return box_cost(catalog.box(box_id), capsule_value(), count)


## What `count` of a box cost in coins with a capsule worth `value`: its 'capsules' x value (so the
## shop keeps up with the machine, like errands), or a fixed 'price'.
static func box_cost(box: Dictionary, value: float, count := 1) -> int:
	var unit := float(box.capsules) * value if box.has("capsules") else float(box.get("price", 0))
	if unit <= 0.0 or count <= 0:
		return 0
	var one := maxi(1, roundi(minf(unit, Jobs.MAX_PRICE)))  # one box's price, rounded: 10 cost 10x that
	return int(minf(float(one) * count, Jobs.MAX_PRICE))


## The box tiers in the shop: the ones whose map page is open, cheapest first.
func shop_boxes() -> Array[Dictionary]:
	return BoxShop.open_tiers(catalog, page_open, debug_all_tiers and OS.is_debug_build())


func box_in_shop(box_id: String) -> bool:
	return shop_boxes().any(func(b): return b.id == box_id)


## The piles on your stash: every tier in the shop, and any other box you have some of.
func stash_boxes() -> Array[Dictionary]:
	var out := shop_boxes()
	for b in catalog.shop_boxes():
		if in_bag(b.id) > 0 and not out.has(b):
			out.append(b)
	out.sort_custom(func(a, b): return catalog.box_rank(a.id) < catalog.box_rank(b.id))
	return out


## A tier that just came into the shop wears a gold "new!" tag until you buy your first one (the
## first tier never does: it was always there).
func box_is_new(box_id: String) -> bool:
	return catalog.box_rank(box_id) > 0 and box_in_shop(box_id) and int(boxes_bought.get(box_id, 0)) == 0


## Something waits in the boxes tab: boxes on the pile, or a tier that came into the shop.
func box_news() -> bool:
	return bag.values().any(func(n): return int(n) > 0) or shop_boxes().any(func(b): return box_is_new(b.id) and not boxes_greeted.has(b.id))


## The boxes tab showed this tier arriving (its row popped in, your pet said so): only once.
func greet_box(box_id: String) -> void:
	if not boxes_greeted.has(box_id):
		boxes_greeted[box_id] = true
		save_game()


## Buys boxes: they go on your pile (the bag) to open later, by you or your pet. Returns
## whether you could afford them (and the shop sells that tier).
func buy_boxes(box_id: String, count := 1) -> bool:
	var price := box_price(box_id, count)
	if count <= 0 or coins < price or not box_in_shop(box_id):
		return false
	coins -= price
	bag[box_id] = in_bag(box_id) + count
	boxes_bought[box_id] = int(boxes_bought.get(box_id, 0)) + count
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


## Opens `count` boxes from your pile. Returns the new pets, every pet in every box (a sunset box
## holds 2-3), box by box; empty if there aren't that many on the pile.
## Only as many boxes as the room has space for open (a full room opens none: they wait on the pile).
## `force_tier` only works in debug builds, for testing reveals (the first pet of each box).
## `by_pet`: your pet opened it (doesn't count toward packs you opened yourself).
## Once the sorting rule is on, the new pets it sorts leave for new homes (or go to work) as they
## arrive: they're still in what this returns (the reveal shows everything you pulled).
func open_boxes(box_id: String, count := 1, force_tier := "", by_pet := false) -> Array[Pet]:
	var pulled: Array[Pet] = []
	if count <= 0 or in_bag(box_id) < count:
		return pulled
	if not tutorial_active():
		count = mini(count, boxes_that_fit(box_id))
		if count <= 0:
			_room_hit()
			if not by_pet:
				room_full.emit()
			return pulled
	bag[box_id] = in_bag(box_id) - count
	if bag[box_id] <= 0:
		bag.erase(box_id)
	# the tutorial's boxes are plain commons: your first pets shouldn't be a mythic by luck
	var roll_from := TUTORIAL_BOX if tutorial_active() else box_id
	var forced := force_tier if OS.is_debug_build() and not tutorial_active() else ""
	for i in count:
		pulled.append_array(_roller.roll_box(roll_from, forced))
	_sent_home.clear()
	for pet in collection.add(pulled, _sorter()):
		_sent_home[pet.uid] = true
	if room_left() <= 0 and not tutorial_active():
		_room_hit()
	if not by_pet:
		packs_by_hand += count
		check_unlocks()
	changed.emit()
	save_game()
	return pulled


func in_bag(box_id: String) -> int:
	return int(bag.get(box_id, 0))


## How many of a box fit in the room now: each counts as its most pets (a sunset box as 3), rounded
## up, so the last box can squeeze a pet or two past the cap. 0 when the room is full.
func boxes_that_fit(box_id: String) -> int:
	var left := room_left()
	if left <= 0:
		return 0
	var range_: Array = catalog.box(box_id).get("pets", [1, 1])
	return ceili(float(left) / maxi(1, int(range_[range_.size() - 1])))


# ---- the room: one cap for every plain pet together (see Herd, data/herd.json) ----------------

## How many plain pets the room holds now.
func room_cap() -> int:
	return Herd.room_cap(catalog, room)


## Space left in the room (box openings stop at 0: the boxes wait on the pile).
func room_left() -> int:
	return maxi(0, room_cap() - collection.plain_count())


## The room is full: box openings wait.
func room_is_full() -> bool:
	return room_left() <= 0


## The room is nearly full (data/herd.json room "cozy_at").
func room_is_cozy() -> bool:
	return collection.plain_count() >= room_cap() * float(catalog.herd.get("room", {}).get("cozy_at", 0.9))


## What the next room upgrade costs.
func room_price() -> int:
	return Herd.room_cost(catalog, room)


## The room shows (the pill on the pets tab) once a pet has folded into the herd.
func room_shown() -> bool:
	return collection.herd_ever or room > 0


## Buys the next room upgrade with coins. Returns whether you could.
func buy_room() -> bool:
	var price := room_price()
	if coins < price:
		return false
	coins -= price
	room += 1
	changed.emit()
	save_game()
	return true


# ---- new homes: the stall on the pets tab and the sorting rule (see NewHomes) ---------------

## The room stopped a box opening (or is full): the first time, the new homes stall opens.
func _room_hit() -> void:
	if homes.room_was_full:
		return
	homes.room_was_full = true
	check_unlocks()


## Whether the new homes stall is there (the room has been full once).
func homes_open() -> bool:
	return feature_on("new_homes")


## Pets of a rarity the stall may take, in the order it takes them: a plain finish at a time
## (normal before shiny); inside one, resting before working, and counts before the oldest cards.
## Never favourites, the active pet, pets with a part new to the book, holo or better, pets away,
## pinned pulls or party leaders. `n` -1: all of them. Returns { cards: [uids], rest: { key: n }
## (resting counts), work: { key: n } (counts on errands and machines), n }.
func homes_pick(rarity: String, n := -1) -> Dictionary:
	var out := { "cards": [], "rest": {}, "work": {}, "n": 0 }
	var left := n if n >= 0 else (1 << 62)
	var busy := _busy_uids()
	var free_rest := resting_herd()
	var out_now := {}
	for uid: String in _stand_ins_out():
		Herd.put(out_now, Herd.key_of(uid), 1)
	var resting := {}
	for pet in resting_cards():
		resting[pet.uid] = true
	var cards := collection.cards_of(rarity)
	for f in catalog.finishes:
		if left <= 0:
			break
		if not Herd.plain(catalog, str(f.id)):
			continue
		var k := Herd.key(rarity, str(f.id))
		var mine: Array[Pet] = []  # this finish's cards that may go, oldest first
		for pet in cards:
			if pet.finish == f.id and not collection.always_card(pet) and not busy.has(pet.uid):
				mine.append(pet)
		# resting: the count, then the cards
		var take := mini(left, int(free_rest.get(k, 0)))
		if take > 0:
			out.rest[k] = take
			left -= take
		for pet in mine:
			if left <= 0:
				break
			if resting.has(pet.uid):
				out.cards.append(pet.uid)
				left -= 1
		# working: the count on errands and machines, then the cards
		var working := collection.herd_count(k) - int(free_rest.get(k, 0)) - int(out_now.get(k, 0))
		take = mini(left, maxi(0, working))
		if take > 0:
			out.work[k] = take
			left -= take
		for pet in mine:
			if left <= 0:
				break
			if not resting.has(pet.uid):
				out.cards.append(pet.uid)
				left -= 1
	out.n = out.cards.size() + Herd.total(out.rest) + Herd.total(out.work)
	return out


## How many pets of a rarity the stall may take right now.
func homes_can_go(rarity: String) -> int:
	return int(homes_pick(rarity).n)


## The stall takes `n` pets of a rarity (-1: all it may), see homes_pick. They leave for good (a
## star each), their points go in the jar, and full jars drop boxes on your pile. Returns
## { n: how many left, boxes }.
func send_home(rarity: String, n := 1) -> Dictionary:
	var plan := homes_pick(rarity, n)
	if int(plan.n) <= 0:
		return { "n": 0, "boxes": 0 }
	for k in plan.work:
		_herd_off_places(k, int(plan.work[k]))  # off their errands and machines first
	var counts: Dictionary = plan.rest.duplicate()
	for k in plan.work:
		Herd.put(counts, k, int(plan.work[k]))
	var gone := collection.leave(counts, plan.cards)
	var boxes := NewHomes.pay(homes, catalog, rarity, gone)
	if boxes > 0:
		var box := NewHomes.box_id(catalog)
		bag[box] = in_bag(box) + boxes
		homes_paid.emit(boxes)
	homes.by_hand = int(homes.by_hand) + gone
	check_unlocks()
	changed.emit()
	save_game()
	return { "n": gone, "boxes": boxes }


## The sorting rule, if it's on (and found): what Collection.add asks about each new pet from a box.
func _sorter() -> Callable:
	if tutorial_active() or not feature_on("sorting") or not homes.rule.on:
		return Callable()
	return _sort_pet


## The sorting rule on one new pet: "homes" (it leaves, its points go in the jar), "work" (it goes
## to work as it's added) or "" (it stays).
func _sort_pet(pet: Pet) -> String:
	if not NewHomes.sorts(catalog, homes.rule, pet):
		return ""
	NewHomes.count_sorted(homes, NewHomes.today())
	if str(homes.rule.to) == "work":
		_to_work[pet.uid] = true
		return "work"
	var boxes := NewHomes.pay(homes, catalog, pet.rarity, 1)
	if boxes > 0:
		var box := NewHomes.box_id(catalog)
		bag[box] = in_bag(box) + boxes
		homes_paid.emit(boxes)
	return "homes"


## Pets the sorting rule sorted today.
func sorted_today() -> int:
	return NewHomes.sorted_on(homes, NewHomes.today())


## The sorting card: on or off, "below" (a rarity), "to" (homes / work), "keep" (a finish).
func set_rule(key: String, value) -> void:
	match key:
		"on": homes.rule.on = bool(value)
		"below":
			if catalog.tiers.any(func(t): return t.id == str(value)):
				homes.rule.below = str(value)
		"to":
			if str(value) in NewHomes.TO:
				homes.rule.to = str(value)
		"keep":
			if catalog.finish(str(value)).id == str(value):
				homes.rule.keep = str(value)
	changed.emit()
	save_game()


## Rarities the card's "below" stepper offers: every rarity above the lowest, up to the rarest you
## have (and whatever it's set to).
func rule_rarities() -> Array[String]:
	var out: Array[String] = []
	var top := 1
	for t in catalog.tiers:
		if collection.count_of(t.id) > 0:
			top = maxi(top, catalog.rank(t.id) + 1)
	top = maxi(top, catalog.rank(str(homes.rule.below)))
	for i in range(1, mini(top, catalog.tiers.size() - 1) + 1):
		out.append(str(catalog.tiers[i].id))
	return out


## Finishes the card's keep stepper offers: shiny and better, the ones you've had (and whatever
## it's set to).
func rule_finishes() -> Array[String]:
	var had := {}
	for key: String in collection.seen_keys():
		if key.begins_with("finish:"):
			had[key.get_slice(":", 2)] = true
	var out: Array[String] = []
	for f in catalog.finishes:
		if catalog.finish_rank(f.id) >= 1 and (had.has(f.id) or f.id == homes.rule.keep):
			out.append(str(f.id))
	return out


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
	_knack_gates_changed()
	_opened(id)
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
			_opened(str(o))
		if str(entry.get("pet_job", "")) != "":
			_gift_pet(str(entry.pet_job))
		if str(entry.get("announce", "")) != "":
			announcements.append(entry.announce)
		unlocked.emit(entry)
		_milestone(str(entry.id))
		adventures_changed.emit()
		changed.emit()


## Something just opened: the whistle is your pet's managing job, known from the moment it's found.
func _opened(id: String) -> void:
	if id == "feature:" + Automation.WHISTLE:
		automation.taught[Automation.WHISTLE] = true
		automation_changed.emit()


func _earned(earn: Dictionary) -> bool:
	if earn.has("find") and not finds.has(earn.find):
		return false
	if earn.get("first", "") == "part" and not parts_ever:
		return false
	if earn.get("first", "") == "toy" and toys.owned.is_empty():
		return false
	if trips_done < int(earn.get("trips", 0)):
		return false
	if earn.has("machine") and Machine.owned(machine, str(earn.machine)) <= 0:
		return false
	if packs_by_hand < int(earn.get("packs_opened", 0)):
		return false
	if earn.has("open") and not is_unlocked(str(earn.open)):
		return false
	if earn.has("taught") and not knows_job(str(earn.taught)):
		return false
	if earn.get("room", "") == "full" and not homes.room_was_full:
		return false
	if int(homes.by_hand) < int(earn.get("homes_by_hand", 0)):
		return false
	var levels: Dictionary = earn.get("job_level", {})
	for job_id in levels:
		if job_level(str(job_id)) < int(levels[job_id]):
			return false
	return true


## A pet comes along with an unlock (the basket has one asleep in it) and starts on that errand, so
## there's someone to do it even when your only other pet is out on an adventure.
func _gift_pet(job_id: String) -> void:
	var got: Array[Pet] = [_roller.roll(TUTORIAL_BOX)]
	collection.add(got)
	put_on_job(job_id, 1, [got[0].uid])


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
	var bonus := float(run.scout.get("spot", 0.0))
	var found := Intel.roll(location, _place_known, spot_tries, _rng, bonus, run.knack("spots"))
	for id in found:
		spotted[id] = { "by": run.party.who(), "from": run.location_id }
	return found


## Whether you know a place: it's open, or a pet spotted it.
func _place_known(id: String) -> bool:
	return location_open(catalog.location(id)) or spotted.has(id)


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
	jobs_away = {}
	homes = NewHomes.fresh(catalog)
	_to_work.clear()
	errand_tools = {}
	scout_notes = 0
	gear = {}
	stickers.clear()
	_boosts_changed()
	room = 0
	_crews_changed()
	pinned.clear()
	rummaged.clear()
	machine = { "pulls": 0, "lit": 0, "bought": {} }
	fever_until = 0.0
	toys = Toys.fresh()
	_knacks_changed()
	bits = {}
	automation = Automation.fresh()
	_auto_at = 0.0
	_worker_of.clear()
	_worker_speed.clear()
	visited.clear()
	saved_boxes.clear()
	reserve_capsules = default_reserve()
	boxes_bought.clear()
	boxes_greeted.clear()
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
			gap = Jobs.offline_seconds(gap, errands_away_hours(), float(e.offline_after), OFFLINE_CAP) * boost("away")
		_work_for(gap)
	_jobs_at = maxf(_jobs_at, until)


## Every errand works for `seconds`: full meters pay (into your wallet and bag). Returns the loot.
func _work_for(seconds: float) -> Dictionary:
	var total := {}
	if not feature_on("errands") or tutorial_active():
		return total
	for job in open_jobs():
		var size := job_size(job.id)
		if size == 0 or (job.has("scout") and scout_full()):
			continue  # nobody on it, or the scouts' notes are all waiting for trips
		var got := Jobs.work(job, jobs[job.id], size, job_rate(job.id), seconds, _rng, catalog, job_boost(job.id))
		if got.fills > 0:
			if got.loot.has("coins"):
				got.loot.coins = roundi(int(got.loot.coins) * boost("coins"))  # shown as it lands
			if got.loot.has("meal"):  # the kitchen fed your pet (up to its "meal_upto")
				var fed := Jobs.feed(job, hunger, happiness, int(got.loot.meal) / maxi(1, int(job.pay.meal)))
				hunger = fed.food
				happiness = fed.mood
				got.loot.meal = roundi(fed.eaten)  # 0: it wasn't hungry enough, nothing to show
			if got.loot.has("note"):  # the scouts wrote notes, as many as fit
				got.loot.note = mini(int(got.loot.note), scout_hold() - scout_notes)
				scout_notes += int(got.loot.note)
			job_paid.emit(job.id, got.loot)
			got.loot.erase("meal")
			got.loot.erase("note")
			Rewards.add(total, got.loot)
	if not total.is_empty():
		grant(total, false)
		_log_idle({ "coins": Rewards.total(total, "coins"), "parts": Rewards.total(total, "part") })
	return total


## Scout notes you can hold (the scouting errand's hold, and a map case holds more).
func scout_hold() -> int:
	return Jobs.scout_hold(catalog, errand_tools)


## Whether you hold all the scout notes you can (the scouting meter waits, full).
func scout_full() -> bool:
	return scout_notes >= scout_hold()


## Sets the scout notes you hold (the dev driver's "notes" step).
func set_scout_notes(n: int) -> void:
	scout_notes = clampi(n, 0, scout_hold())
	jobs_changed.emit()
	changed.emit()


## The errands you can put pets on: every job whose "needs" is open (data/errands.json).
func open_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for job in catalog.jobs:
		if str(job.get("needs", "")) == "" or is_unlocked(str(job.needs)):
			out.append(job)
	return out


# ---- who's resting: not your active pet, not away on an adventure, not on an errand or working ----

## Who's resting, worked out once until crews, workers, trips or the herd change:
## { cards: [Pet], herd: { count key: n }, n: everyone }.
func _resting() -> Dictionary:
	if _rest.is_empty():
		var gone := away()
		var cards: Array[Pet] = []
		for pet in collection.pets:
			if pet.uid != collection.active_uid and not gone.has(pet.uid) and not _job_of.has(pet.uid) and not _worker_of.has(pet.uid):
				cards.append(pet)
		var used := _herd_used(gone)
		var free := {}
		var n := cards.size()
		for k in collection.herd:
			var left := collection.herd_count(k) - int(used.get(k, 0))
			if left > 0:
				free[k] = left
				n += left
		_rest = { "cards": cards, "herd": free, "n": n }
	return _rest


## Something changed who's resting: it's worked out again when next asked.
func _rest_changed() -> void:
	_rest = {}


## Pets from the herd that are busy: count key -> on errands, working, away or leading a party.
func _herd_used(gone: Dictionary) -> Dictionary:
	var used := {}
	for job_id in jobs:
		var h: Dictionary = jobs[job_id].get("herd", {})
		for k in h:
			Herd.put(used, k, int(h[k]))
	var wh: Dictionary = automation.get("wherd", {})
	for id in wh:
		for k in wh[id]:
			Herd.put(used, k, int(wh[id][k]))
	for uid: String in _stand_ins_out(gone):
		Herd.put(used, Herd.key_of(uid), 1)
	return used


## Stand-ins in use: away on an adventure or leading a workers' party. uid -> true.
func _stand_ins_out(gone := {}) -> Dictionary:
	var out := {}
	for uid: String in (gone if not gone.is_empty() else away()):
		if Herd.is_stand_in(uid):
			out[uid] = true
	for uid in workers_of("adventures"):
		if Herd.is_stand_in(str(uid)):
			out[str(uid)] = true
	return out


## Cards resting (whole pets), in pull order.
func resting_cards() -> Array[Pet]:
	return _resting().cards


## Pets from the herd resting: count key -> how many.
func resting_herd() -> Dictionary:
	return _resting().herd


## Everyone resting, cards and herd.
func resting_count() -> int:
	return int(_resting().n)


## Up to `n` resting pets to show (uids): cards first, then stand-ins for the counts.
func resting_faces(n: int) -> Array:
	var cards: Array = resting_cards().slice(0, n).map(func(p): return p.uid)
	return _faces(cards, resting_herd(), n, 7)


## Resting pets as whole pets: every resting card, and up to data/herd.json "stand_ins" stand-ins
## from each resting count (for parties).
func resting_pets() -> Array[Pet]:
	var out: Array[Pet] = resting_cards().duplicate()
	out.append_array(_resting_stand_ins())
	return out


## Up to data/herd.json "stand_ins" stand-ins from each resting count.
func _resting_stand_ins() -> Array[Pet]:
	var out: Array[Pet] = []
	var skip := _stand_ins_out()
	var per := int(catalog.herd.get("stand_ins", 10))
	var h := resting_herd()
	for k in h:
		for uid in collection.stand_in_uids(k, mini(per, int(h[k])), skip):
			out.append(collection.get_pet(uid))
	return out


## Pets on your spare list: everyone but your active pet and pets away on adventures.
func spare_count() -> int:
	var gone := away()
	return maxi(0, collection.count() - (1 if collection.active() != null else 0) - gone.size())


## Cards first, then stand-ins for `counts` (a different run of faces per `salt`), up to `n` uids.
func _faces(cards: Array, counts: Dictionary, n: int, salt := 0) -> Array:
	var out: Array = cards.slice(0, n)
	for k in counts:
		if out.size() >= n:
			break
		out.append_array(collection.stand_in_uids(k, mini(n - out.size(), int(counts[k])), {}, 1000 + salt * 64))
	return out


## Up to `n` stand-ins (uids) for pets in `counts`, a different run of faces per `salt`.
func herd_faces(counts: Dictionary, n: int, salt := 0) -> Array:
	return _faces([], counts, n, salt)


## A rarity's cards split for its shelf: [always, newest]. Always: pets that stay cards (your active
## pet first, then favourites, better finishes, new parts) and pets busy right now; newest: the other
## plain cards, newest first.
func shelf_split(rarity: String) -> Array:
	var busy := _busy_uids()
	var cards := collection.cards_of(rarity)
	# only a few different ranks: bucket by rank, newest first inside each (no sort over thousands)
	var by_rank := {}  # rank -> pets, newest first
	var newest: Array[Pet] = []
	var finish_ranks := {}
	for i in range(cards.size() - 1, -1, -1):
		var pet := cards[i]
		if collection.always_card(pet) or busy.has(pet.uid):
			if not finish_ranks.has(pet.finish):
				finish_ranks[pet.finish] = catalog.finish_rank(pet.finish)
			var r: int = (1000 if pet.uid == collection.active_uid else 0) + (500 if pet.fav else 0) \
				+ int(finish_ranks[pet.finish]) * 10 + (1 if pet.new_part else 0)
			if not by_rank.has(r):
				by_rank[r] = []
			by_rank[r].append(pet)
		else:
			newest.append(pet)
	var ranks := by_rank.keys()
	ranks.sort()
	ranks.reverse()
	var always: Array[Pet] = []
	for r in ranks:
		always.append_array(by_rank[r])
	return [always, newest]


## Uids that must stay whole cards right now: away, good pulls waiting to be seen, party leaders.
func _busy_uids() -> Dictionary:
	var out := away()
	for uid in pinned:
		out[uid] = true
	for uid in workers_of("adventures"):
		if str(uid) != "":
			out[str(uid)] = true
	return out


## Cards folded into the herd: the errand or machine they were on keeps them, as a count.
func _on_folded(uids: Array, keys: Array) -> void:
	var from_jobs := {}  # job id -> { uid: true }
	var from_workers := {}
	var wh: Dictionary = automation.get("wherd", {})
	for i in uids.size():
		var uid := str(uids[i])
		var k := str(keys[i])
		var job := str(_job_of.get(uid, ""))
		if job != "" and jobs.has(job):
			if not from_jobs.has(job):
				from_jobs[job] = {}
			from_jobs[job][uid] = true
			Herd.put(_job_state(job).herd, k, 1)
		var w := str(_worker_of.get(uid, ""))
		if w != "" and w != "adventures":
			if not from_workers.has(w):
				from_workers[w] = {}
			from_workers[w][uid] = true
			if not wh.has(w):
				wh[w] = {}
			Herd.put(wh[w], k, 1)
	automation.wherd = wh
	for job in from_jobs:
		jobs[job].crew = jobs[job].crew.filter(func(uid): return not from_jobs[job].has(uid))
	for w in from_workers:
		automation.workers[w] = automation.workers[w].filter(func(uid): return not from_workers[w].has(str(uid)))
	if not from_jobs.is_empty():
		_crews_changed()
	if not from_workers.is_empty():
		_workers_changed()
	_rest_changed()


## Picks pets out of `cards` and `counts` by `speed` (a Callable on a Pet): the fastest first, or
## the slowest with `best_first` false; `count` -1 takes everyone. Returns [card uids, { key: n }].
func _pick(cards: Array, counts: Dictionary, count: int, speed: Callable, best_first: bool) -> Array:
	var options := []  # [speed, card uid or "", count key or "", how many]
	for pet: Pet in cards:
		options.append([speed.call(pet), pet.uid, "", 1])
	for k in counts:
		options.append([speed.call(Herd.template(catalog, k)), "", k, int(counts[k])])
	options.sort_custom(func(a, b): return a[0] > b[0] if best_first else a[0] < b[0])
	var left := count if count >= 0 else (1 << 62)
	var out_cards: Array = []
	var out_counts := {}
	for o in options:
		if left <= 0:
			break
		if o[1] != "":
			out_cards.append(o[1])
			left -= 1
		else:
			var take := mini(left, int(o[3]))
			out_counts[o[2]] = take
			left -= take
	return [out_cards, out_counts]


## Spreads `n` pets over places so the smallest fill up first: place id -> how many it gets
## (`sizes` is place id -> how many it has now).
static func water_fill(sizes: Dictionary, n: int) -> Dictionary:
	var out := {}
	if sizes.is_empty() or n <= 0:
		return out
	var ids := sizes.keys()
	ids.sort_custom(func(a, b): return int(sizes[a]) < int(sizes[b]))
	var k := 1
	var level := int(sizes[ids[0]])
	while true:
		while k < ids.size() and int(sizes[ids[k]]) <= level:
			k += 1
		var fits := (int(sizes[ids[k]]) - level) * k if k < ids.size() else -1
		if fits < 0 or fits >= n:
			var each := n / k
			var extra := n % k
			for i in k:
				out[ids[i]] = level - int(sizes[ids[i]]) + each + (1 if i < extra else 0)
			return out
		n -= fits
		level = int(sizes[ids[k]])
	return out


# ---- errands ---------------------------------------------------------------------------

## The uids of the cards on an errand (its pets from the herd are counts, see job_herd).
func job_crew(job_id: String) -> Array:
	return jobs.get(job_id, {}).get("crew", [])


## The pets from the herd on an errand: count key -> how many.
func job_herd(job_id: String) -> Dictionary:
	return jobs.get(job_id, {}).get("herd", {})


## How many pets are on an errand: cards and counts.
func job_size(job_id: String) -> int:
	return job_crew(job_id).size() + Herd.total(job_herd(job_id))


## Up to `n` of an errand's pets to show (polaroids, piles, crowds): uids of its cards first,
## then stand-ins for its counts.
func job_faces(job_id: String, n: int) -> Array:
	return _faces(job_crew(job_id), job_herd(job_id), n, maxi(0, catalog.jobs.find(catalog.job(job_id))))


## An errand's state, made if it has none yet.
func _job_state(job_id: String) -> Dictionary:
	if not jobs.has(job_id):
		jobs[job_id] = { "crew": [], "herd": {}, "fill": 0.0, "join": false }
	if not jobs[job_id].has("herd"):
		jobs[job_id].herd = {}
	return jobs[job_id]


## Which errand a pet is on, or "".
func job_of(uid: String) -> String:
	return str(_job_of.get(uid, ""))


## How full an errand's meter is, 0 to 1.
func job_fill(job_id: String) -> float:
	return float(jobs.get(job_id, {}).get("fill", 0.0))


## How full an errand's meter is right now, between the once-a-second ticks (for drawing it).
func job_fill_now(job_id: String) -> float:
	if catalog.job(job_id).has("scout") and scout_full() and job_size(job_id) > 0:
		return 1.0  # full, waiting for a trip to take a note
	var since := maxf(0.0, Time.get_unix_time_from_system() - _jobs_at) if _jobs_at > 0.0 else 0.0
	return fposmod(job_fill(job_id) + job_rate(job_id) * since, 1.0)


## How many times a second an errand's meter fills with its crew now.
func job_rate(job_id: String) -> float:
	var size := job_size(job_id)
	if size == 0:
		return 0.0
	var job := catalog.job(job_id)
	if not _job_speed.has(job_id):
		var sum := 0.0
		for uid in job_crew(job_id):
			sum += _speed_of(uid, job)
		var h := job_herd(job_id)
		for k in h:
			sum += Jobs.pet_speed(Herd.template(catalog, k), job) * int(h[k])
		_job_speed[job_id] = sum / size
	if not _job_tools.has(job_id):  # what the tools do to this job's speed (per frame, so kept)
		_job_tools[job_id] = [float(catalog.errands.crew_power) + Jobs.tool_sum(catalog, job_id, "crew_power", errand_tools),
			1.0 + Jobs.tool_sum(catalog, job_id, "speed", errand_tools) + Jobs.tool_sum(catalog, job_id, "all_speed", errand_tools),
			Jobs.tool_sum(catalog, job_id, "crew_power", errand_tools)]
	var x := boost("errands")  # the kitchen, the book's errands stickers, toys, knacks
	if job.has("kitchen"):
		x /= 1.0 + kitchen_bonus()  # the cooks don't speed up their own kitchen
	return Jobs.rate(job, size, _job_speed[job_id], _job_tools[job_id][0], _job_tools[job_id][2]) * _job_tools[job_id][1] * x


## The kitchen's cooks or the other crews changed: its bonus (a boost source) is worked out again.
func _kitchen_changed() -> void:
	_kitchen = -1.0
	_boosts_changed()


## How much faster the kitchen's cooks make every other job (0.12 = 12% faster), see Jobs.kitchen_bonus.
## It's the `kitchen` source of the "errands" boost (see boost_parts).
func kitchen_bonus() -> float:
	if _kitchen >= 0.0:
		return _kitchen
	_kitchen = 0.0
	for job in open_jobs():
		if not job.has("kitchen") or job_size(job.id) == 0:
			continue
		var cooks := 0.0
		for uid in job_crew(job.id):
			cooks += _speed_of(uid, job)
		var h := job_herd(job.id)
		for k in h:
			cooks += Jobs.pet_speed(Herd.template(catalog, k), job) * int(h[k])
		var others := 0
		for job_id in jobs:
			if job_id != job.id:
				others += job_size(job_id)
		var power := float(catalog.errands.crew_power) + Jobs.tool_sum(catalog, "", "crew_power", errand_tools)
		_kitchen = Jobs.kitchen_bonus(job, cooks, others, power)
	return _kitchen


## Coins in a plain capsule on the machine now: what errands pay in, and what errand tools and
## boxes are priced in.
func capsule_value() -> float:
	return Machine.coin_value(machine, catalog)


## What an errand's "capsules" pay is worth now (see Jobs.pay): a capsule's coins on the machine,
## the tools' extra capsules, its goals, its crew's tips, big finds and shiny ones.
func job_boost(job_id: String) -> Dictionary:
	var job := catalog.job(job_id)
	var shiny := Jobs.tool_sum(catalog, job_id, "shiny", errand_tools) > 0.0
	return { "coin_value": capsule_value(),
		"worth": Jobs.tool_sum(catalog, job_id, "worth", errand_tools),
		"x": Jobs.goal_x(job, job_level(job_id)) * job_tips(job_id),
		"big": Jobs.tool_sum(catalog, job_id, "big", errand_tools), "big_x": float(catalog.errands.get("big_x", 5)),
		"shiny": Machine.shiny_chance(machine, catalog) * boost("shiny") if shiny else 0.0, "shiny_pay": Machine.shiny_pay(machine, catalog) }


## A job with "tips" pays by its crew's rarity: their average tip (1 for jobs without tips). Fancy
## cups make rare-or-better pets' tips count more.
func job_tips(job_id: String) -> float:
	var job := catalog.job(job_id)
	var size := job_size(job_id)
	if not job.has("tips") or size == 0:
		return 1.0
	if not _job_tip.has(job_id):
		var rare_x := maxf(1.0, Jobs.tool_sum(catalog, job_id, "rare_x", errand_tools))
		var tip := func(rarity: String) -> float:
			return float(job.tips.get(rarity, 1.0)) * (rare_x if catalog.rank(rarity) >= 2 else 1.0)
		var sum := 0.0
		for uid in job_crew(job_id):
			var pet := collection.get_pet(uid)
			sum += tip.call(pet.rarity if pet else "common")
		var h := job_herd(job_id)
		for k in h:
			sum += tip.call(Herd.rarity_of(k)) * int(h[k])
		_job_tip[job_id] = sum / size
	return _job_tip[job_id]


## Coins a minute from every coin-bringing errand with its crew now, on average.
func errands_per_minute() -> float:
	var total := 0.0
	for job in open_jobs():
		var p: Dictionary = job.get("pay", {})
		if p.has("capsules") or p.has("coins"):
			total += job_rate(job.id) * 60.0 * Jobs.average_fill(job, job_boost(job.id))
	return total * boost("coins")


## The coins a minute if a tool had `n` more levels (the upgrades card's "before → after").
func errands_per_minute_with(id: String, n: int) -> float:
	var real := errand_tools
	errand_tools = real.duplicate()
	errand_tools[id] = errand_tool_level(id) + n
	_tools_changed()
	var out := errands_per_minute()
	errand_tools = real
	_tools_changed()
	return out


## How often a job would fill if a tool had `n` more levels (the upgrades card, for jobs that
## bring no coins).
func job_rate_with(job_id: String, id: String, n: int) -> float:
	var real := errand_tools
	errand_tools = real.duplicate()
	errand_tools[id] = errand_tool_level(id) + n
	_tools_changed()
	var out := job_rate(job_id)
	errand_tools = real
	_tools_changed()
	return out


## Sets a tool's level outright (the dev driver's "tool" step).
func set_errand_tool_level(id: String, level: int) -> void:
	errand_tools[id] = maxi(0, level)
	_tools_changed()
	check_unlocks()
	jobs_changed.emit()
	changed.emit()


## The tools changed: what they do to each job is worked out again.
func _tools_changed() -> void:
	_job_tools.clear()
	_job_tip.clear()
	_kitchen_changed()


## Hours errands work at full speed while you're away (comfy naps add more).
func errands_away_hours() -> float:
	return float(catalog.errands.offline_full_hours) + Jobs.tool_sum(catalog, "", "away_hours", errand_tools)


## A job's level: all its tools' levels added up.
func job_level(job_id: String) -> int:
	return Jobs.level(catalog.job(job_id), errand_tools)


func errand_tool_level(id: String) -> int:
	return int(errand_tools.get(id, 0))


## Why a tool can't take another level now ("" if it can, coins aside), see Jobs.tool_block.
func errand_tool_block(id: String) -> String:
	var tool := Jobs.tool(catalog, id)
	if tool.is_empty():
		return "closed"
	var job_open: bool = tool.job == "" or open_jobs().any(func(j): return j.id == tool.job)
	return Jobs.tool_block(catalog, tool, errand_tools, machine, job_open)


## How many levels of a tool `n` buys right now (n -1: as many as you can afford, at least 1)
## and what they cost: [levels, coins].
func errand_tool_plan(id: String, n: int) -> Array:
	var tool := Jobs.tool(catalog, id)
	var have := errand_tool_level(id)
	var levels_left := Jobs.tool_room(tool, have)
	var value := capsule_value()
	if n < 0:
		var base := Jobs.tool_base(tool, value)
		var k := 0
		var cost := 0.0
		while k < mini(levels_left, 1000):
			cost += base * pow(float(tool.get("grow", 1.0)), have + k)
			if cost > coins:
				break
			k += 1
		n = maxi(1, k)
	n = mini(n, levels_left)
	return [n, Jobs.tool_cost(tool, have, n, value)]


## Buys `n` levels of an errand tool (-1: as many as you can afford). Returns the levels bought.
func buy_errand_tool(id: String, n := 1) -> int:
	if Jobs.tool(catalog, id).is_empty() or errand_tool_block(id) != "":
		return 0
	var plan := errand_tool_plan(id, n)
	if plan[0] <= 0 or coins < plan[1]:
		return 0
	coins -= plan[1]
	errand_tools[id] = errand_tool_level(id) + plan[0]
	_tools_changed()
	check_unlocks()  # a job's level may open something (the lemonade stand)
	jobs_changed.emit()
	changed.emit()
	save_game()
	return plan[0]


## Puts resting pets on an errand: these uids (a stand-in's uid means one from its count), or the
## `count` best at it (-1: everyone resting), cards and pets from the herd alike.
func put_on_job(job_id: String, count := 1, uids: Array = []) -> void:
	if not open_jobs().any(func(j): return j.id == job_id) or not feature_on("errands"):
		return
	var cards: Array = []
	var counts := {}
	var named := ""  # the exact pet you tapped, for your pet to name
	if not uids.is_empty():
		var ok := {}
		for pet in resting_cards():
			ok[pet.uid] = true
		var free := resting_herd().duplicate()
		for raw in uids:
			var uid := str(raw)
			if Herd.is_stand_in(uid):
				var k := Herd.key_of(uid)
				if int(free.get(k, 0)) > 0:
					Herd.take(free, k, 1)
					Herd.put(counts, k, 1)
					named = uid
			elif ok.has(uid):
				ok.erase(uid)
				cards.append(uid)
				named = uid
	else:
		var job := catalog.job(job_id)
		var picked := _pick(resting_cards(), resting_herd(), count, func(p: Pet): return _pet_speed(p, job), true)
		cards = picked[0]
		counts = picked[1]
	if cards.is_empty() and counts.is_empty():
		return
	var state := _job_state(job_id)
	state.crew.append_array(cards)
	for k in counts:
		Herd.put(state.herd, k, int(counts[k]))
	last_moved = _moved_name(named, cards, counts)
	_crews_changed()


## Sends pets on an errand home to rest: these uids (a stand-in's uid: one from its count), or the
## `count` slowest at it (-1: all). Returns how many went home.
func take_off_job(job_id: String, count := 1, uids: Array = []) -> int:
	if job_size(job_id) == 0:
		return 0
	var state := _job_state(job_id)
	var cards: Array = []
	var counts := {}
	var named := ""  # the exact pet you tapped, for your pet to name
	if not uids.is_empty():
		var crew := {}
		for uid in state.crew:
			crew[uid] = true
		var h: Dictionary = state.herd.duplicate()
		for raw in uids:
			var uid := str(raw)
			if Herd.is_stand_in(uid):
				var k := Herd.key_of(uid)
				if int(h.get(k, 0)) > 0:
					Herd.take(h, k, 1)
					Herd.put(counts, k, 1)
					named = uid
			elif crew.has(uid):
				crew.erase(uid)
				cards.append(uid)
				named = uid
	else:
		var job := catalog.job(job_id)
		var crew_pets: Array = []
		for uid in state.crew:
			var pet := collection.get_pet(uid)
			if pet:
				crew_pets.append(pet)
		var picked := _pick(crew_pets, state.herd, count, func(p: Pet): return _pet_speed(p, job), false)
		cards = picked[0]
		counts = picked[1]
	var n := cards.size()
	for k in counts:
		Herd.take(state.herd, k, int(counts[k]))
		n += int(counts[k])
	if n == 0:
		return 0
	last_moved = _moved_name(named, cards, counts)
	if cards.is_empty() or _take_off(cards).is_empty():
		_crews_changed()
	return n


## Who your pet names after a move: the pet you tapped, else the last card, else a face for the count.
func _moved_name(named: String, cards: Array, counts: Dictionary) -> String:
	if named != "":
		return named
	if not cards.is_empty():
		return str(cards[-1])
	return collection.stand_in_uids(str(counts.keys()[-1]), 1)[0]


## Spreads every resting pet over the errands: the smallest crews fill up first.
func share_out() -> void:
	_auto_place(resting_cards().map(func(p): return p.uid), resting_herd().duplicate())


## "New pets join here" on an errand: new pets (from boxes, gifts, pets home from adventures) start
## on it (see _place_new).
func set_job_join(job_id: String, on: bool) -> void:
	if not open_jobs().any(func(j): return j.id == job_id and Jobs.shared_out(j)):  # you staff the kitchen and scouting
		return
	_job_state(job_id).join = on
	jobs_changed.emit()
	changed.emit()
	save_game()


func job_joins(job_id: String) -> bool:
	return bool(jobs.get(job_id, {}).get("join", false))


## "New pets join here" on a job's machines (tables): new pets start there while it has empty
## spots, the best workers first. Never adventures (parties keep their slots and "fill up").
func set_worker_join(id: String, on: bool) -> void:
	if id == "adventures" or not knows_others(id):
		return
	var wj: Dictionary = automation.get("wjoin", {})
	if on:
		wj[id] = true
	else:
		wj.erase(id)
	automation.wjoin = wj
	automation_changed.emit()
	changed.emit()
	save_game()


func worker_joins(id: String) -> bool:
	return automation.get("wjoin", {}).has(id)


## Whether any job has "new pets join here" on.
func any_join() -> bool:
	for job in open_jobs():
		if job_joins(job.id):
			return true
	for j in worker_jobs():
		if worker_joins(j.id):
			return true
	return false


## New pets (resting ones; a stand-in's uid is one from its count) go where "new pets join here" is
## on: machines and tables with empty spots first (the best workers first), then the rest over the
## errands that have it, the smallest crews first. Nothing on: they rest. Pets the sorting rule
## sent to work (_to_work) that are still resting then go over every open errand.
func _place_new(uids: Array) -> void:
	var forced: Array = []
	if not _to_work.is_empty():
		forced = uids.filter(func(uid): return _to_work.has(str(uid)))
		_to_work.clear()
	if uids.is_empty() or tutorial_active() or not (forced.size() > 0 or any_join()):
		return
	var resting := {}
	for pet in resting_cards():
		resting[pet.uid] = true
	var cards: Array = []
	var counts := {}
	var free := resting_herd()
	for raw in uids:
		var uid := str(raw)
		if Herd.is_stand_in(uid):
			var k := Herd.key_of(uid)
			if int(counts.get(k, 0)) < int(free.get(k, 0)):
				Herd.put(counts, k, 1)
		elif resting.has(uid):
			resting.erase(uid)
			cards.append(uid)
	# machines and tables first, while they have room
	for j in worker_jobs():
		var id := str(j.id)
		if id == "adventures" or not worker_joins(id) or (cards.is_empty() and counts.is_empty()):
			continue
		var space := Automation.spots(automation, id) - workers_count(id)
		if space <= 0:
			continue
		var pets: Array = []
		for uid in cards:
			var pet := collection.get_pet(uid)
			if pet:
				pets.append(pet)
		var picked := _pick(pets, counts, space, func(p: Pet): return Automation.worker_speed(catalog, p), true)
		if picked[0].is_empty() and picked[1].is_empty():
			continue
		for uid in picked[0]:
			cards.erase(uid)
		for k in picked[1]:
			Herd.take(counts, k, int(picked[1][k]))
		_add_workers(id, picked[0], picked[1])
	if cards.is_empty() and counts.is_empty():
		return
	var joined: Array = open_jobs().filter(func(j): return job_joins(j.id)).map(func(j): return j.id)
	if not joined.is_empty():
		_auto_place(cards, counts, joined)
	# the rule's "go to work" pets nobody took: every open errand
	var left: Array = []
	var still := {}
	for pet in resting_cards():
		still[pet.uid] = true
	for uid in forced:
		if still.has(str(uid)):
			left.append(str(uid))
	if not left.is_empty():
		_auto_place(left)


## Puts these pets (the resting ones; a stand-in's uid is one from its count) and `counts` more from
## the resting herd on the errands with the smallest crews (only the errands in `only`, if given).
func _auto_place(uids: Array, counts := {}, only: Array = []) -> void:
	var open := open_jobs().filter(func(j): return Jobs.shared_out(j))  # not the kitchen or scouting: you staff those
	if not only.is_empty():
		open = open.filter(func(j): return j.id in only)
	if not feature_on("errands") or tutorial_active() or open.is_empty():
		return
	var resting := {}
	for pet in resting_cards():
		resting[pet.uid] = true
	var free := resting_herd()
	var sizes := {}
	for job in open:
		sizes[job.id] = job_size(job.id)
	var more := counts.duplicate()
	var placed := false
	for raw in uids:
		var uid := str(raw)
		if Herd.is_stand_in(uid):
			Herd.put(more, Herd.key_of(uid), 1)
			continue
		if not resting.has(uid):
			continue
		resting.erase(uid)
		var smallest: String = sizes.keys()[0]
		for id in sizes:
			if int(sizes[id]) < int(sizes[smallest]):
				smallest = id
		_job_state(smallest).crew.append(uid)
		sizes[smallest] = int(sizes[smallest]) + 1
		placed = true
	for k in more:
		var adds := water_fill(sizes, mini(int(more[k]), int(free.get(k, 0))))
		for id in adds:
			if int(adds[id]) > 0:
				Herd.put(_job_state(id).herd, k, int(adds[id]))
				sizes[id] = int(sizes[id]) + int(adds[id])
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


## Takes `n` pets of one count off wherever they work (errands first, then machines and tables), for
## an adventure that needs more of them than are resting.
func _herd_off_places(k: String, n: int) -> void:
	var crews := false
	for job_id in jobs:
		var h: Dictionary = _job_state(job_id).herd
		var take := mini(n, int(h.get(k, 0)))
		if take > 0:
			Herd.take(h, k, take)
			n -= take
			crews = true
	var workers := false
	var wh: Dictionary = automation.get("wherd", {})
	for id in wh:
		var take := mini(n, int(wh[id].get(k, 0)))
		if take > 0:
			Herd.take(wh[id], k, take)
			n -= take
			workers = true
	if crews:
		_crews_changed()
	if workers:
		_workers_changed()


func _speed_of(uid: String, job: Dictionary) -> float:
	return _pet_speed(collection.get_pet(uid), job)


## How fast a pet works an errand: its own speed times its own errand knacks (1.0 for nobody).
func _pet_speed(pet: Pet, job: Dictionary) -> float:
	return Jobs.pet_speed(pet, job) * knack_own(pet, "errands") if pet else 1.0


## A crew changed: the lookups are worked out again, and the tab redraws.
func _crews_changed() -> void:
	_rest_changed()
	_job_of.clear()
	for job_id in jobs:
		for uid in jobs[job_id].crew:
			_job_of[uid] = job_id
	_job_speed.clear()
	_job_tip.clear()
	_job_tools.clear()
	_kitchen_changed()  # the kitchen's bonus depends on the crews
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
	for id in pet_box_order():
		if in_bag(id) > 0:
			return id
	if not (feature_on("shopping") and buying_on):
		return ""
	for box in shop_boxes():
		if pet_opens(box.id) and coins - box_price(box.id) >= coin_reserve():
			return box.id
	return ""


## The kinds of box your pet (and the box workers) may open, in the order they get to them.
func pet_box_order() -> Array:
	return stash_boxes().filter(func(b): return pet_opens(b.id)).map(func(b): return b.id)


## How many boxes wait on your pile, all kinds together.
func boxes_on_pile() -> int:
	var n := 0
	for box_id in bag:
		n += in_bag(box_id)
	return n


## Whether your pet may open a pack now: it's allowed to, there's one for it, and there's room.
func can_auto_open() -> bool:
	return packs_on and knows_job("boxes") and not tutorial_active() and room_left() > 0 and next_pet_box() != ""


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
	_pack_timer += delta * boost("automation")
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
## calls this when its little animation pops). Returns the best pet in it (the one its animation
## shows), or null. Every pet in it goes in the idle log; good pulls get pinned for you to see.
func auto_open_pack() -> Pet:
	if not can_auto_open():
		return null
	var box_id := next_pet_box()
	if in_bag(box_id) == 0 and not buy_boxes(box_id, 1):
		return null
	var pulled := open_boxes(box_id, 1, "", true)
	if pulled.is_empty():
		return null
	var good: Array = []
	for pet in pulled:
		if is_good_pull(pet) and collection.get_pet(pet.uid) == pet:  # not one the sorting rule sent off
			pinned.append(pet.uid)
			good.append(pet.display_name(catalog))
	_log_idle({ "packs": 1, "good": good })
	return BoxShop.best_first(pulled, catalog)[0]


## Rare or better, or a holo-or-better finish: worth showing you.
func is_good_pull(pet: Pet) -> bool:
	return catalog.rank(pet.rarity) >= 2 or catalog.finish_rank(pet.finish) >= 2


## You've seen a good pull: `uid` that one (if it's still pinned), or "" the oldest.
func dismiss_pinned(uid := "") -> void:
	var i := 0 if uid == "" else pinned.find(uid)
	if i >= 0 and i < pinned.size():
		pinned.remove_at(i)
		collection.refold()  # a good pull you've seen may fold into the herd now
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


# ---- automation: your pet does one job for you, see Automation and data/automation.json ----

const PET_CRANK_ROLLS := 200  # past this many pulls at once (back from being away) the rest pay like these


## The jobs in the automation tab: the ones that are there yet (their "needs" is open), in order.
func auto_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not tab_open("automation"):
		return out
	for j in catalog.automation.get("jobs", []):
		if str(j.get("needs", "")) == "" or is_open(str(j.needs)):
			out.append(j)
	return out


## Whether your pet has been taught a job (bought with coins).
func knows_job(id: String) -> bool:
	return Automation.taught(automation, id)


## Teaches your pet a job for its coins. If it wasn't doing anything, it starts right away.
## Returns whether it worked.
func teach_job(id: String) -> bool:
	var j := Automation.job(catalog, id)
	if j.is_empty() or knows_job(id) or not auto_jobs().any(func(x): return x.id == id) or coins < int(j.coins):
		return false
	coins -= int(j.coins)
	automation.taught[id] = true
	if automation.task == "":
		automation.task = id
	check_unlocks()
	automation_changed.emit()
	changed.emit()
	save_game()
	return true


## Puts your pet on a job it knows ("" takes it off). It only ever does one: the old one stops.
func set_task(id: String) -> void:
	if (id != "" and not knows_job(id)) or id == automation.task:
		return
	automation.task = id
	_pack_timer = 0.0
	automation_changed.emit()
	changed.emit()
	save_game()


## Why a tool can't take a level now ("max", "closed"), or "".
func auto_tool_block(id: String) -> String:
	return Automation.tool_block(automation, Automation.tool(catalog, id))


func auto_tool_cost(id: String) -> int:
	return Automation.tool_cost(automation, Automation.tool(catalog, id))


## Buys a level of a job's tool. Returns whether it worked.
func buy_auto_tool(id: String) -> bool:
	var cost := auto_tool_cost(id)
	if auto_tool_block(id) != "" or coins < cost:
		return false
	coins -= cost
	automation.tools[id] = Automation.tool_level(automation, id) + 1
	automation_changed.emit()
	changed.emit()
	save_game()
	return true


## Where a party of the adventures job goes and how many go: { place, n }. `slot` -1 is your pet's
## party, 0 and up the workers' parties. A place that isn't open (or none picked yet) is the first
## open one that takes a party.
func auto_party(slot := -1) -> Dictionary:
	var saved: Dictionary = automation.party if slot < 0 else (automation.parties[slot] if slot < automation.parties.size() else {})
	var place := str(saved.get("place", ""))
	if not location_open(catalog.location(place)):
		place = ""
		var open := open_locations()
		for l in open:
			if int(l.get("max_party", 0)) != 1:
				place = str(l.id)
				break
		if place == "" and not open.is_empty():
			place = str(open[0].id)
	var n := int(saved.get("n", 0))
	if n <= 0:
		n = int(Automation.job(catalog, "adventures").get("party", 3))
	return { "place": place, "n": clampi(n, 1, max_party(place) if place != "" else 1) }


## Changes where a party goes (the next time it sets out) and how many go.
func set_auto_party(place: String, n: int, slot := -1) -> void:
	var party := { "place": place, "n": clampi(n, 1, max_party(place)) }
	if slot < 0:
		automation.party = party
	elif slot < automation.parties.size():
		automation.parties[slot] = party
	automation_changed.emit()
	save_game()


## Places the adventures job can send its party, in the data's order.
func auto_places() -> Array[Dictionary]:
	return open_locations()


## A party the adventures job has out (`slot` -1: your pet's, 0 and up: the workers'), or null.
func auto_run(slot := -1) -> RunState:
	for run in runs:
		if run.auto and run.slot == slot:
			return run
	return null


## Your pet's jobs and its workers work up to `until` (called every second): machines crank, boxes
## get opened, parties come home and go out again. (Your pet's boxes job runs with the pack
## opening, see _open_in_background.)
func _work_automation(until: float) -> void:
	_hold_saves = true
	if _auto_at <= 0.0 or until <= _auto_at:
		_auto_at = maxf(_auto_at, until)
	else:
		var gap := until - _auto_at
		_auto_at = until
		if gap > 5.0:  # the computer slept: counts like time with the game closed (a hitch still counts)
			gap = maxf(Automation.away_seconds(catalog, automation, gap) * boost("away"), minf(gap, 60.0))
		_work_for_automation(gap, true)
	_auto_adventures()
	_release_saves()


## Saves once if anything asked to while automation held the saves.
func _release_saves() -> void:
	_hold_saves = false
	if _save_held:
		_save_held = false
		save_game()


## Everything automation does in `seconds` (also time spent away, when the game loads).
func _work_for_automation(seconds: float, show: bool) -> void:
	seconds *= boost("automation")  # quicker at the jobs, more done in the same time (your pet's and the workers')
	if automation.task == "machine":
		var pulls := Automation.crank(catalog, automation, seconds)
		if pulls > 0:
			_pet_cranks(pulls, show)
	var worker_pulls := Automation.work(catalog, automation, "machine", workers_speed("machine"), seconds)
	if worker_pulls > 0:
		_pet_cranks(worker_pulls, false)
	var worker_boxes := Automation.work(catalog, automation, "boxes", workers_speed("boxes"), seconds)
	if worker_boxes > 0:
		_workers_open(worker_boxes)
	if automation.task == Automation.WHISTLE:  # after what the time brought in: then it spends
		var checks := Automation.checks(catalog, automation, seconds)
		if checks > 0:
			_whistle_checks(checks)


## The adventures job: a party that's home is welcomed back quietly (what it found goes in the idle
## log), and while your pet is on the job, and for every worker leading a party, a new one sets out.
func _auto_adventures() -> void:
	for run in runs.duplicate():
		if run.auto and run.status == RunState.Status.DONE:
			var stayed: Array = run.party.lost.map(func(uid): return collection.get_pet(uid)).filter(func(p): return p != null) \
				.map(func(p): return p.display_name(catalog))
			var trip := collect_run(run)
			_log_idle({ "trips": 1, "coins": Rewards.total(trip.get("loot", {}), "coins") })
			if not stayed.is_empty():  # nobody goes missing without you hearing about it
				announcements.append("%s stayed at %s! it must be lovely there." % [", ".join(stayed), trip.get("place", "the trip")])
	if tutorial_active():
		return
	var leaders := workers_of("adventures")
	var due: Array[int] = []
	if automation.task == "adventures" and auto_run(-1) == null:
		due.append(-1)
	for slot in leaders.size():
		if str(leaders[slot]) != "" and auto_run(slot) == null:
			due.append(slot)
	if due.is_empty():
		return
	# who could go, worked out once: pets with nothing to do first, then ones on errands; workers
	# and good pulls you haven't seen yet stay home
	var unseen := {}
	for uid in pinned:
		unseen[uid] = true
	var pools: Array = [resting_cards(), _resting_stand_ins(), sendable_pets()]
	var used := {}
	for slot in due:
		if _send_auto_party(slot, pools, unseen, used):
			# fresh stand-ins for the next party: the ones that just left are away now
			pools = [pools[0], _resting_stand_ins(), pools[2], _sendable_stand_ins(away())]


## Sends party `slot` out (from `pools` of pets, skipping `unseen` and ones `used` already).
## Returns whether it left.
func _send_auto_party(slot: int, pools: Array, unseen: Dictionary, used: Dictionary) -> bool:
	var party := auto_party(slot)
	if str(party.place) == "":
		return false
	var party_pets: Array[Pet] = []
	for pool in pools:
		for pet: Pet in pool:
			if party_pets.size() >= int(party.n):
				break
			if not used.has(pet.uid) and not unseen.has(pet.uid) and not _worker_of.has(pet.uid):
				used[pet.uid] = true
				party_pets.append(pet)
	if party_pets.is_empty():
		return false
	var run := send_on_adventure(str(party.place), party_pets, false)
	if run == null:
		return false
	run.auto = true
	run.slot = slot
	run.chooser = "policy"  # nobody waits for you: every event takes its usual pick
	save_game()
	return true


# ---- workers: the other pets, once your pet has taught them a job ----

var _worker_of := {}  # uid -> job id, for every pet working as a worker
var _worker_speed := {}  # job id -> its workers' speeds added up (see Automation.worker_speed)


## The job a pet works at in automation, or "".
func worker_job(uid: String) -> String:
	return str(_worker_of.get(uid, ""))


## Whether a job has been taught to the other pets (it's on the workers page).
func knows_others(id: String) -> bool:
	return Automation.others(automation, id)


## Jobs taught to the other pets, in order (the workers page).
func worker_jobs() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for j in auto_jobs():
		if knows_others(j.id):
			out.append(j)
	return out


## Why "teach the others" can't be bought for a job ("" when it can, coins aside), see Automation.
func teach_others_block(id: String) -> String:
	return Automation.teach_block(catalog, automation, id)


func teach_others_cost(id: String) -> int:
	return int(Automation.job(catalog, id).get("teach", {}).get("coins", 0))


## Your pet teaches the other pets a job: the workers page opens (or gets the job). Returns whether
## it worked.
func teach_others(id: String) -> bool:
	if teach_others_block(id) != "" or coins < teach_others_cost(id):
		return false
	coins -= teach_others_cost(id)
	automation.others[id] = true
	automation_changed.emit()
	changed.emit()
	save_game()
	return true


## A job's workers (uids). Adventure parties keep their slot: an empty one is "".
func workers_of(id: String) -> Array:
	return automation.workers.get(id, [])


## A job's workers from the herd: count key -> how many (never adventures: a party's leader keeps its slot).
func workers_herd(id: String) -> Dictionary:
	return automation.get("wherd", {}).get(id, {})


## How many pets work at a job: cards and counts.
func workers_count(id: String) -> int:
	return workers_of(id).filter(func(uid): return str(uid) != "").size() + Herd.total(workers_herd(id))


## Up to `n` of a job's workers to show (uids): cards first, then stand-ins for its counts.
func worker_faces(id: String, n: int) -> Array:
	var cards: Array = workers_of(id).filter(func(uid): return str(uid) != "").slice(0, n)
	return _faces(cards, workers_herd(id), n, 20 + auto_jobs().map(func(j): return j.id).find(id))


## Machines, tables or parties for a job's workers: [how many a buy gets, coins]. `n` -1: as many as
## you can afford. Never more than are still out there (see spot_room).
func spot_plan(id: String, n := 1) -> Array:
	var spot: Dictionary = Automation.job(catalog, id).get("spot", {})
	var room := spot_room(id)
	if spot.is_empty() or room <= 0:
		return [0, 0]
	var have := Automation.spots(automation, id)
	if n < 0:
		n = maxi(1, Automation.affordable(catalog, automation, id, coins, room))
	n = mini(n, room)
	return [n, Jobs.tool_cost(spot, have, n)]


## Buys machines (tables, parties) for a job's workers. Returns how many it bought.
func buy_spots(id: String, n := 1) -> int:
	var plan := spot_plan(id, n)
	if not knows_others(id) or int(plan[0]) <= 0 or coins < int(plan[1]):
		return 0
	coins -= int(plan[1])
	_add_spots(id, int(plan[0]))
	automation_changed.emit()
	changed.emit()
	save_game()
	return int(plan[0])


## More spots for a job (paid for already). A new party goes to an open place that has none yet.
func _add_spots(id: String, n: int) -> void:
	automation.spots[id] = Automation.spots(automation, id) + n
	if id == "adventures":
		while automation.parties.size() < Automation.spots(automation, id):
			automation.parties.append({ "place": _free_party_place(), "n": 0 })


## An open place none of the workers' parties goes to yet (one that takes a party first), or "".
func _free_party_place() -> String:
	var taken := {}
	for slot in automation.parties.size():
		taken[str(auto_party(slot).place)] = true
	var spare := ""
	for l in open_locations():
		if taken.has(str(l.id)):
			continue
		if int(l.get("max_party", 0)) != 1:
			return str(l.id)
		if spare == "":
			spare = str(l.id)
	return spare


## The map pages that are open (their ids).
func open_pages() -> Array:
	return catalog.pages.filter(func(p): return page_open(str(p.id))).map(func(p): return str(p.id))


## How many machines (tables, parties) there are for a job in the places you've taken.
func spot_exist(id: String) -> int:
	return Automation.exist(catalog, id, open_pages(), open_locations().size())


## How many are still out there to haul home: what a buy can get at most.
func spot_room(id: String) -> int:
	return Automation.out_there(catalog, automation, id, open_pages(), open_locations().size())


## Every worker, all jobs added up.
func workers_total() -> int:
	var n := _worker_of.size()
	for id in automation.get("wherd", {}):
		n += Herd.total(workers_herd(str(id)))
	return n


## Puts resting pets on a job's empty machines (tables, parties), the best workers first: `count`
## of them, -1 as many as there's room for. Pets from the herd lead parties as stand-ins. Returns
## how many started.
func put_workers(id: String, count := 1) -> int:
	var free_spots := Automation.spots(automation, id) - workers_count(id)
	if not knows_others(id) or free_spots <= 0:
		return 0
	var picked := _pick(resting_cards(), resting_herd(), mini(free_spots, count) if count >= 0 else free_spots,
		func(p: Pet): return Automation.worker_speed(catalog, p), true)
	return _add_workers(id, picked[0], picked[1])


## Puts these resting cards (uids) and pets from the resting herd (`counts`) on a job's machines.
## Returns how many started. `quiet`: no _workers_changed (the caller does it once, e.g. the whistle).
func _add_workers(id: String, cards: Array, counts: Dictionary, quiet := false) -> int:
	cards = cards.duplicate()
	if id == "adventures":  # every party keeps its own slot: a pet from the herd leads it as a stand-in
		var skip := _stand_ins_out()
		for k in counts:
			for uid in collection.stand_in_uids(k, int(counts[k]), skip):
				cards.append(uid)
				skip[uid] = true
		counts = {}
	var n := cards.size() + Herd.total(counts)
	if n == 0:
		return 0
	var list: Array = workers_of(id).duplicate()
	for uid in cards:  # empty party slots get a leader first
		var hole := list.find("")
		if hole >= 0:
			list[hole] = uid
		else:
			list.append(uid)
	automation.workers[id] = list
	if not counts.is_empty():
		var wh: Dictionary = automation.get("wherd", {})
		if not wh.has(id):
			wh[id] = {}
		for k in counts:
			Herd.put(wh[id], k, int(counts[k]))
		automation.wherd = wh
	if not quiet:
		_workers_changed()
	return n


## Sends a job's workers home to rest: `count` of the slowest, -1 all. Returns how many.
func take_off_workers(id: String, count := 1) -> int:
	var list: Array = workers_of(id).filter(func(uid): return str(uid) != "")
	var wh := workers_herd(id)
	if list.is_empty() and wh.is_empty():
		return 0
	if id == "adventures":
		var going := list.slice(list.size() - (list.size() if count < 0 else mini(count, list.size())))  # the last parties stop
		_take_off_workers(going)
		collection.refold()  # a leader that stopped may fold into the herd now
		return going.size()
	var pets: Array = []
	for uid in list:
		var pet := collection.get_pet(str(uid))
		if pet:
			pets.append(pet)
	var picked := _pick(pets, wh, count, func(p: Pet): return Automation.worker_speed(catalog, p), false)
	var n: int = picked[0].size()
	for k in picked[1]:
		Herd.take(wh, k, int(picked[1][k]))
		n += int(picked[1][k])
	if picked[0].is_empty():
		_workers_changed()
	else:
		_take_off_workers(picked[0])
	return n


## Takes these pets off whatever machine, table or party they work at.
func _take_off_workers(uids: Array) -> void:
	var gone := {}
	for uid in uids:
		if _worker_of.has(uid):
			gone[uid] = true
	if gone.is_empty():
		return
	for id in automation.workers:
		if id == "adventures":  # a party keeps its place: its slot just waits for a new leader
			automation.workers[id] = automation.workers[id].map(func(uid): return "" if gone.has(uid) else uid)
		else:
			automation.workers[id] = automation.workers[id].filter(func(uid): return not gone.has(uid))
	_workers_changed()


func _workers_changed() -> void:
	_rest_changed()
	_worker_of.clear()
	_worker_speed.clear()
	for id in automation.workers:
		for uid in automation.workers[id]:
			if str(uid) != "":
				_worker_of[uid] = id
	automation_changed.emit()
	jobs_changed.emit()
	changed.emit()
	save_game()


## A job's workers' speeds added up (how many of your pet they're worth).
func workers_speed(id: String) -> float:
	if not _worker_speed.has(id):
		var sum := 0.0
		for uid in workers_of(id):
			var pet := collection.get_pet(str(uid)) if str(uid) != "" else null
			if pet:
				sum += Automation.worker_speed(catalog, pet) * knack_own(pet, "automation")
		var wh := workers_herd(id)
		for k in wh:
			sum += Automation.worker_speed(catalog, Herd.template(catalog, k)) * int(wh[k])
		_worker_speed[id] = sum
	return float(_worker_speed[id])


# ---- the whistle: your pet manages the workers (Automation.whistle_plan) ----

var whistle_since := { "hauled": {}, "put": 0 }  # what the whistle did since you last looked (not saved)


## The whistle checks on everyone `checks` times: hauls spots home (coins, never under set aside)
## and puts resting pets on the empty ones. Quiet: it all happens at once, one save at the end.
func _whistle_checks(checks: int) -> void:
	var jobs: Array = worker_jobs().map(func(j): return str(j.id))
	var rooms := {}
	for id in jobs:
		rooms[id] = spot_room(id)
	var out := 0  # the workers' parties that are out: their pets aren't resting
	var leaders := workers_of("adventures")
	for slot in leaders.size():
		if str(leaders[slot]) != "" and auto_run(slot) != null:
			out += 1
	var plan := Automation.whistle_plan(catalog, automation, jobs, coins, rooms, resting_count(), checks, out)
	if plan.buys.is_empty() and plan.fill.is_empty():
		return
	coins -= int(plan.spent)
	for id in plan.buys:
		_add_spots(id, int(plan.buys[id]))
		whistle_since.hauled[id] = int(whistle_since.hauled.get(id, 0)) + int(plan.buys[id])
	var at := 0
	if not plan.fill.is_empty():  # the best workers first, cards and pets from the herd alike
		var cards: Array = resting_cards().duplicate()
		var counts: Dictionary = resting_herd().duplicate()
		for id in plan.fill:
			var picked := _pick(cards, counts, int(plan.fill[id]), func(p: Pet): return Automation.worker_speed(catalog, p), true)
			var taken := {}
			for uid in picked[0]:
				taken[uid] = true
			cards = cards.filter(func(p): return not taken.has(p.uid))
			for k in picked[1]:
				Herd.take(counts, k, int(picked[1][k]))
			var n := _add_workers(id, picked[0], picked[1], true)
			at += n
			whistle_since.put = int(whistle_since.put) + n
	if at > 0:
		_workers_changed()
	else:
		automation_changed.emit()
		changed.emit()
		save_game()


## You looked at the whistle's list: "since you looked" starts again.
func whistle_seen() -> void:
	whistle_since = { "hauled": {}, "put": 0 }


## Turns a tick on the whistle's list on or off (`key` "haul" or "fill").
func set_whistle_tick(id: String, key: String, on: bool) -> void:
	var ticks: Dictionary = automation.whistle.ticks
	var t: Dictionary = ticks.get(id, {})
	t[key] = on
	ticks[id] = t
	automation_changed.emit()
	save_game()


## Set aside one step up (1) or down (-1).
func step_whistle_keep(d: int) -> void:
	automation.whistle.keep = Automation.keep_step(catalog, automation, d)
	automation_changed.emit()
	save_game()


## Box workers open `count` boxes from your pile (the kinds your pet may open; they never buy any).
## It counts boxes, not pets: a sunset box is one box however many pets are in it. At most
## WORKER_BOXES_MAX at once (a long time away can't stall the load; the rest wait on the pile).
func _workers_open(count: int) -> void:
	if room_left() <= 0 and boxes_on_pile() > 0:
		_room_hit()
	count = mini(count, room_left())  # a full room: the boxes wait on the pile
	var opened := 0
	var good: Array = []
	var split := BoxShop.split_open(bag, pet_box_order(), mini(count, WORKER_BOXES_MAX))
	for box_id in split:
		var pulled := open_boxes(box_id, int(split[box_id]), "", true)
		if not pulled.is_empty():
			opened += int(split[box_id])
		for pet in pulled:
			if is_good_pull(pet) and not _sent_home.has(pet.uid):  # not one the sorting rule sent off
				if collection.get_pet(pet.uid) != null:  # a big batch may have folded it into the herd already
					pinned.append(pet.uid)
				good.append(pet.display_name(catalog))
	if opened > 0:
		_log_idle({ "packs": opened, "good": good })


## Your pet's machine gives `pulls` capsules. `show`: the tab plays the last one (not when it's
## catching up on time away). Returns everything they held.
func _pet_cranks(pulls: int, show := true) -> Dictionary:
	var total := {}
	var rolls := mini(pulls, PET_CRANK_ROLLS)
	var last := {}
	for i in rolls:
		last = _pet_capsule()
		Rewards.add(total, last.loot)
	if pulls > rolls:  # the rest pay coins, xp and boxes like these (toys only come from the rolled ones)
		for key: String in total.keys():
			if key == "coins" or key == "xp" or key.begins_with("box:"):
				total[key] = int(total[key]) + roundi(int(total[key]) * float(pulls - rolls) / rolls)
	# everything is handed out at once: workers can pull hundreds of capsules a second
	if total.has("xp"):
		total.xp = add_xp(int(total.xp))
	grant(_without(total, "xp"), false)
	_log_idle({ "coins": int(total.get("coins", 0)), "boxes": Rewards.total(total, "box") })
	if show and not last.is_empty():
		pet_cranked.emit(last)
	return total


## One capsule from your pet's own machine (or a worker's): like a plain one from yours (worth the
## same, shiny as often, toys too), but no lucky lights, fever or pet boxes: those stay with your
## lever. Toys are yours right away; the rest is handed out by _pet_cranks.
func _pet_capsule() -> Dictionary:
	var luck := boost("luck")
	var prize := Machine.roll(machine, catalog, _rng, false, luck, boost("toys"))
	if not _machine_gives(str(prize.kind)) or prize.kind in ["pet", "pet_box"]:
		prize = _machine_prize("coins")
	var shiny: bool = prize.kind in ["coins", "golden", "box", "part"] and _rng.randf() < Machine.shiny_chance(machine, catalog) * boost("shiny")
	var loot := Machine.loot(prize, machine, catalog, _rng)
	if loot.has("coins"):
		loot.coins = roundi(int(loot.coins) * boost("coins"))
	if shiny:
		for k in loot:
			loot[k] = roundi(int(loot[k]) * Machine.shiny_pay(machine, catalog))
	var toy := {}
	if prize.kind == "toy":
		var t := Toys.roll(catalog, _rng, luck)
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(toys, t.id, t.finish) }
		toys_changed.emit()
		check_unlocks()
	return { "prize": prize, "loot": loot, "shiny": shiny, "toy": toy }  # _pet_cranks hands it out


func _load_automation(saved: Dictionary) -> void:
	automation = Automation.fresh()
	for id in saved.get("taught", {}):
		if not Automation.job(catalog, str(id)).is_empty():
			automation.taught[str(id)] = true
	for id in saved.get("tools", {}):
		if not Automation.tool(catalog, str(id)).is_empty():
			automation.tools[str(id)] = maxi(0, int(saved.tools[id]))
	var task := str(saved.get("task", ""))  # set once the whistle is known too (below)
	var party: Dictionary = saved.get("party", {})
	automation.party = { "place": str(party.get("place", "")), "n": int(party.get("n", 0)) }
	automation.fill = clampf(float(saved.get("fill", 0.0)), 0.0, 1.0)
	for id in saved.get("others", {}):
		if automation.taught.has(str(id)):
			automation.others[str(id)] = true
	for id in saved.get("spots", {}):
		if not Automation.job(catalog, str(id)).is_empty():
			automation.spots[str(id)] = maxi(0, int(saved.spots[id]))
	for p in saved.get("parties", []):
		if p is Dictionary and automation.parties.size() < Automation.spots(automation, "adventures"):
			automation.parties.append({ "place": str(p.get("place", "")), "n": int(p.get("n", 0)) })
	while automation.parties.size() < Automation.spots(automation, "adventures"):
		automation.parties.append({ "place": "", "n": 0 })
	# workers: pets you still have, not your active pet, not away, one job each, one per spot
	var on_trips := away()
	var placed := {}
	for id in saved.get("workers", {}):
		var list: Array = []
		for raw in saved.workers[id]:
			var uid := str(raw)
			if list.size() >= Automation.spots(automation, str(id)):
				break
			if collection.get_pet(uid) != null and uid != collection.active_uid and not on_trips.has(uid) and not placed.has(uid) and not _job_of.has(uid):
				list.append(uid)
				placed[uid] = true
			elif str(id) == "adventures":
				list.append("")  # that party waits for a new leader
		automation.workers[str(id)] = list
	for id in saved.get("wfill", {}):
		automation.wfill[str(id)] = clampf(float(saved.wfill[id]), 0.0, 1.0)
	# the whistle (v27: older saves start with every tick on and the default set aside)
	var w: Dictionary = saved.get("whistle", {})
	var ticks := {}
	var saved_ticks: Dictionary = w.get("ticks", {})
	for id in saved_ticks:
		if saved_ticks[id] is Dictionary and not Automation.job(catalog, str(id)).is_empty():
			var t := {}
			for key in ["haul", "fill"]:
				if saved_ticks[id].has(key):
					t[key] = bool(saved_ticks[id][key])
			ticks[str(id)] = t
	automation.whistle = { "ticks": ticks, "keep": maxi(-1, int(w.get("keep", -1))), "wait": clampf(float(w.get("wait", 0.0)), 0.0, 1.0) }
	if is_unlocked("feature:" + Automation.WHISTLE):
		automation.taught[Automation.WHISTLE] = true
	automation.task = task if automation.taught.has(task) else ""
	var saved_wjoin = saved.get("wjoin", {})
	if saved_wjoin is Dictionary:
		for id in saved_wjoin:
			if str(id) != "adventures" and automation.others.has(str(id)) and bool(saved_wjoin[id]):
				automation.wjoin[str(id)] = true
	# workers from the herd: counts, as many as the spots still have room for (never adventures)
	var saved_wherd = saved.get("wherd", {})
	if not saved_wherd is Dictionary:
		saved_wherd = {}
	for id in saved_wherd:
		if str(id) == "adventures" or Automation.job(catalog, str(id)).is_empty():
			continue
		var space: int = Automation.spots(automation, str(id)) - automation.workers.get(str(id), []).size()
		var counts := Herd.clean_counts(catalog, saved_wherd[id])
		for k in counts.keys():
			counts[k] = mini(int(counts[k]), maxi(0, space))
			space -= int(counts[k])
			if int(counts[k]) <= 0:
				counts.erase(k)
		if not counts.is_empty():
			automation.wherd[str(id)] = counts
	_worker_of.clear()
	_worker_speed.clear()
	for id in automation.workers:
		for uid in automation.workers[id]:
			if str(uid) != "":
				_worker_of[uid] = id


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
	bag = {}
	tutorial = catalog.tutorial.steps[0].id
	collection.auto_active = true  # your first pet (out of the machine) is your active pet
	started_at = Time.get_unix_time_from_system()
	milestones = {}


## Moves the tutorial on once its step is done: your first pet out of the machine, then (after a
## while of building the machine up) a second one with a map, and it's sent on an adventure.
func _check_tutorial() -> void:
	var before := tutorial
	for i in 4:
		match tutorial:
			"pull":
				if collection.count() >= 1:
					tutorial = "machine"
					_milestone("first pet")
			"machine":
				if collection.count() >= 2:
					tutorial = "send"
					_milestone("adventures")
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
	_knack_gates_changed()
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

## uid -> true for every pet that's out on a trip (including trips back but not welcomed yet, and
## pets that stayed there: they leave when the trip is welcomed back).
func away() -> Dictionary:
	var out := {}
	for run in runs:
		for uid in run.party.uids:
			out[uid] = true
		for uid in run.party.lost:
			out[uid] = true
	return out


## Pets that can be sent: not your active pet, and not already away. Pets on errands can: going
## on an adventure takes them off their errand. From each count in the herd, up to
## data/herd.json "stand_ins" stand-ins (they come home into the count, or leave it).
func sendable_pets() -> Array[Pet]:
	var gone := away()
	var out: Array[Pet] = []
	for pet in collection.pets:
		if pet.uid != collection.active_uid and not gone.has(pet.uid):
			out.append(pet)
	out.append_array(_sendable_stand_ins(gone))
	return out


## Up to data/herd.json "stand_ins" stand-ins from each count, leaving out ones away or leading.
func _sendable_stand_ins(gone: Dictionary) -> Array[Pet]:
	var out: Array[Pet] = []
	var skip := _stand_ins_out(gone)
	var out_of := {}  # count key -> stand-ins already away or leading
	for uid: String in skip:
		Herd.put(out_of, Herd.key_of(uid), 1)
	var per := int(catalog.herd.get("stand_ins", 10))
	for k in collection.herd:
		var free := collection.herd_count(k) - int(out_of.get(k, 0))
		if free > 0:
			for uid in collection.stand_in_uids(k, mini(per, free), skip):
				out.append(collection.get_pet(uid))
	return out


## `by_you`: you sent it (not your pet's or the workers' auto parties): it may take a scout note.
func send_on_adventure(location_id: String, pets: Array[Pet], by_you := true) -> RunState:
	var location := catalog.location(location_id)
	var gone := away()
	var going: Array[Pet] = []
	var picked := {}
	var herd_left := {}  # count key -> stand-ins of it that may still go
	var leading := {}
	if pets.any(func(p): return p != null and Herd.is_stand_in(p.uid)):
		leading = _stand_ins_out(gone)
		for uid: String in leading:
			Herd.put(herd_left, Herd.key_of(uid), -1)
	for pet in pets:  # the sendable ones (see sendable_pets), checked one by one: parties go out hundreds at a time
		if pet == null or picked.has(pet.uid) or pet.uid == collection.active_uid or gone.has(pet.uid):
			continue
		if Herd.is_stand_in(pet.uid):
			var k := Herd.key_of(pet.uid)
			if leading.has(pet.uid) or collection.herd_count(k) + int(herd_left.get(k, 0)) <= 0:
				continue
			Herd.put(herd_left, k, -1)
		elif collection.get_pet(pet.uid) != pet:
			continue
		picked[pet.uid] = true
		going.append(pet)
	if not location_open(location) or going.is_empty() or going.size() > max_party(location_id):
		return null
	# stand-ins: resting ones first; past those they come off errands (then machines and tables)
	var need := {}
	for pet in going:
		if Herd.is_stand_in(pet.uid):
			Herd.put(need, Herd.key_of(pet.uid), 1)
	var free := resting_herd()
	for k in need:
		if int(need[k]) > int(free.get(k, 0)):
			_herd_off_places(k, int(need[k]) - int(free.get(k, 0)))
	# every trip packs the gear you have when it sets off (yours, your pet's and the workers' parties;
	# never dungeons, see Gear.for_trip)
	var run := AdventureRunner.start(location_id, going, Time.get_unix_time_from_system(), _rng.randi(), catalog, finds, machine.bought,
		Gear.for_trip(catalog, gear, location), trip_knacks(going), workers_total())
	# auto parties (your pet's, the workers') never take a note: skip the looking around for them
	if by_you and scout_notes > 0 and Jobs.takes_note(catalog, location, by_you, scout_notes,
			Intel.left_to_find(location, _place_known, not Rumours.hearable(catalog, heard, is_open).is_empty(), catalog)):
		scout_notes -= 1
		run.scout = Jobs.scout_note(catalog)
		jobs_changed.emit()
	runs.append(run)
	_rest_changed()
	_take_off(going.map(func(p): return p.uid))
	_take_off_workers(going.map(func(p): return p.uid))
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
	_rest_changed()
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
	_boost_trip_loot(run.loot, run.gear, run.knacks)
	grant(run.loot, false)
	collection.remove(run.party.lost)
	_clamp_herd_places()
	# the pets that came home go where new pets join (nothing on: they rest)
	_place_new(photo.filter(func(p): return p.home).map(func(p): return p.pet.uid))
	collection.refold()  # pets home again may fold into the herd
	var found := _spot_places(run)
	# experience: from the trip itself, and a lot for discovering things
	var gained := add_xp(run.xp + XP_SPOTTED * found.size() + XP_FIND * new_finds.size())
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
const TREAT_SPEED := 3.0  # how many times as fast they walk while they zoom
const TRAIL_COINS := [0.2, 0.5]  # a coin pickup is worth this times the place's loot (garden: about 1)


## You tossed a treat on the trail: the pets chase it and walk TREAT_SPEED times as fast for
## treat_zoom() seconds. Then the next treat takes treat_every() seconds. Returns whether it worked.
func toss_treat(run: RunState) -> bool:
	if not run in runs or run.status == RunState.Status.DONE or treat_ready_in(run) > 0.0:
		return false
	var now := Time.get_unix_time_from_system()
	_treats[run] = { "zoom_until": now + treat_zoom(run), "ready_at": now + treat_every(run) }
	return true


## Seconds before you can toss this trip the next treat (a treat pouch makes it quicker).
func treat_every(run: RunState) -> float:
	return Gear.value(catalog, run.gear, "treat_every")


## Seconds this trip's pets zoom along after a treat (a treat pouch makes it longer).
func treat_zoom(run: RunState) -> float:
	return Gear.value(catalog, run.gear, "treat_zoom") * run.knack("treats")


## The most a streak of grabs on the trail multiplies what you grab (sticky paws raise it).
func streak_max(run: RunState) -> float:
	return Gear.value(catalog, run.gear, "streak_max")


## How much more likely a part is on the trail (sharper eyes), once parts are open.
func trail_part_x(run: RunState) -> float:
	return Gear.value(catalog, run.gear, "part_x")


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
	var paws := (1.0 + Gear.value(catalog, run.gear, "pickups")) * run.knack("pickups")  # sticky paws (and knacks): worth more
	match kind:
		"coins":
			var amount := maxi(1, roundi(_rng.randf_range(TRAIL_COINS[0], TRAIL_COINS[1]) * float(location.loot) * bonus * paws))
			Rewards.add(run.loot, { "coins": amount })
			return { "coins": amount }
		"xp":
			var amount := add_xp(maxi(1, roundi(bonus)) if paws <= 1.0 else maxi(1, Rewards.count(bonus * paws, _rng)))
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
## into `items` until something uses it. Coins are boosted by the toys your pet is playing with,
## unless `boosted` is false (the loot was boosted already, to show the real amount).
func grant(loot: Dictionary, boosted := true) -> void:
	for key: String in loot:
		var amount := int(loot[key])
		var kind := key.get_slice(":", 0)
		var rest := key.substr(kind.length() + 1)
		match kind:
			"coins":
				coins += roundi(amount * boost("coins")) if boosted else amount
			"box":
				bag[rest] = in_bag(rest) + amount
			"part":
				if not feature_on("parts"):
					continue  # parts come much later in the game: nothing brings one home before that
				parts[rest] = int(parts.get(rest, 0)) + amount
				parts_ever = true
			"find":
				finds[rest] = true
			"bit":
				bits[rest] = int(bits.get(rest, 0)) + amount
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


## Whether your pet can rummage in its room yet (once you have a pet).
func rummage_open() -> bool:
	return collection.active() != null


## Whether this spot in your pet's room has something in it.
func rummage_ready(spot_id: String) -> bool:
	return rummage_open() and float(rummaged.get(spot_id, 0.0)) <= Time.get_unix_time_from_system()


## Your pet dug through a spot in its room: coins, sometimes xp, now and then a common part. The
## spot refills after a while. Returns what it found, e.g. { "coins": 3, "xp": 1 } (empty if the
## spot wasn't ready).
func rummage(spot_id: String) -> Dictionary:
	var spot := catalog.rummage_spot(spot_id)
	if spot.is_empty() or not rummage_ready(spot_id):
		return {}
	rummaged[spot_id] = Time.get_unix_time_from_system() + float(spot.refill)
	var found := { "coins": roundi(_rng.randi_range(int(spot.coins[0]), int(spot.coins[1])) * boost("rummage")) }
	if _rng.randf() < float(spot.get("xp_chance", 0.0)):
		found.xp = add_xp(1)
	var loot := { "coins": found.coins }
	if feature_on("parts") and _rng.randf() < float(spot.get("part_chance", 0.0)):
		var key := "part:%s:%s" % Rewards.roll_part(Jobs.COMMON_BOX, _rng, catalog)
		loot[key] = 1
		found.part = key
	grant(loot)
	return found


# ---- the capsule machine ------------------------------------------------------

## One pull of the capsule machine's lever: every chute drops a capsule (sometimes 2 or 3), each
## with one prize; a shiny ball multiplies what it holds. Once the lights are rewired a pull lights a
## lucky light; when they're all lit this pull is lucky and fever starts (capsules pay more for a
## while). Returns { capsules: [ { prize, loot, shiny, toy, pet } ], lucky, fever (it paid fever) }.
func pull_lever() -> Dictionary:
	var m: Dictionary = catalog.machine
	var now := Time.get_unix_time_from_system()
	var in_fever := now < fever_until
	machine.pulls = int(machine.pulls) + 1
	var pet_due := _pet_box_due()
	var lucky := false
	if Machine.lights_on(machine, catalog):
		machine.lit = int(machine.lit) + 1
		lucky = int(machine.lit) >= Machine.lights_needed(machine, catalog)
		if lucky:
			machine.lit = 0
	var fever := boost("fever")
	var pay := float(m.fever_pay) * fever if in_fever else 1.0
	var capsules: Array = []
	for chute in Machine.chutes(machine, catalog):
		for ball in Machine.balls_from_chute(machine, catalog, _rng):
			capsules.append(_capsule(capsules.is_empty(), lucky, pay, pet_due))
	if lucky:
		fever_until = now + Machine.fever_for(machine, catalog, fever, boost("speed"))
	var result := { "capsules": capsules, "lucky": lucky, "fever": in_fever }
	machine_pulled.emit(result)
	_check_tutorial()
	return result


## Counts pulls while you have hardly any pets (data/machine.json "pet_box"): after "sure_within"
## of them the next capsule is sure to hold a box with a pet inside, so losing your pets on
## adventures can never leave you stuck.
func _pet_box_due() -> bool:
	var pb: Dictionary = catalog.machine.get("pet_box", {})
	if tutorial_active() or pb.is_empty() or collection.count() - 1 >= int(pb.get("few_pets", 1)):
		machine.pet_wait = 0
		return false
	machine.pet_wait = int(machine.get("pet_wait", 0)) + 1
	return int(machine.pet_wait) >= int(pb.get("sure_within", 10))


## One capsule out of a pull: rolls its prize (the tutorial's pets come in the first one), makes
## it shiny sometimes, and hands out what's inside. `pay` multiplies coins (fever); `pet_due`:
## the first capsule holds a pet box (the safety net, see _pet_box_due).
func _capsule(first: bool, lucky: bool, pay: float, pet_due := false) -> Dictionary:
	var m: Dictionary = catalog.machine
	var luck := boost("luck")
	var prize := Machine.roll(machine, catalog, _rng, lucky, luck, boost("toys"), boost("pet_boxes"))
	if tutorial_active():
		prize = _machine_prize("golden" if lucky else "coins")  # nothing fancy while you're starting out
	elif not _machine_gives(str(prize.kind)) or (prize.kind == "pet_box" and not first):
		prize = _machine_prize(Machine.FALLBACK_PRIZE)  # not open yet (boxes, toys, parts); pet boxes: one pull, one chance
	elif first and toys.owned.is_empty() and _machine_gives("toy") and int(machine.pulls) >= int(m.get("first_toy_by", 0)):
		prize = _machine_prize("toy")  # your first toy, sure to come soon after toys can drop
	if first and pet_due:
		prize = _machine_prize("pet_box")
	if prize.kind == "pet_box" and room_left() <= 0:
		prize = _machine_prize("box")  # a full room: the box goes on your pile to wait
		_room_hit()
	var intel: Dictionary = m.get("intel", {})
	if first and not tutorial_active() and not intel.is_empty() and Machine.owned(machine, str(intel.after)) > 0 and not finds.has(str(intel.find)):
		prize = { "id": "intel", "kind": "intel", "find": str(intel.find) }  # a scrap of a map: the next page
	if first and _tutorial_pet_due():
		prize = { "id": "pet", "kind": "pet" }
	elif first and debug_next_prize != "" and OS.is_debug_build():
		prize = _machine_prize(debug_next_prize)
		debug_next_prize = ""
	var shiny: bool = prize.kind in ["coins", "golden", "box", "part"] and _rng.randf() < Machine.shiny_chance(machine, catalog) * boost("shiny")
	var loot := Machine.loot(prize, machine, catalog, _rng, pay)
	if loot.has("coins"):
		loot.coins = roundi(int(loot.coins) * boost("coins"))  # shown as it is
	if shiny:
		for k in loot:
			loot[k] = roundi(int(loot[k]) * Machine.shiny_pay(machine, catalog))
	var toy := {}
	var pet: Pet = null
	if prize.kind == "pet":
		var got: Array[Pet] = [_roller.roll(TUTORIAL_BOX)]
		collection.add(got)
		pet = got[0]
	if prize.kind == "pet_box":
		# the pet is rolled now (it's yours even if nobody opens the box); the machine tab plays the
		# box opening. It doesn't count as a pack you opened yourself.
		var got: Array[Pet] = [_roller.roll(str(prize.get("box", FIRST_PET_BOX)))]
		collection.add(got, _sorter())  # a box opening: the sorting rule sorts it too
		pet = got[0]
		machine.pet_wait = 0
	if prize.kind == "intel":
		grant({ "find:" + str(prize.find): 1 })
	if prize.kind == "toy":
		var t := Toys.roll(catalog, _rng, luck)
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(toys, t.id, t.finish) }
		toys_changed.emit()
		check_unlocks()
	if loot.has("xp"):
		loot.xp = add_xp(int(loot.xp))
		grant(_without(loot, "xp"), false)
	else:
		grant(loot, false)
	return { "prize": prize, "loot": loot, "shiny": shiny, "toy": toy, "pet": pet }


## The chance of each prize in the next capsule (a lucky one when `lucky`), with your boosts (the
## same ones _capsule rolls with) and only the kinds that can come out yet (Machine.odds). For the
## machine's prize card.
func machine_odds(lucky := false, first := true) -> Dictionary:
	return Machine.odds(machine, catalog, _machine_gives, lucky, boost("luck"), boost("toys"), first, boost("pet_boxes"))


func _machine_prize(id: String) -> Dictionary:
	for p in catalog.machine.prizes:
		if p.id == id:
			return p
	return catalog.machine.prizes[0]


## In the tutorial a pet comes out of the machine: your first on an early pull, the second (with a
## map: adventures open) once the machine is built up (data/tutorial.json).
func _tutorial_pet_due() -> bool:
	var t: Dictionary = catalog.tutorial
	match tutorial:
		"pull":
			return int(machine.pulls) >= int(t.get("machine_pet_at", 3))
		"machine":
			return Machine.owned(machine, str(t.get("adventure_after", "oil"))) > 0
	return false


## Machine upgrades bought, every level counted.
func machine_upgrades() -> int:
	return Machine.levels(machine)


## Whether a kind of capsule prize can come out yet: boxes once the boxes tab is open, toys once
## they are, parts once the workbench is (they all open through adventures).
func _machine_gives(kind: String) -> bool:
	match kind:
		"box": return tab_open("boxes")
		"toy": return feature_on("toys") or Machine.add(machine, catalog, "drops") > 0.0
		"part": return feature_on("parts")
		"pet_box": return not tutorial_active()
	return true


## Notes how long into the game something happened (for pacing tests, shown in settings' dev part).
func _milestone(what: String) -> void:
	if started_at > 0.0 and not milestones.has(what):
		milestones[what] = (Time.get_unix_time_from_system() - started_at) / 60.0


## How much one boost kind (data/boosts.json: "coins", "xp", "luck", "speed", "fever", "toys",
## "loot", "errands", "automation") is multiplied right now, every source together (1.0 when nothing is).
## Called every frame (errand meters, the machine), so the totals are kept until a source changes
## (_boosts_changed) and at most a second (plays run out on the once-a-second tick).
func boost(kind: String) -> float:
	if not _boosts.has(kind):
		_boosts[kind] = Boosts.total(boost_parts(kind))
	return _boosts[kind]


## What boosts a kind right now, one part per thing doing it: { source, id, x } (see Boosts). Every
## source is gathered here, since GameState holds their state; a new source appends its parts
## below. Sources: toys your pet is playing with and favourites, the collection book's open
## stickers, your active pet's knacks and the kitchen's cooks (errands only). [] (and an error) for
## a kind that isn't in data/boosts.json.
func boost_parts(kind: String) -> Array[Dictionary]:
	if not Boosts.is_kind(catalog, kind):
		push_error("unknown boost kind %s" % kind)
		return []
	var now := Time.get_unix_time_from_system()
	var out: Array[Dictionary] = []
	out.append_array(Toys.parts(toys, catalog, kind, now))
	out.append_array(Book.parts(catalog, stickers, kind))
	out.append_array(Knacks.parts(catalog, collection.active(), kind, knack_gate))
	if kind == "errands" and kitchen_bonus() > 0.0:
		out.append(Boosts.part("kitchen", "kitchen", 1.0 + kitchen_bonus()))
	return out


## A boost source changed (toys found, played with, levelled, or a play ended; a new save): the
## kept totals are worked out again.
func _boosts_changed() -> void:
	_boosts.clear()


## Something every pet's knacks depend on changed (a pet's parts, a new save): the boosts, each
## pet's own knack share and the errand and worker speeds are worked out again.
func _knacks_changed() -> void:
	_boosts_changed()
	_knack_steps.clear()
	_knack_own.clear()
	knack_version += 1
	_job_speed.clear()
	_worker_speed.clear()


## A knack gate may have opened (an unlock, a machine fix, the tutorial): the boosts are worked out
## again, and the errand or worker speeds only if the knack kinds counting for them changed (a
## machine fix only opens fever and shiny knacks, which neither uses).
func _knack_gates_changed() -> void:
	_boosts_changed()
	var was := { "errands": _knack_counting("errands"), "automation": _knack_counting("automation") }
	_knack_steps.clear()
	_knack_own.clear()
	knack_version += 1
	if _knack_counting("errands") != was.errands:
		_job_speed.clear()
	if _knack_counting("automation") != was.automation:
		_worker_speed.clear()
	knacks_changed.emit()


## The knack kinds counting for a boost kind right now (see Knacks.counting), kept until a gate moves.
func _knack_counting(kind: String) -> Dictionary:
	if not _knack_steps.has(kind):
		_knack_steps[kind] = Knacks.counting(catalog, kind, knack_gate)
	return _knack_steps[kind]


## What a pet's own knacks of a kind do for its own work (see Knacks.own), kept per pet until its
## parts or a gate change, so big crews and parties stay quick.
func knack_own(pet: Pet, kind: String) -> float:
	if pet == null or pet.uid == "":  # a count's template (see Herd.template): pets from the herd have no knacks
		return 1.0
	var steps := _knack_counting(kind)
	if steps.is_empty():
		return 1.0
	if not _knack_own.has(kind):
		_knack_own[kind] = {}
	var per: Dictionary = _knack_own[kind]
	if not per.has(pet.uid):
		per[pet.uid] = Knacks.own_in(catalog, pet, steps)
	return per[pet.uid]


## Whether a knack gate (data/knacks.json "opens") is open: "adventures" (the tutorial is past the
## machine), "machine:<node>" (that node on the machine's tree is fixed), or an unlock id.
func knack_gate(gate: String) -> bool:
	if gate == "adventures":
		return not tutorial in ["pull", "machine"]
	if gate.begins_with("machine:"):
		return Machine.owned(machine, gate.substr(8)) > 0
	return is_open(gate)


## Your active pet's knacks that show right now (see Knacks.of), or another pet's.
func knacks_of(pet: Pet) -> Array[Dictionary]:
	return Knacks.of(catalog, pet, knack_gate)


## Kinds a trip packs when it sets off (RunState.knacks).
const TRIP_KNACKS := ["trip", "tough", "safe", "spots", "finds", "pickups", "treats", "loot"]


## What knacks do for a trip with these pets: your active pet's (the boost, which has the other
## sources too) times the party's own share, per kind; kinds at x1 are left out. `loot` is the
## party's share only (your active pet's loot boost is added when the trip is collected).
func trip_knacks(pets: Array) -> Dictionary:
	var out := {}
	for kind: String in TRIP_KNACKS:
		var share := 1.0
		if not pets.is_empty() and not _knack_counting(kind).is_empty():
			var sum := 0.0
			for pet in pets:
				sum += knack_own(pet, kind)
			share = sum / pets.size()
		var x := share * (1.0 if kind == "loot" else boost(kind))
		if not is_equal_approx(x, 1.0):
			out[kind] = x
	return out


## Opens the sticker of every book page that's full now (once each, for good): the popup shows it.
func check_book() -> void:
	if _loading:
		return
	var opened := Book.newly_full(catalog, collection, stickers)
	if opened.is_empty():
		return
	for id in opened:
		stickers.append(id)
	_boosts_changed()  # the book is a boost source
	for id in opened:
		sticker_opened.emit(id)
	jobs_changed.emit()
	automation_changed.emit()
	changed.emit()
	save_game()


## Gives xp, boosted (the "xp" kind). Returns how much it really was.
func add_xp(amount: int) -> int:
	var real := roundi(amount * boost("xp"))
	xp += real
	return real


# ---- gear: upgrades to adventuring, bought with xp (see Gear, data/gear.json) ----

func gear_level(id: String) -> int:
	return Gear.level(gear, id)


## The gear stickers on the path right now, in path order (see Gear.shown).
func shown_gear() -> Array[Dictionary]:
	return Gear.shown(catalog, gear, is_open)


## Why a gear can't take another level ("" if it can, xp aside): "hidden" (not on the path yet) or "max".
func gear_block(id: String) -> String:
	var g := Gear.info(catalog, id)
	if g.is_empty() or not shown_gear().any(func(s): return s.id == id):
		return "hidden"
	return "max" if gear_level(id) >= int(g.max) else ""


## xp for a gear's next level.
func gear_price(id: String) -> int:
	return Gear.price(catalog, id, gear_level(id))


## Buys a gear's next level with xp. Returns whether it could.
func buy_gear(id: String) -> bool:
	if gear_block(id) != "" or xp < gear_price(id):
		return false
	xp -= gear_price(id)
	gear[id] = gear_level(id) + 1
	gear_changed.emit()
	changed.emit()
	save_game()
	return true


## Sets a gear's level outright (the dev driver's "gear" step).
func set_gear_level(id: String, level: int) -> void:
	var g := Gear.info(catalog, id)
	if g.is_empty():
		return
	gear[id] = clampi(level, 0, int(g.max))
	gear_changed.emit()
	changed.emit()


## The upgrades page opens with the first xp (and stays open once something's bought).
func gear_page_open() -> bool:
	return xp > 0 or gear.values().any(func(lv): return int(lv) > 0)


## The gear a trip there would pack (for the place card's time and odds).
func trip_gear(location_id: String) -> Dictionary:
	return Gear.for_trip(catalog, gear, catalog.location(location_id))


## A trip's haul, boosted as it's collected: the loot and coins boosts multiply its coins (and so
## does the tote bag in the trip's `packed` gear), and loot times luck gives a chance of an extra copy
## of every part and box. The trip's `knacks` (RunState.knacks): the party's own loot share, and
## "finds" gives a chance of an extra copy of every part and bit.
func _boost_trip_loot(loot: Dictionary, packed := {}, knacks := {}) -> void:
	var tote := 1.0 + Gear.value(catalog, packed, "coins")
	var more := boost("loot") * float(knacks.get("loot", 1.0))  # the party's own knacks too
	var lucky := more * boost("luck")
	var finds := float(knacks.get("finds", 1.0))  # knacks: more bits and parts
	for key: String in loot.keys():
		if key.begins_with("part:") and not feature_on("parts"):
			loot.erase(key)  # parts come much later in the game
			continue
		if key == "coins":
			loot[key] = roundi(int(loot[key]) * more * boost("coins") * tote)
		elif key.begins_with("part:"):
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (lucky - 1.0 + finds - 1.0), _rng)
		elif key.begins_with("box:"):
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (lucky - 1.0), _rng)
		elif key.begins_with("bit:") and finds > 1.0:
			loot[key] = int(loot[key]) + Rewards.count(int(loot[key]) * (finds - 1.0), _rng)


## Seconds a capsule takes to pop open, quicker with the capsule speed boost.
func capsule_seconds() -> float:
	return Machine.reveal_seconds(machine, catalog) / boost("speed")


# ---- capsule toys ------------------------------------------------------------------

## Your pet starts playing with a toy (Toys.play). Returns whether it could.
func play_toy(edition: String, play_id: String) -> bool:
	if not Toys.play(toys, catalog, edition, play_id, Time.get_unix_time_from_system()):
		return false
	toys_changed.emit()
	changed.emit()
	save_game()
	return true


## Fixes a toy's wear on the workbench. Returns whether you could afford it.
func fix_toy(edition: String) -> bool:
	var price := Toys.fix_cost(toys, catalog, edition)
	if price <= 0 or coins < price or Toys.playing(toys, edition, Time.get_unix_time_from_system()):
		return false
	coins -= price
	toys.owned[edition].wear = 0.0
	toys_changed.emit()
	changed.emit()
	save_game()
	return true


## Combines spares into the next level (Toys.combine). Returns whether it could.
func combine_toy(edition: String) -> bool:
	if not Toys.combine(toys, catalog, edition):
		return false
	toys_changed.emit()
	save_game()
	return true


## Sacrifices spares of a toy for a chance at a special finish. Returns the finish, or "".
func sacrifice_toy(id: String) -> String:
	if not Toys.can_sacrifice(toys, catalog, id):
		return ""
	var got := Toys.sacrifice(toys, catalog, id, _rng)
	toys_changed.emit()
	save_game()
	return got


## Where pets find a machine bit, for the upgrade card when you're short of one: the open places
## whose treat bag holds it, or, before any of those is found, a place that leads there.
func bit_hint(bit: String) -> String:
	var plural := bit if bit == "glass" else bit + "s"
	var come := "comes" if bit == "glass" else "come"
	var open: Array[String] = []
	var closed: Array[Dictionary] = []
	for location in catalog.locations:
		if not location.get("finish_rewards", []).any(func(r): return r.get("kind", "") == "bit" and str(r.get("id", "")) == bit):
			continue
		if location_open(location):
			open.append(str(location.name))
		else:
			closed.append(location)
	if not open.is_empty():
		return "pets find %s at %s" % [plural, " and ".join(open)]
	for location in closed:
		if spotted.has(location.id):
			return "%s %s from %s. a pet spotted it: say yes on the map!" % [plural, come, location.name]
	for location in closed:
		for from in catalog.locations:
			if location_open(from) and from.get("leads_to", []).any(func(l): return str(l.to) == location.id):
				return "%s %s from a place nobody's found yet. keep going to %s!" % [plural, come, from.name]
	return "pets find %s on adventures" % plural


## Seconds of fever left on the machine (0 when there's none).
func fever_left() -> float:
	return maxf(0.0, fever_until - Time.get_unix_time_from_system())


## Fixes or upgrades one level of a node on the machine's tree (coins and bits). Returns whether you could.
func buy_machine_upgrade(id: String) -> bool:
	if Machine.blocker(machine, catalog, id, coins, bits) != "":
		return false
	coins -= Machine.cost(machine, catalog, id)
	var need := Machine.bits_cost(catalog, id)
	for b in need:
		bits[b] = int(bits.get(b, 0)) - int(need[b])
	machine.bought[id] = Machine.owned(machine, id) + 1
	machine_upgraded.emit(id)
	check_unlocks()
	save_game()
	changed.emit()
	return true


static func _without(loot: Dictionary, key: String) -> Dictionary:
	var out := loot.duplicate()
	out.erase(key)
	return out


func set_pet_out(value: bool) -> void:
	pet_out = value
	changed.emit()


# ---- saving ---------------------------------------------------------------

func save_game() -> void:
	if not _can_save:
		return
	if _hold_saves:  # automation is working through a tick (or loading): it saves once at the end
		_save_held = true
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
		"new_homes": homes,
		"errand_tools": errand_tools,
		"scout_notes": scout_notes,
		"gear": gear,
		"stickers": stickers,
		"room": room,
		"automation": automation,
		"reserve_capsules": reserve_capsules,
		"saved_boxes": saved_boxes.keys(),
		"boxes_bought": boxes_bought,
		"boxes_greeted": boxes_greeted.keys(),
		"visited": visited.keys(),
		"buying_on": buying_on,
		"pinned": pinned,
		"rummaged": rummaged,
		"machine": machine,
		"toys": toys,
		"bits": bits,
		"started_at": started_at,
		"milestones": milestones,
		"idle_log": idle_log,
		"runs": runs.map(func(r): return r.to_dict()),
		"saved_at": Time.get_unix_time_from_system(),
	}
	SaveFile.write(save_path, data)


## Loads the save. Returns false if there's none yet (a brand new player).
func load_game() -> bool:
	_loading = true
	var loaded := _load_save()
	_loading = false
	return loaded


func _load_save() -> bool:
	var data := SaveFile.read(save_path)
	if data.is_empty():
		return false
	if int(data.get("version", 1)) > SAVE_VERSION:
		# don't downgrade a save from a newer game: play with it, but never write over it
		push_warning("save is from a newer version of the game; it won't be overwritten")
		_can_save = false
	var from_version := int(data.get("version", 1))
	data = _migrate(data)
	BoxShop.fix_retired(data)  # not tied to a version: lucky boxes on the pile or on a trip turn into sunset boxes
	coins = int(data.get("coins", coins))
	xp = int(data.get("xp", 0))
	hunger = data.get("hunger", hunger)
	happiness = data.get("happiness", happiness)
	pet_out = data.get("pet_out", false)
	tutorial = str(data.get("tutorial", "done"))  # saves from before the tutorial skip it
	# before the collection: its pets_added would open a page's sticker again otherwise
	stickers = Book.clean(catalog, data.get("stickers", []))  # v24: older saves open theirs after loading (check_book)
	_boosts_changed()
	collection.auto_active = true  # your first pet is always your active pet (you can change it later)
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
		if not open_jobs().any(func(j): return j.id == job_id) or not saved_jobs[job_id] is Dictionary:
			continue  # a job that's gone, or not open (yet): its pets rest
		var crew: Array = []
		for raw_uid in saved_jobs[job_id].get("crew", []):
			var uid := str(raw_uid)
			if collection.get_pet(uid) != null and uid != collection.active_uid and not on_trips.has(uid) and not placed.has(uid):
				crew.append(uid)
				placed[uid] = true
		jobs[job_id] = { "crew": crew, "herd": Herd.clean_counts(catalog, saved_jobs[job_id].get("herd", {})),
			"fill": clampf(float(saved_jobs[job_id].get("fill", 0.0)), 0.0, 1.0), "join": bool(saved_jobs[job_id].get("join", false)) }
	if from_version < 28 and bool(data.get("jobs_auto", false)):
		# v28: "your pet shares out new pets" became "new pets join here" on each job: every open
		# errand it shared out to (not the kitchen or scouting: you staff those)
		for job in open_jobs():
			if Jobs.shared_out(job):
				_job_state(job.id).join = true
	homes = NewHomes.clean(catalog, data.get("new_homes", {}))  # v28 added new homes
	errand_tools = {}
	_tools_changed()
	var saved_tools: Dictionary = data.get("errand_tools", {})
	for id in saved_tools:
		if not Jobs.tool(catalog, str(id)).is_empty():
			errand_tools[str(id)] = maxi(0, int(saved_tools[id]))
	scout_notes = clampi(int(data.get("scout_notes", 0)), 0, scout_hold())  # v23
	_crews_changed()
	gear = Gear.clean(catalog, data.get("gear", {}))  # v22 added gear: older saves start with none
	room = maxi(0, int(data.get("room", 0)))  # v28 added the room
	if from_version < 28:
		# a save from before the room that already had more pets gets room for them (and a bit more),
		# so boxes and box jobs keep opening (before the catch-up below: box workers open boxes there)
		var margin := float(catalog.herd.get("room", {}).get("old_save_margin", 0.1))
		room = maxi(room, Herd.room_level_for(catalog, ceili(collection.plain_count() * (1.0 + margin))))
	_load_automation(data.get("automation", {}))
	reserve_capsules = clampi(int(data.get("reserve_capsules", default_reserve())), 0, reserve_max())  # v25
	_hold_saves = true  # no saving halfway through loading
	_clamp_herd_places()
	_hold_saves = false
	_save_held = false
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
	boxes_bought.clear()
	var bought: Dictionary = data.get("boxes_bought", {})
	for id in bought:
		boxes_bought[str(id)] = int(bought[id])
	boxes_greeted.clear()
	for id in data.get("boxes_greeted", []):
		boxes_greeted[str(id)] = true
	buying_on = bool(data.get("buying_on", true))
	pinned.assign(data.get("pinned", []).filter(func(uid): return collection.get_pet(str(uid)) != null).map(func(uid): return str(uid)))
	idle_log = data.get("idle_log", {})
	rummaged.clear()
	var saved_rummage: Dictionary = data.get("rummaged", {})
	for id in saved_rummage:
		if not catalog.rummage_spot(str(id)).is_empty():
			rummaged[str(id)] = float(saved_rummage[id])
	var saved_machine: Dictionary = data.get("machine", {})
	machine = { "pulls": int(saved_machine.get("pulls", 0)), "lit": int(saved_machine.get("lit", 0)), "bought": {},
		"pet_wait": int(saved_machine.get("pet_wait", 0)) }
	var saved_bought: Dictionary = saved_machine.get("bought", {})
	for id in saved_bought:
		if not Machine.node(catalog, str(id)).is_empty():
			machine.bought[str(id)] = int(saved_bought[id])
	bits = {}
	var saved_bits: Dictionary = data.get("bits", {})
	for b in saved_bits:
		bits[str(b)] = maxi(0, int(saved_bits[b]))
	started_at = float(data.get("started_at", 0.0))
	milestones = data.get("milestones", {})
	toys = Toys.fresh()
	var saved_toys: Dictionary = data.get("toys", {})
	var owned: Dictionary = saved_toys.get("owned", {})
	for k in owned:
		var bits := str(k).split(":")
		if bits.size() == 2 and not Toys.toy(catalog, bits[0]).is_empty() and not Toys.finish(catalog, bits[1]).is_empty():
			var e: Dictionary = owned[k]
			toys.owned[str(k)] = { "level": clampi(int(e.get("level", 1)), 1, int(catalog.toys.max_level)),
				"spares": maxi(0, int(e.get("spares", 0))), "wear": clampf(float(e.get("wear", 0.0)), 0.0, 1.0) }
	for p in saved_toys.get("playing", []):
		if p is Dictionary and toys.owned.has(str(p.get("key", ""))):
			toys.playing.append({ "key": str(p.key), "until": float(p.get("until", 0.0)), "wear": float(p.get("wear", 0.0)) })
	Toys.finish_plays(toys, Time.get_unix_time_from_system())  # plays that ended while the game was closed
	_knacks_changed()
	if from_version >= 15 and from_version < 20:
		_regate()
		if knows_job("boxes"):  # it had the cushion: opening boxes stays (now in the automation tab)
			unlocks["feature:packs"] = true
			unlocks["tab:automation"] = true
	# catch up on time spent closed: coins at the slowest rate, stats to the floor at worst (before
	# the errands catch up, so the kitchen's meals made while you were away still count)
	var away := Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))
	if away > 0.0:
		coins += int(minf(away, OFFLINE_CAP) * 0.4 / COIN_INTERVAL * boost("away"))
		hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * away)
		happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * away)
	# errands kept going while the game was closed: full speed for a while, then slower
	var e: Dictionary = catalog.errands
	var closed := Jobs.offline_seconds(Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0)),
		errands_away_hours(), float(e.offline_after), OFFLINE_CAP) * boost("away")
	var brought := _work_for(closed)
	jobs_away = { "coins": Rewards.total(brought, "coins"), "parts": Rewards.total(brought, "part") }
	_jobs_at = Time.get_unix_time_from_system()
	# your pet kept cranking its machine while the game was closed, as long as its stool lets it,
	# and workers too, as long as its stool lets them
	var cranked := Automation.away_seconds(catalog, automation, Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))) * boost("away")
	if cranked > 0.0:
		_hold_saves = true  # no saving halfway through loading: the next autosave has it all
		_work_for_automation(cranked, false)
		_hold_saves = false
		_save_held = false
	_auto_at = Time.get_unix_time_from_system()

	# v28: plain pets fold into the herd (old saves: crews and workers of uids become counts here)
	_rest_changed()
	collection.refold()
	if from_version < 28 and room_is_full() and not homes.room_was_full:
		# new homes came in v28: a room that's full already has been full, the stall is there
		homes.room_was_full = true
		check_unlocks()
	return true


## Pets from the herd on errands and machines never add up to more than the herd has (a save from
## elsewhere, or a count that shrank): the extra ones rest.
func _clamp_herd_places() -> void:
	var have := {}
	for k in collection.herd:
		have[k] = collection.herd_count(k)
	for uid: String in _stand_ins_out():
		Herd.take(have, Herd.key_of(uid), 1)
	var crews := false
	for job_id in jobs:
		var h: Dictionary = _job_state(job_id).herd
		for k in h.keys():
			var ok := mini(int(h[k]), int(have.get(k, 0)))
			Herd.take(have, k, ok)
			if ok < int(h[k]):
				Herd.take(h, k, int(h[k]) - ok)
				crews = true
	var workers := false
	var wh: Dictionary = automation.get("wherd", {})
	for id in wh:
		for k in wh[id].keys():
			var ok := mini(int(wh[id][k]), int(have.get(k, 0)))
			Herd.take(have, k, ok)
			if ok < int(wh[id][k]):
				Herd.take(wh[id], k, int(wh[id][k]) - ok)
				workers = true
	if crews:
		_crews_changed()
	if workers:
		_workers_changed()


## v20: saves from the capsule machine's time (v15 on) kept things old gates had opened: the
## second map page before the map scrap, the boxes tab before better drops, the workbench from
## parts that slipped in early. Everything data/unlocks.json opens closes again unless what earns
## it is really there (places you already found stay open). Older saves (and the test saves) keep
## what the migrations above gave them.
func _regate() -> void:
	if not is_unlocked("feature:parts"):
		parts_ever = false  # parts that slipped in early don't count as your first part
	for _pass in 2:  # twice: an unlock can wait for another one ("open")
		for o in UnlockRules.stale(catalog.unlock_list, _earned):
			unlocks.erase(o)
	_knacks_changed()


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
	# v15 added the capsule machine, v16 capsule toys; saves without them start fresh
	if version < 18:
		# v18: parts come later (a feature of their own); saves that already had parts keep them
		if bool(data.get("parts_ever", false)):
			var had: Array = data.get("unlocks", [])
			data.unlocks = had + ["feature:parts"]
	if version < 17:
		# v17: the boxes tab and toys open through adventures now; saves from before keep them
		if str(data.get("tutorial", "done")) == "done":
			var had: Array = data.get("unlocks", [])
			data.unlocks = had + ["tab:boxes", "feature:toys"]
	if version < 19:
		# v19: parts slipped in early (rummaging, the scrapyard), so v18 opened them for saves that
		# weren't there yet. They close again until the 40th trip; parts already found stay in the bag.
		if int(data.get("trips_done", 0)) < 40:
			data.unlocks = data.get("unlocks", []).filter(func(id): return str(id) != "feature:parts")
	if version < 21:
		# v21: your pet opening boxes is a job in the automation tab now (the cushion teaches it):
		# saves that had it keep it, doing it if it was on
		var had: Array = data.get("unlocks", [])
		if "feature:packs" in had:
			if not "tab:automation" in had:
				data.unlocks = had + ["tab:automation"]
			var a := Automation.fresh()
			a.taught["boxes"] = true
			a.task = "boxes" if bool(data.get("packs_on", true)) else ""
			data.automation = a
	if version < 25:
		# v25: your pet's reserve is kept in capsules, like box prices: the coins it kept become
		# capsules at what one is worth on that save's machine (at least 1 if it kept any)
		var kept := float(data.get("coin_reserve", default_reserve()))
		var value := Machine.coin_value({ "bought": data.get("machine", {}).get("bought", {}) }, catalog)
		data.reserve_capsules = maxi(1, roundi(kept / value)) if kept > 0.0 else 0
		data.erase("coin_reserve")
	# v26 added box tiers (boxes_bought, boxes_greeted) and retired the lucky box: BoxShop.fix_retired
	# (load_game) handles both for any save, whatever its version
	# v27 added the whistle (automation.whistle: ticks, set aside): older saves load with every tick
	# on and the default set aside (_load_automation)
	# v28: the herd, new homes and "new pets join here". Collection.load_from reads the old collection
	# (stars as [uid, palette], the first pet with each part marked), and load_game folds plain pets
	# into counts once everything that keeps pets busy has loaded: old crews and workers of uids turn
	# into counts by themselves. load_game also switches every shared-out errand's "new pets join
	# here" on where jobs_auto was on, and a room that's full already opens the stall.
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
