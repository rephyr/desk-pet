class_name HerdPicker
extends VBoxContainer
## Picking pets by the shelf (C2 look A): a row per rarity that has pets that may go (GameState.
## spare_pick: resting ones first, then off their errands; never favourites or past the keep line):
## a face, the rarity, how many and how many of them work. Tap one to pick it, then 1 / 10 / 100 /
## all. The edge and the school both use it; what "all" means (as many as still fit) is up to them.

signal take(rarity: String, n: int)  # n is -1 for "all"

var picked := ""
var cap := -1  # how many more can go (-1: no limit); 0 greys the buttons out
var _rows := VBoxContainer.new()
var _takes := GridContainer.new()
var _key := ""  # the rarities the rows are for (the counts change in place)
var _counts := {}  # rarity -> its row's count label
var _working := {}  # rarity -> its row's "n working" label


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_rows.add_theme_constant_override("separation", 4)
	add_child(_rows)
	_takes.columns = 4
	_takes.add_theme_constant_override("h_separation", 6)
	for n in [1, 10, 100, -1]:
		var b := UiTheme.button("all" if n < 0 else str(n), func(): take.emit(picked, n))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		if n < 0:
			b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 5))
		_takes.add_child(b)
	add_child(_takes)


## Shows the shelves as they are now: the rows are built again only when a rarity turns up or runs
## out; otherwise just their counts change (box workers change them nearly every frame).
func refresh() -> void:
	var shelves := GameState.spare_shelves()
	if not shelves.has(picked):
		picked = str(shelves.keys()[0]) if not shelves.is_empty() else ""
	var key := str(shelves.keys())
	for b: Button in _takes.get_children():
		b.disabled = picked == "" or cap == 0
	if key != _key:
		_key = key
		UiTheme.clear(_rows)
		_counts.clear()
		_working.clear()
		for rarity in shelves:
			_rows.add_child(_row(str(rarity), shelves[rarity]))
	else:
		for rarity in shelves:
			_show_counts(str(rarity), shelves[rarity])
	_restyle()


## The picked row stitched in pink, the others outlined in their rarity's colour.
func _restyle() -> void:
	for row: PanelContainer in _rows.get_children():
		var rarity := str(row.get_meta("rarity", ""))
		var style := rarity + ("*" if rarity == picked else "")
		if row.get_meta("style", "") == style:
			continue
		row.set_meta("style", style)
		var sb: StyleBox
		if rarity == picked:
			sb = UiTheme.stitched(UiTheme.PINK, UiTheme.DEEP.lerp(UiTheme.PINK_PRESSED, 0.45), 8, 3)
		else:
			sb = UiTheme.box(UiTheme.DEEP, GameState.catalog.tier_color(rarity).lerp(UiTheme.LINE, 0.65), 8, 2, 3)
		sb.content_margin_left = 6
		sb.content_margin_right = 8
		row.add_theme_stylebox_override("panel", sb)


## The screen position of a shelf's row (for pets flying off it).
func row_point(rarity: String) -> Vector2:
	for r in _rows.get_children():
		if r.get_meta("rarity", "") == rarity:
			return (r as Control).get_global_rect().get_center()
	return get_global_rect().get_center()


## A face from a shelf: the pet that would go first (null if there's none).
static func face_of(rarity: String, salt := 0) -> Pet:
	return GameState.spare_face(rarity, salt)


## A row's numbers: how many may go, and how many of those work ("" when none do).
func _show_counts(rarity: String, shelf: Dictionary) -> void:
	var text := UiTheme.num(int(shelf.n))
	var label: Label = _counts[rarity]
	if label.text != text:
		label.text = text
	var working := int(shelf.working)
	var w: Label = _working[rarity]
	w.text = "%s working" % UiTheme.num(working) if working > 0 else ""
	w.visible = working > 0


func _row(rarity: String, shelf: Dictionary) -> Control:
	var catalog := GameState.catalog
	var color := catalog.tier_color(rarity)
	var row := PanelContainer.new()
	row.set_meta("rarity", rarity)
	row.mouse_filter = MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(line)
	var face := PetPortrait.new(1, false)
	face.set_pet(face_of(rarity))
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(face)
	var name_label := UiTheme.label(str(catalog.tier_at(catalog.rank(rarity)).name), color, UiTheme.SMALL)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.mouse_filter = MOUSE_FILTER_IGNORE
	line.add_child(name_label)
	var working := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL - 1)
	working.mouse_filter = MOUSE_FILTER_IGNORE
	working.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(working)
	_working[rarity] = working
	var count := UiTheme.title("", 14, UiTheme.TEXT)
	count.mouse_filter = MOUSE_FILTER_IGNORE
	line.add_child(count)
	_counts[rarity] = count
	_show_counts(rarity, shelf)
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			picked = rarity
			refresh())
	return row
