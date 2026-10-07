class_name HomesPart
extends RefCounted
## GameState's code for the room's cap, new homes, who may go (spare_pick: one rule for everything
## that takes pets), the sorting rule and keep lines.
## A part of GameState (see tools/state_parts.py): works on GameState's state through gs; GameState
## forwards to it, so callers use GameState.<name>() as before.

var gs: GameStateNode


func _init(state: GameStateNode) -> void:
	gs = state


## How many plain pets the room holds now.
func room_cap() -> int:
	return Herd.room_cap(gs.catalog, gs.room)


## Space left in the room (box openings stop at 0: the boxes wait on the pile).
func room_left() -> int:
	return maxi(0, room_cap() - gs.collection.plain_count())


## The room is full: box openings wait.
func room_is_full() -> bool:
	return room_left() <= 0


## The room is nearly full (data/herd.json room "cozy_at").
func room_is_cozy() -> bool:
	return gs.collection.plain_count() >= room_cap() * float(gs.catalog.herd.get("room", {}).get("cozy_at", 0.9))


## What the next room step costs, in its one currency (room_currency).
func room_price() -> int:
	return Herd.room_cost(gs.catalog, gs.room, gs.capsule_value())


## What the next room step is paid in: "coins" or "wisps".
func room_currency() -> String:
	return Herd.room_currency(gs.catalog, gs.room)


## The next room step to show on the house card: { id, name, cap, capsules | wisps }, or {} when
## it's a squeeze-in step and wisps haven't shown up yet (hidden until earned).
func room_next() -> Dictionary:
	var s := Herd.room_step(gs.catalog, gs.room)
	if s.has("wisps") and not wisps_shown():
		return {}
	return s


## Every plain pet in the room, split: [at home on the shelves, out working]. Out working: herd
## pets on errands, at worker spots, away (stand-ins) or in the dungeon's army, and plain cards on
## errands, working, away or in the army. The two add up to plain_count() (pets on jobs count
## toward the room too).
func room_split() -> Array:
	var total := gs.collection.plain_count()
	var gone := gs._out()
	var out := 0
	var used := gs._herd_used(gone)
	var army := gs._army_herd(used)
	for k in used:
		out += int(used[k])
	for k in army:
		out += int(army[k])
	var cards := gone.duplicate()
	for uid in gs._job_of:
		cards[str(uid)] = true
	for uid in gs._worker_of:
		cards[str(uid)] = true
	for uid: String in cards:
		if Herd.is_stand_in(uid):
			continue  # counted with the herd
		var pet := gs.collection.get_pet(uid)
		if pet and Herd.plain(gs.catalog, pet.finish):
			out += 1
	out = clampi(out, 0, total)
	return [total - out, out]


## The room shows (the pill on the pets tab) once a pet has folded into the herd.
func room_shown() -> bool:
	return gs.collection.herd_ever or gs.room > 0


## Builds the next room step, paid in its one currency (coins or wisps). Returns whether you could.
func buy_room() -> bool:
	var price := room_price()
	if room_currency() == "wisps":
		if not wisps_shown() or gs.wisps < price:
			return false
		gs.wisps -= price
	else:
		if gs.coins < price:
			return false
		gs.coins -= price
	gs.room += 1
	gs.changed.emit()
	gs.save_game()
	return true


## Whether wisps have shown up yet (hidden until earned: nothing priced in wisps shows before):
## the dungeon or the plushie machine is open (the two places that pay them), or you hold some.
func wisps_shown() -> bool:
	return gs.wisps > 0 or gs.dungeon_open() or gs.plushie_open()


## The room stopped a box opening (or is full): the first time, the new homes stall opens.
func _room_hit() -> void:
	if gs.homes.room_was_full:
		return
	gs.homes.room_was_full = true
	gs.check_unlocks()


## Whether the new homes stall is there (the room has been full once).
func homes_open() -> bool:
	return gs.feature_on("new_homes")


