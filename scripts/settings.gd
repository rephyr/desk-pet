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
var music_volume := 0.8  # 0 to 1: the hum under pack openings (and music later)
var sound_volume := 0.8  # 0 to 1: everything else you hear
## How much your pet acts out its job out on your windows (QuietPaws): 0 off, 1 big things,
## 2 everything. Only what's drawn: it never changes what gets opened or cranked.
const PAWS_LEVELS: Array[String] = ["off", "big things", "everything"]
const PAWS_DEFAULT := 2
var paws := PAWS_DEFAULT


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
	music_volume = clampf(float(data.get("music_volume", music_volume)), 0.0, 1.0)
	sound_volume = clampf(float(data.get("sound_volume", sound_volume)), 0.0, 1.0)
	paws = paws_from(data)


## The quiet paws level in a settings file's data (the default when it has none).
static func paws_from(data: Dictionary) -> int:
	return clampi(int(data.get("paws", PAWS_DEFAULT)), 0, PAWS_LEVELS.size() - 1)


func _ready() -> void:
	_apply_video()
	_apply_audio()


## The full game window's size, in UI pixels before the screen's own scale.
func window_size() -> Vector2i:
	return RESOLUTIONS[resolution]


## How much the full game is scaled up to fill its window.
func zoom() -> float:
	return float(window_size().x) / float(RESOLUTIONS[0].x)


func _apply_video() -> void:
	Engine.max_fps = max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## Two buses under Master: "Music" and "Sound", each at the player's volume.
func _apply_audio() -> void:
	for bus in [["Music", music_volume], ["Sound", sound_volume]]:
		var i := AudioServer.get_bus_index(bus[0])
		if i < 0:
			AudioServer.add_bus()
			i = AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus[0])
			AudioServer.set_bus_send(i, "Master")
		AudioServer.set_bus_volume_db(i, linear_to_db(bus[1]))
		AudioServer.set_bus_mute(i, bus[1] <= 0.0)


func set_value(key: String, value: Variant) -> void:
	set(key, value)
	reveal_speed = clampf(reveal_speed, MIN_SPEED, MAX_SPEED)
	paws = clampi(paws, 0, PAWS_LEVELS.size() - 1)
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
		"music_volume": music_volume,
		"sound_volume": sound_volume,
		"paws": paws,
	})
	changed.emit()
	if key in ["color_theme", "font_set", "icon_style"]:
		look_changed.emit()
	if key in ["resolution", "max_fps", "vsync"]:
		_apply_video()
		video_changed.emit()
	if key in ["music_volume", "sound_volume"]:
		_apply_audio()
