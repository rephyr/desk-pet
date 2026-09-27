class_name TrailView
extends Control
## A hands-on trip up close: your pet walking the path of the place, as a crayon strip. Click
## anywhere to hurry it along (each hop takes a few seconds off the walk). Things turn up on the
## path as it goes (coins, xp sparkles, a leaf that heals a sore paw, now and then a sparkle with
## a part): click them before they pass. Grabbing several in a row builds a streak that makes them
## worth more. A part stops the pet: it holds the part up and a card asks to keep it or leave it. At an event the pet stops and the choices wait on its trip card. Walking on its
## own still gets there; clicking is the fast, rewarding way.

signal back_to_map
signal welcome_back(run: RunState)  # autoplay only: the trip is home, collect it

const PX_PER_SECOND := 36.0  # scenery moved per second of walking
const PET_X := 0.28  # where the pet walks, as a share of the width
const PICKUP_GAP := [150.0, 260.0]  # px of path between things to grab
const PICKUP_WEIGHTS := { "coins": 60, "xp": 28, "heal": 8, "part": 4 }
const HIT := 26.0
const STREAK_MAX := 1.5  # most a streak multiplies what you grab
var COLORS := { "coins": UiTheme.CYAN, "xp": UiTheme.GOLD, "heal": UiTheme.MINT, "part": UiTheme.PINK }

var run: RunState
var view := PetView.new()
var _back := UiTheme.button("‹ map")
var _title_font: Font = UiTheme.DISPLAY_FONT
var _coin_icon := UiTheme.icon("coin", 14)
var _xp_icon := UiTheme.icon("xp", 14)
var _note_font: Font = UiTheme.BODY_FONT
var _shown_x := -1.0  # world x drawn now, easing toward where the pet really is
var _pickups: Array[Dictionary] = []  # { x, kind, gone }
var _next_pickup := 0.0
var _streak := 0
var _xp_grabbed := 0  # xp sparkles grabbed on this trip (they go straight to you, not the bag)
var _floaters: Array[Dictionary] = []  # { text, at, age, color }
var _hop := 0.0
var _dust := 0.0
var _rng := RandomNumberGenerator.new()
var _found: PartFoundCard = null  # the card for a part the pet just picked up, while you decide
var _held := PetView.new()  # that part, held up over the pet's head
var _held_color := UiTheme.PINK
## Debug: clicks along by itself (for testing and screenshots), see DevArgs --autoplay.
var autoplay := DevArgs.has("autoplay")
## Debug: every thing on the path is this kind, e.g. --pickup=part (see DevArgs).
var forced_pickup := DevArgs.value("pickup")
var _auto_wait := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_rng.randomize()
	view.pixel = 5
	add_child(view)
	_held.pixel = 3
	_held.animated = false
	_held.visible = false
	add_child(_held)
	_back.add_theme_font_size_override("font_size", UiTheme.SMALL)
	_back.pressed.connect(func(): back_to_map.emit())
	add_child(_back)


## Starts showing a trip (a fresh path of things to grab).
func show_run(r: RunState) -> void:
	if r == run:
		return
	if _found:
		_close_found(true)  # switching trips never loses a part: it's kept
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
	# while a part's card is open the pet stands still with it (the trip itself keeps going)
	var walking := run.status == RunState.Status.WALKING and _found == null
	if _found == null:
		_shown_x = lerpf(_shown_x, target, clampf(delta * 8.0, 0.0, 1.0))
	view.walking = walking
	view.visible = run.party.size() > 0  # nobody left on the path
	view.facing = 1
	# new things to grab ahead, while walking
	while walking and _next_pickup < _shown_x + size.x:
		_pickups.append({ "x": _next_pickup, "kind": forced_pickup if forced_pickup != "" else Weighted.pick(PICKUP_WEIGHTS, _rng), "gone": false })
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
	if _found:
		_place_found()
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
	if _found:
		return  # decide on the part first
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
	if run.status == RunState.Status.DONE:
		welcome_back.emit(run)
		return
	if _found:
		_close_found(true)
		return
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
		text = "+%d coins" % got.coins
	elif got.has("xp"):
		text = "+%d xp" % got.xp
		_xp_grabbed += int(got.xp)
	elif got.has("heal"):
		text = "feels better!" if int(got.heal) > 0 else "a nice leaf!"
	elif got.has("part"):
		_show_found(got.part)
		return
	_floaters.append({ "text": text, "at": at, "age": 0.0, "color": COLORS.get(p.kind, UiTheme.TEXT) })
	view.squash = 0.4


# ---- a part found ---------------------------------------------------------------

func _show_found(key: String) -> void:
	var bits := key.split(":")  # part, slot, id
	var catalog := Catalog.shared()
	_held.pet = InventoryTab.part_preview(bits[1], bits[2])
	_held.visible = true
	_held_color = catalog.tier_color(catalog.part(bits[1], bits[2]).rarity)
	var trip := view.pet.display_name(catalog) if view.pet else "your pet"
	PetBubble.say_line(self, "trail_part", { "trip": trip })
	_found = PartFoundCard.new(key, PetBubble.line("trail_part_quote", { "trip": trip }))
	_found.picked.connect(_close_found)
	add_child(_found)
	_place_found()
	view.squash = 0.4
	if autoplay:
		_auto_wait = 2.5  # long enough to see it


