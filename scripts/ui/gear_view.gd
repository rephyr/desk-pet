class_name GearView
extends HBoxContainer
## The adventures tab's upgrades page: gear for the trips, bought with xp (data/gear.json, Gear,
## GameState.buy_gear). A crayon road snakes across a paper panel through the gear stickers, in
## path order; buying one can bring the next ones onto the path (the rest aren't drawn at all).
## Each sticker shows its level pips, what it does as a number ("trips 16% shorter") and its price.
## Tap a sticker to see it on the card on the right, tap it again or the card's button to buy.
## Design: design/mockups/screens/gear.html (effects as numbers, like the errands pegboard).

const COLUMNS := 4  # stickers a row; the road snakes back on the next row
const STOP_WIDTH := 118
const ROW_HEIGHT := 158
const FACE := 66  # the tilted icon square on a sticker
const TILTS := [-3.0, 2.0, -2.0, 3.0, 2.5, -2.5, 2.0, -3.0]

var _picked := ""
var _tapped := false  # you tapped the picked sticker yourself (a second tap buys it)
var _road := Road.new()
var _card := VBoxContainer.new()
var _dirty := true
var _last := ""


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	var paper := PanelContainer.new()
	paper.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 12)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	paper.add_theme_stylebox_override("panel", sb)
	add_child(paper)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	paper.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.title("gear for the trips", 20))
	var sub := UiTheme.label("bought with xp", UiTheme.MUTED, UiTheme.SMALL)
	sub.size_flags_vertical = SIZE_SHRINK_END
	head.add_child(sub)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_road.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_road)
	col.add_child(scroll)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(230, 0)
	side.clip_contents = true
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	_card.add_theme_constant_override("separation", 7)
	side.add_child(_card)
	add_child(side)

	GameState.changed.connect(func(): _dirty = true)
	GameState.gear_changed.connect(func(): _dirty = true)
	visibility_changed.connect(func():
		_dirty = true
		_tapped = false)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not _dirty:
		return
	_dirty = false
	# xp changes on the trail too: only rebuild when something you'd see changed
	var key := "%s|%d|%s|%s|%s" % [str(GameState.gear), GameState.xp, _picked,
		",".join(GameState.shown_gear().map(func(g): return g.id)), GameState.feature_on("parts")]
	if key == _last:
		return
	_last = key
	_rebuild()


## Tap a sticker: it's picked (its card shows); tapped again, it's bought.
func pick(id: String) -> void:
	if _picked == id and _tapped:
		buy(id)
		return
	_picked = id
	_tapped = true
	_dirty = true
	PetBubble.say_line(self, "gear_pick_" + id)


## Buys the next level of a gear; the pet cheers, or says what's missing.
func buy(id: String) -> void:
	var why := GameState.gear_block(id)
	if why == "max":
		PetBubble.say_line(self, "gear_max")
		return
	if why != "":
		return
	if not GameState.buy_gear(id):
		PetBubble.say_line(self, "gear_poor")
		return
	Sfx.play(self, Sfx.sound("machine", "prize"), 2.0)
	var key := "gear_bought_" + id
	PetBubble.say_line(self, key if Catalog.shared().voice.get("ui", {}).has(key) else "gear_bought")
	_last = ""
	_dirty = true
	_road.bought = id


func speak() -> void:
	PetBubble.say_line(self, "gear")


# ---- building it ----------------------------------------------------------------

func _rebuild() -> void:
	var catalog := GameState.catalog
	var shown := GameState.shown_gear()
	if not shown.any(func(g): return g.id == _picked):
		_picked = str(shown[0].id) if not shown.is_empty() else ""
	var parts_on := GameState.feature_on("parts")
	var stops: Array[GearStop] = []
	for i in shown.size():
		stops.append(GearStop.new(shown[i], TILTS[i % TILTS.size()], shown[i].id == _picked, parts_on, self))
	_road.set_stops(stops)
	_rebuild_card(catalog, parts_on)


