class_name AdventuresTab
extends VBoxContainer
## Sending pets on adventures. At the top your active pet chats about what's going on (PetVoice);
## below, pick a place on the left, pick pets in the middle, trips on the right. A trip waiting at an event shows its options there (small parties also show when the
## default gets picked); a trip that's back shows its summary.
## All the rules live in AdventureRunner; this only shows them and passes on clicks.

const PAGE_SIZE := 24
const QUICK_PICK := 10

var _location_id := ""
var _places := VBoxContainer.new()
var _places_key := ""  # which places are listed, to rebuild when something unlocks
var _odds := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _send: Button
var _picked := {}  # uid -> true
var _picked_label := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _quick := GridContainer.new()
var _grid := HFlowContainer.new()
var _page := 0
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _runs := VBoxContainer.new()
var _run_rows: Array[Dictionary] = []  # { run, bar, time } or { run, countdown }
var _result := UiTheme.label("", UiTheme.LILAC, UiTheme.SMALL)
var _dirty := true
var _estimate_key := ""  # which picks the cached estimate is for
var _estimate := 1.0
var _tick := 0.0
var _columns := HBoxContainer.new()
var _portrait := PetPortrait.new(3, true)
var _speech := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _voice_rng := RandomNumberGenerator.new()


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	_voice_rng.randomize()
	add_child(_voice_row())
	_columns.add_theme_constant_override("separation", 14)
	_columns.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_columns)
	_location_id = GameState.open_locations()[0].id
	_columns.add_child(_places_column())
	_columns.add_child(_picker_column())
	_columns.add_child(_runs_column())
	# not GameState.changed: that also fires on every passive coin
	GameState.adventures_changed.connect(func(): _dirty = true)
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	GameState.collection.pets_removed.connect(func(_u): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	visibility_changed.connect(func():
		_rebuild_if_dirty()
		if is_visible_in_tree():
			_speak())


## Your active pet and a speech bubble.
func _voice_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_portrait)
	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.PINK.darkened(0.35), 12, 2, 10))
	bubble.size_flags_horizontal = SIZE_EXPAND_FILL
	bubble.size_flags_vertical = SIZE_SHRINK_CENTER
	_speech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.add_child(_speech)
	row.add_child(bubble)
	return row


## The active pet says something about what's going on; news of a trip it's talking about is
## used up, so it doesn't repeat itself next time.
func _speak() -> void:
	var pet := GameState.collection.active()
	_portrait.visible = pet != null
	if pet == null:
		_speech.text = ""
		return
	_portrait.set_pet(pet)
	var catalog := Catalog.shared()
	var what := PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog)
	GameState.news = {}
	_speech.text = PetVoice.line(pet, what, _voice_rng, catalog)
	_speech.visible_ratio = 0.0
	create_tween().tween_property(_speech, "visible_ratio", 1.0, 0.02 * _speech.text.length())
	_portrait.view.squash = 0.4


func _places_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(230, 0)
	col.add_theme_constant_override("separation", 6)
	_places.add_theme_constant_override("separation", 6)
	col.add_child(_places)
	var gap := Control.new()
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(gap)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_odds)
	_send = UiTheme.button("send ♡", _send_picked)
	col.add_child(_send)
	return col


## Rumours waiting for you at the top, then one heading per open adventure type with its places.
func _rebuild_places() -> void:
	var open := GameState.open_locations()
	var key := ",".join(open.map(func(l): return l.id)) + "|" + ",".join(GameState.rumours)
	if key == _places_key:
		return
	_places_key = key
	if not open.any(func(l): return l.id == _location_id):
		_location_id = open[0].id
	UiTheme.clear(_places)
	var catalog := Catalog.shared()
	if not GameState.rumours.is_empty():
		_places.add_child(UiTheme.label("rumours", UiTheme.PINK))
		for id in GameState.rumours:
			_places.add_child(_rumour_row(catalog.rumour(id)))
	var group := ButtonGroup.new()
	for type in catalog.adventure_types:
		var here := open.filter(func(l): return l.type == type.id)
		if here.is_empty():
			continue
		_places.add_child(UiTheme.label(type.name, UiTheme.PINK))
		for location in here:
			_places.add_child(_place_button(location, group))


