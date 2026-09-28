class_name Sfx
extends RefCounted
## One-shot sounds. An entry is a { file, volume_db } from data/sounds.json; it plays once on the
## "Sound" bus and cleans up after itself.

const DIR := "res://assets/sounds/"  # load() keeps what it loaded, so each file is read once


## Plays `entry` from `owner` (any node in the tree). `semitones` shifts the pitch.
static func play(owner: Node, entry: Dictionary, semitones := 0.0) -> void:
	if entry.is_empty() or owner == null or not owner.is_inside_tree():
		return
	var stream := stream_of(entry)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "Sound"
	player.volume_db = float(entry.get("volume_db", 0.0))
	player.pitch_scale = pow(2.0, semitones / 12.0)
	player.finished.connect(player.queue_free)
	owner.add_child(player)
	player.play()


## The sound an entry points at, or null.
static func stream_of(entry: Dictionary) -> AudioStream:
	var file := str(entry.get("file", ""))
	if file == "" or not ResourceLoader.exists(DIR + file):
		return null
	return load(DIR + file)
