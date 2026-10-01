class_name WorkbenchTab
extends VBoxContainer
## The workbench (was the bag): "your pet" is the bag and the sewing table (InventoryTab), "toys"
## is the toy bench (ToyBench): combine spares into levels, fix wear, sacrifice spares for a chance
## at a special finish, shine favourites with the spares left over; "plushie machine" (PlushieMachine) sews buttons onto a pet's parts, hidden
## until the machine is found. Design: design/mockups/screens/upgrading.html, workbench-toys.html (toys, look B), sacrifice-reels.html.

var bag := InventoryTab.new()
var bench := ToyBench.new()
var plushie := PlushieMachine.new()
var _mode: PanelContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = SIZE_EXPAND_FILL
	_mode = UiTheme.segmented(["your pet", "toys", "plushie machine"], 0, func(i):
		bag.visible = i == 0
		bench.visible = i == 1
		plushie.visible = i == 2
		if i == 1:
			PetBubble.say_line(self, "workbench_toys"))
	_mode.size_flags_horizontal = SIZE_SHRINK_BEGIN
	add_child(_mode)
	bag.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(bag)
	bench.size_flags_vertical = SIZE_EXPAND_FILL
	bench.visible = false
	add_child(bench)
	plushie.visible = false
	add_child(plushie)
	# sewing parts onto your pet comes much later: until then the workbench is just for toys; the
	# plushie machine stays out of sight until it's found
	var sewing := _mode.get_child(0).get_child(0) as Control
	var machine := _mode.get_child(0).get_child(2) as Control
	var pages_open := func():
		sewing.visible = GameState.feature_on("parts")
		machine.visible = GameState.plushie_open()
		if (not sewing.visible and bag.visible) or (not machine.visible and plushie.visible):
			show_page(1)
	GameState.changed.connect(pages_open)
	pages_open.call()
	visibility_changed.connect(speak)
	# the machine just came home: the workbench opens on it
	GameState.unlocked.connect(func(entry: Dictionary):
		if "feature:plushie" in entry.get("opens", []):
			pages_open.call()
			show_page(2))


## Your pet says something about the toys page when the tab opens on it (the other pages speak for
## themselves when they show; having speak() keeps the full game from adding a general line too).
func speak() -> void:
	if is_visible_in_tree() and bench.visible:
		PetBubble.say_line(self, "workbench_toys")


## 0 your pet, 1 toys, 2 the plushie machine (flips the switch at the top too).
func show_page(page: int) -> void:
	(_mode.get_child(0).get_child(page) as Button).pressed.emit()


## Opens the toy bench with this edition picked (from the toys page).
func show_toy(edition: String) -> void:
	show_page(1)
	bench.pick(edition)


