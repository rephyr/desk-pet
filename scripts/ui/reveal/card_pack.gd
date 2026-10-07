class_name CardPack
extends Node2D
## Placeholder foil card pack, drawn from rectangles. You rip the strip off the top along the
## tear line; the pet then comes out of the opening. The origin is the middle of its bottom edge.
## `back` draws what is behind the pet (the pack's back sheet in the opening); this node draws
## the front of the pack and the strip. Real art replaces the drawing only; the controller only
## uses tear, pick_up(), grab/grabbing, throw_strip(), strip_gone, mouth(), rim_y() and back.

const U := 4  # one art pixel
const WIDTH := 30 * U
const HEIGHT := 42 * U
const STRIP := 7 * U  # the part that rips off
const CRIMP := 2 * U  # zigzag sealed edges
const STIFFNESS := 220.0  # the spring pulling the held point after your cursor
const DAMPING := 14.0
const DOG_EAR := 9.0  # how far a let-go flap stays folded (px)
const TEAR_EASE := 90.0  # px of over-pulling that tears one strip-length per second
const TEAR_MAX_SPEED := 1.2  # strip-lengths per second
const GRAVITY := 1400.0  # px/s² on the thrown strip
const THROW_MAX := 1100.0
const THROW_MIN_UP := 350.0
const SPIN := 4.0  # rad/s the thrown strip starts tumbling at
const FADE_TIME := 0.9

var FOIL := Color("6b4fa0")
var FOIL_LIGHT := Color("8e6fd0")
var FOIL_DARK := Color("3d2a63")
var EDGE := Color("c9a0ff")
const SHEEN := Color(1, 1, 1, 0.12)
var LOGO := Color("ff79c6")
const INSIDE := Color("0d0612")
const FOIL_BACK := Color("c8b8e8")  # the silvery inside of the foil, seen on a folded flap
const SHADOW := Color(0, 0, 0, 0.3)

## Colours the pack from a box's "art" in data/boxes.json (foil, foil_light, foil_dark, edge, logo).
func set_art(art: Dictionary) -> void:
	FOIL = Color(art.get("foil", "#6b4fa0"))
	FOIL_LIGHT = Color(art.get("foil_light", "#8e6fd0"))
	FOIL_DARK = Color(art.get("foil_dark", "#3d2a63"))
	EDGE = Color(art.get("edge", "#c9a0ff"))
	LOGO = Color(art.get("logo", "#ff79c6"))
	queue_redraw()
	back.queue_redraw()


## 0..1: how far along the tear line it's ripped.
var tear := 0.0:
	set(value):
		tear = value
		queue_redraw()
		back.queue_redraw()
## Which way you're ripping: 1 = left to right (the torn flap is on the left),
## -1 = right to left.
var direction := 1.0:
	set(value):
		direction = signf(value) if value != 0.0 else 1.0
		queue_redraw()
## Where the player's cursor is (local), while `grabbing`. The held point follows it.
var grab := Vector2.ZERO
var grabbing := false
## 0..1: the ripped-off strip fading out as it flies. 0 puts it back on the pack.
var strip_gone := 0.0:
	set(value):
		strip_gone = value
		if value == 0.0:
			_thrown = false
			_holding = false
			_fly = Vector2.ZERO
			_fly_velocity = Vector2.ZERO
			_spin = 0.0
		queue_redraw()

## The strip folds like paper: the point you picked up (_anchor) is carried to _held, which
## springs after the cursor, and the strip folds along the line halfway between them. Where
## that fold crosses the tear line decides how far it's torn.
var _holding := false
var _anchor := Vector2.ZERO
var _held := Vector2.ZERO
var _held_velocity := Vector2.ZERO
var _thrown := false
var _thrown_shapes: Array = []  # [points, colors] pairs, frozen when the strip comes off
var _thrown_center := Vector2.ZERO
var _fly := Vector2.ZERO  # how far the thrown strip has flown
var _fly_velocity := Vector2.ZERO
var _spin := 0.0
var _spin_velocity := 0.0

