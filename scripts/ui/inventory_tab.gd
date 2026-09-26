class_name InventoryTab
extends VBoxContainer
## What you're carrying: unopened boxes found on adventures, loose parts (for grafting later)
## and anything else pets bring back. Each part is shown on a plain pet so you can see it, and
## can be sewn onto your active pet (Grafting): a before/after, your pet's feelings about it, the result.

signal open_box_requested(box_id: String)

const PART_WIDTH := 96

var _boxes := HFlowContainer.new()
var _parts := HFlowContainer.new()
var _dirty := true
var _shelf := VBoxContainer.new()  # the boxes and parts
var _sewing := VBoxContainer.new()  # the sewing view, instead of the shelf while it's open
var _sew_title := UiTheme.label("", UiTheme.PINK)
var _before := PetPortrait.new(6, true)
var _after := PetPortrait.new(6, true)
var _sew_say := UiTheme.label("", UiTheme.LILAC)
var _sew_button: Button
var _back_button: Button
var _sew_slot := ""
var _sew_part := ""
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()
	_shelf.add_theme_constant_override("separation", 10)
	_shelf.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_shelf)
	_build_sewing()
	add_child(_sewing)
	_shelf.add_child(UiTheme.label("boxes", UiTheme.PINK))
	_boxes.add_theme_constant_override("h_separation", 8)
	_boxes.add_theme_constant_override("v_separation", 8)
	_shelf.add_child(_boxes)
	_shelf.add_child(UiTheme.label("parts", UiTheme.PINK))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parts.size_flags_horizontal = SIZE_EXPAND_FILL
	_parts.add_theme_constant_override("h_separation", 8)
	_parts.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_parts)
	_shelf.add_child(scroll)
	if OS.is_debug_build():
		var give := UiTheme.button("dev: give parts (one of each rarity)", func(): GameState.debug_give_parts())
		give.size_flags_horizontal = SIZE_SHRINK_BEGIN
		_shelf.add_child(give)
	GameState.changed.connect(func(): _dirty = true)
	visibility_changed.connect(_rebuild_if_dirty)


func _rebuild_if_dirty() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _process(_delta: float) -> void:
	_rebuild_if_dirty()


func _rebuild() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	UiTheme.clear(_boxes)
	for box in catalog.boxes:
		var owned := GameState.in_bag(box.id)
		if owned <= 0:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UiTheme.label("%s ×%d" % [box.name, owned], UiTheme.TEXT, UiTheme.SMALL))
		row.add_child(UiTheme.button("open", func(): open_box_requested.emit(box.id)))
		_boxes.add_child(row)
	if _boxes.get_child_count() == 0:
		_boxes.add_child(UiTheme.label("no boxes yet. pets find some on adventures ♡", UiTheme.MUTED, UiTheme.SMALL))

	UiTheme.clear(_parts)
	var keys: Array = GameState.parts.keys()
	keys.sort_custom(func(a, b): return _rank(a) > _rank(b) if _rank(a) != _rank(b) else a < b)
	for key in keys:
		_parts.add_child(_part_tile(key, int(GameState.parts[key])))
	if keys.is_empty():
		_parts.add_child(UiTheme.label("no parts yet. pets sometimes find them on adventures ♡", UiTheme.MUTED, UiTheme.SMALL))
	# anything else adventures bring back that nothing uses yet
	for key: String in GameState.items:
		_boxes.add_child(UiTheme.label("%s ×%d" % [key.replace(":", " ").strip_edges(), GameState.items[key]], UiTheme.TEXT, UiTheme.SMALL))


func _part_tile(key: String, count: int) -> PanelContainer:
	var catalog := Catalog.shared()
	var bits := key.split(":")
	var part := catalog.part(bits[0], bits[1])
	var color := catalog.tier_color(part.rarity)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, color.darkened(0.3), 10, 2, 6))
	panel.custom_minimum_size = Vector2(PART_WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var portrait := PetPortrait.new(2, false)
	portrait.set_pet(_preview(bits[0], bits[1]))
	col.add_child(portrait)
	for line in [["%s ×%d" % [part.get("name", bits[1]), count], UiTheme.TEXT], ["%s · %s" % [bits[0], part.rarity], color]]:
		var l := UiTheme.label(line[0], line[1], UiTheme.SMALL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	if Grafting.can_sew(GameState.collection.active(), bits[0], bits[1], GameState.parts):
		var sew := UiTheme.button("sew on", _open_sewing.bind(bits[0], bits[1]))
		sew.add_theme_font_size_override("font_size", UiTheme.SMALL)
		col.add_child(sew)
	return panel


# ---- sewing ---------------------------------------------------------------------

func _build_sewing() -> void:
	_sewing.visible = false
	_sewing.add_theme_constant_override("separation", 12)
	_sewing.alignment = BoxContainer.ALIGNMENT_CENTER
	_sewing.size_flags_vertical = SIZE_EXPAND_FILL
	_sew_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sewing.add_child(_sew_title)
	var pets := HBoxContainer.new()
	pets.alignment = BoxContainer.ALIGNMENT_CENTER
	pets.add_theme_constant_override("separation", 30)
	pets.add_child(_before)
	var arrow := UiTheme.label("→", UiTheme.MUTED, 28)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pets.add_child(arrow)
	pets.add_child(_after)
	_sewing.add_child(pets)
	_sew_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sew_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sewing.add_child(_sew_say)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	_sew_button = UiTheme.button("sew it on ♡", _sew)
	_back_button = UiTheme.button("not now", _close_sewing)
	buttons.add_child(_sew_button)
	buttons.add_child(_back_button)
	_sewing.add_child(buttons)


func _open_sewing(slot: String, part_id: String) -> void:
	var pet := GameState.collection.active()
	if pet == null:
		return
	var catalog := Catalog.shared()
	_sew_slot = slot
	_sew_part = part_id
	var name: String = catalog.part(slot, part_id).get("name", part_id)
	_sew_title.text = "sew the %s %s onto %s?" % [name, slot, pet.display_name(catalog)]
	_before.set_pet(pet)
	_after.set_pet(Grafting.preview(pet, slot, part_id))
	_after.visible = true
	var risk := PetVoice.graft_line(pet, "risk", Grafting.fail_chance(slot, part_id, catalog), _rng, catalog)
	_sew_say.text = "%s: %s" % [pet.display_name(catalog), risk]
	_sew_button.visible = true
	_back_button.text = "not now"
	_shelf.visible = false
	_sewing.visible = true


func _sew() -> void:
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	var result := GameState.sew_part(_sew_slot, _sew_part)
	if result.is_empty() or pet == null:
		_close_sewing()
		return
	var line := PetVoice.graft_line(pet, "success" if result.ok else "fail", 0.0, _rng, catalog)
	_sew_title.text = "stitched!" if result.ok else "the stitch didn't hold…"
	_before.set_pet(pet)
	_before.view.squash = 0.6
	_after.visible = false
	_sew_say.text = "%s: %s" % [pet.display_name(catalog), line]
	_sew_button.visible = false
	_back_button.text = "okay!"


func _close_sewing() -> void:
	_sewing.visible = false
	_shelf.visible = true
	_dirty = true
	_rebuild_if_dirty()


## A plain pet wearing just this part.
static func _preview(slot: String, id: String) -> Pet:
	var pet := Pet.new()
	for s in Catalog.SLOTS:
		pet.parts[s] = Catalog.shared().default_part(s)
	pet.parts[slot] = id
	return pet


static func _rank(key: String) -> int:
	var bits := key.split(":")
	return Catalog.shared().rank(Catalog.shared().part(bits[0], bits[1]).rarity)
