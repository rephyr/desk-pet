class_name StreetPage
extends RefCounted
## Next door's page of the map ("layout": "street" in data/unlocks.json): a row of back gardens at
## night, drawn by your pet in crayon. A house back along the top for every garden, its windows are
## the garden's lights (one goes dark per visit, see Ours); picket fences between the gardens; our
## own fence along the bottom with their gate in it, and one path in through the gate with a spur up
## into each garden. A garden that's ours is coloured in with your pet's own colour and gets a
## flag on its roof and a flower where the locals' trace was. A garden nobody has found yet is just
## its lit house. MapView hands the page's drawing, clicking and walking pets over to this.
## Everything is laid out on a 546 x 480 sheet (as the mockup), fitted into the map.

const SHEET := Vector2(546, 480)
const PEAKS := [8, 0, 12, 4, 10]  # each house's roof a little different
const PATH_Y := 384.0  # the path along the bottom of the gardens
const FENCE_Y := 430.0  # our fence
const GARDEN_Y := 244.0  # height of a garden's doodle (it sits in its column's middle)
const WINDOW := 11.0


## Where the sheet sits in a map of this size: { k: scale, at: top left }.
static func fit(size: Vector2) -> Dictionary:
	var k := minf(size.x / SHEET.x, size.y / SHEET.y)
	return { "k": k, "at": (size - SHEET * k) / 2.0 }


## A column of the street: its left edge, width and middle (sheet units).
static func column(i: int) -> Dictionary:
	var x0 := 14.0 + i * 104.0
	return { "x0": x0, "w": 100.0, "xc": x0 + 50.0 }


## Whether a place sits in our fence (their gate) rather than in a garden.
static func in_fence(location: Dictionary) -> bool:
	return int(location.get("map", {}).get("y", 0)) >= 1


static func _col(location: Dictionary) -> int:
	return clampi(int(location.get("map", {}).get("x", 0)), 0, PEAKS.size() - 1)


## The middle of a place's doodle, on the sheet.
static func spot(location: Dictionary) -> Vector2:
	var c := column(_col(location))
	return Vector2(c.xc, FENCE_Y + 2.0) if in_fence(location) else Vector2(c.xc, GARDEN_Y)


## What counts as clicking a place, on the sheet: its whole garden, or round the gate.
static func hit_rect(location: Dictionary) -> Rect2:
	var c := column(_col(location))
	if in_fence(location):
		return Rect2(c.xc - 50.0, 400.0, 100.0, 72.0)
	return Rect2(c.x0, 50.0, c.w, 330.0)


## The way a trip walks, on the sheet: in through the gate, along the path, up into its garden.
static func route(location: Dictionary, gate: Dictionary) -> Array[Vector2]:
	var gx: float = column(_col(gate)).xc if not gate.is_empty() else column(2).xc
	var out: Array[Vector2] = [Vector2(gx, 446), Vector2(gx, PATH_Y)]
	if not in_fence(location):
		var xc: float = column(_col(location)).xc
		out.append(Vector2(xc, PATH_Y))
		out.append(Vector2(xc, 300))
	return out


## A point `t` (0..1) of the way along a route.
static func along(points: Array[Vector2], t: float) -> Vector2:
	var total := 0.0
	for i in range(1, points.size()):
		total += points[i - 1].distance_to(points[i])
	var left := clampf(t, 0.0, 1.0) * total
	for i in range(1, points.size()):
		var d := points[i - 1].distance_to(points[i])
		if left <= d or i == points.size() - 1:
			return points[i - 1].lerp(points[i], clampf(left / maxf(d, 0.001), 0.0, 1.0))
		left -= d
	return points[0]


# ---- night colours (made from the theme's roles, like the mockup) -------------------

static func night() -> Color:
	return UiTheme.LILAC.lerp(UiTheme.CYAN, 0.28)


static func night2() -> Color:
	return UiTheme.CYAN.lerp(UiTheme.LILAC, 0.28)


static func lamp() -> Color:
	return UiTheme.GOLD.lerp(UiTheme.PINK, 0.18)


static func off() -> Color:
	return UiTheme.MUTED_SEAM


static func paper() -> Color:
	return UiTheme.PAPER.lerp(UiTheme.DEEP, 0.45)


static func doodle_color(doodle: String) -> Color:
	return night2() if doodle in ["greenhouse", "pond"] else night()


# ---- drawing ---------------------------------------------------------------------

