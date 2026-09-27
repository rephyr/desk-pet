class_name CompactView
extends VBoxContainer
## The small "idle" layer: your active pet, its needs and a few quick buttons.

signal expand_requested
signal let_out_toggled
signal quit_requested

var _work := PetAtWork.new()  # your pet, opening packs while you work
var _errand_line := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _haul := UiTheme.label("", UiTheme.CYAN, UiTheme.SMALL)
var _packs_toggle: Button
var _errands_toggle: Button
var _line_tick := 0.0
var _status := UiTheme.label("out exploring your desktop…", UiTheme.LILAC)
var _coins := UiTheme.label("", UiTheme.CYAN)
var _hunger := UiTheme.bar(UiTheme.PINK)
var _happy := UiTheme.bar(UiTheme.LILAC)
var _out_button: Button
var expand_button: Button  # the tutorial points at it if you shrink the window


func _init() -> void:
	add_theme_constant_override("separation", 8)

	var header := HBoxContainer.new()
	UiTheme.make_window_handle(header)
	var title := UiTheme.label("desk pets ♡", UiTheme.PINK)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(title)
	_coins.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(_coins)
	expand_button = UiTheme.small_button("▴", func(): expand_requested.emit())
	header.add_child(expand_button)
	header.add_child(UiTheme.small_button("×", func(): quit_requested.emit()))
	add_child(header)

	# the pet
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 104)
	add_child(stage)
	_work.set_anchors_preset(PRESET_FULL_RECT)
	stage.add_child(_work)
	_haul.set_anchors_preset(PRESET_TOP_RIGHT)
	_haul.position = Vector2(-60, 0)
	_haul.modulate.a = 0.0
	stage.add_child(_haul)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(PRESET_FULL_RECT)
	_status.visible = false
	stage.add_child(_status)

	# what the errand pets are up to, and the switches for your pet's jobs
	var jobs := HBoxContainer.new()
	jobs.add_theme_constant_override("separation", 6)
	_errand_line.size_flags_horizontal = SIZE_EXPAND_FILL
	_errand_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_errand_line.custom_minimum_size = Vector2(0, 30)
	jobs.add_child(_errand_line)
	var switches := VBoxContainer.new()
	switches.add_theme_constant_override("separation", 2)
	_packs_toggle = _job_toggle("packs", func(on): GameState.packs_on = on, GameState.packs_on)
	_errands_toggle = _job_toggle("errands", func(on): GameState.errands_on = on, GameState.errands_on)
	switches.add_child(_packs_toggle)
	switches.add_child(_errands_toggle)
	jobs.add_child(switches)
	add_child(jobs)
	GameState.errands_hauled.connect(_show_haul)

	add_child(_bar_row("food", _hunger))
	add_child(_bar_row("mood", _happy))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	add_child(buttons)
	for b in [
		UiTheme.button("feed ◆%d" % GameState.FEED_COST, func(): GameState.feed()),
		UiTheme.button("pat", func():
			GameState.pat()
			_work.view.squash = 0.6),
	]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.add_child(b)
	_out_button = UiTheme.button("let out", func(): let_out_toggled.emit())
	_out_button.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(_out_button)

	GameState.changed.connect(_refresh)
	GameState.collection.active_changed.connect(func(_p): _refresh_pet())
	_refresh()
	_refresh_pet()


func _process(delta: float) -> void:
	_hunger.value = GameState.hunger
	_happy.value = GameState.happiness
	_haul.modulate.a = move_toward(_haul.modulate.a, 0.0, delta * 0.6)
	_haul.position.y = -10.0 * (1.0 - _haul.modulate.a)
	_line_tick -= delta
	if _line_tick <= 0.0:
		_line_tick = 1.0
		_refresh_errand_line()


## "bean is picking flowers in the garden · 2:10", taking turns if there are several.
func _refresh_errand_line() -> void:
	var errands: Array = GameState.errands
	if errands.is_empty():
		_errand_line.text = "no errands right now" if GameState.errands_on else ""
		return
	var errand: Dictionary = errands[int(Time.get_ticks_msec() / 4000) % errands.size()]
	var pet := GameState.collection.get_pet(errand.pet)
	var left := maxi(0, ceili(float(errand.ends) - Time.get_unix_time_from_system()))
	var catalog := Catalog.shared()
	var who := "%s %s" % [catalog.part("palette", pet.parts.palette).name, catalog.part("body", pet.parts.body).name] if pet else "someone"
	_errand_line.text = "%s is %s · %d:%02d" % [who, errand.doing, left / 60, left % 60]
	_errand_line.tooltip_text = _errand_line.text


func _show_haul(loot: Dictionary) -> void:
	var coins := Rewards.total(loot, "coins")
	var extra := ""
	if Rewards.total(loot, "part") > 0:
		extra += " + a part"
	if Rewards.total(loot, "box") > 0:
		extra += " + a box"
	_haul.text = "+◆%d%s" % [coins, extra]
	_haul.modulate.a = 1.0


func _job_toggle(text: String, on_toggled: Callable, on: bool) -> Button:
	var b := UiTheme.button(text)
	b.toggle_mode = true
	b.button_pressed = on
	b.add_theme_font_size_override("font_size", UiTheme.SMALL - 1)
	b.custom_minimum_size = Vector2(62, 0)
	b.tooltip_text = "let your pet do this while you're busy"
	b.toggled.connect(func(pressed):
		on_toggled.call(pressed)
		GameState.save_game())
	return b


## Shows whether the pet is home or out on the desktop.
func set_pet_out(out: bool) -> void:
	_work.visible = not out
	_status.visible = out
	_out_button.text = "call back" if out else "let out"


func _refresh() -> void:
	_coins.text = "◆ %d" % GameState.coins
	# jobs your pet hasn't learned yet stay out of sight
	_packs_toggle.visible = GameState.feature_on("packs")
	_errands_toggle.visible = GameState.feature_on("errands")
	_errand_line.visible = GameState.feature_on("errands")


func _refresh_pet() -> void:
	_work.view.pet = GameState.collection.active()


func _bar_row(text: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text)
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	row.add_child(bar)
	return row
