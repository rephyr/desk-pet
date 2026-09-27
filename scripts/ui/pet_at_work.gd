class_name PetAtWork
extends Control
## The little scene in the corner panel while you work: your active pet opening packs for you.
## It walks to the pile, brings a pack back, sits and shakes it, and pop! An ordinary new pet
## hops off; a good one (see GameState.is_good_pull) is held up for you to see, with sparkles,
## until you tap it. It only opens packs while this is on screen and it can afford one without
## going under the reserve (GameState.can_auto_open). Tapping it otherwise pats it.

enum Job { SIT, FETCH, BRING, SHAKE, SHOW, HOP }

const PIXEL := 3
const WALK_SPEED := 45.0  # px per second
const SHAKE_TIME := 2.6
const HOP_TIME := 1.1
const REST_TIME := 3.0  # a little break between packs
const FOIL := Color("6b4fa0")
const FOIL_LIGHT := Color("8e6fd0")

var view := PetView.new()  # your pet
var _held := PetView.new()  # the pet that just came out of a pack
var _say := UiTheme.label("", UiTheme.PINK, UiTheme.SMALL)
var _job := Job.SIT
var _timer := 0.0
var _rest := REST_TIME
var _x := -1.0
var _pack_in_paws := false
var _puff := 0.0
var _time := 0.0
var _front := Node2D.new()  # drawn over the pets: the pack in its paws, the pop, the sparkles
var _saving := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)  # why it isn't opening packs


func _init() -> void:
	custom_minimum_size = Vector2(0, 104)
	mouse_filter = MOUSE_FILTER_STOP
	view.pixel = PIXEL
	add_child(view)
	_held.pixel = 2
	_held.visible = false
	add_child(_held)
	_front.draw.connect(_draw_front)
	add_child(_front)
	_saving.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_saving)
	_say.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_say.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_say.size = Vector2(200, 20)
	add_child(_say)
	GameState.collection.active_changed.connect(func(p): view.pet = p)


func _ready() -> void:
	view.pet = GameState.collection.active()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or view.pet == null:
		return
	_time += delta
	if _x < 0.0:
		if size.x <= 0.0:
			return  # not laid out yet
		_x = _home_x()
	match _job:
		Job.SIT:
			_walk_to(_home_x(), delta)  # back to its spot if it isn't there
			if not GameState.pinned.is_empty():
				_show(GameState.collection.get_pet(GameState.pinned[0]))
			else:
				_rest -= delta
				if _rest <= 0.0 and GameState.can_auto_open():
					_job = Job.FETCH
		Job.FETCH:
			if _walk_to(_pile_x(), delta):
				_pack_in_paws = true
				_job = Job.BRING
		Job.BRING:
			if _walk_to(_home_x(), delta):
				view.facing = 1
				_timer = SHAKE_TIME
				_job = Job.SHAKE
		Job.SHAKE:
			_timer -= delta
			if fmod(_time, 0.5) < delta:
				view.squash = 0.25
			if _timer <= 0.0:
				_pop()
		Job.HOP:
			_timer -= delta
			if _timer <= 0.0:
				_held.visible = false
				_say.text = ""
				_rest = REST_TIME
				_job = Job.SIT
	_puff = move_toward(_puff, 0.0, delta * 2.0)
	_refresh_saving()
	_x = clampf(_x, 14.0, maxf(14.0, size.x - 14.0))  # the panel can change size (moving screens, startup)
	_place()
	queue_redraw()
	_front.queue_redraw()


## A small note by the pile when your pet isn't opening packs, so it never looks stuck.
func _refresh_saving() -> void:
	var text := ""
	if not GameState.feature_on("packs"):
		text = ""
	elif not GameState.packs_on:
		text = "packs are off"
	elif not GameState.can_auto_open() and _job == Job.SIT:
		text = "saving up · ◆%d / ◆%d" % [GameState.coins, GameState.auto_open_needs()]
	_saving.text = text
	_saving.size = Vector2(size.x * 0.5, 16.0)
	_saving.position = Vector2(10.0, 6.0)


func _home_x() -> float:
	return size.x * 0.42


func _pile_x() -> float:
	return size.x - 30.0


func _floor() -> float:
	return size.y - 6.0


func _walk_to(x: float, delta: float) -> bool:
	var d := x - _x
	if absf(d) < 1.0:
		_x = x
		view.walking = false
		return true
	view.facing = 1 if d > 0.0 else -1
	view.walking = true
	_x += clampf(d, -WALK_SPEED * delta, WALK_SPEED * delta)
	return false


