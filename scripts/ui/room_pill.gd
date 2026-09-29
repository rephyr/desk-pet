class_name RoomPill
extends PanelContainer
## The room on the pets tab: a little house, a meter and "412 / 500" (every plain pet together, see
## GameState.room_cap). Full: it turns pink and wiggles now and then. Tap it for the house card
## (HouseCard): the room grows a step at a time.
## Design: design/mockups/screens/pets-shelves.html (look A, the house meter pill), room-house.html.

const WIGGLE_EVERY := 2.6

var _icon := UiTheme.icon_rect("home", 18, UiTheme.LILAC)
var _meter := Control.new()
var _have := UiTheme.title("0", 14, UiTheme.TEXT)
var _cap := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _card: HouseCard
var _dim: ColorRect
var _full := false
var _fill := 0.0
var _wiggle := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	size_flags_vertical = SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(row)
	row.add_child(_icon)
	_meter.custom_minimum_size = Vector2(90, 10)
	_meter.size_flags_vertical = SIZE_SHRINK_CENTER
	_meter.mouse_filter = MOUSE_FILTER_IGNORE
	_meter.draw.connect(_draw_meter)
	row.add_child(_meter)
	var nums := HBoxContainer.new()
	nums.add_theme_constant_override("separation", 3)
	nums.mouse_filter = MOUSE_FILTER_IGNORE
	_have.mouse_filter = MOUSE_FILTER_IGNORE
	_cap.mouse_filter = MOUSE_FILTER_IGNORE
	_have.size_flags_vertical = SIZE_SHRINK_CENTER
	_cap.size_flags_vertical = SIZE_SHRINK_CENTER
	nums.add_child(_have)
	nums.add_child(_cap)
	row.add_child(nums)
	resized.connect(func(): pivot_offset = size / 2.0)
	GameState.changed.connect(refresh)
	GameState.collection.herd_changed.connect(func(_keys): refresh())
	GameState.collection.pets_added.connect(func(_p): refresh())
	GameState.collection.pets_removed.connect(func(_u): refresh())
	refresh()


## Numbers, colours and whether it shows at all (once a pet has folded into the herd). While the
## house card is open it's lit pink.
func refresh() -> void:
	var cap := GameState.room_cap()
	var have := GameState.collection.plain_count()
	_full = GameState.room_is_full()
	_fill = clampf(float(have) / maxf(1.0, cap), 0.0, 1.0)
	_have.text = UiTheme.num(have)
	_cap.text = "/ " + UiTheme.num(cap)
	var open := _card != null and _card.visible
	var color := UiTheme.PINK if _full or open else UiTheme.LILAC
	var sb := UiTheme.box(UiTheme.PINK_PRESSED if open else UiTheme.DEEP, UiTheme.PINK if _full or open else UiTheme.LILAC.lerp(UiTheme.LINE, 0.65), 999, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)
	_icon.texture = UiTheme.icon("home", 18, color)
	_meter.queue_redraw()


func _process(delta: float) -> void:
	if not _full or not is_visible_in_tree():
		if rotation_degrees != 0.0 and not _full:
			rotation_degrees = 0.0
		return
	_wiggle += delta
	if _wiggle >= WIGGLE_EVERY:
		_wiggle = 0.0
		var t := create_tween()
		for deg in [-2.0, 2.0, -1.0, 0.0]:
			t.tween_property(self, "rotation_degrees", deg, 0.1)


func _draw_meter() -> void:
	var r := Rect2(Vector2.ZERO, _meter.size)
	_meter.draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.LINE, 999, 2, 0), r)
	if _fill > 0.0:
		var w := maxf(r.size.y - 4.0, (r.size.x - 4.0) * _fill)
		_meter.draw_style_box(UiTheme.box(UiTheme.PINK if _full else UiTheme.LILAC, Color(0, 0, 0, 0), 999, 0, 0),
			Rect2(Vector2(2, 2), Vector2(w, r.size.y - 4.0)))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		toggle_card()


## The house card (HouseCard), under the pill, with a dim layer over the pets page behind it: tap
## outside it (or its x, or the pill again) and it closes.
func toggle_card() -> void:
	if _card == null:
		_dim = ColorRect.new()
		_dim.top_level = true
		_dim.z_as_relative = false
		_dim.z_index = 5
		_dim.color = Color(UiTheme.SKY, 0.58)
		_dim.mouse_filter = MOUSE_FILTER_STOP
		_dim.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed:
				_dim.accept_event()
				hide_card())
		add_child(_dim)
		_card = HouseCard.new()
		_card.closed.connect(hide_card)
		add_child(_card)
		_dim.visible = false
		_card.visible = false
	if _card.visible:
		hide_card()
		return
	var cover := get_parent()
	while cover != null and not cover is CollectionTab:
		cover = cover.get_parent()
	var r: Rect2 = (cover as Control).get_global_rect() if cover is Control else get_viewport_rect()
	_dim.global_position = r.position
	_dim.size = r.size
	_dim.visible = true
	z_index = 6  # the pill stays lit above the dim layer
	_card.open(self)
	refresh()


func hide_card() -> void:
	if _card:
		_card.close()
		_card.visible = false
		_dim.visible = false
	if z_index != 0:
		z_index = 0
		refresh()
