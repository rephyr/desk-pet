class_name TutorialGuide
extends Control
## The first few minutes of a new game: a soft pulsing outline around the thing to press, and
## one line next to it (data/tutorial.json). It moves on by itself as GameState notices each
## step is done, and disappears for good afterwards. Draws on top, never blocks clicks.

var target_for: Callable  # () -> Control: what to point at right now, or null
var _bubble := PanelContainer.new()
var _line := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
var _target: Control
var _time := 0.0
var _ring := UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 14, 0)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	z_index = UiTheme.Z_POPUP  # over the receipt and the tapes
	_bubble.mouse_filter = MOUSE_FILTER_IGNORE
	_bubble.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.PINK_SEAM, 14, UiTheme.RAISED, 10))
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size = Vector2(220, 0)
	_bubble.add_child(_line)
	add_child(_bubble)


func _process(delta: float) -> void:
	_time += delta
	var info := GameState.tutorial_info()
	_target = target_for.call() if not info.is_empty() and target_for.is_valid() else null
	var showing := _target != null and _target.is_visible_in_tree()
	_bubble.visible = showing
	queue_redraw()
	if not showing:
		return
	# pointing at a tab to get somewhere first: "tap here…", then the step's own line once there
	var on_tab := _target.is_in_group(Spine.TAB_GROUP) and info.has("go")
	_line.text = _fill(str(info.go if on_tab else info.say))
	_line.add_theme_color_override("font_color", UiTheme.PINK if info.speaker in ["box", "machine"] else UiTheme.TEXT)
	# under the target if there's room, otherwise above it; always inside the window
	var rect := _target_rect()
	var bubble_size := _bubble.get_combined_minimum_size()
	var pos := Vector2(rect.position.x, rect.end.y + 10)
	if pos.y + bubble_size.y > size.y:
		pos.y = rect.position.y - bubble_size.y - 10
	pos.x = clampf(pos.x, 4, size.x - bubble_size.x - 4)
	_bubble.position = pos
	_bubble.size = bubble_size


## What it's pointing at right now (or null), for the dev driver's "click guide".
func current_target() -> Control:
	return _target if _target != null and _target.is_visible_in_tree() else null


func _draw() -> void:
	if _target == null or not _target.is_visible_in_tree():
		return
	# a stitched ring that breathes in and out around the thing to press
	var glow := 0.5 + 0.5 * sin(_time * 4.0)
	var r := _target_rect().grow(6.0 + glow * 4.0)
	_ring.dash_color = Color(UiTheme.PINK, 0.55 + 0.45 * glow)
	_ring.width = 3.0
	draw_style_box(_ring, r)


func _target_rect() -> Rect2:
	var r := _target.get_global_rect()
	r.position -= global_position
	return r


## Fills in {active} and {other}: your active pet and the one it'll send.
func _fill(text: String) -> String:
	var active := GameState.collection.active()
	var other := ""
	for pet in GameState.collection.pets:
		if active == null or pet.uid != active.uid:
			other = pet.display_name(Catalog.shared())
			break
	return text.replace("{active}", active.display_name(Catalog.shared()) if active else "").replace("{other}", other)
