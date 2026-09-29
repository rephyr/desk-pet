class_name ToysView
extends HBoxContainer
## The toys page of the collectibles tab. Along the top, what your pet is playing with (a toy only
## boosts while it's played with; you can't switch until it's done: "do not disturb me!"). Under it,
## the set: every toy as a card (a silhouette until you find it; the secret one isn't there until found). On the right,
## the picked toy up close: what it does, each finish you own as its own edition (level, spares, how
## worn it is), and the play buttons. Toys come from the capsule machine (Toys, data/toys.json).
## Design: design/mockups/screens/toys.html.

signal workbench_requested(edition: String)

const TILTS := [-1.5, 1.2, 2.0, -1.0, 1.6, -2.0, 1.0, -1.4]
const WEAR_WORDS := [[0.01, "good as new"], [0.25, "a bit scuffed"], [0.6, "well-loved"], [1.1, "worn out"]]

var _playing_row := HBoxContainer.new()
var _set_title: Label
var _set_count: Label
var _set_meter: ProgressBar
var _set_bonus: Label
var _grid := GridContainer.new()
var _detail := VBoxContainer.new()
var _picked := ""  # toy id
var _set_id := ""  # the set shown (a later globe's set shows once its hatch is open or you have one of its toys)
var _set_tabs := HBoxContainer.new()
var _edition := ""  # "toy:finish" picked in the detail
var _dirty := true
var _tick := 0.0
var _time_labels := {}  # edition -> Label (time left)


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	var main := VBoxContainer.new()
	main.size_flags_horizontal = SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 10)
	add_child(main)

	var playing := PanelContainer.new()
	playing.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.RAISED, UiTheme.LINE, 12, 2, 10))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 14)
	playing.add_child(prow)
	var ptitle := UiTheme.title("playing", 15, UiTheme.LILAC)
	ptitle.size_flags_vertical = SIZE_SHRINK_CENTER
	prow.add_child(ptitle)
	_playing_row.add_theme_constant_override("separation", 12)
	_playing_row.size_flags_horizontal = SIZE_EXPAND_FILL
	prow.add_child(_playing_row)
	main.add_child(playing)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_set_title = UiTheme.title("", 18)
	head.add_child(_set_title)
	_set_tabs.add_theme_constant_override("separation", 6)
	main.add_child(_set_tabs)
	_set_count = UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL + 1)
	_set_count.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_set_count)
	_set_meter = UiTheme.bar(UiTheme.GOLD)
	_set_meter.custom_minimum_size = Vector2(80, 9)
	_set_meter.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_set_meter)
	head.add_child(UiTheme.spacer())
	_set_bonus = UiTheme.label("", UiTheme.GOLD, UiTheme.SMALL + 1)
	_set_bonus.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_set_bonus)
	main.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	_grid.columns = 4
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 14)
	pad.add_child(_grid)
	scroll.add_child(pad)
	main.add_child(scroll)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(248, 0)
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var dscroll := ScrollContainer.new()
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	dscroll.add_child(_detail)
	side.add_child(dscroll)
	add_child(side)

	GameState.toys_changed.connect(func(): _dirty = true)
	GameState.changed.connect(func(): _dirty = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_rebuild())


func speak() -> void:
	PetBubble.say_line(self, "toys" if not GameState.toys.owned.is_empty() else "toys_none")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _dirty:
		_rebuild()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		var now := Time.get_unix_time_from_system()
		for edition in _time_labels:
			(_time_labels[edition] as Label).text = _clock(Toys.left(GameState.toys, edition, now))


