class_name DesktopPet
extends Node2D
## The pet out on the desktop. Lives inside the transparent overlay window and walks
## along the top edges of other windows (and the bottom of the screen).
## Quiet paws (QuietPaws, PawsView): now and then it stands still on an edge and acts out its job
## with poses only (Settings.paws picks how much), holds up a good pull, or taps its foot facing
## the corner panel while an adventure waits.
## For testing, `stage` can be a Control in the game window instead of the overlay (DeskStage):
## its size, mouse and clicks are used, and nothing goes onto the real desktop.

const WALK_SPEED := 60.0
const GRAVITY := 1400.0
const RIDE_SNAP := 64.0  # how far a window may move between polls and still carry the pet
const POLL_INTERVAL := 0.1

enum State { IDLE, WALK, FALL, DRAG }

# a polygon outside the window: everything clicks through (packed arrays can't be const)
static var NO_CLICKS := PackedVector2Array([Vector2(-3, -3), Vector2(-2, -3), Vector2(-2, -2)])
const HEART := [Vector2(-2, 0), Vector2(1, 0), Vector2(-3, 1), Vector2(-2, 1), Vector2(-1, 1),
	Vector2(0, 1), Vector2(1, 1), Vector2(2, 1), Vector2(-2, 2), Vector2(-1, 2),
	Vector2(0, 2), Vector2(1, 2), Vector2(-1, 3), Vector2(0, 3)]

var source: WindowSource
var overlay: Window
var home: Window  # the corner panel / full game window (quiet paws faces it while an adventure waits)
var stage: Control  # set instead of `overlay` to run inside a Control (tests, DeskStage)
var pixel := 4  # screen pixels per art pixel; set before adding to the tree
var paws: QuietPaws  # made in _ready if not set before
var paws_level := -1  # quiet paws: -1 follows Settings.paws

var _sprite := PetView.new()
var _state := State.FALL
var _vel := Vector2.ZERO
var _dir := 1
var _timer := 0.0
var _platforms: Array[Vector3] = []  # (x0, x1, y) in overlay pixels
var _poll := 0.0
var _hidden := false
var _press_pos := Vector2.ZERO
var _drag_offset := Vector2.ZERO
var _moved := false
var _hearts: Array[Vector3] = []  # (x, y, age)
var _click_shape := PackedVector2Array([Vector2.ONE])  # last shape sent; starts as "unset"
var _back: PawsView  # the pile or the machine, behind the pet
var _front: PawsView  # the pack in its paws, the puff, sparkles, dust
var _held := PetView.new()  # a good pull over its head, or a new pet hopping off
var _side := 1  # which side of the pet its props stand on
var _working := false
var _home_rect := Rect2()  # where the corner panel is (read with the other windows, not every frame)
var _snap := Vector2.ZERO  # this frame's nudge onto whole screen pixels
var _props_shown := false  # the views drew something last frame (so they redraw once more to clear)
var _settings: Node  # the Settings autoload (null in the headless tests)


func _ready() -> void:
	if paws == null:
		paws = QuietPaws.new()
	_back = PawsView.new(paws, false)
	_front = PawsView.new(paws, true)
	for v in [_back, _front]:
		v.pixel = pixel
	_sprite.pixel = pixel
	_held.pixel = maxi(2, roundi(pixel * 2.0 / 3.0))
	_held.visible = false
	add_child(_back)
	add_child(_sprite)
	add_child(_held)
	add_child(_front)
	if is_inside_tree():
		_settings = get_node_or_null("/root/Settings")
	_refresh_world()


func set_pet(pet: Pet) -> void:
	_sprite.pet = pet


## Pet size on screen.
func _size() -> Vector2:
	return PetView.size_for(pixel)


## The space it walks around in: the overlay, or the stage.
func _area() -> Vector2:
	return stage.size if stage else Vector2(overlay.size)


func _mouse() -> Vector2:
	return stage.get_local_mouse_position() if stage else overlay.get_mouse_position()


## Drops the pet in at a point (overlay pixels), e.g. under the mouse.
func drop_at(point: Vector2) -> void:
	position = point
	_vel = Vector2(0, -250)
	_state = State.FALL


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_INTERVAL
		_refresh_world()

	match _state:
		State.IDLE: _idle(delta)
		State.WALK: _walk(delta)
		State.FALL: _fall(delta)
		State.DRAG: position = _mouse() + _drag_offset

	_snap = position.round() - position  # draw on whole pixels, no shimmer while walking
	_sprite.position = _snap
	_back.position = _snap
	_front.position = _snap
	_step_paws(delta)
	_sprite.walking = _state == State.WALK
	_sprite.facing = _dir
	if not _hearts.is_empty():
		for i in range(_hearts.size() - 1, -1, -1):
			_hearts[i].z += delta
			if _hearts[i].z > 1.2:
				_hearts.remove_at(i)
		queue_redraw()  # also clears the last heart once it's gone
	_update_click_area()


