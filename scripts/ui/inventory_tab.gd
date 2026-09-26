class_name InventoryTab
extends VBoxContainer
## What you're carrying: unopened boxes found on adventures, loose parts (for grafting later)
## and anything else pets bring back. Each part is shown on a plain pet so you can see it.

signal open_box_requested(box_id: String)

const PART_WIDTH := 96

var _boxes := HFlowContainer.new()
var _parts := HFlowContainer.new()
var _dirty := true


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	add_child(UiTheme.label("boxes", UiTheme.PINK))
	_boxes.add_theme_constant_override("h_separation", 8)
	_boxes.add_theme_constant_override("v_separation", 8)
	add_child(_boxes)
	add_child(UiTheme.label("parts", UiTheme.PINK))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parts.size_flags_horizontal = SIZE_EXPAND_FILL
	_parts.add_theme_constant_override("h_separation", 8)
	_parts.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_parts)
	add_child(scroll)
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
	return panel


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
