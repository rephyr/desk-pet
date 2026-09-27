class_name TrailView
extends Control
## A hands-on trip up close: your pet walking the path of the place, as a crayon strip. Click
## anywhere to hurry it along (each hop takes a few seconds off the walk). Things turn up on the
## path as it goes (coins, xp sparkles, a leaf that heals a sore paw, now and then a sparkle with
## a part): click them before they pass. Grabbing several in a row builds a streak that makes them
## worth more. At an event the pet stops and the choices wait on its trip card. Walking on its
## own still gets there; clicking is the fast, rewarding way.

signal back_to_map

const PX_PER_SECOND := 36.0  # scenery moved per second of walking
const PET_X := 0.28  # where the pet walks, as a share of the width
const PICKUP_GAP := [150.0, 260.0]  # px of path between things to grab
const PICKUP_WEIGHTS := { "coins": 60, "xp": 28, "heal": 8, "part": 4 }
const HIT := 26.0
const STREAK_MAX := 1.5  # most a streak multiplies what you grab
const PAPER := Color("1b1324")
const COLORS := { "coins": UiTheme.CYAN, "xp": Color("ffe08a"), "heal": Color("8fe8c0"), "part": UiTheme.PINK }

var run: RunState
var view := PetView.new()
var _back := UiTheme.button("‹ map")
var _title_font := SystemFont.new()
var _note_font := SystemFont.new()
var _shown_x := -1.0  # world x drawn now, easing toward where the pet really is
var _pickups: Array[Dictionary] = []  # { x, kind, gone }
var _next_pickup := 0.0
var _streak := 0
var _xp_grabbed := 0  # xp sparkles grabbed on this trip (they go straight to you, not the bag)
var _floaters: Array[Dictionary] = []  # { text, at, age, color }
var _hop := 0.0
var _dust := 0.0
var _rng := RandomNumberGenerator.new()
## Debug: clicks along by itself (for testing and screenshots), see DevArgs --autoplay.
var autoplay := DevArgs.has("autoplay")
var _auto_wait := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()
	_title_font.font_names = PackedStringArray(["Coiny", "Maple Mono"])
	_note_font.font_names = PackedStringArray(["Maple Mono", "monospace"])
	view.pixel = 5
	add_child(view)
	_back.add_theme_font_size_override("font_size", UiTheme.SMALL)
	_back.pressed.connect(func(): back_to_map.emit())
	add_child(_back)


## Starts showing a trip (a fresh path of things to grab).
func show_run(r: RunState) -> void:
	if r == run:
		return
	run = r
	_pickups.clear()
	_shown_x = -1.0
	_streak = 0
	_xp_grabbed = 0
	_floaters.clear()
	view.pet = GameState.collection.get_pet(r.party.uids[0]) if r and not r.party.uids.is_empty() else null


func _world_x() -> float:
	var location := Catalog.shared().location(run.location_id)
	var gap := AdventureRunner.gap(location, run.party, run.events.size())
	var elapsed := gap
	if run.status == RunState.Status.WALKING:
		elapsed = clampf(gap - (run.next_at - Time.get_unix_time_from_system()), 0.0, gap)
	return (run.step * gap + elapsed) * PX_PER_SECOND


func _pet_x() -> float:
	return size.x * PET_X


func _ground() -> float:
	return size.y * 0.72


func _process(delta: float) -> void:
	if run == null or not is_visible_in_tree():
		return
	var target := _world_x()
	if _shown_x < 0.0:
		_shown_x = target
		_next_pickup = target + 120.0
	var walking := run.status == RunState.Status.WALKING
	_shown_x = lerpf(_shown_x, target, clampf(delta * 8.0, 0.0, 1.0))
	view.walking = walking
	view.facing = 1
	# new things to grab ahead, while walking
	while walking and _next_pickup < _shown_x + size.x:
		_pickups.append({ "x": _next_pickup, "kind": Weighted.pick(PICKUP_WEIGHTS, _rng), "gone": false })
		_next_pickup += _rng.randf_range(PICKUP_GAP[0], PICKUP_GAP[1])
	# things that slipped past the pet are missed (and break the streak)
	for p in _pickups:
		if not p.gone and _screen_x(p.x) < _pet_x() - 40.0:
			p.gone = true
			_streak = 0
	_pickups = _pickups.filter(func(p): return not p.gone or _screen_x(p.x) > -40.0)
	_hop = move_toward(_hop, 0.0, delta * 3.5)
	_dust = move_toward(_dust, 0.0, delta * 3.0)
	for f in _floaters:
		f.age += delta
	_floaters = _floaters.filter(func(f): return f.age < 1.2)
	if autoplay:
		_autoplay(delta, walking)
	view.position = Vector2(roundf(_pet_x()), _ground() - roundf(sin(_hop * PI) * 18.0))
	_back.position = Vector2(size.x - _back.size.x - 12.0, 12.0)
	queue_redraw()


