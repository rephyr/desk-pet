class_name BookView
extends VBoxContainer
## The collection book, as a sticker album open on two pages. One page per part slot (bodies,
## palettes, patterns, eyes, accessories), then one per body for its finishes. Parts you've pulled
## are stickers stuck in a little crooked, with how many you've had; the rest are empty dashed
## spots with a dark silhouette. Bookmarks along the top jump between spreads.
## A page with a reward sticker (data/book.json, Book) ends with it: a dashed gift spot until the
## page is full, then the sticker itself, stuck in for good.
## `narrow`: the wishing jar stands beside the book (WishJarCard): three stickers a row, and a
## found part's sticker is tapped to wish for it; the wished one gets a jar badge and a pink
## dashed outline.

# the pet every part is shown on, with just that one part swapped in
const SHOWCASE := { "body": "blob", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
const SLOT_TITLES := { "body": "bodies", "palette": "palettes", "pattern": "patterns", "eyes": "eyes", "accessory": "accessories" }
const TILTS := [-2.5, 1.5, -1.0, 2.2, -1.8, 1.0, 2.6, -2.2, 0.8, -1.4]

var _found_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL + 1)
var _marks := HBoxContainer.new()
var _spread := HBoxContainer.new()
var _pages: Array[Dictionary] = []  # { title, bookmark, sticker (its data/book.json page, or {}), tiles: [{ parts, finish, name, tier, seen }] }
var _at := 0  # which spread is open
var _dirty := true
var _shown_wish := ""  # the wish the stickers were drawn with
var narrow := false:
	set(value):
		if value != narrow:
			narrow = value
			_mark_dirty()


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 0)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.spacer())
	head.add_child(_found_label)
	add_child(head)
	_marks.add_theme_constant_override("separation", 4)
	var marks_pad := MarginContainer.new()
	marks_pad.add_theme_constant_override("margin_left", 14)
	marks_pad.add_theme_constant_override("margin_top", 4)
	marks_pad.add_child(_marks)
	add_child(marks_pad)
	var book := PanelContainer.new()
	book.size_flags_vertical = SIZE_EXPAND_FILL
	book.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 14, UiTheme.RAISED, 0))
	book.add_child(_spread)
	_spread.add_theme_constant_override("separation", 0)
	# the binding: stitches down the middle
	_spread.draw.connect(func():
		var x := _spread.size.x / 2.0
		var y := 10.0
		while y < _spread.size.y - 10.0:
			_spread.draw_line(Vector2(x, y), Vector2(x, y + 6.0), UiTheme.PINK_SEAM, 2.0)
			y += 11.0)
	add_child(book)
	GameState.collection.pets_added.connect(func(_p): _mark_dirty())
	GameState.sticker_opened.connect(func(_id): _mark_dirty())
	GameState.collection.seen_changed.connect(_mark_dirty)
	GameState.wish_changed.connect(func(_step):
		if str(GameState.wish.on) != _shown_wish:
			_mark_dirty())
	visibility_changed.connect(_rebuild_if_needed)


func _mark_dirty() -> void:
	_dirty = true
	_rebuild_if_needed()


func _rebuild_if_needed() -> void:
	if not _dirty or not is_visible_in_tree():
		return
	_dirty = false
	_collect()
	_show_spread()


## What's in the book: every part, then every body's finishes, with how often you've pulled each.
func _collect() -> void:
	_pages.clear()
	var catalog := Catalog.shared()
	var collection := GameState.collection
	var got := 0
	var total := 0
	for slot in Catalog.SLOTS:
		var tiles: Array = []
		for part in catalog.slots[slot]:
			var parts := SHOWCASE.duplicate()
			parts[slot] = part.id
			var shown_name: String = "no hat" if slot == "accessory" and part.id == "none" else part.name
			var key := Collection.part_key(slot, part.id)
			tiles.append({ "parts": parts, "finish": "normal", "name": shown_name, "tier": part.rarity, "seen": collection.times_seen(key), "key": key })
		_pages.append({ "title": SLOT_TITLES[slot], "bookmark": SLOT_TITLES[slot], "tiles": tiles, "sticker": Book.page_for(catalog, slot) })
	for body in catalog.slots.body:
		var tiles: Array = []
		for f in catalog.finishes:
			var parts := SHOWCASE.duplicate()
			parts.body = body.id
			tiles.append({ "parts": parts, "finish": f.id, "name": f.name if f.name != "" else "normal", "tier": f.rarity, "seen": collection.times_seen(Collection.finish_key(body.id, f.id)), "key": "" })
		_pages.append({ "title": "%s finishes" % body.name, "bookmark": "finishes" if body == catalog.slots.body[0] else "", "tiles": tiles,
			"sticker": Book.page_for(catalog, "", str(body.id)) })
	for page in _pages:
		for t in page.tiles:
			total += 1
			got += 1 if t.seen > 0 else 0
	_found_label.text = "found %d of %d stickers" % [got, total]


