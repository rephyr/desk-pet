class_name MapView
extends Control
## The adventure map: your active pet's crayon drawing of the world, on dark paper. Places you
## can go are doodled in with the pet's little notes; places a pet spotted are faded in, waiting
## for you to say yes; unexplored directions are ? clouds.
## Pets out on trips walk along as tiny doodles. Everything comes from data/adventures.json
## ("map" on each location), and the drawing zooms to fit whatever has been found so far.

signal place_picked(location_id: String)
signal lead_picked(location_id: String)  # a spotted place you can say yes to
signal rumour_picked(rumour_id: String)
signal edge_picked  # the signpost at the edge (past the edge, see Edge)
signal page_changed(page_id: String)

const EDGE_ID := "edge"  # the signpost's id among the map's spots (and `selected` when it's picked)
const SHEET_TILT := 2.2  # degrees the page tucked under the edge leans

const UNIT := 150.0  # px per map unit when there's plenty of room
const MARGIN := 70.0
const HIT := 34.0  # px around a doodle that counts as clicking it
# colours from the player's theme (set in _init; the map redraws when the look changes)
var PAPER := UiTheme.PAPER
var GRAIN := UiTheme.DOT
var PINK := UiTheme.PINK
var LILAC := UiTheme.LILAC
var MINT := UiTheme.MINT
var PEACH := UiTheme.GOLD.lerp(UiTheme.PINK, 0.35)
var SKY := UiTheme.CYAN
var YELLOW := UiTheme.GOLD
var DIM := UiTheme.MUTED

## The place picked for the next trip, circled on the map.
var selected := ""
## Which map page is showing (data/unlocks.json "pages"). Each page is its own drawing.
var page := ""

var _title_font: Font = UiTheme.DISPLAY_FONT
var _note_font: Font = UiTheme.BODY_FONT
var _nodes: Array[Dictionary] = []  # { id, kind: open / spotted / rumour / unknown, pos, ... }
var _edges: Array[Dictionary] = []  # { from, to, faint }
var _scale := UNIT
var _offset := Vector2.ZERO
var _hover := ""
var _hotspots := {}  # location id -> Control, so the tutorial can point at a place
var _tick := 0.0
var _page_tabs := HBoxContainer.new()
var _needed := {}  # machine bits some upgrade still needs: bit id -> true (a hint on the map where they are)
var _torn := false  # this page ends at the edge: the paper stops short with a torn right side
var _scribbles := []  # [points, colour] in the tucked page's own space, see _sheet_scribbles
var _scribble_key := ""
var _anchor := []  # map points the fit keeps room for though nothing's drawn there (the finished edge)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_page_tabs.add_theme_constant_override("separation", 6)
	add_child(_page_tabs)
	resized.connect(refresh)
	GameState.adventures_changed.connect(refresh)
	GameState.collection.active_changed.connect(func(_p): queue_redraw())
	GameState.edge_changed.connect(refresh)


## Re-reads what's been found and redraws.
func refresh() -> void:
	_refresh_pages()
	_collect()
	_fit()
	_place_hotspots()
	queue_redraw()


## Shows another page of the map (a bookmark was tapped).
func show_map_page(page_id: String) -> void:
	if not GameState.page_open(page_id):
		return
	var changed_page := page != page_id
	page = page_id
	selected = ""
	refresh()
	if changed_page:
		page_changed.emit(page)


## As if the signpost at the edge was tapped (the dev driver's "edge").
func pick_edge() -> void:
	if not _nodes.any(func(n): return n.id == EDGE_ID and n.kind == "edge"):
		return
	selected = EDGE_ID
	edge_picked.emit()
	queue_redraw()


## Where the signpost is on screen (pets sent past the edge fly there).
func edge_point() -> Vector2:
	for node in _nodes:
		if node.id == EDGE_ID:
			return get_global_transform() * _screen(node.pos)
	return get_global_rect().get_center()


## A small invisible control over a place's doodle (for the tutorial to point at), or null.
func hotspot(location_id: String) -> Control:
	return _hotspots.get(location_id)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0 and is_visible_in_tree():
		_tick = 0.5  # walking pets move on
		queue_redraw()
	if is_visible_in_tree() and _nodes.any(_is_new):
		queue_redraw()  # new places glow and their arrows bob


