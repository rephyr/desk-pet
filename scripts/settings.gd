extends Node
## Autoload "Settings": player preferences, saved apart from game progress so a bad save
## never resets them (and they never reset a save).

signal changed

const PATH := "user://settings.json"
const MIN_SPEED := 0.5
const MAX_SPEED := 3.0

var reveal_speed := 1.0  # multiplies every reveal animation
var skip_single_reveal := false  # open 1 box shows the result straight away
var skip_ritual := false  # rare pulls skip the blocker you drag around


func _init() -> void:
	var data := SaveFile.read(PATH)
	reveal_speed = clampf(float(data.get("reveal_speed", reveal_speed)), MIN_SPEED, MAX_SPEED)
	skip_single_reveal = bool(data.get("skip_single_reveal", skip_single_reveal))
	skip_ritual = bool(data.get("skip_ritual", skip_ritual))


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	reveal_speed = clampf(reveal_speed, MIN_SPEED, MAX_SPEED)
	SaveFile.write(PATH, {
		"reveal_speed": reveal_speed,
		"skip_single_reveal": skip_single_reveal,
		"skip_ritual": skip_ritual,
	})
	changed.emit()
