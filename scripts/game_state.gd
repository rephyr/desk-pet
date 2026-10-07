class_name GameStateNode
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
signal homes_rule_changed  # the sorting rule was switched or stepped (the sorting card)
signal gifts_changed  # a present came into the pocket or one was opened (see Gifts)
signal globe_arrived(id: String)  # a new machine globe came home (a pet brought its find), see Machine
signal page_opened(page_id: String)  # a map page was opened by the game's code (open_page)
signal edge_changed  # pets went past the edge (the scribbles and the number to go changed)
signal school_changed  # pets sat down in the school, or the bell rang
signal dungeon_changed  # the army or its orders changed, it set off down the well, or it came home
signal plushie_changed  # the plushie machine changed: a pet fed in, a keeper picked, a reel held, a nudge or hold bought
signal plushie_spun(result: Dictionary)  # the plushie machine spun (or banked, nudged, brought the next pet in), see plushie_spin()
signal wish_changed(step: int)  # the wish moved or pets went into its jar; step = the step that just filled (0: none)
signal workshop_changed(built_id: String)  # helpers joined a drawing in the shed workshop, or one was built (its id)

# ---- GameState's parts, by area (scripts/state/): the code lives there, the state stays here ----
var toys_part := ToysPart.new(self)
var machine_part := MachinePart.new(self)
var boxes_part := BoxesPart.new(self)
var homes_part := HomesPart.new(self)
var workshop_part := WorkshopPart.new(self)
var unlocks_part := UnlocksPart.new(self)
var rest_part := RestPart.new(self)
var errands_part := ErrandsPart.new(self)
var automation_part := AutomationPart.new(self)
var workers_part := WorkersPart.new(self)
var dungeon_part := DungeonPart.new(self)
var perks_part := PerksPart.new(self)
var sewing_part := SewingPart.new(self)
var plushie_part := PlushiePart.new(self)
var edge_part := EdgePart.new(self)
var wish_part := WishPart.new(self)
var adventures_part := AdventuresPart.new(self)
var gear_part := GearPart.new(self)
var boosts_part := BoostsPart.new(self)
# ---- end of the parts ----

var save_path := DevProfile.path("save.json")  # user://save.json, or a test profile's (debug builds)
## Headless tests set this before making a GameState: it starts empty and never loads or saves
## (a test turns saving on with its own save_path).
static var testing := false
## A tool or test script (godot -s ...) runs instead of the game: then no GameState (the autoload or
## one the script makes) loads or saves the real or profile save, unless the script sets this (the
## GameState tests do, on their own profile's save). See tool_run().
static var tool_saves := false
const SAVE_VERSION := 43
const PINNED_MAX := 10  # good pulls waiting to be seen: older ones stop waiting (and may fold into the herd)
const SPARE_FRESH_MS := 1000  # spare_shelves() is worked out again at least this often
const WORKER_BOXES_MAX := 2000  # box workers open at most this many boxes in one go (every pet is rolled)
const OFFLINE_CAP := 12.0 * 3600.0
const FRAME_GAP := 5.0  # a frame this long means the computer slept: counts as closed (no care drain)
const FIRST_PET_BOX := "starter"
const DEBUG_COINS := 1000
const BACKGROUND_PACK_EVERY := 8.0  # seconds per pack your pet opens out of sight (its animation takes about this)
const BACKGROUND_AFTER := 1.0  # out of sight this long before it switches to opening in the background
const TUTORIAL_BOX := "tutorial"  # hidden box the tutorial's pets come from, see data/boxes.json

var catalog := Catalog.shared()
var collection := Collection.new()
var coins := 100  # money: what gets spent on stuff (boxes, food, ...)
const COINS_MAX := 9000000000000000000  # just under int's top (see grant, coins_int)
var xp := 0  # experience from adventures: buys upgrades to adventuring itself
var gear := {}  # gear id -> level, bought with xp (the adventures tab's upgrades page, see Gear)
## The collection book's reward stickers you've opened (page ids, see Book and data/book.json).
## Kept for good: the boost reads this list, not how full the page is now.
var stickers: Array[String] = []
## The wishing jar: what you wish for and every look's jar, see Wish and data/wish.json.
var wish := Wish.fresh()
var hunger := 70.0  # food, 100 = full; starts on the tick, no buff yet (only drains while open, see Care)
var happiness := 70.0  # mood
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
var visits := {}  # location id -> trips welcomed back from there (next door's lights go out one a visit, see Ours)
var _seen_buyable := {}  # tab id -> { "id:level": true } affordable when you last looked (not saved, see upgrade_news)
var find_tries := {}  # find id -> trips that could have met its event so far (it turns up for sure at catalog.find_sure_by)
var sent := {}  # location id -> pets ever sent there, every party added up (the rope at the well waits for enough, see after_sent)
var unshown_ours := {}  # location id -> true: it became ours and the map hasn't coloured it in yet (MapView, then ours_shown; not saved)
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
var _crew_speeds := {}  # job id -> its crew cards' speeds added up, kept while pets only join (see _crew_sum)
var _crew_tips := {}  # job_tips' key -> job id -> the crew cards' tips added up (see _crew_sum)
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
var _spare := {}  # spare_shelves(), worked out again when _spare_changed() or a second old
var _spare_at := 0
var room := 0  # room steps built (the house card): the room holds this many plain pets, see Herd.room_cap
## New homes: the stall's jar, the sorting rule and its count, see NewHomes and data/new_homes.json
var homes := NewHomes.fresh(Catalog.shared())
var workshop := Workshop.fresh(Catalog.shared())  # the shed workshop's drawings, see Workshop
var watching: RunState = null  # the trip you're watching on the trail (AdventuresTab; not saved)
var postcards: Array[Dictionary] = []  # trips the bell rope welcomed back, waiting for you to see (not saved)
var _mend_at := 0.0  # unix time the sewing basket has mended toys up to
var _mend_acc := 0.0  # seconds of mending saved up (the basket stitches once a minute)
var _to_work := {}  # uid -> true: new pets the sorting rule sends to work (placed as they're added)
var _sent_home := {}  # uid -> true: pets from the last open_boxes the sorting rule sent to new homes (or school)
var _school_flush := false  # the sorting rule sat pets down in the school: school_changed is on its way
var edge := Edge.fresh()  # past the edge: pages filled, pets sent, the scribbles (see Edge, data/edge.json)
var school := School.fresh()  # the little school: who sits in the class, the classes of teachers (see School)
var _school_x := 1.0  # School.boost(school), kept (school_changed_boost): a source of the automation and errands boosts


var reserve_capsules := 50  # what your pet never spends on boxes (once it may buy them), in plain capsules
var saved_boxes := {}  # box id -> true: "save for me", your pet leaves these on the pile
var boxes_bought := {}  # box id -> how many you've bought (a tier in the shop is "new!" until the first)
var boxes_greeted := {}  # box id -> true: the boxes tab has shown this tier arriving (your pet said so)
var debug_all_tiers := false  # debug builds: every box tier is in the shop (dev step "tiers all"), not saved
var buying_on := true  # your pet buys more when the pile runs out (once it has the piggy bank)
var pinned: Array[String] = []  # good pulls your pet opened, waiting for you to see them
var join_up_to := ""  # "new pets join here" only takes new pets up to this rarity ("" = every rarity)
var rummaged := {}  # rummage spot id -> unix time it has something in it again (see data/rummage.json)
## The capsule machine, see Machine and data/machine.json: { pulls, lit, bought: { upgrade id: n },
## globes: [globe ids you have], greeted: [globes the machine tab has shown arriving] }
var machine := { "pulls": 0, "lit": 0, "bought": {}, "globes": [], "greeted": [] }  # the first globe is always home (Machine.home)
var fever_until := 0.0  # unix time the machine's fever ends (not saved: it's ten seconds)
## Capsule toys you own and the ones your pet is playing with, see Toys and data/toys.json
var toys := Toys.fresh()
## Presents, one every few hours of wall clock (see Gifts and data/gifts.json): { next_at, pocket }
var gifts := Gifts.fresh()
var debug_gift_roll := ""  # debug builds: the next present holds "one" box, "two" or a "toy" as well
var bits := {}  # machine bits pets bring home from adventures: bit id (gear, spring, bolt, glass) -> how many
var wisps := 0  # the darker currency, one purse: the dungeon's cleared floors pay them (lanterns, data/dungeon.json), plushie machine misses puff them; see grant_wisps
var plushie := Plushie.fresh()  # the plushie machine's state (keeper, hopper, the pet in it and its reels), see Plushie
var debug_land := {}  # debug builds: what the plushie machine's next spin lands on, slot (or "wild") -> symbol
## What your pet does for you (the automation tab), see Automation and data/automation.json
var automation := Automation.fresh()
var dungeon := Dungeon.fresh(Catalog.shared())  # the old well, all the way down (see Dungeon)
var dungeon_news := {}  # the army just came home: { got, floor, early, deepest, nail } (a sewing room run: { got, room, cleared, again }) for your pet to say (not saved)
var sewing := Sewing.fresh()  # E3 the sewing room off the well's floor 20 (see Sewing)
var sew_seats := {}  # the sewing room's seats for room sew_seats_room: mark -> uid of the pet sitting on it (not saved: tap a seat, then a pet)
var sew_seats_room := -1
var sew_last := {}  # the last room run home: { room, got, sent, back, cleared, first } for the sewing page's result (not saved)
var perks := {}  # the wisps perk tree on the well wall: perk id -> level (see Perks, data/perks.json)
## The last run home from the well while you were here (for the page's "came home" report; not saved):
## { run (its floors and orders), tally (Dungeon.run_tally of all of it), front ([Pet] the front row that
## went, the strongest first), lead (your pet, or null), deepest, new_deep, got, best (see _best_bit) }.
## {} once you change the army or the orders ("change the army", a tap on a floor), or a new run goes down.
var dungeon_report := {}
var army_held := false  # the sewing room is open on screen: your pet leading the army waits at home for you (not saved)
var crews_by_themselves := false  # true while jobs_changed is new pets joining on their own (late on, every second): views may catch up later
var _auto_at := 0.0  # unix time your pet's jobs have worked up to
var _boxes_at := 0.0  # ... and the workers' box opening, when it runs on a frame of its own (see _process)
var _hold_saves := false  # automation's tick is running: saves wait for the end of it
var _loading := false  # load_game is running: the book waits (collection signals fire halfway through)
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
var _care_on: Array[String] = []  # care buffs on right now (see _check_care)
var _away := false  # working through time the computer slept: no care buffs (see _without_care)
var _pat_at := -INF  # when a pat last gave mood (unix seconds; data/care.json pat.every)
var _save_timer := 0.0
var _save_task := -1  # a save being written on a worker thread (WorkerThreadPool task id), see save_game
var _run_timer := 0.0
var _tick_phase := 0  # which quarter of the once-a-second work runs next (see _process)
const TICK_PHASE := 0.25
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
	if testing or (tool_run() and not tool_saves):
		_can_save = false
	elif not load_game():
		_start_tutorial()  # a brand new player
	else:
		if collection.count() == 0 and tutorial == "done":
			_give_first_pet()
		check_unlocks.call_deferred()  # an update may have new unlocks this save has earned (after the UI is up: popups)
		_open_edge_pages.call_deferred()
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
		if p and p.uid in dungeon.cards:
			dungeon.cards.erase(p.uid)  # your active pet leads the army, it isn't in it
			dungeon_changed.emit()
		if _was_active != "" and (p == null or p.uid != _was_active):
			_place_new([_was_active])  # your old active pet goes back to work (where new pets join)
		_was_active = p.uid if p else "")
	_was_active = collection.active_uid
	collection.pet_changed.connect(func(_p):
		_spare_changed()  # a favourite or buttons: whether it may go changed
		_worker_speed.clear()
		_job_speed.clear()
		_crew_speeds.clear()
		_job_tip.clear()
		_crew_tips.clear()
		_kitchen_changed())  # the kitchen's bonus depends on the cooks
	collection.pets_removed.connect(func(uids):
		_take_off(uids)
		_take_off_workers(uids)
		for per: Dictionary in _knack_own.values():
			for uid in uids:
				per.erase(uid)
		pinned = pinned.filter(func(uid): return not uid in uids)
		_rest_changed())
	collection.pets_added.connect(func(pets: Array[Pet]):
		_rest_changed()
		_place_new(pets.map(func(p): return p.uid)))


