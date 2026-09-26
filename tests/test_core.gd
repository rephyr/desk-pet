extends SceneTree
## Headless checks for the pet core. Run with:
##   godot --headless -s tests/test_core.gd

const ROLLS := 100000

var _failures := 0


func _init() -> void:
	var catalog := Catalog.new()
	_test_data_is_consistent(catalog)
	_test_odds_match_box(catalog, "starter")
	_test_odds_match_box(catalog, "lucky")
	_test_save_round_trip(catalog)
	_test_old_pets_still_load(catalog)
	_test_dungeon(catalog)
	print("\n%s" % ("ALL PASSED" if _failures == 0 else "%d FAILED" % _failures))
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
	for d in catalog.dungeons:
		_check(not catalog.box(d.box).is_empty(), "dungeon %s drops a real box" % d.id)
		_check(d.chooser in ["player", "timeout", "policy"], "dungeon %s has a known chooser" % d.id)
		for e in d.events:
			_check(catalog.events.has(e), "dungeon %s event %s exists" % [d.id, e])
	for e in catalog.events.values():
		for o in e.options:
			_check(o.has("success") and o.success.has("text"), "event %s option %s has a success text" % [e.id, o.label])
			_check(str(o.get("stat", "")) in ["", "power", "luck", "speed"], "event %s option %s tests a real stat" % [e.id, o.label])


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


## The event dungeons: every pet comes home or doesn't at any party size, the player chooser
## waits for answers, catching up later gives the same result as playing along, lost pets leave
## the collection but stay in the book, and runs survive a save.
func _test_dungeon(catalog: Catalog) -> void:
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
		var run := DungeonRunner.start("below", pets, 0.0, 5, catalog)
		DungeonRunner.resolve(run, PolicyChooser.new(), 1.0e9, catalog)
		_check(run.status == RunState.Status.DONE, "a swarm run finishes by itself (%d pets)" % size)
		_check(run.party.size() + run.party.lost.size() == size, "every pet comes home or doesn't (%d pets)" % size)
		_check(DungeonRunner.summary(run).begins_with("Expedition complete: %d of %d returned." % [run.party.size(), size]),
			"the summary counts who came back")
	var shallow := DungeonRunner.estimate_return("meadow", batch.slice(0, 200), catalog)
	var deep := DungeonRunner.estimate_return("below", batch.slice(0, 200), catalog)
	_check(shallow > deep, "deeper dungeons bring fewer home (%.2f vs %.2f)" % [shallow, deep])

	# catching up in one go matches checking in all the time
	var herd: Array[Pet] = batch.slice(0, 300)
	var at_once := DungeonRunner.start("well", herd, 0.0, 42, catalog)
	DungeonRunner.resolve(at_once, PolicyChooser.new(), 1.0e9, catalog)
	var bit_by_bit := DungeonRunner.start("well", herd, 0.0, 42, catalog)
	for t in range(0, 100000, 7):
		DungeonRunner.resolve(bit_by_bit, PolicyChooser.new(), float(t), catalog)
	_check(bit_by_bit.party.lost == at_once.party.lost and bit_by_bit.coins == at_once.coins,
		"resolving later gives the same run")

	# the player picks: the run waits at each event until answered
	var solo: Array[Pet] = [batch[0]]
	var walk := DungeonRunner.start("garden", solo, 0.0, 7, catalog)
	DungeonRunner.resolve(walk, PlayerChooser.new(), 1.0e9, catalog)
	_check(walk.status == RunState.Status.WAITING and walk.history.is_empty(), "the garden waits for the player")
	var answers := 0
	var now := 1.0e9
	while walk.status != RunState.Status.DONE and answers < 10:
		if walk.status == RunState.Status.WAITING:
			walk.answer = DungeonRunner.allowed_options(walk.current_event(catalog), walk.party)[0]
			answers += 1
		DungeonRunner.resolve(walk, PlayerChooser.new(), now, catalog)
		now += 1.0e6  # time passes between events
	_check(walk.status == RunState.Status.DONE and walk.history.size() == answers, "answering every event finishes the walk")

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

	# a run half way through survives a save
	var saved := RunState.from_dict(JSON.parse_string(JSON.stringify(walk.to_dict())), catalog)
	_check(saved != null and saved.party.lost == walk.party.lost and saved.history.size() == walk.history.size()
		and saved.status == walk.status and saved.coins == walk.coins, "runs survive a save")


## Allowed difference between expected and rolled odds (about 4 standard deviations).
func _tolerance(p: float) -> float:
	return 4.0 * sqrt(p * (1.0 - p) / ROLLS) + 0.0005


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: " + what)
