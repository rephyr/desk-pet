class_name ErrandsTab
extends HBoxContainer
## Errands: a corkboard of jobs (data/errands.json, Jobs), each a sticky note with its meter, what
## it brings and its crew. On the right a shoebox of resting pets. Tap a resting pet, then a note,
## to put it to work; tap a pet on a note to let it rest. A crew can be a couple of pets or
## thousands: up to POLAROIDS each pet gets its own polaroid, past that the note shows a pile, the
## count and a little crowd, and + and − move 1, 10, 100 or all at once.
## Design: design/mockups/screens/errands.html (the corkboard).

const POLAROIDS := 6  # up to this many pets on a job, each gets its own polaroid
const RESTING_POLAROIDS := 9  # the same for the resting pets in the shoebox
const STEPS_AFTER := 12  # the 1 / 10 / 100 / all picker shows once you have more pets than this
const STEPS := [1, 10, 100, -1]  # -1: all
const STREAM_AFTER := 0.25  # fills a second: faster than this, a meter is a steady stream
const TILTS := [-1.5, 1.2, 2.0, -1.0, 1.6, -2.0]
const NOTE_WIDTH := 150  # the narrowest a note gets; fewer columns when the board is narrower
const PHOTO_TILTS := [-4.0, 3.0, -2.0, 5.0, -3.0, 2.0, 4.0, -5.0, 1.0]

var _notes := GridContainer.new()
var _steps_row := HBoxContainer.new()
var _subtitle: Label
var _box := VBoxContainer.new()
var _meters := {}  # job id -> Meter
var _step := 1
var _picked := ""  # uid of a resting pet waiting to be put on a job
var _dirty := true
var _resting: Array[Pet] = []  # worked out once per rebuild
var _away_count := -1  # pets on adventures at the last rebuild
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()

	# the corkboard
	var board := PanelContainer.new()
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	var cork := UiTheme.box(UiTheme.PAPER.lerp(UiTheme.GOLD, 0.04), UiTheme.LINE, 14, 2, 14)
	cork.content_margin_left = 16
	cork.content_margin_right = 16
	board.add_theme_stylebox_override("panel", cork)
	board.draw.connect(func(): _draw_cork(board))
	add_child(board)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	board.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(UiTheme.title("errands", 20))
	_subtitle = _shrinkable(UiTheme.label("pets work here while they rest. nobody wanders off.", UiTheme.MUTED, UiTheme.SMALL + 1))
	_subtitle.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_subtitle)
	_steps_row.add_theme_constant_override("separation", 6)
	var move := UiTheme.label("move", UiTheme.MUTED, UiTheme.SMALL)
	move.size_flags_vertical = SIZE_SHRINK_CENTER
	_steps_row.add_child(move)
	_steps_row.add_child(UiTheme.segmented(STEPS.map(func(n): return "all" if n < 0 else str(n)), 0, func(i):
		_step = STEPS[i]
		_dirty = true))
	head.add_child(_steps_row)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()  # room for the tape and the tilt
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_left", 4)
	pad.add_theme_constant_override("margin_right", 4)
	pad.add_theme_constant_override("margin_bottom", 8)
	_notes.columns = 3
	_notes.size_flags_horizontal = SIZE_EXPAND_FILL
	_notes.add_theme_constant_override("h_separation", 16)
	_notes.add_theme_constant_override("v_separation", 22)
	pad.add_child(_notes)
	scroll.add_child(pad)
	col.add_child(scroll)
	# as many columns of notes as fit, so the board never pushes past the window
	scroll.resized.connect(func():
		var fit := clampi(int((scroll.size.x - 8.0 + 16.0) / (NOTE_WIDTH + 16.0)), 1, 3)
		if fit != _notes.columns:
			_notes.columns = fit)

	# the shoebox of resting pets
	var shoebox := PanelContainer.new()
	shoebox.custom_minimum_size = Vector2(196, 0)
	shoebox.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	_box.add_theme_constant_override("separation", 10)
	shoebox.add_child(_box)
	add_child(shoebox)

	GameState.jobs_changed.connect(func(): _dirty = true)
	GameState.adventures_changed.connect(func():
		if GameState.away().size() != _away_count:
			_dirty = true)
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	GameState.collection.pets_removed.connect(func(_u): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.job_paid.connect(_paid)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_rebuild()
			speak()
		elif not GameState.jobs_away.is_empty():
			GameState.jobs_away = {}  # the "while you were away" note was seen
			_dirty = true)