func _idle(delta: float) -> void:
	if not _stay_supported():
		return
	if paws.just_ended:  # done at work for now: off for a walk
		paws.just_ended = false
		_state = State.WALK
		_dir = [-1, 1].pick_random()
		_timer = randf_range(2.0, 7.0)
		return
	if paws.wants_still:
		return  # at work (or holding up a good pull): the walk waits
	_timer -= delta
	if _timer <= 0.0:
		_state = State.WALK
		_dir = [-1, 1].pick_random()
		_timer = randf_range(2.0, 7.0)


func _walk(delta: float) -> void:
	var seg = _support()
	if seg == null:
		_start_fall()
		return
	if paws.pose == QuietPaws.Pose.HOLD:  # a good pull: stop right here and show it
		_state = State.IDLE
		_timer = randf_range(1.0, 3.0)
		return
	position.y = seg.z
	position.x += _dir * WALK_SPEED * (pixel / 4.0) * delta
	var half := _size().x * 0.3
	if position.x < seg.x + half or position.x > seg.y - half:
		if seg.z < _area().y - 2 and randf() < 0.4:
			position.x += _dir * half * 2.0  # hop off the edge
			_start_fall()
			return
		position.x = clampf(position.x, seg.x + half, seg.y - half)
		_dir = -_dir
	_timer -= delta
	if _timer <= 0.0:
		_state = State.IDLE
		_timer = randf_range(3.0, 10.0)


func _fall(delta: float) -> void:
	var prev_y := position.y
	_vel.y += GRAVITY * delta
	position += _vel * delta
	_vel.x = move_toward(_vel.x, 0.0, 600.0 * delta)
	position.x = clampf(position.x, 20.0, _area().x - 20.0)
	# land on the first platform the feet crossed this frame
	var best = null
	for p in _platforms:
		if position.x >= p.x and position.x <= p.y and prev_y <= p.z and position.y >= p.z:
			if best == null or p.z < best.z:
				best = p
	if best != null and _vel.y > 0.0:
		position.y = best.z
		_sprite.squash = clampf(_vel.y / 900.0, 0.2, 1.0)
		_vel = Vector2.ZERO
		_state = State.IDLE
		_timer = randf_range(1.0, 3.0)


func _start_fall() -> void:
	_state = State.FALL
	_vel = Vector2(_dir * 40.0, 0.0)


## Keeps the pet standing on (and riding) its platform; starts a fall if it is gone.
func _stay_supported() -> bool:
	var seg = _support()
	if seg == null:
		_start_fall()
		return false
	position.y = seg.z
	return true


func _support():
	var best = null
	for p in _platforms:
		if position.x >= p.x and position.x <= p.y and absf(p.z - position.y) <= RIDE_SNAP:
			if best == null or absf(p.z - position.y) < absf(best.z - position.y):
				best = p
	return best


func _refresh_world() -> void:
	var fullscreen := source.is_fullscreen_active(overlay)
	if fullscreen != _hidden:
		_hidden = fullscreen
		visible = not _hidden
	var rects := source.get_windows(overlay)
	_home_rect = source.home_rect(home, overlay)
	var w := _area().x
	var h := _area().y
	var min_y := _size().y  # the pet has to fit above the edge
	_platforms.clear()
	for i in rects.size():
		var r := rects[i]
		var y := r.position.y
		if y < min_y or y >= h:
			continue
		var spans: Array[Vector2] = [Vector2(maxf(r.position.x, 0.0), minf(r.end.x, w))]
		# cut out the parts of this edge hidden behind windows in front of it
		for j in i:
			var f := rects[j]
			if f.position.y <= y and f.end.y > y:
				spans = _subtract(spans, f.position.x, f.end.x)
		for s in spans:
			if s.y - s.x >= _size().x * 0.8:
				_platforms.append(Vector3(s.x, s.y, y))
	_platforms.append(Vector3(0.0, w, h))  # the floor


