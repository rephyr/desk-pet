extends SceneTree
## Headless checks for the pet core. Run with:
##   godot --headless -s tests/test_core.gd -- --profile=test_core
## Without a profile it uses "test_core" anyway: the tests write saves and must never touch the real one.

const ROLLS := 100000

var _failures := 0
var _checks := 0  # printed at the end, so a test that stopped early on a script error shows


func _init() -> void:
	if DevArgs.value("profile") == "":
		DevArgs.overrides["profile"] = "test_core"  # before anything loads a save
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
	_test_herd(catalog)
	_test_herd_game(catalog)
	_test_knacks(catalog)
	_test_herd_knacks(catalog)
	_test_dungeon(catalog)
	_test_plushie(catalog)
	_test_plushie_game(catalog)
	_test_new_homes(catalog)
	_test_new_homes_game(catalog)
	_test_sewing(catalog)
	_test_sewing_game(catalog)
	_test_perks(catalog)
	_test_perks_game(catalog)
	_test_held(catalog)
	_test_held_game(catalog)
	_test_merged_lanes(catalog)
	print("\n%s (%d checks)" % ["ALL PASSED" if _failures == 0 else "%d FAILED" % _failures, _checks])
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
	_check(restored.count() == 50 and restored.pets.size() == c.pets.size() and restored.herd == c.herd, "round trip keeps all pets")
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
	var gone: Array[String] = [c.pets[0].uid, c.pets[1].uid]
	var key := Collection.part_key("body", c.pets[0].parts.body)
	var seen_before := c.times_seen(key)
	c.active_uid = gone[0]
	c.remove(gone)
	_check(c.count() == 1998 and c.get_pet(gone[0]) == null, "lost pets leave the collection")
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
	_check(not "well" in can and not "orchard" in can, "heard or already open rumours don't come again (%s)" % [can])
	_check(not "cellar" in can and not "below" in can, "the cellar and further down are dungeon bands now: their rumours are never heard (%s)" % [can])
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
	var known := ["worth", "speed", "big", "rare_x", "all_speed", "away_hours", "shiny", "crew_power"]
	var ids := {}
	for t in Jobs.all_tools(catalog):
		_check(not ids.has(t.id), "errand tool %s has its own id" % t.id)
		ids[t.id] = true
		_check(t.has("name") and t.has("what") and float(t.coins) > 0.0 and not t.each.is_empty(), "errand tool %s has a name, what it does, a price and an effect" % t.id)
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
			var ok: bool = (bits[0] == "tab" and bits[1] in tabs) or (bits[0] == "feature" and bits[1] in ["errands", "packs", "shopping", "parties", "parties_5", "parties_10", "toys", "parts", "auto_adventures", "dungeon", "lead_army", "plushie", "new_homes", "sorting", "sewing", "keep_lines"]) or (bits[0] == "page" and bits[1] in page_ids) \
				or (bits[0] == "job" and catalog.jobs.any(func(j): return str(j.get("needs", "")) == o))
			_check(ok, "unlock %s opens something real (%s)" % [entry.id, o])
		if entry.earn.has("find"):
			_check(catalog.finds.has(entry.earn.find), "unlock %s waits for a real find" % entry.id)
		_check(not "{" in str(entry.get("announce", "")), "unlock %s announcement has no placeholders" % entry.id)
	for find in catalog.finds:
		var machine_gives: bool = find == str(catalog.machine.get("intel", {}).get("find", ""))
		var dungeon_gives: bool = catalog.dungeon.get("firsts", {}).values().any(func(f): return str(f.get("find", "")) == find)
		var later := str(catalog.finds[find].get("given_by", "")) != ""  # a step not built yet gives it (see data/unlocks.json)
		_check(machine_gives or dungeon_gives or later or catalog.events.values().any(func(e): return e.get("find", "") == find), "some event (or the machine, or a dungeon floor) gives %s" % find)
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
		var learned: bool = catalog.unlock_list.any(func(e): return str(e.get("learns", "")) == str(j.id))
		_check(int(j.coins) > 0 or learned, "job %s is taught with coins (or learned when it opens)" % j.id)
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


## The herd: plain pets fold into counts per rarity x finish; favourites, the active pet, holo and
## better, and pets with a part new to the book stay cards; each shelf keeps its newest 20.
func _test_herd(catalog: Catalog) -> void:
	var keep := int(catalog.herd.keep_cards)
	var c := Collection.new()
	var commons: Array[Pet] = []
	for i in keep + 5:  # all with the same parts: only the first brings anything new to the book
		commons.append(_plain_pet(catalog, "common", "normal", i, commons[0] if i > 0 else null))
	c.add(commons)
	# the very first pet brought every part it has to the book: it stays a card (and is active)
	_check(c.count() == keep + 5 and c.herd_count("common:normal") == 4 and c.pets.size() == keep + 1,
		"a 21st plain common folds the oldest into the herd (%d cards, %d in the herd)" % [c.pets.size(), c.herd_count("common:normal")])
	_check(c.pets[0].new_part and c.pets[0].uid == c.active_uid, "the first pet stays a card (active, new parts)")
	_check(c.count_of("common") == keep + 5 and c.plain_count() == keep + 5, "totals count cards and the herd")
	var shiny: Array[Pet] = [_plain_pet(catalog, "common", "shiny", 99, commons[0])]
	var holo: Array[Pet] = [_plain_pet(catalog, "common", "holo", 98, commons[0])]
	c.add(shiny)
	c.add(holo)
	_check(c.get_pet(holo[0].uid) != null and c.shiny_of("common") == 1 and c.plain_count() == keep + 6,
		"holo stays a card and isn't in the room; shiny counts as plain")
	var fav := c.pets[1]
	c.set_fav(fav.uid, true)
	var more: Array[Pet] = []
	for i in 30:
		more.append(_plain_pet(catalog, "common", "normal", 200 + i, commons[0]))
	c.add(more)
	_check(c.get_pet(fav.uid) != null, "a favourite never folds")
	c.set_fav(fav.uid, false)
	_check(c.get_pet(fav.uid) == null and c.herd_count("common:normal") > 0, "unfaving an old pet folds it")
	var free := c.pets.filter(func(p): return not c.always_card(p)).size()
	_check(free == keep, "each shelf keeps its newest %d plain cards (%d)" % [keep, free])
	# busy pets (away, pinned) never fold
	var c2 := Collection.new()
	var hold := {}
	c2.busy = func(): return hold
	var batch: Array[Pet] = []
	for i in keep + 3:
		batch.append(_plain_pet(catalog, "uncommon", "normal", i))
	hold[str(2)] = true
	c2.add(batch)
	_check(c2.get_pet("2") != null, "a busy pet stays a card")
	# round trip
	var back := Collection.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	_check(back.count() == c.count() and back.herd == c.herd and back.plain_count() == c.plain_count()
		and back.shiny_of("common") == c.shiny_of("common"), "the herd survives a save")
	# stand-ins: a pet from a count, the same look every time; leaving takes one from the count
	var uid := Herd.uid("common:normal", 3)
	var s1 := c.get_pet(uid)
	var s2 := Herd.stand_in(catalog, uid)
	_check(s1 != null and s1.rarity == "common" and s1.finish == "normal" and s1.traits.is_empty() and s1.parts == s2.parts,
		"a stand-in has its count's rarity and finish, no traits, and a steady look")
	_check(Herd.key_of(uid) == "common:normal" and Herd.number_of(uid) == 3, "a stand-in's uid names its count")
	var before := c.herd_count("common:normal")
	var stars := c.fallen_n
	var lost: Array[String] = [uid]
	c.remove(lost)
	_check(c.herd_count("common:normal") == before - 1 and c.fallen_n == stars + 1 and int(c.stand_next["common:normal"]) == 4,
		"a lost stand-in leaves its count and adds a star; its look never comes back")
	_check(c.get_pet(Herd.uid("rare:normal", 0)) == null, "no stand-ins for an empty count")
	# a collection from before the herd (v22): stars were [uid, palette], nothing marked yet
	var old := { "pets": [], "active": "1", "next_id": 4, "seen": {}, "fallen": [[5, "peach"], [9, "mint"]] }
	for i in 3:
		var d := _plain_pet(catalog, "common", "normal", i).to_dict()
		d.uid = str(i + 1)
		old.pets.append(d)
	var migrated := Collection.from_dict(old)
	_check(migrated.fallen == ["peach", "mint"] and migrated.fallen_n == 2, "old stars keep their palettes")
	_check(migrated.pets[0].new_part and migrated.count() == 3, "old pets: the first with each part is marked")
	# the room
	_check(Herd.room_cap(catalog, 0) == int(catalog.herd.room.start) and Herd.room_cap(catalog, 1) > Herd.room_cap(catalog, 0)
		and Herd.room_cost(catalog, 1) > Herd.room_cost(catalog, 0), "room upgrades hold more and cost more")
	# spreading over places: the smallest fill up first
	var spread: Dictionary = load("res://scripts/game_state.gd").water_fill({ "a": 0, "b": 10, "c": 3 }, 20)
	_check(int(spread.a) + int(spread.b) + int(spread.c) == 20 and int(spread.a) == 11 and int(spread.c) == 8 and int(spread.b) == 1,
		"pets spread so the smallest crews fill up first (%s)" % str(spread))
	# a million plain pets: quick, and the save stays tiny
	var big := Collection.new()
	var t0 := Time.get_ticks_msec()
	big.add_plain("common:normal", 1000000)
	var text := JSON.stringify(big.to_dict())
	var again := Collection.from_dict(JSON.parse_string(text))
	_check(again.count() == 1000000 and text.length() < 2000, "a million plain pets fit in a tiny save (%d bytes)" % text.length())
	_check(Time.get_ticks_msec() - t0 < 200, "a million plain pets save and load quickly (%d ms)" % (Time.get_ticks_msec() - t0))
	# lots of holo cards (always cards) don't slow adding plain pets down: refold only looks at plain cards
	var shiny_pile := Collection.new()
	shiny_pile.auto_active = false
	var pile_roller := PetRoller.new(catalog)
	var holos: Array[Pet] = []
	for i in 10000:
		var h := pile_roller.roll("starter", "common")
		h.finish = "holo"
		holos.append(h)
	shiny_pile.add(holos)
	var plains: Array[Pet] = []
	for i in 100:
		var p := pile_roller.roll("starter", "common")
		p.finish = "normal"
		plains.append(p)
	t0 = Time.get_ticks_msec()
	for p in plains:
		var one: Array[Pet] = [p]
		shiny_pile.add(one)
	var t_adds := Time.get_ticks_msec() - t0
	_check(shiny_pile.pets.size() == 10000 + int(catalog.herd.keep_cards) + shiny_pile.pets.filter(func(p): return p.new_part and p.finish == "normal").size(),
		"with 10k holo cards the plain ones still fold (%d cards)" % shiny_pile.pets.size())
	_check(t_adds < 500, "100 adds next to 10k holo cards stay quick (%d ms)" % t_adds)


func _plain_pet(catalog: Catalog, rarity: String, finish: String, seed_n: int, parts_like: Pet = null) -> Pet:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var p := PetRoller.new(catalog, rng).roll("starter", rarity)
	p.finish = finish
	if parts_like:
		p.parts = parts_like.parts.duplicate()
	return p


