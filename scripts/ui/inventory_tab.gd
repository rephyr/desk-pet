class_name InventoryTab
extends HBoxContainer
## Your bag: boxes pets found on trips, and loose parts as stickers (filter by slot). On the right
## the sewing table: pick a part to see your active pet before and after, how tricky the stitch
## is (in words, never a number), and sew it on (Grafting). Rarer parts slip more often.

signal open_box_requested(box_id: String)

const SLOT_FILTERS := ["all", "body", "palette", "pattern", "eyes", "accessory"]
const TILTS := [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0, 2.2, -2.4, 0.8]
## How a stitch feels, by its chance of slipping (up to each number).
const STITCH_WORDS := [[0.06, "an easy stitch"], [0.12, "a simple stitch"], [0.22, "a fiddly stitch"],
	[0.32, "a tricky stitch"], [0.5, "a very tricky stitch"], [1.0, "the trickiest stitch"]]

var _boxes_row := HBoxContainer.new()
var _parts := GridContainer.new()
var _filter := "all"
var _filter_chips := {}
var _dirty := true
var _picked := ""  # "slot:id" of the part on the sewing table
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
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var boxes := PanelContainer.new()
	boxes.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 10))
	_boxes_row.add_theme_constant_override("separation", 14)
	boxes.add_child(_boxes_row)
	left.add_child(boxes)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
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
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_child(_parts)
	scroll.add_child(pad)
	left.add_child(scroll)
	if OS.is_debug_build():
		var give := UiTheme.button("dev: give parts (one of each rarity)", func(): GameState.debug_give_parts())
		give.add_theme_font_size_override("font_size", UiTheme.SMALL)
		give.size_flags_horizontal = SIZE_SHRINK_BEGIN
		left.add_child(give)

	_sew_card.custom_minimum_size = Vector2(264, 0)
	_sew_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 16))
	_sew_card.draw.connect(func():
		_sew_card.draw_style_box(UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 8, 0), Rect2(Vector2(5, 5), _sew_card.size - Vector2(10, 10))))
	_sew_body.add_theme_constant_override("separation", 8)
	_sew_card.add_child(_sew_body)
	add_child(_sew_card)

	GameState.changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
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
	if _dirty and is_visible_in_tree():
		_rebuild()


func _process(_delta: float) -> void:
	_rebuild_if_dirty()


func _rebuild() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	# boxes found on trips
	UiTheme.clear(_boxes_row)
	_boxes_row.add_child(UiTheme.title("boxes", 18))
	var any_box := false
	for box in catalog.boxes:
		var owned := GameState.in_bag(box.id)
		if owned <= 0:
			continue
		any_box = true
		var pack := PackArt.rect(box.get("art", {}), 26, -5.0)
		pack.tooltip_text = "%d %s" % [owned, box.name]
		_boxes_row.add_child(pack)
		var line := UiTheme.label("%d %s" % [owned, box.name], UiTheme.MUTED, UiTheme.SMALL + 1)
		line.size_flags_vertical = SIZE_SHRINK_CENTER
		_boxes_row.add_child(line)
		var open := UiTheme.button("open", func(): open_box_requested.emit(box.id))
		open.size_flags_vertical = SIZE_SHRINK_CENTER
		_boxes_row.add_child(open)
	if not any_box:
		var none := UiTheme.label("no boxes yet. pets find some on trips", UiTheme.MUTED, UiTheme.SMALL + 1)
		none.size_flags_vertical = SIZE_SHRINK_CENTER
		_boxes_row.add_child(none)
	# anything else trips bring back that nothing uses yet
	for key: String in GameState.items:
		_boxes_row.add_child(UiTheme.label("%d %s" % [GameState.items[key], key.replace(":", " ").strip_edges()], UiTheme.TEXT, UiTheme.SMALL))

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
		var none := UiTheme.label("no parts yet. pets sometimes find them on trips", UiTheme.MUTED, UiTheme.SMALL + 1)
		_parts.add_child(none)
	if not _showing_result:
		_show_sewing()


