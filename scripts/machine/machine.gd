class_name Machine
extends RefCounted
## The capsule machine's rules: what a pull rolls and pays (data/machine.json) and the upgrade tree
## you fix it up with (data/machine_tree.json). Works on the machine's state from the save:
##   { pulls: all pulls ever, lit: lucky lights lit right now, bought: { node id: level },
##     globes: [globe ids you have], greeted: [globe ids the machine tab has shown arriving] }
## GameState.pull_lever() uses this; the machine tab draws it.
##
## GLOBES: a globe per map page (sunny, sunset, midnight: machine_tree.json "globes"). A later one
## comes home broken; once its "works" repair is fixed it's the HAND globe (the newest working one,
## the one you pull), and the one before it is the BEHIND globe (your pet, workers and errands).
## Everything that depends on the globe takes `globe` ("" = the hand globe).

## The tree's branches (bits live in machine_tree.json "bits").
const BRANCHES := ["repair", "coins", "chutes", "balls", "shiny", "lights", "drops", "sunset"]
## Effects that only count on their own globe; every other effect counts on its own globe and on
## every newer one (a sunset globe gets the sunny globe's coins, extra balls, shiny, fever, drops).
const OWN_GLOBE := ["chutes", "lights", "glass"]
## The prize a capsule holds when its own kind can't come out yet (GameState._capsule swaps to it).
const FALLBACK_PRIZE := "coins"


# ---- globes ----------------------------------------------------------------------------

## Every globe in the data, oldest first (a catalog without any has just the sunny one).
static func globes(catalog: Catalog) -> Array:
	var g: Array = catalog.machine_tree.get("globes", [])
	return g if not g.is_empty() else [{ "id": "sunny", "name": "sunny globe", "hatch": "drops", "step": 1 }]


static func globe(catalog: Catalog, id: String) -> Dictionary:
	for g in globes(catalog):
		if g.id == id:
			return g
	return {}


static func first_globe(catalog: Catalog) -> String:
	return str(globes(catalog)[0].id)


## Where a globe is in the line (0 the first), or -1 for one that isn't in the data.
static func globe_rank(catalog: Catalog, id: String) -> int:
	var all := globes(catalog)
	for i in all.size():
		if all[i].id == id:
			return i
	return -1


## The globe a node of the tree belongs to.
static func globe_of(catalog: Catalog, n: Dictionary) -> String:
	return str(n.get("globe", first_globe(catalog)))


## The globe that comes home with a find, or "".
static func globe_for_find(catalog: Catalog, find_id: String) -> String:
	for g in globes(catalog):
		if str(g.get("find", "")) == find_id and find_id != "":
			return str(g.id)
	return ""


## The globes you have, oldest first (the first one is always there).
static func home(state: Dictionary, catalog: Catalog) -> Array[String]:
	var have: Array = state.get("globes", [])
	var out: Array[String] = []
	for g in globes(catalog):
		if out.is_empty() or have.has(g.id):
			out.append(str(g.id))
	return out


static func has_globe(state: Dictionary, catalog: Catalog, id: String) -> bool:
	return home(state, catalog).has(id)


## Whether a globe works (its "works" repair is fixed; the first globe always works).
static func works(state: Dictionary, catalog: Catalog, id: String) -> bool:
	var w := str(globe(catalog, id).get("works", ""))
	return w == "" or owned(state, w) > 0


## The newest globe you have, broken or not.
static func newest(state: Dictionary, catalog: Catalog) -> String:
	return home(state, catalog).back()


## The globes you have that work, oldest first.
static func working(state: Dictionary, catalog: Catalog) -> Array[String]:
	var out: Array[String] = []
	for g in home(state, catalog):
		if out.is_empty() or works(state, catalog, g):
			out.append(g)
	return out


## The globe you pull by hand: the newest one that works.
static func hand(state: Dictionary, catalog: Catalog) -> String:
	return working(state, catalog).back()


