class_name HoldSpot
extends Button
## A held landing on the well (every 10th landing the army has cleared, see Dungeon.hold_need): the
## crowd of pets holding it, posed by the band (around the rope at the bottom of the well, beside the
## propped-open door in the cellar, sitting on the stairs further down), and a coral count pill right of
## the shaft ('N' when it's fully held, a dashed 'N/M' while it fills; at the cellar's landing the pill
## sits just under the landing once the sewing room's door is there, clear of it; a pill too wide for
## the gap right of the shaft slides left, under the landing, and stays inside the column). WellColumn places one per landing that can
## be held; a tap opens its card in the dungeon page's side column.
## Design: lanes/mockups2 design/mockups/screens/well-additions.html (look A, held landings).

const SPRITE := Vector2(16, 18)
const STEP := 9.0
const PILL_H := 14.0
const FONT := 10

var landing := 0
var picked := false
var _kind := "stairs"
var _n := 0
var _need := 1
var _looks: Array[Texture2D] = []
var _spots: Array = []  # [top-left in the spot, flipped, look index], back first
var _crowd := Rect2()  # the crowd's box, in the spot
var _pill := Rect2()  # the pill's box, in the spot
var _door := Vector2(-1, -1)  # the propped-open door's bottom left, in the spot (the cellar)
var _door_h := 13.0


func _init() -> void:
	focus_mode = FOCUS_NONE
	flat = true
	text = ""
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	texture_filter = TEXTURE_FILTER_NEAREST
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)