# ---- building it -------------------------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.toys
	var now := Time.get_unix_time_from_system()
	var sets := shown_sets()
	if not sets.any(func(x): return x.id == _set_id):
		_set_id = str(sets[0].id)
	var set_data: Dictionary = sets.filter(func(x): return x.id == _set_id)[0]
	var shown := Toys.shown_toys(state, set_data)
	if _picked == "" or not shown.any(func(t): return t.id == _picked):
		_picked = str(shown[0].id)
	# one set: its name; more: a chip per set to pick which one shows
	_set_title.text = str(set_data.name)
	_set_tabs.visible = sets.size() > 1
	UiTheme.clear(_set_tabs)
	if sets.size() > 1:
		for x in sets:
			var id := str(x.id)
			var chip := UiTheme.filter_chip(str(x.name), UiTheme.PINK, id == _set_id)
			chip.name = "set_" + id
			chip.pressed.connect(func():
				_set_id = id
				_picked = ""
				_edition = ""
				_rebuild())
			_set_tabs.add_child(chip)
	var owned: int = shown.filter(func(t): return Toys.has_toy(state, t.id)).size()
	_set_count.text = "%d of %d" % [owned, shown.size()]
	_set_meter.max_value = shown.size()
	_set_meter.value = owned
	_set_bonus.text = "finished! +1 play slot" if Toys.set_done(state, set_data) else "finish it: +1 play slot"

	# what's being played with, and the free slots
	_time_labels.clear()
	UiTheme.clear(_playing_row)
	var busy: Array = state.playing.filter(func(p): return float(p.until) > now)
	for p in busy:
		_playing_row.add_child(_playing_slot(str(p.key), now))
	for i in Toys.slots(state, catalog) - busy.size():
		var free := UiTheme.label("a free spot: pick a toy and tap play", UiTheme.LOCKED, UiTheme.SMALL + 1)
		free.size_flags_vertical = SIZE_SHRINK_CENTER
		_playing_row.add_child(free)
	var favs: Array = state.owned.keys().filter(func(k): return Toys.is_favourite(state, catalog, k))
	for k in favs:
		_playing_row.add_child(_playing_slot(str(k), now))

	UiTheme.clear(_grid)
	for i in shown.size():
		_grid.add_child(_card(shown[i], TILTS[i % TILTS.size()], now))
	_build_detail(now)


## One toy being played with (or a favourite, always on): the toy, its name, the time left.
func _playing_slot(edition: String, now: float) -> Control:
	var catalog := Catalog.shared()
	var bits := Toys.split(edition)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(ToyView.new(bits[0], bits[1], 3))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.size_flags_vertical = SIZE_SHRINK_CENTER
	col.add_child(UiTheme.label(_edition_name(edition), UiTheme.MINT, UiTheme.SMALL + 1))
	if Toys.is_favourite(GameState.toys, catalog, edition):
		col.add_child(UiTheme.label("a favourite: always on", UiTheme.GOLD, UiTheme.SMALL))
	else:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var t := UiTheme.label(_clock(Toys.left(GameState.toys, edition, now)), UiTheme.MUTED, UiTheme.SMALL)
		_time_labels[edition] = t
		line.add_child(t)
		# the toy shelf hands it again when it's done (tap it: this is the last round)
		if GameState.built("shelf") and Toys.again(GameState.toys, edition):
			line.add_child(UiTheme.label("again!", UiTheme.LILAC, UiTheme.SMALL))
		col.add_child(line)
	row.add_child(col)
	# tap it while it's being played with: your pet won't let go (with the toy shelf: once more, or
	# back on the shelf after this round)
	row.mouse_filter = MOUSE_FILTER_STOP
	row.name = "playing_" + edition.replace(":", "_")
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if GameState.built("shelf") and not Toys.is_favourite(GameState.toys, catalog, edition) \
					and str(_play_of(edition)) != "":
				PetBubble.say_line(self, "toy_again" if GameState.toy_again(edition) else "toy_last")
			else:
				PetBubble.say_line(self, "toy_busy"))
	return row


## The play length a toy is being played with ("" for plays from before v27).
func _play_of(edition: String) -> String:
	for p in GameState.toys.playing:
		if p.key == edition:
			return str(p.get("play", ""))
	return ""


