class_name NightSky
extends Control
## Behind the home panel: one tiny, dim star for every pet that didn't come back, placed and
## tinted by that pet. Never explained or counted. Once the panel can't hold more specks, new
## stars go into a faint milky band instead, so the sky keeps slowly filling in.

const DENSITY := 40.0  # px² of panel per star before the band takes over
const ALPHA := 0.2
const BAND_ALPHA := 0.07


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	GameState.collection.pets_removed.connect(func(_uids): queue_redraw())


func _draw() -> void:
	var fallen := GameState.collection.fallen
	if fallen.is_empty() or size.x < 1.0 or size.y < 1.0:
		return
	var catalog := Catalog.shared()
	var room := int(size.x * size.y / DENSITY)
	var tints := {}
	for i in fallen.size():
		var uid: int = fallen[i][0]
		var palette: String = fallen[i][1]
		if not tints.has(palette):
			var body: String = catalog.part("palette", palette).get("body", "#ffffff")
			tints[palette] = Color(body).lerp(Color.WHITE, 0.4)
		var h := hash(uid)
		var x := float(h & 0xffff) / 65535.0
		var y := float((h >> 16) & 0xffff) / 65535.0
		var tint: Color = tints[palette]
		if i < room:
			# a speck; one in a while is a touch brighter
			tint.a = ALPHA * (1.6 if h % 23 == 0 else lerpf(0.5, 1.0, y))
		else:
			# the band: a soft diagonal across the panel
			var spread := (float(hash(uid * 31) & 0xffff) / 65535.0 - 0.5) * 0.35
			y = clampf(0.85 - 0.7 * x + spread, 0.0, 1.0)
			tint.a = BAND_ALPHA
		draw_rect(Rect2(floorf(x * (size.x - 1.0)), floorf(y * (size.y - 1.0)), 1.0, 1.0), tint)
