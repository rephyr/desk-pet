class_name WorkbenchTab
extends VBoxContainer
## The workbench (was the bag): "your pet" is the bag and the sewing table (InventoryTab), "toys"
## is the toy bench (ToyBench): combine spares into levels, fix wear, sacrifice spares for a chance
## at a special finish. Design: design/mockups/screens/upgrading.html.

var bag := InventoryTab.new()
var bench := ToyBench.new()
var _mode: PanelContainer


func _init() -> void:
	add_theme_constant_override("separation", 8)
	size_flags_vertical = SIZE_EXPAND_FILL
	_mode = UiTheme.segmented(["your pet", "toys"], 0, func(i):
		bag.visible = i == 0
		bench.visible = i == 1
		if i == 1:
			PetBubble.say_line(self, "workbench_toys"))
	_mode.size_flags_horizontal = SIZE_SHRINK_BEGIN
	add_child(_mode)
	bag.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(bag)
	bench.size_flags_vertical = SIZE_EXPAND_FILL
	bench.visible = false
	add_child(bench)
	# sewing parts onto your pet comes much later: until then the workbench is just for toys
	var sewing := _mode.get_child(0).get_child(0) as Control
	var parts_open := func():
		sewing.visible = GameState.feature_on("parts")
		if not sewing.visible and bag.visible:
			(_mode.get_child(0).get_child(1) as Button).pressed.emit()
	GameState.changed.connect(parts_open)
	parts_open.call()


## Opens the toy bench with this edition picked (from the toys page).
func show_toy(edition: String) -> void:
	(_mode.get_child(0).get_child(1) as Button).pressed.emit()
	bench.pick(edition)


