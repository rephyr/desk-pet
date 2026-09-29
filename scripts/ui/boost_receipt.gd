class_name BoostReceipt
extends Control
## The boost receipt (look A, the dark till roll): what the x1.51 tag by the coin pill opens. A dark
## torn receipt printed out of a slot: "our boosts" with the date, then every kind with a shared boost
## (toys, your pet's badges, and later book stickers and the kitchen), a header per kind with its
## total and one dotted-leader line per thing doing it, "thank you, come again ♪" and a barcode.
## 260 x 320; more lines make it taller down to `max_height`, then the lines scroll. The rows come
## from GameState.boost_receipt(). Also holds the paper drawing the "why so much?" slip shares.
## Design: design/mockups/screens/receipt.html (look A).

const WIDTH := 260.0
const HEIGHT := 320.0
const TOOTH := 7.0  # the torn bottom's teeth
const PAD := Vector4(16, 12, 16, 16)  # left, top, right, bottom inside the paper (the teeth come on top)
const BARS := [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 3, 2, 1, 1, 2]

var max_height := HEIGHT  # the most room it has (the page below the tag)
var _inner := VBoxContainer.new()
var _date := UiTheme.label("", UiTheme.MUTED, 10)
var _scroll := ScrollContainer.new()
var _kinds := VBoxContainer.new()
var _lines := MarginContainer.new()  # the kinds, with room for the scrollbar when they scroll
var _shown := ""  # the rows last shown, to rebuild only when they change
var _tween: Tween
var _open := false


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP  # the tab under it doesn't take the clicks
	size = Vector2(WIDTH, HEIGHT)
	visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", int(PAD.x))
	margin.add_theme_constant_override("margin_top", int(PAD.y))
	margin.add_theme_constant_override("margin_right", int(PAD.z))
	margin.add_theme_constant_override("margin_bottom", int(PAD.w + TOOTH))
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(margin)
	_inner.add_theme_constant_override("separation", 0)
	_inner.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(_inner)
	var title := UiTheme.title("our boosts", 17, UiTheme.PINK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(title)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_inner.add_child(_date)
	_inner.add_child(rule(UiTheme.LILAC_SEAM, 12))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var bar := _scroll.get_v_scroll_bar()
	bar.custom_minimum_size.x = 4
	bar.add_theme_stylebox_override("scroll", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 2, 0, 0))
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, UiTheme.box(UiTheme.LILAC_SEAM, UiTheme.LILAC_SEAM, 2, 0, 0))
	_kinds.add_theme_constant_override("separation", 4)
	_lines.size_flags_horizontal = SIZE_EXPAND_FILL
	_lines.add_theme_constant_override("margin_right", 0)
	_lines.add_child(_kinds)
	_scroll.add_child(_lines)
	_inner.add_child(_scroll)
	var thanks := HBoxContainer.new()
	thanks.add_theme_constant_override("separation", 8)
	var words := UiTheme.label("thank you, come again ♪", UiTheme.MUTED, 10)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	thanks.add_child(words)
	thanks.add_child(barcode(UiTheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	_inner.add_child(gap)
	_inner.add_child(thanks)


func is_open() -> bool:
	return _open


## Prints it out of the slot (it unrolls downwards from the top).
func open() -> void:
	_open = true
	refresh(true)
	visible = true
	pivot_offset = Vector2(WIDTH * 0.7, 0)
	scale = Vector2(1, 0.1)
	modulate.a = 0.0
	_play(Vector2.ONE, 1.0, 0.22)


## Folds it back up into the slot.
func fold() -> void:
	if not _open:
		return
	_open = false
	_play(Vector2(1, 0.1), 0.0, 0.18).finished.connect(func():
		if not _open:
			visible = false)


func _play(to_scale: Vector2, to_alpha: float, seconds: float) -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel()
	_tween.tween_property(self, "scale", to_scale, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "modulate:a", to_alpha, seconds * 0.8)
	return _tween


## Shows the boosts as they are now (rebuilt only when something changed, unless `force`).
func refresh(force := false) -> void:
	var rows := GameState.boost_receipt()
	var key := str(rows)
	if key == _shown and not force:
		return
	_shown = key
	var now := Time.get_datetime_dict_from_system()
	var days := ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
	var months := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
	_date.text = "%s %d %s, %02d:%02d" % [days[int(now.weekday)], int(now.day), months[int(now.month) - 1], int(now.hour), int(now.minute)]
	UiTheme.clear(_kinds)
	for row in rows:
		_kinds.add_child(_kind(row))
	_fit()


## As tall as its lines need (never under HEIGHT), up to max_height; past that the lines scroll.
func _fit() -> void:
	var lines := _kinds.get_combined_minimum_size().y
	var rest := _inner.get_combined_minimum_size().y - _scroll.get_combined_minimum_size().y
	var want := PAD.y + rest + lines + PAD.w + TOOTH
	size = Vector2(WIDTH, clampf(want, minf(HEIGHT, max_height), maxf(max_height, 120.0)))
	_lines.add_theme_constant_override("margin_right", 8 if want > size.y + 0.5 else 0)
	queue_redraw()


func _process(_delta: float) -> void:
	if _open and Engine.get_process_frames() % 30 == 0:
		refresh()  # a play may have run out, a toy levelled


func _kind(row: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var coins: bool = row.kind == "coins"
	head.add_child(UiTheme.icon_rect("coin" if coins else "knack_" + str(row.kind), 16, UiTheme.LILAC))
	var name := UiTheme.title(str(row.name), 13, UiTheme.LILAC)
	name.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(name)
	head.add_child(UiTheme.title(Boosts.times(float(row.total)), 14, UiTheme.CYAN if coins else UiTheme.PINK))
	col.add_child(head)
	for l in row.lines:
		var line := leader(str(l.name), Boosts.times(float(l.x)), UiTheme.TEXT, UiTheme.MUTED)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_left", 22)
		pad.add_child(line)
		col.add_child(pad)
	return col


func _draw() -> void:
	draw_paper(self, Rect2(Vector2.ZERO, size), UiTheme.RAISED, UiTheme.LILAC_SEAM, TOOTH)
	# the slot it prints out of
	draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.LILAC_SEAM, 4, 2, 0), Rect2(-6, -4, size.x + 12, 8))


# ---- paper bits both papers use ------------------------------------------------------

## A piece of till paper: a straight top, a torn (zigzag) bottom, a soft shadow under it.
static func draw_paper(ci: CanvasItem, rect: Rect2, fill: Color, stroke: Color, tooth := TOOTH) -> void:
	var pts := paper_points(rect, tooth)
	var shade := PackedVector2Array()
	for p in pts:
		shade.append(p + Vector2(0, 6))
	ci.draw_colored_polygon(shade, Color(UiTheme.SHADOW, 0.45))
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, stroke, 2.0, true)