func _screen_x(world_x: float) -> float:
	return _pet_x() + (world_x - _shown_x)


func _pickup_at(p: Dictionary) -> Vector2:
	return Vector2(_screen_x(p.x), _ground() - 14.0 - 10.0 * sin(p.x * 0.05))


# ---- clicking -------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if run == null or not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	# grab something if it was clicked
	for p in _pickups:
		if not p.gone and _pickup_at(p).distance_to(event.position) <= HIT:
			_grab(p)
			return
	if run.status == RunState.Status.WALKING:
		GameState.hurry(run)
		_hop = 1.0
		_dust = 1.0
		view.squash = 0.35


func _autoplay(delta: float, walking: bool) -> void:
	_auto_wait -= delta
	if _auto_wait > 0.0:
		return
	_auto_wait = 0.4
	if run.status == RunState.Status.WAITING:
		GameState.answer_event(run, AdventureRunner.allowed_options(run.current_event(Catalog.shared()), run.party, Catalog.shared().location(run.location_id))[0])
		_auto_wait = 1.5
		return
	for p in _pickups:
		if not p.gone and _screen_x(p.x) < _pet_x() + 60.0:
			_grab(p)
			return
	if walking:
		GameState.hurry(run)
		_hop = 1.0
		_dust = 1.0
		view.squash = 0.35


func _grab(p: Dictionary) -> void:
	p.gone = true
	_streak += 1
	var got := GameState.trail_pickup(run, p.kind, minf(1.0 + 0.1 * (_streak - 1), STREAK_MAX))
	var at := _pickup_at(p)
	var text := ""
	if got.has("coins"):
		text = "+◆%d" % got.coins
	elif got.has("xp"):
		text = "+%d xp" % got.xp
		_xp_grabbed += int(got.xp)
	elif got.has("heal"):
		text = "feels better!" if int(got.heal) > 0 else "a nice leaf!"
	elif got.has("part"):
		text = "a part!!"
	if _streak >= 3:
		text += "  streak x%d!" % _streak
	_floaters.append({ "text": text, "at": at, "age": 0.0, "color": COLORS.get(p.kind, UiTheme.TEXT) })
	view.squash = 0.4


