extends SceneTree
## Headless checks for the pet core. Run with a profile of your own (the GameState tests write
## their saves into it; a worktree lane adds its name so lanes never share one):
##   godot --headless -s tests/test_core.gd -- --profile=core-test-<lane>
## DESK_PETS_SLOW=3 stretches the time limits when several copies run at once.

const ROLLS := 100000

var _failures := 0
var _checks := 0  # printed at the end, so a test that stopped early on a script error shows
var _skipped: Array[String] = []  # whole groups that didn't run, named in the last line
var _slow := maxf(1.0, OS.get_environment("DESK_PETS_SLOW").to_float())  # stretches the time limits


func _init() -> void:
	var catalog := Catalog.new()
	_test_data_is_consistent(catalog)
	_test_odds_match_box(catalog, "starter")
	_test_odds_match_box(catalog, "lucky")
	var tutorial_roller := PetRoller.new(catalog)
	for i in 500:
		var first := tutorial_roller.roll("tutorial")
		if first.rarity != "common" or first.finish != "normal":
			_check(false, "the tutorial box only gives plain commons (got %s %s)" % [first.finish, first.rarity])
			break
	_check(catalog.box("tutorial").get("hidden", false), "the tutorial box isn't sold in the shop")
	_test_save_round_trip(catalog)
	_test_old_pets_still_load(catalog)
	_test_adventures(catalog)
	_test_voice(catalog)
	_test_garden(catalog)
	_test_intel(catalog)
	_test_grafting(catalog)
	_test_jobs(catalog)
	_test_rummage(catalog)
	_test_machine(catalog)
	_test_toys(catalog)
	_test_boosts(catalog)
	_test_automation(catalog)
	_test_unlocks(catalog)
	_test_gear(catalog)
	_test_book(catalog)
	_test_prices(catalog)
	_test_knacks(catalog)
	_test_game_state(catalog)
	var result := "ALL PASSED" if _failures == 0 else "%d FAILED" % _failures
	if not _skipped.is_empty():
		result += ", BUT SKIPPED " + ", ".join(_skipped)
	print("\n%s (%d checks)" % [result, _checks])
	quit(1 if _failures > 0 else 0)


func _test_data_is_consistent(catalog: Catalog) -> void:
	for slot in Catalog.SLOTS:
		_check(not catalog.parts_of_tier(slot, "common").is_empty(), "%s has a common part" % slot)
		for p in catalog.slots[slot]:
			_check(catalog.rank(p.rarity) >= 0 and catalog.tiers.any(func(t): return t.id == p.rarity),
				"%s/%s has a known rarity" % [slot, p.id])
	for f in catalog.finishes:
		_check(catalog.tiers.any(func(t): return t.id == f.rarity), "finish %s has a known rarity" % f.id)
	for t in catalog.tiers:
		_check(not catalog.parts_of_tier("body", t.id).is_empty(), "body has a part at tier %s" % t.id)
	for b in catalog.boxes:
		for tier in b.tiers:
			_check(catalog.tiers.any(func(t): return t.id == tier), "box %s tier %s exists" % [b.id, tier])
		for f in b.finishes:
			_check(not catalog.finish(f).is_empty() and catalog.finish(f).id == f, "box %s finish %s exists" % [b.id, f])
	for t in catalog.adventure_types:
		_check(t.has("name") and t.has("risk"), "adventure type %s has a name and risk" % t.id)
	var first_pages := catalog.pages.filter(func(p): return p.get("start", false)).map(func(p): return p.id)
	var first_places := catalog.locations.filter(func(l): return l.get("start", false) and l.page in first_pages)
	_check(first_places.size() == 1, "a new game starts with exactly one place to go (%d)" % first_places.size())
	# every place can be reached from the start: spotted on trips (leads_to), through rumours, or on
	# a map page opened by something found on a reachable place
	var reached := { first_places[0].id: true }
	for round_ in catalog.locations.size():
		for entry in catalog.unlock_list:
			var find := str(entry.earn.get("find", ""))
			var from_machine := find == str(catalog.machine.get("intel", {}).get("find", ""))  # the machine's intel scrap
			var found_here := find == "" or from_machine or _found_in(catalog, reached, find)
			if found_here:
				for o in entry.opens:
					if str(o).begins_with("page:"):
						for l in catalog.locations:
							if l.page == str(o).substr(5) and l.get("start", false):
								reached[l.id] = true
		for l in catalog.locations:
			if reached.has(l.id):
				for lead in l.get("leads_to", []):
					reached[lead.to] = true
		for r in catalog.rumours:
			if r.get("requires", []).all(func(id): return reached.has(str(id).trim_prefix("location:"))):
				for id in r.unlocks:
					reached[str(id).trim_prefix("location:")] = true
	for l in catalog.locations:
		_check(reached.has(l.id), "%s can be reached from the start" % l.id)
		_check(l.has("map") and l.map.has("x") and l.map.has("y"), "%s is on the map" % l.id)
		for lead in l.get("leads_to", []):
			_check(not catalog.location(lead.to).is_empty(), "%s leads to a real place (%s)" % [l.id, lead.to])
		for other in catalog.locations:
			if other.id < l.id and l.has("map") and other.has("map"):
				var gap := Vector2(float(l.map.x), float(l.map.y)).distance_to(Vector2(float(other.map.x), float(other.map.y)))
				_check(gap >= 0.8, "%s and %s aren't drawn on top of each other" % [l.id, other.id])
	for l in catalog.locations:
		_check(not catalog.adventure_type(l.type).is_empty(), "location %s has a real type" % l.id)
		_check(not catalog.box(l.box).is_empty(), "location %s drops a real box" % l.id)
		_check(l.has("events") != l.has("pool"), "location %s has either a fixed list or a pool" % l.id)
		var ids: Array = l.get("events", []) + l.get("pool", []).map(func(p): return p.event)
		for e in ids:
			_check(catalog.events.has(e), "location %s event %s exists" % [l.id, e])
		if l.has("pool"):
			_check(int(l.get("draws", 0)) >= 1 and int(l.draws) <= l.pool.size(), "location %s draws a sensible number of events" % l.id)
	for e in catalog.events.values():
		_check(e.options.any(func(o): return int(o.get("min_party", 1)) <= 1), "event %s has an option for a single pet" % e.id)
		for o in e.options:
			_check(o.has("success") and o.success.has("text"), "event %s option %s has a success text" % [e.id, o.label])
			_check(str(o.get("stat", "")) in ["", "power", "luck", "speed"], "event %s option %s tests a real stat" % [e.id, o.label])
			for outcome in [o.success, o.get("failure", {})]:
				for r in outcome.get("rewards", []):
					_check(r.get("kind", "") in ["coins", "box", "part", "rumour", "find"], "event %s option %s reward kind %s is handled" % [e.id, o.label, r.get("kind", "")])
					if r.get("kind", "") == "find":
						_check(catalog.finds.has(r.get("id", "")), "event %s gives a real find" % e.id)
						continue
					for key in ["id", "box"]:
						_check(not r.has(key) or not catalog.box(r[key]).is_empty(), "event %s option %s reward %s is a real box" % [e.id, o.label, key])


