class_name WellWall
extends PanelContainer
## The well wall: a sheet over the dungeon page (the "perks" button by the wisps opens it, ✕ closes
## it) with every wisps perk the army has reached as a tag (PerkTag) on a nail, all on ONE coral
## thread: the chain, each perk waiting for the one before it (coral up to the last one with a level,
## dashed chalk after). The ones you can afford stand out; the next one down that isn't reached yet
## hangs as a chalk outline with "down to landing N" (the Carrot Rule), the plushie perks stay hidden
## until the plushie machine; once every link has a level the 2 endless tips hang at the end. Late in
## the game the wall scrolls inside the sheet. Rules in Perks, state in GameState.
## Design: design/mockups/screens/perks-redo.html look A (the well wall).

signal closed

const COLS := 4
const GAP := Vector2(14, 10)
const HANG := 12.0  # the nail and string above a tag

var _scroll := ScrollContainer.new()
var _board := _Board.new()
var _pop := ""  # a perk just bought: its tag swings once it's built again
var _to_end := false  # the tips just hung: scroll down to them


func _init() -> void:
	name = "well_wall"
	var sb := UiTheme.sticker(UiTheme.WISP.lerp(UiTheme.LILAC_SEAM, 0.55), 14, UiTheme.DEEP.lerp(UiTheme.PAPER, 0.6), 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 6
	add_theme_stylebox_override("panel", sb)
	mouse_filter = MOUSE_FILTER_STOP  # (nothing under the sheet takes a click)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.title("the well wall", 15, UiTheme.WISP))
	head.add_child(UiTheme.spacer())
	var x := UiTheme.small_button("✕", func(): closed.emit())
	x.name = "close_wall"
	x.custom_minimum_size = Vector2(24, 24)
	x.add_theme_color_override("font_color", UiTheme.MUTED)
	x.add_theme_color_override("font_hover_color", UiTheme.PINK)
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	head.add_child(x)
	col.add_child(head)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_board.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_board)
	col.add_child(_scroll)


## Builds the wall again from the game (keeps where it was scrolled to).
func refresh() -> void:
	var catalog := GameState.catalog
	var keep := _scroll.scroll_vertical
	var items: Array = []  # [perk, state]
	var shown := GameState.perks_shown()
	for id in shown:
		if not Perks.is_tip(catalog, id):
			items.append([Perks.perk(catalog, id), _state(id)])
	var carrot := GameState.perk_carrot()
	if not carrot.is_empty():
		items.append([carrot, "carrot"])
	for id in shown:
		if Perks.is_tip(catalog, id):
			items.append([Perks.perk(catalog, id), _state(id)])
	_board.build(items)
	for t in _board.tags:
		(t.get_child(0) as PerkTag).buy.connect(_buy)
	if _pop != "":
		_board.swing(_pop)
		_pop = ""
	if _to_end:
		_to_end = false
		_end.call_deferred()
	else:
		_scroll.set_deferred("scroll_vertical", keep)


func _end() -> void:
	await get_tree().process_frame
	_scroll.scroll_vertical = int(_board.custom_minimum_size.y)


## A perk's tag state: max, wait (the link before it has no level), buy (affordable) or poor.
func _state(id: String) -> String:
	var catalog := GameState.catalog
	if Perks.maxed(catalog, GameState.perks, id):
		return "max"
	if not GameState.perk_available(id):
		return "wait"
	return "buy" if GameState.wisps >= GameState.perk_price(id) else "poor"


## The tag of a perk on the wall (null when it isn't there), for flows.
func tag(id: String) -> PerkTag:
	for t in _board.tags:
		var pt := t.get_child(0) as PerkTag
		if pt.id == id:
			return pt
	return null


func _buy(id: String) -> void:
	var catalog := GameState.catalog
	var done := Perks.chain_done(catalog, GameState.perks)
	if not GameState.buy_perk(id):
		return
	_pop = id
	if not done and Perks.chain_done(catalog, GameState.perks):
		_to_end = true  # the tips just hung at the end: show them
	if str(Perks.perk(catalog, id).get("count", "")) == "entrance":
		PetBubble.say_line(self, "perk_entrance")
	elif Perks.is_tip(catalog, id):
		PetBubble.say_line(self, "perk_tip")
	else:
		PetBubble.say_line(self, "perk_hang")


