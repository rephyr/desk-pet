class_name MapView
extends Control
## The adventure map: your active pet's crayon drawing of the world, on dark paper. Places you
## can go are doodled in with the pet's little notes; places a pet spotted are faded in, waiting
## for you to say yes (some only later, see "wait_minutes"); unexplored directions are ? clouds.
## Pets out on trips walk along as tiny doodles. Everything comes from data/adventures.json
## ("map" on each location), and the drawing zooms to fit whatever has been found so far.

signal place_picked(location_id: String)
signal lead_picked(location_id: String)  # a spotted place you can say yes to
signal rumour_picked(rumour_id: String)

const UNIT := 150.0  # px per map unit when there's plenty of room
const MARGIN := 70.0
const HIT := 34.0  # px around a doodle that counts as clicking it
const PAPER := Color("1b1324")
const GRAIN := Color("2a2036")
const PINK := Color("ff9ccf")
const LILAC := Color("c9a0ff")
const MINT := Color("8fe8c0")
const PEACH := Color("ffb59a")
const SKY := Color("8cc8ff")
const YELLOW := Color("ffe08a")
const DIM := Color("968aaf")
const DOODLE_COLORS := {
	"house": PINK, "grass": MINT, "trees": MINT, "hill": MINT, "apple": PINK,
	"pond": SKY, "stream": SKY, "hut": SKY, "well": LILAC, "door": LILAC, "stairs": LILAC,
}

## The place picked for the next trip, circled on the map.
var selected := ""

var _title_font := SystemFont.new()
var _note_font := SystemFont.new()
var _nodes: Array[Dictionary] = []  # { id, kind: open / spotted / rumour / unknown, pos, ... }
var _edges: Array[Dictionary] = []  # { from, to, faint }
var _scale := UNIT
var _offset := Vector2.ZERO
var _hover := ""
var _hotspots := {}  # location id -> Control, so the tutorial can point at a place
var _tick := 0.0


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_title_font.font_names = PackedStringArray(["Coiny", "Maple Mono"])
	_note_font.font_names = PackedStringArray(["Maple Mono", "monospace"])
	_note_font.font_italic = true
	resized.connect(refresh)
	GameState.adventures_changed.connect(refresh)
	GameState.collection.active_changed.connect(func(_p): queue_redraw())


## Re-reads what's been found and redraws.
func refresh() -> void:
	_collect()
	_fit()
	_place_hotspots()
	queue_redraw()


## A small invisible control over a place's doodle (for the tutorial to point at), or null.
func hotspot(location_id: String) -> Control:
	return _hotspots.get(location_id)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0 and is_visible_in_tree():
		_tick = 0.5  # walking pets and time locks move on
		queue_redraw()


# ---- what's on the map --------------------------------------------------------

func _collect() -> void:
	var catalog := Catalog.shared()
	_nodes.clear()
	_edges.clear()
	var at := {}  # location id -> node, so each place is drawn once
	for location in catalog.locations:
		if not location.has("map"):
			continue
		if GameState.location_open(location):
			at[location.id] = _node(location, "open")
		elif GameState.spotted.has(location.id):
			at[location.id] = _node(location, "spotted")
	for rumour_id in GameState.rumours:
		for unlock in catalog.rumour(rumour_id).get("unlocks", []):
			var id := str(unlock).trim_prefix("location:")
			var location := catalog.location(id)
			if location.has("map") and not at.has(id):
				var node := _node(location, "rumour")
				node.rumour = rumour_id
				at[id] = node
	# unexplored directions from the places you can go
	for id in at.keys():
		var node: Dictionary = at[id]
		if node.kind != "open":
			continue
		for lead in node.location.get("leads_to", []):
			var to := catalog.location(lead.to)
			if not at.has(lead.to) and to.has("map"):
				at[lead.to] = _node(to, "unknown")
			if at.has(lead.to):
				_edges.append({ "from": id, "to": lead.to, "faint": at[lead.to].kind != "open" })
		if node.location.get("more", false):
			var out: Vector2 = node.pos.normalized() if node.pos.length() > 0.1 else Vector2.UP
			var cloud_id: String = id + ":more"
			at[cloud_id] = { "id": cloud_id, "kind": "unknown", "pos": node.pos + out * 0.9, "location": {} }
			_edges.append({ "from": id, "to": cloud_id, "faint": true })
	_nodes.assign(at.values())
	if selected != "" and not at.has(selected):
		selected = ""


