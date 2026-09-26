class_name RevealResult
extends VBoxContainer
## What you got, shown under the banner once a single box is fully revealed:
## name, rarity and finish, NEW parts, and what to do next.

signal open_again
signal done

var _name := UiTheme.label("", UiTheme.TEXT, 18)
var _tags := HBoxContainer.new()
var _news := UiTheme.label("", UiTheme.CYAN, UiTheme.SMALL)
var _again: Button
var _active: Button
var _pet: Pet
var _box_id := ""


func _init() -> void:
	alignment = ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_name)
	_tags.alignment = BoxContainer.ALIGNMENT_CENTER
	_tags.add_theme_constant_override("separation", 10)
	add_child(_tags)
	_news.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_news)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	_again = UiTheme.button("open another", func(): open_again.emit())
	_active = UiTheme.button("make active ♡", func():
		GameState.collection.set_active(_pet.uid)
		_refresh_buttons())
	buttons.add_child(_again)
	buttons.add_child(_active)
	buttons.add_child(UiTheme.button("done", func(): done.emit()))
	add_child(buttons)
	GameState.changed.connect(_refresh_buttons)


func show_pet(pet: Pet, box_id: String) -> void:
	_pet = pet
	_box_id = box_id
	var catalog := Catalog.shared()
	_name.text = pet.display_name(catalog)
	UiTheme.clear(_tags)
	_tags.add_child(UiTheme.tier_label(pet.rarity, UiTheme.FONT_SIZE))
	var f := catalog.finish(pet.finish)
	if f.id != "normal":
		_tags.add_child(UiTheme.label(f.name, catalog.tier_color(f.rarity)))
	var news := new_parts(pet)
	_news.text = "NEW  " + " · ".join(news) if not news.is_empty() else ""
	_refresh_buttons()


## Names of this pet's parts (and body+finish) that had never been pulled before it.
static func new_parts(pet: Pet) -> Array[String]:
	var catalog := Catalog.shared()
	var collection := GameState.collection
	var out: Array[String] = []
	for slot in Catalog.SLOTS:
		if collection.times_seen(Collection.part_key(slot, pet.parts[slot])) == 1:
			out.append(catalog.part(slot, pet.parts[slot]).name)
	if pet.finish != "normal" and collection.times_seen(Collection.finish_key(pet.parts.body, pet.finish)) == 1:
		out.append("%s %s" % [catalog.finish(pet.finish).name, catalog.part("body", pet.parts.body).name])
	return out


func _refresh_buttons() -> void:
	if _pet == null:
		return
	_again.disabled = not GameState.can_open(_box_id)
	var is_active := GameState.collection.active_uid == _pet.uid
	_active.disabled = is_active
	_active.text = "★ active" if is_active else "make active ♡"
