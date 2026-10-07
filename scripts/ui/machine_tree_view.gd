class_name MachineTreeView
extends HBoxContainer
## The machine tab's upgrades page: the old broken capsule machine's upgrade tree
## (data/machine_tree.json, Machine). The repairs are the trunk; the branches (coins, chutes, extra
## balls, shiny balls, lights) grow off them. Fixed nodes are filled in, the ones you can work on
## now breathe, the ones coming next are dark, the rest aren't drawn yet (hidden until earned). On the right, the picked node:
## a little picture of the machine (what's still broken), what it does, and what it costs in coins
## and bits (pets bring bits home from adventures). Design: design/mockups/screens/machine-tree.html.
## A later globe's repairs grow off the old rusted hatch: the page frames the newest globe's part of
## the tree (its "view"), older nodes fade behind it, and a sign per globe pans between them
## (design/mockups/screens/globes.html, the upgrades page).

const MAP := Vector2(600, 540)  # the first globe's part of the tree's map, see data/machine_tree.json "at"
const BRANCH_COLORS := { "repair": "pink", "coins": "cyan", "chutes": "mint", "balls": "gold", "shiny": "lilac", "lights": "gold", "drops": "pink" }
const BRANCH_NAMES := { "repair": "a repair", "coins": "coins", "chutes": "chutes", "balls": "extra balls", "shiny": "shiny balls", "lights": "lights", "drops": "the big one", "sunset": "a repair", "midnight": "a repair" }
const REPAIRS := ["repair", "drops", "sunset", "midnight"]  # branches whose nodes are fixed (not upgraded), drawn big

var tree := TreeMap.new()
var _detail := VBoxContainer.new()
var _picked := ""
var _signs := HBoxContainer.new()
var _newest := ""
var _stale := false  # GameState changed: the tree and the card catch up (at most every STALE_EVERY s)
var _stale_wait := 0.0
const STALE_EVERY := 0.5


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	tree.size_flags_horizontal = SIZE_EXPAND_FILL
	tree.size_flags_vertical = SIZE_EXPAND_FILL
	tree.picked.connect(func(id):
		_picked = id
		_build_detail())
	add_child(tree)
	_signs.position = Vector2(12, 10)
	_signs.add_theme_constant_override("separation", 8)
	tree.add_child(_signs)
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
	# GameState.changed fires on every passive coin: catch up in _process, not on each one
	GameState.changed.connect(func(): _stale = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			var newest := Machine.newest(GameState.machine, Catalog.shared())
			if newest != _newest:
				# a new globe came home: frame its part of the tree and look at its first repair
				_newest = newest
				tree.frame(newest, false)
				_picked = ""
			if _picked == "" or Machine.look(GameState.machine, Catalog.shared(), _picked) == "away":
				_picked = _suggest()
				# the suggestion can be on an older globe (the newest one's all fixed): look at it
				var g := Machine.globe_of(Catalog.shared(), Machine.node(Catalog.shared(), _picked))
				if g != tree.viewing:
					tree.frame(g, false)
			tree.picked_id = _picked
			tree.queue_redraw()
			_build_signs()
			_build_detail())


## The tree and the card catch up on GameState changes, at most every STALE_EVERY seconds.
func _process(delta: float) -> void:
	_stale_wait -= delta
	if _stale and _stale_wait <= 0.0 and is_visible_in_tree():
		_stale = false
		_stale_wait = STALE_EVERY
		tree.queue_redraw()
		_build_detail()