## Pets of a rarity that may go (new homes, past the edge, the school, the wishing jar, helpers,
## holders, the army): ONE rule for all of them. In the order they go: every resting pet before any
## working one; inside each, the plainest finish first, counts before the oldest cards. Only finishes
## below the sorting card's keep line (keep_line()), and never favourites, your active pet, pets with
## a part new to the book, buttons or a keep line (Collection.kept), pets away, pinned pulls, party
## leaders or the army. `n` -1: all of them. Returns { cards: [uids], rest: { key: n } (resting
## counts), work: { key: n } (counts on errands and machines), n, working (how many of n work) }.
func spare_pick(rarity: String, n := -1, ctx := {}) -> Dictionary:
	var out := { "cards": [], "rest": {}, "work": {}, "n": 0, "working": 0 }
	var left := n if n >= 0 else (1 << 62)
	if ctx.is_empty():
		ctx = _spare_ctx()
	var busy: Dictionary = ctx.busy
	var free_rest: Dictionary = ctx.free_rest
	var out_now: Dictionary = ctx.out_now
	var resting: Dictionary = ctx.resting
	var cards := gs.collection.cards_of(rarity)
	var finishes: Array = gs.catalog.finishes.filter(func(f): return may_go_finish(str(f.id)))
	var mine := {}  # finish -> its cards that may go, oldest first (one pass: there can be tens of thousands)
	for f in finishes:
		mine[f.id] = []
	for pet in cards:
		if mine.has(pet.finish) and not gs.collection.kept(pet) and not busy.has(pet.uid):
			mine[pet.finish].append(pet)
	# everyone resting first (plainest finish first: the count, then the cards), then the ones working
	for f in finishes:
		var k := Herd.key(rarity, str(f.id))
		var take := mini(left, int(free_rest.get(k, 0)))
		if take > 0:
			out.rest[k] = take
			left -= take
		for pet: Pet in mine[f.id]:
			if left <= 0:
				break
			if resting.has(pet.uid):
				out.cards.append(pet.uid)
				left -= 1
	for f in finishes:
		var k := Herd.key(rarity, str(f.id))
		var working := gs.collection.herd_count(k) - int(free_rest.get(k, 0)) - int(out_now.get(k, 0))
		var take := mini(left, maxi(0, working))
		if take > 0:
			out.work[k] = take
			left -= take
		for pet: Pet in mine[f.id]:
			if left <= 0:
				break
			if not resting.has(pet.uid):
				out.cards.append(pet.uid)
				out.working += 1
				left -= 1
	out.working += Herd.total(out.work)
	out.n = out.cards.size() + Herd.total(out.rest) + Herd.total(out.work)
	return out


## What spare_pick needs to know about everyone (worked out once for all the rarities): busy uids,
## resting counts, counts out (away, or the army's), resting cards.
func _spare_ctx() -> Dictionary:
	var out_now := {}
	for uid: String in gs._stand_ins_out():
		Herd.put(out_now, Herd.key_of(uid), 1)
	var army := gs.army_herd_keys()  # the dungeon's army's herd pets aren't resting or working: never taken
	for k in army:
		Herd.put(out_now, k, int(army[k]))
	var resting := {}
	for pet in gs.resting_cards():
		resting[pet.uid] = true
	return { "busy": gs._busy_uids(), "free_rest": gs.resting_herd(), "out_now": out_now, "resting": resting }


## The sorting card's keep line: pets of this finish and better never go anywhere (see spare_pick).
func keep_line() -> String:
	return str(gs.homes.rule.get("keep", "holo"))


## Whether pets of this finish may go (below the keep line).
func may_go_finish(finish: String) -> bool:
	return gs.catalog.finish_rank(finish) < gs.catalog.finish_rank(keep_line())


