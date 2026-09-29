class_name WishJarCard
extends PanelContainer
## The wishing jar, a sticker standing beside the collection book (Wish, data/wish.json). The
## sticker you wished for is the jar's label; pets hop in from their shelf (a chip per rarity,
## then 1 / 10 / 100 / all) and fill it with dots in their colours, one band per step. A gold star
## on the jar's side lights for every full step, and the lid glows once the jar is full.
## Nothing wished for yet: an empty jar, no label, the buttons can't be pressed.

const TAKES := [1, 10, 100, -1]  # -1: all

var _art := JarArt.new()
var _count := HBoxContainer.new()
var _chips := HBoxContainer.new()
var _takes: Array[Button] = []
var _shelf := ""  # the rarity whose shelf is picked
var _shelves := {}  # the last GameState.wish_shelves()
var _chip_n := {}  # rarity -> its chip's count label
var _chip_pic := {}  # rarity -> its chip's portrait
var _chips_for := ""  # which shelves (and which one picked) the chips were built for
var _jar_dirty := true
var _shelves_dirty := true
var _shelves_at := -100000  # msec of the last look over the shelves
var _waiting := false  # a later look over the shelves is on its way
const SHELVES_EVERY := 1000  # msec: pets arrive all the time (box tables), the shelves catch up at most once a second


func _init() -> void:
	custom_minimum_size = Vector2(224, 0)
	size_flags_vertical = SIZE_EXPAND_FILL
	var sb := UiTheme.sticker(UiTheme.LILAC_SEAM, 14, UiTheme.RAISED, 10)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_bottom = 12
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := UiTheme.title("wishing jar", 18)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	_art.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(_art)
	_count.alignment = BoxContainer.ALIGNMENT_CENTER
	_count.add_theme_constant_override("separation", 0)
	_count.custom_minimum_size.y = 16
	col.add_child(_count)
	_chips.add_theme_constant_override("separation", 3)
	_chips.alignment = BoxContainer.ALIGNMENT_CENTER
	_chips.custom_minimum_size.y = 46
	col.add_child(_chips)
	var takes := HBoxContainer.new()
	takes.add_theme_constant_override("separation", 5)
	col.add_child(takes)
	for n in TAKES:
		var b := UiTheme.button("all" if n < 0 else str(n))
		b.name = "wish_take_%s" % ("all" if n < 0 else str(n))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size.x = 0
		b.pressed.connect(func(): send(n))
		takes.add_child(b)
		_takes.append(b)
	GameState.wish_changed.connect(func(_step): _mark_dirty(true))
	GameState.collection.pets_added.connect(func(_p): _mark_dirty())
	GameState.collection.pets_removed.connect(func(_u): _mark_dirty())
	GameState.collection.herd_changed.connect(func(_k): _mark_dirty())
	GameState.jobs_changed.connect(_mark_dirty)
	GameState.automation_changed.connect(_mark_dirty)
	GameState.new_game.connect(func():
		_shelf = ""
		_shelves_at = -100000
		_mark_dirty(true))
	visibility_changed.connect(_refresh_if_needed)


## Something changed: the shelves need another look (and the jar, when `jar`).
func _mark_dirty(jar := false) -> void:
	_jar_dirty = _jar_dirty or jar
	_shelves_dirty = true
	_refresh_if_needed.call_deferred()  # pets arrive in bursts: once a frame is plenty


func _refresh_if_needed() -> void:
	if not is_visible_in_tree():
		return
	if _jar_dirty:
		_refresh_jar()
	if not _shelves_dirty:
		return
	var wait := _shelves_at + SHELVES_EVERY - Time.get_ticks_msec()
	if wait <= 0:
		_refresh_shelves()
	elif not _waiting:
		_waiting = true
		get_tree().create_timer(wait / 1000.0).timeout.connect(func():
			_waiting = false
			_refresh_if_needed())


## Picks a shelf (a rarity) to send pets from.
func pick_shelf(rarity: String) -> void:
	_shelf = rarity
	if _shelves.has(rarity):
		_show_shelves()
	else:
		_refresh_shelves()


