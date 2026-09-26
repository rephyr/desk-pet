class_name CollectionTab
extends VBoxContainer
## Your pets (sortable, paged grid + details) and the collection book.

const PAGE_SIZE := 40
const SORTS := ["newest", "rarity", "finish"]

var _pets_view := HBoxContainer.new()
var _book := BookView.new()
var _grid := HFlowContainer.new()
var _scroll := ScrollContainer.new()
var _details := PetDetails.new()
var _count := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _sort: Button
var _sort_index := 0
var _pets_button: Button
var _book_button: Button
var _page := 0
var _selected_uid := ""
var _dirty := true


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	add_child(bar)
	var group := ButtonGroup.new()
	_pets_button = _mode_button("pets", group, true)
	_book_button = _mode_button("book", group, false)
	bar.add_child(_pets_button)
	bar.add_child(_book_button)
	bar.add_child(UiTheme.spacer())
	bar.add_child(_count)
	# a cycling button, not an OptionButton: its dropdown would be a separate OS popup
	# window (embed_subwindows is off), which doesn't open properly on Hyprland
	_sort = UiTheme.button("sort: " + SORTS[0], _next_sort)
	bar.add_child(_sort)
	bar.add_child(UiTheme.small_button("‹", func(): _turn(-1)))
	bar.add_child(_page_label)
	bar.add_child(UiTheme.small_button("›", func(): _turn(1)))

	_pets_view.size_flags_vertical = SIZE_EXPAND_FILL
	_pets_view.add_theme_constant_override("separation", 12)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_scroll.add_child(_grid)
	_pets_view.add_child(_scroll)
	_pets_view.add_child(_details)
	add_child(_pets_view)
	add_child(_book)
	_book.visible = false

	GameState.collection.pets_added.connect(func(_p):
		_dirty = true
		_rebuild_if_visible())
	GameState.collection.pets_removed.connect(func(uids):
		if _selected_uid in uids:
			_selected_uid = ""
		_dirty = true
		_rebuild_if_visible())
	visibility_changed.connect(_rebuild_if_visible)


func _mode_button(text: String, group: ButtonGroup, pressed: bool) -> Button:
	var b := UiTheme.button(text)
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = pressed
	b.toggled.connect(func(on):
		if on:
			_show_book(text == "book"))
	return b


func show_book(book: bool) -> void:
	(_book_button if book else _pets_button).button_pressed = true  # also calls _show_book


func _show_book(book: bool) -> void:
	_book.visible = book
	_pets_view.visible = not book
	for c in [_sort, _page_label]:
		c.visible = not book


func _next_sort() -> void:
	_sort_index = (_sort_index + 1) % SORTS.size()
	_sort.text = "sort: " + SORTS[_sort_index]
	_page = 0
	_rebuild()


func _turn(step: int) -> void:
	var pages := _page_count()
	_page = clampi(_page + step, 0, pages - 1)
	_rebuild()


func _page_count() -> int:
	return maxi(1, ceili(GameState.collection.pets.size() / float(PAGE_SIZE)))


func _rebuild_if_visible() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	UiTheme.clear(_grid)
	var pets := _sorted(GameState.collection.pets)
	_count.text = "%d pets" % pets.size()
	_page = clampi(_page, 0, _page_count() - 1)
	_page_label.text = "%d/%d" % [_page + 1, _page_count()]
	for pet in pets.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var card := PetCard.new(pet, 3, false)
		card.pressed.connect(_select)
		card.set_selected(pet.uid == _selected_uid)
		_grid.add_child(card)
	if _selected_uid == "" and not pets.is_empty():
		_select(GameState.collection.active())
	_scroll.scroll_vertical = 0  # a new page starts at the top


func _select(pet: Pet) -> void:
	if pet == null:
		return
	_selected_uid = pet.uid
	for card in _grid.get_children():
		if card is PetCard:
			card.set_selected(card.pet.uid == pet.uid)
	_details.show_pet(pet)


func _sorted(pets: Array[Pet]) -> Array[Pet]:
	var catalog := Catalog.shared()
	var out := pets.duplicate()
	match SORTS[_sort_index]:
		"newest":
			out.reverse()
		"rarity":
			out.sort_custom(func(a: Pet, b: Pet):
				var ra := catalog.rank(a.rarity)
				var rb := catalog.rank(b.rarity)
				return ra > rb if ra != rb else catalog.finish_rank(a.finish) > catalog.finish_rank(b.finish))
		"finish":
			out.sort_custom(func(a: Pet, b: Pet):
				var fa := catalog.finish_rank(a.finish)
				var fb := catalog.finish_rank(b.finish)
				return fa > fb if fa != fb else catalog.rank(a.rarity) > catalog.rank(b.rarity))
	return out
