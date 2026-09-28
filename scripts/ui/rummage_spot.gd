class_name RummageSpot
extends Control
## A spot in your pet's room it can dig through (see data/rummage.json and GameState.rummage):
## the little dresser, the plant pot, the sock pile, the toy box. Crayon doodles like the rest of
## the room. Gold twinkles over it while something's in there; tap it and your pet comes to dig.
## While it digs the spot shakes, bits fly out, and the drawer or lid is open. HomeTab places it
## (by its bottom middle) and moves your pet.

signal tapped(spot: RummageSpot)

## How big each doodle is, and where your pet dives in (from the top left).
const SIZES := {
	"dresser": Vector2(96, 84), "plant": Vector2(72, 124), "socks": Vector2(76, 44), "toybox": Vector2(80, 62),
}
const DIVE := {
	"dresser": Vector2(48, 16), "plant": Vector2(36, 86), "socks": Vector2(38, 16), "toybox": Vector2(40, 22),
}

var spot: Dictionary
var digging := false  # your pet is in it right now
var _ready_now := false
var _time := randf() * 3.0


func _init(spot_data: Dictionary) -> void:
	spot = spot_data
	size = SIZES.get(spot.draw, Vector2(64, 64))
	custom_minimum_size = size
	mouse_filter = MOUSE_FILTER_STOP


func _process(delta: float) -> void:
	_time += delta
	var ready_now := GameState.rummage_ready(spot.id)
	if ready_now != _ready_now:
		_ready_now = ready_now
		tooltip_text = "%s: something's in there!" % spot.name if ready_now else "%s: back in a bit" % spot.name
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if ready_now else CURSOR_ARROW
	if _ready_now or digging:
		queue_redraw()


## Where your pet goes in, in the room's coordinates.
func dive_point() -> Vector2:
	return position + DIVE.get(spot.draw, size / 2.0)


func is_ready() -> bool:
	return _ready_now


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped.emit(self)
		accept_event()


func _draw() -> void:
	var shake := Vector2(sin(_time * 38.0) * 2.5, 0.0) if digging else Vector2.ZERO
	draw_set_transform(shake)
	match spot.draw:
		"dresser": _draw_dresser()
		"plant": _draw_plant()
		"socks": _draw_socks()
		"toybox": _draw_toybox()
	draw_set_transform(Vector2.ZERO)
	if digging:
		_draw_bits()
	elif _ready_now:
		_draw_twinkles()


func _fill(color: Color, amount: float) -> Color:
	var c := UiTheme.PAGE.lerp(color, amount)
	return c if _ready_now or digging else c.lerp(UiTheme.PAPER, 0.35)


func _line(color: Color) -> Color:
	return color if _ready_now or digging else Color(color, 0.55)


func _outline(points: PackedVector2Array, fill: Color, line: Color, width := 2.5) -> void:
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, line, width, true)


func _draw_dresser() -> void:
	var seam := _line(UiTheme.LILAC_SEAM)
	_outline(PackedVector2Array([Vector2(4, 4), Vector2(48, 1), Vector2(92, 4), Vector2(94, 82), Vector2(2, 82)]),
		_fill(UiTheme.LILAC, 0.22), seam)
	for y in [30.0, 56.0]:
		draw_line(Vector2(8, y), Vector2(88, y), seam, 2.0)
	for y in [17.0, 43.0, 69.0]:
		draw_circle(Vector2(48, y), 3.0, _line(UiTheme.LILAC))
	if digging:
		# the top drawer pulled out
		_outline(PackedVector2Array([Vector2(0, 10), Vector2(96, 10), Vector2(98, 30), Vector2(-2, 30)]),
			_fill(UiTheme.LILAC, 0.32), _line(UiTheme.LILAC))


