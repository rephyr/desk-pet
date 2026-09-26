class_name Pet
extends RefCounted
## One pet: its rolled parts, finish, traits and stats. Plain data, no visuals.

const STATS: Array[String] = ["power", "luck", "speed"]

var uid := ""
var parts := {}  # slot -> part id, see Catalog.SLOTS
var finish := "normal"
var traits: Array[String] = []
var stats := {}  # stat name -> int
var rarity := "common"  # overall tier, rolled first; the finish is a separate axis
var box := ""  # which box it came from
var pulled_at := 0  # unix time


func display_name(catalog: Catalog) -> String:
	var words: Array[String] = []
	var finish_name: String = catalog.finish(finish).name
	if finish_name != "":
		words.append(finish_name)
	words.append(catalog.part("palette", parts.palette).get("name", parts.palette))
	words.append(catalog.part("body", parts.body).get("name", parts.body))
	return " ".join(words)


func to_dict() -> Dictionary:
	return {
		"uid": uid,
		"parts": parts,
		"finish": finish,
		"traits": traits,
		"stats": stats,
		"rarity": rarity,
		"box": box,
		"pulled_at": pulled_at,
	}


## Loads a saved pet. Slots, parts or finishes that have since been added or removed from
## data/ are fixed up so old saves keep working.
static func from_dict(d: Dictionary, catalog: Catalog = Catalog.shared()) -> Pet:
	var p := Pet.new()
	p.uid = str(d.get("uid", ""))
	var saved: Dictionary = d.get("parts", {})
	for slot in Catalog.SLOTS:
		var id: String = saved.get(slot, "")
		p.parts[slot] = id if not catalog.part(slot, id).is_empty() else catalog.default_part(slot)
	p.finish = catalog.finish(d.get("finish", "")).id
	p.traits.assign(d.get("traits", []))
	p.stats = {}
	for key in d.get("stats", {}):
		p.stats[key] = int(d.stats[key])  # JSON gives floats back
	var tier: String = d.get("rarity", "")
	p.rarity = tier if catalog.tiers.any(func(t): return t.id == tier) else catalog.tiers[0].id
	p.box = d.get("box", "")
	p.pulled_at = int(d.get("pulled_at", 0))
	return p