func _subtract(spans: Array[Vector2], a: float, b: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s in spans:
		if b <= s.x or a >= s.y:
			out.append(s)
			continue
		if a > s.x:
			out.append(Vector2(s.x, a))
		if b < s.y:
			out.append(Vector2(b, s.y))
	return out


func _body_rect() -> Rect2:
	var s := _size()
	return Rect2(position - Vector2(s.x / 2.0, s.y + pixel * 2), Vector2(s.x, s.y + pixel * 2))


## Only the pet catches clicks; everything else on the overlay clicks through.
## Setting the shape is not free (the OS reshapes the window), so only do it when it changes.
func _update_click_area() -> void:
	if stage:
		return  # inside the game window: it gets its clicks like everything else there
	var shape: PackedVector2Array
	if _state == State.DRAG:
		shape = PackedVector2Array()  # the whole overlay catches the drag
	elif _hidden or not visible:
		shape = NO_CLICKS
	else:
		var r := Rect2(_body_rect().grow(2).position.round(), _body_rect().grow(2).size.round())
		shape = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	if shape != _click_shape:
		_click_shape = shape
		overlay.mouse_passthrough_polygon = shape


func _input(event: InputEvent) -> void:
	if _hidden or not visible:
		return
	if stage:
		if not stage.is_visible_in_tree():
			return
		event = stage.make_input_local(event)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _body_rect().has_point(event.position):
			_press_pos = event.position
			_drag_offset = position - event.position
			_moved = false
			_state = State.DRAG
			get_viewport().set_input_as_handled()
		elif not event.pressed and _state == State.DRAG:
			if not _moved:
				_pat()
			_vel = Vector2.ZERO
			_state = State.FALL
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _state == State.DRAG:
		if event.position.distance_to(_press_pos) > 6.0:
			_moved = true


# ---- quiet paws ----------------------------------------------------------------

## Moves quiet paws on a frame and poses the pet and its props.
func _step_paws(delta: float) -> void:
	var grounded := _state == State.IDLE or _state == State.WALK
	var seg = _support() if grounded else null
	# the side with more room (where the props go) must fit the biggest prop, as it's drawn
	var free: float = maxf(seg.y - position.x, position.x - seg.x) if seg != null else 0.0
	var room: bool = seg != null and free >= PawsView.widest() * pixel / 3.0
	paws.step(delta, grounded and seg != null, _state == State.IDLE, room, level())
	var working := paws.stint_left > 0.0
	if working and not _working and seg != null:
		_side = 1 if seg.y - position.x >= position.x - seg.x else -1  # the side with more room
	_working = working
	match paws.pose:
		QuietPaws.Pose.BOXES, QuietPaws.Pose.MACHINE:
			_dir = _side
		QuietPaws.Pose.WAIT:
			var at := _home_rect
			if at.has_area() and absf(at.get_center().x - position.x) > 2.0:
				_dir = 1 if at.get_center().x > position.x else -1
	if paws.squash > 0.0:
		_sprite.squash = maxf(_sprite.squash, paws.squash)
		paws.squash = 0.0
	# the pet in its paws: held up over its head, or hopping off
	var showing := paws.held != null and (paws.pose == QuietPaws.Pose.HOLD or paws.hop > 0.0)
	if _held.pet != paws.held:
		_held.pet = paws.held
	_held.visible = showing
	if showing:
		var k := pixel / 3.0
		if paws.pose == QuietPaws.Pose.HOLD:
			var bob := roundf(sin(paws.time * 4.0) * 2.0 * k)
			_held.position = _snap + Vector2(0, -_size().y + 4.0 * k + bob).round()
			_held.facing = _dir
			_held.modulate.a = 1.0
			_held.walking = false
		else:
			# out of the pack in its paws, over the pile and away
			var t := paws.hop
			_held.facing = _side
			_held.walking = true
			_held.position = _snap + Vector2(_side * (14.0 + t * 90.0) * k, -absf(sin(t * PI * 2.5)) * 22.0 * k).round()
			_held.modulate.a = 1.0 - t * t
	_back.side = _side
	_back.facing = _dir
	_front.side = _side
	_front.facing = _dir
	_front.held_at = _held.position - _snap  # the views sit at _snap too
	# the props only change while there's a pose or a puff; one more redraw clears the last frame
	var shown := paws.pose != QuietPaws.Pose.NONE or paws.puff > 0.0
	if shown or _props_shown:
		_back.queue_redraw()
		_front.queue_redraw()
	_props_shown = shown


## How much quiet paws shows: Settings.paws, unless a test set it. (The autoload is looked up once
## in _ready, so the headless tests, which have none, can load this.)
func level() -> int:
	if paws_level >= 0:
		return paws_level
	return int(_settings.paws) if _settings else QuietPaws.EVERYTHING


## Which way it's facing (1 right, -1 left), for tests.
func facing() -> int:
	return _dir


func _pat() -> void:
	paws.gs.pat()
	_sprite.squash = 0.6
	_hearts.append(Vector3(randf_range(-10, 10), 0, 0))


func _draw() -> void:
	# little pixel hearts floating up after a pat
	for heart in _hearts:
		var a := 1.0 - heart.z / 1.2
		var base := Vector2(heart.x, -_size().y - 8 - heart.z * 40.0)
		var c := Color("ff79c6", a)
		for p in HEART:
			draw_rect(Rect2(base + p * 3, Vector2(3, 3)), c)
