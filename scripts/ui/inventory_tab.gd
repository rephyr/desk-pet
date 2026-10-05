class_name InventoryTab
extends HBoxContainer
## The workbench's "your pet" page (design/mockups/screens/parts-redo.html, look A): loose parts as
## sticker tiles (filter by slot), each with its knack's doodle and size on your active pet (its
## finish and the part's plushie buttons counted, see Knacks.row) and the kind in a word; under the
## bag your pet's knacks as chips. On the right the sewing table: your pet now and after, the knack
## that leaves (struck out) and the one coming in, how tricky the stitch is (in words, never a
## number), and sew it on (Grafting). Rarer parts slip more often. A part that came off a pet with
## buttons (the plushie machine) keeps them: its sticker shows them.
## Boxes found on trips aren't here: they wait on the home pile and the boxes tab opens them.

const SLOT_FILTERS := ["all", "body", "palette", "pattern", "eyes", "accessory"]
const TILTS := [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0, 2.2, -2.4, 0.8]
## How a stitch feels, by its chance of slipping (up to each number).
const STITCH_WORDS := [[0.06, "an easy stitch"], [0.12, "a simple stitch"], [0.22, "a fiddly stitch"],
	[0.32, "a tricky stitch"], [0.5, "a very tricky stitch"], [1.0, "the trickiest stitch"]]
const SEW_W := 276  # the sewing table's width
const STALE_EVERY := 1.0  # GameState changes often: the page checks at most this often whether its parts changed

var _parts := GridContainer.new()
var _filter := "all"
var _filter_chips := {}
var _dirty := true
var _stale := false  # something changed in GameState: rebuilt only if what the page shows changed
var _stale_at := 0.0
var _shown := ""  # what the page was built from (see _signature)
var _picked := ""  # the bag key ("slot:id", or "slot:id@n" with buttons) of the part on the sewing table
var _strip := PanelContainer.new()  # your pet's knacks
var _strip_title := UiTheme.title("", 15)
var _chips := GridContainer.new()
var _sew_card := PanelContainer.new()
var _sew_body := VBoxContainer.new()
var _rng := RandomNumberGenerator.new()
var _showing_result := false  # the sewing result stays up until you say "lovely!"


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()

	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	add_child(left)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(UiTheme.title("parts", 18))
	for f in SLOT_FILTERS:
		var chip := UiTheme.filter_chip(f, UiTheme.PINK, f == "all")
		chip.toggle_mode = false
		chip.pressed.connect(func():
			_filter = f
			for id in _filter_chips:
				_filter_chips[id].button_pressed = id == f
			_rebuild())
		chip.toggle_mode = true
		chip.button_pressed = f == "all"
		_filter_chips[f] = chip
		head.add_child(chip)
	left.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_parts.columns = 5
	_parts.size_flags_horizontal = SIZE_EXPAND_FILL
	_parts.add_theme_constant_override("h_separation", 10)
	_parts.add_theme_constant_override("v_separation", 12)
	var pad := MarginContainer.new()  # room for the count badges and the picked tile's stitches
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_top", 9)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.add_child(_parts)
	scroll.add_child(pad)
	left.add_child(scroll)

	# your pet's knacks, under the bag
	_strip.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 10))
	var strip_col := VBoxContainer.new()
	strip_col.add_theme_constant_override("separation", 6)
	_strip.add_child(strip_col)
	_strip_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_strip_title.clip_text = true
	strip_col.add_child(_strip_title)
	_chips.columns = 3
	_chips.add_theme_constant_override("h_separation", 8)
	_chips.add_theme_constant_override("v_separation", 5)
	strip_col.add_child(_chips)
	left.add_child(_strip)
	if OS.is_debug_build():
		var give := UiTheme.button("dev: give parts (one of each rarity)", func(): GameState.debug_give_parts())
		give.add_theme_font_size_override("font_size", UiTheme.SMALL)
		give.size_flags_horizontal = SIZE_SHRINK_BEGIN
		left.add_child(give)

	_sew_card.custom_minimum_size = Vector2(SEW_W, 0)
	_sew_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 16))
	_sew_card.draw.connect(func():
		_sew_card.draw_style_box(UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 8, 0), Rect2(Vector2(5, 5), _sew_card.size - Vector2(10, 10))))
	_sew_body.add_theme_constant_override("separation", 8)
	_sew_card.add_child(_sew_body)
	add_child(_sew_card)

	GameState.changed.connect(func(): _stale = true)
	GameState.knacks_changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.collection.pet_changed.connect(func(_p): _stale = true)
	visibility_changed.connect(func():
		_rebuild_if_dirty()
		if is_visible_in_tree():
			speak())