func _node(location: Dictionary, kind: String) -> Dictionary:
	return { "id": location.id, "kind": kind, "location": location,
		"pos": Vector2(float(location.map.x), float(location.map.y)) }


## Zooms so everything found fits, as big as it comfortably can be.
func _fit() -> void:
	if _nodes.is_empty():
		return
	var box := Rect2(_nodes[0].pos, Vector2.ZERO)
	for node in _nodes:
		box = box.expand(node.pos)
	var room := size - Vector2(MARGIN, MARGIN) * 2.0
	_scale = minf(UNIT, minf(room.x / maxf(box.size.x, 0.5), room.y / maxf(box.size.y, 0.5)))
	_offset = size / 2.0 - box.get_center() * _scale + Vector2(0, 10)


func _screen(pos: Vector2) -> Vector2:
	return _offset + pos * _scale


func _place_hotspots() -> void:
	for spot in _hotspots.values():
		spot.queue_free()
	_hotspots.clear()
	for node in _nodes:
		if node.kind != "open":
			continue
		var spot := Control.new()
		spot.mouse_filter = MOUSE_FILTER_IGNORE
		spot.size = Vector2(HIT, HIT) * 2.0
		spot.position = _screen(node.pos) - spot.size / 2.0
		add_child(spot)
		_hotspots[node.id] = spot


# ---- clicking -----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := _node_at(event.position)
		var id: String = over.id if not over.is_empty() else ""
		if id != _hover:
			_hover = id
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if id != "" else CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var node := _node_at(event.position)
		if node.is_empty():
			return
		match node.kind:
			"open":
				selected = node.id
				place_picked.emit(node.id)
			"spotted":
				lead_picked.emit(node.id)
			"rumour":
				rumour_picked.emit(node.rumour)
		queue_redraw()
		accept_event()


func _node_at(point: Vector2) -> Dictionary:
	for node in _nodes:
		if node.kind != "unknown" and _screen(node.pos).distance_to(point) <= HIT:
			return node
	return {}


# ---- drawing --------------------------------------------------------------------

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	var grain := RandomNumberGenerator.new()
	grain.seed = 7
	for i in int(size.x * size.y / 900.0):
		draw_rect(Rect2(grain.randf() * size.x, grain.randf() * size.y, 1.5, 1.5), GRAIN)

	var active := GameState.collection.active()
	var title := "%s's map" % (active.display_name(Catalog.shared()) if active else "my")
	draw_string(_title_font, Vector2(16, 30), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, PINK)
	_crayon([Vector2(18, 38), Vector2(18 + minf(title.length() * 10.0, 280.0), 35)], PINK, 2.0, 1)

	var by_id := {}
	for node in _nodes:
		by_id[node.id] = node
	for edge in _edges:
		_dotted(_screen(by_id[edge.from].pos), _screen(by_id[edge.to].pos), DIM if edge.faint else PEACH, hash(edge.from + edge.to))
	for node in _nodes:
		_draw_node(node)
	_draw_trips()


