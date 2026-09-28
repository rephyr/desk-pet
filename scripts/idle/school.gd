class_name School
extends RefCounted
## The little school (data/school.json, the automation tab's school page): spare herd pets sit in
## a class; a full class rings the bell and stays on as teachers for good, and every worker gets a
## bit quicker (each class's step, multiplied together). Pure rules on the saved state:
##   { seated: { count key: pets in the class now }, classes: [{ size, step, faces: [3 stand-in uids] }] }
## Seated pets are already off the herd (they're at school); ringing the bell makes them stars.


static func fresh() -> Dictionary:
	return { "seated": {}, "classes": [] }


## The size of class `i` (0 = the first): the data's sizes, then each one `grow` times the last.
static func class_size(catalog: Catalog, i: int) -> int:
	var s: Dictionary = catalog.school
	var sizes: Array = s.get("sizes", [40])
	if i < sizes.size():
		return maxi(1, int(sizes[i]))
	var step := maxi(1, int(s.get("round", 10)))
	var raw := float(sizes[-1]) * pow(float(s.get("grow", 2.0)), i - sizes.size() + 1)
	return maxi(step, roundi(minf(raw, 1.0e15) / step) * step)


## The class being filled now (0 = the first).
static func class_number(state: Dictionary) -> int:
	return state.get("classes", []).size()


static func seated(state: Dictionary) -> int:
	return Herd.total(state.get("seated", {}))


static func seats_left(catalog: Catalog, state: Dictionary) -> int:
	return maxi(0, class_size(catalog, class_number(state)) - seated(state))


static func full(catalog: Catalog, state: Dictionary) -> bool:
	return seated(state) > 0 and seats_left(catalog, state) == 0


## Stand points of a rarity: how much one pet lifts its class's step.
static func points(catalog: Catalog, rarity: String) -> float:
	return float(catalog.school.get("points", {}).get(rarity, 1))


## A class's step in % from who sits in it: base + per_point x their average stand points, to 0.1.
static func step(catalog: Catalog, counts: Dictionary) -> float:
	var n := Herd.total(counts)
	if n <= 0:
		return 0.0
	var sum := 0.0
	for k in counts:
		sum += points(catalog, Herd.rarity_of(k)) * int(counts[k])
	var s: Dictionary = catalog.school.get("step", {})
	return snappedf(float(s.get("base", 1.0)) + float(s.get("per_point", 1.4)) * sum / n, 0.1)


## Every worker's speed from the classes that finished: each class's (1 + step %) multiplied together.
static func boost(state: Dictionary) -> float:
	var x := 1.0
	for c in state.get("classes", []):
		x *= 1.0 + float(c.get("step", 0.0)) / 100.0
	return x


## Adds `counts` (count key -> pets) to the class, up to its seats left. Returns what sat down.
static func seat(catalog: Catalog, state: Dictionary, counts: Dictionary) -> Dictionary:
	var sat := {}
	var left := seats_left(catalog, state)
	for k in counts:
		var take := mini(left, int(counts[k]))
		if take <= 0:
			continue
		Herd.put(state.seated, k, take)
		sat[k] = take
		left -= take
	return sat


## The bell: a full class becomes a class of teachers and the next class starts. `faces` are a few
## stand-in uids to remember it by. Returns the class, or {} when it isn't full.
static func ring(catalog: Catalog, state: Dictionary, faces: Array) -> Dictionary:
	if not full(catalog, state):
		return {}
	var done := { "size": seated(state), "step": step(catalog, state.seated), "faces": faces.slice(0, 3) }
	state.classes.append(done)
	state.seated = {}
	return done


## Which pets to draw at `desks` desks for `counts`: count key per desk, in proportion to the class
## (every kind that's there gets at least one desk), the rarest first.
static func desk_keys(catalog: Catalog, counts: Dictionary, desks: int) -> Array[String]:
	var out: Array[String] = []
	var n := Herd.total(counts)
	if n <= 0 or desks <= 0:
		return out
	var keys := counts.keys()
	keys.sort_custom(func(a, b):
		var ra := catalog.rank(Herd.rarity_of(a))
		var rb := catalog.rank(Herd.rarity_of(b))
		return ra > rb if ra != rb else str(a) < str(b))
	for k in keys:
		var share := maxi(1, roundi(float(counts[k]) / n * desks))
		for i in share:
			out.append(str(k))
	return out.slice(0, desks)


## The state from a save: known count keys, sizes and steps in range (older saves: fresh).
static func clean(catalog: Catalog, raw) -> Dictionary:
	var out := fresh()
	if not raw is Dictionary:
		return out
	var classes = raw.get("classes", [])
	if classes is Array:
		for c in classes:
			if not c is Dictionary:
				continue
			var faces: Array = []
			var saved_faces = c.get("faces", [])
			if saved_faces is Array:
				for f in saved_faces:
					if f is String and Herd.is_stand_in(f) and Herd.valid_key(catalog, Herd.key_of(f)):
						faces.append(f)
			var i: int = out.classes.size()
			var size_v = c.get("size", 0)
			var step_v = c.get("step", 0.0)
			out.classes.append({ "size": clampi(int(size_v) if (size_v is int or size_v is float) else 0, 0, class_size(catalog, i)),
				"step": clampf(float(step_v) if (step_v is int or step_v is float) else 0.0, 0.0, 1000.0), "faces": faces.slice(0, 3) })
	out.seated = Herd.clean_counts(catalog, raw.get("seated", {}))
	return out


## Pets past a class's seats (a save from elsewhere) stand up again: returns them (count key -> n)
## for the herd to take back.
static func trim(catalog: Catalog, state: Dictionary) -> Dictionary:
	var out := {}
	var over := seated(state) - class_size(catalog, class_number(state))
	if over <= 0:
		return out
	for k in state.seated.keys():
		var take := mini(over, int(state.seated[k]))
		if take > 0:
			Herd.take(state.seated, k, take)
			out[k] = take
			over -= take
	return out