func speak() -> void:
	var parts := 0
	for key in GameState.parts:
		parts += int(GameState.parts[key])
	PetBubble.say_line(self, "bag" if parts > 0 else "bag_empty")


func _rebuild_if_dirty() -> void:
	if not is_visible_in_tree():
		return
	if _stale and not _dirty and _stale_at <= 0.0:
		_stale = false
		_stale_at = STALE_EVERY
		_dirty = _signature() != _shown
	if _dirty:
		_rebuild()


func _process(delta: float) -> void:
	_stale_at -= delta
	_rebuild_if_dirty()


## What the page is built from: the bag, your active pet's looks and finish, and the knack gates.
func _signature() -> String:
	var pet := GameState.collection.active()
	var who := "" if pet == null else "%s|%s|%s|%s" % [pet.uid, pet.parts, pet.finish, pet.buttons]
	return "%s|%s|%d" % [GameState.parts, who, GameState.knack_version]


func _rebuild() -> void:
	_dirty = false
	_shown = _signature()
	# the parts
	UiTheme.clear(_parts)
	var keys: Array = GameState.parts.keys().filter(func(k: String): return _filter == "all" or k.get_slice(":", 0) == _filter)
	keys.sort_custom(func(a, b): return _rank(a) > _rank(b) if _rank(a) != _rank(b) else a < b)
	if not GameState.parts.has(_picked):
		_picked = ""
	if _picked == "" and not keys.is_empty():
		_picked = keys[0]
	for i in keys.size():
		_parts.add_child(_part_tile(keys[i], int(GameState.parts[keys[i]]), i))
	if keys.is_empty():
		var none := UiTheme.label("no parts yet", UiTheme.MUTED, UiTheme.SMALL + 1)
		_parts.add_child(none)
	_show_strip()
	if not _showing_result:
		_show_sewing()


## A bag part's knack as it would be on your active pet (its finish, the part's buttons), {} when
## the part has none that shows.
static func bag_knack(bag_key: String) -> Dictionary:
	var catalog := Catalog.shared()
	if not Knacks.system_open(catalog, GameState.knack_gate):
		return {}
	var bits := Grafting.split_key(bag_key)
	var pet := GameState.collection.active()
	return Knacks.row(catalog, bits[0], bits[1], GameState.knack_gate, pet.finish if pet else "normal", int(bits[2]))


func _part_tile(key: String, count: int, i: int) -> Control:
	var catalog := Catalog.shared()
	var bits := Grafting.split_key(key)
	var part := catalog.part(bits[0], bits[1])
	var color := catalog.tier_color(part.rarity)
	var k := bag_knack(key)
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var sb := UiTheme.sticker(color, 10, UiTheme.RAISED, 4)
	sb.content_margin_top = 6
	sb.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", sb)
	panel.custom_minimum_size = Vector2(84, 0)
	panel.tooltip_text = "%s %s (%s)" % [part.get("name", bits[1]), bits[0], catalog.tier_at(catalog.rank(part.rarity)).name]
	if not k.is_empty():
		panel.tooltip_text += "\n%s: %s" % [k.name, k.text]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(part_preview(bits[0], bits[1]))
	col.add_child(portrait)
	col.add_child(_tile_line(str(part.get("name", bits[1])), UiTheme.TEXT, UiTheme.SMALL))
	if k.is_empty():  # a knack that hasn't opened yet: just the slot
		col.add_child(_tile_line(bits[0], UiTheme.MUTED, UiTheme.SMALL - 1))
	else:
		var n := HBoxContainer.new()
		n.alignment = BoxContainer.ALIGNMENT_CENTER
		n.add_theme_constant_override("separation", 3)
		n.mouse_filter = MOUSE_FILTER_IGNORE
		n.add_child(UiTheme.icon_rect(str(k.icon), 14))
		var size := UiTheme.title("+%d%%" % int(k.n), 14, UiTheme.MINT)
		size.mouse_filter = MOUSE_FILTER_IGNORE
		n.add_child(size)
		col.add_child(n)
		col.add_child(_tile_line(str(k.short), UiTheme.MUTED, UiTheme.SMALL - 1))
	var picked := key == _picked
	panel.draw.connect(func():
		if count > 1:
			var badge := "×%s" % UiTheme.num(count)
			var w := UiTheme.BODY_FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x + 12.0
			var r := Rect2(panel.size.x - w + 6.0, -7.0, w, 18.0)
			panel.draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 9, 2, 0), r)
			panel.draw_string(UiTheme.BODY_FONT, r.position + Vector2(6, 13), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.TEXT)
		if int(bits[2]) > 0:  # its buttons, along the top
			KnackBadge.draw_button_row(panel, int(bits[2]), Vector2(10, 9), 3.0)
		if picked:
			panel.draw_style_box(UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 14, 0), Rect2(Vector2(-5, -5), panel.size + Vector2(10, 10))))
	panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_picked = key
			_rebuild()
			var pet := GameState.collection.active()
			if pet:
				PetBubble.say(self, PetVoice.graft_line(pet, "risk", Grafting.fail_chance(bits[0], bits[1], catalog), _rng, catalog)))
	return Tilted.new(panel, 0.0 if picked else TILTS[i % TILTS.size()])