## How many pets of each rarity may go right now: rarity -> { n, working } (see spare_pick; rarities
## with none are left out). Kept for a second at most: pickers ask every frame.
func spare_shelves() -> Dictionary:
	# with tens of thousands of cards a count takes tens of ms: then it's kept a little longer
	var fresh := GameStateNode.SPARE_FRESH_MS * (3 if gs.collection.pets.size() > 5000 else 1)
	if gs._spare.is_empty() or Time.get_ticks_msec() - gs._spare_at > fresh:
		gs._spare = { "shelves": {} }
		gs._spare_at = Time.get_ticks_msec()
		# the same counts as spare_pick(rarity, -1) for every rarity, in one pass and without lists
		var ctx := _spare_ctx()
		var busy: Dictionary = ctx.busy
		var resting: Dictionary = ctx.resting
		var may := {}
		for f in gs.catalog.finishes:
			if may_go_finish(str(f.id)):
				may[f.id] = true
		var counts := {}  # rarity -> [may go, of them working]
		var keep_uids: Dictionary = gs.collection.keep_uids
		var active_uid := gs.collection.active_uid
		for pet in gs.collection.pets:  # Collection.kept written out: this runs over every card
			if may.has(pet.finish) and not busy.has(pet.uid) and not (pet.fav or pet.new_part or not pet.buttons.is_empty() \
					or pet.uid == active_uid or keep_uids.has(pet.uid)):
				var c: Array = counts.get_or_add(pet.rarity, [0, 0])
				c[0] += 1
				if not resting.has(pet.uid):
					c[1] += 1
		for tier in gs.catalog.tiers:
			var c: Array = counts.get(tier.id, [0, 0])
			var n: int = c[0]
			var working: int = c[1]
			for f in may:
				var k := Herd.key(str(tier.id), str(f))
				var rest := int(ctx.free_rest.get(k, 0))
				var work := maxi(0, gs.collection.herd_count(k) - rest - int(ctx.out_now.get(k, 0)))
				n += rest + work
				working += work
			if n > 0:
				gs._spare.shelves[tier.id] = { "n": n, "working": working }
	return gs._spare.shelves


## Who may go changed (a favourite, a pin, the keep line): spare_shelves() works it out again.
func _spare_changed() -> void:
	gs._spare = {}


## How many pets of a rarity may go right now (the stall, the edge, the school...).
func homes_can_go(rarity: String) -> int:
	return int(spare_shelves().get(rarity, {}).get("n", 0))


## The face of a pet that would go soon from a shelf (null when none may); `salt` picks another.
func spare_face(rarity: String, salt := 0) -> Pet:
	var plan := spare_pick(rarity, 8)
	if not plan.cards.is_empty() and plan.rest.is_empty():
		return gs.collection.get_pet(str(plan.cards[salt % plan.cards.size()]))
	for part in [plan.rest, plan.work]:
		for k in part:
			var uids := gs.herd_faces({ k: 1 }, 1, salt)
			if not uids.is_empty():
				return gs.collection.get_pet(str(uids[0]))
	return null


## Takes up to `n` pets of a rarity for good (-1: all that may go, see spare_pick): off their
## errands and machines if they have to. `star`: they're gone (a star each); otherwise they stay on
## somewhere (school, holders, helpers). Returns { n: how many went, counts: count key -> how many
## (cards too, by rarity and finish), palettes: the looks of up to `keep` of them }.
func _take_spare(rarity: String, n: int, keep: int, star: bool) -> Dictionary:
	var out := { "n": 0, "counts": {}, "palettes": [] }
	var plan := spare_pick(rarity, n)
	if int(plan.n) <= 0:
		return out
	for uid in plan.cards:
		var pet := gs.collection.get_pet(str(uid))
		if pet:
			Herd.put(out.counts, Herd.key(pet.rarity, pet.finish), 1)
			if out.palettes.size() < keep:
				out.palettes.append(str(pet.parts.palette))
	var counts: Dictionary = plan.rest.duplicate()
	for k in plan.work:
		Herd.put(counts, k, gs._herd_off_places(k, int(plan.work[k])))  # off their errands and machines first
	for k in counts:
		Herd.put(out.counts, k, int(counts[k]))
		for uid in gs.collection.stand_in_uids(k, mini(int(counts[k]), maxi(0, keep - out.palettes.size()))):
			var face := Herd.stand_in(gs.catalog, uid)
			if face:
				out.palettes.append(str(face.parts.palette))
	out.n = gs.collection.leave(counts, plan.cards, star)
	_spare_changed()
	return out


