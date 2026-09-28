class_name MachineTreeView
extends HBoxContainer
## The machine tab's upgrades page: the old broken capsule machine's upgrade tree
## (data/machine_tree.json, Machine). The repairs are the trunk; the branches (coins, chutes, extra
## balls, shiny balls, lights) grow off them. Fixed nodes are filled in, the ones you can work on
## now breathe, the ones coming later are dark, the rest are "?". On the right, the picked node:
## a little picture of the machine (what's still broken), what it does, and what it costs in coins
## and bits (pets bring bits home from adventures). Design: design/mockups/screens/machine-tree.html.

const MAP := Vector2(600, 460)  # the tree's map, see data/machine_tree.json "at"
const BRANCH_COLORS := { "repair": "pink", "coins": "cyan", "chutes": "mint", "balls": "gold", "shiny": "lilac", "lights": "gold", "drops": "pink" }
const BRANCH_NAMES := { "repair": "a repair", "coins": "coins", "chutes": "chutes", "balls": "extra balls", "shiny": "shiny balls", "lights": "lights", "drops": "the big one" }

var tree := TreeMap.new()
var _detail := VBoxContainer.new()
var _picked := ""


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	tree.size_flags_horizontal = SIZE_EXPAND_FILL
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	tree.picked.connect(func(id):
		_picked = id
		_build_detail())
	add_child(tree)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(250, 0)
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 8)
	scroll.add_child(_detail)
	side.add_child(scroll)
	add_child(side)
	GameState.changed.connect(func():
		if is_visible_in_tree():
			tree.queue_redraw()
			_build_detail())
	visibility_changed.connect(func():
		if is_visible_in_tree():
			if _picked == "":
				_picked = _suggest()
			tree.picked_id = _picked
			tree.queue_redraw()
			_build_detail())


## The node worth looking at first: the cheapest one you can work on.
func _suggest() -> String:
	var catalog := Catalog.shared()
	var best := ""
	for n in catalog.machine_tree.nodes:
		if Machine.look(GameState.machine, catalog, n.id) == "next" or (Machine.owned(GameState.machine, n.id) > 0 and not Machine.maxed(GameState.machine, catalog, n.id)):
			if best == "" or Machine.cost(GameState.machine, catalog, n.id) < Machine.cost(GameState.machine, catalog, best):
				best = n.id
	return best if best != "" else str(catalog.machine_tree.nodes[0].id)


static func color_of(branch: String) -> Color:
	match str(BRANCH_COLORS.get(branch, "pink")):
		"cyan": return UiTheme.CYAN
		"mint": return UiTheme.MINT
		"gold": return UiTheme.GOLD
		"lilac": return UiTheme.LILAC
	return UiTheme.PINK


func _build_detail() -> void:
	UiTheme.clear(_detail)
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.machine
	var n := Machine.node(catalog, _picked)
	if n.is_empty():
		return
	var mini := MachineMini.new()
	mini.size_flags_horizontal = SIZE_SHRINK_CENTER
	_detail.add_child(mini)
	var look := Machine.look(state, catalog, _picked)
	if look == "hidden":
		_detail.add_child(_centered(UiTheme.title("???", 19)))
		_detail.add_child(_wrapped("something else is broken in there… fix what's next to it first.", UiTheme.MUTED))
		return
	var color := color_of(n.branch)
	_detail.add_child(_centered(UiTheme.title(str(n.name), 19)))
	var level := Machine.owned(state, _picked)
	var max_level := int(n.get("max", 1))
	var kind := str(BRANCH_NAMES.get(n.branch, n.branch))
	if max_level > 1:
		kind += ", level %d of %d" % [level, max_level]
	_detail.add_child(_centered(UiTheme.label(kind, color, UiTheme.SMALL + 1)))
	_detail.add_child(_wrapped(str(n.says), UiTheme.TEXT))
	_detail.add_child(_wrapped(str(n.gain), UiTheme.MINT))
	if Machine.maxed(state, catalog, _picked):
		_detail.add_child(_centered(UiTheme.label("fixed ✓" if max_level == 1 else "all done ✓", UiTheme.MINT, UiTheme.SMALL + 1)))
		return
	if look == "dim":
		_detail.add_child(_wrapped("fix %s first." % str(Machine.node(catalog, str(n.from)).name), UiTheme.MUTED))
		return
	# what it costs, and what you have
	var costs := VBoxContainer.new()
	costs.add_theme_constant_override("separation", 4)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 10))
	box.add_child(costs)
	var price := Machine.cost(state, catalog, _picked)
	costs.add_child(_cost_row("coin", "%s coins" % UiTheme.num(price), GameState.coins >= price, "you have %s" % UiTheme.num(GameState.coins)))
	var need := Machine.bits_cost(catalog, _picked)
	for b in need:
		var have := int(GameState.bits.get(b, 0))
		costs.add_child(_cost_row("bit_" + b, "%d %s" % [int(need[b]), MachineTab.bit_name(b, int(need[b]))], have >= int(need[b]), "you have %d" % have))
		if have < int(need[b]):
			var hint := UiTheme.label(GameState.bit_hint(b), UiTheme.MUTED, UiTheme.SMALL)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = 170  # wraps inside the cost box, never widens the side panel
			costs.add_child(hint)
	_detail.add_child(box)
	var why := Machine.blocker(state, catalog, _picked, GameState.coins, GameState.bits)
	var text := "fix it" if n.branch == "repair" or n.branch == "drops" else "upgrade"
	if why == "coins":
		text = "not enough coins"
	elif why != "":
		text = "not yet"
	var go := UiTheme.button(text, func():
		if GameState.buy_machine_upgrade(_picked):
			MachineTab.cheer(self, _picked))
	go.disabled = why != ""
	_detail.add_child(go)