## The herd in the game itself (GameState): an old save's crews and workers turn into counts,
## errands and workers work from counts, stand-ins go on adventures, the room makes boxes wait.
func _test_herd_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the herd in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var roller := PetRoller.new(catalog, rng)
	var pets := []
	var coin: Dictionary = catalog.job("coin_hunt")
	var speed_sum := 0.0
	for i in 300:
		var p := roller.roll("starter", "common")
		p.finish = "normal"
		p.uid = str(i + 1)
		if i >= 1 and i <= 200:
			speed_sum += Jobs.pet_speed(p, coin)
		pets.append(p.to_dict())
	var crew := range(2, 202).map(func(n): return str(n))
	var workers := range(202, 242).map(func(n): return str(n))
	var auto := Automation.fresh()
	auto.taught = { "machine": true }
	auto.others = { "machine": true }
	auto.spots = { "machine": 50 }
	auto.workers = { "machine": workers }
	var old := { "version": 22, "coins": 10000000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "tab:automation", "feature:parties", "location:meadow"],
		"collection": { "pets": pets, "active": "1", "next_id": 301, "seen": {}, "fallen": [[5, "peach"]] },
		"jobs": { "coin_hunt": { "crew": crew, "fill": 0.5 } }, "automation": auto }
	SaveFile.write(path, old)
	var old_size := FileAccess.get_file_as_string(path).length()
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(c.count() == 300 and c.fallen_n == 1 and c.fallen == ["peach"], "an old save loads with every pet and its stars (%d)" % c.count())
	_check(c.herd_total() > 200 and c.pets.size() < 100, "old plain pets fold into the herd (%d cards)" % c.pets.size())
	_check(gs.job_size("coin_hunt") == 200 and not gs.job_herd("coin_hunt").is_empty() and gs.job_crew("coin_hunt").size() < 200,
		"an old crew of uids turns into counts (%d on the coin hunt)" % gs.job_size("coin_hunt"))
	_check(gs.workers_count("machine") == 40 and not gs.workers_herd("machine").is_empty(), "old workers turn into counts too")
	var cards_rate := Jobs.rate(coin, 200, speed_sum / 200.0, float(catalog.errands.crew_power))
	var herd_rate: float = gs.job_rate("coin_hunt")
	_check(absf(herd_rate - cards_rate) / cards_rate < 0.15, "a crew from counts works about as fast (%.4f vs %.4f)" % [herd_rate, cards_rate])
	gs.save_game()
	var new_size := FileAccess.get_file_as_string(path).length()
	_check(new_size < old_size / 3, "the save shrinks (%d -> %d bytes)" % [old_size, new_size])
	var resting: int = gs.resting_count()
	_check(resting == 300 - 1 - 200 - 40, "everyone else rests (%d)" % resting)
	# errands from counts
	gs.put_on_job("coin_hunt", -1)
	_check(gs.resting_count() == 0 and gs.job_size("coin_hunt") == 259, "+ all puts every resting pet on (%d)" % gs.job_size("coin_hunt"))
	var off: int = gs.take_off_job("coin_hunt", 100)
	_check(off == 100 and gs.resting_count() == 100 and gs.job_size("coin_hunt") == 159, "taking off 100 sends 100 home")
	gs.unlocks["feature:parts"] = true  # the scrapyard opens: two jobs to share out over
	gs.share_out()
	_check(gs.resting_count() == 0 and absi(gs.job_size("coin_hunt") - gs.job_size("scrapyard")) <= 159,
		"sharing out fills the smaller crew first (%d and %d)" % [gs.job_size("coin_hunt"), gs.job_size("scrapyard")])
	_check(gs.job_size("scrapyard") == 100, "every resting pet went to the empty scrapyard (%d)" % gs.job_size("scrapyard"))
	gs.take_off_job("scrapyard", -1)
	# new pets join the coin hunt: a new active pet sends the old one back to work there
	var resting_card: Array[Pet] = gs.resting_cards()
	_check(not resting_card.is_empty(), "a card is resting (to make active)")
	if not resting_card.is_empty():
		gs.set_job_join("coin_hunt", true)
		c.set_active(resting_card[0].uid)
		_check(gs.job_of("1") == "coin_hunt", "with new pets joining the coin hunt, the old active pet goes back to work there")
		gs.set_job_join("coin_hunt", false)
		c.set_active("1")
		gs.take_off_job(gs.job_of(resting_card[0].uid), 1, [resting_card[0].uid])
	# your pet names the pet you tapped, not another face from its count
	var tapped: Array = []
	for k in gs.resting_herd():
		tapped = c.stand_in_uids(k, 3)
		break
	_check(tapped.size() >= 2, "resting stand-ins to tap (%d)" % tapped.size())
	if not tapped.is_empty():
		gs.put_on_job("coin_hunt", 1, [tapped[-1]])
		_check(gs.last_moved == str(tapped[-1]), "your pet names the stand-in you tapped (%s)" % gs.last_moved)
		gs.take_off_job("coin_hunt", 1, [tapped[-1]])
		_check(gs.last_moved == str(tapped[-1]), "and the one you sent home")
	# workers from counts
	var put: int = gs.put_workers("machine", -1)
	_check(put == 10 and gs.workers_count("machine") == 50 and gs.workers_speed("machine") > 0.0, "workers fill up their machines from counts")
	_check(gs.take_off_workers("machine", 5) == 5 and gs.workers_count("machine") == 45, "workers go home from counts")
	# stand-ins on an adventure: the lost one leaves the count (a star), the rest come home into it
	var going: Array[Pet] = []
	for pet: Pet in gs.sendable_pets():
		if Herd.is_stand_in(pet.uid) and going.size() < 3:
			going.append(pet)
	var herd_before := c.herd_total()
	var run: RunState = gs.send_on_adventure("meadow", going)
	_check(run != null and run.party.size() == 3, "stand-ins from the herd go on an adventure")
	_check(not gs.sendable_pets().any(func(p): return p.uid == going[0].uid), "a stand-in away can't be sent twice")
	run.status = RunState.Status.DONE
	var lost_uid: String = run.party.uids[0]
	run.party.uids.erase(lost_uid)
	run.party.lost.append(lost_uid)
	var stars := c.fallen_n
	gs.collect_run(run)
	_check(c.herd_total() == herd_before - 1 and c.fallen_n == stars + 1, "a stand-in that stays leaves the herd and adds a star")
	_check(c.count() == 299, "the others come home (%d)" % c.count())
	# the room: full, box openings wait (nothing lost); more room opens them again
	gs.room = 0
	c.add_plain("common:normal", maxi(0, gs.room_cap() - c.plain_count()))
	gs.bag = { "starter": 3 }
	var none: Array = gs.open_boxes("starter", 1)
	_check(none.is_empty() and gs.in_bag("starter") == 3 and gs.room_left() == 0, "a full room: the box waits on the pile")
	_check(gs.buy_room() and gs.room == 1 and gs.room_left() > 0, "more room, bought with coins")
	_check(gs.open_boxes("starter", 1).size() == 1 and gs.in_bag("starter") == 2, "then the box opens")
	# a million plain pets in the game: save, load and a job stay quick
	c.add_plain("common:normal", 1000000)
	var t0 := Time.get_ticks_msec()
	gs.save_game()
	var t_save := Time.get_ticks_msec() - t0
	var size := FileAccess.get_file_as_string(path).length()
	t0 = Time.get_ticks_msec()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	var t_load := Time.get_ticks_msec() - t0
	_check(gs2.collection.count() == c.count(), "a million plain pets load back (%d)" % gs2.collection.count())
	t0 = Time.get_ticks_msec()
	gs2.put_on_job("coin_hunt", -1)
	var rate: float = gs2.job_rate("coin_hunt")
	var t_job := Time.get_ticks_msec() - t0
	_check(gs2.job_size("coin_hunt") > 1000000 and rate > 0.0, "a million pets on one errand")
	_check(size < 300000, "the save stays small with a million pets (%d bytes)" % size)
	_check(t_save < 300 and t_load < 1500 and t_job < 300, "a million pets: save %d ms, load %d ms, a job %d ms" % [t_save, t_load, t_job])
	print("  a million plain pets: save %d ms, load %d ms, a job %d ms, %d bytes" % [t_save, t_load, t_job, size])
	gs.free()
	gs2.free()
	# a save from before the room with more pets than its first level holds gets room for them
	var many := []
	for i in 700:
		var p := roller.roll("starter", "common")
		p.finish = "normal"
		p.uid = str(i + 1)
		many.append(p.to_dict())
	SaveFile.write(path, { "version": 22, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"collection": { "pets": many, "active": "1", "next_id": 701 } })
	var gs3: Node = load("res://scripts/game_state.gd").new()
	_check(gs3.room_left() > 0 and gs3.room > 0, "an old save with 700 pets loads with room to spare (%d / %d)" % [gs3.collection.plain_count(), gs3.room_cap()])
	gs3.free()
	_check(Herd.room_cap(catalog, Herd.room_level_for(catalog, 5000)) >= 5000 and Herd.room_cap(catalog, Herd.room_level_for(catalog, 5000) - 1) < 5000,
		"the room level for 5000 pets is the smallest that holds them")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Where the herd meets knacks: counts work at their plain template's speed (no uid, no knack
## share), cards at their own knack-adjusted speed, on errands and as workers alike.
func _test_herd_knacks(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the herd's knacks: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var roller := PetRoller.new(catalog, rng)
	var active := roller.roll("starter", "common")
	active.uid = "1"
	var dressed := roller.roll("starter", "common")
	dressed.uid = "2"
	dressed.finish = "holo"  # always a card
	dressed.stats = Herd.stats_for(catalog, "common")  # the same stats as a count's template
	dressed.traits = []
	dressed.parts.palette = "mint"  # minty fresh: errands
	dressed.parts.accessory = "crown"  # royal: automation
	var auto := Automation.fresh()
	auto.taught = { "machine": true }
	auto.others = { "machine": true }
	auto.spots = { "machine": 10 }
	var save := { "version": load("res://scripts/game_state.gd").SAVE_VERSION, "coins": 1000, "tutorial": "done",
		"saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:parts", "feature:errands", "tab:errands", "tab:automation"],
		"collection": { "pets": [active.to_dict(), dressed.to_dict()], "herd": { "common:normal": 3 }, "active": "1", "next_id": 3 },
		"automation": auto }
	SaveFile.write(path, save)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var card: Pet = gs.collection.get_pet("2")
	var job: Dictionary = catalog.job("coin_hunt")
	var template := Herd.template(catalog, "common:normal")
	_check(card != null and gs.feature_on("parts") and gs.feature_on("errands"), "the dressed card loads with parts and errands open")
	if card == null:
		gs.free()
		return
	_check(is_equal_approx(Jobs.pet_speed(card, job), Jobs.pet_speed(template, job)), "the card and the count have the same plain speed")
	_check(gs._pet_speed(card, job) > Jobs.pet_speed(card, job), "minty fresh makes the card faster on errands (%.3f)" % gs._pet_speed(card, job))
	_check(template.uid == "" and gs.knack_own(template, "errands") == 1.0 and gs.knack_own(template, "automation") == 1.0,
		"a count's template counts no knacks")
	gs.put_on_job("coin_hunt", 1)
	_check(gs.job_crew("coin_hunt") == ["2"] and gs.job_herd("coin_hunt").is_empty(), "+1 picks the dressed card ahead of an equal count")
	gs.put_on_job("coin_hunt", -1)
	gs.take_off_job("coin_hunt", 1)
	_check(gs.job_crew("coin_hunt") == ["2"] and gs.job_size("coin_hunt") == 3, "-1 sends a pet from the count home first")
	gs.take_off_job("coin_hunt", -1)
	_check(gs.job_size("coin_hunt") == 0, "everyone home again")
	var put: int = gs.put_workers("machine", -1)
	var own: float = gs.knack_own(card, "automation")
	var want := Automation.worker_speed(catalog, card) * own + Automation.worker_speed(catalog, template) * 3
	_check(put == 4 and own > 1.0, "the card and 3 from the count start working (%d, x%.3f)" % [put, own])
	_check(is_equal_approx(gs.workers_speed("machine"), want), "only the card adds its knack share to the workers (%.3f vs %.3f)" % [gs.workers_speed("machine"), want])
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## The plushie machine (F1/F2, Plushie, data/plushie.json): odds by a part's buttons, the spin rules
## (auto-bank, hold doubles, cracks, caps), bank / hold / nudge, the wild reel, wisps, buttons on
## knacks and through grafting.
func _test_plushie(catalog: Catalog) -> void:
	var d: Dictionary = catalog.plushie
	var most := Plushie.max_buttons(catalog)
	_check(most == 5 and d.button.size() == most and d.crack.size() == most, "a part holds 0-5 buttons, with odds for 0-4")
	for t in catalog.tiers:
		_check(int(d.spins.get(t.id, 0)) >= 1 and int(d.puff.get(t.id, 0)) >= 1, "every rarity gives spins and puffs wisps (%s)" % t.id)
	for f in catalog.finishes:
		_check(d.nudges.has(f.id), "every finish has nudges (%s)" % f.id)
	for tr in d.traits:
		_check(catalog.trait_info(tr).size() > 0, "trait tilt %s is a real trait" % tr)
	for n in most:
		for traits in [[], ["lucky"], ["curious"], ["lucky", "curious", "greedy", "zoomy"]]:
			var o := Plushie.odds_for(catalog, n, traits)
			_check(int(o.button) + int(o.blank) + int(o.crack) == 100 and int(o.blank) >= 0, "odds add up to 100%% (%d buttons, %s)" % [n, traits])
			_check(int(o.crack) >= int(d.crack_min), "a crack never gets rarer than crack_min (%d buttons, %s)" % [n, traits])
	_check(Plushie.odds_for(catalog, most, []).is_empty(), "a full part has no odds (it doesn't spin)")
	_check(Plushie.odds_for(catalog, 0, []).button == 34 and Plushie.odds_for(catalog, 4, []).button == 5, "button 34% at none, 5% at four")
	_check(Plushie.odds_for(catalog, 0, ["lucky"]).crack == 5 and Plushie.odds_for(catalog, 0, ["curious"]).button == 36, "lucky: fewer cracks, curious: more buttons")
	_check(Plushie.spins_for(catalog, { "rarity": "epic" }) == 4 and Plushie.spins_for(catalog, { "rarity": "common", "traits": ["zoomy"] }) == 2,
		"spins by rarity (epic 4), zoomy +1")
	# a try
	var keeper := Pet.new()
	keeper.uid = "1"
	keeper.parts = { "body": "bunny", "palette": "gold", "pattern": "stars", "eyes": "cyclops", "accessory": "horns" }
	var st := Plushie.fresh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	_check(Plushie.needs_next(st) and Plushie.spin(catalog, st, keeper, rng).is_empty(), "nobody in the machine: no spin")
	Plushie.feed(catalog, st, { "rarity": "common", "finish": "normal", "traits": [] })
	Plushie.feed(catalog, st, { "rarity": "rare", "finish": "shiny", "traits": [] })
	Plushie.feed(catalog, st, { "rarity": "uncommon", "finish": "normal", "traits": [] })
	var hop := Plushie.next_pet(catalog, st, keeper)
	_check(hop.fed.rarity == "rare" and st.try.spins == 3 and st.nudges == 1 and st.hopper.size() == 2,
		"the best pet hops in first: a shiny rare, 3 spins, 1 nudge")
	var all_forced := { "body": "button", "palette": "crack", "pattern": "blank", "eyes": "button", "accessory": "blank" }
	var r1 := Plushie.spin(catalog, st, keeper, rng, all_forced)
	var reels: Array = st.try.reels
	_check(r1.landed.size() == 5 and reels[0].held == 1 and reels[1].held == 0 and reels[2].held == 0 and reels[3].held == 1,
		"a button holds one, a crack and a blank hold nothing")
	_check(r1.puffed.size() == 3 and r1.puffed[1] == 24 and r1.puffed[2] == 12 and r1.wisps == 48, "misses puff wisps by rarity, a crack twice as much (%s)" % [r1.puffed])
	_check(st.try.spins == 2 and Plushie.total(keeper) == 0, "a spin used, nothing sewn on yet")
	_check(Plushie.toggle_hold(catalog, st, 0) and reels[0].hold, "hold the body reel")
	_check(not Plushie.toggle_hold(catalog, st, 2), "a reel holding nothing can't be held")
	var r2 := Plushie.spin(catalog, st, keeper, rng, { "body": "button", "palette": "blank", "pattern": "blank", "accessory": "blank" })
	_check(Plushie.buttons(keeper, "eyes") == 1 and reels[3].banked and r2.sewn.get("eyes", 0) == 1, "an unheld button banks by itself at the next spin")
	_check(not r2.landed.has(3), "a banked reel stops for this pet")
	_check(reels[0].held == 3 and not reels[0].hold, "a held reel that lands a button gets two more (3), and needs holding again")
	var nudges_before := int(st.nudges)
	reels[0].strip = ["crack", "button", "blank"]
	_check(Plushie.can_nudge(catalog, st, keeper, 0) and Plushie.nudge(catalog, st, keeper, 0, rng) == "crack", "a nudge moves the cell above into the middle")
	_check(reels[0].held == 0 and st.nudges == nudges_before - 1, "nudged onto a crack: the held buttons go, a nudge is used")
	reels[0].strip = ["button", "crack", "blank"]
	st.nudges = 1
	Plushie.nudge(catalog, st, keeper, 0, rng)
	_check(reels[0].held == 3 and st.nudges == 0, "nudged back onto the button: lands again from before the spin (3)")
	_check(not Plushie.can_nudge(catalog, st, keeper, 0), "no nudges left in the pool")
	_check(Plushie.toggle_hold(catalog, st, 0), "hold the body again")
	var r3 := Plushie.spin(catalog, st, keeper, rng, { "body": "crack", "palette": "blank", "pattern": "button", "accessory": "blank" })
	_check(reels[0].held == 0 and Plushie.buttons(keeper, "body") == 0, "a crack takes the held buttons away")
	_check(st.try.spins == 0 and Plushie.needs_next(st), "the spins are used up")
	_check(r3.landed.size() == 4, "every reel still going landed")
	_check(not Plushie.toggle_hold(catalog, st, 2), "no holding with no spins left")
	var r4 := Plushie.next_pet(catalog, st, keeper)
	_check(Plushie.buttons(keeper, "pattern") == 1 and r4.sewn.get("pattern", 0) == 1, "whatever's held when the spins run out is banked")
	_check(r4.fed.rarity == "uncommon" and not reels.any(func(r): return r.banked or r.held > 0), "the next pet hops in, the reels start over")
	# keepers: a swap there and back doesn't spin a banked reel again; a new keeper gets what's held
	var st_b: Dictionary = st.duplicate(true)
	var keeper_b := Pet.from_dict(keeper.to_dict(), catalog)
	var other := Pet.from_dict(keeper.to_dict(), catalog)
	other.uid = "2"
	other.buttons = {}
	Plushie.spin(catalog, st_b, keeper_b, rng, { "body": "button", "palette": "blank", "pattern": "blank", "eyes": "blank", "accessory": "blank" })
	_check(Plushie.bank(catalog, st_b, keeper_b, 0) == 1 and st_b.try.reels[0].banked, "bank the body")
	_check(not Plushie.can_hold(catalog, st_b, 0) and not Plushie.can_hold(catalog, st_b, 1), "a banked reel or one holding nothing can't be held")
	Plushie.set_keeper(catalog, st_b, other)
	Plushie.set_keeper(catalog, st_b, keeper_b)
	_check(st_b.try.reels[0].banked and st_b.keeper == "1", "a keeper swap there and back: the banked reel stays banked for this pet")
	var rb := Plushie.spin(catalog, st_b, keeper_b, rng, { "body": "button", "palette": "button", "pattern": "button", "eyes": "button", "accessory": "button" })
	_check(not rb.landed.has(0) and Plushie.anything_held(st_b), "so it doesn't spin again")
	var sewn_b := Plushie.set_keeper(catalog, st_b, other)
	_check(sewn_b.size() == 4 and Plushie.total(other) == 4 and not Plushie.anything_held(st_b), "a new keeper: whatever the reels held is sewn onto it, never dropped")
	st_b.try = Plushie.fresh_try()
	Plushie.next_pet(catalog, st_b, keeper_b)
	_check(not st_b.try.reels.any(func(r): return r.banked), "the next pet starts every reel again")
	# caps, full parts, bank, the hold limit
	keeper.buttons["body"] = 4
	Plushie.spin(catalog, st, keeper, rng, { "body": "button", "palette": "button", "pattern": "button", "eyes": "button", "accessory": "button" })
	_check(reels[0].held == 1, "a part with 4 buttons can only hold 1 more")
	_check(Plushie.bank(catalog, st, keeper, 0) == 1 and Plushie.full(catalog, keeper, "body") and reels[0].banked, "bank: sewn on, the body is full")
	_check(not Plushie.active(catalog, st, keeper, 0) and Plushie.odds(catalog, st, keeper, 0).is_empty(), "a full part doesn't spin")
	_check(Plushie.toggle_hold(catalog, st, 1) and Plushie.toggle_hold(catalog, st, 2) and not Plushie.toggle_hold(catalog, st, 3), "two holds at once to start with")
	st.bought.hold = 1
	_check(Plushie.toggle_hold(catalog, st, 3), "a bought hold makes three")
	_check(Plushie.toggle_hold(catalog, st, 3) and not reels[3].hold, "tap again to let go")
	# the shop and the wild reel
	st.bought = { "nudge": 0, "hold": 0 }
	_check(Plushie.price(catalog, st, keeper, "nudge") == 60 and Plushie.price(catalog, st, keeper, "hold") == 400, "a nudge 60 wisps, a hold 400")
	Plushie.buy(catalog, st, keeper, "nudge")
	_check(Plushie.price(catalog, st, keeper, "nudge") == 78 and st.nudges == 1, "a bought nudge goes in the pool, the next costs more")
	_check(Plushie.price(catalog, st, keeper, "wild") == 500, "the wild reel: 250 x the fed pet's rarity step (uncommon: 500)")
	_check(Plushie.wild_default(catalog, keeper) == "palette", "the wild reel starts on the part with the fewest buttons")
	var stuffed := Pet.from_dict(keeper.to_dict(), catalog)
	for slot in Catalog.SLOTS:
		stuffed.buttons[slot] = most
	_check(not Plushie.wild_available(catalog, st, stuffed) and Plushie.price(catalog, st, stuffed, "wild") == -1, "no wild reel when every part is full")
	var pricey: Dictionary = st.duplicate(true)
	pricey.bought.nudge = 5000
	_check(Plushie.price(catalog, pricey, keeper, "nudge") == roundi(float(d.shop.max)), "prices stop at shop.max")
	Plushie.buy(catalog, st, keeper, "wild")
	_check(st.try.wild.slot == "palette" and Plushie.price(catalog, st, keeper, "wild") == -1, "one wild reel per pet")
	Plushie.wild_step(catalog, st, keeper, -1)
	_check(st.try.wild.slot == "accessory", "‹ › skips the full body")
	Plushie.wild_step(catalog, st, keeper, 1)
	st.try.reels[1].hold = false
	var before := Plushie.buttons(keeper, "palette")
	var r5 := Plushie.spin(catalog, st, keeper, rng, { "wild": "button", "palette": "blank", "pattern": "blank", "eyes": "blank", "accessory": "blank" })
	_check(r5.wild.symbol == "button" and Plushie.buttons(keeper, "palette") >= before + 1, "the wild reel's button goes straight onto the part you picked")
	var r6 := Plushie.next_pet(catalog, st, keeper)
	_check(r6.fed.rarity == "common" and st.try.wild.is_empty(), "the wild reel was for that pet only")
	# wisps
	var plain := Pet.new()
	var gifted := Pet.new()
	gifted.buttons = { "body": 5, "eyes": 5 }
	st.try.fed = { "rarity": "epic", "traits": [] }
	_check(Plushie.puff(catalog, st, plain, false) == 40 and Plushie.puff(catalog, st, plain, true) == 80, "an epic's miss puffs 40, a crack 80")
	_check(Plushie.puff(catalog, st, gifted, false) == 80, "perfection: a keeper with 10 buttons makes misses puff twice as much")
	st.try.fed = { "rarity": "epic", "traits": ["greedy"] }
	_check(Plushie.puff(catalog, st, plain, false) == 60, "greedy pets puff half as much again")
	# saved and loaded
	var round_trip := Plushie.clean(JSON.parse_string(JSON.stringify(st)), catalog)
	_check(round_trip.try.reels.size() == 5 and int(round_trip.nudges) == int(st.nudges) and round_trip.hopper.size() == st.hopper.size(),
		"the machine survives a save")
	_check(Plushie.clean({ "try": { "reels": ["odd", { "strip": ["x"] }] }, "hopper": "nope" }, catalog).try.reels.size() == 5, "a broken save loads a fresh machine")
	# buttons make knacks bigger
	var open := func(_gate: String) -> bool: return true
	keeper.buttons.erase("eyes")
	var bare: Dictionary = Knacks.of(catalog, keeper, open).filter(func(k): return k.slot == "eyes")[0]
	keeper.buttons["eyes"] = 5
	var sewn_eyes: Dictionary = Knacks.of(catalog, keeper, open).filter(func(k): return k.slot == "eyes")[0]
	_check(sewn_eyes.buttons == 5 and sewn_eyes.n == roundi(float(bare.n) * 3.5), "5 buttons: the part's knack x3.5 (%d -> %d)" % [bare.n, sewn_eyes.n])
	var agree := true
	for kind in Boosts.kinds(catalog):
		var by_rows := 0
		for k in Knacks.of(catalog, keeper, open):
			if Knacks.covers(catalog, str(k.kind), kind):
				by_rows += int(k.n)
		agree = agree and by_rows == Knacks.total(catalog, keeper, kind, open)
	_check(agree, "lean knack totals count the buttons too")
	var copy := Pet.from_dict(JSON.parse_string(JSON.stringify(keeper.to_dict())), catalog)
	_check(copy.buttons == keeper.buttons, "buttons survive a save")
	_check(Pet.from_dict({ "buttons": { "body": 9, "tail": 2 } }, catalog).buttons == { "body": 5 }, "odd buttons from a save are fixed up")
	# grafting keeps buttons on the part
	_check(Grafting.split_key("body:bunny@3") == ["body", "bunny", 3] and Grafting.split_key("eyes:round") == ["eyes", "round", 0], "bag keys with buttons")
	_check(Grafting.valid_key("body:bunny@3", catalog) and not Grafting.valid_key("body:bunny@9", catalog) and not Grafting.valid_key("body:bunny@0", catalog),
		"a bag key names a real part with 1-5 buttons")
	var pet := Pet.new()
	for slot in Catalog.SLOTS:
		pet.parts[slot] = catalog.default_part(slot)
	var old_body: String = pet.parts.body
	pet.buttons = { "body": 3 }
	var sure := RandomNumberGenerator.new()
	var bag := { "body:bunny": 1 }
	var held_ok := false
	for t in 200:
		sure.seed = t
		bag = { "body:bunny": 1 }
		var p2 := Pet.from_dict(pet.to_dict(), catalog)
		var res := Grafting.sew(p2, "body", "bunny", bag, sure, catalog)
		if res.ok:
			held_ok = bag.get("body:%s@3" % old_body, 0) == 1 and not p2.buttons.has("body")
			var bag2 := bag.duplicate()
			var back := Grafting.sew(p2, "body", old_body, bag2, sure, catalog, 3)
			if back.is_empty() or not back.ok:
				continue
			held_ok = held_ok and p2.buttons.get("body", 0) == 3 and bag2.get("body:bunny", 0) == 1
			break
	_check(held_ok, "a part keeps its buttons: off into the bag as slot:id@3, and back on with them")
	# a pet with buttons is always a card
	var c := Collection.new()
	var one := Pet.new()
	one.parts = pet.parts.duplicate()
	one.rarity = "common"
	var two := Pet.from_dict(one.to_dict(), catalog)
	c.add([one, two] as Array[Pet])
	two.new_part = false
	_check(not c.always_card(two), "a plain pet may fold")
	two.buttons = { "eyes": 1 }
	_check(c.always_card(two), "a pet with buttons always stays a card")