## The card on the right: the picked gear, what it does now and next, and the button to buy it.
func _rebuild_card(catalog: Catalog, parts_on: bool) -> void:
	UiTheme.clear(_card)
	var g := Gear.info(catalog, _picked)
	if g.is_empty():
		return
	var color := color_of(g)
	var have := GameState.gear_level(_picked)
	var why := GameState.gear_block(_picked)

	var big := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.GOLD if why == "max" else UiTheme.LILAC_SEAM, 26, 2, 0)
	big.add_theme_stylebox_override("panel", sb)
	big.custom_minimum_size = Vector2(96, 96)
	var icon := UiTheme.icon_rect(str(g.icon), 60, color)
	icon.size_flags_horizontal = SIZE_SHRINK_CENTER
	big.add_child(icon)
	var tilted := Tilted.new(big, -3.0)
	tilted.size_flags_horizontal = SIZE_SHRINK_CENTER
	tilted.mouse_filter = MOUSE_FILTER_IGNORE
	_card.add_child(tilted)

	var title := UiTheme.title(str(g.name), 19)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(60, 0)
	_card.add_child(title)
	var does := _wrapped(str(g.does), UiTheme.MUTED, UiTheme.SMALL + 1)
	does.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(does)
	var pips := Pips.new(int(g.max), have, 11)
	pips.size_flags_horizontal = SIZE_SHRINK_CENTER
	_card.add_child(pips)

	var rows := GridContainer.new()
	rows.columns = 2
	rows.add_theme_constant_override("h_separation", 10)
	rows.add_theme_constant_override("v_separation", 4)
	_add_row(rows, "now", Gear.words(catalog, _picked, have, parts_on), UiTheme.TEXT)
	if why != "max":
		_add_row(rows, "next", Gear.words(catalog, _picked, have + 1, parts_on), UiTheme.MINT)
	_card.add_child(rows)

	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	_card.add_child(fill)
	var price := GameState.gear_price(_picked)
	var label := "all done! ♡"
	if why == "":
		label = ("get it" if GameState.xp >= price else "not enough xp yet") + "\n%s xp" % UiTheme.num(price)
	var button := UiTheme.button(label, func(): buy(_picked))
	button.disabled = why != "" or GameState.xp < price
	button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PINK_PRESSED, UiTheme.PINK_SEAM, 8, 2, 8))
	if why == "":
		button.icon = UiTheme.icon("xp", 14, UiTheme.GOLD)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		button.add_theme_constant_override("icon_max_width", 14)
	_card.add_child(button)
	var have_xp := UiTheme.label("you have %s xp" % UiTheme.num(GameState.xp), UiTheme.MUTED, UiTheme.SMALL)
	have_xp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card.add_child(have_xp)


static func color_of(g: Dictionary) -> Color:
	return UiTheme.named_color(str(g.get("color", "")))


static func _add_row(grid: GridContainer, left: String, right: String, color: Color) -> void:
	var l := UiTheme.label(left, UiTheme.MUTED, UiTheme.SMALL + 1)
	l.size_flags_vertical = SIZE_SHRINK_BEGIN
	grid.add_child(l)
	var r := _wrapped(right, color, UiTheme.SMALL + 1)
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(r)


static func _wrapped(text: String, color: Color, size: int) -> Label:
	var l := UiTheme.label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	return l