## True when Godot runs a tool or test script (-s / --script) as the main loop, not the game.
static func tool_run() -> bool:
	var args := OS.get_cmdline_args()
	return "-s" in args or "--script" in args


func _process(delta: float) -> void:
	# food and mood only go down while the game is open (a long frame gap is the computer asleep)
	if delta <= FRAME_GAP:
		var food := Care.drain(catalog, "food", hunger, delta)
		var mood := Care.drain(catalog, "mood", happiness, delta)
		var crossed := Care.crossed(catalog, hunger, happiness, food, mood)
		hunger = food
		happiness = mood
		if crossed:
			_check_care()

	_open_in_background(delta)
	_zoom_runs(delta)

	# the once-a-second work, a quarter on each of four frames a quarter second apart: late in the
	# game errands, your pet's crank and the workers' boxes each take several ms, and all at once
	# they were a hitch every second (smaller batches more often cost more: every batch tells the
	# views)
	_run_timer -= delta
	if _run_timer <= 0.0:
		_run_timer = TICK_PHASE
		var now := Time.get_unix_time_from_system()
		match _tick_phase:
			0:
				_advance_runs()
				_dungeon_tick()
				_tick_gifts(now)
				var ended := _finish_plays(now)
				if not ended.is_empty():
					toys_changed.emit()
					play_ended.emit(ended)
					save_game()
				_workshop_chores(now)
			1: _work_jobs(now)
			2: _work_automation(now, "crank")
			3: _work_automation(now, "boxes")
		_tick_phase = (_tick_phase + 1) % 4

	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()


# ---- boxes ----------------------------------------------------------------

## What `count` of a box cost in coins with a capsule worth `value`: its 'capsules' x value (so the
## shop keeps up with the machine, like errands), or a fixed 'price'.
static func box_cost(box: Dictionary, value: float, count := 1) -> int:
	var unit := float(box.capsules) * value if box.has("capsules") else float(box.get("price", 0))
	if unit <= 0.0 or count <= 0:
		return 0
	var one := maxi(1, roundi(minf(unit, Jobs.MAX_PRICE)))  # one box's price, rounded: 10 cost 10x that
	return int(minf(float(one) * count, Jobs.MAX_PRICE))


# ---- the room: one cap for every plain pet together (see Herd, data/herd.json) ----------------

# ---- new homes: the stall on the pets tab and the sorting rule (see NewHomes) ---------------

# ---- the shed workshop (F3, data/workshop.json) ----------------------------------------

# ---- unlocks ---------------------------------------------------------------

const AUTOMATION := "automation"  # lets you send swarms that follow your rules
const PARTIES := "parties"  # feature: send small parties (see PARTY_SIZES)


## Party sizes the finds open: the cart, the wheelbarrow, the hay wagon (data/unlocks.json).
const PARTY_SIZES := [["parties", 3], ["parties_5", 5], ["parties_10", 10]]


## Debug: a completely fresh game, as a new player would start it. The old save is copied to
## user://save-before-new-game-<time>.json first, so it can be put back by hand.
func debug_new_game() -> void:
	save_game(true)
	var backup := DevProfile.path("save-before-new-game-%d.json" % int(Time.get_unix_time_from_system()))
	DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup))
	coins = 100
	xp = 0
	hunger = 70.0
	happiness = 70.0
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
	workshop = Workshop.fresh(catalog)
	postcards.clear()
	watching = null
	_to_work.clear()
	errand_tools = {}
	scout_notes = 0
	gear = {}
	stickers.clear()
	_boosts_changed()
	room = 0
	edge = Edge.fresh()
	school = School.fresh()
	school_changed_boost()
	wish = Wish.fresh()
	_roller.wish = {}
	_crews_changed()
	pinned.clear()
	join_up_to = ""
	rummaged.clear()
	machine = { "pulls": 0, "lit": 0, "bought": {}, "globes": [Machine.first_globe(catalog)], "greeted": [Machine.first_globe(catalog)] }
	fever_until = 0.0
	toys = Toys.fresh()
	_knacks_changed()
	gifts = Gifts.fresh()
	bits = {}
	wisps = 0
	plushie = Plushie.fresh()
	automation = Automation.fresh()
	dungeon = Dungeon.fresh(catalog)
	dungeon_news = {}
	dungeon_report = {}
	sewing = Sewing.fresh()
	sew_seats = {}
	sew_seats_room = -1
	sew_last = {}
	perks = {}
	collection.keep_uids.clear()
	whistle_seen()
	_auto_at = 0.0
	_boxes_at = 0.0
	_crew_speeds.clear()
	_crew_tips.clear()
	_worker_of.clear()
	_worker_speed.clear()
	visited.clear()
	visits.clear()
	sent.clear()
	find_tries.clear()
	unshown_ours.clear()
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
	_check_care()
	_knacks_changed()  # after load_from: uids start over at 1
	collection.active_changed.emit(collection.active())
	save_game()
	new_game.emit()
	adventures_changed.emit()
	changed.emit()


# ---- your pet at work ----------------------------------------------------------

# ---- who's resting: not your active pet, not away on an adventure, not on an errand or working ----

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

# ---- automation: your pet does one job for you, see Automation and data/automation.json ----

const PET_CRANK_ROLLS := 200  # past this many pulls at once (back from being away) the rest pay like these


# ---- workers: the other pets, once your pet has taught them a job ----

var _worker_of := {}  # uid -> job id, for every pet working as a worker
var _worker_speed := {}  # job id -> its workers' speeds added up (see Automation.worker_speed)


# ---- the whistle: your pet manages the workers (Automation.whistle_plan) ----

var whistle_since := { "hauled": {}, "put": 0 }  # what the whistle did since you last looked (not saved)


# ---- the dungeon: the old well, all the way down (see Dungeon, data/dungeon.json) ----------

# ---- held landings: crowds holding every 10th landing (see Dungeon.hold_need, data "hold") ----

# ---- E3 the sewing room, off the well's floor 20 (see Sewing, data/sewing.json) ----------

# ---- the wisps perk tree on the well wall (see Perks, data/perks.json) -----------------

# ---- keep lines: the sorting card keeps pets as cards (see Sewing) --------------------

# ---- the plushie machine (F1/F2, see Plushie) --------------------------------

# ---- grafting ----------------------------------------------------------------

## Sews a part from the inventory onto your active pet (see Grafting), with `buttons` buttons on it
## (a part that came off a pet with buttons). Returns { ok, old }, or {}.
func sew_part(slot: String, part_id: String, buttons := 0) -> Dictionary:
	var pet := collection.active()
	var was := pet.rarity if pet else ""
	var result := Grafting.sew(pet, slot, part_id, parts, _rng, catalog, buttons)
	if result.is_empty():
		return result
	if pet.rarity != was:  # a pet is as rare as its rarest part: it moved shelves
		collection.retier(pet, was)
	collection.pet_changed.emit(pet)
	collection.active_changed.emit(pet)  # everything showing your pet redraws it
	changed.emit()
	save_game()
	return result


# ---- tutorial ----------------------------------------------------------------

# ---- past the edge and the little school: pets spent for good (C2) ----------------------

const DESK_FACES := 2000000  # school faces past this sit at the desks


