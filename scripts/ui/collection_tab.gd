class_name CollectionTab
extends VBoxContainer
## Collectibles: your pets, your capsule toys (ToysView) and the collection book.
## Pets are a bookcase (Bookcase): a pink cushion with your active pet, favourites and best ones on
## top, and a plank per rarity with the newest standing and the herd piled up beside them. Tap a
## plank to open that shelf (ShelfView: the herd's counts, the always-cards, the newest, and the
## chosen pet's sticker). The room pill on the right (RoomPill) shows how full the room is.
## Once the room has been full, the new homes stall stands in a side column beside the bookcase
## (NewHomesStall: pick a plank, take its pets), and later the sorting rule card under it
## (SortingCard). An opened shelf gets the whole width (its sticker needs it).
## No dropdowns: a dropdown is a separate OS popup window (embed_subwindows is off), which doesn't
## open properly on Hyprland.
## Design: design/mockups/screens/pets-shelves.html (look A), new-homes.html (look A, the stall).

const SIDE_WIDTH := 252

var _pets_view := HBoxContainer.new()
var _left := VBoxContainer.new()
var _side := VBoxContainer.new()
var stall := NewHomesStall.new()
var sorting := SortingCard.new()
var _sorting_holder: Tilted
var _homes_key := ""
var _bookcase := Bookcase.new()
var _shelf := ShelfView.new()
var _book := BookView.new()
var toys := ToysView.new()
var _room := RoomPill.new()
var _mode: PanelContainer  # the pets | toys | book switch
var _toys_button: Button
var _dirty := true
var _knacks_seen := ""  # which knack kinds showed when the grid was last drawn (see _knacks_key)
var _queued := false  # a rebuild is waiting for the end of the frame


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.custom_minimum_size = Vector2(0, 30)
	add_child(bar)
	_mode = UiTheme.segmented(["pets", "toys", "book"], 0, func(i): _show_mode(i))
	bar.add_child(_mode)
	bar.add_child(UiTheme.spacer())
	bar.add_child(_room)

	_pets_view.size_flags_vertical = SIZE_EXPAND_FILL
	_pets_view.add_theme_constant_override("separation", 14)
	_left.size_flags_horizontal = SIZE_EXPAND_FILL
	_left.size_flags_vertical = SIZE_EXPAND_FILL
	_left.add_child(_bookcase)
	_left.add_child(_shelf)
	_pets_view.add_child(_left)
	_shelf.visible = false
	# the new homes stall and the sorting card, once they're found
	_side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	_side.add_theme_constant_override("separation", 12)
	_side.add_child(stall)
	_sorting_holder = Tilted.new(sorting, -1.2)
	_side.add_child(_sorting_holder)
	_side.visible = false
	_pets_view.add_child(_side)
	add_child(_pets_view)
	_bookcase.shelf_opened.connect(open_shelf)
	_bookcase.plank_picked.connect(func(r): stall.set_rarity(r))
	_shelf.closed.connect(close_shelf)
	add_child(toys)
	toys.visible = false
	# the toys switch is locked ("???") until toys open (through adventures)
	_toys_button = _mode.get_child(0).get_child(1) as Button
	_lock_toys()
	GameState.changed.connect(_lock_toys)
	GameState.new_game.connect(_lock_toys)
	add_child(_book)
	_book.visible = false

	var c := GameState.collection
	c.pets_added.connect(func(pets: Array[Pet]): _mark_dirty(pets.map(func(p): return p.rarity)))
	c.pet_changed.connect(func(pet: Pet): _mark_dirty([pet.rarity]))
	c.herd_changed.connect(func(keys: Array): _mark_dirty(keys.map(func(k): return Herd.rarity_of(k))))
	c.pets_removed.connect(func(_u): _mark_dirty())
	c.active_changed.connect(func(_p): _mark_dirty())
	GameState.unlocked.connect(func(_e): _mark_dirty())
	GameState.changed.connect(func():  # the sorting rule changed: the planks under its line change
		if _homes_state() != _homes_key:
			_mark_dirty())
	GameState.new_game.connect(func():
		close_shelf()
		_mark_dirty())
	GameState.room_full.connect(func(): _room.refresh())
	# knacks showing up (parts open, a machine fix, the tutorial moving on) redraw the badges
	GameState.knacks_changed.connect(func():
		if _knacks_key() != _knacks_seen:
			_mark_dirty())
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_room.hide_card()
		_rebuild_if_visible()
		if is_visible_in_tree() and _pets_view.visible:
			speak()
		elif is_visible_in_tree() and toys.visible:
			toys.speak())
	_room.visible = false


