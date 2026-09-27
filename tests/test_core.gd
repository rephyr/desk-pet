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
			var found_here := find == "" or _found_in(catalog, reached, find)
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
	var per_min := float(Rewards.total(once.loot, "coins")) / 60.0
	_check(per_min > 3.0 and per_min < 12.0, "3 pets on the coin hunt earn a gentle trickle (%.1f coins a minute)" % per_min)
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
	var tabs := ["home", "boxes", "collection", "adventures", "errands", "inventory", "settings"]
	var page_ids := catalog.pages.map(func(p): return p.id)
	for entry in catalog.unlock_list:
		_check(entry.show in ["locked", "hidden"], "unlock %s is shown locked or hidden" % entry.id)
		for o in entry.opens:
			var bits := str(o).split(":")
			var ok: bool = (bits[0] == "tab" and bits[1] in tabs) or (bits[0] == "feature" and bits[1] in ["errands", "packs", "shopping", "parties", "parties_5", "parties_10"]) or (bits[0] == "page" and bits[1] in page_ids)
			_check(ok, "unlock %s opens something real (%s)" % [entry.id, o])
		if entry.earn.has("find"):
			_check(catalog.finds.has(entry.earn.find), "unlock %s waits for a real find" % entry.id)
		_check(not "{" in str(entry.get("announce", "")), "unlock %s announcement has no placeholders" % entry.id)
	for find in catalog.finds:
		_check(catalog.events.values().any(func(e): return e.get("find", "") == find), "some event gives %s" % find)
	var meadow := catalog.location("meadow")
	var seen := false
	for t in 200:
		if "meadow_basket" in AdventureRunner.pick_events(meadow, t, { "basket": true }, catalog):
			seen = true
	_check(not seen, "a find's event stops turning up once it's found")
	var automation: Array = catalog.unlock_list.filter(func(e): return "feature:packs" in e.opens or "feature:errands" in e.opens)
	_check(automation.all(func(e): return e.show == "hidden"), "automation stays hidden until found")
	var packs: Array = catalog.unlock_list.filter(func(e): return "feature:packs" in e.opens)
	_check(packs.all(func(e): return int(e.earn.get("packs_opened", 0)) >= 100), "your pet only opens packs after you've opened plenty yourself")


## Allowed difference between expected and rolled odds (about 4 standard deviations).
func _tolerance(p: float) -> float:
	return 4.0 * sqrt(p * (1.0 - p) / ROLLS) + 0.0005


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL: " + what)
