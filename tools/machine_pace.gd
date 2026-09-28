extends SceneTree
## How long fixing up the capsule machine takes, for pacing the early game (data/machine.json,
## data/machine_tree.json). A player pulls steadily (the lever takes LEVER_SECONDS, then the
## capsules' reveal) and buys the cheapest node they can the moment they can. Once adventures are
## open (after "oil the lever", see data/tutorial.json) a pet brings home one bit every
## BIT_EVERY seconds, the kind the player needs most (they pick where to go by it).
## Prints the minute each node is bought, averaged over RUNS players.
##   godot --headless -s tools/machine_pace.gd

const LEVER_SECONDS := 0.9
const BIT_EVERY := 150.0
const RUNS := 30
const MINUTES := 90.0


func _init() -> void:
	var catalog := Catalog.new()
	var m: Dictionary = catalog.machine
	var bought_at := {}  # "node level" -> [minutes]
	var order := []
	var pet_boxes := 0  # boxes with a pet inside, over every run
	for run in RUNS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 100 + run
		var state := { "pulls": 0, "lit": 0, "bought": {} }
		var coins := 0.0
		var bits := {}
		var t := 0.0
		var next_bit := -1.0
		var fever_until := -1.0
		while t < MINUTES * 60.0:
			t += LEVER_SECONDS + Machine.reveal_seconds(state, catalog)
			state.pulls += 1
			var lucky := false
			if Machine.lights_on(state, catalog):
				state.lit += 1
				lucky = state.lit >= Machine.lights_needed(state, catalog)
				if lucky:
					state.lit = 0
			var pay := float(m.fever_pay) if t < fever_until else 1.0
			for chute in Machine.chutes(state, catalog):
				for ball in Machine.balls_from_chute(state, catalog, rng):
					var prize := Machine.roll(state, catalog, rng, lucky)
					if prize.kind == "pet_box":
						if chute == 0 and ball == 0:
							pet_boxes += 1  # only a pull's first capsule can hold one
						else:
							prize = catalog.machine.prizes[0]
					var loot := Machine.loot(prize, state, catalog, rng, pay)
					var c := float(loot.get("coins", 0))
					if rng.randf() < Machine.shiny_chance(state, catalog):
						c *= Machine.shiny_pay(state, catalog)
					coins += c
			if lucky:
				fever_until = t + Machine.fever_seconds(state, catalog)
			# adventures bring bits once they're open
			if next_bit < 0.0 and Machine.owned(state, "oil") > 0:
				next_bit = t + BIT_EVERY
			if next_bit > 0.0 and t >= next_bit:
				next_bit += BIT_EVERY
				var want := _wanted_bit(state, catalog, bits)
				bits[want] = int(bits.get(want, 0)) + 1
			# buy the cheapest node you can
			var best := ""
			for n in catalog.machine_tree.nodes:
				if Machine.blocker(state, catalog, n.id, int(coins), bits) != "":
					continue
				if best == "" or Machine.cost(state, catalog, n.id) < Machine.cost(state, catalog, best):
					best = n.id
			if best != "":
				coins -= Machine.cost(state, catalog, best)
				var need := Machine.bits_cost(catalog, best)
				for b in need:
					bits[b] = int(bits[b]) - int(need[b])
				state.bought[best] = Machine.owned(state, best) + 1
				var key := "%s %d" % [best, state.bought[best]]
				if not bought_at.has(key):
					bought_at[key] = []
					order.append(key)
				bought_at[key].append(t / 60.0)
	print("minute  node (reached by how many of %d players)" % RUNS)
	var rows := []
	for key in order:
		var a: Array = bought_at[key]
		rows.append([a.reduce(func(x, y): return x + y, 0.0) / a.size(), key, a.size()])
	rows.sort_custom(func(a, b): return a[0] < b[0])
	for r in rows:
		print("%6.1f  %s (%d)" % r)
	print("pet boxes: %.1f a player in %d minutes (the safety net for running out of pets not counted)" % [float(pet_boxes) / RUNS, int(MINUTES)])
	quit()


## The bit the player needs most: the first one a "next" node is short of.
func _wanted_bit(state: Dictionary, catalog: Catalog, bits: Dictionary) -> String:
	for n in catalog.machine_tree.nodes:
		if Machine.look(state, catalog, n.id) == "next" and not Machine.maxed(state, catalog, n.id):
			var need := Machine.bits_cost(catalog, n.id)
			for b in need:
				if int(bits.get(b, 0)) < int(need[b]):
					return b
	return "gear"