func _rumour_row(rumour: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var title := UiTheme.label(rumour.title, UiTheme.LILAC)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.tooltip_text = rumour.about
	title.mouse_filter = MOUSE_FILTER_PASS
	row.add_child(title)
	row.add_child(UiTheme.button("let's go!", func(): GameState.follow_rumour(rumour.id)))
	return row


func _place_button(location: Dictionary, group: ButtonGroup) -> Button:
	var b := UiTheme.button("%s\n%s" % [location.name, _about(location.minutes)])
	b.toggle_mode = true
	b.button_group = group
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.button_pressed = location.id == _location_id
	b.toggled.connect(func(on):
		if on:
			_location_id = location.id
			_trim_to_party_size()
			_rebuild_picker())
	return b


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
		col.add_child(UiTheme.button("dev: unlock everything", func(): GameState.debug_unlock_all()))
		col.add_child(UiTheme.button("dev: lock everything", func(): GameState.debug_lock_all()))
	return col


# ---- picking ----------------------------------------------------------------

func _max_party() -> int:
	return GameState.max_party(_location_id)


## Pets you could send, weakest first (so quick picks never grab your best ones). A place for
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
		if _picked.size() >= _max_party():
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
		if _picked.size() >= _max_party():
			return
		_picked[pet.uid] = true
	for card in _grid.get_children():
		if card is PetCard:
			card.set_selected(_picked.has(card.pet.uid))
	_refresh_send()


func _trim_to_party_size() -> void:
	if _picked.size() > _max_party():
		_picked.clear()


func _picked_pets() -> Array[Pet]:
	var out: Array[Pet] = []
	for pet in GameState.sendable_pets():
		if _picked.has(pet.uid):
			out.append(pet)
	return out


## For the tutorial: a pet to pick for the trip, then the send button.
func tutorial_target() -> Control:
	if not _picked.is_empty():
		return _send
	for card in _grid.get_children():
		if card is PetCard:
			return card
	return null


func _turn(step: int) -> void:
	_page += step
	_rebuild_picker()


func _send_picked() -> void:
	if GameState.send_on_adventure(_location_id, _picked_pets()) != null:
		_picked.clear()
		_result.visible = false
		_rebuild()


# ---- building -----------------------------------------------------------------

func _rebuild_if_dirty() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	_rebuild_places()
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
	var d := catalog.location(_location_id)
	var pets := _picked_pets()
	var most := _max_party()
	if most == 1:
		_picked_label.text = "who goes?"
	elif most <= Chooser.SMALL_PARTY:
		_picked_label.text = "%d of %d picked" % [pets.size(), most]
	else:
		_picked_label.text = "%d picked" % pets.size()
	_send.disabled = pets.is_empty()
	if pets.is_empty():
		_odds.text = "pick who goes ♡"
		return
	var time := _duration(AdventureRunner.duration(d, Party.make(pets, catalog)))
	match Chooser.kind_for(pets.size()):
		"player":
			_odds.text = "%s · you choose the way ♡" % time
		"timeout":
			_odds.text = "%s · you'll be asked along the way ♡" % time
		_:
			# trial runs are slow for big swarms: only redo them when the picks change
			var key := _location_id + ":" + ",".join(_picked.keys())
			if key != _estimate_key:
				_estimate_key = key
				_estimate = AdventureRunner.estimate_return(_location_id, pets, catalog)
			_odds.text = "%s · about %d%% come home" % [time, roundi(_estimate * 100.0)]


func _rebuild_runs() -> void:
	UiTheme.clear(_runs)
	_run_rows.clear()
	var catalog := Catalog.shared()
	for run in GameState.runs:
		var d := catalog.location(run.location_id)
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

		# a single pet's trip reads like a little story, told by your active pet: how it's feeling,
		# what came up and what it spotted (never any numbers), the choices, then what happened
		var speaker := GameState.collection.active()
		var solo := run.party.setting_out() == 1 and speaker != null
		if solo and run.status != RunState.Status.DONE:
			col.add_child(_wrapped(PetVoice.feeling(speaker, run.party, run.history, catalog), UiTheme.PINK))
		match run.status:
			RunState.Status.WAITING:
				var event := run.current_event(catalog)
				var options := AdventureRunner.options_of(event, d)
				var allowed := AdventureRunner.allowed_options(event, run.party, d)
				col.add_child(_wrapped(event.title, UiTheme.TEXT))
				var scene := str(event.text)
				if solo:
					scene += " " + PetVoice.spotted(speaker, event, run.party, d, catalog)
				col.add_child(_wrapped(scene, UiTheme.LILAC))
				for i in allowed:
					var option: Dictionary = options[i]
					var b := UiTheme.button(option.label, GameState.answer_event.bind(run, i))
					b.add_theme_font_size_override("font_size", UiTheme.SMALL)
					col.add_child(b)
				if run.chooser == "timeout":
					var countdown := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
					col.add_child(countdown)
					_run_rows.append({ "run": run, "countdown": countdown, "default": options[Chooser.default_option(event, allowed)].label })
			RunState.Status.DONE:
				col.add_child(_wrapped(AdventureRunner.summary(run), UiTheme.TEXT))
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
		if not run.history.is_empty():
			col.add_child(_wrapped("\n".join(run.history.map(func(e): return "· " + str(e.text))), UiTheme.MUTED))
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
		if row.has("countdown"):
			row.countdown.text = "if nobody picks: %s in %s" % [row.default, _duration(TimeoutChooser.deadline(run) - now)]
			continue
		var d := catalog.location(run.location_id)
		var gap := AdventureRunner.gap(d, run.party, run.events.size())
		var within := clampf(1.0 - (run.next_at - now) / gap, 0.0, 1.0)
		row.bar.value = (run.step + within) / (run.events.size() + 1.0)
		var left := _duration(run.next_at - now)
		row.time.text = ("heading home… %s" if run.step >= run.events.size() else "on the way… %s") % left


func _collect(run: RunState) -> void:
	var text := GameState.collect_run(run)
	if text == "":
		return
	_result.text = text
	_result.visible = true
	_rebuild()
	_speak()


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
