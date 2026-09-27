class_name PetCard
extends PanelContainer
## One pet as a sticker: outlined in its rarity colour, with a soft glow for the very rare ones.
## It lifts and tilts a little under the mouse; the chosen one gets a pink ring.

signal pressed(pet: Pet)

const WIDTH := 92

var pet: Pet
var _selected := false


func _init(p_pet: Pet, pixel := 3, animated := false) -> void:
	pet = p_pet
	var catalog := Catalog.shared()
	var color := catalog.tier_color(pet.rarity)
	var rank := catalog.rank(pet.rarity)
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	size_flags_horizontal = SIZE_EXPAND_FILL
	tooltip_text = pet.display_name(catalog)

	var style := UiTheme.sticker(color, 10, UiTheme.RAISED, 6)
	if rank >= 4:
		style.shadow_color = Color(color, 0.4)  # legendary and up glow
		style.shadow_size = 10
		style.shadow_offset = Vector2.ZERO
	add_theme_stylebox_override("panel", style)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)

	var portrait := PetPortrait.new(pixel, animated)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet)
	col.add_child(portrait)

	var name_label := UiTheme.label(pet.display_name(catalog), UiTheme.TEXT, UiTheme.SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(WIDTH - 14, 0)
	col.add_child(name_label)

	var tag := UiTheme.tier_label(pet.rarity, UiTheme.SMALL)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tag)

	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(func(): _lift(true))
	mouse_exited.connect(func(): _lift(false))


func set_selected(selected: bool) -> void:
	_selected = selected
	queue_redraw()


func _lift(up: bool) -> void:
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation_degrees", -1.0 if up else 0.0, 0.15)
	t.tween_property(self, "scale", Vector2(1.04, 1.04) if up else Vector2.ONE, 0.15)


func _draw() -> void:
	if _selected:
		draw_style_box(UiTheme.box(Color(0, 0, 0, 0), UiTheme.PINK, 14, 2, 0), Rect2(Vector2(-5, -5), size + Vector2(10, 10)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(pet)
