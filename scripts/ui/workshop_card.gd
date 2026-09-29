class_name WorkshopCard
extends PanelContainer
## The shed workshop (F3, look A): a card stuck on the backyard map when you tap the old shed once
## it's ours and the whistle is found. Drawings pinned on a wooden plank (each with a little bar),
## the picked one's needs (helpers, and how many at its tier or up), shelf chips to pick who helps,
## 1 / 10 / 100 / all, and "not yet" / "build it!". All the pinned drawings fill at once; building
## one pins the next in its spot. Your pet talks in the shared bubble. Rules: Workshop, GameState.
## Design: design/mockups/screens/shed-workshop.html (look A).

signal closed  # "not yet"
signal to_place  # the "adventure ›" pill: the shed's own place card instead

const WIDTH := 298.0
const PAPER_TILTS := [-3.0, 2.0, -1.5]

var picked := ""  # the drawing picked on the plank
var from := ""  # the shelf (rarity) helpers come from
var _fresh := ""  # a drawing just pinned (it pops in)
var _planks := HBoxContainer.new()
var _need_rows := VBoxContainer.new()
var _helpers_meter := Meter.new()
var _helpers_value := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
var _tier_name := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _tier_meter := Meter.new()
var _tier_value := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
var _chips := HBoxContainer.new()
var _takes: Array[Button] = []
var _build: Button
var _build_tilt: Tilted
var _nudge := 0.0
var _cheer := 0
var _dirty := true
var _wait := 0.0  # the herd changes all the time once pets work: redraw at most this often
var _papers := {}  # drawing id -> its Paper on the plank
var _plank_key := ""  # what the plank was built for (pins + picked): same key, just refill the bars
var _chip_counts := {}  # rarity -> the count label on its shelf chip
var _chips_key := ""  # which shelves had chips (and the picked one): same key, just new counts

const REDRAW := 0.4


func _init() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	mouse_filter = MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)

	# the old shed, ours!
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var title := UiTheme.title(Catalog.shared().location("shed").get("name", "the old shed"), 18)
	head.add_child(title)
	var ours := UiTheme.label("ours!", UiTheme.GOLD, UiTheme.SMALL)
	ours.size_flags_vertical = SIZE_SHRINK_END
	head.add_child(ours)
	head.add_child(UiTheme.spacer())
	var go := UiTheme.small_button("adventure ›", func(): to_place.emit())
	go.add_theme_font_size_override("font_size", UiTheme.SMALL)
	go.add_theme_color_override("font_color", UiTheme.MUTED)
	head.add_child(go)
	col.add_child(head)

	# the plank the drawings are pinned on
	var plank := PanelContainer.new()
	var wood := UiTheme.box(UiTheme.DEEP.lerp(UiTheme.GOLD, 0.08), UiTheme.LINE.lerp(UiTheme.GOLD, 0.14), 10, 2, 6)
	wood.content_margin_top = 13
	wood.content_margin_bottom = 10
	plank.add_theme_stylebox_override("panel", wood)
	plank.draw.connect(func():
		var line := UiTheme.LINE.lerp(UiTheme.GOLD, 0.14)
		var y := 36.0
		while y < plank.size.y - 4.0:
			plank.draw_rect(Rect2(2.0, y, plank.size.x - 4.0, 2.0), line)
			y += 36.0)
	_planks.alignment = BoxContainer.ALIGNMENT_CENTER
	_planks.add_theme_constant_override("separation", 8)
	plank.add_child(_planks)
	col.add_child(plank)

	# the picked drawing's needs
	_need_rows.add_theme_constant_override("separation", 5)
	_need_rows.add_child(_need_row(UiTheme.label("helpers", UiTheme.MUTED, UiTheme.SMALL), _helpers_meter, _helpers_value))
	_need_rows.add_child(_need_row(_tier_name, _tier_meter, _tier_value))
	col.add_child(_need_rows)

	# who helps: a shelf, then how many
	_chips.add_theme_constant_override("separation", 4)
	col.add_child(_chips)
	var takes := GridContainer.new()
	takes.columns = 4
	takes.add_theme_constant_override("h_separation", 6)
	for n in Catalog.shared().workshop.get("takes", [1, 10, 100, -1]):
		var b := UiTheme.button("all" if int(n) < 0 else str(int(n)), _take.bind(int(n)))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		var pad := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if int(n) < 0 else UiTheme.LILAC_SEAM, 8, 2, 4)
		b.add_theme_stylebox_override("normal", pad)
		takes.add_child(b)
		_takes.append(b)
	col.add_child(takes)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var not_yet := UiTheme.button("not yet", func(): closed.emit())
	not_yet.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(not_yet)
	_build = UiTheme.button("build it!", _build_it)
	_build.icon = UiTheme.icon("heart", 14)
	_build.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_build.add_theme_constant_override("icon_max_width", 14)
	_build.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	_build_tilt = Tilted.new(_build, 0.0)
	_build_tilt.size_flags_horizontal = SIZE_EXPAND_FILL
	_build_tilt.size_flags_stretch_ratio = 1.6
	row.add_child(_build_tilt)
	col.add_child(row)

	var c := GameState.collection
	for sig: Signal in [c.herd_changed, c.pets_added, c.pets_removed, c.pet_changed, c.active_changed]:
		sig.connect(func(_x): mark())
	for sig: Signal in [GameState.jobs_changed, GameState.automation_changed, GameState.adventures_changed, GameState.new_game]:
		sig.connect(mark)
	GameState.workshop_changed.connect(func(_id): mark())
	visibility_changed.connect(mark)