## Rolls lots of pets and compares how often each finish shows up with the box's odds.
func _test_odds_match_box(catalog: Catalog, box_id: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var roller := PetRoller.new(catalog, rng)
	var finish_counts := {}
	var tier_counts := {}
	for i in ROLLS:
		var pet := roller.roll(box_id)
		finish_counts[pet.finish] = finish_counts.get(pet.finish, 0) + 1
		tier_counts[pet.rarity] = tier_counts.get(pet.rarity, 0) + 1
		_check_parts_fit_rarity(catalog, pet)

	var box := catalog.box(box_id)
	print("\n== %s box, %d rolls ==" % [box_id, ROLLS])
	print("finish        expected   got")
	var expected := Weighted.chances(box.finishes)
	for f in expected:
		var got := float(finish_counts.get(f, 0)) / ROLLS
		print("  %-10s %8.3f%% %8.3f%%" % [f, expected[f] * 100.0, got * 100.0])
		_check(absf(got - expected[f]) < _tolerance(expected[f]), "%s finish %s odds" % [box_id, f])

	# the pet's rarity is rolled once, so it must follow the box's tier odds exactly
	print("rarity        expected   got")
	expected = Weighted.chances(box.tiers)
	for t in expected:
		var got := float(tier_counts.get(t, 0)) / ROLLS
		print("  %-10s %8.3f%% %8.3f%%" % [t, expected[t] * 100.0, got * 100.0])
		_check(absf(got - expected[t]) < _tolerance(expected[t]), "%s rarity %s odds" % [box_id, t])


## Exactly the pet's rarity at the top: one part matches it and none go above it.
func _check_parts_fit_rarity(catalog: Catalog, pet: Pet) -> void:
	var best := 0
	for slot in Catalog.SLOTS:
		best = maxi(best, catalog.rank(catalog.part(slot, pet.parts[slot]).rarity))
	if best != catalog.rank(pet.rarity):
		_check(false, "pet %s parts top out at its rarity %s" % [pet.parts, pet.rarity])


func _test_save_round_trip(catalog: Catalog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var roller := PetRoller.new(catalog, rng)
	var c := Collection.new()
	var batch: Array[Pet] = []
	for i in 50:
		batch.append(roller.roll("lucky"))
	c.add(batch)
	c.set_active(c.pets[10].uid)

	var restored := Collection.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(restored.pets.size() == 50, "round trip keeps all pets")
	_check(restored.active_uid == c.pets[10].uid, "round trip keeps the active pet")
	_check(JSON.stringify(restored.pets[3].to_dict()) == JSON.stringify(c.pets[3].to_dict()),
		"round trip keeps pet data")
	var key := Collection.part_key("body", c.pets[0].parts.body)
	_check(restored.times_seen(key) == c.times_seen(key), "round trip keeps the book")

	# new pets after loading must not reuse ids
	var more: Array[Pet] = [roller.roll("starter")]
	restored.add(more)
	_check(restored.get_pet("50") != null and more[0].uid == "51", "ids continue after loading")


## A pet saved before a slot existed, or with a part that was since removed, still loads.
func _test_old_pets_still_load(catalog: Catalog) -> void:
	var old := { "uid": "7", "parts": { "body": "cat", "palette": "removed-palette" }, "finish": "gone" }
	var pet := Pet.from_dict(old, catalog)
	_check(pet.parts.body == "cat", "old pet keeps its known parts")
	for slot in Catalog.SLOTS:
		_check(not catalog.part(slot, pet.parts[slot]).is_empty(), "old pet gets a valid %s" % slot)
	_check(pet.finish == catalog.finishes[0].id, "unknown finish falls back to normal")


## Adventures: every pet comes home or doesn't at any party size, who chooses depends on the
## party size, the player chooser waits for answers, small parties time out to the default,
## catching up later gives the same result as playing along, lost pets leave the collection but
## stay in the book, and runs survive a save.
func _test_adventures(catalog: Catalog) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var roller := PetRoller.new(catalog, rng)
	var c := Collection.new()
	var batch: Array[Pet] = []
	for i in 2000:
		batch.append(roller.roll("starter"))
	c.add(batch)

	# a swarm run by the rules, 1 pet and 1000, resolved in one call long after
	for size in [1, 1000]:
		var pets: Array[Pet] = batch.slice(0, size)
		var run := AdventureRunner.start("below", pets, 0.0, 5, catalog)
		AdventureRunner.resolve(run, PolicyChooser.new(), 1.0e9, catalog)
		_check(run.status == RunState.Status.DONE, "a run by the rules finishes by itself (%d pets)" % size)
		_check(run.party.size() + run.party.lost.size() == size, "every pet comes home or doesn't (%d pets)" % size)
		_check(AdventureRunner.summary(run).begins_with("Expedition complete: %d of %d returned." % [run.party.size(), size]),
			"the summary counts who came back")
	var shallow := AdventureRunner.estimate_return("meadow", batch.slice(0, 200), catalog)
	var deep := AdventureRunner.estimate_return("below", batch.slice(0, 200), catalog)
	_check(shallow > deep, "deadlier places bring fewer home (%.2f vs %.2f)" % [shallow, deep])

	# catching up in one go matches checking in all the time
	var herd: Array[Pet] = batch.slice(0, 300)
	var at_once := AdventureRunner.start("well", herd, 0.0, 42, catalog)
	AdventureRunner.resolve(at_once, PolicyChooser.new(), 1.0e9, catalog)
	var bit_by_bit := AdventureRunner.start("well", herd, 0.0, 42, catalog)
	for t in range(0, 100000, 7):
		AdventureRunner.resolve(bit_by_bit, PolicyChooser.new(), float(t), catalog)
	_check(bit_by_bit.party.lost == at_once.party.lost and bit_by_bit.loot == at_once.loot,
		"resolving later gives the same run")

	_check(Chooser.kind_for(1) == "player" and Chooser.kind_for(5) == "timeout" and Chooser.kind_for(500) == "policy",
		"who chooses depends on the party size")

	# small parties: the default is picked at the deadline, even if nobody looked for hours
	var few: Array[Pet] = batch.slice(0, 5)
	var ignored := AdventureRunner.start("woods", few, 0.0, 11, catalog)
	var event_at := ignored.next_at
	AdventureRunner.resolve(ignored, Chooser.for_run(ignored), 1.0e9, catalog)
	_check(ignored.status == RunState.Status.DONE, "an ignored small party carries on with the defaults")
	var watched := AdventureRunner.start("woods", few, 0.0, 11, catalog)
	AdventureRunner.resolve(watched, Chooser.for_run(watched), event_at + TimeoutChooser.TIMEOUT - 1.0, catalog)
	_check(watched.status == RunState.Status.WAITING, "a small party waits for an answer until the deadline")
	for t in range(0, 20000, 5):
		AdventureRunner.resolve(watched, Chooser.for_run(watched), float(t), catalog)
	_check(watched.party.lost == ignored.party.lost and watched.loot == ignored.loot, "timing out gives the same trip whenever it's resolved")

	# the player picks: the run waits at each event until answered
	var solo: Array[Pet] = [batch[0]]
	var walk := AdventureRunner.start("garden", solo, 0.0, 7, catalog)
	AdventureRunner.resolve(walk, PlayerChooser.new(), 1.0e9, catalog)
	_check(walk.status == RunState.Status.WAITING and walk.history.is_empty(), "the garden waits for the player")
	var answers := 0
	var now := 1.0e9
	while walk.status != RunState.Status.DONE and answers < 10:
		if walk.status == RunState.Status.WAITING:
			walk.answer = AdventureRunner.allowed_options(walk.current_event(catalog), walk.party, catalog.location("garden"))[0]
			answers += 1
		AdventureRunner.resolve(walk, PlayerChooser.new(), now, catalog)
		now += 1.0e6  # time passes between events
	var played := walk.history.filter(func(e): return e.event != "finish").size()
	_check(walk.status == RunState.Status.DONE and played == answers, "answering every event finishes the walk")

	# lost pets leave the collection, the book keeps them, each leaves a star
	var gone: Array[String] = [batch[0].uid, batch[1].uid]
	var key := Collection.part_key("body", batch[0].parts.body)
	var seen_before := c.times_seen(key)
	c.active_uid = batch[0].uid
	c.remove(gone)
	_check(c.pets.size() == 1998 and c.get_pet(gone[0]) == null, "lost pets leave the collection")
	_check(c.times_seen(key) == seen_before, "the book still remembers them")
	_check(c.fallen.size() == 2, "each lost pet leaves a star")
	_check(c.active() != null, "losing the active pet picks another")
	var c2 := Collection.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(c2.fallen == c.fallen, "the stars survive a save")

	# a trip saved before v5 (as a "dungeon" run with coins/boxes/parts) still loads
	var old := { "dungeon": "woods", "chooser": "player", "seed": 3.0, "step": 1.0, "started": 0.0, "next_at": 5.0,
		"status": 0.0, "party": { "uids": ["9"], "stats": { "9": { "power": 7.0 } }, "names": { "9": "old pet" } },
		"coins": 12.0, "boxes": { "starter": 1.0 }, "parts": [["eyes", "sleepy"], ["eyes", "sleepy"]] }
	var loaded := RunState.from_dict(old, catalog)
	_check(loaded != null and loaded.location_id == "woods" and loaded.loot == { "coins": 12, "box:starter": 1, "part:eyes:sleepy": 2 },
		"an old dungeon run loads as an adventure")

	# a run half way through survives a save
	var saved := RunState.from_dict(JSON.parse_string(JSON.stringify(walk.to_dict())), catalog)
	_check(saved != null and saved.party.lost == walk.party.lost and saved.history.size() == walk.history.size()
		and saved.status == walk.status and saved.loot == walk.loot, "runs survive a save")


## The pet's voice: every eye gives a personality with something to say in every situation,
## every accessory has a tic (even if empty), and lines never show a {placeholder}.
func _test_voice(catalog: Catalog) -> void:
	var situations := ["idle", "away", "needs_you", "someone_back", "back_all", "back_some", "back_none", "part_found", "rumour", "spotted", "at_work"]
	var ids: Array = catalog.voice.personalities.map(func(p): return p.id)
	_check(catalog.voice.default in ids, "the default personality exists")
	for eyes in catalog.slots.eyes:
		_check(catalog.voice.personalities.any(func(p): return eyes.id in p.eyes), "eyes %s have a personality" % eyes.id)
	for accessory in catalog.slots.accessory:
		_check(catalog.voice.tics.has(accessory.id), "accessory %s has a tic" % accessory.id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for p in catalog.voice.personalities:
		var pet := Pet.new()
		pet.parts = { "eyes": p.eyes[0], "accessory": "crown" }
		_check(PetVoice.personality(pet, catalog) == p.id, "eyes %s pick %s" % [p.eyes[0], p.id])
		for kind in situations:
			_check(not p.lines.get(kind, []).is_empty(), "%s has lines for %s" % [p.id, kind])
			for i in 6:
				var text := PetVoice.line(pet, { "kind": kind, "place": "the woods", "home": 12, "sent": 100, "lost": 88,
					"rumour": "a deep well", "spot": "the meadow", "who": "bean", "then": ["part_found", "spotted", "rumour"] }, rng, catalog)
				_check(not "{" in text and text != "", "%s %s line fills in: %s" % [p.id, kind, text])
				_check(not " the the " in " " + text, "%s %s line doesn't say 'the the': %s" % [p.id, kind, text])
	var news := { "place": "the woods", "home": 0, "sent": 5, "parts": 0 }
	var worker := Pet.new()
	worker.parts = { "eyes": "round", "accessory": "none" }
	var summary := PetVoice.work_summary(worker, { "coins": 40, "parts": 3, "packs": 2, "good": ["holo fox"] }, rng, catalog)
	_check(summary.contains("3 parts") and summary.contains("holo fox") and not "{" in summary, "your pet tells you what it did: %s" % summary)
	_check(PetVoice.work_summary(worker, {}, rng, catalog) == "", "nothing done, nothing to tell")
	var none: Array[RunState] = []
	var quiet: Array[String] = []
	_check(PetVoice.situation(news, quiet, none, catalog).kind == "back_none", "nobody home is back_none")
	_check(PetVoice.situation({}, quiet, none, catalog).kind == "idle", "nothing going on is idle")
	var whisper: Array[String] = ["well"]
	_check(PetVoice.situation({}, whisper, none, catalog).kind == "rumour", "a waiting rumour gets mentioned")

	# rumours: each can be heard once, only when what it needs is open, and only if it opens something new
	var open := {}
	var is_open := func(id): return open.has(id)
	var can := Rumours.hearable(catalog, {}, is_open).map(func(r): return r.id)
	_check("well" in can and "orchard" in can and not "cellar" in can, "only rumours whose way is open can be heard (%s)" % [can])
	open["location:well"] = true
	can = Rumours.hearable(catalog, { "orchard": true }, is_open).map(func(r): return r.id)
	_check("cellar" in can and not "well" in can and not "orchard" in can, "heard or already open rumours don't come again (%s)" % [can])
	for r in catalog.rumours:
		for id in r.unlocks + r.get("requires", []):
			var bits: PackedStringArray = str(id).split(":")
			var real: bool = (bits[0] == "type" and not catalog.adventure_type(bits[1]).is_empty()) or (bits[0] == "location" and not catalog.location(bits[1]).is_empty())
			_check(real, "rumour %s points at something real: %s" % [r.id, id])


## The garden path: trips draw different events from its pool, hurt twice (or hurt badly) means
## the pet doesn't come back and its bag is lost, going home keeps the bag, and your active pet
## has a readable hint (never a number) for every option.
func _test_garden(catalog: Catalog) -> void:
	var garden := catalog.location("garden")
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var roller := PetRoller.new(catalog, rng)
	var bean: Array[Pet] = [roller.roll("starter", "common")]

	var seen := {}
	for t in 40:
		var events := AdventureRunner.pick_events(garden, t)
		_check(events.size() == int(garden.draws), "a garden trip meets %d events" % garden.draws)
		var unique := {}
		for e in events:
			unique[e] = true
			seen[e] = true
		_check(unique.size() == events.size(), "no event twice in one trip")
	_check(seen.size() == garden.pool.size(), "over many trips every garden event turns up (%d of %d)" % [seen.size(), garden.pool.size()])

	var party := Party.make(bean, catalog)
	party.hurt(1, 1, rng)
	_check(party.size() == 1 and party.injured_count() == 1, "hurt once: still going")
	party.hurt(1, 1, rng)
	_check(party.size() == 0 and party.lost.size() == 1, "hurt twice: doesn't come back")
	party = Party.make(bean, catalog)
	party.hurt(1, 2, rng)
	_check(party.size() == 0, "hurt badly: doesn't come back at once")

	# always taking the riskiest option: the garden is safe (nobody's ever lost there, a failure
	# just brings nothing); in the meadow some pets don't come back, and then the bag is empty
	var garden_risky := _risky_runs("garden", bean, catalog)
	_check(garden_risky.lost == 0, "nobody gets lost in the safe garden (%d were)" % garden_risky.lost)
	var meadow_risky := _risky_runs("meadow", bean, catalog)
	_check(meadow_risky.lost > 0 and meadow_risky.kept > 0, "risky adventures sometimes go wrong and sometimes pay off")

	# going home straight away ends the trip with the pet and whatever it had
	var early := AdventureRunner.start("garden", bean, 0.0, 3, catalog)
	AdventureRunner.resolve(early, PlayerChooser.new(), 1.0e9, catalog)
	early.answer = AdventureRunner.options_of(early.current_event(catalog), garden).size() - 1
	AdventureRunner.resolve(early, PlayerChooser.new(), 2.0e9, catalog)
	AdventureRunner.resolve(early, PlayerChooser.new(), 3.0e9, catalog)
	_check(early.status == RunState.Status.DONE and early.party.size() == 1 and early.history.size() == 1, "go home ends the trip, pet safe")
	_check(not early.history.any(func(e): return e.event == "finish"), "going home early skips the treat bag")
	var full := AdventureRunner.start("garden", bean, 0.0, 4, catalog)
	var t := 0.0
	for i in 20:
		if full.status == RunState.Status.WAITING:
			full.answer = 0  # the safe way every time
		AdventureRunner.resolve(full, PlayerChooser.new(), t, catalog)
		t += 1.0e5
	_check(full.history.any(func(e): return e.event == "finish") and full.party.size() == 1, "going all the way ends with a treat bag")
	_check(Rewards.depth_boost(3) > Rewards.depth_boost(0), "later events pay more")
	_check(full.xp >= AdventureRunner.XP_EVENT * 3 + AdventureRunner.XP_FINISH, "a whole trip earns xp (%d)" % full.xp)
	_check(early.xp == AdventureRunner.XP_EVENT, "going home straight away earns a little xp (%d)" % early.xp)
	_check(RunState.from_dict(JSON.parse_string(JSON.stringify(full.to_dict())), catalog).xp == full.xp, "trip xp survives a save")

	# hints: every option gets words, never a number or a {placeholder}; bias tilts them
	var risky := {}
	for id in garden.pool.map(func(p): return p.event):
		var event: Dictionary = catalog.events[id]
		for option in AdventureRunner.options_of(event, garden):
			for p in catalog.voice.personalities:
				var speaker := Pet.new()
				speaker.parts = { "eyes": p.eyes[0], "accessory": "none" }
				var text := PetVoice.hint(speaker, option, Party.make(bean, catalog), garden, catalog)
				_check(text != "" and not "{" in text and not "%" in text and not text.contains("0."), "hint for %s / %s (%s): %s" % [id, option.label, p.id, text])
			if option.get("failure", {}).has("hurt"):
				risky = option
	# the story lines on top of a trip: a feeling for every state, a "spotted" line for every event
	var hurt_party := Party.make(bean, catalog)
	hurt_party.hurt(1, 1, rng)
	var none: Array[Dictionary] = []
	var went_badly: Array[Dictionary] = [{ "success": false }]
	for p in catalog.voice.personalities:
		var speaker := Pet.new()
		speaker.parts = { "eyes": p.eyes[0], "accessory": "none" }
		for text in [PetVoice.feeling(speaker, Party.make(bean, catalog), none, catalog),
				PetVoice.feeling(speaker, Party.make(bean, catalog), went_badly, catalog),
				PetVoice.feeling(speaker, hurt_party, none, catalog)]:
			_check(text != "" and not "{" in text, "%s feeling line: %s" % [p.id, text])
		for id in garden.pool.map(func(x): return x.event):
			var text := PetVoice.spotted(speaker, catalog.events[id], Party.make(bean, catalog), garden, catalog)
			_check(text != "" and not "{" in text, "%s spotted at %s: %s" % [p.id, id, text])

	var bands := {}
	for id in ["overconfident", "cheerful", "nervous"]:
		var p: Dictionary = catalog.voice.personalities.filter(func(x): return x.id == id)[0]
		var speaker := Pet.new()
		speaker.parts = { "eyes": p.eyes[0], "accessory": "none" }
		var text := PetVoice.hint(speaker, risky, Party.make(bean, catalog), garden, catalog)
		for i in p.hints.risk.size():
			if text.ends_with(str(p.hints.risk[i]).replace("{trip}", Party.make(bean, catalog).who())):
				bands[id] = i
	_check(bands.get("overconfident", 9) <= bands.get("cheerful", -1) and bands.get("cheerful", 9) <= bands.get("nervous", -1),
		"overconfident pets sound surer and nervous ones more scared (%s)" % [bands])


## Runs 60 adventures to `place_id` always taking the riskiest option. Returns how many came back
## with something ({ kept }) and how many lost the pet ({ lost }), checking a lost party ends the
## adventure right there, with an empty bag.
func _risky_runs(place_id: String, pets: Array[Pet], catalog: Catalog) -> Dictionary:
	var place := catalog.location(place_id)
	var out := { "lost": 0, "kept": 0 }
	for t in 60:
		var run := AdventureRunner.start(place_id, pets, 0.0, t, catalog)
		var now := 0.0
		for i in 20:
			if run.status == RunState.Status.DONE:
				break
			if run.status == RunState.Status.WAITING:
				var options := AdventureRunner.options_of(run.current_event(catalog), place)
				var riskiest := 0
				for j in options.size() - 1:  # not "go home", the last one
					if float(options[j].get("chance", 1.0)) < float(options[riskiest].get("chance", 1.0)):
						riskiest = j
				run.answer = riskiest
			AdventureRunner.resolve(run, PlayerChooser.new(), now, catalog)
			if run.party.size() == 0:
				_check(run.status == RunState.Status.DONE, "%s: nobody left, the adventure ends right away" % place_id)
			now += 1.0e5
		_check(run.status == RunState.Status.DONE, "a %s adventure always ends" % place_id)
		if run.party.size() == 0:
			out.lost += 1
			_check(run.loot.is_empty(), "a pet that doesn't come back brings nothing home")
		elif not run.loot.is_empty():
			out.kept += 1
	return out


## Spotting places on trips: only unknown places, and the safety net means nobody waits long.
func _test_intel(catalog: Catalog) -> void:
	var garden := catalog.location("garden")
	var rng := RandomNumberGenerator.new()
	var worst := 0
	for t in 300:
		rng.seed = t
		var tries := {}
		var trips := 0
		var found: Array[String] = []
		while not "meadow" in found and trips < 50:
			trips += 1
			found.append_array(Intel.roll(garden, func(id): return id in found, tries, rng))
		worst = maxi(worst, trips)
	_check(worst <= 5, "the meadow is always spotted within a few garden trips (worst %d)" % worst)
	var all_known := Intel.roll(garden, func(_id): return true, {}, rng)
	_check(all_known.is_empty(), "places already known aren't spotted again")


## Sewing parts onto your active pet: it works or it doesn't, rarer is riskier, the old part comes
## back, a failed stitch only costs the new part, and sewn parts show and survive a save.
func _test_grafting(catalog: Catalog) -> void:
	_check(Grafting.fail_chance("eyes", "round", catalog) < Grafting.fail_chance("eyes", "cyclops", catalog)
		or catalog.part("eyes", "round").rarity == catalog.part("eyes", "cyclops").rarity, "rarer parts are riskier to sew on")
	var rng := RandomNumberGenerator.new()
	var worked := 0
	var failed := 0
	for t in 400:
		rng.seed = t
		var pet := Pet.new()
		for slot in Catalog.SLOTS:
			pet.parts[slot] = catalog.default_part(slot)
		pet.rarity = "common"
		var legendary: Dictionary = catalog.parts_of_tier("body", "legendary")[0]
		var inventory := { "body:%s" % legendary.id: 1 }
		var old_body: String = pet.parts.body
		var result := Grafting.sew(pet, "body", legendary.id, inventory, rng, catalog)
		_check(not inventory.has("body:%s" % legendary.id), "the part is used up either way")
		if result.ok:
			worked += 1
			if pet.parts.body != legendary.id or not "body" in pet.sewn or pet.rarity != "legendary" or inventory.get("body:" + old_body, 0) != 1:
				_check(false, "a stitch that holds swaps the part, marks it sewn, raises the rarity and gives the old part back")
		else:
			failed += 1
			if pet.parts.body != old_body or not pet.sewn.is_empty():
				_check(false, "a stitch that fails leaves the pet as it was")
	_check(worked > 0 and failed > 0, "legendary parts sometimes hold and sometimes don't (%d / %d)" % [worked, failed])
	var fail_rate := float(failed) / 400.0
	_check(absf(fail_rate - float(catalog.grafting.fail.legendary)) < 0.08, "fails about as often as the data says (%.2f)" % fail_rate)

	var pet := Pet.new()
	for slot in Catalog.SLOTS:
		pet.parts[slot] = catalog.default_part(slot)
	_check(not Grafting.can_sew(pet, "eyes", pet.parts.eyes, { "eyes:%s" % pet.parts.eyes: 1 }), "can't sew on what it's already wearing")
	_check(not Grafting.can_sew(pet, "eyes", "sparkle", {}), "can't sew on a part you don't have")
	var look := Grafting.preview(pet, "eyes", "sparkle")
	_check(pet.parts.eyes != "sparkle" and look.parts.eyes == "sparkle", "the preview doesn't change the real pet")
	var plain := PetLook.texture_for(look.parts, false, []).get_image()
	var stitched := PetLook.texture_for(look.parts, false, ["eyes"]).get_image()
	_check(plain.get_data() != stitched.get_data(), "sewn parts show stitch marks")
	look.sewn.assign(["eyes", "body"])
	_check(Pet.from_dict(JSON.parse_string(JSON.stringify(look.to_dict())), catalog).sewn == look.sewn, "stitches survive a save")

	var bands := {}
	for p in catalog.voice.personalities:
		var speaker := Pet.new()
		speaker.parts = { "eyes": p.eyes[0], "accessory": "none" }
		for kind in ["risk", "success", "fail"]:
			var line := PetVoice.graft_line(speaker, kind, 0.6, rng, catalog)
			_check(line != "" and not "{" in line, "%s has a %s line for sewing" % [p.id, kind])
		bands[p.id] = p.graft.risk.find(PetVoice.graft_line(speaker, "risk", 0.6, rng, catalog))
	_check(bands.overconfident <= bands.cheerful and bands.cheerful <= bands.nervous, "overconfident pets sound braver about sewing (%s)" % [bands])


## Errands: one formula for every job, bigger crews go faster (but each pet helps less), time away
## pays the same however it's split up, and errands only ever bring commons and uncommons.
func _test_jobs(catalog: Catalog) -> void:
	_check(not catalog.jobs.is_empty(), "there are errands to do")
	var power := float(catalog.errands.crew_power)
	for job in catalog.jobs:
		_check(job.has("name") and float(job.seconds) > 0.0 and job.has("pay"), "errand %s has a name, a time and a pay" % job.id)
		if job.has("needs"):
			_check(catalog.unlock_list.any(func(u): return str(job.needs) in u.opens), "errand %s waits for something that opens (%s)" % [job.id, job.needs])
	_check(catalog.job("scrapyard").get("needs", "") == "feature:parts", "the scrapyard waits for parts")
	_check(not catalog.job("coin_hunt").has("needs"), "the coin hunt is there as soon as errands are")
	var coin: Dictionary = catalog.job("coin_hunt")
	var one := Jobs.rate(coin, 1, 1.0, power)
	var three := Jobs.rate(coin, 3, 1.0, power)
	var thousand := Jobs.rate(coin, 1000, 1.0, power)
	_check(three > one * 2.0 and three < one * 3.0, "3 pets work faster than 1, but not 3x (%.2fx)" % (three / one))
	_check(thousand / 1000.0 < three / 3.0, "each extra pet helps a little less")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	# an hour in one go or in 3600 little ticks pays about the same
	var a := { "fill": 0.0 }
	var b := { "fill": 0.0 }
	var once: Dictionary = Jobs.work(coin, a, 3, three, 3600.0, rng, catalog)
	var ticks := 0
	for i in 3600:
		ticks += Jobs.work(coin, b, 3, three, 1.0, rng, catalog).fills
	_check(once.fills == ticks, "time away counts the same however it's split (%d and %d fills)" % [once.fills, ticks])
	var per_min := float(Rewards.total(once.loot, "coins")) / 60.0  # a capsule is worth 1 coin here
	_check(per_min > 3.0 and per_min < 12.0, "3 pets on the coin hunt find a gentle trickle (%.1f capsules' worth a minute)" % per_min)
	# errands pay in capsules: they grow with the machine, and stay well under pulling the lever
	var rich: Dictionary = Jobs.work(coin, { "fill": 0.99 }, 1, 1.0, 1.0, rng, catalog, { "coin_value": 74.0 })
	_check(int(rich.loot.get("coins", 0)) == 5 * 74, "a find is worth 5 capsules of the machine (%d)" % int(rich.loot.get("coins", 0)))
	var one_pet_capsules := Jobs.rate(coin, 1, 1.0, power) * 60.0 * 5.0
	_check(one_pet_capsules < 26.0 * 0.2, "one pet on the coin hunt finds well under what pulling gives (%.1f capsules a minute)" % one_pet_capsules)
	_test_errand_tools(catalog)
	# thousands of pets for a whole day stays quick and sane
	var start := Time.get_ticks_msec()
	var scrap: Dictionary = catalog.job("scrapyard")
	var big: Dictionary = Jobs.work(scrap, { "fill": 0.0 }, 5000, Jobs.rate(scrap, 5000, 1.0, power), 36000.0, rng, catalog)
	_check(Time.get_ticks_msec() - start < 1000, "a huge crew's day away is worked out quickly")
	_check(Rewards.total(big.loot, "part") > big.fills * 0.9, "every scrapyard fill brings a part (%d fills)" % big.fills)
	var uncommon := 0
	for key: String in big.loot:
		var bits := key.split(":")
		var tier: String = catalog.part(bits[1], bits[2]).rarity
		_check(tier in ["common", "uncommon"], "errands never bring rare parts (%s)" % key)
		if tier == "uncommon":
			uncommon += int(big.loot[key])
	_check(uncommon > 0, "a big scrapyard crew finds an uncommon now and then")
	var small: Dictionary = Jobs.work(scrap, { "fill": 0.0 }, 2, 1.0, 400.0, rng, catalog)
	_check(small.loot.keys().all(func(k): return catalog.part(k.split(":")[1], k.split(":")[2]).rarity == "common"), "a small scrapyard crew only finds commons")
	# faster pets: rarer ones and fitting traits
	var slow := Pet.new()
	slow.stats = { "speed": 5 }
	var quick := Pet.new()
	quick.stats = { "speed": 40 }
	var greedy := Pet.new()
	greedy.stats = { "speed": 5 }
	greedy.traits.assign(["greedy"])
	_check(Jobs.pet_speed(quick, coin) > Jobs.pet_speed(slow, coin), "pets with a better stat work faster")
	_check(Jobs.pet_speed(greedy, coin) > Jobs.pet_speed(slow, coin), "greedy pets hunt coins faster")
	_check(Jobs.pet_speed(quick, coin) <= 1.25 and Jobs.pet_speed(slow, coin) >= 0.75, "stats only nudge (about 25%% either way)")
	var off := Jobs.offline_seconds(20.0 * 3600.0, 8.0, 0.5, 12.0 * 3600.0)
	_check(is_equal_approx(off, 10.0 * 3600.0), "a day away counts 8 h at full speed, then half, up to the cap (%.1f h)" % (off / 3600.0))


## Errand tools: coins buy them on the upgrades page; jobs level up and reach goals.
func _test_errand_tools(catalog: Catalog) -> void:
	var known := ["worth", "speed", "big", "rare_x", "all_speed", "away_hours", "shiny", "crew_power", "hold"]
	var ids := {}
	for t in Jobs.all_tools(catalog):
		_check(not ids.has(t.id), "errand tool %s has its own id" % t.id)
		ids[t.id] = true
		_check(t.has("name") and t.has("what") and float(t.get("capsules", 0)) > 0.0 and not t.each.is_empty(), "errand tool %s has a name, what it does, a price and an effect" % t.id)
		_check(FileAccess.get_file_as_string("res://scripts/ui/ui_theme.gd").contains('\t"%s": ' % t.icon), "errand tool %s has an icon (%s)" % [t.id, t.icon])
		_check(t.each.keys().all(func(k): return k in known), "errand tool %s only does things errands understand" % t.id)
		if t.has("machine"):
			_check(not Machine.node(catalog, str(t.machine)).is_empty(), "errand tool %s waits for a real machine upgrade" % t.id)
		_check(Jobs.tool_cost(t, 5) >= Jobs.tool_cost(t, 0), "errand tool %s costs more the more you have" % t.id)
	var coin: Dictionary = catalog.job("coin_hunt")
	var lemon: Dictionary = catalog.job("lemonade")
	_check(Jobs.tool_cost(Jobs.tool(catalog, "noses"), 0, 3) == Jobs.tool_cost(Jobs.tool(catalog, "noses"), 0) + Jobs.tool_cost(Jobs.tool(catalog, "noses"), 1) + Jobs.tool_cost(Jobs.tool(catalog, "noses"), 2), "buying 3 levels costs the 3 levels added up")
	_check(Jobs.level(coin, { "noses": 4, "paws": 3, "snack": 9 }) == 7, "a job's level is its own tools' levels")
	_check(Jobs.goal_x(coin, 24) == 1.0 and Jobs.goal_x(coin, 25) == 2.0 and Jobs.goal_x(coin, 50) == 4.0, "coin hunt goals double its coins at lv 25 and 50")
	_check(str(Jobs.next_goal(coin, 3).get("text", "")).contains("lemonade"), "the coin hunt's first goal is the lemonade stand")
	_check(catalog.unlock_list.any(func(u): return "job:lemonade" in u.opens and int(u.earn.get("job_level", {}).get("coin_hunt", 0)) == int(coin.goals[0].at)), "the lemonade stand opens at the coin hunt's first goal")
	_check(Jobs.tool_sum(catalog, "coin_hunt", "all_speed", { "snack": 2 }) > 0.0 and Jobs.tool_sum(catalog, "coin_hunt", "speed", { "sign": 5 }) == 0.0, "tools for everyone reach every job, a job's own only that job")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "pockets"), {}, {}, true).begins_with("at lv"), "deeper pockets wait for the coin hunt's level")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "cups"), { "cups": 1 }, {}, true) == "max", "a tool with a max stops there")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "lemons"), {}, {}, false) == "closed", "a job's tools wait for the job")
	_check(float(lemon.tips.rare) > float(lemon.tips.common), "rarer pets get bigger tips")
	var plain := Jobs.average_fill(coin, { "coin_value": 10.0 })
	var better := Jobs.average_fill(coin, { "coin_value": 10.0, "worth": 2.0, "big": 0.1, "big_x": 5.0 })
	_check(is_equal_approx(plain, 50.0) and is_equal_approx(better, 70.0 * 1.4), "tools make each find worth more (%.1f -> %.1f)" % [plain, better])
	_test_more_jobs(catalog)


