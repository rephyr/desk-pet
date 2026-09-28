extends SceneTree
## Headless checks for the pet core. Run with:
##   godot --headless -s tests/test_core.gd

const ROLLS := 100000

var _failures := 0
var _checks := 0  # printed at the end, so a test that stopped early on a script error shows


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
	_test_automation(catalog)
	_test_unlocks(catalog)
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


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + what)
