extends Node
## Autoload "GameState": the pet's stats, coins and saving.
## Stats never punish you for being away: they sink to a floor and stay there.

signal changed

const SAVE_PATH := "user://save.json"
const STAT_FLOOR := 20.0
const HUNGER_DECAY := 100.0 / (4.0 * 3600.0)  # full to floor in about 4 h
const HAPPY_DECAY := 100.0 / (6.0 * 3600.0)
const COIN_INTERVAL := 10.0  # seconds per coin at full happiness
const FEED_COST := 3

var hunger := 80.0  # 100 = full
var happiness := 80.0
var coins := 10
var pet_out := false

var _coin_timer := 0.0
var _save_timer := 0.0


func _ready() -> void:
	load_game()


func _process(delta: float) -> void:
	hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * delta)
	happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * delta)

	# happy, fed pets earn faster; an ignored one still earns a little
	_coin_timer += delta * lerpf(0.4, 1.0, (happiness + hunger) / 200.0)
	if _coin_timer >= COIN_INTERVAL:
		_coin_timer -= COIN_INTERVAL
		coins += 1
		changed.emit()

	_save_timer += delta
	if _save_timer >= 30.0:
		_save_timer = 0.0
		save_game()


func feed() -> bool:
	if coins < FEED_COST or hunger >= 99.0:
		return false
	coins -= FEED_COST
	hunger = minf(100.0, hunger + 30.0)
	happiness = minf(100.0, happiness + 5.0)
	changed.emit()
	return true


func pat() -> void:
	happiness = minf(100.0, happiness + 8.0)
	changed.emit()


func set_pet_out(value: bool) -> void:
	pet_out = value
	changed.emit()


func save_game() -> void:
	var data := {
		"hunger": hunger,
		"happiness": happiness,
		"coins": coins,
		"pet_out": pet_out,
		"saved_at": Time.get_unix_time_from_system(),
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	hunger = data.get("hunger", hunger)
	happiness = data.get("happiness", happiness)
	coins = int(data.get("coins", coins))
	pet_out = data.get("pet_out", false)

	# catch up on time spent closed: coins at the slowest rate, stats to the floor at worst
	var away := Time.get_unix_time_from_system() - float(data.get("saved_at", 0.0))
	if away > 0.0:
		coins += int(minf(away, 12.0 * 3600.0) * 0.4 / COIN_INTERVAL)
		hunger = maxf(STAT_FLOOR, hunger - HUNGER_DECAY * away)
		happiness = maxf(STAT_FLOOR, happiness - HAPPY_DECAY * away)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		save_game()