func _draw_node(node: Dictionary) -> void:
	var at := _screen(node.pos)
	var k := clampf(_scale / UNIT * 1.25, 0.75, 1.3)
	var seed := hash(node.id)
	if node.kind == "unknown":
		_cloud(at, k, DIM, seed)
		_label(at + Vector2(0, 6) * k, "?", LILAC, _title_font, int(22 * k))
		return
	if node.kind == "rumour":
		_cloud(at, k, LILAC, seed)
		_label(at + Vector2(0, 6) * k, "?", PINK, _title_font, int(22 * k))
		var rumour := Catalog.shared().rumour(node.rumour)
		_label(at + Vector2(0, 44) * k, rumour.title, LILAC, _title_font, int(17 * k))
		_label(at + Vector2(0, 62) * k, "someone heard about this!", DIM, _note_font, int(13 * k))
		_label(at + Vector2(0, 79) * k, "tap to go!", PINK, _note_font, int(13 * k))
		return
	var location: Dictionary = node.location
	var doodle := str(location.map.get("doodle", "house"))
	var color: Color = DOODLE_COLORS.get(doodle, PINK)
	if node.kind == "spotted":
		color.a = 0.45
	if node.id == selected or node.id == _hover:
		_circle(at, 34.0 * k, Vector2.ONE, PINK if node.id == selected else Color(PINK, 0.5), 2.0, seed + 1)
	_doodle(doodle, at, k, color, seed)
	_label(at + Vector2(0, 44) * k, location.name, Color(color, 1.0) if node.kind == "open" else DIM, _title_font, int(17 * k))
	if node.kind == "open":
		var note := str(location.map.get("note", ""))
		if note != "":
			draw_string(_note_font, at + Vector2(30, -24) * k, note, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), YELLOW if doodle != "house" else PINK)
		if doodle == "house":
			_heart(at + Vector2(30, -28) * k + Vector2(_note_font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k)).x + 10, 0), 6.0 * k, PINK)
	else:
		var by := str(GameState.spotted[node.id].get("by", ""))
		var wait := GameState.lead_wait(node.id)
		var line := "%s saw this!" % by if by != "" else "someone saw this!"
		_label(at + Vector2(0, 62) * k, line, DIM, _note_font, int(13 * k))
		var when := "tap to go!" if wait <= 0.0 else "not yet · %s" % _clock(wait)
		_label(at + Vector2(0, 79) * k, when, PINK if wait <= 0.0 else DIM, _note_font, int(13 * k))


## Pets out on trips, walking out, standing at an event, or back at home waiting for you.
func _draw_trips() -> void:
	var now := Time.get_unix_time_from_system()
	var home_node := {}
	for node in _nodes:
		if node.location.get("start", false):
			home_node = node
	if home_node.is_empty():
		return
	var home := _screen(home_node.pos)
	var i := 0
	for run in GameState.runs:
		var place := home
		for node in _nodes:
			if node.id == run.location_id:
				place = _screen(node.pos)
		var spot := home
		match run.status:
			RunState.Status.WAITING:
				spot = place + Vector2(-26, 10)
			RunState.Status.DONE:
				spot = home + Vector2(-38 - i * 16, 14)
			_:
				var location := Catalog.shared().location(run.location_id)
				var gap := AdventureRunner.gap(location, run.party, run.events.size())
				var within := clampf(1.0 - (run.next_at - now) / gap, 0.0, 1.0)
				if run.step >= run.events.size():
					spot = place.lerp(home, within)
				else:
					spot = home.lerp(place, clampf((run.step + within) / maxf(1.0, run.events.size()), 0.0, 1.0))
		_little_pet(spot, LILAC, hash(run.rng_seed))
		var tag: String = run.party.who() if run.party.setting_out() == 1 else "%d pets" % run.party.setting_out()
		if run.status == RunState.Status.DONE:
			tag += " is back!"
		elif run.status == RunState.Status.WAITING:
			tag += "?"
		draw_string(_note_font, spot + Vector2(10, -8), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, LILAC)
		i += 1


# ---- crayon ---------------------------------------------------------------------

