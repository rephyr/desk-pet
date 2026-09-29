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
	_test_automation(catalog)
	_test_unlocks(catalog)
	_test_gear(catalog)
	_test_herd(catalog)
	_test_herd_game(catalog)
	_test_new_homes(catalog)
	_test_new_homes_game(catalog)
	_test_prices(catalog)
	_test_room(catalog)
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
			var ok: bool = (bits[0] == "tab" and bits[1] in tabs) or (bits[0] == "feature" and bits[1] in ["errands", "packs", "shopping", "parties", "parties_5", "parties_10", "toys", "parts", "auto_adventures", "new_homes", "sorting"]) or (bits[0] == "page" and bits[1] in page_ids) \
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
		_check(t.bonus in Toys.KINDS or t.bonus == "all", "toy %s has a known bonus" % t.id)
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
	_check(is_equal_approx(Toys.multiplier(state, catalog, "coins", now), 1.0), "a toy on the shelf does nothing")
	_check(Toys.play(state, catalog, "acorn:normal", "quick", now), "your pet can play with a toy")
	_check(Toys.multiplier(state, catalog, "coins", now + 1.0) > 1.0, "a toy being played with boosts")
	_check(not Toys.play(state, catalog, "acorn:ghost", "quick", now), "one play slot to start")
	_check(Toys.finish_plays(state, now + 60.0).is_empty(), "a play isn't over early")
	var ended := Toys.finish_plays(state, now + 3600.0)
	_check(ended == ["acorn:normal"] and float(state.owned["acorn:normal"].wear) > 0.0, "a finished play wears the toy")
	_check(is_equal_approx(Toys.multiplier(state, catalog, "coins", now + 3601.0), 1.0), "after playing the boost stops")
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
func _gear_losses(place_id: String, pets: Array[Pet], gear: Dictionary, catalog: Catalog) -> int:
	var place := catalog.location(place_id)
	var lost := 0
	for t in 200:
		var run := AdventureRunner.start(place_id, pets, 0.0, t, catalog, {}, {}, gear)
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
	# the kitchen and scouting with crews from the herd
	gs.unlocks["job:kitchen"] = true
	gs.unlocks["job:scouting"] = true
	var coin_before: float = gs.job_rate("coin_hunt")
	var k0: String = gs.resting_herd().keys()[0]
	gs.put_on_job("kitchen", 4, c.stand_in_uids(k0, 4))
	_check(gs.job_size("kitchen") == 4 and gs.job_crew("kitchen").is_empty(), "a kitchen crew all from the herd (%d)" % gs.job_size("kitchen"))
	_check(gs.kitchen_bonus() > 0.0 and gs.job_rate("coin_hunt") > coin_before,
		"herd cooks make the coin hunt faster (%.3f, %.4f -> %.4f)" % [gs.kitchen_bonus(), coin_before, gs.job_rate("coin_hunt")])
	var k1: String = gs.resting_herd().keys()[0]
	gs.put_on_job("scouting", 3, c.stand_in_uids(k1, 3))
	_check(gs.job_size("scouting") == 3 and gs.job_rate("scouting") > 0.0, "a scouting crew all from the herd works")
	gs.set_scout_notes(gs.scout_hold())
	_check(gs.job_fill_now("scouting") == 1.0, "herd scouts with every note waiting: the meter waits full")
	gs.set_scout_notes(0)
	var resting_now: int = gs.resting_count()
	var coin_size: int = gs.job_size("coin_hunt")
	var scrap_size: int = gs.job_size("scrapyard")
	gs.share_out()
	_check(gs.job_size("kitchen") == 4 and gs.job_size("scouting") == 3 and gs.resting_count() == 0,
		"sharing out skips the kitchen and scouting (%d resting went elsewhere)" % resting_now)
	gs.set_job_join("kitchen", true)
	_check(not gs.job_joins("kitchen"), "new pets never join the kitchen by themselves")
	gs.take_off_job("coin_hunt", gs.job_size("coin_hunt") - coin_size)
	gs.take_off_job("scrapyard", gs.job_size("scrapyard") - scrap_size)
	gs.take_off_job("kitchen", -1)
	gs.take_off_job("scouting", -1)
	_check(gs.resting_count() == resting_now + 7, "everyone comes home again (%d)" % gs.resting_count())
	gs.unlocks.erase("job:kitchen")
	gs.unlocks.erase("job:scouting")
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
	# the room's coin steps are priced in capsules too
	for st: Dictionary in catalog.herd.get("room", {}).get("steps", []):
		_check((float(st.get("capsules", 0)) > 0.0) != st.has("wisps") and not st.has("coins"), "room step %s costs capsules or wisps, one of them" % st.id)
	_check(Herd.room_cost(catalog, 2, fixed) == roundi(8.0 * Herd.room_cost(catalog, 2, fresh)), "a coin room step costs 8x on a repaired machine (%d)" % Herd.room_cost(catalog, 2, fixed))
	_check(Herd.room_cost(catalog, 0, fresh) == 10 * game_state.box_cost(starter, fresh), "the first room step costs 10 starter boxes")
	for level in [0, 10, 100, 1000]:
		_check(Herd.room_cost(catalog, level, top) > 0, "a room step after %d never costs less than nothing" % level)
	# the save chain: an old save's coin reserve turns into capsules (v26), a save that already
	# keeps capsules keeps them
	if not DevProfile.active():
		return
	var path := DevProfile.path("save.json")
	var machine := { "bought": { "tape": 1, "oil": 1, "flap": 1 } }
	for case in [[22, { "coin_reserve": 400 }, 50], [24, { "coin_reserve": 400 }, 50], [25, { "reserve_capsules": 30 }, 30], [22, {}, int(reserve.capsules)]]:
		for f in [path, path + ".bak", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		var data := { "version": case[0], "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "machine": machine }
		data.merge(case[1])
		SaveFile.write(path, data)
		var gs: Node = game_state.new()
		_check(gs.reserve_capsules == case[2], "a v%d save with %s keeps a reserve of %d capsules (%d)" % [case[0], case[1], case[2], gs.reserve_capsules])
		gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Room steps (the house card): named steps that each hold more, coin steps priced in capsules and
## squeeze-in steps in wisps (one currency each, hidden until wisps show up), endless steps after
## the list, the shelves | jobs split, wisps in the save, and old room levels keeping their room.
func _test_room(catalog: Catalog) -> void:
	var r: Dictionary = catalog.herd.get("room", {})
	var steps: Array = r.get("steps", [])
	_check(steps.size() >= 2 and Herd.room_cap(catalog, 0) == int(r.start), "the room starts at %d with %d steps" % [int(r.start), steps.size()])
	var grows := true
	var coin_steps := 0
	var wisps_after := true
	for i in steps.size() + 6:
		grows = grows and Herd.room_cap(catalog, i + 1) > Herd.room_cap(catalog, i)
		var cur := Herd.room_currency(catalog, i)
		if cur == "coins":
			coin_steps += 1
			wisps_after = wisps_after and coin_steps == i + 1  # every coin step comes before the wisp ones
		if i > 0 and cur == Herd.room_currency(catalog, i - 1):
			var v := 8.0 if cur == "coins" else 1.0
			grows = grows and Herd.room_cost(catalog, i, v) > Herd.room_cost(catalog, i - 1, v)
	_check(grows, "every room step holds more and costs more than the one before")
	_check(coin_steps >= 1 and coin_steps < steps.size() and wisps_after, "coin steps first, then squeeze-in steps (%d coin steps)" % coin_steps)
	var ui: Dictionary = catalog.voice.get("ui", {})
	var said := true
	for i in steps.size() + 2:  # every listed step and the endless ones: a name, and your pet's line for it
		var s := Herd.room_step(catalog, i)
		var id := str(s.get("id", ""))
		var ok: bool = str(s.get("name", "")) != "" and id != "" and not ui.get("room_" + id, []).is_empty()
		if not ok:
			print("  room step %d (%s) has no name or no room_%s line" % [i, id, id])
		said = said and ok
	_check(said, "every room step has a name and a line")
	_check(Herd.room_cost(catalog, coin_steps, 8.0) == Herd.room_cost(catalog, coin_steps, 1000.0) and Herd.room_currency(catalog, coin_steps) == "wisps",
		"a squeeze-in step costs wisps, whatever a capsule is worth (%d)" % Herd.room_cost(catalog, coin_steps))
	for level in [30, 100]:
		var cap := Herd.room_cap(catalog, level)
		_check(cap > Herd.room_cap(catalog, level - 1) or cap >= int(Herd.ROOM_TOP), "endless step %d still holds more (%d)" % [level, cap])
		_check(cap > 0 and Herd.room_cost(catalog, level) > 0 and Herd.room_currency(catalog, level) == "wisps", "endless step %d holds and costs more than nothing" % level)
	_check(str(Herd.room_step(catalog, steps.size()).name) != "" and Herd.room_cap(catalog, steps.size() + 1) == 2 * Herd.room_cap(catalog, steps.size()),
		"after the list the room keeps doubling")
	_check(Herd.room_cap(catalog, Herd.room_level_for(catalog, 5000)) >= 5000 and Herd.room_cap(catalog, Herd.room_level_for(catalog, 5000) - 1) < 5000,
		"the fewest steps that hold 5000 pets")
	if not DevProfile.active():
		print("  skipped the room in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	var game_state: GDScript = load("res://scripts/game_state.gd")
	var clear := func():
		for f in [path, path + ".bak", path + ".tmp"]:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	# old saves: a v26 room level becomes steps that hold at least as much
	for level in [0, 1, 2, 5, 10]:
		clear.call()
		SaveFile.write(path, { "version": 26, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "room": level })
		var gs: Node = game_state.new()
		var old_cap := maxi(50, roundi(500.0 * pow(1.5, level) / 50.0) * 50)
		var fewest: bool = gs.room == 0 or Herd.room_cap(catalog, gs.room - 1) < old_cap
		_check(gs.room_cap() >= old_cap and fewest,
			"a v26 room at level %d keeps its room (%d, was %d)" % [level, gs.room_cap(), old_cap])
		gs.free()
	# a game: coin steps take coins, squeeze-in steps wait for wisps and take only wisps
	clear.call()
	SaveFile.write(path, { "version": 27, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "coins": 1000000000,
		"unlocks": ["feature:errands", "tab:errands"], "room": 0,
		"collection": { "pets": [_plain_pet(catalog, "common", "normal", 7).to_dict()], "herd": { "common:normal": 399 }, "active": "1", "next_id": 2, "seen": {} },
		"jobs": { "coin_hunt": { "crew": [], "herd": { "common:normal": 120 }, "fill": 0.0 } } })
	var gs: Node = game_state.new()
	var split: Array = gs.room_split()
	_check(split[0] + split[1] == gs.collection.plain_count() and split[1] == gs.job_size("coin_hunt") and split[1] > 0,
		"the room counts pets on jobs too: %d on the shelves, %d on jobs, %d in all" % [split[0], split[1], gs.collection.plain_count()])
	var coins_before: int = gs.coins
	var price: int = gs.room_price()
	_check(gs.buy_room() and gs.room == 1 and gs.coins == coins_before - price and gs.room_cap() == Herd.room_cap(catalog, 1), "a coin step takes its coins")
	gs.room = coin_steps
	_check(gs.room_next().is_empty() and not gs.buy_room() and gs.room == coin_steps, "the squeeze-in steps stay hidden until wisps show up")
	var short := Herd.room_cost(catalog, coin_steps) - 1
	gs.grant({ "wisps": short })
	gs.wisps_seen = true  # in case the first squeeze-in step costs a single wisp
	_check(gs.wisps_shown() and str(gs.room_next().get("name", "")) == str(Herd.room_step(catalog, coin_steps).name), "then the next squeeze-in step shows")
	var coins_now: int = gs.coins
	_check(not gs.buy_room() and gs.wisps == short, "short on wisps: nothing built")
	gs.grant_wisps(short + 1)
	var wprice: int = gs.room_price()
	_check(gs.buy_room() and gs.room == coin_steps + 1 and gs.wisps == 2 * short + 1 - wprice and gs.coins == coins_now, "a squeeze-in step takes only wisps (%d), no coins" % wprice)
	gs.save_game()
	var gs2: Node = game_state.new()
	_check(gs2.wisps == gs.wisps and gs2.wisps_seen and gs2.room == coin_steps + 1, "wisps and the room load back")
	gs2.free()
	gs.free()
	clear.call()
