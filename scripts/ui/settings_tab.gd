class_name SettingsTab
extends ScrollContainer
## Player preferences (see the Settings autoload), on two pages. general: the look (colours, font,
## icons), opening boxes, what your pet does while you work, and sound volumes. video: resolution,
## frame rate, vsync. Everything applies straight away.


func _init() -> void:
	horizontal_scroll_mode = SCROLL_MODE_DISABLED
	var root := VBoxContainer.new()
	root.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	var video := _video()
	video.visible = false
	var pages := UiTheme.segmented(["general", "video"], 0, func(i):
		col.visible = i == 0
		video.visible = i == 1)
	pages.size_flags_horizontal = SIZE_SHRINK_BEGIN
	root.add_child(pages)
	root.add_child(col)
	root.add_child(video)
	col.add_child(_look())

	var two := HBoxContainer.new()
	two.add_theme_constant_override("separation", 12)
	col.add_child(two)
	var boxes := _section("opening boxes")
	two.add_child(boxes.panel)
	var speed := _slider_row(boxes.body, "reveal speed", Settings.MIN_SPEED, Settings.MAX_SPEED, 0.25, Settings.reveal_speed,
		func(v): return "%sx" % v, func(v): Settings.set_value("reveal_speed", v))
	speed.add_theme_color_override("font_color", UiTheme.MUTED)
	boxes.body.add_child(_stitch_line())
	boxes.body.add_child(_switch("skip the pack animation for one box", Settings.skip_single_reveal, func(on): Settings.set_value("skip_single_reveal", on)))
	boxes.body.add_child(_switch("skip the mist on very rare pulls", Settings.skip_ritual, func(on): Settings.set_value("skip_ritual", on)))

	var work := _section("your pet at work")
	two.add_child(work.panel)
	var pet := GameState.collection.active()
	var who := pet.display_name(Catalog.shared()) if pet else "your pet"
	# once your pet has learned to (the automation tab); it can move to another job there too
	var boxes_switch := _switch("open boxes in the corner", GameState.packs_on, func(on): GameState.set_job("packs", on))
	boxes_switch.visible = GameState.knows_job("boxes")
	work.body.add_child(boxes_switch)
	# nothing to switch yet: the section stays out of sight
	work.panel.visible = GameState.knows_job("boxes") or GameState.feature_on("shopping")
	GameState.automation_changed.connect(func():
		if is_instance_valid(boxes_switch):
			boxes_switch.visible = GameState.knows_job("boxes")
			boxes_switch.set_pressed_no_signal(GameState.packs_on)
			work.panel.visible = GameState.knows_job("boxes") or GameState.feature_on("shopping"))
	# quiet paws: how much your pet acts out its job out on your windows (only what's drawn: it's
	# not another switch for opening boxes). There once there's something to act out.
	# stacked, so a wide font or a long label never pushes the half-width section past the window
	var paws := _choice("out on your windows", Settings.PAWS_LEVELS, Settings.paws, func(i): Settings.set_value("paws", i), true)
	paws.name = "PawsRow"
	paws.visible = QuietPaws.has_something(GameState)
	work.body.add_child(paws)
	var show_paws := func():
		if is_instance_valid(paws):
			paws.visible = QuietPaws.has_something(GameState)
	GameState.automation_changed.connect(show_paws)
	GameState.tutorial_changed.connect(show_paws)
	if GameState.feature_on("shopping"):  # once it has the piggy bank, it buys boxes too
		work.body.add_child(_switch("buy boxes when the pile runs out", GameState.buying_on, func(on): GameState.set_job("buying", on)))
		# the reserve is kept in capsules like box prices, shown in coins at what a capsule is worth now
		var in_coins := func(v): return UiTheme.num(roundi(v * GameState.capsule_value()))
		var kept := _slider_row(work.body, "coins %s always keeps" % who, 0, GameState.reserve_max(), GameState.reserve_step(),
			GameState.reserve_capsules, in_coins, func(v): GameState.set_reserve(int(v)))
		kept.add_theme_color_override("font_color", UiTheme.CYAN)
		GameState.changed.connect(func():  # a machine fix makes a capsule worth more while this is open
			if is_instance_valid(kept):
				kept.text = in_coins.call(GameState.reserve_capsules))

	var sound := _section("sound")
	col.add_child(sound.panel)
	var pct := func(v): return "%d%%" % roundi(v * 100.0)
	_slider_row(sound.body, "music", 0.0, 1.0, 0.05, Settings.music_volume, pct,
		func(v): Settings.set_value("music_volume", v)).add_theme_color_override("font_color", UiTheme.MUTED)
	_slider_row(sound.body, "sounds", 0.0, 1.0, 0.05, Settings.sound_volume, pct,
		func(v): Settings.set_value("sound_volume", v)).add_theme_color_override("font_color", UiTheme.MUTED)

	if OS.is_debug_build():
		var dev := _section("dev")
		col.add_child(dev.panel)
		var fresh := UiTheme.button("dev: new game (backs up your save first)")
		fresh.pressed.connect(func():
			# a second click within a few seconds confirms, so it can't happen by accident
			if fresh.text.begins_with("sure?"):
				GameState.debug_new_game()
				fresh.text = "done (old save: save-before-new-game-*.json)"
			else:
				fresh.text = "sure? click again to start over"
				get_tree().create_timer(4.0).timeout.connect(func():
					if fresh.text.begins_with("sure?"):
						fresh.text = "dev: new game (backs up your save first)"))
		dev.body.add_child(fresh)
		# how long into the game things opened, for testing the pacing
		var times := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL + 1)
		times.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var show_times := func():
			var ms: Dictionary = GameState.milestones
			var played := (Time.get_unix_time_from_system() - GameState.started_at) / 60.0 if GameState.started_at > 0.0 else 0.0
			var parts: Array[String] = []
			for k in ms:
				parts.append("%s at %.1f min" % [k, float(ms[k])])
			times.text = ("this game: %.0f min so far, %d machine upgrades. " % [played, GameState.machine_upgrades()]) + (", ".join(parts) if not parts.is_empty() else "nothing opened yet")
		visibility_changed.connect(func(): if is_visible_in_tree(): show_times.call())
		show_times.call()
		dev.body.add_child(times)


