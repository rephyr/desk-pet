class_name Crayon
extends RefCounted
## Crayon drawing onto any CanvasItem: wobbly lines drawn twice, circles, and the little doodle for
## each kind of place (the map, the postcard's stamp). Colours come from the player's theme.

const DOODLE_COLORS := {
	"house": "pink", "grass": "mint", "trees": "mint", "hill": "mint", "apple": "pink",
	"pond": "cyan", "stream": "cyan", "hut": "cyan", "well": "lilac", "door": "lilac", "stairs": "lilac",
	"fence": "lilac", "moon": "lilac",
}


## The colour a place's doodle is drawn in.
static func doodle_color(kind: String) -> Color:
	match str(DOODLE_COLORS.get(kind, "pink")):
		"mint":
			return UiTheme.MINT
		"cyan":
			return UiTheme.CYAN
		"lilac":
			return UiTheme.LILAC
	return UiTheme.PINK


static func peach() -> Color:
	return UiTheme.GOLD.lerp(UiTheme.PINK, 0.35)


## A wobbly crayon stroke: a couple of slightly offset passes, the same wobble every redraw.
static func line(ci: CanvasItem, points: Array, color: Color, width: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for pass_ in 2:
		var stroke := PackedVector2Array()
		for p in points:
			stroke.append(p + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 1.3)
		ci.draw_polyline(stroke, Color(color, color.a * (0.9 if pass_ == 0 else 0.45)), width * (1.0 if pass_ == 0 else 0.7), true)


## A wobbly crayon circle (squash makes it an oval).
static func circle(ci: CanvasItem, center: Vector2, radius: float, squash: Vector2, color: Color, width: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := []
	for i in 27:
		var a := TAU * i / 26.0
		points.append(center + Vector2(cos(a) * squash.x, sin(a) * squash.y) * radius * rng.randf_range(0.95, 1.05))
	line(ci, points, color, width, seed)


## The little drawing for each kind of place.
static func doodle(ci: CanvasItem, kind: String, at: Vector2, k: float, color: Color, seed: int) -> void:
	var s := 24.0 * k
	match kind:
		"house":
			line(ci, [at + Vector2(-s, s * 0.8), at + Vector2(-s, -s * 0.1), at + Vector2(0, -s), at + Vector2(s, -s * 0.1),
				at + Vector2(s, s * 0.8), at + Vector2(-s, s * 0.8)], color, 3.0, seed)
			line(ci, [at + Vector2(-s * 0.25, s * 0.8), at + Vector2(-s * 0.25, s * 0.25), at + Vector2(s * 0.25, s * 0.25),
				at + Vector2(s * 0.25, s * 0.8)], color, 2.0, seed + 1)
		"grass":
			for i in 6:
				var x := -s + i * s * 0.4
				line(ci, [at + Vector2(x, s * 0.6), at + Vector2(x + s * 0.12, 0), at + Vector2(x + s * 0.24, s * 0.6)], color, 2.0, seed + i)
			circle(ci, at + Vector2(-s * 0.4, -s * 0.2), s * 0.2, Vector2.ONE, UiTheme.PINK, 2.0, seed + 9)
			circle(ci, at + Vector2(s * 0.4, -s * 0.3), s * 0.18, Vector2.ONE, UiTheme.GOLD, 2.0, seed + 10)
		"trees":
			for i in 3:
				var x := (i - 1) * s * 0.8
				line(ci, [at + Vector2(x - s * 0.45, s * 0.5), at + Vector2(x, -s * 0.8), at + Vector2(x + s * 0.45, s * 0.5),
					at + Vector2(x - s * 0.45, s * 0.5)], color, 2.5, seed + i)
				line(ci, [at + Vector2(x, s * 0.5), at + Vector2(x, s * 0.85)], peach(), 2.0, seed + 5 + i)
		"hill":
			var points := []
			for i in 13:
				var a := PI * i / 12.0
				points.append(at + Vector2(-cos(a) * s * 1.2, s * 0.6 - sin(a) * s * 1.1))
			line(ci, points, color, 3.0, seed)
			line(ci, [at + Vector2(0, -s * 0.5), at + Vector2(0, -s * 1.2), at + Vector2(s * 0.5, -s * 1.0), at + Vector2(0, -s * 0.85)], UiTheme.PINK, 2.0, seed + 1)
		"apple":
			circle(ci, at, s * 0.7, Vector2(1.0, 0.9), color, 3.0, seed)
			line(ci, [at + Vector2(0, -s * 0.6), at + Vector2(s * 0.1, -s * 1.0)], peach(), 2.0, seed + 1)
			line(ci, [at + Vector2(s * 0.1, -s * 0.9), at + Vector2(s * 0.5, -s * 1.0), at + Vector2(s * 0.2, -s * 0.75)], UiTheme.MINT, 2.0, seed + 2)
		"pond":
			circle(ci, at + Vector2(0, s * 0.2), s * 1.1, Vector2(1.0, 0.45), color, 3.0, seed)
			line(ci, [at + Vector2(-s * 0.6, s * 0.25), at + Vector2(-s * 0.1, s * 0.15)], color, 1.5, seed + 1)
			circle(ci, at + Vector2(s * 0.3, -s * 0.05), s * 0.22, Vector2.ONE, UiTheme.GOLD, 2.0, seed + 2)
		"stream":
			for row in 3:
				var points := []
				for i in 9:
					points.append(at + Vector2(-s * 1.1 + i * s * 0.28, (row - 1) * s * 0.4 + sin(i * 1.3 + row) * s * 0.12))
				line(ci, points, color, 2.0, seed + row)
		"hut":
			line(ci, [at + Vector2(-s * 0.9, s * 0.8), at + Vector2(-s * 0.9, 0), at + Vector2(0, -s * 0.8), at + Vector2(s * 0.9, 0),
				at + Vector2(s * 0.9, s * 0.8), at + Vector2(-s * 0.9, s * 0.8)], color, 3.0, seed)
			line(ci, [at + Vector2(-s * 0.3, s * 0.1), at + Vector2(s * 0.3, s * 0.1), at + Vector2(s * 0.3, s * 0.5),
				at + Vector2(-s * 0.3, s * 0.5), at + Vector2(-s * 0.3, s * 0.1)], color, 2.0, seed + 1)
		"well":
			circle(ci, at + Vector2(0, s * 0.45), s * 0.8, Vector2(1.0, 0.35), color, 3.0, seed)
			line(ci, [at + Vector2(-s * 0.7, s * 0.4), at + Vector2(-s * 0.7, -s * 0.6), at + Vector2(0, -s), at + Vector2(s * 0.7, -s * 0.6),
				at + Vector2(s * 0.7, s * 0.4)], color, 2.5, seed + 1)
		"door":
			var points := [at + Vector2(-s * 0.6, s * 0.8)]
			for i in 9:
				var a := PI + PI * i / 8.0
				points.append(at + Vector2(cos(a) * s * 0.6, -s * 0.1 + sin(a) * s * 0.6))
			points.append(at + Vector2(s * 0.6, s * 0.8))
			line(ci, points, color, 3.0, seed)
			circle(ci, at + Vector2(s * 0.3, s * 0.3), s * 0.08, Vector2.ONE, UiTheme.GOLD, 2.0, seed + 1)
		"stairs":
			var points := []
			for i in 4:
				points.append(at + Vector2(-s + i * s * 0.55, -s * 0.6 + i * s * 0.45))
				points.append(at + Vector2(-s + (i + 1) * s * 0.55, -s * 0.6 + i * s * 0.45))
			line(ci, points, color, 3.0, seed)
		"fence":  # beyond the fence (the sunset box's stamp)
			for i in 3:
				var x := (i - 1) * s * 0.66
				line(ci, [at + Vector2(x - s * 0.22, s * 0.8), at + Vector2(x - s * 0.22, -s * 0.5), at + Vector2(x, -s * 0.8),
					at + Vector2(x + s * 0.22, -s * 0.5), at + Vector2(x + s * 0.22, s * 0.8)], color, 3.0, seed + i)
			for y in [-s * 0.1, s * 0.45]:
				line(ci, [at + Vector2(-s * 1.05, y), at + Vector2(s * 1.05, y - s * 0.03)], color, 2.0, seed + 7 + int(y))
		"moon":  # next door, at night (the midnight box's stamp)
			var points := []
			for i in 15:
				var a := deg_to_rad(50.0 + 260.0 * i / 14.0)
				points.append(at + Vector2(cos(a), sin(a)) * s * 0.8)
			for i in 15:
				var a := deg_to_rad(280.5 - 201.0 * i / 14.0)
				points.append(at + Vector2(s * 0.4, 0) + Vector2(cos(a), sin(a)) * s * 0.624)
			line(ci, points, color, 3.0, seed)
			circle(ci, at + Vector2(s * 0.75, -s * 0.55), s * 0.1, Vector2.ONE, UiTheme.GOLD, 2.0, seed + 1)
		_:
			circle(ci, at, s * 0.7, Vector2.ONE, color, 3.0, seed)
