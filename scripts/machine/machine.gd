class_name Machine
extends RefCounted
## The capsule machine's rules: what a pull rolls and pays (data/machine.json) and the upgrade tree
## you fix it up with (data/machine_tree.json). Works on the machine's state from the save:
##   { pulls: all pulls ever, lit: lucky lights lit right now, bought: { node id: level } }
## GameState.pull_lever() uses this; the machine tab draws it.

## Machine bits pets bring home from adventures, and the tree's branches.
const BITS := ["gear", "spring", "bolt", "glass"]
const BRANCHES := ["repair", "coins", "chutes", "balls", "shiny", "lights", "drops"]


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
## fixed: you can work on it), "dim" (you can see it coming, not yet) or "hidden" (a "?").
static func look(state: Dictionary, catalog: Catalog, id: String) -> String:
	var n := node(catalog, id)
	if n.is_empty():
		return "hidden"
	if owned(state, id) > 0:
		return "owned"
	var from := str(n.get("from", ""))
	if from == "" or owned(state, from) > 0:
		return "next"
	if look(state, catalog, from) == "next":
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


## Everything bought multiplied together for one effect (1.0 when nothing has it), e.g. coins_x.
static func mult(state: Dictionary, catalog: Catalog, key: String) -> float:
	var m := 1.0
	for n in catalog.machine_tree.nodes:
		var level := owned(state, n.id)
		if level > 0 and n.each.has(key):
			m *= pow(float(n.each[key]), level)
	return m


## Everything bought added up for one effect (0 when nothing has it), e.g. chutes, shiny.
static func add(state: Dictionary, catalog: Catalog, key: String) -> float:
	var total := 0.0
	for n in catalog.machine_tree.nodes:
		total += float(n.each.get(key, 0.0)) * owned(state, n.id)
	return total


## Machine upgrades bought, every level counted.
static func levels(state: Dictionary) -> int:
	var total := 0
	for id in state.get("bought", {}):
		total += int(state.bought[id])
	return total


# ---- what it does now ------------------------------------------------------------------

## Coins in a plain capsule.
static func coin_value(state: Dictionary, catalog: Catalog) -> float:
	return float(catalog.machine_tree.get("base_coins", 1)) * mult(state, catalog, "coins_x")


static func chutes(state: Dictionary, catalog: Catalog) -> int:
	return 1 + int(add(state, catalog, "chutes"))


## Whether the lucky lights work (and so fever).
static func lights_on(state: Dictionary, catalog: Catalog) -> bool:
	return add(state, catalog, "lights") > 0.0


## How many lucky lights have to be lit for a lucky capsule and fever.
static func lights_needed(_state: Dictionary, catalog: Catalog) -> int:
	return int(catalog.machine.lights)


static func fever_seconds(state: Dictionary, catalog: Catalog) -> float:
	return float(catalog.machine.fever_seconds) + add(state, catalog, "fever_s")


## Chance a ball is shiny, and how much a shiny one multiplies what it holds.
static func shiny_chance(state: Dictionary, catalog: Catalog) -> float:
	return add(state, catalog, "shiny")


static func shiny_pay(state: Dictionary, catalog: Catalog) -> float:
	return 2.0 + add(state, catalog, "shiny_x")


## How many balls come out of one chute on a pull: 1, sometimes 2 or 3 (extra-ball upgrades).
static func balls_from_chute(state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator) -> int:
	var r := rng.randf()
	var triple := add(state, catalog, "triple")
	if r < triple:
		return 3
	if r < triple + add(state, catalog, "double"):
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
static func roll(state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator, lucky := false, toy_luck := 1.0, toy_rate := 1.0) -> Dictionary:
	var drops := add(state, catalog, "drops")
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


## What a prize pays, e.g. { "coins": 4 }, { "xp": 1 }, { "part:eyes:round": 1 }, { "box:starter": 1 }.
## `pay` multiplies coins (fever); coins are also worth the machine's coin value. A toy or a pet pays
## {} here: GameState makes those.
static func loot(prize: Dictionary, state: Dictionary, catalog: Catalog, rng: RandomNumberGenerator, pay := 1.0) -> Dictionary:
	match str(prize.kind):
		"coins", "golden":
			var n := rng.randi_range(int(prize.coins[0]), int(prize.coins[1]))
			return { "coins": maxi(1, roundi(n * coin_value(state, catalog) * pay)) }
		"xp":
			return { "xp": int(prize.get("amount", 1)) }
		"part":
			return { "part:%s:%s" % Rewards.roll_part(Jobs.COMMON_BOX, rng, catalog): 1 }
		"box":
			return { "box:%s" % prize.get("box", "starter"): 1 }
	return {}
