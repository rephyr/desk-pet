class_name Chest
extends Node2D
## Placeholder chest drawn from rectangles. The origin is the middle of the chest's bottom edge.
## `back` draws what's behind the pet (the dark inside and the lid, which hinges at the back);
## this node draws the front of the chest, in front of the pet.
## Real art replaces the drawing only; the controller only uses lid_open, mouth() and back.

const U := 4  # one art pixel
const BODY := Vector2i(34, 14)  # in art pixels
const LID := Vector2i(36, 8)
const WOOD := Color("3a2350")
const WOOD_DARK := Color("24142f")
const BAND := Color("c9a0ff")
const LOCK := Color("ffc857")
const INSIDE := Color("0d0612")

## 0 = closed, 1 = fully open.
var lid_open := 0.0:
	set(value):
		lid_open = value
		queue_redraw()
		back.queue_redraw()

## Drawn behind the pet: the dark inside of the chest.
var back := Node2D.new()


func _init() -> void:
	texture_filter = TEXTURE_FILTER_NEAREST
	back.draw.connect(_draw_inside)


## Where light and the pet come out, relative to the origin.
static func mouth() -> Vector2:
	return Vector2(0, -BODY.y * U)


static func width() -> float:
	return BODY.x * U


func _draw_inside() -> void:
	var w := BODY.x * U
	var h := BODY.y * U
	back.draw_rect(Rect2(-w / 2.0 + U, -h - U * 2, w - U * 2, U * 4), INSIDE)
	_draw_lid(back, h)


func _draw() -> void:
	var w := BODY.x * U
	var h := BODY.y * U
	# body
	draw_rect(Rect2(-w / 2.0, -h, w, h), WOOD_DARK)
	draw_rect(Rect2(-w / 2.0 + U, -h + U, w - U * 2, h - U * 2), WOOD)
	for x in [-w / 2.0 + U * 5, w / 2.0 - U * 7]:
		draw_rect(Rect2(x, -h, U * 2, h), BAND)
	draw_rect(Rect2(-w / 2.0, -h, w, U), BAND.darkened(0.3))
	# lock, hidden once the lid is up
	if lid_open < 0.5:
		draw_rect(Rect2(-U * 2, -h - U, U * 4, U * 5), LOCK)
		draw_rect(Rect2(-U / 2.0, -h + U, U, U * 2), WOOD_DARK)


func _draw_lid(canvas: CanvasItem, h: float) -> void:
	# the lid swings back on a hinge at its back edge (drawn as lifting and tilting away)
	var lw := LID.x * U
	var lh := LID.y * U
	var lift := lid_open * h * 1.3
	var squash := lerpf(1.0, 0.35, lid_open)  # tilting back makes it look shorter from the front
	var top := -h - lh * squash - lift
	canvas.draw_rect(Rect2(-lw / 2.0, top, lw, lh * squash), WOOD_DARK)
	canvas.draw_rect(Rect2(-lw / 2.0 + U, top + U * squash, lw - U * 2, (lh - U * 2) * squash), WOOD.lightened(0.08))
	for x in [-lw / 2.0 + U * 6, lw / 2.0 - U * 8]:
		canvas.draw_rect(Rect2(x, top, U * 2, lh * squash), BAND)