func _part_tile(key: String, count: int, i: int) -> Control:
	var catalog := Catalog.shared()
	var bits := key.split(":")
	var part := catalog.part(bits[0], bits[1])
	var color := catalog.tier_color(part.rarity)
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(color, 10, UiTheme.RAISED, 6))
	panel.custom_minimum_size = Vector2(84, 0)
	panel.tooltip_text = "%s %s (%s)" % [part.get("name", bits[1]), bits[0], catalog.tier_at(catalog.rank(part.rarity)).name]
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(part_preview(bits[0], bits[1]))
	col.add_child(portrait)
	for line in [[part.get("name", bits[1]), UiTheme.TEXT], [bits[0], UiTheme.MUTED]]:
		var l := UiTheme.label(line[0], line[1], UiTheme.SMALL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(l)
	var picked := key == _picked
	panel.draw.connect(func():
		if count > 1:
			var badge := "×%d" % count
			var w := UiTheme.BODY_FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x + 12.0
			var r := Rect2(panel.size.x - w + 4.0, -7.0, w, 18.0)
			panel.draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 9, 2, 0), r)
			panel.draw_string(UiTheme.BODY_FONT, r.position + Vector2(6, 13), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.TEXT)
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


# ---- the sewing table -----------------------------------------------------------------

func _show_sewing() -> void:
	UiTheme.clear(_sew_body)
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	_sew_body.add_child(UiTheme.title("sew it on?", 18))
	if pet == null or _picked == "":
		_sew_body.add_child(_muted("pick a part to try it on your active pet"))
		return
	var bits := _picked.split(":")
	_sew_body.add_child(_muted("onto %s, your active pet" % pet.display_name(catalog)))
	var ba := HBoxContainer.new()
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
	var can := Grafting.can_sew(pet, bits[0], bits[1], GameState.parts)
	ba.add_child(_framed(Grafting.preview(pet, bits[0], bits[1]), "after", UiTheme.stitched(UiTheme.PINK, UiTheme.DEEP, 12, 6)))
	_sew_body.add_child(ba)

	var part := catalog.part(bits[0], bits[1])
	var facts := GridContainer.new()
	facts.columns = 2
	facts.add_theme_constant_override("h_separation", 12)
	facts.add_theme_constant_override("v_separation", 3)
	var rows := [
		["part", "%s %s" % [part.get("name", bits[1]), bits[0]], catalog.tier_color(part.rarity)],
		["stitch", _stitch_words(Grafting.fail_chance(bits[0], bits[1], catalog)), UiTheme.GOLD],
		["mood", "changes how it feels" if bits[0] == "eyes" else "no change", UiTheme.MINT],
	]
	for row in rows:
		facts.add_child(UiTheme.label(row[0], UiTheme.MUTED, UiTheme.SMALL + 1))
		facts.add_child(UiTheme.label(row[1], row[2], UiTheme.SMALL + 1))
	_sew_body.add_child(facts)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	_sew_body.add_child(fill)
	var sew := UiTheme.button("sew it on" if can else _why_not_sew(pet, bits[0], bits[1]), _sew.bind(bits[0], bits[1]))
	sew.disabled = not can
	_sew_body.add_child(sew)
	var fine := _muted("if the stitch holds, the old %s goes back in your bag" % bits[0])
	fine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sew_body.add_child(fine)


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


func _sew(slot: String, part_id: String) -> void:
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	var result := GameState.sew_part(slot, part_id)
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
	var ok := UiTheme.button("lovely!" if result.ok else "oh well", func():
		_showing_result = false
		_dirty = true
		_rebuild_if_dirty())
	ok.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(ok)
	_sew_body.add_child(col)


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
	var bits := key.split(":")
	return Catalog.shared().rank(Catalog.shared().part(bits[0], bits[1]).rarity)
