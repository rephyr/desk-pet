class_name RevealBlocker
extends Node2D
## Sparkly mist hiding a very rare pet. The player drags it around to peek, then flicks it away.
## Placeholder drawing: a cluster of soft circles.

const PUFFS := [
	[Vector2(0, -60), 46.0], [Vector2(-38, -40), 36.0], [Vector2(38, -42), 38.0],
	[Vector2(-30, -85), 32.0], [Vector2(30, -88), 34.0], [Vector2(0, -105), 30.0],
	[Vector2(-44, -70), 26.0], [Vector2(46, -72), 26.0], [Vector2(0, -25), 34.0],
]

var tint := Color("c9a0ff")
var _time := randf() * 10.0


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Rough area it covers, relative to its position (for grabbing it).
func cover_rect() -> Rect2:
	return Rect2(-80, -140, 160, 150)


func _draw() -> void:
	for puff in PUFFS:
		var wobble := Vector2(sin(_time * 1.3 + puff[1]), cos(_time * 1.1 + puff[1])) * 3.0
		draw_circle(puff[0] + wobble, puff[1] + 6.0, tint.darkened(0.55))
	for puff in PUFFS:
		var wobble := Vector2(sin(_time * 1.3 + puff[1]), cos(_time * 1.1 + puff[1])) * 3.0
		draw_circle(puff[0] + wobble, puff[1], tint.darkened(0.25))
	# twinkles
	for i in 7:
		var p := Vector2(sin(i * 12.9 + _time * 0.7) * 55.0, -65.0 + cos(i * 7.3 + _time * 0.9) * 45.0)
		var s := 2.0 + (sin(_time * 4.0 + i) + 1.0) * 1.5
		draw_rect(Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), Color(1, 1, 1, 0.8))