## A centred one-line label on a tile that trims with "…" instead of growing the tile.
static func _tile_line(text: String, color: Color, size: int) -> Label:
	var l := UiTheme.label(text, color, size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.clip_text = true
	l.custom_minimum_size = Vector2(40, 0)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


# ---- your pet's knacks ------------------------------------------------------------------

## What sewing the picked part on would change: { out: the knack that leaves ({} for none), in: the
## one that comes ({} for none) }; both {} when it can't change anything.
func _swap(pet: Pet) -> Dictionary:
	var none := { "out": {}, "in": {} }
	if pet == null or _picked == "":
		return none
	var bits := Grafting.split_key(_picked)
	if pet.parts.get(bits[0], "") == bits[1]:
		return none
	var catalog := Catalog.shared()
	if not Knacks.system_open(catalog, GameState.knack_gate):
		return none
	var after := Grafting.preview(pet, bits[0], bits[1], bits[2])
	return {
		"out": Knacks.row(catalog, bits[0], str(pet.parts.get(bits[0], "")), GameState.knack_gate, pet.finish, Plushie.buttons(pet, bits[0])),
		"in": Knacks.row(catalog, bits[0], bits[1], GameState.knack_gate, after.finish, Plushie.buttons(after, bits[0])),
	}


func _show_strip() -> void:
	UiTheme.clear(_chips)
	var pet := GameState.collection.active()
	var knacks := GameState.knacks_of(pet)
	var swap := _swap(pet)
	_strip.visible = not knacks.is_empty() or not swap.in.is_empty()
	if not _strip.visible:
		return
	_strip_title.text = "%s's knacks" % pet.display_name(Catalog.shared())
	for k in knacks:
		_chips.add_child(_knack_chip(k, "out" if not swap.out.is_empty() and k.slot == swap.out.slot else ""))
	if not swap.in.is_empty():
		_chips.add_child(_knack_chip(swap.in, "in"))


## A knack as a little pill: its doodle, its size and the kind in a word. `mode`: "out" (it would
## leave: faded and struck out), "in" (it would come: a dashed pink edge) or "". `fit`: as wide as
## its words (else it fills its grid cell and trims them with "…").
func _knack_chip(k: Dictionary, mode := "", fit := false) -> Control:
	var tier := Catalog.shared().tier_color(str(k.tier))
	var p := PanelContainer.new()
	var sb: StyleBox
	if mode == "in":
		sb = UiTheme.stitched(UiTheme.PINK, UiTheme.DEEP, 10, 0)
	else:
		sb = UiTheme.box(UiTheme.DEEP, UiTheme.MUTED_SEAM if mode == "out" else Color(tier, 0.7), 999, 2, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	if not fit:
		p.size_flags_horizontal = SIZE_EXPAND_FILL
		p.custom_minimum_size = Vector2(120, 0)
	p.tooltip_text = "%s: %s" % [k.name, k.text]
	if mode == "out":
		p.modulate.a = 0.6
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	p.add_child(row)
	row.add_child(UiTheme.icon_rect(str(k.icon), 14, UiTheme.MUTED if mode == "out" else UiTheme.TEXT))
	var n := UiTheme.title("+%d%%" % int(k.n), 13, UiTheme.MUTED if mode == "out" else UiTheme.MINT)
	row.add_child(n)
	var word := UiTheme.label(str(k.short), UiTheme.MUTED if mode == "out" else UiTheme.TEXT, UiTheme.SMALL)
	if not fit:
		word.size_flags_horizontal = SIZE_EXPAND_FILL
		word.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		word.clip_text = true
		word.custom_minimum_size = Vector2(30, 0)
	row.add_child(word)
	if mode == "out":
		_strike(n)
		_strike(word)
	return p


## Draws a line through a label's text (a knack that would leave).
static func _strike(l: Label) -> void:
	l.draw.connect(func():
		var font := l.get_theme_font("font")
		var fs := l.get_theme_font_size("font_size")
		var w := minf(font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, l.size.x)
		var y := l.size.y / 2.0 + 1.0
		l.draw_line(Vector2(0, y), Vector2(w, y), UiTheme.MUTED, 1.5))


# ---- the sewing table -----------------------------------------------------------------

func _show_sewing() -> void:
	UiTheme.clear(_sew_body)
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	_sew_body.add_child(UiTheme.title("sew it on?", 18))
	if pet == null or _picked == "":
		return
	var bits := Grafting.split_key(_picked)
	_sew_body.add_child(_muted("onto %s, your active pet" % pet.display_name(catalog)))
	var ba := HBoxContainer.new()
	ba.alignment = BoxContainer.ALIGNMENT_CENTER
	ba.add_theme_constant_override("separation", 6)
	ba.add_child(_framed(pet, "now", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 12, 2, 6)))
	var thread := Control.new()
	thread.custom_minimum_size = Vector2(34, 96)
	thread.draw.connect(func():
		var pts := PackedVector2Array()
		for i in 17:
			var t := i / 16.0
			pts.append(Vector2(4 + t * 26.0, 48 + sin(t * TAU) * 8.0))
		for i in range(0, 16, 2):
			thread.draw_line(pts[i], pts[i + 1], UiTheme.PINK, 2.4)
		thread.draw_line(Vector2(24, 42), Vector2(30, 48), UiTheme.PINK, 2.4)
		thread.draw_line(Vector2(24, 54), Vector2(30, 48), UiTheme.PINK, 2.4))
	ba.add_child(thread)
	var can := Grafting.can_sew(pet, bits[0], bits[1], GameState.parts, bits[2])
	ba.add_child(_framed(Grafting.preview(pet, bits[0], bits[1], bits[2]), "after", UiTheme.stitched(UiTheme.PINK, UiTheme.DEEP, 12, 6)))
	_sew_body.add_child(ba)

	# the knack that leaves and the one that comes
	var swap := _swap(pet)
	if not swap.out.is_empty() or not swap.in.is_empty():
		var rows := VBoxContainer.new()
		rows.add_theme_constant_override("separation", 6)
		if not swap.out.is_empty():
			rows.add_child(_swap_row(swap.out, false))
		if not swap.in.is_empty():
			rows.add_child(_swap_row(swap.in, true))
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 2)
		_sew_body.add_child(gap)
		_sew_body.add_child(rows)

	var part := catalog.part(bits[0], bits[1])
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 12)
	facts.add_theme_constant_override("v_separation", 3)
	var lines := [
		["part", "%s %s" % [part.get("name", bits[1]), bits[0]], catalog.tier_color(part.rarity)],
		["stitch", _stitch_words(Grafting.fail_chance(bits[0], bits[1], catalog)), UiTheme.GOLD],
	]
	if int(bits[2]) > 0:
		lines.append(["buttons", str(bits[2]), UiTheme.PINK])
	for line in lines:
		facts.add_child(UiTheme.label(line[0], UiTheme.MUTED, UiTheme.SMALL + 1))
		facts.add_child(UiTheme.label(line[1], line[2], UiTheme.SMALL + 1))
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 2)
	_sew_body.add_child(gap2)
	_sew_body.add_child(facts)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	_sew_body.add_child(fill)
	var sew := UiTheme.button("sew it on" if can else _why_not_sew(pet, bits[0], bits[1]), _sew.bind(bits[0], bits[1], bits[2]))
	sew.disabled = not can
	_sew_body.add_child(sew)


