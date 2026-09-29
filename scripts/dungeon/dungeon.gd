class_name Dungeon
extends RefCounted
## The first dungeon: the old well, all the way down (data/dungeon.json). An army of pets goes down
## floor by floor; each floor's strength is against the army's power, losses are the cost, every
## cleared floor pays the darker currency (wisps) for the pets SENT (never for pets lost).
## Pure rules, no game state: GameState keeps the state from the save and hands out what a run
## brought. The state:
##   { deep: the deepest floor ever cleared, bands: [band ids shown already (old saves had them open)],
##     target: go down to this floor, home_at: come home when this % are gone, first: who goes first
##     (a line of data "first", once earned), cards: [uids in the army], herd: { rarity: pets from the
##     herd }, run: {} or the run that's out (see send), last: {} or { floor, got, back } of the last
##     run (a sewing room run has room: its number, door, seconds; see Sewing), firsts: { floor: true }
##     (what a floor gives the first time is given), held: { "10": { count key: n } } (the crowds holding
##     landings, see hold_need), start: the landing the orders start from (0: the top, or a fully held
##     landing) }. The entrance's width is a wisps perk (Perks).
## An ARMY for the rules: { cards: [{ uid, power, rank }] best first, herd: { count key: { n, power,
## rank } }, luck: the knock doors' chance, boost: the power boost, and from the perks (all optional):
## front_n: cards in the front row, front_x: the front row's cards x, behind_x: pets walking behind x,
## band_x: { band kind (rope, doors, stairs) or "room": x } }. Gear never counts here.


static func data(catalog: Catalog) -> Dictionary:
	return catalog.dungeon


static func fresh(catalog: Catalog) -> Dictionary:
	var d := data(catalog)
	return { "deep": 0, "bands": [str(d.bands[0].id)], "target": mini(int(d.get("target_ahead", 5)), int(d.bands[0].get("to", 10))),
		"home_at": int(d.get("home_at_start", 30)), "first": str(d.first.lines[0]), "cards": [], "herd": {}, "run": {},
		"last": {}, "firsts": {}, "held": {}, "start": 0 }


## A saved state made safe: unknown bands and lines dropped, numbers in range (cards and herd picks
## are checked against the pets by GameState).
static func clean(catalog: Catalog, raw) -> Dictionary:
	var out := fresh(catalog)
	if not raw is Dictionary:
		return out
	var d := data(catalog)
	out.deep = maxi(0, int(raw.get("deep", 0)))
	for id in raw.get("bands", []):
		if not band(catalog, str(id)).is_empty() and not str(id) in out.bands:
			out.bands.append(str(id))
	out.home_at = int(raw.get("home_at", out.home_at))
	if not out.home_at in d.home_at.map(func(v): return int(v)):
		out.home_at = int(d.get("home_at_start", 30))
	out.first = str(raw.get("first", out.first))
	if not out.first in d.first.lines:
		out.first = str(d.first.lines[0])
	out.target = clampi(int(raw.get("target", out.target)), 1, target_max(catalog, out))
	for uid in raw.get("cards", []):
		if not str(uid) in out.cards:
			out.cards.append(str(uid))
	var herd = raw.get("herd", {})
	if herd is Dictionary:
		for rarity in herd:
			if catalog.tiers.any(func(t): return t.id == str(rarity)) and int(herd[rarity]) > 0:
				out.herd[str(rarity)] = int(herd[rarity])
	var run = raw.get("run", {})
	if run is Dictionary and run.has("floors") and run.has("at"):
		out.run = run
	var last = raw.get("last", {})
	if last is Dictionary and last.has("floor"):
		out.last = { "floor": int(last.floor), "got": int(last.get("got", 0)), "back": int(last.get("back", 0)) }
		if last.has("room"):  # a sewing room run (its room's number)
			out.last.room = maxi(0, int(last.room))
	var firsts = raw.get("firsts", {})
	if firsts is Dictionary:
		for f in firsts:
			out.firsts[str(f)] = true
	# the crowds holding landings: only real landings (every 10th), counts made safe, at most the need
	var held = raw.get("held", {})
	if held is Dictionary:
		var every := hold_every(catalog)
		for key in held:
			var f := int(str(key)) if str(key).is_valid_int() else 0
			if f <= 0 or f % every != 0:
				continue
			var counts := Herd.clean_counts(catalog, held[key])
			var over := Herd.total(counts) - hold_need(catalog, f)
			var keys := counts.keys()
			keys.sort()
			for k in keys:
				if over <= 0:
					break
				var cut := mini(over, int(counts[k]))
				Herd.take(counts, k, cut)
				over -= cut
			if Herd.total(counts) > 0:
				out.held[str(f)] = counts
	out.start = int(raw.get("start", 0))
	if not out.start in starts(catalog, out):
		out.start = 0
	out.target = clampi(maxi(out.target, out.start + 1), 1, target_max(catalog, out))
	return out