## The paper the road is drawn on: the stickers sit along it, COLUMNS a row, snaking back and forth.
## The road is dashed, and solid up to every sticker that has a level (the part you've walked).
class Road extends Control:
	var bought := ""  # a gear just bought: its sticker squashes and sparkles once it's rebuilt
	var _stops: Array[GearStop] = []
	var _sparks: Array[Dictionary] = []  # { at, v, age }

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_PASS
		resized.connect(_place)

	func set_stops(stops: Array[GearStop]) -> void:
		for s in _stops:
			s.queue_free()
		_stops = stops
		for s in _stops:
			add_child(s)
		var rows := ceili(_stops.size() / float(COLUMNS))
		custom_minimum_size = Vector2(COLUMNS * STOP_WIDTH, maxi(1, rows) * ROW_HEIGHT + 6)
		_place()
		if bought != "":
			for s in _stops:
				if s.id == bought:
					s.pop.call_deferred()
					_burst.call_deferred(s)
			bought = ""

	## Where the i-th sticker sits (its top middle).
	func _spot(i: int) -> Vector2:
		var slot := size.x / COLUMNS
		var row := i / COLUMNS
		var column := i % COLUMNS
		if row % 2 == 1:
			column = COLUMNS - 1 - column  # the road comes back the other way
		return Vector2(slot * (column + 0.5), 8.0 + row * ROW_HEIGHT)

	func _place() -> void:
		for i in _stops.size():
			var s := _stops[i]
			s.size = Vector2(STOP_WIDTH, ROW_HEIGHT - 8)
			s.position = _spot(i) - Vector2(STOP_WIDTH / 2.0, 0)
		queue_redraw()

	func _face_center(i: int) -> Vector2:
		return _spot(i) + Vector2(0, 6 + FACE / 2.0)

	func _draw() -> void:
		for i in range(1, _stops.size()):
			var points := _leg(i)
			var walked := _stops[i].level > 0 and _stops[i - 1].level > 0
			if walked:
				Crayon.line(self, points, UiTheme.PINK, 3.0, 40 + i)
			else:
				_dashed(points, UiTheme.PINK_SEAM, 3.0)
		for s in _sparks:
			var t: float = s.age / 0.8
			var at: Vector2 = s.at + s.v * (1.0 - pow(1.0 - t, 3.0))
			var c := Color(UiTheme.GOLD, 1.0 - t)
			draw_set_transform(at, t * PI, Vector2.ONE)
			draw_rect(Rect2(-3, -3, 6, 6), c)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## The road from sticker i-1 to sticker i: straight along a row, a loop out to the side between rows.
	func _leg(i: int) -> Array:
		var a := _face_center(i - 1)
		var b := _face_center(i)
		if (i - 1) / COLUMNS == i / COLUMNS:
			return [a, b]
		var out := size.x / COLUMNS * 0.45 * (1.0 if ((i - 1) / COLUMNS) % 2 == 0 else -1.0)
		var points := []
		for k in 17:
			var t := k / 16.0
			var u := 1.0 - t
			var c1 := a + Vector2(out * 1.4, 0)
			var c2 := b + Vector2(out * 1.4, 0)
			points.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
		return points

	func _dashed(points: Array, color: Color, width: float) -> void:
		var on := true
		var left := 9.0
		for k in range(1, points.size()):
			var p: Vector2 = points[k - 1]
			var q: Vector2 = points[k]
			var d := p.distance_to(q)
			while d > 0.0:
				var step := minf(d, left)
				var r := p.move_toward(q, step)
				if on:
					draw_line(p, r, color, width, true)
				p = r
				d -= step
				left -= step
				if left <= 0.0:
					on = not on
					left = 9.0 if on else 8.0

	func _burst(s: GearStop) -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var at := s.position + Vector2(STOP_WIDTH / 2.0, 6 + FACE / 2.0)
		for k in 14:
			var a := rng.randf() * TAU
			_sparks.append({ "at": at, "v": Vector2(cos(a), sin(a)) * rng.randf_range(30.0, 70.0), "age": 0.0 })

	func _process(delta: float) -> void:
		if _sparks.is_empty():
			return
		for s in _sparks:
			s.age += delta
		_sparks = _sparks.filter(func(s): return s.age < 0.8)
		queue_redraw()


