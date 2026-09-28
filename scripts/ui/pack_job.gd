class_name PackJob
extends RefCounted
## Your pet opening your pile of boxes, as a little routine that both places it happens share: the
## corner panel (PetAtWork) and its room on the home screen (HomeTab). Sit a moment, walk to the
## pile, bring a pack back, shake it, and pop! An ordinary new pet hops off; a good one (see
## GameState.is_good_pull) is held up for a few seconds (tap to move on sooner). This only moves along the floor and keeps
## time; each place draws it its own way, at its own size. While neither is on screen, GameState
## opens packs in the background instead.

enum Job { SIT, FETCH, BRING, SHAKE, SHOW, HOP }

const SHAKE_TIME := 2.6
const HOP_TIME := 1.1
const SHOW_TIME := 3.0  # how long a good pull is held up before your pet carries on
const REST_TIME := 3.0  # a little break between packs

var job := Job.SIT
var x := -1.0  # where your pet is along the floor (px), -1 until the first step
var speed := 45.0  # px per second
var facing := 1
var walking := false
var pack_in_paws := false
var puff := 0.0  # 1 right after a pop, fading
var squash := 0.0  # a bounce for the view to take (then it sets this back to 0)
var held: Pet  # the pet that just came out: hopping off, or held up
var said := ""  # a short line over it ("a peach cat!")
var timer := 0.0
var time := 0.0
var _rest := REST_TIME


## One frame: `home_x` is where your pet sits, `pile_x` where the pile is.
func step(delta: float, home_x: float, pile_x: float) -> void:
	time += delta
	GameState.pack_job_seen()  # on screen: opening happens here, not in the background
	if x < 0.0:
		x = home_x
	match job:
		Job.SIT:
			_walk_to(home_x, delta)  # back to its spot if it isn't there
			if not GameState.pinned.is_empty():
				_show(GameState.collection.get_pet(GameState.pinned[0]))
			else:
				_rest -= delta * GameState.boost("automation")  # the automation speed boost shortens its breaks
				if _rest <= 0.0 and GameState.can_auto_open():
					job = Job.FETCH
		Job.FETCH:
			if _walk_to(pile_x, delta):
				pack_in_paws = true
				job = Job.BRING
		Job.BRING:
			if _walk_to(home_x, delta):
				facing = 1
				timer = SHAKE_TIME
				job = Job.SHAKE
		Job.SHAKE:
			timer -= delta
			if fmod(time, 0.5) < delta:
				squash = 0.25
			if timer <= 0.0:
				_pop()
		Job.SHOW:
			timer -= delta
			if timer <= 0.0:
				tap()  # seen it: on to the next one, no click needed
		Job.HOP:
			timer -= delta
			if timer <= 0.0:
				held = null
				said = ""
				_rest = REST_TIME
				job = Job.SIT
	puff = move_toward(puff, 0.0, delta * 2.0)


## How far the new pet has hopped away, 0 to 1.
func hop_progress() -> float:
	return 1.0 - timer / HOP_TIME


## You tapped your pet (or the good pull's moment is over). Returns true if that was "seen it!"
## for a good pull it was holding up (it goes to the collection like the others); otherwise it's
## just a pat, for the caller.
func tap() -> bool:
	if job != Job.SHOW:
		return false
	GameState.dismiss_pinned(held.uid if held else "")
	held = null
	said = ""
	_rest = REST_TIME
	job = Job.SIT
	return true


func _walk_to(to: float, delta: float) -> bool:
	var d := to - x
	if absf(d) < 1.0:
		x = to
		walking = false
		return true
	facing = 1 if d > 0.0 else -1
	walking = true
	x += clampf(d, -speed * delta, speed * delta)
	return false


## The pack opens: a new pet! Good ones are shown off, the rest hop away to the collection.
func _pop() -> void:
	pack_in_paws = false
	puff = 1.0
	squash = 0.6
	var pet := GameState.auto_open_pack()
	if pet == null:
		_rest = REST_TIME
		job = Job.SIT
		return
	if GameState.pinned.has(pet.uid):  # a good pull that's still yours (not sorted off)
		_show(pet)
		return
	held = pet
	said = "a %s!" % pet.display_name(Catalog.shared())
	timer = HOP_TIME
	job = Job.HOP


func _show(pet: Pet) -> void:
	if pet == null:
		GameState.dismiss_pinned()
		return
	held = pet
	said = "look!! a %s!" % pet.display_name(Catalog.shared())
	timer = SHOW_TIME
	job = Job.SHOW
