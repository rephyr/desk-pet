class_name StitchBox
extends StyleBox
## A rounded box with a stitched outline: dashes instead of a solid border, like a patch sewn on.
## Used for the active tab, the chosen thing in a picker, and rewards (see UiTheme.stitched).

@export var bg_color := Color(0, 0, 0, 0)
@export var dash_color := Color.WHITE
@export var radius := 10.0
@export var width := 2.0
@export var dash := 6.0
@export var gap := 4.0


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	var r := minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var outline := _rounded(rect.grow(-width / 2.0), maxf(r - width / 2.0, 0.0))
	if bg_color.a > 0.0:
		RenderingServer.canvas_item_add_polygon(to_canvas_item, _rounded(rect, r), PackedColorArray([bg_color]))
	# walk the outline, drawing a dash, skipping a gap, and so on
	var on := true
	var left := dash
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var seg := a.distance_to(b)
		var t := 0.0
		while seg - t > 0.001:  # not t < seg: rounding can leave a sliver that never gets used up
			var step := minf(left, seg - t)
			if on:
				RenderingServer.canvas_item_add_line(to_canvas_item, a.lerp(b, t / seg), a.lerp(b, (t + step) / seg), dash_color, width, true)
			t += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap


## Points round a rounded rectangle, clockwise from the top left.
static func _rounded(rect: Rect2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(r, r), PI],
		[Vector2(rect.end.x - r, rect.position.y + r), PI * 1.5],
		[rect.end - Vector2(r, r), 0.0],
		[Vector2(rect.position.x + r, rect.end.y - r), PI * 0.5],
	]
	for c in corners:
		for s in 7:
			var ang: float = c[1] + (PI / 2.0) * s / 6.0
			pts.append(c[0] + Vector2(cos(ang), sin(ang)) * r)
	return pts
