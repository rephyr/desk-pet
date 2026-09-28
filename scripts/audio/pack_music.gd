class_name PackMusic
extends AudioStreamPlayer
## The music of opening one pack (made in LMMS, see tools/music/pack_sounds.py). When the strip
## comes off the pack breathes out (a soft airy shimmer) and a hum starts inside it; every rarity
## step adds a layer on top (celesta, strings, choir, brass, and something slightly wrong for
## mythic) with a little rising chime; pulling the pet out brings in tremolo strings that want to
## resolve; the reveal plays the rarity's fanfare, which resolves them, while the layers fade.
##
## The layers are seamless loops of the same length, played together by one
## AudioStreamSynchronized so they stay in time; each fades in and out on its own. They're on the
## "Music" bus; the chimes and fanfares are one-shots on the "Sound" bus (Sfx). Files and volumes
## are in data/sounds.json ("pack").

const AIR := 0
const HUM := 1
const HOLD := 7  # after the five rarity layers (uncommon..mythic are 2..6)
const OFF_DB := -60.0
const OPEN_FADE := [0.3, 1.2]  # seconds for the air and the hum to come in
const HOLD_FADE := 2.5
const END_FADE := 0.9  # the layers fading under the fanfare

var _sounds: Dictionary = Catalog.shared().sounds.get("pack", {})
var _sync := AudioStreamSynchronized.new()
var _level: Array[float] = []  # each layer, 0..1
var _target: Array[float] = []
var _speed: Array[float] = []  # per second


func _ready() -> void:
	bus = "Music"
	volume_db = float(_sounds.get("loops_db", 0.0))
	var files: Array = _sounds.get("loops", [])
	_sync.stream_count = files.size()
	for i in files.size():
		var loop := Sfx.stream_of({ "file": files[i] })
		if loop is AudioStreamOggVorbis:
			(loop as AudioStreamOggVorbis).loop = true
		_sync.set_sync_stream(i, loop)
		_sync.set_sync_stream_volume(i, OFF_DB)
		_level.append(0.0)
		_target.append(0.0)
		_speed.append(1.0)
	stream = _sync


## The strip came off: the pack breathes out, and the hum starts.
func open() -> void:
	for i in _level.size():
		_level[i] = 0.0
		_target[i] = 0.0
	_fade(AIR, 1.0, OPEN_FADE[0])
	_fade(HUM, 1.0, OPEN_FADE[1])
	play()


## The light climbed to `rank` (1 = uncommon): its layer comes in, with a chime.
func to_rank(rank: int) -> void:
	_fade(HUM + rank, 1.0, float(Catalog.shared().reveal.get("layer_fade", 0.8)) / Settings.reveal_speed)
	var steps: Array = _sounds.get("steps", [])
	if rank >= 1 and rank <= steps.size():
		Sfx.play(self, steps[rank - 1])


## Pulling the pet out: strings that want to resolve.
func hold() -> void:
	_fade(HOLD, 1.0, HOLD_FADE)


## The pet is out: the rarity's fanfare, and everything else fades under it.
func climax(rarity: String) -> void:
	Sfx.play(self, _sounds.get("reveal", {}).get(rarity, {}))
	stop_layers(END_FADE)


## "…and it's foil!"
func finish() -> void:
	Sfx.play(self, _sounds.get("finish", {}))


## Fades everything out (or at once, for 0).
func stop_layers(seconds := 0.3) -> void:
	for i in _level.size():
		_fade(i, 0.0, seconds)
		if seconds <= 0.0:
			_level[i] = 0.0


func _fade(layer: int, to: float, seconds: float) -> void:
	if layer < 0 or layer >= _level.size():
		return
	_target[layer] = to
	_speed[layer] = 1.0 / maxf(seconds, 0.01)


func _process(delta: float) -> void:
	if not playing:
		return
	var any := false
	for i in _level.size():
		_level[i] = move_toward(_level[i], _target[i], _speed[i] * delta)
		_sync.set_sync_stream_volume(i, linear_to_db(_level[i]) if _level[i] > 0.001 else OFF_DB)
		any = any or _level[i] > 0.0 or _target[i] > 0.0
	if not any:
		stop()