## A face for the school, `n` of a count: stand-in numbers of live pets only ever count up from 0,
## so these count down from -1 and never share a look (or a cached Pet) with one.
static func school_face(k: String, n: int) -> String:
	return Herd.uid(k, -1 - n)


# ---- adventures -------------------------------------------------------------

# ---- the trail (clicking along a trip yourself) -----------------------------------

const XP_SPOTTED := 10  # xp for a pet spotting a new place
const XP_FIND := 25  # xp for bringing home a special find
const TREAT_SPEED := 3.0  # how many times as fast they walk while they zoom
const TRAIL_COINS := [0.2, 0.5]  # a coin pickup is worth this times the place's loot (garden: about 1)


## A coin amount worked out as a float, rounded and kept under COINS_MAX: past int's top it would
## wrap round to minus coins.
static func coins_int(f: float) -> int:
	return roundi(clampf(f, -float(COINS_MAX), float(COINS_MAX)))


# ---- presents ---------------------------------------------------------------

## Presents in the pocket, waiting for you to open them.
func gifts_waiting() -> int:
	return int(gifts.pocket)


## Whether presents come yet: from when the boxes tab opens (hidden until then).
func gifts_open() -> bool:
	return tab_open("boxes")


## Moves the present clock on to `now` (every second while open, and once on load for the time
## closed: the same either way). `save`: save when one came in.
func _tick_gifts(now: float, save := true) -> void:
	var started := float(gifts.next_at) > 0.0
	var added := Gifts.tick(gifts, catalog.gifts, now, gifts_open())
	if added > 0 or started != (float(gifts.next_at) > 0.0):
		gifts_changed.emit()
		if save:
			save_game()


## Opens a present from the pocket: it's rolled now, so the box is your newest tier today. Boxes go
## on your pile; a toy capsule goes into your toys, the way the machine gives one. Never bits, never
## a pet. Returns { box, boxes, toy: { id, finish, new } or {} }, or {} when the pocket is empty.
func open_gift() -> Dictionary:
	if gifts_waiting() <= 0:
		return {}
	gifts.pocket = gifts_waiting() - 1
	var toys_open := _machine_gives("toy")
	var got := Gifts.roll(catalog.gifts, _rng, toys_open)
	if debug_gift_roll != "" and OS.is_debug_build():
		got = { "boxes": 2 if debug_gift_roll == "two" else 1, "toy": debug_gift_roll == "toy" and toys_open }
		debug_gift_roll = ""
	var box := newest_box_id()
	var toy := {}
	if got.toy:
		var t := Toys.roll(catalog, _rng, boost("luck"), Machine.toy_sets(machine, catalog))  # only sets whose hatch is open
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(toys, t.id, t.finish) }
		toys_changed.emit()
	grant({ "box:" + box: int(got.boxes) })  # checks unlocks (a first toy) and emits changed
	gifts_changed.emit()
	save_game()
	return { "box": box, "boxes": int(got.boxes), "toy": toy }


## Debug: n presents in the pocket now (up to the pocket's size), the clock started.
func debug_set_gifts(n: int) -> void:
	gifts.pocket = clampi(n, 0, Gifts.cap(catalog.gifts))
	if float(gifts.next_at) <= 0.0:
		gifts.next_at = Time.get_unix_time_from_system() + Gifts.every(catalog.gifts)
	gifts_changed.emit()


## Debug: the present clock moves `hours` on (to check the step and the pocket's size).
func debug_gift_clock(hours: float) -> void:
	if float(gifts.next_at) > 0.0:
		gifts.next_at = float(gifts.next_at) - hours * 3600.0
	_tick_gifts(Time.get_unix_time_from_system())


# ---- care -----------------------------------------------------------------

## Coins a snack (the feed button) costs now: data/care.json "snack" capsules at what a plain capsule
## is worth, so it grows with the machine.
func snack_price() -> int:
	return Care.snack_price(catalog, capsule_value())


## Gives your pet a snack, if it has room for one and you can pay. Returns whether it ate.
func feed() -> bool:
	var price := snack_price()
	var snack: Dictionary = catalog.care.get("snack", {})
	if coins < price or hunger >= float(snack.get("full_at", 99)):
		return false
	coins -= price
	hunger = minf(100.0, hunger + float(snack.get("food", 30)))
	happiness = minf(100.0, happiness + float(snack.get("mood", 5)))
	_check_care()
	changed.emit()
	return true


## A pat: mood goes up, at most once every data/care.json pat.every seconds (a pat in between is
## still a pat, just no mood).
func pat() -> void:
	var p: Dictionary = catalog.care.get("pat", {})
	var now := Time.get_unix_time_from_system()
	if now - _pat_at < float(p.get("every", 0)):
		return
	_pat_at = now
	happiness = minf(100.0, happiness + float(p.get("mood", 8)))
	_check_care()
	changed.emit()


## Sets food and mood (the dev step `care`), kept between the floor and 100.
func set_care(food: float, mood: float) -> void:
	hunger = clampf(food, Care.floor_value(catalog), 100.0)
	happiness = clampf(mood, Care.floor_value(catalog), 100.0)
	_check_care()
	changed.emit()


## Food or mood moved: when a care buff turned on or off, the boosts it's on are worked out again.
func _check_care() -> void:
	var now := Care.on_ids(catalog, hunger, happiness)
	if now == _care_on:
		return
	_care_on = now
	_forget_care_boosts()
	if not _loading:
		changed.emit()


## The kept totals of the kinds care boosts go stale (a buff turned on or off, or time away began
## or ended).
func _forget_care_boosts() -> void:
	for b in catalog.care.get("buffs", []):
		_boosts.erase(str(b.kind))


## Does `work` for time the computer slept without the care buffs: like food and mood, they only
## count while the game is open (time closed is the same: boost_parts leaves them out while loading).
func _without_care(work: Callable) -> void:
	_away = true
	_forget_care_boosts()
	work.call()
	_away = false
	_forget_care_boosts()


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

# ---- the wishing jar (see Wish, data/wish.json) ----------------------------------

# ---- gear: upgrades to adventuring, bought with xp (see Gear, data/gear.json) ----

# ---- capsule toys ------------------------------------------------------------------

static func _without(loot: Dictionary, key: String) -> Dictionary:
	var out := loot.duplicate()
	out.erase(key)
	return out


func set_pet_out(value: bool) -> void:
	pet_out = value
	changed.emit()


# ---- saving ---------------------------------------------------------------

## `wait`: written before this returns (quitting); otherwise the running game writes it on a worker
## thread (late in the game a save is megabytes of JSON, ~300 ms).
func save_game(wait := false) -> void:
	if not _can_save:
		return
	if _hold_saves:  # automation is working through a tick (or loading): the next autosave has it
		return
	var data := {
		"version": SAVE_VERSION,
		"coins": coins,
		"xp": xp,
		"hunger": hunger,
		"happiness": happiness,
		"pet_out": pet_out,
		"collection": collection.to_dict(true),
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
		"workshop": workshop,
		"errand_tools": errand_tools,
		"scout_notes": scout_notes,
		"gear": gear,
		"stickers": stickers,
		"room": room,
		"edge": edge,
		"school": school,
		"wish": wish,
		"automation": automation,
		"dungeon": dungeon,
		"wisps": wisps,
		"reserve_capsules": reserve_capsules,
		"sewing": sewing,
		"perks": perks,
		"saved_boxes": saved_boxes.keys(),
		"boxes_bought": boxes_bought,
		"boxes_greeted": boxes_greeted.keys(),
		"visited": visited.keys(),
		"visits": visits,
		"sent": sent,
		"find_tries": find_tries,
		"buying_on": buying_on,
		"pinned": pinned,
		"join_up_to": join_up_to,
		"rummaged": rummaged,
		"machine": machine,
		"toys": toys,
		"gifts": gifts,
		"bits": bits,
		"plushie": plushie,
		"started_at": started_at,
		"milestones": milestones,
		"idle_log": idle_log,
		"runs": runs.map(func(r): return r.to_dict()),
		"saved_at": Time.get_unix_time_from_system(),
	}
	_finish_save()  # one write at a time, in order
	if wait or not is_inside_tree():  # GameStates made by tests and tools write straight away
		SaveFile.write(save_path, data)
		return
	# the worker thread must not read anything the game keeps changing: everything but the
	# collection (already copies, see Collection.to_dict) is copied here
	var pets: Dictionary = data.collection
	data.erase("collection")
	data = data.duplicate(true)
	data.collection = pets
	var path := save_path
	_save_task = WorkerThreadPool.add_task(func(): SaveFile.write(path, data), false, "save")


## Waits for a save still being written on its worker thread.
func _finish_save() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1


