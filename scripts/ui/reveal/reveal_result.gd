class_name RevealResult
extends PanelContainer
## The result card once a single box is fully revealed: your new pet framed in its rarity colour,
## its name, rarity and finish, gold "new" tags for parts you'd never had, and what to do next.

signal open_again
signal done

var _frame := PanelContainer.new()
var _portrait := PetPortrait.new(6, true)
var _name := UiTheme.title("", 24)
var _tags := HBoxContainer.new()
var _news := HFlowContainer.new()
var _again: Button
var _again_price := UiTheme.label("", UiTheme.CYAN, UiTheme.SMALL)
var _active: Button
var _pet: Pet
var _box_id := ""


func _init() -> void:
	custom_minimum_size = Vector2(300, 0)
	add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 14, UiTheme.RAISED, 16))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	_frame.size_flags_horizontal = SIZE_SHRINK_CENTER
	_frame.add_child(_portrait)
	col.add_child(_frame)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name)
	_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	_tags.add_theme_constant_override("separation", 6)
	col.add_child(_tags)
	_news.alignment = FlowContainer.ALIGNMENT_CENTER
	_news.add_theme_constant_override("h_separation", 5)
	_news.add_theme_constant_override("v_separation", 5)
	col.add_child(_news)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	col.add_child(gap)
	_active = UiTheme.small_button("make it your active pet", func():
		GameState.collection.set_active(_pet.uid)
		_refresh_buttons())
	_active.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	_active.add_theme_color_override("font_color", UiTheme.MUTED)
	_active.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(_active)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_again = _two_line_button("open another", _again_price, func(): open_again.emit())
	var lovely := UiTheme.button("lovely!", func(): done.emit())
	for b in [_again, lovely]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.add_child(b)
	col.add_child(buttons)
	GameState.changed.connect(_refresh_buttons)


func _two_line_button(text: String, small: Label, on_pressed: Callable) -> Button:
	var b := UiTheme.button("", on_pressed)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.set_anchors_preset(PRESET_FULL_RECT)
	var top := UiTheme.label(text)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	b.add_child(col)
	b.custom_minimum_size = Vector2(0, 42)
	return b


func show_pet(pet: Pet, box_id: String) -> void:
	_pet = pet
	_box_id = box_id
	var catalog := Catalog.shared()
	var color := catalog.tier_color(pet.rarity)
	var frame := UiTheme.box(UiTheme.DEEP, color, 12, 2, 10)
	frame.shadow_color = Color(color, 0.35)
	frame.shadow_size = 12
	_frame.add_theme_stylebox_override("panel", frame)
	_portrait.set_pet(pet)
	_name.text = pet.display_name(catalog)
	UiTheme.clear(_tags)
	_tags.add_child(UiTheme.tag(catalog.tier_at(catalog.rank(pet.rarity)).name, color, color))
	var f := catalog.finish(pet.finish)
	if f.id != "normal":
		_tags.add_child(UiTheme.tag(f.name, UiTheme.GOLD))
	UiTheme.clear(_news)
	for part in new_parts(pet):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		row.add_child(UiTheme.label("new", UiTheme.GOLD, UiTheme.SMALL))
		row.add_child(UiTheme.label(part, UiTheme.TEXT, UiTheme.SMALL))
		var t := PanelContainer.new()
		var sb := UiTheme.box(UiTheme.DEEP, UiTheme.GOLD.lerp(UiTheme.LINE, 0.45), 999, 2, 1)
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		t.add_theme_stylebox_override("panel", sb)
		t.add_child(row)
		_news.add_child(t)
	_refresh_buttons()


## Names of this pet's parts (and body+finish) that had never been pulled before it.
static func new_parts(pet: Pet) -> Array[String]:
	var catalog := Catalog.shared()
	var collection := GameState.collection
	var out: Array[String] = []
	for slot in Catalog.SLOTS:
		if collection.times_seen(Collection.part_key(slot, pet.parts[slot])) == 1:
			out.append("%s %s" % [catalog.part(slot, pet.parts[slot]).name, slot])
	if pet.finish != "normal" and collection.times_seen(Collection.finish_key(pet.parts.body, pet.finish)) == 1:
		out.append("%s %s" % [catalog.finish(pet.finish).name, catalog.part("body", pet.parts.body).name])
	return out


func _refresh_buttons() -> void:
	if _pet == null:
		return
	var left := GameState.in_bag(_box_id)
	_again.disabled = left < 1
	_again.tooltip_text = "buy more at the counter" if left < 1 else ""
	_again_price.text = "%d left on the pile" % left if left > 0 else "the pile is empty"
	_again_price.add_theme_color_override("font_color", UiTheme.MINT if left > 0 else UiTheme.LILAC)
	var is_active := GameState.collection.active_uid == _pet.uid
	_active.visible = not is_active
