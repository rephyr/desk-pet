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


static func from_dict(d: Dictionary) -> Pet:
	var p := Pet.new()
	p.uid = str(d.get("uid", ""))
	p.parts = d.get("parts", {})
	p.finish = d.get("finish", "normal")
	p.traits.assign(d.get("traits", []))
	p.stats = {}
	for key in d.get("stats", {}):
		p.stats[key] = int(d.stats[key])  # JSON gives floats back
	p.rarity = d.get("rarity", "common")
	p.box = d.get("box", "")
	p.pulled_at = int(d.get("pulled_at", 0))
	return p
