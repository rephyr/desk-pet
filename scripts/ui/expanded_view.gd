class_name ExpandedView
extends VBoxContainer
## The full game layer: your pet's room (home), then tabs for boxes, the collection, adventures
## and your inventory.

signal collapse_requested
signal quit_requested

var _coins := UiTheme.label("", UiTheme.CYAN)
var boxes := BoxesTab.new()
var collection := CollectionTab.new()
var adventures := AdventuresTab.new()
var home := HomeTab.new()
var _tabs := {}  # name -> Control
var _tab_buttons := {}  # name -> Button
var _current := "boxes"
var _hint := UiTheme.label("", UiTheme.PINK, UiTheme.SMALL)


func _init() -> void:
	add_theme_constant_override("separation", 12)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	UiTheme.make_window_handle(header)
	add_child(header)
	var title := UiTheme.label("desk pets ♡", UiTheme.PINK)
	title.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(title)
	var title_gap := Control.new()
	title_gap.custom_minimum_size = Vector2(12, 0)
	header.add_child(title_gap)

	var body := MarginContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	var inventory := InventoryTab.new()
	inventory.open_box_requested.connect(func(box_id):
		show_tab("boxes")
		boxes.open(box_id, 1))
	home.go.connect(show_tab)
	home.open_box.connect(func(box_id):
		show_tab("boxes")
		boxes.open(box_id, 1))
	_tabs = { "home": home, "boxes": boxes, "collection": collection, "adventures": adventures, "inventory": inventory, "settings": SettingsTab.new() }
	var group := ButtonGroup.new()
	for tab_name in _tabs:
		body.add_child(_tabs[tab_name])
		var b := UiTheme.button(tab_name)
		b.toggle_mode = true
		b.button_group = group
		b.toggled.connect(func(on):
			if not on:
				return
			if not GameState.tab_open(tab_name):
				# locked: say what opens it, and stay where you were
				_say_hint(GameState.tab_hint(tab_name))
				_tab_buttons[_current].button_pressed = true
				return
			_current = tab_name
			_show(tab_name))
		header.add_child(b)
		_tab_buttons[tab_name] = b
	add_child(body)
	show_start()

	_hint.modulate.a = 0.0
	header.add_child(_hint)
	var gap := UiTheme.spacer()
	gap.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(gap)
	_coins.mouse_filter = MOUSE_FILTER_PASS
	header.add_child(_coins)
	if OS.is_debug_build():
		var cheat := UiTheme.small_button("+%d" % GameState.DEBUG_COINS, func(): GameState.add_debug_coins())
		cheat.tooltip_text = "debug only: free coins for testing"
		header.add_child(cheat)
	header.add_child(UiTheme.small_button("▾", func(): collapse_requested.emit()))
	header.add_child(UiTheme.small_button("×", func(): quit_requested.emit()))

	GameState.changed.connect(_refresh)
	GameState.tutorial_changed.connect(_refresh_tabs)
	GameState.unlocked.connect(func(_e): _refresh_tabs())
	GameState.new_game.connect(_refresh_tabs)
	_refresh()
	_refresh_tabs()


## Which tabs a tutorial step shows: they appear one by one as you learn them.
const TUTORIAL_TABS := {
	"open_first": ["boxes", "settings"],
	"open_second": ["boxes", "settings"],
	"make_active": ["boxes", "collection", "settings"],
	"send": ["boxes", "collection", "adventures", "settings"],
}


func _refresh_tabs() -> void:
	var shown: Array = TUTORIAL_TABS.get(GameState.tutorial, _tabs.keys())
	for tab_name in _tab_buttons:
		var b: Button = _tab_buttons[tab_name]
		b.visible = tab_name in shown
		# locked tabs show a padlock; tapping them tells you what opens them
		var locked := not GameState.tab_open(tab_name)
		b.icon = UiTheme.lock_icon() if locked else null
		b.modulate = Color(1, 1, 1, 0.55) if locked else Color.WHITE
		b.tooltip_text = GameState.tab_hint(tab_name)
	# jump to where the tutorial wants you
	match GameState.tutorial:
		"open_first":
			show_tab("boxes")


## The button the tutorial is pointing at right now, or null.
func tutorial_target() -> Control:
	match GameState.tutorial:
		"open_first", "open_second":
			return null if boxes.is_revealing() else (boxes.tutorial_target() if boxes.visible else _tab_buttons.boxes)
		"make_active":
			return collection.tutorial_target() if collection.visible else _tab_buttons.collection
		"send":
			return adventures.tutorial_target() if adventures.visible else _tab_buttons.adventures
	return null


## Where the full game opens: your pet's room, or the boxes while the tutorial is on.
func show_start() -> void:
	show_tab("boxes" if GameState.tutorial_active() else "home")


func show_tab(tab_name: String) -> void:
	if _tab_buttons.has(tab_name):
		_tab_buttons[tab_name].button_pressed = true  # also calls _show through the toggle


func _show(tab_name: String) -> void:
	_current = tab_name
	for n in _tabs:
		_tabs[n].visible = n == tab_name


func _refresh() -> void:
	_coins.text = "◆ %d   xp %d" % [GameState.coins, GameState.xp]


func _say_hint(text: String) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.5)
	t.tween_property(_hint, "modulate:a", 0.0, 0.6)