func mark() -> void:
	_dirty = true


## The card opens: your pet says hello, the picked drawing stays picked if it's still up.
func open() -> void:
	_fresh = ""
	_plank_key = ""
	_chips_key = ""
	mark()
	refresh()
	PetBubble.say(self, str(Catalog.shared().workshop.get("open_say", "")))


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_wait -= delta
	if _dirty and _wait <= 0.0:
		refresh()
	# a full drawing: "build it!" gives a little nudge now and then
	if not _build.disabled:
		_nudge = fmod(_nudge + delta, 1.4)
		var t := _nudge / 1.4
		_build_tilt.degrees = -2.0 if t > 0.74 and t < 0.82 else (2.0 if t >= 0.82 and t < 0.9 else 0.0)
	elif _build_tilt.degrees != 0.0:
		_build_tilt.degrees = 0.0


func refresh() -> void:
	_dirty = false
	_wait = REDRAW
	var catalog := Catalog.shared()
	var state := GameState.workshop
	var pins := Workshop.pinned(state)
	if not picked in pins:
		picked = pins[0] if not pins.is_empty() else ""
	# the plank: the same drawings pinned (and picked) only refill their bars
	var key := "%s|%s" % [",".join(PackedStringArray(state.pinned.map(func(x): return str(x)))), picked]
	if key == _plank_key and _fresh == "":
		for id: String in _papers:
			(_papers[id] as Paper).refill(Workshop.fill(catalog, state, id), Workshop.full(catalog, state, id))
	else:
		_plank_key = key
		_papers.clear()
		UiTheme.clear(_planks)
		for i in state.pinned.size():
			var id := str(state.pinned[i])
			if id == "":
				continue
			var paper := Paper.new(Workshop.drawing(catalog, id), Workshop.fill(catalog, state, id), Workshop.full(catalog, state, id), id == picked)
			paper.name = "paper_" + id
			paper.pressed.connect(_pick.bind(id))
			_papers[id] = paper
			var held := Tilted.new(paper, PAPER_TILTS[i % PAPER_TILTS.size()])
			_planks.add_child(held)
			if id == _fresh:
				_pop(held)
	_fresh = ""
	var d := Workshop.drawing(catalog, picked)
	_need_rows.visible = not d.is_empty()
	_build.disabled = d.is_empty() or not Workshop.full(catalog, state, picked)
	_build.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.PINK_PRESSED, UiTheme.PINK, 8, 2, 6) if not _build.disabled else UiTheme.box(UiTheme.DEEP, UiTheme.MUTED_SEAM, 8, 2, 6))
	_build.add_theme_color_override("font_color", UiTheme.PINK if not _build.disabled else UiTheme.TEXT)
	if d.is_empty():
		UiTheme.clear(_chips)
		_chips_key = ""
		_chip_counts.clear()
		return
	var p := Workshop.prog(state, picked)
	var tier_color := catalog.tier_color(str(d.tier))
	_helpers_meter.set_fill(float(p.sent) / maxf(1.0, float(d.need)), UiTheme.LILAC)
	_helpers_value.text = "%s/%s" % [UiTheme.num(int(p.sent)), UiTheme.num(int(d.need))]
	_helpers_value.add_theme_color_override("font_color", UiTheme.PINK if int(p.sent) >= int(d.need) else UiTheme.TEXT)
	_tier_name.text = "%s or up" % catalog.tier_at(catalog.rank(str(d.tier))).name
	_tier_name.add_theme_color_override("font_color", tier_color)
	_tier_meter.set_fill(float(p.qual) / maxf(1.0, float(d.count)), tier_color)
	_tier_value.text = "%s/%s" % [UiTheme.num(mini(int(p.qual), int(d.count))), UiTheme.num(int(d.count))]
	_tier_value.add_theme_color_override("font_color", UiTheme.PINK if int(p.qual) >= int(d.count) else UiTheme.TEXT)
	_refresh_chips(d)


