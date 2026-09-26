class_name Chest
extends Node2D
## Placeholder chest, seen from the front and slightly above, drawn from rectangles.
## The lid is hinged at the back: opening it swings it up and over until it stands behind the
## chest showing its underside, and the inside (back wall, dark floor) becomes visible.
## The origin is the middle of the chest's bottom edge.
## `back` draws what is behind the pet (inside, and the lid once it has swung past upright);
## this node draws what is in front of it (front wall, and the lid while it's still closed-ish).
## Real art replaces the drawing only; the controller only uses lid_open, mouth(), rim_y() and back.

const U := 4  # one art pixel
const WIDTH := 34 * U
const FRONT := 11 * U  # height of the front wall
const DEPTH := 6 * U  # how much of the top you see from slightly above
const LIP := 4 * U  # the lid's front edge
const LID_LENGTH := 22 * U  # the lid's real front-to-back length (seen full size when upright)
const OPEN_ANGLE := deg_to_rad(105.0)
const OVERHANG := U  # the lid is a little wider than the chest

const WOOD := Color("3a2350")
const WOOD_LIGHT := Color("4a2f66")
const WOOD_DARK := Color("24142f")
const LID_INSIDE := Color("2b1838")
const BAND := Color("c9a0ff")
const BAND_DARK := Color("8a6fb8")
const LOCK := Color("ffc857")
const INSIDE := Color("0d0612")

## 0 = closed, 1 = fully open.
var lid_open := 0.0:
	set(value):
		lid_open = value
		queue_redraw()
		back.queue_redraw()

## Drawn behind the pet: see the class notes.
var back := Node2D.new()


func _init() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	back.texture_filter = TEXTURE_FILTER_NEAREST
	back.draw.connect(_draw_back)


## The top edge of the front wall. Anything inside the chest is hidden below this line.
static func rim_y() -> float:
	return -FRONT


## Middle of the chest's opening, where the light comes from.
static func mouth() -> Vector2:
	return Vector2(0, -FRONT - DEPTH * 0.5)


static func width() -> float:
	return WIDTH


# ---- geometry -------------------------------------------------------------

func _hinge_y() -> float:
	return -FRONT - DEPTH - LIP


## Where the lid's front edge is on screen, and how tall its lip looks, for the current angle.
## Closed, the lid lies flat (only DEPTH of its length shows); upright, its full length shows.
func _lid_front() -> Vector2:
	var angle := lid_open * OPEN_ANGLE
	var foreshorten := float(DEPTH) / LID_LENGTH
	var front_y := _hinge_y() + LID_LENGTH * (foreshorten * cos(angle) - sin(angle))
	var lip := LIP * maxf(cos(angle), 0.0)
	return Vector2(front_y, lip)


## The lid belongs behind the pet once its front edge has risen above the hinge.
func _lid_behind() -> bool:
	return _lid_front().x < _hinge_y()


# ---- drawing --------------------------------------------------------------

func _draw_back() -> void:
	var top := -FRONT - DEPTH  # back rim
	var inner := Rect2(-WIDTH / 2.0 + U, top, WIDTH - U * 2, DEPTH)
	# the inside: back wall (lit a little) over the dark floor
	back.draw_rect(inner, INSIDE)
	back.draw_rect(Rect2(inner.position, Vector2(inner.size.x, DEPTH * 0.45)), WOOD_DARK)
	# the back wall's top edge and the sides of the opening
	back.draw_rect(Rect2(-WIDTH / 2.0, top - LIP, WIDTH, LIP), WOOD)
	back.draw_rect(Rect2(-WIDTH / 2.0, top - LIP, WIDTH, U), BAND_DARK)
	back.draw_rect(Rect2(-WIDTH / 2.0, top, U, DEPTH), WOOD)
	back.draw_rect(Rect2(WIDTH / 2.0 - U, top, U, DEPTH), WOOD)
	if _lid_behind():
		_draw_lid(back)


func _draw() -> void:
	# front wall
	draw_rect(Rect2(-WIDTH / 2.0, -FRONT, WIDTH, FRONT), WOOD_DARK)
	draw_rect(Rect2(-WIDTH / 2.0 + U, -FRONT + U, WIDTH - U * 2, FRONT - U * 2), WOOD)
	for x in [-WIDTH / 2.0 + U * 5, WIDTH / 2.0 - U * 7]:
		draw_rect(Rect2(x, -FRONT, U * 2, FRONT), BAND)
	draw_rect(Rect2(-WIDTH / 2.0, -FRONT, WIDTH, U), BAND_DARK)  # front rim
	if not _lid_behind():
		_draw_lid(self)


## The lid as one panel from the hinge to its front edge, plus the lip hanging off the front.
## Before it passes upright you see its top (light wood); after, its underside (dark).
func _draw_lid(canvas: CanvasItem) -> void:
	var hinge := _hinge_y()
	var f := _lid_front()
	var front_y := f.x
	var lip := f.y
	var x0 := -WIDTH / 2.0 - OVERHANG
	var w := WIDTH + OVERHANG * 2
	var showing_top := front_y > hinge
	var panel := Rect2(x0, minf(hinge, front_y), w, absf(front_y - hinge))
	canvas.draw_rect(panel, WOOD_LIGHT if showing_top else LID_INSIDE)
	canvas.draw_rect(Rect2(panel.position, Vector2(w, U)), WOOD_DARK)
	canvas.draw_rect(Rect2(panel.position + Vector2(0, panel.size.y - U), Vector2(w, U)), WOOD_DARK)
	for x in [x0 + U * 6, x0 + w - U * 8]:
		canvas.draw_rect(Rect2(x, panel.position.y, U * 2, panel.size.y), BAND if showing_top else BAND_DARK)
	if lip > 0.5:
		# the lip hangs down from the front edge (it folds away as the lid opens)
		var lip_rect := Rect2(x0, front_y, w, lip)
		canvas.draw_rect(lip_rect, WOOD_DARK)
		canvas.draw_rect(lip_rect.grow_individual(-U, 0, -U, -U), WOOD)
		for x in [x0 + U * 6, x0 + w - U * 8]:
			canvas.draw_rect(Rect2(x, front_y, U * 2, lip), BAND)
		if lid_open < 0.35:
			canvas.draw_rect(Rect2(-U * 2, front_y + lip - U * 2, U * 4, U * 4), LOCK)
			canvas.draw_rect(Rect2(-U / 2.0, front_y + lip - U, U, U * 2), WOOD_DARK)
