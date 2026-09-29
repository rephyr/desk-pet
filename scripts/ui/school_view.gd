class_name SchoolView
extends HBoxContainer
## The little school (C2 look A, the classroom), the automation tab's school page. Left: the
## classroom, a chalkboard with a teacher and "class 4 +3.2%" (the step this class would give), 24
## desks filling up in the class's rarity mix, and the teachers row (finished classes). Right: the
## side card, every worker's x number, the class's seats, the shelves with 1 / 10 / 100 / all, and
## "ring the bell", which glows once the class is full. You ring it yourself. Rules: School.

const SIDE_WIDTH := 250

var _board_face := PetPortrait.new(2, false)
var _board_class := UiTheme.title("", 22, UiTheme.TEXT)
var _chalk := UiTheme.title("", 20)
var _desks := VBoxContainer.new()
var _teachers := HBoxContainer.new()
var _teachers_line: Control
var _boost := UiTheme.title("", 24, UiTheme.TEXT)
var _class := UiTheme.title("", 14, UiTheme.LILAC)
var _seats := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _meter := UiTheme.bar(UiTheme.PINK)
var _picker := HerdPicker.new()
var _bell: Button
var _dirty := true  # the classroom is built again: the class or your pet changed, or the size
var _time := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_room())
	add_child(_side())
	GameState.school_changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	resized.connect(func(): _dirty = true)


func _room() -> Control:
	var room := PanelContainer.new()
	room.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_bottom = 10
	room.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	room.add_child(col)
	# the chalkboard
	var board := PanelContainer.new()
	var bb := UiTheme.box(UiTheme.DEEP.lerp(UiTheme.LILAC, 0.07), UiTheme.LILAC_SEAM.lerp(UiTheme.GOLD, 0.22), 8, 5, 6)
	bb.content_margin_left = 16
	bb.content_margin_right = 16
	bb.shadow_color = UiTheme.SHADOW
	bb.shadow_size = 7
	bb.shadow_offset = Vector2(0, 5)
	board.add_theme_stylebox_override("panel", bb)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	board.add_child(line)
	_board_face.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(_board_face)
	_board_class.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(_board_class)
	_chalk.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(_chalk)
	col.add_child(board)
	# the desks: 6 x 4
	_desks.size_flags_vertical = SIZE_EXPAND_FILL
	_desks.add_theme_constant_override("separation", 0)
	col.add_child(_desks)
	# the teachers: finished classes, newest first
	_teachers_line = UiTheme.stitch_line()
	col.add_child(_teachers_line)
	_teachers.add_theme_constant_override("separation", 10)
	col.add_child(_teachers)
	return room


func _side() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.clip_contents = true
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	side.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect("school", 22, UiTheme.PINK))
	head.add_child(UiTheme.title("the little school", 18))
	col.add_child(head)
	var boost := PanelContainer.new()
	var bs := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 6)
	bs.content_margin_left = 10
	bs.content_margin_right = 10
	boost.add_theme_stylebox_override("panel", bs)
	var brow := HBoxContainer.new()
	var every := UiTheme.label("every worker", UiTheme.MUTED, UiTheme.SMALL)
	every.size_flags_horizontal = SIZE_EXPAND_FILL
	every.size_flags_vertical = SIZE_SHRINK_CENTER
	brow.add_child(every)
	brow.add_child(_boost)
	boost.add_child(brow)
	col.add_child(boost)
	var crow := HBoxContainer.new()
	_class.size_flags_horizontal = SIZE_EXPAND_FILL
	crow.add_child(_class)
	_seats.size_flags_vertical = SIZE_SHRINK_CENTER
	crow.add_child(_seats)
	col.add_child(crow)
	_meter.max_value = 1.0
	_meter.step = 0.0
	col.add_child(_meter)
	_picker.take.connect(_seat)
	col.add_child(_picker)
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)
	_bell = UiTheme.button("ring the bell", _ring)
	_bell.icon = UiTheme.icon("bell", 16, UiTheme.MUTED)
	_bell.add_theme_constant_override("icon_max_width", 16)
	col.add_child(_bell)
	return side


