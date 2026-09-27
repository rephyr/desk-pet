class_name HomeTab
extends VBoxContainer
## The first thing you see in the full game: your active pet's room. The pet sits in the middle
## and talks about what's going on (PetVoice); around it, little cards for what needs you (trips,
## boxes in the bag, parts to sew on, the map), each one a shortcut to its tab. Feed and pat here.

signal go(tab_name: String)  # a card was tapped: show that tab
signal open_box(box_id: String)

var _speech := UiTheme.label("", UiTheme.TEXT)
var _pet := PetPortrait.new(9, true)
var _name := UiTheme.label("", UiTheme.PINK, 18)
var _food := UiTheme.bar(UiTheme.PINK)
var _mood := UiTheme.bar(UiTheme.LILAC)
var _cards := {}  # name -> { panel, title, line }
var _rng := RandomNumberGenerator.new()
var _dirty := true


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()

	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.PINK.darkened(0.35), 14, 2, 14))
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_speech.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.add_child(_speech)
	add_child(bubble)

	var room := HBoxContainer.new()
	room.size_flags_vertical = SIZE_EXPAND_FILL
	room.add_theme_constant_override("separation", 20)
	add_child(room)
	room.add_child(_card_column(["trips", "boxes"]))
	room.add_child(_middle())
	room.add_child(_card_column(["parts", "map"]))

	GameState.changed.connect(func(): _dirty = true)
	GameState.adventures_changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_speak()
			_refresh())


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_food.value = GameState.hunger
	_mood.value = GameState.happiness
	if _dirty:
		_refresh()


## The pet, its name, how it's doing, and feed / pat.
func _middle() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	# the room: a soft glow behind your pet and a little crayon rug under it, drawn behind everything
	col.draw.connect(func():
		var center := _pet.position + _pet.size / 2.0
		for i in 6:
			col.draw_circle(center, 150.0 - i * 22.0, Color(UiTheme.LILAC, 0.035))
		var feet := Vector2(center.x, _pet.position.y + _pet.size.y - 4.0)
		var rug := PackedVector2Array()
		for i in 33:
			var a := TAU * i / 32.0
			rug.append(feet + Vector2(cos(a) * 110.0, sin(a) * 22.0))
		col.draw_colored_polygon(rug, Color(UiTheme.PINK, 0.08))
		col.draw_polyline(rug, Color(UiTheme.PINK, 0.35), 2.0, true))
	col.sort_children.connect(col.queue_redraw)  # after layout, so the glow sits behind the pet
	_pet.size_flags_horizontal = SIZE_SHRINK_CENTER
	_pet.clicked.connect(func():
		GameState.pat()
		_pet.view.squash = 0.6)
	col.add_child(_pet)
	var under_rug := Control.new()
	under_rug.custom_minimum_size = Vector2(0, 18)
	col.add_child(under_rug)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_name)
	for row in [["food", _food], ["mood", _mood]]:
		var line := HBoxContainer.new()
		line.custom_minimum_size = Vector2(220, 0)
		line.size_flags_horizontal = SIZE_SHRINK_CENTER
		var label := UiTheme.label(row[0], UiTheme.MUTED, UiTheme.SMALL)
		label.custom_minimum_size = Vector2(44, 0)
		line.add_child(label)
		line.add_child(row[1])
		col.add_child(line)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 8)
	buttons.add_child(UiTheme.button("feed ◆%d" % GameState.FEED_COST, func(): GameState.feed()))
	buttons.add_child(UiTheme.button("pat", func():
		GameState.pat()
		_pet.view.squash = 0.6))
	col.add_child(buttons)
	return col


func _card_column(names: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	for card_name in names:
		col.add_child(_card(card_name))
	return col


## A little card: a title and one line, tappable.
func _card(card_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.LILAC.darkened(0.45), 12, 2, 12))
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var title := UiTheme.label("", UiTheme.PINK)
	var line := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for l in [title, line]:
		l.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(l)
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tapped(card_name))
	_cards[card_name] = { "panel": panel, "title": title, "line": line }
	return panel


func _tapped(card_name: String) -> void:
	match card_name:
		"trips", "map":
			go.emit("adventures")
		"parts":
			go.emit("inventory")
		"boxes":
			var owned := _first_box_in_bag()
			if owned != "":
				open_box.emit(owned)
			else:
				go.emit("boxes")


## What each card says right now; a card with something waiting glows a little.
func _refresh() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	_pet.set_pet(pet)
	_name.text = pet.display_name(catalog) if pet else ""

	var back := GameState.runs.filter(func(r): return r.status == RunState.Status.DONE).size()
	var waiting := GameState.runs.filter(func(r): return r.status == RunState.Status.WAITING).size()
	var away := GameState.runs.size()
	_set_card("trips", "trips", _pick([
		[back > 0, "%d back! say welcome ->" % back],
		[waiting > 0, "%d waiting for you ->" % waiting],
		[away > 0, "%d out and about" % away],
		[true, "nobody's away"]]), back + waiting > 0)

	var boxes := 0
	for box_id in GameState.bag:
		boxes += GameState.in_bag(box_id)
	_set_card("boxes", "boxes", "%d in your bag. open one ->" % boxes if boxes > 0 else "get more in the shop ->", boxes > 0)

	var parts := 0
	for key in GameState.parts:
		parts += int(GameState.parts[key])
	_set_card("parts", "parts", "%d to sew on ->" % parts if parts > 0 else "none yet. pets find them on trips", parts > 0)

	var ready := GameState.spotted.keys().filter(func(id): return GameState.lead_wait(id) <= 0.0).size() + GameState.rumours.size()
	_set_card("map", "map", "somewhere new to go! ->" if ready > 0 else "go on a trip ->", ready > 0)


func _set_card(card_name: String, title: String, line: String, glow: bool) -> void:
	var card: Dictionary = _cards[card_name]
	card.title.text = title
	card.line.text = line
	var border := UiTheme.PINK if glow else UiTheme.LILAC.darkened(0.45)
	card.panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, border, 12, 2, 12))


static func _pick(options: Array) -> String:
	for option in options:
		if option[0]:
			return option[1]
	return ""


func _first_box_in_bag() -> String:
	for box in Catalog.shared().boxes:
		if GameState.in_bag(box.id) > 0:
			return box.id
	return ""


## Your pet says what's worth saying (the same news the adventures tab would talk about).
func _speak() -> void:
	var pet := GameState.collection.active()
	if pet == null:
		_speech.text = ""
		return
	var catalog := Catalog.shared()
	# big news first: something found, something new opened up
	var news := GameState.take_announcement()
	if news != "":
		var more := GameState.take_announcement()
		_speech.text = news + (" " + more if more != "" else "")
		_speech.visible_ratio = 0.0
		create_tween().tween_property(_speech, "visible_ratio", 1.0, 0.02 * _speech.text.length())
		return
	# first what it did for you while you were busy, if anything
	var work := PetVoice.work_summary(pet, GameState.take_idle_log(), _rng, catalog)
	if work != "":
		_speech.text = work
	else:
		var what := PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog)
		GameState.news = {}
		_speech.text = PetVoice.line(pet, what, _rng, catalog)
	_speech.visible_ratio = 0.0
	create_tween().tween_property(_speech, "visible_ratio", 1.0, 0.02 * _speech.text.length())
	_pet.view.squash = 0.4
