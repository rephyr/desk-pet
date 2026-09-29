extends SceneTree
## Plays lots of one-pet trips to every place with a few play styles and prints what they pay,
## to tune data/adventures.json against the price of a box. Run with:
##   godot --headless -s tools/balance.gd
## safe: always the surest option. sensible: risky while healthy, safe once hurt, home if hurt
## and the next thing looks dangerous. greedy: always the biggest prize.

const TRIPS := 3000


func _init() -> void:
	var catalog := Catalog.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var roller := PetRoller.new(catalog, rng)
	var box_price := float(catalog.box("starter").capsules)  # at the start (a capsule worth 1 coin)
	print("one pet (a common), %d trips each. a box costs %d." % [TRIPS, box_price])
	print("%-10s %-9s %8s %8s %8s %8s %8s" % ["place", "style", "coins", "per min", "parts", "boxes", "lost"])
	for location in catalog.locations:
		if not location.has("pool") and location.get("type", "") == "dungeon":
			continue  # the old dungeon places aren't tuned for one pet yet
		for style in ["safe", "sensible", "greedy"]:
			var coins := 0.0
			var parts := 0.0
			var boxes := 0.0
			var lost := 0
			for t in TRIPS:
				var pets: Array[Pet] = [roller.roll("starter", "common")]
				var run := AdventureRunner.start(location.id, pets, 0.0, t, catalog)
				var now := 0.0
				for i in 30:
					if run.status == RunState.Status.DONE:
						break
					if run.status == RunState.Status.WAITING:
						run.answer = _pick(style, run, location, catalog)
					AdventureRunner.resolve(run, PlayerChooser.new(), now, catalog)
					now += 1.0e5
				if run.party.size() == 0:
					lost += 1
				coins += Rewards.total(run.loot, "coins")
				parts += Rewards.total(run.loot, "part")
				boxes += Rewards.total(run.loot, "box")
			var minutes := float(location.minutes)
			print("%-10s %-9s %8.1f %8.1f %8.2f %8.2f %7.0f%%" % [location.id, style, coins / TRIPS,
				coins / TRIPS / minutes, parts / TRIPS, boxes / TRIPS, 100.0 * lost / TRIPS])
	_errands(catalog, rng)
	_rummage(catalog)
	_box_tiers(catalog, rng)
	_spots(catalog)
	_gifts(catalog)
	_globes(catalog)
	_ours(catalog, rng)
	_dungeon(catalog, rng)
	quit()


## The box tiers (data/boxes.json): what a pet costs from each (in capsules, = coins on a fresh
## machine), how rare they come out, and how often a box holds one of the looks only that tier has.
func _box_tiers(catalog: Catalog, rng: RandomNumberGenerator) -> void:
	const BOXES := 20000
	var roller := PetRoller.new(catalog, rng)
	print("\nbox tiers, %d boxes each" % BOXES)
	print("%-13s %6s %9s %11s %10s %9s %10s" % ["box", "caps", "pets/box", "caps/pet", "avg rank", "rare+", "new look"])
	for box in catalog.shop_boxes():
		var looks := {}
		for l in catalog.new_looks(box.id):
			looks["%s:%s" % [l.slot, l.id]] = true
		var pets := 0
		var rank_sum := 0
		var rare := 0
		var with_look := 0
		for i in BOXES:
			var got := roller.roll_box(box.id)
			var has_look := false
			for pet in got:
				pets += 1
				rank_sum += catalog.rank(pet.rarity)
				rare += 1 if catalog.rank(pet.rarity) >= 2 else 0
				for slot in Catalog.SLOTS:
					has_look = has_look or looks.has("%s:%s" % [slot, pet.parts[slot]])
			with_look += 1 if has_look else 0
		print("%-13s %6d %9.2f %11.1f %10.2f %8.1f%% %9.1f%%" % [box.name, int(box.capsules), float(pets) / BOXES,
			float(box.capsules) * BOXES / pets, float(rank_sum) / pets, 100.0 * rare / pets, 100.0 * with_look / BOXES])