## Loads the save. Returns false if there's none yet (a brand new player).
func load_game() -> bool:
	_finish_save()
	_loading = true
	var loaded := _load_save()
	_loading = false
	_forget_care_boosts()  # totals kept while loading left the care buffs out (time closed)
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
	wish = Wish.clean(catalog, data.get("wish", {}))  # v38: older saves start with an empty jar
	_roller.wish = Wish.weights(catalog, wish)
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
		if Grafting.valid_key(str(key), catalog) and int(saved_parts[key]) > 0:  # "slot:id", or "slot:id@n" with buttons (v24)
			parts[str(key)] = int(saved_parts[key])
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
			if not raw.has("parts_on"):  # saved before runs kept it: parts are open or not right now
				run.parts = feature_on("parts")
			runs.append(run)

	# the dungeon before the jobs: its army's pets aren't on errands
	wisps = maxi(0, int(data.get("wisps", 0)))  # v33 added the dungeon (and its wisps), v34 the plushie machine (same purse)
	dungeon = Dungeon.clean(catalog, data.get("dungeon", {}))
	sewing = Sewing.clean(data.get("sewing", {}))  # v35 added the sewing room
	perks = Perks.clean(catalog, data.get("perks", {}))  # v36 added the wisps perks (the entrance moved in)
	if from_version < 35 and int(dungeon.deep) >= int(catalog.sewing.get("door_floor", 20)):
		finds["little_key"] = true  # been past floor 20 already: the key was found there
	var trips := away()
	dungeon.cards = dungeon.cards.filter(func(uid): return collection.get_pet(uid) != null and uid != collection.active_uid \
		and not Herd.is_stand_in(uid) and not trips.has(uid))
	_rest_changed()
	jobs.clear()
	var on_trips := _out()
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
	homes = NewHomes.clean(catalog, data.get("new_homes", {}))  # v28 added new homes (v35: its keep lines)
	_keep_lines_changed()
	errand_tools = {}
	_tools_changed()
	var saved_tools: Dictionary = data.get("errand_tools", {})
	for id in saved_tools:
		if not Jobs.tool(catalog, str(id)).is_empty():
			errand_tools[str(id)] = maxi(0, int(saved_tools[id]))
	scout_notes = clampi(int(data.get("scout_notes", 0)), 0, scout_hold())  # v23
	_crews_changed()
	gear = Gear.clean(catalog, data.get("gear", {}))  # v22 added gear: older saves start with none
	room = maxi(0, int(data.get("room", 0)))  # v28 added the room (v40: steps built on the house card)
	if from_version < 28:
		# a save from before the room that already had more pets gets room for them (and a bit more),
		# so boxes and box jobs keep opening (before the catch-up below: box workers open boxes there)
		var margin := float(catalog.herd.get("room", {}).get("old_save_margin", 0.1))
		room = maxi(room, Herd.room_level_for(catalog, ceili(collection.plain_count() * (1.0 + margin))))
	edge = Edge.clean(catalog, data.get("edge", {}))  # v32 added the edge and the school
	school = School.clean(catalog, data.get("school", {}))
	school_changed_boost()
	var stood := School.trim(catalog, school)  # never more in a class than its seats: the rest go back
	for k in stood:
		collection.add_plain(k, int(stood[k]))
	_load_automation(data.get("automation", {}))
	reserve_capsules = clampi(int(data.get("reserve_capsules", default_reserve())), 0, reserve_max())  # v25
	_hold_saves = true  # no saving halfway through loading
	_clamp_herd_places()
	_hold_saves = false
	visited.clear()
	for id in data.get("visited", []):
		visited[str(id)] = true
	if not data.has("visited"):
		# from before places glowed: everywhere already open counts as visited
		for location in catalog.locations:
			if location_open(location):
				visited[location.id] = true
	visits.clear()
	unshown_ours.clear()
	var saved_visits: Dictionary = data.get("visits", {})
	for id in saved_visits:
		if not catalog.location(str(id)).is_empty():
			visits[str(id)] = maxi(0, int(saved_visits[id]))
	sent.clear()
	if data.has("sent"):
		var saved_sent: Dictionary = data.sent
		for id in saved_sent:
			if not catalog.location(str(id)).is_empty():
				sent[str(id)] = maxi(0, int(saved_sent[id]))
	else:
		# from before pets sent were counted: every trip welcomed back had at least one pet, and the
		# parties still out count in full
		for id in visits:
			sent[id] = int(visits[id])
		for run in runs:
			sent[run.location_id] = sent_to(run.location_id) + run.party.setting_out()
	find_tries.clear()
	var saved_find_tries: Dictionary = data.get("find_tries", {})  # v43 added them
	for id in saved_find_tries:
		if catalog.finds.has(str(id)):
			find_tries[str(id)] = maxi(0, int(saved_find_tries[id]))
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
	join_up_to = str(data.get("join_up_to", ""))
	if join_up_to != "" and not catalog.tiers.any(func(t): return t.id == join_up_to):
		join_up_to = ""
	if pinned.size() > PINNED_MAX:  # older saves kept every unseen good pull (the refold below folds the rest)
		pinned = pinned.slice(pinned.size() - PINNED_MAX)
	idle_log = data.get("idle_log", {})
	rummaged.clear()
	var saved_rummage: Dictionary = data.get("rummaged", {})
	for id in saved_rummage:
		if not catalog.rummage_spot(str(id)).is_empty():
			rummaged[str(id)] = float(saved_rummage[id])
	var saved_machine: Dictionary = data.get("machine", {})
	machine = { "pulls": int(saved_machine.get("pulls", 0)), "lit": int(saved_machine.get("lit", 0)), "bought": {},
		"pet_wait": int(saved_machine.get("pet_wait", 0)), "globes": [], "greeted": [] }
	# globes you have (unknown ones dropped; the first is always there) and the ones already shown arriving
	var first := Machine.first_globe(catalog)
	for g in [first] + Array(saved_machine.get("globes", [first])):
		if Machine.globe_rank(catalog, str(g)) >= 0 and not machine.globes.has(str(g)):
			machine.globes.append(str(g))
	for g in saved_machine.get("greeted", machine.globes):
		if machine.globes.has(str(g)) and not machine.greeted.has(str(g)):
			machine.greeted.append(str(g))
	if not machine.greeted.has(first):
		machine.greeted.append(first)
	var saved_bought: Dictionary = saved_machine.get("bought", {})
	for id in saved_bought:
		if not Machine.node(catalog, str(id)).is_empty():
			machine.bought[str(id)] = int(saved_bought[id])
	for id in finds:  # a globe's find that came home without it (any save): it's home now
		if Machine.globe_for_find(catalog, str(id)) != "" and not machine.globes.has(Machine.globe_for_find(catalog, str(id))):
			machine.globes.append(Machine.globe_for_find(catalog, str(id)))
	bits = {}
	var saved_bits: Dictionary = data.get("bits", {})
	for b in saved_bits:
		bits[str(b)] = maxi(0, int(saved_bits[b]))
	plushie = Plushie.clean(data.get("plushie", {}), catalog)
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
				"spares": maxi(0, int(e.get("spares", 0))), "wear": clampf(float(e.get("wear", 0.0)), 0.0, 1.0),
				"stars": maxi(0, int(e.get("stars", 0))) }  # v42 added stars (shining a favourite)
	for p in saved_toys.get("playing", []):
		if p is Dictionary and toys.owned.has(str(p.get("key", ""))):
			toys.playing.append({ "key": str(p.key), "until": float(p.get("until", 0.0)), "wear": float(p.get("wear", 0.0)),
				"play": str(p.get("play", "")), "again": bool(p.get("again", true)) })  # v39 added the play's length (the toy shelf)
	workshop = Workshop.clean(catalog, data.get("workshop", {}))  # v39 added the shed workshop
	postcards.clear()
	watching = null
	_finish_plays(Time.get_unix_time_from_system())  # plays that ended while the game was closed
	# the sewing basket kept stitching while the game was closed
	_mend_at = Time.get_unix_time_from_system()
	_mend_acc = 0.0
	if Workshop.has(workshop, "basket"):
		var closed_for := minf(maxf(0.0, _mend_at - float(data.get("saved_at", _mend_at))), OFFLINE_CAP)
		Toys.mend(toys, float(catalog.workshop.get("basket_mend_per_hour", 0.0)) * closed_for / 3600.0, _mend_at)
	gifts = Gifts.clean(data.get("gifts", {}), catalog.gifts)  # v29: older saves start the clock below
	_knacks_changed()
	if from_version >= 15 and from_version < 20:
		_regate()
		if knows_job("boxes"):  # it had the cushion: opening boxes stays (now in the automation tab)
			unlocks["feature:packs"] = true
			unlocks["tab:automation"] = true
	# food and mood stay as they were while the game was closed (they only go down while it's open);
	# the kitchen's meals made while you were away top them up to its line from there. The buffs
	# don't count for time closed (boost_parts leaves them out while loading).
	_check_care()
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
	_auto_at = Time.get_unix_time_from_system()
	_boxes_at = _auto_at
	# presents came while the game was closed, the same as if it had been open (only the clock counts)
	_tick_gifts(Time.get_unix_time_from_system(), false)
	# the music box: your pet kept leading the army while the game was closed, for up to its hours
	_hold_saves = true
	_army_while_away(float(data.get("saved_at", 0.0)), Time.get_unix_time_from_system())
	_hold_saves = false

	# v28: plain pets fold into the herd (old saves: crews and workers of uids become counts here)
	_rest_changed()
	collection.refold()
	if from_version < 28 and room_is_full() and not homes.room_was_full:
		# new homes came in v28: a room that's full already has been full, the stall is there
		homes.room_was_full = true
		check_unlocks()
	if from_version < 35 and finds.has("little_key") and not is_unlocked("feature:sewing"):
		check_unlocks()  # v35: the key found before the sewing room was built opens its door
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
	# v29 added presents (gifts): nothing to convert; saves with the boxes tab open start the clock
	# on load (built as v25 in the care lane)
	# v30 added machine globes (machine.globes, machine.greeted): load_game gives an older save just
	# the first globe, already seen (built as v24 in the globes lane)
	if version < 31 and not data.has("visits"):
		# v31 counts visits per place (next door's lights, places becoming ours): every place
		# already visited counts once (built as v24 in the nextdoor lane)
		data.visits = Ours.visits_from(data.get("visited", []))
	# v32: past the edge and the little school; older saves start with neither (Edge.clean,
	# School.clean in load_game; built as v24 in the edge lane)
	# v34 (built as v24 in the plushie lane): the plushie machine (its state, wisps, buttons on
	# pets, bag keys "slot:id@n"); older saves have none of it and load an empty machine. Wisps
	# the dungeon paid (v33) stay: it's the one purse.
	# v35 (built as v27 in the sewing lane): the sewing room (its state, keep lines on the sorting
	# rule, room runs in the dungeon's run); nothing moves: older saves start with none of it
	# (load_game: past floor 20 already = the key)
	if version < 7:
		# v7: dungeon places open one rumour at a time; saves that had the dungeons keep them all
		var had: Array = data.get("unlocks", [])
		if "type:dungeon" in had:
			data.unlocks = had + ["location:cellar", "location:below"]
			data.heard = ["well", "cellar", "below"]
	if version < 33:
		# v33 (built as v24 in the dungeon lane): the well line is one dungeon. The cellar and further down stop being trips and become
		# bands of it; a save that had them open has those bands already (the unlocks stay). Rumours
		# waiting about them go, and parties going there go to the well instead (trips already out
		# there come home as usual).
		var had: Array = data.get("unlocks", [])
		var dg: Dictionary = data.get("dungeon", {}) if data.get("dungeon", {}) is Dictionary else {}
		var bands: Array = [str(Catalog.shared().dungeon.bands[0].id)]
		var band_places: Array[String] = []
		for b in Catalog.shared().dungeon.bands:
			var place := str(b.get("place", ""))
			if place != "" and ("location:" + place) in had and not str(b.id) in bands:
				bands.append(str(b.id))
		for l in Catalog.shared().locations:
			if l.has("band"):
				band_places.append(str(l.id))
		dg["bands"] = bands
		data.dungeon = dg
		data.rumours = data.get("rumours", []).filter(func(id): return not str(id) in band_places)
		var a = data.get("automation", {})
		if a is Dictionary:
			var parties: Array = [a.get("party", {})] + a.get("parties", [])
			for p in parties:
				if p is Dictionary and str(p.get("place", "")) in band_places:
					p.place = str(Catalog.shared().dungeon.bands[0].get("place", "well"))
	if version < 36:
		# v36 (built as v28 in the sewing lane): the wisps perk tree. The entrance's level moves out
		# of the dungeon into the perks.
		var dg = data.get("dungeon", {})
		if dg is Dictionary and int(dg.get("entrance", 0)) > 0:
			var pk = data.get("perks", {})
			if not pk is Dictionary:
				pk = {}
			pk["entrance"] = int(dg.entrance)
			data.perks = pk
		if dg is Dictionary:
			dg.erase("entrance")
	if version < 37:
		# v37 (built as v29 in the sewing lane): held landings. Older saves hold none and start from
		# the top.
		var dg = data.get("dungeon", {})
		if dg is Dictionary:
			dg["held"] = {}
			dg["start"] = 0
	if version < 38:
		data.wish = Wish.fresh()  # v38 (built as v26 in the wish lane): the wishing jar; older saves start with nothing wished for
	# v39 (built as v27 in the workshop lane): the shed workshop. Nothing to convert here: load_game's
	# Workshop.clean gives older saves a fresh one (the first 3 drawings pinned, nothing built), and
	# toys being played with load without a play length (the toy shelf doesn't hand those again)
	if version >= 28 and version < 40 and data.has("room"):
		# v40 (built as v27 in the house lane): the room grows in named steps (the house card) instead
		# of levels of 500 x 1.5^L: an old level becomes the fewest steps that hold at least as much,
		# so nobody loses room (a big old room can land on a squeeze-in step: kept, for free)
		var level := maxi(0, int(data.get("room", 0)))
		var old_cap := maxi(50, roundi(minf(500.0 * pow(1.5, level), 1.0e15) / 50.0) * 50)
		data.room = Herd.room_level_for(catalog, old_cap)
	data.version = SAVE_VERSION
	return data


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_finish_save()  # even if this save can't go ahead, the one on its way gets written
		save_game(true)


