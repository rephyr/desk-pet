class_name UiTheme
extends RefCounted
## The game's look in one place: the player's colour theme, font set and icon style (settings,
## see data/themes.json), the Theme built from them, and small widget helpers.
## Screens use the colour roles below, never raw colours, so every theme works. When the player
## changes the look, apply() reloads everything and Settings.look_changed tells the windows to
## rebuild. Design reference: DESIGN.md and design/mockups/.

const THEMES_PATH := "res://data/themes.json"
const FONTS_DIR := "res://fonts/"

# colour roles (set by apply() from the chosen theme)
static var PAGE := Color("1a1024")  # the window background
static var DEEP := Color("120a19")  # wells and buttons, sunk below the page
static var RAISED := Color("241634")  # stickers: cards, bubbles, panels
static var PAPER := Color("1b1324")  # behind drawn scenes (map, trail, room)
static var SKY := Color("0f0816")  # the night sky strip
static var LINE := Color("2c1d3d")  # quiet outlines and stitched dividers
static var DOT := Color("2a1c3b")  # the dotted page
static var TEXT := Color("f5dcec")
static var MUTED := Color("9a88ad")  # secondary text
static var MUTED_SEAM := Color("4d4457")
static var LOCKED := Color("76688a")  # locked and disabled things
static var PINK := Color("ff79c6")  # the voice: titles, hover, selected
static var PINK_SEAM := Color("a64f81")
static var PINK_PRESSED := Color("592a45")
static var LILAC := Color("c9a0ff")  # structure
static var LILAC_SEAM := Color("6f588c")
static var CYAN := Color("8be9fd")  # coins, always
static var GOLD := Color("ffe08a")  # xp and sparkles, always
static var MINT := Color("8fe8c0")  # healing and growth
static var SHADOW := Color(0.02, 0.01, 0.05, 0.6)
static var DARK := true  # the theme is a dark one
# older names for the same roles
static var BG := PAGE
static var BG_DEEP := DEEP
static var BG_RAISED := RAISED

# fonts (set by apply() from the chosen font set)
static var DISPLAY_FONT: Font  # titles and big moments
static var BODY_FONT: Font  # everything else
static var BOLD_FONT: Font
static var FONT_SIZE := 13
static var SMALL := 11
static var ICON_STYLE := "doodle"

static var _theme: Theme
static var _data := {}
static var _icons := {}


## Reads the player's look from Settings and sets every role, font and icon style.
static func apply() -> void:
	var data := _load_data()
	var defaults: Dictionary = data.get("default", {})
	var theme_id: String = Settings.color_theme if Settings.color_theme != "" else str(defaults.get("theme", "plum"))
	var font_id: String = Settings.font_set if Settings.font_set != "" else str(defaults.get("font", "coiny"))
	ICON_STYLE = Settings.icon_style if Settings.icon_style != "" else str(defaults.get("icons", "doodle"))

	var t := _find(data.get("themes", []), theme_id)
	var c: Dictionary = t.get("colors", {})
	PAGE = _c(c, "page", PAGE); DEEP = _c(c, "deep", DEEP); RAISED = _c(c, "raised", RAISED)
	PAPER = _c(c, "paper", PAPER); SKY = _c(c, "sky", SKY); LINE = _c(c, "line", LINE); DOT = _c(c, "dot", DOT)
	TEXT = _c(c, "text", TEXT); MUTED = _c(c, "muted", MUTED); MUTED_SEAM = _c(c, "muted_seam", MUTED_SEAM)
	LOCKED = _c(c, "locked", LOCKED)
	PINK = _c(c, "pink", PINK); PINK_SEAM = _c(c, "pink_seam", PINK_SEAM); PINK_PRESSED = _c(c, "pink_pressed", PINK_PRESSED)
	LILAC = _c(c, "lilac", LILAC); LILAC_SEAM = _c(c, "lilac_seam", LILAC_SEAM)
	CYAN = _c(c, "cyan", CYAN); GOLD = _c(c, "gold", GOLD); MINT = _c(c, "mint", MINT); SHADOW = _c(c, "shadow", SHADOW)
	DARK = str(t.get("kind", "dark")) == "dark"
	BG = PAGE; BG_DEEP = DEEP; BG_RAISED = RAISED
	var tiers := {}
	for tier_id: String in t.get("tiers", {}):
		tiers[tier_id] = Color(t.tiers[tier_id])
	Catalog.shared().tier_overrides = tiers

	var f := _find(data.get("fonts", []), font_id)
	DISPLAY_FONT = _font(f.get("display", {}))
	BODY_FONT = _font(f.get("body", {}))
	BOLD_FONT = _font(f.get("body_bold", f.get("body", {})))
	FONT_SIZE = int(f.get("size", 13))
	SMALL = 11
	_theme = null
	_icons.clear()


## The looks the player can pick: { themes: [...], fonts: [...], icon_styles: [...] }.
static func looks() -> Dictionary:
	return _load_data()


