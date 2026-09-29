class_name Pet
extends RefCounted
## One pet: its rolled parts, finish, traits and stats. Plain data, no visuals.

const STATS: Array[String] = ["power", "luck", "speed"]

var uid := ""
var parts := {}  # slot -> part id, see Catalog.SLOTS
var sewn: Array[String] = []  # slots whose part was sewn on (they show stitch marks)
var finish := "normal"
var traits: Array[String] = []
var stats := {}  # stat name -> int
var rarity := "common"  # overall tier, rolled first; the finish is a separate axis
var box := ""  # which box it came from
var pulled_at := 0  # unix time
var fav := false  # a favourite: on the pets tab's cushion, and always a card (never folds into the herd)
var new_part := false  # it brought a part the book hadn't seen yet: always a card
var buttons := {}  # slot -> buttons sewn on that part by the plushie machine (1..5, see Plushie): always a card


func display_name(catalog: Catalog) -> String:
	var words: Array[String] = []
	var finish_name: String = catalog.finish(finish).name
	if finish_name != "":
		words.append(finish_name)
	words.append(catalog.part("palette", parts.palette).get("name", parts.palette))
	words.append(catalog.part("body", parts.body).get("name", parts.body))
	return " ".join(words)


func to_dict() -> Dictionary:
	var d := {
		"uid": uid,
		"parts": parts,
		"sewn": sewn,
		"finish": finish,
		"traits": traits,
		"stats": stats,
		"rarity": rarity,
		"box": box,
		"pulled_at": pulled_at,
	}
	if fav:
		d.fav = true
	if new_part:
		d.new_part = true
	if not buttons.is_empty():
		d.buttons = buttons.duplicate()
	return d


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
	p.sewn.assign(d.get("sewn", []).filter(func(s): return s in Catalog.SLOTS))
	p.traits.assign(d.get("traits", []))
	p.stats = {}
	for key in d.get("stats", {}):
		p.stats[key] = int(d.stats[key])  # JSON gives floats back
	var tier: String = d.get("rarity", "")
	p.rarity = tier if catalog.tiers.any(func(t): return t.id == tier) else catalog.tiers[0].id
	p.box = d.get("box", "")
	p.pulled_at = int(d.get("pulled_at", 0))
	p.fav = bool(d.get("fav", false))
	p.new_part = bool(d.get("new_part", false))
	var saved_buttons = d.get("buttons", {})  # v24: the plushie machine's buttons
	if saved_buttons is Dictionary:
		for slot in saved_buttons:
			var n := clampi(int(saved_buttons[slot]), 0, Plushie.max_buttons(catalog))
			if str(slot) in Catalog.SLOTS and n > 0:
				p.buttons[str(slot)] = n
	return p