## The toy bench: a row per toy you have on the left; on the right the picked toy: its editions
## (combine, fix), sacrifice (x1, x10, all) and, for a favourite, shining it with its spares.
## Design: design/mockups/screens/workbench-toys.html (look B).
class ToyBench extends HBoxContainer:
	const STALE_EVERY := 3.0
	const SACRIFICE_STEPS := [1, 10]  # tries a button risks, then one for all

	var _rows := VBoxContainer.new()
	var _right := VBoxContainer.new()
	var _picked := ""  # "toy:finish"
	var _result := {}  # what the last sacrifice brought: finish (or "nothing") -> how many
	var _dirty := true
	var _stale := false  # toys came in by themselves: built again at most every STALE_EVERY s
	var _stale_at := 0.0

	func _init() -> void:
		add_theme_constant_override("separation", 14)
		var left := ScrollContainer.new()
		left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		left.custom_minimum_size = Vector2(272, 0)
		_rows.size_flags_horizontal = SIZE_EXPAND_FILL
		_rows.add_theme_constant_override("separation", 6)
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = SIZE_EXPAND_FILL
		pad.add_theme_constant_override("margin_right", 8)
		pad.add_child(_rows)
		left.add_child(pad)
		add_child(left)
		_right.size_flags_horizontal = SIZE_EXPAND_FILL
		_right.add_theme_constant_override("separation", 10)
		add_child(_right)
		GameState.toys_changed.connect(func(): _stale = true)
		GameState.changed.connect(func(): _stale = true)
		visibility_changed.connect(func():
			if is_visible_in_tree():
				_rebuild())

	func pick(edition: String) -> void:
		if Toys.split(edition)[0] != Toys.split(_picked)[0]:
			_result = {}
		_picked = edition
		_rebuild()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_stale_at -= delta
		if _dirty or (_stale and _stale_at <= 0.0):
			_rebuild()

	func _rebuild() -> void:
		_dirty = false
		_stale = false
		_stale_at = STALE_EVERY
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var toys: Array = Toys.all(catalog).filter(func(t): return Toys.has_toy(state, t.id))
		if not toys.any(func(t): return t.id == Toys.split(_picked)[0]) or not state.owned.has(_picked):
			_picked = _best_edition(str(toys[0].id)) if not toys.is_empty() else ""
		UiTheme.clear(_rows)
		UiTheme.clear(_right)
		if toys.is_empty():
			_rows.add_child(UiTheme.label("no toys yet: they come out of the capsule machine", UiTheme.MUTED, UiTheme.SMALL + 1))
			return
		for t in toys:
			_rows.add_child(_row(t))
		_build_right()

	## The editions you have of a toy, plainest first.
	func _editions(id: String) -> Array:
		var out: Array = []
		for f in Catalog.shared().toys.finishes:
			if GameState.toys.owned.has(Toys.key(id, f.id)):
				out.append(Toys.key(id, f.id))
		return out

	## The edition a tap on a toy's row picks: one that's ready to combine or shine, else the one
	## with the most spares.
	func _best_edition(id: String) -> String:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var best := ""
		for k in _editions(id):
			if Toys.can_combine(state, catalog, k) or Toys.can_shine(state, catalog, k):
				return k
			if best == "" or int(state.owned[k].spares) > int(state.owned[best].spares):
				best = k
		return best

	func _spares_of(id: String) -> int:
		var n := 0
		for k in _editions(id):
			n += int(GameState.toys.owned[k].spares)
		return n

	# ---- the list on the left -----------------------------------------------------------

	func _row(t: Dictionary) -> Control:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var id := str(t.id)
		var on := id == Toys.split(_picked)[0]
		var eds := _editions(id)
		var b := Button.new()
		b.name = "toy_" + id
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		b.custom_minimum_size = Vector2(0, 50)
		var style: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 6) if on else UiTheme.box(UiTheme.RAISED, UiTheme.LINE, 10, 2, 6)
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, style)
		b.pressed.connect(func(): pick(_best_edition(id)))
		var row := HBoxContainer.new()
		row.set_anchors_preset(PRESET_FULL_RECT)
		row.offset_left = 8
		row.offset_right = -10
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(row)
		var art := ToyView.new(id, "normal", 3)  # the dots say which finishes
		art.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(art)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.size_flags_vertical = SIZE_SHRINK_CENTER
		col.add_theme_constant_override("separation", 2)
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 6)
		name_row.add_child(UiTheme.label(str(t.name), UiTheme.TEXT, UiTheme.SMALL + 1))
		var ready := eds.filter(func(k): return Toys.can_combine(state, catalog, k) or Toys.can_shine(state, catalog, k)).size()
		if ready > 0:
			name_row.add_child(_tag("%d ready!" % ready if ready > 1 else "ready!", UiTheme.GOLD))
		col.add_child(name_row)
		var dots := HBoxContainer.new()
		dots.add_theme_constant_override("separation", 4)
		for k in eds:
			dots.add_child(FinishDot.new(Toys.split(k)[1], Toys.is_favourite(state, catalog, k)))
		col.add_child(dots)
		row.add_child(col)
		var count := UiTheme.label("x" + UiTheme.num(_spares_of(id) + eds.size()), UiTheme.MUTED, UiTheme.SMALL + 1)
		count.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(count)
		for c in [art, col, count] + col.get_children() + name_row.get_children() + dots.get_children():
			c.mouse_filter = MOUSE_FILTER_IGNORE
		return b

	func _tag(text: String, color: Color) -> Label:
		var l := UiTheme.label(text, UiTheme.DEEP, UiTheme.SMALL)
		var box := UiTheme.box(color, color, 9, 0, 0)
		box.content_margin_left = 6
		box.content_margin_right = 6
		l.add_theme_stylebox_override("normal", box)
		return l

	# ---- the picked toy -----------------------------------------------------------------

	func _build_right() -> void:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var bits := Toys.split(_picked)
		var id := bits[0]
		var t := Toys.toy(catalog, id)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 12)
		var art := ToyView.new(id, bits[1], 4)
		head.add_child(art)
		var words := VBoxContainer.new()
		words.size_flags_vertical = SIZE_SHRINK_CENTER
		words.add_theme_constant_override("separation", 0)
		words.add_child(UiTheme.title(str(t.name), 20))
		words.add_child(UiTheme.label(str(t.tier), MachineTab.MachineStage._tier_color(t.tier), UiTheme.SMALL + 1))
		head.add_child(words)
		head.add_child(UiTheme.spacer())
		var spares := UiTheme.title("%s spare" % UiTheme.num(_spares_of(id)), 15, UiTheme.TEXT)
		spares.size_flags_vertical = SIZE_SHRINK_CENTER
		head.add_child(spares)
		_right.add_child(head)

		var eds := HBoxContainer.new()
		eds.add_theme_constant_override("separation", 8)
		for k in _editions(id):
			eds.add_child(_edition_card(k))
		_right.add_child(eds)
		_right.add_child(_sacrifice_card(id))
		if Toys.is_favourite(state, catalog, _picked):
			_right.add_child(_shine_card())

	## One edition: its level and spares, what it's ready for, and combine / fix right there.
	func _edition_card(edition: String) -> Control:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var e: Dictionary = state.owned[edition]
		var fin := Toys.finish(catalog, Toys.split(edition)[1])
		var on := edition == _picked
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.mouse_filter = MOUSE_FILTER_STOP
		panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.PINK if on else UiTheme.LINE, 10, 2, 8))
		panel.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				pick(edition))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		panel.add_child(col)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.add_child(FinishDot.new(str(fin.id), Toys.is_favourite(state, catalog, edition)))
		top.add_child(UiTheme.label(str(fin.name), UiTheme.TEXT, UiTheme.SMALL + 1))
		top.add_child(UiTheme.spacer())
		top.add_child(UiTheme.label("lv %d" % int(e.level), UiTheme.GOLD, UiTheme.SMALL + 1))
		col.add_child(top)
		col.add_child(UiTheme.label("%s spare" % UiTheme.num(int(e.spares)), UiTheme.MUTED, UiTheme.SMALL))
		var now := Time.get_unix_time_from_system()
		var need := Toys.combine_cost(state, catalog, edition)
		if Toys.can_combine(state, catalog, edition):
			col.add_child(_small_button("combine", func():
				if GameState.combine_toy_all(edition) > 0:
					PetBubble.say_line(self, "toy_combined")
				pick(edition)))
		elif need > 0:
			col.add_child(UiTheme.label("%d more for lv %d" % [need - int(e.spares), int(e.level) + 1], UiTheme.MUTED, UiTheme.SMALL))
		else:
			var st := Toys.stars(state, edition)
			col.add_child(UiTheme.label("max" + ("  " + "★".repeat(st) if st > 0 else ""), UiTheme.GOLD, UiTheme.SMALL))
		var price := Toys.fix_cost(state, catalog, edition)
		if price > 0 and not Toys.is_favourite(state, catalog, edition):
			var fix := _small_button("fix  %s" % UiTheme.num(price), func():
				if GameState.fix_toy(edition):
					PetBubble.say_line(self, "toy_fixed")
				pick(edition))
			fix.disabled = GameState.coins < price or Toys.playing(state, edition, now)
			fix.tooltip_text = ToysView._wear_word(float(e.wear))
			col.add_child(fix)
		return panel

	func _small_button(text: String, on_pressed: Callable) -> Button:
		var b := UiTheme.button(text, on_pressed)
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		return b

	func _card(title: String, accent: Color) -> VBoxContainer:
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiTheme.stitched(accent.lerp(UiTheme.LINE, 0.5), UiTheme.RAISED, 12, 10))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)
		col.add_child(UiTheme.title(title, 15, accent))
		return col  # the caller adds its panel (col.get_parent()) where it goes

	## Spares of the normal edition for a chance at a fancy one: once, ten times or all at once.
	func _sacrifice_card(id: String) -> Control:
		var catalog := Catalog.shared()
		var sac: Dictionary = catalog.toys.sacrifice
		var state: Dictionary = GameState.toys
		var col := _card("sacrifice", UiTheme.PINK)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var normal := Toys.key(id, "normal")
		var tries := Toys.sacrifice_tries(state, catalog, id)
		for i in int(sac.spares):
			row.add_child(ToyView.new(id, "normal", 2, tries <= 0))
		row.add_child(UiTheme.label(" %s normal spare" % UiTheme.num(int(state.owned.get(normal, {}).get("spares", 0))), UiTheme.MUTED, UiTheme.SMALL + 1))
		row.add_child(UiTheme.spacer())
		var steps: Array = SACRIFICE_STEPS.filter(func(n): return n < tries)
		for n in steps:
			row.add_child(_risk_button("x%d" % n if n > 1 else "risk it", id, n, false))
		row.add_child(_risk_button("all %s" % UiTheme.num(tries) if tries > 1 else "risk it", id, maxi(1, tries), tries <= 0))
		col.add_child(row)
		var odds := HBoxContainer.new()
		odds.add_theme_constant_override("separation", 12)
		var total := 0.0
		for k in sac.odds:
			total += float(sac.odds[k])
		for k in sac.odds:
			var name := "nothing" if k == "nothing" else str(Toys.finish(catalog, k).name)
			odds.add_child(UiTheme.label("%s %s" % [name, UiTheme.percent(float(sac.odds[k]) / total)], UiTheme.MUTED if k == "nothing" else UiTheme.TEXT, UiTheme.SMALL))
		col.add_child(odds)
		if not _result.is_empty():
			var got := HBoxContainer.new()
			got.add_theme_constant_override("separation", 10)
			for f in catalog.toys.finishes:
				if _result.has(f.id):
					got.add_child(UiTheme.label("+%s %s" % [UiTheme.num(int(_result[f.id])), f.name], UiTheme.MINT, UiTheme.SMALL + 1))
			if _result.has("nothing"):
				var empty := HBoxContainer.new()
				empty.add_theme_constant_override("separation", 5)
				empty.add_child(UiTheme.label(UiTheme.num(int(_result.nothing)), UiTheme.TEXT, UiTheme.SMALL + 1))
				empty.add_child(UiTheme.label("came up empty", UiTheme.MUTED, UiTheme.SMALL + 1))
				got.add_child(empty)
			col.add_child(got)
		return col.get_parent()

	func _risk_button(text: String, id: String, tries: int, off: bool) -> Button:
		var b := _small_button(text, func():
			_result = GameState.sacrifice_toys(id, tries)
			var won := _result.keys().any(func(k): return k != "nothing")
			PetBubble.say_line(self, "toy_sacrificed_win" if won else "toy_sacrificed_lose")
			_dirty = true)
		b.add_theme_color_override("font_color", UiTheme.PINK)
		b.disabled = off
		return b

	## A favourite's spares shine it: a star at a time, each ten times dearer, each a bit more boost.
	func _shine_card() -> Control:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var e: Dictionary = state.owned[_picked]
		var col := _card("shine it up", UiTheme.LILAC)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var bits := Toys.split(_picked)
		var art := ToyView.new(bits[0], bits[1], 5)
		row.add_child(art)
		var words := VBoxContainer.new()
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		words.size_flags_vertical = SIZE_SHRINK_CENTER
		words.add_theme_constant_override("separation", 4)
		var st := Toys.stars(state, _picked)
		var stars := UiTheme.label("★".repeat(st) + "☆", UiTheme.GOLD, 18)
		words.add_child(stars)
		var need := Toys.shine_cost(state, catalog, _picked)
		var now_x := Toys.boost(state, catalog, _picked)
		e.stars = st + 1  # what the next star would make it
		var next_x := Toys.boost(state, catalog, _picked)
		e.stars = st
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.add_child(UiTheme.label("%s of %s" % [UiTheme.num(mini(int(e.spares), need)), UiTheme.num(need)], UiTheme.MUTED, UiTheme.SMALL + 1))
		line.add_child(UiTheme.label("x%s → x%s" % [ToysView._num(now_x), ToysView._num(next_x)], UiTheme.MINT, UiTheme.SMALL + 1))
		words.add_child(line)
		row.add_child(words)
		var go := UiTheme.button("shine", func():
			if GameState.shine_toy(_picked):
				PetBubble.say_line(self, "toy_shined")
			pick(_picked))
		go.disabled = not Toys.can_shine(state, catalog, _picked)
		go.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(go)
		col.add_child(row)
		return col.get_parent()


## A finish as a small dot (normal, holo, gold foil, ghost); a gold ring once it's a favourite.
class FinishDot extends Control:
	var _finish := ""
	var _max := false

	func _init(finish_id: String, maxed := false) -> void:
		_finish = finish_id
		_max = maxed
		custom_minimum_size = Vector2(12, 12)
		size_flags_vertical = SIZE_SHRINK_CENTER
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		if _max:
			draw_circle(c, 6.0, UiTheme.GOLD)
		var colors := { "normal": UiTheme.TEXT, "holo": UiTheme.LILAC, "foil": UiTheme.GOLD, "ghost": UiTheme.CYAN }
		draw_circle(c, 4.5, colors.get(_finish, UiTheme.TEXT))
