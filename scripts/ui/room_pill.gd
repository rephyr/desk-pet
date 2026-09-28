class_name RoomPill
extends PanelContainer
## The room on the pets tab: a little house, a meter and "412 / 500" (every plain pet together, see
## GameState.room_cap). Full: it turns pink and wiggles now and then. Tap it for the room card:
## more room for coins.
## Design: design/mockups/screens/pets-shelves.html (look A, the house meter pill).

const WIGGLE_EVERY := 2.6

var _icon := UiTheme.icon_rect("home", 18, UiTheme.LILAC)
var _meter := Control.new()
var _have := UiTheme.title("0", 14, UiTheme.TEXT)
var _cap := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _card: PanelContainer
var _card_price: Button
var _card_sizes: Label
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


## Numbers, colours and whether it shows at all (once a pet has folded into the herd).
func refresh() -> void:
	var cap := GameState.room_cap()
	var have := GameState.collection.plain_count()
	_full = GameState.room_is_full()
	_fill = clampf(float(have) / maxf(1.0, cap), 0.0, 1.0)
	_have.text = UiTheme.num(have)
	_cap.text = "/ " + UiTheme.num(cap)
	var color := UiTheme.PINK if _full else UiTheme.LILAC
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK if _full else UiTheme.LILAC.lerp(UiTheme.LINE, 0.65), 999, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	add_theme_stylebox_override("panel", sb)
	_icon.texture = UiTheme.icon("home", 18, color)
	_meter.queue_redraw()
	if _card and _card.visible:
		_fill_card()


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


## The room card, under the pill: "more room", 500 → 750, and the price.
func toggle_card() -> void:
	if _card == null:
		_card = PanelContainer.new()
		_card.top_level = true
		_card.z_index = 5
		_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		_card.add_child(col)
		col.add_child(UiTheme.title("more room", 16, UiTheme.LILAC))
		_card_sizes = UiTheme.title("", 14, UiTheme.TEXT)
		col.add_child(_card_sizes)
		_card_price = UiTheme.button("", func(): _buy())
		_card_price.icon = UiTheme.icon("coin", 14, UiTheme.CYAN)
		_card_price.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6))
		col.add_child(_card_price)
		add_child(_card)
		_card.visible = false
	_card.visible = not _card.visible
	if _card.visible:
		_fill_card()
		_card.reset_size()
		# right under the pill, its right edge lined up with the pill's
		_card.global_position = global_position + Vector2(size.x - _card.get_combined_minimum_size().x, size.y + 8.0)


func hide_card() -> void:
	if _card:
		_card.visible = false


func _fill_card() -> void:
	_card_sizes.text = "%s → %s" % [UiTheme.num(GameState.room_cap()), UiTheme.num(Herd.room_cap(GameState.catalog, GameState.room + 1))]
	_card_price.text = UiTheme.num(GameState.room_price())
	_card_price.disabled = GameState.coins < GameState.room_price()


func _buy() -> void:
	if not GameState.buy_room():
		PetBubble.say_line(self, "room_poor")
		return
	hide_card()
	PetBubble.say_line(self, "room_more")
