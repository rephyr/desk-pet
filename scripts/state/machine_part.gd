class_name MachinePart
extends RefCounted
## GameState's code for the capsule machine: pulls, capsules, the tree's upgrades, globes and bits.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## A machine globe came home that the machine tab hasn't shown arriving yet (its news dot), or "".
func globe_news() -> String:
	var first := Machine.first_globe(gs.catalog)
	for g in Machine.home(gs.machine, gs.catalog):
		if g != first and not gs.machine.get("greeted", []).has(g):
			return g
	return ""


## The machine tab showed this globe arriving (it slid in, your pet said so): only once.
func greet_globe(id: String) -> void:
	if gs.machine.get("greeted", []).is_empty():
		gs.machine.greeted = [Machine.first_globe(gs.catalog)]
	if not gs.machine.greeted.has(id):
		gs.machine.greeted.append(id)
		gs.save_game()
		gs.changed.emit()


## A find that is a machine globe brings it home (safe to call again: it's only added once).
func _globe_home(find_id: String) -> void:
	var g := Machine.globe_for_find(gs.catalog, find_id)
	if gs.machine.get("globes", []).is_empty():
		gs.machine.globes = [Machine.first_globe(gs.catalog)]
	if g == "" or gs.machine.globes.has(g):
		return
	gs.machine.globes.append(g)
	gs.globe_arrived.emit(g)


## One pull of the capsule machine's lever: every chute drops a capsule (sometimes 2 or 3), each
## with one prize; a shiny ball multiplies what it holds. Once the lights are rewired a pull lights a
## lucky light; when they're all lit this pull is lucky and fever starts (capsules pay more for a
## while). Returns { capsules: [ { prize, loot, shiny, toy, pet } ], lucky, fever (it paid fever) }.
func pull_lever() -> Dictionary:
	var m: Dictionary = gs.catalog.machine
	var now := Time.get_unix_time_from_system()
	var in_fever := now < gs.fever_until
	gs.machine.pulls = int(gs.machine.pulls) + 1
	var pet_due := _pet_box_due()
	var g := Machine.hand(gs.machine, gs.catalog)  # your hand pulls the newest globe that works
	var lucky := false
	if Machine.lights_on(gs.machine, gs.catalog, g):
		gs.machine.lit = int(gs.machine.lit) + 1
		lucky = int(gs.machine.lit) >= Machine.lights_needed(gs.machine, gs.catalog)
		if lucky:
			gs.machine.lit = 0
	var fever := gs.boost("fever")
	var pay := float(m.fever_pay) * fever if in_fever else 1.0
	var capsules: Array = []
	for chute in Machine.chutes(gs.machine, gs.catalog, g):
		for ball in Machine.balls_from_chute(gs.machine, gs.catalog, gs._rng, g):
			capsules.append(_capsule(capsules.is_empty(), lucky, pay, pet_due, g))
	if lucky:
		gs.fever_until = now + Machine.fever_for(gs.machine, gs.catalog, fever, gs.boost("speed"), g)
	var result := { "capsules": capsules, "lucky": lucky, "fever": in_fever, "globe": g }
	gs.machine_pulled.emit(result)
	gs._check_tutorial()
	return result


## Counts pulls while you have hardly any pets (data/machine.json "pet_box"): after "sure_within"
## of them the next capsule is sure to hold a box with a pet inside, so losing your pets on
## adventures can never leave you stuck.
func _pet_box_due() -> bool:
	var pb: Dictionary = gs.catalog.machine.get("pet_box", {})
	if gs.tutorial_active() or pb.is_empty() or gs.collection.count() - 1 >= int(pb.get("few_pets", 1)):
		gs.machine.pet_wait = 0
		return false
	gs.machine.pet_wait = int(gs.machine.get("pet_wait", 0)) + 1
	return int(gs.machine.pet_wait) >= int(pb.get("sure_within", 10))