## What your pet says on this page.
static func line_key() -> String:
	return "school_full" if GameState.class_full() else "school_cheer"


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if _dirty:
		_dirty = false
		_rebuild()
	else:
		_picker.refresh()  # the shelves' counts (cheap: it rebuilds its rows only when a rarity comes or goes)
	# the bell wiggles now and then once the class is full
	if GameState.class_full():
		_bell.pivot_offset = _bell.size / 2.0
		var t := fmod(_time, 1.2) / 1.2
		_bell.rotation = deg_to_rad(-3.0 if t > 0.74 and t < 0.82 else (3.0 if t >= 0.82 and t < 0.9 else 0.0))
	else:
		_bell.rotation = 0.0


func _rebuild() -> void:
	var catalog := GameState.catalog
	var school: Dictionary = GameState.school
	var number := School.class_number(school)
	var need := School.class_size(catalog, number)
	var sat := School.seated(school)
	var classes: Array = school.get("classes", [])
	# the board: the newest teacher at the front (your pet, before there are any)
	var teacher: Pet = null
	if not classes.is_empty() and not classes[-1].faces.is_empty():
		teacher = Herd.stand_in(catalog, str(classes[-1].faces[0]))
	_board_face.set_pet(teacher if teacher else GameState.collection.active())
	_board_class.text = "class %d" % (number + 1)
	_chalk.text = "+%.1f%%" % School.step(catalog, school.seated) if sat > 0 else ""
	# the desks, filled in proportion to the class
	UiTheme.clear(_desks)
	var desks := int(catalog.school.get("desks", 24))
	var filled := floori(minf(1.0, float(sat) / need) * desks)
	if sat > 0:
		filled = maxi(filled, 1)
	var keys := School.desk_keys(catalog, school.seated, filled)
	var per_row := 6
	var row: HBoxContainer
	for i in desks:
		if i % per_row == 0:
			row = HBoxContainer.new()
			row.size_flags_vertical = SIZE_EXPAND_FILL
			row.add_theme_constant_override("separation", 6)
			_desks.add_child(row)
		var face: Pet = null
		if i < keys.size():
			face = Herd.stand_in(catalog, GameState.school_face(keys[i], GameState.DESK_FACES + i))
		row.add_child(Desk.new(face))
	# the teachers row
	UiTheme.clear(_teachers)
	_teachers_line.visible = not classes.is_empty()
	_teachers.visible = not classes.is_empty()
	if not classes.is_empty():
		_teachers.add_child(UiTheme.title("teachers", 13, UiTheme.LILAC))
		var shown := int(catalog.school.get("teachers_shown", 4))
		var room := size.x - SIDE_WIDTH - get_theme_constant("separation") - 32.0  # the classroom's inside
		var used: float = (_teachers.get_child(0) as Control).get_combined_minimum_size().x
		for i in range(classes.size() - 1, maxi(-1, classes.size() - 1 - shown), -1):
			var group := _group(classes[i], i == classes.size() - 1)
			used += _teachers.get_theme_constant("separation") + group.get_combined_minimum_size().x
			if used > room and _teachers.get_child_count() > 1:
				group.free()
				break  # only as many as fit (the newest first)
			_teachers.add_child(group)
	# the side card
	_boost.text = "x%.2f" % GameState.school_boost()
	_class.text = "class %d" % (number + 1)
	_seats.text = "%s of %s" % [UiTheme.num(sat), UiTheme.num(need)]
	_meter.value = minf(1.0, float(sat) / need)
	_picker.cap = School.seats_left(catalog, school)
	_picker.refresh()
	var ready := GameState.class_full()
	_bell.disabled = not ready
	_bell.icon = UiTheme.icon("bell", 16, UiTheme.PINK if ready else UiTheme.MUTED)
	if ready:
		var glow := UiTheme.box(UiTheme.DEEP.lerp(UiTheme.PINK_PRESSED, 0.5), UiTheme.PINK, 8, 2, 6)
		glow.shadow_color = Color(UiTheme.PINK, 0.4)
		glow.shadow_size = 10
		for state in ["normal", "hover", "pressed"]:
			_bell.add_theme_stylebox_override(state, glow)
		_bell.add_theme_color_override("font_color", UiTheme.PINK)
		_bell.add_theme_color_override("font_hover_color", UiTheme.TEXT)
	else:
		for state in ["normal", "hover", "pressed"]:
			_bell.remove_theme_stylebox_override(state)
		_bell.remove_theme_color_override("font_color")
		_bell.remove_theme_color_override("font_hover_color")