## Draws the whole street onto the map. `nodes` are the map's places on this page ({ id, kind:
## open / spotted / unknown, location }), `pet_color` your pet's crayon, `selected` / `hover` ids,
## `grow` how far your pet has got colouring in a place that just became ours (id -> 0..1; MapView
## keeps the timing, anything not in it is fully coloured).
static func draw(ci: CanvasItem, fit_: Dictionary, nodes: Array, pet_color: Color, selected: String, hover: String, grow := {}) -> void:
	var k: float = fit_.k
	var o: Vector2 = fit_.at
	var T := func(v: Vector2) -> Vector2: return o + v * k
	_stars(ci, T, k)
	_moon(ci, T.call(Vector2(222, 56)), k)
	var gate := {}
	for n in nodes:
		if in_fence(n.location):
			gate = n
	var gx: float = column(_col(gate.location)).xc if not gate.is_empty() else column(2).xc
	# the path: in through their gate, along the bottom, a spur up into each garden found so far
	var road := Color(lamp(), 0.45)
	var found: Array[int] = [_col(gate.location) if not gate.is_empty() else 2]
	for n in nodes:
		if n.kind != "unknown" and not in_fence(n.location):
			found.append(_col(n.location))
			_dashed(ci, T.call(Vector2(column(_col(n.location)).xc, PATH_Y)), T.call(Vector2(column(_col(n.location)).xc, 318)), road)
	_dashed(ci, T.call(Vector2(gx, 424)), T.call(Vector2(gx, PATH_Y)), road)
	_dashed(ci, T.call(Vector2(column(found.min()).xc, PATH_Y)), T.call(Vector2(column(found.max()).xc, PATH_Y)), road)
	# picket fences between the gardens, with a gap where the path goes through
	for i in range(1, PEAKS.size()):
		var x: float = column(i).x0 - 2.0
		for y in range(160, 410, 12):
			if absf(y - PATH_Y) < 18.0:
				continue
			ci.draw_line(T.call(Vector2(x, y + 5)), T.call(Vector2(x, y - 5)), Color(off(), 0.6), 2.0 * k, true)
	_our_fence(ci, T, k, gx)
	var by_col := {}
	for n in nodes:
		if not in_fence(n.location):
			by_col[_col(n.location)] = n
	for i in PEAKS.size():
		if by_col.has(i):
			_garden(ci, T, k, i, by_col[i], pet_color, selected, hover, float(grow.get(by_col[i].id, 1.0)))
	if not gate.is_empty():
		_gate(ci, T, k, gate, pet_color, selected, hover, float(grow.get(gate.id, 1.0)))