## The plushie machine in the game: nothing before the find, then the machine and a free button;
## feeding from the herd and from cards (pets leave for good, each a star); the keeper stays a card;
## a try survives a save; a save from before the machine loads an empty one.
func _test_plushie_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the plushie machine in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var roller := PetRoller.new(catalog, rng)
	var pets := []
	for i in 6:
		var p := roller.roll("starter", "common")
		p.finish = "normal"
		p.uid = str(i + 1)
		p.parts.body = "bunny"  # a knack for the free button to go on
		pets.append(p.to_dict())
	pets[2].fav = true
	var old := { "version": 23, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:parts", "feature:errands", "tab:errands", "tab:inventory"],
		"parts": { "body:bunny": 1, "body:bunny@2": 3, "body:nope@1": 1 },
		"collection": { "pets": pets, "herd": { "common:normal": 30, "rare:shiny": 2 }, "active": "1", "next_id": 7 } }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(not gs.plushie_open() and gs.wisps == 0 and Plushie.needs_next(gs.plushie) and gs.plushie.hopper.is_empty(),
		"a save from before the machine loads with none of it")
	_check(gs.parts.get("body:bunny@2", 0) == 3 and not gs.parts.has("body:nope@1"), "bag keys with buttons load (unknown parts don't)")
	gs.check_unlocks()
	_check(not gs.plushie_open(), "nothing opens the machine before its find")
	_check(not gs.plushie_feed_herd("common") and gs.plushie_spin().is_empty(), "and it can't be used before then")
	var active: Pet = c.active()
	gs.grant({ "find:plushie_machine": 1 })
	_check(gs.plushie_open() and Plushie.total(active) == 1, "the find opens the machine and sews one free button onto your active pet")
	_check(Plushie.buttons(active, str(Knacks.best(catalog, active, gs.knack_gate).slot)) == 1, "on the part with its best knack")
	gs.grant({ "find:plushie_machine": 1 })
	_check(Plushie.total(active) == 1, "only once")
	gs.grant({ "wisps": 5 })
	gs.grant_wisps(7)
	_check(gs.wisps == 12, "wisps come through grant and grant_wisps")
	# keepers
	var keepers: Array = gs.plushie_keepers()
	_check(keepers[0] == active and keepers[1].uid == "3", "keepers: your active pet first, then favourites")
	_check(gs.plushie_keeper() == active, "your active pet is the keeper to start with")
	# feeding
	var stars := c.fallen_n
	var count := c.count()
	_check(gs.plushie_feed_herd("common") and gs.plushie_feed_herd("rare"), "pets from the herd go into the hopper")
	_check(c.herd_count("common:normal") == 29 and c.herd_count("rare:shiny") == 1, "they leave their counts")
	_check(c.fallen_n == stars + 2 and c.count() == count - 2, "each one that goes in adds a star")
	_check(not gs.plushie_feed_herd("mythic"), "no mythics in the herd, none to feed")
	var cards: Array = gs.plushie_cards()
	_check(not cards.any(func(p): return p.uid in ["1", "3"]), "never your active pet or a favourite")
	_check(gs.plushie_feed_card("2") and c.get_pet("2") == null, "a card goes in and leaves for good")
	_check(not gs.plushie_feed_card("1") and not gs.plushie_feed_card("3"), "the active pet and favourites can't be fed")
	gs.put_on_job("coin_hunt", -1)
	_check(gs.resting_herd().get("common:normal", 0) == 0, "every common from the herd is on the coin hunt")
	var on_job: int = gs.job_size("coin_hunt")
	_check(gs.plushie_feed_herd("common") and gs.job_size("coin_hunt") == on_job - 1, "none resting: one comes off its job")
	_check(gs.plushie.hopper.size() == 4, "four in the hopper")
	# a try
	var res: Dictionary = gs.plushie_spin()
	_check(res.get("next", false) and gs.plushie.try.fed.rarity == "rare" and gs.plushie.try.spins == 3, "the lever brings the best pet in first (the shiny rare)")
	_check(gs.plushie.nudges == 1, "its shine adds a nudge")
	gs.debug_land = { "body": "button", "palette": "crack", "pattern": "blank", "eyes": "button", "accessory": "blank" }
	var wisps_before: int = gs.wisps
	res = gs.plushie_spin()
	_check(res.landed.size() == 5 and gs.wisps > wisps_before, "a spin lands every reel and misses puff wisps")
	_check(gs.plushie_hold(0), "hold the body")
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	var st2: Dictionary = gs2.plushie
	_check(gs2.plushie_open() and gs2.wisps == gs.wisps and st2.try.reels[0].hold and st2.try.reels[0].held == 1 and st2.try.spins == 2,
		"a try survives a save (held, on hold, spins left)")
	_check(st2.hopper.size() == 3 and gs2.collection.active().buttons == active.buttons, "the hopper and the buttons too")
	_check(gs2.plushie_keeper().uid == "1", "and the keeper")
	gs2.free()
	# the keeper stays a card; swapping waits until nothing's held
	_check(not gs.plushie_swap(1), "no new keeper while a reel holds buttons")
	gs.plushie_bank(0)
	gs.plushie_bank(3)
	_check(Plushie.total(active) >= 3, "banked buttons are sewn on")
	_check(gs.plushie_can_swap(), "‹ › can go once nothing's held")
	_check(gs.plushie_swap(1) and gs.plushie_keeper().uid == "3", "then ‹ › picks the next keeper")
	_check(gs._busy_uids().has("3"), "the keeper can't fold into the herd")
	_check(gs.plushie.try.reels[0].banked and gs.plushie.try.reels[3].banked, "banked reels stay banked across a swap")
	_check(gs.plushie_swap(-1) and gs.plushie_keeper().uid == "1" and gs.plushie.try.reels[0].banked, "and there and back again")
	gs.plushie_swap(1)
	_check(not gs.sendable_pets().any(func(p): return p.uid == "3"), "the keeper can't go on an adventure")
	# an old save with the keeper away: the machine waits for it, nothing is reset
	var trip: RunState = gs.send_on_adventure("garden", [c.get_pet("4")] as Array[Pet])
	_check(trip != null, "a pet goes on an adventure")
	gs.plushie.keeper = "4"
	gs.plushie.try.reels[2].held = 1
	_check(gs.plushie_keeper() == null and str(gs.plushie.keeper) == "4" and gs.plushie.try.reels[2].held == 1 and gs.plushie.try.reels[0].banked,
		"a keeper that's away: no keeper for now, the reels keep what they hold")
	_check(gs.plushie_spin().is_empty(), "and no spins until it's home")
	gs.plushie.try.reels[2].held = 0
	gs.plushie.keeper = "3"
	_check(gs._herd_off_places("mythic:normal", 1) == 0, "nobody of that count on a job: none taken off")
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## New homes: points pay boxes (the jar keeps the rest), the sorting rule's line and keeps, the day's
## count, and pets leaving the collection (a star each, the book keeps them).
func _test_new_homes(catalog: Catalog) -> void:
	var st := NewHomes.fresh(catalog)
	_check(not st.rule.on and st.points == 0, "the sorting rule starts off and the jar empty")
	_check(NewHomes.pay(st, catalog, "common", 24) == 0 and st.points == 24, "24 commons: no box yet, 24 in the jar")
	_check(NewHomes.pay(st, catalog, "common", 1) == 1 and st.points == 0, "the 25th common fills a box")
	_check(NewHomes.pay(st, catalog, "mythic", 1) == 1 and st.points == 15, "a mythic: a box and 15 left over")
	_check(NewHomes.pay(st, catalog, "rare", 5) == 1 and st.points == 15, "5 rares: a box")
	# never a box engine: a starter box's pets are worth well under a box
	var box: Dictionary = catalog.box("starter")
	var weight := 0.0
	var points := 0.0
	for t in box.tiers:
		weight += float(box.tiers[t])
		points += float(box.tiers[t]) * NewHomes.worth(catalog, t)
	_check(points / weight < NewHomes.box_at(catalog) / 4.0, "a box's pet is worth under a quarter of a box (%.2f points)" % (points / weight))
	var rule := { "on": true, "below": "rare", "to": "homes", "keep": "holo" }
	var p := _plain_pet(catalog, "common", "normal", 1)
	_check(NewHomes.sorts(catalog, rule, p), "a plain common is below the line")
	p.finish = "shiny"
	_check(NewHomes.sorts(catalog, rule, p), "a shiny common too (the keep is holo and up)")
	p.finish = "holo"
	_check(not NewHomes.sorts(catalog, rule, p), "a holo common is kept")
	p.finish = "normal"
	p.new_part = true
	_check(not NewHomes.sorts(catalog, rule, p), "a pet with a part new to the book is always kept")
	p.new_part = false
	p.fav = true
	_check(not NewHomes.sorts(catalog, rule, p), "a favourite is always kept")
	p.fav = false
	_check(not NewHomes.sorts(catalog, rule, _plain_pet(catalog, "rare", "normal", 2)), "a rare isn't below rare")
	rule.on = false
	_check(not NewHomes.sorts(catalog, rule, p), "an off rule sorts nothing")
	NewHomes.count_sorted(st, "2026-09-29", 3)
	_check(NewHomes.sorted_on(st, "2026-09-29") == 3 and NewHomes.sorted_on(st, "2026-09-30") == 0, "sorted today counts one day")
	NewHomes.count_sorted(st, "2026-09-30")
	_check(NewHomes.sorted_on(st, "2026-09-30") == 1 and st.sorted == 4, "a new day starts over (the total keeps going)")
	var odd := NewHomes.clean(catalog, { "points": "x", "rule": { "below": "nope", "to": "moon", "keep": 3, "on": true }, "today": 5 })
	_check(odd.points == 0 and odd.rule.below == "rare" and odd.rule.to == "homes" and odd.rule.keep == "holo" and odd.rule.on, "a broken save's rule falls back to the defaults")
	# leaving: counts and cards go, a star each; the active pet stays
	var c := Collection.new()
	var cards: Array[Pet] = []
	for i in 5:
		cards.append(_plain_pet(catalog, "common", "normal", 10 + i))
	c.add(cards)
	c.add_plain("common:normal", 1000)
	var left_n := [0]
	c.pets_left.connect(func(n): left_n[0] += n)
	var stars := c.fallen_n
	var active := c.active_uid
	var n := c.leave({ "common:normal": 400 }, [active, cards[2].uid, cards[3].uid])
	_check(n == 402 and left_n[0] == 402 and c.fallen_n == stars + 402, "400 from the count and 2 cards leave, a star each (%d)" % n)
	_check(c.active_uid == active and c.get_pet(active) != null, "the active pet never leaves")
	_check(c.herd_count("common:normal") == 600 and c.count() == 603 and c.plain_count() == 603, "the counts go down with them")
	_check(c.get_pet(cards[2].uid) == null, "a card that left is gone")
	_check(c.stand_next.get("common:normal", 0) >= 400, "the looks of the pets that left never come back")
	# the sorting rule inside add: the book counts the pet, it leaves at once
	var sorter := func(pet: Pet) -> String: return "homes" if pet.rarity == "common" else ""
	var newcomers: Array[Pet] = [_plain_pet(catalog, "common", "normal", 50), _plain_pet(catalog, "rare", "normal", 51)]
	var before := c.count()
	var went := c.add(newcomers, sorter)
	_check(went.size() == 1 and c.count() == before + 1 and c.get_pet(went[0].uid) == null, "a sorted pet never joins the collection")
	_check(c.times_seen(Collection.finish_key(went[0].parts.body, went[0].finish)) >= 1, "the book still counts a pet that went to a new home")
	_check(c.finish_seen("normal") and not c.finish_seen("prismatic"), "the book knows which finishes it has had")
	# a finish changed by hand (the dev dress step) keeps the room and the folding right
	var plain_before := c.plain_count()
	var dressed := c.get_pet(cards[0].uid)
	c.set_finish(dressed, "holo")
	_check(c.plain_count() == plain_before - 1 and not c._plain_cards.has(dressed), "a pet dressed holo leaves the room count and never folds")
	c.set_finish(dressed, "normal")
	_check(c.plain_count() == plain_before and c._plain_cards.has(dressed), "dressed back plain it counts again (and may fold)")


