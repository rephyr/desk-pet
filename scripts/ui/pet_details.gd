class_name PetDetails
extends PanelContainer
## Everything about one pet: big portrait, parts with their rarities, traits, stats,
## and the button to make it your active pet.

var _pet: Pet
var _portrait := PetPortrait.new(6, true)
var _name := UiTheme.label("", UiTheme.TEXT)
var _tags := HBoxContainer.new()
var _info := VBoxContainer.new()
var _active_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(240, 0)
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.LILAC.darkened(0.45), 10, 2, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)
	col.add_child(_portrait)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_name)
	_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	_tags.add_theme_constant_override("separation", 8)
	col.add_child(_tags)
	_info.add_theme_constant_override("separation", 1)
	col.add_child(_info)
	col.add_child(UiTheme.spacer())
	_active_button = UiTheme.button("make active ♡", func():
		if _pet:
			GameState.collection.set_active(_pet.uid))
	col.add_child(_active_button)
	GameState.collection.active_changed.connect(func(_p): _refresh_active())
	show_pet(null)


## The "make active" button (the tutorial points at it).
func active_button() -> Button:
	return _active_button


func show_pet(pet: Pet) -> void:
	_pet = pet
	visible = pet != null
	if pet == null:
		return
	var catalog := Catalog.shared()
	_portrait.set_pet(pet)
	_name.text = pet.display_name(catalog)

	UiTheme.clear(_tags)
	_tags.add_child(UiTheme.tier_label(pet.rarity, UiTheme.FONT_SIZE))
	var f := catalog.finish(pet.finish)
	if f.id != "normal":
		_tags.add_child(UiTheme.label(f.name, catalog.tier_color(f.rarity)))

	UiTheme.clear(_info)
	_section("parts")
	for slot in Catalog.SLOTS:
		var p := catalog.part(slot, pet.parts[slot])
		_row(slot, p.get("name", pet.parts[slot]), catalog.tier_color(p.get("rarity", "common")))
	_section("traits")
	if pet.traits.is_empty():
		_row("", "none", UiTheme.MUTED)
	for id in pet.traits:
		var t := catalog.trait_info(id)
		_row(t.get("name", id), t.get("desc", ""), UiTheme.LILAC)
	_section("stats")
	for stat in Pet.STATS:
		_row(stat, str(pet.stats.get(stat, 0)), UiTheme.TEXT)
	_refresh_active()


func _refresh_active() -> void:
	if _pet == null:
		return
	var is_active := GameState.collection.active_uid == _pet.uid
	var away := GameState.away().has(_pet.uid)
	_active_button.disabled = is_active or away
	_active_button.text = "★ your active pet" if is_active else ("away…" if away else "make active ♡")


func _section(title: String) -> void:
	var l := UiTheme.label(title, UiTheme.PINK, UiTheme.SMALL)
	_info.add_child(l)


func _row(key: String, value: String, color: Color) -> void:
	var row := HBoxContainer.new()
	var k := UiTheme.label(key, UiTheme.MUTED, UiTheme.SMALL)
	k.custom_minimum_size = Vector2(72, 0)
	row.add_child(k)
	var v := UiTheme.label(value, color, UiTheme.SMALL)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(v)
	_info.add_child(row)
