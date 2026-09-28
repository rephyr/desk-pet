class_name ErrandsTab
extends VBoxContainer
## Errands: the idle way to make coins, and where coins go when the machine waits for bits. Two
## pages. JOBS: a corkboard of jobs (data/errands.json, Jobs), each a sticky note with its meter,
## what it brings, its level and goals, and its crew. On the right a shoebox of resting pets. Tap a
## resting pet, then a note, to put it to work; tap a pet on a note to let it rest. A crew can be a
## couple of pets or thousands: up to POLAROIDS each pet gets its own polaroid, past that the note
## shows a pile, the count and a little crowd, and + and − move 1, 10, 100 or all at once.
## UPGRADES: the pegboard (ErrandToolsView), tools bought with coins. At the top, what errands
## bring a minute, so every tool you buy shows.
## Design: design/mockups/screens/errands.html (the corkboard), errands-upgrades.html (A: pegboard).

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
var _picked := ""  # uid of a resting pet waiting to be put on a job (a stand-in's: one from its count)
var _dirty := true
var _resting: Array = []  # uids of the resting pets shown (cards, then stand-ins), worked out once per rebuild
var _resting_n := 0  # everyone resting, cards and herd
var _away_count := -1  # pets on adventures at the last rebuild
var _rng := RandomNumberGenerator.new()
var _jobs_page := HBoxContainer.new()
var tools := ErrandToolsView.new()
var _mode: PanelContainer
var _buy_row := HBoxContainer.new()
var _income: Label
var _income_at := 0.0  # seconds until the coins a minute are worked out again


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()

	# jobs | upgrades, how many levels a tap buys, and what errands bring a minute
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_mode = UiTheme.segmented(["jobs", "upgrades"], 0, func(i): _show_page(i))
	bar.add_child(_mode)
	_buy_row.add_theme_constant_override("separation", 6)
	var buy := UiTheme.label("buy", UiTheme.MUTED, UiTheme.SMALL)
	buy.size_flags_vertical = SIZE_SHRINK_CENTER
	_buy_row.add_child(buy)
	_buy_row.add_child(UiTheme.segmented(["x1", "x10", "max"], 0, func(i): tools.buy_n = [1, 10, -1][i]))
	_buy_row.visible = false
	bar.add_child(_buy_row)
	bar.add_child(UiTheme.spacer())
	bar.add_child(_income_pill())
	add_child(bar)
	_jobs_page.add_theme_constant_override("separation", 14)
	_jobs_page.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_jobs_page)
	tools.visible = false
	add_child(tools)

	# the corkboard
	var board := PanelContainer.new()
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	var cork := UiTheme.box(UiTheme.PAPER.lerp(UiTheme.GOLD, 0.04), UiTheme.LINE, 14, 2, 14)
	cork.content_margin_left = 16
	cork.content_margin_right = 16
	board.add_theme_stylebox_override("panel", cork)
	board.draw.connect(func(): _draw_cork(board))
	_jobs_page.add_child(board)
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
	_jobs_page.add_child(shoebox)

	GameState.jobs_changed.connect(func(): _dirty = true)
	GameState.unlocked.connect(func(e: Dictionary):
		_dirty = true  # a new job may have opened: show it
		if e.opens.any(func(o): return str(o).begins_with("job:")):
			show_page(0))
	GameState.adventures_changed.connect(func():
		if GameState.away().size() != _away_count:
			_dirty = true)
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	GameState.collection.pets_removed.connect(func(_u): _dirty = true)
	GameState.collection.herd_changed.connect(func(_keys): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.job_paid.connect(_paid)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_rebuild()
			speak()
		elif not GameState.jobs_away.is_empty():
			GameState.jobs_away = {}  # the "while you were away" note was seen
			_dirty = true)


## 0 the jobs, 1 the upgrades (flips the switch at the top too).
func show_page(page: int) -> void:
	(_mode.get_child(0).get_child(page) as Button).pressed.emit()


func _show_page(page: int) -> void:
	_jobs_page.visible = page == 0
	tools.visible = page == 1
	_buy_row.visible = page == 1
	if page == 1:
		PetBubble.say_line(self, "errands_upgrades")
	else:
		_dirty = true


## "◆ 448 a minute on errands": the number every tool makes go up.
func _income_pill() -> Control:
	var pill := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.CYAN.lerp(UiTheme.LINE, 0.6), 999, 2, 0)
	sb.content_margin_left = 10
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_vertical = SIZE_SHRINK_CENTER
	pill.tooltip_text = "what errands bring while you're busy"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(UiTheme.icon_rect("coin", 18, UiTheme.CYAN))
	_income = UiTheme.title("0", 20, UiTheme.CYAN)
	row.add_child(_income)
	var words := UiTheme.label("a minute\non errands", UiTheme.MUTED, UiTheme.SMALL)
	words.add_theme_constant_override("line_spacing", -3)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(words)
	pill.add_child(row)
	return pill