## One capsule out of a pull: rolls its prize (the tutorial's pets come in the first one), makes
## it shiny sometimes, and hands out what's inside. `pay` multiplies coins (fever); `pet_due`:
## the first capsule holds a pet box (the safety net, see _pet_box_due).
func _capsule(first: bool, lucky: bool, pay: float, pet_due := false, g := "") -> Dictionary:
	var m: Dictionary = gs.catalog.machine
	var luck := gs.boost("luck")
	g = g if g != "" else Machine.hand(gs.machine, gs.catalog)
	var prize := Machine.roll(gs.machine, gs.catalog, gs._rng, lucky, luck, gs.boost("toys"), gs.boost("pet_boxes"), g)
	if gs.tutorial_active():
		prize = _machine_prize("golden" if lucky else "coins")  # nothing fancy while you're starting out
	elif not _machine_gives(str(prize.kind)) or (prize.kind == "pet_box" and not first):
		prize = _machine_prize(Machine.FALLBACK_PRIZE)  # not open yet (boxes, toys, parts); pet boxes: one pull, one chance
	elif first and gs.toys.owned.is_empty() and _machine_gives("toy") and int(gs.machine.pulls) >= int(m.get("first_toy_by", 0)):
		prize = _machine_prize("toy")  # your first toy, sure to come soon after toys can drop
	if first and pet_due:
		prize = _machine_prize("pet_box")
	if prize.kind == "pet_box" and gs.room_left() <= 0:
		prize = _machine_prize("box")  # a full room: the box goes on your pile to wait
		gs._room_hit()
	var intel: Dictionary = m.get("intel", {})
	if first and not gs.tutorial_active() and not intel.is_empty() and Machine.owned(gs.machine, str(intel.after)) > 0 and not gs.finds.has(str(intel.find)):
		prize = { "id": "intel", "kind": "intel", "find": str(intel.find) }  # a scrap of a map: the next page
	if first and _tutorial_pet_due():
		prize = { "id": "pet", "kind": "pet" }
	elif first and gs.debug_next_prize != "" and OS.is_debug_build():
		prize = _machine_prize(gs.debug_next_prize)
		gs.debug_next_prize = ""
	if prize.kind in ["box", "pet_box"]:
		prize = prize.duplicate()
		prize.box = Machine.box_of(gs.machine, gs.catalog, g)  # the globe's box tier (its hatch, or the one before)
	var shiny: bool = prize.kind in ["coins", "golden", "box", "part"] and gs._rng.randf() < Machine.shiny_chance(gs.machine, gs.catalog, g) * gs.boost("shiny")
	var loot := Machine.loot(prize, gs.machine, gs.catalog, gs._rng, pay, g)
	if loot.has("coins"):
		loot.coins = GameStateNode.coins_int(int(loot.coins) * gs.boost("coins"))  # shown as it is
	if shiny:
		for k in loot:
			loot[k] = GameStateNode.coins_int(float(loot[k]) * Machine.shiny_pay(gs.machine, gs.catalog, g))
	var toy := {}
	var pet: Pet = null
	if prize.kind == "pet":
		var got: Array[Pet] = [gs._roller.roll(GameStateNode.TUTORIAL_BOX)]
		gs.collection.add(got)
		pet = got[0]
	if prize.kind == "pet_box":
		# the pet is rolled now (it's yours even if nobody opens the box); the machine tab plays the
		# box opening. It doesn't count as a pack you opened yourself.
		var got: Array[Pet] = [gs._roller.roll(str(prize.get("box", GameStateNode.FIRST_PET_BOX)))]
		gs.collection.add(got, gs._sorter())  # a box opening: the sorting rule sorts it too
		pet = got[0]
		gs.machine.pet_wait = 0
	if prize.kind == "intel":
		gs.grant({ "find:" + str(prize.find): 1 })
	if prize.kind == "toy":
		var t := Toys.roll(gs.catalog, gs._rng, luck, Machine.toy_sets(gs.machine, gs.catalog, g))
		toy = { "id": t.id, "finish": t.finish, "new": Toys.add(gs.toys, t.id, t.finish) }
		gs.toys_changed.emit()
		gs.check_unlocks()
	if loot.has("xp"):
		loot.xp = gs.add_xp(int(loot.xp))
		gs.grant(GameStateNode._without(loot, "xp"), false)
	else:
		gs.grant(loot, false)
	return { "prize": prize, "loot": loot, "shiny": shiny, "toy": toy, "pet": pet }


