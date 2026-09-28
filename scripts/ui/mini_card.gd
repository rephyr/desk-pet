class_name MiniCard
extends PanelContainer
## A small pet sticker for the bookcase (the cushion and an opened shelf): the pet, its name, its
## rarity (or its finish, in gold). A moon for your active pet, "new!" for one that brought a part
## new to the book, a heart for a favourite; holo and better glow. In an opened shelf it wears its
## best knack's badge on the bottom-right corner (see Knacks, KnackBadge). Hold it in a Tilted for
## the tilt.
## Design: design/mockups/screens/pets-shelves.html (look A).

signal pressed(pet: Pet)

const WIDTH := 76

var pet: Pet
var _selected := false
var _best := {}  # the knack on the corner badge ({} for none)


## `knack`: wear the best knack's badge on the corner (an opened shelf).
func _init(p_pet: Pet, width := WIDTH, knack := false) -> void:
	pet = p_pet
	var catalog := Catalog.shared()
	if knack:
		_best = Knacks.best(catalog, pet, GameState.knack_gate)
	var color := catalog.tier_color(pet.rarity)
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	custom_minimum_size = Vector2(width, 0)
	tooltip_text = pet.display_name(catalog)
	var sb := UiTheme.box(UiTheme.RAISED, color, 14, 2, 0)
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 7
	sb.content_margin_bottom = 5
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 5
	sb.shadow_offset = Vector2(0, 3)
	if not Herd.plain(catalog, pet.finish):
		sb.shadow_color = Color(color, 0.45)  # holo and better glow in their rarity's colour
		sb.shadow_size = 9
		sb.shadow_offset = Vector2.ZERO
	add_theme_stylebox_override("panel", sb)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet)
	col.add_child(portrait)
	var name_label := UiTheme.label(pet.display_name(catalog), UiTheme.TEXT, UiTheme.SMALL - 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(width - 8, 0)
	col.add_child(name_label)
	var f := catalog.finish(pet.finish)
	var line := UiTheme.label(str(f.name) if f.id != "normal" else catalog.tier_at(catalog.rank(pet.rarity)).name,
		UiTheme.GOLD if f.id != "normal" else color, UiTheme.SMALL - 1)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(line)

	resized.connect(func(): pivot_offset = size / 2.0)
	mouse_entered.connect(func(): _lift(true))
	mouse_exited.connect(func(): _lift(false))


func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()


func _lift(up: bool) -> void:
	var holder := get_parent() as Tilted
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "rotation_degrees", 0.0 if up else (holder.degrees if holder else 0.0), 0.15)
	t.tween_property(self, "scale", Vector2(1.05, 1.05) if up else Vector2.ONE, 0.15)


func _draw() -> void:
	if _selected:
		draw_style_box(UiTheme.box(Color(0, 0, 0, 0), UiTheme.PINK, 17, 2, 0), Rect2(Vector2(-5, -5), size + Vector2(10, 10)))
	var c := GameState.collection
	if pet.uid == c.active_uid:
		# your active pet: a little moon in a dark bubble on the top left corner
		var at := Vector2(1, 1)
		draw_circle(at, 9.0, UiTheme.DEEP)
		draw_arc(at, 9.0, 0.0, TAU, 24, UiTheme.LINE, 2.0, true)
		draw_circle(at, 5.0, UiTheme.GOLD)
		draw_circle(at + Vector2(2.4, -1.6), 4.2, UiTheme.DEEP)
	elif pet.new_part:
		var font := UiTheme.BODY_FONT
		var w := font.get_string_size("new!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 10.0
		draw_set_transform(Vector2(w / 2.0 - 8.0, 0.0), deg_to_rad(-8.0))
		draw_style_box(UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 8, 0, 0), Rect2(-w / 2.0, -8.0, w, 15.0))
		draw_string(font, Vector2(-w / 2.0 + 5.0, 3.5), "new!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, UiTheme.DEEP)
		draw_set_transform(Vector2.ZERO)
	if pet.fav:
		draw_texture_rect(UiTheme.icon("heart", 16), Rect2(Vector2(size.x - 11.0, -7.0), Vector2(16, 16)), false)
	if not _best.is_empty():
		# 20 px, poking out over the bottom-right corner (moon / new! and the heart have the top)
		var at := Vector2(size.x - 3.0, size.y - 3.0)
		draw_circle(at + Vector2(0, 1), 11.0, UiTheme.SHADOW)
		KnackBadge.draw_badge(self, _best, at, 20.0, 10.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit(pet)