## A3: the savings jar, the kitchen and scouting.
func _test_more_jobs(catalog: Catalog) -> void:
	var power := float(catalog.errands.crew_power)
	var coin: Dictionary = catalog.job("coin_hunt")
	var lemon: Dictionary = catalog.job("lemonade")
	var jar: Dictionary = catalog.job("jar")
	var kitchen: Dictionary = catalog.job("kitchen")
	var scout: Dictionary = catalog.job("scouting")
	for job in [jar, kitchen, scout]:
		_check(not job.is_empty(), "the %s is an errand" % job.get("id", "?"))
		_check(FileAccess.get_file_as_string("res://scripts/ui/ui_theme.gd").contains('\t"%s": ' % job.get("doodle", "?")), "errand %s has a doodle" % job.get("id", "?"))
	# each opens through a job_level unlock that matches a goal on the job it waits for
	for job in catalog.jobs:
		if not str(job.get("needs", "")).begins_with("job:"):
			continue
		var entry: Dictionary = {}
		for u in catalog.unlock_list:
			if str(job.needs) in u.opens:
				entry = u
		var levels: Dictionary = entry.get("earn", {}).get("job_level", {})
		_check(levels.size() == 1, "errand %s opens at another errand's level" % job.id)
		for other_id in levels:
			var other := catalog.job(str(other_id))
			_check(other.get("goals", []).any(func(g): return int(g.at) == int(levels[other_id]) and str(g.get("text", "")) != ""),
				"errand %s opens at a goal of the %s that says so (lv %d)" % [job.id, other_id, int(levels[other_id])])
	_check(Jobs.goal_words(lemon, lemon.goals[0]) == "x2 tips and a savings jar opens", "a goal with both reads: %s" % Jobs.goal_words(lemon, lemon.goals[0]))
	_check(Jobs.goal_words(coin, coin.goals[1]) == "x2 coins and a kitchen opens", "the coin hunt's lv 25: %s" % Jobs.goal_words(coin, coin.goals[1]))
	# the jar: extra pets barely help; one pet in it beats one on the coin hunt, a crew doesn't
	var jar_hour := func(n): return Jobs.rate(jar, n, 1.0, power) * 3600.0 * float(jar.pay.capsules)
	var coin_hour := func(n): return Jobs.rate(coin, n, 1.0, power) * 3600.0 * float(coin.pay.capsules)
	_check(jar_hour.call(1) > coin_hour.call(1), "one pet in the jar beats one on the coin hunt (%.0f vs %.0f an hour)" % [jar_hour.call(1), coin_hour.call(1)])
	_check(jar_hour.call(5) < coin_hour.call(5), "a crew of 5 earns more on the coin hunt (%.0f vs %.0f)" % [jar_hour.call(5), coin_hour.call(5)])
	_check(Jobs.rate(jar, 4, 1.0, power) / Jobs.rate(jar, 1, 1.0, power) < Jobs.rate(coin, 4, 1.0, power) / Jobs.rate(coin, 1, 1.0, power),
		"the jar uses its own crew power (4 pets help less there)")
	_check(is_equal_approx(Jobs.rate(jar, 4, 1.0, power, 0.1) / Jobs.rate(jar, 4, 1.0, power), pow(4.0, 0.1)), "teamwork still adds to the jar's own crew power")
	# the kitchen: soft, capped, never beats a real job
	var bonus := [1, 2, 4, 10].map(func(c): return Jobs.kitchen_bonus(kitchen, c, 1, power))
	_check(absf(bonus[0] - 0.10) < 0.005 and absf(bonus[1] - 0.15) < 0.005 and absf(bonus[2] - 0.20) < 0.005 and absf(bonus[3] - 0.25) < 0.005,
		"1/2/4/10 cooks: every job 10/15/20/25%% faster (%s)" % [bonus])
	_check(Jobs.kitchen_bonus(kitchen, 1000.0, 1, power) <= float(kitchen.kitchen.most), "the kitchen never goes past its most")
	_check(Jobs.kitchen_bonus(kitchen, 2.0, 1000, power) < 0.002, "with 1000 pets elsewhere, 2 cooks barely matter (%.4f)" % Jobs.kitchen_bonus(kitchen, 2.0, 1000, power))
	var thin := Jobs.faster_words(Jobs.kitchen_bonus(kitchen, 2.0, 1000, power))
	_check(thin.begins_with("every job 0.") and not thin.begins_with("every job 0.0"), "a thinned-out kitchen shows a decimal, not 0%% (%s)" % thin)
	_check(Jobs.faster_words(0.12) == "every job 12% faster" and Jobs.faster_words(0.0001) == "", "the kitchen's line: whole percent, or nothing when it rounds away")
	for others in [1, 3, 10, 100, 1000]:
		for cooks in [1, 2, 5]:
			var gain_kitchen := Jobs.kitchen_bonus(kitchen, cooks, others, power)
			var gain_job := pow(float(others + cooks) / others, power) - 1.0
			_check(gain_kitchen <= gain_job + 1e-9, "%d cooks with %d pets elsewhere help less than on a real job (%.3f vs %.3f)" % [cooks, others, gain_kitchen, gain_job])
	_check(not Jobs.shared_out(kitchen) and not Jobs.shared_out(scout) and Jobs.shared_out(coin), "share out skips the kitchen and scouting")
	var meal: Dictionary = Jobs.pay(kitchen, 2, 1, RandomNumberGenerator.new(), catalog)
	_check(int(meal.get("meal", 0)) == 2 * int(kitchen.pay.meal) and not meal.has("coins"), "the kitchen pays meals, not coins (%s)" % [meal])
	# a meal tops food up only to meal_upto (feeding it yourself does the rest), never lowers it
	var upto := float(kitchen.get("meal_upto", 100.0))
	_check(upto < 100.0, "the kitchen's meals stop short of a full belly (meal_upto %.0f)" % upto)
	var fed := Jobs.feed(kitchen, 30.0, 30.0, 1000)
	_check(is_equal_approx(fed.food, upto) and fed.mood <= upto, "a thousand meals still only reach %.0f (%s)" % [upto, fed])
	fed = Jobs.feed(kitchen, 95.0, 90.0, 3)
	_check(fed.food == 95.0 and fed.mood == 90.0 and fed.eaten == 0.0, "a full pet eats nothing and loses nothing (%s)" % [fed])
	fed = Jobs.feed(kitchen, 30.0, 30.0, 1)
	_check(is_equal_approx(fed.eaten, float(kitchen.pay.meal)) and is_equal_approx(fed.mood, 30.0 + float(kitchen.meal_mood)), "one meal: its food and mood (%s)" % [fed])
	# scouting: notes held, who takes them
	_check(Jobs.scout_hold(catalog, {}) == 2 and Jobs.scout_hold(catalog, { "map_case": 3 }) == 5, "you hold 2 notes, 5 with the map case")
	_check(int(Jobs.pay(scout, 3, 1, RandomNumberGenerator.new(), catalog).get("note", 0)) == 3, "each full scouting meter writes a note")
	var garden := catalog.location("garden")
	var well := catalog.location("well")
	_check(Jobs.takes_note(catalog, garden, true, 1, true), "a trip you send takes a note")
	_check(not Jobs.takes_note(catalog, garden, false, 1, true), "auto parties never take notes")
	_check(not Jobs.takes_note(catalog, well, true, 1, true), "dungeon trips never take notes")
	_check(not Jobs.takes_note(catalog, garden, true, 0, true), "no notes, nothing to take")
	_check(not Jobs.takes_note(catalog, garden, true, 1, false), "a place with nothing left to find takes no note")
	var nothing_known := func(_id): return false
	var all_known := func(_id): return true
	_check(Intel.left_to_find(garden, nothing_known, false, catalog), "the garden has places to spot")
	_check(not Intel.left_to_find(garden, all_known, false, catalog), "a garden with every lead known and no rumours has nothing left")
	_check(Intel.left_to_find(catalog.location("fields"), all_known, true, catalog), "the fields can still bring rumours")
	# the note's bonus: more spotting over many seeded rolls, rumours x1.5
	var rng := RandomNumberGenerator.new()
	var plain := 0
	var scouted := 0
	for t in 2000:
		rng.seed = t
		plain += Intel.roll(garden, nothing_known, {}, rng).size()
		rng.seed = t
		scouted += Intel.roll(garden, nothing_known, {}, rng, float(scout.scout.spot)).size()
	_check(scouted > plain * 1.1, "a scouted trip spots more (%d vs %d)" % [scouted, plain])
	var run := RunState.new()
	var rumour := { "kind": "rumour", "chance": 0.4 }
	_check(AdventureRunner.scouted(rumour, run).chance == 0.4, "an unscouted trip hears rumours as usual")
	run.scout = Jobs.scout_note(catalog)
	_check(is_equal_approx(float(AdventureRunner.scouted(rumour, run).chance), 0.6) and rumour.chance == 0.4, "a scouted trip's rumours are x1.5 (the data stays the same)")
	_check(AdventureRunner.scouted({ "kind": "coins", "amount": [1, 2] }, run).get("chance", -1) == -1, "only rumours change")
	var pets: Array[Pet] = [PetRoller.new(catalog).roll("starter")]
	var trip := AdventureRunner.start("garden", pets, 0.0, 1, catalog)
	trip.scout = Jobs.scout_note(catalog)
	_check(RunState.from_dict(JSON.parse_string(JSON.stringify(trip.to_dict())), catalog).scouted, "a scouted trip stays scouted through a save")
	_check(is_equal_approx(float(RunState.from_dict(JSON.parse_string(JSON.stringify(trip.to_dict())), catalog).scout.get("rumour_x", 0.0)), float(scout.scout.rumour_x)),
		"the note's rumour_x rides along with the trip")
	# the scouting job is found by its "scout" block, not its id
	_check(Jobs.scout_job(catalog).get("id", "") == "scouting" and Jobs.scout_settings(catalog) == scout.scout, "the scout job is the one with a scout block")
	var renamed := Catalog.new()
	for j in renamed.jobs:
		if j.has("scout"):
			j.id = "lookouts"
	_check(Jobs.scout_hold(renamed, {}) == int(scout.scout.hold), "scouting renamed in data still holds its notes")


## Whether some place already reached has an event that gives this find.
func _found_in(catalog: Catalog, reached: Dictionary, find: String) -> bool:
	for l in catalog.locations:
		if not reached.has(l.id):
			continue
		for e in l.get("events", []) + l.get("pool", []).map(func(p): return p.event):
			if catalog.events[e].get("find", "") == find:
				return true
	return false


