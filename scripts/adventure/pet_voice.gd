class_name PetVoice
extends RefCounted
## What the active pet says about adventures (data/voice.json). Pure: a pet, what's going on, and
## the dice go in, a line comes out. The pet's eyes pick its personality and its accessory adds a
## little tic, so the same news sounds different from different pets.

const RISK_STEPS := [0.85, 0.7, 0.55, 0.4]  # chance at or above each = ready, sure, unsure, wobbly; below = shaking
const REWARD_STEPS := [6.0, 16.0, 40.0]  # worth at or above each = coins, shiny, special; below = a crumb


## The personality id for a pet, from its eyes.
static func personality(pet: Pet, catalog: Catalog) -> String:
	var eyes := str(pet.parts.get("eyes", ""))
	for p in catalog.voice.personalities:
		if eyes in p.eyes:
			return p.id
	return catalog.voice.default


## What's worth talking about right now, most important first: a trip just welcomed back, a
## rumour waiting for you, a trip waiting for a choice, a trip back but not welcomed yet, a trip
## out, or nothing. `news` is the latest welcomed trip ({ place, home, sent, parts }) or {};
## `rumours` are the ids of rumours waiting for you.
static func situation(news: Dictionary, rumours: Array[String], runs: Array[RunState], catalog: Catalog) -> Dictionary:
	var about := str(catalog.rumour(rumours[0]).about) if not rumours.is_empty() else ""
	if not news.is_empty():
		var sent := int(news.sent)
		var home := int(news.home)
		var kind := "back_all" if home >= sent else ("back_none" if home == 0 else "back_some")
		var then: Array[String] = []
		if int(news.get("parts", 0)) > 0:
			then.append("part_found")
		var spots: Array = news.get("spotted", [])
		if not spots.is_empty():
			then.append("spotted")
		if about != "":
			then.append("rumour")
		return { "kind": kind, "place": news.place, "home": home, "sent": sent, "lost": sent - home,
			"rumour": about, "spot": spots[0] if not spots.is_empty() else "", "who": news.get("who", ""), "then": then }
	if about != "":
		return { "kind": "rumour", "rumour": about }
	for status in [RunState.Status.WAITING, RunState.Status.DONE, RunState.Status.WALKING]:
		for run in runs:
			if run.status == status:
				var kind: String = { RunState.Status.WAITING: "needs_you", RunState.Status.DONE: "someone_back",
					RunState.Status.WALKING: "away" }[status]
				return { "kind": kind, "place": catalog.location(run.location_id).name }
	return { "kind": "idle" }


## A line for the situation, in this pet's voice.
static func line(pet: Pet, what: Dictionary, rng: RandomNumberGenerator, catalog: Catalog) -> String:
	var text := _pick(pet, str(what.kind), rng, catalog)
	for then in what.get("then", []):
		text += " " + _pick(pet, then, rng, catalog)
	for key in ["place", "home", "sent", "lost", "rumour", "spot", "who"]:
		if what.has(key):
			text = text.replace("{%s}" % key, str(what[key]))
	return text + str(catalog.voice.tics.get(str(pet.parts.get("accessory", "")), ""))


static func _pick(pet: Pet, kind: String, rng: RandomNumberGenerator, catalog: Catalog) -> String:
	var id := personality(pet, catalog)
	for p in catalog.voice.personalities:
		if p.id == id:
			var options: Array = p.lines.get(kind, [])
			if not options.is_empty():
				return str(options[rng.randi_range(0, options.size() - 1)])
	return ""


## What the active pet says about one option on a trip, e.g. "bean spotted something shiny!
## bean looks a bit wobbly…". Risk is read from the real chance (and how bad failing would be), reward
## from what the option can give; neither is ever shown as a number. Each personality says it
## its own way and some read risk wrong on purpose (see "bias" in data/voice.json).
static func hint(speaker: Pet, option: Dictionary, party: Party, location: Dictionary, catalog: Catalog, boost := 1.0) -> String:
	var h: Dictionary = _personality(speaker, catalog).get("hints", {})
	if h.is_empty():
		return ""
	var trip := party.who()
	if option.get("home", false):
		return str(h.home).replace("{trip}", trip)
	var parts: Array[String] = []
	var risky := false
	var failure: Dictionary = option.get("failure", {})
	for key in ["hurt", "lost", "injured"]:
		risky = risky or failure.has(key)
	var band := 0
	if risky:
		var chance := AdventureRunner.success_chance(option, party, location)
		band = 4
		for i in RISK_STEPS.size():
			if chance >= RISK_STEPS[i]:
				band = i
				break
		if int(failure.get("hearts", 1)) >= 2:
			band += 1  # failing would be very bad
		band = clampi(band + int(h.get("bias", 0)), 0, 4)
	# what it spotted first, then how it feels about going for it
	var worth := reward_worth(option.success, location) * boost
	if worth > 0.0:
		var step := 0
		for i in REWARD_STEPS.size():
			if worth >= REWARD_STEPS[i]:
				step = i + 1
		parts.append(str(h.reward[mini(step, h.reward.size() - 1)]).replace("{trip}", trip))
	parts.append(str(h.risk[band]).replace("{trip}", trip))
	if option.success.has("heal"):
		parts.append(str(h.rest))
	return " ".join(parts)