## One garden: its house (windows = lights), and, once found, what's in it.
static func _garden(ci: CanvasItem, T: Callable, k: float, i: int, node: Dictionary, pet_color: Color, selected: String, hover: String, grow: float) -> void:
	var location: Dictionary = node.location
	var c := column(i)
	var x0: float = c.x0
	var w: float = c.w
	var xc: float = c.xc
	var peak: float = 58.0 + PEAKS[i]
	var seed := hash(node.id)
	var id: String = node.id
	var ours: bool = node.kind == "open" and GameState.is_ours(id)
	grow = grow if ours else 1.0
	# the house back
	Crayon.line(ci, [T.call(Vector2(x0 + 3, 96)), T.call(Vector2(xc, peak)), T.call(Vector2(x0 + w - 3, 96))], night(), 3.0 * k, seed)
	Crayon.line(ci, [T.call(Vector2(x0 + 9, 92)), T.call(Vector2(x0 + 9, 152))], night(), 3.0 * k, seed + 1)
	Crayon.line(ci, [T.call(Vector2(x0 + w - 9, 92)), T.call(Vector2(x0 + w - 9, 152))], night(), 3.0 * k, seed + 2)
	if i % 2 == 0:  # a chimney
		Crayon.line(ci, [T.call(Vector2(xc + 22, peak + 18)), T.call(Vector2(xc + 22, peak + 4)), T.call(Vector2(xc + 31, peak + 4)),
			T.call(Vector2(xc + 31, peak + 26))], night(), 2.0 * k, seed + 3)
	# its windows: the lights, lit ones first
	var lights := Ours.lights(location)
	var on := GameState.lights_left(id) if node.kind == "open" else lights
	var cols := ceili(lights / 2.0)
	for n in lights:
		var row := 0 if n < cols else 1
		var in_row := cols if row == 0 else lights - cols
		var at_ := n if row == 0 else n - cols
		var rw := in_row * WINDOW + (in_row - 1) * 6.0
		window(ci, T.call(Vector2(xc - rw / 2.0 + at_ * (WINDOW + 6.0), 104.0 + row * 20.0)), WINDOW * k, n < on)
	if ours and grow >= 1.0:
		_flag(ci, T.call(Vector2(xc, peak)), k, pet_color, seed + 4)
	if node.kind == "unknown":
		return  # nobody has found it yet: just its lit house
	# the garden
	if ours:
		scribble(ci, func(_y): return [T.call(Vector2(x0 + 6, 0)).x, T.call(Vector2(x0 + w - 6, 0)).x],
			T.call(Vector2(0, 162)).y, T.call(Vector2(0, 372)).y, 10, grow, pet_color)
	var at: Vector2 = T.call(Vector2(xc, GARDEN_Y))
	if id == selected or id == hover:
		Crayon.circle(ci, at, 42.0 * k, Vector2(1.0, 0.95), UiTheme.PINK if id == selected else Color(UiTheme.PINK, 0.5), 2.6, seed + 5)
	var doodle := str(location.map.get("doodle", "house"))
	var color := pet_color if ours else doodle_color(doodle)
	if node.kind == "spotted":
		color.a = 0.45
	var body := UiTheme.BODY_FONT
	var title := UiTheme.DISPLAY_FONT
	var note := str(location.map.get("note", ""))
	if node.kind == "open" and note != "":
		_centred(ci, body, T.call(Vector2(xc, 198)), note, int(12 * k), UiTheme.GOLD)
	Crayon.doodle(ci, doodle, at, k, color, seed)
	var lines := name_lines(str(location.name))
	for j in lines.size():
		_centred(ci, title, T.call(Vector2(xc, 298 + j * 15)), lines[j], int(13 * k), Color(color, 1.0) if node.kind == "open" else UiTheme.MUTED)
	if node.kind == "spotted":
		_centred(ci, body, T.call(Vector2(xc, 298 + lines.size() * 15 + 4)), "tap to go!", int(12 * k), UiTheme.PINK)
		return
	var trace := str(location.map.get("trace", ""))
	if ours:
		Crayon.doodle(ci, "flower", T.call(Vector2(x0 + 22, 352)), k, pet_color, seed + 6)
	elif trace != "":
		Crayon.doodle(ci, trace, T.call(Vector2(x0 + 24, 352)), k, UiTheme.MUTED, seed + 6)


## Their gate, in our fence.
static func _gate(ci: CanvasItem, T: Callable, k: float, node: Dictionary, pet_color: Color, selected: String, hover: String, grow: float) -> void:
	var gx: float = column(_col(node.location)).xc
	var id: String = node.id
	var ours: bool = node.kind == "open" and GameState.is_ours(id)
	grow = grow if ours else 1.0
	var color := pet_color if ours else night()
	if ours:
		scribble(ci, func(_y): return [T.call(Vector2(gx - 20, 0)).x, T.call(Vector2(gx + 20, 0)).x],
			T.call(Vector2(0, 420)).y, T.call(Vector2(0, 446)).y, 3, grow, pet_color)
	var at: Vector2 = T.call(Vector2(gx, FENCE_Y + 2))
	if id == selected or id == hover:
		Crayon.circle(ci, at, 32.0 * k, Vector2(1.0, 0.8), UiTheme.PINK if id == selected else Color(UiTheme.PINK, 0.5), 2.6, hash(id) + 5)
	Crayon.doodle(ci, "gate", at, 0.85 * k, color, hash(id))
	_centred(ci, UiTheme.DISPLAY_FONT, T.call(Vector2(gx, 466)), str(node.location.name), int(13 * k), color)


## A crayon colouring-in: zigzag bands from the bottom up between y0 and y1, `half(y)` giving the
## [left, right] edges at a height. `grow` (0..1) is how much of it is coloured so far.
static func scribble(ci: CanvasItem, half: Callable, y0: float, y1: float, bands: int, grow: float, color: Color) -> void:
	var bh := (y1 - y0) / bands
	var shown := grow * bands
	var tint := Color(color, 0.28 if UiTheme.DARK else 0.34)
	for b in bands:
		if b >= shown:
			break
		var bot := y1 - b * bh
		var top := bot - bh - 2.0
		var edges: Array = half.call((top + bot) / 2.0)
		var l := float(edges[0])
		var r := float(edges[1])
		if r - l < 4.0:
			continue
		var right := lerpf(l, r, clampf(shown - b, 0.0, 1.0))  # the band being coloured right now
		var points := PackedVector2Array()
		var x := l
		var i := 0
		while x <= right:
			points.append(Vector2(x, top if i % 2 == 1 else bot))
			x += 7.0
			i += 1
		if points.size() >= 2:
			ci.draw_polyline(points, tint, 3.2, true)