func _draw_plant() -> void:
	var leaf := _fill(UiTheme.MINT, 0.3)
	var edge := _line(UiTheme.MINT)
	_outline(PackedVector2Array([Vector2(28, 84), Vector2(2, 34), Vector2(12, 2), Vector2(30, 40)]), leaf, edge, 2.2)
	_outline(PackedVector2Array([Vector2(40, 84), Vector2(44, 28), Vector2(70, 10), Vector2(62, 56)]), leaf, edge, 2.2)
	_outline(PackedVector2Array([Vector2(34, 86), Vector2(30, 50), Vector2(44, 26), Vector2(46, 62)]), leaf, edge, 2.2)
	_outline(PackedVector2Array([Vector2(8, 84), Vector2(64, 84), Vector2(56, 122), Vector2(16, 122)]),
		_fill(UiTheme.PINK, 0.25), _line(UiTheme.PINK_SEAM))


func _draw_socks() -> void:
	_outline(PackedVector2Array([Vector2(2, 34), Vector2(6, 18), Vector2(26, 16), Vector2(50, 12), Vector2(64, 22), Vector2(72, 36), Vector2(44, 42), Vector2(14, 42)]),
		_fill(UiTheme.CYAN, 0.22), _line(UiTheme.CYAN), 2.2)
	_outline(PackedVector2Array([Vector2(20, 18), Vector2(34, 2), Vector2(52, 6), Vector2(58, 18), Vector2(42, 16), Vector2(28, 24)]),
		_fill(UiTheme.PINK, 0.22), _line(UiTheme.PINK), 2.2)
	draw_line(Vector2(14, 30), Vector2(50, 28), _line(UiTheme.LILAC_SEAM), 2.0)


func _draw_toybox() -> void:
	var gold := _line(UiTheme.GOLD)
	_outline(PackedVector2Array([Vector2(4, 14), Vector2(76, 12), Vector2(78, 60), Vector2(6, 62)]), _fill(UiTheme.GOLD, 0.18), gold)
	draw_arc(Vector2(24, 40), 8.0, 0.0, TAU, 16, _line(UiTheme.CYAN), 2.0, true)
	var tri := PackedVector2Array([Vector2(50, 30), Vector2(60, 48), Vector2(40, 48), Vector2(50, 30)])
	draw_polyline(tri, gold, 2.0, true)
	if digging:
		# the lid flipped open, leaning back
		_outline(PackedVector2Array([Vector2(2, 12), Vector2(10, -8), Vector2(84, -26), Vector2(78, -8)]), _fill(UiTheme.GOLD, 0.28), gold)
	else:
		_outline(PackedVector2Array([Vector2(0, 2), Vector2(80, 0), Vector2(82, 14), Vector2(2, 16)]), _fill(UiTheme.GOLD, 0.28), gold)


## Gold twinkles over the top: something's in there.
func _draw_twinkles() -> void:
	for i in 3:
		var at := Vector2(size.x * [0.14, 0.86, 0.5][i], size.y * [0.0, 0.2, -0.16][i])
		var t := 0.5 + 0.5 * sin(_time * 4.4 + i * 2.1)
		var r := 3.0 + 5.0 * t
		var c := Color(UiTheme.GOLD, 0.3 + 0.7 * t)
		draw_line(at - Vector2(r, 0), at + Vector2(r, 0), c, 2.0)
		draw_line(at - Vector2(0, r), at + Vector2(0, r), c, 2.0)


## Bits flying up out of it while your pet digs.
func _draw_bits() -> void:
	var from := DIVE.get(spot.draw, size / 2.0) as Vector2
	var colors := [UiTheme.CYAN, UiTheme.PINK, UiTheme.LILAC, UiTheme.GOLD]
	for i in 4:
		var t := fmod(_time * 1.6 + i * 0.25, 1.0)
		var at := from + Vector2((i - 1.5) * 26.0 * t, -60.0 * t + 50.0 * t * t)
		draw_set_transform(at, t * 4.0 + i)
		draw_rect(Rect2(-4, -4, 8, 8), Color(colors[i], 1.0 - t))
	draw_set_transform(Vector2.ZERO)