func _cost_row(icon: String, text: String, ok: bool, have: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.icon_rect(icon, 16, UiTheme.CYAN))
	row.add_child(UiTheme.label(text, UiTheme.CYAN if ok else UiTheme.PINK, UiTheme.SMALL + 1))
	row.add_child(UiTheme.label("(%s)" % have, UiTheme.MUTED, UiTheme.SMALL))
	return row


func _wrapped(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color, UiTheme.SMALL + 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 210
	return l


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## The tree itself: links, then nodes (circle, icon, level, a bit badge if it's waiting for one, name).
class TreeMap extends Control:
	signal picked(id: String)

	var picked_id := ""
	var _time := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_time += delta
			queue_redraw()

	func _scale() -> float:
		return minf((size.x - 60.0) / MAP.x, (size.y - 50.0) / MAP.y)

	func _at(n: Dictionary) -> Vector2:
		var s := _scale()
		var origin := (size - MAP * s) / 2.0 + Vector2(0, -4)
		return origin + Vector2(float(n.at[0]), float(n.at[1])) * s

	func _radius(n: Dictionary) -> float:
		return (26.0 if n.branch in ["repair", "drops"] else 21.0) * clampf(_scale(), 0.75, 1.2)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for n in Catalog.shared().machine_tree.nodes:
				if event.position.distance_to(_at(n)) < _radius(n) + 6.0:
					picked_id = n.id
					picked.emit(n.id)
					queue_redraw()
					return
		elif event is InputEventMouseMotion:
			var over := false
			for n in Catalog.shared().machine_tree.nodes:
				over = over or event.position.distance_to(_at(n)) < _radius(n) + 6.0
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if over else CURSOR_ARROW

	func _draw() -> void:
		draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		var nodes: Array = catalog.machine_tree.nodes
		# links first
		for n in nodes:
			if not n.has("from"):
				continue
			var a := _at(Machine.node(catalog, n.from))
			var b := _at(n)
			var on := Machine.owned(state, n.id) > 0
			if on:
				draw_line(a, b, UiTheme.LILAC_SEAM, 3.0, true)
			else:
				draw_dashed_line(a, b, UiTheme.LINE, 3.0, 7.0, true)
		var font := UiTheme.BODY_FONT
		for n in nodes:
			var look := Machine.look(state, catalog, n.id)
			var c := _at(n)
			var r := _radius(n)
			var color := MachineTreeView.color_of(n.branch)
			match look:
				"owned":
					draw_circle(c, r, UiTheme.PAGE.lerp(color, 0.3))
					draw_arc(c, r, 0, TAU, 40, color, 3.0, true)
				"next":
					var breathe := 0.5 + 0.5 * sin(_time * 3.0)
					draw_arc(c, r + 4.0 + breathe * 4.0, 0, TAU, 40, Color(color, 0.5 - breathe * 0.35), 2.0, true)
					draw_circle(c, r, UiTheme.RAISED)
					_dashed_ring(c, r, color)
				_:
					draw_circle(c, r, UiTheme.DEEP)
					if look == "hidden":
						_dashed_ring(c, r, UiTheme.LINE)
					else:
						draw_arc(c, r, 0, TAU, 40, UiTheme.LINE, 3.0, true)
			if n.id == picked_id:
				draw_arc(c, r + 3.0, 0, TAU, 40, UiTheme.TEXT, 2.0, true)
			if look == "hidden":
				var q := "?"
				draw_string(UiTheme.DISPLAY_FONT, c + Vector2(-6, 7), q, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiTheme.LOCKED)
				continue
			var icon := UiTheme.icon("tree_" + str(n.icon), 22, color if look != "dim" else UiTheme.LOCKED)
			draw_texture_rect(icon, Rect2(c - Vector2(11, 11), Vector2(22, 22)), false)
			var level := Machine.owned(state, n.id)
			var max_level := int(n.get("max", 1))
			if max_level > 1:
				var pill := "%d/%d" % [level, max_level]
				var pr := Rect2(c + Vector2(-16, r - 8), Vector2(32, 15))
				draw_style_box(UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 7, 0, 0), pr)
				draw_string(UiTheme.DISPLAY_FONT, pr.position + Vector2(0, 12), pill, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 11, UiTheme.DEEP)
			# waiting for a bit you don't have
			if look == "next" and not Machine.maxed(state, catalog, n.id):
				var need := Machine.bits_cost(catalog, n.id)
				for b in need:
					if int(GameState.bits.get(b, 0)) < int(need[b]):
						var bc := c + Vector2(r * 0.75, -r * 0.8)
						draw_circle(bc, 11.0, UiTheme.DEEP)
						draw_arc(bc, 11.0, 0, TAU, 24, UiTheme.PINK, 2.0, true)
						draw_texture_rect(UiTheme.icon("bit_" + str(b), 16), Rect2(bc - Vector2(8, 8), Vector2(16, 16)), false)
						break
			var label_y := r + (22.0 if max_level > 1 else 16.0)
			var name_color := UiTheme.TEXT if look in ["owned", "next"] else UiTheme.MUTED
			draw_string(font, c + Vector2(-70, label_y), str(n.name), HORIZONTAL_ALIGNMENT_CENTER, 140, UiTheme.SMALL + 1, name_color)

	func _dashed_ring(c: Vector2, r: float, color: Color) -> void:
		for i in 16:
			var a := TAU * i / 16.0
			draw_arc(c, r, a, a + TAU / 32.0, 4, color, 3.0, true)


