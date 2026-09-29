class_name SewDoor
extends Button
## The sewing room's little pink door, cut through the well's right wall on floor 20 (WellColumn
## places it once the tiny key is found): a dashed tunnel, an arched pink door with a coral knob.
## Tap it and the column slides over to the rooms (DungeonView).
## Design: lanes/mockups2 design/mockups/screens/well-additions.html (the sewing room door).

const DOOR := Vector2(12, 17)
const PAD := Vector2(6, 6)  # the tap area around the door
var tunnel := 0.0  # how far left of the door the tunnel reaches (to the well's wall)


func _init() -> void:
	focus_mode = FOCUS_NONE
	flat = true
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)


## Puts the door with its bottom left corner at `at` (in the column), the wall `wall` px to its left.
func place(at: Vector2, wall: float) -> void:
	tunnel = wall
	custom_minimum_size = DOOR + PAD * 2.0 + Vector2(4, 0)
	size = custom_minimum_size
	position = at - Vector2(PAD.x, DOOR.y + PAD.y)
	queue_redraw()


func _draw() -> void:
	var base := Vector2(PAD.x, PAD.y + DOOR.y)  # the door's bottom left
	# the tunnel through the wall
	var t := PackedVector2Array([base + Vector2(-tunnel - 1.0, 0), base + Vector2(-tunnel - 1.0, -DOOR.y - 2.0),
		base + Vector2(DOOR.x + 4.0, -DOOR.y - 2.0), base + Vector2(DOOR.x + 4.0, 0)])
	draw_colored_polygon(t, UiTheme.DEEP)
	t.append(t[0])
	_dashed(t, UiTheme.LILAC_SEAM, 1.6)
	# the door: straight sides, a round top
	var r := DOOR.x / 2.0
	var pts := PackedVector2Array([base, base + Vector2(0, -DOOR.y + r)])
	for i in range(1, 12):
		var a := PI + PI * i / 12.0
		pts.append(base + Vector2(r, -DOOR.y + r) + Vector2(cos(a), sin(a)) * r)
	pts.append(base + Vector2(DOOR.x, -DOOR.y + r))
	pts.append(base + Vector2(DOOR.x, 0))
	var fill := UiTheme.PINK_PRESSED if is_hovered() else UiTheme.RAISED.lerp(UiTheme.PINK, 0.22)
	draw_colored_polygon(pts, fill)
	pts.append(pts[0])
	draw_polyline(pts, UiTheme.PINK, 1.8, true)
	draw_circle(base + Vector2(DOOR.x - 3.2, -6.0), 1.6, UiTheme.WISP)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()


func _dashed(points: PackedVector2Array, color: Color, width: float) -> void:
	var on := true
	var left := 3.0
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d := a.distance_to(b)
		var s := 0.0
		while s < d:
			var step := minf(left, d - s)
			if on:
				draw_line(a.lerp(b, s / d), a.lerp(b, (s + step) / d), color, width)
			s += step
			left -= step
			if left <= 0.001:
				on = not on
				left = 3.0
