class_name Postcard
extends Control
## What a trip brought home, as a postcard from the place (shown after "welcome back"). Left: a
## photo of the pets who came home, with a gap where one stayed, and a few notes on what happened.
## Right: a stamp of the place, what they brought back stuck on like stickers, and any new place
## they spotted. Signed by whoever came home. The data comes from GameState.collect_run().

signal closed

const MOST_IN_PHOTO := 5
const MOST_PARTS := 4
const MOST_NOTES := 4
const PART_TILTS := [-4.0, 3.0, -2.0, 4.0]

var _card := PanelContainer.new()
var _tilted := Tilted.new(_card, -1.5)
var _left := VBoxContainer.new()
var _right := VBoxContainer.new()
var _love := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL + 1)
var _doodle := ""
var _place := ""
var coins_why := {}  # the trip coins' "why so much?" (see Boosts.why)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP  # the map under it doesn't take clicks
	_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 18))
	_tilted.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_tilted.offset_left = 18
	_tilted.offset_right = -18
	_tilted.offset_top = 22
	_tilted.offset_bottom = -70
	add_child(_tilted)
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 16)
	_card.add_child(halves)
	for half in [_left, _right]:
		half.size_flags_horizontal = SIZE_EXPAND_FILL
		half.size_flags_stretch_ratio = 1.0
		half.add_theme_constant_override("separation", 8)
	halves.add_child(_left)
	var seam := Control.new()
	seam.custom_minimum_size = Vector2(2, 0)
	seam.draw.connect(func():
		for y in range(0, int(seam.size.y), 11):
			seam.draw_line(Vector2(1, y), Vector2(1, minf(y + 6, seam.size.y)), UiTheme.LILAC_SEAM, 2.0))
	halves.add_child(seam)
	halves.add_child(_right)

	var foot := HBoxContainer.new()
	foot.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	foot.offset_left = 18
	foot.offset_right = -18
	foot.offset_top = -52
	foot.offset_bottom = -16
	_love.size_flags_horizontal = SIZE_EXPAND_FILL
	_love.size_flags_vertical = SIZE_SHRINK_CENTER
	foot.add_child(_love)
	var lovely := UiTheme.button("lovely", func(): closed.emit())
	lovely.icon = UiTheme.icon("heart", 14)
	lovely.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lovely.add_theme_constant_override("icon_max_width", 14)
	lovely.custom_minimum_size = Vector2(130, 0)
	foot.add_child(lovely)
	add_child(foot)