## New homes in the game: an old save moves over (sharing on -> every errand's switch on, a full
## room opens the stall), the stall takes the right pets in the right order and pays boxes, the
## sorting card opens after enough by hand, the rule sorts new pets from boxes (to new homes or to
## work) and "new pets join here" places new pets (machines first, then errands).
func _test_new_homes_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped new homes in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 30:
		var p := _plain_pet(catalog, "common", "normal", 100 + i)
		p.uid = str(i + 1)
		if i == 1:
			p.fav = true
		if i == 2:
			p.new_part = true
		if i == 3:
			p.finish = "holo"
		pets.append(p.to_dict())
	var old := { "version": 23, "coins": 1000000000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "tab:automation"], "jobs_auto": true, "room": 0,
		"collection": { "pets": pets, "herd": { "common:normal": 471 }, "active": "1", "next_id": 31, "seen": {} },
		"jobs": { "coin_hunt": { "crew": [], "herd": { "common:normal": 100 }, "fill": 0.0 } } }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(gs.job_joins("coin_hunt"), "an old save with sharing on: new pets join every open errand")
	_check(gs.room_is_full() and gs.homes.room_was_full and gs.homes_open(), "an old save with a full room has the stall (%d / %d)" % [c.plain_count(), gs.room_cap()])
	_check(not gs.feature_on("sorting") and not gs.homes.rule.on, "the sorting card waits (and starts off)")
	# who goes, and in what order: resting before working, never the ones that always stay
	var resting: int = gs.resting_count() - 3  # the favourite, the new part and the holo rest too, but stay
	var plan: Dictionary = gs.homes_pick("common", resting + 5)
	_check(Herd.total(plan.work) + plan.cards.filter(func(u): return gs.job_of(u) != "").size() == 5, "resting pets go first, then 5 from work")
	var every: Dictionary = gs.homes_pick("common")
	var keep := ["1", "2", "3", "4"]  # active, favourite, new part, holo
	_check(not every.cards.any(func(u): return u in keep), "never the active pet, a favourite, a new part or holo")
	var stars := c.fallen_n
	var bag0: int = gs.in_bag("starter")
	var got: Dictionary = gs.send_home("common", 60)
	_check(got.n == 60 and got.boxes == 2 and gs.in_bag("starter") == bag0 + 2 and gs.homes.points == 10, "60 commons: 2 boxes and 10 in the jar")
	_check(c.fallen_n == stars + 60, "every pet that leaves adds a star")
	_check(gs.room_left() == 60, "they free room (%d)" % gs.room_left())
	var size_before: int = gs.job_size("coin_hunt")
	got = gs.send_home("common", -1)
	_check(gs.job_size("coin_hunt") == 0 and size_before == 100 and c.count() == 4, "all: the resting and the working go, the 4 that always stay stay (%d)" % c.count())
	_check(gs.feature_on("sorting"), "after 300 by hand the sorting card turns up (%d)" % gs.homes.by_hand)
	# the rule: only box openings, below the line leave at once, the rest stay
	c.add_plain("common:normal", 20)
	gs.bag["starter"] = 100
	gs.set_rule("on", true)
	gs.set_rule("below", "rare")
	gs.set_rule("to", "homes")
	gs.set_rule("keep", "holo")
	var count0 := c.count()
	var stars0 := c.fallen_n
	var pulled: Array = gs.open_boxes("starter", 30, "common")
	var stayed := pulled.filter(func(pet): return c.get_pet(pet.uid) != null)
	_check(pulled.size() == 30 and stayed.all(func(pet): return pet.new_part or catalog.finish_rank(pet.finish) >= catalog.finish_rank("holo")),
		"new commons leave as they come, but new parts and holo stay (%d stayed)" % stayed.size())
	_check(c.count() == count0 + stayed.size() and c.fallen_n == stars0 + 30 - stayed.size(), "the sorted ones are stars now")
	_check(gs.sorted_today() == 30 - stayed.size(), "sorted today counts them (%d)" % gs.sorted_today())
	# a good pull the rule sends off is never pinned for your pet to show (or logged as good)
	gs.set_rule("below", "epic")
	gs.pinned.clear()
	var rares: Array = gs.open_boxes("starter", 40, "rare", true)
	var rares_gone := rares.filter(func(pet): return c.get_pet(pet.uid) == null)
	_check(rares_gone.size() > 0 and rares_gone.all(func(pet): return gs._sent_home.has(pet.uid)), "rares sorted off are known as sent home (%d of %d)" % [rares_gone.size(), rares.size()])
	gs.pinned.assign(["a", "b", "c"])
	gs.dismiss_pinned("b")
	gs.dismiss_pinned("zz")
	_check(gs.pinned == ["a", "c"], "seeing one good pull takes only that one off the wall")
	gs.pinned.clear()
	gs.set_rule("below", "rare")
	count0 = c.count()
	gs.debug_give_pets(3)  # not a box opening: never sorted
	_check(c.count() == count0 + 3, "pets that don't come out of a box aren't sorted")
	gs.homes.today.day = "2000-01-01"
	_check(gs.sorted_today() == 0, "a new day: sorted today starts over")
	# to work: every open errand when no switch is on
	gs.set_job_join("coin_hunt", false)
	gs.set_rule("to", "work")
	var hunt0: int = gs.job_size("coin_hunt")
	pulled = gs.open_boxes("starter", 10, "common")
	var sorted_n: int = pulled.filter(func(pet): return NewHomes.sorts(catalog, gs.homes.rule, pet)).size()
	_check(gs.job_size("coin_hunt") == hunt0 + sorted_n, "the rule's work pets go to the errands (%d of %d)" % [gs.job_size("coin_hunt") - hunt0, sorted_n])
	gs.set_rule("on", false)
	# busy paws: machines with room first (the best workers), then the errands switched on
	gs.automation.taught["machine"] = true
	gs.automation.others["machine"] = true
	gs.automation.spots["machine"] = 3
	gs.set_worker_join("machine", true)
	gs.set_job_join("coin_hunt", true)
	var hunt1: int = gs.job_size("coin_hunt")
	gs.debug_give_pets(10)
	_check(gs.workers_count("machine") == 3 and gs.job_size("coin_hunt") == hunt1 + 7, "new pets fill the machines first, the rest join the coin hunt")
	gs.set_worker_join("machine", false)
	gs.set_job_join("coin_hunt", false)
	var rest0: int = gs.resting_count()
	gs.debug_give_pets(5)
	_check(gs.resting_count() == rest0 + 5, "no switch on: new pets rest")
	gs.set_worker_join("adventures", true)
	_check(not gs.worker_joins("adventures"), "adventures never get the switch (parties keep their slots)")
	# a round trip keeps it all
	gs.set_job_join("coin_hunt", true)
	gs.set_rule("on", true)
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(gs2.job_joins("coin_hunt") and gs2.homes.rule.on and gs2.homes.rule.to == "work" and gs2.homes.points == gs.homes.points
		and gs2.homes.by_hand == gs.homes.by_hand, "new homes and the switches load back")
	gs2.free()
	# a million commons, all at once
	gs.room = 30
	c.add_plain("common:normal", 1000000)
	var t0 := Time.get_ticks_msec()
	got = gs.send_home("common", -1)
	var ms := Time.get_ticks_msec() - t0
	_check(got.n >= 1000000 and ms < 500, "a million commons leave in one go (%d ms)" % ms)
	_check(c.fallen.size() <= int(catalog.herd.get("fallen_keep", 16384)), "stars past the kept palettes are only counted")
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## The dungeon, the plushie machine and new homes together: a v23 save loads at the newest version
## with all three moved over; a pet is in one place at a time (the keeper is never sent, never in the
## army; the stall never takes the army's cards or herd pets).
func _test_merged_lanes(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the merged lanes: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 12:
		var p := _plain_pet(catalog, "common" if i < 6 else "rare", "normal", 300 + i)
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	var old := { "version": 23, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "location:cellar", "feature:parts", "feature:errands", "tab:errands",
			"tab:automation", "tab:inventory"],
		"jobs_auto": true, "room": 0,
		"collection": { "pets": pets, "herd": { "common:normal": 600 }, "active": "1", "next_id": 13, "seen": {} },
		"jobs": { "coin_hunt": { "crew": [], "herd": { "common:normal": 50 }, "fill": 0.0 } } }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	var newest: int = load("res://scripts/game_state.gd").SAVE_VERSION
	_check(newest == 29, "the save chain ends at v29 (dungeon 24, plushie 25, new homes 26, the sewing room 27, perks 28, held landings 29)")
	_check("cellar" in gs.dungeon.bands, "v24: an old save's open cellar is a dungeon band")
	_check(not gs.plushie_open() and gs.wisps == 0 and gs.plushie.hopper.is_empty(), "v25: an empty plushie machine and no wisps")
	_check(gs.job_joins("coin_hunt"), "v26: sharing on -> new pets join the errand")
	_check(gs.homes_open(), "v26: a full room has the stall (%d / %d)" % [c.plain_count(), gs.room_cap()])
	gs.save_game()
	_check(int(SaveFile.read(path).get("version", 0)) == newest, "it saves at v26")
	# the keeper stays home: never sendable, never in the army
	gs.grant({ "find:deep_rope": 1, "find:plushie_machine": 1 })
	_check(gs.dungeon_open() and gs.plushie_open(), "the dungeon and the plushie machine open")
	var keeper_pet: Pet = null
	for pet in gs.plushie_keepers():
		if pet.uid != c.active_uid and int(pet.uid) > 6:  # a rare card, strong enough for the front row
			keeper_pet = pet
			break
	while gs.plushie_keeper() != keeper_pet and gs.plushie_swap(1):
		pass
	var keeper: String = gs.plushie_keeper_uid()
	_check(keeper == keeper_pet.uid, "a rare card is the keeper (%s)" % keeper)
	_check(not gs.sendable_pets().any(func(p): return p.uid == keeper), "the keeper can't be sent on an adventure")
	gs.army_best()
	_check(not gs.army().cards.any(func(p): return p.uid == keeper) and not gs.army_choices().any(func(p): return p.uid == keeper),
		"army best never picks the keeper")
	_check(not gs.set_army_card(keeper, true), "nor can it be put in the army by hand")
	var soldier: String = gs.army().cards[0].uid
	_check(not gs.plushie_keepers().any(func(p): return p.uid == soldier), "a pet in the army can't become the keeper")
	# the stall never takes the army's cards or herd pets
	gs.set_army_herd("common", 100)
	var army_herd: int = Herd.total(gs.army_herd_keys())
	_check(army_herd == 100, "100 commons from the herd in the army (%d)" % army_herd)
	var every: Dictionary = gs.homes_pick("common")
	_check(not every.cards.any(func(u): return u in gs.dungeon.cards or u == keeper), "the stall never picks army cards or the keeper")
	var herd_before: int = c.herd_count("common:normal")
	gs.send_home("common", -1)
	_check(c.herd_count("common:normal") == army_herd and herd_before - army_herd > 0,
		"all: every common goes but the army's (%d left)" % c.herd_count("common:normal"))
	_check(Herd.total(gs.army_herd_keys()) == army_herd, "the army still has its herd pets")
	_check(gs.send_army(), "and the army can still go down")
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + what)


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
	_check(Knacks.size(catalog, "spots", "epic", "holo", 2) == 60, "with 2 buttons: x2 = 60%")
	var open := func(gate: String) -> bool: return gate != "feature:dungeon"  # everything but the dungeon
	var shut := func(gate: String) -> bool: return gate != "feature:parts"
	var pet := Pet.new()
	pet.parts = { "body": "bunny", "palette": "gold", "pattern": "stars", "eyes": "cyclops", "accessory": "horns" }
	var ks := Knacks.of(catalog, pet, open)
	_check(ks.size() == 4 and not ks.any(func(k): return k.kind == "power"), "the demon horns' power knack stays hidden until the dungeon opens (%d)" % ks.size())
	var all_open := func(_gate: String) -> bool: return true
	_check(Knacks.of(catalog, pet, all_open).any(func(k): return k.kind == "power"), "the demon horns' power knack shows once the dungeon is open")
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
			seen[i] += Intel.roll(garden, func(_id): return false, {}, rng, 1.0 if i == 0 else 1.5).size()
	_check(seen[1] > seen[0], "spotting knacks spot more places (%d vs %d)" % [seen[1], seen[0]])