## One chip per shelf that has pets who could help (a face and how many may go).
func _refresh_chips(d: Dictionary) -> void:
	var catalog := Catalog.shared()
	var have := {}
	for tier in catalog.tiers:
		var n := GameState.homes_can_go(str(tier.id))
		if n > 0:
			have[str(tier.id)] = n
	if not have.has(from):
		from = ""
		for tier_id: String in have:  # the first shelf that counts toward the tier, else the first
			if Workshop.meets(catalog, d, tier_id):
				from = tier_id
				break
		if from == "" and not have.is_empty():
			from = have.keys()[0]
	_chips.visible = not have.is_empty()
	# the same shelves (and the same one picked): only their counts change
	var key := "%s|%s" % [",".join(PackedStringArray(have.keys())), from]
	if key == _chips_key:
		for tier_id: String in have:
			(_chip_counts[tier_id] as Label).text = UiTheme.num(int(have[tier_id]))
	else:
		_chips_key = key
		_chip_counts.clear()
		UiTheme.clear(_chips)
		for tier_id: String in have:
			_chips.add_child(_chip(tier_id, int(have[tier_id])))
	for b in _takes:
		b.disabled = from == ""


func _chip(tier_id: String, n: int) -> Control:
	var catalog := Catalog.shared()
	var color := catalog.tier_color(tier_id)
	var on := tier_id == from
	var b := Button.new()
	b.name = "shelf_" + tier_id
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = catalog.tier_at(catalog.rank(tier_id)).name
	b.custom_minimum_size = Vector2(38, 40)
	var sb: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.DEEP, 10, 3) if on else UiTheme.box(UiTheme.DEEP, color.lerp(UiTheme.LINE, 0.55), 10, 2, 3)
	for state in ["normal", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("hover", sb if on else UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 10, 2, 3))
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var face := PetPortrait.new(1, false)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.size_flags_horizontal = SIZE_SHRINK_CENTER
	face.set_pet(NewHomesStall.face_for(tier_id))
	col.add_child(face)
	var count := UiTheme.title(UiTheme.num(n), 11, UiTheme.TEXT)
	_chip_counts[tier_id] = count
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(count)
	b.add_child(col)
	b.pressed.connect(func():
		from = tier_id
		refresh())
	var held := Tilted.new(b, -2.0 if on else 0.0)
	held.size_flags_horizontal = SIZE_EXPAND_FILL
	return held