## Drawn behind the pet: see the class notes.
var back := Node2D.new()


## Picks the strip up at `point` (local; clamped onto the strip). While nothing is torn yet,
## the end you grab is the end that peels.
func pick_up(point: Vector2) -> void:
	var top := rim_y() - STRIP + CRIMP
	var at := Vector2(clampf(point.x, -WIDTH / 2.0, WIDTH / 2.0), clampf(point.y, top, rim_y()))
	if tear <= 0.0:
		direction = 1.0 if at.x < 0.0 else -1.0
	if _holding:
		# keep the current fold: carry on from where the old held point is now
		at = _anchor
	else:
		_held = at
		_held_velocity = Vector2.ZERO
	_anchor = at
	_holding = true
	grab = point
	grabbing = true


## Tears the strip off and throws it with `velocity` (px/s); it tumbles away and fades.
func throw_strip(velocity: Vector2) -> void:
	_thrown_shapes = _strip_shapes()
	var box := Rect2(Vector2(-WIDTH / 2.0, rim_y() - STRIP), Vector2(WIDTH, STRIP))
	for shape in _thrown_shapes:
		for q in shape[0]:
			box = box.expand(q)
	_thrown_center = box.get_center()
	tear = 1.0
	grabbing = false
	_thrown = true
	_fly_velocity = velocity.limit_length(THROW_MAX)
	_fly_velocity.y = minf(_fly_velocity.y, -THROW_MIN_UP)
	_spin_velocity = SPIN * signf(_fly_velocity.x if _fly_velocity.x != 0.0 else direction)


func _init() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	back.texture_filter = TEXTURE_FILTER_NEAREST
	back.draw.connect(_draw_back)


## The tear line: anything inside the pack is hidden below it.
static func rim_y() -> float:
	return -HEIGHT + STRIP


## Where the light comes out.
static func mouth() -> Vector2:
	return Vector2(0, rim_y())


func _draw_back() -> void:
	if tear <= 0.0:
		return
	# the back sheet's edge, seen through the opening
	back.draw_rect(Rect2(-WIDTH / 2.0 + U, rim_y() - U * 2, WIDTH - U * 2, U * 2), FOIL_DARK)
	back.draw_rect(Rect2(-WIDTH / 2.0 + U * 2, rim_y() - U, WIDTH - U * 4, U), INSIDE)


func _draw() -> void:
	var top := rim_y()
	# body
	draw_rect(Rect2(-WIDTH / 2.0, top, WIDTH, HEIGHT - STRIP - CRIMP), FOIL)
	draw_rect(Rect2(-WIDTH / 2.0, top, U, HEIGHT - STRIP - CRIMP), FOIL_LIGHT)
	draw_rect(Rect2(WIDTH / 2.0 - U, top, U, HEIGHT - STRIP - CRIMP), FOIL_DARK)
	# diagonal foil sheen
	for i in 3:
		var y := top + U * (6 + i * 9)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-WIDTH / 2.0, y + U * 6), Vector2(-WIDTH / 2.0, y + U * 8),
			Vector2(WIDTH / 2.0, y - U * 2), Vector2(WIDTH / 2.0, y - U * 4)]), SHEEN)
	_draw_logo(Vector2(0, top + (HEIGHT - STRIP) * 0.45))
	_crimp(-CRIMP, 1.0)  # bottom seal
	# where it's ripped: a jagged dark gap growing from the side you started on
	if tear > 0.0 and strip_gone < 1.0:
		var torn := WIDTH * tear
		for i in int(torn / U):
			var h := U if i % 2 == 0 else U * 2
			var x := -WIDTH / 2.0 + i * U if direction > 0.0 else WIDTH / 2.0 - (i + 1) * U
			draw_rect(Rect2(x, top - h / 2.0, U, h), INSIDE)
	_draw_strip()
	if tear <= 0.0 and not _holding:
		# dotted tear line, and a notch at both ends showing where to start
		for i in range(1, int(WIDTH / (U * 2))):
			draw_rect(Rect2(-WIDTH / 2.0 + i * U * 2, rim_y() - U / 2.0, U, U / 2.0), Color(EDGE, 0.8))
		for side in [-1.0, 1.0]:
			var x: float = WIDTH / 2.0 * side
			draw_colored_polygon(PackedVector2Array([Vector2(x, rim_y() - U), Vector2(x - U * 2 * side, rim_y()),
				Vector2(x, rim_y() + U)]), INSIDE)