func _update_income() -> void:
	var text := UiTheme.num(GameState.errands_per_minute())
	if text != _income.text:
		var grew := _income.text != "0" and text != _income.text
		_income.text = text
		if grew and is_visible_in_tree():
			_income.pivot_offset = _income.size / 2.0
			var tween := _income.create_tween()
			tween.tween_property(_income, "scale", Vector2(1.25, 1.25), 0.1)
			tween.tween_property(_income, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK)


func speak() -> void:
	var resting := GameState.resting_count()
	if GameState.spare_count() == 0:
		PetBubble.say_line(self, "errands_nobody")
	elif resting > 0:
		PetBubble.say_line(self, "errands_resting", { "count": ExpandedView._thousands(resting) })
	else:
		PetBubble.say_line(self, "errands")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_income_at -= delta
	if _income_at <= 0.0:
		_income_at = 0.5
		_update_income()
	if not _jobs_page.visible:
		return
	if _dirty:
		_rebuild()
	for job_id in _meters:
		_meters[job_id].fill = GameState.job_fill_now(job_id)


# ---- building it ----------------------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	_meters.clear()
	_resting_n = GameState.resting_count()
	_resting = GameState.resting_faces(RESTING_POLAROIDS + 1)
	_away_count = GameState.away().size()
	var many := GameState.spare_count() > STEPS_AFTER
	_steps_row.visible = many
	if not many:
		_step = 1
	if _picked != "" and not _picked in _resting:
		_picked = ""
	UiTheme.clear(_notes)
	var catalog := Catalog.shared()
	var notes: Array[Control] = []
	for job in GameState.open_jobs():
		notes.append(_job_note(job))
	for job in catalog.jobs:
		var wait := level_wait(job)
		if not wait.is_empty() and not GameState.is_unlocked(str(job.needs)):
			notes.append(_waiting_note(job, wait))
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
	var size := GameState.job_size(job.id)
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
	if not job.get("tools", []).is_empty():
		_level_sticker(panel, "lv %d" % GameState.job_level(job.id))
	col.add_child(_wrapped(str(job.does), UiTheme.MUTED))

	var meter := Meter.new()
	meter.color = color
	meter.stream = rate > STREAM_AFTER
	_meters[job.id] = meter
	col.add_child(meter)
	if meter.stream:
		col.add_child(_shrinkable(UiTheme.label(_per_minute(job, rate), color, UiTheme.SMALL)))
	else:
		col.add_child(_shrinkable(UiTheme.label(_pay_words(job, size), color, UiTheme.SMALL)))
		col.add_child(_shrinkable(UiTheme.label(_every(rate), UiTheme.MUTED, UiTheme.SMALL)))
	if not job.get("goals", []).is_empty():
		col.add_child(GoalTrack.new(job, color))
		col.add_child(_wrapped(goal_line(job), UiTheme.TEXT))
	if size <= POLAROIDS:
		col.add_child(_row("crew of %d" % size, "%.1fx" % (rate * float(job.seconds)) if size > 0 else "stopped", color))
		col.add_child(_crew_photos(job, GameState.job_faces(job.id, POLAROIDS), color))
	else:
		col.add_child(_pile_and_count(GameState.job_faces(job.id, 3), color, ExpandedView._thousands(size), "pets on it"))
		var crowd := Crowd.new()
		crowd.set_pets(GameState.job_faces(job.id, Crowd.MOST), size)
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
	minus.disabled = size == 0
	buttons.add_child(minus)
	var plus := UiTheme.button("+ a pet" if _step == 1 else "+ " + amount, func(): _put_on(job, _step))
	plus.add_theme_stylebox_override("normal", _primary())
	plus.disabled = _resting_n == 0
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
	if crew.size() < POLAROIDS and _resting_n > 0:
		var empty := Polaroid.new(null, color)
		empty.tooltip_text = "put a resting pet here"
		empty.pressed.connect(func(): _put_on(job, 1, [_picked] if _picked != "" else []))
		grid.add_child(empty)
	return grid


## A job that opens at another job's level (the lemonade stand at coin hunt lv 10): what it
## waits for, as { job, level }, or {} if it waits for something else.
static func level_wait(job: Dictionary) -> Dictionary:
	var needs := str(job.get("needs", ""))
	if needs == "":
		return {}
	for entry in Catalog.shared().unlock_list:
		if needs in entry.opens:
			var levels: Dictionary = entry.earn.get("job_level", {})
			for job_id in levels:
				return { "job": Catalog.shared().job(str(job_id)), "level": int(levels[job_id]) }
	return {}