func _card(t: Dictionary, tilt: float, now: float) -> Control:
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.toys
	var have := Toys.has_toy(state, t.id)
	var tier_color := MachineTab.MachineStage._tier_color(t.tier)
	var editions := _editions(t.id)
	var best := str(editions.back()) if not editions.is_empty() else ""
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(112, 124)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var on: bool = t.id == _picked
	var style: StyleBox = UiTheme.box(UiTheme.RAISED if have else UiTheme.RAISED.lerp(UiTheme.PAGE, 0.4), tier_color if have else UiTheme.LINE, 10, 2, 6)
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 6) if on else style)
	b.pressed.connect(func():
		_picked = t.id
		_edition = ""
		_rebuild())
	var col := VBoxContainer.new()
	col.set_anchors_preset(PRESET_FULL_RECT)
	col.offset_top = 8
	col.offset_bottom = -6
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(col)
	var art := ToyView.new(t.id, Toys.split(best)[1] if best != "" else "normal", 4, not have)
	art.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(art)
	var name_label := UiTheme.label(t.name, UiTheme.TEXT if have else UiTheme.LOCKED, UiTheme.SMALL + 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	var tier_label := UiTheme.label(t.tier, tier_color if have else UiTheme.LOCKED, UiTheme.SMALL)
	tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(tier_label)
	for c in col.get_children():
		c.mouse_filter = MOUSE_FILTER_IGNORE
	if have:
		var level := 0
		var count := 0
		var busy := false
		var ready := false
		for e in editions:
			level = maxi(level, int(state.owned[e].level))
			count += 1 + int(state.owned[e].spares)
			busy = busy or Toys.playing(state, e, now)
			ready = ready or Toys.can_combine(state, catalog, e)
		b.add_child(_badge("lv %d" % level, UiTheme.GOLD, Vector2(6, 4), false))
		b.add_child(_badge("x%d" % count, UiTheme.TEXT, Vector2(-6, -8), true))
		if busy:
			b.add_child(_ribbon("playing!", UiTheme.MINT))
		elif ready:
			b.add_child(_ribbon("level up ready!", UiTheme.GOLD))
	var holder := Tilted.new(b, tilt)
	holder.size_flags_horizontal = SIZE_EXPAND_FILL
	return holder


## The toy sets that show: the first always, a later globe's once its rusted hatch is open or you
## have one of its toys (hidden until earned).
static func shown_sets() -> Array:
	var catalog := Catalog.shared()
	var first := Machine.first_globe(catalog)
	return catalog.toys.sets.filter(func(x):
		var g := str(x.get("globe", first))
		return g == first or Machine.hatch_open(GameState.machine, catalog, g) or x.toys.any(func(t): return Toys.has_toy(GameState.toys, t.id)))


func _badge(text: String, color: Color, at: Vector2, right: bool) -> Control:
	var l := UiTheme.label(text, color, UiTheme.SMALL)
	if right:
		var box := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 9, 2, 0)
		box.content_margin_left = 6
		box.content_margin_right = 6
		l.add_theme_stylebox_override("normal", box)
		l.set_anchors_preset(PRESET_TOP_RIGHT)
		l.grow_horizontal = GROW_DIRECTION_BEGIN
		l.position.y = at.y
		l.offset_right = -at.x + 12
	else:
		l.position = at
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _ribbon(text: String, color: Color) -> Control:
	var l := UiTheme.label(text, UiTheme.DEEP, UiTheme.SMALL)
	var box := UiTheme.box(color, color, 9, 0, 0)
	box.content_margin_left = 8
	box.content_margin_right = 8
	l.add_theme_stylebox_override("normal", box)
	l.set_anchors_preset(PRESET_CENTER_BOTTOM)
	l.grow_horizontal = GROW_DIRECTION_BOTH
	l.offset_top = -4
	l.offset_bottom = 10
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


# ---- the toy up close --------------------------------------------------------------------

