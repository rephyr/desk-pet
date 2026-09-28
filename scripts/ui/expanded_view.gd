class_name ExpandedView
extends HBoxContainer
## The full game: an open book. The starry spine on the left (your pet on its moon, the tabs),
## the dotted page on the right: your pet's speech bubble, coins, xp and the window buttons along
## the top, then the tab. Tabs: home (your pet's room), machine (the capsule machine), boxes,
## collectibles (pets, toys, the book), adventures, errands, automation (jobs your pet does for you),
## workbench (the bag and sewing, toys), settings.

signal collapse_requested
signal quit_requested

var boxes := BoxesTab.new()
var collection := CollectionTab.new()
var adventures := AdventuresTab.new()
var errands := ErrandsTab.new()
var home := HomeTab.new()
var machine := MachineTab.new()
var automation := AutomationTab.new()
var spine := Spine.new()
var bubble := PetBubble.new()
var _coins := UiTheme.chip("coin", "", UiTheme.CYAN)
var _xp := UiTheme.chip("xp", "", UiTheme.GOLD)
var _tabs := {}  # id -> Control
var _current := "boxes"
var _rng := RandomNumberGenerator.new()

## Tab ids (the save and unlocks use these), with the names and icons players see.
const TABS := [
	["home", "home", "home"],
	["machine", "machine", "machine"],
	["boxes", "boxes", "boxes"],
	["collection", "collectibles", "pets"],
	["adventures", "adventures", "trips"],
	["errands", "errands", "errands"],
	["automation", "automation", "automation"],
	["inventory", "workbench", "bag"],
]


func _init() -> void:
	add_theme_constant_override("separation", 0)
	_rng.randomize()
	add_child(spine)
	var page := DottedPage.new()
	page.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(page)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	page.add_child(column)

	# along the top: the bubble, coins and xp, the window buttons
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	UiTheme.make_window_handle(top)
	column.add_child(top)
	var tail_gap := Control.new()
	tail_gap.custom_minimum_size = Vector2(4, 0)
	tail_gap.mouse_filter = MOUSE_FILTER_PASS
	top.add_child(tail_gap)
	# the bubble floats in a slot one line tall: a longer line grows it down over the page instead
	# of pushing the whole window down
	var slot := Control.new()
	slot.size_flags_horizontal = SIZE_EXPAND_FILL
	slot.size_flags_vertical = SIZE_SHRINK_CENTER
	slot.mouse_filter = MOUSE_FILTER_PASS
	slot.custom_minimum_size.y = PetBubble.one_line_height()
	bubble.z_index = 5
	slot.add_child(bubble)
	var fit := func():
		bubble.position = Vector2.ZERO
		bubble.size = Vector2(slot.size.x, bubble.get_combined_minimum_size().y)
	slot.resized.connect(fit)
	bubble.minimum_size_changed.connect(fit)
	top.add_child(slot)
	top.add_child(_coins)
	top.add_child(_xp)
	if OS.is_debug_build():
		var cheat := UiTheme.small_button("+%d" % GameState.DEBUG_COINS, func(): GameState.add_debug_coins())
		cheat.tooltip_text = "debug only: free coins for testing"
		cheat.add_theme_font_size_override("font_size", UiTheme.SMALL)
		top.add_child(cheat)
	top.add_child(_window_button("▾", "shrink to the corner", func(): collapse_requested.emit()))
	top.add_child(_window_button("×", "close", func(): quit_requested.emit()))

	var body := MarginContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	column.add_child(body)
	var workbench := WorkbenchTab.new()
	collection.toys.workbench_requested.connect(func(edition):
		show_tab("inventory")
		workbench.show_toy(edition))
	workbench.bag.open_box_requested.connect(func(box_id):
		show_tab("boxes")
		boxes.open(box_id, 1))
	home.go.connect(show_tab)
	home.open_box.connect(func(box_id):
		show_tab("boxes")
		boxes.open(box_id, 1))
	_tabs = { "home": home, "machine": machine, "boxes": boxes, "collection": collection, "adventures": adventures, "errands": errands, "automation": automation, "inventory": workbench, "settings": SettingsTab.new() }
	for tab_id in _tabs:
		body.add_child(_tabs[tab_id])
	for t in TABS:
		spine.add_tab(t[0], t[1], t[2])
	spine.add_tab("settings", "", "settings", true)
	spine.tab_pressed.connect(_on_tab_pressed)
	show_start()

	GameState.changed.connect(_refresh)
	GameState.collection.active_changed.connect(func(_p): _refresh())
	GameState.adventures_changed.connect(_refresh_tabs)
	GameState.tutorial_changed.connect(_refresh_tabs)
	GameState.unlocked.connect(func(_e): _refresh_tabs())
	GameState.new_game.connect(_refresh_tabs)
	GameState.play_ended.connect(func(_e): PetBubble.say_line(self, "toy_done"))
	_refresh()
	_refresh_tabs()