## The stall takes `n` pets of a rarity (-1: all it may), see spare_pick. They leave for good (a
## star each), their points go in the jar, and full jars drop boxes on your pile. Returns
## { n: how many left, boxes }.
func send_home(rarity: String, n := 1) -> Dictionary:
	var gone := int(_take_spare(rarity, n, 0, true).n)
	if gone <= 0:
		return { "n": 0, "boxes": 0 }
	var boxes := NewHomes.pay(gs.homes, gs.catalog, rarity, gone)
	if boxes > 0:
		var box := NewHomes.box_id(gs.catalog)
		gs.bag[box] = gs.in_bag(box) + boxes
		gs.homes_paid.emit(boxes)
	gs.homes.by_hand = int(gs.homes.by_hand) + gone
	gs.check_unlocks()
	gs.changed.emit()
	gs.save_game()
	return { "n": gone, "boxes": boxes }


## The sorting rule, if it's on (and found), or keep lines that pick something: what Collection.add
## asks about each new pet from a box.
func _sorter() -> Callable:
	if gs.tutorial_active():
		return Callable()
	var rule_on: bool = gs.feature_on("sorting") and gs.homes.rule.on
	if not rule_on and not keep_lines_on():
		return Callable()
	return _sort_pet


## The sorting card on one new pet: keep lines first (a match stays a card), then the sorting rule:
## "homes" (it leaves, its points go in the jar), "work" (it goes to work as it's added), "school" (it
## sits down in the school's class: seat_in_school's rule, no star) or "" (it stays).
func _sort_pet(pet: Pet) -> String:
	if _keep_new(pet):
		return ""
	if not gs.feature_on("sorting") or not NewHomes.sorts(gs.catalog, gs.homes.rule, pet):
		return ""
	if str(gs.homes.rule.to) == "school":  # it sits down in the class while there are seats (else it stays)
		if not gs.school_open() or School.seats_left(gs.catalog, gs.school) <= 0:
			return ""
		NewHomes.count_sorted(gs.homes, NewHomes.today())
		School.seat(gs.catalog, gs.school, { Herd.key(pet.rarity, pet.finish): 1 })
		if not gs._school_flush:
			gs._school_flush = true
			_flush_school.call_deferred()
		return "school"
	NewHomes.count_sorted(gs.homes, NewHomes.today())
	if str(gs.homes.rule.to) == "work":
		gs._to_work[pet.uid] = true
		return "work"
	var boxes := NewHomes.pay(gs.homes, gs.catalog, pet.rarity, 1)
	if boxes > 0:
		var box := NewHomes.box_id(gs.catalog)
		gs.bag[box] = gs.in_bag(box) + boxes
		gs.homes_paid.emit(boxes)
	return "homes"


## The sorting rule sat pets down in the school: the school hears about it once.
func _flush_school() -> void:
	gs._school_flush = false
	gs.school_changed.emit()


## Where the sorting rule can send pets: new homes, work, and the school once it's there.
func rule_destinations() -> Array[String]:
	var out: Array[String] = ["homes", "work"]
	if gs.school_open():
		out.append("school")
	return out


## Pets the sorting rule sorted today.
func sorted_today() -> int:
	return NewHomes.sorted_on(gs.homes, NewHomes.today())


## The sorting card: on or off, "below" (a rarity), "to" (homes / work / school), "keep" (a finish).
func set_rule(key: String, value) -> void:
	match key:
		"on": gs.homes.rule.on = bool(value)
		"below":
			if gs.catalog.tiers.any(func(t): return t.id == str(value)):
				gs.homes.rule.below = str(value)
		"to":
			if str(value) in rule_destinations():
				gs.homes.rule.to = str(value)
		"keep":
			if gs.catalog.finish(str(value)).id == str(value):
				gs.homes.rule.keep = str(value)
	gs._rest_changed()  # the keep line: which finishes may go anywhere (and the army holds)
	gs.homes_rule_changed.emit()
	gs.changed.emit()
	gs.save_game()


## Rarities the card's "below" stepper offers: every rarity above the lowest, up to the rarest you
## have (and whatever it's set to).
func rule_rarities() -> Array[String]:
	var out: Array[String] = []
	var top := 1
	for t in gs.catalog.tiers:
		if gs.collection.count_of(t.id) > 0:
			top = maxi(top, gs.catalog.rank(t.id) + 1)
	top = maxi(top, gs.catalog.rank(str(gs.homes.rule.below)))
	for i in range(1, mini(top, gs.catalog.tiers.size() - 1) + 1):
		out.append(str(gs.catalog.tiers[i].id))
	return out


