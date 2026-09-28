class_name QuietPaws
extends RefCounted
## Quiet paws: out on your windows (DesktopPet) your pet keeps doing its one job in place, with
## poses only, no text. This is the brain: it reads the game and says which pose to strike; the
## desktop pet holds still for it and PawsView draws the props. It only watches: it never opens,
## buys or cranks anything, and never tells the game it was seen (GameState keeps opening packs in
## the background exactly as it would without it). Settings.paws picks how much it shows:
##   0 off         nothing, the pet just walks around
##   1 big things  a good pull held over its head (HOLD), a foot tap while an adventure waits (WAIT)
##   2 everything  the big things, plus the boxes routine (BOXES) and the tiny crank machine (MACHINE)
## Tuning in data/care.json "paws".

enum Pose { NONE, BOXES, MACHINE, HOLD, WAIT }
enum Phase { REACH, HOLD, SHAKE }  # the boxes routine: faces the pile, holds a pack, shakes it

const OFF := 0
const BIG := 1
const EVERYTHING := 2
const QUEUE := 3  # good pulls waiting to be held up, at most

var gs: Node  # GameState (or a test's own)
var pose := Pose.NONE
var phase := Phase.REACH
var held: Pet  # HOLD: the good pull over its head; BOXES: the new pet hopping off
var hop := 0.0  # 0 to 1 while an ordinary new pet hops away (0 when none)
var puff := 0.0  # 1 right after a pack pops, fading
var bounce := 0.0  # 1 right after the tiny machine gives a capsule, fading
var squash := 0.0  # a bounce for the view to take (then it sets this back to 0)
var crank := 0.0  # the tiny machine's handle, 0 to 1 a turn (follows automation.fill)
var dust := 0.0  # 1 on a foot tap, fading
var stint_left := 0.0  # seconds of standing still at work left (0: not at work)
var wants_still := false  # the desktop pet should stand still (a stint or a hold)
var just_ended := false  # a stint just ended: the desktop pet should walk again (it clears this)
var time := 0.0

var _cfg: Dictionary
var _pulls: Array[Dictionary] = []  # { pet, age } good pulls to hold up, oldest first
var _hold_left := 0.0  # > 0 while the front pull is held up
var _stint_room := false  # the edge had room for the pile or the machine when the stint began
var _hop_time := 1.1
var _level := EVERYTHING
var _delta := 0.016  # this frame's


func _init(state: Node = null) -> void:
	gs = state if state != null else Engine.get_main_loop().root.get_node_or_null("GameState")
	_cfg = gs.catalog.care.get("paws", {})
	_hop_time = float(_cfg.get("hop", 1.1))
	gs.opened_in_background.connect(opened)
	gs.pet_cranked.connect(cranked)


func cfg(key: String, fallback: Variant) -> Variant:
	return _cfg.get(key, fallback)


## One frame. `grounded`: standing or walking on an edge (not falling, not being dragged).
## `stopped`: standing still. `room`: the edge is wide enough for the pile or the machine.
## `level`: Settings.paws.
func step(delta: float, grounded: bool, stopped: bool, room: bool, level: int) -> void:
	time += delta
	_delta = delta
	_level = level
	puff = move_toward(puff, 0.0, delta * 2.0)
	bounce = move_toward(bounce, 0.0, delta * 1.6)
	dust = move_toward(dust, 0.0, delta * 3.3)
	if hop > 0.0:
		hop += delta / _hop_time
		if hop >= 1.0:
			hop = 0.0
			if pose != Pose.HOLD:
				held = null
	_follow_crank(delta)
	if level <= OFF:
		_pulls.clear()
		_hold_left = 0.0
		_end_stint()
		_set_pose(Pose.NONE)
		return

	# good pulls wait for the pet to land, but not forever
	var hold := float(cfg("hold", 4.0))
	for p in _pulls:
		p.age = float(p.age) + delta
	while not _pulls.is_empty() and _hold_left <= 0.0 and float(_pulls[0].age) > float(cfg("hold_waits", 10.0)):
		_pulls.pop_front()
	if not grounded:
		_end_stint()  # dragged or falling: no poses (a hold waits for the landing)
		just_ended = false  # it lands wherever it lands, and may start again there
		_hold_left = 0.0  # an interrupted hold starts over on landing, if it hasn't waited too long
		_set_pose(Pose.NONE)
		return
	if not _pulls.is_empty():
		if _hold_left <= 0.0:
			_hold_left = hold
			squash = 0.5
		_hold_left -= delta
		held = _pulls[0].pet
		hop = 0.0
		wants_still = true
		_set_pose(Pose.HOLD)
		if _hold_left <= 0.0:
			_pulls.pop_front()
			held = null
			wants_still = stint_left > 0.0
		return

	var kind := _stint_kind(room if stint_left <= 0.0 else _stint_room)
	if stint_left <= 0.0:
		if stopped and kind != Pose.NONE:
			var span: Array = cfg("stint", [20, 40])
			stint_left = randf_range(float(span[0]), float(span[1]))
			_stint_room = room
		else:
			wants_still = false
			_set_pose(Pose.NONE)
			return
	if kind == Pose.NONE:
		_end_stint()
		_set_pose(Pose.NONE)
		return
	stint_left -= delta
	wants_still = true
	_set_pose(kind)
	match kind:
		Pose.BOXES: _boxes()
		Pose.WAIT: _tap()
	if stint_left <= 0.0:
		_end_stint()