## Opens the book on the spread with this sticker's page (the popup's "show me").
func open_page(page_id: String) -> void:
	_collect()
	_dirty = false
	for i in _pages.size():
		if page_id != "" and str(_pages[i].sticker.get("id", "")) == page_id:
			_at = i >> 1
			break
	_show_spread()


func _show_spread() -> void:
	_shown_wish = str(GameState.wish.on)
	var spreads := ceili(_pages.size() / 2.0)
	_at = clampi(_at, 0, spreads - 1)
	UiTheme.clear(_marks)
	for i in _pages.size():
		var page: Dictionary = _pages[i]
		if page.bookmark == "":
			continue
		var on: bool = i / 2 == _at or (page.bookmark == "finishes" and _at >= i / 2)
		var mark := Button.new()
		mark.text = page.bookmark
		mark.focus_mode = FOCUS_NONE
		mark.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		var sb := UiTheme.box(UiTheme.RAISED if on else UiTheme.DEEP, UiTheme.PINK_SEAM if on else UiTheme.LINE, 8, 2, 4)
		sb.corner_radius_bottom_left = 0
		sb.corner_radius_bottom_right = 0
		sb.border_width_bottom = 0
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_bottom = 10 if on else 6
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			mark.add_theme_stylebox_override(state, sb)
		mark.add_theme_color_override("font_color", UiTheme.PINK if on else UiTheme.MUTED)
		mark.size_flags_vertical = SIZE_SHRINK_END
		if _full(page):
			mark.icon = UiTheme.icon("xp", 12)
			mark.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			mark.add_theme_constant_override("icon_max_width", 12)
		var to := i / 2
		mark.pressed.connect(func():
			_at = to
			_show_spread())
		_marks.add_child(mark)
	UiTheme.clear(_spread)
	for side in 2:
		var index := _at * 2 + side
		_spread.add_child(_page(_pages[index] if index < _pages.size() else {}, side, spreads))


func _full(page: Dictionary) -> bool:
	return page.tiles.all(func(t): return t.seen > 0)


func _page(page: Dictionary, side: int, spreads: int) -> Control:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = SIZE_EXPAND_FILL
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 12 if narrow else 18)
	margin.add_theme_constant_override("margin_top", 12 if narrow else 14)
	margin.add_theme_constant_override("margin_bottom", 6 if narrow else 8)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8 if narrow else 12)
	margin.add_child(col)
	if page.is_empty():
		return margin
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiTheme.title(page.title, 20))
	var found: int = page.tiles.filter(func(t): return t.seen > 0).size()
	var full: bool = found == page.tiles.size()
	var count := UiTheme.label("page full!" if full else "%d of %d" % [found, page.tiles.size()], UiTheme.GOLD if full else UiTheme.MUTED, UiTheme.SMALL + 1)
	count.size_flags_vertical = SIZE_SHRINK_END
	head.add_child(count)
	col.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3 if narrow else 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8 if narrow else 12)
	for i in page.tiles.size():
		grid.add_child(_slot(page.tiles[i], i))
	if not page.sticker.is_empty():
		grid.add_child(_reward(page.sticker))
	col.add_child(grid)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	var turn := HBoxContainer.new()
	if side == 0 and _at > 0:
		turn.add_child(UiTheme.small_button("‹ back", func():
			_at -= 1
			_show_spread()))
	turn.add_child(UiTheme.spacer())
	if side == 1 and _at < spreads - 1:
		turn.add_child(UiTheme.small_button("turn ›", func():
			_at += 1
			_show_spread()))
	col.add_child(turn)
	return margin


