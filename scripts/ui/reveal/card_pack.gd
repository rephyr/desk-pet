class_name CardPack
extends Node2D
## Placeholder foil card pack, drawn from rectangles. You rip the strip off the top along the
## tear line; the pet then comes out of the opening. The origin is the middle of its bottom edge.
## `back` draws what is behind the pet (the pack's back sheet in the opening); this node draws
## the front of the pack and the strip. Real art replaces the drawing only; the controller only
## uses tear, strip_gone, mouth(), rim_y() and back.

const U := 4  # one art pixel
const WIDTH := 30 * U
const HEIGHT := 42 * U
const STRIP := 7 * U  # the part that rips off
const CRIMP := 2 * U  # zigzag sealed edges
const TILT := 0.3  # how far the strip lifts while you rip it (radians)

const FOIL := Color("6b4fa0")
const FOIL_LIGHT := Color("8e6fd0")
const FOIL_DARK := Color("3d2a63")
const EDGE := Color("c9a0ff")
const SHEEN := Color(1, 1, 1, 0.12)
const LOGO := Color("ff79c6")
const INSIDE := Color("0d0612")

## 0..1: how far along the tear line it's ripped.
var tear := 0.0:
	set(value):
		tear = value
		queue_redraw()
		back.queue_redraw()
## Which way you're ripping: 1 = left to right (the strip peels up from the left),
## -1 = right to left.
var direction := 1.0:
	set(value):
		direction = signf(value) if value != 0.0 else 1.0
		queue_redraw()
## 0..1: the ripped-off strip flying away.
var strip_gone := 0.0:
	set(value):
		strip_gone = value
		queue_redraw()

## Drawn behind the pet: see the class notes.
var back := Node2D.new()


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


## The strip: still attached at the far end, its torn end lifting up as you rip, then flying
## off up and away in the direction you ripped.
func _draw_strip() -> void:
	if strip_gone >= 1.0:
		return
	var pivot := Vector2(WIDTH / 2.0 * direction, rim_y())
	# positive angles turn clockwise on screen: that lifts the left end when pivoting on the right
	var angle := (tear * TILT + strip_gone * 1.4) * direction
	var fly := Vector2(strip_gone * 160.0 * direction, -strip_gone * 220.0)
	# rotate around the pivot, then move
	draw_set_transform(pivot - pivot.rotated(angle) + fly, angle, Vector2.ONE)
	var alpha := 1.0 - strip_gone
	var y := -HEIGHT
	draw_rect(Rect2(-WIDTH / 2.0, y + CRIMP, WIDTH, STRIP - CRIMP), Color(FOIL_LIGHT, alpha))
	_crimp(y + CRIMP, -1.0, alpha)
	if tear <= 0.0:
		# dotted tear line
		for i in range(1, int(WIDTH / (U * 2))):
			draw_rect(Rect2(-WIDTH / 2.0 + i * U * 2, rim_y() - U / 2.0, U, U / 2.0), Color(EDGE, 0.8))
		# a little notch showing where to start
		draw_colored_polygon(PackedVector2Array([Vector2(-WIDTH / 2.0, rim_y() - U), Vector2(-WIDTH / 2.0 + U * 2, rim_y()),
			Vector2(-WIDTH / 2.0, rim_y() + U)]), INSIDE)
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