# ---- forwarders: the parts' functions, so GameState.<name>() works as before (tools/state_parts.py writes this block) ----

# adventures_part.gd
func debug_give_parts() -> void: adventures_part.debug_give_parts()
func away() -> Dictionary: return adventures_part.away()
func sendable_pets() -> Array[Pet]: return adventures_part.sendable_pets()
func _sendable_stand_ins(gone: Dictionary) -> Array[Pet]: return adventures_part._sendable_stand_ins(gone)
func send_on_adventure(location_id: String, pets: Array[Pet], by_you := true) -> RunState: return adventures_part.send_on_adventure(location_id, pets, by_you)
func answer_event(run: RunState, option_index: int) -> void: adventures_part.answer_event(run, option_index)
func collect_run(run: RunState) -> Dictionary: return adventures_part.collect_run(run)
func toss_treat(run: RunState) -> bool: return adventures_part.toss_treat(run)
func treat_every(run: RunState) -> float: return adventures_part.treat_every(run)
func treat_zoom(run: RunState) -> float: return adventures_part.treat_zoom(run)
func streak_max(run: RunState) -> float: return adventures_part.streak_max(run)
func trail_part_x(run: RunState) -> float: return adventures_part.trail_part_x(run)
func treat_ready_in(run: RunState) -> float: return adventures_part.treat_ready_in(run)
func zooming(run: RunState) -> bool: return adventures_part.zooming(run)
func _zoom_runs(delta: float) -> void: adventures_part._zoom_runs(delta)
func trail_pickup(run: RunState, kind: String, bonus := 1.0) -> Dictionary: return adventures_part.trail_pickup(run, kind, bonus)
func keep_trail_part(run: RunState, key: String) -> void: adventures_part.keep_trail_part(run, key)
func _advance_runs() -> void: adventures_part._advance_runs()
func _advance(run: RunState) -> bool: return adventures_part._advance(run)
func debug_finish_runs() -> void: adventures_part.debug_finish_runs()

# automation_part.gd
func auto_jobs() -> Array[Dictionary]: return automation_part.auto_jobs()
func knows_job(id: String) -> bool: return automation_part.knows_job(id)
func teach_job(id: String) -> bool: return automation_part.teach_job(id)
func set_task(id: String) -> void: automation_part.set_task(id)
func auto_tool_block(id: String) -> String: return automation_part.auto_tool_block(id)
func auto_tool_cost(id: String) -> int: return automation_part.auto_tool_cost(id)
func buy_auto_tool(id: String) -> bool: return automation_part.buy_auto_tool(id)
func auto_party(slot := -1) -> Dictionary: return automation_part.auto_party(slot)
func set_auto_party(place: String, n: int, slot := -1) -> void: automation_part.set_auto_party(place, n, slot)
func auto_places() -> Array[Dictionary]: return automation_part.auto_places()
func auto_run(slot := -1) -> RunState: return automation_part.auto_run(slot)
func _work_automation(until: float, part := "") -> void: automation_part._work_automation(until, part)
func _release_saves() -> void: automation_part._release_saves()
func _work_for_automation(seconds: float, show: bool, boxes := true, rest := true) -> void: automation_part._work_for_automation(seconds, show, boxes, rest)
func _auto_adventures() -> void: automation_part._auto_adventures()
func _pet_cranks(pulls: int, show := true) -> Dictionary: return automation_part._pet_cranks(pulls, show)
func _pet_capsule(ctx: Dictionary) -> Dictionary: return automation_part._pet_capsule(ctx)
func _crank_context() -> Dictionary: return automation_part._crank_context()
func _load_automation(saved: Dictionary) -> void: automation_part._load_automation(saved)

# boosts_part.gd
func grant(loot: Dictionary, boosted := true) -> void: boosts_part.grant(loot, boosted)
func grant_wisps(n: int, quiet := false) -> void: boosts_part.grant_wisps(n, quiet)
func boost(kind: String) -> float: return boosts_part.boost(kind)
func boost_parts(kind: String) -> Array[Dictionary]: return boosts_part.boost_parts(kind)
func boost_receipt() -> Array: return boosts_part.boost_receipt()
func _boost_line_name(part: Dictionary) -> String: return boosts_part._boost_line_name(part)
func capsule_why() -> Dictionary: return boosts_part.capsule_why()
func errands_why() -> Dictionary: return boosts_part.errands_why()
func _errands_layered(with_tools: bool, with_goals: bool, with_tips: bool, with_boost := false) -> float: return boosts_part._errands_layered(with_tools, with_goals, with_tips, with_boost)
func _boosts_changed() -> void: boosts_part._boosts_changed()
func _knacks_changed() -> void: boosts_part._knacks_changed()
func _knack_gates_changed() -> void: boosts_part._knack_gates_changed()
func _knack_counting(kind: String) -> Dictionary: return boosts_part._knack_counting(kind)
func knack_own(pet: Pet, kind: String) -> float: return boosts_part.knack_own(pet, kind)
func knack_gate(gate: String) -> bool: return boosts_part.knack_gate(gate)
func knacks_of(pet: Pet) -> Array[Dictionary]: return boosts_part.knacks_of(pet)
func trip_knacks(pets: Array) -> Dictionary: return boosts_part.trip_knacks(pets)
func check_book() -> void: boosts_part.check_book()
func add_xp(amount: int) -> int: return boosts_part.add_xp(amount)

