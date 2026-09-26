class_name DungeonTab
extends HBoxContainer
## Sending pets into dungeons: pick a dungeon on the left, pick pets in the middle, runs on the
## right. A run waiting at an event shows its options there; a run that's back shows its summary.
## All the rules live in DungeonRunner; this only shows them and passes on clicks.

const PAGE_SIZE := 24
const QUICK_PICK := 10

var _dungeon_id := ""
var _odds := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _send: Button
var _picked := {}  # uid -> true
var _picked_label := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _quick := GridContainer.new()
var _grid := HFlowContainer.new()
var _page := 0
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _runs := VBoxContainer.new()
var _run_rows: Array[Dictionary] = []  # { run, bar, time }
var _result := UiTheme.label("", UiTheme.LILAC, UiTheme.SMALL)
var _dirty := true
var _tick := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	_dungeon_id = Catalog.shared().dungeons[0].id
	add_child(_dungeons_column())
	add_child(_picker_column())
	add_child(_runs_column())
	GameState.changed.connect(func(): _dirty = true)
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	visibility_changed.connect(_rebuild_if_dirty)


func _dungeons_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(230, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(UiTheme.label("the dungeon", UiTheme.PINK))
	var group := ButtonGroup.new()
	for d in Catalog.shared().dungeons:
		var who := "one pet, you choose" if int(d.max_party) == 1 else "as many as you like"
		var b := UiTheme.button("%s\n%s · %s" % [d.name, _about(d.minutes), who])
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = d.id == _dungeon_id
		b.toggled.connect(func(on):
			if on:
				_dungeon_id = d.id
				_trim_to_party_size()
				_rebuild_picker())
		col.add_child(b)
	var gap := Control.new()
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(gap)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_odds)
	_send = UiTheme.button("send ♡", _send_picked)
	col.add_child(_send)
	return col


func _picker_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var top := HBoxContainer.new()
	top.add_child(_picked_label)
	top.add_child(UiTheme.spacer())
	top.add_child(UiTheme.small_button("‹", func(): _turn(-1)))
	top.add_child(_page_label)
	top.add_child(UiTheme.small_button("›", func(): _turn(1)))
	col.add_child(top)

	_quick.columns = 4
	_quick.add_theme_constant_override("h_separation", 4)
	_quick.add_theme_constant_override("v_separation", 4)
	var catalog := Catalog.shared()
	for tier in catalog.tiers:
		var b := UiTheme.button("+%d %s" % [QUICK_PICK, tier.name], _quick_pick.bind(tier.id))
		b.add_theme_color_override("font_color", catalog.tier_color(tier.id))
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		_quick.add_child(b)
	var clear := UiTheme.button("clear", func():
		_picked.clear()
		_rebuild_picker())
	clear.add_theme_font_size_override("font_size", UiTheme.SMALL)
	clear.size_flags_horizontal = SIZE_EXPAND_FILL
	_quick.add_child(clear)
	col.add_child(_quick)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)
	col.add_child(scroll)
	return col


func _runs_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(270, 0)
	col.add_theme_constant_override("separation", 8)
	col.add_child(UiTheme.label("away", UiTheme.PINK))
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.visible = false
	col.add_child(_result)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_runs.size_flags_horizontal = SIZE_EXPAND_FILL
	_runs.add_theme_constant_override("separation", 8)
	scroll.add_child(_runs)
	col.add_child(scroll)
	if OS.is_debug_build():
		col.add_child(UiTheme.button("dev: skip the walking", func(): GameState.debug_finish_runs()))
	return col


# ---- picking ----------------------------------------------------------------

func _max_party() -> int:
	return int(Catalog.shared().dungeon(_dungeon_id).get("max_party", 0))


## Pets you could send, weakest first (so quick picks never grab your best ones). A dungeon for
## one pet lists the strongest first instead: that's the one you'd take yourself.
func _available() -> Array[Pet]:
	var catalog := Catalog.shared()
	var strongest_first := _max_party() == 1
	var pets := GameState.sendable_pets()
	pets.sort_custom(func(a: Pet, b: Pet):
		var ra := catalog.rank(a.rarity)
		var rb := catalog.rank(b.rarity)
		if ra != rb:
			return ra > rb if strongest_first else ra < rb
		var pa := int(a.stats.get("power", 0))
		var pb := int(b.stats.get("power", 0))
		return pa > pb if strongest_first else pa < pb)
	return pets


func _quick_pick(tier_id: String) -> void:
	var added := 0
	for pet in _available():
		if added >= QUICK_PICK:
			break
		if pet.rarity == tier_id and not _picked.has(pet.uid):
			_picked[pet.uid] = true
			added += 1
	_rebuild_picker()


func _toggle(pet: Pet) -> void:
	if _picked.has(pet.uid):
		_picked.erase(pet.uid)
	else:
		if _max_party() == 1:
			_picked.clear()
		_picked[pet.uid] = true
	for card in _grid.get_children():
		if card is PetCard:
			card.set_selected(_picked.has(card.pet.uid))
	_refresh_send()


func _trim_to_party_size() -> void:
	var most := _max_party()
	if most > 0 and _picked.size() > most:
		_picked.clear()


func _picked_pets() -> Array[Pet]:
	var out: Array[Pet] = []
	for pet in GameState.sendable_pets():
		if _picked.has(pet.uid):
			out.append(pet)
	return out


