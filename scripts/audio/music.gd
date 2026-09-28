class_name Music
extends AudioStreamPlayer
## Background music on the "Music" bus (its volume is the music slider in settings). It plays
## while the full game is open and fades out when the game goes back to its small corner panel or
## tucks away for something fullscreen: on the desktop the pet stays quiet. The tune is made in
## LMMS (tools/music/home_room.py) and loops seamlessly.
##
## While a pack is being opened (PackOpening sets `ducked`) it steps back so the pack's own music
## can play.

const TRACK := "res://assets/music/home_room.ogg"
const VOLUME_DB := -10.0
const FADE_IN := 2.0  # seconds
const FADE_OUT := 1.2
const SILENT_DB := -60.0
const DUCK_DB := -20.0  # how far it steps back under a pack opening
const DUCK_FADE := 0.6

static var ducked := false

var wanted := false  # the full game is open: fade in (false: fade out, then pause)
var _level := 0.0  # 0..1, where the fade is
var _duck := 0.0  # 0..1, how far it has stepped back


func _ready() -> void:
	bus = "Music"
	var track := load(TRACK) as AudioStream
	if track is AudioStreamOggVorbis:
		(track as AudioStreamOggVorbis).loop = true
	stream = track
	volume_db = SILENT_DB


func _process(delta: float) -> void:
	var before := _level
	_level = move_toward(_level, 1.0 if wanted else 0.0, delta / (FADE_IN if wanted else FADE_OUT))
	if _level > 0.0:
		if stream_paused:
			stream_paused = false  # picks up where it left off
		elif not playing:
			play()
	elif before > 0.0:
		stream_paused = true
	_duck = move_toward(_duck, 1.0 if ducked else 0.0, delta / DUCK_FADE)
	if _level > 0.0:
		volume_db = lerpf(SILENT_DB, VOLUME_DB, sqrt(_level)) + DUCK_DB * _duck
