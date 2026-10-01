class_name GoalsNote
extends PanelContainer
## "next up": a note taped to the home wall with the closest few goals (Goals): what each opens, the
## next thing to do for it and how far along that is. Tap a goal to go where it's done. Hidden
## while there's nothing in reach (and during the tutorial).

signal go(tab_name: String)

const SHOWN := 3
const WIDTH := 216

var _rows := VBoxContainer.new()
var _key := ""  # what it shows now: built again only when that changes


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var sb := UiTheme.sticker(UiTheme.LINE, 6, UiTheme.RAISED, 12)
	sb.content_margin_top = 14
	sb.corner_radius_bottom_right = 12
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(UiTheme.title("next up", 14, UiTheme.PINK))
	_rows.add_theme_constant_override("separation", 7)
	_rows.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(_rows)
	add_child(col)
	draw.connect(func():  # a strip of tape holding it to the wall
		var tape := Rect2(size.x / 2.0 - 20.0, -8.0, 40.0, 14.0)
		draw_set_transform(tape.get_center(), deg_to_rad(2.0))
		draw_rect(Rect2(-tape.size / 2.0, tape.size), Color(UiTheme.PINK, 0.45))
		draw_set_transform(Vector2.ZERO))


## Shows the goals as they are now (cheap when nothing moved).
func refresh() -> void:
	var goals := [] if GameState.tutorial_active() else Goals.list(GameState).slice(0, SHOWN)
	var key := ""
	for g in goals:
		var s := _next_step(g)
		key += "%s|%s|%d|%d;" % [g.name, s.text, int(s.have), int(s.need)]
	visible = not goals.is_empty()
	if key == _key:
		return
	_key = key
	UiTheme.clear(_rows)
	for g in goals:
		_rows.add_child(_row(g))


## The first step not done yet (the last one when all are, waiting on the unlock itself).
static func _next_step(g: Dictionary) -> Dictionary:
	for s in g.steps:
		if float(s.have) < float(s.need):
			return s
	return g.steps.back()


func _row(g: Dictionary) -> Control:
	var s := _next_step(g)
	var box := VBoxContainer.new()
	box.name = "goal_" + str(g.id)
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = MOUSE_FILTER_STOP
	box.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	box.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			go.emit(str(s.go)))
	var name := UiTheme.label(str(g.name), UiTheme.MINT, UiTheme.SMALL + 1)
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.custom_minimum_size.x = 40
	box.add_child(name)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var what := UiTheme.label(str(s.text), UiTheme.MUTED, UiTheme.SMALL)
	what.size_flags_horizontal = SIZE_EXPAND_FILL
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.custom_minimum_size.x = 40
	line.add_child(what)
	if float(s.need) > 1.0:
		var n := UiTheme.label("%s/%s" % [UiTheme.num(float(s.have)), UiTheme.num(float(s.need))], UiTheme.TEXT, UiTheme.SMALL)
		n.size_flags_vertical = SIZE_SHRINK_END
		line.add_child(n)
	box.add_child(line)
	var bar := UiTheme.bar(UiTheme.MINT)
	bar.custom_minimum_size = Vector2(0, 6)
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = clampf(float(s.have) / maxf(1.0, float(s.need)), 0.0, 1.0)
	box.add_child(bar)
	for c in [name, line, what, bar] + line.get_children():
		c.mouse_filter = MOUSE_FILTER_IGNORE
	return box
