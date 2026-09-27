class_name PartFoundCard
extends Tilted
## The little card that pops up on the trail when the pet picks up a part: the part, its slot and
## rarity, a line from the pet, and "leave it" / "add to bag". It points left at the pet, which
## holds the part up over its head (TrailView draws that).

signal picked(keep: bool)

const WIDTH := 236.0
const TAIL_Y := 58.0  # where the pointer sits, from the top of the card

var key := ""  # "part:slot:id"
var _panel := PanelContainer.new()
var _color := UiTheme.PINK


func _init(part_key: String, quote: String) -> void:
	super(null, 1.0)
	key = part_key
	mouse_filter = MOUSE_FILTER_STOP
	var catalog := Catalog.shared()
	var bits := part_key.split(":")  # part, slot, id
	var part := catalog.part(bits[1], bits[2])
	_color = catalog.tier_color(part.rarity)
	_panel.add_theme_stylebox_override("panel", UiTheme.sticker(_color, 12, UiTheme.RAISED, 12))
	_panel.custom_minimum_size.x = WIDTH
	_panel.draw.connect(_draw_tail)
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)
	col.add_child(UiTheme.title("new body part found!", 17))

	# the part as a little sticker, then its name, slot and rarity on their own lines
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, _color, 8, 2, 4))
	var portrait := PetPortrait.new(2, false)
	portrait.set_pet(InventoryTab.part_preview(bits[1], bits[2]))
	tile.add_child(portrait)
	row.add_child(tile)
	var about := VBoxContainer.new()
	about.add_theme_constant_override("separation", 0)
	about.size_flags_vertical = SIZE_SHRINK_CENTER
	about.add_child(UiTheme.label(part.get("name", bits[2])))
	about.add_child(UiTheme.label(bits[1], UiTheme.MUTED, UiTheme.SMALL))
	about.add_child(UiTheme.tier_label(part.rarity))
	row.add_child(about)

	if quote != "":
		var said := UiTheme.label("\"%s\"" % quote, UiTheme.LILAC, UiTheme.SMALL + 1)
		said.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		said.custom_minimum_size.x = WIDTH - 24.0
		col.add_child(said)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	col.add_child(buttons)
	var leave := UiTheme.button("leave it", func(): picked.emit(false))
	leave.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(leave)
	var keep := UiTheme.button("add to bag", func(): picked.emit(true))
	keep.icon = UiTheme.icon("inventory", 14)
	keep.size_flags_horizontal = SIZE_EXPAND_FILL
	keep.size_flags_stretch_ratio = 1.4
	keep.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, _color, 8, 2, 6))
	buttons.add_child(keep)

	# a little pop, like it was just slapped down
	scale = Vector2(0.5, 0.5)
	modulate.a = 0.0
	resized.connect(func(): pivot_offset = Vector2(0.0, TAIL_Y))
	var t := create_tween().set_parallel()
	t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.15)


## The pointer on the left edge, toward the part the pet is holding up.
func _draw_tail() -> void:
	var pts := PackedVector2Array([Vector2(1, TAIL_Y - 9), Vector2(-10, TAIL_Y), Vector2(1, TAIL_Y + 9)])
	_panel.draw_colored_polygon(pts, _color)
