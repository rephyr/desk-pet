class_name Mound
extends Control
## A mound of tiny pets (the herd): how many you see grows slowly with the count (about log10, at
## most data/herd.json "mound_max"), so a million pets are a big pile, not a million pictures.
## Rows get narrower going up (shrink 2) like a heap of sand. Drawn in one go from cached looks.

const SPRITE := Vector2(16, 18)
const STEP_X := 9.0
const STEP_Y := 7.0

var _looks: Array[Texture2D] = []
var _spots: Array = []  # [position, flipped, texture index], back rows first


## `faces`: uids to take looks from (cards, or stand-ins for a count), cycled if there are fewer
## than the mound shows. `shown`: how many tiny pets. `max_w` / `h`: the room it may take.
func _init(faces: Array, shown: int, max_w := 300.0, h := 36.0, shrink := 2) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	for uid in faces:
		var pet := GameState.collection.get_pet(str(uid))
		if pet:
			_looks.append(PetLook.texture_for(pet.parts, false, pet.sewn))
	if _looks.is_empty() or shown <= 0:
		custom_minimum_size = Vector2(0, h)
		return
	var rows := maxi(1, floori((h - SPRITE.y) / STEP_Y) + 1)
	var fits := func(b: int) -> int:
		var c := 0
		for r in rows:
			c += maxi(0, b - shrink * r)
		return c
	var b := 1 if shrink > 0 else floori((max_w - SPRITE.x) / STEP_X) + 1
	while fits.call(b) < shown and (b * STEP_X + SPRITE.x) <= max_w:
		b += 1
	var w := (b - 1) * STEP_X + SPRITE.x
	custom_minimum_size = Vector2(w, h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 + shown
	var k := 0
	var placed: Array = []
	for r in rows:
		if k >= shown:
			break
		var in_row := mini(maxi(0, b - shrink * r), shown - k)
		var x0 := (b - in_row) / 2.0 * STEP_X
		for c in in_row:
			var pos := Vector2(x0 + c * STEP_X + rng.randf_range(-1.5, 1.5), h - SPRITE.y - r * STEP_Y - rng.randf() * 2.0)
			placed.append([pos.round(), rng.randf() < 0.5, k % _looks.size(), r])
			k += 1
	# the back (upper) rows are drawn first, so the front row sits on top
	placed.sort_custom(func(a, b2): return a[3] > b2[3])
	_spots = placed


func _draw() -> void:
	for s in _spots:
		var tex: Texture2D = _looks[s[2]]
		var r := Rect2(s[0], SPRITE)
		if s[1]:
			r = Rect2(s[0] + Vector2(SPRITE.x, 0), Vector2(-SPRITE.x, SPRITE.y))
		draw_texture_rect(tex, r, false)
