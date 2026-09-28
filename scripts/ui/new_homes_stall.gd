class_name NewHomesStall
extends PanelContainer
## New homes: a striped stall in the pets page's side column. Pick a shelf in the bookcase, then
## take 1, 10, 100 or all of its pets. Their points fill the box jar toward a box, and full jars
## drop boxes on the pile under it. Your pet cheers every time, always the same words.
## Design: design/mockups/screens/new-homes.html (look A, the stall).

const AWNING_H := 30.0
const SCALLOP := 10.0
const STRIPE := 21.0

var rarity := ""  # the shelf it takes from
var _from := PanelContainer.new()
var _from_face := PetPortrait.new(1, false)
var _from_name := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
var _from_count := UiTheme.title("0", 16, UiTheme.TEXT)
var _takes: Array[Button] = []
var _jar_box := PanelContainer.new()
var _meter := Control.new()
var _frac := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _pile_count := UiTheme.title("0", 18, UiTheme.TEXT)
var _pile_name := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _fill := 0.0
var _dirty := true  # everything is worked out again (who may go, the face)
var _jar_dirty := false  # just the jar and the pile
var _pins := 0  # pinned pulls at the last refresh (they can't go)


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 0))
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 12)
	pad.add_theme_constant_override("margin_right", 12)
	pad.add_theme_constant_override("margin_bottom", 12)
	pad.add_theme_constant_override("margin_top", int(AWNING_H + SCALLOP) + 4)
	add_child(pad)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	pad.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect("home", 22, UiTheme.MINT))
	head.add_child(UiTheme.title("new homes", 20, UiTheme.PINK))
	col.add_child(head)

	# where they come from: the picked shelf and how many of it may go
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_from.add_child(row)
	_from_face.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_from_face)
	_from_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_from_name.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_from_name)
	_from_count.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_from_count)
	col.add_child(_from)

	var takes := GridContainer.new()
	takes.columns = 4
	takes.add_theme_constant_override("h_separation", 6)
	for n in GameState.catalog.new_homes.get("takes", [1, 10, 100, -1]):
		var b := UiTheme.button("all" if int(n) < 0 else str(int(n)), _take.bind(int(n)))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		if int(n) < 0:
			b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 5))
		takes.add_child(b)
		_takes.append(b)
	col.add_child(takes)

	# the box jar: points toward the next box
	var jar := HBoxContainer.new()
	jar.add_theme_constant_override("separation", 8)
	_jar_box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 3))
	_jar_box.custom_minimum_size = Vector2(34, 34)
	_jar_box.add_child(UiTheme.icon_rect("boxes", 22, UiTheme.LILAC))
	_jar_box.resized.connect(func(): _jar_box.pivot_offset = _jar_box.size / 2.0)
	jar.add_child(_jar_box)
	_meter.custom_minimum_size = Vector2(40, 12)
	_meter.size_flags_horizontal = SIZE_EXPAND_FILL
	_meter.size_flags_vertical = SIZE_SHRINK_CENTER
	_meter.draw.connect(_draw_meter)
	jar.add_child(_meter)
	_frac.size_flags_vertical = SIZE_SHRINK_CENTER
	jar.add_child(_frac)
	col.add_child(jar)

	# the pile of boxes it paid (your pile: the bag)
	var pile := HBoxContainer.new()
	pile.add_theme_constant_override("separation", 8)
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(44, 30)
	for spot in [Vector2(0, 5), Vector2(12, 0), Vector2(22, 7)]:
		var box := UiTheme.icon_rect("boxes", 22, UiTheme.LILAC)
		box.position = spot
		box.size = Vector2(22, 22)
		stack.add_child(box)
	pile.add_child(stack)
	_pile_count.size_flags_vertical = SIZE_SHRINK_CENTER
	pile.add_child(_pile_count)
	_pile_name.size_flags_vertical = SIZE_SHRINK_CENTER
	pile.add_child(_pile_name)
	col.add_child(pile)

	# who may go only changes with the herd, the crews, trips and pins: `changed` (every coin
	# tick) just redoes the jar and the pile, unless a pin came or went
	var c := GameState.collection
	c.herd_changed.connect(func(_k): mark())
	c.pets_added.connect(func(_p): mark())
	c.pets_removed.connect(func(_u): mark())
	c.pets_left.connect(func(_n): mark())
	c.pet_changed.connect(func(_p): mark())
	c.active_changed.connect(func(_p): mark())
	for sig: Signal in [GameState.jobs_changed, GameState.automation_changed, GameState.adventures_changed, GameState.new_game]:
		sig.connect(mark)
	GameState.homes_paid.connect(func(_b): mark())
	GameState.changed.connect(func():
		if GameState.pinned.size() != _pins:
			mark()
		else:
			_jar_dirty = true)
	visibility_changed.connect(mark)


## Takes from this shelf now.
func set_rarity(r: String) -> void:
	rarity = r
	_dirty = true
	refresh()


## Something changed: the numbers are worked out again (at most once a frame, while it shows).
func mark() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _dirty:
		refresh()
	elif _jar_dirty:
		_refresh_jar()


