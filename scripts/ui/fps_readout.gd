class_name FpsReadout
extends Label
## The "show fps" setting: a small frame rate readout in the bottom corner of the full game's page.
## Updates twice a second and never takes clicks from what's under it.

var _wait := 0.0  # seconds until the next update


func _init() -> void:
	name = "FpsReadout"
	mouse_filter = MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	size_flags_vertical = SIZE_FILL  # labels shrink to the middle by default: fill the page down to its bottom
	add_theme_color_override("font_color", UiTheme.MUTED)
	add_theme_font_size_override("font_size", UiTheme.SMALL)
	visible = Settings.show_fps
	Settings.changed.connect(_on_settings_changed)


## A setting changed: show or hide with the switch.
func _on_settings_changed() -> void:
	visible = Settings.show_fps


func _process(delta: float) -> void:
	if not visible:
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = 0.5
	text = "%d fps" % Engine.get_frames_per_second()