## A job still to come, and how close its opening is: "opens at coin hunt lv 10", 7 / 10.
func _waiting_note(job: Dictionary, wait: Dictionary) -> Control:
	var color := _color(job)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(NOTE_WIDTH, 300)
	panel.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.LINE, Color(UiTheme.DEEP, 0.5), 8, 12))
	var col := _column(panel, 6)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UiTheme.icon_rect(str(job.doodle), 34, color)
	icon.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(icon)
	var name_label := UiTheme.title("a " + str(job.name), 15, color)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(name_label)
	var at := _wrapped("opens at %s lv %d" % [wait.job.name, wait.level], UiTheme.LOCKED)
	at.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(at)
	var have := GameState.job_level(wait.job.id)
	var meter := Meter.new()
	meter.color = _color(wait.job)
	meter.fill = clampf(float(have) / wait.level, 0.0, 1.0)
	col.add_child(meter)
	var count := _wrapped("%d / %d" % [mini(have, wait.level), wait.level], UiTheme.LOCKED)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(count)
	return panel


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
	_box.add_child(_heading("resting", _resting_n))
	if _resting_n <= RESTING_POLAROIDS:
		_box.add_child(_wrapped("now tap a job" if _picked != "" else ("tap a pet, then a job" if _resting_n > 0 else "everyone's busy!"), UiTheme.MUTED))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 8)
		for i in _resting.size():
			var uid: String = _resting[i]
			var pet := GameState.collection.get_pet(uid)
			var photo := Polaroid.new(pet, UiTheme.PINK)
			photo.picked = uid == _picked
			photo.tooltip_text = pet.display_name(catalog) if pet else ""
			photo.pressed.connect(func():
				_picked = "" if _picked == uid else uid
				_dirty = true)
			grid.add_child(Tilted.new(photo, PHOTO_TILTS[(i + 3) % PHOTO_TILTS.size()]))
		_box.add_child(grid)
	else:
		_box.add_child(_pile_and_count(_resting.slice(0, 3), UiTheme.PINK, ExpandedView._thousands(_resting_n), "having a nap"))
		var share := UiTheme.button("share them out", func():
			GameState.share_out()
			PetBubble.say_line(self, "errands_share"))
		share.add_theme_stylebox_override("normal", _primary())
		_box.add_child(share)
		_box.add_child(_wrapped("or tap a job's + to send %s" % ("them all" if _step < 0 else str(_step)), UiTheme.MUTED))
	if GameState.spare_count() > STEPS_AFTER:
		# busy paws: a switch per errand (the notes are full already), new pets start on the ones on
		_box.add_child(_heading("new pets join", -1))
		for job in GameState.open_jobs():
			var sw := join_switch(GameState.job_joins(job.id), func(on):
				GameState.set_job_join(job.id, on)
				PetBubble.say_line(self, "join_on" if on else "join_off"))
			sw.text = str(job.name)
			sw.add_theme_color_override("font_pressed_color", _color(job))
			sw.add_theme_color_override("font_hover_pressed_color", _color(job))
			_box.add_child(sw)

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
	if _resting_n == 0:
		PetBubble.say_line(self, "errands_busy")
		return
	var before := GameState.job_size(job.id)
	GameState.put_on_job(job.id, count, uids)
	var added := GameState.job_size(job.id) - before
	if added == 1:
		PetBubble.say_line(self, "errands_on", { "name": _name(GameState.last_moved), "job": job.name })
	elif added > 1:
		PetBubble.say_line(self, "errands_many_on", { "count": ExpandedView._thousands(added), "job": job.name })


func _take_off(job: Dictionary, count: int, uids: Array = []) -> void:
	var gone := GameState.take_off_job(job.id, count, uids)
	if gone == 1:
		PetBubble.say_line(self, "errands_off", { "name": _name(GameState.last_moved) })
	elif gone > 1:
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


