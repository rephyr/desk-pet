class_name PerkTag
extends PanelContainer
## One wisps perk as a tag on the well wall (WellWall, see Perks): its thing, its name, level pips
## (a tip's "lv N"), what it does now → next as numbers, and one tap to buy ("hang it up" for the
## first level, "one more" after). Looks by state: buy (you can afford it: coral outline, a solid
## coral button), poor (a sunk button), wait (the perk before it has no level yet: faint and dashed,
## just its price), max ("all done!"), carrot (the next one down, not reached yet: chalk, "down to
## landing N" with how far the army has been).
## Design: design/mockups/screens/perks-redo.html look A (the well wall).

signal buy(id: String)

const THING := 28

var id := ""
var state := "poor"


## `p` the perk (data/perks.json), `st` its state (buy | poor | wait | max | carrot).
func _init(p: Dictionary, st: String) -> void:
	var catalog := GameState.catalog
	id = str(p.id)
	state = st
	name = "tag_" + id
	mouse_filter = MOUSE_FILTER_PASS
	var tip := Perks.is_tip(catalog, id)
	var lv := GameState.perk_level(id)
	var chalk := Color(UiTheme.TEXT, 0.62)
	var sb: StyleBox
	match st:
		"buy":
			sb = UiTheme.sticker(UiTheme.WISP, 10, UiTheme.RAISED, 9)
		"max":
			sb = UiTheme.sticker(UiTheme.WISP.lerp(UiTheme.LILAC_SEAM, 0.6), 10, UiTheme.RAISED, 9)
		"wait":
			sb = UiTheme.stitched(UiTheme.LILAC_SEAM, UiTheme.RAISED.lerp(UiTheme.PAGE, 0.45), 10, 9)
		"carrot":
			sb = UiTheme.stitched(chalk, UiTheme.DEEP.lerp(UiTheme.PAGE, 0.4), 10, 9)
		_:
			sb = UiTheme.sticker(UiTheme.GOLD.lerp(UiTheme.LILAC_SEAM, 0.65) if tip else UiTheme.LILAC_SEAM, 10, UiTheme.RAISED, 9)
	sb.content_margin_top = 13  # (the hole the string goes through)
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(col)
	# the thing, the name and the pips
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 7)
	var look := "carrot" if st == "carrot" else ("on" if lv > 0 or tip else ("off" if st == "wait" else "next"))
	var thing := TextureRect.new()
	thing.texture = PerkNail.texture(str(p.get("thing", "bow")), look, THING)
	thing.custom_minimum_size = Vector2(THING, THING)
	thing.size_flags_vertical = SIZE_SHRINK_CENTER
	thing.texture_filter = TEXTURE_FILTER_LINEAR
	top.add_child(thing)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 3)
	who.size_flags_horizontal = SIZE_EXPAND_FILL
	who.size_flags_vertical = SIZE_SHRINK_CENTER
	var nm := UiTheme.title(str(p.name), 13, chalk if st == "carrot" else (UiTheme.MUTED if st == "wait" else UiTheme.TEXT))
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(40, 0)
	who.add_child(nm)
	if st != "carrot":
		if tip:
			who.add_child(_lv_pill(lv))
		else:
			who.add_child(_Pips.new(lv, Perks.max_level(p)))
	top.add_child(who)
	col.add_child(top)
	if st == "carrot":
		_goal(col, int(p.get("floor", 0)))
		return
	col.add_child(_effect(p, lv, st == "max"))
	match st:
		"max":
			var done := PanelContainer.new()
			var dsb := UiTheme.stitched(UiTheme.PINK_SEAM, Color(0, 0, 0, 0), 8, 2)
			dsb.content_margin_left = 8
			dsb.content_margin_right = 8
			done.add_theme_stylebox_override("panel", dsb)
			done.add_child(UiTheme.label("all done!", UiTheme.PINK, UiTheme.SMALL))
			var tilt := Tilted.new(done, -3.0)
			tilt.size_flags_horizontal = SIZE_SHRINK_END
			col.add_child(tilt)
		"wait":
			var row := _price_row(GameState.perk_price(id), Color(UiTheme.MUTED, 0.7))
			var box := PanelContainer.new()
			var wsb := UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 8, 3)
			wsb.content_margin_left = 10
			wsb.content_margin_right = 10
			box.add_theme_stylebox_override("panel", wsb)
			row.alignment = BoxContainer.ALIGNMENT_END
			box.add_child(row)
			col.add_child(box)
		_:
			col.add_child(_buy_button(p, lv, tip, st == "buy"))