## The toy bench: three benches side by side for the toy picked in the tray under them.
class ToyBench extends VBoxContainer:
	var _benches := HBoxContainer.new()
	var _tray := HBoxContainer.new()
	var _picked := ""  # "toy:finish"
	var _result := ""  # what the last sacrifice brought ("" nothing yet, "nothing", or a finish)
	var _dirty := true

	func _init() -> void:
		add_theme_constant_override("separation", 10)
		_benches.add_theme_constant_override("separation", 12)
		_benches.size_flags_vertical = SIZE_EXPAND_FILL
		add_child(_benches)
		add_child(UiTheme.title("your toys", 14, UiTheme.LILAC))
		var scroll := ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.custom_minimum_size = Vector2(0, 92)
		var pad := MarginContainer.new()
		pad.add_theme_constant_override("margin_top", 8)
		pad.add_theme_constant_override("margin_right", 8)
		pad.add_theme_constant_override("margin_left", 4)
		_tray.add_theme_constant_override("separation", 10)
		pad.add_child(_tray)
		scroll.add_child(pad)
		add_child(scroll)
		GameState.toys_changed.connect(func(): _dirty = true)
		GameState.changed.connect(func(): _dirty = true)
		visibility_changed.connect(func():
			if is_visible_in_tree():
				_rebuild())

	func pick(edition: String) -> void:
		_picked = edition
		_result = ""
		_rebuild()

	func _process(_delta: float) -> void:
		if is_visible_in_tree() and _dirty:
			_rebuild()

	func _rebuild() -> void:
		_dirty = false
		var state: Dictionary = GameState.toys
		var editions: Array = []
		for t in Toys.all(Catalog.shared()):
			for f in Catalog.shared().toys.finishes:
				var k := Toys.key(t.id, f.id)
				if state.owned.has(k):
					editions.append(k)
		if not _picked in editions:
			_picked = editions[0] if not editions.is_empty() else ""
		UiTheme.clear(_tray)
		for k in editions:
			_tray.add_child(_chip(k))
		if editions.is_empty():
			_tray.add_child(UiTheme.label("no toys yet: they come out of the capsule machine", UiTheme.MUTED, UiTheme.SMALL + 1))
		UiTheme.clear(_benches)
		_benches.add_child(_combine_bench())
		_benches.add_child(_fix_bench())
		_benches.add_child(_sacrifice_bench())

	func _chip(edition: String) -> Control:
		var state: Dictionary = GameState.toys
		var bits := Toys.split(edition)
		var t := Toys.toy(Catalog.shared(), bits[0])
		var e: Dictionary = state.owned[edition]
		var b := Button.new()
		b.focus_mode = FOCUS_NONE
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var tier_color := MachineTab.MachineStage._tier_color(t.tier)
		var style: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 6) if edition == _picked else UiTheme.box(UiTheme.RAISED, tier_color, 10, 2, 6)
		for s in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(s, style)
		b.custom_minimum_size = Vector2(76, 80)
		b.pressed.connect(func(): pick(edition))
		var col := VBoxContainer.new()
		col.set_anchors_preset(PRESET_FULL_RECT)
		col.offset_top = 4
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_theme_constant_override("separation", 0)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		var art := ToyView.new(bits[0], bits[1], 3)
		art.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(art)
		var l := UiTheme.label(ToysView._edition_name(edition), UiTheme.MUTED, UiTheme.SMALL)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.custom_minimum_size.x = 70
		col.add_child(l)
		for c in col.get_children():
			c.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(col)
		var count := UiTheme.label("lv %d  +%d" % [int(e.level), int(e.spares)], UiTheme.GOLD, UiTheme.SMALL)
		count.position = Vector2(6, 2)
		count.mouse_filter = MOUSE_FILTER_IGNORE
		b.add_child(count)
		return b

	# ---- the benches -------------------------------------------------------------------

	func _bench(title: String, what: String, accent: Color) -> Array:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UiTheme.stitched(accent.lerp(UiTheme.LINE, 0.5), UiTheme.RAISED, 14, 12))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)
		var head := UiTheme.title(title, 17, accent)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(head)
		var about := UiTheme.label(what, UiTheme.MUTED, UiTheme.SMALL + 1)
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		about.custom_minimum_size.x = 150
		col.add_child(about)
		return [panel, col]

	func _row_of(edition: String, n: int, pixel := 3, missing := false) -> Control:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 4)
		var bits := Toys.split(edition)
		for i in n:
			row.add_child(ToyView.new(bits[0], bits[1], pixel, missing))
		return row

	func _grow() -> Control:
		var c := Control.new()
		c.size_flags_vertical = SIZE_EXPAND_FILL
		return c

	func _combine_bench() -> Control:
		var parts := _bench("combine", "spares of the same toy make it a level better. always works.", UiTheme.MINT)
		var col: VBoxContainer = parts[1]
		if _picked == "":
			col.add_child(_grow())
			return parts[0]
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.toys
		var e: Dictionary = state.owned[_picked]
		var need := Toys.combine_cost(state, catalog, _picked)
		if need == 0:
			col.add_child(_centered_label("it's a favourite! as good as it gets.", UiTheme.GOLD))
			col.add_child(_grow())
			return parts[0]
		col.add_child(_row_of(_picked, mini(need, 5), 3, int(e.spares) < need))
		col.add_child(_centered_label("%d of %d spares" % [mini(int(e.spares), need), need], UiTheme.MUTED))
		var bits := Toys.split(_picked)
		var out := ToyView.new(bits[0], bits[1], 5)
		out.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(out)
		var level := int(e.level) + 1
		var fav := level >= int(catalog.toys.max_level)
		col.add_child(_centered_label("level %d%s" % [level, ": a favourite, always on!" if fav else ""], UiTheme.MINT))
		col.add_child(_grow())
		var go := UiTheme.button("combine", func():
			if GameState.combine_toy(_picked):
				PetBubble.say_line(self, "toy_combined"))
		go.disabled = not Toys.can_combine(state, catalog, _picked)
		col.add_child(go)
		return parts[0]

	func _fix_bench() -> Control:
		var parts := _bench("fix", "sew a well-loved toy back up. good as new.", UiTheme.CYAN)
		var col: VBoxContainer = parts[1]
		if _picked == "":
			col.add_child(_grow())
			return parts[0]
		var state: Dictionary = GameState.toys
		var e: Dictionary = state.owned[_picked]
		var bits := Toys.split(_picked)
		var art := ToyView.new(bits[0], bits[1], 5)
		art.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(art)
		var fav := Toys.is_favourite(state, Catalog.shared(), _picked)
		col.add_child(_centered_label("a favourite never wears out" if fav else "it's %s" % ToysView._wear_word(float(e.wear)), UiTheme.MUTED))
		if float(e.wear) > 0.0 and not fav:
			var meter := UiTheme.bar(UiTheme.CYAN)
			meter.value = (1.0 - float(e.wear)) * 100.0
			meter.custom_minimum_size = Vector2(120, 9)
			meter.size_flags_horizontal = SIZE_SHRINK_CENTER
			col.add_child(meter)
		col.add_child(_grow())
		var price := Toys.fix_cost(state, Catalog.shared(), _picked)
		var busy := Toys.playing(state, _picked, Time.get_unix_time_from_system())
		var go := UiTheme.button("fix it  (%s coins)" % price if price > 0 else "nothing to fix", func():
			if GameState.fix_toy(_picked):
				PetBubble.say_line(self, "toy_fixed"))
		go.disabled = price <= 0 or GameState.coins < price or busy
		go.tooltip_text = "it's being played with" if busy else ("you need %d more coins" % (price - GameState.coins) if GameState.coins < price else "")
		col.add_child(go)
		return parts[0]

	func _sacrifice_bench() -> Control:
		var catalog := Catalog.shared()
		var sac: Dictionary = catalog.toys.sacrifice
		var parts := _bench("sacrifice", "%d spares of a toy for a chance at a special one. gone either way." % int(sac.spares), UiTheme.PINK)
		var col: VBoxContainer = parts[1]
		if _picked == "":
			col.add_child(_grow())
			return parts[0]
		var id := Toys.split(_picked)[0]
		var normal := Toys.key(id, "normal")
		var state: Dictionary = GameState.toys
		var spares := int(state.owned.get(normal, {}).get("spares", 0))
		col.add_child(_row_of(normal, int(sac.spares), 3, spares < int(sac.spares)))
		col.add_child(_centered_label("%d of %d normal spares" % [mini(spares, int(sac.spares)), int(sac.spares)], UiTheme.MUTED))
		if _result != "":
			if _result == "nothing":
				col.add_child(_centered_label("nothing this time…", UiTheme.MUTED))
			else:
				var won := ToyView.new(id, _result, 5)
				won.size_flags_horizontal = SIZE_SHRINK_CENTER
				col.add_child(won)
				col.add_child(_centered_label("%s!!" % ToysView._edition_name(Toys.key(id, _result)), UiTheme.PINK))
		else:
			# the odds, like a box shows them
			var odds := GridContainer.new()
			odds.columns = 2
			odds.add_theme_constant_override("h_separation", 12)
			var total := 0.0
			for k in sac.odds:
				total += float(sac.odds[k])
			for k in sac.odds:
				var name := "nothing" if k == "nothing" else ToysView._edition_name(Toys.key(id, k))
				odds.add_child(UiTheme.label(name, UiTheme.MUTED if k == "nothing" else UiTheme.TEXT, UiTheme.SMALL + 1))
				odds.add_child(UiTheme.label(UiTheme.percent(float(sac.odds[k]) / total), UiTheme.MUTED, UiTheme.SMALL + 1))
			odds.size_flags_horizontal = SIZE_SHRINK_CENTER
			col.add_child(odds)
		col.add_child(_grow())
		var go := UiTheme.button("risk it", func():
			var got := GameState.sacrifice_toy(id)
			_result = got if got != "" else "nothing"
			PetBubble.say_line(self, "toy_sacrificed_win" if got != "" else "toy_sacrificed_lose")
			_dirty = true)
		go.add_theme_color_override("font_color", UiTheme.PINK)
		go.disabled = not Toys.can_sacrifice(state, catalog, id)
		col.add_child(go)
		return parts[0]

	func _centered_label(text: String, color: Color) -> Label:
		var l := UiTheme.label(text, color, UiTheme.SMALL + 1)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return l