func _close_found(keep: bool) -> void:
	if keep:
		GameState.keep_trail_part(run, _found.key)
	PetBubble.say_line(self, "trail_part_kept" if keep else "trail_part_left")
	_found.queue_free()
	_found = null
	_held.visible = false
	# the pet catches up on the walk: what it passed while standing still is gone, but that's
	# not a miss, so the streak stays
	var target := _world_x()
	for p in _pickups:
		if not p.gone and _pet_x() + (p.x - target) < _pet_x() - 40.0:
			p.gone = true


## The part over the pet's head, bobbing, and its card beside it pointing at it.
func _place_found() -> void:
	var bob := sin(Time.get_ticks_msec() * 0.006) * 3.0
	_held.position = view.position + Vector2(0.0, -PetView.size_for(view.pixel).y - 6.0 + bob)
	var card := _found.get_combined_minimum_size()
	_found.size = card
	var at := _held_centre() + Vector2(48.0, -PartFoundCard.TAIL_Y)
	_found.position = Vector2(minf(at.x, size.x - card.x - 12.0), clampf(at.y, 12.0, size.y - card.y - 12.0))


func _held_centre() -> Vector2:
	return _held.position - Vector2(0.0, PetView.size_for(_held.pixel).y / 2.0)


# ---- drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))
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
	if _found:
		_draw_held_glow()
	if _dust > 0.0:
		for i in 4:
			draw_circle(Vector2(_pet_x() - 14.0 - i * 7.0, ground + 2.0), 3.0 * _dust, Color(UiTheme.LILAC, 0.5 * _dust))
	# what's going on
	draw_string(_title_font, Vector2(16, 34), location.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.PINK)
	# progress pips, then what's in the bag and the xp so far
	var x := 20.0
	for i in run.events.size():
		var done := i < run.step
		draw_circle(Vector2(x, 52), 5.0, UiTheme.PINK if done else Color(0, 0, 0, 0))
		draw_arc(Vector2(x, 52), 5.0, 0.0, TAU, 16, UiTheme.PINK if done else UiTheme.PINK_SEAM, 2.0, true)
		x += 15.0
	x += 8.0
	var bag := "%d in the bag" % Rewards.total(run.loot, "coins")
	draw_texture_rect(_coin_icon, Rect2(x, 45, 14, 14), false)
	draw_string(_note_font, Vector2(x + 18, 57), bag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.CYAN)
	x += 30.0 + _note_font.get_string_size(bag, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_texture_rect(_xp_icon, Rect2(x, 45, 14, 14), false)
	draw_string(_note_font, Vector2(x + 18, 57), "%d xp" % (run.xp + _xp_grabbed), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.GOLD)
	var hint := ""
	match run.status:
		RunState.Status.WALKING:
			hint = "click to hurry!  grab things on the path"
		RunState.Status.WAITING:
			hint = "something's up! pick what to do on the adventure card"
		RunState.Status.DONE:
			hint = "back home! say welcome back" if run.party.size() > 0 else "the adventure is over. say welcome back"
	draw_string(_note_font, Vector2(16, size.y - 18.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.LILAC)
	if run.status == RunState.Status.WAITING:
		draw_string(_title_font, Vector2(_pet_x() + 22.0, ground - 90.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiTheme.PINK)
	if _streak >= 2:
		draw_set_transform(Vector2(18, 90), deg_to_rad(-3.0))
		draw_string(_title_font, Vector2.ZERO, "streak ×%d!" % _streak, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiTheme.GOLD)
		draw_set_transform(Vector2.ZERO)
	for f in _floaters:
		var c: Color = f.color
		c.a = 1.0 - f.age / 1.2
		draw_string(_note_font, f.at + Vector2(-20.0, -70.0 - f.age * 30.0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, c)


## Two layers of doodles that scroll by: far away slowly, close up at walking speed.
func _draw_scenery(doodle: String) -> void:
	var ground := _ground()
	var far := Color(UiTheme.LILAC, 0.18)
	var near := Color(UiTheme.MINT, 0.45)
	if doodle in ["pond", "stream"]:
		near = Color(UiTheme.CYAN, 0.45)
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


## A soft glow in the part's rarity colour behind the part the pet holds up, and a few twinkles.
func _draw_held_glow() -> void:
	var at := _held_centre()
	var t := Time.get_ticks_msec() * 0.001
	for i in 4:
		draw_circle(at, 34.0 - i * 7.0 + sin(t * 3.0) * 2.0, Color(_held_color, 0.08 + i * 0.03))
	for s in [[Vector2(-30, -8), 0.0, 5.0], [Vector2(32, 4), 1.3, 5.0], [Vector2(18, -28), 2.4, 3.5]]:
		var twinkle := 0.35 + 0.65 * absf(sin(t * 2.5 + s[1]))
		var c := Color(UiTheme.GOLD, twinkle)
		var p: Vector2 = at + s[0]
		var r: float = s[2] * twinkle
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r * 2.0), p + Vector2(r * 0.4, -r * 0.4), p + Vector2(r * 2.0, 0), p + Vector2(r * 0.4, r * 0.4), p + Vector2(0, r * 2.0), p + Vector2(-r * 0.4, r * 0.4), p + Vector2(-r * 2.0, 0), p + Vector2(-r * 0.4, -r * 0.4)]), c)


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
