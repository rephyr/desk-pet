class_name UnlockPopup
extends Control
## Something new opened up (data/unlocks.json): a card pops up over the full game with what it is,
## what it does, and what found it. "show me" goes to its tab (if it has one), "lovely" closes it.
## Unlocks that happen while the game sits small in the corner wait here until the full game is
## open again, and several in a row come one after another. A full collection book page's reward
## sticker (GameState.sticker_opened) comes the same way.

signal go(tab_id: String, unlock_id: String)

var can_show: Callable  # () -> bool: whether the full game is on screen

var _queue: Array[Dictionary] = []
var _dim := ColorRect.new()
var _card := PanelContainer.new()
var _found := UiTheme.label("", UiTheme.GOLD, UiTheme.SMALL + 1)
var _title := UiTheme.title("", 22)
var _text := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 2)
var _buttons := HBoxContainer.new()
var _showing := false
var _sticker_showing := false
var _quiet_stickers := false  # the dev driver's "stickers off"
static var up := false  # a card is up (other things that pop, like a new box tier arriving, wait for it)


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	_dim.color = Color(UiTheme.SKY, 0.7)
	_dim.mouse_filter = MOUSE_FILTER_STOP  # the game waits under it
	add_child(_dim)
	_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.PINK_SEAM, 14, UiTheme.RAISED, 20))
	_card.custom_minimum_size = Vector2(340, 0)
	_card.draw.connect(func():
		# a strip of tape holding it on
		var tape := Rect2(_card.size.x / 2.0 - 26.0, -9.0, 52.0, 16.0)
		_card.draw_set_transform(tape.get_center(), deg_to_rad(-3.0))
		_card.draw_rect(Rect2(-tape.size / 2.0, tape.size), Color(UiTheme.LILAC, 0.45))
		_card.draw_set_transform(Vector2.ZERO))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_card.add_child(col)
	col.add_child(_found)
	col.add_child(_title)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	col.add_child(_text)
	_buttons.add_theme_constant_override("separation", 8)
	_buttons.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(_buttons)
	add_child(Tilted.new(_card, -1.5))
	GameState.unlocked.connect(func(entry):
		if not entry.get("quiet", false):  # quiet ones open without a card
			_queue.append(entry))
	GameState.sticker_opened.connect(_queue_sticker)


## A collection book page filled up: its reward sticker comes as a card too.
func _queue_sticker(page_id: String) -> void:
	if _quiet_stickers:
		return
	var page := Book.page(Catalog.shared(), page_id)
	if page.is_empty():
		return
	_queue.append({ "sticker": page_id, "found_line": "%s page full!" % page_id,
		"popup": { "title": str(page.name), "text": Book.words(Catalog.shared(), page), "go": "book:%s" % page_id } })


func _process(_delta: float) -> void:
	if _showing or _queue.is_empty() or not (can_show.is_valid() and can_show.call()):
		return
	_show(_queue.pop_front())


func _show(entry: Dictionary) -> void:
	var popup: Dictionary = entry.get("popup", {})
	# what opened it: a find a pet brought home, or the first of something
	var earn: Dictionary = entry.get("earn", {})
	var find_name := str(Catalog.shared().finds.get(str(earn.get("find", "")), {}).get("name", ""))
	if entry.has("found_line"):
		_found.text = str(entry.found_line)
	elif find_name != "":
		_found.text = "found: %s" % find_name
	elif earn.has("first"):
		_found.text = "your first %s!" % earn.first
	else:
		_found.text = "something new!"
	_title.text = str(popup.get("title", "something new!"))
	_text.text = str(popup.get("text", entry.get("announce", "")))
	UiTheme.clear(_buttons)
	var tab := str(popup.get("go", ""))
	if tab != "":
		_buttons.add_child(UiTheme.button("show me", func():
			_close()
			go.emit(tab, str(entry.get("id", "")))))
	var lovely := UiTheme.button("lovely", _close)
	lovely.icon = UiTheme.icon("heart", 14)
	lovely.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lovely.add_theme_constant_override("icon_max_width", 14)
	_buttons.add_child(lovely)
	_showing = true
	_sticker_showing = entry.has("sticker")
	up = true
	visible = true
	# centre the card, then pop it in
	var holder := _card.get_parent() as Control
	holder.size = holder.get_combined_minimum_size()
	holder.position = (size - holder.size) / 2.0
	holder.pivot_offset = holder.size / 2.0
	holder.scale = Vector2(0.6, 0.6)
	modulate.a = 0.0
	var t := create_tween().set_parallel()
	t.tween_property(holder, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 1.0, 0.2)


## Test flows: sticker cards stop coming, and any waiting (or up) go away. Unlocks still come.
func quiet_stickers() -> void:
	_quiet_stickers = true
	_queue = _queue.filter(func(e): return not e.has("sticker"))
	if _showing and _sticker_showing:
		_close()


func _close() -> void:
	_showing = false
	up = false
	visible = false


func _exit_tree() -> void:
	if _showing:
		up = false  # freed while up (a look change rebuilds the panel): the new one starts clear
