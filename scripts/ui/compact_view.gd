class_name CompactView
extends VBoxContainer
## The small "idle" layer: your active pet, its needs and a few quick buttons.

signal expand_requested
signal let_out_toggled
signal quit_requested

var _work := PetAtWork.new()  # your pet, opening packs while you work
var _packs_toggle: Button
var _status := UiTheme.label("out exploring your desktop…", UiTheme.LILAC)
var _coins: PanelContainer
var _hunger := UiTheme.bar(UiTheme.PINK)
var _happy := UiTheme.bar(UiTheme.LILAC)
var _out_button: Button
var expand_button: Button  # the tutorial points at it if you shrink the window


func _init() -> void:
	add_theme_constant_override("separation", 0)

	# the header strip: title, coins, grow and close
	var head_panel := PanelContainer.new()
	var head_sb := UiTheme.box(UiTheme.DEEP, UiTheme.DEEP, 0, 0, 0)
	head_sb.content_margin_left = 10
	head_sb.content_margin_right = 4
	head_sb.content_margin_top = 3
	head_sb.content_margin_bottom = 3
	head_panel.add_theme_stylebox_override("panel", head_sb)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	UiTheme.make_window_handle(head_panel)
	head_panel.add_child(header)
	header.add_child(UiTheme.icon_rect("heart", 15))
	var title := UiTheme.title("desk pets", 15)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(title)
	_coins = UiTheme.chip("coin", "", UiTheme.CYAN)
	_coins.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(_coins)
	expand_button = UiTheme.small_button("▴", func(): expand_requested.emit())
	expand_button.tooltip_text = "open the full game"
	header.add_child(expand_button)
	var close := UiTheme.small_button("×", func(): quit_requested.emit())
	close.tooltip_text = "close"
	header.add_child(close)
	add_child(head_panel)

	# the sky strip: your pet at work, its job switches floating top right
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, 112)
	stage.clip_contents = true
	stage.draw.connect(func(): stage.draw_rect(Rect2(Vector2.ZERO, stage.size), Color(UiTheme.SKY, 0.85)))
	add_child(stage)
	_work.set_anchors_preset(PRESET_FULL_RECT)
	stage.add_child(_work)
	var jobs := HBoxContainer.new()
	jobs.add_theme_constant_override("separation", 5)
	jobs.set_anchors_preset(PRESET_TOP_RIGHT)
	jobs.grow_horizontal = GROW_DIRECTION_BEGIN
	jobs.position = Vector2(-8, 7)
	_packs_toggle = _job_toggle("opening packs", func(on): GameState.set_job("packs", on), GameState.packs_on)
	jobs.add_child(_packs_toggle)
	stage.add_child(jobs)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status.set_anchors_preset(PRESET_FULL_RECT)
	_status.visible = false
	stage.add_child(_status)

	var body := MarginContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 12)
	body.add_theme_constant_override("margin_top", 9)
	body.add_theme_constant_override("margin_bottom", 10)
	add_child(body)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	body.add_child(col)

	col.add_child(_bar_row("food", _hunger))
	col.add_child(_bar_row("mood", _happy))
	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(fill)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	col.add_child(buttons)
	var feed := UiTheme.button("feed %d" % GameState.FEED_COST, func(): GameState.feed())
	feed.icon = UiTheme.icon("coin", 13)
	feed.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed.add_theme_constant_override("icon_max_width", 13)
	feed.add_theme_color_override("icon_normal_color", Color.WHITE)
	feed.add_theme_color_override("icon_hover_color", Color.WHITE)
	for b in [
		feed,
		UiTheme.button("pat", func():
			GameState.pat()
			_work.view.squash = 0.6),
	]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.add_child(b)
	_out_button = UiTheme.button("let out", func(): let_out_toggled.emit())
	_out_button.tooltip_text = "your pet walks around on your windows"
	_out_button.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(_out_button)

	GameState.changed.connect(_refresh)
	GameState.collection.active_changed.connect(func(_p): _refresh_pet())
	_refresh()
	_refresh_pet()


func _process(_delta: float) -> void:
	_hunger.value = GameState.hunger
	_happy.value = GameState.happiness


func _job_toggle(text: String, on_toggled: Callable, on: bool) -> Button:
	var b := UiTheme.filter_chip(text, UiTheme.PINK, on)
	b.tooltip_text = "let your pet do this while you're busy"
	b.toggled.connect(on_toggled)
	return b


## Shows whether the pet is home or out on the desktop.
func set_pet_out(out: bool) -> void:
	_work.visible = not out
	_status.visible = out
	_out_button.text = "call back" if out else "let out"


func _refresh() -> void:
	(_coins.find_child("Amount", true, false) as Label).text = ExpandedView._thousands(GameState.coins)
	# jobs your pet hasn't learned yet stay out of sight
	_packs_toggle.visible = GameState.knows_job("boxes")
	_packs_toggle.set_pressed_no_signal(GameState.packs_on)


func _refresh_pet() -> void:
	_work.view.pet = GameState.collection.active()


func _bar_row(text: String, bar: ProgressBar) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, UiTheme.MUTED, UiTheme.SMALL)
	l.custom_minimum_size = Vector2(38, 0)
	row.add_child(l)
	row.add_child(bar)
	return row