## A knack on the sewing table: its doodle in a little rarity-edged square, its name and what it
## does. `coming`: the new one (a pink ring); else the one that leaves (faded, dashed, struck out).
func _swap_row(k: Dictionary, coming: bool) -> Control:
	var tier := Catalog.shared().tier_color(str(k.tier))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 9)
	if not coming:
		row.modulate.a = 0.6
	var square := PanelContainer.new()
	square.custom_minimum_size = Vector2(30, 30)
	square.size_flags_vertical = SIZE_SHRINK_CENTER
	var sb: StyleBox = UiTheme.box(UiTheme.DEEP.lerp(tier, 0.12), tier, 8, 2, 0) if coming \
		else UiTheme.stitched(tier, UiTheme.DEEP.lerp(tier, 0.12), 8, 0)
	square.add_theme_stylebox_override("panel", sb)
	var ic := UiTheme.icon_rect(str(k.icon), 18)
	ic.size_flags_horizontal = SIZE_SHRINK_CENTER
	square.add_child(ic)
	if coming:
		square.draw.connect(func():
			square.draw_style_box(UiTheme.box(Color(0, 0, 0, 0), UiTheme.PINK, 11, 2, 0), Rect2(Vector2(-4, -4), square.size + Vector2(8, 8))))
	row.add_child(square)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	var name_l := UiTheme.label(str(k.name), UiTheme.TEXT if coming else UiTheme.MUTED, UiTheme.SMALL + 1)
	var text_l := UiTheme.label(str(k.text), UiTheme.MINT if coming else UiTheme.MUTED, UiTheme.SMALL)
	for l: Label in [name_l, text_l]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.custom_minimum_size = Vector2(60, 0)
		words.add_child(l)
		if not coming:
			_strike(l)
	row.add_child(words)
	return row