## Workers' spots (data/automation.json): what the 10th, 100th and 1000th one costs and what the
## first 10 / 100 / 1000 cost together (prices flatten past "flat_at"), and how many exist.
func _short(n: float) -> String:
	for u in [[1e15, "Q"], [1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]]:
		if n >= u[0]:
			return ("%.1f" % (n / u[0])).trim_suffix(".0") + u[1]
	return str(roundi(n))


func _spots(catalog: Catalog) -> void:
	print("\nworkers' spots: the nth one, and the first n together")
	print("%-11s %10s %10s %10s %10s %10s %10s  %s" % ["job", "10th", "100th", "1000th", "first 10", "first 100", "first 1000", "exist"])
	var pages := catalog.pages.map(func(p): return str(p.id))
	for j in catalog.automation.get("jobs", []):
		var spot: Dictionary = j.get("spot", {})
		if spot.is_empty():
			continue
		var row := [str(j.id)]
		for n in [10, 100, 1000]:
			row.append(_short(Jobs.tool_cost(spot, n - 1, 1)))
		for n in [10, 100, 1000]:
			row.append(_short(Jobs.tool_cost(spot, 0, n)))
		var exist := "1 a place" if spot.has("per_place") else "%d (all pages)" % Automation.exist(catalog, str(j.id), pages, 0)
		row.append(exist)
		print("%-11s %10s %10s %10s %10s %10s %10s  %s" % row)


## Presents (data/gifts.json), every one opened as it comes: the most they bring a day. They're a
## little extra, never the way to get boxes.
func _gifts(catalog: Catalog) -> void:
	var cfg: Dictionary = catalog.gifts
	var per_day := Gifts.per_day(cfg)
	var boxes := per_day * (1.0 + float(cfg.two_boxes))
	var price := float(catalog.box("starter").capsules)  # at the start (a capsule worth 1 coin)
	print("\npresents, one every %.1f h, a pocket of %d" % [Gifts.every(cfg) / 3600.0, Gifts.cap(cfg)])
	print("%.1f presents a day at most: %.1f boxes (%.0f coins of starter boxes), %.1f toy capsules once toys are open"
		% [per_day, boxes, boxes * price, per_day * float(cfg.toy)])
	print("away a whole day: %d presents waiting (the pocket), %.1f boxes" % [Gifts.cap(cfg), Gifts.cap(cfg) * (1.0 + float(cfg.two_boxes))])


## Rummaging in your pet's room, tapping every spot as soon as it's ready: the most it can bring.
## It should stay well under a sensible garden trip (it's something to do while trips are out).
func _rummage(catalog: Catalog) -> void:
	var coins := 0.0
	var xp := 0.0
	var parts := 0.0
	for spot in catalog.rummage_spots:
		var per_min := 60.0 / float(spot.refill)
		coins += (float(spot.coins[0]) + float(spot.coins[1])) / 2.0 * per_min
		xp += float(spot.get("xp_chance", 0.0)) * per_min
		parts += float(spot.get("part_chance", 0.0)) * per_min
	print("\nrummaging, every spot tapped as soon as it's ready")
	print("coins %.1f a minute, xp %.2f a minute, a part every %.0f min" % [coins, xp, 1.0 / parts if parts > 0.0 else INF])