## Roughly what an outcome's rewards are worth, in coins, for picking a reward hint.
static func reward_worth(outcome: Dictionary, location: Dictionary) -> float:
	var worth := 0.0
	for r in outcome.get("rewards", []):
		match str(r.get("kind", "")):
			"coins":
				worth += (float(r.amount[0]) + float(r.amount[1])) / 2.0 * float(location.loot)
			"part":
				worth += float(r.get("chance", 0.0)) * 20.0
			"box":
				worth += float(r.get("chance", 0.0)) * 50.0
			_:
				worth += float(r.get("chance", 0.0)) * 15.0
	return worth


static func _personality(pet: Pet, catalog: Catalog) -> Dictionary:
	var id := personality(pet, catalog)
	for p in catalog.voice.personalities:
		if p.id == id:
			return p
	return {}


## How the pet on a trip seems right now, in the active pet's words: just set off, the last event
## went well or badly, or it's hurt. This is how you know it's hurt; there are no hearts shown.
static func feeling(speaker: Pet, party: Party, history: Array[Dictionary], catalog: Catalog) -> String:
	var lines: Dictionary = _personality(speaker, catalog).get("hints", {}).get("feeling", {})
	var key := "start"
	if party.injured_count() > 0:
		key = "hurt"
	elif not history.is_empty():
		key = "good" if history.back().get("success", true) else "bad"
	return str(lines.get(key, "")).replace("{trip}", party.who())


## What the pet on a trip spotted at an event: the tempting option's reward and how dangerous it
## looks, in the active pet's words. With nothing risky it's the best reward on offer.
static func spotted(speaker: Pet, event: Dictionary, party: Party, location: Dictionary, catalog: Catalog, boost := 1.0) -> String:
	var tempting := {}
	var best := -1.0
	for option in event.options:
		var risky: bool = option.get("failure", {}).has("hurt") or option.get("failure", {}).has("lost")
		var score := reward_worth(option.success, location) + (1000.0 if risky else 0.0)
		if score > best:
			best = score
			tempting = option
	return hint(speaker, tempting, party, location, catalog, boost) if not tempting.is_empty() else ""


## What your active pet says about having a part sewn on: how it feels about the risk before
## (`kind` "risk", from the real chance and its bias), or "success" / "fail" after.
static func graft_line(pet: Pet, kind: String, fail_chance: float, rng: RandomNumberGenerator, catalog: Catalog) -> String:
	var p := _personality(pet, catalog)
	var lines: Dictionary = p.get("graft", {})
	if kind != "risk":
		var options: Array = lines.get(kind, [""])
		return str(options[rng.randi_range(0, options.size() - 1)])
	var band := 4
	for i in RISK_STEPS.size():
		if 1.0 - fail_chance >= RISK_STEPS[i]:
			band = i
			break
	band = clampi(band + int(p.get("hints", {}).get("bias", 0)), 0, 4)
	return str(lines.get("risk", [""])[band])


## What your pet did while you were busy (GameState.idle_log), told in one breath:
## "while you were busy: ◆150, 2 parts, 3 packs opened, and one was a holo fox! i worked so hard!"
static func work_summary(pet: Pet, log: Dictionary, rng: RandomNumberGenerator, catalog: Catalog) -> String:
	var bits: Array[String] = []
	if int(log.get("coins", 0)) > 0:
		bits.append("◆%d" % log.coins)
	if int(log.get("parts", 0)) > 0:
		bits.append("%d part%s" % [log.parts, "s" if int(log.parts) > 1 else ""])
	if int(log.get("boxes", 0)) > 0:
		bits.append("%d box%s" % [log.boxes, "es" if int(log.boxes) > 1 else ""])
	if int(log.get("packs", 0)) > 0:
		bits.append("%d pack%s opened" % [log.packs, "s" if int(log.packs) > 1 else ""])
	if bits.is_empty():
		return ""
	var text := "while you were busy: " + ", ".join(bits)
	var good: Array = log.get("good", [])
	if not good.is_empty():
		text += ", and one was a %s!" % good[0] if good.size() == 1 else ", and %d were really special!" % good.size()
	else:
		text += "!"
	return text + " " + _pick(pet, "at_work", rng, catalog)
