class_name PetSprite
extends Node2D
## Placeholder pet drawn from a tiny pixel map until real part sprites exist.
## Origin is at the pet's feet, centred.

const PIXEL := 4
# . empty, o outline, b body, l light belly, e eye, c cheek
const SHAPE := [
	"....oo....oo....",
	"...obbo..obbo...",
	"...obbbooobbo...",
	"..obbbbbbbbbbo..",
	".obbbbbbbbbbbbo.",
	".obbeebbbbeebbo.",
	".obbeebbbbeebbo.",
	".obcbbbbbbbbcbo.",
	".obbbbboobbbbbo.",
	".obbblllllllbbo.",
	".obbllllllllbbo.",
	"..obllllllllbo..",
	"..obbbbbbbbbbo..",
	"...oboooooobo...",
	"...oo......oo...",
]
const COLORS := {
	"o": Color("2a1033"),
	"b": Color("c9a0ff"),
	"l": Color("f5dcec"),
	"e": Color("2a1033"),
	"c": Color("ff79c6"),
}

var facing := 1  # 1 right, -1 left
var walking := false
var squash := 0.0  # set by the pet when landing, springs back

var _time := 0.0
var _blink := 0.0


static func size() -> Vector2:
	return Vector2(SHAPE[0].length(), SHAPE.size()) * PIXEL


func _process(delta: float) -> void:
	_time += delta
	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 5.0)
	squash = move_toward(squash, 0.0, delta * 4.0)
	queue_redraw()


func _draw() -> void:
	var w: int = SHAPE[0].length()
	var h: int = SHAPE.size()
	var bob := 0.0
	if walking:
		bob = -absf(sin(_time * 12.0)) * PIXEL
	else:
		bob = sin(_time * 2.0) * 0.5 * PIXEL
	# squash-and-stretch around the feet
	var sy := 1.0 - squash * 0.3
	var sx := 1.0 + squash * 0.25
	draw_set_transform(Vector2(0, bob), 0.0, Vector2(sx * facing, sy))
	for y in h:
		var row: String = SHAPE[y]
		for x in w:
			var ch := row[x]
			if ch == ".":
				continue
			if ch == "e" and _blink < 0.0:
				ch = "b" if y == 5 else "o"  # eyes closed: a single dark line
			var pos := Vector2(x - w / 2.0, y - h) * PIXEL
			draw_rect(Rect2(pos.round(), Vector2(PIXEL, PIXEL)), COLORS[ch])