func speak() -> void:
	var resting := GameState.resting_pets().size()
	if GameState.sendable_pets().is_empty():
		PetBubble.say_line(self, "errands_nobody")
	elif resting > 0:
		PetBubble.say_line(self, "errands_resting", { "count": ExpandedView._thousands(resting) })
	else:
		PetBubble.say_line(self, "errands")


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _dirty:
		_rebuild()
	for job_id in _meters:
		_meters[job_id].fill = GameState.job_fill_now(job_id)


# ---- building it ----------------------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	_meters.clear()
	_resting = GameState.resting_pets()
	_away_count = GameState.away().size()
	var many := GameState.sendable_pets().size() > STEPS_AFTER
	_steps_row.visible = many
	if not many:
		_step = 1
	if _picked != "" and not _resting.any(func(p): return p.uid == _picked):
		_picked = ""
	UiTheme.clear(_notes)
	var catalog := Catalog.shared()
	var notes: Array[Control] = []
	for job in catalog.jobs:
		notes.append(_job_note(job))
	var coming: Dictionary = catalog.errands.get("coming", {})
	if not coming.is_empty():
		notes.append(_coming_note(coming))
	for i in notes.size():
		var tilted := Tilted.new(notes[i], TILTS[i % TILTS.size()])
		tilted.size_flags_horizontal = SIZE_EXPAND_FILL  # the notes share the board's width
		_notes.add_child(tilted)
	_rebuild_box()


func _job_note(job: Dictionary) -> Control:
	var color := _color(job)
	var crew := GameState.job_crew(job.id)
	var rate := GameState.job_rate(job.id)
	var panel := _note_panel(color)
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND if _picked != "" else CURSOR_ARROW
	panel.gui_input.connect(func(e: InputEvent):
		if _clicked(e) and _picked != "":
			_put_on(job, 1, [_picked]))
	var col := _column(panel, 8)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(str(job.doodle), 34, color))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.add_child(UiTheme.title(job.name, 17, color))
	names.add_child(UiTheme.label("brings " + str(job.brings), UiTheme.MUTED, UiTheme.SMALL))
	head.add_child(names)
	col.add_child(head)
	col.add_child(_wrapped(str(job.does), UiTheme.MUTED))

	var meter := Meter.new()
	meter.color = color
	meter.stream = rate > STREAM_AFTER
	_meters[job.id] = meter
	col.add_child(meter)
	if meter.stream:
		col.add_child(_shrinkable(UiTheme.label(_per_minute(job, rate), color, UiTheme.SMALL)))
	else:
		col.add_child(_row(_pay_words(job, crew.size()), _every(rate), UiTheme.MUTED))
	if crew.size() <= POLAROIDS:
		col.add_child(_row("crew of %d" % crew.size(), "%.1fx" % (rate * float(job.seconds)) if not crew.is_empty() else "stopped", color))
		col.add_child(_crew_photos(job, crew, color))
	else:
		col.add_child(_pile_and_count(crew, color, ExpandedView._thousands(crew.size()), "pets on it"))
		var crowd := Crowd.new()
		crowd.set_pets(crew)
		col.add_child(crowd)

	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	fill.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(fill)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	var amount := "all" if _step < 0 else str(_step)
	var minus := UiTheme.button("−" if _step == 1 else "− " + amount, func(): _take_off(job, _step))
	minus.disabled = crew.is_empty()
	buttons.add_child(minus)
	var plus := UiTheme.button("+ a pet" if _step == 1 else "+ " + amount, func(): _put_on(job, _step))
	plus.add_theme_stylebox_override("normal", _primary())
	plus.disabled = _resting.is_empty()
	buttons.add_child(plus)
	col.add_child(buttons)
	return panel


