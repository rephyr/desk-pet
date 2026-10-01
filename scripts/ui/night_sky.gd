class_name NightSky
extends Control
## Behind the home panel: one tiny, dim star for every pet that didn't come back or left for a new
## home, never explained or counted. Star i is placed by its number (not by the pet: pets from the herd have no uid of
## their own) and tinted by that pet's palette. Once the panel can't hold more specks, new stars go
## into a faint milky band instead, so the sky keeps slowly filling in. A million stars cost the
## same as the panel's worth plus the band: the rest are only counted. The stars are painted into a
## picture once, and new ones are added to it as they come (redrawing them all every time a pet
## left was a hitch with a sky full of them).

const DENSITY := 40.0  # px² of panel per star before the band takes over
const ALPHA := 0.2
const BAND_ALPHA := 0.07
const BAND_MAX := 6000  # stars drawn into the band at most


var _img: Image
var _tex: ImageTexture
var _drawn := 0  # stars painted into the picture so far


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(_repaint)
	GameState.collection.pets_removed.connect(func(_uids): _add_stars())
	GameState.collection.pets_left.connect(func(_n): _add_stars())
	GameState.collection.stars_added.connect(func(_n): _add_stars())
	GameState.dungeon_changed.connect(_add_stars)  # the army's lost herd pets are stars too
	GameState.new_game.connect(_repaint)


## Paints the whole sky again (a new size, a new game).
func _repaint() -> void:
	_img = null
	_drawn = 0
	_add_stars()


## Paints the stars that aren't in the picture yet.
func _add_stars() -> void:
	var c := GameState.collection
	var w := int(size.x)
	var h := int(size.y)
	if w < 1 or h < 1:
		return
	if c.fallen_n < _drawn or (_img != null and (_img.get_width() != w or _img.get_height() != h)):
		_img = null  # fewer stars than painted (a new save) or a new size: start over
		_drawn = 0
	var upto := mini(c.fallen_n, w * h / int(DENSITY) + BAND_MAX) if not c.fallen.is_empty() else 0
	if upto <= _drawn and _img != null:
		return
	if _img == null:
		_img = Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	_paint(_drawn, upto)
	_drawn = maxi(_drawn, upto)
	if _tex == null or _tex.get_size() != Vector2(w, h):
		_tex = ImageTexture.create_from_image(_img)
	else:
		_tex.update(_img)
	queue_redraw()


## Stars `from` to `to` into the picture.
func _paint(from: int, to: int) -> void:
	var c := GameState.collection
	var catalog := Catalog.shared()
	var room := int(size.x * size.y / DENSITY)
	var w := _img.get_width() - 1
	var hh := _img.get_height() - 1
	var tints := {}
	for i in range(from, to):
		var h := hash(i * 7919 + 1)
		# past the palettes kept one by one, a star takes one of theirs by its number
		var palette: String = c.fallen[i] if i < c.fallen.size() else c.fallen[h % c.fallen.size()]
		if not tints.has(palette):
			var body: String = catalog.part("palette", palette).get("body", "#ffffff")
			tints[palette] = Color(body).lerp(Color.WHITE, 0.4)
		var x := float(h & 0xffff) / 65535.0
		var y := float((h >> 16) & 0xffff) / 65535.0
		var tint: Color = tints[palette]
		if i < room:
			# a speck; one in a while is a touch brighter
			tint.a = ALPHA * (1.6 if h % 23 == 0 else lerpf(0.5, 1.0, y))
		else:
			# the band: a soft diagonal across the panel
			var spread := (float(hash(i * 31 + 7) & 0xffff) / 65535.0 - 0.5) * 0.35
			y = clampf(0.85 - 0.7 * x + spread, 0.0, 1.0)
			tint.a = BAND_ALPHA
		var px := int(x * w)
		var py := int(y * hh)
		_img.set_pixel(px, py, _img.get_pixel(px, py).blend(tint))


func _draw() -> void:
	if _tex != null and _drawn > 0:
		draw_texture(_tex, Vector2.ZERO)