## A wobbly crayon stroke: a couple of slightly offset passes, the same wobble every redraw.
func _crayon(points: Array, color: Color, width: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for pass_ in 2:
		var line := PackedVector2Array()
		for p in points:
			line.append(p + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * 1.3)
		draw_polyline(line, Color(color, color.a * (0.9 if pass_ == 0 else 0.45)), width * (1.0 if pass_ == 0 else 0.7), true)


func _dotted(from: Vector2, to: Vector2, color: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var steps := int(from.distance_to(to) / 9.0)
	var side := (to - from).orthogonal().normalized()
	var bend := rng.randf_range(-14.0, 14.0)
	for i in range(0, steps, 2):
		var a := float(i) / steps
		var b := float(i + 1) / steps
		var pa := from.lerp(to, a) + side * sin(a * PI) * bend
		var pb := from.lerp(to, b) + side * sin(b * PI) * bend
		_crayon([pa, pb], color, 2.2, seed + i)


func _circle(center: Vector2, radius: float, squash: Vector2, color: Color, width: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var points := []
	for i in 27:
		var a := TAU * i / 26.0
		points.append(center + Vector2(cos(a) * squash.x, sin(a) * squash.y) * radius * rng.randf_range(0.95, 1.05))
	_crayon(points, color, width, seed)


func _cloud(at: Vector2, k: float, color: Color, seed: int) -> void:
	for puff in [[-20, 3, 14], [0, -5, 17], [20, 3, 14], [0, 8, 12]]:
		_circle(at + Vector2(puff[0], puff[1]) * k, puff[2] * k, Vector2.ONE, color, 2.0, seed + puff[0])


func _heart(at: Vector2, r: float, color: Color) -> void:
	_crayon([at + Vector2(0, r), at + Vector2(-r, -r * 0.2), at + Vector2(-r * 0.6, -r), at + Vector2(0, -r * 0.4),
		at + Vector2(r * 0.6, -r), at + Vector2(r, -r * 0.2), at + Vector2(0, r)], color, 2.0, 3)


func _label(at: Vector2, text: String, color: Color, font: Font, font_size: int) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, at - Vector2(width / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _little_pet(at: Vector2, color: Color, seed: int) -> void:
	_circle(at, 7.0, Vector2.ONE, color, 2.0, seed)
	_crayon([at + Vector2(-6, -4), at + Vector2(-5, -11), at + Vector2(-1, -6)], color, 2.0, seed + 1)
	_crayon([at + Vector2(6, -4), at + Vector2(5, -11), at + Vector2(1, -6)], color, 2.0, seed + 2)


## The little drawing for each kind of place.
func _doodle(kind: String, at: Vector2, k: float, color: Color, seed: int) -> void:
	var s := 24.0 * k
	match kind:
		"house":
			_crayon([at + Vector2(-s, s * 0.8), at + Vector2(-s, -s * 0.1), at + Vector2(0, -s), at + Vector2(s, -s * 0.1),
				at + Vector2(s, s * 0.8), at + Vector2(-s, s * 0.8)], color, 3.0, seed)
			_crayon([at + Vector2(-s * 0.25, s * 0.8), at + Vector2(-s * 0.25, s * 0.25), at + Vector2(s * 0.25, s * 0.25),
				at + Vector2(s * 0.25, s * 0.8)], color, 2.0, seed + 1)
		"grass":
			for i in 6:
				var x := -s + i * s * 0.4
				_crayon([at + Vector2(x, s * 0.6), at + Vector2(x + s * 0.12, 0), at + Vector2(x + s * 0.24, s * 0.6)], color, 2.0, seed + i)
			_circle(at + Vector2(-s * 0.4, -s * 0.2), s * 0.2, Vector2.ONE, PINK, 2.0, seed + 9)
			_circle(at + Vector2(s * 0.4, -s * 0.3), s * 0.18, Vector2.ONE, YELLOW, 2.0, seed + 10)
		"trees":
			for i in 3:
				var x := (i - 1) * s * 0.8
				_crayon([at + Vector2(x - s * 0.45, s * 0.5), at + Vector2(x, -s * 0.8), at + Vector2(x + s * 0.45, s * 0.5),
					at + Vector2(x - s * 0.45, s * 0.5)], color, 2.5, seed + i)
				_crayon([at + Vector2(x, s * 0.5), at + Vector2(x, s * 0.85)], PEACH, 2.0, seed + 5 + i)
		"hill":
			var points := []
			for i in 13:
				var a := PI * i / 12.0
				points.append(at + Vector2(-cos(a) * s * 1.2, s * 0.6 - sin(a) * s * 1.1))
			_crayon(points, color, 3.0, seed)
			_crayon([at + Vector2(0, -s * 0.5), at + Vector2(0, -s * 1.2), at + Vector2(s * 0.5, -s * 1.0), at + Vector2(0, -s * 0.85)], PINK, 2.0, seed + 1)
		"apple":
			_circle(at, s * 0.7, Vector2(1.0, 0.9), color, 3.0, seed)
			_crayon([at + Vector2(0, -s * 0.6), at + Vector2(s * 0.1, -s * 1.0)], PEACH, 2.0, seed + 1)
			_crayon([at + Vector2(s * 0.1, -s * 0.9), at + Vector2(s * 0.5, -s * 1.0), at + Vector2(s * 0.2, -s * 0.75)], MINT, 2.0, seed + 2)
		"pond":
			_circle(at + Vector2(0, s * 0.2), s * 1.1, Vector2(1.0, 0.45), color, 3.0, seed)
			_crayon([at + Vector2(-s * 0.6, s * 0.25), at + Vector2(-s * 0.1, s * 0.15)], color, 1.5, seed + 1)
			_circle(at + Vector2(s * 0.3, -s * 0.05), s * 0.22, Vector2.ONE, YELLOW, 2.0, seed + 2)
		"stream":
			for row in 3:
				var points := []
				for i in 9:
					points.append(at + Vector2(-s * 1.1 + i * s * 0.28, (row - 1) * s * 0.4 + sin(i * 1.3 + row) * s * 0.12))
				_crayon(points, color, 2.0, seed + row)
		"hut":
			_crayon([at + Vector2(-s * 0.9, s * 0.8), at + Vector2(-s * 0.9, 0), at + Vector2(0, -s * 0.8), at + Vector2(s * 0.9, 0),
				at + Vector2(s * 0.9, s * 0.8), at + Vector2(-s * 0.9, s * 0.8)], color, 3.0, seed)
			_crayon([at + Vector2(-s * 0.3, s * 0.1), at + Vector2(s * 0.3, s * 0.1), at + Vector2(s * 0.3, s * 0.5),
				at + Vector2(-s * 0.3, s * 0.5), at + Vector2(-s * 0.3, s * 0.1)], color, 2.0, seed + 1)
		"well":
			_circle(at + Vector2(0, s * 0.45), s * 0.8, Vector2(1.0, 0.35), color, 3.0, seed)
			_crayon([at + Vector2(-s * 0.7, s * 0.4), at + Vector2(-s * 0.7, -s * 0.6), at + Vector2(0, -s), at + Vector2(s * 0.7, -s * 0.6),
				at + Vector2(s * 0.7, s * 0.4)], color, 2.5, seed + 1)
		"door":
			var points := [at + Vector2(-s * 0.6, s * 0.8)]
			for i in 9:
				var a := PI + PI * i / 8.0
				points.append(at + Vector2(cos(a) * s * 0.6, -s * 0.1 + sin(a) * s * 0.6))
			points.append(at + Vector2(s * 0.6, s * 0.8))
			_crayon(points, color, 3.0, seed)
			_circle(at + Vector2(s * 0.3, s * 0.3), s * 0.08, Vector2.ONE, YELLOW, 2.0, seed + 1)
		"stairs":
			var points := []
			for i in 4:
				points.append(at + Vector2(-s + i * s * 0.55, -s * 0.6 + i * s * 0.45))
				points.append(at + Vector2(-s + (i + 1) * s * 0.55, -s * 0.6 + i * s * 0.45))
			_crayon(points, color, 3.0, seed)
		_:
			_circle(at, s * 0.7, Vector2.ONE, color, 3.0, seed)


func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60] if s >= 3600 else "%d:%02d" % [s / 60, s % 60]