## Fills the postcard with one trip (the Dictionary from GameState.collect_run()).
func show_trip(trip: Dictionary) -> void:
	_place = str(trip.place)
	coins_why = {}
	_doodle = str(trip.doodle)
	UiTheme.clear(_left)
	UiTheme.clear(_right)
	var home: Array[String] = []
	for shot in trip.photo:
		if shot.home:
			home.append(shot.pet.display_name(Catalog.shared()))

	# left: greetings, the photo, the notes
	var greetings := VBoxContainer.new()
	greetings.add_theme_constant_override("separation", 0)
	greetings.add_child(UiTheme.label("greetings from", UiTheme.MUTED))
	greetings.add_child(UiTheme.title(_place + "!", 22))
	_left.add_child(greetings)
	var photo := _photo(trip.photo, _names(home) if not home.is_empty() else _place)
	var tilt := Tilted.new(photo, 2.5)
	tilt.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_left.add_child(tilt)
	var notes: Array = trip.notes.slice(maxi(0, trip.notes.size() - MOST_NOTES))
	for note in notes:
		var l := UiTheme.label(note.text, UiTheme.LILAC if note.stayed else UiTheme.TEXT, UiTheme.SMALL + 1)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left.add_child(l)

	# right: the stamp, what came back, new places
	var corner := Control.new()
	corner.custom_minimum_size = Vector2(0, 74)
	corner.draw.connect(_draw_stamp.bind(corner))
	_right.add_child(corner)
	_right.add_child(UiTheme.label("we brought back", UiTheme.MUTED, UiTheme.SMALL + 1))
	coins_why = trip.get("coins_why", {})
	if not coins_why.get("lines", []).is_empty():
		var room := Control.new()  # room for the "why so much?" tape over the coins
		room.custom_minimum_size.y = 2  # plus the column's gap: 10 px
		_right.add_child(room)
	var tags := HFlowContainer.new()
	tags.add_theme_constant_override("h_separation", 6)
	tags.add_theme_constant_override("v_separation", 6)
	_right.add_child(tags)
	var loot: Dictionary = trip.loot
	var coins := Rewards.total(loot, "coins")
	if coins > 0:
		# "why so much?" on the coins, once something multiplied them (the tote, badges, boosts)
		var why := coins_why
		tags.add_child(WhyTape.wrap(UiTheme.chip("coin", str(coins), UiTheme.CYAN), func(): return why))
	if int(trip.xp) > 0:
		tags.add_child(UiTheme.chip("xp", str(trip.xp), UiTheme.GOLD))
	for key: String in loot:
		if key.begins_with("box:"):
			var n := int(loot[key])
			var box_name := str(Catalog.shared().box(key.substr(4)).get("name", "box"))
			tags.add_child(UiTheme.tag("a %s" % box_name if n == 1 else "%d %ses" % [n, box_name], UiTheme.LILAC))
	for key: String in loot:
		if key.begins_with("bit:"):
			tags.add_child(UiTheme.chip("bit_" + key.substr(4), "%d %s" % [int(loot[key]), MachineTab.bit_name(key.substr(4), int(loot[key]))], UiTheme.TEXT))
	for find_name in trip.finds:
		tags.add_child(UiTheme.tag(find_name, UiTheme.GOLD))
	var heard := Rewards.total(loot, "rumour")
	if heard > 0:
		tags.add_child(UiTheme.tag("heard a rumour" if heard == 1 else "heard %d rumours" % heard, UiTheme.LILAC))
	var parts: Array[String] = []
	for key: String in loot:
		if key.begins_with("part:"):
			for i in int(loot[key]):
				parts.append(key)
	if not parts.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for i in mini(parts.size(), MOST_PARTS):
			row.add_child(Tilted.new(_part_sticker(parts[i]), PART_TILTS[i % PART_TILTS.size()]))
		if parts.size() > MOST_PARTS:
			var more := UiTheme.label("+%d more" % (parts.size() - MOST_PARTS), UiTheme.MUTED, UiTheme.SMALL)
			more.size_flags_vertical = SIZE_SHRINK_CENTER
			row.add_child(more)
		_right.add_child(row)
	if tags.get_child_count() == 0 and parts.is_empty():
		_right.add_child(UiTheme.label("nothing this time", UiTheme.MUTED, UiTheme.SMALL + 1))
	var grow := Control.new()
	grow.size_flags_vertical = SIZE_EXPAND_FILL
	_right.add_child(grow)
	for place in trip.spotted:
		_right.add_child(_spotted(place))

	_love.text = "love, %s" % (_names(home) if not home.is_empty() else _place)
	# it rises in, like it was just pulled out of the letterbox
	modulate.a = 0.0
	_tilted.offset_top = 46
	_tilted.offset_bottom = -46
	var t := create_tween().set_parallel()
	t.tween_property(self, "modulate:a", 1.0, 0.25)
	for side in [["offset_top", 22], ["offset_bottom", -70]]:
		t.tween_property(_tilted, side[0], side[1], 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))


## "peach cat", "peach cat and sky bunny", "a, b and c", "a, b and 3 others".
static func _names(names: Array[String]) -> String:
	if names.size() <= 1:
		return "".join(names)
	if names.size() > 3:
		return "%s, %s and %d others" % [names[0], names[1], names.size() - 2]
	return "%s and %s" % [", ".join(names.slice(0, -1)), names[-1]]


