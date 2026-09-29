class_name WhyTape
extends Button
## A strip of pink washi tape saying "why so much?", stuck where coins land (the trip postcard's
## coins, the errands pill, the machine's "N coins a capsule"). Tap it for its WhySlip: where the
## number started, what multiplied it, and what it all came to; tap again to fold it. It only shows
## once something did multiply the number (its why has a line). `source` is a Callable giving the
## why (a Boosts.why dictionary); `also` (optional) is one more thing that must be true for it to show.
## Design: design/mockups/screens/receipt.html (look A).

var source: Callable
var also: Callable
var slip := WhySlip.new()
var _check := 0.0


func _init(why_source: Callable = Callable()) -> void:
	source = why_source
	text = "why so much?"
	focus_mode = FOCUS_NONE
	visible = false
	z_index = UiTheme.Z_TAPE
	rotation_degrees = 8.0
	add_theme_font_size_override("font_size", 10)
	var sb := TapeBox.new()
	var hover := TapeBox.new()
	hover.color = Color(UiTheme.PINK, 0.75)
	for state in ["normal", "pressed", "focus"]:
		add_theme_stylebox_override(state, sb)
	for state in ["hover", "hover_pressed"]:
		add_theme_stylebox_override(state, hover)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(c, UiTheme.DEEP)
	resized.connect(func(): pivot_offset = size / 2.0)
	pressed.connect(toggle)


## Opens or folds the slip.
func toggle() -> void:
	if slip.visible:
		slip.visible = false
		return
	slip.show_why(source.call())
	slip.visible = true
	slip.pivot_offset = Vector2(slip.size.x / 2.0, 0)
	slip.scale = Vector2(1, 0.3)
	slip.modulate.a = 0.0
	var t := slip.create_tween().set_parallel()
	t.tween_property(slip, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(slip, "modulate:a", 1.0, 0.15)


## Shows the tape once its why has a line (and `also` agrees); keeps an open slip up to date.
func refresh() -> void:
	var why: Dictionary = source.call() if source.is_valid() else {}
	var show: bool = not why.is_empty() and not why.lines.is_empty() and (not also.is_valid() or bool(also.call()))
	if show != visible:
		visible = show
	if not show:
		slip.visible = false
	elif slip.visible:
		slip.show_why(why)


func _process(delta: float) -> void:
	if get_parent() is CanvasItem and not (get_parent() as CanvasItem).is_visible_in_tree():
		return  # its page is away
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		refresh()


## Wraps `target` (a pill or a chip) in a box as big as it, with the tape stuck across the middle of
## its top edge (tilted up to the right, so it covers none of the number) and the slip hanging
## under it over whatever follows. `right`: for a wide pill at the window's right edge, the slip is
## right-aligned under it (so it stays inside the window) and the tape holds the pill's top left
## corner, clear of its words.
## Put the box where the target was.
static func wrap(target: Control, why_source: Callable, right := false) -> Control:
	var box := Control.new()
	box.mouse_filter = MOUSE_FILTER_PASS
	box.size_flags_vertical = target.size_flags_vertical
	box.size_flags_horizontal = target.size_flags_horizontal
	box.add_child(target)
	var tape := WhyTape.new(why_source)
	tape.rotation_degrees = -8.0  # its low end on the left, so the words at the right stay clear
	box.add_child(tape)
	box.add_child(tape.slip)
	var grow := func(): box.custom_minimum_size = target.get_combined_minimum_size()
	target.minimum_size_changed.connect(grow)
	grow.call()
	var place := func():
		target.position = Vector2.ZERO
		target.size = box.size
		tape.size = tape.get_combined_minimum_size()
		tape.position = Vector2(-tape.size.x * 0.45, -tape.size.y * 0.65) if right else Vector2((box.size.x - tape.size.x) / 2.0, -tape.size.y * 0.8)
		tape.slip.position = Vector2(box.size.x - WhySlip.WIDTH if right else 0.0, box.size.y + 6.0)
	box.resized.connect(place)
	tape.resized.connect(place)
	return box


## The washi: see-through pink with torn ends.
class TapeBox extends StyleBox:
	var color := Color(UiTheme.PINK, 0.55)
	const SHAPE := [[0, .12], [.04, 0], [.09, .14], [.14, 0], [1, 0], [.96, .5], [1, 1], [.12, 1], [.06, .86], [0, 1], [.03, .5]]

	func _init() -> void:
		content_margin_left = 9
		content_margin_right = 9
		content_margin_top = 3
		content_margin_bottom = 3

	func _draw(to_canvas_item: RID, rect: Rect2) -> void:
		var pts := PackedVector2Array()
		for p in SHAPE:
			pts.append(rect.position + Vector2(p[0] * rect.size.x, p[1] * rect.size.y))
		RenderingServer.canvas_item_add_polygon(to_canvas_item, pts, PackedColorArray([color]))