## Errands (data/errands.json) for crews of common pets: coins or parts a minute, in all and per
## pet. Errands are the floor: per pet they should pay well under a sensible adventure.
func _errands(catalog: Catalog, rng: RandomNumberGenerator) -> void:
	var power := float(catalog.errands.crew_power)
	print("\nerrands, common pets (speed about 0.95). one hour each.")
	print("%-10s %6s %10s %10s %8s" % ["job", "crew", "per min", "per pet", "uncommon"])
	for job in catalog.jobs:
		if not (job.pay.has("capsules") or job.pay.has("coins") or job.pay.has("part")):
			continue  # the kitchen and scouting bring no coins or parts (see below)
		for crew in [1, 3, 5, 10, 100, 1000]:
			var got: Dictionary = Jobs.work(job, { "fill": 0.0 }, crew, Jobs.rate(job, crew, 0.95, power), 3600.0, rng, catalog)
			var kind := "coins" if job.pay.has("coins") or job.pay.has("capsules") else "part"
			var per_min := Rewards.total(got.loot, kind) / 60.0
			var uncommon := 0
			for key: String in got.loot:
				if key.begins_with("part:") and catalog.part(key.split(":")[1], key.split(":")[2]).rarity == "uncommon":
					uncommon += int(got.loot[key])
			print("%-10s %6d %10.2f %10.3f %8d" % [job.id, crew, per_min, per_min / crew, uncommon])
	# the savings jar against the coin hunt (capsules' worth an hour, a capsule = 1 coin here)
	var coin: Dictionary = catalog.job("coin_hunt")
	var jar: Dictionary = catalog.job("jar")
	print("\nsavings jar vs coin hunt, capsules' worth an hour")
	for crew in [1, 2, 5, 10, 100]:
		var c := Jobs.rate(coin, crew, 0.95, power) * 3600.0 * float(coin.pay.capsules)
		var j := Jobs.rate(jar, crew, 0.95, power) * 3600.0 * float(jar.pay.capsules)
		print("crew %4d: coin hunt %8.0f  jar %8.0f  %s" % [crew, c, j, "jar" if j > c else "coin hunt"])
	# the kitchen: how much faster the other jobs get, with this many pets on them
	var kitchen: Dictionary = catalog.job("kitchen")
	print("\nkitchen: every other job this much faster (cooks at speed 1)")
	print("%-6s %8s %8s %8s %8s" % ["cooks", "10", "100", "1000", "nobody"])
	for cooks in [1, 2, 4, 10]:
		print("%-6d %7.1f%% %7.1f%% %7.1f%% %7.1f%%" % [cooks, 100.0 * Jobs.kitchen_bonus(kitchen, cooks, 10, power),
			100.0 * Jobs.kitchen_bonus(kitchen, cooks, 100, power), 100.0 * Jobs.kitchen_bonus(kitchen, cooks, 1000, power),
			100.0 * Jobs.kitchen_bonus(kitchen, cooks, 0, power)])
	# the kitchen's meals against your pet getting hungry (it only tops food up to meal_upto)
	var decay := 100.0 / float(catalog.care.drain_hours.food)
	print("kitchen meals: food an hour vs %.0f an hour lost to hunger while open, meals stop at %.0f (full tummy above %.0f)" % [decay,
		float(kitchen.get("meal_upto", 100.0)), float(Care.buff_of(catalog, "food").above)])
	for cooks in [1, 3, 10]:
		var food := Jobs.rate(kitchen, cooks, 0.95, power) * 3600.0 * float(kitchen.pay.meal)
		print("  %2d cooks: +%.0f food an hour" % [cooks, food])


func _pick(style: String, run: RunState, location: Dictionary, catalog: Catalog) -> int:
	var event := run.current_event(catalog)
	var options := AdventureRunner.options_of(event, location)
	var allowed := AdventureRunner.allowed_options(event, run.party, location)
	var hurt := run.party.injured_count() > 0
	var best := allowed[0]
	var best_score := -INF
	for i in allowed:
		var option: Dictionary = options[i]
		if option.get("home", false):
			continue
		var chance := AdventureRunner.success_chance(option, run.party, location)
		var worth := PetVoice.reward_worth(option.success, location)
		var risky: bool = option.get("failure", {}).has("hurt")
		var score := 0.0
		match style:
			"safe":
				score = chance * 100.0 + worth * 0.01
			"sensible":
				# go for it when healthy, but never bet both hearts at once
				var both: bool = int(option.get("failure", {}).get("hearts", 1)) >= 2
				score = worth * chance - (40.0 if hurt and risky else 0.0) - (40.0 if both else 0.0)
			"greedy":
				score = worth
		if score > best_score:
			best_score = score
			best = i
	if style == "sensible" and hurt:
		var picked: Dictionary = options[best]
		if picked.get("failure", {}).has("hurt") and location.get("go_home", false):
			return options.size() - 1  # go home with the bag
	return best