func speak() -> void:
	PetBubble.say_line(self, "settings")


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		speak()


# ---- video --------------------------------------------------------------------

func _video() -> Control:
	var s := _section("video")
	s.body.add_child(_choice("resolution", Settings.RESOLUTIONS.map(func(r): return "%d × %d" % [r.x, r.y]),
		Settings.resolution, func(i): Settings.set_value("resolution", i)))
	var note := UiTheme.label("the size of the full game window. the game scales up to fill it. if it's too big for your screen, it shrinks to the biggest size that fits.", UiTheme.MUTED, UiTheme.SMALL)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.body.add_child(note)
	s.body.add_child(_stitch_line())
	s.body.add_child(_choice("frame rate", Settings.FPS_CAPS.map(func(f): return "no cap" if f == 0 else "%d fps" % f),
		maxi(0, Settings.FPS_CAPS.find(Settings.max_fps)), func(i): Settings.set_value("max_fps", Settings.FPS_CAPS[i])))
	s.body.add_child(_switch("vsync", Settings.vsync, func(on): Settings.set_value("vsync", on)))
	s.body.add_child(_switch("show fps", Settings.show_fps, func(on): Settings.set_value("show_fps", on)))
	return s.panel


## A label and a row of choices (no dropdown: popups open as their own window, which our
## always-on-top window hides on Linux). on_pick(index) runs when one is picked.
func _choice(text: String, options: Array, current: int, on_pick: Callable, stacked := false) -> Control:
	var row: BoxContainer = VBoxContainer.new() if stacked else HBoxContainer.new()  # stacked: the label over the choices
	row.add_theme_constant_override("separation", 6 if stacked else 10)
	var name_label := UiTheme.label(text)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(name_label)
	var picks := UiTheme.segmented(options, current, on_pick)
	if stacked:
		picks.size_flags_horizontal = SIZE_SHRINK_BEGIN
	row.add_child(picks)
	return row


