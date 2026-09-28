class_name Party
extends RefCounted
## The pets on one run, as plain records: their uids and stats (traits already applied), who is
## injured and who was lost. Events work on the totals, so a party of 1 and of 10,000 go through
## the same maths; only picking *which* pets get hurt or lost looks at individual records.

const INJURED_STRENGTH := 0.5  # an injured pet counts this much towards the party's totals

var uids: Array[String] = []  # still with the party
var stats := {}  # uid -> { stat: value }, for everyone who set out
var injured := {}  # uid -> true
var lost: Array[String] = []  # didn't come back, in order
var names := {}  # uid -> display name, for the texts


static func make(pets: Array[Pet], catalog: Catalog) -> Party:
	var party := Party.new()
	for pet in pets:
		party.uids.append(pet.uid)
		party.names[pet.uid] = pet.display_name(catalog)
		var s := {}
		for stat_name in Pet.STATS:
			s[stat_name] = stat_of(pet, stat_name, catalog)
		party.stats[pet.uid] = s
	return party


## A pet's stat with its traits applied (e.g. brave = more power).
static func stat_of(pet: Pet, stat_name: String, catalog: Catalog) -> float:
	var value := float(pet.stats.get(stat_name, 0))
	for t in pet.traits:
		value *= float(catalog.trait_info(t).get("mods", {}).get(stat_name, 1.0))
	return value


func size() -> int:
	return uids.size()


func setting_out() -> int:
	return stats.size()


func injured_count() -> int:
	return injured.size()


## The party's combined stat; injured pets count for less.
func total(stat_name: String) -> float:
	var sum := 0.0
	for uid in uids:
		sum += float(stats[uid].get(stat_name, 0.0)) * (INJURED_STRENGTH if injured.has(uid) else 1.0)
	return sum


func average(stat_name: String) -> float:
	return total(stat_name) / maxf(1.0, size())


## "the party", or the pet's name when it's alone.
func who() -> String:
	return str(names.get(uids[0], "the party")) if size() == 1 else "the party"


## Loses `count` pets, the injured first. Returns who.
func lose(count: int, rng: RandomNumberGenerator) -> Array[String]:
	var gone: Array[String] = []
	var pool := _shuffled(injured.keys(), rng)
	pool.append_array(_shuffled(uids.filter(func(u): return not injured.has(u)), rng))
	for uid in pool.slice(0, mini(count, pool.size())):
		uids.erase(uid)
		injured.erase(uid)
		lost.append(uid)
		gone.append(uid)
	return gone


func injure(count: int, rng: RandomNumberGenerator) -> int:
	var healthy := _shuffled(uids.filter(func(u): return not injured.has(u)), rng)
	for uid in healthy.slice(0, mini(count, healthy.size())):
		injured[uid] = true
	return mini(count, healthy.size())


## Hurts `count` pets, each losing `hearts` hearts: a pet has two (healthy, then hurt), so a
## second heart lost means it doesn't come back. The first-aid leaf (see Gear) can turn that into
## staying hurt: `saves` pets for sure, then each other one at `share` chance.
## Returns { injured, lost, saved }.
func hurt(count: int, hearts: int, rng: RandomNumberGenerator, saves := 0, share := 0.0) -> Dictionary:
	var out := { "injured": 0, "lost": 0, "saved": 0 }
	for uid in _shuffled(uids, rng).slice(0, mini(count, uids.size())):
		if hearts >= 2 or injured.has(uid):
			var saved := saves > 0 or (share > 0.0 and rng.randf() < share)
			if saved:
				saves = maxi(0, saves - 1)
				out.saved += 1
				if not injured.has(uid):
					injured[uid] = true
					out.injured += 1
				continue
			uids.erase(uid)
			injured.erase(uid)
			lost.append(uid)
			out.lost += 1
		else:
			injured[uid] = true
			out.injured += 1
	return out


func heal(count: int, rng: RandomNumberGenerator) -> int:
	var hurt := _shuffled(injured.keys(), rng)
	for uid in hurt.slice(0, mini(count, hurt.size())):
		injured.erase(uid)
	return mini(count, hurt.size())


## The injured stay behind and don't come back.
func leave_injured() -> int:
	var hurt: Array[String] = []
	hurt.assign(injured.keys())
	for uid in hurt:
		uids.erase(uid)
		lost.append(uid)
	injured.clear()
	return hurt.size()


func to_dict() -> Dictionary:
	return { "uids": uids, "stats": stats, "injured": injured.keys(), "lost": lost, "names": names }


static func from_dict(d: Dictionary) -> Party:
	var party := Party.new()
	party.uids.assign(d.get("uids", []).map(func(u): return str(u)))
	party.lost.assign(d.get("lost", []).map(func(u): return str(u)))
	party.stats = d.get("stats", {})
	party.names = d.get("names", {})
	for uid in d.get("injured", []):
		party.injured[str(uid)] = true
	for uid in party.uids:
		if not party.stats.has(uid):
			party.stats[uid] = {}
	return party


static func _shuffled(list: Array, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	out.assign(list)
	for i in range(out.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := out[i]
		out[i] = out[j]
		out[j] = tmp
	return out