## The machine globes (data/machine_tree.json): coins a pull by hand (every chute, extra balls, shiny,
## fever) and a worker's capsule on the globe behind, with the sunny globe all fixed and then after
## each sunset fix. Fixing the nest moves your hand to the sunset globe: that must never make your
## pull worse (tune the sunset globe's "step" if it does).
func _globes(catalog: Catalog) -> void:
	var state := { "bought": {}, "globes": ["sunny"] }
	for n in catalog.machine_tree.nodes:
		if Machine.globe_of(catalog, n) == Machine.first_globe(catalog):
			state.bought[n.id] = int(n.get("max", 1))
	print("\nglobes: coins a pull by hand, and a worker's capsule on the globe behind (sunny all fixed)")
	print("%-18s %-7s %14s %-7s %14s" % ["after", "hand", "coins/pull", "behind", "coins/capsule"])
	var rows: Array = [["sunny all fixed", []], ["sunset home", ["@sunset"]]]
	for n in Machine.repairs(catalog, "sunset"):
		rows.append([str(n.id), [str(n.id)]])
	var sunny_pull := 0.0
	for row in rows:
		for id in row[1]:
			if str(id).begins_with("@"):
				state.globes.append(str(id).substr(1))
			else:
				state.bought[id] = 1
		var hand := Machine.hand(state, catalog)
		var behind := Machine.behind(state, catalog)
		var pull := _per_pull(state, catalog, hand)
		var worker := _per_capsule(state, catalog, behind)
		if row[0] == "sunny all fixed":
			sunny_pull = pull
		print("%-18s %-7s %14s %-7s %14s" % [row[0], hand, _num(pull), behind, _num(worker)])
		if row[0] == "nest":
			var ok := pull >= sunny_pull
			print("  %s: the nest %s (x%.2f)" % ["ok" if ok else "WORSE", "keeps your pull at least as good" if ok else "makes your pull worse: tune the sunset step", pull / maxf(sunny_pull, 0.001)])


## Coins in one capsule from a globe on average (coins and golden capsules, shiny ones pay more).
func _per_capsule(state: Dictionary, catalog: Catalog, g: String) -> float:
	var odds := Machine.odds(state, catalog, func(_k): return true, false, 1.0, 1.0, false, 1.0, g)
	var coins := 0.0
	for p in catalog.machine.prizes:
		if p.kind in ["coins", "golden"]:
			coins += float(odds.get(p.id, 0.0)) * (float(p.coins[0]) + float(p.coins[1])) / 2.0
	var shiny := 1.0 + Machine.shiny_chance(state, catalog, g) * (Machine.shiny_pay(state, catalog, g) - 1.0)
	return coins * Machine.coin_value(state, catalog, g) * shiny


## Coins in one pull by hand: every chute's capsules, and fever once the lights work.
func _per_pull(state: Dictionary, catalog: Catalog, g: String) -> float:
	var balls := 1.0 + Machine.add(state, catalog, "double", g) + 2.0 * Machine.add(state, catalog, "triple", g)
	var fever := 1.0
	if Machine.lights_on(state, catalog, g):
		var lights := float(Machine.lights_needed(state, catalog))
		var fever_pulls := Machine.fever_for(state, catalog, 1.0, 1.0, g) / Machine.reveal_seconds(state, catalog)
		fever = (lights + fever_pulls * (float(catalog.machine.fever_pay) - 1.0)) / lights
	return Machine.chutes(state, catalog, g) * balls * _per_capsule(state, catalog, g) * fever


