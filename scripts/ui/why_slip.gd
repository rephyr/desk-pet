class_name WhySlip
extends Control
## The small torn slip a "why so much?" tape opens: where the coins started ("found on the way 47"),
## one dotted-leader line per thing that multiplied them ("a tote bag x1.30", "our boosts x1.51"), a
## dashed rule and "all together" with the big cyan number. The data is a Boosts.why dictionary.
## It floats over what's under it and takes no clicks (the tape folds it).
## Design: design/mockups/screens/receipt.html (look A).

const WIDTH := 214.0

var _col := VBoxContainer.new()
var _shown := ""


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	z_index = UiTheme.Z_SLIP
	var margin := MarginContainer.new()
	margin.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_bottom", int(8 + BoostReceipt.TOOTH))
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(margin)
	_col.add_theme_constant_override("separation", 0)
	_col.mouse_filter = MOUSE_FILTER_IGNORE
	margin.add_child(_col)


## Fills it with a why ({ start: { name, value }, lines: [ { name, x } ], total }).
func show_why(why: Dictionary) -> void:
	var key := str(why)
	if key == _shown:
		return
	_shown = key
	UiTheme.clear(_col)
	if why.is_empty():
		return
	_col.add_child(BoostReceipt.leader(str(why.start.name), UiTheme.num(float(why.start.value)), UiTheme.TEXT, UiTheme.MUTED))
	for l in why.lines:
		_col.add_child(BoostReceipt.leader(str(l.name), Boosts.times(float(l.x)), UiTheme.TEXT, UiTheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 3
	_col.add_child(gap)
	_col.add_child(BoostReceipt.rule(UiTheme.LILAC_SEAM, 4))
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 4)
	var words := UiTheme.label("all together", UiTheme.MUTED, UiTheme.SMALL)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.size_flags_vertical = SIZE_SHRINK_END
	eq.add_child(words)
	eq.add_child(UiTheme.title(UiTheme.num(float(why.total)), 15, UiTheme.CYAN))
	_col.add_child(eq)
	var h := 9.0 + _col.get_combined_minimum_size().y + 8.0 + BoostReceipt.TOOTH
	size = Vector2(WIDTH, h)
	custom_minimum_size = Vector2.ZERO
	queue_redraw()


func _draw() -> void:
	BoostReceipt.draw_paper(self, Rect2(Vector2.ZERO, size), UiTheme.DEEP, UiTheme.LILAC_SEAM, BoostReceipt.TOOTH)