## The chance of each prize in the next capsule (a lucky one when `lucky`), with your boosts (the
## same ones _capsule rolls with) and only the kinds that can come out yet (Machine.odds). For the
## machine's prize card.
func machine_odds(lucky := false, first := true) -> Dictionary:
	return Machine.odds(gs.machine, gs.catalog, _machine_gives, lucky, gs.boost("luck"), gs.boost("toys"), first, gs.boost("pet_boxes"), Machine.hand(gs.machine, gs.catalog))


func _machine_prize(id: String) -> Dictionary:
	for p in gs.catalog.machine.prizes:
		if p.id == id:
			return p
	return gs.catalog.machine.prizes[0]


## In the tutorial a pet comes out of the machine: your first on an early pull, the second (with a
## map: adventures open) once the machine is built up (data/tutorial.json).
func _tutorial_pet_due() -> bool:
	var t: Dictionary = gs.catalog.tutorial
	match gs.tutorial:
		"pull":
			return int(gs.machine.pulls) >= int(t.get("machine_pet_at", 3))
		"machine":
			return Machine.owned(gs.machine, str(t.get("adventure_after", "oil"))) > 0
	return false


## Machine upgrades bought, every level counted.
func machine_upgrades() -> int:
	return Machine.levels(gs.machine)


## Whether a kind of capsule prize can come out yet: boxes once the boxes tab is open, toys once
## they are, parts once the workbench is (they all open through adventures).
func _machine_gives(kind: String) -> bool:
	match kind:
		"box": return gs.tab_open("boxes")
		"toy": return gs.feature_on("toys") or Machine.add(gs.machine, gs.catalog, "drops") > 0.0
		"part": return gs.feature_on("parts")
		"pet_box": return not gs.tutorial_active()
	return true


## Seconds a capsule takes to pop open, quicker with the capsule speed boost.
func capsule_seconds() -> float:
	return Machine.reveal_seconds(gs.machine, gs.catalog) / gs.boost("speed")


## Where pets find a machine bit, for the upgrade card when you're short of one: the open places
## whose treat bag holds it, or, before any of those is found, a place that leads there.
func bit_hint(bit: String) -> String:
	var plural := Machine.bit_name(gs.catalog, bit, 2)
	var come := "come" if plural != Machine.bit_name(gs.catalog, bit, 1) else "comes"
	var open: Array[String] = []
	var closed: Array[Dictionary] = []
	for location in gs.catalog.locations:
		if not location.get("finish_rewards", []).any(func(r): return r.get("kind", "") == "bit" and str(r.get("id", "")) == bit):
			continue
		if gs.location_open(location):
			open.append(str(location.name))
		else:
			closed.append(location)
	if not open.is_empty():
		return "pets find %s at %s" % [plural, " and ".join(open)]
	for location in closed:
		if gs.spotted.has(location.id):
			return "%s %s from %s. a pet spotted it: say yes on the map!" % [plural, come, location.name]
	for location in closed:
		for from in gs.catalog.locations:
			if gs.location_open(from) and from.get("leads_to", []).any(func(l): return str(l.to) == location.id):
				return "%s %s from a place nobody's found yet. keep going to %s!" % [plural, come, from.name]
	return "pets find %s on adventures" % plural


## Seconds of fever left on the machine (0 when there's none).
func fever_left() -> float:
	return maxf(0.0, gs.fever_until - Time.get_unix_time_from_system())


## Fixes or upgrades one level of a node on the machine's tree (coins and bits). Returns whether you could.
func buy_machine_upgrade(id: String) -> bool:
	if Machine.blocker(gs.machine, gs.catalog, id, gs.coins, gs.bits) != "":
		return false
	gs.coins -= Machine.cost(gs.machine, gs.catalog, id)
	var need := Machine.bits_cost(gs.catalog, id)
	for b in need:
		gs.bits[b] = int(gs.bits.get(b, 0)) - int(need[b])
	gs.machine.bought[id] = Machine.owned(gs.machine, id) + 1
	gs.machine_upgraded.emit(id)
	gs.check_unlocks()
	gs.save_game()
	gs.changed.emit()
	return true