## Why a part can't be sewn on right now, as the greyed-out button's text.
static func _why_not_sew(pet: Pet, slot: String, id: String) -> String:
	if pet == null:
		return "pick an active pet first"
	if pet.parts.get(slot, "") == id:
		return "already wearing this one"
	return "none left in your bag"


func _framed(pet: Pet, caption: String, frame: StyleBox) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", frame)
	var portrait := PetPortrait.new(4, true)
	portrait.set_pet(pet)
	panel.add_child(portrait)
	col.add_child(panel)
	var l := UiTheme.label(caption, UiTheme.MUTED, UiTheme.SMALL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(l)
	return col


func _sew(slot: String, part_id: String, buttons := 0) -> void:
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	var result := GameState.sew_part(slot, part_id, buttons)
	if result.is_empty() or pet == null:
		return
	PetBubble.say(self, PetVoice.graft_line(pet, "success" if result.ok else "fail", 0.0, _rng, catalog))
	_showing_result = true
	UiTheme.clear(_sew_body)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	var portrait := PetPortrait.new(6, true)
	portrait.set_pet(GameState.collection.active())
	portrait.size_flags_horizontal = SIZE_SHRINK_CENTER
	portrait.view.squash = 0.7
	col.add_child(portrait)
	var title := UiTheme.title("it held!" if result.ok else "the stitch slipped…", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var name: String = catalog.part(slot, part_id).get("name", part_id)
	var what := _muted("%s has the %s %s now, with a neat little stitch." % [pet.display_name(catalog), name, slot] if result.ok
		else "the %s %s came loose and got lost. %s is just the same." % [name, slot, pet.display_name(catalog)])
	what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(what)
	if result.ok:  # its new knack, as a chip
		var k := Knacks.row(catalog, slot, part_id, GameState.knack_gate, pet.finish, buttons) \
			if Knacks.system_open(catalog, GameState.knack_gate) else {}
		if not k.is_empty():
			var chip := _knack_chip(k, "", true)
			chip.size_flags_horizontal = SIZE_SHRINK_CENTER
			col.add_child(chip)
	var ok := UiTheme.button("lovely!" if result.ok else "oh well", func():
		_showing_result = false
		_dirty = true
		_rebuild_if_dirty())
	ok.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(ok)
	_sew_body.add_child(col)
	_dirty = true  # the bag and the strip catch up; the table keeps the result up


static func _stitch_words(chance: float) -> String:
	for step in STITCH_WORDS:
		if chance <= step[0]:
			return step[1]
	return STITCH_WORDS[-1][1]


func _muted(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.MUTED, UiTheme.SMALL + 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(220, 0)
	return l


## A plain pet wearing just this part (how a part is shown on its own: tiles, the trail card).
static func part_preview(slot: String, id: String) -> Pet:
	var pet := Pet.new()
	for s in Catalog.SLOTS:
		pet.parts[s] = Catalog.shared().default_part(s)
	pet.parts[slot] = id
	return pet


static func _rank(key: String) -> int:
	var bits := Grafting.split_key(key)
	return Catalog.shared().rank(Catalog.shared().part(bits[0], bits[1]).rarity) * 10 + int(bits[2])