## A found part stuck in a little crooked, or an empty dashed spot with a dark silhouette.
func _slot(tile: Dictionary, i: int) -> Control:
	var got: bool = tile.seen > 0
	var color := Catalog.shared().tier_color(tile.tier)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = _tile_size()
	if got:
		panel.add_theme_stylebox_override("panel", UiTheme.sticker(color, 10, UiTheme.PAGE, 4))
		panel.tooltip_text = "%s (%s)" % [tile.name, Catalog.shared().tier_at(Catalog.shared().rank(tile.tier)).name]
	else:
		panel.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.LINE, UiTheme.DEEP.lerp(UiTheme.RAISED, 0.5), 10, 4))
		panel.tooltip_text = "not found yet"
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var pet := Pet.new()
	pet.parts = tile.parts
	pet.finish = tile.finish
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet, not got)
	if not got:
		portrait.modulate.a = 0.35
	col.add_child(portrait)
	var name_label := UiTheme.label(tile.name if got else "???", UiTheme.TEXT if got else UiTheme.LOCKED, UiTheme.SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	if got:
		var count := UiTheme.label("×%s" % UiTheme.num(tile.seen), UiTheme.MUTED, UiTheme.SMALL)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(count)
	if got and narrow and str(tile.key) != "":
		_make_wishable(panel, tile)
	return Tilted.new(panel, TILTS[i % TILTS.size()] if got else 0.0)


## A found part's sticker while the jar is out: tap it to wish for it. The wished one wears a jar
## badge and a pink dashed outline.
func _make_wishable(panel: PanelContainer, tile: Dictionary) -> void:
	var key := str(tile.key)
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.gui_input.connect(func(event: InputEvent):
		# on release over it, like a button (dragging off and letting go cancels; the book redraws
		# right after, the sticker with it)
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT \
				and Rect2(Vector2.ZERO, panel.size).has_point(event.position):
			if GameState.set_wish(key):
				var done := bool(Wish.where(GameState.catalog, Wish.sent(GameState.wish, key)).done)
				PetBubble.say_line(self, "wish_done" if done else "wish_pick", { "name": tile.name }))
	if key != str(GameState.wish.on):
		return
	panel.draw.connect(func():
		var r := Rect2(Vector2(-4, -4), panel.size + Vector2(8, 8))
		_dashed_rect(panel, r, UiTheme.PINK)
		var c := Vector2(2, 1)
		panel.draw_circle(c, 12.0, UiTheme.PINK_SEAM)
		panel.draw_circle(c, 10.0, UiTheme.RAISED)
		panel.draw_texture_rect(UiTheme.icon("jar", 16, UiTheme.PINK), Rect2(c - Vector2(8, 8), Vector2(16, 16)), false))


static func _dashed_rect(on: CanvasItem, r: Rect2, color: Color) -> void:
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var length := a.distance_to(b)
		var t := 0.0
		while t < length:
			on.draw_line(a.lerp(b, t / length), a.lerp(b, minf(t + 5.0, length) / length), color, 2.0)
			t += 9.0


func _tile_size() -> Vector2:
	return Vector2(74, 78) if narrow else Vector2(78, 90)


## The pet a part's sticker shows: the showcase pet with just that part swapped in.
static func showcase_pet(key: String) -> Pet:
	var pet := Pet.new()
	pet.parts = SHOWCASE.duplicate()
	var bits := key.split(":")
	if bits.size() == 3 and pet.parts.has(bits[1]):
		pet.parts[bits[1]] = bits[2]
	return pet


## A part's name as the book shows it ("no hat" for no accessory).
static func look_name(key: String) -> String:
	var bits := key.split(":")
	if bits.size() != 3:
		return ""
	if bits[1] == "accessory" and bits[2] == "none":
		return "no hat"
	return str(Catalog.shared().part(bits[1], bits[2]).get("name", bits[2]))


## The page's reward: a dashed gift spot until the page is full, then its sticker, in gold.
func _reward(sticker: Dictionary) -> Control:
	var open := GameState.stickers.has(str(sticker.id))
	var panel := PanelContainer.new()
	panel.custom_minimum_size = _tile_size()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(col)
	if open:
		var sb := UiTheme.sticker(UiTheme.GOLD, 10, UiTheme.PAGE, 4)
		sb.shadow_color = Color(UiTheme.GOLD, 0.3)  # a soft gold glow
		sb.shadow_size = 9
		sb.shadow_offset = Vector2.ZERO
		panel.add_theme_stylebox_override("panel", sb)
		var line := Book.words(Catalog.shared(), sticker)
		panel.tooltip_text = line
		col.add_child(_wrapped(str(sticker.name), UiTheme.GOLD))
		col.add_child(_wrapped(line, UiTheme.MUTED))
		return Tilted.new(panel, 2.0)
	panel.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.GOLD.lerp(UiTheme.LINE, 0.4), UiTheme.DEEP.lerp(UiTheme.RAISED, 0.5), 10, 4))
	var gift := UiTheme.icon_rect("boxes", 18, UiTheme.GOLD)
	gift.size_flags_horizontal = SIZE_SHRINK_CENTER
	gift.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(gift)  # no words: what's in it shows when the page is full (open question for Emilia)
	return panel


static func _wrapped(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color, UiTheme.SMALL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 66
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l