# boxes_part.gd
func set_job(job: String, on: bool) -> void: boxes_part.set_job(job, on)
func coin_reserve() -> int: return boxes_part.coin_reserve()
func default_reserve() -> int: return boxes_part.default_reserve()
func reserve_step() -> int: return boxes_part.reserve_step()
func reserve_max() -> int: return boxes_part.reserve_max()
func set_reserve(capsules: int) -> void: boxes_part.set_reserve(capsules)
func box_price(box_id: String, count := 1) -> int: return boxes_part.box_price(box_id, count)
func shop_boxes() -> Array[Dictionary]: return boxes_part.shop_boxes()
func book_rank() -> int: return boxes_part.book_rank()
func box_in_shop(box_id: String) -> bool: return boxes_part.box_in_shop(box_id)
func stash_boxes() -> Array[Dictionary]: return boxes_part.stash_boxes()
func box_is_new(box_id: String) -> bool: return boxes_part.box_is_new(box_id)
func box_news() -> bool: return boxes_part.box_news()
func greet_box(box_id: String) -> void: boxes_part.greet_box(box_id)
func buy_boxes(box_id: String, count := 1) -> bool: return boxes_part.buy_boxes(box_id, count)
func debug_give_box(box_id: String) -> void: boxes_part.debug_give_box(box_id)
func coins_short(box_id: String, count := 1) -> int: return boxes_part.coins_short(box_id, count)
func open_boxes(box_id: String, count := 1, force_tier := "", by_pet := false) -> Array[Pet]: return boxes_part.open_boxes(box_id, count, force_tier, by_pet)
func in_bag(box_id: String) -> int: return boxes_part.in_bag(box_id)
func boxes_that_fit(box_id: String) -> int: return boxes_part.boxes_that_fit(box_id)
func debug_give_pets(count: int) -> void: boxes_part.debug_give_pets(count)
func add_debug_coins() -> void: boxes_part.add_debug_coins()
func _give_first_pet() -> void: boxes_part._give_first_pet()
func pet_opens(box_id: String) -> bool: return boxes_part.pet_opens(box_id)
func save_for_me(box_id: String, on: bool) -> void: boxes_part.save_for_me(box_id, on)
func next_pet_box() -> String: return boxes_part.next_pet_box()
func pet_box_order() -> Array: return boxes_part.pet_box_order()
func boxes_on_pile() -> int: return boxes_part.boxes_on_pile()
func can_auto_open() -> bool: return boxes_part.can_auto_open()
func pack_job_seen() -> void: boxes_part.pack_job_seen()
func _open_in_background(delta: float) -> void: boxes_part._open_in_background(delta)
func background_packing() -> float: return boxes_part.background_packing()
func auto_open_pack() -> Pet: return boxes_part.auto_open_pack()
func _pin(uids: Array[String]) -> void: boxes_part._pin(uids)
func is_good_pull(pet: Pet) -> bool: return boxes_part.is_good_pull(pet)
func dismiss_pinned(uid := "") -> void: boxes_part.dismiss_pinned(uid)
func take_idle_log() -> Dictionary: return boxes_part.take_idle_log()
func _log_idle(add: Dictionary) -> void: boxes_part._log_idle(add)
func newest_box_id() -> String: return boxes_part.newest_box_id()

# dungeon_part.gd
func take_dungeon_news() -> Dictionary: return dungeon_part.take_dungeon_news()
func dungeon_open() -> bool: return dungeon_part.dungeon_open()
func dungeon_running() -> bool: return dungeon_part.dungeon_running()
func _out() -> Dictionary: return dungeon_part._out()
func _army_herd(used: Dictionary) -> Dictionary: return dungeon_part._army_herd(used)
func army_herd_keys() -> Dictionary: return dungeon_part.army_herd_keys()
func army_power_of(pet: Pet) -> float: return dungeon_part.army_power_of(pet)
func army_cards() -> Array[Pet]: return dungeon_part.army_cards()
func army_choices() -> Array[Pet]: return dungeon_part.army_choices()
func _strongest_first(pets: Array[Pet]) -> Array[Pet]: return dungeon_part._strongest_first(pets)
func army() -> Dictionary: return dungeon_part.army()
func army_herd_room(rarity: String) -> int: return dungeon_part.army_herd_room(rarity)
func set_army_card(uid: String, on: bool) -> bool: return dungeon_part.set_army_card(uid, on)
func army_best() -> void: dungeon_part.army_best()
func set_army_herd(rarity: String, n: int) -> void: dungeon_part.set_army_herd(rarity, n)
func army_fill_up() -> void: dungeon_part.army_fill_up()
func army_empty() -> void: dungeon_part.army_empty()
func _off_work(uids: Array) -> void: dungeon_part._off_work(uids)
func _trim_army_herd() -> void: dungeon_part._trim_army_herd()
func set_order(key: String, step: int) -> void: dungeon_part.set_order(key, step)
func set_order_to(key: String, value) -> bool: return dungeon_part.set_order_to(key, value)
func set_start(f: int) -> bool: return dungeon_part.set_start(f)
func army_rules(a: Dictionary = {}) -> Dictionary: return dungeon_part.army_rules(a)
func _army_rules(cards: Array, herd_keys: Dictionary) -> Dictionary: return dungeon_part._army_rules(cards, herd_keys)
func floor_words(from: int, to: int, rules: Dictionary = {}) -> Dictionary: return dungeon_part.floor_words(from, to, rules)
func send_army(quiet := false, away := false) -> bool: return dungeon_part.send_army(quiet, away)
func dungeon_floor_now() -> float: return dungeon_part.dungeon_floor_now()
func dungeon_left() -> float: return dungeon_part.dungeon_left()
func _dungeon_tick() -> void: dungeon_part._dungeon_tick()
func _finish_dungeon_run(quiet := false) -> void: dungeon_part._finish_dungeon_run(quiet)
func _best_bit(run: Dictionary, firsts: Array[int], deep_before: int, deepest: bool, to: int) -> Dictionary: return dungeon_part._best_bit(run, firsts, deep_before, deepest, to)
func drop_dungeon_report() -> void: dungeon_part.drop_dungeon_report()
func _home_again() -> void: dungeon_part._home_again()
func _run_losses(run: Dictionary) -> int: return dungeon_part._run_losses(run)
func hold_spots() -> Array[int]: return dungeon_part.hold_spots()
func hold_can_go(f: int, rarity: String) -> int: return dungeon_part.hold_can_go(f, rarity)
func hold_room(f: int) -> int: return dungeon_part.hold_room(f)
func hold_faces(f: int, n: int) -> Array: return dungeon_part.hold_faces(f, n)
func send_holders(f: int, rarity: String, n: int) -> int: return dungeon_part.send_holders(f, rarity, n)
func _army_while_away(saved_at: float, now: float) -> int: return dungeon_part._army_while_away(saved_at, now)

# edge_part.gd
func edge_open() -> bool: return edge_part.edge_open()
func edge_torn() -> bool: return edge_part.edge_torn()
func edge_to_go() -> int: return edge_part.edge_to_go()
func edge_done(page_id: String) -> bool: return edge_part.edge_done(page_id)
func resting_shelves() -> Dictionary: return edge_part.resting_shelves()
func send_past_edge(rarity: String, n: int) -> int: return edge_part.send_past_edge(rarity, n)
func _open_edge_pages() -> void: edge_part._open_edge_pages()
func school_open() -> bool: return edge_part.school_open()
func seat_in_school(rarity: String, n: int) -> int: return edge_part.seat_in_school(rarity, n)
func class_full() -> bool: return edge_part.class_full()
func ring_bell() -> bool: return edge_part.ring_bell()
func school_boost() -> float: return edge_part.school_boost()
func school_changed_boost() -> void: edge_part.school_changed_boost()
func pets_a_minute() -> float: return edge_part.pets_a_minute()

# errands_part.gd
func _work_jobs(until: float) -> void: errands_part._work_jobs(until)
func _work_for(seconds: float) -> Dictionary: return errands_part._work_for(seconds)
func scout_hold() -> int: return errands_part.scout_hold()
func scout_full() -> bool: return errands_part.scout_full()
func set_scout_notes(n: int) -> void: errands_part.set_scout_notes(n)
func open_jobs() -> Array[Dictionary]: return errands_part.open_jobs()
func _crew_sum(cache: Dictionary, job_id: String, f: Callable) -> float: return errands_part._crew_sum(cache, job_id, f)
func job_crew(job_id: String) -> Array: return errands_part.job_crew(job_id)
func job_herd(job_id: String) -> Dictionary: return errands_part.job_herd(job_id)
func job_size(job_id: String) -> int: return errands_part.job_size(job_id)
func job_faces(job_id: String, n: int) -> Array: return errands_part.job_faces(job_id, n)
func _job_state(job_id: String) -> Dictionary: return errands_part._job_state(job_id)
func job_of(uid: String) -> String: return errands_part.job_of(uid)
func job_fill(job_id: String) -> float: return errands_part.job_fill(job_id)
func job_fill_now(job_id: String) -> float: return errands_part.job_fill_now(job_id)
func job_rate(job_id: String) -> float: return errands_part.job_rate(job_id)
func _job_errands_x(job_id: String) -> float: return errands_part._job_errands_x(job_id)
func _job_plain_rate(job_id: String, with_tools: bool) -> float: return errands_part._job_plain_rate(job_id, with_tools)
func _job_tool_numbers(job_id: String) -> Array: return errands_part._job_tool_numbers(job_id)
func _kitchen_changed() -> void: errands_part._kitchen_changed()
func kitchen_bonus() -> float: return errands_part.kitchen_bonus()
func capsule_value() -> float: return errands_part.capsule_value()
func job_boost(job_id: String, with_tools := true, with_goals := true, with_tips := true) -> Dictionary: return errands_part.job_boost(job_id, with_tools, with_goals, with_tips)
func job_tips(job_id: String, with_tools := true) -> float: return errands_part.job_tips(job_id, with_tools)
func errands_per_minute() -> float: return errands_part.errands_per_minute()
func errands_per_minute_with(id: String, n: int) -> float: return errands_part.errands_per_minute_with(id, n)
func job_rate_with(job_id: String, id: String, n: int) -> float: return errands_part.job_rate_with(job_id, id, n)
func set_errand_tool_level(id: String, level: int) -> void: errands_part.set_errand_tool_level(id, level)
func _tools_changed() -> void: errands_part._tools_changed()
func errands_away_hours() -> float: return errands_part.errands_away_hours()
func job_level(job_id: String) -> int: return errands_part.job_level(job_id)
func errand_tool_level(id: String) -> int: return errands_part.errand_tool_level(id)
func errand_tool_block(id: String) -> String: return errands_part.errand_tool_block(id)
func errand_tool_plan(id: String, n: int) -> Array: return errands_part.errand_tool_plan(id, n)
func buy_errand_tool(id: String, n := 1) -> int: return errands_part.buy_errand_tool(id, n)
func put_on_job(job_id: String, count := 1, uids: Array = []) -> void: errands_part.put_on_job(job_id, count, uids)
func take_off_job(job_id: String, count := 1, uids: Array = []) -> int: return errands_part.take_off_job(job_id, count, uids)
func share_out() -> void: errands_part.share_out()
func set_job_join(job_id: String, on: bool) -> void: errands_part.set_job_join(job_id, on)
func job_joins(job_id: String) -> bool: return errands_part.job_joins(job_id)
func _auto_place(uids: Array, counts := {}, only: Array = [], by_themselves := false) -> void: errands_part._auto_place(uids, counts, only, by_themselves)
func _take_off(uids: Array) -> Array: return errands_part._take_off(uids)
func _pet_speed(pet: Pet, job: Dictionary) -> float: return errands_part._pet_speed(pet, job)
func _crews_changed(joined: Variant = null) -> void: errands_part._crews_changed(joined)