## Finishes the card's keep stepper offers: shiny and better, the ones you've had (and whatever
## it's set to).
func rule_finishes() -> Array[String]:
	var out: Array[String] = []
	for f in gs.catalog.finishes:
		if gs.catalog.finish_rank(f.id) >= 1 and (gs.collection.finish_seen(f.id) or f.id == gs.homes.rule.keep):
			out.append(str(f.id))
	return out


## Whether the sorting card has its keep lines (the button tin teaches them).
func keep_lines_on() -> bool:
	return gs.feature_on("keep_lines") and keep_line_count() > 0


## How many keep lines the rooms cleared have earned.
func keep_line_count() -> int:
	return Sewing.keep_lines(gs.catalog, int(gs.sewing.cleared))


## Each keep line's pick ("" for nothing), as many as are earned.
func keep_lines() -> Array[String]:
	var out: Array[String] = []
	var lines: Array = gs.homes.rule.get("lines", [])
	for i in keep_line_count():
		out.append(str(lines[i]) if i < lines.size() else "")
	return out


## What keep lines can pick: nothing, every trait, the keep parts the book has seen (and whatever a
## line has now).
func keep_line_options() -> Array[String]:
	var seen := {}
	for key in gs.collection.seen_keys():
		seen[str(key)] = true
	var out := Sewing.keep_options(gs.catalog, seen)
	for pick in keep_lines():
		if not pick in out:
			out.append(pick)
	return out


## Sets keep line `i` to a pick ("" for nothing). A pick it had before lets its pets go (they may
## fold into the herd now) unless another line keeps the same kind.
func set_keep_line(i: int, pick: String) -> bool:
	if i < 0 or i >= keep_line_count() or not Sewing.keep_valid(gs.catalog, pick):
		return false
	var lines: Array = gs.homes.rule.lines
	while lines.size() < keep_line_count():
		lines.append("")
	if str(lines[i]) == pick:
		return true
	lines[i] = pick
	_keep_lines_changed()
	gs.collection.refold()
	gs._rest_changed()
	gs.homes_rule_changed.emit()
	gs.changed.emit()
	gs.save_game()
	return true


## How many pets a keep line keeps now.
func kept_count(pick: String) -> int:
	return gs.homes.kept.get(pick, []).filter(func(uid): return gs.collection.get_pet(str(uid)) != null).size()


## A new pet from a box: kept by the first keep line it matches (the oldest past the cap drops off).
## Only plain ones: the rest are cards anyway. Returns whether it's kept.
func _keep_new(pet: Pet) -> bool:
	if not keep_lines_on() or not Herd.plain(gs.catalog, pet.finish):
		return false
	for pick in keep_lines():
		if pick != "" and Sewing.mark_matches(pick, pet):
			gs.homes.kept[pick] = gs.homes.kept.get(pick, []).filter(func(uid): return gs.collection.get_pet(str(uid)) != null)
			for uid in Sewing.keep(gs.catalog, gs.homes.kept, pick, pet.uid):
				if not keep_lines().any(func(other): return other != pick and gs.homes.kept.get(other, []).has(uid)):
					gs.collection.keep_uids.erase(str(uid))
			gs.collection.keep_uids[pet.uid] = true
			return true
	return false


## The kept lists follow the lines: lists no line picks any more go, and Collection.keep_uids is
## worked out again.
func _keep_lines_changed() -> void:
	var picks: Array[String] = []
	if keep_lines_on():
		picks = keep_lines()
	for pick in gs.homes.kept.keys():
		if not pick in picks:
			gs.homes.kept.erase(pick)
		else:  # pets gone since (lost in the dungeon, fed to the plushie machine) drop off
			gs.homes.kept[pick] = gs.homes.kept[pick].filter(func(uid): return gs.collection.get_pet(str(uid)) != null)
	gs.collection.keep_uids.clear()
	for pick in gs.homes.kept:
		for uid in gs.homes.kept[pick]:
			gs.collection.keep_uids[str(uid)] = true
