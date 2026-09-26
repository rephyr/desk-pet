class_name PetCard
extends PanelContainer
## A trading-card style tile for one pet: frame in its rarity colour, glow for the rare ones.

signal pressed(pet: Pet)

const WIDTH := 104

var pet: Pet
var _style: StyleBoxFlat


func _init(p_pet: Pet, pixel := 3, animated := false) -> void:
	pet = p_pet
	var catalog := Catalog.shared()
	var color := catalog.tier_color(pet.rarity)
	var rank := catalog.rank(pet.rarity)
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	tooltip_text = pet.display_name(catalog)

	_style = UiTheme.box(UiTheme.BG_RAISED, color.darkened(0.25 if rank < 2 else 0.0), 10, 2, 6)
	_style.shadow_color = Color(color, 0.45)
	_style.shadow_size = rank * 3  # rarer cards glow more
	add_theme_stylebox_override("panel", _style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)

	var portrait := PetPortrait.new(pixel, animated)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet)
	col.add_child(portrait)

	var name_label := UiTheme.label(pet.display_name(catalog), UiTheme.TEXT, UiTheme.SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(WIDTH - 12, 0)
	col.add_child(name_label)

	var tag := UiTheme.tier_label(pet.rarity, UiTheme.SMALL - 1)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)


func set_selected(selected: bool) -> void:
	_style.bg_color = UiTheme.BG_RAISED.lightened(0.12) if selected else UiTheme.BG_RAISED
	_style.set_border_width_all(3 if selected else 2)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(pet)
		accept_event()
