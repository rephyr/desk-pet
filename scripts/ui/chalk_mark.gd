class_name ChalkMark
extends Button
## One mark of a sewing room's chalk lock (SewingPage): a chalk drawing of what the room asks for,
## a part (bunny ears, a halo, horns...), a trait, a finish swatch, a rarity circle in its tier's
## colour, or a button with how many. Dashed chalk until a front-row pet matches it, then filled in
## solid. No words on it: tapping a dashed one has your pet say where it comes from.
## Design: lanes/mockups2 design/mockups/screens/well-additions.html (the sewing room).

const SIZE := 44
const DRAW := 34

## Chalk drawings on a 24 grid: [the part that fills in, lines that stay lines]. Keyed by the mark
## ("part:body:bunny"), else by its kind and id ("trait:zoomy" -> "zoomy", "finish:holo" -> "holo").
const DRAWINGS := {
	"part:body:bunny": ['<path d="M8.6 13.6 Q5.4 3 8.4 2.6 Q11.2 3 10.6 13.6 Z"/><path d="M13.4 13.6 Q12.8 3 15.6 2.6 Q18.6 3 15.4 13.6 Z"/><path d="M5 21.4 Q5 13.4 12 13.2 Q19 13.4 19 21.4"/>', ''],
	"part:accessory:halo": ['<path d="M5.4 21 Q5 11.6 12 11.4 Q19 11.6 18.6 21"/>', '<ellipse cx="12" cy="5.6" rx="7" ry="2.4"/>'],
	"part:accessory:horns": ['<path d="M7.4 12.4 Q2.6 10.4 3.2 3.4 Q6.6 8.6 10.4 11.4 Z"/><path d="M16.6 12.4 Q21.4 10.4 20.8 3.4 Q17.4 8.6 13.6 11.4 Z"/><path d="M5 21.4 Q5 12.4 12 12.2 Q19 12.4 19 21.4"/>', ''],
	"part:accessory:crown": ['<path d="M5 17 L4.2 7.5 L8.6 11.4 L12 5.4 L15.4 11.4 L19.8 7.5 L19 17 Z"/>', '<path d="M5 20.2 L19 20.2"/>'],
	"part:accessory:headphones": ['<rect x="3.4" y="12.6" width="4.4" height="7.4" rx="1.8"/><rect x="16.2" y="12.6" width="4.4" height="7.4" rx="1.8"/>', '<path d="M5.6 13 Q5.4 4.6 12 4.6 Q18.6 4.6 18.4 13"/>'],
	"part:eyes:sparkle": ['<path d="M7.6 6.4 Q8.2 10.4 11.4 11 Q8.2 11.6 7.6 15.6 Q7 11.6 3.8 11 Q7 10.4 7.6 6.4 Z"/><path d="M16.4 6.4 Q17 10.4 20.2 11 Q17 11.6 16.4 15.6 Q15.8 11.6 12.6 11 Q15.8 10.4 16.4 6.4 Z"/>', ''],
	"part:eyes:cyclops": ['<path d="M3 12 Q12 3.6 21 12 Q12 20.4 3 12 Z"/>', '<circle cx="12" cy="12" r="2.6"/>'],
	"part:eyes:x": ['', '<path d="M4.6 8.4 L9.6 13.4 M9.6 8.4 L4.6 13.4 M14.4 8.4 L19.4 13.4 M19.4 8.4 L14.4 13.4"/>'],
	"part:body:fox": ['<path d="M4.5 4 L9 9 Q12 8 15 9 L19.5 4 L19 12.5 Q18 19 12 20.5 Q6 19 5 12.5 Z"/>', '<path d="M10.2 15.6 L12 17 L13.8 15.6"/>'],
	"part:body:dragon": ['<path d="M5 20.6 Q4.5 12 8 9 L7 3.8 L10.4 7.6 L12 3 L13.6 7.6 L17 3.8 L16 9 Q19.5 12 19 20.6 Z"/>', '<path d="M10 16.6 L10 17.4 M14 16.6 L14 17.4"/>'],
	"part:body:void": ['<circle cx="12" cy="12" r="8"/>', '<path d="M12 12 Q14.4 10 12.8 8.4 Q9.4 7.2 8.2 10.6 Q7.4 15 12 15.8 Q16.6 15.6 16.2 10.6"/>'],
	"part:pattern:stars": ['<path d="M12 3 L14.4 9 L20.8 9.4 L15.8 13.4 L17.6 19.8 L12 16.2 L6.4 19.8 L8.2 13.4 L3.2 9.4 L9.6 9 Z"/>', ''],
	"part:pattern:circuit": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<path d="M7 7.6 L11 7.6 L11 12 L15.4 12 M8.6 16.4 L13 16.4 L13 20.2"/><circle cx="16.8" cy="12" r="1.3"/><circle cx="7" cy="7.6" r="1.1"/>'],
	"part:pattern:checker": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<path d="M3.5 12 L20.5 12 M12 3.5 L12 20.5"/>'],
	"shiny": ['<path d="M12 6.6 Q12.7 11.3 17.4 12 Q12.7 12.7 12 17.4 Q11.3 12.7 6.6 12 Q11.3 11.3 12 6.6 Z"/>', '<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>'],
	"holo": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<path d="M4.4 11 L11 4.4 M4.4 17.4 L17.4 4.4 M9.4 19.6 L19.6 9.4"/>'],
	"ghost": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<circle cx="9.4" cy="11" r="1.3"/><circle cx="14.6" cy="11" r="1.3"/>'],
	"glitch": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<path d="M6.4 8 L12.6 8 M9.4 12 L17.6 12 M6 16 L11.4 16"/>'],
	"prismatic": ['<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>', '<path d="M6.4 17 Q12 6 17.6 17 M9 17 Q12 10.6 15 17"/>'],
	"normal": ['', '<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>'],
	"zoomy": ['<path d="M13.4 3 L6.6 13.2 L11.4 13.2 L10 21 L17.4 10.2 L12.6 10.2 Z"/>', ''],
	"lazy": ['', '<path d="M4.6 6 L11 6 L4.6 13 L11 13"/><path d="M13 11.4 L19.4 11.4 L13 18.6 L19.4 18.6"/>'],
	"brave": ['<path d="M12 3.6 L19 6.2 Q19.2 15 12 20.6 Q4.8 15 5 6.2 Z"/>', ''],
	"lucky": ['<circle cx="8.8" cy="8.6" r="3.3"/><circle cx="15.2" cy="8.8" r="3.3"/><circle cx="8.7" cy="14.8" r="3.3"/><circle cx="15.1" cy="15" r="3.3"/>', '<path d="M12.2 12.2 Q15.6 17 19.4 20.8"/>'],
	"greedy": ['<path d="M12 3.5 L19.5 10.5 L12 20.5 L4.5 10.5 Z"/>', '<path d="M5 10.5 L19 10.5"/>'],
	"cuddly": ['<path d="M12 20.1 Q3.4 13.6 4.3 8.4 Q5.4 4.2 9.3 5.1 Q11.2 5.7 12 8 Q12.9 5.6 14.8 5.1 Q18.7 4.3 19.7 8.4 Q20.6 13.5 12 20.1 Z"/>', ''],
	"hungry": ['<path d="M12 8 Q7 5.5 5.4 10 Q4.4 16 8.5 19.6 Q10.5 20.6 12 19.6 Q13.5 20.6 15.5 19.6 Q19.6 16 18.6 10 Q17 5.5 12 8 Z"/>', '<path d="M12 8 Q12.4 5 14.4 3.6"/>'],
	"curious": ['<circle cx="10.4" cy="10.4" r="5.6"/>', '<path d="M14.6 14.6 L20 20.2"/>'],
	"tier": ['<circle cx="12" cy="12" r="7.6"/>', ''],
	"buttons": ['<circle cx="10" cy="10" r="6.8"/>', '<circle cx="8.2" cy="8.2" r=".9"/><circle cx="11.8" cy="8.2" r=".9"/><circle cx="8.2" cy="11.8" r=".9"/><circle cx="11.8" cy="11.8" r=".9"/>'],
}