## One little tab per open page, top right, when there's more than one.
func _refresh_pages() -> void:
	var open: Array = Catalog.shared().pages.filter(func(p): return GameState.page_open(p.id))
	var was := page
	if page == "" or not open.any(func(p): return p.id == page):
		page = open[0].id if not open.is_empty() else ""
	if page != was:
		page_changed.emit.call_deferred(page)
	UiTheme.clear(_page_tabs)
	_page_tabs.visible = open.size() > 1
	for p in open:
		# a bookmark hanging from the top of the paper
		var b := Button.new()
		b.text = p.name
		b.focus_mode = FOCUS_NONE
		b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		var on: bool = p.id == page
		var sb := UiTheme.box(UiTheme.RAISED if on else UiTheme.DEEP, UiTheme.PINK_SEAM if on else UiTheme.LINE, 8, 2, 4)
		sb.corner_radius_top_left = 0
		sb.corner_radius_top_right = 0
		sb.border_width_top = 0
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 8 if on else 4
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, sb)
		b.add_theme_color_override("font_color", UiTheme.PINK if on else UiTheme.MUTED)
		b.add_theme_color_override("font_hover_color", UiTheme.PINK)
		b.size_flags_vertical = SIZE_SHRINK_BEGIN
		b.pressed.connect(func(): show_map_page(p.id))
		_page_tabs.add_child(b)
	_page_tabs.reset_size()
	_page_tabs.position = Vector2(size.x - _page_tabs.size.x - 16.0, 0.0)


# ---- what's on the map --------------------------------------------------------

func _collect() -> void:
	var catalog := Catalog.shared()
	_nodes.clear()
	_edges.clear()
	var at := {}  # location id -> node, so each place is drawn once
	for location in catalog.locations:
		if not location.has("map") or str(location.get("page", "")) != page:
			continue
		if GameState.location_open(location):
			at[location.id] = _node(location, "open")
		elif GameState.spotted.has(location.id):
			at[location.id] = _node(location, "spotted")
	for rumour_id in GameState.rumours:
		for unlock in catalog.rumour(rumour_id).get("unlocks", []):
			var id := str(unlock).trim_prefix("location:")
			var location := catalog.location(id)
			if location.has("map") and not at.has(id) and str(location.get("page", "")) == page:
				var node := _node(location, "rumour")
				node.rumour = rumour_id
				at[id] = node
	# the edge: a signpost where this page stops (or a rumour of it)
	var edge_data: Dictionary = catalog.edge
	_torn = page != "" and page == str(edge_data.get("page", "")) and GameState.edge_torn()
	if page == str(edge_data.get("page", "")) and edge_data.has("map"):
		var edge_pos := Vector2(float(edge_data.map.get("x", 0.0)), float(edge_data.map.get("y", 0.0)))
		if GameState.edge_open():
			at[EDGE_ID] = { "id": EDGE_ID, "kind": "edge", "pos": edge_pos, "location": {} }
		elif not GameState.edge_torn() and GameState.rumours.any(func(r): return catalog.rumour(r).get("unlocks", []).has("feature:edge")):
			var rumour_id: String = GameState.rumours.filter(func(r): return catalog.rumour(r).get("unlocks", []).has("feature:edge"))[0]
			at[EDGE_ID] = { "id": EDGE_ID, "kind": "rumour", "rumour": rumour_id, "pos": edge_pos, "location": {} }
	# the narrower torn paper is drawn with its own layout (data/edge.json "layout"); the edge's spot
	# keeps its room once it's gone, so the page doesn't jump
	_anchor.clear()
	if _torn:
		var spot: Array = edge_data.get("layout", {}).get(EDGE_ID, [])
		if spot.size() == 2:
			_anchor.append(Vector2(float(spot[0]), float(spot[1])))
		var layout: Dictionary = edge_data.get("layout", {})
		for id in at:
			if layout.has(id) and layout[id] is Array and layout[id].size() == 2:
				at[id].pos = Vector2(float(layout[id][0]), float(layout[id][1]))
	# unexplored directions from the places you can go
	for id in at.keys():
		var node: Dictionary = at[id]
		if node.kind != "open":
			continue
		for lead in node.location.get("leads_to", []):
			var to := catalog.location(lead.to)
			if not at.has(lead.to) and to.has("map") and str(to.get("page", "")) == page:
				at[lead.to] = _node(to, "unknown")
			if at.has(lead.to):
				_edges.append({ "from": id, "to": lead.to, "faint": at[lead.to].kind != "open" })
		if node.location.get("more", false):
			var out: Vector2 = node.pos.normalized() if node.pos.length() > 0.1 else Vector2.UP
			var cloud_id: String = id + ":more"
			at[cloud_id] = { "id": cloud_id, "kind": "unknown", "pos": node.pos + out * 0.9, "location": {} }
			_edges.append({ "from": id, "to": cloud_id, "faint": true })
	_nodes.assign(at.values())
	_needed.clear()
	for n in catalog.machine_tree.nodes:
		if not Machine.maxed(GameState.machine, catalog, n.id):
			for b in Machine.bits_cost(catalog, n.id):
				_needed[b] = true
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
	for p in _anchor:
		box = box.expand(p)
	var area := Vector2(paper_width(), size.y)
	var room := area - Vector2(MARGIN, MARGIN) * 2.0
	_scale = minf(UNIT, minf(room.x / maxf(box.size.x, 0.5), room.y / maxf(box.size.y, 0.5)))
	_offset = area / 2.0 - box.get_center() * _scale + Vector2(0, 10)


