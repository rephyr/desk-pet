class_name Goals
extends RefCounted
## What earns the next unlocks, shown as goals with their progress: the carrot that keeps you pulling
## and sending (Emilia, playtest 1). One goal per unlock in data/unlocks.json that's in reach: its
## other unlocks ("open") are open, and what it needs is somewhere you can get to (the place with
## its find is open, the machine node shows on the tree, the job is there). Each goal names what
## it opens ("goal" in data/unlocks.json, else its popup title) and lists its steps, each with how
## far along it is. Nothing here explains how a feature works: it only says what to do next.
## Reads GameState (`gs`), changes nothing.


## Every goal in reach: { id, name, steps: [{ text, have, need, place }], done (0..1) }, the
## closest first.
static func list(gs: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry in gs.catalog.unlock_list:
		var g := goal(gs, entry)
		if not g.is_empty():
			out.append(g)
	out.sort_custom(func(a, b): return float(a.done) > float(b.done))
	return out


## The goals with a step at this place (a find there, pets to send there).
static func at_place(gs: Node, location_id: String) -> Array[Dictionary]:
	return list(gs).filter(func(g): return g.steps.any(func(s): return s.place == location_id))


## One unlock's goal, or {} when it's open already or out of reach.
static func goal(gs: Node, entry: Dictionary) -> Dictionary:
	if entry.opens.all(func(o): return gs.is_unlocked(o)):
		return {}
	var earn: Dictionary = entry.earn
	if earn.get("called", false) or (earn.has("open") and not gs.is_unlocked(str(earn.open))):
		return {}
	var steps: Array[Dictionary] = []
	for key in earn:
		if key == "open":
			continue
		var got = _steps(gs, str(key), earn[key])  # null: out of reach
		if got == null:
			return {}  # out of reach: nothing to work towards yet
		steps.append_array(got)
	if steps.is_empty():
		return {}
	var done := 0.0
	for s in steps:
		done += clampf(float(s.have) / maxf(1.0, float(s.need)), 0.0, 1.0)
	return { "id": str(entry.id), "name": name_of(entry), "steps": steps, "done": done / steps.size() }


## What an unlock is called on its goal: "goal" in the data, else its popup's title without "new: ".
static func name_of(entry: Dictionary) -> String:
	if entry.has("goal"):
		return str(entry.goal)
	return str(entry.get("popup", {}).get("title", entry.id)).trim_prefix("new: ").trim_suffix("!")


## `place`: the place it's about (its card shows the goal too), `go`: the tab it's done on.
static func _step(text: String, have: float, need: float, place := "", go := "adventures") -> Dictionary:
	return { "text": text, "have": minf(have, need), "need": need, "place": place, "go": go }


## The steps for one earn condition, or null when it can't be worked towards yet.
static func _steps(gs: Node, key: String, want: Variant):
	var catalog: Catalog = gs.catalog
	match key:
		"find":
			return _find_steps(gs, str(want))
		"trips":
			return [_step("adventures", gs.trips_done, int(want))]
		"machine":
			var n := Machine.node(catalog, str(want))
			if n.is_empty() or (n.has("from") and Machine.owned(gs.machine, str(n.from)) <= 0):
				return null  # not on the tree yet
			return [_step(str(n.name), mini(1, Machine.owned(gs.machine, str(want))), 1, "", "machine")]
		"packs_opened":
			if not gs.tab_open("boxes"):
				return null
			return [_step("boxes opened by hand", gs.packs_by_hand, int(want), "", "boxes")]
		"first":
			if not gs.is_unlocked("feature:parts" if str(want) == "part" else "feature:toys"):
				return null  # nothing drops them yet
			if str(want) == "part":
				return [_step("a first part", 1 if gs.parts_ever else 0, 1)]
			return [_step("a first toy", 0 if gs.toys.owned.is_empty() else 1, 1, "", "machine")]
		"taught":
			if not gs.tab_open("automation"):
				return null
			return [_step("your pet learns %s" % _job_name(catalog, str(want)), 1 if gs.knows_job(str(want)) else 0, 1, "", "automation")]
		"others":
			if not gs.tab_open("automation"):
				return null
			return [_step("the others learn %s" % _job_name(catalog, str(want)), 1 if gs.knows_others(str(want)) else 0, 1, "", "automation")]
		"room":
			if not gs.room_shown():
				return null
			return [_step("a full room", 1 if gs.homes.room_was_full else 0, 1, "", "collection")]
		"homes_by_hand":
			return [_step("pets to new homes", int(gs.homes.by_hand), int(want), "", "collection")]
		"floor":
			if not gs.dungeon_open():
				return null
			return [_step("the army down to floor %d" % int(want), int(gs.dungeon.deep), int(want))]
		"sewing":
			return [_step("sewing rooms", int(gs.sewing.cleared), int(want))]
		"job_level":
			if not gs.tab_open("errands"):
				return null
			var out: Array[Dictionary] = []
			for job_id in want:
				var job: Dictionary = gs.open_jobs().filter(func(j): return j.id == job_id).front() if gs.open_jobs().any(func(j): return j.id == job_id) else {}
				if job.is_empty():
					return null
				out.append(_step("%s level" % str(job.get("name", job_id)), gs.job_level(str(job_id)), int(want[job_id]), "", "errands"))
			return out
		"all_places":
			if not gs.page_open(str(want)):
				return null
			var places: Array = catalog.locations.filter(func(l): return str(l.get("page", "")) == str(want) and not l.has("band"))
			var open := places.filter(func(l): return gs.location_open(l)).size()
			return [_step("places %s" % str(catalog.page_info(str(want)).get("name", want)), open, places.size())]
		"edge":
			return null  # next door's own hook (GameState.edge_done): shown as pets past the edge
		"edge_sent":
			if not gs.feature_on("edge"):
				return null
			return [_step("pets past the edge", int(gs.edge.get("ever", 0)), int(want))]
		"ours":
			if not gs.next_door_open():
				return null  # places only become ours once next door is open
			var place := catalog.location(str(want))
			return [_step("%s becomes ours" % str(place.get("name", want)), gs.visits_at(str(want)), Ours.needed(catalog, place), str(want))]
	return null


## A find comes from a trip to its place (once its event can turn up there), from a dungeon floor,
## or from a sewing room.
static func _find_steps(gs: Node, find_id: String):
	var catalog: Catalog = gs.catalog
	if gs.finds.has(find_id):
		return [_step(str(catalog.finds.get(find_id, {}).get("name", find_id)), 1, 1)]
	for floor in gs.catalog.dungeon.get("firsts", {}):
		if str(gs.catalog.dungeon.firsts[floor].get("find", "")) == find_id:
			if not gs.dungeon_open():
				return null
			return [_step("the army down to floor %s" % floor, int(gs.dungeon.deep), int(floor))]
	var rooms: Array = gs.catalog.sewing.get("rooms", [])
	for i in rooms.size():
		if str(rooms[i].get("first", {}).get("find", "")) == find_id:
			if not gs.feature_on("sewing"):
				return null
			return [_step("sewing rooms", int(gs.sewing.cleared), i + 1)]
	for location in catalog.locations:
		var ids: Array = location.get("events", []) + location.get("pool", []).map(func(p): return p.event)
		for id in ids:
			var e: Dictionary = catalog.events.get(str(id), {})
			if str(e.get("find", "")) != find_id:
				continue
			if not gs.location_open(location):
				return null
			return _event_steps(gs, e, location)
	return null


## The steps of a find's event at its place: what it waits for (workers, pets sent there), then a
## trip there (a few for a place that draws its events, see GameState.find_tries).
static func _event_steps(gs: Node, e: Dictionary, location: Dictionary):
	var catalog: Catalog = gs.catalog
	if e.has("after") and not gs.finds.has(str(e.after)):
		return null  # waits for another find first
	if e.has("after_machine") and Machine.owned(gs.machine, str(e.after_machine)) <= 0:
		return null  # waits for the machine
	var place := str(location.id)
	var where := str(location.get("name", place))
	var out: Array[Dictionary] = []
	if e.has("after_workers"):
		out.append(_step("workers", gs.workers_total(), int(e.after_workers)))
	if e.has("after_sent"):
		out.append(_step("pets sent to %s" % where, gs.sent_to(place), int(e.after_sent), place))
	var party := int(e.get("min_party", 1))
	var trip := "a party of %d to %s" % [party, where] if party > 1 else "a trip to %s" % where
	if location.has("pool"):
		out.append(_step(trip.replace("a trip to", "trips to"), int(gs.find_tries.get(str(e.find), 0)), catalog.find_sure_by, place))
	else:
		out.append(_step(trip, 0, 1, place))
	return out


static func _job_name(catalog: Catalog, id: String) -> String:
	return str(Automation.job(catalog, id).get("name", id))
