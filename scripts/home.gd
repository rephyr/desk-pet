extends Control
## The home window: a small pinned panel where you look after the pet.
## When the pet is let out, it moves into a transparent overlay and walks on your windows.

const PINK := Color("ff79c6")
const LILAC := Color("c9a0ff")
const CYAN := Color("8be9fd")
const TEXT := Color("f5dcec")
const BG := Color("1a1024")
const BG_DEEP := Color("120a19")

var _source: WindowSource
var _overlay: Window
var _pet: DesktopPet
var _home_pet: PetSprite
var _coins: Label
var _status: Label
var _hunger: ProgressBar
var _happy: ProgressBar
var _out_button: Button
var _fullscreen_check := 0.0
var _tucked_away := false


func _ready() -> void:
	var win := get_window()
	win.title = "Desk Pets"
	_build_ui()
	_create_overlay()
	GameState.changed.connect(_refresh)
	_out_button.disabled = true
	# give the OS a moment to actually show the home window before setting up around it
	await get_tree().create_timer(0.3).timeout
	_source = WindowSource.create()
	_source.setup(win, _overlay)
	_out_button.disabled = false
	_set_out(GameState.pet_out)


func _process(delta: float) -> void:
	_hunger.value = GameState.hunger
	_happy.value = GameState.happiness
	_fullscreen_check -= delta
	if _source and _fullscreen_check <= 0.0:
		_fullscreen_check = 0.25
		_tuck_away(_source.is_fullscreen_active(get_window()))
		# moved the home panel to another monitor: the pet comes along
		if _pet and _source.overlay_misplaced(get_window(), _overlay):
			_source.place_overlay(get_window(), _overlay)
			_pet.drop_at(Vector2(_overlay.size.x / 2.0, 80.0))


## Hides the panel (and lets clicks through) while a game or video is fullscreen on its screen.
func _tuck_away(hide_it: bool) -> void:
	if hide_it == _tucked_away:
		return
	_tucked_away = hide_it
	visible = not hide_it
	if hide_it:
		get_window().mouse_passthrough_polygon = PackedVector2Array([Vector2(-3, -3), Vector2(-2, -3), Vector2(-2, -2)])
	else:
		get_window().mouse_passthrough_polygon = PackedVector2Array()


func _create_overlay() -> void:
	_overlay = Window.new()
	_overlay.title = "Desk Pets Overlay"
	_overlay.borderless = true
	_overlay.transparent = true
	_overlay.transparent_bg = true
	_overlay.always_on_top = true
	_overlay.unfocusable = true
	_overlay.visible = false
	add_child(_overlay)


func _set_out(out: bool) -> void:
	GameState.set_pet_out(out)
	if out:
		_overlay.show()
		_source.place_overlay(get_window(), _overlay)
		_pet = DesktopPet.new()
		_pet.source = _source
		_pet.overlay = _overlay
		_pet.visible = false
		_overlay.add_child(_pet)
		# once the overlay has settled on the screen, pop out where the mouse is
		# (on the button you just pressed)
		await get_tree().create_timer(0.3).timeout
		if _pet:
			var mouse := _source.mouse_position(_overlay)
			_pet.drop_at(mouse.clamp(Vector2(40, 80), Vector2(_overlay.size) - Vector2(40, 0)))
			_pet.visible = true
	elif _pet:
		_pet.queue_free()
		_pet = null
		_overlay.hide()
	_home_pet.visible = not out
	_status.visible = out
	_out_button.text = "call back" if out else "let out"


func _refresh() -> void:
	_coins.text = "◆ %d" % GameState.coins


# ---- UI -------------------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Maple Mono", "Maple Mono NF", "monospace"])
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 13
	t.set_color("font_color", "Label", TEXT)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _box(BG_DEEP, PINK if state == "hover" else LILAC.darkened(0.4), 8)
		if state == "pressed":
			sb.bg_color = PINK.darkened(0.6)
		if state == "focus":
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", PINK)
	t.set_color("font_pressed_color", "Button", TEXT)
	theme = t

	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_FULL_RECT)
	var bg := _box(BG, PINK.darkened(0.3), 14)
	bg.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)

	# header doubles as the drag handle
	var header := HBoxContainer.new()
	header.mouse_filter = MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input)
	col.add_child(header)
	var title := Label.new()
	title.text = "desk pets ♡"
	title.add_theme_color_override("font_color", PINK)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(title)
	_coins = Label.new()
	_coins.add_theme_color_override("font_color", CYAN)
	_coins.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(_coins)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.pressed.connect(func(): get_tree().quit())
	header.add_child(close)

	# the pet at home
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 72)
	col.add_child(stage)
	_home_pet = PetSprite.new()
	stage.add_child(_home_pet)
	stage.resized.connect(func(): _home_pet.position = Vector2(stage.size.x / 2.0, stage.size.y - 4))
	_status = Label.new()
	_status.text = "out exploring your desktop…"
	_status.add_theme_color_override("font_color", LILAC)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(PRESET_FULL_RECT)
	stage.add_child(_status)

	_hunger = _bar(col, "food", PINK)
	_happy = _bar(col, "mood", LILAC)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	col.add_child(buttons)
	var feed := _button(buttons, "feed ◆%d" % GameState.FEED_COST)
	feed.pressed.connect(func(): GameState.feed())
	var pat := _button(buttons, "pat")
	pat.pressed.connect(func():
		GameState.pat()
		_home_pet.squash = 0.6)
	_out_button = _button(buttons, "let out")
	_out_button.pressed.connect(func(): _set_out(not GameState.pet_out))
	_refresh()


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		DisplayServer.window_start_drag(get_window().get_window_id())


func _bar(parent: Control, label: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 10)
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	var back := _box(BG_DEEP, color.darkened(0.5), 5)
	var fill := _box(color, color, 5)
	back.set_content_margin_all(0)
	fill.set_content_margin_all(0)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	row.add_child(bar)
	return bar


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.focus_mode = FOCUS_NONE
	parent.add_child(b)
	return b


func _box(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(6)
	return sb
