class_name Spine
extends Control
## The left edge of the full game: a strip of night sky sewn onto the page. Your active pet sits
## on a little moon at the top; the tabs stand in a column under it (icon, name below), settings
## at the bottom. The active tab is a stitched-on patch. The dim stars behind are NightSky's.

signal tab_pressed(tab_id: String)

const WIDTH := 80.0

const TAB_GROUP := "spine_tab"

var _sky := NightSky.new()
var _column := VBoxContainer.new()
var _pet := PetView.new()
var _work := MoonWork.new()  # a tiny pack in its paws while it opens your pile out of sight
var _toy := ToyView.new("", "normal", 2)  # the toy it's playing with, at its side
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
	_work.pet_view = _pet
	moon.add_child(_work)
	_toy.visible = false
	moon.add_child(_toy)
	moon.resized.connect(func():
		_pet.position = Vector2(moon.size.x / 2.0, moon.size.y - 8.0)  # PetView draws from its bottom centre
		_work.position = _pet.position
		_toy.position = _pet.position + Vector2(10, -34))
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
	GameState.toys_changed.connect(_show_toy)
	_show_toy()


## The toy your pet is playing with sits at its side on the moon (the first one, if there are more).
func _show_toy() -> void:
	var now := Time.get_unix_time_from_system()
	for p in GameState.toys.playing:
		if float(p.until) > now:
			var bits := Toys.split(str(p.key))
			_toy.show_toy(bits[0], bits[1], 2)
			_toy.visible = true
			_toy.tooltip_text = "playing! do not disturb"
			return
	_toy.visible = false


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
	b.add_to_group(TAB_GROUP)  # the tutorial says "tap here" while it points at one of these
	b.set_meta("tab_id", id)
	b.text = text
	b.icon = UiTheme.icon(icon_name, 18, UiTheme.MUTED)
	b.set_meta("icon_name", icon_name)
	b.focus_mode = FOCUS_NONE
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 18)
	# a long name ("adventures") a size smaller, so it fits the spine
	b.add_theme_font_size_override("font_size", UiTheme.SMALL if text.length() <= 8 else UiTheme.SMALL - 2)
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
		var patch := UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 2)
		b.add_theme_stylebox_override("normal", patch if on else StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", patch if on else StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", UiTheme.PINK if on else UiTheme.MUTED)
		b.icon = UiTheme.icon(b.get_meta("icon_name"), 18, UiTheme.PINK if on else UiTheme.MUTED)
		(b.get_parent() as Tilted).degrees = -3.0 if on else 0.0


## Shows or hides a tab (the tutorial, or not earned yet: never shown locked), and its news dot.
func set_tab_state(id: String, shown: bool, news := false) -> void:
	var b: Button = _tabs[id]
	b.get_parent().visible = shown
	_news[id].visible = news and shown
	set_current(_current)


## The gold dot on a tab: something new there.
func set_news(id: String, news: bool) -> void:
	if _news.has(id):
		_news[id].visible = news and _tabs[id].get_parent().visible


func tab_button(id: String) -> Button:
	return _tabs.get(id)


## Over your pet on the moon, while it opens your pile out of sight (you're on another tab): a
## tiny pack at its side that shakes harder as it gets close, then pop! and a tiny new pet hops
## off the moon. A good pull gets a moment of gold sparkles. Draws from your pet's feet.
class MoonWork extends Node2D:
	const HOP_TIME := 1.2
	const SHAKE_FROM := 0.55  # the pack shows up this far into each one

	var pet_view: PetView
	var _hopper := PetView.new()
	var _puff := 0.0
	var _hop := 0.0
	var _sparkle := 0.0
	var _time := 0.0

	func _init() -> void:
		_hopper.pixel = 1
		_hopper.visible = false
		add_child(_hopper)
		GameState.opened_in_background.connect(_popped)

	func _popped(pet: Pet) -> void:
		_puff = 1.0
		_hop = HOP_TIME
		_hopper.pet = pet
		_hopper.visible = true
		_sparkle = 1.6 if GameState.is_good_pull(pet) else 0.0
		if pet_view:
			pet_view.squash = 0.5

	func _process(delta: float) -> void:
		_time += delta
		_puff = move_toward(_puff, 0.0, delta * 2.0)
		_sparkle = move_toward(_sparkle, 0.0, delta)
		if _hop > 0.0:
			_hop = maxf(0.0, _hop - delta)
			var t := 1.0 - _hop / HOP_TIME
			_hopper.position = Vector2(lerpf(-14.0, -34.0, t), -absf(sin(t * PI * 2.0)) * 10.0)
			_hopper.modulate.a = 1.0 if t < 0.7 else (1.0 - t) / 0.3
			_hopper.visible = _hop > 0.0
		queue_redraw()

	func _draw() -> void:
		var p := GameState.background_packing()
		if p >= SHAKE_FROM:
			var box := GameState.next_pet_box()
			if box != "":
				var k := (p - SHAKE_FROM) / (1.0 - SHAKE_FROM)  # 0..1, shaking harder
				var tex := PackArt.texture(Catalog.shared().box(box).get("art", {}), 14)
				var s := Vector2(14, 14 * 1.3)
				draw_set_transform(Vector2(20.0 + sin(_time * 45.0) * 1.5 * k, -16.0), sin(_time * 38.0) * 0.3 * k)
				draw_texture_rect(tex, Rect2(-s / 2.0, s), false)
				draw_set_transform(Vector2.ZERO)
		if _puff > 0.0:
			draw_arc(Vector2(16, -20), 6.0 + (1.0 - _puff) * 16.0, 0.0, TAU, 20, Color(UiTheme.GOLD, _puff), 2.0 * _puff + 0.5, true)
		if _sparkle > 0.0:
			for i in 4:
				var a := TAU * i / 4.0 + _time * 2.0
				var at := Vector2(0, -26) + Vector2(cos(a) * 26.0, sin(a) * 18.0)
				var r := 2.0 + 2.0 * absf(sin(_time * 6.0 + i))
				var c := Color(UiTheme.GOLD, minf(1.0, _sparkle))
				draw_line(at - Vector2(r, 0), at + Vector2(r, 0), c, 1.5)
				draw_line(at - Vector2(0, r), at + Vector2(0, r), c, 1.5)