## Which pose a stint would strike now: an adventure waiting beats the job.
func _stint_kind(room: bool) -> Pose:
	if _level >= BIG and adventure_waiting():
		return Pose.WAIT
	if _level < EVERYTHING or not room:
		return Pose.NONE
	if gs.packs_on and gs.background_packing() >= 0.0:
		return Pose.BOXES
	if gs.automation.task == "machine" and gs.knows_job("machine"):
		return Pose.MACHINE
	return Pose.NONE


## Whether your pet has anything to act out on your windows yet: adventures (after the tutorial)
## or a job. Until then the setting stays out of sight.
static func has_something(state: Node) -> bool:
	return not state.tutorial_active() or not state.automation.taught.is_empty()


## A trip you sent is back (a postcard) or stopped at a question: it's waiting for you.
func adventure_waiting() -> bool:
	for run in gs.runs:
		if not run.auto and run.status != RunState.Status.WALKING:
			return true
	return false


func _boxes() -> void:
	var p: float = gs.background_packing()
	if p < float(cfg("reach_until", 0.3)):
		phase = Phase.REACH
	elif p < float(cfg("shake_from", 0.55)):
		phase = Phase.HOLD
	else:
		phase = Phase.SHAKE
		if fmod(time, 0.5) < _delta:
			squash = 0.25


func _tap() -> void:
	var every := float(cfg("tap_every", 0.4))
	if fmod(time, every) < _delta:  # the foot comes down on every beat
		squash = 0.2
		dust = 1.0


func _set_pose(p: Pose) -> void:
	pose = p


func _end_stint() -> void:
	if stint_left > 0.0 or (wants_still and _hold_left <= 0.0):
		just_ended = true
	stint_left = 0.0
	wants_still = false
	if pose == Pose.HOLD:
		held = null


func _follow_crank(delta: float) -> void:
	var fill := float(gs.automation.get("fill", 0.0))
	if fill < crank - 0.5:
		crank -= 1.0  # it went round: a capsule came out
	crank = move_toward(crank, fill, delta * 0.5)


## GameState opened a pack out of sight (opened_in_background).
func opened(pet: Pet) -> void:
	if pet == null or _level <= OFF:
		return
	if gs.is_good_pull(pet):
		show_off(pet)
		if pose == Pose.BOXES:
			puff = 1.0
		return
	if pose == Pose.BOXES:
		puff = 1.0
		squash = 0.6
		held = pet
		hop = 0.001


## Holds this pet up over its head (the good pull), once it's standing.
func show_off(pet: Pet) -> void:
	if _level <= OFF or pet == null:
		return
	if _pulls.size() < QUEUE:
		_pulls.append({ "pet": pet, "age": 0.0 })


## Your pet's own little machine gave a capsule (pet_cranked).
func cranked(_result: Dictionary) -> void:
	if pose == Pose.MACHINE:
		bounce = 1.0
		squash = 0.25


## Seconds the good pull has left over its head (0 when it isn't holding one).
func hold_left() -> float:
	return maxf(0.0, _hold_left) if pose == Pose.HOLD else 0.0