## "new pets join here": a small switch on a job (errand notes, the workers' side card).
static func join_switch(on: bool, on_toggle: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = "new pets join here"
	b.button_pressed = on
	b.focus_mode = FOCUS_NONE
	b.add_theme_font_size_override("font_size", UiTheme.SMALL)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size = Vector2(60, 0)
	b.toggled.connect(on_toggle)
	return b


## "740 coins a find" or "a part": what one full meter brings.
static func _pay_words(job: Dictionary, crew: int) -> String:
	var p: Dictionary = job.get("pay", {})
	if p.has("capsules"):
		var each := Jobs.average_fill(job, GameState.job_boost(job.id)) * GameState.boost("coins")
		return "%s%s coins a %s" % ["about " if job.has("tips") else "", UiTheme.num(each), "sale" if job.has("tips") else "find"]
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
	if p.has("capsules"):
		return "%s coins a minute" % UiTheme.num(rate * 60.0 * Jobs.average_fill(job, GameState.job_boost(job.id)) * GameState.boost("coins"))
	if p.has("coins"):
		return "%s coins a minute" % ExpandedView._thousands(roundi(rate * 60.0 * (float(p.coins[0]) + float(p.coins[1])) / 2.0))
	return "%s parts a minute" % ExpandedView._thousands(roundi(rate * 60.0 * float(p.get("part", 1))))


## "lv 7. at lv 10: a lemonade stand opens", or "lv 100. every goal reached!"
static func goal_line(job: Dictionary) -> String:
	var lv := GameState.job_level(job.id)
	var next := Jobs.next_goal(job, lv)
	if next.is_empty():
		return "lv %d. every goal reached!" % lv
	return "lv %d. at lv %d: %s" % [lv, int(next.at), Jobs.goal_words(job, next)]


## The job's level on a little gold sticker stuck over the note's top right corner (drawn on top,
## so it never makes the note wider).
static func _level_sticker(panel: PanelContainer, text: String) -> void:
	panel.draw.connect(func():
		var font := UiTheme.DISPLAY_FONT
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		var at := Vector2(panel.size.x - w + 8.0, -8.0)
		panel.draw_set_transform(at + Vector2(w, 18.0) / 2.0, deg_to_rad(8.0))
		var r := Rect2(-Vector2(w, 18.0) / 2.0, Vector2(w, 18.0))
		panel.draw_style_box(UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 9, 0, 0), r)
		panel.draw_string(font, r.position + Vector2(7.0, 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.DEEP)
		panel.draw_set_transform(Vector2.ZERO))


## A little rounded tag in a colour with dark text, like "lv 7" or "max".
static func pill(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.box(color, color, 999, 0, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 1
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = MOUSE_FILTER_IGNORE
	var l := UiTheme.title(text, 12, UiTheme.DEEP)
	p.add_child(l)
	return p


static func _color(job: Dictionary) -> Color:
	return UiTheme.named_color(str(job.get("color", "")))


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

	## `uids`: faces to pick from; `total`: how many pets the crowd stands for (the crowd grows with it).
	func set_pets(uids: Array, total := -1) -> void:
		var n := float(maxi(1, total if total >= 0 else uids.size()))
		var shown := mini(mini(uids.size(), roundi(8.0 + log(n) / log(10.0) * 14.0)), MOST)
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


## A job's goals along a dotted line: a star for each, gold once reached, the next one twinkling,
## the line filled up to the job's level (early goals get more room).
class GoalTrack extends Control:
	var _job: Dictionary
	var _tint: Color
	var _time := 0.0
	var _since := 0.0
	var _stars: Array[Texture2D] = []  # reached, next, still to come

	func _init(job: Dictionary, color: Color) -> void:
		_job = job
		_tint = color
		_stars = [UiTheme.icon("star", 18, UiTheme.GOLD), UiTheme.icon("star", 18, color), UiTheme.icon("star", 18, UiTheme.LINE)]
		custom_minimum_size = Vector2(0, 22)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			set_process(is_visible_in_tree())

	func _process(delta: float) -> void:
		_time += delta
		_since += delta
		if _since > 0.066:  # the next star twinkles; about 15 redraws a second is plenty
			_since = 0.0
			queue_redraw()

	func _x(level: float, last: float) -> float:
		return 9.0 + sqrt(clampf(level / last, 0.0, 1.0)) * (size.x - 18.0)

	func _draw() -> void:
		var goals: Array = _job.get("goals", [])
		if goals.is_empty():
			return
		var last := float(goals[-1].at)
		var lv := GameState.job_level(_job.id)
		var y := size.y / 2.0
		var x := 9.0
		while x < size.x - 9.0:
			draw_line(Vector2(x, y), Vector2(minf(x + 5.0, size.x - 9.0), y), UiTheme.LINE, 2.0)
			x += 9.0
		if lv > 0:
			draw_line(Vector2(9.0, y), Vector2(_x(lv, last), y), _tint, 4.0)
		var next := Jobs.next_goal(_job, lv)
		for g in goals:
			var got := lv >= int(g.at)
			var is_next := not next.is_empty() and int(next.at) == int(g.at)
			var s := 18.0 * (1.0 + 0.15 * sin(_time * 4.0) if is_next else 1.0)
			var tex := _stars[0 if got else (1 if is_next else 2)]
			draw_texture_rect(tex, Rect2(Vector2(_x(float(g.at), last), y) - Vector2(s, s) / 2.0, Vector2(s, s)), false)
