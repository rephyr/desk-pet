class_name Ours
extends RefCounted
## Places becoming "ours" (next door, zone 3). Every next-door garden has a house behind it whose
## windows are its lights ("lights" in data/adventures.json): one goes out for every visit (a trip
## welcomed back from there), and when the last one is out your pet colours the garden in and the
## place is ours. Their gate and their garden path are ours from the start ("ours_at_start");
## places on other pages become ours after their page's "ours_after" visits (the backyard: lots),
## but only once next door is open ("ours": "opens_with"). An ours trip is safer and pays a bit
## more (the "ours" danger and loot), and the locals' trace events ("local": true) stop there.
## Pure rules: GameState keeps the visits (GameState.visits) and nothing here is ever saved.


## Visits it takes for this place to be ours: its lights, or its page's "ours_after"; 0 = never.
static func needed(catalog: Catalog, location: Dictionary) -> int:
	if location.has("lights"):
		return int(location.lights)
	return int(catalog.page_info(str(location.get("page", ""))).get("ours_after", 0))


## How many lights the house behind this place has (0: it has no house, e.g. a backyard place).
static func lights(location: Dictionary) -> int:
	return int(location.get("lights", 0))


## Lights still on behind this place after `visits` visits (0 once it's ours).
static func lights_left(location: Dictionary, visits: int) -> int:
	if location.get("ours_at_start", false):
		return 0
	return maxi(0, lights(location) - visits)


## The map page that has to be open before anything is ours.
static func opens_with(catalog: Catalog) -> String:
	return str(catalog.ours.get("opens_with", ""))


## Whether a place is ours after `visits` visits, with next door open (`open`) or not.
static func is_ours(catalog: Catalog, location: Dictionary, visits: int, open: bool) -> bool:
	if not open or location.is_empty():
		return false
	if location.get("ours_at_start", false):
		return true
	var n := needed(catalog, location)
	return n > 0 and visits >= n


## The place as an ours trip meets it: danger and loot multiplied by the "ours" numbers. A copy:
## the catalog's own place stays as it is. Not ours: the place itself.
static func place(catalog: Catalog, location: Dictionary, ours: bool) -> Dictionary:
	if not ours or location.is_empty():
		return location
	var out := location.duplicate()
	out.danger = float(location.get("danger", 1.0)) * float(catalog.ours.get("danger", 1.0))
	out.loot = float(location.get("loot", 1.0)) * float(catalog.ours.get("loot", 1.0))
	return out


## What your pet says ("say_dark" when a light goes out, "say_ours" when a place turns ours).
static func say(catalog: Catalog, key: String, location: Dictionary) -> String:
	return str(catalog.ours.get(key, "")).replace("{place}", str(location.get("name", "")))


## Visits for a save from before they were counted (v24): every place already visited counts once.
static func visits_from(visited: Array) -> Dictionary:
	var out := {}
	for id in visited:
		out[str(id)] = 1
	return out
