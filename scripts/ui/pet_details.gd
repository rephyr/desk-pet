class_name PetDetails
extends PanelContainer
## Everything about one pet, as a big sticker with a stitched edge: its portrait, name, rarity and
## finish, parts, traits and stats, and the button to make it your active pet.

var _pet: Pet
var _portrait := PetPortrait.new(6, true)
var _name := UiTheme.title("", 20)
var _tags := HBoxContainer.new()
var _info := GridContainer.new()
var _active_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(236, 0)
	add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 16))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	col.add_child(_portrait)
	# everything about the pet scrolls, so a pet with lots of traits never pushes the button (or
	# the window) past the bottom edge
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var about := VBoxContainer.new()
	about.size_flags_horizontal = SIZE_EXPAND_FILL
	about.add_theme_constant_override("separation", 4)
	scroll.add_child(about)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.add_child(_name)
	_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	_tags.add_theme_constant_override("separation", 6)
	about.add_child(_tags)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	about.add_child(gap)
	_info.columns = 2
	_info.add_theme_constant_override("h_separation", 12)
	_info.add_theme_constant_override("v_separation", 2)
	about.add_child(_info)
	_active_button = UiTheme.button("make active", func():
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
	var tier_color := catalog.tier_color(pet.rarity)
	_tags.add_child(UiTheme.tag(catalog.tier_at(catalog.rank(pet.rarity)).name, tier_color, tier_color))
	var f := catalog.finish(pet.finish)
	if f.id != "normal":
		_tags.add_child(UiTheme.tag(f.name, UiTheme.GOLD))

	UiTheme.clear(_info)
	for slot in Catalog.SLOTS:
		var p := catalog.part(slot, pet.parts[slot])
		_row(slot, p.get("name", pet.parts[slot]), UiTheme.TEXT)
	if pet.traits.is_empty():
		_row("trait", "none", UiTheme.MUTED)
	for id in pet.traits:
		var t := catalog.trait_info(id)
		_row("trait", t.get("name", id), UiTheme.TEXT)
		_row("", t.get("desc", ""), UiTheme.MUTED)
	for stat in Pet.STATS:
		_row(stat, str(pet.stats.get(stat, 0)), UiTheme.TEXT)
	_refresh_active()


func _refresh_active() -> void:
	if _pet == null:
		return
	var is_active := GameState.collection.active_uid == _pet.uid
	var away := GameState.away().has(_pet.uid)
	_active_button.disabled = is_active or away
	_active_button.text = "your active pet" if is_active else ("away on an adventure…" if away else "make active")
	_active_button.icon = UiTheme.icon("heart", 14) if is_active or not away else null
	_active_button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_active_button.add_theme_constant_override("icon_max_width", 14)
	_active_button.add_theme_color_override("icon_normal_color", Color.WHITE)
	_active_button.add_theme_color_override("icon_disabled_color", Color.WHITE)


func _row(key: String, value: String, color: Color) -> void:
	var k := UiTheme.label(key, UiTheme.MUTED, UiTheme.SMALL)
	k.size_flags_vertical = SIZE_SHRINK_BEGIN
	_info.add_child(k)
	var v := UiTheme.label(value, color, UiTheme.SMALL)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.custom_minimum_size = Vector2(130, 0)
	_info.add_child(v)


func _draw() -> void:
	# a stitched line just inside the edge, like the sticker was sewn on
	var inner := Rect2(Vector2(5, 5), size - Vector2(10, 10))
	var sb := UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 8, 0)
	draw_style_box(sb, inner)