## Unlocks: every one can be earned, every find has an event that gives it, and once found that
## event stops turning up.
func _test_unlocks(catalog: Catalog) -> void:
	var tabs := ["home", "machine", "boxes", "collection", "adventures", "errands", "automation", "inventory", "settings"]
	var page_ids := catalog.pages.map(func(p): return p.id)
	for entry in catalog.unlock_list:
		_check(entry.show in ["locked", "hidden"], "unlock %s is shown locked or hidden" % entry.id)
		for o in entry.opens:
			var bits := str(o).split(":")
			var ok: bool = (bits[0] == "tab" and bits[1] in tabs) or (bits[0] == "feature" and bits[1] in ["errands", "packs", "shopping", "parties", "parties_5", "parties_10", "toys", "parts", "auto_adventures"]) or (bits[0] == "page" and bits[1] in page_ids) \
				or (bits[0] == "job" and catalog.jobs.any(func(j): return str(j.get("needs", "")) == o))
			_check(ok, "unlock %s opens something real (%s)" % [entry.id, o])
		if entry.earn.has("find"):
			_check(catalog.finds.has(entry.earn.find), "unlock %s waits for a real find" % entry.id)
		_check(not "{" in str(entry.get("announce", "")), "unlock %s announcement has no placeholders" % entry.id)
	for find in catalog.finds:
		var machine_gives: bool = find == str(catalog.machine.get("intel", {}).get("find", ""))
		_check(machine_gives or catalog.events.values().any(func(e): return e.get("find", "") == find), "some event (or the machine) gives %s" % find)
	var meadow := catalog.location("meadow")
	var seen := false
	for t in 200:
		if "meadow_basket" in AdventureRunner.pick_events(meadow, t, { "basket": true }, catalog):
			seen = true
	_check(not seen, "a find's event stops turning up once it's found")
	# the basket waits for the flap: errands open once bits start holding the machine up
	var basket_before := false
	var basket_after := false
	for t in 200:
		basket_before = basket_before or "meadow_basket" in AdventureRunner.pick_events(meadow, t, {}, catalog)
		basket_after = basket_after or "meadow_basket" in AdventureRunner.pick_events(meadow, t, {}, catalog, { "flap": 1 })
	_check(not basket_before and basket_after, "the basket only turns up once the flap is fixed")
	# finds don't ask: the pet brings them home by itself, even with nobody answering
	var roller := PetRoller.new(catalog, RandomNumberGenerator.new())
	var herd: Array[Pet] = []
	for i in 3:
		herd.append(roller.roll("starter"))
	var run := AdventureRunner.start("meadow", herd.slice(0, 1), 0.0, 1, catalog)
	run.events.assign(["meadow_basket"])
	AdventureRunner.resolve(run, PlayerChooser.new(), 1.0e9, catalog)
	_check(run.status == RunState.Status.DONE and run.loot.has("find:basket") and str(run.history[0].text).begins_with("i found"),
		"a find comes home by itself, no question")
	for size in [2, 3]:
		var wagon := AdventureRunner.start("meadow", herd.slice(0, size), 0.0, 1, catalog)
		wagon.events.assign(["meadow_wagon"])
		AdventureRunner.resolve(wagon, PlayerChooser.new(), 1.0e9, catalog)
		_check(wagon.history.any(func(h): return h.event == "meadow_wagon") == (size >= 3), "the hay wagon only turns up for 3+ pets (%d)" % size)
	for e in catalog.events.values():
		if e.has("after_machine"):
			_check(not catalog.machine_tree.nodes.filter(func(n): return n.id == e.after_machine).is_empty(), "event %s waits for a real machine node" % e.id)
	# every bit the machine needs comes from somewhere a pet can go
	var bits_needed := {}
	for n in catalog.machine_tree.nodes:
		for b in n.get("bits", {}):
			bits_needed[b] = true
	for b in bits_needed:
		var from := catalog.locations.filter(func(l): return l.get("finish_rewards", []).any(func(r): return r.get("kind", "") == "bit" and r.get("id", "") == b))
		_check(not from.is_empty(), "some place's treat bag has %s" % b)
	# "open" waits for something an unlock really opens; the workbench never opens from parts
	# before parts are a feature (they used to slip in early)
	var opened := {}
	for entry in catalog.unlock_list:
		for o in entry.opens:
			opened[str(o)] = true
	for entry in catalog.unlock_list:
		if entry.earn.has("open"):
			_check(opened.has(str(entry.earn.open)), "unlock %s waits for something that opens (%s)" % [entry.id, entry.earn.open])
		if entry.earn.get("first", "") == "part":
			_check(str(entry.earn.get("open", "")) == "feature:parts", "unlock %s from a first part waits for parts too" % entry.id)
	# v20 closes what old gates opened: a save like Emilia's (basket and cart found, 9 trips, the
	# flap fixed but not better drops, no toys) loses the second page, the boxes tab and the workbench
	var hers := func(earn: Dictionary) -> bool:
		if earn.has("find") and not str(earn.find) in ["basket", "cart"]:
			return false
		return not (earn.has("machine") or earn.has("first") or earn.has("open") or int(earn.get("trips", 0)) > 9 or int(earn.get("packs_opened", 0)) > 22)
	var stale := UnlockRules.stale(catalog.unlock_list, hers)
	for o in ["page:beyond", "tab:boxes", "tab:inventory", "feature:toys", "feature:parts"]:
		_check(o in stale, "an old save without what earns it loses %s" % o)
	for o in ["feature:errands", "tab:errands", "feature:parties"]:
		_check(not o in stale, "an old save keeps %s it earned" % o)
	_check(UnlockRules.stale(catalog.unlock_list, func(_e): return true).is_empty(), "nothing closes when everything is earned")
	var automation: Array = catalog.unlock_list.filter(func(e): return "feature:packs" in e.opens or "feature:errands" in e.opens)
	_check(automation.all(func(e): return e.show == "hidden"), "automation stays hidden until found")
	var packs: Array = catalog.unlock_list.filter(func(e): return "feature:packs" in e.opens)
	_check(packs.all(func(e): return int(e.earn.get("packs_opened", 0)) >= 100), "your pet only opens packs after you've opened plenty yourself")


## Automation: jobs are real, its tools add up and cost more each level, your pet's machine cranks
## at its pace (faster with the crank, only while you're away with the stool), and the tab and its
## later jobs wait for what earns them.
func _test_automation(catalog: Catalog) -> void:
	var jobs: Array = catalog.automation.get("jobs", [])
	_check(jobs.size() >= 3 and Automation.job(catalog, "machine").get("needs", "") == "", "automation has its jobs, the machine first")
	for j in jobs:
		_check(int(j.coins) > 0, "job %s is taught with coins" % j.id)
		if j.has("needs"):
			var opened := catalog.unlock_list.any(func(e): return str(j.needs) in e.opens)
			_check(opened, "job %s waits for something that opens (%s)" % [j.id, j.needs])
	for t in Automation.all_tools(catalog):
		_check(Jobs.tool_cost(t, 1) > Jobs.tool_cost(t, 0), "tool %s costs more each level" % t.id)
	var state := Automation.fresh()
	var slow := Automation.crank_seconds(catalog, state)
	_check(Automation.crank(catalog, state, slow * 3.5) == 3, "your pet's machine pulls once every %ds" % roundi(slow))
	_check(Automation.tool_block(state, Automation.tool(catalog, "crank")) == "closed", "tools wait for their job to be taught")
	state.taught["machine"] = true
	_check(Automation.tool_block(state, Automation.tool(catalog, "crank")) == "", "a taught job's tools can be bought")
	state.tools["crank"] = 5
	_check(Automation.crank_seconds(catalog, state) < slow, "a smoother crank cranks faster")
	_check(Automation.away_seconds(catalog, state, 7200.0) == 0.0, "without a stool it stops while you're away")
	state.tools["stool"] = 1
	_check(is_equal_approx(Automation.away_seconds(catalog, state, 7200.0), 3600.0), "a stool keeps it going an hour while you're away")
	state.tools["crank"] = 999
	_check(Automation.tool_block(state, Automation.tool(catalog, "crank")) == "max", "tools stop at their max")
	# the tab opens with the tiny machine, once the machine is fully fixed; it's hidden until then
	var tab: Array = catalog.unlock_list.filter(func(e): return "tab:automation" in e.opens)
	_check(tab.size() == 1 and tab[0].show == "hidden" and tab[0].earn.get("machine", "") == "drops" and catalog.finds.has(str(tab[0].earn.get("find", ""))),
		"the automation tab stays hidden until the machine's fixed and the tiny machine is home")
	var ev: Array = catalog.events.values().filter(func(e): return str(e.get("find", "")) == "tiny_machine")
	_check(ev.size() == 1 and str(ev[0].get("after_machine", "")) == "drops", "the tiny machine only turns up once the machine is fully fixed")
	var boxes: Array = catalog.unlock_list.filter(func(e): return "feature:packs" in e.opens)
	_check(boxes.all(func(e): return str(e.earn.get("open", "")) == "tab:automation"), "opening boxes waits for the automation tab")
	# workers: taught to the others once your pet's tools are far enough, slower than your pet
	# (better with rarity), each needs a spot, and their tools only count for them
	var w := Automation.fresh()
	_check(Automation.teach_block(catalog, w, "machine") == "taught", "your pet learns a job before it teaches it")
	w.taught["machine"] = true
	var after: Dictionary = Automation.job(catalog, "machine").teach.get("after", {})
	if not after.is_empty():
		_check(Automation.teach_block(catalog, w, "machine") == "lv", "teaching the others waits for your pet's tools")
		for t in after:
			w.tools[t] = int(after[t])
	_check(Automation.teach_block(catalog, w, "machine") == "", "then it can teach the others")
	w.others["machine"] = true
	_check(Automation.teach_block(catalog, w, "machine") == "done", "you only teach them once")
	var common := Pet.new()
	common.rarity = "common"
	var mythic := Pet.new()
	mythic.rarity = catalog.tiers[catalog.tiers.size() - 1].id
	_check(Automation.worker_speed(catalog, common) < 1.0 and Automation.worker_speed(catalog, common) < Automation.worker_speed(catalog, mythic),
		"a common worker is slower than your pet, a rarer one faster than a common")
	_check(Automation.worker_speed(catalog, mythic) <= 1.0 + 0.001, "no worker beats your pet")
	_check(Automation.spot_cost(catalog, w, "machine") > 0 and Automation.spot_cost(catalog, w, "machine", 2) > 2 * Automation.spot_cost(catalog, w, "machine") - 1,
		"machines for workers cost more each")
	var base := Automation.worker_seconds(catalog, w, "machine")
	_check(Automation.work(catalog, w, "machine", 2.0, base * 5.25) == 10, "two full-speed workers pull twice as often")
	_check(Automation.work(catalog, w, "machine", 0.0, 1000.0) == 0, "no workers, no pulls")
	w.tools["grease"] = 3
	_check(Automation.worker_seconds(catalog, w, "machine") < base, "grease makes the workers' machines faster")
	_check(is_equal_approx(Automation.crank_seconds(catalog, w), Automation.crank_seconds(catalog, Automation.fresh()) / (1.0 + 0.1 * int(w.tools.get("crank", 0)))),
		"the workers' tools don't speed up your pet")


## Allowed difference between expected and rolled odds (about 4 standard deviations).
func _tolerance(p: float) -> float:
	return 4.0 * sqrt(p * (1.0 - p) / ROLLS) + 0.0005


## Every rummage spot can be drawn and pays something, and a rummaged spot waits to refill.
func _test_rummage(catalog: Catalog) -> void:
	_check(not catalog.rummage_spots.is_empty(), "there are spots to rummage in")
	for spot in catalog.rummage_spots:
		_check(str(spot.get("draw", "")) in ["dresser", "plant", "socks", "toybox"], "rummage spot %s has a drawing (RummageSpot)" % spot.id)
		_check(float(spot.refill) > 0.0 and int(spot.coins[0]) > 0 and int(spot.coins[1]) >= int(spot.coins[0]), "rummage spot %s pays and refills" % spot.id)


## The capsule machine and its upgrade tree: every prize pays something real, lucky capsules only
## hold lucky prizes, better-drops prizes wait for it, every node grows from a real node, costs grow,
## repairs open what grows from them, and the effects add up.
func _test_machine(catalog: Catalog) -> void:
	var m: Dictionary = catalog.machine
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var fresh := { "pulls": 0, "lit": 0, "bought": {} }
	for p in m.prizes:
		_check(str(p.kind) in ["coins", "golden", "xp", "part", "box", "toy", "pet_box"], "machine prize %s has a known kind" % p.id)
		if p.kind == "toy":
			continue  # GameState rolls the toy itself (Toys)
		if p.kind == "pet_box":
			_check(int(m.get("pet_box", {}).get("sure_within", 0)) > 0 and int(m.pet_box.get("few_pets", 0)) >= 1, "a pet box is sure to come when you're out of pets")
			_check(not catalog.box(str(p.box)).is_empty() and not p.has("drops"), "machine prize %s opens a real box from the start" % p.id)
			continue  # GameState rolls the pet itself
		if p.kind == "box":
			_check(not catalog.box(str(p.box)).is_empty(), "machine prize %s gives a real box" % p.id)
		var loot := Machine.loot(p, fresh, catalog, rng)
		_check(not loot.is_empty() and loot.values().all(func(n): return int(n) > 0), "machine prize %s pays something (%s)" % [p.id, loot])
	var seen := {}
	for i in 5000:
		seen[Machine.roll(fresh, catalog, rng).id] = true
		var lucky := Machine.roll(fresh, catalog, rng, true)
		if not lucky.get("lucky", false):
			_check(false, "a lucky capsule only holds lucky prizes (got %s)" % lucky.id)
			break
	for p in m.prizes:
		var waits := float(p.get("drops", 0)) > 0.0
		_check(seen.has(p.id) != waits, "machine prize %s %s a machine without better drops" % [p.id, "stays out of" if waits else "comes out of"])
	_check(int(Machine.loot(m.prizes[0], fresh, catalog, rng, 3.0).coins) >= 3, "fever multiplies the coins in a capsule")
	# the tree
	var ids := {}
	for n in catalog.machine_tree.nodes:
		ids[n.id] = true
	for n in catalog.machine_tree.nodes:
		_check(not n.has("from") or ids.has(n.from), "tree node %s grows from a real node" % n.id)
		_check(n.branch in Machine.BRANCHES, "tree node %s is on a known branch" % n.id)
		_check(n.at is Array and n.at.size() == 2, "tree node %s has a place on the map" % n.id)
		for b in n.get("bits", {}):
			_check(b in Machine.BITS, "tree node %s asks for a real bit (%s)" % [n.id, b])
		if int(n.get("max", 1)) > 1:
			var once := { "bought": { n.id: 1 } }
			_check(Machine.cost(once, catalog, n.id) >= Machine.cost(fresh, catalog, n.id), "tree node %s doesn't get cheaper" % n.id)
	var root: String = catalog.machine_tree.nodes[0].id
	_check(Machine.look(fresh, catalog, root) == "next", "the first repair can be worked on straight away")
	var child: Dictionary = catalog.machine_tree.nodes.filter(func(n): return n.get("from", "") == root)[0]
	_check(Machine.look(fresh, catalog, child.id) == "dim", "what grows from it shows, dim")
	var fixed := { "bought": { root: 1 } }
	_check(Machine.look(fixed, catalog, child.id) == "next", "fixing a node opens what grows from it")
	_check(Machine.coin_value(fixed, catalog) > Machine.coin_value(fresh, catalog), "the first repair makes capsules worth more")
	_check(Machine.blocker(fresh, catalog, root, 0, {}) == "coins", "no coins, no repair")
	_check(Machine.blocker(fresh, catalog, root, 1000000, {}) == "", "with coins, the first repair can be bought")
	var flap := { "bought": { "tape": 1, "oil": 1 } }
	_check(Machine.blocker(flap, catalog, "flap", 1000000, {}) == "spring", "a repair that needs a bit waits for it")
	_check(Machine.chutes(fresh, catalog) == 1 and Machine.chutes({ "bought": { "chute2": 1 } }, catalog) == 2, "a fixed chute is another chute")
	_check(not Machine.lights_on(fresh, catalog) and Machine.lights_on({ "bought": { "wires": 1 } }, catalog), "the lights work once they're rewired")
	var balls := 0
	for i in 1000:
		balls += Machine.balls_from_chute({ "bought": { "double": 5 } }, catalog, rng)
	_check(balls > 1100, "double drop sometimes gives two balls (%d from 1000)" % balls)


## Capsule toys: every toy has art and a real tier and bonus, rolls give real toys, boosts start
## small and grow with levels and finishes, wear shrinks them (never below the floor), plays take a
## slot and end with wear, spares combine into levels up to a favourite, sacrifice uses spares.
func _test_toys(catalog: Catalog) -> void:
	var d: Dictionary = catalog.toys
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for t in Toys.all(catalog):
		_check(d.tiers.has(t.tier), "toy %s has a real tier" % t.id)
		_check(Boosts.is_kind(catalog, t.bonus) or t.bonus == "all", "toy %s has a known bonus" % t.id)
		var rows: Array = d.art.get(t.id, [])
		_check(rows.size() == 14 and rows.all(func(r): return str(r).length() == 14), "toy %s has 14 x 14 art" % t.id)
		for r in rows:
			for ch in str(r):
				if ch != "." and not d.palette.has(ch):
					_check(false, "toy %s art uses a colour in the palette (%s)" % [t.id, ch])
	for i in 2000:
		var got := Toys.roll(catalog, rng, 1.0 + (i % 3))
		if Toys.toy(catalog, got.id).is_empty() or Toys.finish(catalog, got.finish).is_empty():
			_check(false, "a rolled toy is real (%s)" % got)
			break
	var state := Toys.fresh()
	_check(Toys.add(state, "acorn", "normal"), "a first acorn is a new edition")
	_check(not Toys.add(state, "acorn", "normal"), "a second acorn is a spare")
	_check(is_equal_approx(Toys.boost(state, catalog, "acorn:normal"), float(d.tiers.common.base)), "a new common toy boosts by its tier's base (x1.1)")
	Toys.add(state, "acorn", "ghost")
	_check(Toys.boost(state, catalog, "acorn:ghost") > Toys.boost(state, catalog, "acorn:normal"), "a ghost toy boosts more than a normal one")
	var now := 1000.0
	_check(is_equal_approx(Boosts.total(Toys.parts(state, catalog, "coins", now)), 1.0), "a toy on the shelf does nothing")
	_check(Toys.play(state, catalog, "acorn:normal", "quick", now), "your pet can play with a toy")
	_check(Boosts.total(Toys.parts(state, catalog, "coins", now + 1.0)) > 1.0, "a toy being played with boosts")
	_check(not Toys.play(state, catalog, "acorn:ghost", "quick", now), "one play slot to start")
	_check(Toys.finish_plays(state, now + 60.0).is_empty(), "a play isn't over early")
	var ended := Toys.finish_plays(state, now + 3600.0)
	_check(ended == ["acorn:normal"] and float(state.owned["acorn:normal"].wear) > 0.0, "a finished play wears the toy")
	_check(is_equal_approx(Boosts.total(Toys.parts(state, catalog, "coins", now + 3601.0)), 1.0), "after playing the boost stops")
	state.owned["acorn:normal"].wear = 1.0
	var worn := Toys.boost(state, catalog, "acorn:normal") - 1.0
	_check(worn > 0.0 and worn >= (float(d.tiers.common.base) - 1.0) * float(d.worn_floor) - 0.0001, "a worn out toy still works a little")
	_check(Toys.fix_cost(state, catalog, "acorn:normal") > 0, "fixing a worn toy costs something")
	state.owned["acorn:normal"].spares = 20
	var level := 1
	while Toys.combine(state, catalog, "acorn:normal"):
		level += 1
	_check(level == int(d.max_level) and Toys.is_favourite(state, catalog, "acorn:normal"), "spares combine up to a favourite")
	_check(Toys.boost(state, catalog, "acorn:normal") > float(d.tiers.common.base), "levels make the boost bigger")
	_check("acorn:normal" in Toys.active(state, catalog, now), "a favourite is always on")
	_check(not Toys.play(state, catalog, "acorn:normal", "quick", now), "a favourite doesn't need playtime")
	state.owned["acorn:normal"].spares = int(d.sacrifice.spares)
	var before: int = state.owned.size()
	var got := Toys.sacrifice(state, catalog, "acorn", rng)
	_check(int(state.owned["acorn:normal"].spares) == 0, "sacrifice uses the spares either way")
	_check(got == "" or state.owned.size() >= before, "a lucky sacrifice gives a special edition")
	_check(not Toys.can_sacrifice(state, catalog, "acorn"), "no spares, no sacrifice")
	var full := Toys.fresh()
	for t in catalog.toys.sets[0].toys:
		Toys.add(full, t.id, "normal")
	_check(Toys.slots(full, catalog) == int(d.slots) + 1, "a finished set gives another play slot")