# ---- the look ----------------------------------------------------------------

func _look() -> PanelContainer:
	var s := _section("the look")
	var looks := UiTheme.looks()
	var current: Dictionary = looks.get("default", {})
	var theme_id: String = Settings.color_theme if Settings.color_theme != "" else str(current.get("theme", "plum"))
	var font_id: String = Settings.font_set if Settings.font_set != "" else str(current.get("font", "coiny"))

	s.body.add_child(UiTheme.label("colours", UiTheme.MUTED, UiTheme.SMALL + 1))
	var themes := HBoxContainer.new()
	themes.add_theme_constant_override("separation", 12)
	s.body.add_child(themes)
	for t: Dictionary in looks.get("themes", []):
		themes.add_child(_pick(_swatch(t), t.name, t.kind, t.id == theme_id, func(): Settings.set_value("color_theme", t.id)))

	var lower := HBoxContainer.new()
	lower.add_theme_constant_override("separation", 16)
	s.body.add_child(lower)
	var fonts_col := VBoxContainer.new()
	fonts_col.add_child(UiTheme.label("font", UiTheme.MUTED, UiTheme.SMALL + 1))
	var fonts := HBoxContainer.new()
	fonts.add_theme_constant_override("separation", 10)
	fonts_col.add_child(fonts)
	lower.add_child(fonts_col)
	for f: Dictionary in looks.get("fonts", []):
		fonts.add_child(_pick(_font_face(f), f.name, "", f.id == font_id, func(): Settings.set_value("font_set", f.id)))
	var icons_col := VBoxContainer.new()
	icons_col.add_child(UiTheme.label("icons", UiTheme.MUTED, UiTheme.SMALL + 1))
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 10)
	icons_col.add_child(icons)
	lower.add_child(icons_col)
	for st: Dictionary in looks.get("icon_styles", []):
		icons.add_child(_pick(_icon_face(st.id), st.name, "", st.id == UiTheme.ICON_STYLE, func(): Settings.set_value("icon_style", st.id)))
	return s.panel


## A choice: its face, a name (and a small note) under it; the chosen one is stitched and tilted.
func _pick(face: Control, text: String, note: String, chosen: bool, on_pick: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.tooltip_text = text
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	var holder := PanelContainer.new()
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	var ring: StyleBox = UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 14, 4) if chosen else StyleBoxEmpty.new()
	if not chosen:
		ring.set_content_margin_all(4)
	holder.add_theme_stylebox_override("panel", ring)
	holder.add_child(face)
	col.add_child(holder)
	var name_label := UiTheme.label(text, UiTheme.TEXT if note != "" else UiTheme.MUTED, UiTheme.SMALL)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(name_label)
	if note != "":
		var n := UiTheme.label(note, UiTheme.MUTED, UiTheme.SMALL)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(n)
	b.add_child(col)
	b.custom_minimum_size = col.get_combined_minimum_size()
	col.resized.connect(func(): b.custom_minimum_size = col.get_combined_minimum_size())
	b.mouse_entered.connect(func(): if not chosen: b.position.y -= 2)
	b.mouse_exited.connect(func(): if not chosen: b.position.y += 2)
	if not chosen:
		b.pressed.connect(on_pick)
	return Tilted.new(b, -2.0 if chosen else 0.0)


