class_name MachineTab
extends VBoxContainer
## The capsule machine: pull the lever towards you; every chute drops a capsule with one prize
## (data/machine.json, Machine, GameState.pull_lever). Two pages: the machine itself (with the
## upgrades you can work on right now next to it) and its upgrade tree (MachineTreeView): you're
## fixing up an old broken machine with coins and bits (pets bring bits home from adventures). Your
## lever is never automated (later your pet cranks a little machine of its own, much slower, see the
## automation tab), so pulling has to feel good forever: the lever is the whole point of this tab.
## Design: design/mockups/screens/capsules.html, machine-tree.html.

const NEXT_UP := 3  # upgrades shown next to the machine

var stage := MachineStage.new()
var upgrades := MachineTreeView.new()
var _machine_page := HBoxContainer.new()
var _next := VBoxContainer.new()
var _bits_row := HBoxContainer.new()
var _mode: PanelContainer
var _last := ""
var _table := PanelContainer.new()  # where a pet box out of a capsule gets opened
var _opening := PackOpening.new()
var _box_coming := false  # a pet box popped out and its opening is about to start


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_mode = UiTheme.segmented(["machine", "upgrades"], 0, func(i): _show_page(i))
	bar.add_child(_mode)
	bar.add_child(UiTheme.spacer())
	_bits_row.add_theme_constant_override("separation", 6)
	bar.add_child(_bits_row)
	add_child(bar)

	_machine_page.add_theme_constant_override("separation", 14)
	_machine_page.size_flags_vertical = SIZE_EXPAND_FILL
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	stage.size_flags_vertical = SIZE_EXPAND_FILL
	_machine_page.add_child(stage)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(236, 0)
	side.add_theme_constant_override("separation", 8)
	side.add_child(UiTheme.title("next up", 16, UiTheme.LILAC))
	_next.add_theme_constant_override("separation", 8)
	side.add_child(_next)
	side.add_child(UiTheme.button("all upgrades →", func(): show_page(1)))
	_machine_page.add_child(side)
	add_child(_machine_page)
	upgrades.visible = false
	add_child(upgrades)
	# a box with a pet inside, out of a capsule: opened right here, with the real ritual
	_table.size_flags_vertical = SIZE_EXPAND_FILL
	_table.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 14))
	_table.visible = false
	_opening.allow_again = false  # there's no pile to open another from here
	_opening.closed.connect(_close_box)
	_table.add_child(_opening)
	add_child(_table)
	stage.pet_box.connect(_open_box)

	GameState.changed.connect(_refresh)
	GameState.machine_pulled.connect(stage.show_pull)
	GameState.machine_upgraded.connect(stage.fixed)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_last = ""
			_refresh()
			speak())


## A pet box popped out of a capsule: after a moment the machine steps aside and the box lands
## to be ripped open.
func _open_box(pet: Pet, box_id: String) -> void:
	_box_coming = true
	await get_tree().create_timer(0.8).timeout
	_box_coming = false
	_machine_page.visible = false
	upgrades.visible = false
	_mode.visible = false
	_table.visible = true
	_opening.play(pet, box_id)


func _close_box() -> void:
	_table.visible = false
	_mode.visible = true
	_show_page(0)
	PetBubble.say_line(self, "machine_pet_box_done")


## Whether something at the machine is still being shown (capsules opening, a prize's card, a pet
## box): unlock popups wait for it.
func busy() -> bool:
	return is_visible_in_tree() and (stage.showing_prize() or _box_coming or _table.visible)


func speak() -> void:
	PetBubble.say_line(self, "machine_first" if int(GameState.machine.pulls) == 0 else "machine")


## 0 the machine, 1 its upgrade tree (flips the switch at the top too).
func show_page(page: int) -> void:
	(_mode.get_child(0).get_child(page) as Button).pressed.emit()


func _show_page(page: int) -> void:
	_machine_page.visible = page == 0
	upgrades.visible = page == 1


## For the tutorial: the lever (while a pull is what it wants).
func tutorial_target() -> Control:
	return stage.lever_target


## Pulls the lever all the way, as if you did (the dev driver's "pull" step).
func pull() -> void:
	show_page(0)
	stage.pull_by_itself()


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	var key := "%d|%s|%s" % [GameState.coins, str(GameState.bits), str(GameState.machine.bought)]
	if key == _last:
		return
	_last = key
	UiTheme.clear(_bits_row)
	for b in Machine.BITS:
		var n := int(GameState.bits.get(b, 0))
		var chip := UiTheme.chip("bit_" + b, "%d %s" % [n, bit_name(b, n)], UiTheme.TEXT if n > 0 else UiTheme.LOCKED)
		chip.tooltip_text = "machine bits: pets find them on adventures"
		_bits_row.add_child(chip)
	# the upgrades you can work on right now, cheapest first
	UiTheme.clear(_next)
	var catalog := Catalog.shared()
	var open: Array = catalog.machine_tree.nodes.filter(func(n):
		var look := Machine.look(GameState.machine, catalog, n.id)
		return (look == "next" or look == "owned") and not Machine.maxed(GameState.machine, catalog, n.id))
	open.sort_custom(func(a, b): return Machine.cost(GameState.machine, catalog, a.id) < Machine.cost(GameState.machine, catalog, b.id))
	for n in open.slice(0, NEXT_UP):
		_next.add_child(NodeCard.new(n))
	if open.is_empty():
		_next.add_child(UiTheme.label("everything's fixed! for now…", UiTheme.MUTED, UiTheme.SMALL + 1))


static func bit_name(bit: String, n: int) -> String:
	return bit if n == 1 or bit == "glass" else bit + "s"


## A little fanfare when something on the machine gets fixed or upgraded.
static func cheer(from: Node, id: String) -> void:
	Sfx.play(from, _sound("light"), 7.0)
	Sfx.play(from, _sound("prize"))
	PetBubble.say_line(from, "machine_fix_" + id if Catalog.shared().voice.get("ui", {}).has("machine_fix_" + id) else "machine_fix")


static func _sound(key: String) -> Dictionary:
	return Sfx.sound("machine", key)