## Something changed for these rarities ([]: anything). The rebuild waits for the end of the frame,
## so a burst of changes (a box opened: pets added, then folded) rebuilds once. An open shelf of
## another rarity is left alone (the bookcase rebuilds when the shelf closes).
func _mark_dirty(rarities: Array = []) -> void:
	if _shelf.visible and is_visible_in_tree() and not rarities.is_empty() and not _shelf.rarity in rarities:
		return
	_dirty = true
	if not _queued:
		_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_queued = false
	_rebuild_if_visible()


func speak() -> void:
	var n := GameState.collection.count()
	if n <= 1:
		PetBubble.say_line(self, "pets_alone")
	elif GameState.room_shown() and GameState.room_is_full():
		PetBubble.say_line(self, "room_full")
	elif GameState.room_shown() and GameState.room_is_cozy():
		PetBubble.say_line(self, "pets_cozy")
	else:
		PetBubble.say_line(self, "pets", { "count": ExpandedView._thousands(n) })


func show_book(book: bool) -> void:
	show_mode(2 if book else 0)


## The book, open on the spread with this sticker's page (data/book.json).
func open_book_page(page_id: String) -> void:
	show_book(true)
	_book.open_page(page_id)


## 0 pets, 1 toys, 2 the book.
func show_mode(mode: int) -> void:
	(_mode.get_child(0).get_child(mode) as Button).pressed.emit()  # flips the switch too


## Opens a rarity's shelf (`pet` chosen, or its first card).
func open_shelf(rarity: String, pet: Pet = null) -> void:
	if GameState.collection.count_of(rarity) <= 0:
		return
	_bookcase.visible = false
	_side.visible = false  # an opened shelf takes the whole width (its sticker needs the room)
	_shelf.visible = true
	_shelf.open(rarity, pet)
	if pet == null:
		PetBubble.say_line(self, "shelf_" + rarity)


func close_shelf() -> void:
	_shelf.visible = false
	_bookcase.visible = true
	_side.visible = GameState.homes_open()
	_shelf.rarity = ""
	_dirty = true
	_rebuild_if_visible()


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
	_room.visible = mode == 0 and GameState.room_shown()
	_room.hide_card()
	if mode == 2:
		PetBubble.say_line(self, "book")
	elif mode == 1:
		toys.speak()
	else:
		_rebuild_if_visible()


## For the tutorial: a pet to tap (the cushion's first), or once a shelf is open, make active.
func tutorial_target() -> Control:
	if _shelf.visible and _shelf.details.visible and not _shelf.details.active_button().disabled:
		return _shelf.details.active_button()
	return _bookcase.first_mini()


func _rebuild_if_visible() -> void:
	if _dirty and is_visible_in_tree() and _pets_view.visible:
		_rebuild()


## What the pets page's new homes part depends on (the planks show the rule's line).
func _homes_state() -> String:
	if not GameState.homes_open():
		return ""
	return "%s|%s|%s" % [str(GameState.homes.rule), str(GameState.feature_on("sorting")), str(GameState.sorted_today())]


## The shelf the stall takes from: the one picked, else the lowest rarity you have.
func _stall_rarity() -> String:
	var c := GameState.collection
	if _bookcase.picked != "" and c.count_of(_bookcase.picked) > 0:
		return _bookcase.picked
	for tier in GameState.catalog.tiers:
		if c.count_of(tier.id) > 0:
			return str(tier.id)
	return ""


func _rebuild() -> void:
	_dirty = false
	_homes_key = _homes_state()
	_knacks_seen = _knacks_key()
	_room.visible = GameState.room_shown()
	_room.refresh()
	var homes := GameState.homes_open()
	_bookcase.stall_on = homes
	_bookcase.picked = _stall_rarity() if homes else ""
	_sorting_holder.visible = GameState.feature_on("sorting")
	if homes:
		stall.set_rarity(_bookcase.picked)
	if _shelf.visible and GameState.collection.count_of(_shelf.rarity) > 0:
		_side.visible = false
		_shelf.rebuild()
	else:
		_shelf.visible = false
		_bookcase.visible = true
		_side.visible = homes
		_bookcase.rebuild()


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