## Lays the spot out on landing `f` from the well's geometry `geo` (in the column): y (the landing),
## y0 (the landing above), l / r (the shaft's walls), cx, dip (how far a rope floor sags), kind
## (rope, doors, stairs), door_x (the cellar floor's door, -1 if none), sew_door (the sewing room's door
## is on this landing). `faces`: Pets for the crowd.
func setup(f: int, n: int, need: int, faces: Array, shown: int, geo: Dictionary) -> void:
	landing = f
	_n = n
	_need = maxi(1, need)
	_kind = str(geo.kind)
	_looks.clear()
	for pet in faces:
		if pet is Pet:
			_looks.append(PetLook.texture_for(pet.parts, false, pet.sewn))
	if _looks.is_empty():
		shown = 0
	var spots := _lay(shown, geo)  # in the column
	var y: float = geo.y
	var r: float = geo.r
	# the pill: right of the shaft, on the landing; just under it when the sewing room's door is there
	# (tucked up to the landing, the next floor's word nudges down under it, see WellColumn)
	var font := _font()
	var w := font.get_string_size(_pill_text(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x + 12.0
	var pill := Rect2(Vector2(r + 5.0, y + 1.0 if geo.get("sew_door", false) else y - 8.0), Vector2(w, PILL_H))
	# (kept inside the column: slid left when it's too wide for the gap, and dropped just under the
	# landing, clear of its floor line, when it has to reach back over the shaft's wall)
	var right := float(geo.get("w", 0.0)) - 2.0
	if right <= r:  # (no width yet)
		right = INF
	if pill.end.x > right:
		pill.position.x = maxf(float(geo.l), right - w)
		if pill.position.x < r + 2.0:
			pill.position.y = y + 1.0
	var box := pill
	var crowd := Rect2()
	for s in spots:
		var sr := Rect2(s[0], SPRITE)
		crowd = sr if not crowd.has_area() else crowd.merge(sr)
	var door := Vector2(-1, -1)
	if _kind == "doors" and float(geo.get("door_x", -1.0)) >= 0.0 and n >= _need:
		door = Vector2(float(geo.door_x), y)
		_door_h = float(geo.get("door_h", 13.0))
		var dr := Rect2(door + Vector2(-6.0, -_door_h), Vector2(16.0, _door_h))
		crowd = dr if not crowd.has_area() else crowd.merge(dr)
	if crowd.has_area():
		box = box.merge(crowd)
	position = box.position.floor()
	size = (box.size + Vector2(2, 2)).ceil()
	custom_minimum_size = size
	var off := position
	_pill = Rect2(pill.position - off, pill.size)
	_crowd = Rect2(crowd.position - off, crowd.size) if crowd.has_area() else Rect2()
	_door = door - off if door.x >= 0.0 else Vector2(-1, -1)
	_spots = spots.map(func(s): return [s[0] - off, s[1], s[2]])
	queue_redraw()


## Where the crowd's tiny pets sit (in the column), back first: [top-left, flipped, look index].
func _lay(shown: int, geo: Dictionary) -> Array:
	var out: Array = []
	if shown <= 0:
		return out
	var y: float = geo.y
	var l: float = geo.l
	var r: float = geo.r
	var cx: float = geo.cx
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + landing
	match _kind:
		"rope":  # around the rope's end, on the sagging rope floor: 5 in front, 4 behind
			var dip: float = geo.get("dip", 8.0)
			var rows := [[0, 5, 0.0], [1, 4, -6.0]]
			var k := 0
			for row in rows:
				var m := mini(int(row[1]), shown - k)
				if m <= 0:
					break
				for i in m:
					var x := cx - (m - 1) * STEP / 2.0 + i * STEP
					var t := clampf((x - l) / maxf(1.0, r - l), 0.0, 1.0)
					var sag := (y - 1.0) + 2.0 * t * (1.0 - t) * (dip + 1.0)
					out.append([Vector2(x - SPRITE.x / 2.0 + rng.randf_range(-1, 1), sag - SPRITE.y + 3.0 + float(row[2])).round(), rng.randf() < 0.5, k, int(row[0])])
					k += 1
		"doors":  # beside the door, right to left, two rows
			var gap := 8.0 if _n >= _need else 3.0  # (room for the door swung open once it's held)
			var right: float = (float(geo.door_x) - gap) if float(geo.get("door_x", -1.0)) >= 0.0 else r - 4.0
			var per := maxi(1, floori((right - (l + 3.0) - SPRITE.x) / STEP) + 1)
			var k := 0
			for row in 2:
				var m := mini(per - row, shown - k)
				if m <= 0:
					break
				for i in m:
					var x := right - SPRITE.x - i * STEP - row * STEP / 2.0
					out.append([Vector2(x + rng.randf_range(-1, 1), y - SPRITE.y - row * 6.0 - rng.randf()).round(), rng.randf() < 0.5, k, row])
					k += 1
		_:  # sitting on the stairs down to the landing and the first step of the next: the bottom first
			var y0: float = geo.y0
			var down_right: bool = geo.get("down_right", true)
			var xs := l + 4.0 if down_right else r - 4.0
			var xe := r - 4.0 if down_right else l + 4.0
			var dx := (xe - xs) / 4.0
			var dy := (y - y0) / 4.0
			var treads: Array = []  # [middle x, y], the bottom first
			treads.append([xe - dx * 0.5, y])  # the landing (the next floor's first step goes back the other way)
			for i in range(3, -1, -1):
				treads.append([xs + (i + 0.5) * dx, y0 + i * dy])
			var k := 0
			for layer in 3:
				for t in treads:
					if k >= shown:
						break
					var x: float = float(t[0]) + (layer - 1) * 4.0 * signf(dx)
					out.append([Vector2(x - SPRITE.x / 2.0, float(t[1]) - SPRITE.y + 1.0 - layer * 3.0).round(), rng.randf() < 0.5, k, layer])
					k += 1
	# the back rows first (higher up first on the stairs), so the front ones sit on top
	out.sort_custom(func(a, b): return a[3] > b[3] if a[3] != b[3] else a[0].y < b[0].y)
	return out.map(func(s): return [s[0], s[1], int(s[2]) % _looks.size()])


func _pill_text() -> String:
	return short(_n) if _n >= _need else "%s/%s" % [short(_n), short(_need)]


## A count as short as it goes (500, 3.1k, 24k, 1.2M): for the pills and the hold card's meter.
static func short(n: int) -> String:
	if n < 1000:
		return str(n)
	var units := ["k", "M", "B", "T"]
	var v := float(n)
	for u in units:
		v /= 1000.0
		if v < 1000.0:
			return str(snappedf(v, 0.1) if v < 100.0 else roundf(v)).trim_suffix(".0") + u
	return UiTheme.num(n)


## The pill's bottom edge, in the column.
func pill_bottom() -> float:
	return position.y + _pill.end.y


func _font() -> Font:
	return UiTheme.BODY_FONT if UiTheme.BODY_FONT else get_theme_default_font()


func _has_point(point: Vector2) -> bool:
	return _pill.grow(3.0).has_point(point) or (_crowd.has_area() and _crowd.grow(2.0).has_point(point))


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
		queue_redraw()


func _draw() -> void:
	if _door.x >= 0.0:
		_propped_door()
	for s in _spots:
		if s[1]:  # flipped: mirrored in place (a rect with a negative width lands a sprite's width off)
			draw_set_transform(s[0] + Vector2(SPRITE.x, 0), 0.0, Vector2(-1, 1))
			draw_texture_rect(_looks[s[2]], Rect2(Vector2.ZERO, SPRITE), false)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_texture_rect(_looks[s[2]], Rect2(s[0], SPRITE), false)
	# the count pill: coral when it's held, dashed lilac while it fills
	var full := _n >= _need
	var hot := is_hovered() or picked
	var pts := _capsule(_pill)
	draw_colored_polygon(pts, UiTheme.DEEP)
	if full:
		var edge := UiTheme.WISP if hot else UiTheme.WISP.lerp(UiTheme.LINE, 0.4)
		pts.append(pts[0])
		draw_polyline(pts, edge, 2.0, true)
	else:
		pts.append(pts[0])
		_dashed(pts, UiTheme.PINK if hot else UiTheme.LILAC_SEAM, 1.8)
	var font := _font()
	var t := _pill_text()
	var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT).x
	var base := _pill.position + Vector2((_pill.size.x - tw) / 2.0, _pill.size.y / 2.0 + FONT * 0.36)
	draw_string(font, base.round(), t, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, UiTheme.WISP if full else UiTheme.TEXT)


## The cellar landing's door, propped wide open: a dark doorway and the door swung back against the wall.
func _propped_door() -> void:
	var dw := 9.0
	var at := _door
	var r := dw / 2.0
	var arch := PackedVector2Array([at, at + Vector2(0, -_door_h + r)])
	for i in range(1, 8):
		var a := PI + PI * i / 8.0
		arch.append(at + Vector2(r, -_door_h + r) + Vector2(cos(a), sin(a)) * r)
	arch.append(at + Vector2(dw, -_door_h + r))
	arch.append(at + Vector2(dw, 0))
	draw_colored_polygon(arch, UiTheme.DEEP.darkened(0.45))
	arch.append(at)
	draw_polyline(arch, UiTheme.LILAC, 1.7, true)
	# the door itself, swung open towards us (a narrow slanted leaf on its hinge)
	var leaf := PackedVector2Array([at, at + Vector2(0, -_door_h + 2.0), at + Vector2(-5.0, -_door_h + 4.0), at + Vector2(-5.0, 1.5)])
	draw_colored_polygon(leaf, UiTheme.RAISED)
	leaf.append(leaf[0])
	draw_polyline(leaf, UiTheme.LILAC, 1.5, true)


## A rounded pill's outline.
func _capsule(rect: Rect2) -> PackedVector2Array:
	var rad := rect.size.y / 2.0
	var out := PackedVector2Array()
	var lc := rect.position + Vector2(rad, rad)
	var rc := rect.position + Vector2(rect.size.x - rad, rad)
	for i in 9:
		var a := -PI / 2.0 + PI * i / 8.0
		out.append(rc + Vector2(cos(a), sin(a)) * rad)
	for i in 9:
		var a := PI / 2.0 + PI * i / 8.0
		out.append(lc + Vector2(cos(a), sin(a)) * rad)
	return out


## A dashed line along points (3 on, 3 off).
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