## One gear on the road: a tilted icon square, its name, level pips, what it does now and its price
## (or a star at max). The picked one is stitched in pink; one you can't afford yet has a faded price.
class GearStop extends Control:
	var id := ""
	var level := 0
	var _view: GearView
	var _face: Tilted

	func _init(g: Dictionary, tilt: float, picked: bool, parts_on: bool, view: GearView) -> void:
		id = str(g.id)
		_view = view
		level = GameState.gear_level(id)
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var catalog := GameState.catalog
		var maxed := level >= int(g.max)
		var color := GearView.color_of(g)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.set_anchors_preset(PRESET_FULL_RECT)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(col)

		var face := PanelContainer.new()
		var sb: StyleBox
		if picked:
			sb = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 20, 0)
		else:
			sb = UiTheme.sticker(UiTheme.GOLD if maxed else UiTheme.LILAC_SEAM, 20, UiTheme.RAISED, 0)
		face.add_theme_stylebox_override("panel", sb)
		face.mouse_filter = MOUSE_FILTER_IGNORE
		var icon := UiTheme.icon_rect(str(g.icon), 40, color)
		icon.size_flags_horizontal = SIZE_SHRINK_CENTER
		face.add_child(icon)
		_face = Tilted.new(face, 0.0 if picked else tilt)
		_face.custom_minimum_size = Vector2(FACE, FACE)
		_face.size_flags_horizontal = SIZE_SHRINK_CENTER
		_face.mouse_filter = MOUSE_FILTER_IGNORE
		var face_row := MarginContainer.new()
		face_row.add_theme_constant_override("margin_top", 6)
		face_row.mouse_filter = MOUSE_FILTER_IGNORE
		face_row.add_child(_face)
		col.add_child(face_row)
		if maxed:
			var star := UiTheme.icon_rect("star", 16, UiTheme.GOLD)
			star.position = Vector2(STOP_WIDTH / 2.0 + FACE / 2.0 - 12, 0)
			add_child(star)

		var name_label := _centered(str(g.name), UiTheme.TEXT, UiTheme.SMALL + 1)
		col.add_child(name_label)
		var pips := Pips.new(int(g.max), level, 8)
		pips.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(pips)
		var how := _centered(Gear.words(catalog, id, level, parts_on), UiTheme.GOLD if maxed else UiTheme.MUTED, UiTheme.SMALL)
		how.add_theme_constant_override("line_spacing", -2)
		col.add_child(how)
		if not maxed:
			var price_row := HBoxContainer.new()
			price_row.alignment = BoxContainer.ALIGNMENT_CENTER
			price_row.add_theme_constant_override("separation", 3)
			price_row.mouse_filter = MOUSE_FILTER_IGNORE
			price_row.add_child(UiTheme.icon_rect("xp", 12, UiTheme.GOLD))
			var price := GameState.gear_price(id)
			price_row.add_child(UiTheme.label(UiTheme.num(price), UiTheme.GOLD, UiTheme.SMALL))
			if GameState.xp < price:
				price_row.modulate.a = 0.55
			col.add_child(price_row)
		tooltip_text = str(g.does)

	func _centered(text: String, color: Color, font_size: int) -> Label:
		var l := UiTheme.label(text, color, font_size)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(STOP_WIDTH - 6, 0)
		l.mouse_filter = MOUSE_FILTER_IGNORE
		return l

	## Bought: the sticker squashes and springs back.
	func pop() -> void:
		await get_tree().process_frame  # laid out first
		if not is_inside_tree():
			return
		_face.pivot_offset = _face.size / 2.0
		var t := create_tween()
		t.tween_property(_face, "scale", Vector2(1.15, 0.85), 0.12).set_ease(Tween.EASE_OUT)
		t.tween_property(_face, "scale", Vector2.ONE, 0.33).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			_view.pick(id)


## Level pips: filled for each level you have, empty for the rest.
class Pips extends Control:
	var _max := 0
	var _have := 0
	var _d := 8.0

	func _init(most: int, have: int, diameter: float) -> void:
		_max = most
		_have = have
		_d = diameter
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(most * (diameter + 4.0) - 4.0 + 2.0, diameter + 2.0)

	func _draw() -> void:
		var r := _d / 2.0
		for i in _max:
			var c := Vector2(1.0 + r + i * (_d + 4.0), 1.0 + r)
			if i < _have:
				draw_circle(c, r, UiTheme.PINK)
			else:
				draw_arc(c, r - 1.0, 0.0, TAU, 20, UiTheme.LINE, 2.0, true)
