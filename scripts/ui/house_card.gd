class_name HouseCard
extends PanelContainer
## The house card, opened from the room pill (RoomPill) on the bookcase: "our house" and how full
## the room is, the cut-away house (HouseDrawing) with chips for pets on the shelves and pets out on
## jobs (every plain pet counts toward the room, pets on jobs too), and a "next up" row: the next
## step's name, the room growing (750 > 1,100) and "build it" + its coin price, or "squeeze in" +
## wisps for a squeeze-in step (hidden until wisps have shown up). Each step is ONE currency. Short
## on it: the button stays tappable and your pet says so. The card stays open after a build.
## Design: design/mockups/screens/room-house.html (look A, the dollhouse).

const WIDTH := 400.0
const WELL_H := 232.0
const FACES := 24  # different looks for the tiny pets

signal closed

var _pill: Control  # the room pill it hangs under (its tail points at it)
var _count_have := UiTheme.title("", 15, UiTheme.TEXT)
var _count_cap := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _house := HouseDrawing.new()
var _shelves := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _jobs := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _next := PanelContainer.new()
var _next_name := UiTheme.title("", 16, UiTheme.TEXT)
var _jump_from := UiTheme.label("", UiTheme.MUTED, 12)
var _jump_to := UiTheme.label("", UiTheme.TEXT, 12)
var _buy := Button.new()
var _buy_row := HBoxContainer.new()
var _buy_word := UiTheme.label("", UiTheme.TEXT)
var _buy_icon := UiTheme.icon_rect("coin", 14)
var _buy_price := UiTheme.label("", UiTheme.CYAN)
var _shown := ""  # the house drawn: "steps built|step in pencil|looks"
var _looks: Array = []  # the tiny pets' looks (_faces), worked out when the card opens or a step is built
var _styled := ""  # the look the step row and button have: "wisp|poor"
var _queued := false  # a refresh is waiting for the end of the frame


func _init() -> void:
	top_level = true
	z_as_relative = false
	z_index = 7
	mouse_filter = MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	var sb := UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	add_theme_stylebox_override("panel", sb)
	draw.connect(_draw_tail)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	# our house, the count, the x
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.custom_minimum_size = Vector2(0, 26)
	head.add_child(UiTheme.icon_rect("home", 20, UiTheme.LILAC))
	head.add_child(UiTheme.title("our house", 18, UiTheme.PINK))
	head.add_child(UiTheme.spacer())
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 4)
	_count_have.size_flags_vertical = SIZE_SHRINK_CENTER
	_count_cap.size_flags_vertical = SIZE_SHRINK_CENTER
	count.add_child(_count_have)
	count.add_child(_count_cap)
	head.add_child(count)
	var x := UiTheme.small_button("✕", close)
	x.add_theme_color_override("font_color", UiTheme.MUTED)
	x.add_theme_color_override("font_hover_color", UiTheme.PINK)
	x.tooltip_text = "close"
	head.add_child(x)
	col.add_child(head)

	# the house, in a dark well, with the shelves and jobs chips
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(0, WELL_H)
	well.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 12, 2, 0))
	well.clip_contents = true
	var center := CenterContainer.new()
	center.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(_house)
	well.add_child(center)
	var side_margin := MarginContainer.new()
	side_margin.mouse_filter = MOUSE_FILTER_IGNORE
	for m in ["margin_left", "margin_top"]:
		side_margin.add_theme_constant_override(m, 8)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_horizontal = SIZE_SHRINK_BEGIN
	side.size_flags_vertical = SIZE_SHRINK_BEGIN
	side.add_child(_who("shelf", _shelves, "on the shelves"))
	side.add_child(_who("errands", _jobs, "out on jobs"))
	side_margin.add_child(side)
	well.add_child(side_margin)
	col.add_child(well)

	# next up: the step, the room growing, the price
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var what := VBoxContainer.new()
	what.add_theme_constant_override("separation", 3)
	what.size_flags_horizontal = SIZE_EXPAND_FILL
	_next_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.add_child(_next_name)
	var jump := HBoxContainer.new()
	jump.add_theme_constant_override("separation", 5)
	jump.add_child(UiTheme.icon_rect("home", 14, UiTheme.LILAC))
	jump.add_child(_jump_from)
	jump.add_child(_jump_to)
	what.add_child(jump)
	row.add_child(what)
	_buy.focus_mode = FOCUS_NONE
	_buy.size_flags_vertical = SIZE_SHRINK_CENTER
	_buy.pressed.connect(_on_buy)
	_buy_row.add_theme_constant_override("separation", 6)
	_buy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_buy_row.mouse_filter = MOUSE_FILTER_IGNORE
	for c: Control in [_buy_word, _buy_icon, _buy_price]:
		c.mouse_filter = MOUSE_FILTER_IGNORE
		c.size_flags_vertical = SIZE_SHRINK_CENTER
		_buy_row.add_child(c)
	_buy_word.add_theme_constant_override("line_spacing", 0)
	_buy.add_child(_buy_row)
	row.add_child(_buy)
	_next.add_child(row)
	col.add_child(_next)

	# coins tick, boxes open and jobs work many times a second: refresh at most once a frame
	GameState.changed.connect(_queue)
	GameState.collection.herd_changed.connect(func(_k): _queue())
	GameState.collection.pets_added.connect(func(_p): _queue())
	GameState.collection.pets_removed.connect(func(_u): _queue())
	GameState.jobs_changed.connect(_queue)