## A tiny window drawn in theme `t`'s own colours.
func _swatch(t: Dictionary) -> Control:
	var c: Dictionary = t.colors
	var col := func(key: String) -> Color: return Color(c[key])
	var tiers: Dictionary = t.get("tiers", {})
	var face := Control.new()
	face.custom_minimum_size = Vector2(112, 62)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.draw.connect(func():
		var r := Rect2(Vector2.ZERO, face.size)
		face.draw_style_box(UiTheme.box(col.call("deep"), col.call("pink_seam"), 10, 2, 0), r)
		face.draw_rect(Rect2(26, 2, r.size.x - 28, r.size.y - 4), col.call("page"))
		for i in 4:
			face.draw_rect(Rect2(8, 9 + i * 8, 12, 4), col.call("pink") if i == 1 else col.call("muted_seam"))
		var y := 3.0
		while y < r.size.y - 4:
			face.draw_line(Vector2(24, y), Vector2(24, y + 3), col.call("pink_seam"), 1.0)
			y += 6.0
		face.draw_style_box(UiTheme.box(col.call("raised"), col.call("pink_seam"), 5, 1, 0), Rect2(32, 8, r.size.x - 40, 9))
		var borders := [col.call("lilac_seam"), Color(tiers.get("legendary", "#ffc857")), Color(tiers.get("rare", "#5cc8ff"))]
		for i in 3:
			face.draw_style_box(UiTheme.box(col.call("raised"), borders[i], 4, 1, 0), Rect2(32 + i * 25, 23, 21, 22))
		face.draw_circle(Vector2(r.size.x - 20, r.size.y - 9), 3.0, col.call("cyan"))
		face.draw_circle(Vector2(r.size.x - 11, r.size.y - 9), 3.0, col.call("gold")))
	return face


## "Aa" and a pet name, written in font set `f`.
func _font_face(f: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 10, UiTheme.RAISED, 6))
	panel.custom_minimum_size = Vector2(98, 62)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	var aa := UiTheme.label("Aa", UiTheme.PINK, 22)
	aa.add_theme_font_override("font", UiTheme.font_for(f.display))
	aa.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(aa)
	var sample := UiTheme.label("lilac blob", UiTheme.TEXT, UiTheme.SMALL + 1)
	sample.add_theme_font_override("font", UiTheme.font_for(f.body))
	sample.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sample)
	panel.add_child(col)
	return panel


## Four icons in `style`.
func _icon_face(style: String) -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 10, UiTheme.RAISED, 8))
	panel.custom_minimum_size = Vector2(84, 62)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = SIZE_SHRINK_CENTER
	for n in ["home", "boxes", "coin", "heart"]:
		var r := TextureRect.new()
		r.texture = UiTheme.icon(n, 18, UiTheme.TEXT, style)
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.custom_minimum_size = Vector2(18, 18)
		r.texture_filter = TEXTURE_FILTER_NEAREST if style == "pixel" else TEXTURE_FILTER_LINEAR
		grid.add_child(r)
	panel.add_child(grid)
	return panel


# ---- pieces --------------------------------------------------------------------

## A sticker with a title; returns { panel, body } so rows can be added to body.
func _section(text: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.add_child(UiTheme.title(text, 18))
	panel.add_child(body)
	return { "panel": panel, "body": body }


## A labelled slider; returns the value label (so it can be coloured).
func _slider_row(parent: Control, text: String, lo: float, hi: float, step: float, value: float, fmt: Callable, on_change: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := UiTheme.label(text)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(120, 0)
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.focus_mode = FOCUS_NONE
	row.add_child(slider)
	var value_label := UiTheme.label(fmt.call(value))
	value_label.custom_minimum_size = Vector2(40, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)
	slider.value_changed.connect(func(v):
		value_label.text = fmt.call(v)
		on_change.call(v))
	parent.add_child(row)
	return value_label


func _switch(text: String, on: bool, on_toggle: Callable) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # a long pet name wraps instead of widening the page
	b.custom_minimum_size = Vector2(120, 0)
	b.focus_mode = FOCUS_NONE
	b.button_pressed = on
	b.toggled.connect(on_toggle)
	return b


func _stitch_line() -> Control:
	var line := Control.new()
	line.custom_minimum_size = Vector2(0, 6)
	line.draw.connect(func():
		var x := 0.0
		while x < line.size.x:
			line.draw_line(Vector2(x, 3), Vector2(minf(x + 5.0, line.size.x), 3), UiTheme.LINE, 2.0)
			x += 9.0)
	return line