## How wide the paper is: all of it, or short of the tucked page at the edge.
func paper_width() -> float:
	return size.x * (1.0 - clampf(float(Catalog.shared().edge.get("peek", 0.3)), 0.0, 0.6)) if _torn else size.x


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
			"edge":
				selected = EDGE_ID
				edge_picked.emit()
		queue_redraw()
		accept_event()


func _node_at(point: Vector2) -> Dictionary:
	for node in _nodes:
		if node.kind != "unknown" and _screen(node.pos).distance_to(point) <= HIT:
			return node
	return {}


# ---- drawing --------------------------------------------------------------------

func _draw() -> void:
	if _torn:
		if GameState.edge_open():
			_draw_sheet()
		_draw_torn_paper()
	else:
		draw_style_box(UiTheme.box(PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))
	var grain := RandomNumberGenerator.new()
	grain.seed = 7
	var grain_w := paper_width() - (18.0 if _torn else 0.0)
	for i in int(grain_w * size.y / 900.0):
		draw_rect(Rect2(grain.randf() * grain_w, grain.randf() * size.y, 1.5, 1.5), GRAIN)

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
	if node.kind == "edge":
		_draw_signpost(node, at, k, seed)
		return
	if node.kind == "unknown":
		_cloud(at, k, DIM, seed)
		_label(at + Vector2(0, 6) * k, "?", LILAC, _title_font, int(22 * k))
		var hidden := bit_of(node.location)
		if hidden != "" and _needed.has(hidden):
			_bit_line(at + Vector2(0, 44) * k, hidden, "%s out this way?" % MachineTab.bit_name(hidden, 2), k, 0.7)
		return
	if node.kind == "rumour":
		_cloud(at, k, LILAC, seed)
		_label(at + Vector2(0, 6) * k, "?", PINK, _title_font, int(22 * k))
		var rumour := Catalog.shared().rumour(str(node.rumour))
		_label(at + Vector2(0, 44) * k, rumour.title, LILAC, _title_font, int(17 * k))
		_label(at + Vector2(0, 62) * k, "someone heard about this!", DIM, _note_font, int(13 * k))
		_label(at + Vector2(0, 79) * k, "tap to go!", PINK, _note_font, int(13 * k))
		return
	var location: Dictionary = node.location
	var doodle := str(location.map.get("doodle", "house"))
	var color := Crayon.doodle_color(doodle)
	if node.kind == "spotted":
		color.a = 0.45
	if _is_new(node):
		_draw_new_glow(at, k)
	if node.id == selected or node.id == _hover:
		_circle(at, 34.0 * k, Vector2.ONE, PINK if node.id == selected else Color(PINK, 0.5), 2.0, seed + 1)
	_doodle(doodle, at, k, color, seed)
	_label(at + Vector2(0, 44) * k, location.name, Color(color, 1.0) if node.kind == "open" else DIM, _title_font, int(17 * k))
	var bit := bit_of(location)
	if node.kind == "open":
		if bit != "":
			_bit_line(at + Vector2(0, 62) * k, bit, "%s here!" % MachineTab.bit_name(bit, 2), k, 1.0)
		var note := str(location.map.get("note", ""))
		if note != "":
			draw_string(_note_font, at + Vector2(30, -24) * k, note, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k), YELLOW if doodle != "house" else PINK)
		if doodle == "house":
			_heart(at + Vector2(30, -28) * k + Vector2(_note_font.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, int(14 * k)).x + 10, 0), 6.0 * k, PINK)
	else:
		if bit != "":  # a little icon after the name: what's waiting there
			var w := _title_font.get_string_size(location.name, HORIZONTAL_ALIGNMENT_LEFT, -1, int(17 * k)).x
			var s := 16.0 * k
			draw_texture_rect(UiTheme.icon("bit_" + bit, int(s)), Rect2(at + Vector2(w / 2.0 + 5.0 * k, 44.0 * k - s + 2.0 * k), Vector2(s, s)), false)
		var by := str(GameState.spotted[node.id].get("by", ""))
		var line := "%s saw this!" % by if by != "" else "someone saw this!"
		_label(at + Vector2(0, 62) * k, line, DIM, _note_font, int(13 * k))
		_label(at + Vector2(0, 79) * k, "tap to go!", PINK, _note_font, int(13 * k))