func _crew_photos(job: Dictionary, crew: Array, color: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	for i in crew.size():
		var uid: String = crew[i]
		var photo := Polaroid.new(GameState.collection.get_pet(uid), color)
		photo.tooltip_text = _name(uid) + "\ntap to let it rest"
		photo.pressed.connect(func(): _take_off(job, 1, [uid]))
		grid.add_child(Tilted.new(photo, PHOTO_TILTS[i % PHOTO_TILTS.size()]))
	if crew.size() < POLAROIDS and not _resting.is_empty():
		var empty := Polaroid.new(null, color)
		empty.tooltip_text = "put a resting pet here"
		empty.pressed.connect(func(): _put_on(job, 1, [_picked] if _picked != "" else []))
		grid.add_child(empty)
	return grid


func _coming_note(coming: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NOTE_WIDTH, 300)
	panel.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.LINE, Color(UiTheme.DEEP, 0.5), 8, 12))
	var col := _column(panel, 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UiTheme.icon_rect("job_coming", 40, UiTheme.LOCKED)
	icon.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(icon)
	for line in [[coming.name, UiTheme.LOCKED], [coming.hint, UiTheme.LOCKED]]:
		var l := _wrapped(str(line[0]), line[1])
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	return panel


func _rebuild_box() -> void:
	UiTheme.clear(_box)
	var catalog := Catalog.shared()
	var away: Dictionary = GameState.jobs_away
	if int(away.get("coins", 0)) + int(away.get("parts", 0)) > 0:
		_box.add_child(_away_note(away))
	var resting := _resting
	_box.add_child(_heading("resting", resting.size()))
	if resting.size() <= RESTING_POLAROIDS:
		_box.add_child(_wrapped("now tap a job" if _picked != "" else ("tap a pet, then a job" if not resting.is_empty() else "everyone's busy!"), UiTheme.MUTED))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 8)
		for i in resting.size():
			var pet: Pet = resting[i]
			var photo := Polaroid.new(pet, UiTheme.PINK)
			photo.picked = pet.uid == _picked
			photo.tooltip_text = pet.display_name(catalog)
			photo.pressed.connect(func():
				_picked = "" if _picked == pet.uid else pet.uid
				_dirty = true)
			grid.add_child(Tilted.new(photo, PHOTO_TILTS[(i + 3) % PHOTO_TILTS.size()]))
		_box.add_child(grid)
	else:
		var uids: Array = resting.slice(0, 3).map(func(p): return p.uid)
		_box.add_child(_pile_and_count(uids, UiTheme.PINK, ExpandedView._thousands(resting.size()), "having a nap"))
		var share := UiTheme.button("share them out", func():
			GameState.share_out()
			PetBubble.say_line(self, "errands_share"))
		share.add_theme_stylebox_override("normal", _primary())
		_box.add_child(share)
		_box.add_child(_wrapped("or tap a job's + to send %s" % ("them all" if _step < 0 else str(_step)), UiTheme.MUTED))
	if GameState.sendable_pets().size() > STEPS_AFTER:
		var auto := CheckButton.new()
		auto.text = "%s shares out new pets" % _active_name()
		auto.button_pressed = GameState.jobs_auto
		auto.focus_mode = FOCUS_NONE
		auto.add_theme_font_size_override("font_size", UiTheme.SMALL)
		auto.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		auto.custom_minimum_size = Vector2(120, 0)
		auto.toggled.connect(func(on):
			GameState.set_jobs_auto(on)
			PetBubble.say_line(self, "errands_auto_on" if on else "errands_auto_off"))
		_box.add_child(auto)

	var out: Array = GameState.away().keys()
	if not out.is_empty():
		_box.add_child(_heading("on adventures", out.size()))
		var pile := Pile.new(out.slice(0, 3), UiTheme.MUTED)
		pile.modulate.a = 0.5
		_box.add_child(pile)


func _away_note(away: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.RAISED.lerp(UiTheme.MINT, 0.1), UiTheme.MINT.lerp(UiTheme.LINE, 0.6), 6, 2, 8))
	var col := _column(panel, 1)
	col.add_child(UiTheme.title("while you were away", 13, UiTheme.MINT))
	var bits: Array[String] = []
	if int(away.get("coins", 0)) > 0:
		bits.append("%s coins" % ExpandedView._thousands(int(away.coins)))
	if int(away.get("parts", 0)) > 0:
		bits.append("%s part%s" % [ExpandedView._thousands(int(away.parts)), "s" if int(away.parts) > 1 else ""])
	col.add_child(_wrapped(" and ".join(bits), UiTheme.TEXT))
	return Tilted.new(panel, -1.5)


