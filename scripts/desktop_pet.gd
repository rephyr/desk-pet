class_name DesktopPet
extends Node2D
## The pet out on the desktop. Lives inside the transparent overlay window and walks
## along the top edges of other windows (and the bottom of the screen).

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
var pixel := 4  # screen pixels per art pixel; set before adding to the tree

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


func _ready() -> void:
	_sprite.pixel = pixel
	add_child(_sprite)
	_refresh_world()


func set_pet(pet: Pet) -> void:
	_sprite.pet = pet


## Pet size on screen.
func _size() -> Vector2:
	return PetView.size_for(pixel)


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
		State.DRAG: position = overlay.get_mouse_position() + _drag_offset

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
	position.y = seg.z
	position.x += _dir * WALK_SPEED * (pixel / 4.0) * delta
	var half := _size().x * 0.3
	if position.x < seg.x + half or position.x > seg.y - half:
		if seg.z < overlay.size.y - 2 and randf() < 0.4:
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
	position.x = clampf(position.x, 20.0, overlay.size.x - 20.0)
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
	var w := float(overlay.size.x)
	var h := float(overlay.size.y)
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
	if _hidden:
		return
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


func _pat() -> void:
	GameState.pat()
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
