class_name EncounterArt
extends RefCounted
## The pixel art for an adventure event (data/encounter_art.json): what the pets found, drawn on
## the trail just ahead of them while they wait at it (TrailView). Sprites are rows of letters,
## each letter a colour from the sprite's palette. Each call makes a new texture, so keep it while
## it's shown (a static cache of textures would outlive the renderer at quit).


## The art for `event_id` ({ texture, glow, eerie, flat, float }), or {} if it has none.
static func of(event_id: String) -> Dictionary:
	var all: Dictionary = Catalog.shared().encounter_art
	var art: Dictionary = all.get(event_id, {})
	if art.has("alias"):
		var base: Dictionary = all.get(str(art.alias), {})
		art = base.merged(art, true)
	if not art.has("rows"):
		return {}
	return {
		"texture": _texture(art.rows, art.get("pal", {})),
		"glow": bool(art.get("glow", false)),
		"eerie": bool(art.get("eerie", false)),
		"flat": bool(art.get("flat", false)),
		"float": int(art.get("float", 0)),
	}


static func _texture(rows: Array, pal: Dictionary) -> ImageTexture:
	var w := 0
	for row in rows:
		w = maxi(w, str(row).length())
	var image := Image.create_empty(maxi(w, 1), maxi(rows.size(), 1), false, Image.FORMAT_RGBA8)
	var colors := {}
	for key in pal:
		colors[key] = Color.html(str(pal[key]))
	for y in rows.size():
		var row := str(rows[y])
		for x in row.length():
			var ch := row[x]
			if colors.has(ch):
				image.set_pixel(x, y, colors[ch])
	return ImageTexture.create_from_image(image)