## One little window of a house: lit (a light is on) or gone dark. `at` is its top left.
static func window(ci: CanvasItem, at: Vector2, s: float, lit: bool) -> void:
	var h := roundf(s * 1.25)
	var r := Rect2(at - Vector2(0, h - s), Vector2(s, h))
	ci.draw_rect(r, lamp() if lit else (UiTheme.DEEP if UiTheme.DARK else UiTheme.MUTED_SEAM))  # dark windows stay dark on a light theme
	ci.draw_rect(r, lamp() if lit else off(), false, 1.6)
	var bar := paper() if lit else off()
	ci.draw_line(Vector2(r.get_center().x, r.position.y + 1.5), Vector2(r.get_center().x, r.end.y - 1.5), bar, 1.0)
	ci.draw_line(Vector2(r.position.x + 1.5, r.position.y + h * 0.45), Vector2(r.end.x - 1.5, r.position.y + h * 0.45), bar, 1.0)


## A little flag on a roof (the place is ours), in your pet's colour.
static func _flag(ci: CanvasItem, at: Vector2, k: float, color: Color, seed: int) -> void:
	Crayon.line(ci, [at, at + Vector2(0, -16) * k], color, 2.0, seed)
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -16) * k, at + Vector2(12, -12) * k, at + Vector2(0, -8) * k]), color)


## A small flag by a doodle on the other pages (a backyard place that's ours).
static func small_flag(ci: CanvasItem, at: Vector2, k: float, color: Color, seed: int) -> void:
	_flag(ci, at, k * 0.8, color, seed)


static func _our_fence(ci: CanvasItem, T: Callable, k: float, gx: float) -> void:
	var y := FENCE_Y
	for x in range(10, 540, 13):
		if absf(x - gx) <= 30.0:
			continue
		var pts := PackedVector2Array()
		for p in [Vector2(x, y + 12), Vector2(x, y - 1), Vector2(x + 2, y - 5), Vector2(x + 4, y - 1), Vector2(x + 4, y + 12)]:
			pts.append(T.call(p))
		ci.draw_polyline(pts, off(), 2.2 * k, true)
	for seg in [[6.0, gx - 30.0], [gx + 30.0, 540.0]]:
		ci.draw_line(T.call(Vector2(seg[0], y + 4)), T.call(Vector2(seg[1], y + 4)), Color(off(), 0.7), 2.2 * k, true)


static func _stars(ci: CanvasItem, T: Callable, k: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 26:
		var p := Vector2(rng.randf() * 540.0, 46.0 + rng.randf() * 400.0)
		ci.draw_circle(T.call(p), (0.7 + rng.randf() * 0.7) * k, Color(UiTheme.LILAC, 0.15 + rng.randf() * 0.3))


static func _moon(ci: CanvasItem, at: Vector2, k: float) -> void:
	var pts: Array = Crayon.bend(at + Vector2(4, -11) * k, at + Vector2(-12, -8) * k, at + Vector2(-9, 5) * k)
	pts.append_array(Crayon.bend(at + Vector2(-9, 5) * k, at + Vector2(-4, 13) * k, at + Vector2(7, 9) * k))
	pts.append_array(Crayon.bend(at + Vector2(7, 9) * k, at + Vector2(-5, 4) * k, at + Vector2(4, -11) * k))
	Crayon.line(ci, pts, Color(lamp(), 0.8), 2.0, 57)


static func _dashed(ci: CanvasItem, from: Vector2, to: Vector2, color: Color) -> void:
	var d := from.distance_to(to)
	var n := int(d / 14.0)
	for i in n + 1:
		var a := from.lerp(to, minf(1.0, i * 14.0 / maxf(d, 0.001)))
		var b := from.lerp(to, minf(1.0, (i * 14.0 + 7.0) / maxf(d, 0.001)))
		ci.draw_line(a, b, color, 2.5, true)


## A place's name over one or two lines (long names break at the first space, like the mockup).
static func name_lines(text: String) -> Array[String]:
	var out: Array[String] = []
	var space := text.find(" ")
	if text.length() > 12 and space > 0:
		out.append(text.substr(0, space))
		out.append(text.substr(space + 1))
	else:
		out.append(text)
	return out


static func _centred(ci: CanvasItem, font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	if font_size <= 0:
		return  # the street before it has a size (its first frame on screen)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	ci.draw_string(font, at - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