## An army for Dungeon's rules: `n` cards of `power` (rarity rank `rank`), `herd` plain commons of `herd_power`.
func _army(n: int, power: float, herd: int, herd_power: float, rank := 0, luck := 1.0) -> Dictionary:
	var cards: Array = []
	for i in n:
		cards.append({ "uid": "c%d" % i, "power": power, "rank": rank })
	var h := {}
	if herd > 0:
		h["common:normal"] = { "n": herd, "power": herd_power, "rank": 0 }
	return { "cards": cards, "herd": h, "luck": luck, "boost": 1.0 }


## E1, the old well dungeon (Dungeon, data/dungeon.json): floors, power, a run, the lanterns (wisps)
## it pays, losses and who goes first; then in the game: the army's pets are busy, lost ones become
## stars, firsts pay once, the key stays hidden, the cellar and further down are bands, the v24 save.
func _test_dungeon(catalog: Catalog) -> void:
	var d: Dictionary = catalog.dungeon
	# the well: bands and floors
	_check(is_equal_approx(Dungeon.strength(catalog, 1), 120.0) and is_equal_approx(Dungeon.strength(catalog, 10), 100.0 * pow(1.2, 10)),
		"floor strength is 100 x 1.2^floor (%.1f, %.1f)" % [Dungeon.strength(catalog, 1), Dungeon.strength(catalog, 10)])
	var kinds := [1, 10, 11, 13, 15, 17, 19, 20, 21, 30].map(func(f): return Dungeon.floor_kind(catalog, f))
	_check(kinds == ["rope", "rope", "door", "tiny", "knock", "tiny", "knock", "door", "stairs", "guard"], "the well's floors: rope, doors, tiny and knock doors, stairs, a guard every 10th (%s)" % [kinds])
	_check(is_equal_approx(Dungeon.strength(catalog, 30), 100.0 * pow(1.2, 30) * 2.0), "a guard floor is twice as strong")
	var fresh := Dungeon.fresh(catalog)
	_check(Dungeon.shown_bands(catalog, fresh) == ["well"] and Dungeon.target_max(catalog, fresh) == 5, "a new dungeon shows the well only, and aims 5 floors down at most")
	fresh.deep = 10
	_check(Dungeon.shown_bands(catalog, fresh) == ["well", "cellar"] and Dungeon.target_max(catalog, fresh) == 15, "at the bottom of the well the cellar shows")
	_check(not Dungeon.first_earned(catalog, fresh), "who goes first isn't earned at floor 10")
	fresh.deep = 11
	_check(Dungeon.first_earned(catalog, fresh), "who goes first is earned in the cellar")
	var word_low: Array = Dungeon.word(catalog, 0.1)
	var word_high: Array = Dungeon.word(catalog, 10.0)
	_check(word_low[0] == "brr!" and word_high[0] == "easy peasy", "feeling words go from easy peasy to brr!")

	# pet power: stat (traits) x rarity x finish x its own knack
	var pet := _plain_pet(catalog, "rare", "normal", 3)
	pet.traits.clear()
	var base := float(pet.stats.power) * float(d.power.rarity_x.rare)
	_check(is_equal_approx(Dungeon.pet_power(catalog, pet), base), "a rare's power is its stat x the rare multiplier")
	pet.finish = "holo"
	_check(is_equal_approx(Dungeon.pet_power(catalog, pet, 1.1), base * float(d.power.finish_x.holo) * 1.1), "a finish and its own power knack multiply it")

	# rope floors: only the front row; tiny doors: only rare and up
	var a := _army(30, 10.0, 100, 5.0)
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "rope"), 200.0), "on a rope floor only the front row fights (%.1f)" % Dungeon.army_power(catalog, a, "rope"))
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "door"), 200.0 + 10 * 10 * 0.5 + 100 * 5 * 0.5), "on other floors everyone behind counts half")
	_check(Dungeon.army_power(catalog, a, "tiny") == 0.0, "commons don't fit through a tiny door")
	a.cards.push_front({ "uid": "r", "power": 50.0, "rank": catalog.rank("rare") })
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "tiny"), 50.0), "a rare fits through a tiny door")

	# a knock-back door nobody answers sends them home: no pay for that floor
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var strong := _army(20, 1.0e6, 280, 1.0e5, catalog.rank("rare"), 0.0)
	var knocked := Dungeon.simulate(catalog, strong, { "target": 20, "home_at": 90 }, rng)
	_check(knocked.why == "knock" and int(knocked.turned) == 15 and Dungeon.cleared_to(knocked) == 14 and knocked.floors.size() == 14,
		"a missed knock door ends the run on the floor before (%s at %d)" % [knocked.why, int(knocked.turned)])
	var weak := Dungeon.simulate(catalog, _army(20, 0.0, 0, 0.0), { "target": 5, "home_at": 90 }, rng)
	_check(weak.why == "stuck" and Dungeon.cleared_to(weak) == 0 and Dungeon.run_pay(weak) == 0, "an army with no power can't pass floor 1 and brings nothing")

	# pay: per pet sent (at most the entrance), never per pet lost
	_check(Dungeon.pay(catalog, 5, 1000, 0) == Dungeon.pay(catalog, 5, 300, 0) and Dungeon.pay(catalog, 5, 300, 0) > Dungeon.pay(catalog, 5, 100, 0),
		"a floor pays for the pets sent, at most the entrance")
	_check(Dungeon.pay(catalog, 12, 300, 0) > Dungeon.pay(catalog, 11, 300, 0), "deeper floors pay more")
	rng.seed = 11
	var fine := Dungeon.simulate(catalog, _army(20, 1000.0, 280, 50.0), { "target": 5, "home_at": 90 }, rng)
	var hurt := Dungeon.simulate(catalog, _army(20, 15.0, 280, 1.0), { "target": 5, "home_at": 90 }, rng)
	var lost_fine := Dungeon.run_lost(fine)
	var lost_hurt := Dungeon.run_lost(hurt)
	_check(Dungeon.cleared_to(hurt) == 5 and lost_hurt[0].size() + Herd.total(lost_hurt[1]) > lost_fine[0].size() + Herd.total(lost_fine[1]),
		"a weaker army loses more on the way (%d)" % (lost_hurt[0].size() + Herd.total(lost_hurt[1])))
	_check(Dungeon.run_pay(fine) == Dungeon.run_pay(hurt) and Dungeon.run_pay(fine) > 0, "and brings home just as much: pay never looks at losses (%d, %d)" % [Dungeon.run_pay(fine), Dungeon.run_pay(hurt)])

	# come home when X% are gone
	rng.seed = 2
	var home := Dungeon.simulate(catalog, _army(20, 12.0, 280, 1.0), { "target": 10, "home_at": 10 }, rng)
	var lost_home := Dungeon.run_lost(home)
	_check(home.why == "home" and Dungeon.cleared_to(home) < 10 and lost_home[0].size() + Herd.total(lost_home[1]) >= 30,
		"'come home when 10%% are gone' brings them home early (%s at floor %d)" % [home.why, Dungeon.cleared_to(home)])

	# who goes first: the injured first until it's earned, then the herd, anyone or the front row
	var cards := [{ "uid": "a", "power": 9.0, "rank": 0 }, { "uid": "b", "power": 8.0, "rank": 0 }, { "uid": "c", "power": 7.0, "rank": 0 }, { "uid": "d", "power": 6.0, "rank": 0 }]
	var herd := { "common:normal": 10 }
	var got: Array = Dungeon._take(2, "", cards.duplicate(), { "a": true, "c": true }, herd.duplicate(), {}, 20, rng)
	got[0].sort()
	_check(got[0] == ["a", "c"] and Herd.total(got[1]) == 0, "before who goes first is earned, the injured go first (%s)" % [got[0]])
	got = Dungeon._take(3, "plain ones", cards.duplicate(), {}, herd.duplicate(), {}, 20, rng)
	_check(got[0].is_empty() and Herd.total(got[1]) == 3, "'plain ones' go first: the herd")
	got = Dungeon._take(3, "the front row", cards.duplicate(), {}, herd.duplicate(), {}, 20, rng)
	_check(got[0].size() == 3 and Herd.total(got[1]) == 0, "'the front row' goes first: the cards")
	var no_gear := RegEx.create_from_string("Gear\\.[a-z_]+\\(|\\bgear\\b")
	_check(no_gear.search(FileAccess.get_file_as_string("res://scripts/dungeon/dungeon.gd")) == null, "gear never counts in the dungeon")
	_test_dungeon_game(catalog)


func _test_dungeon_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the dungeon in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	var tiers := ["common", "uncommon", "rare", "epic"]
	for i in 30:
		var p := _plain_pet(catalog, tiers[i % tiers.size()], "holo", 100 + i)  # holo: they stay cards
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	var auto := Automation.fresh()
	auto.party = { "place": "cellar", "n": 3 }
	var old := { "version": 23, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "location:cellar", "location:below", "feature:parts", "tab:automation",
			"feature:errands", "tab:errands"],
		"heard": ["well", "cellar"], "rumours": ["cellar"],
		"collection": { "pets": pets, "active": "1", "next_id": 31, "seen": {}, "herd": { "common:normal": 500 }, "herd_ever": true },
		"automation": auto, "room": 20 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	# v24: the cellar and further down are bands already reached; waiting rumours and parties move on
	_check(gs.dungeon.bands == ["well", "cellar", "below"], "an old save that had the cellar and further down has those bands (%s)" % [gs.dungeon.bands])
	_check(not "cellar" in gs.rumours and gs.automation.party.place == "well", "their rumours go, a party going there goes to the well")
	_check(gs.is_unlocked("location:cellar"), "the old unlocks stay")
	_check(not gs.location_open(catalog.location("cellar")) and not gs.location_open(catalog.location("below")), "the cellar and further down aren't trips any more")
	var some: Array[Pet] = [gs.collection.get_pet("2")]
	_check(gs.send_on_adventure("cellar", some) == null, "nobody can be sent to a band")
	_check(gs.location_open(catalog.location("well")), "the top of the well is still a trip")
	_check(not gs.dungeon_open(), "the dungeon waits for the rope find")
	gs.grant({ "find:deep_rope": 1 })
	_check(gs.dungeon_open(), "the rope find opens the dungeon")

	# the army's pets are busy: not resting, not sendable, not on errands
	var resting_before: int = gs.resting_count()
	gs.army_best()
	var army: Dictionary = gs.army()
	_check(army.cards.size() == 20 and int(army.sent) == 20, "the best ones fill the front row (%d)" % army.cards.size())
	var best_uid: String = army.cards[0].uid
	_check(not gs.resting_cards().any(func(p): return p.uid == best_uid) and not gs.sendable_pets().any(func(p): return p.uid == best_uid),
		"a card in the army isn't resting or sendable")
	gs.set_army_herd("common", 1000)
	army = gs.army()
	_check(int(army.herd.get("common", 0)) == 280 and int(army.sent) == 300, "the herd fills the entrance and no more (%d)" % int(army.sent))
	_check(gs.resting_count() == resting_before - 300, "the army's pets aren't resting (%d)" % gs.resting_count())
	gs.put_on_job("coin_hunt", -1)
	_check(gs.job_size("coin_hunt") == resting_before - 300 and int(gs.army().sent) == 300, "errands take everyone else, never the army")
	gs.take_off_job("coin_hunt", -1)
	_check(gs.floor_words(1, 3).size() == 3, "the next floors get feeling words")

	# a run: it goes, its pets stay busy, it comes home
	_check(gs.send_army() and gs.dungeon_running(), "the army goes down")
	_check(not gs.set_army_card("2", true) and gs.dungeon_floor_now() >= 0.0, "the army can't change while it's down there")
	var sent_uids: Array = gs.dungeon.run.cards.duplicate()
	var lost_uid: String = sent_uids[5]
	var stars: int = gs.collection.fallen_n
	var plain: int = gs.collection.plain_count()
	var parts_before := 0
	for k in gs.parts:
		parts_before += int(gs.parts[k])
	var floors := []
	for f in range(1, 11):
		floors.append({ "f": f, "cleared": true, "lost_cards": [lost_uid] if f == 3 else [], "lost_herd": { "common:normal": 5 } if f == 4 else {}, "pay": 2 })
	# before parts are open, floor 10's part waits for a later clear (never lost)
	gs.unlocks.erase("feature:parts")
	gs.dungeon.run = { "at": 0.0, "floors": floors.slice(0, 10).map(func(f): return { "f": f.f, "cleared": true, "lost_cards": [], "lost_herd": {}, "pay": 0 }),
		"why": "target", "turned": 0, "cards": sent_uids, "herd": { "common:normal": 280 }, "sent": 300, "target": 10 }
	gs._dungeon_tick()
	_check(not gs.dungeon.firsts.has("10"), "floor 10's part waits while parts aren't open")
	gs.unlocks["feature:parts"] = true
	gs.dungeon.deep = 0
	gs.dungeon.last = {}
	gs.dungeon.run = { "at": 0.0, "floors": floors, "why": "target", "turned": 0, "cards": sent_uids, "herd": { "common:normal": 280 }, "sent": 300, "target": 10 }
	gs._dungeon_tick()
	_check(not gs.dungeon_running() and gs.wisps == 20 and int(gs.dungeon.deep) == 10, "home: 10 floors lit, their wisps paid (%d)" % gs.wisps)
	_check(gs.collection.get_pet(lost_uid) == null and gs.collection.fallen_n == stars + 6, "pets that didn't come back are stars now (%d)" % (gs.collection.fallen_n - stars))
	_check(gs.collection.herd_count("common:normal") == 495 and gs.collection.plain_count() == plain - 5, "and they leave the room")
	_check(not lost_uid in gs.dungeon.cards and gs.dungeon.last.back == 294, "the army and the last run know (%d came home)" % int(gs.dungeon.last.back))
	var parts_after := 0
	for k in gs.parts:
		parts_after += int(gs.parts[k])
	_check(parts_after == parts_before + 1 and gs.dungeon.firsts.has("10"), "floor 10 gives the first dungeon part")
	_check(gs.feature_on("lead_army") and gs.knows_job("army"), "and your pet learns to lead the army")
	_check(not gs.finds.has("little_key"), "the key stays hidden before floor 20")
	gs.dungeon.run = { "at": 0.0, "floors": floors, "why": "target", "turned": 0, "cards": gs.dungeon.cards.duplicate(), "herd": {}, "sent": 19, "target": 10 }
	gs._finish_dungeon_run()
	var parts_again := 0
	for k in gs.parts:
		parts_again += int(gs.parts[k])
	_check(parts_again == parts_after, "a floor's first thing comes only once")
	var deep_floors := []
	for f in range(1, 21):
		deep_floors.append({ "f": f, "cleared": true, "lost_cards": [], "lost_herd": {}, "pay": 1 })
	gs.dungeon.run = { "at": 0.0, "floors": deep_floors, "why": "target", "turned": 0, "cards": gs.dungeon.cards.duplicate(), "herd": {}, "sent": 19, "target": 20 }
	gs._finish_dungeon_run()
	_check(gs.finds.has("little_key") and gs.announcements.any(func(t): return "key" in t), "floor 20 gives the key, with one quiet line")
	# your pet leads the army: it goes down again whenever it's home
	gs.set_task("army")
	gs._dungeon_tick()
	_check(gs.dungeon_running(), "leading the army sends it again when it's home")
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(gs2.dungeon_running() and gs2.wisps == gs.wisps and int(gs2.dungeon.deep) == 20 and gs2.dungeon.cards.size() == gs.dungeon.cards.size(),
		"the dungeon comes back from the save")
	gs.free()
	gs2.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## E3 the sewing room (Sewing, data/sewing.json): fixed rooms and rolled ones (the same every time,
