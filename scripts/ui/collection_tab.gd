class_name CollectionTab
extends VBoxContainer
## Collectibles: your pets (a sortable, filterable, paged grid of stickers + the chosen pet's
## details), your capsule toys (ToysView) and the collection book. Filters are chips and sorts are buttons, never dropdowns: a dropdown is a
## separate OS popup window (embed_subwindows is off), which doesn't open properly on Hyprland.

const PAGE_SIZE := 24
const SORTS := ["newest", "rarest", "a to z"]
const FILTERS := ["common", "uncommon", "rare", "epic", "legendary", "mythic"]

var _pets_view := HBoxContainer.new()
var _book := BookView.new()
var toys := ToysView.new()
var _grid := GridContainer.new()
var _scroll := ScrollContainer.new()
var _details := PetDetails.new()
var _count := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _pets_bar := HBoxContainer.new()
var _mode: PanelContainer  # the pets | toys | book switch
var _toys_button: Button
var _filter_row := HFlowContainer.new()
var _all_chip: Button
var _chips := {}  # tier id or "sparkly" -> Button
var _sort_index := 0
var _page := 0
var _selected_uid := ""
var _dirty := true
var _knacks_seen := ""  # which knack kinds showed when the grid was last drawn (see _knacks_key)


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_mode = UiTheme.segmented(["pets", "toys", "book"], 0, func(i): _show_mode(i))
	bar.add_child(_mode)
	_pets_bar.add_theme_constant_override("separation", 8)
	_pets_bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(_pets_bar)
	_pets_bar.add_child(UiTheme.segmented(SORTS, 0, func(i):
		_sort_index = i
		_page = 0
		_rebuild()))
	_pets_bar.add_child(UiTheme.spacer())
	_pets_bar.add_child(_count)
	_pets_bar.add_child(UiTheme.small_button("‹", func(): _turn(-1)))
	_pets_bar.add_child(_page_label)
	_pets_bar.add_child(UiTheme.small_button("›", func(): _turn(1)))

	_filter_row.add_theme_constant_override("h_separation", 5)
	_filter_row.add_theme_constant_override("v_separation", 5)
	add_child(_filter_row)
	_all_chip = UiTheme.filter_chip("all", UiTheme.PINK, true)
	_all_chip.pressed.connect(func():
		for id in _chips:
			_chips[id].set_pressed_no_signal(false)
		_all_chip.set_pressed_no_signal(true)
		_page = 0
		_rebuild())
	_filter_row.add_child(_all_chip)
	var catalog := Catalog.shared()
	for tier_id in FILTERS:
		_add_chip(tier_id, catalog.tier_at(catalog.rank(tier_id)).name, catalog.tier_color(tier_id))
	_add_chip("sparkly", "sparkly", UiTheme.GOLD)

	_pets_view.size_flags_vertical = SIZE_EXPAND_FILL
	_pets_view.add_theme_constant_override("separation", 14)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.columns = 5
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_theme_constant_override("margin_top", 12)  # room for the knack badges on the top row's corners
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_child(_grid)
	_scroll.add_child(pad)
	_pets_view.add_child(_scroll)
	_pets_view.add_child(_details)
	add_child(_pets_view)
	add_child(toys)
	toys.visible = false
	# the toys switch is locked ("???") until toys open (through adventures)
	_toys_button = _mode.get_child(0).get_child(1) as Button
	_lock_toys()
	GameState.changed.connect(_lock_toys)
	GameState.new_game.connect(_lock_toys)
	add_child(_book)
	_book.visible = false

	GameState.collection.pets_added.connect(func(_p):
		_dirty = true
		_rebuild_if_visible())
	GameState.collection.pet_changed.connect(func(_p):
		_dirty = true
		_rebuild_if_visible())
	GameState.new_game.connect(func():
		_selected_uid = ""
		_page = 0
		_dirty = true
		_rebuild_if_visible())
	GameState.collection.pets_removed.connect(func(uids):
		if _selected_uid in uids:
			_selected_uid = ""
		_dirty = true
		_rebuild_if_visible())
	# knacks showing up (parts open, a machine fix, the tutorial moving on) redraw the badges
	GameState.knacks_changed.connect(func():
		if _knacks_key() != _knacks_seen:
			_dirty = true
			_rebuild_if_visible())
	visibility_changed.connect(func():
		_rebuild_if_visible()
		if is_visible_in_tree() and _pets_view.visible:
			speak()
		elif is_visible_in_tree() and toys.visible:
			toys.speak())