## The tags in a snake (row 1 left to right, row 2 right to left...) so one thread runs through them
## all, nail to nail; each tag hangs a little crooked.
class _Board extends Control:
	const TILTS := [-1.4, 1.1, -0.6, 1.5, -1.0, 0.7]

	var tags: Array[Tilted] = []
	var _lit := -1  # the thread is coral up to this tag (the last one with a level)
	var _swing_tween: Tween

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_PASS
		resized.connect(_lay)

	func build(items: Array) -> void:
		for t in tags:
			remove_child(t)
			t.queue_free()
		tags.clear()
		_lit = -1
		for i in items.size():
			var p: Dictionary = items[i][0]
			var tag := PerkTag.new(p, str(items[i][1]))
			var tilt := Tilted.new(tag, TILTS[i % TILTS.size()])
			add_child(tilt)
			tags.append(tilt)
			if str(items[i][1]) != "carrot" and (GameState.perk_level(str(p.id)) > 0 or Perks.is_tip(GameState.catalog, str(p.id))):
				_lit = i
		_lay()

	func _lay() -> void:
		var w := size.x
		if w <= 0.0:
			return
		var cw := floorf((w - (COLS - 1) * GAP.x) / COLS)
		var y := 0.0
		var i := 0
		while i < tags.size():
			var row := i / COLS
			var h := 0.0
			for k in range(i, mini(i + COLS, tags.size())):
				h = maxf(h, tags[k].get_combined_minimum_size().y)
			for k in range(i, mini(i + COLS, tags.size())):
				var c := k - i
				var colx := (COLS - 1 - c) if row % 2 == 1 else c
				tags[k].position = Vector2(colx * (cw + GAP.x), y + HANG)
				tags[k].size = Vector2(cw, h)
			y += HANG + h + GAP.y
			i += COLS
		custom_minimum_size = Vector2(0, y + 4.0)
		queue_redraw()

	## The nail a tag hangs on.
	func _nail(i: int) -> Vector2:
		var t := tags[i]
		return Vector2(t.position.x + t.size.x / 2.0, t.position.y - HANG + 3.0)

	func _draw() -> void:
		var chalk := Color(UiTheme.TEXT, 0.3)
		var lit := Color(UiTheme.WISP, 0.8)
		for i in tags.size() - 1:
			var a := _nail(i)
			var b := _nail(i + 1)
			var pts := PackedVector2Array()
			if absf(a.y - b.y) < 4.0:  # along a row: a little sag
				for s in 13:
					var t := s / 12.0
					pts.append(a.lerp(b, t) + Vector2(0, sin(t * PI) * 9.0))
			else:  # down to the next row, round the end of this one
				var side := 1.0 if a.x > size.x / 2.0 else -1.0
				var c1 := a + Vector2(side * 26.0, 30.0)
				var c2 := b + Vector2(side * 26.0, -40.0)
				for s in 17:
					var t := s / 16.0
					var u := 1.0 - t
					pts.append(a * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + b * t * t * t)
			if i < _lit:
				draw_polyline(pts, lit, 2.0, true)
			else:
				_dashed(pts, chalk, 2.0)
		for i in tags.size():  # the nails and strings
			var n := _nail(i)
			draw_line(n, n + Vector2(0, HANG + 2.0), UiTheme.MUTED, 2.0)
			draw_circle(n, 3.0, UiTheme.MUTED)

	func _dashed(pts: PackedVector2Array, color: Color, width: float) -> void:
		var on := true
		var left := 3.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var d := a.distance_to(b)
			var s := 0.0
			while s < d:
				var step := minf(left, d - s)
				if on:
					draw_line(a.lerp(b, s / d), a.lerp(b, (s + step) / d), color, width)
				s += step
				left -= step
				if left <= 0.001:
					on = not on
					left = 3.0 if on else 5.0

	## A tag swings on its nail (just bought).
	func swing(id: String) -> void:
		for t in tags:
			if (t.get_child(0) as PerkTag).id == id:
				var rest := t.degrees
				if _swing_tween:
					_swing_tween.kill()
				_swing_tween = create_tween()
				_swing_tween.tween_property(t, "degrees", rest + 7.0, 0.12)
				_swing_tween.tween_property(t, "degrees", rest - 5.0, 0.15)
				_swing_tween.tween_property(t, "degrees", rest + 2.0, 0.15)
				_swing_tween.tween_property(t, "degrees", rest, 0.18)
				return
