class_name PetLook
extends RefCounted
## Placeholder art: builds a small pixel image of a pet from its parts.
## Everything here gets replaced by real part sprites later; only texture_for() is the API.

const W := 16
const H := 18

# The shared head and body below the ears (rows 6..17). Characters:
# . empty  o outline  b body  l light belly  c cheek
const BASE := [
	"..obbbbbbbbbbo..",
	".obbbbbbbbbbbbo.",
	".obbbbbbbbbbbbo.",
	".obbbbbbbbbbbbo.",
	".obcbbbbbbbbcbo.",
	".obbbbboobbbbbo.",
	".obbblllllllbbo.",
	".obbllllllllbbo.",
	"..obllllllllbo..",
	"..obbbbbbbbbbo..",
	"...oboooooobo...",
	"...oo......oo...",
]
const BASE_TOP := 6

# Rows 0..5 per body: ears, horns and so on. Missing rows are empty.
const BODIES := {
	"blob": { 5: "...oooooooooo..." },
	"cat": {
		3: "....oo....oo....",
		4: "...obbo..obbo...",
		5: "...obbbooobbo...",
	},
	"bear": {
		4: "..ooo......ooo..",
		5: "..obboooooobbo..",
	},
	"bunny": {
		0: "...oo......oo...",
		1: "..obbo....obbo..",
		2: "..olbo....oblo..",
		3: "..olbo....oblo..",
		4: "..obbo....obbo..",
		5: "..obboooooobbo..",
	},
	"fox": {
		2: "..o..........o..",
		3: "..oo........oo..",
		4: "..obo......obo..",
		5: "..obboooooobbo..",
	},
	"dragon": {
		3: "...o........o...",
		4: "...oo......oo...",
		5: "...oboooooobo...",
	},
	"void": {
		3: ".......oo.......",
		4: ".......oo.......",
		5: "...oooooooooo...",
	},
}

# Extra pixels per body: [x, y, char]. "a" is the palette accent.
const BODY_EXTRAS := {
	"dragon": [[0, 12], [0, 13], [15, 12], [15, 13], [0, 11], [15, 11]],
	"fox": [[14, 15], [15, 14], [15, 15]],
}

# Eye pixels [x, y] per style; blink replaces them with a line on the lower row.
const EYES := {
	"round": [[4, 8], [5, 8], [4, 9], [5, 9], [10, 8], [11, 8], [10, 9], [11, 9]],
	"sleepy": [[4, 9], [5, 9], [10, 9], [11, 9]],
	"happy": [[3, 9], [4, 8], [5, 9], [10, 9], [11, 8], [12, 9]],
	"sparkle": [[4, 8], [5, 8], [4, 9], [5, 9], [10, 8], [11, 8], [10, 9], [11, 9]],
	"cyclops": [[6, 7], [7, 7], [8, 7], [9, 7], [6, 8], [7, 8], [8, 8], [9, 8], [7, 9], [8, 9]],
	"x": [[3, 7], [5, 7], [4, 8], [3, 9], [5, 9], [10, 7], [12, 7], [11, 8], [10, 9], [12, 9]],
}
const EYE_SHINE := { "sparkle": [[4, 8], [10, 8]], "cyclops": [[7, 7]] }
const BLINKS := ["round", "sparkle", "cyclops"]

# Accessory pixels: [x, y, colour].
const ACCESSORIES := {
	"bow": [[11, 4, "ff79c6"], [13, 4, "ff79c6"], [11, 5, "ff79c6"], [12, 5, "d94f9a"], [13, 5, "ff79c6"]],
	"leaf": [[8, 3, "6fe3a8"], [9, 3, "6fe3a8"], [7, 4, "6fe3a8"], [8, 4, "3fae78"], [7, 5, "3fae78"]],
	"headphones": [[3, 4, "3b3b4f"], [4, 3, "3b3b4f"], [5, 3, "3b3b4f"], [6, 3, "3b3b4f"], [7, 3, "3b3b4f"],
		[8, 3, "3b3b4f"], [9, 3, "3b3b4f"], [10, 3, "3b3b4f"], [11, 3, "3b3b4f"], [12, 4, "3b3b4f"],
		[0, 8, "5cc8ff"], [0, 9, "5cc8ff"], [0, 10, "5cc8ff"], [15, 8, "5cc8ff"], [15, 9, "5cc8ff"], [15, 10, "5cc8ff"]],
	"halo": [[6, 0, "ffe66d"], [7, 0, "ffe66d"], [8, 0, "ffe66d"], [9, 0, "ffe66d"],
		[5, 1, "ffe66d"], [10, 1, "ffe66d"], [6, 2, "ffe66d"], [7, 2, "ffe66d"], [8, 2, "ffe66d"], [9, 2, "ffe66d"]],
	"crown": [[5, 2, "ffc857"], [8, 2, "ffc857"], [10, 2, "ffc857"], [5, 3, "ffc857"], [6, 3, "ffc857"],
		[7, 3, "ffc857"], [8, 3, "ffc857"], [9, 3, "ffc857"], [10, 3, "ffc857"], [5, 4, "ffc857"],
		[6, 4, "ffc857"], [7, 4, "ff4f9a"], [8, 4, "ffc857"], [9, 4, "ffc857"], [10, 4, "ffc857"]],
	"horns": [[2, 2, "ff4f5a"], [3, 3, "ff4f5a"], [4, 4, "c9303a"], [13, 2, "ff4f5a"], [12, 3, "ff4f5a"], [11, 4, "c9303a"]],
}