var mark := ""
var on := false
var _tex: Texture2D
var _count := ""  # a button lock's number


func _init(p_mark: String, p_on: bool) -> void:
	mark = p_mark
	on = p_on
	custom_minimum_size = Vector2(SIZE, SIZE)
	focus_mode = FOCUS_NONE
	mouse_default_cursor_shape = CURSOR_ARROW if on else CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	var hover := UiTheme.box(Color(chalk(), 0.1), Color(0, 0, 0, 0), 8, 0, 0)
	for state in ["normal", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, empty)
	add_theme_stylebox_override("hover", empty if on else hover)
	var kind := mark.get_slice(":", 0)
	var color := chalk()
	if kind == "tier":
		color = GameState.catalog.tier_color(mark.get_slice(":", 1))
	if kind == "buttons":
		_count = mark.get_slice(":", 1)
	_tex = texture(mark, on, color, DRAW)


## The chalk colour (text at 72%).
static func chalk() -> Color:
	return Color(UiTheme.TEXT, 0.72)


## The drawing for a mark: [fills, lines].
static func drawing(p_mark: String) -> Array:
	if DRAWINGS.has(p_mark):
		return DRAWINGS[p_mark]
	var p := p_mark.split(":")
	var key := p[0] if p[0] in ["tier", "buttons"] else (p[p.size() - 1] if p.size() > 1 else p_mark)
	return DRAWINGS.get(key, ['<circle cx="12" cy="12" r="7"/>', ''])


## A mark drawn in chalk at `px` pixels: dashed, or filled in solid.
static func texture(p_mark: String, solid: bool, color: Color, px: int) -> Texture2D:
	var d := drawing(p_mark)
	var hex := "#" + color.to_html(false)
	var dash := "" if solid else ' stroke-dasharray="2.4 1.7"'
	var fill := ""
	if solid:
		fill = (' fill="%s"' % hex) if p_mark.begins_with("tier:") else (' fill="%s" fill-opacity="0.4"' % hex)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-opacity="%.2f" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round"%s><g%s>%s</g><g>%s</g></svg>' % [
		hex, color.a, dash, fill, d[0], d[1]]
	var img := Image.new()
	img.load_svg_from_string(svg, px * 2 / 24.0)
	return ImageTexture.create_from_image(img)


func _draw() -> void:
	var r := Rect2((size - Vector2(DRAW, DRAW)) / 2.0, Vector2(DRAW, DRAW))
	draw_texture_rect(_tex, r, false)
	if _count != "":
		var font := UiTheme.DISPLAY_FONT if UiTheme.DISPLAY_FONT else get_theme_default_font()
		var fs := 16
		var w := font.get_string_size(_count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(r.end.x - w, r.end.y - 1.0), _count, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiTheme.TEXT, 0.95 if on else 0.72))