## The globe your pet, workers and errands use: the one before the hand globe (the hand globe
## while it's the only one that works).
static func behind(state: Dictionary, catalog: Catalog) -> String:
	var w := working(state, catalog)
	return w[w.size() - 2] if w.size() >= 2 else w[0]


static func _g(state: Dictionary, catalog: Catalog, g: String) -> String:
	return g if g != "" else hand(state, catalog)


## Whether a globe's rusted hatch is open.
static func hatch_open(state: Dictionary, catalog: Catalog, id: String) -> bool:
	var h := str(globe(catalog, id).get("hatch", ""))
	return h != "" and owned(state, h) > 0


## The box tier a globe's box and pet box prizes are: the newest open hatch from this globe down
## (a globe drops what the one before it drops until its own hatch opens).
static func box_of(state: Dictionary, catalog: Catalog, g := "") -> String:
	var all := globes(catalog)
	var i := globe_rank(catalog, _g(state, catalog, g))
	while i >= 0:
		if hatch_open(state, catalog, str(all[i].id)) and all[i].has("box"):
			return str(all[i].box)
		i -= 1
	return str(all[0].get("box", "starter"))


## The toy sets (data/toys.json) a globe's toys come from: the first globe's always, and every
## later globe's up to this one once its hatch is open.
static func toy_sets(state: Dictionary, catalog: Catalog, g := "") -> Array[String]:
	var rank := globe_rank(catalog, _g(state, catalog, g))
	var first := first_globe(catalog)
	var out: Array[String] = []
	for s in catalog.toys.get("sets", []):
		var sg := str(s.get("globe", first))
		if sg == first or (globe_rank(catalog, sg) <= rank and hatch_open(state, catalog, sg)):
			out.append(str(s.id))
	return out


## What a globe's capsules are worth next to the first globe's: its "step".
static func step(catalog: Catalog, g: String) -> float:
	return float(globe(catalog, g).get("step", 1.0))


# ---- bits -------------------------------------------------------------------------------

## Every machine bit id, in the data's order.
static func all_bits(catalog: Catalog) -> Array[String]:
	var out: Array[String] = []
	for b in catalog.machine_tree.get("bits", {}):
		out.append(str(b))
	return out


## The bits a globe's repairs ask for (the bits pills show the newest globe's).
static func bits_of(catalog: Catalog, g: String) -> Array[String]:
	var first := first_globe(catalog)
	var out: Array[String] = []
	var bits: Dictionary = catalog.machine_tree.get("bits", {})
	for b in bits:
		if str(bits[b].get("globe", first)) == g:
			out.append(str(b))
	return out


static func bit_info(catalog: Catalog, id: String) -> Dictionary:
	return catalog.machine_tree.get("bits", {}).get(id, {})


## A bit's name for `n` of them: "1 cork", "2 corks", "2 amber glass".
static func bit_name(catalog: Catalog, id: String, n: int) -> String:
	var info := bit_info(catalog, id)
	if info.is_empty():
		return id if n == 1 else id + "s"
	return str(info.get("name", id)) if n == 1 else str(info.get("plural", info.get("name", id)))


# ---- the tree -------------------------------------------------------------------------

static func node(catalog: Catalog, id: String) -> Dictionary:
	for n in catalog.machine_tree.nodes:
		if n.id == id:
			return n
	return {}


static func owned(state: Dictionary, id: String) -> int:
	return int(state.get("bought", {}).get(id, 0))


static func maxed(state: Dictionary, catalog: Catalog, id: String) -> bool:
	var n := node(catalog, id)
	return not n.is_empty() and owned(state, id) >= int(n.get("max", 1))