func _window_button(text: String, tip: String, on_pressed: Callable) -> Button:
	var b := UiTheme.small_button(text, on_pressed)
	b.tooltip_text = tip
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	return b


## Which tabs a tutorial step shows: they appear one by one as you learn them.
const TUTORIAL_TABS := {
	"pull": ["home", "machine", "collection", "settings"],
	"machine": ["home", "machine", "collection", "settings"],
	"send": ["home", "machine", "collection", "adventures", "settings"],
}


func _refresh_tabs() -> void:
	var shown: Array = TUTORIAL_TABS.get(GameState.tutorial, _tabs.keys())
	var back := GameState.runs.any(func(r: RunState): return r.status != RunState.Status.WALKING)
	for tab_id in _tabs:
		var news := false
		match tab_id:
			"boxes": news = GameState.box_news()
			"adventures": news = back
		spine.set_tab_state(tab_id, tab_id in shown and not GameState.tab_hidden(tab_id), not GameState.tab_open(tab_id), news)
		spine.tab_button(tab_id).tooltip_text = GameState.tab_hint(tab_id)
	# the very start: the capsule machine
	if GameState.tutorial == "pull":
		show_tab("machine")


func _on_tab_pressed(tab_id: String) -> void:
	if not GameState.tab_open(tab_id):
		# locked: the pet says what opens it, and you stay where you were
		PetBubble.say(self, GameState.tab_hint(tab_id))
		return
	show_tab(tab_id)


## The button the tutorial is pointing at right now, or null.
func tutorial_target() -> Control:
	match GameState.tutorial:
		"pull":
			# only until the first pull: after that you know what the lever does
			if int(GameState.machine.pulls) > 0:
				return null
			return machine.tutorial_target() if machine.visible else spine.tab_button("machine")
		"send":
			return adventures.tutorial_target() if adventures.visible else spine.tab_button("adventures")
	return null


## Where the full game opens: your pet's room, or where the tutorial is.
func show_start() -> void:
	match GameState.tutorial:
		"done": show_tab("home")
		"send": show_tab("adventures")
		_: show_tab("machine")


func show_tab(tab_id: String, opens: Array = []) -> void:
	if not _tabs.has(tab_id) or not GameState.tab_open(tab_id):
		return
	_current = tab_id
	for n in _tabs:
		_tabs[n].visible = n == tab_id
	spine.set_current(tab_id)
	if not opens.is_empty() and _tabs[tab_id].has_method("show_unlock"):  # an unlock's "show me": the tab can open on what it opened
		_tabs[tab_id].show_unlock(opens)
	# tabs with something of their own to say say it when they open; the rest get a general line
	if not _tabs[tab_id].has_method("speak"):
		_general_line()


func current_tab() -> String:
	return _current


func _general_line() -> void:
	var pet := GameState.collection.active()
	if pet == null:
		return
	var catalog := Catalog.shared()
	PetBubble.say(self, PetVoice.line(pet, PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog), _rng, catalog))


func _refresh() -> void:
	(_coins.find_child("Amount", true, false) as Label).text = UiTheme.num(GameState.coins)
	(_xp.find_child("Amount", true, false) as Label).text = _thousands(GameState.xp)
	bubble.visible = GameState.collection.active() != null
	# news dots: boxes waiting in the bag, trips waiting for you
	spine.set_news("boxes", GameState.box_news())
	spine.set_news("adventures", GameState.runs.any(func(r: RunState): return r.status != RunState.Status.WALKING))


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


## The page: the dotted backing paper of a sticker book.
class DottedPage extends MarginContainer:
	func _init() -> void:
		add_theme_constant_override("margin_left", 16)
		add_theme_constant_override("margin_right", 12)
		add_theme_constant_override("margin_top", 10)
		add_theme_constant_override("margin_bottom", 12)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PAGE)
		var y := 8.0
		while y < size.y:
			var x := 8.0
			while x < size.x:
				draw_rect(Rect2(x - 1, y - 1, 2, 2), UiTheme.DOT)
				x += 16.0
			y += 16.0
