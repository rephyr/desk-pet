extends SceneTree
## Headless checks for the pet core. Run with a profile of your own (the GameState tests write
## their saves into it; a worktree lane adds its name so lanes never share one):
##   godot --headless -s tests/test_core.gd -- --profile=core-test-<lane>
## Without a profile it uses "test_core" anyway: the tests write saves and must never touch the real one.
## DESK_PETS_SLOW=3 stretches the time limits when several copies run at once.

const ROLLS := 100000

var _failures := 0
var _checks := 0  # printed at the end, so a test that stopped early on a script error shows
var _skipped: Array[String] = []  # whole groups that didn't run, named in the last line
var _slow := maxf(1.0, OS.get_environment("DESK_PETS_SLOW").to_float())  # stretches the time limits


func _init() -> void:
	if DevArgs.value("profile") == "":
		DevArgs.overrides["profile"] = "test_core"  # before anything loads a save
	var catalog := Catalog.new()
	_test_data_is_consistent(catalog)
	_test_odds_match_box(catalog, "starter")
	_test_odds_match_box(catalog, "sunset")
	_test_odds_match_box(catalog, "midnight")
	_test_box_tiers(catalog)
	_test_numbers()
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
	_test_globes(catalog)
	_test_toys(catalog)
	_test_boosts(catalog)
	_test_automation(catalog)
	_test_whistle(catalog)
	_test_unlocks(catalog)
	_test_gear(catalog)
	_test_book(catalog)
	_test_prices(catalog)
	_test_knacks(catalog)
	_test_care(catalog)
	_test_paws(catalog)
	_test_gifts(catalog)
	(load("res://scripts/game_state.gd") as GDScript).set("testing", false)  # the care tests make GameStates without a save; the GameState tests load their own
	(load("res://scripts/game_state.gd") as GDScript).set("tool_saves", true)  # ... from the test profile, even though this is a -s script
	_test_game_state(catalog)
	_test_herd(catalog)
	_test_herd_game(catalog)
	_test_new_homes(catalog)
	_test_new_homes_game(catalog)
	_test_herd_with_the_rest(catalog)
	_test_receipt(catalog)
	_test_whys_add_up(catalog)
	_test_next_door(catalog)
	_test_edge(catalog)
	_test_school(catalog)
	_test_edge_school_game(catalog)
	_test_herd_knacks(catalog)
	_test_dungeon(catalog)
	_test_plushie(catalog)
	_test_plushie_game(catalog)
	_test_sewing(catalog)
	_test_sewing_game(catalog)
	_test_perks(catalog)
	_test_perks_game(catalog)
	_test_held(catalog)
	_test_held_game(catalog)
	_test_merged_lanes(catalog)
	_test_wish(catalog)
	_test_party_places(catalog)
	_test_workshop(catalog)
	_test_workshop_game(catalog)
	_test_room(catalog)
	_test_goals_game(catalog)
	(load("res://scripts/game_state.gd") as GDScript).set("tool_saves", false)  # the autoload made after this never touches a save
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
			if other.id < l.id and l.has("map") and other.has("map") and other.page == l.page:
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


## How numbers read on screen (NumFormat, what UiTheme.num shows).
func _test_numbers() -> void:
	var cases := { 9999.0: "9,999", 12345.0: "12.3k", 99940.0: "99.9k", 999400.0: "999k", 999960.0: "1M", 99960.0: "100k",
		3.1e15: "3.1Qa", 4.2e21: "4.2Sx", -25000.0: "-25k" }
	for n: float in cases:
		_check(NumFormat.short(n) == cases[n], "NumFormat.short(%s) is %s (got %s)" % [n, cases[n], NumFormat.short(n)])
	_check(NumFormat.full(-1234567) == "-1,234,567", "NumFormat.full puts in commas")
	_check(NumFormat.apart(4.21e12, 4.23e12) == ["4.21T", "4.23T"], "before → after shows the change (%s)" % [NumFormat.apart(4.21e12, 4.23e12)])
	_check(NumFormat.apart(4.2e12, 5.0e12) == ["4.2T", "5T"], "before → after stays short when it can")


## Box tiers (B1): the shop sells a tier once its map page is open, a better tier holds more pets,
## finishes and looks are gated by tier, workers count boxes (not the pets in them), and old saves'
## lucky boxes become sunset boxes.
func _test_box_tiers(catalog: Catalog) -> void:
	var shop := catalog.shop_boxes()
	_check(shop.size() == 3 and shop[0].id == "starter" and shop[1].id == "sunset" and shop[2].id == "midnight", "the shop's tiers are sunny, sunset, midnight")
	_check(catalog.box("lucky").is_empty(), "the lucky box is retired")
	for i in range(1, shop.size()):
		_check(float(shop[i].capsules) >= 5 * float(shop[i - 1].capsules) and float(shop[i].capsules) <= 10 * float(shop[i - 1].capsules), "%s costs about x8 the tier before (in capsules)" % shop[i].id)
		_check(Weighted.chances(shop[i].tiers).get("common", 0.0) < Weighted.chances(shop[i - 1].tiers).get("common", 0.0), "%s has better odds than the tier before" % shop[i].id)
		for f in shop[i - 1].finishes:
			_check(shop[i].finishes.has(f), "%s keeps every finish of the tier before (%s)" % [shop[i].id, f])
		_check(shop[i].has("arrives") and str(shop[i].arrives) != "", "%s has a line for arriving" % shop[i].id)
	_check(not shop[0].finishes.has("glitch") and not shop[0].finishes.has("prismatic"), "sunny boxes have no glitch or prismatic")
	_check(shop[1].finishes.has("glitch") and not shop[1].finishes.has("prismatic"), "sunset boxes add glitch, not prismatic")
	_check(shop[2].finishes.has("prismatic"), "midnight boxes add prismatic")
	var page_ids := catalog.pages.map(func(p): return p.id)
	for b in shop:
		_check(b.has("page") and b.has("stamp") and b.has("pets"), "box %s has a page, a stamp and a pet count" % b.id)
	# which tiers the shop sells: a page that doesn't exist yet keeps its tier out
	var only_start := func(page: String): return catalog.pages.any(func(p): return p.id == page and p.get("start", false))
	var with_beyond := func(page: String): return page in ["backyard", "beyond"]
	var every := func(_page: String): return true
	_check(BoxShop.open_tiers(catalog, only_start).map(func(b): return b.id) == ["starter"], "a new game's shop sells only sunny boxes")
	_check(BoxShop.open_tiers(catalog, with_beyond).map(func(b): return b.id) == ["starter", "sunset"], "beyond the fence brings sunset boxes")
	_check(not "next_door" in page_ids or BoxShop.open_tiers(catalog, with_beyond).size() == 2, "midnight boxes wait for next door")
	_check(BoxShop.open_tiers(catalog, only_start, true).size() == 3, "the dev switch puts every tier in")
	_check(BoxShop.open_tiers(catalog, every).size() == 3, "every page open: every tier")
	# pets per box, and what they can be
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var roller := PetRoller.new(catalog, rng)
	var counts := {}
	for i in 600:
		counts[roller.roll_box("sunset").size()] = true
	_check(counts.keys().all(func(n): return n in [2, 3]) and counts.size() == 2, "a sunset box holds 2 or 3 pets (%s)" % str(counts.keys()))
	_check(roller.roll_box("starter").size() == 1, "a sunny box holds one pet")
	_check(roller.roll_box("tutorial").size() == 1, "the tutorial box holds one pet")
	var gated := {}  # part key -> the box it comes from
	for slot in Catalog.SLOTS:
		for p in catalog.slots[slot]:
			if p.has("from"):
				_check(not catalog.box(str(p.from)).is_empty() and not catalog.box(str(p.from)).get("hidden", false), "look %s comes from a real shop box" % p.id)
				gated["%s:%s" % [slot, p.id]] = str(p.from)
	_check(gated.values().has("sunset") and gated.values().has("midnight"), "sunset and midnight boxes have new looks")
	for t in catalog.tiers:
		_check(Catalog.SLOTS.any(func(sl): return not catalog.parts_in(sl, t.id, "starter").is_empty()), "a sunny box can still roll a %s pet" % t.id)
	var seen := { "starter": {}, "sunset": {} }
	for box_id in seen:
		for t in catalog.tiers:
			for i in 300:
				var pet := roller.roll(box_id, t.id)
				_check_parts_fit_rarity(catalog, pet)
				for slot in Catalog.SLOTS:
					seen[box_id]["%s:%s" % [slot, pet.parts[slot]]] = true
				seen[box_id]["finish:" + pet.finish] = true
	for key in gated:
		if gated[key] != "starter":
			_check(not seen.starter.has(key), "a sunny box never has %s" % key)
		if gated[key] == "midnight":
			_check(not seen.sunset.has(key), "a sunset box never has %s" % key)
	_check(seen.sunset.has("body:fox"), "a sunset box can have a fox")
	for f in ["glitch", "prismatic"]:
		_check(not seen.starter.has("finish:" + f), "a sunny box never rolls %s" % f)
	_check(not seen.sunset.has("finish:prismatic"), "a sunset box never rolls prismatic")
	var sunny_place: Dictionary = catalog.locations.filter(func(l): return l.box == "starter")[0]
	var trip_gated := false
	for i in 3000:
		var got := Rewards.roll_part(str(sunny_place.box), rng, catalog)
		trip_gated = trip_gated or gated.has("%s:%s" % got)
	_check(not trip_gated, "trips to sunny places never bring a look from a better box")
	# workers open boxes, not pets: 5 boxes from sunny 2 + sunset 10 is sunny 2, sunset 3
	var split := BoxShop.split_open({ "starter": 2, "sunset": 10 }, ["starter", "sunset"], 5)
	_check(split == { "starter": 2, "sunset": 3 }, "workers open 5 boxes, not 5 pets (%s)" % str(split))
	_check(BoxShop.split_open({ "starter": 4, "sunset": 10 }, ["sunset"], 3) == { "sunset": 3 }, "workers skip boxes saved for you")
	_check(BoxShop.split_open({ "sunset": 1 }, ["starter", "sunset"], 5) == { "sunset": 1 }, "workers stop when the pile runs out")
	# lucky boxes become sunset boxes (any save version, twice is the same as once)
	var old := { "version": 24, "bag": { "starter": 4, "lucky": 3 }, "saved_boxes": ["lucky"],
		"runs": [{ "loot": { "box:lucky": 2, "coins": 5 }, "log": [{ "loot": { "box:lucky": 1 } }] },
			{ "boxes": { "lucky": 2 } }] }
	BoxShop.fix_retired(old)
	BoxShop.fix_retired(old)
	_check(old.bag == { "starter": 4, "sunset": 3 }, "old lucky boxes are sunset boxes now (%s)" % str(old.bag))
	_check(old.saved_boxes == ["sunset"], "saved-for-you lucky boxes stay saved as sunset boxes")
	_check(old.runs[0].loot == { "box:sunset": 2, "coins": 5 } and old.runs[0].log[0].loot == { "box:sunset": 1 }, "adventures still out bring sunset boxes")
	_check(old.runs[1].boxes == { "sunset": 2 }, "pre-v5 runs' boxes turn into sunset boxes too")
	_check(old.boxes_bought.has("sunset") and old.boxes_bought.has("starter"), "tiers already on the pile don't show up as new")
	var newer := { "bag": { "sunset": 2 }, "boxes_bought": {}, "boxes_greeted": [] }
	BoxShop.fix_retired(newer)
	_check(newer.boxes_bought.is_empty() and newer.boxes_greeted.is_empty(), "a save with tiers keeps what it had bought")
	# "new" looks: two pets in one box sharing a look you'd never had still show it as new
	var c := Collection.new()
	var first := Pet.new()
	first.parts = { "body": "blob", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
	c.add([first] as Array[Pet])
	var twin_a := Pet.new()
	twin_a.parts = { "body": "blob", "palette": "gold", "pattern": "plain", "eyes": "round", "accessory": "none" }
	twin_a.finish = "holo"
	var twin_b := Pet.new()
	twin_b.parts = { "body": "fox", "palette": "gold", "pattern": "plain", "eyes": "round", "accessory": "none" }
	var box_pets: Array[Pet] = [twin_a, twin_b]
	c.add(box_pets)
	var fresh := c.new_keys(box_pets)
	_check(fresh.has(Collection.part_key("palette", "gold")), "a new look two pets in one box share is new")
	_check(fresh.has(Collection.part_key("body", "fox")) and fresh.has(Collection.finish_key("blob", "holo")), "each pet's own new looks are new")
	_check(not fresh.has(Collection.part_key("body", "blob")) and not fresh.has(Collection.part_key("eyes", "round")), "looks you already had aren't new")


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
		batch.append(roller.roll("sunset"))
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
	var situations := ["idle", "away", "needs_you", "someone_back", "back_all", "back_one", "back_some", "back_none", "part_found", "rumour", "spotted", "at_work"]
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
			var real: bool = (bits[0] == "type" and not catalog.adventure_type(bits[1]).is_empty()) or (bits[0] == "location" and not catalog.location(bits[1]).is_empty()) \
				or (bits[0] == "page" and catalog.pages.any(func(pg): return pg.id == bits[1])) \
				or (bits[0] == "feature" and catalog.unlock_list.any(func(e): return id in e.opens))
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
	var top := PetLook.top_row(look.parts)
	_check(top > 0 and top < PetLook.H and plain.get_used_rect().position.y == top, "the top of a pet's art is its first row with anything in it")
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
	_check(three > one * 1.1 and three < one * 3.0, "3 pets work faster than 1, but not 3x (%.2fx)" % (three / one))
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
	_check(per_min > 5.0 and per_min < 20.0, "3 pets on the coin hunt find a gentle trickle (%.1f capsules' worth a minute)" % per_min)
	# errands pay in capsules: they grow with the machine, and stay well under pulling the lever
	var rich: Dictionary = Jobs.work(coin, { "fill": 0.99 }, 1, 1.0, 1.0, rng, catalog, { "coin_value": 74.0 })
	_check(int(rich.loot.get("coins", 0)) == 20 * 74, "a find is worth 20 capsules of the machine (%d)" % int(rich.loot.get("coins", 0)))
	var one_pet_capsules := Jobs.rate(coin, 1, 1.0, power) * 60.0 * float(coin.pay.capsules)
	_check(one_pet_capsules < 26.0 * 0.5, "one pet on the coin hunt finds under half of what pulling gives (%.1f capsules a minute)" % one_pet_capsules)
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
	_check(Jobs.goal_x(coin, 24) == 1.0 and is_equal_approx(Jobs.goal_x(coin, 25), 1.1) and is_equal_approx(Jobs.goal_x(coin, 50), 1.21), "coin hunt goals grow its coins at lv 25 and 50 (and stack)")
	_check(str(Jobs.next_goal(coin, 3).get("text", "")).contains("lemonade"), "the coin hunt's first goal is the lemonade stand")
	_check(catalog.unlock_list.any(func(u): return "job:lemonade" in u.opens and int(u.earn.get("job_level", {}).get("coin_hunt", 0)) == int(coin.goals[0].at)), "the lemonade stand opens at the coin hunt's first goal")
	_check(Jobs.tool_sum(catalog, "coin_hunt", "all_speed", { "snack": 2 }) > 0.0 and Jobs.tool_sum(catalog, "coin_hunt", "speed", { "sign": 5 }) == 0.0, "tools for everyone reach every job, a job's own only that job")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "pockets"), {}, {}, true).begins_with("at lv"), "deeper pockets wait for the coin hunt's level")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "cups"), { "cups": 1 }, {}, true) == "max", "a tool with a max stops there")
	_check(Jobs.tool_block(catalog, Jobs.tool(catalog, "lemons"), {}, {}, false) == "closed", "a job's tools wait for the job")
	_check(float(lemon.tips.rare) > float(lemon.tips.common), "rarer pets get bigger tips")
	var plain := Jobs.average_fill(coin, { "coin_value": 10.0 })
	var better := Jobs.average_fill(coin, { "coin_value": 10.0, "worth": 2.0, "big": 0.1, "big_x": 5.0 })
	_check(is_equal_approx(plain, 200.0) and is_equal_approx(better, 220.0 * 1.4), "tools make each find worth more (%.1f -> %.1f)" % [plain, better])
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
	_check(Jobs.goal_words(lemon, lemon.goals[0]) == "x1.1 tips and a savings jar opens", "a goal with both reads: %s" % Jobs.goal_words(lemon, lemon.goals[0]))
	_check(Jobs.goal_words(coin, coin.goals[1]) == "x1.1 coins and a kitchen opens", "the coin hunt's lv 25: %s" % Jobs.goal_words(coin, coin.goals[1]))
	# hidden until earned: what a goal opens never shows ahead, and a goal that only opens a job shows nothing
	_check(Jobs.goal_words(coin, coin.goals[1], true) == "x1.1 coins", "ahead, the coin hunt's lv 25 reads: %s" % Jobs.goal_words(coin, coin.goals[1], true))
	_check(int(Jobs.next_shown_goal(coin, 0).get("at", 0)) == 25, "the lemonade stand's goal doesn't show ahead: the next shown is lv 25")
	var scout_at := int(jar.goals[0].at)
	_check(not Jobs.shown_ahead(jar.goals[0]) and int(Jobs.next_shown_goal(jar, 0).get("at", 0)) > scout_at, "scouting's goal on the savings jar stays hidden")
	var ui := FileAccess.get_file_as_string("res://scripts/ui/errands_tab.gd")
	_check(not ui.contains("opens at %s lv"), "no waiting notes for jobs still to come")
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
	var k_most := float(kitchen.kitchen.most)
	var k_half := float(kitchen.kitchen.half)
	var soft := [1, 2, 4, 10].map(func(c): return k_most * c / (c + k_half))
	_check(range(4).all(func(i): return absf(bonus[i] - soft[i]) < 0.005) and bonus[0] < bonus[1] and bonus[2] < bonus[3],
		"1/2/4/10 cooks: most x cooks / (cooks + half), each cook adds less (%s)" % [bonus])
	_check(Jobs.kitchen_bonus(kitchen, 1000.0, 1, power) <= float(kitchen.kitchen.most), "the kitchen never goes past its most")
	_check(Jobs.kitchen_bonus(kitchen, 2.0, 1000, power) < 0.002, "with 1000 pets elsewhere, 2 cooks barely matter (%.4f)" % Jobs.kitchen_bonus(kitchen, 2.0, 1000, power))
	var thin := Jobs.faster_words(Jobs.kitchen_bonus(kitchen, 2.0, 200, power))
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
		_check(entry.show == "hidden" and not entry.has("hint"), "unlock %s stays hidden until earned (never shown locked)" % entry.id)
		for o in entry.opens:
			var bits := str(o).split(":")
			var ok: bool = (bits[0] == "tab" and bits[1] in tabs) or (bits[0] == "feature" and bits[1] in ["errands", "packs", "shopping", "parties", "parties_5", "parties_10", "toys", "parts", "auto_adventures", "whistle", "new_homes", "sorting", "edge", "school", "dungeon", "lead_army", "plushie", "sewing", "keep_lines", "wish", "workshop"]) or (bits[0] == "page" and bits[1] in page_ids) \
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