# ---- held landings: crowds holding every 10th landing (data "hold") -----------------------

static func _hold(catalog: Catalog) -> Dictionary:
	return data(catalog).get("hold", {})


## A whole number from data "hold" (faces, card_faces, looks...), `fallback` when it isn't there.
static func hold_int(catalog: Catalog, key: String, fallback: int) -> int:
	return int(_hold(catalog).get(key, fallback))


## Every how many floors a landing can be held.
static func hold_every(catalog: Catalog) -> int:
	return maxi(1, int(_hold(catalog).get("every", 10)))


## How many pets it takes to hold landing `f` (0 if it isn't a landing that can be held): the list for
## the first few, then the last one x grow each step after.
static func hold_need(catalog: Catalog, f: int) -> int:
	var every := hold_every(catalog)
	if f <= 0 or f % every != 0:
		return 0
	var need: Array = _hold(catalog).get("need", [500])
	var i := f / every - 1
	if i < need.size():
		return int(need[i])
	return roundi(float(need.back()) * pow(float(_hold(catalog).get("grow", 3)), i - need.size() + 1))


## What the crowd on landing `f` holds: the rope, the door or the stairs (by its band's kind).
static func hold_what(catalog: Catalog, f: int) -> String:
	return str(_hold(catalog).get("what", {}).get(str(band_of(catalog, f).kind), "the stairs"))


## How many pets hold landing `f` now.
static func held_n(state: Dictionary, f: int) -> int:
	return Herd.total(state.get("held", {}).get(str(f), {}))


## Whether landing `f` is fully held (the army can start there).
static func is_held(catalog: Catalog, state: Dictionary, f: int) -> bool:
	var need := hold_need(catalog, f)
	return need > 0 and held_n(state, f) >= need