## A sign per globe you have (once there are two), top left of the tree: tap one to pan to its part.
func _build_signs() -> void:
	UiTheme.clear(_signs)
	var catalog := Catalog.shared()
	var home := Machine.home(GameState.machine, catalog)
	_signs.visible = home.size() > 1
	if home.size() < 2:
		return
	for i in home.size():
		var g: String = home[i]
		var color := MachineTab.globe_color(g)
		var b := Button.new()
		b.name = "sign_" + g
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.text = str(Machine.globe(catalog, g).get("name", g))
		b.icon = UiTheme.icon(str(Machine.globe(catalog, g).get("icon", "globe_sunny")), 16, color)
		b.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		b.add_theme_font_size_override("font_size", 14)
		var on := g == tree.viewing
		for state in ["normal", "hover", "pressed", "focus"]:
			var sb := UiTheme.box(UiTheme.RAISED if on or state == "hover" else UiTheme.DEEP, color if on or state == "hover" else UiTheme.LINE, 6, 2, 0)
			sb.content_margin_left = 8
			sb.content_margin_right = 10
			sb.content_margin_top = 4
			sb.content_margin_bottom = 3
			b.add_theme_stylebox_override(state, sb)
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(key, color if on else UiTheme.MUTED)
		b.rotation_degrees = -2.0 if i % 2 == 0 else 2.0
		b.pressed.connect(func():
			tree.frame(g, true)
			_build_signs())
		_signs.add_child(b)


## The node worth looking at first: the newest globe's next repair while it has any, otherwise the
## cheapest one you can work on.
func _suggest() -> String:
	var catalog := Catalog.shared()
	var best := ""
	var newest := Machine.newest(GameState.machine, catalog)
	if newest != Machine.first_globe(catalog):
		for n in Machine.repairs(catalog, newest):
			if not Machine.maxed(GameState.machine, catalog, n.id):
				return str(n.id)
	for n in catalog.machine_tree.nodes:
		if Machine.look(GameState.machine, catalog, n.id) == "next" or (Machine.owned(GameState.machine, n.id) > 0 and not Machine.maxed(GameState.machine, catalog, n.id)):
			if best == "" or Machine.cost(GameState.machine, catalog, n.id) < Machine.cost(GameState.machine, catalog, best):
				best = n.id
	return best if best != "" else str(catalog.machine_tree.nodes[0].id)