func _build_detail(now: float) -> void:
	UiTheme.clear(_detail)
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.toys
	var t := Toys.toy(catalog, _picked)
	var editions := _editions(_picked)
	if editions.is_empty():
		var art := ToyView.new(_picked, "normal", 7, true)
		art.size_flags_horizontal = SIZE_SHRINK_CENTER
		_detail.add_child(art)
		_detail.add_child(_centered(UiTheme.title(str(t.name), 20)))
		_detail.add_child(_centered(UiTheme.label("not found yet", UiTheme.LOCKED, UiTheme.SMALL + 1)))
		return
	if _edition == "" or not _edition in editions:
		_edition = editions.back()
	var e: Dictionary = state.owned[_edition]
	var bits := Toys.split(_edition)
	var art := ToyView.new(bits[0], bits[1], 7)
	art.size_flags_horizontal = SIZE_SHRINK_CENTER
	_detail.add_child(art)
	_detail.add_child(_centered(UiTheme.title(_edition_name(_edition), 19)))
	_detail.add_child(_centered(UiTheme.label("%s, level %d" % [t.tier, int(e.level)], MachineTab.MachineStage._tier_color(t.tier), UiTheme.SMALL + 1)))
	var boost := Toys.boost(state, catalog, _edition)
	var does := UiTheme.label("while it plays: %s (x%s)" % [t.does, _num(boost)], UiTheme.MINT, UiTheme.SMALL + 1)
	does.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	does.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_child(does)

	# each finish you own is its own edition: pick one
	for k in editions:
		_detail.add_child(_edition_row(k))

	_detail.add_child(UiTheme.stitch_line())
	if Toys.is_favourite(state, catalog, _edition):
		_detail.add_child(_centered(UiTheme.label("a favourite! it's always on.", UiTheme.GOLD, UiTheme.SMALL + 1)))
	elif Toys.playing(state, _edition, now):
		_detail.add_child(_centered(UiTheme.label("playing! do not disturb.", UiTheme.MINT, UiTheme.SMALL + 1)))
	else:
		var free: bool = state.playing.filter(func(p): return float(p.until) > now).size() < Toys.slots(state, catalog)
		var worn := _wear_word(float(e.wear))
		_detail.add_child(_centered(UiTheme.label("it's %s" % worn, UiTheme.MUTED, UiTheme.SMALL + 1)))
		for p in catalog.toys.play:
			var label := "%s (%s)" % [p.name, _minutes(float(p.minutes))]
			var btn := UiTheme.button(label, func():
				if GameState.play_toy(_edition, p.id):
					PetBubble.say_line(self, "toy_play"))
			btn.disabled = not free
			btn.tooltip_text = "" if free else "your pet's busy playing: wait until it's done"
			_detail.add_child(btn)
		if not free:
			var busy := UiTheme.label("every spot is busy playing", UiTheme.LOCKED, UiTheme.SMALL)
			busy.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_detail.add_child(busy)
	var bench := UiTheme.button("workbench →", func(): workbench_requested.emit(_edition))
	_detail.add_child(bench)


func _edition_row(edition: String) -> Control:
	var state: Dictionary = GameState.toys
	var catalog := Catalog.shared()
	var e: Dictionary = state.owned[edition]
	var fin := Toys.finish(catalog, Toys.split(edition)[1])
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	var on := edition == _edition
	var style := UiTheme.box(UiTheme.DEEP, UiTheme.PINK if on else UiTheme.LINE, 8, 2, 6)
	for s in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(s, style)
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(func():
		_edition = edition
		_rebuild())
	var row := HBoxContainer.new()
	row.set_anchors_preset(PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(row)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.size_flags_vertical = SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var spares := int(e.spares)
	col.add_child(UiTheme.label("%s%s" % [fin.name, "  +%d spare" % spares if spares > 0 else ""], UiTheme.TEXT, UiTheme.SMALL + 1))
	var need := Toys.combine_cost(state, catalog, edition)
	var note := "max level" if need == 0 else ("ready to level up!" if spares >= need else "%d more for level %d" % [need - spares, int(e.level) + 1])
	if float(e.wear) >= 0.01:
		note = _wear_word(float(e.wear))
	col.add_child(UiTheme.label(note, UiTheme.GOLD if note == "ready to level up!" else UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(col)
	var lv := UiTheme.label("lv %d" % int(e.level), UiTheme.GOLD, UiTheme.SMALL + 1)
	lv.size_flags_vertical = SIZE_SHRINK_CENTER
	lv.custom_minimum_size.x = 30
	row.add_child(lv)
	for c in col.get_children():
		c.mouse_filter = MOUSE_FILTER_IGNORE
	return b


# ---- helpers --------------------------------------------------------------------------

## The editions you own of a toy, plainest first (so .back() is the fanciest).
func _editions(toy_id: String) -> Array:
	var out: Array = []
	for f in Catalog.shared().toys.finishes:
		var k := Toys.key(toy_id, f.id)
		if GameState.toys.owned.has(k):
			out.append(k)
	return out


static func _edition_name(edition: String) -> String:
	return Toys.edition_name(Catalog.shared(), edition)


static func _wear_word(wear: float) -> String:
	for w in WEAR_WORDS:
		if wear < float(w[0]):
			return str(w[1])
	return "worn out"


static func _clock(seconds: float) -> String:
	var s := ceili(seconds)
	if s >= 3600:
		return "%d:%02d:%02d left" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d left" % [s / 60, s % 60]


static func _minutes(m: float) -> String:
	return "%d min" % int(m) if m < 60.0 else ("%d h" % int(m / 60.0))


static func _num(x: float) -> String:
	return str(snappedf(x, 0.01)).trim_suffix(".0")


func _centered(l: Label) -> Label:
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
