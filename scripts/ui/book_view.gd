class_name BookView
extends ScrollContainer
## The collection book: every part and every body+finish combo, with how many you've pulled.
## Undiscovered entries show as dark silhouettes.

# the pet every part is shown on, with just that one part swapped in
const SHOWCASE := { "body": "cat", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
const SLOT_TITLES := { "body": "bodies", "palette": "palettes", "pattern": "patterns", "eyes": "eyes", "accessory": "accessories" }

var _pages := VBoxContainer.new()
var _dirty := true


func _init() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_pages.size_flags_horizontal = SIZE_EXPAND_FILL
	_pages.add_theme_constant_override("separation", 14)
	add_child(_pages)
	GameState.collection.pets_added.connect(func(_p): _mark_dirty())
	visibility_changed.connect(_rebuild_if_needed)


func _mark_dirty() -> void:
	_dirty = true
	_rebuild_if_needed()


func _rebuild_if_needed() -> void:
	if not _dirty or not is_visible_in_tree():
		return
	_dirty = false
	for child in _pages.get_children():
		child.queue_free()
	var catalog := Catalog.shared()
	var collection := GameState.collection
	for slot in Catalog.SLOTS:
		var tiles: Array[Control] = []
		var found := 0
		for part in catalog.slots[slot]:
			var seen := collection.times_seen(Collection.part_key(slot, part.id))
			found += 1 if seen > 0 else 0
			var parts := SHOWCASE.duplicate()
			parts[slot] = part.id
			tiles.append(_tile(parts, "normal", part.name, part.rarity, seen, 3))
		_add_page("%s  %d/%d" % [SLOT_TITLES[slot], found, tiles.size()], tiles)

	# finishes: one row per body
	for body in catalog.slots.body:
		var tiles: Array[Control] = []
		var found := 0
		for f in catalog.finishes:
			var seen := collection.times_seen(Collection.finish_key(body.id, f.id))
			found += 1 if seen > 0 else 0
			var parts := SHOWCASE.duplicate()
			parts.body = body.id
			tiles.append(_tile(parts, f.id, f.name if f.name != "" else "normal", f.rarity, seen, 2))
		_add_page("%s finishes  %d/%d" % [body.name, found, tiles.size()], tiles)


func _add_page(title: String, tiles: Array[Control]) -> void:
	_pages.add_child(UiTheme.label(title, UiTheme.PINK))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for t in tiles:
		flow.add_child(t)
	_pages.add_child(flow)


func _tile(parts: Dictionary, finish: String, title: String, tier_id: String, seen: int, pixel: int) -> PanelContainer:
	var discovered := seen > 0
	var color := Catalog.shared().tier_color(tier_id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(78, 0)
	panel.add_theme_stylebox_override("panel",
		UiTheme.box(UiTheme.BG_RAISED, color if discovered else UiTheme.BG_RAISED.lightened(0.1), 8, 2, 4))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)

	var pet := Pet.new()
	pet.parts = parts
	pet.finish = finish
	var portrait := PetPortrait.new(pixel, false)
	portrait.set_pet(pet, not discovered)
	col.add_child(portrait)
	var name_label := UiTheme.label(title if discovered else "???", color if discovered else UiTheme.MUTED, UiTheme.SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var count := UiTheme.label("×%d" % seen if discovered else " ", UiTheme.MUTED, UiTheme.SMALL - 1)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(count)
	return panel
