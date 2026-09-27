class_name Spine
extends Control
## The left edge of the full game: a strip of night sky sewn onto the page. Your active pet sits
## on a little moon at the top; the tabs stand in a column under it (icon, name below), settings
## at the bottom. The active tab is a stitched-on patch. The dim stars behind are NightSky's.

signal tab_pressed(tab_id: String)

const WIDTH := 80.0

var _sky := NightSky.new()
var _column := VBoxContainer.new()
var _pet := PetView.new()
var _tabs := {}  # id -> Button
var _news := {}  # id -> the gold dot
var _current := ""


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	clip_contents = true
	_sky.set_anchors_preset(PRESET_FULL_RECT)
	add_child(_sky)
	_column.set_anchors_preset(PRESET_FULL_RECT)
	_column.offset_top = 10
	_column.offset_bottom = -10
	_column.offset_right = -6
	_column.add_theme_constant_override("separation", 4)
	_column.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(_column)

	var moon := Control.new()
	moon.custom_minimum_size = Vector2(0, 76)
	moon.draw.connect(func():
		var c := Vector2(moon.size.x / 2.0, moon.size.y - 7.0)
		moon.draw_set_transform(c, 0.0, Vector2(1.0, 0.24))
		moon.draw_circle(Vector2.ZERO, 26.0, UiTheme.RAISED)
		moon.draw_arc(Vector2(0, -3), 25.0, PI * 1.1, PI * 1.9, 16, UiTheme.LINE, 4.0)
		moon.draw_set_transform(Vector2.ZERO)
		# before your first pet: an empty seat waiting on the moon
		if _pet.pet == null:
			moon.draw_style_box(UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 12, 0), Rect2(c + Vector2(-20, -50), Vector2(40, 44))))
	_pet.pixel = 3
	moon.add_child(_pet)
	moon.resized.connect(func(): _pet.position = Vector2(moon.size.x / 2.0, moon.size.y - 8.0))  # PetView draws from its bottom centre
	moon.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pet.squash = 0.6
			GameState.pat())
	moon.tooltip_text = "your active pet"
	_column.add_child(moon)
	GameState.collection.active_changed.connect(func(p):
		_pet.pet = p
		moon.queue_redraw())
	_pet.pet = GameState.collection.active()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiTheme.SKY)
	# the seam: a row of stitches where the spine is sewn to the page
	var x := size.x - 3.0
	var y := 10.0
	while y < size.y - 10.0:
		draw_line(Vector2(x, y), Vector2(x, minf(y + 6.0, size.y - 10.0)), UiTheme.PINK_SEAM, 2.0)
		y += 11.0


## Adds a tab: `icon_name` from UiTheme.icon, `text` under it. Settings goes at the bottom.
func add_tab(id: String, text: String, icon_name: String, at_bottom := false) -> void:
	if at_bottom:
		var gap := Control.new()
		gap.size_flags_vertical = SIZE_EXPAND_FILL
		gap.mouse_filter = MOUSE_FILTER_IGNORE
		_column.add_child(gap)
	var b := Button.new()
	b.text = text
	b.icon = UiTheme.icon(icon_name, 18, UiTheme.MUTED)
	b.set_meta("icon_name", icon_name)
	b.focus_mode = FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 18)
	b.add_theme_font_size_override("font_size", UiTheme.SMALL)
	b.add_theme_constant_override("h_separation", 3)
	b.custom_minimum_size = Vector2(62, 50)
	b.size_flags_horizontal = SIZE_SHRINK_CENTER
	var plain := StyleBoxEmpty.new()
	plain.set_content_margin_all(4)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, plain)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	b.add_theme_color_override("icon_normal_color", Color.WHITE)
	b.pressed.connect(func(): tab_pressed.emit(id))
	var dot := Control.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.position = Vector2(46, 4)
	dot.size = Vector2(8, 8)
	dot.mouse_filter = MOUSE_FILTER_IGNORE
	dot.draw.connect(func(): dot.draw_circle(Vector2(4, 4), 4.0, UiTheme.GOLD))
	dot.visible = false
	b.add_child(dot)
	_news[id] = dot
	var holder := Tilted.new(b)
	holder.size_flags_horizontal = SIZE_SHRINK_CENTER
	_column.add_child(holder)
	_tabs[id] = b


## Shows `id` as the active tab (the stitched patch, tilted a little).
func set_current(id: String) -> void:
	_current = id
	for tab_id in _tabs:
		var b: Button = _tabs[tab_id]
		var on: bool = tab_id == id
		if b.get_meta("locked", false):
			continue
		var patch := UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 4)
		b.add_theme_stylebox_override("normal", patch if on else StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", patch if on else StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UiTheme.PINK if on else UiTheme.MUTED)
		if not b.has_meta("locked") or not b.get_meta("locked"):
			b.icon = UiTheme.icon(b.get_meta("icon_name"), 18, UiTheme.PINK if on else UiTheme.MUTED)
		(b.get_parent() as Tilted).degrees = -3.0 if on else 0.0


## Shows or hides a tab (tutorial), locks it (padlock and "???"), and its news dot.
func set_tab_state(id: String, shown: bool, locked: bool, news := false) -> void:
	var b: Button = _tabs[id]
	b.get_parent().visible = shown
	b.set_meta("locked", locked)
	if locked:
		b.icon = UiTheme.icon("lock", 18, UiTheme.LOCKED)
		b.add_theme_color_override("font_color", UiTheme.LOCKED)
	b.set_meta("label", b.get_meta("label", b.text))
	b.text = "???" if locked else b.get_meta("label")
	_news[id].visible = news and not locked
	if not locked:
		set_current(_current)


## The gold dot on a tab: something new there.
func set_news(id: String, news: bool) -> void:
	if _news.has(id):
		_news[id].visible = news and not _tabs[id].get_meta("locked", false)


func tab_button(id: String) -> Button:
	return _tabs.get(id)