func refresh() -> void:
	_dirty = false
	_pins = GameState.pinned.size()
	var catalog := GameState.catalog
	var can := GameState.homes_can_go(rarity) if rarity != "" else 0
	var color := catalog.tier_color(rarity) if rarity != "" else UiTheme.MUTED
	_from.add_theme_stylebox_override("panel", _from_style(color))
	_from_name.text = catalog.tier_at(catalog.rank(rarity)).name if rarity != "" else ""
	_from_name.add_theme_color_override("font_color", color)
	_from_count.text = UiTheme.num(can)
	_from_face.set_pet(_face())
	for b in _takes:
		b.disabled = can <= 0
	_refresh_jar()


## The jar's points and the pile's boxes.
func _refresh_jar() -> void:
	_jar_dirty = false
	var catalog := GameState.catalog
	var at := NewHomes.box_at(catalog)
	var points := int(GameState.homes.points)
	_fill = clampf(float(points) / at, 0.0, 1.0)
	_meter.queue_redraw()
	_frac.text = "%d/%d" % [points, at]
	var box := NewHomes.box_id(catalog)
	_pile_count.text = UiTheme.num(GameState.in_bag(box))
	var box_name := str(catalog.box(box).get("name", "box"))
	_pile_name.text = box_name + ("es" if box_name.ends_with("x") else "s")


## A face for the "from" row: the shelf's newest card, else one from its count.
func _face() -> Pet:
	if rarity == "":
		return null
	var c := GameState.collection
	var cards := c.cards_of(rarity)
	for i in range(cards.size() - 1, -1, -1):
		if Herd.plain(GameState.catalog, cards[i].finish):
			return cards[i]
	for f in GameState.catalog.finishes:
		var k := Herd.key(rarity, str(f.id))
		if c.herd_count(k) > 0:
			return c.get_pet(c.stand_in_uids(k, 1)[0])
	return cards[-1] if not cards.is_empty() else null


static func _from_style(color: Color) -> StyleBoxFlat:
	var sb := UiTheme.box(UiTheme.DEEP, color.lerp(UiTheme.LINE, 0.55), 10, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 10
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	return sb


func _take(n: int) -> void:
	if rarity == "":
		return
	var got := GameState.send_home(rarity, n)
	if int(got.n) <= 0:
		return
	PetBubble.say_line(self, "homes_cheer")
	if int(got.boxes) > 0:
		_pop(int(got.boxes))
	refresh()


## A box dropped: the jar's box hops and "+1" floats up from it.
func _pop(boxes: int) -> void:
	var t := create_tween()
	t.tween_property(_jar_box, "scale", Vector2(1.3, 0.8), 0.15).set_trans(Tween.TRANS_BACK)
	t.tween_property(_jar_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var rise := UiTheme.title("+%s" % UiTheme.num(boxes), 14, UiTheme.PINK)
	rise.mouse_filter = MOUSE_FILTER_IGNORE
	rise.top_level = true
	rise.z_index = 9
	add_child(rise)
	rise.global_position = _jar_box.global_position + Vector2(_jar_box.size.x / 2.0 - 8.0, -6.0)
	var r := rise.create_tween().set_parallel()
	r.tween_property(rise, "global_position:y", rise.global_position.y - 34.0, 1.2).set_ease(Tween.EASE_OUT)
	r.tween_property(rise, "modulate:a", 0.0, 1.2).set_ease(Tween.EASE_IN)
	r.chain().tween_callback(rise.queue_free)


func _draw_meter() -> void:
	var r := Rect2(Vector2.ZERO, _meter.size)
	_meter.draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.LILAC.lerp(UiTheme.LINE, 0.55), 999, 2, 0), r)
	if _fill > 0.0:
		var w := maxf(r.size.y - 4.0, (r.size.x - 4.0) * _fill)
		_meter.draw_style_box(UiTheme.box(UiTheme.LILAC, Color(0, 0, 0, 0), 999, 0, 0), Rect2(Vector2(2, 2), Vector2(w, r.size.y - 4.0)))


## The striped awning along the top, scalloped at the bottom (pink and pale stripes; an odd number
## of them, so both ends are pink and follow the sticker's rounded corners).
func _draw() -> void:
	var x0 := 2.0
	var w := size.x - 4.0
	var n := maxi(3, roundi(w / STRIPE))
	if n % 2 == 0:
		n += 1
	var stripe := w / n
	var pale := UiTheme.TEXT.lerp(UiTheme.RAISED, 0.3)
	var base := StyleBoxFlat.new()
	base.bg_color = UiTheme.PINK_SEAM
	base.corner_radius_top_left = 10
	base.corner_radius_top_right = 10
	base.anti_aliasing = true
	draw_style_box(base, Rect2(x0, 2.0, w, AWNING_H))
	for i in n:
		var color := UiTheme.PINK_SEAM if i % 2 == 0 else pale
		var sx := x0 + i * stripe
		if i % 2 == 1:
			draw_rect(Rect2(sx, 2.0, stripe, AWNING_H), color)
		draw_circle(Vector2(sx + stripe / 2.0, 2.0 + AWNING_H), stripe / 2.0 - 0.5, color, true, -1.0, true)