## One upgrade you can work on, next to the machine: its icon, name, what it gives, what it costs
## (coins and bits). Tap to buy it when you can.
class NodeCard extends Button:
	var info: Dictionary

	func _init(n: Dictionary) -> void:
		info = n
		focus_mode = FOCUS_NONE
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		var why := Machine.blocker(state, catalog, n.id, GameState.coins, GameState.bits)
		var color := MachineTreeView.color_of(n.branch)
		disabled = why != ""
		mouse_default_cursor_shape = CURSOR_ARROW if disabled else CURSOR_POINTING_HAND
		var normal := UiTheme.box(UiTheme.RAISED, UiTheme.LINE, 10, 2, 0)
		for s in ["normal", "disabled", "focus"]:
			add_theme_stylebox_override(s, normal)
		add_theme_stylebox_override("hover", UiTheme.box(UiTheme.RAISED, color, 10, 2, 0))
		add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.RAISED.lerp(color, 0.12), color, 10, 2, 0))
		var row := HBoxContainer.new()
		row.set_anchors_preset(PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		row.offset_top = 9
		row.offset_bottom = -9
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(row)
		var icon := UiTheme.icon_rect("tree_" + str(n.icon), 26, color)
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		row.add_child(col)
		var name_label := UiTheme.label(str(n.name), color, 14)
		name_label.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		col.add_child(name_label)
		var gain := UiTheme.label(str(n.gain), UiTheme.MUTED, UiTheme.SMALL + 1)
		gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(gain)
		var cost := HBoxContainer.new()
		cost.add_theme_constant_override("separation", 4)
		cost.add_child(UiTheme.icon_rect("coin", 12, UiTheme.CYAN))
		var price := Machine.cost(state, catalog, n.id)
		cost.add_child(UiTheme.label(UiTheme.num(price), UiTheme.CYAN if GameState.coins >= price else UiTheme.MUTED, UiTheme.SMALL + 1))
		var need := Machine.bits_cost(catalog, n.id)
		for b in need:
			cost.add_child(UiTheme.icon_rect("bit_" + b, 13))
			var have := int(GameState.bits.get(b, 0)) >= int(need[b])
			cost.add_child(UiTheme.label("%d" % int(need[b]), UiTheme.TEXT if have else UiTheme.PINK, UiTheme.SMALL + 1))
		col.add_child(cost)
		for c in [row, icon, col, name_label, gain, cost] + cost.get_children():
			c.mouse_filter = MOUSE_FILTER_IGNORE
		row.minimum_size_changed.connect(func(): custom_minimum_size.y = row.get_combined_minimum_size().y + 18.0)
		pressed.connect(func():
			if GameState.buy_machine_upgrade(info.id):
				MachineTab.cheer(self, info.id))


## The machine itself, drawn: a glass globe full of capsules on a pink body, the lucky lights on
## its front, the flap a capsule rolls out of, and the lever on its side. Drawn in a 520 x 470
## "design" space (like the mockup) and scaled to fit.
##
## The lever: grab the knob and drag down. It swings towards you (the knob grows as it comes
## closer), clicking past each notch; at the bottom it clunks, the machine jolts, the capsules in
## the globe jump, and one capsule drops out of the flap, bounces and pops open. Let go and the
## lever springs back up with a little wobble.
class MachineStage extends Control:
	signal pet_box(pet: Pet, box_id: String)  # a capsule held a box with a pet inside, for the tab to open
	const DESIGN := Vector2(520, 470)
	const GLOBE := Vector2(200, 150)
	const GLOBE_R := 118.0
	const PIVOT := Vector2(335, 329)
	const ARM := 110.0
	const FLAP := Vector2(200, 372)
	const REST_Y := 418.0  # where a capsule rests on the rug
	const NOTCHES := 6
	const FIRE_AT := 0.96  # pulled this far, the lever clunks and the capsule comes out
	const DRAG_LENGTH := 150.0  # design px of dragging for a full pull
	const RESTS := [[130,210],[172,222],[214,218],[256,212],[110,172],[150,184],[194,182],[238,178],[276,152],[124,134],[166,146],[210,142],[252,120],[146,106],[190,104],[230,84],[172,68],[232,238]]

	var _pull := 0.0  # 0 standing up .. 1 pulled all the way towards you (drawn)
	var _want := 0.0  # where your hand has it
	var _held := false
	var _latched := false  # it clunked: stays down until you let go
	var _spring_t := -1.0  # seconds into springing back, or -1
	var _spring_from := 0.0
	var _grab_y := 0.0
	var _notch := 0
	var _hover := false
	var _time := 0.0
	var _idle := 0.0  # seconds since the last pull (the knob starts to beg after a while)
	var _shake := 0.0
	var _jolt := 0.0  # the machine squashing down on a clunk
	var _balls: Array = []  # capsules in the globe: { rest, off, vel, rot, spin, color }
	var _out: Array = []  # capsules rolling out: { pos, vel, rot, spin, color, t, result, bounces, gold }
	var _bits: Array = []  # confetti: { pos, vel, rot, color, t, life, size }
	var _floats: Array = []  # rising "+3": { pos, text, color, t, size, icon }
	var _flying: Array = []  # coins flying up to the counter: { from, to, t, delay, amount }
	var _popup := PrizePopup.new()  # a good prize's picture, over the globe
	var _pips_pop: Array[float] = []  # each light's pop (1 -> 0) when it lights
	var _shown_coins := -1.0  # the counter, catching up with the real coins as they fly in
	var _counter_pop := 0.0
	var _flap := 0.0  # the flap swinging open (1) and shut
	var _fever_was := false
	var _fever_music: AudioStreamPlayer
	var _fever_level := 0.0
	var _rng := RandomNumberGenerator.new()
	var _auto := false  # pulling by itself (dev driver)
	var _refused := 0.0  # the knob shaking "not yet" (1 -> 0)
	var _halves: Array = []  # the two halves of a capsule that just popped: { pos, vel, rot, spin, color, top, t }
	## Sits over the lever, for the tutorial to point at (drawing is all in _draw).
	var lever_target := Control.new()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		_rng.randomize()
		var colors := _colors()
		for i in RESTS.size():
			_balls.append({ "rest": Vector2(RESTS[i][0], RESTS[i][1]), "off": Vector2.ZERO, "vel": Vector2.ZERO,
				"rot": _rng.randf() * TAU, "spin": 0.0, "color": colors[i % colors.size()] })
		_fever_music = AudioStreamPlayer.new()
		_fever_music.bus = "Music"
		var loop := Sfx.stream_of(MachineTab._sound("fever_loop"))
		if loop is AudioStreamOggVorbis:
			(loop as AudioStreamOggVorbis).loop = true
		_fever_music.stream = loop
		_fever_music.volume_db = -60.0
		add_child(_fever_music)
		lever_target.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(lever_target)
		add_child(_popup)

	static func _colors() -> Array:
		return [UiTheme.PINK, UiTheme.CYAN, UiTheme.MINT, UiTheme.GOLD, UiTheme.LILAC]

	# ---- where things are ----------------------------------------------------------

	func _scale() -> float:
		return minf(size.x / 560.0, size.y / 540.0)

	func _origin() -> Vector2:
		var s := _scale()
		var shake := Vector2(sin(_time * 90.0), cos(_time * 77.0)) * _shake * 3.0
		return size / 2.0 + Vector2(0, 20) - Vector2(260, 235) * s + shake

	func _to_screen(p: Vector2) -> Vector2:
		return _origin() + p * _scale()

	func _to_design(p: Vector2) -> Vector2:
		return (p - _origin()) / _scale()

	## The lever's knob (design space) and how big it is, for `pull` 0..1.
	func _knob(pull: float) -> Array:
		var phi := pull * 1.95  # swings past flat, towards you
		var tip := PIVOT + Vector2(0, -ARM * cos(phi))
		var near := sin(minf(phi, PI / 2.0)) + maxf(0.0, phi - PI / 2.0) * 0.4  # how close to you it is
		return [tip, 17.0 * (1.0 + near * 0.75), near]

	func _counter_at() -> Vector2:
		return Vector2(34, 32)

	# ---- input -----------------------------------------------------------------------

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var d := _to_design(event.position)
			var k: Array = _knob(_pull)
			_hover = d.distance_to(k[0]) < k[1] + 16.0 or (absf(d.x - PIVOT.x) < 22.0 and d.y > k[0].y - 10.0 and d.y < PIVOT.y + 12.0)
			mouse_default_cursor_shape = CURSOR_DRAG if _held else (CURSOR_POINTING_HAND if _hover and _out.is_empty() else CURSOR_ARROW)
			if _held:
				_want = clampf((event.position.y - _grab_y) / (DRAG_LENGTH * _scale()), 0.0, 1.0)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _hover and not _can_grab() and not _out.is_empty():
				# still waiting for the capsule: the knob won't budge
				_refused = 1.0
				Sfx.play(self, MachineTab._sound("tick"), -9.0)
			elif event.pressed and _hover and _can_grab():
				_held = true
				_spring_t = -1.0
				_grab_y = event.position.y - _pull * DRAG_LENGTH * _scale()
				_want = _pull
				mouse_default_cursor_shape = CURSOR_DRAG
				accept_event()
			elif not event.pressed and _held:
				_let_go()

	func _can_grab() -> bool:
		# one pull at a time: wait for the capsule to pop open; you can catch the lever on its way
		# back up once it's most of the way there
		return not _auto and _out.is_empty() and (_spring_t < 0.0 or _pull < 0.35)

	## Whether the lever can be pulled right now (the dev driver waits for this).
	func ready_to_pull() -> bool:
		return _out.is_empty() and not _held and not _auto and (_spring_t < 0.0 or _pull < 0.35)

	func _let_go() -> void:
		_held = false
		_latched = false
		_spring_from = _pull
		_spring_t = 0.0
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if _hover else CURSOR_ARROW
		if _pull > 0.3:
			Sfx.play(self, MachineTab._sound("spring"), _rng.randf_range(-1.0, 1.0))

	## The dev driver's pull: the lever goes down and comes back by itself.
	func pull_by_itself() -> void:
		if _auto:
			return
		_auto = true
		_held = true
		_spring_t = -1.0
		var tw := create_tween()
		tw.tween_property(self, "_want", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.15)
		tw.tween_callback(func():
			if not _latched:
				# a slow frame can end the tween before the lever reached the bottom: clunk anyway
				_pull = 1.0
				_latched = true
				_fire()
			_auto = false
			_let_go())

	# ---- every frame -------------------------------------------------------------------

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_time += delta
		_idle += delta
		_shake = move_toward(_shake, 0.0, delta * 4.0)
		_refused = move_toward(_refused, 0.0, delta * 3.0)
		_jolt = move_toward(_jolt, 0.0, delta * 5.0)
		_counter_pop = move_toward(_counter_pop, 0.0, delta * 4.0)
		_flap = move_toward(_flap, 0.0, delta * 2.2)

		# the lever: follows your hand with a little weight, heavier near the bottom
		if _held:
			var target := _want if not _latched else 1.0
			_pull = lerpf(_pull, target, 1.0 - exp(-delta * lerpf(28.0, 16.0, _pull)))
			var notch := int(floor(_pull * NOTCHES + 0.001))
			if notch > _notch and not _latched:
				for n in range(_notch + 1, notch + 1):
					Sfx.play(self, MachineTab._sound("tick"), n * 1.5 - 2.0)
					_nudge_balls(10.0 + n * 3.0)
				_shake = maxf(_shake, 0.12)
			_notch = notch if not _latched else NOTCHES
			if _pull >= FIRE_AT and not _latched:
				_latched = true
				_fire()
		elif _spring_t >= 0.0:
			# springs back with a wobble past the top
			_spring_t += delta
			var dur := Machine.spring_seconds(GameState.machine, Catalog.shared())
			var k := _spring_t / dur
			_pull = _spring_from * exp(-k * 4.2) * cos(k * 7.5)
			if k >= 1.6:
				_pull = 0.0
				_spring_t = -1.0
			_notch = int(floor(maxf(_pull, 0.0) * NOTCHES))
		else:
			_pull = 0.0

		_popup.position = _to_screen(GLOBE + Vector2(0, 30)) - _popup.size / 2.0
		var knob: Array = _knob(0.0)
		lever_target.position = _to_screen(knob[0] - Vector2(24, 24))
		lever_target.size = Vector2(48, PIVOT.y - knob[0].y + 44) * _scale()
		_move_balls(delta)
		_move_out(delta)
		_move_bits(delta)
		for f in _floats:
			f.t += delta
		_floats = _floats.filter(func(f): return f.t < 1.0)
		for i in _pips_pop.size():
			_pips_pop[i] = move_toward(_pips_pop[i], 0.0, delta * 3.0)
		_move_flying(delta)
		if _shown_coins < 0.0:
			_shown_coins = GameState.coins
		elif _flying.is_empty() and _out.is_empty():
			# nothing on its way: catch up with coins spent or earned elsewhere
			_shown_coins = move_toward(_shown_coins, GameState.coins, maxf(1.0, absf(GameState.coins - _shown_coins)) * delta * 8.0)
		_fever(delta)
		queue_redraw()

	func _fever(delta: float) -> void:
		var on := GameState.fever_left() > 0.0
		if on and not _fever_was:
			Sfx.play(self, MachineTab._sound("fever"))
			PetBubble.say_line(self, "machine_fever")
		_fever_was = on
		_fever_level = move_toward(_fever_level, 1.0 if on else 0.0, delta * (2.0 if on else 1.0))
		if _fever_music.stream == null:
			return
		if _fever_level > 0.0 and not _fever_music.playing:
			_fever_music.play()
		_fever_music.volume_db = lerpf(-50.0, 0.0, sqrt(_fever_level))
		_duck(_fever_level > 0.3)
		if _fever_level <= 0.0 and _fever_music.playing:
			_fever_music.stop()

	var _ducking := false

	## The room music steps back under the fever tune (and comes back after).
	func _duck(on: bool) -> void:
		if on != _ducking:
			_ducking = on
			Music.ducked = on

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
			# left the tab: the fever tune stops with it
			_fever_music.stop()
			_fever_level = 0.0
			_duck(false)
			_held = false
			_latched = false

	# ---- a pull ---------------------------------------------------------------------------

	## The lever hit the bottom: clunk, jolt, and a capsule comes out.
	func _fire() -> void:
		_idle = 0.0
		Sfx.play(self, MachineTab._sound("clunk"), _rng.randf_range(-0.6, 0.6))
		Sfx.play(self, MachineTab._sound("rattle"), _rng.randf_range(-1.5, 1.5))
		_shake = 1.0
		_jolt = 1.0
		_flap = 1.0
		for b in _balls:
			b.vel += Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(-260.0, -120.0))
			b.spin += _rng.randf_range(-8.0, 8.0)
		GameState.pull_lever()  # comes back through show_pull()

	## Whether capsules are still opening or a good prize's card is up (unlock popups wait for it).
	func showing_prize() -> bool:
		return is_visible_in_tree() and (_popup.visible or not _out.is_empty())

	## Something on the machine got fixed: a puff of sparkles where it is, and a little jolt.
	func fixed(id: String) -> void:
		var where := { "tape": Vector2(260, 100), "glass": GLOBE, "oil": Vector2(335, 330), "flap": Vector2(200, 370),
			"wires": Vector2(200, 309), "drops": Vector2(200, 31), "chute2": Vector2(200, 370), "chute3": Vector2(200, 370), "chute4": Vector2(200, 370) }
		var at: Vector2 = where.get(id, GLOBE)
		_shake = 0.6
		_jolt = 0.6
		var colors := _colors()
		for i in 18:
			var a := _rng.randf() * TAU
			_bits.append({ "pos": at, "vel": Vector2(cos(a), sin(a)) * _rng.randf_range(80.0, 220.0), "rot": _rng.randf() * TAU,
				"color": UiTheme.GOLD if i % 2 == 0 else colors[i % colors.size()], "t": 0.0, "life": _rng.randf_range(0.5, 0.9), "size": _rng.randf_range(4.0, 7.0) })

	## The capsules the machine just gave (GameState.machine_pulled): one out of each chute (two or
	## three with extra balls), popping open one after another.
	func show_pull(result: Dictionary) -> void:
		var colors := _colors()
		var capsules: Array = result.capsules
		var n := Machine.chutes(GameState.machine, Catalog.shared())
		for i in capsules.size():
			var cap: Dictionary = capsules[i]
			var gold: bool = cap.prize.kind == "golden" or result.lucky
			var from := Vector2(_chute_x(i % n, n), FLAP.y - 10.0)
			_out.append({ "pos": from, "vel": Vector2(_rng.randf_range(-70.0, 70.0), 40.0 + 30.0 * (i / n)), "rot": 0.0,
				"spin": _rng.randf_range(-10.0, 10.0), "color": UiTheme.GOLD if gold else colors[(int(GameState.machine.pulls) + i) % colors.size()],
				"t": -0.08 * i, "result": cap, "fever": result.fever, "bounces": 0, "gold": gold, "shiny": cap.shiny,
				"reveal": GameState.capsule_seconds() * (1.25 if gold else 1.0) })
		if not Machine.lights_on(GameState.machine, Catalog.shared()):
			return
		# the lucky light that just came on (or all of them, flashing, for a lucky pull)
		var lit := int(GameState.machine.lit)
		var need := Machine.lights_needed(GameState.machine, Catalog.shared())
		_pips_pop.resize(need)
		if result.lucky:
			for i in need:
				_pips_pop[i] = 1.0
		elif lit > 0:
			_pips_pop[lit - 1] = 1.0
			Sfx.play(self, MachineTab._sound("light"), (lit - 1) * 12.0 / need)

	## Where chute `i` of `n` is along the front (design space).
	static func _chute_x(i: int, n: int) -> float:
		var gap := minf(70.0, 180.0 / n)
		return FLAP.x + (i - (n - 1) / 2.0) * gap

	func _pop(c: Dictionary) -> void:
		var result: Dictionary = c.result
		var prize: Dictionary = result.prize
		var loot: Dictionary = result.loot
		var at: Vector2 = c.pos
		Sfx.play(self, MachineTab._sound("pop"), _rng.randf_range(-1.0, 1.5))
		var colors := _colors()
		var burst := 22 if c.gold or c.shiny else 12
		for i in burst:
			var a := _rng.randf() * TAU
			var sp := _rng.randf_range(90.0, 260.0 if c.gold else 190.0)
			_bits.append({ "pos": at, "vel": Vector2(cos(a), sin(a) - 0.8) * sp, "rot": _rng.randf() * TAU,
				"color": UiTheme.GOLD if c.gold and i % 2 == 0 else colors[i % colors.size()], "t": 0.0, "life": _rng.randf_range(0.5, 0.9), "size": _rng.randf_range(4.0, 7.0) })
		var coins := int(loot.get("coins", 0))
		match str(prize.kind):
			"coins":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "+%s%s" % [UiTheme.num(coins), "  shiny!" if c.shiny else ""], "color": UiTheme.GOLD if c.shiny else UiTheme.CYAN, "t": 0.0, "size": 22 if c.fever or c.shiny else 18, "icon": true })
				_send_coins(at, coins)
				if _rng.randf() < 0.12:
					PetBubble.say_line(self, "machine_coins")
			"golden":
				_popup.show_prize(UiTheme.icon_rect("coin", 64, UiTheme.CYAN), "a golden capsule!", "%s coins!!" % UiTheme.num(coins), "", UiTheme.GOLD)
				_send_coins(at, coins)
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_golden")
			"xp":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "+%d xp" % int(loot.get("xp", 1)), "color": UiTheme.GOLD, "t": 0.0, "size": 18, "icon": false })
				Sfx.play(self, MachineTab._sound("light"), 7.0)
			"part":
				var key: String = loot.keys()[0]
				var bits := key.split(":")
				var part := Catalog.shared().part(bits[1], bits[2])
				var portrait := PetPortrait.new(3, false)
				portrait.set_pet(InventoryTab.part_preview(bits[1], bits[2]))
				_popup.show_prize(portrait, "a part!", "%s, %s" % [str(part.get("name", bits[2])), bits[1]], str(part.get("rarity", "common")), Catalog.shared().tier_color(str(part.get("rarity", "common"))))
				Sfx.play(self, MachineTab._sound("prize"), 2.0)
				PetBubble.say_line(self, "machine_part")
			"box":
				var box := TextureRect.new()
				var box_id := str(prize.get("box", "starter"))
				box.texture = PackArt.texture(Catalog.shared().box(box_id).get("art", {}), 56)
				box.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				_popup.show_prize(box, "a whole box!!", "it's on your pile", str(Catalog.shared().box(box_id).get("name", "")), UiTheme.PINK)
				Sfx.play(self, MachineTab._sound("jackpot"), -3.0)
				PetBubble.say_line(self, "machine_box")
			"toy":
				_show_toy(result.toy)
			"pet":
				_show_pet(result.pet)
			"pet_box":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "a box!!", "color": UiTheme.PINK, "t": 0.0, "size": 22, "icon": false })
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_pet_box")
				if result.pet:
					pet_box.emit(result.pet, str(prize.get("box", "starter")))
			"intel":
				_popup.show_prize(MapScrap.new(), "a scrap of a map!", "someone drew what's past the fence…", "intel", UiTheme.GOLD, true)
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_intel")
		if c.shiny and str(prize.kind) != "coins":
			PetBubble.say_line(self, "machine_shiny")

	## A pet out of the machine (the start of the game): its picture, big, and its name.
	func _show_pet(pet: Pet) -> void:
		if pet == null:
			return
		var portrait := PetPortrait.new(5, true)
		portrait.set_pet(pet)
		var second := GameState.collection.pets.size() >= 2
		_popup.show_prize(portrait, "%s!" % pet.display_name(Catalog.shared()), "and it's holding a scribbled map…" if second else "a pet came out of the machine!!", "new friend", UiTheme.PINK, true)
		Sfx.play(self, MachineTab._sound("jackpot"))
		PetBubble.say_line(self, "machine_pet_map" if second else "machine_pet")

	## A toy out of a capsule: its picture, big, with "new!" if it's one you didn't have.
	func _show_toy(toy: Dictionary) -> void:
		var catalog := Catalog.shared()
		var info := Toys.toy(catalog, toy.id)
		var fin := Toys.finish(catalog, toy.finish)
		var special: bool = toy.finish != "normal"
		var tier := str(info.get("tier", "common"))
		var color := UiTheme.LILAC if special else _tier_color(tier)
		var title := ("%s %s!" % [fin.name, info.name]) if special else "%s!" % info.name
		var owned: Dictionary = GameState.toys.owned.get(Toys.key(toy.id, toy.finish), {})
		var sub := "a new toy!" if toy.new else "one more for the workbench (%d spare)" % int(owned.get("spares", 0))
		_popup.show_prize(ToyView.new(toy.id, toy.finish, 7), title, sub, str(fin.name) if special else tier, color, toy.new)
		Sfx.play(self, MachineTab._sound("jackpot" if special or tier in ["rare", "secret"] else "prize"), 0.0 if special else 3.0)
		PetBubble.say_line(self, "machine_toy_new" if toy.new else "machine_toy")

	static func _tier_color(tier: String) -> Color:
		match tier:
			"uncommon": return Catalog.shared().tier_color("uncommon")
			"rare": return Catalog.shared().tier_color("rare")
			"secret": return Catalog.shared().tier_color("mythic")
		return Catalog.shared().tier_color("common")

	## A few coins fly from the capsule up to the counter; the counter counts as they land.
	func _send_coins(from_design: Vector2, amount: int) -> void:
		var n := clampi(amount, 1, 7)
		var each := float(amount) / n
		for i in n:
			_flying.append({ "from": _to_screen(from_design), "t": 0.0, "delay": i * 0.05, "amount": each,
				"bend": Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-90.0, -40.0)) })

	func _move_flying(delta: float) -> void:
		var landed: Array = []
		for f in _flying:
			if f.delay > 0.0:
				f.delay -= delta
				continue
			f.t += delta / 0.5
			if f.t >= 1.0:
				landed.append(f)
		for f in landed:
			_flying.erase(f)
			_shown_coins = minf(_shown_coins + f.amount, GameState.coins)
			_counter_pop = 1.0
			Sfx.play(self, MachineTab._sound("coin"), _rng.randf_range(0.0, 3.0))

	# ---- little physics ------------------------------------------------------------------

	func _nudge_balls(power: float) -> void:
		for b in _balls:
			b.vel += Vector2(_rng.randf_range(-power, power), _rng.randf_range(-power * 1.4, 0.0))

	func _move_balls(delta: float) -> void:
		for b in _balls:
			# each capsule is on a soft spring back to where it sits in the pile
			var acc: Vector2 = -b.off * 90.0 - b.vel * 7.0
			b.vel += acc * delta
			b.off += b.vel * delta
			b.off = b.off.limit_length(26.0)
			b.rot += b.spin * delta
			b.spin = move_toward(b.spin, 0.0, delta * 10.0)

	func _move_out(delta: float) -> void:
		var popped: Array = []
		for c in _out:
			c.t += delta
			c.vel.y += 1400.0 * delta
			c.pos += c.vel * delta
			c.rot += c.spin * delta
			if c.pos.y > REST_Y:
				c.pos.y = REST_Y
				if c.vel.y > 120.0:
					c.vel.y *= -0.42
					c.vel.x *= 0.7
					c.bounces += 1
					if c.bounces == 1:
						Sfx.play(self, MachineTab._sound("plonk"), _rng.randf_range(-1.0, 1.0))
				else:
					c.vel.y = 0.0
					c.vel.x *= 0.9
			c.pos.x = clampf(c.pos.x, 60.0, 460.0)
			if c.t > c.reveal:
				popped.append(c)
		for c in popped:
			_out.erase(c)
			_split(c)
			_pop(c)
		for h in _halves:
			h.t += delta
			h.vel.y += 1100.0 * delta
			h.pos += h.vel * delta
			h.rot += h.spin * delta
		_halves = _halves.filter(func(h): return h.t < 0.6)

	## The capsule breaks into its two halves: the top flies off, the bottom tips over.
	func _split(c: Dictionary) -> void:
		_halves.append({ "pos": c.pos, "vel": Vector2(_rng.randf_range(-80.0, 80.0), -420.0), "rot": c.rot, "spin": _rng.randf_range(-12.0, 12.0), "color": c.color, "top": true, "t": 0.0 })
		_halves.append({ "pos": c.pos, "vel": Vector2(_rng.randf_range(-40.0, 40.0), -120.0), "rot": c.rot, "spin": _rng.randf_range(-5.0, 5.0), "color": c.color, "top": false, "t": 0.0 })

	func _move_bits(delta: float) -> void:
		for b in _bits:
			b.t += delta
			b.vel.y += 700.0 * delta
			b.vel *= 0.985
			b.pos += b.vel * delta
			b.rot += delta * 9.0
		_bits = _bits.filter(func(b): return b.t < b.life)

	# ---- drawing -------------------------------------------------------------------------

	func _draw() -> void:
		var bg := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0)
		draw_style_box(bg, Rect2(Vector2.ZERO, size))
		var s := _scale()
		var o := _origin()
		# the floor, across the whole stage
		var floor_y := o.y + 400.0 * s
		var fl := StyleBoxFlat.new()
		fl.bg_color = UiTheme.PAGE
		fl.corner_radius_bottom_left = 12
		fl.corner_radius_bottom_right = 12
		draw_style_box(fl, Rect2(2, floor_y, size.x - 4, size.y - floor_y - 2))
		draw_line(Vector2(2, floor_y), Vector2(size.x - 2, floor_y), UiTheme.LILAC_SEAM, 3.0)

		draw_set_transform(o, 0.0, Vector2(s, s))
		_draw_rays()
		_ellipse(Vector2(210, 428), 190, 30, UiTheme.PAGE.lerp(UiTheme.LILAC, 0.12), UiTheme.LILAC_SEAM, true)
		# the machine squashes down a little on a clunk
		var squash := sin(_jolt * PI) * _jolt
		draw_set_transform(o + Vector2(0, 410.0 * s * squash * 0.025), 0.0, Vector2(s * (1.0 + squash * 0.015), s * (1.0 - squash * 0.025)))
		_draw_globe()
		_draw_body()
		var pulled_past := _pull > 0.5
		if not pulled_past:
			_draw_lever()
		_draw_flap()
		if pulled_past:
			_draw_lever()
		draw_set_transform(o, 0.0, Vector2(s, s))
		for c in _out:
			# the last part before it opens: it wobbles harder and harder, then puffs up
			var left: float = c.reveal - c.t
			var wob := 0.0
			var puff := 1.0
			if left < 0.55:
				var k := 1.0 - left / 0.55
				wob = sin(c.t * 38.0) * 0.35 * k
				puff = 1.0 + 0.12 * k * k
			if c.gold or c.shiny:
				draw_circle(c.pos, 34.0 * puff, Color(UiTheme.GOLD, 0.12 + 0.06 * sin(_time * 12.0)))
			if c.shiny:
				draw_sparkle(self, c.pos + Vector2(16, -18), 6.0 + 2.0 * sin(_time * 9.0), UiTheme.GOLD)
			draw_set_transform(o + c.pos * s, 0.0, Vector2(s, s) * puff)
			draw_capsule(self, Vector2.ZERO, 20.0, c.color, c.rot + wob)
			draw_set_transform(o, 0.0, Vector2(s, s))
		for h in _halves:
			var a: float = 1.0 - maxf(0.0, h.t - 0.3) / 0.3
			draw_set_transform(o + h.pos * s, h.rot, Vector2(s, s))
			_draw_half(20.0, h.color if h.top else UiTheme.TEXT.lerp(UiTheme.PAGE, 0.12), h.top, a)
			draw_set_transform(o, 0.0, Vector2(s, s))
		for b in _bits:
			var a: float = 1.0 - b.t / b.life
			draw_set_transform(o + b.pos * s, b.rot, Vector2(s, s))
			draw_rect(Rect2(Vector2(-b.size, -b.size) / 2.0, Vector2(b.size, b.size)), Color(b.color, a))
		draw_set_transform(o, 0.0, Vector2(s, s))
		if int(GameState.machine.pulls) == 0 and not _held and not GameState.tutorial_active():
			_draw_hint()
		for f in _floats:
			_draw_float(f)
		if _popup.visible:
			_draw_prize_rays()
		draw_set_transform(Vector2.ZERO)
		for f in _flying:
			if f.delay > 0.0:
				continue
			var t: float = f.t
			var to := _counter_at()
			var mid: Vector2 = (f.from + to) / 2.0 + f.bend
			var p: Vector2 = f.from.lerp(mid, t).lerp(mid.lerp(to, t), t)
			draw_texture_rect(UiTheme.icon("coin", 16, UiTheme.CYAN), Rect2(p - Vector2(8, 8), Vector2(16, 16)), false)
		_draw_counter()

	func _draw_rays() -> void:
		if _fever_level <= 0.0:
			return
		var c := GLOBE + Vector2(0, 60)
		for i in 12:
			var a := _time * 0.6 + TAU * i / 12.0
			var pts := PackedVector2Array([c, c + Vector2(cos(a - 0.09), sin(a - 0.09)) * 330.0, c + Vector2(cos(a + 0.09), sin(a + 0.09)) * 330.0])
			draw_colored_polygon(pts, Color(UiTheme.GOLD, 0.07 * _fever_level))

	func _draw_globe() -> void:
		var glass := UiTheme.PAGE.lerp(UiTheme.LILAC, 0.09)
		if _fever_level > 0.0:
			draw_circle(GLOBE, GLOBE_R + 14.0, Color(UiTheme.GOLD, 0.10 * _fever_level + 0.04 * sin(_time * 8.0) * _fever_level))
		draw_circle(GLOBE, GLOBE_R, glass)
		for b in _balls:
			draw_capsule(self, b.rest + b.off, 20.0, b.color, b.rot)
		# hides capsules poking out past the glass
		draw_arc(GLOBE, GLOBE_R + 13.0, 0, TAU, 72, UiTheme.PAPER, 26.0, true)
		if _fever_level > 0.0:
			draw_circle(GLOBE, GLOBE_R + 14.0, Color(UiTheme.GOLD, 0.10 * _fever_level))
		draw_arc(GLOBE, GLOBE_R, 0, TAU, 72, UiTheme.LILAC.lerp(UiTheme.GOLD, _fever_level), 3.5, true)
		var clear := _fixed("glass")
		var shine := Color(UiTheme.TEXT, 0.35 if clear else 0.15)
		draw_polyline(_quad(Vector2(126, 96), Vector2(140, 66), Vector2(172, 52), 12), shine, 4.0, true)
		draw_polyline(_quad(Vector2(112, 128), Vector2(113, 118), Vector2(116, 110), 6), shine, 4.0, true)
		if not clear:
			# old glass: cloudy, scratched, and cracked (taped up once you've fixed that)
			for h in [[Vector2(150, 110), 60.0], [Vector2(240, 170), 70.0], [Vector2(190, 210), 50.0]]:
				draw_circle(h[0], h[1], Color(UiTheme.TEXT, 0.06))
			for sc in [[Vector2(140, 150), Vector2(170, 138)], [Vector2(230, 90), Vector2(252, 102)], [Vector2(150, 200), Vector2(168, 206)]]:
				draw_line(sc[0], sc[1], Color(UiTheme.MUTED, 0.45), 1.5, true)
			var crack := PackedVector2Array([Vector2(262, 56), Vector2(252, 84), Vector2(266, 104), Vector2(254, 132), Vector2(270, 158)])
			draw_polyline(crack, Color(UiTheme.MUTED, 0.9), 2.5, true)
			draw_line(Vector2(252, 84), Vector2(238, 92), Color(UiTheme.MUTED, 0.7), 1.8, true)
			if _fixed("tape"):
				for y in [78.0, 122.0]:
					_tape(Vector2(260, y), -0.5)
		# the hatch on top: rusted shut until better drops opens it
		var hatch := _fixed("drops")
		_rounded(Rect2(160, 22, 80, 18), 7, UiTheme.PAGE.lerp(UiTheme.PINK, 0.4), UiTheme.PINK if hatch else UiTheme.PINK_SEAM, 3.0)
		if hatch:
			draw_circle(Vector2(200, 31), 6.0 + sin(_time * 4.0), Color(UiTheme.GOLD, 0.5))
		else:
			for x in [170.0, 230.0]:
				draw_circle(Vector2(x, 31), 3.0, RUST)
				draw_circle(Vector2(x, 31), 1.2, UiTheme.DEEP)

	const RUST := Color("8a6448")

	func _fixed(id: String) -> bool:
		return Machine.owned(GameState.machine, id) > 0

	## A strip of tape across the crack.
	func _tape(at: Vector2, angle: float) -> void:
		var d := Vector2(cos(angle), sin(angle))
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([at - d * 22 - n * 7, at + d * 22 - n * 7, at + d * 22 + n * 7, at - d * 22 + n * 7])
		draw_colored_polygon(pts, Color(UiTheme.GOLD.lerp(UiTheme.TEXT, 0.4), 0.75))
		draw_line(pts[1], pts[2], Color(UiTheme.GOLD, 0.6), 1.5)
		draw_line(pts[3], pts[0], Color(UiTheme.GOLD, 0.6), 1.5)

	func _draw_body() -> void:
		var trim := PackedVector2Array()
		trim.append_array(_quad(Vector2(82, 262), Vector2(200, 250), Vector2(318, 262), 14))
		trim.append(Vector2(318, 280))
		trim.append_array(_quad(Vector2(318, 280), Vector2(200, 270), Vector2(82, 280), 14))
		_poly(trim, UiTheme.PAGE.lerp(UiTheme.PINK, 0.4), UiTheme.PINK, 3.0)
		var body := PackedVector2Array()
		body.append_array(_quad(Vector2(92, 278), Vector2(200, 268), Vector2(308, 278), 14))
		body.append(Vector2(322, 408))
		body.append_array(_quad(Vector2(322, 408), Vector2(200, 418), Vector2(78, 408), 14))
		_poly(body, UiTheme.PAGE.lerp(UiTheme.PINK, 0.22), UiTheme.PINK, 3.5)
		# the lucky lights
		_rounded(Rect2(136, 294, 128, 30), 8, UiTheme.RAISED, UiTheme.GOLD, 2.5)
		var need := Machine.lights_needed(GameState.machine, Catalog.shared())
		var lit := int(GameState.machine.lit)
		if _pips_pop.size() != need:
			_pips_pop.resize(need)
		var w := 112.0 / need
		var r := minf(5.0, w / 2.0 - 1.5)
		var working := Machine.lights_on(GameState.machine, Catalog.shared())
		for i in need:
			var at := Vector2(144.0 + w * (i + 0.5), 309)
			if not working:
				# chewed wires: dead little bulbs until they're rewired
				draw_circle(at, r, UiTheme.DEEP)
				draw_arc(at, r, 0, TAU, 16, UiTheme.LINE, 1.8, true)
				continue
			var on := i < lit
			if _fever_level > 0.0:
				on = int(_time * 14.0) % need == i or int(_time * 14.0 + need / 2.0) % need == i
			var pop: float = _pips_pop[i]
			if on or pop > 0.0:
				draw_circle(at, r + 3.0 + pop * 5.0, Color(UiTheme.GOLD, 0.25 * maxf(pop, 0.5)))
			draw_circle(at, r * (1.0 + pop * 0.5), UiTheme.GOLD if on or pop > 0.0 else UiTheme.DEEP)
			draw_arc(at, r * (1.0 + pop * 0.5), 0, TAU, 16, UiTheme.GOLD, 1.8, true)
		if not working:
			# the chewed wire hanging off the lights
			draw_polyline(_quad(Vector2(262, 318), Vector2(282, 330), Vector2(272, 346), 8), UiTheme.MUTED, 2.0, true)
			draw_line(Vector2(272, 346), Vector2(268, 350), UiTheme.GOLD, 2.0, true)
			draw_line(Vector2(272, 346), Vector2(277, 350), UiTheme.GOLD, 2.0, true)
		if not _fixed("oil"):
			for r_at in [[Vector2(108, 300), 6.0], [Vector2(118, 312), 3.5], [Vector2(292, 388), 5.0], [Vector2(96, 392), 4.0], [Vector2(300, 296), 3.0]]:
				draw_circle(r_at[0], r_at[1], RUST)
		# the lever's mount on the side
		_rounded(Rect2(318, 306, 34, 46), 9, UiTheme.RAISED, UiTheme.GOLD if _fixed("oil") else RUST, 3.0)

	## One flap per chute along the front (bent-shut chutes aren't there until they're fixed).
	func _draw_flap() -> void:
		var n := Machine.chutes(GameState.machine, Catalog.shared())
		var half := minf(32.0, 180.0 / n / 2.0 - 3.0)
		for i in n:
			_draw_one_flap(_chute_x(i, n), half)
		if not _fixed("flap"):
			var x := _chute_x(0, n)
			draw_capsule(self, Vector2(x + 6, 388), 12.0, UiTheme.MINT, 0.6)
			draw_line(Vector2(x - half + 4, 360), Vector2(x + half - 6, 372), UiTheme.PINK_SEAM, 3.0, true)

	func _draw_one_flap(x: float, half: float) -> void:
		var slot := PackedVector2Array()
		slot.append_array(_quad(Vector2(x - half, 348), Vector2(x, 342), Vector2(x + half, 348), 8))
		slot.append(Vector2(x + half, 392))
		slot.append_array(_quad(Vector2(x + half, 392), Vector2(x, 396), Vector2(x - half, 392), 8))
		_poly(slot, UiTheme.DEEP, UiTheme.PINK_SEAM, 2.5)
		# the flap: hinged at the top, it swings up towards you as a capsule comes through (its
		# bottom edge rises and it catches the light)
		var open := sin(minf(_flap, 1.0) * PI * 0.5)
		var bottom := lerpf(388.0, 356.0, open)
		var lid := PackedVector2Array()
		var in_half := half - 3.0
		lid.append_array(_quad(Vector2(x - in_half, 353), Vector2(x, 347), Vector2(x + in_half, 353), 8))
		lid.append(Vector2(x + in_half + open * 5.0, bottom))
		lid.append_array(_quad(Vector2(x + in_half + open * 5.0, bottom), Vector2(x, bottom + 4.0), Vector2(x - in_half - open * 5.0, bottom), 8))
		draw_colored_polygon(lid, UiTheme.PAGE.lerp(UiTheme.PINK, lerpf(0.14, 0.34, open)))
		draw_line(Vector2(x - minf(10.0, half / 2.0), bottom - 5.0), Vector2(x + minf(10.0, half / 2.0), bottom - 5.0), UiTheme.PINK_SEAM, 2.5, true)
		draw_polyline(_quad(Vector2(x - in_half + 1.0, 354), Vector2(x, 348), Vector2(x + in_half - 1.0, 354), 8), UiTheme.PINK_SEAM, 2.0, true)

	func _draw_lever() -> void:
		var k: Array = _knob(_pull)
		var tip: Vector2 = k[0]
		var r: float = k[1]
		var near: float = k[2]
		# begs a little when it's been a while
		var beg := 0.0
		if _idle > 6.0 and not _held and _spring_t < 0.0:
			beg = maxf(0.0, sin(_time * 5.0)) * 2.5
		tip.y += beg
		draw_line(PIVOT, tip, UiTheme.GOLD, 9.0 * (1.0 + near * 0.5), true)
		draw_circle(PIVOT, 7.0, UiTheme.GOLD)
		draw_arc(PIVOT, 7.0, 0, TAU, 16, UiTheme.DEEP, 2.0, true)
		tip.x += sin(_time * 60.0) * 3.0 * _refused
		var waiting := not _out.is_empty() and not _held
		var knob := UiTheme.PINK.lerp(UiTheme.TEXT, 0.2 if (_hover or _held) and not waiting else 0.0)
		if waiting:
			knob = knob.lerp(UiTheme.PINK_SEAM, 0.55)
		if _hover and not _held and not waiting:
			draw_circle(tip, r + 6.0, Color(UiTheme.PINK, 0.15))
		draw_circle(tip + Vector2(0, r * 0.12), r, UiTheme.DEEP)
		draw_circle(tip, r, knob)
		draw_arc(tip, r, 0, TAU, 32, UiTheme.DEEP, 2.5, true)
		draw_circle(tip - Vector2(r, r) * 0.35, r * 0.26, Color(UiTheme.TEXT, 0.55))

	## Half a capsule, open side down (top) or up (bottom), centred on the origin.
	func _draw_half(r: float, color: Color, top: bool, alpha: float) -> void:
		var pts := PackedVector2Array()
		for i in 17:
			var ang := (PI + PI * i / 16.0) if top else (PI * i / 16.0)
			pts.append(Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, Color(color, alpha))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(UiTheme.DEEP, alpha), 2.0, true)

	func _draw_hint() -> void:
		var font := UiTheme.DISPLAY_FONT
		var bob := sin(_time * 4.0) * 5.0
		draw_string(font, Vector2(368, 222), "pull me!", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PINK)
		var x := 392.0
		var y0 := 234.0 + bob
		draw_line(Vector2(x, y0), Vector2(x, y0 + 38), UiTheme.PINK, 2.5, true)
		draw_polyline(PackedVector2Array([Vector2(x - 10, y0 + 28), Vector2(x, y0 + 40), Vector2(x + 10, y0 + 28)]), UiTheme.PINK, 2.5, true)

	func _draw_float(f: Dictionary) -> void:
		var t: float = f.t
		var p: Vector2 = f.pos + Vector2(0, -40.0 * (1.0 - pow(1.0 - t, 3.0)))
		var a := 1.0 if t < 0.6 else (1.0 - t) / 0.4
		var font := UiTheme.DISPLAY_FONT
		var sz: int = f.size
		var w := font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var left := p.x - (w + (18.0 if f.icon else 0.0)) / 2.0
		draw_string_outline(font, Vector2(left, p.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(UiTheme.DEEP, a))
		draw_string(font, Vector2(left, p.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(f.color, a))
		if f.icon:
			draw_texture_rect(UiTheme.icon("coin", 16, UiTheme.CYAN), Rect2(Vector2(left + w + 3.0, p.y - 14.0), Vector2(16, 16)), false, Color(1, 1, 1, a))

	## Soft rays turning behind a good prize.
	func _draw_prize_rays() -> void:
		var c := GLOBE + Vector2(0, 30)
		var col := Color(_popup.color, 0.14 * _popup.modulate.a)
		for i in 14:
			var a := _time * 0.8 + TAU * i / 14.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - 0.1), sin(a - 0.1)) * 170.0, c + Vector2(cos(a + 0.1), sin(a + 0.1)) * 170.0]), col)

	func _draw_counter() -> void:
		var at := _counter_at()
		var pop := sin(_counter_pop * PI) * _counter_pop
		var font := UiTheme.DISPLAY_FONT
		var sz := int(26.0 * (1.0 + pop * 0.12))
		draw_texture_rect(UiTheme.icon("coin", 22, UiTheme.CYAN), Rect2(at + Vector2(-16, -12 - pop * 2.0), Vector2(22, 22)), false)
		draw_string(font, at + Vector2(12, 8), UiTheme.num(_shown_coins), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, UiTheme.TEXT.lerp(UiTheme.CYAN, pop * 0.6))
		var per := Machine.coin_value(GameState.machine, Catalog.shared()) * GameState.toy_boost("coins")
		var chutes := Machine.chutes(GameState.machine, Catalog.shared())
		var line := "%s coin%s a capsule%s" % [UiTheme.num(per), "" if per < 1.5 else "s", ", %d chutes" % chutes if chutes > 1 else ""]
		var left := GameState.fever_left()
		if left > 0.0:
			line = "fever! every capsule x%d for %d more seconds" % [int(Catalog.shared().machine.fever_pay), ceili(left)]
		draw_string(UiTheme.BODY_FONT, at + Vector2(-16, 30), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.GOLD if left > 0.0 else UiTheme.MUTED)

	# ---- drawing helpers ------------------------------------------------------------------

	## A two-tone capsule: a coloured top half and a cream bottom, with a shine.
	static func draw_capsule(ci: CanvasItem, at: Vector2, r: float, color: Color, rot: float) -> void:
		ci.draw_circle(at, r, UiTheme.TEXT.lerp(UiTheme.PAGE, 0.12))
		var half := PackedVector2Array()
		for i in 17:
			var a := rot + PI + PI * i / 16.0
			half.append(at + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(half, color)
		ci.draw_line(half[0], half[16], UiTheme.DEEP, 2.0, true)
		ci.draw_arc(at, r, 0, TAU, 28, UiTheme.DEEP, 2.0, true)
		ci.draw_arc(at, r * 0.62, rot + PI * 1.15, rot + PI * 1.55, 8, Color(UiTheme.TEXT, 0.6), 2.2, true)

	static func draw_sparkle(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI / 2.0
			pts.append(at + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.3))
		ci.draw_colored_polygon(pts, color)

	func _quad(a: Vector2, c: Vector2, b: Vector2, steps: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in steps + 1:
			var t := float(i) / steps
			pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
		return pts

	func _poly(pts: PackedVector2Array, fill: Color, line: Color, width: float) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, width, true)

	func _rounded(rect: Rect2, radius: int, fill: Color, line: Color, width: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = line
		sb.set_border_width_all(int(round(width)))
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		draw_style_box(sb, rect)

	func _ellipse(c: Vector2, rx: float, ry: float, fill: Color, line: Color, dashed: bool) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts.slice(0, 48), fill)
		if dashed:
			for i in 48:
				if i % 2 == 0:
					draw_line(pts[i], pts[i + 1], line, 2.5, true)
		else:
			draw_polyline(pts, line, 2.5, true)


## A good prize out of the machine, as a picture: a card over the globe with the thing itself (a
## toy, a part, a box, the xp star, a golden coin), its name, a line under it, and a coloured tag.
## "new!" on a toy you didn't have. Pops in, stays a moment, fades.
class PrizePopup extends PanelContainer:
	var color := UiTheme.PINK
	var _col := VBoxContainer.new()
	var _holder := CenterContainer.new()
	var _title := Label.new()
	var _sub := Label.new()
	var _tag := PanelContainer.new()
	var _tag_label := Label.new()
	var _new := Label.new()
	var _tween: Tween

	func _init() -> void:
		visible = false
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(200, 0)
		_col.alignment = BoxContainer.ALIGNMENT_CENTER
		_col.add_theme_constant_override("separation", 4)
		add_child(_col)
		_holder.custom_minimum_size = Vector2(0, 104)
		_col.add_child(_holder)
		_title.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		_title.add_theme_font_size_override("font_size", 20)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_title)
		_sub.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		_sub.add_theme_color_override("font_color", UiTheme.MUTED)
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_sub)
		_tag.size_flags_horizontal = SIZE_SHRINK_CENTER
		_tag_label.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		_tag_label.add_theme_color_override("font_color", UiTheme.DEEP)
		_tag.add_child(_tag_label)
		_col.add_child(_tag)
		_new.text = "new!"
		_new.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		_new.add_theme_font_size_override("font_size", 15)
		_new.add_theme_color_override("font_color", UiTheme.DEEP)
		var sticker := UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 8, 0, 0)
		sticker.content_margin_left = 9
		sticker.content_margin_right = 9
		sticker.content_margin_top = 3
		sticker.content_margin_bottom = 3
		_new.add_theme_stylebox_override("normal", sticker)
		_new.rotation_degrees = 10.0
		_new.top_level = false
		add_child(_new)
		for c in [_col, _holder, _title, _sub, _tag, _tag_label, _new]:
			c.mouse_filter = MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			_new.position = Vector2(size.x - _new.size.x + 12, -12)

	func show_prize(picture: Control, title: String, sub: String, tag: String, tint: Color, is_new := false) -> void:
		color = tint
		for old in _holder.get_children():
			old.queue_free()
		picture.mouse_filter = MOUSE_FILTER_IGNORE
		_holder.add_child(picture)
		_title.text = title
		_title.add_theme_color_override("font_color", tint)
		_sub.text = sub
		_sub.visible = sub != ""
		_tag.visible = tag != ""
		_tag_label.text = tag
		var tag_box := UiTheme.box(tint, tint, 9, 0, 0)
		tag_box.content_margin_left = 10
		tag_box.content_margin_right = 10
		tag_box.content_margin_top = 1
		tag_box.content_margin_bottom = 1
		_tag.add_theme_stylebox_override("panel", tag_box)
		_new.visible = is_new
		var card := UiTheme.box(UiTheme.RAISED, tint, 16, 3, 14)
		card.shadow_color = Color(tint, 0.18)
		card.shadow_size = 10
		add_theme_stylebox_override("panel", card)
		visible = true
		reset_size()
		pivot_offset = size / 2.0
		rotation_degrees = -2.0
		if _tween:
			_tween.kill()
		scale = Vector2(0.5, 0.5)
		modulate.a = 0.0
		_tween = create_tween()
		_tween.set_parallel()
		_tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, 0.15)
		_tween.chain().tween_interval(2.6 if is_new else 2.0)
		_tween.chain().tween_property(self, "modulate:a", 0.0, 0.4)
		_tween.chain().tween_callback(func(): visible = false)