## Boosts: one kind table (data/boosts.json), every source gives parts { source, id, x }, the total
## is their product. Toys are the source so far: a playing toy or a favourite counts, a finished play
## doesn't, an "all" toy counts for the kinds marked all, and other sources multiply on top.
func _test_boosts(catalog: Catalog) -> void:
	var ids := Boosts.kinds(catalog)
	for k in catalog.boosts.kinds:
		_check(str(k.get("id", "")) != "" and str(k.get("name", "")) != "", "boost kind %s has an id and a name" % k)
	for src in catalog.boosts.sources:
		_check(str(src) != "", "boost sources have names")
	for t in Toys.all(catalog):
		_check(t.bonus in ids or t.bonus == "all", "toy %s's bonus is a boost kind" % t.id)
	var now := 1000.0
	var state := Toys.fresh()
	for k in ids:
		var none := Toys.parts(state, catalog, k, now)
		_check(none.is_empty() and is_equal_approx(Boosts.total(none), 1.0), "no toys, no %s boost" % k)
	Toys.add(state, "acorn", "normal")  # coins
	Toys.add(state, "acorn", "holo")  # coins
	Toys.add(state, "moth", "normal")  # all
	Toys.add(state, "snail", "normal")  # speed, stays on the shelf
	for key in ["acorn:normal", "acorn:holo", "moth:normal"]:
		state.playing.append({ "key": key, "until": now + 600.0, "wear": 0.0 })
	var coins := Toys.parts(state, catalog, "coins", now)
	_check(coins.size() == 3 and coins.all(func(p): return p.source == "toys"), "two coins toys and an all toy: three coins parts")
	_check(Toys.parts(state, catalog, "luck", now).size() == 1, "the all toy counts for luck")
	_check(Toys.parts(state, catalog, "speed", now).is_empty(), "a speed toy on the shelf does nothing")
	_check(Toys.parts(state, catalog, "fever", now).is_empty(), "an all toy doesn't count for kinds not marked all")
	var product := 1.0
	for key in ["acorn:normal", "acorn:holo", "moth:normal"]:
		product *= Toys.boost(state, catalog, key)
	_check(product > 1.0 and is_equal_approx(Boosts.total(coins), product), "the coins total is every toy's boost multiplied")
	var holo := coins.filter(func(p): return p.id == "acorn:holo")
	_check(holo.size() == 1 and is_equal_approx(float(holo[0].x), Toys.boost(state, catalog, "acorn:holo")), "a part is its edition and its boost")
	_check(Toys.parts(state, catalog, "coins", now + 601.0).is_empty(), "a play that's over counts no more")
	state.owned["snail:normal"].level = int(catalog.toys.max_level)
	var fav := Toys.parts(state, catalog, "speed", now + 601.0)
	_check(fav.size() == 1 and fav[0].id == "snail:normal", "a favourite counts without playing")
	var book := Boosts.part("book", "page:meadow", 1.5)
	_check(is_equal_approx(Boosts.total(coins + [book]), product * 1.5), "boosts from different sources multiply")
	_check(is_equal_approx(Boosts.total([]), 1.0), "nothing boosting is x1")
	_check(not Boosts.is_kind(catalog, "no such kind") and Boosts.kind(catalog, "no such kind").is_empty(), "an unknown kind isn't in the table")
	_check(Toys.parts(state, catalog, "no such kind", now).is_empty(), "no toy boosts an unknown kind")


## Gear: xp upgrades to adventuring (data/gear.json, Gear), and what they do on a trip.
func _test_gear(catalog: Catalog) -> void:
	var all := Gear.all(catalog)
	_check(all.size() == 8, "there are 8 gear upgrades (%d)" % all.size())
	var opened := {}
	for entry in catalog.unlock_list:
		for o in entry.opens:
			opened[str(o)] = true
	var base: Dictionary = catalog.gear.base
	var seen := {}
	var icons := FileAccess.get_file_as_string("res://scripts/ui/ui_theme.gd")  # UiTheme needs the game running
	for g in all:
		for field in ["name", "icon", "color", "does", "xp", "grow", "max", "each", "show"]:
			_check(g.has(field), "gear %s has %s" % [g.id, field])
		_check(icons.contains('"%s":' % g.icon), "gear %s has a real icon" % g.id)
		if g.has("after"):
			_check(seen.has(str(g.after)), "gear %s comes after an earlier one (%s)" % [g.id, g.after])
		if g.has("needs"):
			var needs := str(g.needs)
			var known := opened.has(needs) or (needs.begins_with("location:") and not catalog.location(needs.substr(9)).is_empty())
			_check(known, "gear %s waits for something real (%s)" % [g.id, needs])
		for key in ["show", "show_parts"]:
			if g.has(key):
				for m in RegEx.create_from_string("\\{(\\w+)%?\\}").search_all(str(g[key])):
					_check(g.each.has(m.get_string(1)) or base.has(m.get_string(1)), "gear %s shows %s, a value it changes" % [g.id, m.get_string(1)])
		for lv in range(1, int(g.max) + 1):
			var text := Gear.words(catalog, g.id, lv, true)
			_check(text != "" and not "{" in text, "gear %s lv %d reads: %s" % [g.id, lv, text])
		seen[g.id] = true

	_check(Gear.price(catalog, "boots", 0) == 30 and Gear.price(catalog, "boots", 1) == 48, "boots cost 30, then x1.6 (%d)" % Gear.price(catalog, "boots", 1))
	_check(is_equal_approx(Gear.value(catalog, { "boots": 5 }, "walk"), 0.4), "boots lv 5: trips 40% shorter")
	_check(Gear.value(catalog, {}, "treat_every") == 15.0 and Gear.value(catalog, { "pouch": 3 }, "treat_every") == 9.0
		and Gear.value(catalog, { "pouch": 3 }, "treat_zoom") == 11.0, "the treat pouch: a treat every 9 s, zoom 11 s at lv 3")
	_check(is_equal_approx(Gear.value(catalog, { "paws": 3 }, "streak_max"), 2.25), "sticky paws lv 3: streaks up to x2.25")
	_check(is_equal_approx(Gear.value(catalog, { "eyes": 3 }, "part_x"), 2.5), "sharper eyes lv 3: trail parts x2.5 (4 -> 10)")
	_check(Gear.words(catalog, "boots", 1) == "trips 8% shorter" and Gear.words(catalog, "boots", 0) == "as usual", "boots read as numbers")
	_check(Gear.words(catalog, "pouch", 1) == "a treat every 13\u00a0s, zoom 9\u00a0s", "the pouch reads as numbers (%s)" % Gear.words(catalog, "pouch", 1))
	_check(Gear.words(catalog, "eyes", 3) == "+45% bits" and Gear.words(catalog, "eyes", 3, true) == "+45% bits, trail parts x2.5",
		"sharper eyes only mention parts once they're open")
	_check(Gear.clean(catalog, { "boots": 99, "nope": 2, "tote": -1 }) == { "boots": 5 }, "saved gear is clamped and cleaned")

	# the path: boots and the tote first, the rest once their "after" has a level and "needs" is open
	var closed := func(_id): return false
	var everything := func(_id): return true
	var ids := func(list): return list.map(func(g): return g.id)
	_check(ids.call(Gear.shown(catalog, {}, everything)) == ["boots", "tote"], "a fresh path shows boots and the tote")
	_check("pouch" in ids.call(Gear.shown(catalog, { "boots": 1 }, closed)), "boots bring the treat pouch onto the path")
	var mid := { "boots": 1, "tote": 1, "pouch": 1, "paws": 1, "eyes": 1 }
	_check(not "charm" in ids.call(Gear.shown(catalog, mid, closed)), "the charm waits for the meadow")
	_check("charm" in ids.call(Gear.shown(catalog, mid, func(id): return id == "location:meadow")), "the charm shows once the meadow is open")
	var late := mid.merged({ "leaf": 1 })
	_check(not "harness" in ids.call(Gear.shown(catalog, late, func(id): return id == "location:meadow")), "the harness waits for the wheelbarrow")
	_check("harness" in ids.call(Gear.shown(catalog, late, everything)), "the harness shows with parties of 5")
	_check(Gear.for_trip(catalog, { "boots": 3 }, catalog.location("well")).is_empty(), "no gear in dungeons")
	_check(Gear.for_trip(catalog, { "boots": 3 }, catalog.location("meadow")) == { "boots": 3 }, "trips pack the gear")

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var roller := PetRoller.new(catalog, rng)
	var bean: Array[Pet] = [roller.roll("starter", "common")]
	# comfy boots: shorter walks
	var plain := AdventureRunner.start("garden", bean, 0.0, 1, catalog)
	var booted := AdventureRunner.start("garden", bean, 0.0, 1, catalog, {}, {}, { "boots": 5 })
	_check(is_equal_approx(AdventureRunner.run_gap(booted, catalog), AdventureRunner.run_gap(plain, catalog) * 0.6) and is_equal_approx(booted.next_at, plain.next_at * 0.6),
		"boots lv 5: 0.6 x the walk")
	# the lucky charm: only risky options, never past the cap, never at a safe place
	var meadow := catalog.location("meadow")
	var party := Party.make(bean, catalog)
	var risky := { "chance": 0.5, "failure": { "text": "", "hurt": [1, 1] } }
	var sure := { "chance": 0.9, "failure": { "text": "", "lost": [1, 1] } }
	var safe := { "chance": 0.5, "failure": { "text": "" } }
	_check(is_equal_approx(AdventureRunner.success_chance(risky, party, meadow, 0.12), 0.62), "the charm adds its luck to a risky option")
	_check(is_equal_approx(AdventureRunner.success_chance(sure, party, meadow, 0.12), AdventureRunner.MAX_CHANCE), "the charm stays under the cap")
	_check(is_equal_approx(AdventureRunner.success_chance(safe, party, meadow, 0.12), 0.5), "the charm does nothing for a safe option")
	_check(is_equal_approx(AdventureRunner.success_chance(risky, party, catalog.location("garden"), 0.12), 0.5), "nothing's risky in the garden")
	# the comfy harness: fewer losses on the same trips
	var lost_plain := _gear_losses("meadow", bean, {}, catalog)
	var lost_harness := _gear_losses("meadow", bean, { "harness": 3 }, catalog)
	_check(lost_harness < lost_plain, "the harness means fewer losses (%d vs %d)" % [lost_harness, lost_plain])
	# the first-aid leaf: a hurt pet hurt again stays (once a trip per level), then it's lost
	var p2 := Party.make(bean, catalog)
	p2.hurt(1, 1, rng)
	var saved := p2.hurt(1, 1, rng, 1, 0.0)
	_check(p2.size() == 1 and saved.saved == 1 and saved.lost == 0, "the leaf saves a pet hurt again")
	p2.hurt(1, 1, rng, 0, 0.0)
	_check(p2.size() == 0, "with no saves left it doesn't come back")
	var hurt_event := {}
	var hurt_pick := -1
	for entry in meadow.pool:
		var e: Dictionary = catalog.events[entry.event]
		for j in e.options.size():
			var fail: Dictionary = e.options[j].get("failure", {})
			if hurt_pick < 0 and fail.has("hurt") and int(fail.get("hearts", 1)) == 1 and not fail.has("lost"):
				hurt_event = e
				hurt_pick = j
	var leaf_checked := false
	for t in 100:
		var run := AdventureRunner.start("meadow", bean, 0.0, t, catalog, {}, {}, { "leaf": 1 })
		run.party.injured[bean[0].uid] = true
		var fails := 0
		for k in 40:
			if run.party.size() == 0:
				break
			var entry := AdventureRunner.play(hurt_event, hurt_pick, run, catalog)
			if not entry.success:
				fails += 1
				if fails == 1:
					_check(run.party.size() == 1 and run.saves_used == 1 and str(entry.text).ends_with(Gear.leaf_text(catalog)),
						"the leaf saves a hurt solo pet once (%s)" % entry.text)
		if fails >= 2:
			_check(run.party.size() == 0, "a second hit with no saves left loses it")
			leaf_checked = true
			var back := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())), catalog)
			_check(back.gear == { "leaf": 1 } and back.saves_used == 1, "a run keeps its gear and saves through a save")
			break
	_check(leaf_checked, "the leaf test found a trip with two misses")
	# sharper eyes: more bits in the treat bag
	var bits := [0, 0]
	for t in 400:
		for i in 2:
			var run := AdventureRunner.start("meadow", bean, 0.0, t, catalog, {}, {}, {} if i == 0 else { "eyes": 3 })
			AdventureRunner._finish_treat(run, meadow, catalog)
			bits[i] += Rewards.total(run.loot, "bit")
	_check(bits[1] > bits[0] * 1.2, "sharper eyes bring more bits home (%d vs %d)" % [bits[1], bits[0]])


## Pets lost over 200 meadow trips always taking the riskiest option, with this gear packed.
func _gear_losses(place_id: String, pets: Array[Pet], gear: Dictionary, catalog: Catalog, knacks := {}) -> int:
	var place := catalog.location(place_id)
	var lost := 0
	for t in 200:
		var run := AdventureRunner.start(place_id, pets, 0.0, t, catalog, {}, {}, gear, knacks)
		var now := 0.0
		for i in 20:
			if run.status == RunState.Status.DONE:
				break
			if run.status == RunState.Status.WAITING:
				var options := AdventureRunner.options_of(run.current_event(catalog), place)
				var riskiest := 0
				for j in options.size() - 1:
					if float(options[j].get("chance", 1.0)) < float(options[riskiest].get("chance", 1.0)):
						riskiest = j
				run.answer = riskiest
			AdventureRunner.resolve(run, PlayerChooser.new(), now, catalog)
			now += 1.0e5
		lost += run.party.lost.size()
	return lost