## The whistle (automation layer 2): spot prices flatten, how many spots exist grows with the map,
## and your pet's checks haul spots home (never under set aside, cheapest first) and fill them.
func _test_whistle(catalog: Catalog) -> void:
	# flattened spot prices: the one-go sum matches adding them up, and spot 1000 is still a price
	for id in ["machine", "boxes", "adventures"]:
		var spot: Dictionary = Automation.job(catalog, id).spot
		_check(spot.has("flat_at") and spot.has("grow_late"), "%s spots flatten" % id)
		for have in [0, 5, int(spot.flat_at) - 3, int(spot.flat_at) + 10]:
			var sum := 0.0
			for i in 100:
				sum += Jobs.tool_cost(spot, have + i, 1)
			var one_go := float(Jobs.tool_cost(spot, have, 100))
			_check(absf(one_go - sum) <= maxf(100.0, sum * 1e-9), "100 %s spots from %d cost them added up (%s vs %s)" % [id, have, one_go, sum])
		var far := 100 if spot.has("per_place") else 1000  # parties: one per place, never thousands
		var late := Jobs.tool_cost(spot, far, 1)
		_check(late > 0 and late < roundi(Jobs.MAX_PRICE), "spot %d for %s has a real price (%s)" % [far, id, late])
		var f := int(spot.flat_at)
		_check(float(Jobs.tool_cost(spot, f + 1, 1)) / Jobs.tool_cost(spot, f, 1) < float(Jobs.tool_cost(spot, 2, 1)) / Jobs.tool_cost(spot, 1, 1),
			"%s spots grow slower past %d" % [id, f])
	_check(Jobs.tool_cost(Automation.job(catalog, "machine").spot, 0, 0) == 0, "no spots cost nothing")
	# how many exist: each open page adds more; parties one per open place
	var st := Automation.fresh()
	var one := Automation.exist(catalog, "machine", ["backyard"], 6)
	var two := Automation.exist(catalog, "machine", ["backyard", "beyond"], 11)
	_check(one > 0 and two > one, "a new map page means more machines out there (%d, %d)" % [one, two])
	_check(Automation.exist(catalog, "adventures", ["backyard"], 6) == 6 and Automation.exist(catalog, "adventures", ["backyard"], 9) == 9,
		"one party per open place")
	st.spots.machine = one + 5
	_check(Automation.out_there(catalog, st, "machine", ["backyard"], 6) == 0, "a save with more than exist keeps them, none left out there")
	st.spots.machine = 3
	_check(Automation.out_there(catalog, st, "machine", ["backyard"], 6) == one - 3, "out there = exist - home")
	_check(Automation.affordable(catalog, st, "machine", 1 << 60, 7) == 7, "buying as many as you can stops at what's out there")
	var price3 := Jobs.tool_cost(Automation.job(catalog, "machine").spot, 3, 3)
	_check(Automation.affordable(catalog, st, "machine", price3, 1000) == 3, "as many as you can afford, found by halving")
	# checks: every check_seconds, faster with the pencil
	var w := Automation.fresh()
	var every := Automation.check_seconds(catalog, w)
	_check(Automation.checks(catalog, w, every * 2.5) == 2 and Automation.checks(catalog, w, every * 0.5) == 1, "the whistle checks every %ss (and keeps the rest)" % every)
	w.tools.pencil = 5
	_check(Automation.check_seconds(catalog, w) < every, "a sharper pencil checks faster")
	_check(Automation.haul_size(catalog, w) == 1, "it hauls one a check")
	w.tools.wagon = 1
	_check(Automation.haul_size(catalog, w) == 2, "a bigger wagon hauls two")
	# the plan: nothing unless your pet is managing
	w.taught = { "machine": true, "boxes": true, "whistle": true }
	w.others = { "machine": true, "boxes": true }
	w.spots = { "machine": 10, "boxes": 0 }
	w.workers = { "machine": ["a", "b"] }
	var jobs := ["machine", "boxes"]
	var rooms := { "machine": 50, "boxes": 20 }
	var rich := 1 << 50
	w.task = "machine"
	var idle := Automation.whistle_plan(catalog, w, jobs, rich, rooms, 100, 5)
	_check(idle.buys.is_empty() and idle.fill.is_empty(), "the whistle does nothing while your pet does another job")
	w.task = "whistle"
	var plan := Automation.whistle_plan(catalog, w, jobs, rich, rooms, 100, 1)
	var bought := 0
	for id in plan.buys:
		bought += int(plan.buys[id])
	_check(bought == 2, "with the wagon a check hauls two home (%d)" % bought)
	var m_next := Jobs.tool_cost(Automation.job(catalog, "machine").spot, 10, 1)
	var t_next := Jobs.tool_cost(Automation.job(catalog, "boxes").spot, 0, 1)
	var cheap := "machine" if m_next < t_next else "boxes"
	var solo := Automation.whistle_plan(catalog, w.merged({ "tools": { "wagon": 0 } }, true), jobs, rich, rooms, 100, 1)
	_check(solo.buys.keys() == [cheap], "the cheapest spot comes home first (%s)" % [solo.buys])
	_check(int(plan.fill.get("machine", 0)) == 10 + int(plan.buys.get("machine", 0)) - 2, "empty machines get resting pets (%s)" % [plan.fill])
	var keep := Automation.keep(catalog, w)
	var tight := Automation.whistle_plan(catalog, w, jobs, keep + mini(m_next, t_next) - 1, rooms, 0, 50)
	_check(tight.buys.is_empty() and tight.spent == 0, "the whistle never spends the coins set aside")
	var some := keep + mini(m_next, t_next) * 3
	var spent := Automation.whistle_plan(catalog, w, jobs, some, rooms, 0, 50)
	_check(spent.spent > 0 and some - int(spent.spent) >= keep, "it spends down to set aside, no further")
	w.whistle.ticks = { "machine": { "haul": false, "fill": false }, "boxes": { "haul": false, "fill": false } }
	var off := Automation.whistle_plan(catalog, w, jobs, rich, rooms, 100, 5)
	_check(off.buys.is_empty() and off.fill.is_empty(), "ticked off, nothing happens")
	_check(Automation.whistle_plan(catalog, w, jobs, rich, rooms, 100, 0).buys.is_empty(), "no checks, nothing happens")
	w.whistle.ticks = {}
	_check(Automation.whistle_plan(catalog, w, jobs, rich, { "machine": 0, "boxes": 0 }, 0, 5).buys.is_empty(), "nothing left out there, nothing hauled")
	# set aside steps
	var k := Automation.fresh()
	var start := Automation.keep(catalog, k)
	k.whistle.keep = Automation.keep_step(catalog, k, 1)
	_check(Automation.keep(catalog, k) > start, "+ sets more aside")
	k.whistle.keep = Automation.keep_step(catalog, k, -1)
	_check(Automation.keep(catalog, k) == start, "− goes back a step")
	k.whistle.keep = 0
	_check(Automation.keep_step(catalog, k, -1) == 0, "set aside never goes under 0")
	# the whistle turns up at the old well once you have enough workers, and only once
	var well := catalog.location("well")
	var e: Dictionary = catalog.events.get("well_whistle", {})
	_check(e.get("find", "") == "whistle" and int(e.get("after_workers", 0)) > 0, "the whistle is a find that waits for workers")
	var need := int(e.get("after_workers", 0))
	_check(not "well_whistle" in AdventureRunner.pick_events(well, 1, {}, catalog, {}, need - 1), "no whistle with %d workers" % (need - 1))
	_check("well_whistle" in AdventureRunner.pick_events(well, 1, {}, catalog, {}, need), "the whistle with %d workers" % need)
	_check(not "well_whistle" in AdventureRunner.pick_events(well, 1, { "whistle": true }, catalog, {}, need), "found once, gone")
	var rope_at := int(catalog.events.well_rope.get("after_sent", 0))
	_check(not "well_rope" in AdventureRunner.pick_events(well, 1, { "whistle": true }, catalog, {}, need, false, rope_at - 1), "no rope with %d pets sent to the well" % (rope_at - 1))
	_check("well_rope" in AdventureRunner.pick_events(well, 1, { "whistle": true }, catalog, {}, need, false, rope_at), "the rope once %d have gone down" % rope_at)
	var alone: Array[Pet] = [_plain_pet(catalog, "common", "normal", 1)]
	var lone := AdventureRunner.start("well", alone, 0.0, 1, catalog, { "whistle": true }, {}, {}, {}, need, false, rope_at)
	_check("well_rope" in lone.events and AdventureRunner.applies(catalog.events.well_rope, lone.party), "a lone pet meets the rope once enough have gone down")
	_check(Automation.job(catalog, "whistle").get("id", "") == "whistle" and Automation.tool(catalog, "wagon").get("job", "") == "whistle",
		"the whistle is a job with its own tools")
	_check(Automation.tool_block(Automation.fresh(), Automation.tool(catalog, "pencil")) == "closed", "its tools wait for the whistle")
	# parties get their pets set aside before the machines take everyone
	var p := Automation.fresh()
	p.task = "whistle"
	p.taught = { "machine": true, "adventures": true, "whistle": true }
	p.others = { "machine": true, "adventures": true }
	p.spots = { "machine": 60, "adventures": 2 }
	p.workers = { "machine": [], "adventures": ["", ""] }
	var size := int(Automation.job(catalog, "adventures").get("party", 3))
	var pjobs := ["machine", "adventures"]
	var fill := Automation.whistle_plan(catalog, p, pjobs, 0, { "machine": 0, "adventures": 0 }, 40, 1)
	_check(int(fill.fill.get("adventures", 0)) == 2 and int(fill.fill.get("machine", 0)) == 40 - 2 - 2 * size,
		"empty parties get leaders and their pets stay free (%s)" % [fill.fill])
	_check(fill.fill.keys()[0] == "adventures", "parties are filled first")
	var out := Automation.whistle_plan(catalog, p.merged({ "workers": { "machine": [], "adventures": ["a", "b"] } }, true), pjobs, 0, { "machine": 0, "adventures": 0 }, 40, 1, 2)
	_check(int(out.fill.get("machine", 0)) == 40, "parties that are out took their pets already (%s)" % [out.fill])
	# workers from the herd fill spots too
	var hp := p.merged({ "spots": { "machine": 30, "adventures": 0 }, "workers": { "machine": ["a", "b"] }, "wherd": { "machine": { "common:normal": 28 } } }, true)
	_check(Automation._working(hp, "machine") == 30, "herd workers count as working (%d)" % Automation._working(hp, "machine"))
	var full := Automation.whistle_plan(catalog, hp, ["machine"], 0, { "machine": 0 }, 40, 1)
	_check(int(full.fill.get("machine", 0)) == 0, "spots filled by the herd aren't filled again (%s)" % [full.fill])
	hp.wherd = { "machine": { "common:normal": 20 } }
	var some_left := Automation.whistle_plan(catalog, hp, ["machine"], 0, { "machine": 0 }, 40, 1)
	_check(int(some_left.fill.get("machine", 0)) == 8, "only the spots the herd left empty get pets (%s)" % [some_left.fill])
	p.spots = { "machine": 0, "adventures": 0 }
	p.workers = { "adventures": [] }
	var few := Automation.whistle_plan(catalog, p.merged({ "tools": { "wagon": 0 } }, true), ["adventures"], rich, { "adventures": 5 }, size, 1)
	_check(few.buys.is_empty(), "no party hauled home without pets to lead it and go (%s)" % [few.buys])
	var enough := Automation.whistle_plan(catalog, p.merged({ "tools": { "wagon": 0 } }, true), ["adventures"], rich, { "adventures": 5 }, size + 1, 1)
	_check(int(enough.buys.get("adventures", 0)) == 1, "a party comes home when there's a leader and a crew")


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
			_check(b in Machine.all_bits(catalog), "tree node %s asks for a real bit (%s)" % [n.id, b])
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
	# the prize card: odds add up, follow better drops, swap kinds that aren't open for coins
	var all_open := func(_k): return true
	var early := Machine.odds(fresh, catalog, all_open)
	var total := 0.0
	for id in early:
		total += float(early[id])
	_check(absf(total - 1.0) < 0.0001, "the machine's odds add up to 1 (%.4f)" % total)
	var dropped := { "bought": { "drops": 2 } }
	for p in m.prizes:
		var waits := float(p.get("drops", 0)) > 0.0
		_check(early.has(p.id) != waits, "prize %s %s the odds before better drops" % [p.id, "is missing from" if waits else "is on"])
		_check(Machine.odds(dropped, catalog, all_open).has(p.id), "prize %s is on the odds with better drops" % p.id)
	var no_boxes := Machine.odds(dropped, catalog, func(k): return k != "box")
	var box_w := 0.0
	var all_w := 0.0
	for p in m.prizes:
		all_w += float(p.weight)
		if p.kind == "box":
			box_w += float(p.weight)
	_check(not no_boxes.has("box") and absf(float(no_boxes.coins) - (float(m.prizes[0].weight) + box_w) / all_w) < 0.0001, "a kind that isn't open yet counts as coins on the odds")
	var lucky_odds := Machine.odds(dropped, catalog, all_open, true, 2.0, 1.5)
	var lucky_total := 0.0
	for id in lucky_odds:
		lucky_total += float(lucky_odds[id])
		var p: Dictionary = m.prizes.filter(func(x): return x.id == id)[0]
		_check(p.get("lucky", false), "lucky odds only hold lucky prizes (%s)" % id)
	_check(absf(lucky_total - 1.0) < 0.0001, "lucky odds add up to 1")
	var rate_up := Machine.odds(dropped, catalog, all_open, false, 1.0, 3.0)
	_check(float(rate_up.toy) > float(Machine.odds(dropped, catalog, all_open).toy), "toys that make toys show on the odds")
	# fever stays a burst: even fully upgraded with big toys it ends before the lights relight
	var maxed_fever := { "bought": { "wires": 1 } }
	for n in catalog.machine_tree.nodes:
		if n.each.has("fever_s"):
			maxed_fever.bought[n.id] = int(n.get("max", 1))
	var relight := func(speed: float) -> float: return Machine.lights_needed(maxed_fever, catalog) * Machine.reveal_seconds(maxed_fever, catalog) / speed
	_check(Machine.fever_for(maxed_fever, catalog, 5.0, 3.0) < relight.call(3.0), "fever ends before the lights relight, even with a 5x fever toy and a 3x speed toy")
	_check(Machine.fever_for(maxed_fever, catalog) < relight.call(1.0), "fully upgraded fever ends before the lights relight")
	_check(is_equal_approx(Machine.fever_for(maxed_fever, catalog), Machine.fever_seconds(maxed_fever, catalog)), "fully upgraded fever without toys isn't cut short (%.1f s)" % Machine.fever_for(maxed_fever, catalog))
	_check(Machine.fever_for(fresh, catalog) > 0.0, "fever lasts a while")
	# a speed toy never cancels longer fever: every level still adds fever pulls
	var fever_node := ""
	for n in catalog.machine_tree.nodes:
		if n.each.has("fever_s"):
			fever_node = str(n.id)
	for speed in [1.0, 1.1, 1.5, 3.0]:
		var last := 0.0
		for lv in int(Machine.node(catalog, fever_node).get("max", 1)) + 1:
			var st := { "bought": { "wires": 1, fever_node: lv } }
			var pulls: float = Machine.fever_for(st, catalog, 1.0, speed) * speed / Machine.reveal_seconds(st, catalog)
			_check(pulls > last + 0.01, "longer fever level %d still adds fever pulls with a x%.1f speed toy (%.2f pulls)" % [lv, speed, pulls])
			last = pulls
	_check(is_equal_approx(Machine.fever_for(maxed_fever, catalog, 1.0, 1.5) * 1.5, Machine.fever_for(maxed_fever, catalog)), "a speed toy gives the same fever pulls in less time")
	# a pet box only comes in a pull's first capsule: in the others it counts as coins
	var later := Machine.odds(dropped, catalog, all_open, false, 1.0, 1.0, false)
	var first_odds := Machine.odds(dropped, catalog, all_open)
	_check(not later.has("pet_box") and first_odds.has("pet_box"), "a pet box is only on the first capsule's odds")
	_check(absf(float(later.coins) - float(first_odds.coins) - float(first_odds.pet_box)) < 0.0001, "a later capsule's pet box chance goes to coins")
	_check(not Machine.many_capsules(fresh, catalog) and Machine.many_capsules({ "bought": { "chute2": 1 } }, catalog) and Machine.many_capsules({ "bought": { "double": 1 } }, catalog), "a second chute or double drop means more capsules a pull")
	for p in m.prizes:
		_check(p.has("name") or (p.kind == "box" and catalog.box(str(p.box)).has("name")), "prize %s has a name for the prize card" % p.id)


## A5: a globe per map page. The sunset globe comes home with its find, broken; its nodes hide until
## then; the nest makes it the one you pull and the sunny one moves behind (pet, workers, errands);
## coins, extra balls, shiny, fever and drops carry over to newer globes, chutes, lights and glass
## don't; its hatch gives sunset boxes and sunset toys; its bits only drop once it's home.
func _test_globes(catalog: Catalog) -> void:
	var globes := Machine.globes(catalog)
	_check(globes.map(func(g): return g.id) == ["sunny", "sunset", "midnight"], "three globes: sunny, sunset, midnight")
	for g in globes:
		_check(float(g.get("step", 1)) >= 1.0, "globe %s's capsules are worth at least the sunny ones" % g.id)
		_check(not catalog.box(str(g.get("box", ""))).is_empty(), "globe %s's hatch gives a real box tier" % g.id)
		_check(g.has("view") and g.view.size() == 4, "globe %s has its part of the tree" % g.id)
		if g.id != "sunny":
			_check(Machine.globe_for_find(catalog, str(g.find)) == g.id, "globe %s comes home with its find" % g.id)
	_check(catalog.finds.has("sunset_globe"), "the sunset globe is a real find")
	var ev: Array = catalog.events.values().filter(func(e): return str(e.get("find", "")) == "sunset_globe")
	_check(ev.size() == 1 and str(ev[0].get("after", "")) == "tiny_machine" and str(ev[0].get("after_machine", "")) == "drops" and ev[0].get("auto", false)
		and catalog.location("fields").events.has(ev[0].id), "the sunset globe turns up in the far fields, after the tiny machine")
	var nest := Machine.node(catalog, "nest")
	_check(Machine.globe_of(catalog, nest) == "sunset" and str(nest.get("from", "")) == "drops", "the sunset branch grows off the old rusted hatch")
	_check(Machine.repairs(catalog, "sunset").map(func(n): return n.id) == ["nest", "cork", "pulley", "amber", "hatch"], "the sunset globe has its five fixes")
	# bits: every bit has its data, every node asks for its own globe's bits, sunset bits have a place
	for b in Machine.all_bits(catalog):
		var info := Machine.bit_info(catalog, b)
		_check(info.has("name") and info.has("plural") and info.has("color") and Machine.globe_rank(catalog, str(info.get("globe", ""))) >= 0, "bit %s has a name, plural, colour and globe" % b)
	for n in catalog.machine_tree.nodes:
		for b in n.get("bits", {}):
			_check(str(Machine.bit_info(catalog, b).get("globe", "")) == Machine.globe_of(catalog, n), "node %s asks for its own globe's bits (%s)" % [n.id, b])
	_check(Machine.bits_of(catalog, "sunny") == ["gear", "spring", "bolt", "glass"] and Machine.bits_of(catalog, "sunset") == ["cork", "pulley", "wire", "amber"], "each globe has its bits")
	for b in Machine.bits_of(catalog, "sunset"):
		var from: Array = catalog.locations.filter(func(l): return l.get("finish_rewards", []).any(func(r): return r.get("id", "") == b and r.get("after", "") == "sunset_globe"))
		_check(not from.is_empty(), "sunset bit %s drops somewhere, once the sunset globe is home" % b)
	_check(Machine.bit_name(catalog, "wire", 2) == "copper wire" and Machine.bit_name(catalog, "cork", 2) == "corks" and Machine.bit_name(catalog, "cork", 1) == "cork", "bit names come from data")

	# the sunny globe all fixed up
	var state := { "bought": {}, "globes": ["sunny"] }
	for n in catalog.machine_tree.nodes:
		if Machine.globe_of(catalog, n) == "sunny":
			state.bought[n.id] = int(n.get("max", 1))
	_check(Machine.hand(state, catalog) == "sunny" and Machine.behind(state, catalog) == "sunny" and Machine.newest(state, catalog) == "sunny", "one globe: you and the workers both use it")
	_check(Machine.look(state, catalog, "nest") == "away" and Machine.look(state, catalog, "hatch") == "away", "the sunset fixes hide until the sunset globe is home")
	_check(Machine.home({ "bought": {}, "globes": ["sunset", "nope"] }, catalog) == ["sunny", "sunset"], "the sunny globe is always home, unknown globes aren't")
	state.globes = ["sunny", "sunset"]
	_check(Machine.look(state, catalog, "nest") == "next" and Machine.look(state, catalog, "cork") == "dim", "once it's home its first fix is next")
	_check(Machine.repairs(catalog, "sunset").all(func(n): return Machine.look(state, catalog, n.id) in ["next", "dim"]), "the whole sunset chain shows once it's home (no ? in its fixes list or on the tree)")
	_check(Machine.hand(state, catalog) == "sunny" and Machine.behind(state, catalog) == "sunny" and Machine.newest(state, catalog) == "sunset", "a broken new globe: you keep pulling the sunny one")
	_check(Machine.bits_of(catalog, Machine.newest(state, catalog)) == ["cork", "pulley", "wire", "amber"], "the bits pills show the newest globe's bits")
	_check(Machine.repairs_left(state, catalog, "sunset") and not Machine.repairs_left(state, catalog, "sunny"), "the sunset globe has repairs left")
	var sunny_before := Machine.coin_value(state, catalog, "sunny")
	state.bought.nest = 1
	_check(Machine.hand(state, catalog) == "sunset" and Machine.behind(state, catalog) == "sunny", "the nest out: you pull the sunset globe, the sunny one is behind")
	_check(is_equal_approx(Machine.coin_value(state, catalog), Machine.coin_value(state, catalog, "sunset")), "the hand globe is the default")
	_check(is_equal_approx(Machine.coin_value(state, catalog, "sunset"), sunny_before * Machine.step(catalog, "sunset")), "sunset capsules: the sunny coins x its step")
	_check(is_equal_approx(Machine.coin_value(state, catalog, "sunny"), sunny_before), "the sunny globe's worth doesn't change")
	_check(Machine.chutes(state, catalog, "sunset") == 1 and Machine.chutes(state, catalog, "sunny") == 4, "chutes only count on their own globe")
	_check(not Machine.lights_on(state, catalog, "sunset") and Machine.lights_on(state, catalog, "sunny"), "lights only count on their own globe")
	_check(Machine.shiny_chance(state, catalog, "sunset") == 0.0 and Machine.shiny_chance(state, catalog, "sunny") > 0.0, "shiny balls wait for the sunset globe's own glass")
	_check(Machine.add(state, catalog, "double", "sunset") > 0.0 and is_equal_approx(Machine.add(state, catalog, "double", "sunset"), Machine.add(state, catalog, "double", "sunny")), "extra balls carry over to the newer globe")
	_check(is_equal_approx(Machine.fever_seconds(state, catalog, "sunset"), Machine.fever_seconds(state, catalog, "sunny")), "longer fever carries over")
	_check(Machine.add(state, catalog, "drops", "sunset") > 0.0, "better drops carries over")
	state.bought.cork = 1
	_check(is_equal_approx(Machine.coin_value(state, catalog, "sunset"), sunny_before * Machine.step(catalog, "sunset") * 2.0) and is_equal_approx(Machine.coin_value(state, catalog, "sunny"), sunny_before), "sunset coins only count on the sunset globe (not the older one)")
	state.bought.pulley = 1
	_check(Machine.chutes(state, catalog, "sunset") == 2, "the pulley gives the sunset globe a second chute")
	state.bought.amber = 1
	_check(Machine.lights_on(state, catalog, "sunset") and is_equal_approx(Machine.shiny_chance(state, catalog, "sunset"), Machine.shiny_chance(state, catalog, "sunny")), "amber glass: lights and the sunny shiny chance on the sunset globe")
	_check(Machine.box_of(state, catalog, "sunset") == "starter" and Machine.toy_sets(state, catalog, "sunset") == ["backyard"], "before its hatch the sunset globe drops what the sunny one does")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var box_prize: Dictionary = catalog.machine.prizes.filter(func(p): return p.kind == "box")[0]
	_check(Machine.loot(box_prize, state, catalog, rng, 1.0, "sunset").has("box:starter"), "a box before the hatch is a sunny box")
	state.bought.hatch = 1
	_check(Machine.box_of(state, catalog, "sunset") == "sunset" and Machine.box_of(state, catalog, "sunny") == "starter", "the rusted hatch: sunset boxes on the sunset globe only")
	_check(Machine.loot(box_prize, state, catalog, rng, 1.0, "sunset").has("box:sunset"), "a box out of the sunset globe is a sunset box")
	_check(Machine.toy_sets(state, catalog, "sunset") == ["backyard", "sunset"] and Machine.toy_sets(state, catalog, "sunny") == ["backyard"], "sunset toys only on the sunset globe, after its hatch")
	_check(not Machine.repairs_left(state, catalog, "sunset"), "all sunset fixes done")
	var sunset_toys := Toys.of_sets(catalog, ["sunset"]).map(func(t): return t.id)
	_check(sunset_toys.size() == 4, "the sunset set has four toys")
	var got_sunset := false
	for i in 3000:
		var t := Toys.roll(catalog, rng, 2.0, ["backyard"])
		if t.id in sunset_toys:
			_check(false, "a sunny roll never gives a sunset toy (%s)" % t.id)
			break
		got_sunset = got_sunset or Toys.roll(catalog, rng, 1.0, ["backyard", "sunset"]).id in sunset_toys
	_check(got_sunset, "a roll with the sunset set can give sunset toys")
	# the finish treat: no sunset bits before the globe is home, then they come
	var roller := PetRoller.new(catalog, rng)
	var pets: Array[Pet] = []
	for i in 5:
		pets.append(roller.roll("starter"))
	var corks_without := 0
	var corks_with := 0
	for seed in 40:
		var a := AdventureRunner.start("orchard", pets, 0.0, seed, catalog)
		AdventureRunner._finish_treat(a, catalog.location("orchard"), catalog, {})
		corks_without += int(a.loot.get("bit:cork", 0)) + int(a.loot.get("bit:amber", 0))
		var b := AdventureRunner.start("orchard", pets, 0.0, seed, catalog)
		AdventureRunner._finish_treat(b, catalog.location("orchard"), catalog, { "sunset_globe": true })
		corks_with += int(b.loot.get("bit:cork", 0))
	_check(corks_without == 0 and corks_with > 0, "orchard corks only come once the sunset globe is home (%d vs %d)" % [corks_without, corks_with])
	var well := AdventureRunner.start("well", pets, 0.0, 1, catalog)
	AdventureRunner._finish_treat(well, catalog.location("well"), catalog, {})
	_check(well.history.is_empty() and well.xp == 0, "the old well gives no treat until the pulleys can come")

	# an injected midnight catalog: any number of globes
	var cat2 := Catalog.new()
	var tree: Dictionary = cat2.machine_tree.duplicate(true)
	tree.nodes.append({ "id": "porch_dust", "globe": "midnight", "branch": "sunset", "at": [390, -440], "name": "dust", "icon": "nest", "max": 1, "coins": 1, "grow": 1, "bits": {}, "each": {}, "fixes": "nest", "from": "hatch" })
	tree.nodes.append({ "id": "porch_hatch", "globe": "midnight", "branch": "sunset", "at": [390, -520], "name": "hatch", "icon": "hatch", "max": 1, "coins": 1, "grow": 1, "bits": {}, "each": { "coins_x": 2, "chutes": 1 }, "fixes": "hatch", "from": "porch_dust" })
	cat2.machine_tree = tree
	var three := { "bought": state.bought.duplicate(), "globes": ["sunny", "sunset", "midnight"] }
	_check(Machine.hand(three, cat2) == "sunset" and Machine.behind(three, cat2) == "sunny" and Machine.newest(three, cat2) == "midnight", "a broken midnight globe: you pull the sunset one")
	three.bought.porch_dust = 1
	_check(Machine.hand(three, cat2) == "midnight" and Machine.behind(three, cat2) == "sunset", "the midnight globe works: you pull it, the sunset one is behind")
	_check(is_equal_approx(Machine.coin_value(three, cat2, "midnight"), Machine.coin_value(three, cat2, "sunset") / Machine.step(cat2, "sunset") * Machine.step(cat2, "midnight")), "midnight capsules: every older globe's coins x its step")
	_check(Machine.chutes(three, cat2, "midnight") == 1 and Machine.box_of(three, cat2, "midnight") == "sunset", "before its hatch the midnight globe has one chute and drops sunset boxes")
	three.bought.porch_hatch = 1
	_check(Machine.box_of(three, cat2, "midnight") == "midnight" and Machine.chutes(three, cat2, "midnight") == 2 and Machine.chutes(three, cat2, "sunset") == 2, "its hatch: midnight boxes, and its chute is its own")

	# GameState: the find brings the globe home, bits wait for it, errands and your pet's crank use
	# the globe behind yours, the v29 -> v30 migration (a GameState in this test profile only)
	if DevProfile.active():
		_test_globes_game(catalog)


func _test_globes_game(catalog: Catalog) -> void:
	var gs: Node = load("res://scripts/game_state.gd").new()
	gs._can_save = false
	gs.machine = { "pulls": 0, "lit": 0, "bought": {}, "globes": ["sunny"], "greeted": ["sunny"] }
	for n in catalog.machine_tree.nodes:
		if Machine.globe_of(catalog, n) == "sunny":
			gs.machine.bought[n.id] = int(n.get("max", 1))
	gs.bits = {}
	gs.grant({ "bit:cork": 3 })
	_check(int(gs.bits.get("cork", 0)) == 0, "no corks before the sunset globe is home")
	gs.grant({ "find:sunset_globe": 1 })
	_check(gs.machine.globes == ["sunny", "sunset"] and gs.globe_news() == "sunset", "its find brings the sunset globe home, news until the tab shows it")
	gs.grant({ "bit:cork": 3 })
	_check(int(gs.bits.get("cork", 0)) == 3, "corks count once it's home")
	gs.greet_globe("sunset")
	_check(gs.globe_news() == "", "shown once")
	var sunny_v := Machine.coin_value(gs.machine, catalog, "sunny")
	gs.machine.bought["nest"] = 1
	gs.machine.bought["cork"] = 1
	var job: String = str(catalog.errands.jobs[0].id)
	_check(is_equal_approx(float(gs.job_boost(job).coin_value), sunny_v), "errands pay at the globe behind yours")
	var total := 0
	var ctx: Dictionary = gs._crank_context()
	for i in 200:
		total += int(gs._pet_capsule(ctx).loot.get("coins", 0))
	_check(total > 0 and total < roundi(200 * Machine.coin_value(gs.machine, catalog, "sunset") * 0.5), "your pet cranks the globe behind yours (%d coins from 200)" % total)
	gs.free()
	# an old save (v29, no globes) loads with just the first globe, already seen
	var old_gs: Node = load("res://scripts/game_state.gd").new()
	old_gs._can_save = false
	old_gs.save_path = DevProfile.path("globes_v29_test.json")
	SaveFile.write(old_gs.save_path, { "version": 29, "machine": { "pulls": 5, "lit": 0, "bought": { "tape": 1 } } })
	old_gs.load_game()
	var first := Machine.first_globe(catalog)
	_check(old_gs.machine.globes == [first] and old_gs.machine.greeted == [first] and old_gs.globe_news() == "", "v29 -> v30: an old save has just the first globe, already seen")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(old_gs.save_path))
	old_gs.free()


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
	# shining: past max level the spares buy stars, each ten times dearer, each a bit more boost
	var shine: Dictionary = d.shine
	var plain_x := Toys.boost(state, catalog, "acorn:normal")
	state.owned["acorn:normal"].spares = int(shine.first) - 1
	_check(not Toys.shine(state, catalog, "acorn:normal"), "a star needs its spares")
	state.owned["acorn:normal"].spares = int(shine.first) * (1 + int(shine.x))
	_check(Toys.shine(state, catalog, "acorn:normal") and Toys.shine(state, catalog, "acorn:normal") and Toys.stars(state, "acorn:normal") == 2,
		"spares shine a favourite: two stars")
	_check(int(state.owned["acorn:normal"].spares) == 0, "the second star cost %d times the first" % int(shine.x))
	_check(Toys.boost(state, catalog, "acorn:normal") > plain_x, "stars make the boost bigger")
	_check(Toys.shine_cost(state, catalog, "acorn:ghost") == 0 or Toys.is_favourite(state, catalog, "acorn:ghost"), "only a favourite shines")
	# risking lots at once: each try takes the same spares, and the tally adds up
	state.owned["acorn:normal"].spares = int(d.sacrifice.spares) * 50 + 1
	var tally := Toys.sacrifice_many(state, catalog, "acorn", 1000, rng)
	var tries := 0
	for k in tally:
		tries += int(tally[k])
	_check(tries == 50 and int(state.owned["acorn:normal"].spares) == 1, "risking all is as many tries as the spares pay for (%d)" % tries)
	var full := Toys.fresh()
	for t in catalog.toys.sets[0].toys:
		Toys.add(full, t.id, "normal")
	_check(Toys.slots(full, catalog) == int(d.slots) + 1, "a finished set gives another play slot")