## A little picture of the machine for the upgrade page: what's still broken shows (the crack, the
## cloudy glass, rust, a stuck flap, dead lights), and what's fixed doesn't.
class MachineMini extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(120, 120)
		mouse_filter = MOUSE_FILTER_IGNORE
		GameState.changed.connect(queue_redraw)

	func _draw() -> void:
		var state: Dictionary = GameState.machine
		var fixed := func(id: String) -> bool: return Machine.owned(state, id) > 0
		var g := Vector2(60, 42)
		draw_circle(g, 32.0, UiTheme.PAGE.lerp(UiTheme.LILAC, 0.09))
		if not fixed.call("glass"):
			draw_circle(g + Vector2(10, -8), 12.0, Color(UiTheme.TEXT, 0.08))
			draw_polyline(PackedVector2Array([g + Vector2(-20, -10), g + Vector2(-12, -14), g + Vector2(-8, -6), g + Vector2(0, -12)]), Color(UiTheme.MUTED, 0.7), 1.5, true)
		if not fixed.call("tape"):
			draw_polyline(PackedVector2Array([g + Vector2(14, -26), g + Vector2(20, -14), g + Vector2(16, -6), g + Vector2(24, 4)]), UiTheme.MUTED, 2.0, true)
		else:
			draw_line(g + Vector2(14, -24), g + Vector2(28, -10), Color(UiTheme.GOLD, 0.8), 5.0)
		draw_arc(g, 32.0, 0, TAU, 40, UiTheme.LILAC, 2.5, true)
		var body := PackedVector2Array([Vector2(30, 74), Vector2(90, 74), Vector2(94, 110), Vector2(26, 110)])
		draw_colored_polygon(body, UiTheme.PAGE.lerp(UiTheme.PINK, 0.22))
		body.append(body[0])
		draw_polyline(body, UiTheme.PINK, 2.5, true)
		if not fixed.call("oil"):
			draw_circle(Vector2(40, 98), 3.0, Color("8a6448"))
			draw_circle(Vector2(80, 84), 2.5, Color("8a6448"))
		var chutes := Machine.chutes(state, Catalog.shared())
		for i in chutes:
			var x := 60.0 + (i - (chutes - 1) / 2.0) * 16.0
			var rect := Rect2(x - 7, 92, 14, 14)
			var tilt := 0.0 if fixed.call("flap") or i > 0 else 0.25
			draw_set_transform(rect.get_center(), tilt, Vector2.ONE)
			draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 3, 2, 0), Rect2(-rect.size / 2.0, rect.size))
			draw_set_transform(Vector2.ZERO)
		for i in 5:
			draw_circle(Vector2(44 + i * 8, 82), 2.2, UiTheme.GOLD if fixed.call("wires") else UiTheme.LINE)
		draw_line(Vector2(94, 88), Vector2(104, 70), UiTheme.GOLD, 4.0, true)
		draw_circle(Vector2(105, 67), 5.0, UiTheme.PINK)