func _need_row(name_label: Label, meter: Meter, value: Label) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	name_label.custom_minimum_size = Vector2(100, 0)
	name_label.clip_text = true
	row.add_child(name_label)
	meter.size_flags_horizontal = SIZE_EXPAND_FILL
	meter.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(meter)
	value.custom_minimum_size = Vector2(58, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _pick(id: String) -> void:
	picked = id
	refresh()
	PetBubble.say(self, str(Workshop.drawing(Catalog.shared(), id).get("say", "")))


func _take(n: int) -> void:
	if picked == "" or from == "":
		return
	var w := Catalog.shared().workshop
	var went := GameState.send_helpers(picked, from, n)
	var full := Workshop.full(Catalog.shared(), GameState.workshop, picked)
	if went <= 0:
		PetBubble.say(self, str(w.get("ready" if full else "fancier", "")))
		return
	if full:
		PetBubble.say(self, str(w.get("ready", "")))
	else:
		var cheer: Array = w.get("cheer", [])
		if not cheer.is_empty():
			PetBubble.say(self, str(cheer[_cheer % cheer.size()]))
			_cheer += 1
	refresh()


func _build_it() -> void:
	var id := picked
	var d := Workshop.drawing(Catalog.shared(), id)
	var i: int = GameState.workshop.pinned.find(id)
	if not GameState.build_drawing(id):
		return
	var next := str(GameState.workshop.pinned[i]) if i >= 0 else ""
	picked = next
	_fresh = next
	refresh()
	PetBubble.say(self, str(d.get("done", "")))


## A drawing just pinned pops onto the plank.
func _pop(held: Control) -> void:
	held.pivot_offset = Vector2(41, 90)
	held.scale = Vector2(0.3, 0.3)
	held.modulate.a = 0.0
	var t := held.create_tween().set_parallel()
	t.tween_property(held, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(held, "modulate:a", 1.0, 0.25)


## A drawing pinned on the plank: crayon on a dotted sheet with a pink pin, its short name and a
## little bar of how many helpers it has. The picked one has a dashed outline.
class Paper:
	extends Button

	const SIZE := Vector2(82, 90)
	const ART := 50

	var d: Dictionary
	var frac := 0.0
	var is_full := false
	var on := false
	var _name := Label.new()

	func _init(drawing: Dictionary, fill: float, full: bool, picked: bool) -> void:
		d = drawing
		frac = fill
		is_full = full
		on = picked
		focus_mode = FOCUS_NONE
		flat = true
		custom_minimum_size = SIZE
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, StyleBoxEmpty.new())
		tooltip_text = str(d.get("name", ""))
		var short := str(d.get("name", "")).trim_prefix("the ")
		_name.text = short
		_name.mouse_filter = MOUSE_FILTER_IGNORE
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		var fs := 11
		while fs > 8 and UiTheme.DISPLAY_FONT.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > SIZE.x - 6.0:
			fs -= 1
		_name.add_theme_font_size_override("font_size", fs)
		_name.add_theme_color_override("font_color", UiTheme.LILAC)
		_name.position = Vector2(0, 9 + ART + 1)
		_name.size = Vector2(SIZE.x, 14)
		add_child(_name)

	## New helpers: the little bar fills (no new node, so a click in progress isn't lost).
	func refill(fill: float, full: bool) -> void:
		if fill != frac or full != is_full:
			frac = fill
			is_full = full
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if on:
			var dash := StitchBox.new()
			dash.dash_color = UiTheme.PINK
			dash.bg_color = Color(0, 0, 0, 0)
			dash.radius = 6
			draw_style_box(dash, r.grow(4))
		var sheet_color := UiTheme.RAISED.lerp(UiTheme.LILAC, 0.13)
		var sheet := UiTheme.box(sheet_color, sheet_color, 4, 0, 0)
		sheet.shadow_color = UiTheme.SHADOW
		sheet.shadow_size = 5
		sheet.shadow_offset = Vector2(0, 3)
		draw_style_box(sheet, r)
		var dot := UiTheme.RAISED.lerp(UiTheme.LILAC, 0.22)
		var y := 4.0
		while y < size.y:
			var x := 4.0
			while x < size.x:
				draw_rect(Rect2(x - 0.7, y - 0.7, 1.4, 1.4), dot)
				x += 8.0
			y += 8.0
		var ink := UiTheme.TEXT
		ink.a = 0.85
		draw_texture_rect(UiTheme.drawing(str(d.get("art", "")), ART, ink, 2.2), Rect2((size.x - ART) / 2.0, 9, ART, ART), false)
		# the pin
		draw_circle(Vector2(size.x / 2.0, 1.0), 6.0, UiTheme.SHADOW)
		draw_circle(Vector2(size.x / 2.0, 0.0), 5.0, UiTheme.PINK)
		# the little bar
		var bar := Rect2(6, size.y - 11, size.x - 12, 5)
		draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.DEEP, 3, 0, 0), bar)
		if frac > 0.0:
			var c := UiTheme.PINK if is_full else UiTheme.LILAC
			draw_style_box(UiTheme.box(c, c, 3, 0, 0), Rect2(bar.position, Vector2(maxf(5.0, bar.size.x * frac), bar.size.y)))


## A rounded meter: a sunk track with a coloured fill.
class Meter:
	extends Control

	var fill := 0.0
	var color := Color.WHITE

	func _init() -> void:
		custom_minimum_size = Vector2(40, 12)
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_fill(f: float, c: Color) -> void:
		fill = clampf(f, 0.0, 1.0)
		color = c
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiTheme.box(UiTheme.DEEP, color.lerp(UiTheme.LINE, 0.55), 999, 2, 0), r)
		if fill > 0.0:
			var w := maxf(r.size.y - 4.0, (r.size.x - 4.0) * fill)
			draw_style_box(UiTheme.box(color, Color(0, 0, 0, 0), 999, 0, 0), Rect2(Vector2(2, 2), Vector2(w, r.size.y - 4.0)))
