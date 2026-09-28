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
	var decay := float(load("res://scripts/game_state.gd").HUNGER_DECAY) * 3600.0
	print("kitchen meals: food an hour vs %.0f an hour lost to hunger, meals stop at %.0f" % [decay, float(kitchen.get("meal_upto", 100.0))])
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