## A place that wants a tap: spotted by a pet and waiting for your yes, or open but never been to.
func _is_new(node: Dictionary) -> bool:
	if node.kind == "edge":
		return int(GameState.edge.get("ever", 0)) == 0  # nobody's gone past it yet
	return node.kind == "spotted" or (node.kind == "open" and not GameState.visited.has(node.id))


## A soft golden glow that breathes round a new place, and a crayon arrow bobbing over it.
func _draw_new_glow(at: Vector2, k: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var breathe := 0.5 + 0.5 * sin(t * 3.0)
	for i in 3:
		draw_circle(at, (46.0 - i * 10.0 + breathe * 5.0) * k, Color(YELLOW, 0.05 + i * 0.04 + breathe * 0.04))
	var tip := at + Vector2(0, -44.0 - absf(sin(t * 4.0)) * 8.0) * k
	_crayon([tip + Vector2(0, -26) * k, tip], YELLOW, 3.0, 11)
	_crayon([tip + Vector2(-9, -10) * k, tip, tip + Vector2(9, -10) * k], YELLOW, 3.0, 12)


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
		if str(Catalog.shared().location(run.location_id).get("page", "")) != page:
			continue  # out on another page of the map
		var place := home
		for node in _nodes:
			if node.id == run.location_id:
				place = _screen(node.pos)
		var spot := home
		match run.status:
			RunState.Status.WAITING:
				# stopped where the walk reached this event (not at the place itself)
				spot = home.lerp(place, clampf((run.step + 1.0) / maxf(1.0, run.events.size()), 0.0, 1.0))
			RunState.Status.DONE:
				spot = home + Vector2(-38 - i * 16, 14)
			_:
				var gap := AdventureRunner.run_gap(run, Catalog.shared())
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


# ---- the edge ---------------------------------------------------------------------

## The map paper, torn off down its right side where the page stops.
func _draw_torn_paper() -> void:
	var w := paper_width()
	var h := size.y
	var r := 14.0
	var pts := PackedVector2Array()
	for i in 5:  # the top-left corner, rounded
		var a := PI + (PI / 2.0) * i / 4.0
		pts.append(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
	pts.append(Vector2(w - 10.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var y := 0.0
	while y < h - 30.0:
		y += rng.randf_range(34.0, 60.0)
		pts.append(Vector2(w - rng.randf_range(0.0, 20.0), minf(y, h - 1.0)))
	pts.append(Vector2(w - 12.0, h))
	for i in 5:  # the bottom-left corner
		var a := PI / 2.0 + (PI / 2.0) * i / 4.0
		pts.append(Vector2(r, h - r) + Vector2(cos(a), sin(a)) * r)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(6, 3))
	draw_colored_polygon(shadow, Color(UiTheme.SHADOW, 0.55))
	draw_colored_polygon(pts, PAPER)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, UiTheme.LINE, 2.0, true)


## The tucked page's rectangle, before its lean (a little of it hides under the torn paper).
func _sheet_rect() -> Rect2:
	var left := paper_width() - size.x * 0.14
	return Rect2(left, 32.0, size.x - left - 6.0, size.y - 42.0)


## The next page, tucked under the edge: a crayon scribble in each sent pet's colours, and how many
## are still to go. Never an outline of what's there.
func _draw_sheet() -> void:
	var rect := _sheet_rect()
	var centre := rect.get_center()
	var half := rect.size / 2.0
	draw_set_transform(centre, deg_to_rad(SHEET_TILT))
	var sb := UiTheme.box(PAPER, UiTheme.LINE, 14, 2, 0)
	sb.shadow_color = UiTheme.SHADOW
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 5)
	draw_style_box(sb, Rect2(-half, rect.size))
	for s in _sheet_scribbles(rect.size):
		draw_polyline(s[0], s[1], 2.6, true)
	# how many to go, in the middle of the part that peeks out
	var peek_mid := (paper_width() + rect.end.x) / 2.0 - centre.x
	var n := UiTheme.num(GameState.edge_to_go())
	var big := 44
	var nw := _title_font.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
	draw_string_outline(_title_font, Vector2(peek_mid - nw / 2.0, 12.0), n, HORIZONTAL_ALIGNMENT_LEFT, -1, big, 10, PAPER)
	draw_string(_title_font, Vector2(peek_mid - nw / 2.0, 12.0), n, HORIZONTAL_ALIGNMENT_LEFT, -1, big, PINK)
	var sub := "to go"
	var sw := _note_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string_outline(_note_font, Vector2(peek_mid - sw / 2.0, 32.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 6, PAPER)
	draw_string(_note_font, Vector2(peek_mid - sw / 2.0, 32.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiTheme.TEXT)
	draw_set_transform(Vector2.ZERO)


## One little squiggle per scribble on the page (worked out again only when there are more), in
## the sheet's own space (its middle at 0, 0).
func _sheet_scribbles(sheet: Vector2) -> Array:
	var marks: Array = GameState.edge.get("marks", [])
	var key := "%d|%d|%s" % [int(GameState.edge.get("page", 0)), marks.size(), str(sheet)]
	if key == _scribble_key:
		return _scribbles
	_scribble_key = key
	_scribbles.clear()
	var catalog := Catalog.shared()
	var tints := {}
	var pad := 12.0
	for i in marks.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(int(GameState.edge.get("page", 0)) * 100003 + i)
		var p := Vector2(rng.randf_range(pad, sheet.x - pad), rng.randf_range(pad, sheet.y - pad)) - sheet / 2.0
		var pts := PackedVector2Array([p])
		for j in 2 + rng.randi_range(0, 2):
			var c := p + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 10))
			var e := p + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
			for t in [0.34, 0.67, 1.0]:
				pts.append(p.lerp(c, t).lerp(c.lerp(e, t), t))
			p = e
		var palette := str(marks[i])
		if not tints.has(palette):
			var body := str(catalog.part("palette", palette).get("body", "")) if palette != "" else ""
			tints[palette] = Color(Color(body) if body != "" else LILAC, 0.8)
		_scribbles.append([pts, tints[palette]])
	return _scribbles


## The signpost at the edge: a crayon post with an arrow board, "the edge" under it.
func _draw_signpost(node: Dictionary, at: Vector2, k: float, seed: int) -> void:
	if _is_new(node):
		_draw_new_glow(at, k)
	if node.id == selected or node.id == _hover:
		_circle(at + Vector2(4, -4) * k, 30.0 * k, Vector2.ONE, PINK if node.id == selected else Color(PINK, 0.5), 2.5, seed + 1)
	_crayon([at + Vector2(0, 26) * k, at + Vector2(0, -16) * k], PINK, 3.0, seed)
	_crayon([at + Vector2(2, -14) * k, at + Vector2(22, -14) * k, at + Vector2(28, -8) * k, at + Vector2(22, -2) * k, at + Vector2(2, -2) * k],
		PINK, 2.6, seed + 2)
	_label(at + Vector2(0, 46) * k, "the edge", PINK, _title_font, int(17 * k))


## The machine bit a place's pets bring home when they go all the way (its finish_rewards), or "".
static func bit_of(location: Dictionary) -> String:
	for r in location.get("finish_rewards", []):
		if str(r.get("kind", "")) == "bit":
			return str(r.get("id", ""))
	return ""


## The colour a bit is drawn in (the same as its icon).
static func bit_color(bit: String) -> Color:
	match bit:
		"gear": return UiTheme.LILAC
		"spring": return UiTheme.MINT
		"bolt": return UiTheme.GOLD
		"glass": return UiTheme.CYAN
	return UiTheme.TEXT


## A bit's icon and a little note, centred on `at` (the text's baseline).
func _bit_line(at: Vector2, bit: String, text: String, k: float, alpha: float) -> void:
	var font_size := int(13 * k)
	var s := 15.0 * k
	var width := s + 4.0 * k + _note_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var left := at.x - width / 2.0
	draw_texture_rect(UiTheme.icon("bit_" + bit, int(ceilf(s))), Rect2(Vector2(left, at.y - s + 2.0 * k), Vector2(s, s)), false, Color(1, 1, 1, alpha))
	draw_string(_note_font, Vector2(left + s + 4.0 * k, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(bit_color(bit), alpha))


# ---- crayon ---------------------------------------------------------------------

func _crayon(points: Array, color: Color, width: float, seed: int) -> void:
	Crayon.line(self, points, color, width, seed)


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
	Crayon.circle(self, center, radius, squash, color, width, seed)


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


func _doodle(kind: String, at: Vector2, k: float, color: Color, seed: int) -> void:
	Crayon.doodle(self, kind, at, k, color, seed)