## A finished class in the teachers row: three of its faces, how many, its step.
func _group(c: Dictionary, fresh: bool) -> Control:
	var pill := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if fresh else UiTheme.LINE, 999, 2, 3)
	sb.content_margin_left = 6
	sb.content_margin_right = 9
	pill.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	pill.add_child(row)
	var crowd := HBoxContainer.new()
	crowd.add_theme_constant_override("separation", -5)
	for uid in c.get("faces", []):
		var face := PetPortrait.new(1, false)
		face.set_pet(Herd.stand_in(GameState.catalog, str(uid)))
		crowd.add_child(face)
	row.add_child(crowd)
	var n := UiTheme.title(UiTheme.num(int(c.get("size", 0))), 12, UiTheme.TEXT)
	n.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(n)
	var step := UiTheme.label("+%.1f%%" % float(c.get("step", 0.0)), UiTheme.PINK, UiTheme.SMALL - 1)
	step.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(step)
	return pill


func _seat(rarity: String, n: int) -> void:
	var sat := GameState.seat_in_school(rarity, n)
	if sat <= 0:
		return
	PetBubble.say_line(self, line_key())


func _ring() -> void:
	var at := _bell.get_global_rect().get_center()
	if not GameState.ring_bell():
		return
	Sfx.play(self, Sfx.sound("machine", "jackpot"), -3.0)
	PetBubble.say_line(self, "school_bell")
	_confetti(at)


## A little burst of paper confetti from the bell.
func _confetti(at: Vector2) -> void:
	var colors := [UiTheme.PINK, UiTheme.LILAC, UiTheme.MINT, UiTheme.GOLD, UiTheme.CYAN]
	for i in 18:
		var bit := ColorRect.new()
		bit.color = colors[i % colors.size()]
		bit.size = Vector2(6, 6)
		bit.top_level = true
		bit.z_index = 20
		bit.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(bit)
		bit.global_position = at
		var to := at + Vector2(randf_range(-120, 120), randf_range(-150, -20))
		var t := bit.create_tween().set_parallel()
		t.tween_property(bit, "global_position", to, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(bit, "rotation", randf_range(2.0, 5.0), 1.1)
		t.tween_property(bit, "modulate:a", 0.0, 1.1).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(bit.queue_free)


## One desk, drawn, with a pet sitting behind it (or empty): the desk top is drawn over the pet.
class Desk extends Control:
	var _face: PetPortrait
	var _top := Control.new()

	func _init(pet: Pet) -> void:
		size_flags_horizontal = SIZE_EXPAND_FILL
		size_flags_vertical = SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(50, 44)
		mouse_filter = MOUSE_FILTER_IGNORE
		if pet:
			_face = PetPortrait.new(2, false)
			_face.set_pet(pet)
			_face.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(_face)
		_top.mouse_filter = MOUSE_FILTER_IGNORE
		_top.set_anchors_preset(PRESET_FULL_RECT)
		_top.draw.connect(_draw_desk)
		add_child(_top)
		resized.connect(_place)

	func _place() -> void:
		if _face:
			# sitting behind the desk, peeking over its top
			_face.position = Vector2(size.x / 2.0 - _face.size.x / 2.0, size.y - 20.0 - _face.size.y + 12.0)
		_top.queue_redraw()

	func _draw_desk() -> void:
		var w := minf(62.0, size.x)
		var x := size.x / 2.0 - w / 2.0
		var top := size.y - 28.0
		var s := w / 62.0
		var wood := UiTheme.RAISED.lerp(UiTheme.GOLD, 0.16)
		var edge := UiTheme.LILAC_SEAM
		var slab := PackedVector2Array([Vector2(x + 4 * s, top + 8), Vector2(x + 58 * s, top + 8), Vector2(x + 56 * s, top + 14), Vector2(x + 6 * s, top + 14)])
		_top.draw_colored_polygon(slab, wood)
		slab.append(slab[0])
		_top.draw_polyline(slab, edge, 2.2, true)
		_top.draw_line(Vector2(x + 10 * s, top + 14), Vector2(x + 9 * s, top + 27), edge, 2.4, true)
		_top.draw_line(Vector2(x + 52 * s, top + 14), Vector2(x + 53 * s, top + 27), edge, 2.4, true)