## How a node shows on the tree: "owned" (fixed, at least one level), "next" (what it grows from is
## fixed: you can work on it), "dim" (you can see it coming, not yet), "hidden" (a "?") or "away"
## (its globe isn't home yet: not there at all).
static func look(state: Dictionary, catalog: Catalog, id: String) -> String:
	var n := node(catalog, id)
	if n.is_empty():
		return "hidden"
	if not has_globe(state, catalog, globe_of(catalog, n)):
		return "away"
	if owned(state, id) > 0:
		return "owned"
	var from := str(n.get("from", ""))
	if from == "" or owned(state, from) > 0:
		return "next"
	if look(state, catalog, from) == "next":
		return "dim"
	# a later globe's repairs are one short chain you see whole once the globe is home (its fixes
	# list shows every one of them)
	if globe_of(catalog, n) != first_globe(catalog) and globe_of(catalog, node(catalog, from)) == globe_of(catalog, n):
		return "dim"
	return "hidden"


## Coins for the next level of a node (0 when it's maxed or there's no such node).
static func cost(state: Dictionary, catalog: Catalog, id: String) -> int:
	var n := node(catalog, id)
	if n.is_empty() or maxed(state, catalog, id):
		return 0
	return roundi(float(n.coins) * pow(float(n.get("grow", 1.0)), owned(state, id)))


## Bits for the next level of a node, e.g. { "spring": 1 }.
static func bits_cost(catalog: Catalog, id: String) -> Dictionary:
	return node(catalog, id).get("bits", {})


## Why you can't buy the next level right now ("" when you can): "maxed", "locked", "coins", or
## the id of a bit you're short of.
static func blocker(state: Dictionary, catalog: Catalog, id: String, coins: int, bits: Dictionary) -> String:
	if maxed(state, catalog, id):
		return "maxed"
	if look(state, catalog, id) not in ["next", "owned"]:
		return "locked"
	var need := bits_cost(catalog, id)
	for b in need:
		if int(bits.get(b, 0)) < int(need[b]):
			return str(b)
	if coins < cost(state, catalog, id):
		return "coins"
	return ""


## Whether a node's effect `key` counts on globe `g`: on its own globe, and (except OWN_GLOBE
## effects) on every newer one.
static func counts(catalog: Catalog, n: Dictionary, key: String, g: String) -> bool:
	var ng := globe_of(catalog, n)
	if ng == g:
		return true
	return not key in OWN_GLOBE and globe_rank(catalog, ng) <= globe_rank(catalog, g)


## Everything bought multiplied together for one effect on a globe (1.0 when nothing has it),
## e.g. coins_x.
static func mult(state: Dictionary, catalog: Catalog, key: String, g := "") -> float:
	g = _g(state, catalog, g)
	var m := 1.0
	for n in catalog.machine_tree.nodes:
		var level := owned(state, n.id)
		if level > 0 and n.each.has(key) and counts(catalog, n, key, g):
			m *= pow(float(n.each[key]), level)
	return m


## Everything bought added up for one effect on a globe (0 when nothing has it), e.g. chutes, shiny.
static func add(state: Dictionary, catalog: Catalog, key: String, g := "") -> float:
	g = _g(state, catalog, g)
	var total := 0.0
	for n in catalog.machine_tree.nodes:
		var level := owned(state, n.id)
		if level > 0 and n.each.has(key) and counts(catalog, n, key, g):
			total += float(n.each[key]) * level
	return total


## Whether any node of a globe has this effect (fixed or not).
static func has_effect(catalog: Catalog, key: String, g: String) -> bool:
	return catalog.machine_tree.nodes.any(func(n): return globe_of(catalog, n) == g and n.each.has(key))


## Whether something on a globe's picture is still broken: a node of that globe that "fixes" it
## isn't fixed yet.
static func broken(state: Dictionary, catalog: Catalog, g: String, fix: String) -> bool:
	return catalog.machine_tree.nodes.any(func(n): return globe_of(catalog, n) == g and str(n.get("fixes", "")) == fix and owned(state, n.id) <= 0)