func refresh() -> void:
	_refresh_jar()
	_refresh_shelves()


## The jar and its N / M.
func _refresh_jar() -> void:
	_jar_dirty = false
	var catalog := GameState.catalog
	var key := str(GameState.wish.on)
	var where := Wish.where(catalog, Wish.sent(GameState.wish, key))
	_art.show_jar(key, where)
	UiTheme.clear(_count)
	if key != "":
		if where.done:
			_count.add_child(UiTheme.label(UiTheme.num(Wish.total(catalog)), UiTheme.TEXT, UiTheme.SMALL + 1))
		else:
			_count.add_child(UiTheme.label(UiTheme.num(where.have), UiTheme.TEXT, UiTheme.SMALL + 1))
			_count.add_child(UiTheme.label(" / %s" % UiTheme.num(where.need), UiTheme.MUTED, UiTheme.SMALL + 1))
	_update_takes()


## Looks over every pet for the shelves (one pass, see GameState.wish_shelves).
func _refresh_shelves() -> void:
	_shelves_dirty = false
	_shelves_at = Time.get_ticks_msec()
	_shelves = GameState.wish_shelves()
	_show_shelves()


## The shelves: a chip per rarity you have pets of that could go. The chips are only built again
## when which shelves there are (or which one is picked) changes; otherwise their counts and
## faces change in place.
func _show_shelves() -> void:
	var catalog := GameState.catalog
	if not _shelves.has(_shelf):
		_shelf = ""
		for t in catalog.tiers:
			if _shelves.has(t.id):
				_shelf = t.id
				break
	var ids: Array[String] = []
	for t in catalog.tiers:
		if _shelves.has(t.id):
			ids.append(str(t.id))
	var built_for := "%s|%s" % [",".join(ids), _shelf]
	if built_for != _chips_for:
		_chips_for = built_for
		UiTheme.clear(_chips)
		_chip_n.clear()
		_chip_pic.clear()
		for id in ids:
			_chips.add_child(_chip(id, _shelves[id]))
	else:
		for id in ids:
			var shelf: Dictionary = _shelves[id]
			(_chip_n[id] as Label).text = UiTheme.num(shelf.n)
			var pic: PetPortrait = _chip_pic[id]
			if pic.get_meta("uid", "") != shelf.first.uid:
				pic.set_pet(shelf.first)
				pic.set_meta("uid", shelf.first.uid)
	_update_takes()


func _update_takes() -> void:
	var key := str(GameState.wish.on)
	var done := bool(Wish.where(GameState.catalog, Wish.sent(GameState.wish, key)).done)
	var can: bool = key != "" and not done and _shelf != ""
	for b in _takes:
		b.disabled = not can


