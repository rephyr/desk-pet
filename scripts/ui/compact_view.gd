class_name CompactView
extends VBoxContainer
## The small "idle" layer: your active pet, its needs and a few quick buttons.

signal expand_requested
signal let_out_toggled
signal quit_requested

var _portrait := PetPortrait.new(4, true)
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
	stage.custom_minimum_size = Vector2(0, 80)
	add_child(stage)
	_portrait.set_anchors_preset(PRESET_FULL_RECT)
	stage.add_child(_portrait)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(PRESET_FULL_RECT)
	_status.visible = false
	stage.add_child(_status)

	add_child(_bar_row("food", _hunger))
	add_child(_bar_row("mood", _happy))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	add_child(buttons)
	for b in [
		UiTheme.button("feed ◆%d" % GameState.FEED_COST, func(): GameState.feed()),
		UiTheme.button("pat", func():
			GameState.pat()
			_portrait.view.squash = 0.6),
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


func _process(_delta: float) -> void:
	_hunger.value = GameState.hunger
	_happy.value = GameState.happiness


## Shows whether the pet is home or out on the desktop.
func set_pet_out(out: bool) -> void:
	_portrait.visible = not out
	_status.visible = out
	_out_button.text = "call back" if out else "let out"


func _refresh() -> void:
	_coins.text = "◆ %d" % GameState.coins


func _refresh_pet() -> void:
	_portrait.set_pet(GameState.collection.active())


func _bar_row(text: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text)
	l.custom_minimum_size = Vector2(44, 0)
	row.add_child(l)
	row.add_child(bar)
	return row
