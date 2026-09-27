class_name PackArt
extends RefCounted
## A crimped foil card pack with a sticker heart, drawn as SVG in a box's colours (its "art" in
## data/boxes.json). Used for the shop's pack stickers and anywhere a small pack shows up.

static var _cache := {}


## The pack at `width` px wide (drawn at 2x for scaled screens), strip on or ripped off.
static func texture(art: Dictionary, width: int, ripped := false) -> ImageTexture:
	var key := "%s|%d|%s" % [str(art), width, ripped]
	if _cache.has(key):
		return _cache[key]
	var body := str(art.get("foil_light", "#8e6fd0"))
	var dark := str(art.get("foil_dark", "#3d2a63"))
	var light := str(art.get("edge", "#c9a0ff"))
	var emblem := str(art.get("logo", "#ff79c6"))
	var top := ""
	for x in range(4, 96, 6):
		top += " L%d 10 L%d 6" % [x + 3, x + 6]
	var bottom := ""
	for x in range(4, 96, 6):
		bottom += " L%d 120 L%d 124" % [x + 3, x + 6]
	var strip := "" if ripped else '<path d="M4 6%s L96 22 L4 22 Z" fill="%s"/><path d="M8 22 L92 22" stroke="%s" stroke-width="2" stroke-dasharray="3 4" stroke-linecap="round"/>' % [top, dark, light]
	var svg := '''<svg xmlns="http://www.w3.org/2000/svg" width="100" height="130" viewBox="0 0 100 130">%s
		<path d="M4 24 Q3 70 5 118 L4 124%s L95 118 Q97 70 96 24 Z" fill="%s" stroke="%s" stroke-width="3" stroke-linejoin="round"/>
		<path d="M18 30 L34 30 L14 104 L6 104 Z" fill="%s" opacity=".35"/>
		<g transform="translate(50 72)"><circle r="21" fill="%s" stroke="%s" stroke-width="2.5"/>
		<path d="M0 11 Q-13 2 -12 -5 Q-10 -12 -4 -10 Q-1 -9 0 -5 Q1 -9 4 -10 Q10 -12 12 -5 Q13 2 0 11 Z" fill="%s" stroke="%s" stroke-width="1.5" stroke-linejoin="round"/></g>
		<path d="M22 108 Q50 104 78 108" stroke="%s" stroke-width="2.5" fill="none" stroke-linecap="round" opacity=".6"/></svg>''' % [
		strip, bottom, body, dark, light, light, dark, emblem, dark, dark]
	var img := Image.new()
	img.load_svg_from_string(svg, width * 2 / 100.0)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## The pack as a control, `width` px wide, tilted a little like a sticker.
static func rect(art: Dictionary, width: int, tilt := -4.0) -> Control:
	var r := TextureRect.new()
	r.texture = texture(art, width)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(width, width * 1.3)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return Tilted.new(r, tilt)