static func paper_points(rect: Rect2, tooth: float) -> PackedVector2Array:
	var w := rect.size.x
	var h := rect.size.y
	var n := maxi(2, roundi(w / (tooth * 1.6)))
	var pts := PackedVector2Array([rect.position, rect.position + Vector2(w, 0)])
	for i in range(n, -1, -1):
		pts.append(rect.position + Vector2(w * i / n, h - tooth + (tooth * 0.8 if i % 2 == 1 else 0.0)))
	return pts


## A little barcode (as in the mockup), `color` bars 12 tall.
static func barcode(color: Color) -> Control:
	var c := Control.new()
	c.mouse_filter = MOUSE_FILTER_IGNORE
	var w := 0.0
	for i in BARS.size():
		w += BARS[i] + (0 if i % 2 == 1 else 1)
	c.custom_minimum_size = Vector2(w, 12)
	c.size_flags_vertical = SIZE_SHRINK_CENTER
	c.draw.connect(func():
		var x := 0.0
		for i in BARS.size():
			if i % 2 == 0:
				c.draw_rect(Rect2(x, 0, BARS[i], 12), color)
			x += BARS[i] + (0 if i % 2 == 1 else 1))
	return c


## A dashed rule across (5 on, 4 off), `height` tall with the dashes in the middle.
static func rule(color: Color, height := 8) -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, height)
	line.mouse_filter = MOUSE_FILTER_IGNORE
	line.draw.connect(func():
		var x := 0.0
		var y := height / 2.0
		while x < line.size.x:
			line.draw_line(Vector2(x, y), Vector2(minf(x + 5.0, line.size.x), y), color, 2.0)
			x += 9.0)
	return line


## "holo acorn ........ x1.25": the name (clipped with … when it's too long), a dotted leader, the
## value. Both are Labels (the dev driver can find them).
static func leader(name: String, value: String, name_color: Color, value_color: Color, font_size := UiTheme.SMALL) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var n := UiTheme.label(name, name_color, font_size)
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(n)
	var v := UiTheme.label(value, value_color, font_size)
	row.add_child(v)
	# the dots go where the words end, so draw again whenever the row lays its words out
	for part: Control in [n, v]:
		part.item_rect_changed.connect(row.queue_redraw)
	row.draw.connect(func():
		var font := n.get_theme_font("font")
		var fs := n.get_theme_font_size("font_size")
		var from := ceilf(n.position.x + minf(font.get_string_size(n.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, n.size.x) + 4.0)
		var to := v.position.x - 4.0
		var y := floorf(n.position.y + (n.size.y - font.get_height(fs)) / 2.0 + font.get_ascent(fs) - 1.0)  # on the baseline
		var x := from
		while x + 2.0 <= to:
			row.draw_rect(Rect2(x, y - 1.0, 2, 2), Color(name_color, 0.35))
			x += 4.0)
	return row
