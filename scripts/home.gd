extends Control
## The game window. Two layers: a small idle panel (CompactView) and the full game (ExpandedView).
## Also owns the transparent overlay the pet walks around in when it's let out.

const COMPACT_SIZE := Vector2i(300, 236)
const EXPANDED_SIZE := Vector2i(920, 600)
const FOCUS_GRACE := 0.6  # ignore focus loss right after expanding (the resize can cause one)
const WATCH_INTERVAL := 0.25

var _source: WindowSource
var _overlay: Window
var _pet: DesktopPet
var _compact: CompactView
var _expanded: ExpandedView
var _expanded_mode := false
var _expanded_at := 0.0
var _scale := 1.0
var _watch := 0.0
var _tucked_away := false
var _out_request := 0  # bumps on every let-out, so an older pending one can tell it's stale
var _keep_open := false  # debug: --expanded keeps the big layer open for testing


func _ready() -> void:
	var win := get_window()
	win.title = "Desk Pets"
	theme = UiTheme.get_theme()
	set_anchors_preset(PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(PRESET_FULL_RECT)
	add_child(panel)
	_compact = CompactView.new()
	_expanded = ExpandedView.new()
	panel.add_child(_compact)
	panel.add_child(_expanded)
	_expanded.visible = false

	_compact.expand_requested.connect(_set_expanded.bind(true))
	_compact.let_out_toggled.connect(func(): _set_out(not GameState.pet_out))
	_compact.quit_requested.connect(_quit)
	_expanded.collapse_requested.connect(_set_expanded.bind(false))
	_expanded.quit_requested.connect(_quit)
	win.focus_exited.connect(_on_focus_lost)
	GameState.collection.active_changed.connect(func(p): if _pet: _pet.set_pet(p))

	_overlay = _make_overlay()
	add_child(_overlay)

	# give the OS a moment to actually show the window before setting up around it
	await get_tree().create_timer(0.3).timeout
	_source = WindowSource.create()
	_source.setup(win, _overlay)
	_apply_size()
	_set_out(GameState.pet_out)
	_apply_dev_args()


func _process(delta: float) -> void:
	_watch -= delta
	if _source == null or _watch > 0.0:
		return
	_watch = WATCH_INTERVAL
	_tuck_away(_source.is_fullscreen_active(get_window()))
	# dragged to a monitor with a different scale: resize to match
	if not is_equal_approx(_source.ui_scale(get_window()), _scale):
		_apply_size()
	# dragged to another monitor: the pet comes along
	if _pet and _source.overlay_misplaced(get_window(), _overlay):
		_source.place_overlay(get_window(), _overlay)
		_pet.drop_at(Vector2(_overlay.size.x / 2.0, 80.0))


func _unhandled_input(event: InputEvent) -> void:
	if _expanded_mode and event.is_action_pressed("ui_cancel"):
		_set_expanded(false)


# ---- layers ---------------------------------------------------------------

func _set_expanded(on: bool) -> void:
	if on == _expanded_mode:
		return
	_expanded_mode = on
	_expanded_at = Time.get_ticks_msec() / 1000.0
	_compact.visible = not on
	_expanded.visible = on
	_apply_size()
	if on:
		get_window().grab_focus()


func _on_focus_lost() -> void:
	# clicking anywhere else puts the game back to the small panel
	if _expanded_mode and not _keep_open and Time.get_ticks_msec() / 1000.0 - _expanded_at > FOCUS_GRACE:
		_set_expanded(false)


func _apply_size() -> void:
	if _source == null:
		return
	_scale = _source.ui_scale(get_window())
	get_window().content_scale_factor = _scale
	_source.set_home_size(get_window(), EXPANDED_SIZE if _expanded_mode else COMPACT_SIZE)


## Hides everything (and lets clicks through) while a game or video is fullscreen on this screen.
func _tuck_away(hide_it: bool) -> void:
	if hide_it == _tucked_away:
		return
	_tucked_away = hide_it
	visible = not hide_it
	var nowhere := PackedVector2Array([Vector2(-3, -3), Vector2(-2, -3), Vector2(-2, -2)])
	get_window().mouse_passthrough_polygon = nowhere if hide_it else PackedVector2Array()


## Debug-build shortcuts for testing, see DevArgs.
func _apply_dev_args() -> void:
	if DevArgs.has("expanded"):
		_keep_open = true
		_set_expanded(true)
	if DevArgs.value("tab") != "":
		_expanded.show_tab(DevArgs.value("tab"))
	if DevArgs.has("book"):
		_expanded.collection.show_book(true)
	var open := DevArgs.value("open")  # e.g. starter:10
	if open != "":
		var bits := open.split(":")
		GameState.add_debug_coins()
		_expanded.boxes.open(bits[0], int(bits[1]) if bits.size() > 1 else 1)


func _quit() -> void:
	GameState.save_game()
	get_tree().quit()


# ---- the pet out on the desktop -------------------------------------------

func _make_overlay() -> Window:
	var w := Window.new()
	w.title = "Desk Pets Overlay"
	w.borderless = true
	w.transparent = true
	w.transparent_bg = true
	w.always_on_top = true
	w.unfocusable = true
	w.visible = false
	return w


func _set_out(out: bool) -> void:
	if _source == null:
		return  # still starting up; _ready applies the saved state once it's ready
	_out_request += 1
	var request := _out_request
	GameState.set_pet_out(out)
	_compact.set_pet_out(out)
	if not out:
		if _pet:
			_pet.queue_free()
			_pet = null
		_overlay.hide()
		return
	if _pet:
		return
	_overlay.show()
	_source.place_overlay(get_window(), _overlay)
	_pet = DesktopPet.new()
	_pet.source = _source
	_pet.overlay = _overlay
	_pet.pixel = roundi(4 * _scale)
	_pet.set_pet(GameState.collection.active())
	_pet.visible = false
	_overlay.add_child(_pet)
	# once the overlay has settled on the screen, pop out where the mouse is
	# (on the button you just pressed)
	await get_tree().create_timer(0.3).timeout
	if _pet and request == _out_request:
		var mouse := _source.mouse_position(_overlay)
		_pet.drop_at(mouse.clamp(Vector2(40, 80), Vector2(_overlay.size) - Vector2(40, 0)))
		_pet.visible = true
