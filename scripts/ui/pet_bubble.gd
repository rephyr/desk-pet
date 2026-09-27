class_name PetBubble
extends PanelContainer
## Your active pet's speech bubble along the top of the full game. Any screen can make the pet
## talk with PetBubble.say(self, "..."); the tail points back at the pet on its moon.

const GROUP := "pet_bubble"
const MARGIN_Y := 7


## How tall the bubble is with one line in it (the top bar keeps this much room for it).
static func one_line_height() -> float:
	return UiTheme.BODY_FONT.get_height(UiTheme.FONT_SIZE) + MARGIN_Y * 2

var _text := UiTheme.label("")


func _init() -> void:
	add_to_group(GROUP)
	var sb := UiTheme.sticker(UiTheme.PINK_SEAM, 14, UiTheme.RAISED, 0)
	sb.content_margin_left = 16
	sb.content_margin_right = 14
	sb.content_margin_top = MARGIN_Y
	sb.content_margin_bottom = MARGIN_Y
	add_theme_stylebox_override("panel", sb)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_SHRINK_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.max_lines_visible = 2
	add_child(_text)


## Makes the pet say `text`, from anywhere in the full game.
static func say(from: Node, text: String) -> void:
	if from.is_inside_tree() and text != "":
		from.get_tree().call_group(GROUP, "show_line", text)


## Says one of the pet's lines for `key` (data/voice.json "ui"), with {count} and the like filled in.
static func say_line(from: Node, key: String, fill := {}) -> void:
	say(from, line(key, fill))


## One of the pet's lines for `key` (data/voice.json "ui") filled in, or "" if there are none.
static func line(key: String, fill := {}) -> String:
	var lines: Array = Catalog.shared().voice.get("ui", {}).get(key, [])
	if lines.is_empty():
		return ""
	var text: String = lines[randi() % lines.size()]
	for k in fill:
		text = text.replace("{%s}" % k, str(fill[k]))
	return text


func show_line(text: String) -> void:
	if text == _text.text:
		return
	_text.text = text
	# a little pop, like the pet just spoke
	pivot_offset = Vector2(0, size.y / 2.0)
	scale = Vector2(0.97, 0.97)
	create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	# the tail: a little rotated square poking out of the left edge
	var mid := Vector2(0, size.y / 2.0)
	var pts := PackedVector2Array([mid + Vector2(1, -7), mid + Vector2(-7, 0), mid + Vector2(1, 7)])
	draw_colored_polygon(pts, UiTheme.RAISED)
	draw_polyline(pts, UiTheme.PINK_SEAM, 2.0, true)