## A chip in the well: an icon and a count ("618 on the shelves").
func _who(icon_name: String, amount: Label, tip: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 999, 2, 0)
	sb.content_margin_left = 5
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.tooltip_text = tip
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 4)
	r.add_child(UiTheme.icon_rect(icon_name, 14, UiTheme.LILAC))
	r.add_child(amount)
	p.add_child(r)
	return p


## Opens it under `pill`, its right edge lined up with the pill's.
func open(pill: Control) -> void:
	_pill = pill
	visible = true
	_looks = _faces()  # the house is drawn again only if these or the steps changed
	_refresh()
	if GameState.room_is_cozy():
		PetBubble.say_line(self, "room_open")


func close() -> void:
	if visible:
		visible = false
		closed.emit()


func _queue() -> void:
	if visible and not _queued:
		_queued = true
		_flush.call_deferred()


func _flush() -> void:
	_queued = false
	_refresh()


## The house as it should be drawn now: "steps built|step in pencil|looks".
func _house_key() -> String:
	var ghost := GameState.room if not GameState.room_next().is_empty() else -1
	return "%d|%d|%d" % [GameState.room, ghost, _looks.hash()]


func _refresh() -> void:
	if not visible:
		return
	var cap := GameState.room_cap()
	var have := GameState.collection.plain_count()
	var cozy := GameState.room_is_cozy()
	_count_have.text = _n(have)
	_count_have.add_theme_color_override("font_color", UiTheme.PINK if cozy else UiTheme.TEXT)
	_count_cap.text = "/ " + _n(cap)
	var split := GameState.room_split()
	_shelves.text = UiTheme.num(split[0])
	_jobs.text = UiTheme.num(split[1])
	var next := GameState.room_next()
	var wisp := next.has("wisps")
	var key := _house_key()
	if _shown != key:  # the house only changes when a step is built (or wisps show up)
		_house.show_house(GameState.room, GameState.room if not next.is_empty() else -1, -1, _looks)
		_shown = key
	var price := GameState.room_price()
	var poor := not next.is_empty() and (GameState.wisps if wisp else GameState.coins) < price
	_style(wisp, poor)
	if next.is_empty():
		_next_name.text = "everyone's moved in ♡"
		_next_name.add_theme_color_override("font_color", UiTheme.MINT)
		_jump_from.text = _n(Herd.room_cap(GameState.catalog, 0)) + "  ›"
		_jump_to.text = _n(cap)
		_buy.visible = false
	else:
		_next_name.text = str(next.name)
		_next_name.add_theme_color_override("font_color", UiTheme.TEXT)
		_jump_from.text = _n(cap) + "  ›"
		_jump_to.text = _n(int(next.cap))
		_buy.visible = true
		var color := UiTheme.WISP if wisp else UiTheme.CYAN
		_buy_word.text = "squeeze in" if wisp else "build it"
		_buy_word.add_theme_color_override("font_color", UiTheme.LOCKED if poor else UiTheme.TEXT)
		_buy_icon.texture = UiTheme.icon("wisp" if wisp else "coin", 14, color)
		_buy_icon.modulate = Color(1, 1, 1, 0.4) if poor else Color.WHITE  # coin and wisp keep their own colours
		_buy_price.text = _n(price)
		_buy_price.add_theme_color_override("font_color", UiTheme.LOCKED if poor else color)
		var need := _buy_row.get_combined_minimum_size()
		_buy.custom_minimum_size = need + Vector2(22, 12)
		_buy_row.position = Vector2(11, 6)
		_buy_row.size = need
	_place.call_deferred()


