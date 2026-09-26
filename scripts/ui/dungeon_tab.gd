class_name DungeonTab
extends HBoxContainer
## Sending pets down the dungeon: pick a floor on the left, pick pets in the middle, runs and
## their results on the right. The words come from data/dungeons.json and get colder deeper down.

const PAGE_SIZE := 24
const QUICK_PICK := 10

var _floor := 0
var _floor_buttons: Array[Button] = []
var _odds := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _send: Button
var _picked := {}  # uid -> true
var _picked_label := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
var _grid := HFlowContainer.new()
var _page := 0
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _runs := VBoxContainer.new()
var _run_rows: Array[Dictionary] = []  # { run, bar, time, collect }
var _result := UiTheme.label("", UiTheme.LILAC, UiTheme.SMALL)
var _dirty := true
var _tick := 0.0


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_floors_column())
	add_child(_picker_column())
	add_child(_runs_column())
	GameState.changed.connect(func(): _dirty = true)
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	visibility_changed.connect(_rebuild_if_dirty)


func _floors_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(230, 0)
	col.add_theme_constant_override("separation", 6)
	col.add_child(UiTheme.label("the dungeon", UiTheme.PINK))
	var group := ButtonGroup.new()
	var floors := GameState.dungeon.floors()
	for i in floors.size():
		var f: Dictionary = floors[i]
		var b := UiTheme.button("%s\n%s · %d%% %s" % [f.name, _about(f.minutes), roundi(f.survive * 100.0), f.odds_word])
		b.toggle_mode = true
		b.button_group = group
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.button_pressed = i == _floor
		b.toggled.connect(func(on):
			if on:
				_floor = i
				_refresh_send())
		col.add_child(b)
		_floor_buttons.append(b)
	var gap := Control.new()
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(gap)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_odds)
	_send = UiTheme.button("", _send_picked)
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

	var quick := GridContainer.new()
	quick.columns = 4
	quick.add_theme_constant_override("h_separation", 4)
	quick.add_theme_constant_override("v_separation", 4)
	var catalog := Catalog.shared()
	for tier in catalog.tiers:
		var b := UiTheme.button("+%d %s" % [QUICK_PICK, tier.name], _quick_pick.bind(tier.id))
		b.add_theme_color_override("font_color", catalog.tier_color(tier.id))
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		quick.add_child(b)
	var clear := UiTheme.button("clear", func():
		_picked.clear()
		_rebuild_picker())
	clear.add_theme_font_size_override("font_size", UiTheme.SMALL)
	clear.size_flags_horizontal = SIZE_EXPAND_FILL
	quick.add_child(clear)
	col.add_child(quick)

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
	col.custom_minimum_size = Vector2(250, 0)
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
		col.add_child(UiTheme.button("dev: finish runs", func(): GameState.debug_finish_runs()))
	return col


# ---- picking ----------------------------------------------------------------

## Pets you could send, weakest first (so quick picks never grab your best ones).
func _available() -> Array[Pet]:
	var catalog := Catalog.shared()
	var pets := GameState.sendable_pets()
	pets.sort_custom(func(a: Pet, b: Pet):
		var ra := catalog.rank(a.rarity)
		var rb := catalog.rank(b.rarity)
		return ra < rb if ra != rb else int(a.stats.get("power", 0)) < int(b.stats.get("power", 0)))
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
		_picked[pet.uid] = true
	for card in _grid.get_children():
		if card is PetCard and card.pet == pet:
			card.set_selected(_picked.has(pet.uid))
	_refresh_send()


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
	if GameState.send_to_dungeon(_floor, _picked_pets()):
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
	# forget picks of pets that are gone or already sent
	var still := {}
	for pet in pets:
		if _picked.has(pet.uid):
			still[pet.uid] = true
	_picked = still
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
	var f := GameState.dungeon.floor_info(_floor)
	var pets := _picked_pets()
	_picked_label.text = "%d picked" % pets.size()
	_send.text = f.send
	_send.disabled = pets.is_empty()
	var catalog := Catalog.shared()
	if pets.is_empty():
		_odds.text = "pick who goes ♡"
		return
	var chance := 0.0
	for pet in pets:
		chance += Dungeon.survive_chance(f, pet, catalog)
	chance /= pets.size()
	_odds.text = "%s · about %d%% %s" % [_duration(Dungeon.run_seconds(f, pets, catalog)), roundi(chance * 100.0), f.odds_word]


func _rebuild_runs() -> void:
	UiTheme.clear(_runs)
	_run_rows.clear()
	for run in GameState.dungeon.runs:
		var f := GameState.dungeon.floor_info(run.floor)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.LILAC.darkened(0.45), 10, 2, 8))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		panel.add_child(col)
		var top := HBoxContainer.new()
		top.add_child(UiTheme.label(f.name, UiTheme.PINK, UiTheme.SMALL))
		top.add_child(UiTheme.spacer())
		top.add_child(UiTheme.label("%d pets" % run.pets.size(), UiTheme.MUTED, UiTheme.SMALL))
		col.add_child(top)
		col.add_child(UiTheme.label(f.away, UiTheme.MUTED, UiTheme.SMALL))
		var bar := UiTheme.bar(UiTheme.LILAC)
		bar.max_value = 1.0
		bar.step = 0.0
		col.add_child(bar)
		var bottom := HBoxContainer.new()
		var time := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
		bottom.add_child(time)
		bottom.add_child(UiTheme.spacer())
		var collect := UiTheme.button("welcome back", _collect.bind(run))
		collect.add_theme_font_size_override("font_size", UiTheme.SMALL)
		bottom.add_child(collect)
		col.add_child(bottom)
		_runs.add_child(panel)
		_run_rows.append({ "run": run, "bar": bar, "time": time, "collect": collect })
	if _run_rows.is_empty():
		_runs.add_child(UiTheme.label("nobody's away", UiTheme.MUTED, UiTheme.SMALL))
	_refresh_runs()


func _refresh_runs() -> void:
	var now := Time.get_unix_time_from_system()
	for row in _run_rows:
		var done := Dungeon.is_done(row.run, now)
		row.bar.value = Dungeon.progress(row.run, now)
		row.time.text = "" if done else _duration(float(row.run.ends) - now) + " left"
		row.collect.visible = done


func _collect(run: Dictionary) -> void:
	var result := GameState.collect_run(run)
	if result.is_empty():
		return
	var f := GameState.dungeon.floor_info(result.floor)
	var loot: Array[String] = []
	if result.coins > 0:
		loot.append("◆ %d" % result.coins)
	for box_id in result.boxes:
		var n: int = result.boxes[box_id]
		loot.append("%d %s%s" % [n, Catalog.shared().box(box_id).name, "es" if n > 1 else ""])
	_result.text = f.back % result.home.size()
	if not loot.is_empty():
		_result.text += "\n" + " · ".join(loot)
	_result.visible = true
	_rebuild()


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