func _process(delta: float) -> void:
	if strip_gone >= 1.0:
		return
	if _thrown:
		_fly_velocity.y += GRAVITY * delta
		_fly += _fly_velocity * delta
		_spin += _spin_velocity * delta
		strip_gone = minf(1.0, strip_gone + delta / FADE_TIME)
		return
	if not _holding:
		return
	# let go: the flap flops back down but stays a little dog-eared
	var target := grab if grabbing else _anchor + Vector2(direction * DOG_EAR, DOG_EAR)
	_held_velocity += (STIFFNESS * (target - _held) - DAMPING * _held_velocity) * delta
	_held += _held_velocity * delta
	# pulling further than the paper reaches tears it, but only when you pull up or towards the
	# far end; pulling back the other way just pulls the flap taut
	var front := _tear_front()
	var over := target.distance_to(front) - _anchor.distance_to(front)
	if over > 0.0 and tear < 1.0:
		var pull := (target - front).normalized()
		var tearing := clampf(pull.x * direction - pull.y + 0.3, 0.0, 1.0)
		tear = minf(1.0, tear + minf(over * tearing / TEAR_EASE, TEAR_MAX_SPEED) * delta)
	# the strip is still stuck on from the tear front to the far end, so the fold can't cross
	# any of that: the held point can't get further from its corners than the paper reaches
	var far := WIDTH / 2.0 * direction
	var front_x := _tear_front().x
	var tip := rim_y() - STRIP
	for pass_ in 3:
		for stuck: Vector2 in [Vector2(front_x, rim_y()), Vector2(front_x, tip), Vector2(far, rim_y()), Vector2(far, tip)]:
			var reach := _anchor.distance_to(stuck)
			var out := _held - stuck
			if out.length() > reach:
				var normal := out.normalized()
				_held = stuck + normal * reach
				_held_velocity -= normal * maxf(0.0, _held_velocity.dot(normal))
	queue_redraw()


## Where the tear has got to along the tear line.
func _tear_front() -> Vector2:
	return Vector2((-WIDTH / 2.0 + WIDTH * tear) * direction, rim_y())


## The fold line, as a point on it and the normal pointing away from the picked-up side.
## Returns [] while there's no fold.
func _fold() -> Array:
	var pull := _held - _anchor
	if not _holding or pull.length() < 0.5:
		return []
	return [(_anchor + _held) / 2.0, pull.normalized()]


## The strip's two pieces of paper: the band and its crimped top.
func _strip_outlines() -> Array[PackedVector2Array]:
	var top := rim_y() - STRIP + CRIMP
	var band := PackedVector2Array([Vector2(-WIDTH / 2.0, rim_y()), Vector2(WIDTH / 2.0, rim_y()),
		Vector2(WIDTH / 2.0, top), Vector2(-WIDTH / 2.0, top)])
	var teeth := PackedVector2Array([Vector2(-WIDTH / 2.0, top + 1.0), Vector2(WIDTH / 2.0, top + 1.0)])
	var x := WIDTH / 2.0
	while x > -WIDTH / 2.0:
		teeth.append(Vector2(x, top))
		teeth.append(Vector2(x - CRIMP / 2.0, top - CRIMP))
		x -= CRIMP
	teeth.append(Vector2(-WIDTH / 2.0, top))
	return [band, teeth]