## A torn scrap of paper with a crayon map on it: the fence, a gate, and places past it with a "?"
## (the intel that comes out of the machine, opening the next map page).
class MapScrap extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(120, 96)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var paper := PackedVector2Array([Vector2(8, 10), Vector2(40, 4), Vector2(72, 12), Vector2(110, 6), Vector2(114, 40),
			Vector2(108, 70), Vector2(112, 90), Vector2(70, 86), Vector2(44, 92), Vector2(10, 86), Vector2(14, 50)])
		draw_colored_polygon(paper, UiTheme.RAISED.lerp(UiTheme.GOLD, 0.18))
		var edge := paper.duplicate()
		edge.append(paper[0])
		draw_polyline(edge, UiTheme.GOLD, 2.0, true)
		# the fence, with a gate in it
		for x in range(18, 104, 9):
			if x > 52 and x < 70:
				continue
			draw_line(Vector2(x, 70), Vector2(x, 58), UiTheme.MUTED, 2.0, true)
		draw_line(Vector2(16, 64), Vector2(52, 64), UiTheme.MUTED, 2.0, true)
		draw_line(Vector2(70, 64), Vector2(106, 64), UiTheme.MUTED, 2.0, true)
		# a dotted path out through the gate, to places with question marks
		for i in 6:
			draw_circle(Vector2(61, 78) + Vector2(i * 4, -i * 9), 1.6, UiTheme.PINK)
		draw_arc(Vector2(84, 26), 9.0, 0, TAU, 20, UiTheme.MINT, 2.0, true)
		draw_arc(Vector2(34, 30), 7.0, 0, TAU, 20, UiTheme.LILAC, 2.0, true)
		draw_string(UiTheme.DISPLAY_FONT, Vector2(80, 31), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.MINT)
		draw_string(UiTheme.DISPLAY_FONT, Vector2(30, 35), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.LILAC)