static func _num(n: float) -> String:
	for u in [[1e12, "T"], [1e9, "B"], [1e6, "M"], [1e3, "k"]]:
		if n >= u[0]:
			return "%.1f%s" % [n / u[0], u[1]]
	return "%.1f" % n


## Next door (E2): a party of commons at each garden by the rules, before and after the place is
## ours (safer, pays more, no locals).
func _ours(catalog: Catalog, rng: RandomNumberGenerator) -> void:
	const RUNS := 300
	var roller := PetRoller.new(catalog, rng)
	var party: Array[Pet] = []
	for i in 20:
		party.append(roller.roll("starter", "common"))
	print("\nnext door, 20 commons by the rules, %d trips each" % RUNS)
	print("%-11s %6s %10s %10s %8s %8s" % ["place", "ours", "coins", "per min", "home", "boxes"])
	for location in catalog.locations:
		if location.page != "next_door":
			continue
		for ours in ([true] if location.get("ours_at_start", false) else [false, true]):  # ours from the start: never met otherwise
			var coins := 0.0
			var home := 0.0
			var boxes := 0.0
			for t in RUNS:
				var run := AdventureRunner.start(location.id, party, 0.0, t, catalog, {}, {}, {}, {}, 0, ours)
				AdventureRunner.resolve(run, PolicyChooser.new(), INF, catalog)
				coins += Rewards.total(run.loot, "coins")
				boxes += Rewards.total(run.loot, "box")
				home += run.party.size() / float(party.size())
			print("%-11s %6s %10.0f %10.0f %7.0f%% %8.2f" % [location.id, "yes" if ours else "no", coins / RUNS,
				coins / RUNS / float(location.minutes), 100.0 * home / RUNS, boxes / RUNS])


## The old well's dungeon (data/dungeon.json): armies of a front row of 20 cards and 280 from the
## herd (average stats for their rarity), sent to floor 40, coming home when half are gone, the
## herd first. How deep they get, what a run pays and costs, and wisps an hour of runs back to back.
func _dungeon(catalog: Catalog, rng: RandomNumberGenerator) -> void:
	const RUNS := 300
	print("\nthe old well: 20 cards in front + 280 from the herd, down to floor 40, home when 50%% are gone, the herd first. %d runs each." % RUNS)
	print("%-20s %8s %8s %8s %8s %10s" % ["army", "floor", "deepest", "wisps", "lost", "wisps/h"])
	for mix in [["common", "common"], ["uncommon", "common"], ["rare", "uncommon"], ["epic", "rare"], ["legendary", "epic"]]:
		var front := Herd.template(catalog, Herd.key(mix[0], "normal"))
		var cards: Array = []
		for i in 20:
			cards.append({ "uid": str(i), "power": Dungeon.pet_power(catalog, front), "rank": catalog.rank(mix[0]) })
		var k := Herd.key(mix[1], "normal")
		var army := { "cards": cards, "herd": { k: { "n": 280, "power": Dungeon.pet_power(catalog, Herd.template(catalog, k)), "rank": catalog.rank(mix[1]) } },
			"luck": Dungeon.knock_chance(catalog, float(front.stats.luck)), "boost": 1.0 }
		var floors := 0.0
		var deepest := 0
		var wisps := 0.0
		var lost := 0.0
		var seconds := 0.0
		for r in RUNS:
			var run := Dungeon.simulate(catalog, army, { "target": 40, "home_at": 50, "first": "plain ones" }, rng)
			var to := Dungeon.cleared_to(run)
			floors += to
			deepest = maxi(deepest, to)
			wisps += Dungeon.run_pay(run)
			var gone := Dungeon.run_lost(run)
			lost += gone[0].size() + Herd.total(gone[1])
			seconds += Dungeon.run_seconds(catalog, run)
		print("%-20s %8.1f %8d %8.0f %8.0f %10.0f" % ["%s + %s" % mix, floors / RUNS, deepest, wisps / RUNS, lost / RUNS, wisps / (seconds / 3600.0)])
