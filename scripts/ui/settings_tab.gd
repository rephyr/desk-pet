class_name SettingsTab
extends VBoxContainer
## Player preferences (see the Settings autoload).


func _init() -> void:
	add_theme_constant_override("separation", 14)
	add_child(UiTheme.label("box opening", UiTheme.PINK))

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 10)
	var name_label := UiTheme.label("reveal speed")
	name_label.custom_minimum_size = Vector2(180, 0)
	speed_row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = Settings.MIN_SPEED
	slider.max_value = Settings.MAX_SPEED
	slider.step = 0.25
	slider.value = Settings.reveal_speed
	slider.custom_minimum_size = Vector2(240, 0)
	slider.focus_mode = FOCUS_NONE
	speed_row.add_child(slider)
	var value_label := UiTheme.label("%s×" % Settings.reveal_speed, UiTheme.CYAN)
	speed_row.add_child(value_label)
	slider.value_changed.connect(func(v):
		value_label.text = "%s×" % v
		Settings.set_value("reveal_speed", v))
	add_child(speed_row)

	add_child(_toggle("skip the chest when opening one box", "skip_single_reveal"))
	add_child(_toggle("skip the mist on very rare pulls", "skip_ritual"))


func _toggle(text: String, key: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.button_pressed = Settings.get(key)
	b.toggled.connect(func(on): Settings.set_value(key, on))
	return b