## The dashed step row and the button's boxes, made again only when their look changes.
func _style(wisp: bool, poor: bool) -> void:
	var key := "%s|%s" % [wisp, poor]
	if _styled == key:
		return
	_styled = key
	var dash := UiTheme.LINE.lerp(UiTheme.WISP, 0.45) if wisp else UiTheme.LINE
	var dashed := UiTheme.stitched(dash, UiTheme.PAGE, 12, 8)
	dashed.content_margin_left = 10
	dashed.content_margin_right = 10
	_next.add_theme_stylebox_override("panel", dashed)
	var color := UiTheme.WISP if wisp else UiTheme.CYAN
	var edge := UiTheme.MUTED_SEAM if poor else (UiTheme.LINE.lerp(UiTheme.WISP, 0.55) if wisp else UiTheme.PINK_SEAM)
	for state in ["normal", "hover", "pressed"]:
		var b := UiTheme.box(UiTheme.PINK_PRESSED if state == "pressed" else UiTheme.DEEP,
			(color if wisp else UiTheme.PINK) if state == "hover" and not poor else edge, 8, 2, 0)
		_buy.add_theme_stylebox_override(state, b)


## Right under the pill, right edges lined up, and never past the window's edges.
func _place() -> void:
	if not visible or _pill == null or not _pill.is_inside_tree():
		return
	reset_size()
	var w := get_combined_minimum_size()
	var pos := _pill.global_position + Vector2(_pill.size.x - w.x, _pill.size.y + 10.0)
	var room := get_viewport_rect().size
	pos.x = clampf(pos.x, 8.0, maxf(8.0, room.x - w.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, room.y - w.y - 8.0))
	global_position = pos
	queue_redraw()


## A little tail on the top edge, pointing up at the pill.
func _draw_tail() -> void:
	if _pill == null or not _pill.is_inside_tree():
		return
	var cx := clampf(_pill.global_position.x + _pill.size.x * 0.5 - global_position.x, 24.0, size.x - 24.0)
	var fill := PackedVector2Array([Vector2(cx - 8, 2.5), Vector2(cx, -6), Vector2(cx + 8, 2.5)])
	draw_colored_polygon(fill, UiTheme.RAISED)
	draw_polyline(PackedVector2Array([Vector2(cx - 9, 1), Vector2(cx, -7), Vector2(cx + 9, 1)]), UiTheme.LILAC_SEAM, 2.0, true)


func _on_buy() -> void:
	var wisp := GameState.room_currency() == "wisps"
	var built := GameState.room
	if not GameState.buy_room():
		PetBubble.say_line(self, "room_poor_wisps" if wisp else "room_poor")
		return
	var s := Herd.room_step(GameState.catalog, built)
	var line := PetBubble.line("room_" + str(s.id))
	PetBubble.say(self, line if line != "" else PetBubble.line("room_more"))
	# the pencil part turns solid, sparkles, and its pets hop in (drawn once: the refresh that
	# buy_room's changed queued finds this house already up)
	_looks = _faces()
	_house.show_house(GameState.room, GameState.room if not GameState.room_next().is_empty() else -1, built, _looks)
	_shown = _house_key()
	_queue()


## Looks for the tiny pets: a few from every count on the shelves, taken in turns so they mix (the
## same every time, so nobody swaps places when a step is built), else your cards.
func _faces() -> Array:
	var herd: Dictionary = GameState.collection.herd
	var lists: Array = []
	if not herd.is_empty():
		var each := maxi(2, ceili(float(FACES) / herd.size()))
		var salt := 0
		for k in herd:
			lists.append(GameState.herd_faces({ k: herd[k] }, each, salt))
			salt += 1
	var out: Array = []
	for i in FACES:
		for l: Array in lists:
			if i < l.size() and out.size() < FACES:
				out.append(l[i])
	if out.size() < 3:
		for pet in GameState.collection.pets:
			if out.size() >= FACES:
				break
			out.append(pet.uid)
	return out


## A number in full up to a million, then short (1.2M): the card never gets wider.
static func _n(v: float) -> String:
	return UiTheme.full_num(roundi(v)) if absf(v) < 1000000.0 else UiTheme.num(v)