## The strip as [points, colors] shapes: the part that stays put, then the folded-over part
## (reflected across the fold, showing the foil's inside, bright along the crease) and its shadow.
func _strip_shapes() -> Array:
	var shapes := []
	var fronts := [FOIL_LIGHT, FOIL]
	var outlines := _strip_outlines()
	var fold := _fold()
	if fold.is_empty():
		for i in outlines.size():
			shapes.append([outlines[i], _flat(outlines[i].size(), fronts[i])])
		return shapes
	var mid: Vector2 = fold[0]
	var n: Vector2 = fold[1]
	var along := n.orthogonal() * 2000.0
	var picked_side := PackedVector2Array([mid + along, mid - along, mid - along - n * 2000.0, mid + along - n * 2000.0])
	var folded := []
	for i in outlines.size():
		for piece in Geometry2D.clip_polygons(outlines[i], picked_side):
			# the part that stays put darkens a little towards the crease, where it bends away
			var colors := PackedColorArray()
			for q in piece:
				var near := clampf(1.0 - (q - mid).dot(n) / 30.0, 0.0, 1.0)
				colors.append(fronts[i].darkened(0.25 * near))
			shapes.append([piece, colors])
		for piece in Geometry2D.intersect_polygons(outlines[i], picked_side):
			var over := PackedVector2Array()
			var colors := PackedColorArray()
			for q in piece:
				var d := (q - mid).dot(n)
				over.append(q - 2.0 * d * n)
				# the inside of the foil: bright at the crease, shading off towards the far edge
				colors.append(FOIL_BACK.lerp(FOIL_DARK, clampf(-d / 60.0, 0.0, 0.7)).darkened(0.1 * i))
			folded.append([over, colors])
	for f in folded:
		var shade := PackedVector2Array()
		for q in f[0]:
			shade.append(q + Vector2(3, 5))
		shapes.append([shade, _flat(shade.size(), SHADOW)])
	shapes.append_array(folded)
	return shapes


static func _flat(count: int, c: Color) -> PackedColorArray:
	var colors := PackedColorArray()
	colors.resize(count)
	colors.fill(c)
	return colors


func _draw_strip() -> void:
	if strip_gone >= 1.0:
		return
	var shapes := _thrown_shapes if _thrown else _strip_shapes()
	if _thrown:
		draw_set_transform(_thrown_center + _fly, _spin, Vector2.ONE)
	var alpha := 1.0 - strip_gone
	for shape in shapes:
		var points: PackedVector2Array = shape[0]
		if _thrown:
			points = Transform2D(0.0, -_thrown_center) * points
		var colors: PackedColorArray = shape[1]
		if alpha < 1.0:
			colors = colors.duplicate()
			for i in colors.size():
				colors[i].a *= alpha
		# a fold right along an edge clips off a sliver too thin to triangulate: skip it
		if points.size() >= 3 and not Geometry2D.triangulate_polygon(points).is_empty():
			draw_polygon(points, colors)
	draw_set_transform(Vector2.ZERO)
## A zigzag sealed edge along y, teeth pointing up (-1) or down (1).
func _crimp(y: float, direction: float, alpha := 1.0) -> void:
	var tooth := CRIMP
	var x := -WIDTH / 2.0
	var i := 0
	while x < WIDTH / 2.0:
		draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + tooth, y),
			Vector2(x + tooth / 2.0, y + tooth * direction)]), Color(FOIL_DARK if i % 2 == 0 else FOIL, alpha))
		x += tooth
		i += 1


func _draw_logo(center: Vector2) -> void:
	# a chunky pixel heart
	var rows := [".oo.oo.", "ooooooo", "ooooooo", ".ooooo.", "..ooo..", "...o..."]
	var px := U * 2
	var origin := center - Vector2(rows[0].length() * px / 2.0, rows.size() * px / 2.0)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "o":
				draw_rect(Rect2(origin + Vector2(x, y) * px, Vector2(px, px)), LOGO)
