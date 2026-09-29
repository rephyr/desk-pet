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
	var box_price := float(catalog.box("starter").price)
	print("one pet (a common), %d trips each. a box costs %d. passive income is about 6 coins a minute." % [TRIPS, box_price])
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
	var rates := _dungeon(catalog, rng)
	_sewing(catalog, rng)
	_perks(catalog, rates)
	quit()


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
		for crew in [1, 3, 5, 10, 100, 1000]:
			var got: Dictionary = Jobs.work(job, { "fill": 0.0 }, crew, Jobs.rate(job, crew, 0.95, power), 3600.0, rng, catalog)
			var kind := "coins" if job.pay.has("coins") else "part"
			var per_min := Rewards.total(got.loot, kind) / 60.0
			var uncommon := 0
			for key: String in got.loot:
				if key.begins_with("part:") and catalog.part(key.split(":")[1], key.split(":")[2]).rarity == "uncommon":
					uncommon += int(got.loot[key])
			print("%-10s %6d %10.2f %10.3f %8d" % [job.id, crew, per_min, per_min / crew, uncommon])


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


## The old well's dungeon (data/dungeon.json): armies of a front row of 20 cards and 280 from the
## herd (average stats for their rarity), sent to floor 40, coming home when half are gone, the
## herd first. How deep they get, what a run pays and costs, and wisps an hour of runs back to back.
func _dungeon(catalog: Catalog, rng: RandomNumberGenerator) -> Array:
	const RUNS := 300
	var rates: Array = []  # [army, deepest floor, wisps an hour], for the perks table
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
		rates.append(["%s + %s" % mix, deepest, wisps / (seconds / 3600.0)])
	return rates


## The wisps perks on the well wall (data/perks.json): each link's prices, the first army from the
## well's table that gets down to its nail, and the hours of that army's runs back to back to buy
## every level (no perks counted in: an army with them earns faster). Then the tips' prices.
func _perks(catalog: Catalog, rates: Array) -> void:
	print("\nthe wisps perks: every level's price, the first army deep enough for the nail, hours of its runs to buy them all.")
	print("%-12s %5s %-34s %-20s %8s %7s" % ["perk", "floor", "prices", "army", "wisps/h", "hours"])
	var total := 0.0
	for p in Perks.chain(catalog):
		var rate: Array = []
		for r in rates:
			if int(r[1]) >= int(p.floor):
				rate = r
				break
		if rate.is_empty():
			rate = rates.back()
		var sum := 0.0
		for c in p.price:
			sum += float(c)
		var hours := sum / maxf(float(rate[2]), 1.0)
		total += hours
		print("%-12s %5d %-34s %-20s %8.0f %7.1f" % [p.id, int(p.floor), " ".join(p.price.map(func(c): return _short(float(c)))), rate[0], float(rate[2]), hours])
	print("the whole chain: %.1f hours of runs" % total)
	var top: Array = rates.back()
	for t in Perks.tips(catalog):
		var row := "%-12s" % t.id
		for lv in [0, 3, 6, 10]:
			var price := Perks.price(catalog, { str(t.id): lv }, str(t.id))
			row += "  lv %d: %s (%.1f h)" % [lv, _short(float(price)), price / maxf(float(top[2]), 1.0)]
		print(row)

## E3 the sewing room (data/sewing.json): the same armies as the well, into each fixed room and the
## first rolled ones (chalk locks left out: this is only the fight). How often each clears it, and
## the wisps an hour of that room back to back (a run is 'seconds' long).
func _sewing(catalog: Catalog, rng: RandomNumberGenerator) -> void:
	const RUNS := 200
	var n := Sewing.fixed_count(catalog) + 3
	print("\nthe sewing room: the same armies, one fight per room, %d runs each. %% cleared (wisps an hour), rooms by the floor their strength is at." % RUNS)
	var head := "%-20s" % "army"
	for i in n:
		head += " %11s" % ("%s%d" % ["r" if Sewing.room(catalog, i).rolled else "", int(Sewing.room(catalog, i).floor)])
	print(head)
	for mix in [["uncommon", "common"], ["rare", "uncommon"], ["epic", "rare"], ["legendary", "epic"], ["mythic", "legendary"]]:
		var front := Herd.template(catalog, Herd.key(mix[0], "normal"))
		var cards: Array = []
		for i in 20:
			cards.append({ "uid": str(i), "power": Dungeon.pet_power(catalog, front), "rank": catalog.rank(mix[0]) })
		var k := Herd.key(mix[1], "normal")
		var army := { "cards": cards, "herd": { k: { "n": 280, "power": Dungeon.pet_power(catalog, Herd.template(catalog, k)), "rank": catalog.rank(mix[1]) } },
			"luck": 0.5, "boost": 1.0 }
		var row := "%-20s" % ("%s + %s" % mix)
		for i in n:
			var r := Sewing.room(catalog, i)
			var cleared := 0
			var wisps := 0.0
			for t in RUNS:
				var run := Sewing.simulate(catalog, army, r, { "first": "plain ones" }, rng)
				cleared += 1 if Dungeon.cleared_to(run) > 0 else 0
				wisps += Dungeon.run_pay(run)
			row += " %4d%% %5s" % [roundi(100.0 * cleared / RUNS), _short(wisps / RUNS * 3600.0 / Sewing.seconds(catalog))]
		print(row)


func _short(n: float) -> String:
	if n >= 1.0e6:
		return "%.1fM" % (n / 1.0e6)
	if n >= 1000.0:
		return "%.1fk" % (n / 1000.0)
	return "%d" % roundi(n)
