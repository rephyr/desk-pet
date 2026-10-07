class_name GameStateNode
extends Node
## Autoload "GameState": the player's progress (coins, care stats, pets, the bag of boxes and
## parts, adventures, unlocks) and saving it.
## Its code lives in parts, one per area (scripts/state/*.gd, see tools/state_parts.py): GameState
## keeps the state (every var, signal and const), the frame loop, and a one-line forwarder for every
## function, so GameState.<name>() works from anywhere. New code for an area goes in its part.

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
var care_part := CarePart.new(self)
var save_part := SavePart.new(self)
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
const SPARE_BIG := 5000  # past this many cards spare_shelves() keeps its count 3x as long, even as pets come and go
const WORKER_BOXES_MAX := 2000  # box workers open at most this many boxes in one go (every pet is rolled)
const OFFLINE_CAP := 12.0 * 3600.0
const FRAME_GAP := 5.0  # a frame this long means the computer slept: counts as closed (no care drain)
const FIRST_PET_BOX := "starter"
const DEBUG_COINS := 1000
const BACKGROUND_PACK_EVERY := 8.0  # seconds per pack your pet opens out of sight (its animation takes about this)
const BACKGROUND_AFTER := 1.0  # out of sight this long before it switches to opening in the background
const TUTORIAL_BOX := "tutorial"  # hidden box the tutorial's pets come from, see data/boxes.json
const AUTOMATION := "automation"  # lets you send swarms that follow your rules
const PARTIES := "parties"  # feature: send small parties (see PARTY_SIZES)
## Party sizes the finds open: the cart, the wheelbarrow, the hay wagon (data/unlocks.json).
const PARTY_SIZES := [["parties", 3], ["parties_5", 5], ["parties_10", 10]]
const PET_CRANK_ROLLS := 200  # past this many pulls at once (back from being away) the rest pay like these
const DESK_FACES := 2000000  # school faces past this sit at the desks
const XP_SPOTTED := 10  # xp for a pet spotting a new place
const XP_FIND := 25  # xp for bringing home a special find
const TREAT_SPEED := 3.0  # how many times as fast they walk while they zoom
const TRAIL_COINS := [0.2, 0.5]  # a coin pickup is worth this times the place's loot (garden: about 1)

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
var _save_soon := -1.0  # seconds until a save something asked for is written (-1: none waiting), see save_game
const SAVE_SOON := 1.5  # a few taps in a row write one save, not one each
var _run_timer := 0.0
var _tick_phase := 0  # which quarter of the once-a-second work runs next (see _process)
const TICK_PHASE := 0.25
var _pack_timer := 0.0  # your pet opening the pile out of sight, see _open_in_background()
var _pack_seen := 0.0  # seconds since a view last showed your pet opening packs
var _treats := {}  # RunState -> { zoom_until, ready_at }: treats tossed on the trail (not saved)
var _worker_of := {}  # uid -> job id, for every pet working as a worker
var _worker_speed := {}  # job id -> its workers' speeds added up (see Automation.worker_speed)
var whistle_since := { "hauled": {}, "put": 0 }  # what the whistle did since you last looked (not saved)


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
	if _save_soon > 0.0:
		_save_soon = maxf(0.0, _save_soon - delta)
	if (_save_timer >= 30.0 or _save_soon == 0.0) and not _still_writing():  # (never waits on the last write)
		_save_timer = 0.0
		_save_soon = -1.0
		_write_save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_finish_save()  # even if this save can't go ahead, the one on its way gets written
		save_game(true)


# ---- statics (callers use GameState.<name>(), the parts GameStateNode.<name>()) ----

## What `count` of a box cost in coins with a capsule worth `value`: its 'capsules' x value (so the
## shop keeps up with the machine, like errands), or a fixed 'price'.
static func box_cost(box: Dictionary, value: float, count := 1) -> int:
	var unit := float(box.capsules) * value if box.has("capsules") else float(box.get("price", 0))
	if unit <= 0.0 or count <= 0:
		return 0
	var one := maxi(1, roundi(minf(unit, Jobs.MAX_PRICE)))  # one box's price, rounded: 10 cost 10x that
	return int(minf(float(one) * count, Jobs.MAX_PRICE))


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


## A face for the school, `n` of a count: stand-in numbers of live pets only ever count up from 0,
## so these count down from -1 and never share a look (or a cached Pet) with one.
static func school_face(k: String, n: int) -> String:
	return Herd.uid(k, -1 - n)


## A coin amount worked out as a float, rounded and kept under COINS_MAX: past int's top it would
## wrap round to minus coins.
static func coins_int(f: float) -> int:
	return roundi(clampf(f, -float(COINS_MAX), float(COINS_MAX)))


static func _without(loot: Dictionary, key: String) -> Dictionary:
	var out := loot.duplicate()
	out.erase(key)
	return out


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

# care_part.gd
func gifts_waiting() -> int: return care_part.gifts_waiting()
func gifts_open() -> bool: return care_part.gifts_open()
func _tick_gifts(now: float, save := true) -> void: care_part._tick_gifts(now, save)
func open_gift() -> Dictionary: return care_part.open_gift()
func debug_set_gifts(n: int) -> void: care_part.debug_set_gifts(n)
func debug_gift_clock(hours: float) -> void: care_part.debug_gift_clock(hours)
func snack_price() -> int: return care_part.snack_price()
func feed() -> bool: return care_part.feed()
func pat() -> void: care_part.pat()
func set_care(food: float, mood: float) -> void: care_part.set_care(food, mood)
func _check_care() -> void: care_part._check_care()
func _forget_care_boosts() -> void: care_part._forget_care_boosts()
func _without_care(work: Callable) -> void: care_part._without_care(work)
func rummage_open() -> bool: return care_part.rummage_open()
func rummage_ready(spot_id: String) -> bool: return care_part.rummage_ready(spot_id)
func rummage(spot_id: String) -> Dictionary: return care_part.rummage(spot_id)
func set_pet_out(value: bool) -> void: care_part.set_pet_out(value)

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

# save_part.gd
func debug_new_game() -> void: save_part.debug_new_game()
func save_game(wait := false) -> void: save_part.save_game(wait)
func _still_writing() -> bool: return save_part._still_writing()
func _write_save(wait := false) -> void: save_part._write_save(wait)
func _finish_save() -> void: save_part._finish_save()
func load_game() -> bool: return save_part.load_game()
func _clamp_herd_places() -> void: save_part._clamp_herd_places()

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
func sew_part(slot: String, part_id: String, buttons := 0) -> Dictionary: return toys_part.sew_part(slot, part_id, buttons)

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
