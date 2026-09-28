class_name ToyView
extends Control
## One capsule toy: its pixel art (data/toys.json) standing on a little plastic stand, in its finish
## (holo, gold foil, ghost: see toy_finish.gdshader), or a dark silhouette when it hasn't been
## found yet. `pixel` is screen pixels per art pixel (the art is 14 x 14).

const SIZE := 14
const FINISH_MODES := { "normal": 0, "holo": 1, "foil": 2, "ghost": 3 }
const SHADER := preload("res://scripts/ui/toy_finish.gdshader")

static var _textures := {}

var _art := TextureRect.new()
var _material := ShaderMaterial.new()
var _toy := ""
var _finish := "normal"
var _missing := false
var _pixel := 4


func _init(toy_id := "", finish_id := "normal", pixel := 4, missing := false) -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_material.shader = SHADER
	_art.material = _material
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_SCALE
	_art.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_art)
	show_toy(toy_id, finish_id, pixel, missing)


func show_toy(toy_id: String, finish_id := "normal", pixel := 4, missing := false) -> void:
	_toy = toy_id
	_finish = finish_id
	_missing = missing
	_pixel = pixel
	custom_minimum_size = Vector2(SIZE * pixel, SIZE * pixel + pixel * 3)
	_art.texture = texture(toy_id) if toy_id != "" else null
	_art.position = Vector2.ZERO
	_art.size = Vector2(SIZE, SIZE) * pixel
	_material.set_shader_parameter("mode", 4 if missing else int(FINISH_MODES.get(finish_id, 0)))
	_material.set_shader_parameter("shade", UiTheme.LINE)
	queue_redraw()


func _draw() -> void:
	if _toy == "":
		return
	var w := SIZE * _pixel
	var c := Vector2(w / 2.0, w + _pixel * 0.8)
	if _finish == "ghost" and not _missing:
		draw_circle(Vector2(w / 2.0, w * 0.55), w * 0.42, Color(UiTheme.CYAN, 0.12))
	# the plastic stand under it
	draw_set_transform(c, 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, w * 0.36, UiTheme.PAGE.lerp(UiTheme.TEXT, 0.14 if not _missing else 0.05))
	draw_arc(Vector2.ZERO, w * 0.36, 0, TAU, 32, UiTheme.DEEP, maxf(2.0, _pixel * 0.9) / 0.28 * 0.28, true)
	draw_set_transform(Vector2.ZERO)


## The toy's art as a 14 x 14 texture (cached), or null if there's no such toy.
static func texture(toy_id: String) -> ImageTexture:
	if _textures.has(toy_id):
		return _textures[toy_id]
	var data: Dictionary = Catalog.shared().toys
	var rows: Array = data.art.get(toy_id, [])
	if rows.is_empty():
		return null
	var img := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in mini(rows.size(), SIZE):
		var row: String = rows[y]
		for x in mini(row.length(), SIZE):
			var ch := row[x]
			if ch != "." and data.palette.has(ch):
				img.set_pixel(x, y, Color(str(data.palette[ch])))
	var tex := ImageTexture.create_from_image(img)
	_textures[toy_id] = tex
	return tex