# ---- drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	if run == null:
		return
	var catalog := Catalog.shared()
	var location := catalog.location(run.location_id)
	_draw_scenery(str(location.get("map", {}).get("doodle", "grass")))
	# the path
	var ground := _ground()
	var path := PackedVector2Array()
	for i in 41:
		var x := size.x * i / 40.0
		path.append(Vector2(x, ground + 4.0 + sin((x + _shown_x) * 0.03) * 2.0))
	draw_polyline(path, Color(UiTheme.PINK, 0.35), 3.0, true)
	for p in _pickups:
		if not p.gone:
			_draw_pickup(p.kind, _pickup_at(p))
	if _dust > 0.0:
		for i in 4:
			draw_circle(Vector2(_pet_x() - 14.0 - i * 7.0, ground + 2.0), 3.0 * _dust, Color(UiTheme.LILAC, 0.5 * _dust))
	# what's going on
	draw_string(_title_font, Vector2(16, 34), location.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.PINK)
	var dots := ""
	for i in run.events.size():
		dots += "●" if i < run.step else "○"
	var bag := Rewards.total(run.loot, "coins")
	draw_string(_note_font, Vector2(16, 56), "%s   bag ◆%d   +%d xp" % [dots, bag, run.xp + _xp_grabbed], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.MUTED)
	var hint := ""
	match run.status:
		RunState.Status.WALKING:
			hint = "click to hurry!  grab things on the path"
		RunState.Status.WAITING:
			hint = "something's up! pick what to do on the trip card →"
		RunState.Status.DONE:
			hint = "back home! say welcome back →"
	draw_string(_note_font, Vector2(16, size.y - 18.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.LILAC)
	if run.status == RunState.Status.WAITING:
		draw_string(_title_font, Vector2(_pet_x() + 22.0, ground - 90.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.PINK)
	if _streak >= 2:
		draw_string(_title_font, Vector2(16, 84), "streak x%d" % _streak, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ffe08a"))
	for f in _floaters:
		var c: Color = f.color
		c.a = 1.0 - f.age / 1.2
		draw_string(_note_font, f.at + Vector2(-20.0, -70.0 - f.age * 30.0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)


## Two layers of doodles that scroll by: far away slowly, close up at walking speed.
func _draw_scenery(doodle: String) -> void:
	var ground := _ground()
	var far := Color(UiTheme.LILAC, 0.18)
	var near := Color("8fe8c0", 0.45)
	if doodle in ["pond", "stream"]:
		near = Color("8cc8ff", 0.45)
	elif doodle in ["hut", "well", "door", "stairs"]:
		near = Color(UiTheme.LILAC, 0.45)
	# far: hills or trees, drifting slowly
	var step := 160.0
	var start := floorf(_shown_x * 0.4 / step) - 1.0
	for i in range(int(start), int(start) + int(size.x / step) + 3):
		var x := i * step - _shown_x * 0.4
		var h := 30.0 + float(hash(i) % 40)
		if doodle in ["trees", "grass", "house", "apple"]:
			draw_colored_polygon(PackedVector2Array([Vector2(x - 26, ground - 20), Vector2(x, ground - 20 - h), Vector2(x + 26, ground - 20)]), far)
		else:
			draw_arc(Vector2(x, ground - 10), 50.0, PI, TAU, 16, far, 2.0)
	# near: tufts, flowers, reeds
	step = 70.0
	start = floorf(_shown_x / step) - 1.0
	for i in range(int(start), int(start) + int(size.x / step) + 3):
		var x := i * step - _shown_x + float(hash(i * 7) % 30)
		match hash(i) % 3:
			0:
				draw_polyline(PackedVector2Array([Vector2(x, ground), Vector2(x + 4, ground - 12), Vector2(x + 8, ground)]), near, 2.0)
			1:
				draw_circle(Vector2(x, ground - 8), 4.0, Color(UiTheme.PINK, 0.4))
				draw_line(Vector2(x, ground - 4), Vector2(x, ground), near, 2.0)
			_:
				draw_line(Vector2(x, ground), Vector2(x - 3, ground - 16), near, 2.0)
				draw_line(Vector2(x + 4, ground), Vector2(x + 6, ground - 12), near, 2.0)


func _draw_pickup(kind: String, at: Vector2) -> void:
	var c: Color = COLORS.get(kind, UiTheme.TEXT)
	match kind:
		"coins":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(0, 8), at + Vector2(-7, 0)]), c)
		"xp":
			for a in [0.0, PI / 2.0]:
				draw_line(at + Vector2(cos(a), sin(a)) * 9.0, at - Vector2(cos(a), sin(a)) * 9.0, c, 2.5)
			draw_circle(at, 3.0, c)
		"heal":
			draw_colored_polygon(PackedVector2Array([at + Vector2(-8, 4), at + Vector2(0, -8), at + Vector2(8, 4), at + Vector2(0, 7)]), c)
		"part":
			var glow := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
			draw_circle(at, 12.0 + glow * 3.0, Color(c, 0.2))
			for a in [0.0, PI / 4.0, PI / 2.0, 3.0 * PI / 4.0]:
				draw_line(at + Vector2(cos(a), sin(a)) * 10.0, at - Vector2(cos(a), sin(a)) * 10.0, c, 2.0)
