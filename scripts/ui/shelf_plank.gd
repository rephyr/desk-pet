class_name ShelfPlank
extends Control
## One rarity's shelf in the bookcase: a tilted tag ("common 48,210"), the newest few standing on
## the plank, a mound of tiny pets that grows with the count, and how many are shiny. Tap it to
## open the shelf.
## Design: design/mockups/screens/pets-shelves.html (look A).

signal opened(rarity: String)

const TILTS := [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0]
const TAG_WIDTH := 118
const PLANK_H := 7.0
const MIN_H := 48.0

var rarity := ""
var _hover := false


func _init(p_rarity: String, index: int) -> void:
	rarity = p_rarity
	var catalog := Catalog.shared()
	var c := GameState.collection
	var color := catalog.tier_color(rarity)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	size_flags_vertical = SIZE_FILL  # Bookcase sets the height
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 4
	row.offset_right = -6
	add_child(row)

	# the tag
	var tag := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.RAISED, color.lerp(UiTheme.LINE, 0.45), 6, 2, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 4
	sb.shadow_offset = Vector2(0, 3)
	tag.add_theme_stylebox_override("panel", sb)
	tag.mouse_filter = MOUSE_FILTER_IGNORE
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", -2)
	words.mouse_filter = MOUSE_FILTER_IGNORE
	words.add_child(UiTheme.label(catalog.tier_at(catalog.rank(rarity)).name, color, UiTheme.SMALL - 1))
	words.add_child(UiTheme.title(ExpandedView._thousands(c.count_of(rarity)), 17, UiTheme.TEXT))
	tag.add_child(words)
	var holder := Tilted.new(tag, TILTS[index % TILTS.size()])
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	holder.size_flags_vertical = SIZE_SHRINK_CENTER
	var tag_col := Control.new()
	tag_col.custom_minimum_size = Vector2(TAG_WIDTH, 0)
	tag_col.mouse_filter = MOUSE_FILTER_IGNORE
	var tag_box := HBoxContainer.new()
	tag_box.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	tag_box.mouse_filter = MOUSE_FILTER_IGNORE
	tag_box.add_child(holder)
	tag_col.add_child(tag_box)
	row.add_child(tag_col)

	# the newest few standing, then the mound, then the shiny count
	var stand := HBoxContainer.new()
	stand.add_theme_constant_override("separation", 4)
	stand.alignment = BoxContainer.ALIGNMENT_BEGIN
	stand.size_flags_horizontal = SIZE_EXPAND_FILL
	stand.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(stand)
	var standing := int(catalog.herd.get("standing", 4))
	var cards := c.cards_of(rarity)
	var faces: Array = []  # newest first: cards, then stand-ins for the counts
	for i in range(cards.size() - 1, -1, -1):
		faces.append(cards[i].uid)
		if faces.size() >= standing + int(catalog.herd.get("mound_max", 60)):
			break
	var counts := {}
	for f in catalog.finishes:
		var k := Herd.key(rarity, f.id)
		if c.herd_count(k) > 0:
			counts[k] = c.herd_count(k)
	var herd_faces := GameState.herd_faces(counts, int(catalog.herd.get("mound_max", 60)), catalog.rank(rarity))
	var standing_faces: Array = (faces + herd_faces).slice(0, standing)
	for i in standing_faces.size():
		var portrait := PetPortrait.new(2, false)
		portrait.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.set_pet(c.get_pet(standing_faces[i]))
		portrait.view.facing = -1 if i % 2 == 1 else 1
		portrait.size_flags_vertical = SIZE_SHRINK_END
		stand.add_child(_on_plank(portrait))
	var rest := c.count_of(rarity) - standing_faces.size()
	if rest > 0:
		var mound_faces: Array = herd_faces + faces.slice(standing)
		if mound_faces.is_empty():
			mound_faces = standing_faces
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(4, 0)
		gap.mouse_filter = MOUSE_FILTER_IGNORE
		stand.add_child(gap)
		var mound := Mound.new(mound_faces, Herd.mound_size(catalog, rest), 300.0, 36.0)
		mound.size_flags_vertical = SIZE_SHRINK_END
		stand.add_child(_on_plank(mound))
	stand.add_child(UiTheme.spacer())
	var shiny := c.shiny_of(rarity)
	if shiny > 0:
		var sh := UiTheme.label("✦ " + ExpandedView._thousands(shiny), UiTheme.GOLD, UiTheme.SMALL)
		sh.size_flags_vertical = SIZE_SHRINK_CENTER
		stand.add_child(sh)
	custom_minimum_size = Vector2(0, MIN_H)
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


## Stands a picture on the plank: its feet just above the plank's board.
func _on_plank(c: Control) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_bottom", int(PLANK_H))
	m.mouse_filter = MOUSE_FILTER_IGNORE
	m.size_flags_vertical = SIZE_SHRINK_END
	m.add_child(c)
	return m


func _draw() -> void:
	var r := Rect2(Vector2(-6, size.y - PLANK_H), Vector2(size.x + 12, PLANK_H))
	draw_style_box(UiTheme.box(UiTheme.LILAC.lerp(UiTheme.PAGE, 0.78), UiTheme.PINK if _hover else UiTheme.LILAC_SEAM, 3, 2, 0), r)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		opened.emit(rarity)