## Whether a globe has something to fix called `fix` at all (fixed or not).
static func has_fix(catalog: Catalog, g: String, fix: String) -> bool:
	return catalog.machine_tree.nodes.any(func(n): return globe_of(catalog, n) == g and str(n.get("fixes", "")) == fix)


## A globe's repairs (its own nodes), in the data's order; the sunset fixes list.
static func repairs(catalog: Catalog, g: String) -> Array:
	return catalog.machine_tree.nodes.filter(func(n): return globe_of(catalog, n) == g)


## Whether a globe still has repairs left.
static func repairs_left(state: Dictionary, catalog: Catalog, g: String) -> bool:
	return repairs(catalog, g).any(func(n): return not maxed(state, catalog, n.id))


## Machine upgrades bought, every level counted.
static func levels(state: Dictionary) -> int:
	var total := 0
	for id in state.get("bought", {}):
		total += int(state.bought[id])
	return total


# ---- what it does now ------------------------------------------------------------------

## Coins in a plain capsule from a globe: base x every coins_x that counts there x its step.
static func coin_value(state: Dictionary, catalog: Catalog, g := "") -> float:
	g = _g(state, catalog, g)
	return float(catalog.machine_tree.get("base_coins", 1)) * mult(state, catalog, "coins_x", g) * step(catalog, g)


static func chutes(state: Dictionary, catalog: Catalog, g := "") -> int:
	return 1 + int(add(state, catalog, "chutes", g))


## Whether a pull can drop more than one capsule (another chute, or double / triple drop).
static func many_capsules(state: Dictionary, catalog: Catalog, g := "") -> bool:
	g = _g(state, catalog, g)
	return chutes(state, catalog, g) > 1 or add(state, catalog, "double", g) > 0.0 or add(state, catalog, "triple", g) > 0.0


## Whether a globe's lucky lights work (and so fever).
static func lights_on(state: Dictionary, catalog: Catalog, g := "") -> bool:
	return add(state, catalog, "lights", g) > 0.0


## How many lucky lights have to be lit for a lucky capsule and fever.
static func lights_needed(_state: Dictionary, catalog: Catalog) -> int:
	return int(catalog.machine.lights)


static func fever_seconds(state: Dictionary, catalog: Catalog, g := "") -> float:
	return float(catalog.machine.fever_seconds) + add(state, catalog, "fever_s", g)


## The longest a fever can last at normal capsule speed: a bit less than lighting every light
## again takes (a pull a capsule, "fever_burst" of lights x capsule seconds), so fever stays a burst
## and never chains into the next one.
static func fever_cap(state: Dictionary, catalog: Catalog) -> float:
	return lights_needed(state, catalog) * reveal_seconds(state, catalog) * float(catalog.machine.fever_burst)


## How long a fever that starts now lasts: the tree's fever seconds times your toys' fever boost,
## never past fever_cap, then divided by `speed` (toys that make capsules quicker): fever counts in
## pulls, so a speed toy gives the same number of fever pulls in less time and every longer fever
## level still adds pulls.
static func fever_for(state: Dictionary, catalog: Catalog, fever_boost := 1.0, speed := 1.0, g := "") -> float:
	return minf(fever_seconds(state, catalog, g) * fever_boost, fever_cap(state, catalog)) / maxf(speed, 0.01)


## Chance a ball is shiny on a globe (only once that globe has its glass, if it has glass to fix),
## and how much a shiny one multiplies what it holds.
static func shiny_chance(state: Dictionary, catalog: Catalog, g := "") -> float:
	g = _g(state, catalog, g)
	if has_effect(catalog, "glass", g) and add(state, catalog, "glass", g) <= 0.0:
		return 0.0
	return add(state, catalog, "shiny", g)


static func shiny_pay(state: Dictionary, catalog: Catalog, g := "") -> float:
	return 2.0 + add(state, catalog, "shiny_x", g)


