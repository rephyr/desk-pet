class_name Bookcase
extends VBoxContainer
## The pets page of collectibles, once there are lots: a pink cushion on top with your active pet,
## favourites and best ones, and a bookcase with a plank per rarity you have (ShelfPlank). Tap a
## plank (or a pet on the cushion) to open that shelf (ShelfView).
## Design: design/mockups/screens/pets-shelves.html (look A, the bookcase).

signal shelf_opened(rarity: String, pet: Pet)

var _cushion := PanelContainer.new()
var _cushion_row := HBoxContainer.new()
var _case := PanelContainer.new()
var _planks := VBoxContainer.new()

## A plank never gets taller than this: with only a shelf or two the bookcase stays short
## instead of stretching one plank over the whole page.
const PLANK_MAX := 76.0


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	var sb := UiTheme.box(UiTheme.RAISED.lerp(UiTheme.PINK, 0.07), UiTheme.PINK_SEAM, 14, 2, 0)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 10
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 5)
	_cushion.add_theme_stylebox_override("panel", sb)
	_cushion.draw.connect(func():
		# a dashed seam just inside the edge, like a sewn cushion
		var inner := Rect2(Vector2(5, 5), _cushion.size - Vector2(10, 10))
		_cushion.draw_style_box(UiTheme.stitched(Color(UiTheme.PINK, 0.3), Color(0, 0, 0, 0), 10, 0), inner))
	_cushion_row.add_theme_constant_override("separation", 10)
	_cushion_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_cushion.add_child(_cushion_row)
	add_child(_cushion)

	var case_sb := UiTheme.box(UiTheme.PAPER, UiTheme.LILAC_SEAM, 14, 2, 0)
	case_sb.content_margin_left = 14
	case_sb.content_margin_right = 14
	case_sb.content_margin_top = 4
	case_sb.content_margin_bottom = 10
	_case.add_theme_stylebox_override("panel", case_sb)
	_case.size_flags_vertical = SIZE_SHRINK_BEGIN
	_planks.add_theme_constant_override("separation", 0)
	_case.add_child(_planks)
	add_child(_case)
	resized.connect(_fit_planks)
	_cushion.resized.connect(_fit_planks)


## Shares the page's height out between the planks, each at most PLANK_MAX.
func _fit_planks() -> void:
	var n := _planks.get_child_count()
	if n == 0:
		return
	var sb := _case.get_theme_stylebox("panel")
	var avail := size.y - (sb.get_minimum_size().y if sb else 0.0)
	if _cushion.visible:
		avail -= _cushion.size.y + get_theme_constant("separation")
	var h := clampf(floorf(avail / n), ShelfPlank.MIN_H, PLANK_MAX)
	for plank in _planks.get_children():
		if not plank.is_queued_for_deletion():
			plank.custom_minimum_size.y = h


func rebuild() -> void:
	var c := GameState.collection
	var catalog := Catalog.shared()
	UiTheme.clear(_cushion_row)
	var on_top := cushion_pets()
	for i in on_top.size():
		var mini := MiniCard.new(on_top[i])
		mini.pressed.connect(func(p: Pet): shelf_opened.emit(p.rarity, p))
		var holder := Tilted.new(mini, [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0][i % 6])
		holder.size_flags_vertical = SIZE_SHRINK_END
		_cushion_row.add_child(holder)
	_cushion.visible = not on_top.is_empty()
	UiTheme.clear(_planks)
	var i := 0
	for tier in catalog.tiers:
		if c.count_of(tier.id) <= 0:
			continue  # hidden until found: no empty mythic shelf
		var plank := ShelfPlank.new(str(tier.id), i)
		plank.opened.connect(func(r): shelf_opened.emit(r, null))
		_planks.add_child(plank)
		i += 1
	_fit_planks.call_deferred()


## The pets on the cushion (data/herd.json "cushion" at most): your active pet, favourites (newest
## first), then the best cards (rarest finish and rarity first, then a part new to the book).
static func cushion_pets() -> Array[Pet]:
	var c := GameState.collection
	var catalog := Catalog.shared()
	var most := int(catalog.herd.get("cushion", 9))
	var out: Array[Pet] = []
	if c.active():
		out.append(c.active())
	for i in range(c.pets.size() - 1, -1, -1):
		if out.size() >= most:
			return out
		if c.pets[i].fav and c.pets[i].uid != c.active_uid:
			out.append(c.pets[i])
	# the best few, kept as a short list while going through the cards once (there can be lots)
	var room := most - out.size()
	var best: Array = []  # [score, pet], best first
	for i in range(c.pets.size() - 1, -1, -1):  # newest first: on a tie the newer one wins
		var pet := c.pets[i]
		if pet.fav or pet.uid == c.active_uid or (Herd.plain(catalog, pet.finish) and not pet.new_part):
			continue
		var score := catalog.finish_rank(pet.finish) * 10 + catalog.rank(pet.rarity) * 3 + (1 if pet.new_part else 0)
		if best.size() >= room and score <= best[-1][0]:
			continue
		var at := best.size()
		while at > 0 and best[at - 1][0] < score:
			at -= 1
		best.insert(at, [score, pet])
		if best.size() > room:
			best.pop_back()
	for b in best:
		out.append(b[1])
	return out


## The cushion's first pet (the tutorial can point at it).
func first_mini() -> Control:
	for holder in _cushion_row.get_children():
		return holder
	return null
