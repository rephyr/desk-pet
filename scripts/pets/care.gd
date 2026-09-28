class_name Care
extends RefCounted
## Care (data/care.json): your active pet's food and mood as buffs, never as guilt. They only go
## down while the game is open, never below the floor; above a buff's line (strictly) they give a
## boost part { source "care", id, x } on the buff's kind (coins for a full tummy, luck for happy),
## so they show with every other source; like the drain, the buffs only count while the game is open. A snack costs capsules (x Machine.coin_value). Pure rules:
## GameState holds food (hunger) and mood (happiness) and adds these parts in boost_parts.


static func data(catalog: Catalog) -> Dictionary:
	return catalog.care


static func floor_value(catalog: Catalog) -> float:
	return float(catalog.care.get("floor", 20))


## Where a stat's buff turns on (its bar's small mark), -1 when there's no buff on it.
static func line(catalog: Catalog, stat: String) -> float:
	return float(buff_of(catalog, stat).get("above", -1))


## A stat ("food" or "mood") after `seconds` of the game being open: down at its drain rate, never
## below the floor (and never raised if it's somehow under it already).
static func drain(catalog: Catalog, stat: String, value: float, seconds: float) -> float:
	var hours := float(catalog.care.get("drain_hours", {}).get(stat, 0.0))
	if hours <= 0.0 or seconds <= 0.0:
		return value
	var lo := floor_value(catalog)
	var per_second := 100.0 / (hours * 3600.0)
	return maxf(minf(value, lo), value - per_second * seconds)


## The buff this stat gives, {} when there's none on it.
static func buff_of(catalog: Catalog, stat: String) -> Dictionary:
	for b in catalog.care.get("buffs", []):
		if str(b.stat) == stat:
			return b
	return {}


## Whether a buff is on at these stats (strictly above its line).
static func on(buff: Dictionary, food: float, mood: float) -> bool:
	var v := food if str(buff.stat) == "food" else mood
	return v > float(buff.above)


## Whether going from one food and mood to another turns a buff on or off (checked every frame,
## so it allocates nothing).
static func crossed(catalog: Catalog, food: float, mood: float, new_food: float, new_mood: float) -> bool:
	for b in catalog.care.get("buffs", []):
		if on(b, food, mood) != on(b, new_food, new_mood):
			return true
	return false


## The buffs on right now, by id (for noticing when one turns on or off).
static func on_ids(catalog: Catalog, food: float, mood: float) -> Array[String]:
	var out: Array[String] = []
	for b in catalog.care.get("buffs", []):
		if on(b, food, mood):
			out.append(str(b.id))
	return out


## The boost parts care gives this kind at these stats.
static func parts(catalog: Catalog, kind: String, food: float, mood: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b in catalog.care.get("buffs", []):
		if str(b.kind) == kind and on(b, food, mood):
			out.append(Boosts.part("care", str(b.id), float(b.x)))
	return out


## Coins a snack costs: its capsules at what a plain capsule is worth now (at least 1).
static func snack_price(catalog: Catalog, coin_value: float) -> int:
	return maxi(1, roundi(float(catalog.care.get("snack", {}).get("capsules", 3)) * coin_value))
