class_name BoostTag
extends Button
## The small dashed cyan "x1.51" by the coin pill: everything multiplying coins right now (shared
## boosts only: toys, your pet's badges, later book stickers and the kitchen). Hidden until coins
## have a boost. Tap it to print the boost receipt (BoostReceipt); tap again to fold it. Solid pink
## while the receipt is out. Design: design/mockups/screens/receipt.html (look A).

signal toggled_receipt(open: bool)

var _on := false
var _check := 0.0  # seconds until the number is looked at again


func _init() -> void:
	focus_mode = FOCUS_NONE
	size_flags_vertical = SIZE_SHRINK_CENTER
	add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	add_theme_font_size_override("font_size", 13)
	visible = false
	_style()
	pressed.connect(func():
		set_on(not _on)
		toggled_receipt.emit(_on))


func set_on(on: bool) -> void:
	_on = on
	_style()


func _style() -> void:
	var off := UiTheme.stitched(UiTheme.CYAN.lerp(UiTheme.LINE, 0.45), UiTheme.DEEP, 999, 0)
	off.dash = 5.0
	off.gap = 4.0
	var on := UiTheme.box(UiTheme.PINK_PRESSED, UiTheme.PINK, 999, 2, 0)
	for sb: StyleBox in [off, on]:
		sb.content_margin_left = 9
		sb.content_margin_right = 9
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
	var hover := off.duplicate() as StitchBox
	hover.dash_color = UiTheme.CYAN
	for state in ["normal", "pressed", "focus"]:
		add_theme_stylebox_override(state, on if _on else off)
	for state in ["hover", "hover_pressed"]:
		add_theme_stylebox_override(state, on if _on else hover)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		add_theme_color_override(c, UiTheme.TEXT if _on else UiTheme.CYAN)


## The number as it is now; hidden while nothing boosts coins.
func refresh() -> void:
	var has := not GameState.boost_parts("coins").is_empty()
	if has != visible:
		visible = has
	if has:
		var t := Boosts.times(GameState.boost("coins"))
		if t != text:
			text = t


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		refresh()
