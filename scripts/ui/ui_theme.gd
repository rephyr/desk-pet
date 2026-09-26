class_name UiTheme
extends RefCounted
## The game's look in one place: colours, the Theme, and small widget helpers.

const PINK := Color("ff79c6")
const LILAC := Color("c9a0ff")
const CYAN := Color("8be9fd")
const TEXT := Color("f5dcec")
const MUTED := Color("9a88ad")
const BG := Color("1a1024")
const BG_DEEP := Color("120a19")
const BG_RAISED := Color("241634")

const FONT_NAMES := ["Maple Mono", "Maple Mono NF", "monospace"]  # TODO: bundle a font for release
const FONT_SIZE := 13
const SMALL := 11

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme == null:
		_theme = _build()
	return _theme


static func _build() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(FONT_NAMES)
	t.default_font = font
	t.default_font_size = FONT_SIZE
	t.set_color("font_color", "Label", TEXT)

	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
			var sb := box(BG_DEEP, LILAC.darkened(0.45), 8)
			match state:
				"hover": sb.border_color = PINK
				"pressed", "hover_pressed":
					sb.bg_color = PINK.darkened(0.65)
					sb.border_color = PINK
				"disabled":
					sb.border_color = MUTED.darkened(0.5)
				"focus": sb.draw_center = false
			t.set_stylebox(state, type, sb)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, PINK)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, TEXT)
		t.set_color("font_disabled_color", type, MUTED.darkened(0.2))

	t.set_stylebox("panel", "PanelContainer", box(BG, PINK.darkened(0.3), 14, 2, 12))
	t.set_stylebox("panel", "PopupMenu", box(BG_DEEP, LILAC.darkened(0.3), 8))
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_hover_color", "PopupMenu", PINK)
	t.set_stylebox("hover", "PopupMenu", box(BG_RAISED, BG_RAISED, 6))
	t.set_stylebox("panel", "TooltipPanel", box(BG_DEEP, LILAC.darkened(0.3), 6))
	t.set_color("font_color", "TooltipLabel", TEXT)

	var grabber := box(LILAC.darkened(0.4), LILAC.darkened(0.4), 4, 0, 0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", box(LILAC.darkened(0.2), LILAC.darkened(0.2), 4, 0, 0))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(PINK.darkened(0.2), PINK.darkened(0.2), 4, 0, 0))
	t.set_stylebox("scroll", "VScrollBar", box(BG_DEEP, BG_DEEP, 4, 0, 0))
	return t


# ---- helpers --------------------------------------------------------------

static func box(bg: Color, border: Color, radius: int, border_width := 2, margin := 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	return sb


static func label(text: String, color := TEXT, size := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
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
	b.add_theme_font_size_override("font_size", FONT_SIZE + 2)
	return b


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
	b.add_theme_stylebox_override("background", box(BG_DEEP, color.darkened(0.5), 5, 2, 0))
	b.add_theme_stylebox_override("fill", box(color, color, 5, 2, 0))
	return b


## Dragging this control moves the whole window (used for headers).
static func make_window_handle(control: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	control.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			DisplayServer.window_start_drag(control.get_window().get_window_id()))


## A tier id as a coloured tag, e.g. "legendary".
static func tier_label(tier_id: String, size := SMALL) -> Label:
	var catalog := Catalog.shared()
	return label(catalog.tier_at(catalog.rank(tier_id)).name, catalog.tier_color(tier_id), size)


static func percent(fraction: float) -> String:
	var p := fraction * 100.0
	if p >= 10.0:
		return "%d%%" % roundi(p)
	if p >= 1.0:
		return "%.1f%%" % p
	return "%.2f%%" % p