## A light polaroid: the pets who came home on a strip of grass, a gap where one stayed.
func _photo(shots: Array, caption: String) -> Control:
	var frame := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.TEXT, UiTheme.TEXT, 4, 0, 8)
	sb.content_margin_bottom = 24
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 4)
	frame.add_theme_stylebox_override("panel", sb)
	var shot := HBoxContainer.new()
	shot.alignment = BoxContainer.ALIGNMENT_CENTER
	shot.add_theme_constant_override("separation", 6)
	shot.custom_minimum_size = Vector2(184, 92)
	var pixel := 3 if shots.size() <= 3 else 2
	for i in mini(shots.size(), MOST_IN_PHOTO):
		if shots[i].home:
			var portrait := PetPortrait.new(pixel)
			portrait.set_pet(shots[i].pet)
			portrait.size_flags_vertical = SIZE_SHRINK_END
			shot.add_child(portrait)
		else:
			var gap := Control.new()
			gap.custom_minimum_size = PetView.size_for(pixel)
			shot.add_child(gap)
	shot.draw.connect(func():
		var grass := shot.size.y * 0.66
		shot.draw_rect(Rect2(0, 0, shot.size.x, grass), UiTheme.DEEP)
		shot.draw_rect(Rect2(0, grass, shot.size.x, shot.size.y - grass), UiTheme.DEEP.lerp(UiTheme.MINT, 0.3)))
	frame.add_child(shot)
	frame.draw.connect(func():
		var w := UiTheme.DISPLAY_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		frame.draw_string(UiTheme.DISPLAY_FONT, Vector2((frame.size.x - w) / 2.0, frame.size.y - 8.0), caption,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DEEP))
	return frame


## A part as a little sticker in its rarity colour: the plain pet wearing it, its name, its rarity.
func _part_sticker(key: String) -> Control:
	var catalog := Catalog.shared()
	var bits := key.split(":")  # part, slot, id
	var part := catalog.part(bits[1], bits[2])
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(catalog.tier_color(part.rarity), 10, UiTheme.RAISED, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var portrait := PetPortrait.new(2, false)
	portrait.set_pet(InventoryTab.part_preview(bits[1], bits[2]))
	col.add_child(portrait)
	for l in [UiTheme.label(part.get("name", bits[2]), UiTheme.TEXT, UiTheme.SMALL), UiTheme.tier_label(part.rarity)]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	return panel


## "spotted a new place!" with its doodle, stitched on in gold.
func _spotted(place: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.GOLD, UiTheme.RAISED, 10, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var doodle := Control.new()
	doodle.custom_minimum_size = Vector2(36, 34)
	doodle.draw.connect(func(): Crayon.doodle(doodle, str(place.doodle), doodle.size / 2.0, 0.55, UiTheme.GOLD, 7))
	row.add_child(doodle)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.add_child(UiTheme.label("spotted a new place!", UiTheme.GOLD, UiTheme.SMALL + 1))
	words.add_child(UiTheme.title(str(place.name), 15, UiTheme.GOLD))
	row.add_child(words)
	return panel


## The stamp in the top right corner (the place's doodle in a perforated frame) and a postmark.
func _draw_stamp(corner: Control) -> void:
	var stamp := Rect2(corner.size.x - 62.0, 2.0, 58.0, 66.0)
	corner.draw_set_transform(stamp.get_center(), deg_to_rad(4.0))
	var r := Rect2(-stamp.size / 2.0, stamp.size)
	corner.draw_rect(r, UiTheme.DEEP)
	for i in 4:  # perforated edges: dots around the frame
		var from: Vector2 = [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)][i]
		var to: Vector2 = [r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y), r.position][i]
		var steps := int(from.distance_to(to) / 6.0)
		for j in steps:
			corner.draw_circle(from.lerp(to, float(j) / steps), 1.6, UiTheme.PINK_SEAM)
	Crayon.doodle(corner, _doodle, Vector2(0, 2), 0.7, Crayon.doodle_color(_doodle), 3)
	corner.draw_set_transform(Vector2.ZERO)
	# the postmark, a faint ring with the place's name, over the stamp's edge
	var mark := Vector2(stamp.position.x - 30.0, 40.0)
	var ink := Color(UiTheme.LILAC, 0.5)
	corner.draw_arc(mark, 31.0, 0.0, TAU, 32, ink, 2.0, true)
	corner.draw_set_transform(mark, deg_to_rad(-12.0))
	var font := UiTheme.BODY_FONT
	# the name one word per line, so it fits in the ring
	var lines := Array(_place.split(" ")) + ["♪"]
	var top := -6.0 * (lines.size() - 1) + 4.0
	for i in lines.size():
		var w := font.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		corner.draw_string(font, Vector2(-w / 2.0, top + i * 12.0), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink)
	corner.draw_set_transform(Vector2.ZERO)