static func get_theme() -> Theme:
	if DISPLAY_FONT == null:
		apply()
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var t := Theme.new()
	t.default_font = BODY_FONT
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)

	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var sb := box(DEEP, LILAC_SEAM, 8, 2, 6)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			match state:
				"hover": sb.border_color = PINK
				"pressed", "hover_pressed":
					sb.bg_color = PINK_PRESSED
					sb.border_color = PINK
				"disabled":
					sb.border_color = MUTED_SEAM
				"focus": sb.draw_center = false
			t.set_stylebox(state, type, sb)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, PINK)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, TEXT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, LOCKED)
		t.set_color("icon_normal_color", type, TEXT)
		t.set_color("icon_hover_color", type, PINK)
		t.set_color("icon_pressed_color", type, TEXT)
		t.set_color("icon_hover_pressed_color", type, TEXT)
		t.set_color("icon_focus_color", type, TEXT)
		t.set_color("icon_disabled_color", type, LOCKED)
		t.set_constant("h_separation", type, 6)

	t.set_stylebox("panel", "PanelContainer", sticker())
	t.set_stylebox("panel", "PopupMenu", box(DEEP, LILAC_SEAM, 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", PINK)
	t.set_stylebox("hover", "PopupMenu", box(RAISED, RAISED, 6))
	t.set_stylebox("panel", "TooltipPanel", box(DEEP, LILAC_SEAM, 6, 2, 7))
	t.set_color("font_color", "TooltipLabel", TEXT)

	# switches: a little pill with a knob
	for type in ["CheckButton"]:
		t.set_icon("checked", type, _svg_texture(_switch_svg(true), 1.0))
		t.set_icon("unchecked", type, _svg_texture(_switch_svg(false), 1.0))
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			var empty := StyleBoxEmpty.new()
			empty.content_margin_top = 4
			empty.content_margin_bottom = 4
			t.set_stylebox(state, type, empty)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, PINK)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, PINK)

	# sliders: a sunk track with a lilac fill and a pink knob
	var track := box(DEEP, LINE, 6, 2, 0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var fill := box(LILAC, LILAC, 6, 0, 0)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _svg_texture('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><circle cx="9" cy="9" r="7" fill="%s" stroke="%s" stroke-width="2"/></svg>' % [_hex(PINK), _hex(RAISED)], 1.0)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)

	for bar in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("grabber", bar, box(LILAC_SEAM, LILAC_SEAM, 4, 0, 0))
		t.set_stylebox("grabber_highlight", bar, box(LILAC, LILAC, 4, 0, 0))
		t.set_stylebox("grabber_pressed", bar, box(PINK, PINK, 4, 0, 0))
		t.set_stylebox("scroll", bar, box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 0))
		var thin := StyleBoxEmpty.new()
		thin.content_margin_left = 3
		thin.content_margin_right = 3
		t.set_stylebox("scroll_focus", bar, thin)
	return t


# ---- styles ---------------------------------------------------------------

static func box(bg: Color, border: Color, radius: int, border_width := 2, margin := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## A sticker on the page: raised, outlined, with a soft shadow under it.
static func sticker(border := LILAC_SEAM, radius := 12, bg := RAISED, margin := 12) -> StyleBoxFlat:
	var sb := box(bg, border, radius, 2, margin)
	sb.shadow_color = SHADOW
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 5)
	return sb


## A stitched outline: dashes instead of a solid border (the active tab, patches, rewards).
static func stitched(dash: Color = PINK, bg: Color = RAISED, radius := 10, margin := 8) -> StitchBox:
	var sb := StitchBox.new()
	sb.bg_color = bg
	sb.dash_color = dash
	sb.radius = radius
	sb.set_content_margin_all(margin)
	return sb


# ---- labels and buttons ----------------------------------------------------