# gear_part.gd
func gear_level(id: String) -> int: return gear_part.gear_level(id)
func shown_gear() -> Array[Dictionary]: return gear_part.shown_gear()
func gear_block(id: String) -> String: return gear_part.gear_block(id)
func gear_price(id: String) -> int: return gear_part.gear_price(id)
func buy_gear(id: String) -> bool: return gear_part.buy_gear(id)
func set_gear_level(id: String, level: int) -> void: gear_part.set_gear_level(id, level)
func gear_page_open() -> bool: return gear_part.gear_page_open()
func trip_gear(location_id: String) -> Dictionary: return gear_part.trip_gear(location_id)
func _boost_trip_loot(loot: Dictionary, packed := {}, knacks := {}) -> Dictionary: return gear_part._boost_trip_loot(loot, packed, knacks)

# homes_part.gd
func room_cap() -> int: return homes_part.room_cap()
func room_left() -> int: return homes_part.room_left()
func room_is_full() -> bool: return homes_part.room_is_full()
func room_is_cozy() -> bool: return homes_part.room_is_cozy()
func room_price() -> int: return homes_part.room_price()
func room_currency() -> String: return homes_part.room_currency()
func room_next() -> Dictionary: return homes_part.room_next()
func room_split() -> Array: return homes_part.room_split()
func room_shown() -> bool: return homes_part.room_shown()
func buy_room() -> bool: return homes_part.buy_room()
func wisps_shown() -> bool: return homes_part.wisps_shown()
func _room_hit() -> void: homes_part._room_hit()
func homes_open() -> bool: return homes_part.homes_open()
func spare_pick(rarity: String, n := -1, ctx := {}) -> Dictionary: return homes_part.spare_pick(rarity, n, ctx)
func keep_line() -> String: return homes_part.keep_line()
func may_go_finish(finish: String) -> bool: return homes_part.may_go_finish(finish)
func spare_shelves() -> Dictionary: return homes_part.spare_shelves()
func _spare_changed() -> void: homes_part._spare_changed()
func homes_can_go(rarity: String) -> int: return homes_part.homes_can_go(rarity)
func spare_face(rarity: String, salt := 0) -> Pet: return homes_part.spare_face(rarity, salt)
func _take_spare(rarity: String, n: int, keep: int, star: bool) -> Dictionary: return homes_part._take_spare(rarity, n, keep, star)
func send_home(rarity: String, n := 1) -> Dictionary: return homes_part.send_home(rarity, n)
func _sorter() -> Callable: return homes_part._sorter()
func rule_destinations() -> Array[String]: return homes_part.rule_destinations()
func sorted_today() -> int: return homes_part.sorted_today()
func set_rule(key: String, value) -> void: homes_part.set_rule(key, value)
func rule_rarities() -> Array[String]: return homes_part.rule_rarities()
func rule_finishes() -> Array[String]: return homes_part.rule_finishes()
func keep_lines_on() -> bool: return homes_part.keep_lines_on()
func keep_line_count() -> int: return homes_part.keep_line_count()
func keep_lines() -> Array[String]: return homes_part.keep_lines()
func keep_line_options() -> Array[String]: return homes_part.keep_line_options()
func set_keep_line(i: int, pick: String) -> bool: return homes_part.set_keep_line(i, pick)
func kept_count(pick: String) -> int: return homes_part.kept_count(pick)
func _keep_lines_changed() -> void: homes_part._keep_lines_changed()

# machine_part.gd
func globe_news() -> String: return machine_part.globe_news()
func greet_globe(id: String) -> void: machine_part.greet_globe(id)
func _globe_home(find_id: String) -> void: machine_part._globe_home(find_id)
func pull_lever() -> Dictionary: return machine_part.pull_lever()
func _capsule(first: bool, lucky: bool, pay: float, pet_due := false, g := "") -> Dictionary: return machine_part._capsule(first, lucky, pay, pet_due, g)
func machine_odds(lucky := false, first := true) -> Dictionary: return machine_part.machine_odds(lucky, first)
func _machine_prize(id: String) -> Dictionary: return machine_part._machine_prize(id)
func machine_upgrades() -> int: return machine_part.machine_upgrades()
func _machine_gives(kind: String) -> bool: return machine_part._machine_gives(kind)
func capsule_seconds() -> float: return machine_part.capsule_seconds()
func bit_hint(bit: String) -> String: return machine_part.bit_hint(bit)
func fever_left() -> float: return machine_part.fever_left()
func buy_machine_upgrade(id: String) -> bool: return machine_part.buy_machine_upgrade(id)

# perks_part.gd
func perk_level(id: String) -> int: return perks_part.perk_level(id)
func perks_shown() -> Array[String]: return perks_part.perks_shown()
func perk_price(id: String) -> int: return perks_part.perk_price(id)
func perk_available(id: String) -> bool: return perks_part.perk_available(id)
func perks_affordable() -> bool: return perks_part.perks_affordable()
func perk_carrot() -> Dictionary: return perks_part.perk_carrot()
func buy_perk(id: String) -> bool: return perks_part.buy_perk(id)
func debug_perk(id: String, lv: int) -> void: perks_part.debug_perk(id, lv)
func perk_count(name: String) -> float: return perks_part.perk_count(name)
func front_row_size() -> int: return perks_part.front_row_size()
func perk_holds() -> int: return perks_part.perk_holds()
func perk_nudges() -> int: return perks_part.perk_nudges()
func perk_away_hours() -> float: return perks_part.perk_away_hours()

# plushie_part.gd
func plushie_open() -> bool: return plushie_part.plushie_open()
func _plushie_keeper_uid() -> String: return plushie_part._plushie_keeper_uid()
func plushie_keepers() -> Array[Pet]: return plushie_part.plushie_keepers()
func plushie_keeper() -> Pet: return plushie_part.plushie_keeper()
func plushie_can_swap() -> bool: return plushie_part.plushie_can_swap()
func plushie_swap(d: int) -> bool: return plushie_part.plushie_swap(d)
func plushie_herd(rarity: String) -> int: return plushie_part.plushie_herd(rarity)
func plushie_feed_herd(rarity: String) -> bool: return plushie_part.plushie_feed_herd(rarity)
func plushie_cards() -> Array[Pet]: return plushie_part.plushie_cards()
func plushie_has_cards() -> bool: return plushie_part.plushie_has_cards()
func plushie_feed_card(uid: String) -> bool: return plushie_part.plushie_feed_card(uid)
func plushie_spin() -> Dictionary: return plushie_part.plushie_spin()
func plushie_bank(i: int) -> int: return plushie_part.plushie_bank(i)
func plushie_hold(i: int) -> bool: return plushie_part.plushie_hold(i)
func plushie_nudge(i: int) -> String: return plushie_part.plushie_nudge(i)
func plushie_price(what: String) -> int: return plushie_part.plushie_price(what)
func plushie_buy(what: String) -> bool: return plushie_part.plushie_buy(what)
func plushie_wild_step(d: int) -> void: plushie_part.plushie_wild_step(d)
func plushie_odds(i: int) -> Dictionary: return plushie_part.plushie_odds(i)

# rest_part.gd
func _resting() -> Dictionary: return rest_part._resting()
func _rest_changed() -> void: rest_part._rest_changed()
func _herd_used(gone: Dictionary) -> Dictionary: return rest_part._herd_used(gone)
func _stand_ins_out(gone := {}) -> Dictionary: return rest_part._stand_ins_out(gone)
func resting_cards() -> Array[Pet]: return rest_part.resting_cards()
func resting_herd() -> Dictionary: return rest_part.resting_herd()
func resting_count() -> int: return rest_part.resting_count()
func resting_faces(n: int) -> Array: return rest_part.resting_faces(n)
func resting_pets() -> Array[Pet]: return rest_part.resting_pets()
func _resting_stand_ins() -> Array[Pet]: return rest_part._resting_stand_ins()
func spare_count() -> int: return rest_part.spare_count()
func _faces(cards: Array, counts: Dictionary, n: int, salt := 0) -> Array: return rest_part._faces(cards, counts, n, salt)
func herd_faces(counts: Dictionary, n: int, salt := 0) -> Array: return rest_part.herd_faces(counts, n, salt)
func shelf_split(rarity: String) -> Array: return rest_part.shelf_split(rarity)
func _busy_uids() -> Dictionary: return rest_part._busy_uids()
func _on_folded(uids: Array, keys: Array) -> void: rest_part._on_folded(uids, keys)
func _pick(cards: Array, counts: Dictionary, count: int, speed: Callable, best_first: bool) -> Array: return rest_part._pick(cards, counts, count, speed, best_first)
func set_worker_join(id: String, on: bool) -> void: rest_part.set_worker_join(id, on)
func worker_joins(id: String) -> bool: return rest_part.worker_joins(id)
func set_join_up_to(rarity: String) -> void: rest_part.set_join_up_to(rarity)
func any_join() -> bool: return rest_part.any_join()
func _place_new(uids: Array) -> void: rest_part._place_new(uids)
func _herd_at_places(k: String) -> int: return rest_part._herd_at_places(k)
func _herd_off_places(k: String, n: int) -> int: return rest_part._herd_off_places(k, n)