## The pack opens: a new pet! Good ones are shown off, the rest hop away to the collection.
func _pop() -> void:
	_pack_in_paws = false
	_puff = 1.0
	view.squash = 0.6
	var pet := GameState.auto_open_pack()
	if pet == null:
		_rest = REST_TIME
		_job = Job.SIT
		return
	if GameState.is_good_pull(pet):
		_show(pet)
		return
	_held.pet = pet
	_held.visible = true
	_say.text = "a %s!" % pet.display_name(Catalog.shared())
	_timer = HOP_TIME
	_job = Job.HOP


func _show(pet: Pet) -> void:
	if pet == null:
		GameState.dismiss_pinned()
		return
	_held.pet = pet
	_held.visible = true
	_say.text = "look!! a %s!" % pet.display_name(Catalog.shared())
	_job = Job.SHOW


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _job == Job.SHOW:
		# seen it! it goes to the collection like the others
		GameState.dismiss_pinned()
		_held.visible = false
		_say.text = ""
		_rest = REST_TIME
		_job = Job.SIT
	else:
		GameState.pat()
		view.squash = 0.6
	accept_event()


func _place() -> void:
	var pet_h := PetView.size_for(PIXEL).y
	view.position = Vector2(roundf(_x), _floor())
	match _job:
		Job.SHOW:
			var bob := roundf(sin(_time * 4.0) * 2.0)
			_held.position = Vector2(roundf(_x), _floor() - pet_h + 4.0 + bob)
			_say.position = Vector2(clampf(_x - _say.size.x / 2.0, 0.0, maxf(0.0, size.x - _say.size.x)), 0)
		Job.HOP:
			var t := 1.0 - _timer / HOP_TIME
			_held.facing = -1
			_held.position = Vector2(roundf(lerpf(_x - 24.0, -20.0, t)), _floor() - roundf(absf(sin(t * PI * 3.0)) * 14.0))
			_say.position = Vector2(clampf(_x - _say.size.x / 2.0, 0.0, maxf(0.0, size.x - _say.size.x)), 0)


func _draw() -> void:
	# a soft floor, and the pile of packs your pet fetches from
	draw_line(Vector2(8, _floor() + 1), Vector2(size.x - 8, _floor() + 1), Color(UiTheme.PINK, 0.18), 2.0)
	var stocked := GameState.can_auto_open()
	if not GameState.feature_on("packs"):
		return  # your pet hasn't got its packs corner yet
	for i in 3:
		_draw_pack(Vector2(_pile_x() + (i - 1) * 7.0, _floor() - 8.0 - i * 3.0), (i - 1) * 0.15, self, not stocked)



## In front of the pets: the pack in its paws, the pop, the sparkles round a good pull.
func _draw_front() -> void:
	if _pack_in_paws:
		var wiggle := sin(_time * 30.0) * 0.25 if _job == Job.SHAKE else 0.0
		_draw_pack(Vector2(_x + view.facing * 10.0, _floor() - 14.0), wiggle, _front)
	if _puff > 0.0:
		for i in 6:
			var a := TAU * i / 6.0
			var r := (1.0 - _puff) * 26.0 + 6.0
			_front.draw_circle(Vector2(_x, _floor() - 22.0) + Vector2(cos(a), sin(a)) * r, 3.0 * _puff, Color(UiTheme.LILAC, _puff))
	if _job == Job.SHOW:
		# sparkles around the good pull
		for i in 5:
			var a := TAU * i / 5.0 + _time * 1.5
			var at := _held.position + Vector2(cos(a) * 26.0, -18.0 + sin(a) * 16.0)
			var twinkle := 2.0 + 2.0 * absf(sin(_time * 5.0 + i))
			_front.draw_line(at - Vector2(twinkle, 0), at + Vector2(twinkle, 0), Color("ffe08a"), 1.5)
			_front.draw_line(at - Vector2(0, twinkle), at + Vector2(0, twinkle), Color("ffe08a"), 1.5)


## A tiny card pack, like the big one you rip open yourself.
func _draw_pack(at: Vector2, tilt: float, on: CanvasItem, empty := false) -> void:
	on.draw_set_transform(at, tilt, Vector2.ONE)
	if empty:
		# a dotted outline where the packs will be once there are coins for them
		on.draw_rect(Rect2(-6, -8, 12, 16), Color(FOIL_LIGHT, 0.35), false, 1.0)
		on.draw_set_transform(Vector2.ZERO)
		return
	on.draw_rect(Rect2(-6, -8, 12, 16), FOIL)
	on.draw_rect(Rect2(-6, -8, 12, 3), FOIL_LIGHT)
	on.draw_rect(Rect2(-2, -1, 4, 3), UiTheme.PINK)
	on.draw_set_transform(Vector2.ZERO)