# Stitch marks for sewn-on parts: little thread dashes at that part's seam, [x, y] per slot.
const STITCHES := {
	"body": [[4, 6], [6, 6], [9, 6], [11, 6]],  # round the neck, where the head was sewn on
	"palette": [[13, 10], [13, 12]],  # a patch on the side
	"pattern": [[2, 11], [2, 13]],
	"eyes": [[6, 10], [9, 10]],  # just under the eyes
	"accessory": [[12, 6], [13, 7]],
}
const THREAD := Color("ffe3f1")

const OUTLINE := Color("2a1033")
const CHEEK := Color("ff79c6")

static var _cache := {}  # look key -> ImageTexture
static var _top_rows := {}  # look key -> the first row of its picture with anything in it


## The pet's picture. Finish effects are not baked in (see shaders/finish.gdshader).
## `sewn` lists slots whose part was sewn on: they get stitch marks.
static func texture_for(parts: Dictionary, blink := false, sewn: Array = []) -> ImageTexture:
	var key := _key(parts, blink, sewn)
	if not _cache.has(key):
		var img := _build(parts, blink, sewn)
		_cache[key] = ImageTexture.create_from_image(img)
		_top_rows[key] = img.get_used_rect().position.y
	return _cache[key]


## The first row of the pet's picture with anything in it (ears, a hat...), worked out once when
## the picture is made.
static func top_row(parts: Dictionary, sewn: Array = []) -> int:
	texture_for(parts, false, sewn)
	return _top_rows[_key(parts, false, sewn)]


static func _key(parts: Dictionary, blink: bool, sewn: Array) -> String:
	return "%s|%s|%s|%s|%s|%s|%s" % [parts.body, parts.palette, parts.pattern, parts.eyes, parts.accessory, blink, ",".join(sewn)]


## The pet's own crayon colour (its palette's body colour: a lilac blob colours in lilac), made
## lighter or darker when it would vanish on the page (a midnight pet on a `dark` page).
static func main_color(pet: Pet, dark := true) -> Color:
	if pet == null:
		return Color("#c9a0ff")
	var palette := Catalog.shared().part("palette", str(pet.parts.get("palette", "")))
	var body := Color(palette.get("body", "#c9a0ff"))
	if dark and body.get_luminance() < 0.35:
		return Color(palette.get("light", "#f5dcec"))
	if not dark and body.get_luminance() > 0.7:
		return Color(palette.get("accent", "#9b6fe0"))
	return body


static func _build(parts: Dictionary, blink: bool, sewn: Array = []) -> Image:
	var palette := Catalog.shared().part("palette", parts.palette)
	var body := Color(palette.get("body", "#c9a0ff"))
	var light := Color(palette.get("light", "#f5dcec"))
	var accent := Color(palette.get("accent", "#9b6fe0"))
	var colors := { "o": OUTLINE, "b": body, "l": light, "c": CHEEK, "a": accent }

	var img := Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	var plain_body: Array[Vector2i] = []  # where a pattern may paint
	var shape: Dictionary = BODIES.get(parts.body, BODIES.blob)
	for y in H:
		var row: String = BASE[y - BASE_TOP] if y >= BASE_TOP else shape.get(y, "")
		for x in row.length():
			if colors.has(row[x]):
				img.set_pixel(x, y, colors[row[x]])
			if row[x] == "b":
				plain_body.append(Vector2i(x, y))
	for p in BODY_EXTRAS.get(parts.body, []):
		img.set_pixel(p[0], p[1], accent)

	_paint_pattern(img, plain_body, parts.pattern, body, accent)
	_paint_eyes(img, parts.eyes, body, blink)
	for p in ACCESSORIES.get(parts.accessory, []):
		img.set_pixel(p[0], p[1], Color(p[2]))
	for slot in sewn:
		for p in STITCHES.get(slot, []):
			img.set_pixel(p[0], p[1], THREAD)
	return img


## Patterns only paint over plain body pixels, never outline, belly or face.
static func _paint_pattern(img: Image, cells: Array[Vector2i], pattern: String, body: Color, accent: Color) -> void:
	for cell in cells:
		var x := cell.x
		var y := cell.y
		var paint := false
		var color := accent
		match pattern:
			"spots": paint = (x * 7 + y * 3) % 11 == 0
			"stripes": paint = y % 3 == 0
			"checker":
				paint = ((x >> 1) + (y >> 1)) % 2 == 0
				color = body.darkened(0.12)
			"stars":
				paint = (x * 13 + y * 7) % 23 == 0
				color = Color("fff6d6")
			"circuit":
				paint = y == 11 or x == 3 or x == 12
				if (x == 3 or x == 12) and y % 4 == 0:
					color = Color("5cf2ff")
		if paint:
			img.set_pixel(x, y, color)


static func _paint_eyes(img: Image, style: String, body: Color, blink: bool) -> void:
	var pixels: Array = EYES.get(style, EYES.round)
	if blink and style in BLINKS:
		var lowest := 0
		for p in pixels:
			lowest = maxi(lowest, p[1])
		for p in pixels:
			img.set_pixel(p[0], p[1], OUTLINE if p[1] == lowest else body)
		return
	for p in pixels:
		img.set_pixel(p[0], p[1], OUTLINE)
	for p in EYE_SHINE.get(style, []):
		img.set_pixel(p[0], p[1], Color.WHITE)