## A node's colour: a later globe's nodes wear the globe's colour, the first globe's their branch's.
static func node_color(n: Dictionary) -> Color:
	var g := Machine.globe_of(Catalog.shared(), n)
	if g != Machine.first_globe(Catalog.shared()):
		return MachineTab.globe_color(g)
	return color_of(str(n.branch))


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
	var mini := MachineMini.new(Machine.globe_of(catalog, n))
	mini.size_flags_horizontal = SIZE_SHRINK_CENTER
	_detail.add_child(mini)
	var look := Machine.look(state, catalog, _picked)
	if look == "hidden" or look == "away":
		return  # not on the tree yet
	var color := node_color(n)
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
		costs.add_child(_cost_row("bit_" + b, "%d %s" % [int(need[b]), Machine.bit_name(catalog, b, int(need[b]))], have >= int(need[b]), "you have %d" % have))
		if have < int(need[b]):
			var hint := UiTheme.label(GameState.bit_hint(b), UiTheme.MUTED, UiTheme.SMALL)
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.custom_minimum_size.x = 170  # wraps inside the cost box, never widens the side panel
			costs.add_child(hint)
	_detail.add_child(box)
	var why := Machine.blocker(state, catalog, _picked, GameState.coins, GameState.bits)
	var text := "fix it" if n.branch in REPAIRS else "upgrade"
	if why == "coins":
		text = "not enough coins"
	elif why != "":
		text = "not yet"
	var go := UiTheme.button(text, func():
		if GameState.buy_machine_upgrade(_picked):
			MachineTab.cheer(self, _picked)
			_stale = true  # the new level and price show straight away, not with the next catch-up
			_stale_wait = 0.0)
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
	var viewing := ""  # the globe whose part of the tree is framed (frame() sets it)
	var _view := Rect2(Vector2.ZERO, MAP)  # the part of the map that's framed (tweened when panning)
	var _time := 0.0
	var _alpha := 1.0  # older globes' nodes fade behind the one you're looking at
	var _tween: Tween
	var _breath := Control.new()  # the breathing rings round the nodes you can work on now, redrawn every frame
	var _rings: Array = []  # [centre, radius, colour, alpha] per breathing node, from the last _draw
	var _drawn_view := Rect2()  # the view the last _draw framed (a pan redraws)
	var _looks := {}  # node id -> its Machine.look, during one _draw
	var _drawing := false

	## Frames globe `g`'s part of the tree (its "view"), sliding over when `animate`.
	func frame(g: String, animate: bool) -> void:
		viewing = g
		var v: Array = Machine.globe(Catalog.shared(), g).get("view", [0, 0, MAP.x, MAP.y])
		var target := Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
		if _tween:
			_tween.kill()
		if animate and is_inside_tree():
			_tween = create_tween()
			_tween.tween_property(self, "_view", target, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		else:
			_view = target
		queue_redraw()

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		# the tree itself only redraws when something changes (it took ~10 ms late in the game)
		_breath.mouse_filter = MOUSE_FILTER_IGNORE
		_breath.set_anchors_preset(PRESET_FULL_RECT)
		_breath.draw.connect(_draw_breath)
		add_child(_breath)
		resized.connect(queue_redraw)

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_time += delta
			if _view != _drawn_view:
				queue_redraw()
			if not _rings.is_empty():
				_breath.queue_redraw()

	func _draw_breath() -> void:
		var breathe := 0.5 + 0.5 * sin(_time * 3.0)
		for ring in _rings:
			var color: Color = ring[2]
			_breath.draw_arc(ring[0], ring[1] + 4.0 + breathe * 4.0, 0, TAU, 40, Color(color, (0.5 - breathe * 0.35) * float(ring[3])), 2.0, true)

	func _scale() -> float:
		return minf((size.x - 60.0) / _view.size.x, (size.y - 50.0) / _view.size.y)

	func _at(n: Dictionary) -> Vector2:
		var s := _scale()
		var origin := (size - _view.size * s) / 2.0 + Vector2(0, -4)
		return origin + (Vector2(float(n.at[0]), float(n.at[1])) - _view.position) * s

	func _radius(n: Dictionary) -> float:
		return (26.0 if n.branch in MachineTreeView.REPAIRS else 21.0) * clampf(_scale(), 0.75, 1.2)

	func _shown(n: Dictionary) -> bool:
		if not _drawing:  # clicks see the machine as it is now
			return not Machine.look(GameState.machine, Catalog.shared(), n.id) in ["away", "hidden"]
		if not _looks.has(n.id):
			_looks[n.id] = Machine.look(GameState.machine, Catalog.shared(), n.id)
		return not _looks[n.id] in ["away", "hidden"]

	## A colour faded like the node being drawn.
	func _k(c: Color) -> Color:
		return Color(c.r, c.g, c.b, c.a * _alpha)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			for n in Catalog.shared().machine_tree.nodes:
				if _shown(n) and event.position.distance_to(_at(n)) < _radius(n) + 6.0:
					picked_id = n.id
					picked.emit(n.id)
					queue_redraw()
					return
		elif event is InputEventMouseMotion:
			var over := false
			for n in Catalog.shared().machine_tree.nodes:
				over = over or (_shown(n) and event.position.distance_to(_at(n)) < _radius(n) + 6.0)
			mouse_default_cursor_shape = CURSOR_POINTING_HAND if over else CURSOR_ARROW

	func _draw() -> void:
		_drawn_view = _view
		_rings.clear()
		_looks.clear()  # worked out once per draw (_draw_name asks about every node on the row)
		_drawing = true
		draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		var nodes: Array = catalog.machine_tree.nodes
		var many := Machine.home(state, catalog).size() > 1
		# links first
		for n in nodes:
			if not n.has("from") or not _shown(n):
				continue
			var from := Machine.node(catalog, n.from)
			var a := _at(from)
			var b := _at(n)
			var on := Machine.owned(state, n.id) > 0
			_alpha = 1.0 if not many or Machine.globe_of(catalog, n) == viewing else 0.45
			if on:
				draw_line(a, b, _k(MachineTreeView.node_color(n).lerp(UiTheme.LINE, 0.4) if Machine.globe_of(catalog, n) != Machine.first_globe(catalog) else UiTheme.LILAC_SEAM), 3.0, true)
			else:
				draw_dashed_line(a, b, _k(UiTheme.LINE), 3.0, 7.0, true)
		var font := UiTheme.BODY_FONT
		for n in nodes:
			var look := Machine.look(state, catalog, n.id)
			if look == "away" or look == "hidden":
				continue  # not there yet: nothing unearned shows as a "?"
			_alpha = 1.0 if not many or Machine.globe_of(catalog, n) == viewing else 0.45
			var c := _at(n)
			var r := _radius(n)
			var color := MachineTreeView.node_color(n)
			match look:
				"owned":
					draw_circle(c, r, _k(UiTheme.PAGE.lerp(color, 0.3)))
					draw_arc(c, r, 0, TAU, 40, _k(color), 3.0, true)
				"next":
					_rings.append([c, r, color, _alpha])
					draw_circle(c, r, _k(UiTheme.RAISED))
					_dashed_ring(c, r, color)
				_:
					draw_circle(c, r, _k(UiTheme.DEEP))
					draw_arc(c, r, 0, TAU, 40, _k(UiTheme.LINE), 3.0, true)
			if n.id == picked_id:
				draw_arc(c, r + 3.0, 0, TAU, 40, _k(UiTheme.TEXT), 2.0, true)
			var icon := UiTheme.icon("tree_" + str(n.icon), 22, color if look != "dim" else UiTheme.LOCKED)
			draw_texture_rect(icon, Rect2(c - Vector2(11, 11), Vector2(22, 22)), false, Color(1, 1, 1, _alpha))
			var level := Machine.owned(state, n.id)
			var max_level := int(n.get("max", 1))
			if max_level > 1:
				# the body font: the display font's slash leans back ("3\3")
				var pill := "%d/%d" % [level, max_level]
				var pw := maxf(32.0, UiTheme.BODY_FONT.get_string_size(pill, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10.0)
				var pr := Rect2(c + Vector2(-pw / 2.0, r - 8), Vector2(pw, 15))
				draw_style_box(UiTheme.box(_k(UiTheme.GOLD), _k(UiTheme.GOLD), 7, 0, 0), pr)
				draw_string(UiTheme.BODY_FONT, pr.position + Vector2(0, 11.5), pill, HORIZONTAL_ALIGNMENT_CENTER, pr.size.x, 11, _k(UiTheme.DEEP))
			# waiting for a bit you don't have
			if look == "next" and not Machine.maxed(state, catalog, n.id):
				var need := Machine.bits_cost(catalog, n.id)
				for b in need:
					if int(GameState.bits.get(b, 0)) < int(need[b]):
						var bc := c + Vector2(r * 0.75, -r * 0.8)
						draw_circle(bc, 11.0, _k(UiTheme.DEEP))
						draw_arc(bc, 11.0, 0, TAU, 24, _k(UiTheme.PINK), 2.0, true)
						draw_texture_rect(UiTheme.icon("bit_" + str(b), 16), Rect2(bc - Vector2(8, 8), Vector2(16, 16)), false, Color(1, 1, 1, _alpha))
						break
			var label_y := r + (22.0 if max_level > 1 else 16.0)
			var name_color := UiTheme.TEXT if look in ["owned", "next"] else UiTheme.MUTED
			if Machine.globe_of(catalog, n) != Machine.first_globe(catalog):
				# a later globe's repairs are a chain going up: their names sit beside them
				draw_string(font, c + Vector2(r + 10.0, 5.0), str(n.name), HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL + 1, _k(name_color))
			else:
				_draw_name(font, n, c, label_y, _k(name_color))
		_alpha = 1.0
		_drawing = false

	## A first-globe node's name under it, wrapped to the room between it and its neighbours on the
	## same row (and the panel's edges) so names never run into each other; a smaller hand if a word
	## is still too wide. A paper patch behind each line keeps it clear of the links.
	func _draw_name(font: Font, n: Dictionary, c: Vector2, label_y: float, color: Color) -> void:
		var half := minf(70.0, minf(c.x - 6.0, size.x - 6.0 - c.x))
		for o in Catalog.shared().machine_tree.nodes:
			if o.id == n.id or not _shown(o) or Machine.globe_of(Catalog.shared(), o) != Machine.globe_of(Catalog.shared(), n):
				continue
			var p := _at(o)
			if absf(p.y - c.y) < 4.0:
				half = minf(half, absf(p.x - c.x) / 2.0 - 3.0)
		var width := half * 2.0
		var fs := UiTheme.SMALL + 1
		var lines := _wrap(font, str(n.name), width, fs)
		while fs > UiTheme.SMALL - 1 and lines.any(func(l): return font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width):
			fs -= 1
			lines = _wrap(font, str(n.name), width, fs)
		var y := c.y + label_y
		for l in lines:
			var w := font.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_rect(Rect2(c.x - w / 2.0 - 2.0, y - fs + 1.0, w + 4.0, fs + 3.0), _k(UiTheme.PAPER))
			draw_string(font, Vector2(c.x - w / 2.0, y), l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
			y += fs + 2.0

	## Words packed into lines no wider than `width` (a lone long word gets a line of its own).
	func _wrap(font: Font, text: String, width: float, fs: int) -> Array:
		var lines := []
		var line := ""
		for word in text.split(" "):
			var tried := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(tried, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
				lines.append(line)
				line = word
			else:
				line = tried
		if line != "":
			lines.append(line)
		return lines

	func _dashed_ring(c: Vector2, r: float, color: Color) -> void:
		for i in 16:
			var a := TAU * i / 16.0
			draw_arc(c, r, a, a + TAU / 32.0, 4, _k(color), 3.0, true)


## A little picture of the machine for the upgrade page: what's still broken shows (the crack, the
## cloudy glass, rust, a stuck flap, dead lights; a later globe's nest, holes, sagging lever and
## rusted hatch), and what's fixed doesn't. It draws the globe the picked node belongs to.
class MachineMini extends Control:
	var globe := ""

	func _init(g := "") -> void:
		globe = g if g != "" else Machine.first_globe(Catalog.shared())
		custom_minimum_size = Vector2(120, 120)
		mouse_filter = MOUSE_FILTER_IGNORE
		GameState.changed.connect(queue_redraw)

	func _draw() -> void:
		var state: Dictionary = GameState.machine
		var catalog := Catalog.shared()
		var info := Machine.globe(catalog, globe)
		var broken := func(fix: String) -> bool: return Machine.broken(state, catalog, globe, fix)
		var mended := func(fix: String) -> bool: return Machine.has_fix(catalog, globe, fix) and not Machine.broken(state, catalog, globe, fix)
		var glass_c := UiTheme.named_color(str(info.get("glass", "lilac")), UiTheme.LILAC)
		var body_c := UiTheme.named_color(str(info.get("body", "pink")), UiTheme.PINK)
		var seam_c := UiTheme.named_color(str(info.get("seam", "pink_seam")), UiTheme.PINK_SEAM)
		var rust := MachineTab.MachineStage.RUST
		var g := Vector2(60, 42)
		draw_circle(g, 32.0, UiTheme.PAGE.lerp(glass_c, 0.09))
		if mended.call("amber"):
			draw_circle(g, 32.0, Color(glass_c.lerp(UiTheme.GOLD, 0.45), 0.14))
		if broken.call("glass") or broken.call("amber"):
			draw_circle(g + Vector2(10, -8), 12.0, Color(UiTheme.TEXT, 0.08))
			draw_polyline(PackedVector2Array([g + Vector2(-20, -10), g + Vector2(-12, -14), g + Vector2(-8, -6), g + Vector2(0, -12)]), Color(UiTheme.MUTED, 0.7), 1.5, true)
		if broken.call("crack"):
			draw_polyline(PackedVector2Array([g + Vector2(14, -26), g + Vector2(20, -14), g + Vector2(16, -6), g + Vector2(24, 4)]), UiTheme.MUTED, 2.0, true)
		elif mended.call("crack"):
			draw_line(g + Vector2(14, -24), g + Vector2(28, -10), Color(UiTheme.GOLD, 0.8), 5.0)
		if broken.call("nest"):
			draw_polyline(PackedVector2Array([g + Vector2(-18, 22), g + Vector2(0, 28), g + Vector2(18, 22)]), rust, 3.0, true)
			for leaf in [Vector2(52, 8), Vector2(66, 6), Vector2(74, 12)]:
				draw_circle(leaf, 3.5, UiTheme.MINT.darkened(0.3))
		for h in [g + Vector2(-16, -6), g + Vector2(18, 8), g + Vector2(-4, 18)]:
			if broken.call("holes"):
				draw_circle(h, 3.2, UiTheme.DEEP)
				draw_arc(h, 3.2, 0, TAU, 12, glass_c, 1.2, true)
			elif mended.call("holes"):
				draw_circle(h, 3.2, MachineTab.MachineStage.CORK)
		draw_arc(g, 32.0, 0, TAU, 40, glass_c, 2.5, true)
		if Machine.has_fix(catalog, globe, "hatch"):
			var open := Machine.hatch_open(state, catalog, globe)
			draw_rect(Rect2(g + Vector2(-12, -38), Vector2(24, 7)), UiTheme.PAGE.lerp(body_c if open else rust, 0.5))
		var body := PackedVector2Array([Vector2(30, 74), Vector2(90, 74), Vector2(94, 110), Vector2(26, 110)])
		draw_colored_polygon(body, UiTheme.PAGE.lerp(body_c, 0.22))
		body.append(body[0])
		draw_polyline(body, body_c, 2.5, true)
		if broken.call("rust") or broken.call("nest"):
			draw_circle(Vector2(40, 98), 3.0, rust)
			draw_circle(Vector2(80, 84), 2.5, rust)
		var chutes := Machine.chutes(state, catalog, globe)
		for i in chutes:
			var x := 60.0 + (i - (chutes - 1) / 2.0) * 16.0
			var rect := Rect2(x - 7, 92, 14, 14)
			var tilt := 0.25 if broken.call("flap") and i == 0 else 0.0
			draw_set_transform(rect.get_center(), tilt, Vector2.ONE)
			draw_style_box(UiTheme.box(UiTheme.DEEP, seam_c, 3, 2, 0), Rect2(-rect.size / 2.0, rect.size))
			draw_set_transform(Vector2.ZERO)
		var lit := Machine.lights_on(state, catalog, globe)
		for i in 5:
			draw_circle(Vector2(44 + i * 8, 82), 2.2, UiTheme.GOLD if lit else UiTheme.LINE)
		if broken.call("sag"):
			draw_line(Vector2(94, 88), Vector2(108, 100), UiTheme.GOLD, 4.0, true)
			draw_circle(Vector2(110, 103), 5.0, UiTheme.PINK)
		else:
			draw_line(Vector2(94, 88), Vector2(104, 70), UiTheme.GOLD, 4.0, true)
			draw_circle(Vector2(105, 67), 5.0, UiTheme.PINK)
			if mended.call("sag"):
				draw_arc(Vector2(108, 56), 4.0, 0, TAU, 12, UiTheme.LILAC, 1.6, true)