# sewing_part.gd
func sewing_open() -> bool: return sewing_part.sewing_open()
func sew_room(i: int) -> Dictionary: return sewing_part.sew_room(i)
func sew_front() -> Array[Pet]: return sewing_part.sew_front()
func sew_can_sit(pet: Pet) -> bool: return sewing_part.sew_can_sit(pet)
func sew_pickable() -> Array[Pet]: return sewing_part.sew_pickable()
func sew_pick_room(i: int) -> void: sewing_part.sew_pick_room(i)
func sew_seat(i: int, mark: String, uid: String) -> bool: return sewing_part.sew_seat(i, mark, uid)
func sew_unseat(i: int, mark: String) -> void: sewing_part.sew_unseat(i, mark)
func sew_seat_pets(i: int) -> Dictionary: return sewing_part.sew_seat_pets(i)
func sew_seated(i: int) -> Array[Pet]: return sewing_part.sew_seated(i)
func sew_marks(i: int) -> Array: return sewing_part.sew_marks(i)
func sew_party(i: int) -> Dictionary: return sewing_part.sew_party(i)
func sew_can_go(i: int, party := {}) -> bool: return sewing_part.sew_can_go(i, party)
func sew_word(i: int, party := {}) -> Array: return sewing_part.sew_word(i, party)
func send_to_room(i: int) -> bool: return sewing_part.send_to_room(i)
func _finish_room_run(quiet := false) -> void: sewing_part._finish_room_run(quiet)
func sew_hint(mark: String) -> String: return sewing_part.sew_hint(mark)
func debug_sewn(n: int) -> void: sewing_part.debug_sewn(n)

# toys_part.gd
func _finish_plays(now: float) -> Array: return toys_part._finish_plays(now)
func toy_again(edition: String) -> bool: return toys_part.toy_again(edition)
func play_toy(edition: String, play_id: String) -> bool: return toys_part.play_toy(edition, play_id)
func fix_toy(edition: String) -> bool: return toys_part.fix_toy(edition)
func combine_toy(edition: String) -> bool: return toys_part.combine_toy(edition)
func sacrifice_toy(id: String) -> String: return toys_part.sacrifice_toy(id)
func sacrifice_toys(id: String, tries: int) -> Dictionary: return toys_part.sacrifice_toys(id, tries)
func combine_toy_all(edition: String) -> int: return toys_part.combine_toy_all(edition)
func shine_toy(edition: String) -> bool: return toys_part.shine_toy(edition)

# unlocks_part.gd
func is_unlocked(id: String) -> bool: return unlocks_part.is_unlocked(id)
func unlock(id: String) -> void: unlocks_part.unlock(id)
func location_open(location: Dictionary) -> bool: return unlocks_part.location_open(location)
func page_open(page_id: String) -> bool: return unlocks_part.page_open(page_id)
func feature_on(feature: String) -> bool: return unlocks_part.feature_on(feature)
func tab_open(tab_name: String) -> bool: return unlocks_part.tab_open(tab_name)
func check_unlocks() -> void: unlocks_part.check_unlocks()
func find_events_at(location: Dictionary, n := 1 << 30) -> Array[Dictionary]: return unlocks_part.find_events_at(location, n)
func _count_find_tries(location: Dictionary, n: int) -> Array: return unlocks_part._count_find_tries(location, n)
func open_page(page_id: String) -> bool: return unlocks_part.open_page(page_id)
func _earned(earn: Dictionary) -> bool: return unlocks_part._earned(earn)
func all_places_open(page_id: String) -> bool: return unlocks_part.all_places_open(page_id)
func take_announcement() -> String: return unlocks_part.take_announcement()
func is_open(id: String) -> bool: return unlocks_part.is_open(id)
func follow_lead(location_id: String) -> void: unlocks_part.follow_lead(location_id)
func _spot_places(run: RunState) -> Array[String]: return unlocks_part._spot_places(run)
func _place_known(id: String) -> bool: return unlocks_part._place_known(id)
func open_locations() -> Array[Dictionary]: return unlocks_part.open_locations()
func next_door_open() -> bool: return unlocks_part.next_door_open()
func sent_to(location_id: String) -> int: return unlocks_part.sent_to(location_id)
func visits_at(location_id: String) -> int: return unlocks_part.visits_at(location_id)
func lights_left(location_id: String) -> int: return unlocks_part.lights_left(location_id)
func is_ours(location_id: String) -> bool: return unlocks_part.is_ours(location_id)
func ours_shown(location_id: String) -> void: unlocks_part.ours_shown(location_id)
func add_visits(location_id: String, n := 1) -> String: return unlocks_part.add_visits(location_id, n)
func follow_rumour(rumour_id: String) -> void: unlocks_part.follow_rumour(rumour_id)
func _hear_rumours(count: int) -> void: unlocks_part._hear_rumours(count)
func max_party(location_id: String) -> int: return unlocks_part.max_party(location_id)
func debug_unlock_all() -> void: unlocks_part.debug_unlock_all()
func tutorial_active() -> bool: return unlocks_part.tutorial_active()
func tutorial_info() -> Dictionary: return unlocks_part.tutorial_info()
func _start_tutorial() -> void: unlocks_part._start_tutorial()
func _check_tutorial() -> void: unlocks_part._check_tutorial()
func debug_lock_all() -> void: unlocks_part.debug_lock_all()
func _milestone(what: String) -> void: unlocks_part._milestone(what)
func buyable(tab_id: String) -> Array[String]: return unlocks_part.buyable(tab_id)
func upgrade_news(tab_id: String) -> bool: return unlocks_part.upgrade_news(tab_id)
func saw_upgrades(tab_id: String) -> void: unlocks_part.saw_upgrades(tab_id)

# wish_part.gd
func wish_open() -> bool: return wish_part.wish_open()
func set_wish(key: String) -> bool: return wish_part.set_wish(key)
func wish_shelves() -> Dictionary: return wish_part.wish_shelves()
func send_to_wish(rarity: String, n: int) -> Dictionary: return wish_part.send_to_wish(rarity, n)
func debug_wish(key: String, sent_n := -1) -> bool: return wish_part.debug_wish(key, sent_n)

# workers_part.gd
func worker_job(uid: String) -> String: return workers_part.worker_job(uid)
func knows_others(id: String) -> bool: return workers_part.knows_others(id)
func worker_jobs() -> Array[Dictionary]: return workers_part.worker_jobs()
func teach_others_block(id: String) -> String: return workers_part.teach_others_block(id)
func teach_others_cost(id: String) -> int: return workers_part.teach_others_cost(id)
func teach_others(id: String) -> bool: return workers_part.teach_others(id)
func workers_of(id: String) -> Array: return workers_part.workers_of(id)
func workers_herd(id: String) -> Dictionary: return workers_part.workers_herd(id)
func workers_count(id: String) -> int: return workers_part.workers_count(id)
func worker_faces(id: String, n: int) -> Array: return workers_part.worker_faces(id, n)
func spot_plan(id: String, n := 1) -> Array: return workers_part.spot_plan(id, n)
func buy_spots(id: String, n := 1) -> int: return workers_part.buy_spots(id, n)
func _add_spots(id: String, n: int) -> void: workers_part._add_spots(id, n)
func party_places() -> Array[Dictionary]: return workers_part.party_places()
func open_pages() -> Array: return workers_part.open_pages()
func spot_exist(id: String) -> int: return workers_part.spot_exist(id)
func spot_room(id: String) -> int: return workers_part.spot_room(id)
func workers_total() -> int: return workers_part.workers_total()
func put_workers(id: String, count := 1) -> int: return workers_part.put_workers(id, count)
func _add_workers(id: String, cards: Array, counts: Dictionary, quiet := false) -> int: return workers_part._add_workers(id, cards, counts, quiet)
func take_off_workers(id: String, count := 1) -> int: return workers_part.take_off_workers(id, count)
func _take_off_workers(uids: Array) -> void: workers_part._take_off_workers(uids)
func _workers_changed() -> void: workers_part._workers_changed()
func workers_speed(id: String) -> float: return workers_part.workers_speed(id)
func _whistle_checks(checks: int) -> void: workers_part._whistle_checks(checks)
func whistle_seen() -> void: workers_part.whistle_seen()
func set_whistle_tick(id: String, key: String, on: bool) -> void: workers_part.set_whistle_tick(id, key, on)
func step_whistle_keep(d: int) -> void: workers_part.step_whistle_keep(d)
func _workers_open(count: int) -> void: workers_part._workers_open(count)

# workshop_part.gd
func workshop_open() -> bool: return workshop_part.workshop_open()
func workshop_shown() -> bool: return workshop_part.workshop_shown()
func built(id: String) -> bool: return workshop_part.built(id)
func helpers_can_go(id: String, rarity: String) -> int: return workshop_part.helpers_can_go(id, rarity)
func send_helpers(id: String, rarity: String, n := 1) -> int: return workshop_part.send_helpers(id, rarity, n)
func build_drawing(id: String) -> bool: return workshop_part.build_drawing(id)
func debug_build(id: String) -> bool: return workshop_part.debug_build(id)
func _built(id: String) -> void: workshop_part._built(id)
func take_postcard() -> Dictionary: return workshop_part.take_postcard()
func _vane(run: RunState) -> bool: return workshop_part._vane(run)
func _workshop_chores(now: float) -> void: workshop_part._workshop_chores(now)
func _ring_bell() -> void: workshop_part._ring_bell()
# ---- end of the forwarders ----