# ---- doing things ----------------------------------------------------------------

func _put_on(job: Dictionary, count: int, uids: Array = []) -> void:
	_picked = ""
	_dirty = true
	if _resting.is_empty():
		PetBubble.say_line(self, "errands_busy")
		return
	var before := GameState.job_crew(job.id).size()
	GameState.put_on_job(job.id, count, uids)
	var added := GameState.job_crew(job.id).size() - before
	if added == 1:
		PetBubble.say_line(self, "errands_on", { "name": _name(GameState.job_crew(job.id)[-1]), "job": job.name })
	elif added > 1:
		PetBubble.say_line(self, "errands_many_on", { "count": ExpandedView._thousands(added), "job": job.name })


func _take_off(job: Dictionary, count: int, uids: Array = []) -> void:
	var gone := GameState.take_off_job(job.id, count, uids)
	if gone.size() == 1:
		PetBubble.say_line(self, "errands_off", { "name": _name(gone[0]) })
	elif gone.size() > 1:
		PetBubble.say_line(self, "errands_many_off")


## A meter filled: a little "+6" floats up from it, and now and then your pet says what was found.
func _paid(job_id: String, loot: Dictionary) -> void:
	if not is_visible_in_tree() or not _meters.has(job_id) or not is_instance_valid(_meters[job_id]):
		return
	var meter: Meter = _meters[job_id]
	var coins := Rewards.total(loot, "coins")
	var parts := Rewards.total(loot, "part")
	var text := "+%s" % ExpandedView._thousands(coins) if coins > 0 else ("+ a part" if parts == 1 else "+%s parts" % ExpandedView._thousands(parts))
	var pop := UiTheme.title(text, 14, meter.color)
	pop.top_level = true
	pop.mouse_filter = MOUSE_FILTER_IGNORE
	meter.add_child(pop)
	pop.global_position = meter.global_position + Vector2(meter.size.x / 2.0 - pop.get_combined_minimum_size().x / 2.0, -14)
	var tween := pop.create_tween().set_parallel()
	tween.tween_property(pop, "global_position:y", pop.global_position.y - 30.0, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(pop, "modulate:a", 0.0, 1.1).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(pop.queue_free)
	if parts == 1 and _rng.randf() < 0.35:
		for key: String in loot:
			if key.begins_with("part:"):
				var bits := key.split(":")
				PetBubble.say_line(self, "errands_part", { "part": "a " + str(Catalog.shared().part(bits[1], bits[2]).get("name", bits[2])) + " " + bits[1] })


# ---- little helpers ----------------------------------------------------------------

func _note_panel(color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.custom_minimum_size = Vector2(NOTE_WIDTH, 300)
	var sb := UiTheme.sticker(color.lerp(UiTheme.LINE, 0.55), 6, UiTheme.RAISED, 12)
	sb.content_margin_top = 16
	sb.corner_radius_bottom_right = 18
	panel.add_theme_stylebox_override("panel", sb)
	# a strip of tape holding it to the board
	panel.draw.connect(func():
		var tape := Rect2(panel.size.x / 2.0 - 23.0, -9.0, 46.0, 15.0)
		panel.draw_set_transform(tape.get_center(), deg_to_rad(-4.0))
		panel.draw_rect(Rect2(-tape.size / 2.0, tape.size), Color(color, 0.45))
		panel.draw_set_transform(Vector2.ZERO))
	return panel


func _column(panel: PanelContainer, gap: int) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", gap)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(col)
	return col


func _pile_and_count(uids: Array, color: Color, count: String, what: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.add_child(Pile.new(uids.slice(0, 3), color))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	words.add_child(UiTheme.title(count, 22, color))
	words.add_child(UiTheme.label(what, UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(words)
	return row


func _heading(text: String, count: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.title(text, 16, UiTheme.LILAC))
	if count > RESTING_POLAROIDS:
		var n := UiTheme.label(ExpandedView._thousands(count), UiTheme.MUTED, UiTheme.SMALL)
		n.size_flags_vertical = SIZE_SHRINK_END
		row.add_child(n)
	return row


func _row(left: String, right: String, right_color: Color) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = MOUSE_FILTER_IGNORE
	var l := _shrinkable(UiTheme.label(left, UiTheme.MUTED, UiTheme.SMALL))
	l.tooltip_text = left
	row.add_child(l)
	row.add_child(UiTheme.label(right, right_color, UiTheme.SMALL))
	return row


## A one-line label that gives way when there's no room: it's cut short with "…" instead of
## pushing its container (and the window) wider.
func _shrinkable(l: Label) -> Label:
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	return l


func _wrapped(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color, UiTheme.SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _primary() -> StyleBoxFlat:
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	return sb


## "6 coins" or "a part": what one full meter brings.
static func _pay_words(job: Dictionary, crew: int) -> String:
	var p: Dictionary = job.get("pay", {})
	if p.has("coins"):
		return "%d coins" % roundi((float(p.coins[0]) + float(p.coins[1])) / 2.0)
	var uncommon: Dictionary = job.get("uncommon", {})
	return "a part, sometimes uncommon" if crew >= int(uncommon.get("crew", 1 << 30)) else "a common part"


static func _every(rate: float) -> String:
	if rate <= 0.0:
		return "nobody on it"
	var s := maxi(1, roundi(1.0 / rate))
	return "every %dm %02ds" % [s / 60, s % 60] if s >= 60 else "every %ds" % s


static func _per_minute(job: Dictionary, rate: float) -> String:
	var p: Dictionary = job.get("pay", {})
	if p.has("coins"):
		return "%s coins a minute" % ExpandedView._thousands(roundi(rate * 60.0 * (float(p.coins[0]) + float(p.coins[1])) / 2.0))
	return "%s parts a minute" % ExpandedView._thousands(roundi(rate * 60.0 * float(p.get("part", 1))))


static func _color(job: Dictionary) -> Color:
	match str(job.get("color", "")):
		"cyan": return UiTheme.CYAN
		"lilac": return UiTheme.LILAC
		"mint": return UiTheme.MINT
		"gold": return UiTheme.GOLD
	return UiTheme.PINK


static func _name(uid: String) -> String:
	var pet := GameState.collection.get_pet(uid)
	return pet.display_name(Catalog.shared()) if pet else "someone"


static func _active_name() -> String:
	var pet := GameState.collection.active()
	return pet.display_name(Catalog.shared()) if pet else "your pet"


static func _clicked(e: InputEvent) -> bool:
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT


## The corkboard: little specks on the paper.
static func _draw_cork(board: Control) -> void:
	var y := 5.0
	var row := 0
	while y < board.size.y - 4.0:
		var x := 3.0 + (row % 2) * 6.0
		while x < board.size.x - 4.0:
			board.draw_rect(Rect2(x, y, 2, 2), Color(UiTheme.GOLD, 0.08))
			x += 13.0
		y += 13.0
		row += 1


## A photo of a pet: a light frame, the pet inside, a pin on top. With no pet, a dashed "+" slot.
class Polaroid extends Control:
	signal pressed
	const SIZE := Vector2(46, 54)
	var pin: Color
	var picked := false:
		set(value):
			picked = value
			queue_redraw()
	var _pet: Pet

	func _init(pet: Pet, pin_color: Color) -> void:
		_pet = pet
		pin = pin_color
		custom_minimum_size = SIZE
		size = SIZE
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		if pet:
			var view := PetView.new()
			view.pixel = 2
			view.animated = false
			view.pet = pet
			view.position = Vector2(SIZE.x / 2.0, SIZE.y - 12.0)
			add_child(view)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()

	func _draw() -> void:
		if _pet == null:
			draw_style_box(UiTheme.stitched(pin.lerp(UiTheme.LINE, 0.6), Color(0, 0, 0, 0), 4, 0), Rect2(Vector2.ZERO, SIZE))
			var font := UiTheme.BODY_FONT
			draw_string(font, Vector2(0, SIZE.y / 2.0 + 6.0), "+", HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 16, UiTheme.MUTED)
			return
		draw_rect(Rect2(Vector2(1, 3), SIZE), UiTheme.SHADOW)
		draw_rect(Rect2(Vector2.ZERO, SIZE), UiTheme.TEXT.lerp(UiTheme.PAGE, 0.2))
		draw_rect(Rect2(Vector2(4, 4), SIZE - Vector2(8, 14)), UiTheme.DEEP)
		draw_circle(Vector2(SIZE.x / 2.0, 0), 3.5, pin)
		if picked:
			draw_style_box(UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 8, 0), Rect2(Vector2(-5, -5), SIZE + Vector2(10, 10)))


## Three polaroids stacked a little crooked, pinned once: a crew too big for one photo each.
class Pile extends Control:
	const OFFSETS := [Vector2(0, 4), Vector2(9, 0), Vector2(18, 6)]
	const ANGLES := [-7.0, 5.0, -2.0]

	func _init(uids: Array, pin: Color) -> void:
		custom_minimum_size = Vector2(66, 62)
		mouse_filter = MOUSE_FILTER_IGNORE
		for i in uids.size():
			var photo := Polaroid.new(GameState.collection.get_pet(uids[i]), pin if i == uids.size() - 1 else Color(0, 0, 0, 0))
			photo.mouse_filter = MOUSE_FILTER_IGNORE
			photo.position = OFFSETS[i]
			photo.pivot_offset = Polaroid.SIZE / 2.0
			photo.rotation_degrees = ANGLES[i]
			add_child(photo)


## A bustling little crowd of tiny pets, more of them the bigger the crew (never more than fit).
class Crowd extends Control:
	const MOST := 44
	var _views: Array[PetView] = []
	var _time := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 44)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			set_process(is_visible_in_tree())

	func set_pets(uids: Array) -> void:
		var shown := mini(mini(uids.size(), roundi(8.0 + log(float(uids.size())) / log(10.0) * 14.0)), MOST)
		for i in shown:
			var view := PetView.new()
			view.pixel = 1
			view.animated = false
			view.pet = GameState.collection.get_pet(uids[i])
			view.set_meta("i", i)
			add_child(view)
			_views.append(view)
		resized.connect(_place)

	func _place() -> void:
		for view in _views:
			var i: int = view.get_meta("i")
			view.position = Vector2(8.0 + fposmod(i * 37.0, 100.0) / 100.0 * (size.x - 16.0), 18.0 + floorf(i / 11.0) * 9.0 + (i * 13) % 5)
			view.set_meta("y", view.position.y)

	func _process(delta: float) -> void:
		_time += delta
		for view in _views:
			if view.has_meta("y"):
				view.position.y = view.get_meta("y") - roundf(absf(sin(_time * 5.5 + view.get_meta("i") * 1.3)) * 2.0)


## An errand's meter: fills up and pays; when it fills faster than you can see, a flowing stripe.
class Meter extends Control:
	var color := Color.WHITE
	var stream := false
	var fill := 0.0:
		set(value):
			if stream or absf(value - fill) > 0.001:
				fill = value
				queue_redraw()
	var _time := 0.0
	var _well := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 6, 2, 0)
	var _bar: StyleBoxFlat

	func _init() -> void:
		custom_minimum_size = Vector2(0, 12)
		mouse_filter = MOUSE_FILTER_IGNORE
		clip_contents = true

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			set_process(is_visible_in_tree())

	func _process(delta: float) -> void:
		if stream:
			_time += delta

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _bar == null:
			_bar = UiTheme.box(color, color, 6, 0, 0)
		draw_style_box(_well, r)
		if stream:
			draw_style_box(_bar, r.grow(-2))
			var x := -size.y + fposmod(_time * 28.0, 12.0)
			while x < size.x:
				draw_line(Vector2(x, size.y - 2), Vector2(x + size.y - 4, 2), Color(UiTheme.DEEP, 0.35), 4.0)
				x += 12.0
		elif fill > 0.02:
			draw_style_box(_bar, Rect2(Vector2(2, 2), Vector2(maxf(size.y - 4, (size.x - 4) * fill), size.y - 4)))