## How many balls come out of one chute on a pull: 1, sometimes 2 or 3 (extra-ball upgrades).
static func balls_from_chute(state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator, g := "") -> int:
	g = _g(state, catalog, g)
	var r := rng.randf()
	var triple := add(state, catalog, "triple", g)
	if r < triple:
		return 3
	if r < triple + add(state, catalog, "double", g):
		return 2
	return 1


## Seconds from the clunk until a capsule pops open (and the lever can be pulled again).
static func reveal_seconds(_state: Dictionary, catalog: Catalog) -> float:
	return float(catalog.machine.reveal_seconds)


## Seconds the lever takes to spring back up after a pull.
static func spring_seconds(_state: Dictionary, catalog: Catalog) -> float:
	return float(catalog.machine.spring_seconds)


# ---- one capsule ------------------------------------------------------------------------

## Rolls one capsule's prize. `lucky`: the lucky lights were all lit, only lucky prizes.
## Prizes that need better drops ("drops") only join once it's fixed. `toy_luck` (your toys' luck)
## makes lucky prizes weigh more, `toy_rate` makes toys weigh more.
static func roll(state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator, lucky := false, toy_luck := 1.0, toy_rate := 1.0, g := "") -> Dictionary:
	var drops := add(state, catalog, "drops", g)
	var weights := {}
	var prizes: Array = catalog.machine.prizes
	for i in prizes.size():
		var p: Dictionary = prizes[i]
		if lucky and not p.get("lucky", false):
			continue
		if drops < float(p.get("drops", 0)):
			continue
		weights[i] = float(p.weight) * (toy_luck if p.get("lucky", false) else 1.0) * (toy_rate if p.kind == "toy" else 1.0)
	return prizes[Weighted.pick(weights, rng)]


## The chance of each prize (by id) in one capsule, adding up to 1: the same weights roll() uses.
## `gives` says whether a kind of prize can come out yet (a kind that can't comes out as coins, the
## way GameState._capsule swaps it). `first`: the pull's first capsule, the only one that can hold a
## pet box (in any other it's coins too). For the machine's prize card.
static func odds(state: Dictionary, catalog: Catalog, gives: Callable, lucky := false, toy_luck := 1.0, toy_rate := 1.0, first := true, g := "") -> Dictionary:
	var drops := add(state, catalog, "drops", g)
	var weights := {}
	for p: Dictionary in catalog.machine.prizes:
		if lucky and not p.get("lucky", false):
			continue
		if drops < float(p.get("drops", 0)):
			continue
		var w := float(p.weight) * (toy_luck if p.get("lucky", false) else 1.0) * (toy_rate if p.kind == "toy" else 1.0)
		var opens: bool = gives.call(str(p.kind)) and (first or p.kind != "pet_box")
		var id := str(p.id) if opens else FALLBACK_PRIZE
		weights[id] = float(weights.get(id, 0.0)) + w
	return Weighted.chances(weights)


## What a prize pays, e.g. { "coins": 4 }, { "xp": 1 }, { "part:eyes:round": 1 }, { "box:starter": 1 }.
## `pay` multiplies coins (fever); coins are also worth the globe's coin value, and a box is the
## globe's box tier (box_of). A toy or a pet pays {} here: GameState makes those.
static func loot(prize: Dictionary, state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator, pay := 1.0, g := "") -> Dictionary:
	match str(prize.kind):
		"coins", "golden":
			var n := rng.randi_range(int(prize.coins[0]), int(prize.coins[1]))
			return { "coins": maxi(1, roundi(n * coin_value(state, catalog, g) * pay)) }
		"xp":
			return { "xp": int(prize.get("amount", 1)) }
		"part":
			return { "part:%s:%s" % Rewards.roll_part(Jobs.COMMON_BOX, rng, catalog): 1 }
		"box":
			return { "box:%s" % box_of(state, catalog, g): 1 }
	return {}
