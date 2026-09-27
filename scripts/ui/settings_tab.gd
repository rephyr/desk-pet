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

	add_child(_toggle("skip the pack animation when opening one box", "skip_single_reveal"))
	add_child(_toggle("skip the mist on very rare pulls", "skip_ritual"))

	add_child(UiTheme.label("your pet at work", UiTheme.PINK))
	var reserve_row := HBoxContainer.new()
	reserve_row.add_theme_constant_override("separation", 10)
	var reserve_name := UiTheme.label("coins your pet always keeps")
	reserve_name.custom_minimum_size = Vector2(230, 0)
	reserve_row.add_child(reserve_name)
	var reserve := HSlider.new()
	reserve.min_value = 0
	reserve.max_value = 200
	reserve.step = 10
	reserve.value = GameState.coin_reserve
	reserve.custom_minimum_size = Vector2(200, 0)
	reserve.focus_mode = FOCUS_NONE
	reserve_row.add_child(reserve)
	var reserve_value := UiTheme.label("◆%d" % GameState.coin_reserve, UiTheme.CYAN)
	reserve_row.add_child(reserve_value)
	reserve.value_changed.connect(func(v):
		GameState.coin_reserve = int(v)
		reserve_value.text = "◆%d" % int(v)
		GameState.save_game())
	add_child(reserve_row)
	if OS.is_debug_build():
		add_child(UiTheme.label("dev", UiTheme.PINK))
		var fresh := UiTheme.button("dev: new game (backs up your save first)")
		fresh.pressed.connect(func():
			# a second click within a few seconds confirms, so it can't happen by accident
			if fresh.text.begins_with("sure?"):
				GameState.debug_new_game()
				fresh.text = "done ♡ (old save: save-before-new-game-*.json)"
			else:
				fresh.text = "sure? click again to start over"
				get_tree().create_timer(4.0).timeout.connect(func():
					if fresh.text.begins_with("sure?"):
						fresh.text = "dev: new game (backs up your save first)"))
		add_child(fresh)


func _toggle(text: String, key: String) -> CheckButton:
	var b := CheckButton.new()
	b.text = text
	b.focus_mode = FOCUS_NONE
	b.button_pressed = Settings.get(key)
	b.toggled.connect(func(on): Settings.set_value(key, on))
	return b