func _chip(rarity: String, shelf: Dictionary) -> Control:
	var color := GameState.catalog.tier_color(rarity)
	var on := rarity == _shelf
	var b := Button.new()
	b.name = "wish_shelf_" + rarity
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = GameState.catalog.tier_at(GameState.catalog.rank(rarity)).name
	b.custom_minimum_size = Vector2(32, 44)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb: StyleBox
	if on:
		sb = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 9, 2)
	else:
		sb = UiTheme.sticker(color.lerp(UiTheme.LINE, 0.5), 9, UiTheme.RAISED, 2)
		(sb as StyleBoxFlat).shadow_size = 3
		(sb as StyleBoxFlat).shadow_offset = Vector2(0, 2)
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(func(): pick_shelf(rarity))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	b.add_child(col)
	var portrait := PetPortrait.new(1, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.size_flags_horizontal = SIZE_SHRINK_CENTER
	portrait.set_pet(shelf.first)
	portrait.set_meta("uid", shelf.first.uid)
	col.add_child(portrait)
	_chip_pic[rarity] = portrait
	var n := UiTheme.title(UiTheme.num(shelf.n), 12, color)
	_chip_n[rarity] = n
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(n)
	var holder := Tilted.new(b, -3.0 if on else 0.0)
	holder.size_flags_horizontal = SIZE_EXPAND_FILL
	return holder


## Sends `n` pets from the picked shelf into the jar (-1: all that fit). Your pet cheers.
func send(n: int) -> void:
	if _shelf == "":
		return
	var rarity := _shelf
	var from: Control = null
	for c in _chips.get_children():
		var b := c.get_child(0) as Control
		if b and b.name == "wish_shelf_" + rarity:
			from = b
	var first: Pet = _shelves.get(rarity, {}).get("first")  # the chip's face: the one that goes first
	var got := GameState.send_to_wish(rarity, n)
	if int(got.sent) <= 0:
		return
	if _chip_n.has(rarity):  # the count drops now; the next look over the shelves catches the rest
		var shelf: Dictionary = _shelves[rarity]
		shelf.n = maxi(0, int(shelf.n) - int(got.sent))
		(_chip_n[rarity] as Label).text = UiTheme.num(shelf.n)
	_hop(from, first, mini(8, int(got.sent)))
	if int(got.after) > int(got.before):
		PetBubble.say_line(self, "wish_step_%d" % int(got.after))
		_star_rises()
	else:
		PetBubble.say_line(self, "wish_send")


## A few little pets hop from the shelf into the jar.
func _hop(from: Control, pet: Pet, count: int) -> void:
	if from == null or pet == null or not is_inside_tree():
		return
	var start := from.get_global_rect().get_center()
	var mouth := _art.mouth_global()
	for i in count:
		var p := PetPortrait.new(1, false)
		p.set_pet(pet)
		p.mouse_filter = MOUSE_FILTER_IGNORE
		p.top_level = true
		add_child(p)
		p.global_position = start - p.size / 2.0 + Vector2((i - count / 2.0) * 3.0, 0)
		p.pivot_offset = p.size / 2.0
		var t := p.create_tween()
		t.tween_interval(i * 0.07)
		var mid := (start + mouth) / 2.0 + Vector2(0, -40)
		t.tween_method(func(k: float):
			var a := start.lerp(mid, k)
			var b := mid.lerp(mouth, k)
			p.global_position = a.lerp(b, k) - p.size / 2.0
			p.scale = Vector2.ONE * lerpf(1.0, 0.6, k)
			p.modulate.a = 1.0 if k < 0.7 else lerpf(1.0, 0.0, (k - 0.7) / 0.3), 0.0, 1.0, 0.6)
		t.tween_callback(p.queue_free)


## A gold star floats up out of the jar.
func _star_rises() -> void:
	var star := UiTheme.icon_rect("xp", 20)
	star.top_level = true
	add_child(star)
	var at := _art.mouth_global() + Vector2(-10, 20)
	star.global_position = at
	var t := star.create_tween().set_parallel()
	t.tween_property(star, "global_position:y", at.y - 44.0, 1.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(star, "modulate:a", 0.0, 1.3).set_ease(Tween.EASE_IN)
	t.chain().tween_callback(star.queue_free)


## The jar itself, drawn: glass, the pets' dots filling it band by band, the step lines, a star
## per step down its side, the lid (glowing once it's full) and the wished sticker as its label.
class JarArt:
	extends Control

	const SPECKS := 110  # how many dots are drawn in a full jar (only the drawing; data/wish.json "dots" is how many colours a jar keeps)
	const VIEW := Vector2(172, 214)  # the drawing's own size; it's scaled to fit
	const TOP := 44.0  # where the top band starts
	const BOT := 200.0  # the jar's floor
	const GLASS := [[40, 40], ["q", 18, 48, 18, 80], [20, 186], ["q", 22, 206, 46, 207], [126, 207], ["q", 150, 206, 152, 186], [154, 80], ["q", 154, 48, 132, 40]]

	var _key := ""
	var _where := {}
	var _label: Control
	var _glass := PackedVector2Array()

	func _init() -> void:
		custom_minimum_size = Vector2(172, 200)
		mouse_filter = MOUSE_FILTER_IGNORE
		resized.connect(_place_label)
		_glass = _path(GLASS)

	func show_jar(key: String, where: Dictionary) -> void:
		var label_changed := key != _key or _label == null
		_key = key
		_where = where
		if label_changed:
			if _label:
				_label.queue_free()
				_label = null
			if key != "":
				_label = _make_label(key)
				add_child(_label)
			_place_label()
		queue_redraw()

	## Where pets drop in (the lid), in global coordinates.
	func mouth_global() -> Vector2:
		return get_global_transform() * _to_local_px(Vector2(86, 36))

	func _make_label(key: String) -> Control:
		var bits := key.split(":")
		var part := Catalog.shared().part(bits[1], bits[2])
		var tier := str(part.get("rarity", "common"))
		var color := Catalog.shared().tier_color(tier)
		var panel := PanelContainer.new()
		var sb := UiTheme.sticker(color.lerp(UiTheme.LINE, 0.4), 7, UiTheme.RAISED, 4)
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 3)
		panel.add_theme_stylebox_override("panel", sb)
		panel.mouse_filter = MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		panel.add_child(col)
		var portrait := PetPortrait.new(2, false)
		portrait.mouse_filter = MOUSE_FILTER_IGNORE
		portrait.set_pet(BookView.showcase_pet(key))
		col.add_child(portrait)
		var name_label := UiTheme.label(BookView.look_name(key), UiTheme.TEXT, UiTheme.SMALL)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(name_label)
		var tier_label := UiTheme.tier_label(tier, UiTheme.SMALL - 1)
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(tier_label)
		panel.custom_minimum_size.x = 84
		var t := Tilted.new(panel, -3.0)
		t.mouse_filter = MOUSE_FILTER_IGNORE
		return t

	func _place_label() -> void:
		if _label == null:
			return
		var s := _label.get_combined_minimum_size()
		_label.size = s
		_label.position = (_to_local_px(Vector2(86, 112)) - s / 2.0).round()

	func _scale() -> float:
		return minf(size.x / VIEW.x, size.y / VIEW.y)

	func _offset() -> Vector2:
		return (size - VIEW * _scale()) / 2.0

	func _to_local_px(p: Vector2) -> Vector2:
		return _offset() + p * _scale()

	func _draw() -> void:
		var k := _scale()
		draw_set_transform(_offset(), 0.0, Vector2(k, k))
		var full := int(_where.get("full", 0))
		var done := bool(_where.get("done", false))
		var band := (BOT - TOP) / 4.0
		var level := minf(4.0, full + float(_where.get("f", 0.0))) if _key != "" else 0.0
		var fill_y := BOT - level * band
		# the glass
		draw_colored_polygon(_glass, UiTheme.PAGE.lerp(UiTheme.LILAC, 0.06))
		# what's in it: the pets' colours, up to the level
		if level > 0.0:
			var below := PackedVector2Array([Vector2(0, fill_y), Vector2(VIEW.x, fill_y), Vector2(VIEW.x, VIEW.y), Vector2(0, VIEW.y)])
			for poly in Geometry2D.intersect_polygons(_glass, below):
				draw_colored_polygon(poly, UiTheme.DEEP.lerp(UiTheme.PINK, 0.16))
			_draw_dots(fill_y)
			if not done:
				var wave := PackedVector2Array()
				for i in 29:
					var x := 20.0 + i * (132.0 / 28.0)
					wave.append(Vector2(x, fill_y + sin(x / 11.0) * 1.8))
				draw_polyline(wave, UiTheme.PINK, 2.0, true)
		# the step lines
		for s in [1, 2, 3]:
			var y: float = BOT - s * band
			var x := 26.0
			while x < 146.0:
				draw_line(Vector2(x, y + 1.0), Vector2(minf(x + 4.0, 146.0), y + 1.0), UiTheme.LILAC_SEAM, 1.6)
				x += 9.0
		var outline := _glass.duplicate()
		outline.append(_glass[0])
		draw_polyline(outline, UiTheme.LILAC_SEAM, 2.6, true)
		draw_line(Vector2(32, 72), Vector2(33, 150), Color(UiTheme.TEXT, 0.14), 3.0, true)  # a shine on the glass
		# the neck and the lid
		var neck := UiTheme.box(UiTheme.DEEP, UiTheme.LILAC_SEAM, 3, 2, 0)
		neck.draw(get_canvas_item(), _px(Rect2(46, 30, 80, 12)))
		if done:  # the lid glows
			for g in 4:
				var glow := UiTheme.box(Color(UiTheme.GOLD, 0.10), Color(0, 0, 0, 0), 10 + g * 2, 0, 0)
				var grow := 3.0 + g * 3.0
				glow.draw(get_canvas_item(), _px(Rect2(40 - grow, 10 - grow, 92 + grow * 2.0, 22 + grow * 2.0)))
		var lid := UiTheme.box(UiTheme.RAISED.lerp(UiTheme.PINK, 0.3), UiTheme.GOLD if done else UiTheme.PINK_SEAM, 6, 2, 0)
		lid.draw(get_canvas_item(), _px(Rect2(40, 10, 92, 22)))
		draw_set_transform(_offset(), 0.0, Vector2(k, k))
		for x in range(52, 125, 12):
			draw_line(Vector2(x, 17), Vector2(x, 25), UiTheme.GOLD if done else UiTheme.PINK_SEAM, 2.0)
		# a star per step down its side, gold once full
		for s in [1, 2, 3, 4]:
			_draw_star(Vector2(160, BOT - s * band + 4.0), 7.0, full >= s)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	## A rect in the drawing's units, in this control's pixels (styleboxes draw untransformed).
	func _px(r: Rect2) -> Rect2:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return Rect2(_to_local_px(r.position), r.size * _scale())

	func _draw_dots(fill_y: float) -> void:
		var jar: Dictionary = GameState.wish.jars.get(_key, {})
		var dots: Array = jar.get("dots", [])
		var catalog := Catalog.shared()
		var colors: Array[Color] = []
		for d in dots:
			colors.append(Color(str(catalog.part("palette", str(d)).get("body", "#ff79c6"))))
		if colors.is_empty():
			colors.append(UiTheme.PINK)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(_key)
		var inside := Geometry2D.offset_polygon(_glass, -4.0)
		var shape: PackedVector2Array = inside[0] if not inside.is_empty() else _glass
		for i in SPECKS:
			var p := Vector2(22.0 + rng.randf() * 128.0, TOP - 6.0 + rng.randf() * (BOT - TOP + 6.0))
			var r := 2.0 + rng.randf() * 2.2
			if p.y - r * 0.5 < fill_y or not Geometry2D.is_point_in_polygon(p, shape):
				continue
			var c: Color = colors[i % colors.size()]
			c.a = 0.85
			draw_circle(p, r, c)

	func _draw_star(c: Vector2, r: float, on: bool) -> void:
		var pts := PackedVector2Array()
		var tips := [Vector2(0, -r), Vector2(r, 0), Vector2(0, r), Vector2(-r, 0)]
		for i in 4:
			var a: Vector2 = tips[i]
			var b: Vector2 = tips[(i + 1) % 4]
			var pull := (a + b) * 0.22  # the quadratic's control point, pulled in
			for j in 6:
				var t := j / 6.0
				pts.append(c + a.lerp(pull, t).lerp(pull.lerp(b, t), t))
		if on:
			draw_colored_polygon(pts, UiTheme.GOLD)
		var line := pts.duplicate()
		line.append(pts[0])
		draw_polyline(line, UiTheme.GOLD if on else UiTheme.MUTED_SEAM, 1.8, true)

	## A path of points and ["q", control x, control y, x, y] quadratic curves, as one outline.
	static func _path(steps: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for s in steps:
			if s[0] is String:
				var from := out[out.size() - 1]
				var ctrl := Vector2(s[1], s[2])
				var to := Vector2(s[3], s[4])
				for j in range(1, 9):
					var t := j / 8.0
					out.append(from.lerp(ctrl, t).lerp(ctrl.lerp(to, t), t))
			else:
				out.append(Vector2(s[0], s[1]))
		# the last curve ends where the first point is: drop the repeat
		if out.size() > 1 and out[out.size() - 1].is_equal_approx(out[0]):
			out.remove_at(out.size() - 1)
		return out