## The landings a crowd could hold: every 10th, down to the deepest floor the army has cleared.
static func hold_spots(catalog: Catalog, state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	var every := hold_every(catalog)
	var f := every
	while f <= int(state.get("deep", 0)):
		out.append(f)
		f += every
	return out


## Where the orders can start from: the top (0), and every fully held landing.
static func starts(catalog: Catalog, state: Dictionary) -> Array[int]:
	var out: Array[int] = [0]
	out.append_array(held_landings(catalog, state))
	return out


## The fully held landings (their guards are gone: see strength).
static func held_landings(catalog: Catalog, state: Dictionary) -> Array[int]:
	var out: Array[int] = []
	for f in hold_spots(catalog, state):
		if is_held(catalog, state, f):
			out.append(f)
	return out


## The kind a floor fights as: a fully held guard landing is plain stairs (its guard is gone).
static func kind_at(catalog: Catalog, f: int, held: Array) -> String:
	var kind := floor_kind(catalog, f)
	return "stairs" if kind == "guard" and f in held else kind


# ---- the well: bands and floors ---------------------------------------------------

static func band(catalog: Catalog, id: String) -> Dictionary:
	for b in data(catalog).bands:
		if b.id == id:
			return b
	return {}


## The band a floor is in (the last one goes on forever).
static func band_of(catalog: Catalog, f: int) -> Dictionary:
	var bands: Array = data(catalog).bands
	for b in bands:
		if f >= int(b.from) and (not b.has("to") or f <= int(b.to)):
			return b
	return bands[bands.size() - 1]


## What a floor is like: rope, door, tiny (a tiny door), knock (a knock-back door), stairs or guard.
static func floor_kind(catalog: Catalog, f: int) -> String:
	var b := band_of(catalog, f)
	match str(b.kind):
		"rope":
			return "rope"
		"doors":
			if f in b.get("tiny", []).map(func(v): return int(v)):
				return "tiny"
			if f in b.get("knock", []).map(func(v): return int(v)):
				return "knock"
			return "door"
		"stairs":
			var every := int(b.get("guard_every", 0))
			return "guard" if every > 0 and f % every == 0 else "stairs"
	return "door"


## A floor's strength (never shown as a number: see word()). `held`: the landing is fully held, so a
## guard floor's guard is gone (no guard_x).
static func strength(catalog: Catalog, f: int, held := false) -> float:
	var s: Dictionary = data(catalog).strength
	var x := float(band_of(catalog, f).get("guard_x", 1.0)) if floor_kind(catalog, f) == "guard" and not held else 1.0
	return float(s.base) * pow(float(s.grow), f) * x


## The bands shown on the well: ones the army has stood at the top of, and ones an old save had open.
static func shown_bands(catalog: Catalog, state: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for b in data(catalog).bands:
		if str(b.id) in state.get("bands", []) or int(state.get("deep", 0)) >= int(b.from) - 1:
			out.append(str(b.id))
	return out


## The deepest floor drawn: the end of the last band shown (the last band goes on forever).
static func shown_to(catalog: Catalog, state: Dictionary) -> int:
	var to := 1
	for id in shown_bands(catalog, state):
		var b := band(catalog, id)
		if not b.has("to"):
			return 1 << 20
		to = maxi(to, int(b.to))
	return to


## The deepest floor the orders may aim for: a few past the deepest cleared, inside the bands shown.
static func target_max(catalog: Catalog, state: Dictionary) -> int:
	return maxi(1, mini(int(state.get("deep", 0)) + int(data(catalog).get("target_ahead", 5)), shown_to(catalog, state)))


## Whether "who goes first" has been earned.
static func first_earned(catalog: Catalog, state: Dictionary) -> bool:
	return int(state.get("deep", 0)) >= int(data(catalog).first.get("earn_floor", 11))


## How many pets fit through the entrance at once, at its level (widening it is the first wisps perk).
static func entrance(catalog: Catalog, level: int) -> int:
	return int(Perks.count_at(catalog, "entrance", level))


## What clearing a floor pays: base x grow^floor x pets sent (at most the entrance) x pay_x (the
## lanterns boost), at least 1.
static func pay(catalog: Catalog, f: int, sent: int, level: int, pay_x := 1.0) -> int:
	var p: Dictionary = data(catalog).pay
	return maxi(1, roundi(float(p.base) * pow(float(p.grow), f) * mini(sent, entrance(catalog, level)) * pay_x))


## How many cards fight in the front row for an army (the pinwheel perk makes it more).
static func front_n(catalog: Catalog, army: Dictionary) -> int:
	return int(army.get("front_n", Perks.count_at(catalog, "front_row", 0)))


## The feeling word for a floor from the army's power over its strength: [word, heat].
static func word(catalog: Catalog, ratio: float) -> Array:
	for w in data(catalog).words:
		if ratio >= float(w[0]):
			return [str(w[1]), str(w[2]) if w.size() > 2 else ""]
	var last: Array = data(catalog).words.back()
	return [str(last[1]), str(last[2]) if last.size() > 2 else ""]


# ---- power -----------------------------------------------------------------------

## A pet's power: its power stat (traits count) x its rarity x its finish x its own power knack.
static func pet_power(catalog: Catalog, pet: Pet, own := 1.0) -> float:
	var p: Dictionary = data(catalog).power
	return Party.stat_of(pet, "power", catalog) * float(p.rarity_x.get(pet.rarity, 1.0)) * float(p.finish_x.get(pet.finish, 1.0)) * own


## The knock doors' chance: base + per_luck x the front row's average luck, x the luck boost.
static func knock_chance(catalog: Catalog, avg_luck: float, luck_boost := 1.0) -> float:
	var b := band_of(catalog, _first_knock(catalog))
	var k: Dictionary = b.get("knock_luck", { "base": 0.5, "per_luck": 0.0, "max": 0.95 })
	return clampf((float(k.base) + float(k.per_luck) * avg_luck) * luck_boost, 0.0, float(k.get("max", 0.95)))


static func _first_knock(catalog: Catalog) -> int:
	for b in data(catalog).bands:
		if not b.get("knock", []).is_empty():
			return int(b.knock[0])
	return 1


## The army's power on a kind of floor (no one hurt yet), for the feeling words.
static func army_power(catalog: Catalog, army: Dictionary, kind: String) -> float:
	var herd := {}
	for k in army.get("herd", {}):
		herd[k] = int(army.herd[k].n)
	return _power(catalog, army.get("cards", []), {}, herd, {}, army.get("herd", {}), kind, army)


## The band kind a floor kind is in ("room" for the sewing room's rooms), for the army's band_x.
static func band_kind(kind: String) -> String:
	match kind:
		"rope": return "rope"
		"door", "tiny", "knock": return "doors"
		"stairs", "guard": return "stairs"
	return kind


## Rope floors: only the front row fights. Tiny doors: only pets rare enough get through (the best
## of them in front). Everyone else walking behind counts herd_x, injured pets injured_x. The army's
## perks: front_x on the front row, behind_x on everyone behind, band_x by where they are.
static func _power(catalog: Catalog, cards: Array, hurt: Dictionary, herd: Dictionary, herd_hurt: Dictionary, info: Dictionary,
		kind: String, army: Dictionary) -> float:
	var d := data(catalog)
	var boost := float(army.get("boost", 1.0)) * float(army.get("band_x", {}).get(band_kind(kind), 1.0))
	var in_row := front_n(catalog, army)
	var fx := float(army.get("front_x", 1.0))
	var hx := float(d.get("herd_x", 0.5)) * float(army.get("behind_x", 1.0))
	var ix := float(d.get("injured_x", 0.5))
	var need := _tiny_rank(catalog) if kind == "tiny" else -1
	var sum := 0.0
	var in_front := 0
	for c in cards:
		if int(c.rank) < need:
			continue
		var p := float(c.power) * (ix if hurt.has(c.uid) else 1.0)
		if in_front < in_row:
			sum += p * fx
			in_front += 1
		elif kind != "rope":
			sum += p * hx
	if kind != "rope":
		for k in herd:
			if int(info[k].rank) < need:
				continue
			var n := int(herd[k])
			var h := mini(n, int(herd_hurt.get(k, 0)))
			sum += float(info[k].power) * hx * ((n - h) + h * ix)
	return sum * boost


static func _tiny_rank(catalog: Catalog) -> int:
	for b in data(catalog).bands:
		if b.has("tiny_from"):
			return catalog.rank(str(b.tiny_from))
	return 0


# ---- a run -----------------------------------------------------------------------

## Works a whole run out when the army sets off, floor by floor. `orders`: { target, start (the held
## landing it starts from, 0 the top: the floors above it are skipped, no fights and no pay), held
## (the fully held landings: a held guard floor has no guard), home_at (a
## percent), first (a line of data "first", or "" before it's earned: injured first, then anyone),
## entrance (its level), pay_x (the lanterns boost) }. Returns { floors: [{ f, cleared, lost_cards: [uids], lost_herd:
## { key: n }, pay }], why: target | home | stuck | knock | gone, turned: the floor they turned back
## at (0 if none) }. A knock door that isn't answered sends them home (no losses, no pay for it); a
## floor too strong to pass takes its losses and pays nothing. Pay never looks at losses.
## `orders.safe` (the music box's runs while the game is closed, see away_safe): the army only goes
## as deep as floors it clears safely (its power at least `safe` x the floor's): nobody is lost or
## hurt there, and it turns home before the first floor that isn't (why "safe").
static func simulate(catalog: Catalog, army: Dictionary, orders: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var d := data(catalog)
	var cards: Array = army.get("cards", []).duplicate()
	var info: Dictionary = army.get("herd", {})
	var herd := {}
	for k in info:
		if int(info[k].n) > 0:
			herd[k] = int(info[k].n)
	var hurt := {}
	var herd_hurt := {}
	var sent := cards.size() + Herd.total(herd)
	var limit := maxi(1, ceili(sent * float(orders.get("home_at", 30)) / 100.0))
	var first := str(orders.get("first", ""))
	var lost_n := 0
	var floors: Array = []
	var why := "target"
	var turned := 0
	var f := clampi(int(orders.get("start", 0)), 0, maxi(0, int(orders.get("target", 1)) - 1))
	var held: Array = orders.get("held", [])
	var safe := float(orders.get("safe", 0.0))
	while f < int(orders.get("target", 1)) and sent > 0:
		f += 1
		var kind := kind_at(catalog, f, held)
		if kind == "knock" and rng.randf() >= float(army.get("luck", 0.5)):
			why = "knock"
			turned = f
			break
		var ratio := _power(catalog, cards, hurt, herd, herd_hurt, info, kind, army) / strength(catalog, f, f in held)
		if safe > 0.0 and ratio < safe:
			why = "safe"  # losses only happen while you're here
			break
		var gone := [[], {}] if safe > 0.0 else _fight(catalog, ratio, first, cards, hurt, herd, herd_hurt, rng, front_n(catalog, army))
		lost_n += gone[0].size() + Herd.total(gone[1])
		var cleared := ratio >= float(d.get("stuck", 0.4))
		floors.append({ "f": f, "cleared": cleared, "lost_cards": gone[0], "lost_herd": gone[1],
			"pay": pay(catalog, f, sent, int(orders.get("entrance", 0)), float(orders.get("pay_x", 1.0))) if cleared else 0 })
		if not cleared:
			why = "stuck"
			turned = f
			break
		if lost_n >= sent:
			why = "gone"
			break
		if lost_n >= limit and f < int(orders.get("target", 1)):
			why = "home"
			break
	return { "floors": floors, "why": why, "turned": turned }


## One fight at `ratio` (the army's power over what it's up against): some get hurt (they fight at
## injured_x from now on), some don't come back, by who goes first. The army's pools change in place.
## Returns [lost card uids, { count key: n }].
static func _fight(catalog: Catalog, ratio: float, first: String, cards: Array, hurt: Dictionary, herd: Dictionary,
		herd_hurt: Dictionary, rng: RandomNumberGenerator, front := -1) -> Array:
	var d := data(catalog)
	var l: Dictionary = d.losses
	var alive := cards.size() + Herd.total(herd)
	var fresh := alive - hurt.size() - Herd.total(herd_hurt)
	_injure(_round(fresh * minf(float(l.max_share), float(l.injure) / maxf(ratio, 0.01)), rng), cards, hurt, herd, herd_hurt, rng)
	var n_lost := mini(alive, _round(alive * minf(float(l.max_share), float(l.lose) / maxf(ratio * ratio, 0.0001)), rng))
	return _take(n_lost, first, cards, hurt, herd, herd_hurt, front if front >= 0 else int(Perks.count_at(catalog, "front_row", 0)), rng)


## A room of the sewing room (see Sewing): one fight against `strength` where everyone fights (no
## rope, no tiny doors). A clear (at least the stuck ratio) pays `pay`. The run stands at `door`
## (the well floor the rooms are off) the whole time. Returns the usual run shape, one entry.
static func simulate_room(catalog: Catalog, army: Dictionary, strength: float, pay: int, door: int, first: String,
		rng: RandomNumberGenerator) -> Dictionary:
	var d := data(catalog)
	var cards: Array = army.get("cards", []).duplicate()
	var info: Dictionary = army.get("herd", {})
	var herd := {}
	for k in info:
		if int(info[k].n) > 0:
			herd[k] = int(info[k].n)
	if cards.size() + Herd.total(herd) <= 0:
		return { "floors": [], "why": "gone", "turned": 0 }
	var ratio := _power(catalog, cards, {}, herd, {}, info, "room", army) / maxf(strength, 0.001)
	var gone := _fight(catalog, ratio, first, cards, {}, herd, {}, rng, front_n(catalog, army))
	var cleared := ratio >= float(d.get("stuck", 0.4))
	return { "floors": [{ "f": door, "cleared": cleared, "lost_cards": gone[0], "lost_herd": gone[1], "pay": pay if cleared else 0 }],
		"why": "target" if cleared else "stuck", "turned": 0 }


## The deepest floor a run cleared (0 if none).
static func cleared_to(run: Dictionary) -> int:
	var to := 0
	for fl in run.get("floors", []):
		if fl.get("cleared", true):
			to = maxi(to, int(fl.f))
	return to


## Wisps a run brought home.
static func run_pay(run: Dictionary) -> int:
	var got := 0
	for fl in run.get("floors", []):
		got += int(fl.get("pay", 0))
	return got


## Everyone a run lost: [card uids, { count key: n }].
static func run_lost(run: Dictionary) -> Array:
	var cards: Array = []
	var herd := {}
	for fl in run.get("floors", []):
		cards.append_array(fl.get("lost_cards", []))
		for k in fl.get("lost_herd", {}):
			Herd.put(herd, str(k), int(fl.lost_herd[k]))
	return [cards, herd]


## How long a run takes: a floor at a time, and back from a floor they turned at. A run from a held
## landing takes only the floors it walked (the skipped ones take no time).
static func run_seconds(catalog: Catalog, run: Dictionary) -> float:
	if run.has("seconds"):  # a sewing room run takes its own time
		return float(run.seconds)
	var walked: int = run.get("floors", []).size()
	var start := int(run.get("start", 0))
	var floors := maxi(1, walked + (1 if int(run.get("turned", 0)) > 0 and start + walked < int(run.turned) else 0))
	return floors * float(data(catalog).get("seconds_per_floor", 20))


## Where the army is now (floors from the top, 0 at the well mouth), `seconds` after it set off.
static func run_floor(catalog: Catalog, run: Dictionary, seconds: float) -> float:
	if run.has("room"):  # in the sewing room: the army stands at its door the whole time
		return float(run.get("door", data(catalog).get("door_floor", 20)))
	var per := float(data(catalog).get("seconds_per_floor", 20))
	var start := float(run.get("start", 0))  # from a held landing: it pops out there
	var deepest := maxf(float(run.get("turned", 0)), start + run.get("floors", []).size())
	return clampf(start + seconds / per, start, deepest)


static func _round(x: float, rng: RandomNumberGenerator) -> int:
	var whole := floori(x)
	return whole + (1 if rng.randf() < x - whole else 0)


## Hurts `n` pets that aren't hurt yet, anyone.
static func _injure(n: int, cards: Array, hurt: Dictionary, herd: Dictionary, herd_hurt: Dictionary, rng: RandomNumberGenerator) -> void:
	var pool_cards: Array = cards.filter(func(c): return not hurt.has(c.uid))
	var pool_herd := {}
	for k in herd:
		var free := int(herd[k]) - int(herd_hurt.get(k, 0))
		if free > 0:
			pool_herd[k] = free
	var picked := _random(n, pool_cards, pool_herd, rng)
	for c in picked[0]:
		hurt[c.uid] = true
	for k in picked[1]:
		herd_hurt[k] = int(herd_hurt.get(k, 0)) + int(picked[1][k])


## Takes `n` pets out of the army, by who goes first. Returns [lost card uids, { key: n }].
static func _take(n: int, first: String, cards: Array, hurt: Dictionary, herd: Dictionary, herd_hurt: Dictionary,
		row_n: int, rng: RandomNumberGenerator) -> Array:
	var lost_cards: Array = []
	var lost_herd := {}
	if n <= 0:
		return [lost_cards, lost_herd]
	var order: Array = []  # [card pool, herd pool] in the order they go
	match first:
		"":  # not earned yet: the injured first, then anyone
			var hurt_herd := {}
			for k in herd_hurt:
				if int(herd_hurt[k]) > 0:
					hurt_herd[k] = mini(int(herd_hurt[k]), int(herd.get(k, 0)))
			order.append([cards.filter(func(c): return hurt.has(c.uid)), hurt_herd])
			order.append([cards, herd])
		"plain ones":
			order.append([[], herd])
			order.append([cards, {}])
		"the front row":
			order.append([cards.slice(0, row_n), {}])
			order.append([cards, herd])
		_:
			order.append([cards, herd])
	var left := n
	for pools in order:
		if left <= 0:
			break
		var gone_cards := {}
		for uid in lost_cards:
			gone_cards[uid] = true
		var pool_cards: Array = pools[0].filter(func(c): return not gone_cards.has(c.uid))
		var pool_herd := {}
		for k in pools[1]:
			var have := mini(int(pools[1][k]), int(herd.get(k, 0)) - int(lost_herd.get(k, 0)))
			if have > 0:
				pool_herd[k] = have
		var picked := _random(left, pool_cards, pool_herd, rng)
		for c in picked[0]:
			lost_cards.append(c.uid)
		for k in picked[1]:
			Herd.put(lost_herd, k, int(picked[1][k]))
		left -= picked[0].size() + Herd.total(picked[1])
	# out of the army for good
	var out := {}
	for uid in lost_cards:
		out[uid] = true
		hurt.erase(uid)
	var kept: Array = cards.filter(func(c): return not out.has(c.uid))
	cards.clear()
	cards.append_array(kept)
	for k in lost_herd:
		var n_k := int(lost_herd[k])
		var was_hurt := int(herd_hurt.get(k, 0))
		var from_hurt := mini(was_hurt, roundi(n_k * float(was_hurt) / maxf(1.0, float(herd[k])))) if first != "" else mini(was_hurt, n_k)
		Herd.take(herd, k, n_k)
		herd_hurt[k] = mini(maxi(0, was_hurt - from_hurt), int(herd.get(k, 0)))
	return [lost_cards, lost_herd]


## Up to `n` picked at random out of cards and counts, each pet about as likely as any other:
## [cards, { key: n }]. The cards are picked one by one; the herd's share is split over its counts
## in one go (so a herd-sized army costs a step per count, not per pet).
static func _random(n: int, pool_cards: Array, pool_herd: Dictionary, rng: RandomNumberGenerator) -> Array:
	var cards := pool_cards.duplicate()
	var herd_total := Herd.total(pool_herd)
	var take := mini(n, cards.size() + herd_total)
	var split := _split(take, [cards.size(), herd_total], rng)
	var out_cards: Array = []
	for i in split[0]:
		var r := rng.randi_range(0, cards.size() - 1)
		out_cards.append(cards[r])
		cards[r] = cards[cards.size() - 1]
		cards.pop_back()
	var keys: Array = pool_herd.keys()
	var sizes: Array = keys.map(func(k): return int(pool_herd[k]))
	var shares := _split(split[1], sizes, rng)
	var out_herd := {}
	for i in keys.size():
		if shares[i] > 0:
			out_herd[keys[i]] = shares[i]
	return [out_cards, out_herd]


## `n` picks shared out over groups of `sizes` (n at most their total), each group about in step
## with its size, never more than it has: [how many from each].
static func _split(n: int, sizes: Array, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var left := n
	var pool := 0
	for s in sizes:
		pool += int(s)
	for s in sizes:
		var size := int(s)
		var x := 0
		if left > 0 and size > 0:
			var rest := pool - size
			x = clampi(_round(left * float(size) / float(pool), rng), maxi(0, left - rest), mini(size, left))
		out.append(x)
		left -= x
		pool -= size
	return out