## Boosts: one kind table (data/boosts.json), every source gives parts { source, id, x }, the total
## is their product. Sources are toys, the book, knacks and the kitchen (data/boosts.json "sources");
## here the toys: a playing toy or a favourite counts, a finished play doesn't, an "all" toy counts
## for the kinds marked all, and other sources multiply on top.
func _test_boosts(catalog: Catalog) -> void:
	var ids := Boosts.kinds(catalog)
	for k in catalog.boosts.kinds:
		_check(str(k.get("id", "")) != "" and str(k.get("name", "")) != "", "boost kind %s has an id and a name" % k)
	for src in catalog.boosts.sources:
		_check(str(src) != "", "boost sources have names")
	var trip := Boosts.trip_kinds(catalog)
	_check("trip" in trip and "loot" in trip and not "coins" in trip, "trips pack the kinds marked trip")
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
	# a trip that set off before parts are in the game: the chest brings no part and doesn't say so
	var chest: Dictionary = catalog.events.garden_chest
	var early_ok := false
	for t in 50:
		var early := AdventureRunner.start("meadow", bean, 0.0, t, catalog)
		early.parts = false
		var said := AdventureRunner.play(chest, 0, early, catalog)
		if said.success:
			_check(Rewards.total(early.loot, "part") == 0 and not str(said.text).contains("part"),
				"before parts, the chest says no part and brings none (%s)" % said.text)
			var kept := RunState.from_dict(JSON.parse_string(JSON.stringify(early.to_dict())), catalog)
			_check(not kept.parts, "a run from before parts stays that way through a save")
			early_ok = true
			break
	_check(early_ok, "the chest opened on some early trip")
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
	# looks from a box that isn't in the shop yet don't count (midnight needs next door)
	var bodies := Book.page(catalog, "bodies")
	var sunny := catalog.box_rank("starter")
	var sunset := catalog.box_rank("sunset")
	_check(not Book.keys(catalog, bodies, sunny).has(Collection.part_key("body", "fox"))
		and not Book.keys(catalog, bodies, sunny).has(Collection.part_key("body", "dragon")), "with only the sunny box, fox and dragon aren't on the bodies page")
	_check(Book.keys(catalog, bodies, sunset).has(Collection.part_key("body", "fox"))
		and not Book.keys(catalog, bodies, sunset).has(Collection.part_key("body", "dragon")), "the sunset box brings fox, not dragon")
	_check(Book.keys(catalog, bodies).size() == catalog.slots.body.size(), "with every box, every body counts")
	var fin_sunset := Book.keys(catalog, fin, sunset)
	_check(fin_sunset.has(Collection.finish_key("blob", "glitch")) and not fin_sunset.has(Collection.finish_key("blob", "prismatic"))
		and not Book.keys(catalog, fin, sunny).has(Collection.finish_key("blob", "glitch")), "glitch counts from the sunset box, prismatic only with midnight")
	var c3 := Collection.new()
	for k in Book.keys(catalog, bodies, sunset):
		c3.see(k)
	_check(Book.full(catalog, c3, bodies, sunset) and not Book.full(catalog, c3, bodies), "no dragon needed while the midnight box isn't out")
	# every look a page counts can really come out of a box in the shop by then
	var unearnable: Array[String] = []
	for rank in [sunny, sunset, catalog.box_rank("midnight")]:
		var shop := catalog.shop_boxes().filter(func(b): return catalog.box_rank(str(b.id)) <= rank)
		for p in pages:
			for k: String in Book.keys(catalog, p, rank):
				var bits := k.split(":")
				var ok := false
				for b in shop:
					if p.has("slot"):
						var part := catalog.part(str(p.slot), bits[2])
						ok = ok or (float(b.tiers.get(str(part.rarity), 0)) > 0.0
							and catalog.parts_in(str(p.slot), str(part.rarity), str(b.id)).any(func(x): return x.id == part.id))
					else:
						ok = ok or float(b.finishes.get(bits[2], 0)) > 0.0
				if not ok:
					unearnable.append("%s@%d" % [k, rank])
	_check(unearnable.is_empty(), "every look a book page counts comes out of a box in the shop (%s)" % [unearnable])
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
	_check(gs.book_rank() == catalog.box_rank("starter"), "a new game's book counts the sunny box's looks")
	var tb: float = gs.workers_speed("machine")
	var crank_before: float = Automation.crank_seconds(catalog, gs.automation) / gs.boost("automation")
	gs.automation.workers["machine"] = [gs.collection.pets[1].uid]
	gs._worker_speed.clear()
	var worker_before: float = gs.workers_speed("machine") * gs.boost("automation")
	gs.collection.add(last)
	_check(opened == ["bodies"] and gs.stickers == ["bodies"], "the last body opens the bodies sticker (%s)" % [opened])
	var again: Array[Pet] = [Pet.new()]
	again[0].parts = { "body": "blob", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
	gs.collection.add(again)
	_check(opened.size() == 1, "a sticker opens only once")
	_check(is_equal_approx(gs.boost("automation"), 1.1), "the blanket is x1.1 automation (%s)" % [gs.boost_parts("automation")])
	_check(Automation.crank_seconds(catalog, gs.automation) / gs.boost("automation") < crank_before, "the automation sticker makes your pet crank faster")
	_check(gs.workers_speed("machine") * gs.boost("automation") > worker_before and worker_before > tb, "the automation sticker makes the workers faster")
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
	var golden_before: float = gs.machine_odds().get("golden", 0.0)
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
	# a v22 save (before scout notes, stickers and box tiers) with a lucky box and a full page
	var v22 := { "version": 22, "bag": { "lucky": 2, "starter": 1 }, "collection": { "seen": {} } }
	for k in keys:
		v22.collection.seen[k] = 1
	SaveFile.write(path, v22)
	var gs4: Node = GS.new()
	gs4.save_path = path
	gs4.load_game()
	gs4.check_book()
	_check(gs4.bag == { "sunset": 2, "starter": 1 }, "a v22 save's lucky boxes load as sunset boxes (%s)" % [gs4.bag])
	_check(gs4.stickers == ["eyes"], "a v22 save with a full page gets its sticker (%s)" % [gs4.stickers])
	_check(gs4.scout_notes == 0, "a v22 save starts with no scout notes")
	gs4._can_save = true
	gs4.save_game()
	_check(int(SaveFile.read(path).get("version", 0)) == GS.SAVE_VERSION, "a v22 save is saved back at v%d" % GS.SAVE_VERSION)
	# every pet out of a box counts: two pets of one sunset box finish a page together
	var gs5: Node = GS.new()
	var got5: Array[String] = []
	gs5.sticker_opened.connect(func(id): got5.append(id))
	for k in keys.slice(0, keys.size() - 2):
		gs5.collection.see(k)
	var box_pair: Array[Pet] = []
	for k in keys.slice(keys.size() - 2):
		var pet := Pet.new()
		pet.parts = { "body": "blob", "palette": "lilac", "pattern": "plain", "eyes": str(k).get_slice(":", 2), "accessory": "none" }
		box_pair.append(pet)
	gs5.collection.add(box_pair)
	_check(got5 == ["eyes"], "the last two eyes out of one box open the eyes sticker (%s)" % [got5])
	for f in [path, path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	for n in [gs, gs2, gs3, gs4, gs5]:
		n.free()


## The wishing jar (Wish, data/wish.json): steps, what can be wished for, weights inside a tier
## that never move rarity, which pets go (and never come back), the unlock, the save.
func _test_wish(catalog: Catalog) -> void:
	var st: Array = Wish.steps(catalog)
	_check(st.map(func(x): return int(x)) == [200, 600, 2000, 6000] and Wish.total(catalog) == 8800, "the jar has 4 steps of 200 / 600 / 2k / 6k (%s)" % [st])
	var w0 := Wish.where(catalog, 0)
	_check(w0.full == 0 and w0.have == 0 and w0.need == 200 and not w0.done, "an empty jar: step 1, 0 / 200")
	var w199 := Wish.where(catalog, 199)
	_check(w199.full == 0 and w199.have == 199, "199 in: still step 1")
	var w200 := Wish.where(catalog, 200)
	_check(w200.full == 1 and w200.have == 0 and w200.need == 600, "200 in: one full step, 0 / 600")
	var w800 := Wish.where(catalog, 800)
	_check(w800.full == 2 and w800.need == 2000, "800 in: two full steps")
	var w8800 := Wish.where(catalog, 8800)
	_check(w8800.full == 4 and w8800.done, "8,800 in: the jar is full")
	_check(Wish.can_wish(catalog, "part:pattern:spots") and Wish.can_wish(catalog, "part:accessory:none") and Wish.can_wish(catalog, "part:body:bunny"), "parts can be wished for")
	_check(not Wish.can_wish(catalog, "finish:blob:shiny") and not Wish.can_wish(catalog, "part:pattern:nope") and not Wish.can_wish(catalog, ""), "finishes and unknown looks can't")

	# rarity never moves: the tier shares are the same with heavy wishes on
	var heavy := { "part:pattern:spots": 4.0, "part:body:bunny": 4.0, "part:eyes:sleepy": 4.0, "part:palette:toxic": 4.0, "part:accessory:crown": 4.0, "part:body:fox": 4.0 }
	for box_id in ["starter", "sunset"]:
		var plain := _wish_roll(catalog, box_id, {}, 20000, 11)
		var wished := _wish_roll(catalog, box_id, heavy, 20000, 11)
		var worst := 0.0
		for t in catalog.tiers:
			worst = maxf(worst, absf(float(plain.tiers.get(t.id, 0)) - float(wished.tiers.get(t.id, 0))) / 20000.0)
		_check(worst < 0.015, "%s box: wishes don't move rarity (worst tier differs by %.2f%%)" % [box_id, worst * 100.0])
		for p in wished.bad:
			_check(false, "a wished pet's parts still fit its rarity: %s" % p)
	# the weight works inside the tier: spots among the common patterns
	var none := _wish_roll(catalog, "starter", {}, 20000, 5)
	var spots := _wish_roll(catalog, "starter", { "part:pattern:spots": 4.0 }, 20000, 5)
	var share0: float = float(none.looks.get("part:pattern:spots", 0)) / (none.looks.get("part:pattern:spots", 0) + none.looks.get("part:pattern:plain", 0))
	var share4: float = float(spots.looks.get("part:pattern:spots", 0)) / (spots.looks.get("part:pattern:spots", 0) + spots.looks.get("part:pattern:plain", 0))
	_check(absf(share0 - 0.5) < 0.03 and absf(share4 - 0.8) < 0.04, "spots x4: its share of the common patterns goes 50%% to 80%% (%.3f to %.3f)" % [share0, share4])
	# a look alone in its tier (the only rare body) turns up more on rare pets, through the signature slot
	var bunny := _wish_roll(catalog, "starter", { "part:body:bunny": 4.0 }, 20000, 7)
	var b0 := float(none.rare_bunny) / maxi(1, none.tiers.get("rare", 0))
	var b4 := float(bunny.rare_bunny) / maxi(1, bunny.tiers.get("rare", 0))
	_check(b4 > b0 * 1.5, "bunny x4 turns up more on rare pets (%.3f to %.3f)" % [b0, b4])
	# no wish: exactly the same rolls as before for the same seed
	var r1 := RandomNumberGenerator.new()
	r1.seed = 99
	var r2 := RandomNumberGenerator.new()
	r2.seed = 99
	var a := PetRoller.new(catalog, r1)
	var b := PetRoller.new(catalog, r2)
	b.wish = { "part:pattern:spots": 2.0 }
	b.wish = {}
	var same := true
	for i in 300:
		var pa := a.roll("sunset")
		var pb := b.roll("sunset")
		same = same and pa.parts == pb.parts and pa.rarity == pb.rarity and pa.finish == pb.finish
	_check(same, "no wish rolls exactly as before")
	# weights: only looks with a full step, by step
	var ws := Wish.fresh()
	ws.jars["part:pattern:spots"] = { "sent": 800, "dots": [] }
	ws.jars["part:eyes:happy"] = { "sent": 150, "dots": [] }
	var wt := Wish.weights(catalog, ws)
	_check(wt.size() == 1 and is_equal_approx(float(wt.get("part:pattern:spots", 0.0)), 2.0), "two full steps weigh x2, a jar without a full step nothing (%s)" % [wt])
	var clean := Wish.clean(catalog, { "on": "finish:blob:shiny", "jars": { "part:pattern:spots": { "sent": 99999, "dots": ["mint", "nope"] }, "bogus": { "sent": 5 } } })
	_check(clean.on == "" and clean.jars.size() == 1 and clean.jars["part:pattern:spots"].sent == 8800 and clean.jars["part:pattern:spots"].dots == ["mint"], "clean keeps only real looks, within a jar (%s)" % [clean])

	# GameState: hidden until the box tables, resting herd pets only, they never come back
	var GS: GDScript = load("res://scripts/game_state.gd")
	GS.testing = true
	var gs: Node = GS.new()
	var c: Collection = gs.collection
	var popped: Array = []
	gs.unlocked.connect(func(e): popped.append(e.id))
	gs.debug_give_pets(40)
	c.add_plain("common:normal", 400)
	c.add_plain("common:shiny", 20)
	c.add_plain("rare:normal", 30)
	gs.coins = 10000000000
	gs.check_unlocks()
	_check(not gs.wish_open(), "the jar is hidden before the box tables")
	_check(not gs.set_wish("part:pattern:plain"), "no wishing before the jar")
	gs.automation.taught["boxes"] = true
	_check(gs.teach_others("boxes"), "the others learn to open boxes")
	_check(gs.wish_open() and "wish" in popped, "teaching the others to open boxes brings the jar (%s)" % [popped])
	var spots_key := "part:pattern:spots"
	if c.times_seen(spots_key) == 0:
		c.see(spots_key)
	_check(not gs.set_wish("part:pattern:nope") and not gs.set_wish("finish:blob:normal"), "only a real part can be wished for")
	_check(gs.set_wish(spots_key) and gs.wish.on == spots_key, "wishing for spots")
	# who can go: the shared rule (GameState.spare_pick), resting pets first
	var active: Pet = c.active()
	gs.unlocks["feature:errands"] = true
	gs.put_on_job("coin_hunt", 100)
	var on_job: int = gs.job_size("coin_hunt")
	var shelves: Dictionary = gs.wish_shelves()
	_check(shelves.keys().all(func(r): return int(shelves[r].n) == int(gs.spare_pick(str(r)).n)), "a shelf holds its rarity's pets that may go (%s)" % [shelves.keys()])
	var face: Pet = shelves.common.first
	_check(face != null and face.rarity == "common" and face.finish == "normal", "the shelf's face is a plain common (normal finishes go first)")
	var cards := c.pets.size()
	var commons_free := int(shelves.common.n)
	var stars: int = c.fallen_n
	var shiny_before: int = c.herd_count("common:shiny")
	var sent: Dictionary = gs.send_to_wish("common", 10)
	_check(sent.sent == 10 and c.pets.size() == cards, "sending 10 takes 10 from the resting count first (%d)" % sent.sent)
	_check(c.fallen_n == stars + 10, "they never come back: 10 new stars")
	_check(c.herd_count("common:shiny") == shiny_before, "the plainest finish goes first (the shinies stay)")
	_check(Wish.sent(gs.wish, spots_key) == 10 and gs.wish.jars[spots_key].dots.size() == 10, "the jar counts them and keeps their colours")
	_check(gs.job_size("coin_hunt") == on_job and c.active() == active, "pets on errands and the active pet stay")
	_check(int(gs.wish_shelves().common.n) == commons_free - 10, "the shelf has 10 fewer")
	# a full step: the roller learns the wish
	_check(gs._roller.wish.is_empty(), "no full step yet: the boxes roll as always")
	var steps: Array = []
	gs.wish_changed.connect(func(step): steps.append(step))
	var more: Dictionary = gs.send_to_wish("common", 190)
	_check(more.before == 0 and more.after == 1 and steps == [1], "200 in: the first step fills (%s)" % [steps])
	_check(is_equal_approx(float(gs._roller.wish.get(spots_key, 0.0)), 1.5), "one full step: spots weighs x1.5 in every box (%s)" % [gs._roller.wish])
	# switching keeps the old jar's steps (and its weight)
	var sleepy := "part:eyes:sleepy"
	if c.times_seen(sleepy) == 0:
		c.see(sleepy)
	gs.set_wish(sleepy)
	_check(Wish.sent(gs.wish, spots_key) == 200 and Wish.sent(gs.wish, sleepy) == 0, "switching keeps spots' 200")
	_check(gs._roller.wish.has(spots_key), "spots keeps its boost after switching")
	gs.set_wish(spots_key)
	_check(int(Wish.where(catalog, Wish.sent(gs.wish, spots_key)).full) == 1, "switching back: one step still full")
	# the cap: never more than a whole jar
	gs.debug_wish(spots_key, 8795)
	var last: Dictionary = gs.send_to_wish("common", -1)
	_check(last.sent == 5 and Wish.sent(gs.wish, spots_key) == 8800 and last.after == 4, "the last 5 fill the jar and no more (%d)" % last.sent)
	_check(gs.send_to_wish("common", 10).sent == 0, "a full jar takes nobody")
	# the save keeps it; an old save starts with an empty jar
	var path := DevProfile.path("wish_save.json") if DevProfile.active() else "user://wish_test_save.json"
	gs.save_path = path
	gs._can_save = true
	gs.save_game()
	var gs2: Node = GS.new()
	gs2.save_path = path
	gs2.load_game()
	_check(gs2.wish.on == spots_key and Wish.sent(gs2.wish, spots_key) == 8800 and Wish.sent(gs2.wish, sleepy) == 0, "a save round trip keeps the wish and its jar")
	_check(is_equal_approx(float(gs2._roller.wish.get(spots_key, 0.0)), 4.0), "a loaded game rolls with the jar's weight (%s)" % [gs2._roller.wish])
	_check(gs2.wish_open(), "the jar stays open after loading")
	SaveFile.write(path, { "version": 37, "collection": { "seen": {} }, "unlocks": [] })
	var gs3: Node = GS.new()
	gs3.save_path = path
	gs3.load_game()
	_check(gs3.wish.on == "" and gs3.wish.jars.is_empty() and gs3._roller.wish.is_empty() and not gs3.wish_open(), "a v37 save starts with no wish and no jar")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
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
	_test_auto_stand_ins(catalog)
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
	for pet in batch:
		pet.fav = true  # favourites never fold into the herd: these tests follow pets by uid (the herd has its own)
	var c := Collection.new()
	c.add(batch)
	c.set_active("1")
	return c.to_dict()


## A save shaped like `version` wrote it (21 and up): 30 pets well into the game, the machine
## fully fixed, the automation tab open, errands going. v22 added gear, v23 scout notes, v24 stickers,
## v25 the box reserve in capsules, v26 box tiers (boxes_bought, boxes_greeted), v27 the whistle
## (automation.whistle; older ones have none). None has machine globes (v30): they load with the first.
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
	if version >= 26:
		d.boxes_bought = {}
		d.boxes_greeted = []
	if version < 27:
		d.automation.erase("whistle")
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


## A save as it is on disk, minus when it was written and when the next present comes (the present
## clock starts on load from the clock on the wall), to compare two saves.
func _same_save(a: Dictionary, b: Dictionary) -> bool:
	var x := a.duplicate(true)
	var y := b.duplicate(true)
	for s in [x, y]:
		s.erase("saved_at")
		if s.get("gifts") is Dictionary:
			s.gifts.erase("next_at")
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
	_check(float(gs.gifts.next_at) > Time.get_unix_time_from_system() and gs.gifts_waiting() == 0,
		"an old save (before v29) with the boxes tab open starts the present clock on load, nothing waiting yet")
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
	# v26: box tiers. A v25 save's lucky boxes are sunset boxes, and what's on its pile isn't "new!"
	var lucky25 := _old_save(25)
	lucky25.bag = { "starter": 2, "lucky": 3 }
	lucky25.saved_boxes = ["lucky"]
	var gs25 = _state_from(lucky25)
	_check(gs25.in_bag("sunset") == 3 and gs25.in_bag("lucky") == 0 and gs25.saved_boxes.has("sunset"),
		"a v25 save's lucky boxes load as sunset boxes (%s)" % [gs25.bag])
	_check(gs25.boxes_bought.has("sunset") and gs25.boxes_bought.has("starter"), "a v25 save's piles count as bought")
	gs25.free()
	var v26 := _old_save(26)
	v26.boxes_bought = { "starter": 7 }
	v26.boxes_greeted = ["sunset"]
	var gs26 = _state_from(v26)
	_check(int(gs26.boxes_bought.get("starter", 0)) == 7 and gs26.boxes_greeted.has("sunset") and not gs26.boxes_bought.has("sunset"),
		"a v26 save keeps what it bought and greeted (%s, %s)" % [gs26.boxes_bought, gs26.boxes_greeted.keys()])
	gs26.free()
	# v27: the whistle. A v26 save has none: every tick on, the default set aside, not taught
	var w26 = _state_from(_old_save(26))
	_check(w26.automation.whistle == Automation.whistle_fresh() and not w26.automation.taught.has("whistle"),
		"a v26 save starts the whistle fresh (%s)" % [w26.automation.whistle])
	_check(Automation.tick(w26.automation, "machine", "haul") and Automation.tick(w26.automation, "machine", "fill"), "and every tick is on")
	w26.free()
	var v27 := _old_save(27)
	v27.unlocks = v27.unlocks + ["feature:whistle"]
	v27.automation.task = "whistle"
	v27.automation.whistle = { "ticks": { "machine": { "haul": false } }, "keep": 3, "wait": 0.5 }
	var gs27 = _state_from(v27)
	_check(gs27.automation.task == "whistle" and gs27.automation.taught.has("whistle") and not Automation.tick(gs27.automation, "machine", "haul")
		and Automation.tick(gs27.automation, "machine", "fill") and int(gs27.automation.whistle.keep) == 3,
		"a v27 save keeps its pet managing, its ticks and set aside (%s)" % [gs27.automation.whistle])
	gs27.free()
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
	# the running game works the crank and the workers' boxes on frames apart (_process): each keeps
	# its own clock, so neither loses time to the other
	gs = _crank_state(0, 3, 0, -60.0)
	var t0 := Time.get_unix_time_from_system() - 10.0
	gs._auto_at = t0
	gs._boxes_at = t0
	gs._work_automation(t0 + 1.0, "crank")
	_check(is_equal_approx(gs._auto_at, t0 + 1.0) and is_equal_approx(gs._boxes_at, t0), "the crank's frame leaves the boxes' clock alone")
	gs._work_automation(t0 + 1.25, "boxes")
	_check(is_equal_approx(gs._boxes_at, t0 + 1.25) and is_equal_approx(gs._auto_at, t0 + 1.0), "the boxes' frame works their own 1.25 s")
	gs._work_automation(t0 + 2.0)
	_check(is_equal_approx(gs._auto_at, t0 + 2.0) and is_equal_approx(gs._boxes_at, t0 + 2.0), "working everything at once moves both clocks")
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


## Auto parties from the herd: each count offers a few stand-ins at a time (10), so 20 parties in
## one go look up fresh ones when they run low (never the same pet twice, never a leader).
func _test_auto_stand_ins(_catalog: Catalog) -> void:
	var d := _old_save(gs_version(), 10)
	d.collection.herd = { "common:normal": 300 }
	var all := { "adventures": true }
	d.automation = { "taught": all, "others": all, "spots": { "adventures": 20 } }
	var gs = _state_from(d)
	_check(gs.collection.herd_total() == 300, "300 plain pets in the herd (%d)" % gs.collection.herd_total())
	_check(gs.put_workers("adventures", -1) == 20, "20 party leaders")
	for slot in 20:
		gs.set_auto_party("meadow", 3, slot)
	gs._work_automation(Time.get_unix_time_from_system())
	var auto_runs: Array = gs.runs.filter(func(r): return r.auto)
	var leaders := {}
	for uid in gs.workers_of("adventures"):
		leaders[str(uid)] = true
	var went := {}
	var twice := 0
	var stand_ins := 0
	for r in auto_runs:
		for uid in r.party.uids:
			twice += 1 if went.has(uid) or leaders.has(uid) else 0
			went[uid] = true
			stand_ins += 1 if Herd.is_stand_in(uid) else 0
	_check(auto_runs.size() == 20 and auto_runs.all(func(r): return r.party.setting_out() == 3),
		"20 full parties of 3 set out from the herd (%d)" % auto_runs.size())
	_check(twice == 0 and went.size() == 60 and stand_ins == 60, "60 different stand-ins, none twice (%d, %d stand-ins, %d twice)" % [went.size(), stand_ins, twice])
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
	var old := { "version": 27, "coins": 1000000000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "tab:automation"], "jobs_auto": true, "room": 0,
		"collection": { "pets": pets, "herd": { "common:normal": 471 }, "active": "1", "next_id": 31, "seen": {} },
		"jobs": { "coin_hunt": { "crew": [], "herd": { "common:normal": 100 }, "fill": 0.0 } } }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(gs.job_joins("coin_hunt"), "an old save with sharing on: new pets join every open errand")
	# a save from before the room gets room for its pets and some more, so its room isn't full: no stall yet
	_check(not gs.room_is_full() and gs.room_cap() >= c.plain_count() * 1.1 and not gs.homes_open(),
		"an old save gets room for its pets, the stall waits (%d / %d)" % [c.plain_count(), gs.room_cap()])
	gs.room = 0  # the first room, exactly full: the next opening that bumps into it opens the stall
	gs.bag["starter"] = 1
	_check(gs.room_is_full() and gs.open_boxes("starter", 1).is_empty() and gs.homes.room_was_full and gs.homes_open(),
		"a full room stops a box and opens the stall (%d / %d)" % [c.plain_count(), gs.room_cap()])
	gs.bag.erase("starter")
	_check(not gs.feature_on("sorting") and not gs.homes.rule.on, "the sorting card waits (and starts off)")
	# who goes, and in what order: resting before working, never the ones that always stay
	var resting: int = gs.resting_count() - 3  # the favourite, the new part and the holo rest too, but stay
	var plan: Dictionary = gs.spare_pick("common", resting + 5)
	_check(Herd.total(plan.work) + plan.cards.filter(func(u): return gs.job_of(u) != "").size() == 5, "resting pets go first, then 5 from work")
	var every: Dictionary = gs.spare_pick("common")
	var keep := ["1", "2", "3", "4"]  # active, favourite, new part, holo
	_check(not every.cards.any(func(u): return u in keep), "never the active pet, a favourite, a new part or holo")
	# the keep line (the sorting card's "keep ‹holo› and up") keeps pets everywhere, the rule on or off
	gs.set_rule("keep", "ghost")
	var with_holo: Dictionary = gs.spare_pick("common")
	_check("4" in with_holo.cards and not with_holo.cards.any(func(u): return u in ["1", "2", "3"]),
		"the keep line at ghost: holo may go, never the active pet, a favourite or a new part")
	_check(int(gs.spare_shelves().common.n) == int(with_holo.n), "the shelves count what may go (%d)" % int(with_holo.n))
	_check(int(gs.spare_shelves().common.working) == int(with_holo.working), "... and how many of them work (%d, the shelf says %d)" % [int(with_holo.working), int(gs.spare_shelves().common.working)])
	gs.set_rule("keep", "shiny")
	_check(not gs.may_go_finish("shiny") and gs.may_go_finish("normal") and not gs.spare_pick("common").cards.has("4"), "the keep line at shiny: shinies and holo stay")
	gs.set_rule("keep", "holo")
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
	# only the newest few wait: a pinned pet can't fold or leave, so a pile of them filled the room
	gs.pinned.clear()
	var many: Array[String] = []
	for i in gs.PINNED_MAX + 25:
		many.append("p%d" % i)
	gs._pin(many)
	_check(gs.pinned == many.slice(25), "only the newest %d good pulls wait to be seen (%d)" % [gs.PINNED_MAX, gs.pinned.size()])
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
	# "up to" a rarity: rarer new pets rest (for the army, the edge...)
	gs.set_job_join("coin_hunt", true)
	gs.set_join_up_to("common")
	var hunt2: int = gs.job_size("coin_hunt")
	var rares0: int = int(gs.resting_shelves().get("rare", 0)) + gs.resting_cards().filter(func(p): return p.rarity == "rare").size()
	var roller := PetRoller.new(catalog)
	var new_ones: Array[Pet] = []
	for i in 3:
		new_ones.append(roller.roll("starter", "common"))
		new_ones.append(roller.roll("starter", "rare"))
	c.add(new_ones)
	var rares1: int = int(gs.resting_shelves().get("rare", 0)) + gs.resting_cards().filter(func(p): return p.rarity == "rare").size()
	_check(gs.job_size("coin_hunt") == hunt2 + 3 and rares1 == rares0 + 3, "up to common: the commons join, the rares rest (%d, %d)" % [gs.job_size("coin_hunt") - hunt2, rares1 - rares0])
	gs.set_join_up_to("nope")
	_check(gs.join_up_to == "common", "only a real rarity")
	gs.save_game()
	var gs3: Node = load("res://scripts/game_state.gd").new()
	_check(gs3.join_up_to == "common", "\"up to\" loads back (%s)" % gs3.join_up_to)
	gs3.free()
	gs.set_join_up_to("")
	gs.set_job_join("coin_hunt", false)
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


## The herd next to what came before it: the kitchen and its cooks, the whistle, the workers' count
## (the whistle's find), sunset boxes and the room, and sharing out from a v27 save.
func _test_herd_with_the_rest(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the herd with the rest: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var roller := PetRoller.new(catalog, rng)
	var pets := []
	for i in 300:
		var p := roller.roll("starter", "common")
		p.finish = "normal"
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	var auto := Automation.fresh()
	auto.erase("whistle")
	auto.taught = { "machine": true }
	auto.others = { "machine": true }
	auto.spots = { "machine": 60 }
	auto.workers = { "machine": range(2, 42).map(func(n): return str(n)) }
	var old := { "version": 27, "coins": 100000000000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "tab:automation", "job:kitchen", "job:scouting", "job:lemonade"],
		"jobs_auto": true, "collection": { "pets": pets, "active": "1", "next_id": 301, "seen": {} }, "automation": auto }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(gs.job_joins("coin_hunt") and gs.job_joins("lemonade") and not gs.job_joins("kitchen") and not gs.job_joins("scouting"),
		"a v27 save sharing out: new pets join the errands it shared out to, never the kitchen or scouting")
	gs.set_job_join("kitchen", true)
	_check(not gs.job_joins("kitchen"), "the kitchen never gets the switch (you staff it)")
	_check(c.herd_total() > 200 and gs.workers_count("machine") == 40 and gs.workers_total() == 40,
		"folded workers still count as workers (%d, the whistle's find looks at it)" % gs.workers_total())
	# the kitchen with cooks from the herd
	gs.put_on_job("coin_hunt", 50)
	var plain_rate: float = gs.job_rate("coin_hunt")
	gs.put_on_job("kitchen", 20)
	_check(gs.job_size("kitchen") == 20 and Herd.total(gs.job_herd("kitchen")) > 0, "cooks come from the herd (%d)" % gs.job_size("kitchen"))
	_check(gs.kitchen_bonus() > 0.0 and gs.job_rate("coin_hunt") > plain_rate, "a kitchen of counts speeds the coin hunt (%.3f)" % gs.kitchen_bonus())
	gs.share_out()
	_check(gs.job_size("kitchen") == 20 and gs.job_size("scouting") == 0 and gs.resting_count() == 0, "sharing out the herd skips the kitchen and scouting")
	gs.take_off_job("coin_hunt", -1)
	gs.take_off_job("lemonade", -1)
	# the whistle fills the empty machines from the herd
	gs.unlocks["feature:whistle"] = true
	gs.automation.taught["whistle"] = true
	gs.automation.task = "whistle"
	var rest0: int = gs.resting_count()
	var work0: int = gs.workers_count("machine")
	gs._whistle_checks(1)
	var put: int = gs.workers_count("machine") - work0
	_check(put > 0 and gs.resting_count() == rest0 - put and Herd.total(gs.workers_herd("machine")) > 0,
		"the whistle puts resting pets from the herd on the machines (%d)" % put)
	# sunset boxes and the room: a box counts as its most pets
	gs.automation.task = ""
	gs.room = 0
	c.add_plain("common:normal", maxi(0, gs.room_cap() - c.plain_count() - 5))
	_check(gs.room_left() == 5 and gs.boxes_that_fit("sunset") == 2 and gs.boxes_that_fit("starter") == 5,
		"5 spaces take 2 sunset boxes or 5 sunny ones (%d)" % gs.room_left())
	gs.bag["sunset"] = 10
	var got: Array = gs.open_boxes("sunset", 10)
	_check(gs.in_bag("sunset") == 8 and got.size() >= 4 and got.size() <= 6, "opening 10 sunset boxes with room for 5 opens 2 (%d pets)" % got.size())
	gs.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Care (data/care.json, Care): food and mood are buffs, only drain while open, snacks cost capsules.
func _test_care(catalog: Catalog) -> void:
	var line := float(Care.buff_of(catalog, "food").above)
	_check(line == 70.0 and float(Care.buff_of(catalog, "mood").above) == 70.0, "both care lines are at 70")
	var coins71 := Care.parts(catalog, "coins", 71.0, 20.0)
	_check(coins71.size() == 1 and coins71[0].source == "care" and coins71[0].id == "full_tummy" and is_equal_approx(float(coins71[0].x), 1.2),
		"food 71 is a full tummy: coins x1.2")
	_check(Care.parts(catalog, "coins", 70.0, 100.0).is_empty(), "food 70 is no bonus (strictly above the line)")
	var luck := Care.parts(catalog, "luck", 20.0, 71.0)
	_check(luck.size() == 1 and luck[0].id == "happy" and is_equal_approx(float(luck[0].x), 1.1), "mood 71 is happy: luck x1.1")
	_check(Care.parts(catalog, "luck", 100.0, 70.0).is_empty(), "a full tummy isn't luck")
	for k in Boosts.kinds(catalog):
		if k != "coins" and k != "luck":
			_check(Care.parts(catalog, k, 100.0, 100.0).is_empty(), "care doesn't boost %s" % k)
	for b in catalog.care.buffs:
		_check(Boosts.is_kind(catalog, str(b.kind)) and str(b.name) != "", "care buff %s has a real kind and a name" % b.id)
	_check("care" in catalog.boosts.sources, "care is a boost source")
	var kitchen: Dictionary = catalog.job("kitchen")
	_check(float(kitchen.meal_upto) <= line, "the kitchen alone never gives a full tummy (meal_upto %s)" % kitchen.meal_upto)
	_check(is_equal_approx(Care.drain(catalog, "food", 50.0, 3600.0), 25.0), "food drains 25 an hour (full to the floor in about 4 h)")
	_check(Care.drain(catalog, "food", 22.0, 3600.0) == 20.0, "food never drains below the floor")
	_check(Care.line(catalog, "food") == line and Care.line(catalog, "mood") == float(Care.buff_of(catalog, "mood").above),
		"each bar's mark sits at its own buff's line")
	_check(not catalog.care.has("tick"), "no separate tick number to drift from the buff lines")
	_check(Care.crossed(catalog, 71.0, 50.0, 69.0, 50.0) and Care.crossed(catalog, 50.0, 69.0, 50.0, 71.0)
		and not Care.crossed(catalog, 90.0, 90.0, 80.0, 80.0), "crossing a line is noticed, moving above it isn't")

	var GS: GDScript = load("res://scripts/game_state.gd")
	GS.testing = true
	var gs: Node = GS.new()
	_check(gs.hunger <= line and gs.happiness <= line, "a new game starts without a care buff")
	var base: float = gs.boost("coins")
	gs.hunger = 70.003
	gs._check_care()
	_check(is_equal_approx(gs.boost("coins"), base * 1.2), "the coins boost goes up once food passes 70 (%.3f)" % gs.boost("coins"))
	gs._process(1.0)  # drains below 70 again
	_check(gs.hunger < line and is_equal_approx(gs.boost("coins"), base), "and back down when it drains under (%.3f)" % gs.boost("coins"))
	# snacks
	gs.coins = 100
	gs.hunger = 40.0
	var price: int = gs.snack_price()
	_check(price == 3, "a snack costs 3 capsules at the start (%d)" % price)
	_check(gs.feed() and gs.coins == 100 - price and is_equal_approx(gs.hunger, 70.0), "a snack costs its price and gives 30 food")
	gs.hunger = float(catalog.care.snack.full_at)
	_check(not gs.feed() and gs.coins == 100 - price, "a full pet takes no snack (food %s)" % catalog.care.snack.full_at)
	gs.hunger = 40.0
	gs.coins = price - 1
	_check(not gs.feed() and gs.hunger == 40.0, "no snack without the coins")
	gs.machine.bought["tape"] = 1  # x2 coins a capsule
	_check(gs.snack_price() == 6, "the snack price follows the machine's coin value (%d)" % gs.snack_price())
	# pats: mood, but not more often than pat.every
	gs.happiness = 40.0
	gs.pat()
	var pat_mood := float(catalog.care.pat.mood)
	_check(is_equal_approx(gs.happiness, 40.0 + pat_mood), "a pat gives %s mood" % pat_mood)
	gs.pat()
	_check(is_equal_approx(gs.happiness, 40.0 + pat_mood), "a second pat right away gives no mood")
	gs._pat_at -= float(catalog.care.pat.every)
	gs.pat()
	_check(is_equal_approx(gs.happiness, 40.0 + pat_mood * 2.0), "after pat.every seconds a pat gives mood again")
	# the buffs only count while the game is open: none while loading or working through a sleep
	gs.hunger = 90.0
	gs.happiness = 90.0
	gs._check_care()
	_check(gs.boost_parts("coins").any(func(p): return p.source == "care"), "open, a full tummy is a coins part")
	var seen := []
	gs._without_care(func(): seen.append(gs.boost("coins")))
	_check(is_equal_approx(seen[0], base) and is_equal_approx(gs.boost("coins"), base * 1.2),
		"time the computer slept works without the buff, and it's back after (%.3f, %.3f)" % [seen[0], gs.boost("coins")])
	gs._loading = true
	_check(not gs.boost_parts("coins").any(func(p): return p.source == "care"), "time closed (loading) works without the buff")
	gs._loading = false
	# no trickle; a long frame gap drains nothing
	gs.coins = 50
	gs.hunger = 60.0
	gs.happiness = 60.0
	for i in 60:
		gs._process(1.0)
	_check(gs.coins == 50, "a minute open with nothing going on brings no coins (%d)" % gs.coins)
	_check(gs.hunger < 60.0 and gs.happiness < 60.0, "food and mood drain while the game is open")
	var was: float = gs.hunger
	gs._process(10.0)
	_check(gs.hunger == was, "a 10 s frame gap (the computer slept) drains nothing")
	# closed: nothing drains, no coins
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://profiles/test-core/"))
	var path := "user://profiles/test-core/care_save.json"
	gs.save_path = path
	gs._can_save = true
	gs.hunger = 90.0
	gs.happiness = 90.0
	gs.save_game()
	var data := SaveFile.read(path)
	data.saved_at = float(data.saved_at) - 3600.0
	SaveFile.write(path, data)
	var gs2: Node = GS.new()
	gs2.save_path = path
	gs2.load_game()
	_check(is_equal_approx(gs2.hunger, 90.0) and is_equal_approx(gs2.happiness, 90.0), "an hour closed leaves food and mood as they were (%.1f, %.1f)" % [gs2.hunger, gs2.happiness])
	_check(gs2.coins == gs.coins, "an hour closed brings no trickle coins (%d vs %d)" % [gs2.coins, gs.coins])
	_check(is_equal_approx(gs2.boost("coins"), base * 1.2) and gs2.boost_parts("luck").any(func(p): return p.source == "care"),
		"a loaded full, happy pet has its buffs (coins %.3f)" % gs2.boost("coins"))
	for f in [path, path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	for n in [gs, gs2]:
		n.free()


## Quiet paws (QuietPaws, PawsView, data/care.json "paws", Settings.paws): out on your windows your
## pet acts out its job with poses only. The setting only changes what's drawn: never a second
## switch for opening boxes.
func _test_paws(catalog: Catalog) -> void:
	var cfg: Dictionary = catalog.care.get("paws", {})
	_check(float(cfg.get("hold", 0)) == 4.0 and (cfg.get("stint", []) as Array).size() == 2,
		"care.json has the paws block (a good pull held 4 s, stints)")
	# the setting: off / big things / everything, everything by default, kept in settings.json
	var S: GDScript = load("res://scripts/settings.gd")
	_check(S.PAWS_LEVELS == ["off", "big things", "everything"] and S.paws_from({}) == 2, "paws has 3 levels and starts at everything")
	_check(S.paws_from({ "paws": 9 }) == 2 and S.paws_from({ "paws": -3 }) == 0 and S.paws_from({ "paws": 1 }) == 1, "paws is kept to 0..2")
	var settings: Node = S.new()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://profiles/test-core/"))
	var spath := "user://profiles/test-core/paws_settings.json"
	settings.file_path = spath
	settings.set_value("paws", 1)
	_check(S.paws_from(SaveFile.read(spath)) == 1, "the paws setting survives a write and a read")
	settings.set_value("paws", 7)
	_check(settings.paws == 2, "set_value keeps paws in range")
	settings.free()
	for f in [spath, spath + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

	var GS: GDScript = load("res://scripts/game_state.gd")
	GS.testing = true
	var gs: Node = GS.new()
	gs.tutorial = "done"
	var roller := PetRoller.new(catalog)
	var good := roller.roll("starter", "rare")
	var plain := roller.roll("starter", "common")
	plain.finish = "normal"
	_check(gs.is_good_pull(good) and not gs.is_good_pull(plain), "a rare is a good pull, a plain common isn't")
	var waiting := RunState.new()
	waiting.status = RunState.Status.DONE
	var paws := QuietPaws.new(gs)
	# off: nothing, even with a good pull and a postcard waiting
	paws.step(0.1, true, true, true, 0)
	paws.opened(good)
	gs.runs.append(waiting)
	paws.step(0.1, true, true, true, 0)
	_check(paws.pose == QuietPaws.Pose.NONE and not paws.wants_still, "off: no poses at all")
	gs.runs.erase(waiting)
	# big things: a good pull held up 4 s, a foot tap for a waiting adventure, no boxes routine
	paws.step(0.1, true, true, true, 1)
	paws.opened(good)
	paws.step(0.1, true, false, true, 1)
	_check(paws.pose == QuietPaws.Pose.HOLD and paws.held == good and paws.wants_still, "big things: a good pull is held up, even mid-walk")
	for i in 37:
		paws.step(0.1, true, true, true, 1)
	_check(paws.pose == QuietPaws.Pose.HOLD, "still held up after 3.8 s")
	for i in 5:
		paws.step(0.1, true, true, true, 1)
	_check(paws.pose != QuietPaws.Pose.HOLD and paws.held == null, "and put down after 4 s")
	paws.opened(plain)
	paws.step(0.1, true, true, true, 1)
	_check(paws.pose == QuietPaws.Pose.NONE and paws.held == null, "an ordinary pull isn't held up")
	gs.runs.append(waiting)
	paws.step(0.1, true, true, true, 1)
	_check(paws.pose == QuietPaws.Pose.WAIT and paws.stint_left > 0.0, "a postcard waiting: it taps its foot")
	gs.runs.erase(waiting)
	var sent := RunState.new()
	sent.status = RunState.Status.DONE
	sent.auto = true
	gs.runs.append(sent)
	var quiet := QuietPaws.new(gs)
	quiet.step(0.1, true, true, true, 2)
	_check(quiet.pose == QuietPaws.Pose.NONE, "a trip your pet sent itself doesn't wait for you")
	gs.runs.erase(sent)
	# the boxes job: only at everything, following the background opening
	gs.automation.taught["boxes"] = true
	gs.set_task("boxes")
	for i in 20:
		gs.debug_give_box("starter")
	gs._pack_seen = 2.0
	gs._pack_timer = 0.8
	_check(gs.background_packing() >= 0.0, "the background opening is going")
	var big := QuietPaws.new(gs)
	big.step(0.1, true, true, true, 1)
	_check(big.pose == QuietPaws.Pose.NONE, "big things: no boxes routine")
	var all := QuietPaws.new(gs)
	all.step(0.1, true, true, false, 2)
	_check(all.pose == QuietPaws.Pose.NONE, "no stint on an edge without room for the pile")
	all.step(0.1, true, true, true, 2)
	_check(all.pose == QuietPaws.Pose.BOXES and all.phase == QuietPaws.Phase.REACH and all.wants_still, "everything: the boxes routine, facing the pile first")
	gs._pack_timer = 3.5
	all.step(0.1, true, true, true, 2)
	_check(all.phase == QuietPaws.Phase.HOLD, "then holding the pack")
	gs._pack_timer = 6.0
	all.step(0.1, true, true, true, 2)
	_check(all.phase == QuietPaws.Phase.SHAKE, "then shaking it")
	all.opened(plain)
	all.step(0.1, true, true, true, 2)
	_check(all.puff > 0.0 and all.held == plain and all.hop > 0.0, "a pop: puff, and the new pet hops off")
	gs.automation.taught["machine"] = true
	gs.set_task("machine")
	all.step(0.1, true, true, true, 2)
	_check(all.pose == QuietPaws.Pose.MACHINE, "on the crank job: the tiny machine")
	all.cranked({})
	_check(all.bounce == 1.0, "a crank bounces the machine")
	gs.runs.append(waiting)
	all.step(0.1, true, true, true, 2)
	_check(all.pose == QuietPaws.Pose.WAIT, "an adventure waiting beats the job")
	all.show_off(good)
	all.step(0.1, true, true, true, 2)
	_check(all.pose == QuietPaws.Pose.HOLD, "a good pull beats the foot tap")
	for i in 42:
		all.step(0.1, true, true, true, 2)
	_check(all.pose == QuietPaws.Pose.WAIT, "and after it, back to tapping")
	all.step(0.1, false, false, true, 2)
	_check(all.pose == QuietPaws.Pose.NONE and not all.wants_still, "dragged or falling: no poses")
	gs.runs.erase(waiting)
	# a hold cut short by a drag: a fresh hold on landing, unless it waited too long
	var paused := QuietPaws.new(gs)
	paused.show_off(good)
	for i in 10:
		paused.step(0.1, true, true, true, 1)
	for i in 20:
		paused.step(0.1, false, false, true, 1)
	paused.step(0.1, true, true, true, 1)
	_check(paused.pose == QuietPaws.Pose.HOLD and paused.hold_left() > 3.8, "a short drag: the good pull is held up again, 4 s from the landing")
	for i in 120:
		paused.step(0.1, false, false, true, 1)
	paused.step(0.1, true, true, true, 1)
	_check(paused.pose != QuietPaws.Pose.HOLD and paused.held == null, "a long drag: the good pull is let go (waited past hold_waits)")

	# not a second switch: the background opening opens just as many packs at every level
	var opened_at: Array[int] = []
	for level in 3:
		var g: Node = GS.new()
		g.tutorial = "done"
		g.automation.taught["boxes"] = true
		g.set_task("boxes")
		for i in 40:
			g.debug_give_box("starter")
		var p := QuietPaws.new(g)
		var before: int = g.in_bag("starter")
		var task_before: String = g.automation.task
		for i in 800:
			g._open_in_background(0.1)
			p.step(0.1, true, true, true, level)
		opened_at.append(before - g.in_bag("starter"))
		_check(g.background_packing() >= 0.0 and g.packs_on and g.automation.task == task_before,
			"level %d: the background opening keeps going (quiet paws never counts as seeing it)" % level)
		_check(g.pinned.size() == (g.idle_log.get("good", []) as Array).size(), "level %d: every good pull still waits for the home screen" % level)
		g.free()
	_check(opened_at[0] > 5 and opened_at[0] == opened_at[1] and opened_at[1] == opened_at[2], "the same packs get opened at off, big things and everything (%s)" % [opened_at])
	gs.pinned.append(good.uid)
	var pin_before: Array[String] = gs.pinned.duplicate()
	for level in [2, 0, 1, 2]:
		paws.step(0.1, true, true, true, level)
	_check(gs.automation.task == "machine" and gs.pinned == pin_before, "changing the level leaves the job and the pinned pulls alone")

	# the desktop pet on a pretend desktop (stage mode, nothing on the real one)
	gs.set_task("boxes")
	gs._pack_seen = 2.0
	gs._pack_timer = 1.0
	var stage := Control.new()
	stage.size = Vector2(920, 600)
	var src := StageSource.new()
	src.windows = [Rect2(100, 300, 500, 300)]
	src.home = Rect2(700, 440, 200, 160)
	var dp := DesktopPet.new()
	dp.source = src
	dp.stage = stage
	dp.paws = QuietPaws.new(gs)
	dp.paws_level = 2
	stage.add_child(dp)
	dp._ready()
	dp.drop_at(Vector2(260, 200))
	var frames := 0
	while dp._state != DesktopPet.State.IDLE and frames < 200:
		dp._process(0.05)
		frames += 1
	dp._process(0.05)
	_check(is_equal_approx(dp.position.y, 300.0), "the pet lands on the window's top edge (%s)" % dp.position)
	_check(dp.paws.pose == QuietPaws.Pose.BOXES, "and starts on its boxes routine there")
	var x0 := dp.position.x
	var moved := false
	for i in 200:
		dp._process(0.05)
		moved = moved or absf(dp.position.x - x0) > 0.1
	_check(not moved and dp.paws.pose == QuietPaws.Pose.BOXES, "it stays put for its work stint (10 s)")
	dp._state = DesktopPet.State.WALK
	dp._timer = 5.0
	dp.paws.show_off(good)
	dp._process(0.05)
	dp._process(0.05)
	var x1 := dp.position.x
	for i in 20:
		dp._process(0.05)
	_check(dp.paws.pose == QuietPaws.Pose.HOLD and dp._state == DesktopPet.State.IDLE and is_equal_approx(dp.position.x, x1),
		"a good pull stops it mid-walk to hold it up")
	var held_on := dp.position + dp._held.position
	_check(held_on.is_equal_approx(held_on.round()) and (dp._front.position + dp._front.held_at).is_equal_approx(held_on - dp.position),
		"the held pet sits on whole screen pixels, with its sparkles (%s)" % held_on)
	for i in 90:
		dp._process(0.05)
	gs.runs.append(waiting)
	dp._process(0.05)
	_check(dp.paws.pose == QuietPaws.Pose.WAIT and dp.facing() == 1, "an adventure waiting: it faces the corner panel (on its right)")
	src.home = Rect2(0, 440, 60, 160)
	dp._refresh_world()  # windows are read every POLL_INTERVAL
	dp._process(0.05)
	_check(dp.facing() == -1, "and turns when the corner panel is on its left")
	dp.drop_at(Vector2(dp.position.x, 150))
	dp._process(0.05)
	_check(dp.paws.pose == QuietPaws.Pose.NONE, "picked up or falling: no poses")
	dp.paws.show_off(good)
	dp._process(0.05)
	_check(dp.paws.pose == QuietPaws.Pose.NONE, "a good pull waits while it falls")
	frames = 0
	while dp._state == DesktopPet.State.FALL and frames < 200:
		dp._process(0.05)
		frames += 1
	dp._process(0.05)
	_check(dp.paws.pose == QuietPaws.Pose.HOLD, "and is held up once it lands")
	gs.runs.erase(waiting)
	dp.paws_level = 0
	var x2 := dp.position.x
	moved = false
	for i in 300:
		dp._process(0.05)
		moved = moved or absf(dp.position.x - x2) > 1.0
	_check(moved and dp.paws.pose == QuietPaws.Pose.NONE, "off: it walks around like before")
	# a narrow edge: the tiny machine's handle wouldn't fit beside it, so no stint there
	var reach_px := PawsView.widest() * 4 / 3.0
	_check(PawsView.widest() >= PawsView.reach(QuietPaws.Pose.BOXES) and reach_px > 88.0, "the room check fits the machine's handle (%.1f px)" % reach_px)
	gs._pack_seen = 2.0
	gs._pack_timer = 1.0
	var narrow := StageSource.new()
	narrow.windows = [Rect2(300, 300, 170, 300)]
	var dp2 := DesktopPet.new()
	dp2.source = narrow
	dp2.stage = stage
	dp2.paws = QuietPaws.new(gs)
	dp2.paws_level = 2
	stage.add_child(dp2)
	dp2._ready()
	dp2.drop_at(Vector2(385, 200))
	frames = 0
	while dp2._state != DesktopPet.State.IDLE and frames < 200:
		dp2._process(0.05)
		frames += 1
	dp2._process(0.05)
	_check(is_equal_approx(dp2.position.y, 300.0) and dp2.paws.pose == QuietPaws.Pose.NONE,
		"in the middle of a narrow edge (85 px each side): no pile, no machine")
	stage.free()

	# the settings row: hidden until there's something to act out (the flow clicks it)
	var fresh: Node = GS.new()
	fresh.tutorial = "pull"
	_check(fresh.tutorial_active() and not QuietPaws.has_something(fresh), "the out on your windows row is hidden in the tutorial with no job")
	fresh.automation.taught["boxes"] = true
	_check(QuietPaws.has_something(fresh), "it shows once your pet knows a job")
	fresh.automation.taught.clear()
	fresh.tutorial = "done"
	_check(QuietPaws.has_something(fresh), "and once adventures are open (after the tutorial)")
	fresh.free()
	gs.free()


## Presents (Gifts, data/gifts.json): one every 3 h of wall clock, a pocket of 3, from when the
## boxes tab opens; a box of the newest tier, sometimes 2, sometimes a toy as well; never bits or a
## pet. Out on your windows the pet digs one up and wears it until you tap it.
func _test_gifts(catalog: Catalog) -> void:
	var cfg: Dictionary = catalog.gifts
	_check(float(cfg.every) == 10800.0 and int(cfg.pocket) == 3 and float(cfg.first_after) == 10800.0,
		"gifts.json: one every 3 h, a pocket of 3, the first 3 h after the boxes tab opens")
	var h := 3600.0
	var t0 := 1_000_000.0
	# the clock
	var st := Gifts.fresh()
	_check(Gifts.tick(st, cfg, t0, false) == 0 and Gifts.tick(st, cfg, t0 + 50.0 * h, false) == 0 and float(st.next_at) == 0.0,
		"nothing before the boxes tab opens, not even the clock starting")
	Gifts.tick(st, cfg, t0, true)
	_check(is_equal_approx(float(st.next_at), t0 + 3.0 * h) and int(st.pocket) == 0, "the boxes tab opens: the clock starts, the first in 3 h")
	Gifts.tick(st, cfg, t0 + 2.99 * h, true)
	_check(int(st.pocket) == 0, "nothing at 2.99 h")
	_check(Gifts.tick(st, cfg, t0 + 3.0 * h, true) == 1 and int(st.pocket) == 1, "one at 3 h")
	Gifts.tick(st, cfg, t0 + 100.0 * h, true)
	_check(int(st.pocket) == 3, "the pocket stops at 3 however long it's been (%d)" % st.pocket)
	st.pocket = 2  # one taken out
	Gifts.tick(st, cfg, t0 + 102.9 * h, true)
	_check(int(st.pocket) == 2, "the next doesn't come before 3 h after one was taken out")
	Gifts.tick(st, cfg, t0 + 103.0 * h, true)
	_check(int(st.pocket) == 3, "and comes 3 h after")
	var back := { "next_at": t0 + 500.0 * h, "pocket": 0 }
	Gifts.tick(back, cfg, t0, true)
	_check(float(back.next_at) <= t0 + 3.0 * h, "a clock set backwards never holds a present back more than 3 h")
	Gifts.tick(back, cfg, t0 + 3.0 * h, true)
	_check(int(back.pocket) == 1, "and one comes on time after it")
	# open or closed pays the same
	var open_st := { "next_at": t0 + 3.0 * h, "pocket": 0 }
	for i in 36000:
		Gifts.tick(open_st, cfg, t0 + i + 1.0, true)
	var closed_st := { "next_at": t0 + 3.0 * h, "pocket": 0 }
	Gifts.tick(closed_st, cfg, t0 + 36000.0, true)
	_check(open_st == closed_st and int(closed_st.pocket) == 3, "10 h open in 1 s ticks == 10 h closed (%s vs %s)" % [open_st, closed_st])
	var clean := Gifts.clean({ "next_at": -5, "pocket": 99 }, cfg)
	_check(float(clean.next_at) == 0.0 and int(clean.pocket) == 3, "a saved pocket is kept to 0..3")
	_check(is_equal_approx(Gifts.per_day(cfg), 8.0), "8 presents a day at most")

	# GameState: opening presents
	var GS: GDScript = load("res://scripts/game_state.gd")
	GS.testing = true
	var gs: Node = GS.new()
	gs.tutorial = "done"
	_check(not gs.gifts_open(), "a new game has no presents (the boxes tab is closed)")
	gs._tick_gifts(Time.get_unix_time_from_system())
	_check(float(gs.gifts.next_at) == 0.0 and gs.gifts_waiting() == 0, "the clock waits for the boxes tab")
	gs.unlocks["tab:boxes"] = true
	gs._tick_gifts(Time.get_unix_time_from_system())
	_check(float(gs.gifts.next_at) > 0.0 and gs.gifts_waiting() == 0, "the boxes tab open: the clock starts")
	_check(gs.newest_box_id() == "starter" and not catalog.box(gs.newest_box_id()).is_empty(), "newest_box_id is the first tier while no other is in the shop")
	gs.debug_all_tiers = true
	var top := ""
	for b in catalog.shop_boxes():
		if top == "" or catalog.box_rank(str(b.id)) > catalog.box_rank(top):
			top = str(b.id)
	_check(gs.newest_box_id() == top and top != "starter", "with every tier in the shop, a present holds the newest (%s)" % gs.newest_box_id())
	gs.debug_all_tiers = false
	_check(gs.open_gift().is_empty(), "an empty pocket opens nothing")
	var pets_before: int = gs.collection.pets.size()
	var bits_before: Dictionary = gs.bits.duplicate()
	var boxes := 0
	var twos := 0
	var toys_seen := 0
	for i in 500:
		gs.gifts.pocket = 1
		var got: Dictionary = gs.open_gift()
		boxes += int(got.boxes)
		twos += 1 if int(got.boxes) == 2 else 0
		toys_seen += 0 if (got.toy as Dictionary).is_empty() else 1
		if got.box != gs.newest_box_id():
			_check(false, "a present holds the newest box (%s)" % got.box)
			break
	_check(gs.in_bag("starter") == boxes and gs.gifts_waiting() == 0, "the boxes land on the pile (%d)" % boxes)
	_check(gs.collection.pets.size() == pets_before and gs.bits == bits_before, "500 presents: never a pet, never bits")
	_check(toys_seen == 0 and gs.toys.owned.is_empty(), "no toy capsules before toys are open")
	_check(twos > 60 and twos < 140, "2 boxes about 1 in 5 (%d of 500)" % twos)
	gs.unlocks["feature:toys"] = true
	var toy_count := 0
	for i in 500:
		gs.gifts.pocket = 1
		toy_count += 0 if (gs.open_gift().toy as Dictionary).is_empty() else 1
	_check(toy_count > 60 and toy_count < 140 and not gs.toys.owned.is_empty(), "toys open: a toy capsule as well about 1 in 5 (%d of 500)" % toy_count)
	_check(gs.collection.pets.size() == pets_before and gs.bits == bits_before, "still never a pet or bits with toys")
	gs.gifts.pocket = 1
	gs.debug_gift_roll = "toy"
	var toy_gift: Dictionary = gs.open_gift()
	_check(int(toy_gift.boxes) == 1 and not (toy_gift.toy as Dictionary).is_empty(), "a toy comes with a box, not instead of it")
	gs.debug_set_gifts(9)
	_check(gs.gifts_waiting() == 3, "the dev step keeps the pocket to 3")
	# the save
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://profiles/test-core/"))
	var path := "user://profiles/test-core/gifts_save.json"
	gs.save_path = path
	gs._can_save = true
	gs.gifts = { "next_at": Time.get_unix_time_from_system() + 2.0 * h, "pocket": 1 }
	gs.save_game()
	var gs2: Node = GS.new()
	gs2.save_path = path
	gs2.load_game()
	_check(gs2.gifts_waiting() == 1 and absf(float(gs2.gifts.next_at) - float(gs.gifts.next_at)) < 1.0, "the pocket and the clock survive a save")
	var data := SaveFile.read(path)
	_check(int(data.version) == GS.SAVE_VERSION and data.has("gifts"), "the save has gifts (v%d)" % data.version)
	# closed for 10 h: the same as open
	data.gifts = { "next_at": float(data.saved_at) + 3.0 * h, "pocket": 0 }
	data.saved_at = float(data.saved_at) - 10.0 * h
	data.gifts.next_at = float(data.saved_at) + 3.0 * h
	SaveFile.write(path, data)
	var gs3: Node = GS.new()
	gs3.save_path = path
	gs3.load_game()
	_check(gs3.gifts_waiting() == 3, "10 h closed fills the pocket (%d)" % gs3.gifts_waiting())
	# an older save (v24) with the boxes tab open: the clock starts on load
	data.version = 24
	data.erase("gifts")
	SaveFile.write(path, data)
	var gs4: Node = GS.new()
	gs4.save_path = path
	gs4.load_game()
	_check(gs4.gifts_waiting() == 0 and float(gs4.gifts.next_at) > Time.get_unix_time_from_system() + 2.9 * h,
		"a v24 save loads with a fresh clock (the first in 3 h)")
	for f in [path, path + ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(f))

	# quiet paws: digging one up
	gs.gifts.pocket = 1
	var paws := QuietPaws.new(gs)
	paws.step(0.1, true, true, true, 2, false)
	_check(paws.pose != QuietPaws.Pose.DIG, "no dig on the bottom of the screen")
	paws.step(0.1, true, true, true, 0, true)
	_check(paws.pose != QuietPaws.Pose.DIG and not paws.worn, "no dig at off")
	paws.step(0.1, true, false, true, 1, true)
	_check(paws.pose != QuietPaws.Pose.DIG, "no dig mid-walk")
	paws.step(0.1, true, true, true, 1, true)
	_check(paws.pose == QuietPaws.Pose.DIG and paws.wants_still, "big things, standing on a window edge with a present: it digs")
	for i in 20:
		paws.step(0.1, true, true, true, 1, true)
	_check(paws.worn and paws.pose != QuietPaws.Pose.DIG, "after 1.6 s it wears the present")
	var roller := PetRoller.new(catalog)
	paws.show_off(roller.roll("starter", "rare"))
	paws.step(0.1, true, true, true, 1, true)
	_check(paws.pose == QuietPaws.Pose.HOLD and paws.worn, "a good pull is held up with the present still on")
	var beat := QuietPaws.new(gs)
	beat.show_off(roller.roll("starter", "rare"))
	beat.step(0.1, true, true, true, 2, true)
	_check(beat.pose == QuietPaws.Pose.HOLD, "a good pull beats a dig")
	gs.gifts.pocket = 0
	paws.step(0.1, true, true, true, 1, true)
	_check(not paws.worn, "the pocket emptied on the home tab: the present on its head is gone")
	var cut := QuietPaws.new(gs)
	gs.gifts.pocket = 1
	cut.step(0.1, true, true, true, 2, true)
	cut.step(0.1, false, false, true, 2, true)
	_check(cut.pose == QuietPaws.Pose.NONE and cut.dig_left == 0.0 and not cut.worn, "picked up mid-dig: the dig stops")
	# the desktop pet: a tap opens the present instead of a pat
	var stage := Control.new()
	stage.size = Vector2(920, 600)
	var src := StageSource.new()
	src.windows = [Rect2(100, 300, 500, 300)]
	var dp := DesktopPet.new()
	dp.source = src
	dp.stage = stage
	dp.paws = QuietPaws.new(gs)
	dp.paws_level = 1
	stage.add_child(dp)
	dp._ready()
	dp.drop_at(Vector2(260, 200))
	var frames := 0
	while not dp.paws.worn and frames < 400:
		dp._process(0.05)
		frames += 1
	_check(dp.paws.worn and is_equal_approx(dp.position.y, 300.0), "the desktop pet lands on the window and digs the present up")
	var r0: Rect2 = dp._body_rect()
	_check(r0.size.y > PetView.size_for(4).y + PawsView.PRESENT_H * 3.0, "the present on its head is part of what you can tap")
	gs.happiness = 40.0
	gs._pat_at = -INF
	var in_bag: int = gs.in_bag("starter")
	dp.tap()
	_check(gs.gifts_waiting() == 0 and gs.in_bag("starter") > in_bag and gs.happiness == 40.0 and not dp.paws.worn and dp.paws.pop > 0.0,
		"a tap while it wears one opens the present (not a pat)")
	dp.tap()
	_check(gs.happiness > 40.0, "a tap without one is a pat")
	gs.gifts.pocket = 1
	for i in 100:
		dp._process(0.05)
	_check(not dp.paws.worn and dp.paws.pose != QuietPaws.Pose.DIG, "it waits a while after a tap before digging up the next")
	stage.free()
	for n in [gs, gs2, gs3, gs4]:
		n.free()

## Past the edge (pure rules): pages fill with pets, "all" never overfills, scribbles stay capped,
## the page opens once, a save's odd values are cleaned.
func _test_edge(catalog: Catalog) -> void:
	var e := Edge.fresh()
	var need := Edge.need(catalog, e)
	_check(need == 500 and Edge.to_go(catalog, e) == 500 and not Edge.done(catalog, e), "the first page past the edge needs 500 pets (%d)" % need)
	var filled := Edge.add(catalog, e, 100, ["peach", "mint"])
	_check(filled.is_empty() and Edge.to_go(catalog, e) == 400 and int(e.ever) == 100, "100 pets past the edge: 400 to go")
	_check(e.marks.size() == 100 and e.marks[0] == "peach" and e.marks[1] == "mint", "a scribble per pet, in their colours (%d)" % e.marks.size())
	filled = Edge.add(catalog, e, 1000, [])
	_check(filled == ["next_door"] and int(e.ever) == 500 and Edge.page_full(catalog, e, "next_door"), "the rest fill the page and it opens, never past it (%s, %d)" % [filled, int(e.ever)])
	_check(Edge.done(catalog, e) and Edge.to_go(catalog, e) == 0 and e.marks.is_empty(), "with every page full nothing is tucked under the edge")
	_check(Edge.add(catalog, e, 50, []).is_empty() and int(e.ever) == 500, "nobody goes past a finished edge")
	_check(Edge.marks_for(catalog, 12500, 25000) == 260 and Edge.marks_for(catalog, 25000, 25000) == int(catalog.edge.marks_max),
		"a big page spreads its scribbles over marks_max")
	var odd := Edge.clean(catalog, { "page": 7, "sent": -4, "ever": "lots", "marks": [1, 2] })
	_check(Edge.done(catalog, odd) and int(odd.ever) == 0 and int(odd.sent) == 0, "a save's odd edge is cleaned (%s)" % odd)
	var half := Edge.clean(catalog, { "page": 0, "sent": 3, "ever": 3, "marks": ["peach", "nope", 5] })
	_check(int(half.sent) == 3 and half.marks.size() == 3 and half.marks[1] == "" and half.marks[2] == "", "unknown colours are blank (%s)" % str(half.marks))
	var over := Edge.clean(catalog, { "page": 0, "sent": 9999, "ever": 3 })
	_check(Edge.page_full(catalog, over, "next_door") and int(over.sent) == 0 and int(over.ever) == 9999, "a save past a page's need opens it (%s)" % over)
	# a later build needs fewer pets a page: the page opens and the rest carry on
	var real_pages: Array = catalog.edge.pages
	catalog.edge.pages = [{ "id": "a", "need": 100 }, { "id": "b", "need": 300 }]
	var lower := Edge.clean(catalog, { "page": 0, "sent": 250, "ever": 250, "marks": ["peach", "mint"] })
	_check(Edge.page_full(catalog, lower, "a") and int(lower.page) == 1 and int(lower.sent) == 150 and lower.marks.is_empty() and int(lower.ever) == 250,
		"a page that needs fewer pets now opens, the rest go on the next (%s)" % lower)
	catalog.edge.pages = real_pages
	_check(Edge.clean(catalog, null) == Edge.fresh(), "a save without an edge starts fresh")


## The little school (pure rules): class sizes, the step from the class's mix, seats never overfill,
## the bell only rings for a full class, classes multiply.
func _test_school(catalog: Catalog) -> void:
	_check(School.class_size(catalog, 0) == 40 and School.class_size(catalog, 4) == 900 and School.class_size(catalog, 5) == 1800
		and School.class_size(catalog, 6) == 3600, "class sizes 40 .. 900, then twice the last")
	_check(is_equal_approx(School.step(catalog, { "common:normal": 40 }), 2.4), "a class of commons: +2.4%")
	var mix := School.step(catalog, { "common:normal": 29, "uncommon:shiny": 10, "rare:normal": 1 })
	_check(is_equal_approx(mix, 2.9), "a mixed class steps more (+%.1f%%)" % mix)
	_check(School.step(catalog, { "epic:normal": 40 }) > School.step(catalog, { "rare:normal": 40 }), "rarer classes step more")
	var st := School.fresh()
	var sat := School.seat(catalog, st, { "common:normal": 30, "rare:normal": 30 })
	_check(School.seated(st) == 40 and int(sat.get("common:normal", 0)) == 30 and int(sat.get("rare:normal", 0)) == 10,
		"seats stop at the class's size (%s)" % sat)
	_check(School.seats_left(catalog, st) == 0 and School.full(catalog, st), "a full class")
	var st2 := School.fresh()
	School.seat(catalog, st2, { "common:normal": 12 })
	_check(School.ring(catalog, st2, []).is_empty() and School.seated(st2) == 12, "the bell doesn't ring for a class that isn't full")
	var done := School.ring(catalog, st, ["h:common:normal:1"])
	_check(not done.is_empty() and st.classes.size() == 1 and School.seated(st) == 0 and School.class_size(catalog, School.class_number(st)) == 100,
		"the bell: the class becomes teachers and class 2 starts")
	School.seat(catalog, st, { "common:normal": 100 })
	School.ring(catalog, st, [])
	var x := School.boost(st)
	_check(is_equal_approx(x, (1.0 + float(st.classes[0].step) / 100.0) * 1.024), "classes multiply (x%.4f)" % x)
	var desks := School.desk_keys(catalog, { "common:normal": 200, "epic:normal": 1 }, 24)
	_check(desks.size() == 24 and desks[0] == "epic:normal" and desks.count("epic:normal") == 1, "every kind in the class gets a desk, rarest first")
	var junk := School.clean(catalog, { "seated": { "common:normal": 70, "bad:key": 3 }, "classes": [{ "size": 99999, "step": "x", "faces": ["1", "h:common:normal:4"] }, 7] })
	_check(junk.classes.size() == 1 and int(junk.classes[0].size) == 40 and float(junk.classes[0].step) == 0.0 and junk.classes[0].faces == ["h:common:normal:4"],
		"a save's odd classes are cleaned (%s)" % str(junk.classes))
	var extra := School.trim(catalog, junk)
	_check(School.seated(junk) == 100 or (School.seated(junk) == 70 and extra.is_empty()), "a class within its seats keeps everyone")
	var over := { "seated": { "common:normal": 150 }, "classes": [] }
	var back := School.trim(catalog, over)
	_check(School.seated(over) == 40 and int(back.get("common:normal", 0)) == 110, "past its seats, the rest stand up again (%s)" % back)


## Past the edge and the school in the game: when the edge shows, it only ever takes resting herd
## pets, the page opens next door once, the school opens after the edge, classes make every worker
## quicker (the school is a source of the automation and errands boosts), teachers add no stars,
## the sorting rule can send new pets to school, and it all saves (a v31 save loads with neither).
func _test_edge_school_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the edge and school in the game: they need a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var roller := PetRoller.new(catalog, rng)
	var pets := []
	for i in 30:
		var p := roller.roll("starter", "common")
		p.finish = "normal"
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	SaveFile.write(path, { "version": 31, "coins": 100000000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "page:beyond", "location:orchard"], "room": 40,
		"collection": { "pets": pets, "active": "1", "next_id": 31, "herd": { "common:normal": 400, "common:shiny": 50, "rare:normal": 30 } } })
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(gs.edge == Edge.fresh() and gs.school == School.fresh(), "a v31 save loads with a fresh edge and school")
	_check(not gs.edge_open() and not gs.edge_torn(), "the edge is hidden until it's earned")
	# a rumour of it can come first
	var can := Rumours.hearable(catalog, gs.heard, gs.is_open).map(func(r): return r.id)
	_check("edge" in can, "the edge's rumour can be heard once the orchard is open (%s)" % str(can))
	var popped := []
	gs.unlocked.connect(func(entry): popped.append(str(entry.id)))
	var pages_opened := []
	gs.page_opened.connect(func(id): pages_opened.append(id))
	gs.heard["edge"] = true
	gs.rumours.append("edge")
	gs.follow_rumour("edge")
	_check(gs.edge_open() and popped.is_empty() and gs.rumours.is_empty(), "saying yes to its rumour opens the edge early, quietly")
	gs.unlocks.erase("feature:edge")
	gs.rumours.append("edge")
	# every place past the fence open: the edge opens (and its waiting rumour goes)
	for id in ["well", "cellar"]:
		gs.unlocks["location:" + id] = true
	gs.spotted["below"] = { "by": "", "from": "" }
	gs.follow_lead("below")
	_check(gs.edge_open() and "edge" in popped, "the last place past the fence opens the edge (%s)" % str(popped))
	_check(not "edge" in gs.rumours, "a rumour of the edge has nothing left to lead to")
	# who goes: the shared rule (GameState.spare_pick): resting pets first, then off their errands
	gs.put_on_job("coin_hunt", 300)
	var on_job: int = gs.job_size("coin_hunt")
	var resting_commons: int = int(gs.resting_shelves().get("common", 0))
	var stars := c.fallen_n
	var count_before := c.count()
	var sent: int = gs.send_past_edge("common", resting_commons)
	_check(sent == resting_commons and sent > 0 and sent < 400, "the resting commons go first (%d of %d)" % [sent, resting_commons])
	_check(gs.job_size("coin_hunt") == on_job, "while some rest, pets on errands stay (%d on the job)" % gs.job_size("coin_hunt"))
	_check(c.fallen_n == stars + sent and c.count() == count_before - sent, "each one a star, gone for good")
	_check(c.fallen.size() <= int(catalog.herd.fallen_keep), "star colours kept one by one stay capped (%d)" % c.fallen.size())
	var more_sent: int = gs.send_past_edge("common", 100)
	_check(more_sent == 100 and gs.job_size("coin_hunt") < on_job, "then they come off their errands (%d went, %d on the job)" % [more_sent, gs.job_size("coin_hunt")])
	sent += more_sent
	_check(gs.edge_to_go() == 500 - sent, "the number to go drops (%d)" % gs.edge_to_go())
	# the school opens after the first 100, once the automation tab is there
	_check(not gs.school_open(), "the school waits for the automation tab")
	gs.unlocks["tab:automation"] = true
	gs.check_unlocks()
	_check(gs.school_open() and "school" in popped, "then the school opens")
	# "all" never sends more than the page needs; a full page opens next door once
	gs.take_off_job("coin_hunt", -1)
	c.add_plain("common:normal", 5000)
	sent = gs.send_past_edge("common", -1)
	_check(gs.edge_done("next_door") and gs.is_unlocked("page:next_door") and popped.count("next_door") == 1 and pages_opened == ["next_door"],
		"a full page opens next door through open_page (%s, %s)" % [str(popped), str(pages_opened)])
	_check(int(gs.edge.ever) == 500 and not gs.edge_open() and gs.edge_torn(), "never more than the page needs (%d), the tear stays" % int(gs.edge.ever))
	gs.check_unlocks()
	gs._open_edge_pages()
	_check(popped.count("next_door") == 1 and pages_opened.size() == 1, "next door opens only once")
	# the school: seats stop at the class, the bell only rings when it's full
	var herd_now := c.herd_total()
	var seated: int = gs.seat_in_school("common", 100)
	_check(seated == 40 and c.herd_total() == herd_now - 40 and gs.class_full(), "the first class seats 40, off the herd (%d)" % seated)
	_check(gs.seat_in_school("rare", 5) == 0, "a full class takes nobody else")
	gs.automation.taught["machine"] = true
	gs.automation.others["machine"] = true
	gs.automation.spots["machine"] = 10
	gs.put_workers("machine", -1)
	gs.put_on_job("coin_hunt", 100)
	var worker_before: float = gs.workers_speed("machine") * gs.boost("automation")
	var rate_before: float = gs.job_rate("coin_hunt")
	stars = c.fallen_n
	_check(gs.ring_bell(), "you ring the bell")
	_check(c.fallen_n == stars and gs.school.classes.size() == 1 and not gs.class_full(), "the class stays on as teachers (they stay: no stars)")
	var x: float = gs.school_boost()
	_check(is_equal_approx(x, 1.024) and is_equal_approx(gs.workers_speed("machine") * gs.boost("automation"), worker_before * x) and is_equal_approx(gs.job_rate("coin_hunt"), rate_before * x),
		"every worker and errand crew is quicker (x%.3f)" % x)
	var school_parts: Array = gs.boost_parts("automation").filter(func(pt): return pt.source == "school")
	_check(school_parts.size() == 1 and is_equal_approx(float(school_parts[0].x), x) and gs.boost_parts("errands").any(func(pt): return pt.source == "school")
		and not gs.boost_parts("coins").any(func(pt): return pt.source == "school"), "the school is a boost source on automation and errands (%s)" % str(school_parts))
	var on_receipt := false
	for kind in gs.boost_receipt():
		for line in kind.lines:
			on_receipt = on_receipt or line.name == "the little school"
	_check(on_receipt, "the receipt names the little school")
	_check(not gs.ring_bell(), "an empty class can't ring")
	# the school's faces never share a number with a live stand-in (those count up from 0)
	var face_uid: String = gs.school.classes[0].faces[0]
	_check(Herd.is_stand_in(face_uid) and Herd.number_of(face_uid) < 0 and Herd.valid_key(catalog, Herd.key_of(face_uid)) and Herd.stand_in(catalog, face_uid) != null,
		"a teacher's face is a stand-in no live pet can be (%s)" % face_uid)
	# pets a minute only while box workers really open: boxes on the pile they may open, room for the pets
	gs.automation.taught["boxes"] = true
	gs.automation.others["boxes"] = true
	gs.automation.spots["boxes"] = 5
	gs.put_workers("boxes", -1)
	gs.bag.clear()
	var room_was: int = gs.room
	gs.room = 30  # plenty of room
	_check(gs.workers_count("boxes") > 0 and gs.pets_a_minute() == 0.0, "no boxes on the pile: no pets a minute (%.1f)" % gs.pets_a_minute())
	gs.bag["starter"] = 50
	_check(gs.pets_a_minute() > 0.0, "boxes on the pile: pets a minute (%.1f)" % gs.pets_a_minute())
	gs.save_for_me("starter", true)
	_check(gs.pets_a_minute() == 0.0, "boxes saved for you don't count")
	gs.save_for_me("starter", false)
	gs.room = 0
	c.add_plain("common:normal", gs.room_left())
	_check(gs.room_is_full() and gs.pets_a_minute() == 0.0, "a full room: no pets a minute")
	gs.room = room_was
	gs.take_off_workers("boxes", -1)
	gs.bag.clear()
	_check(gs.seat_in_school("common", 7) == 7 and School.seated(gs.school) == 7, "class 2 starts filling")
	# the sorting rule's "go to: school": new pets from boxes sit down while there are seats
	gs.unlocks["feature:new_homes"] = true
	gs.unlocks["feature:sorting"] = true
	gs.set_rule("on", true)
	gs.set_rule("below", "rare")
	gs.set_rule("keep", "holo")
	gs.set_rule("to", "school")
	_check(str(gs.homes.rule.to) == "school" and "school" in gs.rule_destinations(), "the sorting rule can send pets to school once it's open")
	stars = c.fallen_n
	var seated_before := School.seated(gs.school)
	gs.room += 20
	gs.bag["starter"] = 5
	var got_pets: Array = gs.open_boxes("starter", 5)
	var sortable := got_pets.filter(func(pt): return NewHomes.sorts(catalog, gs.homes.rule, pt)).size()
	_check(got_pets.size() == 5 and School.seated(gs.school) == seated_before + sortable and c.fallen_n == stars,
		"new pets below the line sit down in the school, no stars (%d of %d)" % [School.seated(gs.school) - seated_before, sortable])
	var left_seats := School.seats_left(catalog, gs.school)
	gs.seat_in_school("common", -1)
	gs.set_rule("to", "homes")
	gs.set_rule("to", "school")
	var herd_full_class := c.herd_total() + c.pets.size()
	gs.bag["starter"] = 5
	got_pets = gs.open_boxes("starter", 5)
	_check(left_seats >= 0 and gs.class_full() and c.herd_total() + c.pets.size() == herd_full_class + got_pets.size(), "with the class full, sorted pets stay")
	gs.set_rule("on", false)
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(str(gs2.edge) == str(gs.edge) and str(gs2.school) == str(gs.school), "the edge and the school save and load (%s vs %s, %s vs %s)" % [gs2.edge, gs.edge, gs2.school, gs.school])
	_check(gs2.collection.herd_total() == c.herd_total() and gs2.collection.fallen_n == c.fallen_n, "the herd and the stars load too")
	gs2.free()
	# a million in the herd stay quick
	c.add_plain("common:normal", 1000000)
	var t0 := Time.get_ticks_msec()
	var rings := 0
	for i in 12:
		gs.seat_in_school("common", -1)
		if gs.ring_bell():
			rings += 1
	var took := Time.get_ticks_msec() - t0
	_check(rings == 12 and took < 1500, "a million pets: 12 classes in %d ms" % took)
	print("  the school with a million pets: 12 classes in %d ms, x%.3f" % [took, gs.school_boost()])
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
		_check(int(d.spins.get(t.id, 0)) >= 1 and int(d.puff.get(t.id, 0)) == 0, "every rarity gives spins, misses puff nothing (%s)" % t.id)
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
	_check(r1.puffed.is_empty() and r1.wisps == 0, "misses and cracks puff nothing (%s)" % [r1.puffed])
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
	# caps, full parts, bank, the hold limit (a mythic: good enough for any part's next button)
	st.try.fed.rarity = "mythic"
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
	_check(Plushie.price(catalog, st, keeper, "wild") == 250 * (catalog.rank("mythic") + 1), "the wild reel: 250 x the fed pet's rarity step (mythic: %d)" % (250 * (catalog.rank("mythic") + 1)))
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
	_check(Plushie.puff(catalog, st, plain, false) == 0 and Plushie.puff(catalog, st, gifted, true) == 0, "a miss puffs nothing, not even a crack on a perfect keeper")
	st.try.fed = { "rarity": "epic", "traits": ["greedy"] }
	_check(Plushie.puff(catalog, st, plain, false) == 0, "greedy pets puff nothing either")
	_test_plushie_stakes(catalog)
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
	var old := { "version": 33, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "wisps": 9,
		"unlocks": ["feature:parts", "feature:errands", "tab:errands", "tab:inventory"],
		"parts": { "body:bunny": 1, "body:bunny@2": 3, "body:nope@1": 1 },
		"collection": { "pets": pets, "herd": { "common:normal": 30, "rare:shiny": 2 }, "active": "1", "next_id": 7 } }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(not gs.plushie_open() and Plushie.needs_next(gs.plushie) and gs.plushie.hopper.is_empty(),
		"a v33 save (before the machine) loads with none of it")
	_check(gs.wisps == 9, "the wisps the dungeon paid stay: one purse (%d)" % gs.wisps)
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
	_check(gs.wisps == 21, "wisps come through grant and grant_wisps, into the same purse")
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
	_check(res.landed.size() == 5 and gs.wisps == wisps_before, "a spin lands every reel; misses puff no wisps")
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
	# the dungeon's army (merge): the keeper stays home, and an army pet can't be the keeper
	gs.unlocks["feature:dungeon"] = true
	gs.take_off_job("coin_hunt", 3, ["3", "5", "6"])
	_check(gs.resting_cards().any(func(p): return p.uid == "3") and not gs.army_choices().any(func(p): return p.uid == "3") and not gs.set_army_card("3", true),
		"the keeper can't go in the dungeon's army")
	var soldier: Pet = gs.army_choices()[0]
	_check(gs.set_army_card(soldier.uid, true), "another resting card can")
	_check(not gs.plushie_keepers().has(soldier), "a pet in the army can't be the keeper")
	gs.set_army_card(soldier.uid, false)
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
	_check(newest == 43, "the save chain ends at v43 (herd + new homes 28, dungeon 33, plushie 34, the sewing room 35, perks 36, held landings 37, the wishing jar 38, the shed workshop 39, room steps 40, join up to 41, toy stars 42, find tries 43)")
	_check(gs.room_cap() >= c.plain_count() and (gs.room == 0 or Herd.room_cap(catalog, gs.room - 1) < ceili(c.plain_count() * 1.1)),
		"v40: a v23 save's room is the fewest steps with room for its pets (%d steps, %d / %d)" % [gs.room, c.plain_count(), gs.room_cap()])
	_check(gs.workshop == Workshop.fresh(catalog) and not gs.workshop_open(), "v39: an old save gets a fresh workshop, still closed")
	_check(gs.wish == Wish.fresh() and not gs.wish_open(), "v38: an old save has nothing wished for and no jar yet")
	_check("cellar" in gs.dungeon.bands, "v33: an old save's open cellar is a dungeon band")
	_check(not gs.plushie_open() and gs.wisps == 0 and gs.plushie.hopper.is_empty(), "v34: an empty plushie machine and no wisps")
	_check(gs.job_joins("coin_hunt"), "v28: sharing on -> new pets join the errand")
	_check(not gs.room_is_full(), "v28: an old save gets room for its pets (%d / %d)" % [c.plain_count(), gs.room_cap()])
	gs.save_game()
	_check(int(SaveFile.read(path).get("version", 0)) == newest, "it saves at the newest version")
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
	var keeper: String = gs._plushie_keeper_uid()
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
	var every: Dictionary = gs.spare_pick("common")
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


## Rolls `n` pets with a wish: { tiers: { tier: n }, looks: { book key: n }, rare_bunny, bad: [...] }.
func _wish_roll(catalog: Catalog, box_id: String, wish: Dictionary, n: int, seed_: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	var roller := PetRoller.new(catalog, rng)
	roller.wish = wish
	var out := { "tiers": {}, "looks": {}, "rare_bunny": 0, "bad": [] }
	for i in n:
		var pet := roller.roll(box_id)
		out.tiers[pet.rarity] = int(out.tiers.get(pet.rarity, 0)) + 1
		for slot in Catalog.SLOTS:
			var k := Collection.part_key(slot, pet.parts[slot])
			out.looks[k] = int(out.looks.get(k, 0)) + 1
		if pet.rarity == "rare" and pet.parts.body == "bunny":
			out.rare_bunny += 1
		var top := 0
		for slot in Catalog.SLOTS:
			top = maxi(top, catalog.rank(catalog.part(slot, pet.parts[slot]).rarity))
		if top != catalog.rank(pet.rarity) and out.bad.size() < 3:
			out.bad.append("%s %s" % [pet.rarity, pet.parts])
	return out


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
	var old := { "noses": 180, "paws": 400, "pockets": 2500, "lemons": 900, "sign": 1600, "cups": 12000, "bigger_jar": 7875,
		"slot": 12000, "map_case": 15000, "glasses": 20000, "snack": 1200, "naps": 3000, "pebbles": 8000, "team": 20000 }
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
	var beds := Herd.room_cap(catalog, 1) - Herd.room_cap(catalog, 0)
	_check(Herd.room_cost(catalog, 0, fresh) == beds * game_state.box_cost(starter, fresh), "the first room step costs a starter box per new bed")
	for level in [0, 10, 100, 1000]:
		_check(Herd.room_cost(catalog, level, top) > 0, "a room step after %d never costs less than nothing" % level)


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
	# a bag part's row (the workbench's tiles and sewing table) is the same row the pet shows
	var same := true
	for k in Knacks.of(catalog, pet, all_open):
		same = same and Knacks.row(catalog, k.slot, k.part, all_open, pet.finish, int(k.buttons)) == k
	_check(same, "Knacks.row gives the same rows as Knacks.of")
	_check(Knacks.row(catalog, "accessory", "crown", all_open, "holo", 2).n == Knacks.size(catalog, "automation", "legendary", "holo", 2),
		"a bag tile's size counts the pet's finish and the part's buttons")
	_check(Knacks.row(catalog, "accessory", "horns", open).is_empty(), "a hidden kind has no row")
	_check(Knacks.row(catalog, "accessory", "crown", all_open).short == "automation", "the short word for small tiles")
	for kind: String in d.kinds:
		_check(str(d.kinds[kind].get("short", "")) != "", "knack kind %s has a short word" % kind)
	var spots := Knacks.parts(catalog, pet, "spots", open)
	_check(spots.size() == 1 and spots[0].source == "knacks" and spots[0].id == "body:bunny+eyes:cyclops" and is_equal_approx(float(spots[0].x), 1.32),
		"big ears + one big eye add up: one part, +32% spotting")
	_check(is_equal_approx(Boosts.total(Knacks.parts(catalog, pet, "coins", open)), 1.40), "golden touch: +40% coins")
	_check(Knacks.parts(catalog, pet, "fever", open).is_empty(), "no fever knack, no fever part")
	_check(Knacks.best(catalog, pet, open).slot == "palette", "the best badge: the legendary one (golden touch)")
	_check(is_equal_approx(Knacks.own(catalog, pet, "spots", open), 1.32), "a card pet counts its knacks in full on its own work: +32% spotting on its own trips")
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
	_check(is_equal_approx(Knacks.party(catalog, party, "spots", open), 1.16), "a party's own knacks are the average (32% and 0%)")
	_check(is_equal_approx(Knacks.party(catalog, [], "spots", open), 1.0), "nobody, x1")
	# the lean totals (no display rows) agree with the rows the badges show
	var roll_rng := RandomNumberGenerator.new()
	roll_rng.seed = 11
	var roller := PetRoller.new(catalog, roll_rng)
	var agree := true
	var many: Array = []
	for i in 300:
		var p := roller.roll("midnight")
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
		Knacks.party_all(catalog, many, Boosts.trip_kinds(catalog), open)
	var per_pet := float(Time.get_ticks_usec() - t0) / (10.0 * many.size())
	print("knacks: party_all over %d trip kinds %.1f us per pet" % [Boosts.trip_kinds(catalog).size(), per_pet])
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


func _test_receipt(catalog: Catalog) -> void:
	# the "x1.25" numbers
	_check(Boosts.times(1.25) == "x1.25", "x1.25 (got %s)" % Boosts.times(1.25))
	_check(Boosts.times(1.0) == "x1.00", "nothing is x1.00")
	_check(Boosts.times(12.46) == "x12.5", "from 10: one decimal (got %s)" % Boosts.times(12.46))
	_check(Boosts.times(123.4) == "x123", "from 100: whole (got %s)" % Boosts.times(123.4))
	_check(Boosts.times(1234.0) == "x1.2k", "from 1000: 1.2k (got %s)" % Boosts.times(1234.0))
	_check(Boosts.times(3400000.0) == "x3.4M", "then 3.4M (got %s)" % Boosts.times(3400000.0))
	# line names
	_check(Toys.edition_name(catalog, "acorn:holo") == "holo acorn" and Toys.edition_name(catalog, "acorn:normal") == "acorn",
		"toy editions read \"holo acorn\", \"acorn\"")
	_check(Knacks.part_names(catalog, "body:bunny+eyes:cyclops") == "big ears + one big eye",
		"a pet's badges read \"big ears + one big eye\" (got %s)" % Knacks.part_names(catalog, "body:bunny+eyes:cyclops"))
	# the receipt: kinds in boosts.json order, lines in sources order, each kind totted up
	var namer := func(part: Dictionary) -> String:
		return Toys.edition_name(catalog, str(part.id)) if part.source == "toys" else Knacks.part_names(catalog, str(part.id))
	_check(Boosts.receipt(catalog, {}, namer).is_empty(), "no boosts, an empty receipt")
	var now := 1000.0
	var state := Toys.fresh()
	for ed in [["acorn", "normal"], ["acorn", "holo"], ["moth", "normal"]]:
		Toys.add(state, ed[0], ed[1])
		state.playing.append({ "key": Toys.key(ed[0], ed[1]), "until": now + 600.0, "wear": 0.0 })
	var by_kind := {}
	for k in Boosts.kinds(catalog):
		by_kind[k] = Toys.parts(state, catalog, k, now)
	var knack := Boosts.part("knacks", "palette:gold", 1.4)
	by_kind["coins"] = [knack] + by_kind["coins"]  # listed first, but knacks come after toys on the receipt
	var rows := Boosts.receipt(catalog, by_kind, namer)
	var kinds: Array = rows.map(func(r): return r.kind)
	_check(kinds == ["coins", "xp", "luck"], "the moth's all bonus: coins, xp, luck, in the table's order (got %s)" % [kinds])
	var coins: Dictionary = rows[0]
	var names: Array = coins.lines.map(func(l): return l.name)
	_check(names.size() == 4 and names.slice(0, 3).has("holo acorn") and names.slice(0, 3).has("acorn") and names.slice(0, 3).has("moon moth")
		and names[3] == Knacks.part_names(catalog, "palette:gold"), "the coins lines: the toys first, then the badge (got %s)" % [names])
	_check(is_equal_approx(float(coins.total), Boosts.total(by_kind["coins"])) and coins.name == "coins", "a kind's total is its parts multiplied")
	_check(rows[2].lines.size() == 1 and rows[2].lines[0].source == "toys", "luck: only the moth")
	var odd := { "coins": [Boosts.part("someday", "x", 1.1), Boosts.part("toys", "acorn:normal", 1.05)] }
	var last: Array = Boosts.receipt(catalog, odd, func(p): return str(p.source))[0].lines
	_check(last[0].source == "toys" and last[1].source == "someday", "a source not in the list goes last")
	# the machine's coin lines multiply up to a capsule's coins
	var machine := { "bought": {} }
	_check(Machine.coin_parts(machine, catalog).is_empty(), "a broken machine: nothing multiplies its coins")
	machine.bought = { "tape": 1, "shine": 3, "chute2": 1 }
	var cp := Machine.coin_parts(machine, catalog)
	var product := float(catalog.machine_tree.get("base_coins", 1))
	for p in cp:
		product *= float(p.x)
	_check(cp.size() == 2 and cp[0].name == "tape up the crack" and is_equal_approx(float(cp[0].x), 2.0) and is_equal_approx(float(cp[1].x), pow(1.25, 3)),
		"tape x2, shinier coins x1.25^3 (the chute doesn't touch coins)")
	_check(is_equal_approx(product, Machine.coin_value(machine, catalog)), "the lines multiplied are a capsule's coins")
	# a "why so much?": lines at x1 did nothing, so they're left out; the total is what it came to
	var why := Boosts.why("found on the way", 47, [{ "name": "a tote bag", "x": 1.3 }, { "name": "the party's badges", "x": 1.0 },
		{ "name": "our boosts", "x": 1.51 }], roundi(47 * 1.51 * 1.3))
	_check(why.lines.size() == 2 and why.lines[0].name == "a tote bag" and why.start.value == 47, "the badges at x1 are left off the slip")
	_check(int(why.total) == 92, "found 47, tote x1.30, our boosts x1.51: all together 92 (got %d)" % int(why.total))


## The machine's and the errands' "why so much?": where it starts times every line comes to the
## number shown (a GameState of its own, nothing saved).
func _test_whys_add_up(catalog: Catalog) -> void:
	var gs: Node = load("res://scripts/game_state.gd").new()
	var adds_up := func(why: Dictionary) -> bool:
		var v := float(why.start.value)
		for l in why.lines:
			v *= float(l.x)
		return absf(v - float(why.total)) <= maxf(0.02 * absf(float(why.total)), 0.001)
	gs.machine = { "pulls": 0, "lit": 0, "bought": { "tape": 1, "shine": 3 } }
	var cw: Dictionary = gs.capsule_why()
	_check(cw.lines.size() >= 2 and adds_up.call(cw), "the capsule's why multiplies up to its coins (%s)" % [cw])
	# errands: two jobs, rare pets on the stand, every kind of tool
	gs.unlocks["feature:errands"] = true
	gs.unlocks["job:lemonade"] = true
	var pets: Array[Pet] = []
	for i in 12:
		var p: Pet = gs._roller.roll(gs.FIRST_PET_BOX)
		p.rarity = "rare" if i % 2 == 0 else "common"
		pets.append(p)
	gs.collection.add(pets)
	gs.put_on_job("coin_hunt", -1, pets.slice(0, 6).map(func(p): return p.uid))
	gs.put_on_job("lemonade", -1, pets.slice(6).map(func(p): return p.uid))
	var before: Dictionary = gs.errands_why()
	_check(adds_up.call(before), "the errands' why multiplies up to the pill (%s)" % [before])
	for t in [["noses", 3], ["paws", 4], ["snack", 2], ["lemons", 2]]:
		gs.errand_tools[t[0]] = t[1]
	gs._tools_changed()
	var tooled: Dictionary = gs.errands_why()
	_check(adds_up.call(tooled) and is_equal_approx(float(tooled.total), gs.errands_per_minute()), "with tools it still adds up (%s)" % [tooled])
	var line := func(why: Dictionary, name: String) -> float:
		for l in why.lines:
			if l.name == name:
				return float(l.x)
		return 1.0
	gs.errand_tools["cups"] = 1
	gs._tools_changed()
	var cupped: Dictionary = gs.errands_why()
	_check(adds_up.call(cupped), "with the fancy cups it still adds up (%s)" % [cupped])
	_check(line.call(cupped, "our tools") > line.call(tooled, "our tools") + 0.01 and is_equal_approx(line.call(cupped, "tips"), line.call(tooled, "tips")),
		"the fancy cups count under our tools, not tips")
	# the book's errands and coins stickers: "our boosts" on the slip, named on the receipt
	var st: Array[String] = ["patterns", "palettes"]
	gs.stickers = st
	gs._boosts_changed()
	var stuck: Dictionary = gs.errands_why()
	_check(adds_up.call(stuck) and line.call(stuck, "our boosts") > 1.2, "with stickers the errands' why still adds up (%s)" % [stuck])
	_check(gs._boost_line_name(Boosts.part("book", "palettes", 1.1)) == "a paint set", "a sticker's receipt line is its name")
	_check(gs._boost_line_name(Boosts.part("kitchen", "kitchen", 1.1)) == "the kitchen", "the kitchen's receipt line")
	gs.free()


## Next door (E2): every garden has lights and its own column on the street, only the game's code
## opens it, places become ours after their lights (the gate and path at once, the backyard after
## many visits, nothing while next door is closed), and an ours trip is safer, pays more and never
## meets the locals.
func _test_next_door(catalog: Catalog) -> void:
	var page := catalog.page_info("next_door")
	_check(page.get("paper", "") == "night" and page.get("layout", "") == "street", "next door is a night page laid out as a street")
	var places: Array = catalog.locations.filter(func(l): return l.page == "next_door")
	_check(places.size() == 6, "next door has six places (%d)" % places.size())
	var columns := {}
	var in_fence := 0
	for l in places:
		_check(Ours.lights(l) > 0, "%s has lights" % l.id)
		_check(l.box == "midnight", "%s is a midnight box place" % l.id)
		var x := int(l.map.x)
		_check(float(l.map.x) == float(x) and x >= 0 and x < 5, "%s sits in a column of the street" % l.id)
		if int(l.map.y) >= 1:  # in our fence (StreetPage.in_fence)
			in_fence += 1
		else:
			_check(not columns.has(x), "%s has a garden of its own" % l.id)
			columns[x] = true
			if l.get("ours_at_start", false):  # ours from the start: the locals are never seen there
				_check(not l.map.has("trace"), "%s (ours from the start) has no locals' trace" % l.id)
			else:
				_check(str(l.map.get("trace", "")) != "", "%s has a trace of the locals" % l.id)
		if l.get("ours_at_start", false):
			_check(not l.pool.any(func(p): return catalog.events[p.event].get("local", false)), "%s (ours from the start) has no local events" % l.id)
	_check(in_fence == 1, "one place sits in our fence (their gate)")
	_check(catalog.location("doghouse").get("risky", false), "the doghouse is risky")
	var lights := places.map(func(l): return Ours.lights(l))
	lights.sort()
	_check(lights == [3, 4, 5, 5, 6, 8], "lights are 3/4/5/5/6/8 (%s)" % str(lights))
	for id in ["their_gate", "their_path"]:
		_check(catalog.location(id).get("ours_at_start", false) and catalog.location(id).get("start", false), "%s starts as ours" % id)
	# the locals only ever as traces: their events stop once a place is ours, so every place keeps enough others
	for l in catalog.locations:
		if l.has("pool"):
			var others: Array = l.pool.filter(func(p): return not catalog.events[p.event].get("local", false))
			_check(others.size() >= int(l.draws), "%s has enough events without the locals" % l.id)
	for e in catalog.events.values():
		if e.get("local", false):
			_check(catalog.locations.any(func(l): return l.page == "next_door" and not l.get("ours_at_start", false) and l.get("pool", []).any(func(p): return p.event == e.id)), "local event %s can turn up next door" % e.id)
	# only the game's code opens next door (GameState.open_page): nothing earns it, and it never goes stale
	var opens: Array = catalog.unlock_list.filter(func(e): return "page:next_door" in e.opens)
	_check(opens.size() == 1 and UnlockRules.called(opens[0]) and opens[0].show == "hidden", "next door opens only when the game calls for it")
	_check(UnlockRules.opening(catalog.unlock_list, "page:next_door").get("id", "") == "next_door", "open_page finds next door's unlock")
	_check(opens[0].has("popup") and str(opens[0].popup.get("go", "")) == "adventures", "next door pops up and goes to adventures")
	_check(not "page:next_door" in UnlockRules.stale(catalog.unlock_list, func(_e): return false), "an old save never loses next door")
	_check(not UnlockRules.called(catalog.unlock_list[0]), "other unlocks aren't called")
	# lights and ours
	var greenhouse := catalog.location("greenhouse")
	for visits in 6:
		_check(Ours.lights_left(greenhouse, visits) == 5 - visits, "a light goes out per visit (%d)" % visits)
		_check(Ours.is_ours(catalog, greenhouse, visits, true) == (visits >= 5), "the greenhouse is ours at its last light (%d)" % visits)
	_check(Ours.lights_left(greenhouse, 99) == 0, "lights never go below none")
	_check(Ours.is_ours(catalog, catalog.location("their_gate"), 0, true) and Ours.lights_left(catalog.location("their_gate"), 0) == 0, "the gate is ours from the start")
	_check(not Ours.is_ours(catalog, catalog.location("their_gate"), 0, false), "nothing is ours while next door is closed")
	_check(not Ours.is_ours(catalog, greenhouse, 50, false), "not even with lots of visits")
	var meadow := catalog.location("meadow")
	var after := int(catalog.page_info("backyard").get("ours_after", 0))
	_check(after >= 20, "the backyard takes lots of visits (%d)" % after)
	_check(not Ours.is_ours(catalog, meadow, after - 1, true) and Ours.is_ours(catalog, meadow, after, true), "a backyard place is ours after %d visits" % after)
	_check(not Ours.is_ours(catalog, meadow, after * 3, false), "the backyard waits for next door")
	_check(not Ours.is_ours(catalog, catalog.location("fields"), 999, true), "beyond the fence never becomes ours")
	_check(Ours.lights_left(meadow, 0) == 0, "backyard places have no lights of their own")
	_check(Ours.opens_with(catalog) == "next_door", "ours opens with next door")
	_check(not "{" in Ours.say(catalog, "say_ours", greenhouse) and "the greenhouse" in Ours.say(catalog, "say_ours", greenhouse), "your pet says which place it coloured in")
	_check(not "{" in Ours.say(catalog, "say_dark", greenhouse), "the lights-out line has no placeholders")
	# an ours trip: safer, pays more, no locals
	var mine := Ours.place(catalog, catalog.location("doghouse"), true)
	_check(is_equal_approx(float(mine.danger), float(catalog.location("doghouse").danger) * 0.5), "ours halves the danger")
	_check(is_equal_approx(float(mine.loot), float(catalog.location("doghouse").loot) * 1.2), "ours pays x1.2")
	_check(float(catalog.location("doghouse").danger) == 1.6, "the catalog's place stays as it was")
	_check(Ours.place(catalog, greenhouse, false) == greenhouse, "not ours: the place as it is")
	var locals_ours := false
	var locals_theirs := false
	for t in 300:
		for e in AdventureRunner.pick_events(catalog.location("doghouse"), t, {}, catalog, {}, 0, true):
			locals_ours = locals_ours or catalog.events[e].get("local", false)
		for e in AdventureRunner.pick_events(catalog.location("doghouse"), t, {}, catalog, {}, 0, false):
			locals_theirs = locals_theirs or catalog.events[e].get("local", false)
	_check(not locals_ours and locals_theirs, "the locals turn up until a place is ours, then never")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var roller := PetRoller.new(catalog, rng)
	var herd: Array[Pet] = []
	for i in 60:
		herd.append(roller.roll("starter"))
	var run := AdventureRunner.start("doghouse", herd, 0.0, 3, catalog, {}, {}, {}, {}, 0, true)
	_check(run.ours and not run.events.any(func(e): return catalog.events[e].get("local", false)), "an ours run meets no locals")
	var saved := RunState.from_dict(JSON.parse_string(JSON.stringify(run.to_dict())), catalog)
	_check(saved != null and saved.ours, "an ours run stays ours through a save")
	var old := run.to_dict()
	old.erase("ours")
	_check(not RunState.from_dict(old, catalog).ours, "a run saved before ours isn't ours")
	_check(AdventureRunner.place(run, catalog).loot == mine.loot, "the run meets the ours place")
	var theirs := AdventureRunner.estimate_return("doghouse", herd, catalog, 40)
	var ours := AdventureRunner.estimate_return("doghouse", herd, catalog, 40, {}, {}, true)
	_check(ours >= theirs, "more come home from the doghouse once it's ours (%.2f vs %.2f)" % [ours, theirs])
	# v31 (built as v24): visits per place, every place visited before counts once
	_check(Ours.visits_from(["garden", "meadow"]) == { "garden": 1, "meadow": 1 }, "old saves count one visit per place visited")


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
	# a card pet's own work gets its FULL knacks (playtest 1, P4): the same size its badge shows
	var mint_n := int(Knacks.row(catalog, "palette", "mint", gs.knack_gate, card.finish).n)
	var crown_n := int(Knacks.row(catalog, "accessory", "crown", gs.knack_gate, card.finish).n)
	_check(mint_n == 8 and crown_n == 60, "a holo card's badges: minty fresh 5 x1.5 = 8%%, royal 40 x1.5 = 60%% (%d, %d)" % [mint_n, crown_n])
	_check(is_equal_approx(gs._pet_speed(card, job), Jobs.pet_speed(card, job) * (1.0 + mint_n / 100.0)),
		"the card's errand speed gets minty fresh in full (x%.3f)" % (gs._pet_speed(card, job) / Jobs.pet_speed(card, job)))
	_check(is_equal_approx(gs.knack_own(card, "automation"), 1.0 + crown_n / 100.0), "its worker speed gets royal in full (x%.2f)" % gs.knack_own(card, "automation"))
	var horned := Pet.from_dict(card.to_dict())
	horned.parts.accessory = "horns"  # little horns: the army's power
	var dungeon_open := func(_gate: String) -> bool: return true
	_check(is_equal_approx(Knacks.own(catalog, horned, "power", dungeon_open), 1.0 + Knacks.size(catalog, "power", "mythic", "holo") / 100.0),
		"a card's power knack counts in full for its own army power")
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

	# the music box's away runs: only floors cleared safely (power at least away_safe x the floor's), nobody lost
	var safe_x := float(catalog.dungeon.get("away_safe", 0.0))
	var mid_army := _army(20, 15.0, 280, 1.0)
	rng.seed = 11
	var safe_run := Dungeon.simulate(catalog, mid_army, { "target": 10, "home_at": 90, "safe": safe_x }, rng)
	var lost_safe := Dungeon.run_lost(safe_run)
	_check(safe_x > float(catalog.dungeon.stuck) and safe_run.why == "safe" and Dungeon.cleared_to(safe_run) < 10 and lost_safe[0].is_empty() and Herd.total(lost_safe[1]) == 0,
		"an away run turns home before the first floor it can't clear safely, nobody lost (%s at %d)" % [safe_run.why, Dungeon.cleared_to(safe_run)])
	var next_f := Dungeon.cleared_to(safe_run) + 1
	_check(Dungeon.army_power(catalog, mid_army, Dungeon.floor_kind(catalog, next_f)) / Dungeon.strength(catalog, next_f) < safe_x,
		"the floor it turned at wasn't safe")
	var easy_run := Dungeon.simulate(catalog, _army(20, 1.0e6, 280, 1.0e5), { "target": 5, "home_at": 90, "safe": safe_x }, rng)
	_check(easy_run.why == "target" and Dungeon.cleared_to(easy_run) == 5 and Dungeon.run_pay(easy_run) > 0, "a strong army goes all the way down safely and brings its wisps")

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
	# floors the army had cleared before it set off walk cleared_x times faster; new ones take seconds_per_floor
	var per := float(d.seconds_per_floor)
	var fast := per / float(d.cleared_x)
	_check(float(d.cleared_x) > 1.0, "cleared floors are faster (x%.1f)" % float(d.cleared_x))
	var walk_floors: Array = range(1, 7).map(func(f): return { "f": f, "cleared": true, "lost_cards": [], "lost_herd": {}, "pay": 1 })
	var walk := { "floors": walk_floors, "start": 0, "known": 4, "sent": 10 }
	_check(is_equal_approx(Dungeon.run_seconds(catalog, walk), 4 * fast + 2 * per),
		"4 floors cleared before and 2 new ones take %.1f s (%.1f)" % [4 * fast + 2 * per, Dungeon.run_seconds(catalog, walk)])
	_check(is_equal_approx(Dungeon.run_floor(catalog, walk, 4 * fast), 4.0) and is_equal_approx(Dungeon.run_floor(catalog, walk, 4 * fast + per / 2.0), 4.5),
		"the army walks the known floors quickly, then slows down on the new ones")
	_check(Dungeon.floors_done(catalog, walk, 2 * fast + 0.01) == 2 and Dungeon.floors_done(catalog, walk, 1.0e6) == 6, "the floors behind it are done")
	walk.known = 0
	_check(is_equal_approx(Dungeon.run_seconds(catalog, walk), 6 * per), "a run with nothing cleared before walks every floor at seconds_per_floor")
	var held_walk := { "floors": walk_floors.slice(0, 2).map(func(fl): return fl.merged({ "f": int(fl.f) + 10 }, true)), "start": 10, "known": 11 }
	_check(is_equal_approx(Dungeon.run_seconds(catalog, held_walk), fast + per) and is_equal_approx(Dungeon.run_floor(catalog, held_walk, fast), 11.0),
		"from a held landing only the floors walked count, known ones fast")
	# every floor of a run says who got bumped and who stayed below, as it happens
	var tally := Dungeon.run_tally(hurt.merged({ "sent": 300 }), hurt.floors.size())
	var lost_all := Dungeon.run_lost(hurt)
	_check(hurt.floors.all(func(fl): return fl.has("hurt_herd") and fl.has("hurt_cards") and fl.has("ratio")), "each floor keeps who was bumped and how it went")
	_check(int(tally.lost) == lost_all[0].size() + Herd.total(lost_all[1]) and int(tally.walking) == 300 - int(tally.lost) and int(tally.got) == Dungeon.run_pay(hurt),
		"the run's tally adds up its floors (%d lost, %d walking)" % [int(tally.lost), int(tally.walking)])
	_check(int(tally.hurt) > 0 and int(Dungeon.run_tally(hurt, 1).hurt) <= int(tally.hurt), "a weak army gets bumped on the way (%d)" % int(tally.hurt))
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
	var old := { "version": 32, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "location:cellar", "location:below", "feature:parts", "tab:automation",
			"feature:errands", "tab:errands"],
		"heard": ["well", "cellar"], "rumours": ["cellar"],
		"collection": { "pets": pets, "active": "1", "next_id": 31, "seen": {}, "herd": { "common:normal": 500 }, "herd_ever": true },
		"automation": auto, "room": 20 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	# v33 (built as v24): the cellar and further down are bands already reached; waiting rumours and parties move on
	_check(gs.dungeon.bands == ["well", "cellar", "below"], "an old save that had the cellar and further down has those bands (%s)" % [gs.dungeon.bands])
	_check(not "cellar" in gs.rumours and gs.automation.party.place == "well", "their rumours go, a party going there goes to the well")
	_check(gs.is_unlocked("location:cellar"), "the old unlocks stay")
	_check(not gs.location_open(catalog.location("cellar")) and not gs.location_open(catalog.location("below")), "the cellar and further down aren't trips any more")
	var some: Array[Pet] = [gs.collection.get_pet("2")]
	_check(gs.send_on_adventure("cellar", some) == null, "nobody can be sent to a band")
	_check(gs.location_open(catalog.location("well")), "the top of the well is still a trip")
	_check(not gs.dungeon_open(), "the dungeon waits for the rope find")
	# the rope: every pet ever sent to the well counts, and the next party once enough have gone finds it
	var rope_at := int(catalog.events.well_rope.get("after_sent", 0))
	_check(rope_at > 0 and not catalog.events.well_rope.has("min_party"), "the rope waits for pets sent to the well, not one big party (%d)" % rope_at)
	_check(gs.sent_to("well") == 0, "an old save with no visits starts the count at 0 (%d)" % gs.sent_to("well"))
	gs.finds["whistle"] = true
	var two: Array[Pet] = [gs.collection.get_pet("2")]
	var first_run: RunState = gs.send_on_adventure("well", two)
	_check(first_run != null and gs.sent_to("well") == 1, "a lone pet counts one (%d)" % gs.sent_to("well"))
	_check(not "well_rope" in first_run.events, "no rope while few have gone down")
	gs.sent["well"] = rope_at - 1
	var one: Array[Pet] = [gs.collection.get_pet("3")]
	var short_run: RunState = gs.send_on_adventure("well", one)
	_check(short_run != null and not "well_rope" in short_run.events and gs.sent_to("well") == rope_at, "the party that makes %d doesn't find it yet" % rope_at)
	var next: Array[Pet] = [gs.collection.get_pet("4")]
	var rope_run: RunState = gs.send_on_adventure("well", next)
	_check(rope_run != null and "well_rope" in rope_run.events, "the next party at the well, even alone, finds the rope")
	var counted: Dictionary = SaveFile.read(path).get("sent", {})
	_check(int(counted.get("well", 0)) == rope_at + 1, "the count is saved (%s)" % [counted])
	for r in [first_run, short_run, rope_run]:
		gs.runs.erase(r)  # home again, for the army below
	gs.finds.erase("whistle")
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
	# with nobody resting, the army's herd comes off the errands (the shared rule, see spare_pick)
	gs.set_army_herd("common", 0)
	gs.put_on_job("coin_hunt", -1)
	var hunt_all: int = gs.job_size("coin_hunt")
	gs.set_army_herd("common", 100)
	_check(int(gs.army().herd.get("common", 0)) == 100 and gs.job_size("coin_hunt") == hunt_all - 100,
		"the army's herd comes off the errands (%d in it, %d off)" % [int(gs.army().herd.get("common", 0)), hunt_all - gs.job_size("coin_hunt")])
	gs.take_off_job("coin_hunt", -1)
	# fill up: the plainest shelf first, up to the entrance; empty: nobody walks behind
	gs.collection.add_plain("uncommon:normal", 100)
	gs.set_army_herd("common", 0)
	gs.set_army_herd("uncommon", 10)
	gs.army_fill_up()
	army = gs.army()
	_check(int(army.sent) == 300 and int(army.herd.get("common", 0)) == 270 and int(army.herd.get("uncommon", 0)) == 10,
		"fill up tops the entrance up with commons first (%s)" % [army.herd])
	gs.set_army_herd("common", 0)
	gs.set_army_herd("uncommon", 0)
	gs.collection.add_plain("common:holo", 50)  # (past the keep line: never taken)
	gs.homes.rule.keep = "holo"
	var room_common: int = gs.army_herd_room("common")
	gs.army_fill_up()
	army = gs.army()
	_check(int(army.herd.get("common", 0)) == mini(room_common, 280) and not gs.army_herd_keys().has("common:holo"),
		"fill up only takes pets that may go (%s)" % [gs.army_herd_keys()])
	gs.dungeon.cards.clear()
	gs.army_fill_up()
	_check(int(gs.army().herd.get("common", 0)) == mini(room_common, 300) and gs.army().cards.is_empty(),
		"fill up never adds cards to the front row (%d)" % gs.army().cards.size())
	gs.army_empty()
	_check(Herd.total(gs.army_herd_keys()) == 0, "empty: nobody from the shelves walks behind")
	gs.army_best()
	gs.set_army_herd("common", 280)
	_check(gs.floor_words(1, 3).size() == 3, "the next floors get feeling words")

	# a run: it goes, its pets stay busy, it comes home
	_check(gs.send_army() and gs.dungeon_running(), "the army goes down")
	_check(int(gs.dungeon.run.get("known", -1)) == int(gs.dungeon.deep), "the run knows how deep the army had been (cleared floors go faster)")
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
	var report: Dictionary = gs.dungeon_report
	_check(not report.is_empty() and int(report.tally.lost) == 6 and int(report.got) == 20 and bool(report.new_deep) and report.front.size() == 20,
		"the came home report has the run's losses, wisps and the front row that went (%s)" % [report.get("tally", {})])
	_check(report.front.any(func(p): return p.uid == lost_uid) and report.tally.lost_cards.has(lost_uid), "a front row pet that stayed below is still in the report (as a face)")
	_check(str(report.best.get("kind", "")) == "part" and int(report.best.f) == 10, "the best bit is the first find: floor 10's part (%s)" % [report.best])
	gs.drop_dungeon_report()
	_check(gs.dungeon_report.is_empty(), "changing the army puts the report away")
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
	_check(Sewing.one(catalog, "part:accessory:halo") == "a halo" and Sewing.one(catalog, "buttons:1") == "1 button" and Sewing.one(catalog, "buttons:3") == "3 buttons"
		and Sewing.one(catalog, "trait:lazy") == "lazy", "a seat's word names one pet (%s)" % Sewing.one(catalog, "part:accessory:halo"))
	_check(Sewing.ones(catalog, "part:accessory:halo") == "halos" and Sewing.ones(catalog, "trait:lazy") == "lazy ones" and Sewing.ones(catalog, "tier:epic") == "epic ones",
		"the picker's word names the pets that fit (%s)" % Sewing.ones(catalog, "tier:epic"))

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
## rooms after the last, and it all comes back from the save (a v34 save loads with none of it).
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
	var old := { "version": 34, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:new_homes", "feature:sorting", "feature:parts"],
		"finds": ["deep_rope"],
		"collection": { "pets": pets, "active": "1", "next_id": 13, "seen": {}, "herd": { "common:normal": 400 }, "herd_ever": true },
		"dungeon": { "deep": 12, "bands": ["well", "cellar"] }, "room": 30 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.sewing.cleared == 0 and not gs.sewing_open() and not gs.finds.has("little_key"), "a v34 save loads with no sewing room (and no key before floor 20)")
	_check(gs.homes.rule.lines.is_empty() and gs.homes.kept.is_empty(), "and no keep lines")
	gs.grant({ "find:little_key": 1 })
	_check(gs.sewing_open(), "the tiny key opens the sewing room's door")
	gs.army_best()
	gs.set_army_herd("common", 100)
	_check(not gs.sew_can_go(0) and not gs.send_to_room(0), "the button tin's seats are empty: nobody goes in")
	_check(not gs.sew_can_go(1), "the next room doesn't even show yet")
	var front: Array = gs.sew_front()
	front[0].parts.body = "bunny"
	_check(gs.sew_marks(0) == [false, false, false], "a bunny in the front row fills nothing by itself: marks count the pets on their seats")
	_check(not gs.sew_seat(0, "tier:rare", front[0].uid) and gs.sew_seated(0).is_empty(), "an epic bunny can't sit on the rare seat")
	_check(gs.sew_seat(0, "part:body:bunny", front[0].uid) and gs.sew_marks(0) == [true, false, false], "it sits on the bunny ears seat")
	# any pet you seat counts, not only the army's strongest: a plain rare cat nobody lined up
	var weak := _plain_pet(catalog, "rare", "holo", 900)
	weak.parts.body = "cat"
	weak.traits.clear()
	gs.collection.add([weak] as Array[Pet])
	_check(not gs.army_cards().any(func(p): return p.uid == weak.uid), "the rare cat isn't in the army")
	_check(gs.sew_pickable().any(func(p): return p.uid == weak.uid) and gs.sew_seat(0, "tier:rare", weak.uid), "but it can sit on the rare seat")
	# your active pet may go in too
	var me: Pet = gs.collection.active()
	me.finish = "shiny"
	_check(gs.sew_pickable().has(me) and gs.sew_seat(0, "finish:shiny", me.uid), "your active pet sits on the shiny seat")
	_check(gs.sew_marks(0) == [true, true, true] and gs.sew_can_go(0), "every seat has a pet: in we go")
	var party: Dictionary = gs.sew_party(0)
	_check(party.cards.has(me) and party.cards.has(weak) and int(party.sent) == 13 + 100 and int(party.more) == int(party.sent) - 3,
		"the seated pets and the whole army go in (%d, %d more)" % [int(party.sent), int(party.more)])
	gs.sew_unseat(0, "finish:shiny")
	_check(gs.sew_marks(0) == [true, true, false], "taking your pet off empties its seat")
	# one pet can fill several seats
	var all_three := _plain_pet(catalog, "rare", "shiny", 901)
	all_three.parts.body = "bunny"
	all_three.fav = true  # (stays a card)
	gs.collection.add([all_three] as Array[Pet])
	gs.sew_pick_room(1)
	gs.sew_pick_room(0)
	_check(gs.sew_seated(0).is_empty(), "lining up another room starts with empty seats")
	_check(gs.sew_seat(0, "tier:rare", all_three.uid) and gs.sew_marks(0) == [true, true, true] and gs.sew_seated(0).size() == 1, "a shiny rare bunny sits on all three seats")
	gs.sew_unseat(0, "part:body:bunny")
	_check(gs.sew_seated(0).is_empty(), "and gets up from all of them")
	gs.sew_seat(0, "part:body:bunny", front[0].uid)
	gs.sew_seat(0, "tier:rare", weak.uid)
	gs.sew_seat(0, "finish:shiny", me.uid)
	var busy_uid: String = front[3].uid
	_check(gs.send_to_room(0) and gs.dungeon_running() and gs.dungeon.run.room == 0, "in we go: the seated pets and the army are in the button tin")
	_check(me.uid in gs.dungeon.run.cards and weak.uid in gs.dungeon.run.cards, "your pet and the rare cat went in")
	_check(not gs.resting_cards().any(func(p): return p.uid == busy_uid) and not gs.send_army(), "its pets are busy, and nobody else goes down meanwhile")
	_check(not gs.sew_pickable().any(func(p): return p.uid == weak.uid), "pets in the room can't sit anywhere else")
	var herd0: int = gs.collection.herd_count("common:normal")
	gs.dungeon.run.at = 0.0
	gs.dungeon.run.floors = [{ "f": 20, "cleared": true, "lost_cards": [busy_uid, me.uid], "lost_herd": { "common:normal": 3 }, "pay": 7 }]
	var wisps0: int = gs.wisps
	gs._dungeon_tick()
	_check(not gs.dungeon_running() and gs.wisps == wisps0 + 7 and gs.sewing.cleared == 1, "back from the tin: its wisps paid, one room cleared")
	_check(gs.collection.get_pet(busy_uid) == null and gs.collection.herd_count("common:normal") == herd0 - 3, "the ones that didn't come back are gone")
	_check(gs.collection.get_pet(me.uid) != null, "your pet always comes home")
	_check(int(gs.sew_last.get("room", -1)) == 0 and gs.sew_last.cleared and gs.sew_last.first and int(gs.sew_last.got) == 7
		and int(gs.sew_last.back) == int(gs.sew_last.sent) - 4, "the page's result: the tin, cleared for the first time, 7 wisps, who came home (%s)" % [gs.sew_last])
	_check(gs.sew_seated(0).size() == 3 and gs.sew_marks(0) == [true, true, true], "the seats stay for another go")
	_check(gs.dungeon.last.get("room", -1) == 0 and gs.feature_on("keep_lines") and gs.keep_line_count() == 1, "the last time card knows the room; keep lines open")
	_check(gs.sew_can_go(0) and Sewing.shown(gs.sewing) == 2, "the tin can be done again, and the pin cushion shows")
	# a replay gives no firsts; a room too strong isn't cleared
	_check(gs.send_to_room(0), "again: the same seats go in")
	gs.dungeon.run.at = 0.0
	gs.dungeon.run.floors = [{ "f": 20, "cleared": true, "lost_cards": [], "lost_herd": {}, "pay": 3 }]
	gs._dungeon_tick()
	_check(gs.sewing.cleared == 1 and not gs.sew_last.first, "doing the tin again doesn't count as a new room")
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
	var plan: Dictionary = gs.spare_pick("common")
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
	gs.plushie.keeper = all_three.uid
	var rolled_i: int = gs.sewing.cleared
	gs.sew_pick_room(rolled_i)
	var keeper_ok: bool = not gs.army_choices().any(func(p): return p.uid == all_three.uid) and gs.sew_pickable().any(func(p): return p.uid == all_three.uid)
	_check(keeper_ok, "the plushie keeper never joins the army, but it can sit on a seat")
	all_three.buttons = { "body": 1 }
	var lock: String = gs.sew_room(rolled_i).marks[0]
	if Sewing.mark_matches(lock, all_three):
		_check(gs.sew_seat(rolled_i, lock, all_three.uid), "the keeper sits on the button seat")
	gs.dungeon.run = { "at": 0.0, "floors": [{ "f": 20, "cleared": false, "lost_cards": [all_three.uid], "lost_herd": {}, "pay": 0 }],
		"why": "stuck", "turned": 0, "cards": [all_three.uid], "herd": {}, "sent": 1, "target": 5, "room": rolled_i, "door": 20, "seconds": 60.0 }
	gs._dungeon_tick()
	_check(gs.collection.get_pet(all_three.uid) != null and str(gs.plushie.keeper) == all_three.uid, "the keeper always comes home too")
	_check(not gs.sew_last.cleared and int(gs.sew_last.got) == 0, "a room too strong: no pennant, nothing paid")
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
	_check(gs3.finds.has("little_key") and gs3.sewing_open(), "a v34 save past floor 20 gets the key and its door")
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
	var old := { "version": 35, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:lead_army", "tab:automation", "feature:parts"],
		"finds": ["deep_rope"], "automation": auto, "wisps": 100000,
		"collection": { "pets": pets, "active": "1", "next_id": 31, "seen": {}, "herd": { "common:normal": 3000 }, "herd_ever": true },
		"dungeon": { "deep": 12, "bands": ["well", "cellar"], "entrance": 2, "target": 5, "firsts": { "10": true } }, "room": 40 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.perk_level("entrance") == 2 and not gs.dungeon.has("entrance"), "v35 -> v36: the entrance's level moved into the perks")
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
	_check(int(saved.version) == gs_version() and saved.perks.get("thimble", 0) == 1 and not saved.dungeon.has("entrance"), "it saves at v%d with the perks" % gs_version())
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
	var herd_was := int(away.collection.herd.get("common:normal", 0))
	_check(herd_left == herd_was and herd_was > 0, "away runs never lose pets: losses only happen while you're here (%d of %d)" % [herd_left, herd_was])
	_check(gs2.collection.pets.size() == away.collection.pets.size(), "and no card pets lost either (%d of %d)" % [gs2.collection.pets.size(), away.collection.pets.size()])
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
	var old := { "version": 36, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["page:beyond", "location:well", "feature:dungeon", "feature:parts", "feature:errands", "tab:errands"],
		"finds": ["deep_rope"], "wisps": 0,
		"collection": { "pets": pets, "active": "1", "next_id": 35, "seen": {}, "herd": { "common:normal": 12000, "uncommon:normal": 3000 }, "herd_ever": true },
		"dungeon": { "deep": 32, "bands": ["well", "cellar", "below"], "target": 5, "firsts": { "10": true, "20": true } }, "room": 60 }
	SaveFile.write(path, old)
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(gs.dungeon.held.is_empty() and int(gs.dungeon.start) == 0, "v36 -> v37: nothing held, the orders start at the top")
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
	_check(int(saved.version) == gs_version() and saved.dungeon.held.has("30") and int(saved.dungeon.start) == 30, "it saves at v%d with the held landings" % gs_version())
	gs.free()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(Dungeon.starts(catalog, gs2.dungeon) == [0, 10, 20, 30] and int(gs2.dungeon.start) == 30, "and they come back from the save")
	gs2.free()
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


## Workers' parties the game places by itself (the whistle, a bought spot) never go into a dungeon
## or a risky place that isn't ours: pets get lost only where you send them.
func _test_party_places(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped party places: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var gs: Node = load("res://scripts/game_state.gd").new()
	gs.unlocks["page:beyond"] = true
	gs.unlocks["page:next_door"] = true
	for l in catalog.locations:
		gs.unlocks["location:" + str(l.id)] = true
	var dungeons: Array = gs.open_locations().filter(func(l): return str(l.get("type", "")) == "dungeon")
	_check(not dungeons.is_empty(), "the test has a dungeon open (%d)" % dungeons.size())
	var places: Array = gs.party_places()
	_check(not places.any(func(l): return str(l.get("type", "")) == "dungeon"), "no dungeon is a party place")
	_check(not places.any(func(l): return l.get("risky", false) and not gs.is_ours(str(l.id))), "no risky place that isn't ours is a party place")
	_check(gs.spot_exist("adventures") == int(Automation.job(catalog, "adventures").spot.per_place) * places.size(),
		"parties exist per party place (%d)" % gs.spot_exist("adventures"))
	gs.automation.parties = []
	for l in places:
		if int(l.get("max_party", 0)) != 1:
			gs.automation.parties.append({ "place": str(l.id), "n": 0 })
	gs.automation.spots["adventures"] = gs.automation.parties.size()
	gs._add_spots("adventures", 2)
	var n: int = gs.automation.parties.size()
	var picked: Array = [str(gs.automation.parties[n - 2].place), str(gs.automation.parties[n - 1].place), str(gs.auto_party(n - 1).place)]
	_check(not picked.any(func(id): return str(catalog.location(id).get("type", "")) == "dungeon"),
		"every other place taken, new parties still stay out of dungeons (%s)" % [picked])
	gs.free()


## A run of one pet at `place` standing at `event_id`, waiting for an answer (for the weather vane).
func _waiting_run(catalog: Catalog, place: String, event_id: String) -> RunState:
	var roller := PetRoller.new(catalog, RandomNumberGenerator.new())
	var going: Array[Pet] = [roller.roll("starter")]
	var run := AdventureRunner.start(place, going, 0.0, 7, catalog)
	run.events.assign([event_id])
	run.step = 0
	run.next_at = 0.0
	AdventureRunner.resolve(run, PlayerChooser.new(), 1.0, catalog)
	return run


## A plain event (nothing risky at that place) and a risky one: [[place, event], [place, event]].
func _plain_and_risky(catalog: Catalog) -> Array:
	var plain := []
	var risky := []
	for l in catalog.locations:
		for id in l.get("events", []) + l.get("pool", []).map(func(p): return p.event):
			var e: Dictionary = catalog.events.get(id, {})
			if e.is_empty() or e.get("auto", false) or e.has("min_party") or e.has("only_if"):
				continue
			var any_risky: bool = AdventureRunner.options_of(e, l).any(func(o): return AdventureRunner.risky(o, l))
			if any_risky and risky.is_empty():
				risky = [str(l.id), str(id)]
			elif not any_risky and plain.is_empty():
				plain = [str(l.id), str(id)]
	return [plain, risky]


## The shed workshop (F3): its drawings are sound data, helpers fill them (pets below the tier leave
## room for the ones that meet it), building pins the next in the same spot, a save is cleaned, and
## the weather vane only ever answers plain choices you've answered before.
func _test_workshop(catalog: Catalog) -> void:
	var list := Workshop.drawings(catalog)
	var ids: Array = list.map(func(d): return str(d.id))
	_check(ids == ["bell", "shelf", "vane", "chart", "spade", "basket", "banner", "letter"], "the 8 drawings from the mockup, in order (%s)" % [ids])
	var last_need := 0
	var places: Array = catalog.locations.filter(func(l): return str(l.get("page", "")) == "backyard" and l.has("map"))
	var spots: Array[Vector2] = []
	for d in list:
		_check(catalog.tiers.any(func(t): return t.id == d.tier), "drawing %s needs a real tier" % d.id)
		_check(int(d.count) > 0 and int(d.count) <= int(d.need), "drawing %s needs no more at its tier than helpers (%d of %d)" % [d.id, d.count, d.need])
		_check(int(d.need) > last_need, "drawing %s needs more helpers than the one before" % d.id)
		last_need = int(d.need)
		_check(str(d.get("art", "")).begins_with("<"), "drawing %s has its crayon art" % d.id)
		_check(str(d.get("chore", "")) != "" and str(d.get("say", "")) != "" and str(d.get("done", "")) != "", "drawing %s says what it takes away" % d.id)
		var at := Vector2(float(d.at[0]), float(d.at[1]))
		for l in places:
			_check(at.distance_to(Vector2(float(l.map.x), float(l.map.y))) >= 0.35, "drawing %s doesn't stand on %s" % [d.id, l.id])
		for other in spots:
			_check(at.distance_to(other) >= 0.3, "drawing %s doesn't stand on another built thing" % d.id)
		spots.append(at)
	var entry := UnlockRules.opening(catalog.unlock_list, "feature:workshop")
	_check(str(entry.get("earn", {}).get("ours", "")) == "shed" and str(entry.earn.get("open", "")) == "feature:whistle" and entry.show == "hidden",
		"the workshop waits for the old shed being ours and the whistle, hidden till then")
	# a fresh workshop: the first 3 pinned, nothing built
	var ws := Workshop.fresh(catalog)
	_check(ws.pinned == ["bell", "shelf", "vane"] and ws.built.is_empty(), "a new workshop pins the first 3 drawings (%s)" % [ws.pinned])
	# helpers: 40 for the bell rope, 5 of them rare or up
	_check(Workshop.useful(catalog, ws, "bell", "common") == 35, "commons leave room for the 5 rares (%d)" % Workshop.useful(catalog, ws, "bell", "common"))
	_check(Workshop.take(catalog, ws, "bell", "common", 1000) == 35, "all: never more than helps")
	_check(Workshop.useful(catalog, ws, "bell", "uncommon") == 0 and Workshop.take(catalog, ws, "bell", "common", 5) == 0, "then no more commons")
	_check(Workshop.useful(catalog, ws, "bell", "epic") == 5, "epics count as rare or up")
	_check(not Workshop.full(catalog, ws, "bell") and Workshop.build(catalog, ws, "bell") == null, "not full: it can't be built")
	_check(Workshop.take(catalog, ws, "bell", "rare", 10) == 5 and Workshop.full(catalog, ws, "bell"), "5 rares finish it")
	_check(Workshop.take(catalog, ws, "shelf", "legendary", 3) == 3 and Workshop.take(catalog, ws, "vane", "common", 7) == 7,
		"every pinned drawing fills at once")
	_check(int(ws.helpers) == 50, "helpers are counted (%d)" % ws.helpers)
	_check(is_equal_approx(Workshop.fill(catalog, ws, "bell"), 1.0) and is_equal_approx(Workshop.fill(catalog, ws, "shelf"), 0.05), "the plank's bars")
	var next: Variant = Workshop.build(catalog, ws, "bell")
	_check(next == "chart" and ws.pinned == ["chart", "shelf", "vane"] and Workshop.has(ws, "bell"), "building pins the next drawing in its spot (%s)" % [ws.pinned])
	_check(int(Workshop.prog(ws, "shelf").sent) == 3, "the others keep their helpers")
	for id in ["shelf", "vane", "chart", "spade", "basket", "banner", "letter"]:
		Workshop.finish(catalog, ws, id)
	_check(Workshop.pinned(ws).is_empty() and Workshop.all_built(catalog, ws) and ws.built.size() == 8, "all 8 built: nothing left pinned")
	_check(Workshop.finish(catalog, ws, "bell") == null, "a built drawing can't be built again")
	# cleaning a save
	_check(Workshop.clean(catalog, "junk") == Workshop.fresh(catalog) and Workshop.clean(catalog, {}) == Workshop.fresh(catalog), "junk or nothing: a fresh workshop")
	var odd := Workshop.clean(catalog, { "pinned": ["bell", "nope", "bell"], "built": ["bell", "bell", "zz", "shelf"],
		"prog": { "vane": { "sent": -4, "qual": 9 } }, "helpers": -3, "vane": { "garden:garden_fork": 1 } })
	_check(odd.built == ["bell", "shelf"] and odd.pinned == ["vane", "chart", "spade"] and int(odd.helpers) == 0,
		"built ones are never pinned, unknown ones go, empty spots fill up (%s %s)" % [odd.built, odd.pinned])
	_check(int(odd.prog.vane.sent) == 0 and int(odd.prog.vane.qual) == 0 and int(odd.vane["garden:garden_fork"]) == 1, "numbers are never negative, the vane keeps your picks")
	# the weather vane: plain choices only, only what you picked there last
	var pr := _plain_and_risky(catalog)
	_check(not pr[0].is_empty() and not pr[1].is_empty(), "the test found a plain and a risky event")
	if not pr[0].is_empty() and not pr[1].is_empty():
		var vane := Workshop.fresh(catalog)
		var plain := _waiting_run(catalog, pr[0][0], pr[0][1])
		_check(plain.status == RunState.Status.WAITING, "the plain run waits at its event")
		_check(Workshop.vane_pick(catalog, vane, plain) == -1, "nothing picked there before: the vane leaves it to you")
		vane.vane[Workshop.vane_key(pr[0][0], pr[0][1])] = 0
		_check(Workshop.vane_pick(catalog, vane, plain) == 0, "a plain choice: your last pick there")
		vane.vane[Workshop.vane_key(pr[0][0], pr[0][1])] = 99
		_check(Workshop.vane_pick(catalog, vane, plain) == -1, "a pick this party can't take: left to you")
		var risky := _waiting_run(catalog, pr[1][0], pr[1][1])
		vane.vane[Workshop.vane_key(pr[1][0], pr[1][1])] = 0
		_check(risky.status == RunState.Status.WAITING and Workshop.vane_pick(catalog, vane, risky) == -1, "a risky choice always waits for you")
		vane.vane[Workshop.vane_key(pr[0][0], pr[0][1])] = 0
		plain.auto = true
		_check(Workshop.vane_pick(catalog, vane, plain) == -1, "your pet's own trips aren't the vane's")
	# toys: a play knows its length, the shelf hands the ones ending, the basket mends resting toys
	var toys := Toys.fresh()
	Toys.add(toys, "snail", "normal")
	Toys.add(toys, "snail", "holo")
	_check(Toys.play(toys, catalog, "snail:normal", "quick", 0.0) and str(toys.playing[0].play) == "quick", "a play keeps its length")
	_check(Toys.ending(toys, 10.0).is_empty() and Toys.ending(toys, 601.0) == [{ "key": "snail:normal", "play": "quick" }], "the plays ending now")
	_check(Toys.again(toys, "snail:normal") and not Toys.flip_again(toys, "snail:normal", 10.0) and not Toys.again(toys, "snail:normal")
		and Toys.ending(toys, 601.0).is_empty(), "tapped: this round is the last, the shelf leaves it")
	_check(Toys.flip_again(toys, "snail:normal", 10.0) and Toys.ending(toys, 601.0).size() == 1, "tapped again: once more after all")
	_check(not Toys.flip_again(toys, "snail:holo", 10.0), "nothing to flip on a resting toy")
	toys.owned["snail:normal"].wear = 0.5
	toys.owned["snail:holo"].wear = 0.5
	Toys.mend(toys, 0.2, 10.0)
	_check(is_equal_approx(float(toys.owned["snail:holo"].wear), 0.3) and is_equal_approx(float(toys.owned["snail:normal"].wear), 0.5), "the basket mends resting toys, not the one being played with")
	Toys.mend(toys, 5.0, 10.0)
	_check(float(toys.owned["snail:holo"].wear) == 0.0, "never below good as new")


## The workshop in the game: it opens only with the shed ours AND the whistle, helpers are plain
## pets that leave with no star, building pins the next, a v38 save gets a fresh workshop, and each
## built thing does its chore (and leaves alone what stays yours).
func _test_workshop_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the workshop in the game: it needs a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 6:
		var p := _plain_pet(catalog, "common", "normal", 300 + i)
		p.uid = str(i + 1)
		if i == 1:
			p.fav = true
		pets.append(p.to_dict())
	SaveFile.write(path, { "version": 38, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["feature:errands", "tab:errands", "tab:automation"], "room": 30,
		"collection": { "pets": pets, "herd": { "common:normal": 200, "rare:normal": 20 }, "active": "1", "next_id": 7, "seen": {} },
		"toys": { "owned": { "snail:normal": { "level": 1, "spares": 0, "wear": 0.0 } }, "playing": [{ "key": "snail:normal", "until": Time.get_unix_time_from_system() + 600.0, "wear": 0.04 }] } })
	var gs: Node = load("res://scripts/game_state.gd").new()
	var c: Collection = gs.collection
	_check(gs.workshop == Workshop.fresh(catalog), "a v38 save gets a fresh workshop (v39)")
	_check(str(gs.toys.playing[0].get("play", "x")) == "", "an old play loads without a length")
	# it opens only with both: the shed ours and the whistle
	gs.check_unlocks()
	_check(not gs.workshop_open(), "closed at first")
	gs.unlocks["page:next_door"] = true
	gs.add_visits("shed", 40)
	gs.check_unlocks()
	_check(gs.is_ours("shed") and not gs.workshop_open(), "the shed ours but no whistle: still closed")
	gs.visits["shed"] = 0
	gs.unlocks["feature:whistle"] = true
	gs.check_unlocks()
	_check(not gs.is_ours("shed") and not gs.workshop_open(), "the whistle but the shed not ours: still closed")
	gs.visits["shed"] = 40
	gs.check_unlocks()
	_check(gs.workshop_open() and gs.workshop_shown(), "both: the workshop opens")
	# helpers: plain pets only, off for good, no stars
	var stars: int = c.fallen_n
	var count0: int = c.count()
	_check(gs.helpers_can_go("bell", "common") == 35, "35 commons may help (%d)" % gs.helpers_can_go("bell", "common"))
	_check(gs.send_helpers("bell", "common", -1) == 35, "all: 35 commons go")
	_check(c.fallen_n == stars and c.count() == count0 - 35, "helpers stay on for good: no stars (%d -> %d)" % [stars, c.fallen_n])
	_check(c.get_pet("1") != null and c.get_pet("2") != null, "never the active pet or a favourite")
	_check(gs.send_helpers("bell", "common", 10) == 0, "no more commons once only rares help")
	_check(not gs.build_drawing("bell"), "not full: no building")
	_check(gs.send_helpers("bell", "rare", 100) == 5 and Workshop.full(catalog, gs.workshop, "bell"), "5 rares finish the bell rope")
	_check(gs.build_drawing("bell") and gs.built("bell") and gs.workshop.pinned[0] == "chart", "built: the chore chart is pinned in its spot")
	# the bell rope: trips you sent welcome themselves back, not the one you watch, not your pet's
	var going: Array[Pet] = [c.get_pet("3")]
	var mine: RunState = gs.send_on_adventure("garden", going)
	var watched: RunState = gs.send_on_adventure("garden", [c.get_pet("4")] as Array[Pet])
	var auto: RunState = gs.send_on_adventure("garden", [c.get_pet("5")] as Array[Pet])
	auto.auto = true
	for r: RunState in [mine, watched, auto]:
		r.events.clear()
		r.next_at = 0.0
		gs._advance(r)
	gs.watching = watched
	var trips0: int = gs.trips_done
	gs._ring_bell()
	_check(not mine in gs.runs and gs.postcards.size() == 1 and gs.trips_done == trips0 + 1, "a trip you sent is welcomed back, its postcard waits")
	_check(gs.news.is_empty() and str(gs.postcards[0].get("news", {}).get("place", "")) == str(catalog.location("garden").name)
		and gs.postcards[0].has("announce"), "its news waits with its postcard (your pet talks about that trip)")
	_check(watched in gs.runs and auto in gs.runs, "not the one you're watching, not your pet's own")
	gs.watching = null
	gs._ring_bell()
	_check(not watched in gs.runs and gs.postcards.size() == 2, "watching stops: then it's welcomed back too")
	gs.runs.erase(auto)
	_check(not gs.take_postcard().is_empty() and gs.postcards.size() == 1, "postcards are taken one at a time")
	var keep := int(catalog.workshop.letterbox_keep)
	for i in keep + 5:
		gs.postcards.append({ "place": str(i) })
	var one_more: RunState = gs.send_on_adventure("garden", [c.get_pet("6")] as Array[Pet])
	one_more.events.clear()
	one_more.next_at = 0.0
	gs._advance(one_more)
	gs._ring_bell()
	_check(gs.postcards.size() == keep and str(gs.postcards[-1].get("place", "")) == str(catalog.location("garden").name),
		"at most %d postcards wait (the oldest go)" % keep)
	gs.postcards.clear()
	# the weather vane: it answers plain choices you've answered there before, never risky ones
	var pr := _plain_and_risky(catalog)
	if not pr[0].is_empty() and not pr[1].is_empty():
		var plain := _waiting_run(catalog, pr[0][0], pr[0][1])
		var risky := _waiting_run(catalog, pr[1][0], pr[1][1])
		gs.runs.append(plain)
		gs.runs.append(risky)
		gs.answer_event(plain, 0)
		_check(int(gs.workshop.vane.get(Workshop.vane_key(pr[0][0], pr[0][1]), -1)) == 0, "your answers are remembered for the vane")
		plain.status = RunState.Status.WAITING
		plain.step = 0
		plain.next_at = 0.0
		plain.history.clear()
		gs.workshop.vane[Workshop.vane_key(pr[1][0], pr[1][1])] = 0
		gs._advance_runs()
		_check(plain.status == RunState.Status.WAITING and risky.status == RunState.Status.WAITING, "no vane yet: they wait")
		Workshop.finish(catalog, gs.workshop, "vane")
		gs.watching = plain
		gs._advance_runs()
		_check(plain.status == RunState.Status.WAITING, "the vane leaves the trip you're watching to you")
		gs.watching = null
		gs._advance_runs()
		_check(plain.history.size() == 1 and plain.status != RunState.Status.WAITING, "the vane answers the plain choice")
		_check(risky.status == RunState.Status.WAITING and risky.history.is_empty(), "the risky one still waits for you")
		gs.runs.erase(plain)
		gs.runs.erase(risky)
	# the toy shelf: a play that ends starts again, the same length
	var now := Time.get_unix_time_from_system()
	gs.toys.playing.clear()
	Toys.play(gs.toys, catalog, "snail:normal", "long", now - 4000.0)
	var ended: Array = gs._finish_plays(now)
	_check(ended == ["snail:normal"] and gs.toys.playing.is_empty(), "no shelf: the play just ends")
	Workshop.finish(catalog, gs.workshop, "shelf")
	Toys.play(gs.toys, catalog, "snail:normal", "long", now - 4000.0)
	ended = gs._finish_plays(now)
	_check(ended.is_empty() and gs.toys.playing.size() == 1 and str(gs.toys.playing[0].play) == "long" and float(gs.toys.playing[0].until) > now + 1700.0,
		"the toy shelf: your pet plays with it again, just as long")
	gs.toy_again("snail:normal")
	gs.toys.playing[0].until = now - 1.0
	ended = gs._finish_plays(now)
	_check(ended == ["snail:normal"] and gs.toys.playing.is_empty(), "tapped: it goes back on the shelf, the spot is free for a new toy")
	# the chore chart: every errand has new pets join
	_check(not gs.job_joins("coin_hunt"), "no chart: the errand's switch is off")
	gs.debug_build("chart")
	_check(gs.job_joins("coin_hunt"), "the chore chart: every errand has new pets join")
	var hunt0: int = gs.job_size("coin_hunt")
	gs.debug_give_pets(4)
	_check(gs.job_size("coin_hunt") == hunt0 + 4, "new pets start on the errands (%d)" % (gs.job_size("coin_hunt") - hunt0))
	# the garden spade and the sewing basket
	gs.rummaged.clear()
	var coins0: int = gs.coins
	gs.workshop.pinned[gs.workshop.pinned.find("spade")] = "spade"
	gs.debug_build("spade")
	gs._workshop_chores(Time.get_unix_time_from_system())
	_check(catalog.rummage_spots.all(func(sp): return not gs.rummage_ready(str(sp.id))) and gs.coins > coins0, "the garden spade digs every twinkling spot")
	gs.toys.playing.clear()
	gs.toys.owned["snail:normal"].wear = 0.5
	gs.debug_build("basket")
	gs._mend_at = Time.get_unix_time_from_system() - 30.0
	gs._workshop_chores(Time.get_unix_time_from_system())
	_check(float(gs.toys.owned["snail:normal"].wear) == 0.5, "the basket stitches quietly: not every second")
	gs._mend_at = Time.get_unix_time_from_system() - 40.0
	gs._workshop_chores(Time.get_unix_time_from_system())
	_check(float(gs.toys.owned["snail:normal"].wear) < 0.5, "the sewing basket mends resting toys (once a minute)")
	# a round trip keeps it all
	Toys.play(gs.toys, catalog, "snail:normal", "long", Time.get_unix_time_from_system())
	gs.save_game()
	var gs2: Node = load("res://scripts/game_state.gd").new()
	_check(gs2.workshop.built == gs.workshop.built and gs2.workshop.pinned == gs.workshop.pinned and gs2.workshop.vane == gs.workshop.vane
		and int(gs2.workshop.helpers) == 40, "the workshop loads back (%s)" % [gs2.workshop.built])
	_check(str(gs2.toys.playing[0].get("play", "")) == "long", "the play's length loads back")
	gs2.free()
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
	# old saves: a v28-v39 room level becomes steps that hold at least as much
	for version in [28, 39]:
		for level in [0, 1, 2, 5, 10]:
			clear.call()
			SaveFile.write(path, { "version": version, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "room": level })
			var gs: Node = game_state.new()
			var old_cap := maxi(50, roundi(500.0 * pow(1.5, level) / 50.0) * 50)
			var fewest: bool = gs.room == 0 or Herd.room_cap(catalog, gs.room - 1) < old_cap
			_check(gs.room_cap() >= old_cap and fewest,
				"a v%d room at level %d keeps its room (%d, was %d)" % [version, level, gs.room_cap(), old_cap])
			gs.free()
	# a game: coin steps take coins, squeeze-in steps wait for wisps and take only wisps
	clear.call()
	SaveFile.write(path, { "version": 40, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(), "coins": 1000000000,
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
	if short == 0:
		gs.wisps = 0
		gs.unlock("feature:dungeon")  # the first squeeze-in step costs a single wisp: the dungeon opening shows them
	_check(gs.wisps_shown() and str(gs.room_next().get("name", "")) == str(Herd.room_step(catalog, coin_steps).name), "then the next squeeze-in step shows")
	var coins_now: int = gs.coins
	_check(not gs.buy_room() and gs.wisps == short, "short on wisps: nothing built")
	gs.grant_wisps(short + 1)
	var wprice: int = gs.room_price()
	_check(gs.buy_room() and gs.room == coin_steps + 1 and gs.wisps == 2 * short + 1 - wprice and gs.coins == coins_now, "a squeeze-in step takes only wisps (%d), no coins" % wprice)
	gs.save_game()
	var gs2: Node = game_state.new()
	_check(gs2.wisps == gs.wisps and gs2.room == coin_steps + 1, "wisps and the room load back")
	gs2.free()
	gs.free()
	clear.call()


## Goals (the next up note) and finds that turn up for sure: the basket at the meadow.
func _test_goals_game(catalog: Catalog) -> void:
	if not DevProfile.active():
		print("  skipped the goals in the game: they need a profile (-- --profile=test_core)")
		return
	var path := DevProfile.path("save.json")
	for f in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	var pets := []
	for i in 5:
		var p := _plain_pet(catalog, "common", "normal", 400 + i)
		p.uid = str(i + 1)
		pets.append(p.to_dict())
	SaveFile.write(path, { "version": 42, "coins": 1000, "tutorial": "done", "saved_at": Time.get_unix_time_from_system(),
		"unlocks": ["location:meadow"], "collection": { "pets": pets, "active": "1", "next_id": 6, "seen": {} } })
	var gs: Node = load("res://scripts/game_state.gd").new()
	_check(not Goals.list(gs).any(func(g): return g.id == "errands"), "no errands goal before the flap is fixed")
	gs.machine.bought["flap"] = 1
	var errands: Array = Goals.list(gs).filter(func(g): return g.id == "errands")
	_check(errands.size() == 1 and str(errands[0].name) == "errands", "fixing the flap puts errands on the goals")
	var step: Dictionary = errands[0].steps[0] if errands.size() == 1 else {}
	_check(step.get("place", "") == "meadow" and int(step.get("need", 0)) == catalog.find_sure_by, "its step: trips to the meadow (%s)" % step)
	_check(Goals.at_place(gs, "meadow").size() >= 1 and Goals.at_place(gs, "garden").is_empty(), "the meadow's card shows it, the garden's doesn't")
	var met := false
	for i in catalog.find_sure_by:
		var going: Array[Pet] = [gs.collection.get_pet(str(i + 2))]
		var run: RunState = gs.send_on_adventure("meadow", going)
		met = run != null and "meadow_basket" in run.events
	_check(met, "the %d-th trip to the meadow meets the basket for sure" % catalog.find_sure_by)
	_check(int(gs.find_tries.get("basket", 0)) == catalog.find_sure_by, "every trip that could meet it counted (%s)" % gs.find_tries)
	gs.save_game()
	_check(int(SaveFile.read(path).get("find_tries", {}).get("basket", 0)) == catalog.find_sure_by, "the tries are saved (v43)")
	gs.finds["basket"] = true
	gs.check_unlocks()
	_check(gs.tab_open("errands") and not Goals.list(gs).any(func(g): return g.id == "errands"), "once it's found the goal is done and gone")
	gs.free()


## The plushie machine's stakes (playtest 1): cracks knock sewn buttons off (more on a held reel),
## a nudge off a crack puts them back, and each next button needs a better fed pet.
func _test_plushie_stakes(catalog: Catalog) -> void:
	var d: Dictionary = catalog.plushie
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var keeper := Pet.new()
	keeper.uid = "1"
	keeper.parts = { "body": "bunny", "palette": "gold", "pattern": "stars", "eyes": "cyclops", "accessory": "horns" }
	keeper.buttons = { "body": 2, "palette": 2 }
	var st := Plushie.fresh()
	Plushie.feed(catalog, st, { "rarity": "mythic", "finish": "normal", "traits": [] })
	Plushie.next_pet(catalog, st, keeper)
	var r := Plushie.spin(catalog, st, keeper, rng, { "body": "crack", "palette": "blank", "pattern": "blank", "eyes": "blank", "accessory": "blank" })
	_check(Plushie.buttons(keeper, "body") == 2 - int(d.crack_pops) and int(r.popped.get(0, 0)) == int(d.crack_pops),
		"a crack knocks %d sewn button off its part (%s)" % [int(d.crack_pops), r.popped])
	var reels: Array = st.try.reels
	reels[0].strip = ["blank", "crack", "button"]
	Plushie.spin(catalog, st, keeper, rng, { "body": "button", "palette": "blank", "pattern": "blank", "eyes": "blank", "accessory": "blank" })
	_check(Plushie.toggle_hold(catalog, st, 0), "hold the body (it holds a button)")
	var body := Plushie.buttons(keeper, "body")
	Plushie.spin(catalog, st, keeper, rng, { "body": "crack", "palette": "blank", "pattern": "blank", "eyes": "blank", "accessory": "blank" })
	var pops := int(d.crack_pops) + int(d.hold_pops)
	_check(Plushie.buttons(keeper, "body") == maxi(0, body - pops) and int(reels[0].held) == 0, "a crack on a held reel loses what it held and %d sewn ones" % pops)
	reels[0].strip = ["blank", "crack", "button"]
	st.nudges = 1
	var after_crack := Plushie.buttons(keeper, "body")
	_check(Plushie.nudge(catalog, st, keeper, 0, rng) == "blank" and Plushie.buttons(keeper, "body") == after_crack + int(reels[0].get("popped", 0)) + (body - after_crack),
		"a nudge off the crack puts its buttons back")
	# who's good enough: a common spins a part's 1st and 2nd button, not its 3rd
	var weak := Pet.new()
	weak.parts = keeper.parts.duplicate()
	weak.buttons = { "body": 2 }
	var ws := Plushie.fresh()
	Plushie.feed(catalog, ws, { "rarity": "common", "finish": "normal", "traits": [] })
	Plushie.next_pet(catalog, ws, weak)
	_check(Plushie.need_for(catalog, 2) == "rare" and Plushie.blocked(catalog, ws, weak, "body") and not Plushie.active(catalog, ws, weak, 0),
		"a part with 2 buttons needs a rare: a common leaves its reel still")
	_check(Plushie.active(catalog, ws, weak, 1), "the common still spins a part with none")
	var res := Plushie.spin(catalog, ws, weak, rng)
	_check(not res.landed.has(0) and res.landed.has(1), "the still reel doesn't land")
	_check(Plushie.need_for(catalog, 4) == "mythic", "the 5th button needs a mythic")
