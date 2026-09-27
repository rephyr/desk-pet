extends Node
## Autoload "Settings": player preferences, saved apart from game progress so a bad save
## never resets them (and they never reset a save).

signal changed
signal look_changed  ## colours, font or icons changed: windows rebuild in the new look
signal video_changed  ## resolution, frame rate or vsync changed

var file_path := DevProfile.path("settings.json")  # or a test profile's (debug builds)
const MIN_SPEED := 0.5
const MAX_SPEED := 3.0
## Sizes of the full game window. The game is laid out at the first one and scales up to fill
## the others (on top of the screen's own scale).
const RESOLUTIONS: Array[Vector2i] = [Vector2i(920, 600), Vector2i(1150, 750), Vector2i(1380, 900), Vector2i(1610, 1050), Vector2i(1840, 1200)]
const FPS_CAPS: Array[int] = [30, 60, 120, 144, 0]  # 0: no cap

var reveal_speed := 1.0  # multiplies every reveal animation
var skip_single_reveal := false  # open 1 box shows the result straight away
var skip_ritual := false  # rare pulls skip the blocker you drag around
var color_theme := ""  # ids from data/themes.json; "" means the default
var font_set := ""
var icon_style := ""
var resolution := 0  # index into RESOLUTIONS
var max_fps := 0  # frame rate cap, 0 for none
var vsync := true


func _init() -> void:
	var data := SaveFile.read(file_path)
	reveal_speed = clampf(float(data.get("reveal_speed", reveal_speed)), MIN_SPEED, MAX_SPEED)
	skip_single_reveal = bool(data.get("skip_single_reveal", skip_single_reveal))
	skip_ritual = bool(data.get("skip_ritual", skip_ritual))
	color_theme = str(data.get("color_theme", color_theme))
	font_set = str(data.get("font_set", font_set))
	icon_style = str(data.get("icon_style", icon_style))
	resolution = clampi(int(data.get("resolution", resolution)), 0, RESOLUTIONS.size() - 1)
	max_fps = int(data.get("max_fps", max_fps))
	vsync = bool(data.get("vsync", vsync))


func _ready() -> void:
	_apply_video()


## The full game window's size, in UI pixels before the screen's own scale.
func window_size() -> Vector2i:
	return RESOLUTIONS[resolution]


## How much the full game is scaled up to fill its window.
func zoom() -> float:
	return float(window_size().x) / float(RESOLUTIONS[0].x)


func _apply_video() -> void:
	Engine.max_fps = max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	reveal_speed = clampf(reveal_speed, MIN_SPEED, MAX_SPEED)
	SaveFile.write(file_path, {
		"reveal_speed": reveal_speed,
		"skip_single_reveal": skip_single_reveal,
		"skip_ritual": skip_ritual,
		"color_theme": color_theme,
		"font_set": font_set,
		"icon_style": icon_style,
		"resolution": resolution,
		"max_fps": max_fps,
		"vsync": vsync,
	})
	changed.emit()
	if key in ["color_theme", "font_set", "icon_style"]:
		look_changed.emit()
	if key in ["resolution", "max_fps", "vsync"]:
		_apply_video()
		video_changed.emit()
