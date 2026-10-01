class_name PerkNail
extends RefCounted
## The wisps perks' things (the bow, the little flag, the dinner bell...), drawn for the well wall
## (WellWall's tags, see Perks): bought = solid coral, the next one you can buy = a brighter dashed
## outline, one waiting on the perk before = a faint dashed one, the carrot (not reached yet) = chalk.
## Design: design/mockups/screens/perks-redo.html look A (the well wall).

## The things, drawn in a 24 x 24 box (the mockup's paths; the thimble and the ribbon are new).
const THINGS := {
	"bow": '<path d="M12 11 Q7 5.5 4.2 7.6 Q2.6 11 4.4 14.4 Q7.4 16 12 11 Z"/><path d="M12 11 Q17 5.5 19.8 7.6 Q21.4 11 19.6 14.4 Q16.6 16 12 11 Z"/><path d="M11 12.4 L8.4 20.4 M13 12.4 L15.6 20.4"/><circle cx="12" cy="11" r="2"/>',
	"flag": '<path d="M6 21 L6 3.4"/><path d="M6.6 4 L18.6 7.6 L6.6 11.6 Z"/>',
	"bell": '<path d="M5.6 17 Q5.4 8.6 12 7.4 Q18.6 8.6 18.4 17 Z"/><path d="M4 17.2 L20 17.2"/><circle cx="12" cy="19.6" r="1.6"/><path d="M12 7.4 L12 4.6"/>',
	"spool": '<rect x="6" y="3.6" width="12" height="3.2" rx="1.2"/><rect x="6" y="17.2" width="12" height="3.2" rx="1.2"/><path d="M8 6.8 L8 17.2 L16 17.2 L16 6.8 Z"/><path d="M8 9.4 L16 11.6 M8 12.6 L16 14.8"/>',
	"moon": '<path d="M15.6 4 A8.4 8.4 0 1 0 20.2 16.4 A6.8 6.8 0 0 1 15.6 4 Z"/>',
	"lunch": '<rect x="4" y="9" width="16" height="11" rx="2.6"/><path d="M9 9 L9 6.4 Q12 4 15 6.4 L15 9"/><path d="M4 13.6 L20 13.6"/>',
	"scarf": '<path d="M4 7 Q12 3.6 20 7 L20 10.6 Q12 7.2 4 10.6 Z"/><path d="M14.6 9 L16.6 19 L19.6 18.2 L17.8 8.6"/><path d="M16.2 19.8 L15.8 21.4 M18.8 19.2 L19.2 20.8"/>',
	"pinwheel": '<path d="M12 11 L12 3.6 Q16.6 5.4 12 11 Z"/><path d="M12 11 L19.4 11 Q17.6 15.6 12 11 Z"/><path d="M12 11 L12 18.4 Q7.4 16.6 12 11 Z"/><path d="M12 11 L4.6 11 Q6.4 6.4 12 11 Z"/>',
	"musicbox": '<rect x="3.6" y="10" width="15" height="10" rx="2"/><path d="M3.6 10 L6.2 6 L16 6 L18.6 10"/><path d="M18.6 15 L21.6 15 M21.6 13 L21.6 17"/>',
	"star": '<path d="M12 3 L14.4 9 L20.8 9.4 L15.8 13.4 L17.6 19.8 L12 16.2 L6.4 19.8 L8.2 13.4 L3.2 9.4 L9.6 9 Z"/>',
	"thimble": '<path d="M6.6 20 L7.6 9.4 Q8.2 4.2 12 4.2 Q15.8 4.2 16.4 9.4 L17.4 20 Z"/><path d="M5.4 20 L18.6 20"/><path d="M8.8 12.4 L15.2 12.4 M8.5 16 L15.5 16"/>',
	"ribbon": '<path d="M9.8 13.6 Q6.2 7.6 8.8 4.6 Q12 2.2 15.2 4.6 Q17.8 7.6 14.2 13.6"/><path d="M14.2 13.6 L7.6 20.8 M9.8 13.6 L16.4 20.8"/>',
	"coin": '<circle cx="12" cy="12" r="8"/><path d="M12 7.6 L13.2 10.6 L16.4 10.8 L13.9 12.8 L14.8 15.9 L12 14.2 L9.2 15.9 L10.1 12.8 L7.6 10.8 L10.8 10.6 Z"/>',
	"rattle": '<circle cx="12" cy="8.6" r="5.6"/><path d="M12 14.2 L12 19.2"/><circle cx="12" cy="20.6" r="1.5"/>',
}
static var _textures := {}  # "thing|look|px|colours" -> texture


## A thing drawn at `px` x `px`: on (solid coral), next (a brighter dashed outline), off (dashed),
## carrot (chalk, dashed).
static func texture(thing_id: String, thing_look: String, px: int, hover := false, bold := false) -> Texture2D:
	var stroke := UiTheme.WISP
	var fill := "none"
	var dash := ""
	match thing_look:
		"on":
			fill = "#%s\" fill-opacity=\"0.3" % UiTheme.WISP.to_html(false)
		"next":
			stroke = UiTheme.WISP.lerp(UiTheme.LILAC_SEAM, 0.3)
			dash = ' stroke-dasharray="2.4 2.4"'
		"carrot":
			stroke = UiTheme.TEXT.lerp(UiTheme.RAISED, 0.4)
			dash = ' stroke-dasharray="2 3"'
		_:
			stroke = UiTheme.LILAC.lerp(UiTheme.LILAC_SEAM, 0.5)
			dash = ' stroke-dasharray="2.4 2.4"'
	if hover:
		stroke = UiTheme.PINK
	var width := (2.4 if bold else 1.8) * 24.0 / maxf(px, 1.0)  # the same line width at any size
	var key := "%s|%s|%d|%s|%s|%.2f" % [thing_id, thing_look, px, stroke.to_html(), fill, width]
	if _textures.has(key):
		return _textures[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="-1 -1 26 26" fill="%s" stroke="#%s" stroke-width="%.2f" stroke-linecap="round" stroke-linejoin="round"%s>%s</svg>' % [
		fill, stroke.to_html(false), width * 26.0 / 24.0, dash, str(THINGS.get(thing_id, THINGS.bow))]
	var img := Image.new()
	img.load_svg_from_string(svg, 2.0 * px / 24.0)
	img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_textures[key] = tex
	return tex