## The collection book's reward stickers (data/book.json, Book): full pages open a permanent boost
## that multiplies with the other sources and never goes away.
func _test_book(catalog: Catalog) -> void:
	var pages := Book.pages(catalog)
	_check(pages.size() == 6, "the book has 6 sticker pages (%d)" % pages.size())
	var kinds := {}
	for p in pages:
		var real: bool = (p.has("slot") and catalog.slots.has(str(p.slot))) or (p.has("finishes_of") and not catalog.part("body", str(p.finishes_of)).is_empty())
		_check(real, "sticker page %s is on a real slot or body" % p.id)
		_check(float(p.x) > 1.0, "sticker %s boosts (x%.2f)" % [p.id, float(p.x)])
		_check(str(p.kind) in ["coins", "luck", "automation", "errands"], "sticker %s has a known kind" % p.id)
		_check(Book.words(catalog, p) != "" and not Book.words(catalog, p).contains("{"), "sticker %s's line reads right (%s)" % [p.id, Book.words(catalog, p)])
		_check(str(p.name) != "sticky paws", "no sticker is sticky paws (a gear upgrade now)")
		kinds[str(p.kind)] = true
	_check(kinds.size() == 4, "all 4 kinds are on a page")
	_check(Book.words(catalog, Book.page(catalog, "palettes")) == "+10% coins", "the paint set reads +10% coins")
	# full: every key of the page, and the finishes page only looks at its body
	var c := Collection.new()
	var eyes := Book.page(catalog, "eyes")
	var keys := Book.keys(catalog, eyes)
	_check(keys.size() == catalog.slots.eyes.size(), "the eyes page needs every eyes part")
	for k in keys.slice(0, keys.size() - 1):
		c.see(k)
	_check(not Book.full(catalog, c, eyes), "a page with one sticker missing isn't full")
	var seen_signals := [0]
	c.seen_changed.connect(func(): seen_signals[0] += 1)
	c.see(keys[keys.size() - 1])
	_check(Book.full(catalog, c, eyes), "a page with every sticker is full")
	_check(seen_signals[0] == 1, "see() says the book changed (%d)" % seen_signals[0])
	var fin := Book.page(catalog, "finishes")
	for f in catalog.finishes:
		c.see(Collection.finish_key("cat", f.id))
	_check(not Book.full(catalog, c, fin), "the finishes sticker only counts blob's finishes")
	for f in catalog.finishes:
		c.see(Collection.finish_key(str(fin.finishes_of), f.id))
	_check(Book.full(catalog, c, fin), "every blob finish fills the finishes page")
	_check(Book.newly_full(catalog, c, []) == ["eyes", "finishes"], "newly full lists the full pages")
	_check(Book.newly_full(catalog, c, ["eyes"]) == ["finishes"], "newly full skips stickers already open")
	_check(is_equal_approx(Boosts.total(Book.parts(catalog, [], "coins")), 1.0), "no stickers, no boost")
	_check(is_equal_approx(Boosts.total(Book.parts(catalog, ["palettes", "finishes"], "coins")), 1.21), "both coins stickers multiply to x1.21")
	_check(is_equal_approx(Boosts.total(Book.parts(catalog, ["palettes", "finishes"], "luck")), 1.0), "kinds don't mix")
	# permanent: a new part on the page later doesn't take the sticker away
	var more := Catalog.new()
	var fake: Dictionary = more.slots.palette[0].duplicate()
	fake.id = "brand_new"
	more.slots.palette.append(fake)
	var pal := Book.page(more, "palettes")
	var c2 := Collection.new()
	for k in Book.keys(catalog, pal):
		c2.see(k)
	_check(not Book.full(more, c2, pal) and is_equal_approx(Boosts.total(Book.parts(more, ["palettes"], "coins")), 1.1),
		"an open sticker stays when its page gets a new part")

	# GameState: stickers open once, are saved, and reach every boost path
	var GS: GDScript = load("res://scripts/game_state.gd")
	GS.testing = true  # never loads or saves the real game
	var gs: Node = GS.new()
	var opened: Array[String] = []
	gs.sticker_opened.connect(func(id): opened.append(id))
	var body_pets: Array[Pet] = []
	for b in catalog.slots.body:
		var pet := Pet.new()
		pet.parts = { "body": b.id, "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
		body_pets.append(pet)
	var last: Array[Pet] = [body_pets.pop_back()]
	gs.collection.add(body_pets)
	_check(opened.is_empty() and gs.stickers.is_empty(), "no sticker while a body is missing")
	var tb: float = gs.workers_speed("machine")
	var crank_before := Automation.crank_seconds(catalog, gs.automation, gs.boost("automation"))
	var auto_before: float = gs.boost("automation")
	gs.automation.workers["machine"] = [gs.collection.pets[1].uid]
	gs._worker_speed.clear()
	var worker_before: float = gs.workers_speed("machine")
	gs.collection.add(last)
	_check(opened == ["bodies"] and gs.stickers == ["bodies"], "the last body opens the bodies sticker (%s)" % [opened])
	var again: Array[Pet] = [Pet.new()]
	again[0].parts = { "body": "blob", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
	gs.collection.add(again)
	_check(opened.size() == 1, "a sticker opens only once")
	_check(Automation.crank_seconds(catalog, gs.automation, gs.boost("automation")) < crank_before, "the automation sticker makes your pet crank faster")
	_check(gs.workers_speed("machine") * gs.boost("automation") > worker_before * auto_before and worker_before > tb, "the automation sticker makes the workers faster")
	# coins and luck: the book times the toys
	gs.coins = 0
	gs.grant({ "coins": 100 })
	_check(gs.coins == 100, "no coins sticker yet: 100 coins are 100")
	for k in Book.keys(catalog, Book.page(catalog, "palettes")):
		gs.collection.see(k)
	gs.check_book()
	gs.coins = 0
	gs.grant({ "coins": 100 })
	_check(gs.coins == 110, "the paint set makes 100 coins 110 (%d)" % gs.coins)
	Toys.add(gs.toys, "acorn", "normal")
	Toys.play(gs.toys, catalog, "acorn:normal", "quick", Time.get_unix_time_from_system())
	gs._boosts_changed()
	gs.coins = 0
	gs.grant({ "coins": 100 })
	_check(gs.coins == 121, "a coins toy and the paint set multiply (x1.1 x1.1: %d)" % gs.coins)
	for k in keys:
		gs.collection.see(k)
	gs.check_book()
	_check(is_equal_approx(gs.boost("luck"), Boosts.total(Toys.parts(gs.toys, catalog, "luck", Time.get_unix_time_from_system())) * 1.1), "luck is the toys' luck times the magnifying glass")
	# errands: every job's meter fills faster
	gs.unlocks["feature:errands"] = true
	var uid: String = gs.collection.pets[2].uid
	gs.jobs["coin_hunt"] = { "crew": [uid], "fill": 0.0 }
	gs._crews_changed()
	var rate_before: float = gs.job_rate("coin_hunt")
	for k in Book.keys(catalog, Book.page(catalog, "patterns")):
		gs.collection.see(k)
	gs.check_book()
	_check(rate_before > 0.0 and is_equal_approx(gs.job_rate("coin_hunt"), rate_before * 1.1), "the washi tape makes errands 10%% faster (%.4f to %.4f)" % [rate_before, gs.job_rate("coin_hunt")])
	# the save keeps them; an old save with a full page gets its sticker after loading
	# its own file in the lane's profile when there is one (user:// is shared by every worktree)
	var path := DevProfile.path("book_save.json") if DevProfile.active() else "user://profiles/test-core/book_save.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	gs.save_path = path
	gs._can_save = true
	gs.save_game()
	var gs2: Node = GS.new()
	gs2.save_path = path
	gs2.load_game()
	_check(gs2.stickers == gs.stickers, "a save round trip keeps the stickers (%s)" % [gs2.stickers])
	var old := { "version": 23, "collection": { "seen": {} } }
	for k in keys:
		old.collection.seen[k] = 1
	SaveFile.write(path, old)
	var gs3: Node = GS.new()
	var got3: Array[String] = []
	gs3.sticker_opened.connect(func(id): got3.append(id))
	gs3.save_path = path
	gs3.load_game()
	_check(got3.is_empty(), "loading opens no sticker halfway through (%s)" % [got3])
	gs3.check_book()
	_check(got3 == ["eyes"] and gs3.stickers == ["eyes"], "a v23 save with a full page gets its sticker after loading (%s)" % [got3])
	for f in [path, path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	for n in [gs, gs2, gs3]:
		n.free()
	GS.testing = false  # the GameState tests (X4) load their own saves


# ---- GameState itself (X4): old saves, time away, auto parties, workers, gear and the new jobs ----
# These make a real GameState from a save written into the test profile (--profile=...). Without a
# profile they're skipped: they must never read or write the real save.

const GAME_STATE := "res://scripts/game_state.gd"


func _test_game_state(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("skipped the GameState tests: run with -- --profile=core-test-<lane> so they get a save of their own")
		_skipped.append("the GameState tests (no --profile)")
		return
	# "test" is the profile every --from=<save> run plays in: these tests would wipe its save
	if DevProfile.profile_name() == "test":
		_check(false, "the GameState tests need a profile of their own, not \"test\" (try core-test-<lane>)")
		return
	var start := Time.get_ticks_msec()
	_test_migrations(catalog)
	_test_crank_catch_up(catalog)
	_test_auto_adventures(catalog)
	_test_many_workers(catalog)
	_test_gear_state(catalog)
	_test_jobs_state(catalog)
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	print("GameState tests took %.1f s" % ((Time.get_ticks_msec() - start) / 1000.0))


## Writes `data` as the test profile's save, closed `away` seconds ago (negative: saved in the
## future, so nothing catches up), and loads a GameState from it.
func _state_from(data: Dictionary, away := -60.0) -> Node:
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var d := data.duplicate(true)
	d.saved_at = Time.get_unix_time_from_system() - away
	SaveFile.write(path, d)
	return load(GAME_STATE).new()


## The profile's save as the last save_game() wrote it.
func _saved() -> Dictionary:
	return SaveFile.read(DevProfile.path("save.json"))


## Loads the profile's save again, as a fresh start of the game (nothing catches up).
func _reload() -> Node:
	return _state_from(_saved())


## A collection of `n` pets from starter boxes, pet "1" active. `spread`: every rarity in turn
## (workers of different speeds); otherwise all commons.
func _collection_dict(n: int, spread := false, rng_seed := 11) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var roller := PetRoller.new(Catalog.shared(), rng)
	var tiers := Catalog.shared().tiers
	var batch: Array[Pet] = []
	for i in n:
		batch.append(roller.roll("starter", str(tiers[i % tiers.size()].id) if spread else "common"))
	var c := Collection.new()
	c.add(batch)
	c.set_active("1")
	return c.to_dict()


## A save shaped like `version` wrote it (21 and up): 30 pets well into the game, the machine
## fully fixed, the automation tab open, errands going. v22 added gear, v23 scout notes, v24 stickers,
## v25 the box reserve in capsules.
func _old_save(version: int, pets := 30, spread := false) -> Dictionary:
	var d := {
		"version": version, "coins": 5000000, "xp": 40, "hunger": 70.0, "happiness": 60.0, "pet_out": false,
		"collection": _collection_dict(pets, spread), "bag": {}, "parts": {}, "items": {},
		"unlocks": ["feature:errands", "tab:errands", "feature:parties", "location:meadow", "tab:boxes", "feature:toys",
			"tab:automation", "feature:auto_adventures"],
		"trips_done": 30, "heard": [], "rumours": [], "tutorial": "done", "spotted": {}, "spot_tries": {},
		"finds": ["basket", "cart", "tiny_machine"], "packs_by_hand": 10, "parts_ever": false, "announcements": [],
		"jobs": {}, "jobs_auto": false, "errand_tools": {}, "coin_reserve": 50, "saved_boxes": [],
		"visited": ["garden", "meadow"], "buying_on": true, "pinned": [], "rummaged": {},
		"machine": { "pulls": 900, "lit": 0, "bought": { "tape": 1, "oil": 1, "flap": 1, "glass": 1, "wires": 1, "drops": 1 } },
		"toys": Toys.fresh(), "bits": { "gear": 2, "spring": 1 }, "started_at": 0.0, "milestones": {}, "idle_log": {},
		"automation": Automation.fresh(), "runs": [],
	}
	if version >= 22:
		d.gear = {}
	if version >= 23:
		d.scout_notes = 0
	if version >= 24:
		d.stickers = []
	if version >= 25:
		d.erase("coin_reserve")
		d.reserve_capsules = 50
	return d


## The v21 save the migration tests start from: every automation field in use, errand crews and
## tools, and an auto party (slot 0) out on a trip.
func _v21_save(catalog: Catalog, version := 21) -> Dictionary:
	var d := _old_save(version)
	d.jobs = { "coin_hunt": { "crew": ["20", "21"], "fill": 0.25 } }
	d.errand_tools = { "noses": 3, "paws": 2 }
	d.automation = { "task": "adventures", "taught": { "machine": true, "adventures": true }, "tools": { "crank": 3, "stool": 1 },
		"party": { "place": "meadow", "n": 3 }, "fill": 0.5, "others": { "machine": true, "adventures": true },
		"spots": { "machine": 3, "adventures": 2 }, "workers": { "machine": ["5", "6", "7"], "adventures": ["8", ""] },
		"parties": [{ "place": "meadow", "n": 3 }, { "place": "", "n": 0 }], "wfill": { "machine": 0.3 } }
	var c := Collection.from_dict(d.collection)
	var going: Array[Pet] = [c.get_pet("10"), c.get_pet("11"), c.get_pet("12")]
	var run := AdventureRunner.start("meadow", going, Time.get_unix_time_from_system(), 5, catalog, {}, d.machine.bought)
	run.auto = true
	run.slot = 0
	run.chooser = "policy"
	d.runs = [run.to_dict()]
	return d


## A save as it is on disk, minus when it was written (to compare two saves).
func _same_save(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate(true)
	var y := b.duplicate(true)
	x.erase("saved_at")
	y.erase("saved_at")
	return JSON.stringify(x) == JSON.stringify(y)


## Old saves load with every field moved over, and nothing lost on the way.
func _test_migrations(catalog: Catalog) -> void:
	var gs = _state_from(_v21_save(catalog))
	_check(gs.gear == {} and gs.scout_notes == 0 and gs.stickers.is_empty(), "a v21 save starts with no gear, scout notes or stickers")
	_check(gs.collection.pets.size() == 30 and gs.collection.active_uid == "1", "a v21 save keeps its pets and active pet")
	_check(gs.coins == 5000000 and gs.xp == 40 and gs.trips_done == 30 and gs.bits == { "gear": 2, "spring": 1 },
		"a v21 save keeps coins, xp, trips and bits")
	_check(Machine.owned(gs.machine, "drops") == 1 and int(gs.machine.pulls) == 900, "a v21 save keeps its machine")
	for id in ["feature:errands", "tab:automation", "feature:auto_adventures", "location:meadow", "tab:boxes"]:
		_check(gs.is_unlocked(id), "a v21 save keeps %s open" % id)
	var a: Dictionary = gs.automation
	_check(a.task == "adventures" and a.taught.has("machine") and a.taught.has("adventures"), "a v21 save keeps its pet's job (%s)" % a.task)
	_check(a.tools == { "crank": 3, "stool": 1 } and is_equal_approx(float(a.fill), 0.5), "a v21 save keeps its pet's tools and crank (%s)" % [a.tools])
	_check(a.party == { "place": "meadow", "n": 3 }, "a v21 save keeps where its party goes (%s)" % [a.party])
	_check(a.others.has("machine") and a.others.has("adventures") and a.spots == { "machine": 3, "adventures": 2 }, "a v21 save keeps the workers page")
	_check(a.workers.get("machine", []) == ["5", "6", "7"] and a.workers.get("adventures", []) == ["8", ""],
		"a v21 save keeps its workers, an empty party slot too (%s)" % [a.workers])
	_check(a.parties.size() == 2 and str(a.parties[0].place) == "meadow" and is_equal_approx(float(a.wfill.get("machine", 0.0)), 0.3),
		"a v21 save keeps its parties and the workers' crank")
	_check(gs.worker_job("5") == "machine" and gs.worker_job("8") == "adventures", "loaded workers know their jobs")
	_check(gs.job_crew("coin_hunt") == ["20", "21"] and is_equal_approx(gs.job_fill("coin_hunt"), 0.25), "a v21 save keeps its errand crew")
	_check(gs.errand_tools == { "noses": 3, "paws": 2 }, "a v21 save keeps its errand tools")
	var run = gs.auto_run(0)
	_check(gs.runs.size() == 1 and run != null and run.auto and run.chooser == "policy" and ",".join(run.party.uids) == "10,11,12",
		"a v21 save keeps the workers' party out on its trip")
	# round trip: saved at SAVE_VERSION, loading that again changes nothing
	gs.save_game()
	var first := _saved()
	gs.free()
	_check(int(first.version) == gs_version(), "a loaded save is written at the current version (%d)" % int(first.version))
	var again = _reload()
	again.save_game()
	_check(_same_save(first, _saved()), "loading a saved game and saving it again changes nothing")
	again.free()
	# v22 (gear, no scout notes yet), v23 (scout notes, no stickers yet) and v24 (stickers, reserve still
	# in coins) saves load the same way
	var v21 = _state_from(_v21_save(catalog, 21))
	v21.save_game()
	var from_21 := _saved()
	v21.free()
	var x := from_21.duplicate(true)
	x.runs = []  # the runs were started a moment apart
	for version in [22, 23, 24]:
		var later = _state_from(_v21_save(catalog, version))
		later.save_game()
		var y := _saved()
		later.free()
		y.runs = []
		_check(_same_save(x, y), "v21 and v%d saves load the same" % version)
	# v25: the reserve an older save kept in coins becomes capsules at what one was worth on its machine
	for step in [[8000, 1000], [3, 1], [0, 0]]:
		var v24 := _old_save(24)
		v24.machine.bought = { "tape": 1, "oil": 1, "flap": 1 }
		v24.coin_reserve = step[0]
		var gs24 = _state_from(v24)
		_check(gs24.reserve_capsules == step[1] and gs24.coin_reserve() == roundi(step[1] * gs24.capsule_value()),
			"a v24 save keeping %d coins keeps %d capsules (%d)" % [step[0], step[1], gs24.reserve_capsules])
		gs24.free()
	var v25 = _state_from(_old_save(25))
	_check(v25.reserve_capsules == 50, "a v25 save keeps its reserve in capsules (%d)" % v25.reserve_capsules)
	v25.free()
	# v14: your pet opening packs becomes the automation tab's boxes job
	for on in [true, false]:
		var old := { "version": 14, "coins": 100, "collection": _collection_dict(5), "tutorial": "done",
			"unlocks": ["feature:packs", "feature:errands", "tab:errands"], "packs_on": on }
		var gs14 = _state_from(old)
		_check(gs14.knows_job("boxes") and gs14.is_unlocked("tab:automation") and gs14.packs_on == on and gs14.automation.task == ("boxes" if on else ""),
			"a v14 save with the cushion knows the boxes job (%s, task %s)" % ["on" if on else "off", gs14.automation.task])
		gs14.free()
	# v17 (the capsule machine's time, re-gated by v20): the cushion's boxes job still stays
	var v17 := { "version": 17, "coins": 100, "collection": _collection_dict(5), "tutorial": "done",
		"unlocks": ["feature:packs", "tab:boxes"], "packs_on": true, "machine": { "pulls": 10, "lit": 0, "bought": {} } }
	var gs17 = _state_from(v17)
	_check(gs17.knows_job("boxes") and gs17.packs_on and gs17.is_unlocked("tab:automation") and gs17.is_unlocked("feature:packs"),
		"a v17 save with the cushion keeps the boxes job through the re-gating")
	_check(not gs17.is_unlocked("tab:boxes"), "and the boxes tab closes again until the machine earns it")
	gs17.free()
	# v18: parts that slipped in early stay in the bag, but parts close again before the 40th trip
	var part_key := "body:" + str(catalog.slots.body[0].id)
	var v18 := { "version": 18, "coins": 100, "collection": _collection_dict(5), "tutorial": "done", "trips_done": 10,
		"unlocks": ["feature:parts"], "parts_ever": true, "parts": { part_key: 2 } }
	var gs18 = _state_from(v18)
	_check(not gs18.feature_on("parts") and not gs18.parts_ever and int(gs18.parts.get(part_key, 0)) == 2,
		"a v18 save before the 40th trip closes parts again and keeps the ones it found")
	gs18.free()
	# a save from a newer game: played with, never written over
	var newer := _old_save(23)
	newer.version = gs_version() + 1
	newer.coins = 777
	var gs_new = _state_from(newer)
	_check(gs_new.coins == 777, "a save from a newer game still loads")
	gs_new.coins = 5
	gs_new.save_game()
	_check(int(_saved().version) == gs_version() + 1 and int(_saved().coins) == 777, "a save from a newer game is never written over")
	gs_new.free()
	# bad data is cleaned up
	var bad := _old_save(gs_version())
	bad.scout_notes = 99
	bad.gear = { "boots": 99, "nope": 2 }
	bad.jobs = { "coin_hunt": { "crew": ["20"], "fill": 0.0 } }
	bad.automation = { "task": "machine", "taught": { "machine": true, "boxes": true, "adventures": true, "gone_job": true },
		"others": { "machine": true, "boxes": true, "adventures": true, "gone_job": true },
		"spots": { "machine": 3, "boxes": 1, "adventures": 2 },
		"workers": { "machine": ["9999", "1", "20", "5", "5", "6", "7", "9"], "boxes": ["6"], "adventures": ["9999", "8"] } }
	var gs_bad = _state_from(bad)
	_check(gs_bad.scout_notes == gs_bad.scout_hold(), "too many scout notes are cut to what you can hold (%d)" % gs_bad.scout_notes)
	_check(gs_bad.gear == { "boots": 5 }, "unknown gear is dropped and levels kept to the max (%s)" % [gs_bad.gear])
	_check(not gs_bad.automation.taught.has("gone_job") and not gs_bad.automation.others.has("gone_job"), "a job that's gone is forgotten")
	# the save lists jobs in key order (boxes before machine), so "6" stays on the box table
	_check(gs_bad.workers_of("machine") == ["5", "7", "9"] and gs_bad.workers_of("boxes") == ["6"],
		"workers who are gone, the active pet, errand pets, doubles, ones on two jobs and ones past the machines are dropped (%s %s)" % [gs_bad.workers_of("machine"), gs_bad.workers_of("boxes")])
	_check(gs_bad.workers_of("adventures") == ["", "8"], "a party whose leader is gone waits for a new one (%s)" % [gs_bad.workers_of("adventures")])
	_check(gs_bad.automation.parties.size() == 2, "every bought party has its place (%d)" % gs_bad.automation.parties.size())
	gs_bad.free()


func gs_version() -> int:
	return int(load(GAME_STATE).get_script_constant_map().SAVE_VERSION)


## The crank save: your pet on its machine, `workers` machine workers (all commons: half speed), no
## errands, closed `away` seconds ago.
func _crank_state(stool: int, crank: int, workers: int, away: float, pets := 30) -> Node:
	var d := _old_save(gs_version(), pets)
	d.unlocks = d.unlocks.filter(func(id): return not str(id) in ["feature:errands", "tab:errands"])
	var list: Array = []
	for i in workers:
		list.append(str(i + 2))
	d.automation = { "task": "machine", "taught": { "machine": true }, "tools": { "crank": crank, "stool": stool }, "fill": 0.3,
		"others": { "machine": true } if workers > 0 else {}, "spots": { "machine": workers }, "workers": { "machine": list },
		"wfill": { "machine": 0.1 } }
	return _state_from(d, away)


## Your pet's machine (and its workers) keep cranking while the game is closed only as long as the
## stool lets them; a long time away stays quick and pays in proportion.
func _test_crank_catch_up(catalog: Catalog) -> void:
	var state := { "tools": { "crank": 3 } }
	var cs := Automation.crank_seconds(catalog, state)
	var gs = _crank_state(0, 3, 0, 7200.0)
	_check(gs.idle_log.is_empty() and is_equal_approx(float(gs.automation.fill), 0.3), "without a stool nothing is cranked while the game is closed")
	gs.free()
	gs = _crank_state(1, 3, 0, 7200.0)
	var want := fposmod(0.3 + 3600.0 / cs, 1.0)
	_check(absf(float(gs.automation.fill) - want) < 0.01, "with the stool it cranks for an hour of the two away (fill %.3f, want %.3f)" % [float(gs.automation.fill), want])
	_check(int(gs.idle_log.get("coins", 0)) > 0, "the pulls made while away are in the idle log (%s)" % [gs.idle_log])
	gs.free()
	# machine workers: also only as long as the stool lets them
	var ws := Automation.worker_seconds(catalog, Automation.fresh(), "machine")
	gs = _crank_state(0, 3, 7, 7200.0)
	_check(is_equal_approx(float(gs.automation.wfill.machine), 0.1) and gs.idle_log.is_empty(), "without a stool the workers stop while the game is closed")
	gs.free()
	gs = _crank_state(1, 3, 7, 7200.0)
	want = fposmod(0.1 + 7 * 0.5 * 3600.0 / ws, 1.0)
	_check(absf(float(gs.automation.wfill.machine) - want) < 0.01, "with the stool the workers crank for its hour (%.3f, want %.3f)" % [float(gs.automation.wfill.machine), want])
	gs.free()
	# a long time away: tens of thousands of pulls, still quick
	for hours in [2.0, 8.0]:
		var t := Time.get_ticks_msec()
		gs = _crank_state(8, 20, 500, hours * 3600.0, 600)
		_check_quick("%d h away with 500 machine workers loads" % int(hours), Time.get_ticks_msec() - t, 150)
		_check(int(gs.idle_log.get("coins", 0)) > 0, "%d h away pays coins (%s)" % [int(hours), gs.idle_log])
		gs.free()
	# and pays in proportion: the same capsules rolled (same seed), 4x the pulls, 4x the coins
	var coins := []
	for pulls in [800, 3200]:
		gs = _crank_state(0, 3, 0, -60.0)
		gs._rng.seed = 7
		gs._pet_cranks(pulls, false)
		coins.append(int(gs.idle_log.get("coins", 0)))
		gs.free()
	_check(coins[0] > 0 and absi(coins[1] - 4 * coins[0]) <= 4, "4x the pulls away brings 4x the coins (%s)" % [coins])
	# the computer slept with the game open: without a stool at most a minute counts
	for stool in [0, 1]:
		gs = _crank_state(stool, 3, 0, -60.0)
		gs.automation.fill = 0.0
		gs._auto_at = Time.get_unix_time_from_system() - 7200.0
		gs._work_automation(Time.get_unix_time_from_system())
		want = fposmod((60.0 if stool == 0 else 3600.0) / cs, 1.0)
		_check(absf(float(gs.automation.fill) - want) < 0.01, "after a sleep %s (fill %.3f, want %.3f)" % ["a minute counts without the stool" if stool == 0 else "the stool's hour counts", float(gs.automation.fill), want])
		gs.free()


## The adventures job: parties go out with the right pets, never wait, come home quietly and go
## out again; lost pets are announced; nothing goes during the tutorial.
func _test_auto_adventures(catalog: Catalog) -> void:
	# the policy chooser never waits: every event at every place, any party, runs to the end
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var roller := PetRoller.new(catalog, rng)
	var three: Array[Pet] = [roller.roll("starter"), roller.roll("starter"), roller.roll("starter")]
	var c := Collection.new()
	c.add(three)
	var waited := []
	for location in catalog.locations:
		for t in 5:
			var run := AdventureRunner.start(location.id, three, 0.0, t, catalog)
			run.chooser = "policy"
			AdventureRunner.resolve(run, Chooser.for_run(run), 1.0e12, catalog)
			if run.status != RunState.Status.DONE:
				waited.append(location.id)
	_check(waited.is_empty(), "a policy party never stops to wait for you (%s)" % [waited])
	var party := Party.make(three, catalog)
	var bad_pick := []
	for e in catalog.events.values():
		for location in catalog.locations:
			var allowed := AdventureRunner.allowed_options(e, party, location)
			if not allowed.is_empty() and not PolicyChooser.new().choose(e, allowed, null, 0.0) in allowed:
				bad_pick.append(e.id)
	_check(bad_pick.is_empty(), "the policy always picks an option the party may take (%s)" % [bad_pick])

	var d := _old_save(gs_version())
	d.jobs = { "coin_hunt": { "crew": ["20", "21"], "fill": 0.0 } }
	d.pinned = ["2"]
	d.gear = { "boots": 2 }
	d.scout_notes = 2
	d.automation = { "task": "adventures", "taught": { "machine": true, "adventures": true }, "party": { "place": "meadow", "n": 3 },
		"others": { "machine": true }, "spots": { "machine": 2 }, "workers": { "machine": ["3", "4"] } }
	var gs = _state_from(d)
	var now := Time.get_unix_time_from_system()
	gs._work_automation(now)
	var run = gs.auto_run(-1)
	_check(run != null and run.auto and run.slot == -1 and run.chooser == "policy", "your pet sends its party out (auto, slot -1, the policy)")
	if run == null:
		gs.free()
		return
	_check(run.party.setting_out() == int(gs.auto_party().n) and int(gs.auto_party().n) == 3, "the party is as big as you set (%d)" % run.party.setting_out())
	var home := ["1", "2", "3", "4", "20", "21"]
	_check(not run.party.uids.any(func(u): return u in home), "the active pet, unseen pulls, workers and errand pets stay home while others rest (%s)" % [run.party.uids])
	_check(run.scout.is_empty() and gs.scout_notes == 2, "an auto party takes no scout note")
	_check(run.gear == { "boots": 2 }, "an auto party packs the gear (%s)" % [run.gear])
	gs._work_automation(now)
	_check(gs.runs.size() == 1 and gs.auto_run(-1) == run, "one party at a time")
	# home: collected quietly, and a new party sets out
	AdventureRunner.resolve(run, Chooser.for_run(run), 1.0e12, catalog)
	var trips: int = gs.trips_done
	gs.take_idle_log()
	gs._work_automation(now)
	_check(gs.trips_done == trips + 1 and int(gs.idle_log.get("trips", 0)) == 1 and not run in gs.runs, "a party that's home is welcomed back quietly (idle log %s)" % [gs.idle_log])
	var next = gs.auto_run(-1)
	_check(next != null and next != run, "and the next party sets out")
	# a pet that stays behind is announced
	if next != null:
		AdventureRunner.resolve(next, Chooser.for_run(next), 1.0e12, catalog)
		if next.party.size() > 0:
			next.party.lose(1, rng)
		var gone: String = next.party.lost[0]
		var name: String = gs.collection.get_pet(gone).display_name(catalog)
		gs.announcements.clear()
		gs._work_automation(now)
		_check(gs.announcements.any(func(a): return name in a and "stayed" in a), "a pet that stays behind is announced (%s)" % [gs.announcements])
		_check(gs.collection.get_pet(gone) == null, "and it's gone from your pets")
	# a place that's closed (or none picked) falls back to the first open one that takes a party
	gs.automation.party = { "place": "well", "n": 3 }
	_check(gs.auto_party().place == "meadow", "a party set to a closed place goes to an open one (%s)" % gs.auto_party().place)
	gs.automation.party = { "place": "", "n": 0 }
	_check(gs.auto_party().place == "meadow" and gs.auto_party().n == 3, "no place picked: the first open one, the job's party size")
	gs.free()
	# the tutorial: nothing goes out
	d.tutorial = "machine"
	gs = _state_from(d)
	gs._work_automation(now)
	_check(gs.runs.is_empty(), "no auto parties during the tutorial")
	gs.free()


## Thousands of workers: filled fastest first, one job each, never the active pet or errand pets,
## and everything stays quick.
func _test_many_workers(catalog: Catalog) -> void:
	var d := _old_save(gs_version(), 5000, true)
	d.unlocks.append("feature:packs")
	d.jobs = { "coin_hunt": { "crew": ["20", "21"], "fill": 0.0 } }
	var all := { "machine": true, "adventures": true, "boxes": true }
	d.automation = { "taught": all, "others": all, "spots": { "machine": 2000, "boxes": 1000, "adventures": 200 } }
	var gs = _state_from(d)
	_check(gs.automation.parties.size() == 200, "every bought party has its place")
	var t := Time.get_ticks_usec()
	var started: int = gs.put_workers("machine", -1)
	var took := (Time.get_ticks_usec() - t) / 1000
	_check(started == 2000, "2000 workers go on their machines (%d)" % started)
	_check_quick("2000 workers go on their machines", took, 200)
	_check(gs.put_workers("boxes", -1) == 1000 and gs.put_workers("adventures", -1) == 200, "tables and parties fill up too")
	var speed := func(uid): return Automation.worker_speed(catalog, gs.collection.get_pet(str(uid)))
	var slowest := func(list: Array): return list.map(speed).min()
	var fastest := func(list: Array): return list.map(speed).max()
	var resting: Array = gs.resting_pets().map(func(p): return p.uid)
	_check(slowest.call(gs.workers_of("machine")) >= fastest.call(gs.workers_of("boxes"))
		and slowest.call(gs.workers_of("boxes")) >= fastest.call(gs.workers_of("adventures"))
		and slowest.call(gs.workers_of("adventures")) >= fastest.call(resting), "the fastest pets are put on first")
	var seen := {}
	var twice := 0
	for id in ["machine", "boxes", "adventures"]:
		for uid in gs.workers_of(id):
			if seen.has(uid):
				twice += 1
			seen[uid] = true
	_check(seen.size() == 3200 and twice == 0, "nobody works two jobs (%d workers, %d doubles)" % [seen.size(), twice])
	_check(not seen.has("1") and not seen.has("20") and not seen.has("21"), "never your active pet or a pet on an errand")
	var sum := 0.0
	for uid in gs.workers_of("machine"):
		sum += speed.call(uid)
	_check(absf(gs.workers_speed("machine") - sum) < 0.001, "the machines' speed is their workers' speeds added up (%.1f)" % sum)
	gs._hold_saves = true  # as in the game's tick: one save at the end, not one per box they open
	t = Time.get_ticks_usec()
	gs._work_for_automation(3600.0, false)
	took = (Time.get_ticks_usec() - t) / 1000
	gs._release_saves()
	_check_quick("an hour of 3200 workers is worked out", took, 150)
	t = Time.get_ticks_usec()
	gs._work_automation(Time.get_unix_time_from_system())
	took = (Time.get_ticks_usec() - t) / 1000
	var auto_runs: Array = gs.runs.filter(func(r): return r.auto)
	_check(auto_runs.size() == 200, "200 parties set out (%d)" % auto_runs.size())
	_check_quick("200 parties are sent", took, 300)
	var bad := 0
	for r in auto_runs:
		if r.party.setting_out() != 3 or r.party.uids.any(func(u): return seen.has(u) or u in ["1", "20", "21"]):
			bad += 1
	_check(bad == 0, "every party is 3 resting pets, no workers (%d wrong)" % bad)
	t = Time.get_ticks_usec()
	gs.save_game()
	var before: Dictionary = gs.automation.workers.duplicate(true)
	gs.free()
	gs = _reload()
	took = (Time.get_ticks_usec() - t) / 1000
	_check_quick("5000 pets and their workers are saved and loaded", took, 600)
	_check(gs.automation.workers == before and gs.runs.size() == 200, "the workers and their parties survive a save")
	_check(gs.take_off_workers("adventures", 10) == 10, "party leaders can be sent home")
	var leaders: Array = gs.workers_of("adventures")
	_check(leaders.size() == 200 and leaders.slice(190).all(func(u): return u == "") and leaders.slice(0, 190).all(func(u): return u != ""),
		"the last parties wait for new leaders: their slots stay")
	var worker: String = gs.workers_of("machine")[0]
	var lost_uids: Array[String] = [worker, str(leaders[0])]
	gs.collection.remove(lost_uids)
	_check(gs.workers_count("machine") == 1999 and gs.worker_job(worker) == "" and gs.workers_of("adventures")[0] == "",
		"a pet that's gone frees its machine, and its party waits")
	gs.free()
	# box workers open what's on the pile and never buy more
	var small := _old_save(gs_version())
	small.unlocks.append_array(["feature:packs", "feature:shopping"])
	small.bag = { "starter": 5 }
	small.automation = { "taught": { "boxes": true }, "others": { "boxes": true }, "spots": { "boxes": 3 }, "workers": { "boxes": ["3", "4", "5"] } }
	gs = _state_from(small)
	var coins: int = gs.coins
	gs._work_for_automation(3600.0, false)
	_check(gs.in_bag("starter") == 0 and gs.collection.pets.size() == 35 and gs.coins == coins and int(gs.idle_log.get("packs", 0)) == 5,
		"box workers open the pile and never buy more (%d pets, %d coins spent)" % [gs.collection.pets.size(), coins - gs.coins])
	gs.free()


## A2 gear through GameState: bought with xp, packed on every trip but dungeons, kept in the save.
func _test_gear_state(catalog: Catalog) -> void:
	var d := _old_save(gs_version())
	d.xp = 100
	d.unlocks.append_array(["page:beyond", "location:well"])
	var gs = _state_from(d)
	_check(gs.gear_block("pouch") == "hidden" and not gs.buy_gear("pouch"), "gear that isn't on the path yet can't be bought")
	var price: int = gs.gear_price("boots")
	_check(price == Gear.price(catalog, "boots", 0) and gs.buy_gear("boots") and gs.xp == 100 - price and gs.gear_level("boots") == 1,
		"boots cost their xp (%d)" % price)
	gs.xp = 0
	_check(not gs.buy_gear("tote") and gs.gear_level("tote") == 0 and gs.xp == 0, "no xp, no gear")
	gs.xp = 1000000
	gs.set_gear_level("boots", int(Gear.info(catalog, "boots").max))
	_check(gs.gear_block("boots") == "max" and not gs.buy_gear("boots") and gs.xp == 1000000, "gear stops at its max")
	gs.buy_gear("tote")
	var pets: Array[Pet] = [gs.collection.get_pet("5"), gs.collection.get_pet("6")]
	var mine = gs.send_on_adventure("meadow", pets)
	_check(mine != null and mine.gear == gs.trip_gear("meadow") and mine.gear == { "boots": 5, "tote": 1 }, "a trip you send packs your gear")
	var one: Array[Pet] = [gs.collection.get_pet("7")]
	var deep = gs.send_on_adventure("well", one)
	_check(deep != null and deep.gear.is_empty(), "a dungeon trip packs no gear")
	gs.automation = { "task": "adventures", "taught": { "adventures": true }, "tools": {}, "party": { "place": "meadow", "n": 3 }, "fill": 0.0,
		"others": {}, "spots": {}, "workers": {}, "parties": [], "wfill": {} }
	gs._work_automation(Time.get_unix_time_from_system())
	var auto = gs.auto_run(-1)
	_check(auto != null and auto.gear == { "boots": 5, "tote": 1 }, "your pet's party packs the gear too")
	gs.save_game()
	gs.free()
	gs = _reload()
	_check(gs.gear == { "boots": 5, "tote": 1 } and gs.runs.all(func(r): return r.gear == ({} if r.location_id == "well" else { "boots": 5, "tote": 1 })),
		"gear, and what each trip packed, survive a save")
	gs.free()


## A3 jobs through GameState: the kitchen, scouting, the savings jar, sharing out and the chain of
## job levels that opens them.
func _test_jobs_state(catalog: Catalog) -> void:
	var d := _old_save(gs_version())
	d.unlocks.append_array(["job:lemonade", "job:jar", "job:kitchen", "job:scouting"])
	d.hunger = 30.0
	d.happiness = 30.0
	var gs = _state_from(d)
	var kitchen := catalog.job("kitchen")
	var power := float(catalog.errands.crew_power)
	gs.put_on_job("kitchen", 1, ["5"])
	gs.put_on_job("coin_hunt", 1, ["6"])
	var with_kitchen: float = gs.job_rate("coin_hunt")
	var bonus: float = gs.kitchen_bonus()
	var own := Jobs.rate(kitchen, 1, Jobs.pet_speed(gs.collection.get_pet("5"), kitchen), power)
	_check(bonus > 0.0 and is_equal_approx(gs.job_rate("kitchen"), own), "the kitchen speeds the other jobs, not itself (%.3f)" % bonus)
	gs.take_off_job("kitchen", -1)
	var without: float = gs.job_rate("coin_hunt")
	_check(with_kitchen > without and is_equal_approx(with_kitchen / without, 1.0 + bonus), "the coin hunt is %.0f%% faster with a cook" % (bonus * 100.0))
	gs.put_on_job("kitchen", 1, ["5"])
	var upto := float(kitchen.get("meal_upto", 100.0))
	gs._work_for(float(kitchen.seconds) * 50.0)
	_check(is_equal_approx(gs.hunger, upto) and gs.happiness <= upto + 0.001, "the kitchen feeds your pet up to %.0f, no more (%.1f)" % [upto, gs.hunger])
	gs.hunger = 90.0
	gs._work_for(float(kitchen.seconds) * 50.0)
	_check(gs.hunger == 90.0, "a full pet isn't fed down")
	# scouting: notes fill up to the hold, then the meter waits
	var scout := catalog.job("scouting")
	gs.put_on_job("scouting", 1, ["7"])
	gs._work_for(float(scout.seconds) * 20.0)
	_check(gs.scout_notes == gs.scout_hold() and gs.scout_hold() == int(scout.scout.hold), "scouts write notes up to the hold (%d)" % gs.scout_notes)
	var fill: float = gs.job_fill("scouting")
	gs._work_for(float(scout.seconds) * 20.0)
	_check(gs.scout_notes == int(scout.scout.hold) and gs.job_fill("scouting") == fill and gs.job_fill_now("scouting") == 1.0, "a full hold: the meter waits")
	gs.set_errand_tool_level("map_case", 1)
	gs._work_for(float(scout.seconds) * 20.0)
	_check(gs.scout_notes == int(scout.scout.hold) + 1, "the map case holds one more note (%d)" % gs.scout_notes)
	var pets: Array[Pet] = [gs.collection.get_pet("8")]
	var mine = gs.send_on_adventure("meadow", pets)
	_check(mine != null and mine.scouted and gs.scout_notes == int(scout.scout.hold), "a trip you send takes a note")
	var theirs: Array[Pet] = [gs.collection.get_pet("9")]
	var auto = gs.send_on_adventure("meadow", theirs, false)
	_check(auto != null and not auto.scouted and gs.scout_notes == int(scout.scout.hold), "a party your pet sends doesn't")
	gs.save_game()
	gs.free()
	gs = _reload()
	_check(gs.scout_notes == int(scout.scout.hold) and gs.scout_hold() == int(scout.scout.hold) + 1, "scout notes survive a save")
	# share out skips the kitchen and scouting
	gs.take_off_job("kitchen", -1)
	gs.take_off_job("scouting", -1)
	gs.share_out()
	_check(gs.job_crew("kitchen").is_empty() and gs.job_crew("scouting").is_empty() and gs.job_crew("coin_hunt").size() > 0,
		"share out never puts pets in the kitchen or scouting")
	gs.free()
	# the savings jar: one full meter pays one chunk
	d.jobs = {}
	gs = _state_from(d)
	gs.put_on_job("jar", 1, ["5"])
	gs.jobs.jar.fill = 0.999
	var paid := []
	gs.job_paid.connect(func(id, loot): paid.append([id, loot]))
	var coins: int = gs.coins
	gs._work_for(0.002 / gs.job_rate("jar"))
	var chunk := roundi(float(catalog.job("jar").pay.capsules) * Machine.coin_value(gs.machine, catalog))
	_check(paid.size() == 1 and gs.coins - coins == chunk, "a full jar pays one chunk (%d, want %d)" % [gs.coins - coins, chunk])
	gs.free()
	# the chain: coin hunt lv 10 -> lemonade, lv 25 -> kitchen; lemonade lv 10 -> jar; jar lv 10 -> scouting
	var chain := _old_save(gs_version())
	gs = _state_from(chain)
	gs.set_errand_tool_level("noses", 25)
	_check(gs.is_unlocked("job:lemonade") and gs.is_unlocked("job:kitchen") and not gs.is_unlocked("job:jar"), "coin hunt lv 25 opens the lemonade stand and the kitchen")
	gs.coins = Jobs.tool_cost(Jobs.tool(catalog, "lemons"), 0, 10, gs.capsule_value()) + 1
	_check(gs.buy_errand_tool("lemons", -1) == 10 and gs.coins == 1, "as many lemons as you can afford (%d left)" % gs.coins)
	_check(gs.is_unlocked("job:jar") and not gs.is_unlocked("job:scouting"), "lemonade lv 10 opens the savings jar")
	gs.set_errand_tool_level("bigger_jar", 10)
	_check(gs.is_unlocked("job:scouting"), "the jar at lv 10 opens scouting")
	var open: Array = gs.open_jobs().map(func(j): return j.id)
	_check(["lemonade", "jar", "kitchen", "scouting"].all(func(id): return id in open), "and they're all errands you can staff (%s)" % [open])
	gs.free()


## A time limit: `quiet_ms` is about what it takes on a quiet machine; it fails only at 5x that
## (times DESK_PETS_SLOW), so only a real slowdown trips it. Always prints the time.
func _check_quick(what: String, took_ms: int, quiet_ms: int) -> void:
	var limit := roundi(quiet_ms * 5 * _slow)
	print("  time: %s in %d ms (limit %d)" % [what, took_ms, limit])
	_check(took_ms <= limit, "%s quickly (%d ms, limit %d)" % [what, took_ms, limit])


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + what)


## Errand tools and boxes are priced in the machine's plain capsules, like errands pay, so their
## prices keep up with the machine.
func _test_prices(catalog: Catalog) -> void:
	var game_state: GDScript = load("res://scripts/game_state.gd")
	for t in Jobs.all_tools(catalog):
		_check(float(t.get("capsules", 0)) > 0.0 and not t.has("coins"), "errand tool %s is priced in capsules" % t.id)
	for b in catalog.boxes:
		_check(float(b.get("capsules", 0)) > 0.0 and not b.has("price"), "box %s is priced in capsules" % b.id)
	var noses := Jobs.tool(catalog, "noses")
	_check(Jobs.tool_cost(noses, 3, 1, 10.0) == roundi(Jobs.tool_base(noses) * 10.0 * pow(float(noses.grow), 3)), "a tool's price grows with what a capsule is worth")
	_check(Jobs.tool_cost(noses, 0, 0, 10.0) == 0, "no levels cost nothing")
	var spot := { "coins": 500, "grow": 1.5 }
	_check(Jobs.tool_cost(spot, 2, 1, 1000.0) == Jobs.tool_cost(spot, 2), "a spot with a fixed coin price ignores the machine")
	var fresh := Machine.coin_value({ "bought": {} }, catalog)
	var fixed := Machine.coin_value({ "bought": { "tape": 1, "oil": 1, "flap": 1 } }, catalog)
	_check(is_equal_approx(fresh, 1.0) and is_equal_approx(fixed, 8.0), "tape, oil and flap make a capsule worth 8 (%.1f, %.1f)" % [fresh, fixed])
	_check(Jobs.tool_cost(noses, 0, 1, fixed) == roundi(8.0 * Jobs.tool_cost(noses, 0, 1, 2.0) / 2.0), "noses cost 8x on a repaired machine (%d)" % Jobs.tool_cost(noses, 0, 1, fixed))
	var starter := catalog.box("starter")
	_check(game_state.box_cost(starter, fresh) == int(starter.capsules), "a starter box costs its capsules in coins at the start (%d)" % game_state.box_cost(starter, fresh))
	_check(game_state.box_cost(starter, fixed) == 8 * game_state.box_cost(starter, fresh), "a starter box costs 8x on a repaired machine")
	_check(game_state.box_cost(starter, fixed, 10) == 10 * game_state.box_cost(starter, fixed), "10 boxes cost 10 boxes")
	_check(game_state.box_cost(starter, 74.3, 10) == 10 * game_state.box_cost(starter, 74.3), "10 boxes cost 10 boxes when a capsule is worth a fraction (%d)" % game_state.box_cost(starter, 74.3, 10))
	_check(game_state.box_cost(starter, 74.3, 0) == 0, "no boxes cost nothing")
	var reserve: Dictionary = catalog.box_rules.get("reserve", {})
	_check(int(reserve.get("capsules", 0)) > 0 and int(reserve.get("step", 0)) > 0 and int(reserve.get("max", 0)) >= int(reserve.get("capsules", 0)),
		"your pet's box reserve has a start, a step and a top in capsules")
	_check(game_state.box_cost({ "price": 70 }, 1000.0) == 70, "a box with a fixed price ignores the machine")
	# when errands open a capsule is worth about 75 coins: prices then stay what they were in coins
	var old := { "noses": 180, "paws": 400, "pockets": 2500, "lemons": 900, "sign": 1600, "cups": 12000, "bigger_jar": 6000,
		"slot": 9000, "map_case": 15000, "glasses": 20000, "snack": 1200, "naps": 3000, "pebbles": 8000, "team": 20000 }
	for id in old:
		var now := Jobs.tool_cost(Jobs.tool(catalog, id), 0, 1, 75.0)
		_check(absf(now - old[id]) <= 0.1 * old[id], "errand tool %s costs about what it did when errands open (%d, was %d)" % [id, now, old[id]])
	var maxed := { "bought": {} }
	for n in catalog.machine_tree.nodes:
		maxed.bought[n.id] = maxi(1, int(n.get("max", 1)))
	var top := Machine.coin_value(maxed, catalog)
	for t in Jobs.all_tools(catalog):
		_check(Jobs.tool_cost(t, 200, 10, top) > 0, "errand tool %s never costs less than nothing" % t.id)
	_check(game_state.box_cost(starter, top, 1000000) > 0, "a pile of boxes never costs less than nothing")


## Knacks (data/knacks.json, Knacks): one per part, sized by rarity and finish, hidden until their
## system opens; the active pet's feed the boosts, other pets' a share of their own work.
func _test_knacks(catalog: Catalog) -> void:
	var d: Dictionary = catalog.knacks
	var icons := FileAccess.get_file_as_string("res://scripts/ui/ui_theme.gd")  # UiTheme needs the game running
	for slot in Catalog.SLOTS:
		for p in catalog.slots[slot]:
			var key := "%s:%s" % [slot, p.id]
			_check(d.parts.has(key), "part %s has a knack entry" % key)
			var kind := str(d.parts.get(key, {}).get("kind", ""))
			if kind != "":
				_check(d.kinds.has(kind), "part %s's knack kind %s is in the table" % [key, kind])
				_check(str(d.parts[key].get("name", "")) != "", "part %s's knack has a name" % key)
	_check(d.parts["accessory:none"].is_empty(), "no accessory, no knack")
	for key in d.parts:
		var bits: PackedStringArray = str(key).split(":")
		_check(bits.size() == 2 and not catalog.part(bits[0], bits[1]).is_empty(), "knack entry %s is a real part" % key)
	for kind in d.kinds:
		var k: Dictionary = d.kinds[kind]
		_check(float(k.get("step", 0)) > 0 and str(k.get("text", "")).contains("{n}") and icons.contains('"%s":' % k.get("icon", "")),
			"knack kind %s has a step, a text with {n} and a real icon" % kind)
		_check(Boosts.is_kind(catalog, kind) or kind in ["all", "power"], "knack kind %s is a boost kind (or all, or power for later)" % kind)
	for t in catalog.tiers:
		_check(d.rarity_x.has(t.id), "every rarity has a knack size (%s)" % t.id)
	for f in catalog.finishes:
		_check(d.finish_x.has(f.id) and float(d.finish_x[f.id]) >= 1.0, "every finish makes knacks at least as big (%s)" % f.id)
	# sizes: step x rarity x finish
	_check(Knacks.size(catalog, "tough", "common") == 3, "a common blob is 3% tougher")
	_check(Knacks.size(catalog, "tough", "legendary") == 24, "legendary x-eyes: 24% tougher")
	_check(Knacks.size(catalog, "spots", "epic", "holo") == 30, "a holo cyclops: 20 x1.5 = 30% spotting")
	var open := func(_gate: String) -> bool: return true
	var shut := func(gate: String) -> bool: return gate != "feature:parts"
	var pet := Pet.new()
	pet.parts = { "body": "bunny", "palette": "gold", "pattern": "stars", "eyes": "cyclops", "accessory": "horns" }
	var ks := Knacks.of(catalog, pet, open)
	_check(ks.size() == 4 and not ks.any(func(k): return k.kind == "power"), "the demon horns' power knack stays hidden until fights (%d)" % ks.size())
	_check(Knacks.of(catalog, pet, shut).is_empty(), "no knacks at all before parts open")
	var spots := Knacks.parts(catalog, pet, "spots", open)
	_check(spots.size() == 1 and spots[0].source == "knacks" and spots[0].id == "body:bunny+eyes:cyclops" and is_equal_approx(float(spots[0].x), 1.32),
		"big ears + one big eye add up: one part, +32% spotting")
	_check(is_equal_approx(Boosts.total(Knacks.parts(catalog, pet, "coins", open)), 1.40), "golden touch: +40% coins")
	_check(Knacks.parts(catalog, pet, "fever", open).is_empty(), "no fever knack, no fever part")
	_check(Knacks.best(catalog, pet, open).slot == "palette", "the best badge: the legendary one (golden touch)")
	_check(is_equal_approx(Knacks.own(catalog, pet, "spots", open), 1.08), "other pets count a quarter: +8% spotting on their own trips")
	_check(is_equal_approx(Knacks.own(catalog, pet, "spots", shut), 1.0), "and nothing before parts open")
	var hum := Pet.new()
	hum.parts = { "body": "void", "palette": "toxic", "pattern": "plain", "eyes": "sparkle", "accessory": "none" }
	hum.finish = "prismatic"
	for kind in ["coins", "xp", "luck"]:
		_check(is_equal_approx(Boosts.total(Knacks.parts(catalog, hum, kind, open)), 1.6), "the hum counts for %s (2 x12 x2.5 = 60%%)" % kind)
	_check(Knacks.parts(catalog, hum, "speed", open).is_empty(), "the hum doesn't count for kinds not marked all")
	var no_fever := func(gate: String) -> bool: return gate != "machine:wires"
	_check(not Knacks.of(catalog, hum, no_fever).any(func(k): return k.kind == "fever") and Knacks.of(catalog, hum, open).any(func(k): return k.kind == "fever"),
		"glow in the dark shows once the lights (fever) are fixed")
	var party: Array = [pet, hum]
	_check(is_equal_approx(Knacks.party(catalog, party, "spots", open), 1.04), "a party's own share is the average (8% and 0%)")
	_check(is_equal_approx(Knacks.party(catalog, [], "spots", open), 1.0), "nobody, x1")
	# the lean totals (no display rows) agree with the rows the badges show
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = 11
	var roller := PetRoller.new(catalog, roll_rng)
	var agree := true
	var many: Array = []
	for i in 300:
		var p := roller.roll("lucky")
		many.append(p)
		for kind in Boosts.kinds(catalog):
			for gate: Callable in [open, no_fever]:
				var by_rows := 0
				for k in Knacks.of(catalog, p, gate):
					if Knacks.covers(catalog, str(k.kind), kind):
						by_rows += int(k.n)
				if by_rows != Knacks.total(catalog, p, kind, gate):
					agree = false
	_check(agree, "lean knack totals match the badges' rows for 300 rolled pets")
	var t0 := Time.get_ticks_usec()
	for i in 10:
		Knacks.party_all(catalog, many, ["trip", "tough", "safe", "spots", "finds", "pickups", "treats", "loot"], open)
	var per_pet := float(Time.get_ticks_usec() - t0) / (10.0 * many.size())
	print("knacks: party_all over 8 kinds %.1f us per pet" % per_pet)
	# on a trip
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bean: Array[Pet] = [PetRoller.new(catalog, rng).roll("starter", "common")]
	var plain := AdventureRunner.start("garden", bean, 0.0, 1, catalog)
	var quick := AdventureRunner.start("garden", bean, 0.0, 1, catalog, {}, {}, {}, { "trip": 1.25 })
	_check(is_equal_approx(AdventureRunner.run_gap(quick, catalog), AdventureRunner.run_gap(plain, catalog) / 1.25), "a trip knack x1.25: the walk / 1.25")
	var both := AdventureRunner.start("garden", bean, 0.0, 1, catalog, {}, {}, { "boots": 5 }, { "trip": 1.25 })
	_check(is_equal_approx(AdventureRunner.run_gap(both, catalog), AdventureRunner.run_gap(plain, catalog) * 0.6 / 1.25), "boots and knacks together")
	var again := RunState.from_dict(both.to_dict(), catalog)
	_check(is_equal_approx(again.knack("trip"), 1.25) and is_equal_approx(again.walk, both.walk), "a trip's knacks survive a save")
	_check(is_equal_approx(RunState.from_dict(plain.to_dict(), catalog).knack("safe"), 1.0), "a trip without knacks is x1")
	var lost_plain := _gear_losses("meadow", bean, {}, catalog)
	var lost_safe := _gear_losses("meadow", bean, {}, catalog, { "safe": 2.0, "tough": 2.0 })
	_check(lost_safe < lost_plain, "tougher, safe-home pets get lost less (%d vs %d)" % [lost_safe, lost_plain])
	var garden := catalog.location("garden")
	var seen := [0, 0]
	for t in 400:
		for i in 2:
			rng.seed = t
			seen[i] += Intel.roll(garden, func(_id): return false, {}, rng, 0.0, 1.0 if i == 0 else 1.5).size()
	_check(seen[1] > seen[0], "spotting knacks spot more places (%d vs %d)" % [seen[1], seen[0]])