## a button lock first, more marks and buttons deeper), what each mark matches, the lock looks at the
## front row only, the rooms shown, keep lines (how many, what they pick, the cap), a room run.
func _test_sewing(catalog: Catalog) -> void:
	var d: Dictionary = catalog.sewing
	var fixed := Sewing.fixed_count(catalog)
	_check(fixed >= 8 and fixed <= 10, "the sewing room has 8-10 fixed rooms (%d)" % fixed)
	var parts_ok := true
	for i in fixed + 30:
		var r := Sewing.room(catalog, i)
		_check(r.marks.size() >= 3 and r.marks.size() <= 5, "room %d has 3-5 marks (%d)" % [i, r.marks.size()])
		for mark in r.marks:
			var p := str(mark).split(":")
			var real := false
			match p[0]:
				"part": real = p.size() == 3 and not catalog.part(p[1], p[2]).is_empty()
				"trait": real = catalog.traits.any(func(t): return t.id == p[1])
				"finish": real = catalog.finish(p[1]).id == p[1]
				"tier": real = catalog.tiers.any(func(t): return t.id == p[1])
				"buttons": real = int(p[1]) >= 1 and int(p[1]) <= Plushie.max_buttons(catalog) * Catalog.SLOTS.size()
			parts_ok = parts_ok and real
			if not real:
				_check(false, "room %d's mark %s is real" % [i, mark])
		if i > 0:
			_check(Sewing.strength(catalog, r) > Sewing.strength(catalog, Sewing.room(catalog, i - 1)) or r.rolled != Sewing.room(catalog, i - 1).rolled,
				"room %d is stronger than the one before" % i)
	_check(parts_ok, "every room's marks are real parts, traits, finishes, tiers or buttons")
	var names := ["the button tin", "the pin cushion", "the thread maze", "the ribbon drawer", "the big scissors"]
	_check(names.all(func(n): return range(fixed).any(func(i): return Sewing.room(catalog, i).name == n)), "the rooms from the picks are there")
	_check(str(Sewing.room(catalog, fixed - 1).first.get("find", "")) == "plushie_machine", "the last room gives the plushie machine")
	var rolled := Sewing.room(catalog, fixed)
	_check(rolled.rolled and str(rolled.marks[0]).begins_with("buttons:"), "past the fixed rooms they're rolled, a button lock first (%s)" % [rolled.marks])
	_check(Sewing.room(catalog, fixed + 3) == Sewing.room(catalog, fixed + 3), "a rolled room is the same every time")
	var deep := Sewing.room(catalog, fixed + 40)
	_check(int(deep.marks[0].split(":")[1]) > int(rolled.marks[0].split(":")[1]) and deep.marks.size() > rolled.marks.size(),
		"deeper rolled rooms want more buttons and more marks (%s)" % [deep.marks])
	_check(Sewing.room(catalog, fixed).floor > Sewing.room(catalog, fixed - 1).floor, "rolled rooms keep getting stronger")

	# marks: parts, traits, exact finishes and tiers, buttons
	var pet := _plain_pet(catalog, "rare", "shiny", 9)
	pet.parts.body = "bunny"
	pet.traits.assign(["zoomy"])
	_check(Sewing.mark_matches("part:body:bunny", pet) and Sewing.mark_matches("trait:zoomy", pet) and Sewing.mark_matches("finish:shiny", pet)
		and Sewing.mark_matches("tier:rare", pet), "a shiny rare zoomy bunny matches its marks")
	_check(not Sewing.mark_matches("finish:holo", pet) and not Sewing.mark_matches("tier:epic", pet) and not Sewing.mark_matches("trait:lazy", pet)
		and not Sewing.mark_matches("part:accessory:halo", pet), "and nothing else (finishes and tiers are exact)")
	_check(not Sewing.mark_matches("buttons:1", pet), "no buttons, no button lock")
	pet.buttons = { "body": 2, "eyes": 1 }
	_check(Sewing.mark_matches("buttons:3", pet) and not Sewing.mark_matches("buttons:4", pet), "a button lock counts every button on the pet")
	var other := _plain_pet(catalog, "epic", "normal", 10)
	other.parts.body = "cat"
	other.traits.clear()
	var tin := Sewing.room(catalog, 0)
	_check(Sewing.marks_on(tin, [other]) == [false, false, false] and not Sewing.unlocked(tin, [other]), "the tin is locked for a plain epic cat")
	_check(Sewing.unlocked(tin, [other, pet]) and Sewing.ticks(tin, [other, pet]) == [false, true], "a matching front row pet fills every mark and gets a tick")
	_check(Sewing.shown(Sewing.fresh()) == 1 and Sewing.shown({ "cleared": 3 }) == 4, "only the rooms cleared and the next one show")
	_check(Sewing.clean({ "cleared": "x" }).cleared == 0 and Sewing.clean(null).cleared == 0 and Sewing.clean({ "cleared": -4 }).cleared == 0, "junk loads as a fresh sewing room")

	# keep lines: one from the tin, one more from rooms 4 and 7, capped
	_check(Sewing.keep_lines(catalog, 0) == 0 and Sewing.keep_lines(catalog, 1) == 1 and Sewing.keep_lines(catalog, 4) == 2
		and Sewing.keep_lines(catalog, 7) == 3 and Sewing.keep_lines(catalog, 50) == 3, "keep lines: 1 at the tin, then 2 and 3")
	var opts := Sewing.keep_options(catalog, { "part:accessory:halo": true, "part:body:blob": true })
	_check(opts[0] == "" and "trait:zoomy" in opts and "part:accessory:halo" in opts and not "part:accessory:horns" in opts and not "part:body:blob" in opts,
		"keep lines pick nothing, a trait, or a knack part the book has seen (%s)" % [opts])
	_check(Sewing.keep_word(catalog, "trait:zoomy") == "zoomy ones" and Sewing.keep_word(catalog, "part:accessory:halo") == "halos"
		and Sewing.keep_word(catalog, "") == "nothing", "keep lines read keep ‹zoomy ones›, keep ‹halos›")
	var kept := {}
	var dropped: Array = []
	for i in Sewing.keep_cap(catalog) + 3:
		dropped.append_array(Sewing.keep(catalog, kept, "trait:zoomy", str(i)))
	_check(kept["trait:zoomy"].size() == Sewing.keep_cap(catalog) and dropped == ["0", "1", "2"] and kept["trait:zoomy"].back() == str(Sewing.keep_cap(catalog) + 2),
		"a keep line keeps the newest %d, the oldest drop off" % Sewing.keep_cap(catalog))

	# a room run: one fight, a clear pays, a room too strong pays nothing, losses are capped
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var strong := Sewing.simulate(catalog, _army(20, 1.0e6, 280, 1.0e5), tin, {}, rng)
	_check(strong.why == "target" and strong.floors.size() == 1 and bool(strong.floors[0].cleared) and Dungeon.run_pay(strong) == Sewing.pay(catalog, tin, 300, 0),
		"a strong army clears the room and brings its wisps (%d)" % Dungeon.run_pay(strong))
	_check(int(strong.floors[0].f) == int(d.door_floor), "a room run stands at the door on floor %d" % int(d.door_floor))
	var weak := Sewing.simulate(catalog, _army(20, 1.0, 280, 1.0), tin, {}, rng)
	var lost := Dungeon.run_lost(weak)
	var lost_n: int = lost[0].size() + Herd.total(lost[1])
	_check(weak.why == "stuck" and Dungeon.run_pay(weak) == 0, "a weak army doesn't clear the room and brings nothing")
	_check(lost_n > 0 and lost_n <= ceili(300 * float(catalog.dungeon.losses.max_share)) + 1, "it loses some, never more than the cap (%d)" % lost_n)
	var run := { "floors": strong.floors, "room": 0, "door": 20, "seconds": 60.0 }
	_check(is_equal_approx(Dungeon.run_seconds(catalog, run), 60.0) and is_equal_approx(Dungeon.run_floor(catalog, run, 30.0), 20.0),
		"a room run takes its own time, at the door")