func _add_chip(id: String, text: String, color: Color) -> void:
	var chip := UiTheme.filter_chip(text, color)
	chip.toggled.connect(func(_on):
		_all_chip.set_pressed_no_signal(not _chips.values().any(func(c: Button): return c.button_pressed))
		_page = 0
		_rebuild())
	_chips[id] = chip
	_filter_row.add_child(chip)


func speak() -> void:
	var pets := GameState.collection.pets.size()
	PetBubble.say_line(self, "pets" if pets > 1 else "pets_alone", { "count": pets })


func show_book(book: bool) -> void:
	show_mode(2 if book else 0)


## 0 pets, 1 toys, 2 the book.
func show_mode(mode: int) -> void:
	(_mode.get_child(0).get_child(mode) as Button).pressed.emit()  # flips the switch too


func _lock_toys() -> void:
	var open := GameState.feature_on("toys")
	_toys_button.text = "toys" if open else "???"
	_toys_button.icon = null if open else UiTheme.icon("lock", 12, UiTheme.LOCKED)
	_toys_button.tooltip_text = "" if open else GameState.catalog.unlock_list.filter(func(e): return e.id == "toys")[0].get("hint", "")


func _show_mode(mode: int) -> void:
	if mode == 1 and not GameState.feature_on("toys"):
		# locked: your pet says what opens it, and you stay on the pets
		PetBubble.say(self, "toys? " + _toys_button.tooltip_text + "!")
		show_mode(0)
		return
	_book.visible = mode == 2
	toys.visible = mode == 1
	_pets_view.visible = mode == 0
	_pets_bar.visible = mode == 0
	_filter_row.visible = mode == 0
	if mode == 2:
		PetBubble.say_line(self, "book")
	elif mode == 1:
		toys.speak()


## For the tutorial: a pet to tap, or once one's picked, the button to make it active.
func tutorial_target() -> Control:
	if _details.visible and not _details.active_button().disabled:
		return _details.active_button()
	for card in _grid.get_children():
		if card is PetCard:
			return card
	return null


func _turn(step: int) -> void:
	_page = clampi(_page + step, 0, _page_count(_filtered().size()) - 1)
	_rebuild()


func _page_count(n: int) -> int:
	return maxi(1, ceili(n / float(PAGE_SIZE)))


func _rebuild_if_visible() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	_knacks_seen = _knacks_key()
	UiTheme.clear(_grid)
	var pets := _filtered()
	_count.text = "%d pets" % pets.size()
	_page = clampi(_page, 0, _page_count(pets.size()) - 1)
	_page_label.text = "page %d of %d" % [_page + 1, _page_count(pets.size())]
	for pet in pets.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var card := PetCard.new(pet, 3, false, true)
		card.pressed.connect(_select)
		card.set_selected(pet.uid == _selected_uid)
		_grid.add_child(card)
	if _selected_uid == "" and not GameState.collection.pets.is_empty():
		_select(GameState.collection.active())
	elif GameState.collection.get_pet(_selected_uid) != null:
		_details.show_pet(GameState.collection.get_pet(_selected_uid))  # its knacks may have changed
	_scroll.scroll_vertical = 0  # a new page starts at the top


## Which knack kinds show right now, as a word ("" while knacks are shut).
func _knacks_key() -> String:
	var catalog := GameState.catalog
	if not Knacks.system_open(catalog, GameState.knack_gate):
		return ""
	var on: Array[String] = []
	for kind: String in catalog.knacks.kinds:
		if Knacks.kind_open(catalog, kind, GameState.knack_gate):
			on.append(kind)
	return ",".join(on)


func _filtered() -> Array[Pet]:
	var tiers: Array = FILTERS.filter(func(t): return _chips[t].button_pressed)
	var sparkly: bool = _chips.sparkly.button_pressed
	var out: Array[Pet] = []
	for pet in _sorted(GameState.collection.pets):
		if not tiers.is_empty() and not pet.rarity in tiers:
			continue
		if sparkly and pet.finish == "normal":
			continue
		out.append(pet)
	return out


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
		"rarest":
			out.sort_custom(func(a: Pet, b: Pet):
				var ra := catalog.rank(a.rarity)
				var rb := catalog.rank(b.rarity)
				return ra > rb if ra != rb else catalog.finish_rank(a.finish) > catalog.finish_rank(b.finish))
		"a to z":
			out.sort_custom(func(a: Pet, b: Pet): return a.display_name(catalog) < b.display_name(catalog))
	return out