static func label(text: String, color := TEXT, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


## A title in the display font (place names, section heads, big moments).
static func title(text: String, size := 18, color := PINK) -> Label:
	var l := label(text, color, size)
	l.add_theme_font_override("font", DISPLAY_FONT)
	return l


static func button(text: String, on_pressed: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if on_pressed.is_valid():
		b.pressed.connect(on_pressed)
	return b


static func small_button(text: String, on_pressed: Callable = Callable()) -> Button:
	var b := button(text, on_pressed)
	b.flat = true
	b.add_theme_font_size_override("font_size", FONT_SIZE + 1)
	return b


## A small rounded tag, like "rare" or "3 finds here".
static func tag(text: String, color := MUTED, border := LINE) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(DEEP, border, 999, 2, 0)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(label(text, color, SMALL))
	return p


## A coin or xp amount with its icon, e.g. chip("coin", "10,421", CYAN).
static func chip(icon_name: String, text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := box(DEEP, LINE, 999, 2, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 10
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.add_child(icon_rect(icon_name, 16))
	var l := label(text, color)
	l.name = "Amount"
	row.add_child(l)
	p.add_child(row)
	return p


## A row of joined choices, like "pets | book"; on_pick(index) runs when one is picked.
static func segmented(options: Array, current: int, on_pick: Callable) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(DEEP, LINE, 8, 2, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	p.add_child(row)
	for i in options.size():
		var b := Button.new()
		b.text = str(options[i])
		b.focus_mode = Control.FOCUS_NONE
		var on := i == current
		var sb := box(PINK_PRESSED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 3)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override("font_color", TEXT if on else MUTED)
		b.add_theme_color_override("font_hover_color", TEXT if on else PINK)
		b.pressed.connect(func():
			for j in row.get_child_count():
				var other: Button = row.get_child(j)
				var picked := j == i
				var st := box(PINK_PRESSED if picked else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 3)
				st.content_margin_left = 12
				st.content_margin_right = 12
				for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
					other.add_theme_stylebox_override(state, st)
				other.add_theme_color_override("font_color", TEXT if picked else MUTED)
				other.add_theme_color_override("font_hover_color", TEXT if picked else PINK)
			on_pick.call(i))
		row.add_child(b)
	return p


## A round filter chip that toggles on and off, tinted `color` when on.
static func filter_chip(text: String, color: Color, on := false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", SMALL)
	var off_sb := box(Color(0, 0, 0, 0), LINE, 999, 2, 2)
	off_sb.content_margin_left = 10
	off_sb.content_margin_right = 10
	var on_sb := box(DEEP.lerp(color, 0.14), color, 999, 2, 2)
	on_sb.content_margin_left = 10
	on_sb.content_margin_right = 10
	var hover_sb := off_sb.duplicate()
	hover_sb.border_color = color
	b.add_theme_stylebox_override("normal", off_sb)
	b.add_theme_stylebox_override("hover", hover_sb)
	b.add_theme_stylebox_override("pressed", on_sb)
	b.add_theme_stylebox_override("hover_pressed", on_sb)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", MUTED)
	b.add_theme_color_override("font_hover_color", color)
	b.add_theme_color_override("font_pressed_color", color)
	b.add_theme_color_override("font_hover_pressed_color", color)
	return b


## A dashed stitched line across (a divider inside a sticker).
static func stitch_line() -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func():
		var x := 0.0
		while x < line.size.x:
			line.draw_line(Vector2(x, 3), Vector2(minf(x + 5.0, line.size.x), 3), LINE, 2.0)
			x += 9.0)
	return line


## Removes all children right away (not just at the end of the frame, like queue_free alone),
## so a container can be refilled and laid out in the same frame.
static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


static func bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 10)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", box(DEEP, LINE, 5, 2, 0))
	b.add_theme_stylebox_override("fill", box(color, color, 5, 2, 0))
	return b


## Dragging this control moves the whole window (used for headers).
static func make_window_handle(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			DisplayServer.window_start_drag(control.get_window().get_window_id()))


## A tiny padlock, for locked tabs.
static func lock_icon() -> Texture2D:
	return icon("lock", 14, LOCKED)


## A tier id as a coloured tag, e.g. "legendary".
static func tier_label(tier_id: String, size := SMALL) -> Label:
	var catalog := Catalog.shared()
	return label(catalog.tier_at(catalog.rank(tier_id)).name, catalog.tier_color(tier_id), size)


## A number for people: 9,999 as it is, then 12.3k, 4.56M, 7.8B, 1.2T, then 3.4e15 (coins go big).
## A colour role by its name in data (a job's or a gear's "color"): cyan, lilac, mint, gold, else pink.
static func named_color(color_name: String) -> Color:
	match color_name:
		"cyan": return CYAN
		"lilac": return LILAC
		"mint": return MINT
		"gold": return GOLD
	return PINK


static func num(n: float) -> String:
	var a := absf(n)
	if a < 10000.0:
		return ExpandedView._thousands(roundi(n))
	var units := ["k", "M", "B", "T"]
	var v := a
	for u in units:
		v /= 1000.0
		if v < 1000.0:
			var digits := 1 if v < 100.0 else 0
			return ("-" if n < 0 else "") + (str(snappedf(v, pow(10, -digits))).trim_suffix(".0")) + u
	return "%.2e" % n


static func percent(fraction: float) -> String:
	var p := fraction * 100.0
	if p >= 10.0:
		return "%d%%" % roundi(p)
	if p >= 1.0:
		return "%.1f%%" % p
	return "%.2f%%" % p


# ---- icons ------------------------------------------------------------------

## Doodle icons: hand-drawn crayon outlines on a 24px grid (round ends, a little wobbly on
## purpose). Plain ones are drawn in `color`; coin, xp and heart are filled with their fixed colours.
const DOODLES := {
	"home": '<path d="M3.8 11.6 L12 4.1 L20.3 11.2"/><path d="M6 10.2 Q5.8 15 6.3 19.6 Q12 20.4 17.8 19.4 Q18.3 14.8 18 10.1"/><path d="M10.2 19.5 L10.4 15.2 Q12.1 13.7 13.9 15.1 L13.9 19.4"/>',
	"boxes": '<path d="M4.6 10.8 Q4.4 15.5 5 19.8 Q12 20.6 19.2 19.7 Q19.7 15 19.5 10.5"/><path d="M3.4 7.4 Q12 6.8 20.5 7.1 L20.4 10.5 Q12 11 3.6 10.7 Z"/><path d="M12 7.3 L12.1 20.1"/><path d="M12 7 Q8.3 2.4 6.9 5.3 Q7.2 7.6 12 7 Q15.8 2.3 17.2 5.2 Q16.8 7.6 12 7"/>',
	"pets": '<path d="M5 9.2 L5.4 4.4 L9 7.1 Q12 6.2 15.1 7.1 L18.6 4.3 L19.1 9.1 Q20.1 15.2 16.4 18.1 Q12 20.6 7.6 18 Q3.9 15.1 5 9.2 Z"/><circle cx="9.4" cy="12.4" r="0.9" fill="{c}"/><circle cx="14.6" cy="12.4" r="0.9" fill="{c}"/><path d="M10.9 15.2 Q12 16.4 13.1 15.2"/>',
	"trips": '<path d="M3.5 6.6 L9 4.4 L15 6.6 L20.6 4.5 L20.4 17.7 L15 19.6 L9 17.4 L3.7 19.5 Z"/><path d="M9 4.5 L9.1 17.3 M15 6.7 L14.9 19.4"/><path d="M5.8 15.2 Q7.8 11.5 11 12.6 Q13.9 13.4 16 9.6" stroke-dasharray="1.6 2.2"/>',
	"gear": '<path d="M8.1 3.7 L14 3.8 L14.2 11.9 Q19.9 12.5 20.3 16.9 L20.2 19.7 L6.8 19.8 Q5.8 15.1 7.8 12.1 Z"/><path d="M8.4 7.1 L13.7 7 M8.3 9.7 L13.8 9.6 M6.9 17.1 L20.2 17.2"/>',
	"machine": '<circle cx="11" cy="9" r="6.2"/><path d="M5.6 13.6 Q5.4 17.4 6.2 20.4 Q11 21 15.8 20.3 Q16.6 17.3 16.3 13.5"/><path d="M9.4 17.3 L12.6 17.2"/><path d="M16.4 15.2 L19.6 15.1 L19.7 10.6"/><circle cx="19.7" cy="9.4" r="1.3" fill="{c}"/><path d="M8.3 7.6 Q9 6 10.6 5.6" opacity=".6"/>',
	# machine bits (fixed colours) and the machine tree's nodes (drawn in the node's colour)
	"bit_gear": '<circle cx="12" cy="12" r="4.5" stroke="{lilac}"/><path d="M12 3 L12 6 M12 18 L12 21 M3 12 L6 12 M18 12 L21 12 M5.6 5.6 L7.8 7.8 M16.2 16.2 L18.4 18.4 M5.6 18.4 L7.8 16.2 M16.2 7.8 L18.4 5.6" stroke="{lilac}" stroke-width="2.4"/>',
	"bit_spring": '<path d="M7 4 Q17 5 7 8 Q17 9 7 12 Q17 13 7 16 Q17 17 7 20" stroke="{mint}"/>',
	"bit_bolt": '<path d="M8 5 L16 5 L17 8 L7 8 Z" fill="{gold}" stroke="{gold}" stroke-width="1.5"/><path d="M12 8 L12 20 M10 11 L14 11 M10 14 L14 14 M10 17 L14 17" stroke="{gold}"/>',
	"bit_glass": '<path d="M6 4 L18 4 L20 20 L4 20 Z" stroke="{cyan}"/><path d="M8 8 L11 7 M8 11 L10 10.4" stroke="{c}" stroke-width="1.6" opacity=".7"/>',
	"tree_tape": '<path d="M6 16 L18 8 M8 19 L20 11"/><path d="M5 12 L10 17"/>',
	"tree_oil": '<path d="M12 4 Q18 12 18 15 Q18 20 12 20 Q6 20 6 15 Q6 12 12 4 Z"/>',
	"tree_flap": '<path d="M6 8 L18 8 L18 18 L6 18 Z"/><path d="M6 8 L18 13"/>',
	"tree_glass": '<circle cx="12" cy="12" r="7"/><path d="M8.5 9.5 Q10 7.5 12.5 7"/>',
	"tree_lights": '<circle cx="6" cy="12" r="2.5"/><circle cx="12" cy="12" r="2.5"/><circle cx="18" cy="12" r="2.5"/>',
	"tree_drops": '<circle cx="12" cy="12" r="7"/><path d="M9.5 10 Q10 7.5 12.5 7.8 Q15 8.3 14.3 10.8 Q13.6 12.4 12 13 L12 14.5"/><circle cx="12" cy="17" r=".8" fill="{c}"/>',
	"tree_coin": '<path d="M12 4 L19 11 L12 20 L5 11 Z"/><path d="M5.5 11 L18.5 11"/>',
	"tree_chute": '<path d="M5 6 L10 6 L10 18 L5 18 Z M14 6 L19 6 L19 18 L14 18 Z"/>',
	"tree_balls": '<circle cx="9" cy="13" r="4.5"/><circle cx="15.5" cy="10" r="4.5"/>',
	"tree_shiny": '<circle cx="11" cy="13" r="5.5"/><path d="M18 3 L18.8 5.2 L21 6 L18.8 6.8 L18 9 L17.2 6.8 L15 6 L17.2 5.2 Z"/>',
	"errands": '<path d="M7.2 10.2 Q7.6 3.6 12 3.7 Q16.4 3.7 16.8 10.1"/><path d="M3.6 10.4 Q12 9.7 20.4 10.3 L18.6 19.7 Q12 20.6 5.4 19.8 Z"/><path d="M5 14.3 Q12 13.7 19.3 14.2 M9 10.5 L9.6 19.8 M15 10.4 L14.5 19.9" opacity=".7"/>',
	# errand doodles (drawn on a 40 grid, scaled down)
	"job_coins": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M6 26 Q6 16 20 16 Q34 16 34 26 Q34 32 20 32 Q6 32 6 26 Z"/><path d="M11 20 Q20 23 29 20" opacity=".6"/><path d="M26 7 L31 12 L26 17 L21 12 Z" stroke="{cyan}"/><path d="M11 10 L13 7 M8 12 L5 11" opacity=".7"/></g>',
	"job_scrap": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M4 33 Q12 13 20 17 Q28 9 36 33 Z"/><circle cx="15" cy="25" r="3"/><path d="M22 22 Q25 18 28 22 Q25 26 22 22 Z"/><path d="M19 11 Q21 6 24 9 Q27 12 24 14" opacity=".8"/><path d="M29 28 L32 25" opacity=".7"/></g>',
	"job_coming": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M10 20 Q10 9 20 9 Q30 9 30 20 Q30 31 20 31 Q10 31 10 20 Z" stroke-dasharray="3 4"/><path d="M16.5 16 Q17 12.5 20.5 12.8 Q24 13.4 23.2 16.8 Q22.4 19 20 20.2 L20 22.5"/><circle cx="20" cy="27" r=".9" fill="{c}"/></g>',
	"job_lemon": '<path d="M4 13 Q5 6 12 6 Q19 6 20 13 Q19 19 12 19 Q5 19 4 13 Z"/><path d="M2.5 13 L4 13 M20 13 L21.5 13"/><path d="M9 10 Q11 9 13 10" opacity=".6"/>',
	"job_jar": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M12 8 L28 8 L28 12 Q33 15 33 22 L33 30 Q33 34 28 34 L12 34 Q7 34 7 30 L7 22 Q7 15 12 12 Z"/><path d="M11 5 L29 5" /><path d="M16 5 L24 5" stroke="{gold}" opacity=".8"/><path d="M13 24 L20 20 L27 24 L20 28 Z" stroke="{gold}"/><path d="M11 17 Q12 15 14 14.5" opacity=".6"/></g>',
	"job_kitchen": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M6 20 L34 20 L32 31 Q31 34 27 34 L13 34 Q9 34 8 31 Z"/><path d="M3 20 L37 20"/><path d="M14 15 Q12 12 14 9 Q16 6 14 3 M21 15 Q19 12 21 9 Q23 6 21 3 M28 15 Q26 12 28 9" opacity=".7"/></g>',
	"job_scout": '<g transform="scale(0.6)" stroke-width="3.2"><path d="M8 7 L27 7 L32 12 L32 34 L8 34 Z"/><path d="M27 7 L27 12 L32 12"/><path d="M13 16 L26 16 M13 21 L22 21" opacity=".6"/><path d="M13 28 Q17 24 20 27 Q23 30 27 26" stroke-dasharray="2 3"/></g>',
	# automation (the tab, and the machine job's tools)
	"automation": '<circle cx="12" cy="12" r="2.6"/><path d="M12 5.2 Q16.8 5.4 18.6 9.6 Q19.4 14.6 15.6 17.8 Q11 20.4 6.8 17.4 Q3.9 13.6 5.8 8.6 Q7.8 5.4 12 5.2 Z"/><path d="M12 2.6 L12 5.2 M12 18.8 L12 21.4 M2.6 12 L5.2 12 M18.8 12 L21.4 12 M5.4 5.4 L7.1 7.1 M16.9 16.9 L18.6 18.6 M5.4 18.6 L7.1 16.9 M16.9 7.1 L18.6 5.4"/>',
	"auto_speed": '<path d="M4 16 Q4 8 12 8 Q20 8 20 16"/><path d="M12 16 L16 10"/><path d="M4 16 L20 16" opacity=".6"/>',
	"auto_stool": '<path d="M5 9 Q12 6 19 9 L19 11 Q12 13 5 11 Z"/><path d="M7 12 L6 20 M17 12 L18 20 M12 13 L12 20"/>',
	"whistle": '<path d="M3.6 10.2 L13.4 9.8 Q19.8 9.6 20.2 14.6 Q20.1 19.6 14.8 19.8 Q9.8 19.6 9.6 14.8 L3.8 14.4 Z"/><path d="M6.6 10.1 L6.8 12.6" opacity=".7"/><circle cx="14.9" cy="14.7" r="1.6"/><path d="M4.2 7.2 Q3.4 5 4.8 3.6 M8 6.8 Q8.2 4.6 9.8 3.8" opacity=".7"/>',
	"pencil": '<path d="M5 19 L6.2 14.6 L16.4 4.4 L19.6 7.6 L9.4 17.8 Z"/><path d="M14.4 6.4 L17.6 9.6"/><path d="M5 19 L9.4 17.8" opacity=".6"/>',
	"wagon": '<path d="M3.4 9.4 L20.6 9.4 L19 16 L5 16 Z"/><circle cx="8" cy="18.4" r="2"/><circle cx="16" cy="18.4" r="2"/><path d="M20.6 9.4 L22.4 5.6"/>',
	"tool_nose": '<path d="M6 13 Q6 7 12 7 Q18 7 18 13 Q18 17 12 17 Q6 17 6 13 Z"/><path d="M10 12.5 L10 13.5 M14 12.5 L14 13.5"/><path d="M3 9 L5 10 M21 9 L19 10 M4 5 L6 7" opacity=".7"/>',
	"tool_paw": '<path d="M8 15 Q8 11 12 11 Q16 11 16 15 Q16 19 12 19 Q8 19 8 15 Z"/><circle cx="7" cy="9" r="1.8"/><circle cx="10.5" cy="6" r="1.8"/><circle cx="14" cy="6" r="1.8"/><circle cx="17.3" cy="9" r="1.8"/>',
	"tool_pocket": '<path d="M5 6 L19 6 L18 16 Q12 21 6 16 Z"/><path d="M5 9 L19 9" opacity=".7"/><path d="M12 12 L14 14 L12 16 L10 14 Z"/>',
	"tool_lemon": '<path d="M4 13 Q5 6 12 6 Q19 6 20 13 Q19 19 12 19 Q5 19 4 13 Z"/><path d="M2.5 13 L4 13 M20 13 L21.5 13"/><path d="M9 10 Q11 9 13 10" opacity=".6"/>',
	"tool_sign": '<path d="M4 5 L20 5 L20 13 L4 13 Z"/><path d="M8 13 L8 20 M16 13 L16 20"/><path d="M7 9 L17 9" opacity=".6"/>',
	"tool_cup": '<path d="M6 7 L18 7 L16.5 20 L7.5 20 Z"/><path d="M14 3 L12 12"/><path d="M7 11 L17 11" opacity=".6"/>',
	"tool_jar": '<path d="M7 5 L17 5 L17 7.5 Q20 9.5 20 13 L20 18 Q20 20.5 17 20.5 L7 20.5 Q4 20.5 4 18 L4 13 Q4 9.5 7 7.5 Z"/><path d="M9 14 L12 12 L15 14 L12 16 Z"/>',
	"tool_slot": '<path d="M4 9 Q12 7 20 9 L20 12 Q12 14 4 12 Z"/><path d="M8 10.5 L16 10.5" stroke-width="2.6"/><path d="M12 3 L14.5 5.5 L12 8 L9.5 5.5 Z"/><path d="M6 15 L6 20 M18 15 L18 20 M6 20 L18 20" opacity=".7"/>',
	"tool_case": '<path d="M4 8 L20 8 L20 19 L4 19 Z"/><path d="M9 8 L9 5.5 L15 5.5 L15 8"/><path d="M4 12 L20 12" opacity=".7"/><path d="M11 12 L13 12 L13 14 L11 14 Z"/>',
	"tool_glasses": '<circle cx="7.5" cy="14" r="4"/><circle cx="16.5" cy="14" r="4"/><path d="M11.5 13 Q12 11.5 12.5 13"/><path d="M5 10 L7 5 M19 10 L17 5" opacity=".7"/>',
	"tool_snack": '<circle cx="12" cy="12" r="7.5"/><circle cx="9.5" cy="10" r="1"/><circle cx="14" cy="9.5" r="1"/><circle cx="13" cy="14.5" r="1"/><path d="M16.5 6.5 Q19 8 19 10" opacity=".6"/>',
	"tool_nap": '<path d="M16 4 Q10 5 10 11 Q10 17 17 18 Q13 21 9 19.5 Q4 17 4.5 11 Q5 5 12 3.6 Q14.4 3.4 16 4 Z"/><path d="M17 7 L20 7 L17 10 L20 10" opacity=".8"/>',
	"tool_pebble": '<path d="M5 15 Q4 9 11 8.5 Q18 8 19 14 Q19.5 18.5 12 18.5 Q5.5 18.5 5 15 Z"/><path d="M18 2.5 L18.7 4.3 L20.5 5 L18.7 5.7 L18 7.5 L17.3 5.7 L15.5 5 L17.3 4.3 Z"/>',
	"tool_team": '<circle cx="8" cy="9" r="3"/><circle cx="16" cy="9" r="3"/><path d="M3.5 19 Q4 14 8 14 Q10.5 14 12 16 Q13.5 14 16 14 Q20 14 20.5 19"/>',
	# gear (the adventures' upgrades page, drawn on a 40 grid, scaled down)
	"gear_boots": '<g transform="scale(0.6)" stroke-width="3"><path d="M13 5 L22 5 L22.4 20 Q32 21 33 28 L33 33 L10 33 Q8.6 25 12 20 Z"/><path d="M13.5 10 L21.6 10 M13.4 14.2 L21.8 14.2 M10.3 29 L33 29"/></g>',
	"gear_tote": '<g transform="scale(0.6)" stroke-width="3"><path d="M14 13 Q14 5 20 5 Q26 5 26 13"/><path d="M7 13 Q20 12 33 13 L32 33 Q20 34.5 8 33 Z"/><path d="M16 21 Q20 24 24 21"/></g>',
	"gear_pouch": '<g transform="scale(0.6)" stroke-width="3"><path d="M13 14 Q6 22 9 30 Q20 36 31 30 Q34 22 27 14"/><path d="M11 14 Q20 10 29 14"/><path d="M16 12 L13 6 M24 12 L27 6"/><path d="M15 24 Q15 21 17.5 22 L22.5 22 Q25 21 25 24 Q25 27 22.5 26 L17.5 26 Q15 27 15 24 Z" stroke="{pink}"/></g>',
	"gear_paws": '<g transform="scale(0.6)" stroke-width="3"><circle cx="11" cy="14" r="3.2"/><circle cx="17.5" cy="9.5" r="3.2"/><circle cx="24.5" cy="9.5" r="3.2"/><circle cx="31" cy="14" r="3.2"/><path d="M12 27 Q12 18 21 18 Q30 18 30 27 Q30 33 21 32 Q12 33 12 27 Z"/></g>',
	"gear_eyes": '<g transform="scale(0.6)" stroke-width="3"><path d="M3 22 Q11 12 19 22 Q11 31 3 22 Z"/><circle cx="11" cy="22" r="2.6" fill="{c}"/><path d="M21 22 Q29 12 37 22 Q29 31 21 22 Z"/><circle cx="29" cy="22" r="2.6" fill="{c}"/><path d="M31 3 L32.2 6.8 L36 8 L32.2 9.2 L31 13 L29.8 9.2 L26 8 L29.8 6.8 Z" stroke="{gold}" stroke-width="2"/></g>',
	"gear_charm": '<g transform="scale(0.6)" stroke-width="3"><path d="M20 5 L20 10"/><path d="M12 22 Q12 11 20 11 Q28 11 28 22 L30 27 L10 27 Z"/><circle cx="20" cy="31" r="2.6"/><path d="M33 8 L33 13 M30.5 10.5 L35.5 10.5" stroke="{gold}"/></g>',
	"gear_leaf": '<g transform="scale(0.6)" stroke-width="3"><path d="M8 32 Q6 12 30 8 Q34 30 12 32 Z"/><path d="M10 30 Q18 22 26 13" opacity=".6"/><path d="M18 19 L24 19 M21 16 L21 22" stroke="{pink}"/></g>',
	"gear_harness": '<g transform="scale(0.6)" stroke-width="3"><path d="M7 13 Q20 7 33 13"/><path d="M6 13 Q5 29 20 32 Q35 29 34 13"/><path d="M13 11 L14 31 M27 11 L26 31" opacity=".6"/><circle cx="20" cy="21" r="3.6" stroke="{gold}"/><path d="M20 5 Q24 5 24 8 Q24 11 20 11 Q16 11 16 8 Q16 5 20 5 Z"/></g>',
	# knacks (the sewn badges, data/knacks.json kinds; from design/mockups/screens/knacks.html)
	"knack_coins": '<path d="M12 3 L19.6 10.4 L12 21.2 L4.4 10.4 Z" fill="{cyan}" stroke="{cyan}"/><path d="M5 10.4 L19 10.4 M9.2 10.4 L12 4.2 L14.8 10.4 L12 19.8 L9.2 10.4" stroke="{page}" stroke-width="1.1"/>',
	"knack_xp": '<path d="M12 2.6 Q13.1 10 21.4 12 Q13.1 14 12 21.4 Q10.9 14 2.6 12 Q10.9 10 12 2.6 Z" fill="{gold}" stroke="{gold}"/>',
	"knack_luck": '<circle cx="8.8" cy="8.6" r="3.3"/><circle cx="15.2" cy="8.8" r="3.3"/><circle cx="8.7" cy="14.8" r="3.3"/><circle cx="15.1" cy="15" r="3.3"/><path d="M12.2 12.2 Q15.6 17 19.4 20.8"/>',
	"knack_all": '<path d="M12 3.8 L14.1 9.4 L19.8 9.8 L15.4 13.5 L16.8 19.2 L12 16 L7.2 19.2 L8.6 13.5 L4.2 9.8 L9.9 9.4 Z"/>',
	"knack_speed": '<circle cx="12" cy="10" r="6.8"/><path d="M5.3 10 Q12 12.4 18.7 10"/><path d="M7.4 16 L6.6 20.4 Q12 21.2 17.4 20.4 L16.6 16"/>',
	"knack_fever": '<path d="M12 21 Q6 20.4 6.1 14.6 Q6.3 10.2 10 7.2 Q10.2 10 12.1 11 Q11.8 6 15 3.2 Q15.2 8 17.6 11 Q19.2 13.6 18.1 16.6 Q16.8 20.6 12 21 Z"/>',
	"knack_toys": '<circle cx="12" cy="13.4" r="6.2"/><circle cx="6.8" cy="6.9" r="2.5"/><circle cx="17.2" cy="6.9" r="2.5"/><path d="M10.2 15.6 Q12 17 13.8 15.6"/>',
	"knack_loot": '<path d="M9.2 5.6 L14.8 5.6 L13.4 8.4 Q19.2 10.8 19.2 15.8 Q19.2 20.6 12 20.5 Q4.8 20.6 4.8 15.8 Q4.8 10.8 10.6 8.4 Z"/><path d="M10.4 8.5 L13.6 8.5"/>',
	"knack_spots": '<path d="M8.4 20.4 Q4.8 12.4 7 3.8 Q10.4 4.6 11.2 12 Q11.4 17 10.4 20.4"/><path d="M13.8 20.4 Q12.8 17 13 12 Q13.8 4.6 17.2 3.8 Q19.4 12.4 15.8 20.4"/>',
	"knack_trip": '<path d="M8.1 3.7 L13.4 3.8 L13.6 11.9 Q19.4 12.5 19.8 16.9 L19.7 19.7 L6.8 19.8 Q5.8 15.1 7.8 12.1 Z"/><path d="M6.9 17.1 L19.7 17.2"/>',
	"knack_tough": '<path d="M12 20.1 Q3.4 13.6 4.3 8.4 Q5.4 4.2 9.3 5.1 Q11.2 5.7 12 8 Q12.9 5.6 14.8 5.1 Q18.7 4.3 19.7 8.4 Q20.6 13.5 12 20.1 Z"/><path d="M8.8 11.2 L15.2 13.4"/>',
	"knack_safe": '<path d="M3.8 11.6 L12 4.1 L20.3 11.2"/><path d="M6 10.2 Q5.8 15 6.3 19.6 Q12 20.4 17.8 19.4 Q18.3 14.8 18 10.1"/><path d="M12 17.4 Q8.6 15 9.4 13.2 Q10.6 11.6 12 13.4 Q13.4 11.6 14.6 13.2 Q15.4 15 12 17.4 Z"/>',
	"knack_errands": '<path d="M6.2 5.4 L17.8 5.3 L17.6 20.4 L6.4 20.5 Z"/><path d="M9.6 5.3 L9.8 3.6 L14.3 3.6 L14.4 5.3"/><path d="M9 10.2 L15 10.1 M9 14 L14 14"/>',
	"knack_automation": '<circle cx="12" cy="12" r="2.6"/><path d="M12 5.2 Q16.8 5.4 18.6 9.6 Q19.4 14.6 15.6 17.8 Q11 20.4 6.8 17.4 Q3.9 13.6 5.8 8.6 Q7.8 5.4 12 5.2 Z"/><path d="M12 2.6 L12 5.2 M12 18.8 L12 21.4 M2.6 12 L5.2 12 M18.8 12 L21.4 12"/>',
	"knack_away": '<path d="M14.6 4 Q8 5.2 8.1 12 Q8.2 18.8 14.8 20 Q9.4 21.6 6 17.6 Q3 13.2 5.4 8.2 Q8.4 3.6 14.6 4 Z"/><path d="M17.4 7.4 L17.4 10.6 M15.8 9 L19 9"/>',
	"knack_finds": '<path d="M12 3.6 L19.4 7.8 L19.3 16.2 L12 20.4 L4.6 16.1 L4.7 7.8 Z"/><circle cx="12" cy="12" r="3.1"/>',
	"knack_pickups": '<circle cx="6.8" cy="10.2" r="1.8"/><circle cx="10.4" cy="6.6" r="1.8"/><circle cx="14.4" cy="6.6" r="1.8"/><circle cx="17.8" cy="10.2" r="1.8"/><path d="M8 17 Q8.1 12.2 12.3 12.1 Q16.6 12.2 16.8 17 Q16.8 20.2 12.4 19.6 Q8 20.2 8 17 Z"/>',
	"knack_treats": '<path d="M8.2 12 Q8.2 8 12 8 Q15.8 8 15.8 12 Q15.8 16 12 16 Q8.2 16 8.2 12 Z"/><path d="M8.2 12 L4 8.8 L4.2 15.2 Z M15.8 12 L20 8.8 L19.8 15.2 Z"/>',
	"knack_rummage": '<circle cx="10.4" cy="10.4" r="5.6"/><path d="M14.6 14.6 L20 20.2"/>',
	"knack_shiny": '<path d="M11 3 Q12 10 19.6 11.2 Q12 12.4 11 20 Q10 12.4 2.8 11.2 Q10 10 11 3 Z"/><path d="M18.6 3.2 L18.6 7 M16.7 5.1 L20.5 5.1"/>',
	"knack_pet_boxes": '<path d="M4.6 10.8 Q4.4 15.5 5 19.8 Q12 20.6 19.2 19.7 Q19.7 15 19.5 10.5"/><path d="M3.4 7.4 Q12 6.8 20.5 7.1 L20.4 10.5 Q12 11 3.6 10.7 Z"/><path d="M12 7.3 L12.1 20.1"/>',
	"knack_power": '<path d="M12 3.6 L19 6.2 Q19.2 15 12 20.6 Q4.8 15 5 6.2 Z"/><path d="M9 11.6 L11.4 14 L15.2 9.6"/>',
	"star": '<path d="M12 2.5 L14.6 9 L21.5 9.4 L16.2 13.8 L17.9 20.6 L12 16.9 L6.1 20.6 L7.8 13.8 L2.5 9.4 L9.4 9 Z" fill="{c}"/>',
	"bag": '<path d="M8.4 8.2 Q8.5 3.7 12 3.8 Q15.5 3.8 15.6 8.1"/><path d="M4.7 8.3 Q12 7.6 19.3 8.2 L18.7 19.6 Q12 20.5 5.3 19.7 Z"/><path d="M9.5 12.5 Q12 14.1 14.5 12.4"/>',
	"lock": '<path d="M7.4 11 Q7 4.3 12 4.2 Q17 4.2 16.7 11"/><path d="M5 11.1 Q12 10.5 19 10.9 L18.7 19.8 Q12 20.5 5.3 19.9 Z"/><path d="M12 14.2 L12 16.4"/>',
	"settings": '<circle cx="12" cy="12" r="2.4"/><path d="M12 3.6 Q14.6 3.8 13.9 7.2 M12 3.6 Q9.4 3.8 10.1 7.2 M19.3 7.8 Q20.4 10.2 17.1 11.1 M19.3 7.8 Q17.7 5.7 15.3 8.3 M19.3 16.2 Q17.9 18.4 15.3 15.8 M19.3 16.2 Q20.5 13.9 17.1 12.9 M12 20.4 Q9.4 20.2 10.1 16.8 M12 20.4 Q14.6 20.2 13.9 16.8 M4.7 16.2 Q3.6 13.8 6.9 12.9 M4.7 16.2 Q6.3 18.3 8.7 15.7 M4.7 7.8 Q6.1 5.6 8.7 8.2 M4.7 7.8 Q3.5 10.1 6.9 11.1"/>',
	"coin": '<path d="M12 3 L19.6 10.4 L12 21.2 L4.4 10.4 Z" fill="{cyan}" stroke="{cyan}"/><path d="M5 10.4 L19 10.4 M9.2 10.4 L12 4.2 L14.8 10.4 L12 19.8 L9.2 10.4" stroke="{page}" stroke-width="1.1"/>',
	"xp": '<path d="M12 2.6 Q13.1 10 21.4 12 Q13.1 14 12 21.4 Q10.9 14 2.6 12 Q10.9 10 12 2.6 Z" fill="{gold}" stroke="{gold}"/>',
	"heart": '<path d="M12 20.1 Q3.4 13.6 4.3 8.4 Q5.4 4.2 9.3 5.1 Q11.2 5.7 12 8 Q12.9 5.6 14.8 5.1 Q18.7 4.3 19.7 8.4 Q20.6 13.5 12 20.1 Z" fill="{pink}" stroke="{pink}"/>',
}

## Pixel icons (9x9): "o" is the icon's colour, other letters are fixed colours.
const PIXELS := {
	"home": ["....o....", "...o.o...", "..o...o..", ".o.....o.", "ooooooooo", ".o.....o.", ".o.oo..o.", ".o.oo..o.", ".ooooooo."],
	"boxes": [".oo...oo.", "..o.o.o..", "ooooooooo", "o...o...o", "ooooooooo", ".o..o..o.", ".o..o..o.", ".o..o..o.", ".ooooooo."],
	"pets": [".ooooo...", ".o...oo..", ".o.o.o.o.", ".o...o.o.", ".o.o.o.o.", ".o...o.o.", ".ooooo.o.", "..o....o.", "..oooooo."],
	"trips": ["..o...o..", ".ooo.ooo.", "..o...o..", "o.......o", "oo.ooo.oo", "..ooooo..", ".ooooooo.", ".ooooooo.", "..ooooo.."],
	"gear": ["..oooo...", "..o..o...", "..o..o...", "..o..o...", "..o..ooo.", ".o......o", "o.......o", "ooooooooo", ".o.o.o.o."],
	"machine": ["..ooooo..", ".o.....o.", ".o.o...o.", ".o.....o.", "..ooooo.o", ".ooooooo.", ".o.....oo", ".o.ooo.o.", ".ooooooo."],
	"errands": ["...ooo...", "..o...o..", ".o.....o.", "ooooooooo", "o.o.o.o.o", ".ooooooo.", ".o.o.o.o.", ".ooooooo.", "........."],
	"bag": ["...ooo...", "..o...o..", ".ooooooo.", "o.......o", "o..ooo..o", "o.......o", "o.......o", "o.......o", ".ooooooo."],
	"lock": [".........", "...ooo...", "..o...o..", "..o...o..", ".ooooooo.", ".ooo.ooo.", ".ooo.ooo.", ".ooooooo.", "........."],
	"automation": ["....o....", ".o.ooo.o.", "..o...o..", ".o..o..o.", "oo.ooo.oo", ".o..o..o.", "..o...o..", ".o.ooo.o.", "....o...."],
	"settings": ["...o.o...", ".ooooooo.", ".o.....o.", "oo..o..oo", "o..ooo..o", "oo..o..oo", ".o.....o.", ".ooooooo.", "...o.o..."],
	"coin": ["....w....", "...wab...", "..waaab..", ".waaaaab.", "waaaaaaab", ".aaaaabb.", "..aaabb..", "...abb...", "....b...."],
	"xp": ["....g....", "....g....", "...ggg...", "..ggwgg..", "gggwwwggg", "..ggwgg..", "...ggg...", "....g....", "....g...."],
	"heart": [".pp...pp.", "pwpp.pppp", "pwppppppp", "ppppppppd", ".pppppdd.", "..pppdd..", "...pdd...", "....d....", "........."],
}


## An icon at `size` px (drawn at 2x so it stays crisp on scaled screens), in the player's style.
static func icon(icon_name: String, size := 18, color := TEXT, style := "") -> Texture2D:
	if style == "":
		style = ICON_STYLE
	var key := "%s|%d|%s|%s" % [icon_name, size, color.to_html(), style]
	if _icons.has(key):
		return _icons[key]
	var tex: Texture2D
	if style == "pixel" and PIXELS.has(icon_name):
		tex = _pixel_texture(icon_name, size * 2, color)
	elif DOODLES.has(icon_name):
		var body: String = DOODLES[icon_name].replace("{c}", _hex(color)).replace("{cyan}", _hex(CYAN)).replace("{gold}", _hex(GOLD)).replace("{pink}", _hex(PINK)).replace("{page}", _hex(PAGE)).replace("{mint}", _hex(MINT)).replace("{lilac}", _hex(LILAC))
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [_hex(color), body]
		tex = _svg_texture(svg, size * 2 / 24.0)
	_icons[key] = tex
	return tex


## An icon as a control, shown at `size` px.
static func icon_rect(icon_name: String, size := 18, color := TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon(icon_name, size, color)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if ICON_STYLE == "pixel" else CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _pixel_texture(icon_name: String, size: int, color: Color) -> ImageTexture:
	var shine := { "xp": Color("fff6d6"), "heart": Color("ffd1ea") }
	var fixed := { "w": shine.get(icon_name, Color("e8fbff")), "a": CYAN, "b": CYAN.darkened(0.3), "g": GOLD, "p": PINK, "d": PINK.darkened(0.2) }
	var rows: Array = PIXELS[icon_name]
	var img := Image.create_empty(9, 9, false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			var ch: String = rows[y][x]
			if ch == "o":
				img.set_pixel(x, y, color)
			elif fixed.has(ch):
				img.set_pixel(x, y, fixed[ch])
	img.resize(size, size, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(img)


static func _svg_texture(svg: String, scale: float) -> ImageTexture:
	var img := Image.new()
	img.load_svg_from_string(svg, scale)
	return ImageTexture.create_from_image(img)


static func _switch_svg(on: bool) -> String:
	var knob_x := 27 if on else 11
	return '<svg xmlns="http://www.w3.org/2000/svg" width="40" height="22"><rect x="1" y="1" width="38" height="20" rx="10" fill="%s" stroke="%s" stroke-width="2"/><circle cx="%d" cy="11" r="7" fill="%s"/></svg>' % [
		_hex(PINK_PRESSED if on else DEEP), _hex(PINK if on else LINE), knob_x, _hex(PINK if on else MUTED)]


# ---- data -------------------------------------------------------------------

static func _load_data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(THEMES_PATH))
		_data = parsed if parsed is Dictionary else {}
	return _data


static func _find(list: Array, id: String) -> Dictionary:
	for entry: Dictionary in list:
		if entry.get("id", "") == id:
			return entry
	return list[0] if not list.is_empty() else {}


static func _c(colors: Dictionary, key: String, fallback: Color) -> Color:
	return Color(colors[key]) if colors.has(key) else fallback


## A font from a font set's spec in data/themes.json, e.g. { "file": "Fredoka.ttf", "wght": 700 }.
static func font_for(spec: Dictionary) -> Font:
	return _font(spec)


static func _font(spec: Dictionary) -> Font:
	var base: FontFile = load(FONTS_DIR + str(spec.get("file", "MapleMono-Regular.ttf")))
	if not spec.has("wght"):
		return base
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = { TextServerManager.get_primary_interface().name_to_tag("wght"): float(spec.wght) }
	return v


static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)