## The sewing room in the game (GameState): hidden until the key, locked rooms can't be entered, a run
## keeps the army busy and pays, the firsts (keep lines, the plushie machine) come once, keep lines
## keep matching pets from boxes as cards (capped, the stall and the rule never take them), rolled
## rooms after the last, and it all comes back from the save (a v26 save loads with none of it).
func _test_sewing_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the sewing room in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 12:
		var p := _plain_pet(catalog, "epic", "holo", 300 + i)  # holo: they stay cards
		p.uid = str(i + 1)
		p.parts.body = "cat"
		p.traits.clear()
		pets.append(p.to_dict())
	var old := { "version": 26, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:new_homes", "feature:sorting", "feature:parts"],
		"finds": ["deep_rope"],
		"collection": { "pets": pets, "active": "1", "next_id": 13, "seen": {}, "herd": { "common:normal": 400 }, "herd_ever": true },
		"dungeon": { "deep": 12, "bands": ["well", "cellar"] }, "room": 30 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.sewing.cleared == 0 and not gs.sewing_open() and not gs.finds.has("little_key"), "a v26 save loads with no sewing room (and no key before floor 20)")
	_check(gs.homes.rule.lines.is_empty() and gs.homes.kept.is_empty(), "and no keep lines")
	gs.grant({ "find:little_key": 1 })
	_check(gs.sewing_open(), "the tiny key opens the sewing room's door")
	gs.army_best()
	gs.set_army_herd("common", 100)
	_check(not gs.sew_can_go(0) and not gs.send_to_room(0), "the button tin's chalk lock keeps a front row of plain epic cats out")
	_check(not gs.sew_can_go(1), "the next room doesn't even show yet")
	var front: Array = gs.sew_front()
	front[0].parts.body = "bunny"
	front[1].finish = "shiny"
	front[2].rarity = "rare"
	_check(gs.sew_marks(0) == [true, true, true] and gs.sew_can_go(0), "a bunny, a shiny one and a rare one fill the tin's marks")
	var busy_uid: String = front[3].uid
	_check(gs.send_to_room(0) and gs.dungeon_running() and gs.dungeon.run.room == 0, "in we go: the army's in the button tin")
	_check(not gs.resting_cards().any(func(p): return p.uid == busy_uid) and not gs.send_army(), "its pets are busy, and nobody else goes down meanwhile")
	var herd0: int = gs.collection.herd_count("common:normal")
	gs.dungeon.run.at = 0.0
	gs.dungeon.run.floors = [{ "f": 20, "cleared": true, "lost_cards": [busy_uid], "lost_herd": { "common:normal": 3 }, "pay": 7 }]
	var wisps0: int = gs.wisps
	gs._dungeon_tick()
	_check(not gs.dungeon_running() and gs.wisps == wisps0 + 7 and gs.sewing.cleared == 1, "back from the tin: its wisps paid, one room cleared")
	_check(gs.collection.get_pet(busy_uid) == null and gs.collection.herd_count("common:normal") == herd0 - 3, "the ones that didn't come back are gone")
	_check(gs.dungeon.last.get("room", -1) == 0 and gs.feature_on("keep_lines") and gs.keep_line_count() == 1, "the last time card knows the room; keep lines open")
	_check(gs.sew_can_go(0) and Sewing.shown(gs.sewing) == 2, "the tin can be done again, and the pin cushion shows")
	# a replay gives no firsts; a room too strong isn't cleared
	gs.send_to_room(0)
	gs.dungeon.run.at = 0.0
	gs._dungeon_tick()
	_check(gs.sewing.cleared == 1, "doing the tin again doesn't count as a new room")
	# your pet leading the army waits at home while the sewing room is open on screen
	gs.automation.taught["army"] = true
	gs.automation.task = "army"
	gs.army_held = true
	gs._dungeon_tick()
	_check(not gs.dungeon_running() and gs.sew_can_go(0), "leading the army waits while the sewing room shows")
	gs.army_held = false
	gs._dungeon_tick()
	_check(gs.dungeon_running() and not gs.dungeon.run.has("room"), "and takes it down the well again once it's closed")
	gs.dungeon.run.at = 0.0
	gs.automation.task = ""
	gs._dungeon_tick()
	gs.debug_sewn(0)
	# keep lines: matching pets from boxes stay cards past keep_cards, capped, never sorted or taken
	gs.set_rule("on", true)
	gs.set_rule("below", "rare")
	gs.set_rule("keep", "holo")
	_check(gs.set_keep_line(0, "trait:zoomy") and not gs.set_keep_line(1, "trait:lazy"), "one keep line so far")
	gs.bag["starter"] = 400
	var pulled: Array = gs.open_boxes("starter", 400, "common")
	var zoomy := pulled.filter(func(p): return "zoomy" in p.traits and Herd.plain(catalog, p.finish))
	var cap := Sewing.keep_cap(catalog)
	var kept_now := zoomy.slice(maxi(0, zoomy.size() - cap))
	_check(zoomy.size() > cap, "enough zoomy commons to fill the line (%d)" % zoomy.size())
	_check(kept_now.all(func(p): return gs.collection.get_pet(p.uid) != null and gs.collection.keep_uids.has(p.uid)), "the newest zoomy ones stay cards")
	_check(gs.kept_count("trait:zoomy") == cap and not zoomy.slice(0, zoomy.size() - cap).any(func(p): return gs.collection.keep_uids.has(p.uid)),
		"only the newest %d: the oldest ones became plain again" % cap)
	_check(pulled.filter(func(p): return gs.collection.get_pet(p.uid) != null and not p.new_part and Herd.plain(catalog, p.finish) and not "zoomy" in p.traits).is_empty(),
		"the rule still sorts every other common away")
	var plan: Dictionary = gs.homes_pick("common")
	_check(not plan.cards.any(func(uid): return gs.collection.keep_uids.has(uid)), "the stall never takes a kept pet")
	gs.set_rule("on", false)
	var more: Array = gs.open_boxes("starter", 0, "common")
	gs.bag["starter"] = 40
	more = gs.open_boxes("starter", 40, "common")
	var zoomy2 := more.filter(func(p): return "zoomy" in p.traits and Herd.plain(catalog, p.finish))
	_check(zoomy2.all(func(p): return gs.collection.keep_uids.has(p.uid)), "keep lines keep with the rule off too")
	gs.set_keep_line(0, "")
	_check(gs.collection.keep_uids.is_empty() and gs.homes.kept.is_empty(), "changing a line lets its pets go")
	gs.set_keep_line(0, "trait:zoomy")
	# the last room: the plushie machine and a free button; then rolled rooms
	var active: Pet = gs.collection.active()
	var buttons0 := Plushie.total(active)
	gs.debug_sewn(Sewing.fixed_count(catalog))
	_check(gs.plushie_open() and Plushie.total(active) == buttons0 + 1, "the last room opens the plushie machine and sews a button onto your pet")
	_check(gs.keep_line_count() == 3, "three keep lines by then")
	var next: Dictionary = gs.sew_room(int(gs.sewing.cleared))
	_check(next.rolled and str(next.marks[0]).begins_with("buttons:"), "the room after the last is rolled, with a button lock")
	# a round trip: the sewing room, keep lines and a room run out
	gs.set_keep_line(2, "trait:lazy")
	gs.debug_sewn(0)
	gs.dungeon.run = { "at": Time.get_unix_time_from_system(), "floors": [{ "f": 20, "cleared": true, "lost_cards": [], "lost_herd": {}, "pay": 1 }],
		"why": "target", "turned": 0, "cards": [], "herd": {}, "sent": 1, "target": 5, "room": 3, "door": 20, "seconds": 60.0 }
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(gs2.sewing.cleared == gs.sewing.cleared and gs2.sewing_open(), "the sewing room comes back from the save")
	_check(gs2.keep_lines() == gs.keep_lines() and gs2.kept_count("trait:zoomy") == gs.kept_count("trait:zoomy")
		and gs2.collection.keep_uids.size() == gs.collection.keep_uids.size(), "keep lines and their pets come back (%s)" % [gs2.keep_lines()])
	_check(gs2.dungeon_running() and int(gs2.dungeon.run.room) == 3 and gs2.dungeon_left() > 50.0, "a room run out comes back too")
	gs2.free()
	# a save from before that had been past floor 20 has the key (the door shows)
	var older := old.duplicate(true)
	older.dungeon = { "deep": 21, "bands": ["well", "cellar", "below"] }
	SaveFile.write(path, older)
	var gs3: Node = load("res://scripts/game_state.gd").new()
	_check(gs3.finds.has("little_key") and gs3.sewing_open(), "a v26 save past floor 20 gets the key and its door")
	gs3.free()
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## The wisps perk tree on the well wall (Perks, data/perks.json): nails show by depth and needs,
## a chain (each needs the one above), prices and the cap, values, buying, the tips once the chain
## is done, boost parts and counts, a save made safe; the army's perks in the dungeon's maths.
func _test_perks(catalog: Catalog) -> void:
	var yes := func(_id): return true
	var no := func(_id): return false
	var st := {}
	_check(Perks.shown(catalog, st, 0, yes) == ["entrance"], "at the top only the bow shows (%s)" % [Perks.shown(catalog, st, 0, yes)])
	_check(Perks.shown(catalog, st, 12, yes) == ["entrance", "flag", "bell", "spool"], "down to floor 12: the nails to floor 10 (%s)" % [Perks.shown(catalog, st, 12, yes)])
	var deep_no := Perks.shown(catalog, st, 60, no)
	_check(not "thimble" in deep_no and not "ribbon" in deep_no and "star" in deep_no, "the plushie perks stay hidden until the machine opens")
	_check("thimble" in Perks.shown(catalog, st, 60, yes) and "ribbon" in Perks.shown(catalog, st, 60, yes), "and show once it has")
	# the chain
	_check(Perks.available(catalog, st, "entrance", 0, yes) and not Perks.available(catalog, st, "flag", 12, yes), "the bow first; the flag waits for it")
	_check(not Perks.available(catalog, st, "flag", 1, yes), "a hidden nail can't be bought")
	_check(Perks.buy(catalog, st, "entrance", 50, 12, yes) == -1 and Perks.level(st, "entrance") == 0, "not enough wisps: nothing")
	_check(Perks.buy(catalog, st, "flag", 99999, 12, yes) == -1, "the flag can't be bought before the bow")
	var cost := Perks.buy(catalog, st, "entrance", 99999, 12, yes)
	_check(cost == 100 and Perks.level(st, "entrance") == 1, "the bow's first level costs 100 wisps (%d)" % cost)
	_check(Perks.available(catalog, st, "flag", 12, yes) and not Perks.available(catalog, st, "spool", 12, yes), "now the flag can be bought, the spool still waits for the bell")
	_check(Dungeon.entrance(catalog, 0) == 300 and Dungeon.entrance(catalog, 1) == 600 and Dungeon.entrance(catalog, 4) == 4800, "the entrance fits 300, then 600 .. 4.8k")
	_check(Perks.price(catalog, st, "entrance") == 600, "each level costs more")
	st.entrance = 4
	_check(Perks.maxed(catalog, st, "entrance") and Perks.price(catalog, st, "entrance") == -1 and Perks.buy(catalog, st, "entrance", 1 << 40, 12, yes) == -1,
		"a maxed link can't be bought again")
	st.flag = 2
	_check(is_equal_approx(Perks.value(catalog, st, "flag"), 1.4), "the flag at level 2 is x1.40")
	var front := Perks.parts(catalog, st, "front")
	_check(front.size() == 1 and front[0].source == "perks" and is_equal_approx(float(front[0].x), 1.4), "its boost part: perks flag x1.40")
	_check(Perks.parts(catalog, st, "power").is_empty(), "nothing on power until the paper star")
	# counts
	_check(is_equal_approx(Perks.count(catalog, st, "front_row"), 20.0), "the front row is 20 without the pinwheel")
	st.pinwheel = 1
	_check(is_equal_approx(Perks.count(catalog, st, "front_row"), 22.0), "the pinwheel makes it 22")
	_check(is_equal_approx(Perks.count(catalog, st, "holds"), 0.0) and is_equal_approx(Perks.count(catalog, st, "nope"), 0.0), "counts with nothing bought, or no link: 0")
	# one source of truth: the base lives in data/dungeon.json, the links add on top
	var front_was = catalog.dungeon.front_row
	var start_was = catalog.dungeon.entrance.start
	catalog.dungeon.front_row = 30
	catalog.dungeon.entrance.start = 500
	_check(is_equal_approx(Perks.count(catalog, st, "front_row"), 32.0) and Dungeon.entrance(catalog, 0) == 500 and Dungeon.entrance(catalog, 1) == 800,
		"tuning dungeon.json front_row / entrance.start moves the counts (%d, %d)" % [int(Perks.count(catalog, st, "front_row")), Dungeon.entrance(catalog, 1)])
	_check(is_equal_approx(Perks.card_value(catalog, Perks.perk(catalog, "pinwheel"), 2), 34.0), "the pinwheel's card shows the whole front row")
	catalog.dungeon.front_row = front_was
	catalog.dungeon.entrance.start = start_was
	# the tips: once every link has a level
	_check(not Perks.chain_done(catalog, st) and not "coin" in Perks.shown(catalog, st, 60, yes), "the tips wait for the chain")
	_check(not Perks.available(catalog, st, "coin", 60, yes), "and can't be bought before")
	for p in Perks.chain(catalog):
		st[str(p.id)] = maxi(1, Perks.level(st, str(p.id)))
	_check(Perks.chain_done(catalog, st) and Perks.shown(catalog, st, 60, yes).slice(-2) == ["coin", "rattle"], "every link bought once: the lucky coin and the rattle hang at the bottom")
	var tip0 := Perks.price(catalog, st, "coin")
	_check(Perks.buy(catalog, st, "coin", tip0, 60, yes) == tip0 and Perks.price(catalog, st, "coin") == tip0 * 3, "a tip's next level costs x3 (%d)" % tip0)
	st.coin = 3
	_check(is_equal_approx(Perks.value(catalog, st, "coin"), 1.12) and is_equal_approx(float(Perks.parts(catalog, st, "coins")[0].x), 1.12), "the lucky coin gives +4% a level")
	st.rattle = 2
	var pets := Perks.parts(catalog, st, "pets")
	_check(pets.size() == 2 and is_equal_approx(Boosts.total(pets), 1.25 * 1.08), "the lunchbox and the rattle both speed pets/sec (%.3f)" % Boosts.total(pets))
	st.coin = 200
	_check(Perks.price(catalog, st, "coin") == int(float(catalog.perks.price_max)) and not Perks.maxed(catalog, st, "coin"), "a tip never costs more than the cap, and never ends")
	# a save made safe
	var clean := Perks.clean(catalog, { "entrance": 99, "flag": 0, "nope": 3, "coin": 12, "bell": "x" })
	_check(clean == { "entrance": 4, "coin": 12 }, "clean: links clamped to their max, tips any level, unknown and empty ones dropped (%s)" % [clean])
	for kind in ["front", "herd_power", "cellar", "stairs", "lanterns", "pets", "power", "coins"]:
		_check(Boosts.is_kind(catalog, kind), "boost kind %s is in data/boosts.json" % kind)
	for p in Perks.chain(catalog):
		_check(p.has("kind") != p.has("count"), "%s does a boost kind or a count, not both" % p.id)
		_check(p.price.size() == p.steps.size() - 1, "%s has a price for every level" % p.id)
		_check(not p.has("kind") or Boosts.is_kind(catalog, str(p.kind)), "%s's kind is a boost kind" % p.id)
		_check(not p.has("coins") and not p.has("coin_price"), "%s has no coin price" % p.id)
	var floors := Perks.chain(catalog).map(func(p): return int(p.floor))
	var sorted := floors.duplicate()
	sorted.sort()
	_check(floors == sorted and floors[0] == 0, "the chain goes down the well, the bow on top")

	# the army's perks in the dungeon's maths
	var a := _army(30, 10.0, 100, 5.0)
	var base_rope := Dungeon.army_power(catalog, a, "rope")
	var base_door := Dungeon.army_power(catalog, a, "door")
	a.front_x = 2.0
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "rope"), base_rope * 2.0), "front_x doubles the front row")
	a.front_x = 1.0
	a.behind_x = 2.0
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "rope"), base_rope) and is_equal_approx(Dungeon.army_power(catalog, a, "door"), base_rope + (base_door - base_rope) * 2.0),
		"behind_x only counts for the ones walking behind")
	a.behind_x = 1.0
	a.band_x = { "doors": 1.5, "stairs": 3.0, "room": 3.0 }
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "rope"), base_rope) and is_equal_approx(Dungeon.army_power(catalog, a, "knock"), base_door * 1.5)
		and is_equal_approx(Dungeon.army_power(catalog, a, "guard"), base_door * 3.0) and is_equal_approx(Dungeon.army_power(catalog, a, "room"), base_door * 3.0),
		"band_x: the cellar's floors, the stairs and the sewing rooms")
	a.band_x = {}
	a.front_n = 22
	_check(is_equal_approx(Dungeon.army_power(catalog, a, "rope"), base_rope * 22.0 / 20.0), "front_n 22: two more cards fight on the rope")
	_check(Dungeon.pay(catalog, 12, 300, 0, 2.0) == roundi(Dungeon.pay(catalog, 12, 300, 0) * 2.0) or absi(Dungeon.pay(catalog, 12, 300, 0, 2.0) - 2 * Dungeon.pay(catalog, 12, 300, 0)) <= 1,
		"pay_x (lanterns) multiplies a floor's pay")
	_check(Dungeon.pay(catalog, 12, 1000, 1) > Dungeon.pay(catalog, 12, 1000, 0), "a wider entrance pays for more pets")