## The buy button: the word on the left, the wisps price on the right; solid coral when you can.
func _buy_button(p: Dictionary, lv: int, tip: bool, can: bool) -> Button:
	var b := Button.new()
	b.name = "buy_" + id
	b.focus_mode = FOCUS_NONE
	b.text = ""
	b.disabled = not can
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND if can else CURSOR_ARROW
	var on := UiTheme.box(UiTheme.WISP, UiTheme.WISP, 8, 2, 4)
	on.shadow_color = UiTheme.WISP.lerp(UiTheme.DEEP, 0.55)
	on.shadow_size = 0
	on.shadow_offset = Vector2(0, 3)
	var hover := on.duplicate()
	hover.bg_color = UiTheme.WISP.lerp(UiTheme.TEXT, 0.15)
	var down := on.duplicate()
	down.shadow_offset = Vector2(0, 1)
	var off := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 4)
	b.add_theme_stylebox_override("normal", on)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", down)
	b.add_theme_stylebox_override("disabled", off)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = Vector2(0, 26)
	var tint := UiTheme.DEEP if can else UiTheme.MUTED
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -10
	row.add_theme_constant_override("separation", 4)
	var word := UiTheme.label("one more" if lv > 0 or tip else "hang it up", tint, UiTheme.SMALL + 1)
	word.size_flags_horizontal = SIZE_EXPAND_FILL
	word.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(word)
	var price := _price_row(GameState.perk_price(id), tint)
	price.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(price)
	b.add_child(row)
	b.pressed.connect(func(): buy.emit(id))
	return b


## The lantern and a price.
func _price_row(price: int, tint: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var icon := UiTheme.icon_rect("lantern", 14, tint)
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	icon.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var l := UiTheme.label(UiTheme.num(price), tint, UiTheme.SMALL + 1)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


## The carrot's goal: "down to landing N", a meter and how far the army has been.
func _goal(col: VBoxContainer, f: int) -> void:
	var deep := int(GameState.dungeon.deep)
	col.add_child(UiTheme.label("down to landing %d" % f, UiTheme.MUTED, UiTheme.SMALL))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var meter := UiTheme.bar(UiTheme.LILAC)
	meter.custom_minimum_size = Vector2(30, 8)
	meter.max_value = float(maxi(f, 1))
	meter.value = float(mini(deep, f))
	row.add_child(meter)
	row.add_child(UiTheme.label("%d / %d" % [deep, f], UiTheme.TEXT, UiTheme.SMALL))
	col.add_child(row)


## What a perk does now → next, as numbers ("fits 300 → 600", "front row x1.20 → x1.40"); only what
## it does at its max.
func _effect(p: Dictionary, lv: int, maxed: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var what := UiTheme.label(str(p.get("what", "")), UiTheme.MUTED, UiTheme.SMALL)
	what.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	what.clip_text = true
	what.custom_minimum_size = Vector2(40, 0)
	col.add_child(what)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var now := Perks.card_value(GameState.catalog, p, lv)
	if maxed:
		row.add_child(UiTheme.label(fmt(p, now), UiTheme.WISP, UiTheme.SMALL))
	else:
		row.add_child(UiTheme.label(fmt(p, now), UiTheme.TEXT, UiTheme.SMALL))
		row.add_child(UiTheme.label("→", UiTheme.MUTED, UiTheme.SMALL))
		row.add_child(UiTheme.label(fmt(p, Perks.card_value(GameState.catalog, p, lv + 1)), UiTheme.WISP, UiTheme.SMALL))
	col.add_child(row)
	return col


## A perk's number as its tag shows it (data/perks.json "fmt").
static func fmt(p: Dictionary, v: float) -> String:
	match str(p.get("fmt", "x")):
		"num":
			return UiTheme.num(v)
		"cards":
			return "%d cards" % int(v)
		"hours":
			return "%s h" % (str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)
		"plus":
			return "+%d" % int(v)
	return "x%.2f" % v


func _lv_pill(lv: int) -> Control:
	var pill := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.WISP.lerp(UiTheme.LINE, 0.55), 999, 2, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_horizontal = SIZE_SHRINK_BEGIN
	pill.add_child(UiTheme.label("lv %d" % lv, UiTheme.WISP, UiTheme.SMALL - 1))
	return pill


func _draw() -> void:
	# the hole the string goes through
	var c := Vector2(size.x / 2.0, 6.0)
	draw_circle(c, 4.0, UiTheme.DEEP)
	draw_arc(c, 4.0, 0, TAU, 16, UiTheme.LINE, 2.0, true)


## Level pips: one per level, filled coral up to the level bought.
class _Pips extends Control:
	var _on := 0
	var _n := 1

	func _init(on: int, n: int) -> void:
		_on = on
		_n = maxi(n, 1)
		custom_minimum_size = Vector2(_n * 10 - 3, 7)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in _n:
			var c := Vector2(i * 10 + 3.5, 3.5)
			if i < _on:
				draw_circle(c, 3.5, UiTheme.WISP)
			else:
				draw_arc(c, 2.8, 0, TAU, 14, UiTheme.WISP.lerp(UiTheme.LINE, 0.55), 1.5, true)