func _turn(step: int) -> void:
	_page += step
	_rebuild_picker()


func _send_picked() -> void:
	if GameState.send_to_dungeon(_dungeon_id, _picked_pets()) != null:
		_picked.clear()
		_result.visible = false
		_rebuild()


# ---- building -----------------------------------------------------------------

func _rebuild_if_dirty() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	_rebuild_picker()
	_rebuild_runs()


func _rebuild_picker() -> void:
	UiTheme.clear(_grid)
	var pets := _available()
	var still := {}  # forget picks of pets that are gone or already sent
	for pet in pets:
		if _picked.has(pet.uid):
			still[pet.uid] = true
	_picked = still
	_quick.visible = _max_party() != 1
	var pages := maxi(1, ceili(pets.size() / float(PAGE_SIZE)))
	_page = clampi(_page, 0, pages - 1)
	_page_label.text = "%d/%d" % [_page + 1, pages]
	for pet in pets.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		var card := PetCard.new(pet, 2, false)
		card.pressed.connect(_toggle)
		card.set_selected(_picked.has(pet.uid))
		_grid.add_child(card)
	_refresh_send()


func _refresh_send() -> void:
	var catalog := Catalog.shared()
	var d := catalog.dungeon(_dungeon_id)
	var pets := _picked_pets()
	_picked_label.text = "who goes?" if _max_party() == 1 else "%d picked" % pets.size()
	_send.disabled = pets.is_empty()
	if pets.is_empty():
		_odds.text = "pick who goes ♡"
		return
	var time := _duration(DungeonRunner.duration(d, Party.make(pets, catalog)))
	if d.chooser == "player":
		_odds.text = "%s · you choose the way ♡" % time
	else:
		_odds.text = "%s · about %d%% come home" % [time, roundi(DungeonRunner.estimate_return(_dungeon_id, pets, catalog) * 100.0)]


func _rebuild_runs() -> void:
	UiTheme.clear(_runs)
	_run_rows.clear()
	var catalog := Catalog.shared()
	for run in GameState.runs:
		var d := catalog.dungeon(run.dungeon_id)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.LILAC.darkened(0.45), 10, 2, 8))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		panel.add_child(col)

		var top := HBoxContainer.new()
		top.add_child(UiTheme.label(d.name, UiTheme.PINK, UiTheme.SMALL))
		top.add_child(UiTheme.spacer())
		var who := run.party.who() if run.party.setting_out() == 1 else "%d pets" % run.party.setting_out()
		top.add_child(UiTheme.label(who, UiTheme.MUTED, UiTheme.SMALL))
		col.add_child(top)
		for entry in run.history.slice(-2):
			col.add_child(_wrapped(entry.text, UiTheme.MUTED))

		match run.status:
			RunState.Status.WAITING:
				var event := run.current_event(catalog)
				col.add_child(_wrapped(event.title, UiTheme.TEXT))
				col.add_child(_wrapped(str(event.text), UiTheme.LILAC))
				for i in DungeonRunner.allowed_options(event, run.party):
					var option: Dictionary = event.options[i]
					var b := UiTheme.button(option.label, GameState.answer_event.bind(run, i))
					b.add_theme_font_size_override("font_size", UiTheme.SMALL)
					col.add_child(b)
			RunState.Status.DONE:
				col.add_child(_wrapped(DungeonRunner.summary(run), UiTheme.TEXT))
				var back := UiTheme.button("welcome back ♡", _collect.bind(run))
				back.add_theme_font_size_override("font_size", UiTheme.SMALL)
				col.add_child(back)
			_:
				var bar := UiTheme.bar(UiTheme.LILAC)
				bar.max_value = 1.0
				bar.step = 0.0
				col.add_child(bar)
				var time := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
				col.add_child(time)
				_run_rows.append({ "run": run, "bar": bar, "time": time })
		_runs.add_child(panel)
	if GameState.runs.is_empty():
		_runs.add_child(UiTheme.label("nobody's away", UiTheme.MUTED, UiTheme.SMALL))
	_refresh_runs()


## Moves the walking runs' bars and timers along.
func _refresh_runs() -> void:
	var now := Time.get_unix_time_from_system()
	var catalog := Catalog.shared()
	for row in _run_rows:
		var run: RunState = row.run
		var d := catalog.dungeon(run.dungeon_id)
		var gap := DungeonRunner.gap(d, run.party)
		var within := clampf(1.0 - (run.next_at - now) / gap, 0.0, 1.0)
		row.bar.value = (run.step + within) / (d.events.size() + 1.0)
		var left := _duration(run.next_at - now)
		row.time.text = ("heading home… %s" if run.step >= d.events.size() else "on the way… %s") % left


func _collect(run: RunState) -> void:
	var text := GameState.collect_run(run)
	if text == "":
		return
	_result.text = text
	_result.visible = true
	_rebuild()


func _wrapped(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color, UiTheme.SMALL)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	return l


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_rebuild_if_dirty()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_refresh_runs()


static func _about(minutes: float) -> String:
	var hours := snappedf(minutes / 60.0, 0.5)
	return "~%d min" % roundi(minutes) if minutes < 60.0 else ("~%d h" % hours if hours == floorf(hours) else "~%.1f h" % hours)


static func _duration(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