func _test_perks_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the perks in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 30:
		var p := _plain_pet(catalog, "epic", "holo", 500 + i)  # holo: they stay cards
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	var auto := Automation.fresh()
	auto.taught["army"] = true
	var old := { "version": 27, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:lead_army", "tab:automation", "feature:parts"],
		"finds": ["deep_rope"], "automation": auto, "wisps": 100000,
		"collection": { "pets": pets, "active": "1", "next_id": 31, "seen": {}, "herd": { "common:normal": 3000 }, "herd_ever": true },
		"dungeon": { "deep": 12, "bands": ["well", "cellar"], "entrance": 2, "target": 5, "firsts": { "10": true } }, "room": 40 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.perk_level("entrance") == 2 and not gs.dungeon.has("entrance"), "v27 -> v28: the entrance's level moved into the perks")
	_check(int(gs.army().entrance) == 1200, "and still fits 1.2k (%d)" % int(gs.army().entrance))
	_check(gs.perks_shown() == ["entrance", "flag", "bell", "spool"], "the nails down to floor 12 show (%s)" % [gs.perks_shown()])
	# buying
	gs.army_best()
	gs.set_army_herd("common", 3000)
	var rules0: Dictionary = gs.army_rules()
	var power0 := Dungeon.army_power(catalog, rules0, "rope")
	var w0: int = gs.wisps
	_check(not gs.buy_perk("bell"), "the bell waits for the flag")
	_check(gs.buy_perk("flag") and gs.wisps == w0 - 150 and gs.perk_level("flag") == 1, "the flag: 150 wisps")
	_check(is_equal_approx(gs.boost("front"), 1.2) and gs.boost_parts("front")[0].source == "perks", "the front row's boost comes from the perks")
	_check(is_equal_approx(Dungeon.army_power(catalog, gs.army_rules(), "rope"), power0 * 1.2), "and makes the army stronger on the rope")
	gs.wisps = 10
	_check(not gs.buy_perk("flag") and gs.perk_level("flag") == 1, "not enough wisps: nothing")
	gs.wisps = 100000
	# the lanterns pay more
	gs.debug_perk("spool", 5)
	_check(is_equal_approx(gs.boost("lanterns"), 2.5), "the spool at its max: lanterns x2.5")
	gs.send_army()
	var paid := 0
	for fl in gs.dungeon.run.floors:
		paid += int(fl.pay)
	var plain := 0
	for fl in gs.dungeon.run.floors:
		if fl.cleared:
			plain += Dungeon.pay(catalog, int(fl.f), int(gs.dungeon.run.sent), 2)
	_check(paid > 0 and absi(paid - roundi(plain * 2.5)) <= gs.dungeon.run.floors.size(), "a run's floors pay x2.5 (%d vs %d)" % [paid, plain])
	gs.dungeon.run = {}
	gs._rest_changed()
	# the pinwheel: 22 cards in front
	gs.dungeon.deep = 40
	gs.debug_perk("pinwheel", 1)
	gs.army_best()
	_check(gs.front_row_size() == 22 and gs.army().cards.size() == 22 and gs.sew_front().size() == 22, "the pinwheel: army best takes 22 cards (%d)" % gs.army().cards.size())
	# the plushie perks: hidden until the machine opens, then holds and nudges
	for id in ["bell", "nightlight", "lunchbox", "scarf", "musicbox", "star"]:
		gs.debug_perk(id, 1)
	_check(not "thimble" in gs.perks_shown() and not "coin" in gs.perks_shown(), "no plushie perks, no tips, before the plushie machine")
	gs.grant({ "find:plushie_machine": 1 })
	_check("thimble" in gs.perks_shown() and "ribbon" in gs.perks_shown(), "the plushie machine opens: the thimble and the ribbon hang there")
	var holds0 := Plushie.holds_max(catalog, gs.plushie, gs.perk_holds())
	_check(gs.buy_perk("thimble") and Plushie.holds_max(catalog, gs.plushie, gs.perk_holds()) == holds0 + 1, "the thimble: one more hold")
	_check(gs.buy_perk("ribbon") and gs.perk_nudges() == 1, "the ribbon: a nudge more per pet")
	var st := Plushie.fresh()
	st.hopper = [_plain_pet(catalog, "common", "normal", 9).to_dict()]
	Plushie.next_pet(catalog, st, gs.collection.active(), gs.perk_nudges())
	_check(int(st.nudges) == 1, "a plain pet hopping in brings the ribbon's nudge (%d)" % int(st.nudges))
	_check(gs.perks_shown().slice(-2) == ["coin", "rattle"], "the chain is done: the tips hang at the bottom")
	_check(gs.buy_perk("rattle") and is_equal_approx(gs.boost("pets"), 1.25 * 1.04), "the lunchbox and the rattle: pets/sec x%.3f" % gs.boost("pets"))
	_check(is_equal_approx(gs.boost("power"), 1.25 * Boosts.total(Knacks.parts(catalog, gs.collection.active(), "power", gs.knack_gate))), "the paper star shares the army power boost with knacks")
	gs.save_game()
	var saved: Dictionary = SaveFile.read(path)
	_check(int(saved.version) == 29 and saved.perks.get("thimble", 0) == 1 and not saved.dungeon.has("entrance"), "it saves at v29 with the perks")
	gs.free()
	# the music box: your pet kept leading the army while the game was closed
	var away := saved.duplicate(true)
	away.dungeon.run = {}
	away.dungeon.target = 10
	away.dungeon.home_at = 90
	away.automation.task = "army"
	away.wisps = 0
	away.perks.musicbox = 0
	away.perks.erase("musicbox")
	away.saved_at = Time.get_unix_time_from_system() - 2 * 3600
	SaveFile.write(path, away)
	var gs0: Node = load("res://scripts/game_state.gd").new()
	var none: int = gs0.wisps
	gs0.free()
	_check(none == 0, "no music box: nothing happened while the game was closed (%d)" % none)
	# (the chain needs every link for the tips: the music box at level 2 is 2 hours)
	away.perks.musicbox = 2
	SaveFile.write(path, away)
	var gs2: Node = load("res://scripts/game_state.gd").new()
	var one_run := Dungeon.run_seconds(catalog, { "floors": range(10) })
	_check(gs2.wisps > 0 and int(gs2.idle_log.get("wisps", 0)) > 0, "the music box: wisps from runs while away (%d)" % gs2.wisps)
	_check(gs2.dungeon_news.get("got", 0) > 0, "and your pet has news about them")
	var herd_left: int = gs2.collection.herd_count("common:normal")
	_check(herd_left < 3000, "real runs: some pets didn't come back (%d left)" % herd_left)
	_check(gs2.wisps > 10 * Dungeon.pay(catalog, 1, 1, 2), "several runs' worth (%d, a run takes %d s)" % [gs2.wisps, int(one_run)])
	# the cap is data (perks.json away_runs_max) and a save with no saved_at plays nothing
	var cap_was = gs2.catalog.perks.get("away_runs_max", 500)
	gs2.dungeon.run = {}
	gs2.wisps = 0
	gs2.catalog.perks.away_runs_max = 1
	gs2._army_while_away(Time.get_unix_time_from_system() - 3600, Time.get_unix_time_from_system())
	_check(gs2.dungeon_running() and gs2.wisps == 0, "away_runs_max 1: one run sent, none worked out (%d)" % gs2.wisps)
	gs2.catalog.perks.away_runs_max = cap_was
	gs2.dungeon.run = {}
	_check(gs2._army_while_away(0.0, Time.get_unix_time_from_system()) == 0 and not gs2.dungeon_running(), "no saved_at: no runs dated 1970")
	gs2.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Held landings (Dungeon hold_*, data/dungeon.json "hold"): what each landing needs and what its crowd
## holds, the spots down to the deepest floor, where the orders can start, a run from a held landing
## (the floors above it: no fights, no losses, no lanterns, no time), a saved state made safe.
func _test_held(catalog: Catalog) -> void:
	var needs := [10, 20, 30, 40, 50].map(func(f): return Dungeon.hold_need(catalog, f))
	_check(needs == [500, 2000, 8000, 24000, 72000], "landings need 500 / 2k / 8k, then x3 (%s)" % [needs])
	_check(Dungeon.hold_need(catalog, 15) == 0 and Dungeon.hold_need(catalog, 0) == 0, "only every 10th landing can be held")
	var what := [10, 20, 30, 60].map(func(f): return Dungeon.hold_what(catalog, f))
	_check(what == ["the rope", "the door", "the stairs", "the stairs"], "they hold the rope, the door, the stairs (%s)" % [what])
	var st := Dungeon.fresh(catalog)
	_check(st.held.is_empty() and int(st.start) == 0, "a new dungeon holds nothing and starts at the top")
	st.deep = 9
	_check(Dungeon.hold_spots(catalog, st).is_empty(), "no spots before floor 10 is cleared")
	st.deep = 32
	_check(Dungeon.hold_spots(catalog, st) == [10, 20, 30], "spots down to the deepest floor (%s)" % [Dungeon.hold_spots(catalog, st)])
	st.held = { "10": { "common:normal": 500 }, "20": { "common:normal": 1999 }, "30": { "common:normal": 7000, "uncommon:normal": 1000 } }
	_check(Dungeon.starts(catalog, st) == [0, 10, 30] and Dungeon.is_held(catalog, st, 30) and not Dungeon.is_held(catalog, st, 20),
		"the orders can start at the top or a fully held landing (%s)" % [Dungeon.starts(catalog, st)])
	# a run from landing 20 to floor 25
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var army := _army(20, 1.0e4, 280, 1.0e3)
	var run := Dungeon.simulate(catalog, army, { "target": 25, "start": 20, "home_at": 90 }, rng)
	var fs: Array = run.floors.map(func(fl): return int(fl.f))
	_check(fs == [21, 22, 23, 24, 25], "a run from landing 20 walks floors 21 to 25 only (%s)" % [fs])
	var pay := 0
	for f in range(21, 26):
		pay += Dungeon.pay(catalog, f, 300, 0)
	_check(Dungeon.run_pay(run) == pay, "and pays only for those (%d vs %d)" % [Dungeon.run_pay(run), pay])
	run.start = 20
	_check(is_equal_approx(Dungeon.run_seconds(catalog, run), 5.0 * float(catalog.dungeon.seconds_per_floor)), "it takes 5 floors of time")
	_check(is_equal_approx(Dungeon.run_floor(catalog, run, 0.0), 20.0) and is_equal_approx(Dungeon.run_floor(catalog, run, 1.0e6), 25.0),
		"the army pops out at landing 20 and walks down to 25")
	var weak := Dungeon.simulate(catalog, _army(20, 1.0, 0, 0.0), { "target": 25, "start": 20, "home_at": 90 }, rng)
	_check(weak.why == "stuck" and weak.floors.size() == 1 and int(weak.floors[0].f) == 21, "a weak army from landing 20 gets stuck on 21, not on 1")
	var odd := Dungeon.simulate(catalog, army, { "target": 5, "start": 20, "home_at": 90 }, rng)
	_check(not odd.floors.is_empty() and int(odd.floors.back().f) == 5, "a start below the target is ignored (never an empty run)")
	# a fully held stairs landing has no guard, in the fight too
	_check(is_equal_approx(Dungeon.strength(catalog, 30, true), Dungeon.strength(catalog, 30) / 2.0), "a held guard landing loses its guard's x2")
	_check(Dungeon.held_landings(catalog, st) == [10, 30] and Dungeon.kind_at(catalog, 30, [10, 30]) == "stairs"
		and Dungeon.kind_at(catalog, 30, []) == "guard", "held landings: 10 and 30, and 30 fights as plain stairs")
	var edge := _army(20, 1.0, 0, 0.0)
	var lo := 0.0
	var hi := 1.0e7
	for i in 60:  # an army just strong enough for floor 30 without its guard, not with it
		var mid := (lo + hi) / 2.0
		edge = _army(20, mid, 0, 0.0)
		var r := Dungeon.simulate(catalog, edge, { "target": 30, "start": 29, "home_at": 100, "held": [30] }, rng)
		if r.why == "stuck":
			lo = mid
		else:
			hi = mid
	edge = _army(20, hi * 1.2, 0, 0.0)
	var with_held := Dungeon.simulate(catalog, edge, { "target": 30, "start": 29, "home_at": 100, "held": [30] }, rng)
	var no_held := Dungeon.simulate(catalog, edge, { "target": 30, "start": 29, "home_at": 100 }, rng)
	_check(with_held.why != "stuck" and no_held.why == "stuck", "an army walking past held landing 30 fights no guard (%s / %s)" % [with_held.why, no_held.why])
	# a saved state made safe
	var clean := Dungeon.clean(catalog, { "deep": 25, "target": 3, "start": 20,
		"held": { "10": { "common:normal": 900 }, "20": { "common:normal": 2000 }, "15": { "common:normal": 5 }, "x": 3,
			"30": { "common:normal": 8000 }, "40": "no" } })
	_check(clean.held.keys() == ["10", "20", "30"] and Dungeon.held_n(clean, 10) == 500, "bad landings go, too many holders are cut to the need (%s)" % [clean.held])
	_check(int(clean.start) == 20 and int(clean.target) == 21, "a held start stays and the target is below it")
	var past := Dungeon.clean(catalog, { "deep": 25, "start": 30, "held": { "30": { "common:normal": 8000 } } })
	_check(int(past.start) == 0, "a start past the deepest floor goes back to the top")
	var half := Dungeon.clean(catalog, { "deep": 25, "start": 20, "held": { "20": { "common:normal": 10 } } })
	_check(int(half.start) == 0, "a start at a landing that isn't fully held goes back to the top")


func _test_held_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped held landings in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 30:
		var p := _plain_pet(catalog, "epic", "holo", 700 + i)  # holo: they stay cards, never holders
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	for i in 4:
		var p := _plain_pet(catalog, "common", "normal", 800 + i)
		p.uid = str(31 + i)
		p.fav = i == 0  # a favourite never goes
		pets.append(p.to_dict())
	var old := { "version": 28, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:parts", "feature:errands", "tab:errands"],
		"finds": ["deep_rope"], "wisps": 0,
		"collection": { "pets": pets, "active": "1", "next_id": 35, "seen": {}, "herd": { "common:normal": 12000, "uncommon:normal": 3000 }, "herd_ever": true },
		"dungeon": { "deep": 32, "bands": ["well", "cellar", "below"], "target": 5, "firsts": { "10": true, "20": true } }, "room": 60 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.dungeon.held.is_empty() and int(gs.dungeon.start) == 0, "v28 -> v29: nothing held, the orders start at the top")
	_check(gs.hold_spots() == [10, 20, 30], "landings 10, 20 and 30 can be held (%s)" % [gs.hold_spots()])
	# the army's pets never go
	gs.army_best()
	gs.set_army_herd("common", 280)
	var army_n := int(gs.army_herd_keys().get("common:normal", 0))
	var stars: int = gs.collection.fallen_n
	var commons: int = gs.collection.herd_count("common:normal")
	_check(gs.hold_can_go(10, "common") == 500 and gs.hold_can_go(10, "epic") == 0, "at most what the landing needs, never holo cards")
	gs.put_on_job("coin_hunt", 100)
	var went: int = gs.send_holders(10, "common", 200)
	_check(went == 200 and Dungeon.held_n(gs.dungeon, 10) == 200 and gs.collection.herd_count("common:normal") == commons - 200,
		"200 commons hold landing 10 (%d)" % went)
	_check(gs.collection.fallen_n == stars, "holders stay on for good: no night-sky star")
	_check(int(gs.army_herd_keys().get("common:normal", 0)) == army_n, "the army keeps its pets")
	went = gs.send_holders(10, "common", 100000)
	_check(went == 300 and Dungeon.is_held(catalog, gs.dungeon, 10) and gs.send_holders(10, "common", 5) == 0, "it stops at the landing's need (%d)" % went)
	_check(gs.collection.get_pet("31") != null and gs.collection.get_pet("1") != null, "favourites and your pet never go")
	_check(Dungeon.starts(catalog, gs.dungeon) == [0, 10], "landing 10 is a start now")
	gs.dungeon.held["10"] = { "common:normal": 600 }  # (never happens: a crowd over its need)
	var before: int = gs.collection.herd_count("common:normal")
	_check(gs.send_holders(10, "common", 5) == 0 and gs.collection.herd_count("common:normal") == before and gs.hold_room(10) == 0,
		"a landing over its need takes nobody (not the whole shelf)")
	gs.dungeon.held["10"] = { "common:normal": 500 }
	_check(not gs.set_start(20) and int(gs.dungeon.start) == 0, "set_start: not a landing that isn't held")
	# the start stepper
	gs.set_order("start", 1)
	_check(int(gs.dungeon.start) == 10 and int(gs.dungeon.target) == 11, "start from landing 10: the target moves to 11 (%d)" % int(gs.dungeon.target))
	gs.set_order("start", 1)
	_check(int(gs.dungeon.start) == 10, "no further: 20 isn't held")
	gs.set_order("target", -5)
	_check(int(gs.dungeon.target) == 11, "the target never goes above the floor under the start")
	gs.send_holders(20, "common", 2000)
	gs.send_holders(30, "common", 8000)
	gs.send_holders(30, "uncommon", 8000)
	_check(Dungeon.is_held(catalog, gs.dungeon, 20) and Dungeon.is_held(catalog, gs.dungeon, 30), "20 and 30 held with commons and uncommons (%d, %d)" % [Dungeon.held_n(gs.dungeon, 20), Dungeon.held_n(gs.dungeon, 30)])
	gs.set_order("start", 5)
	_check(int(gs.dungeon.start) == 30 and int(gs.dungeon.target) == 31, "the stepper goes on to landing 30")
	# a run from landing 30
	_check(gs.send_army() and int(gs.dungeon.run.start) == 30, "the army goes from landing 30")
	_check(not gs.set_start(10) and int(gs.dungeon.start) == 30, "set_start: not while the army is out")
	_check(gs.dungeon.run.floors.all(func(fl): return int(fl.f) > 30), "no floors above it in the run")
	_check(gs.dungeon_floor_now() >= 30.0, "it's down at landing 30 straight away (%.1f)" % gs.dungeon_floor_now())
	gs.dungeon.run.at = 0.0
	gs._dungeon_tick()
	_check(int(gs.dungeon.last.floor) >= 30, "last time says how far they got (%d)" % int(gs.dungeon.last.floor))
	gs.save_game()
	var saved: Dictionary = SaveFile.read(path)
	_check(int(saved.version) == 29 and saved.dungeon.held.has("30") and int(saved.dungeon.start) == 30, "it saves at v29 with the held landings")
	gs.free()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(Dungeon.starts(catalog, gs2.dungeon) == [0, 10, 20, 30] and int(gs2.dungeon.start) == 30, "and they come back from the save")
	gs2.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
