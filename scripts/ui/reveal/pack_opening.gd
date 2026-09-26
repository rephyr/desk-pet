class_name PackOpening
extends Control
## Opening one box, as a little ritual:
##   1. a card pack lands      2. rip the strip off the top
##   3. the light climbs the rarity tiers one by one, stacking effects, and stops at the pet's
##   4. drag the pet up out of the pack, as slow or fast as you like
##   5. very rare pulls come out behind mist you drag around to peek, then flick away
##   6. a celebration sized to the rarity, the finish as a second surprise, then the result
## Space or double-click skips to the result. Timings and effects come from data/reveal.json,
## and everything runs at the player's reveal speed setting.

signal open_again(box_id: String)
signal closed

enum Stage { IDLE, LANDING, RIP, CLIMB, PEEK, PULL, RITUAL, CELEBRATE, RESULT }

const PET_PIXEL := 6
const RIP_DRAG := 220.0  # drag (px) across the top to rip it fully
const PULL_DRAG := 170.0  # upward drag (px) from peeking to fully out
const FLICK_SPEED := 900.0  # px/s: a quick flick pops the pet out / throws the mist away
const MIST_THROW := 170.0  # dragging the mist this far off the pet also clears it
const PULL_HIDDEN := -0.45  # pull value where the pet is fully inside the pack
const DROP_HEIGHT := 260.0
const DIM_ALPHA := 0.55

var _stage := Stage.IDLE
var _pet: Pet
var _box_id := ""
var _ritual := false  # this pull is rare enough for the mist
var _mist_on := false  # the mist is still in front of the pet
var _run := 0  # bumped on every new opening and skip, so older async steps stop
var _cfg: Dictionary = Catalog.shared().reveal
## Debug: plays the drags by itself (for testing and screenshots), see DevArgs --autoplay.
var autoplay := DevArgs.has("autoplay")

var _dim := ColorRect.new()
var _scene := Node2D.new()  # everything that shakes
var _effects := RevealEffects.new()
var _pack := CardPack.new()
var _pet_clip := Control.new()  # hides the part of the pet still inside the pack
var _pet_view := PetView.new()
var _blocker := RevealBlocker.new()
var _banner := UiTheme.label("", UiTheme.TEXT, 30)
var _hint := UiTheme.label("", UiTheme.MUTED)
var _result := RevealResult.new()
var _tweens: Array[Tween] = []

var _tear := 0.0
var _pull := PULL_HIDDEN
var _blocker_offset := Vector2.ZERO
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_value := 0.0  # tear or pull value when the drag started
var _drag_offset_start := Vector2.ZERO
var _velocity := Vector2.ZERO
var _last_mouse := Vector2.ZERO
var _shake := 0.0


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true

	_dim.color = Color(0, 0, 0, 0)
	_dim.set_anchors_preset(PRESET_FULL_RECT)
	_dim.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_dim)
	add_child(_scene)

	# draw order: back of the opening, light, pet, mist, front of the pack
	_scene.add_child(_pack.back)
	_effects.position = CardPack.mouth()
	_scene.add_child(_effects)
	_pet_clip.clip_contents = true
	_pet_clip.mouse_filter = MOUSE_FILTER_IGNORE
	_pet_clip.position = Vector2(-160, CardPack.rim_y() - 700)
	_pet_clip.size = Vector2(320, 700)  # bottom edge = the tear line
	_scene.add_child(_pet_clip)
	_pet_view.pixel = PET_PIXEL
	_pet_clip.add_child(_pet_view)
	_scene.add_child(_blocker)
	_scene.add_child(_pack)

	_banner.set_anchors_preset(PRESET_TOP_WIDE)
	_banner.position.y = 18
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_banner)
	_hint.set_anchors_preset(PRESET_BOTTOM_WIDE)
	_hint.position.y = -30
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint)
	_result.set_anchors_preset(PRESET_TOP_WIDE)
	_result.position.y = 10
	_result.open_again.connect(func(): open_again.emit(_box_id))
	_result.done.connect(_close)
	add_child(_result)

	resized.connect(_layout)
	_reset()


## Starts the ritual for a pet that was just pulled from `box_id`.
func play(pet: Pet, box_id: String) -> void:
	_reset()
	_pet = pet
	_box_id = box_id
	_pet_view.pet = pet
	var chance := Catalog.shared().tier_chance(box_id, pet.rarity)
	_ritual = not Settings.skip_ritual and chance <= float(_cfg.ritual_max_chance)
	_mist_on = _ritual
	_effects.set_speed(Settings.reveal_speed)
	_scene.visible = true
	if Settings.skip_single_reveal:
		skip()
		return
	_land(_run)


## Jumps straight to the result.
func skip() -> void:
	if _stage == Stage.IDLE or _stage == Stage.RESULT:
		return
	_run += 1
	_kill_tweens()
	var catalog := Catalog.shared()
	_pack.position = Vector2.ZERO
	_set_tear(1.0)
	_pack.strip_gone = 1.0
	var rank := catalog.rank(_pet.rarity)
	for r in rank + 1:
		_effects.add_layers(catalog.reveal_tier(catalog.tier_at(r).id).adds, 0.01)
	_effects.color = catalog.tier_color(_pet.rarity)
	_dim.color.a = DIM_ALPHA if _effects.has_layer("dim") else 0.0
	_mist_on = false
	_set_pull(1.0)
	_show_result()


# ---- the steps ---------------------------------------------------------------

func _land(run: int) -> void:
	_stage = Stage.LANDING
	_say("")
	_pack.position = Vector2(0, -DROP_HEIGHT)
	var t := _tween()
	t.tween_property(_pack, "position:y", 0.0, float(_cfg.land_time)).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	await t.finished
	if run != _run:
		return
	_stage = Stage.RIP
	_say("rip the top off ✦")
	if autoplay:
		await _wait(0.6)
		if run == _run:
			_set_tear(0.35)
			await _wait(0.4)
			if run == _run:
				_rip_off(run)


func _rip_off(run: int) -> void:
	_stage = Stage.CLIMB
	_say("")
	var t := _tween()
	t.tween_method(_set_tear, _tear, 1.0, 0.08)
	t.tween_property(_pack, "strip_gone", 1.0, 0.45).set_ease(Tween.EASE_IN)
	var catalog := Catalog.shared()
	_effects.color = catalog.tier_color(catalog.tier_at(0).id)
	_effects.add_layers(catalog.reveal_tier(catalog.tier_at(0).id).adds)
	_effects.burst(8)
	_climb(run)


## Steps the light up one tier at a time until it reaches the pet's rarity.
func _climb(run: int) -> void:
	var catalog := Catalog.shared()
	var rank := catalog.rank(_pet.rarity)
	for r in range(1, rank + 1):
		var tier := catalog.tier_at(r)
		var step := catalog.reveal_tier(tier.id)
		await _wait(float(step.get("pause", 0.4)))
		if run != _run:
			return
		_step_to(tier.id, r)
	await _wait(0.35)
	if run != _run:
		return
	_peek(run)


func _step_to(tier_id: String, rank: int) -> void:
	var step := Catalog.shared().reveal_tier(tier_id)
	var t := _tween()
	t.tween_property(_effects, "color", Catalog.shared().tier_color(tier_id), 0.15)
	_effects.add_layers(step.get("adds", []))
	_effects.burst(6 + rank * 6)
	if _effects.has_layer("dim"):
		_tween().tween_property(_dim, "color:a", DIM_ALPHA, 0.4)
	if _effects.has_layer("screen_shake"):
		_shake = maxf(_shake, 6.0)
	# the pack jumps a little on every step
	var hop := _tween()
	hop.tween_property(_pack, "position:y", -6.0 - rank * 2.0, 0.08)
	hop.tween_property(_pack, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_BOUNCE)


func _peek(run: int) -> void:
	_stage = Stage.PEEK
	var t := _tween()
	t.tween_method(_set_pull, _pull, 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	if run != _run:
		return
	_stage = Stage.PULL
	_say("pull your pet out ✦")
	if autoplay:
		var t2 := _tween()
		t2.tween_method(_set_pull, 0.0, 0.5, 1.0)
		await t2.finished
		if run == _run:
			_pop_pet(run)


func _pop_pet(run: int) -> void:
	_stage = Stage.CELEBRATE
	_say("")
	var t := _tween()
	t.tween_method(_set_pull, _pull, 1.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished
	if run != _run:
		return
	if _ritual:
		_stage = Stage.RITUAL
		_say("move the mist to peek · flick it away")
		if autoplay:
			var t2 := _tween()
			t2.tween_method(func(o): _blocker_offset = o; _set_pull(_pull), Vector2.ZERO, Vector2(70, -10), 1.2)
			await t2.finished
			if run == _run:
				_velocity = Vector2(1, -1)
				_clear_mist(run)
		return
	_celebrate(run)


func _clear_mist(run: int) -> void:
	_stage = Stage.CELEBRATE
	_say("")
	var t := _tween().set_parallel()
	t.tween_property(_blocker, "position", _blocker.position + _velocity.normalized() * 400.0 + Vector2(0, -150), 0.4)
	t.tween_property(_blocker, "modulate:a", 0.0, 0.4)
	await t.finished
	if run != _run:
		return
	_mist_on = false
	_blocker.visible = false
	_celebrate(run)


## The party: bigger the rarer, then the finish as a second surprise.
func _celebrate(run: int) -> void:
	var catalog := Catalog.shared()
	var step := catalog.reveal_tier(_pet.rarity)
	_stage = Stage.CELEBRATE
	_effects.burst(int(step.get("burst", 10)))
	_shake = maxf(_shake, float(step.get("shake", 0)))
	_pet_view.squash = 0.8
	if step.get("banner", false):
		_banner.text = catalog.tier_at(catalog.rank(_pet.rarity)).name.to_upper() + "!"
		_banner.add_theme_color_override("font_color", catalog.tier_color(_pet.rarity))
		_pop_in(_banner)
	await _wait(float(step.get("hold", 0.4)))
	if run != _run:
		return

	var f := catalog.finish(_pet.finish)
	if f.id != "normal":
		var color := catalog.tier_color(f.rarity)
		_banner.text = "…and it's %s!" % f.name.to_upper()
		_banner.add_theme_color_override("font_color", color)
		_pop_in(_banner)
		var flash := _tween()
		flash.tween_property(_pet_view, "modulate", Color(2.5, 2.5, 2.5), 0.12)
		flash.tween_property(_pet_view, "modulate", Color.WHITE, 0.4)
		_effects.color = color  # the light takes on the finish's colour
		_effects.burst(40 + catalog.rank(f.rarity) * 20)
		await _wait(float(_cfg.finish_flash_time))
		if run != _run:
			return
	_show_result()


func _show_result() -> void:
	_stage = Stage.RESULT
	_say("")
	_banner.visible = false
	_result.visible = true
	_result.show_pet(_pet, _box_id)


func _close() -> void:
	_reset()
	closed.emit()


func _reset() -> void:
	_run += 1
	_kill_tweens()
	_stage = Stage.IDLE
	_effects.clear()
	_dim.color.a = 0.0
	_set_tear(0.0)
	_pack.strip_gone = 0.0
	_pack.direction = 1.0
	_set_pull(PULL_HIDDEN)
	_blocker_offset = Vector2.ZERO
	_mist_on = false
	_blocker.visible = false
	_blocker.modulate.a = 1.0
	_banner.visible = false
	_result.visible = false
	_shake = 0.0
	_scene.visible = false
	_pet_view.modulate = Color.WHITE
	_say("open a box to see what's inside ✦")


# ---- state setters --------------------------------------------------------

func _set_tear(value: float) -> void:
	_tear = value
	_pack.tear = value
	_effects.leak = value


## -0.45 hidden in the pack, 0 peeking out, 1 all the way out.
func _set_pull(value: float) -> void:
	_pull = value
	var rim_y := CardPack.rim_y()
	var pet_h := PetView.size_for(PET_PIXEL).y
	var hidden := rim_y + pet_h + 8.0
	var peek := rim_y + pet_h * 0.72
	var out := rim_y - 18.0
	var feet_y := lerpf(peek, hidden, -value / -PULL_HIDDEN) if value < 0.0 else lerpf(peek, out, value)
	_pet_view.position = Vector2(_pet_clip.size.x / 2.0, feet_y - _pet_clip.position.y)
	# while it's still coming out, the mist rides along; after that the player moves it
	_blocker.visible = _mist_on and value >= 0.0
	if _mist_on:
		_blocker.position = Vector2(0, feet_y) + _blocker_offset


# ---- input ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.double_click:
			skip()
		elif event.pressed:
			_start_drag(event.position)
		elif _dragging:
			_end_drag()
		accept_event()
	elif event is InputEventMouseMotion:
		_velocity = _velocity.lerp((event.position - _last_mouse) / maxf(get_process_delta_time(), 0.001), 0.5)
		_last_mouse = event.position
		if _dragging:
			_drag_to(event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and is_visible_in_tree():
		skip()


func _start_drag(pos: Vector2) -> void:
	if not (_stage in [Stage.RIP, Stage.PULL, Stage.RITUAL]):
		return
	_dragging = true
	_drag_from = pos
	_last_mouse = pos
	_velocity = Vector2.ZERO
	_drag_value = _tear if _stage == Stage.RIP else _pull
	_drag_offset_start = _blocker_offset


func _drag_to(pos: Vector2) -> void:
	var up := _drag_from.y - pos.y
	match _stage:
		Stage.RIP:
			# rip along the top in either direction (or upwards); the first sideways pull decides
			# which end peels up
			var sideways := pos.x - _drag_from.x
			if _tear == 0.0 and absf(sideways) > 4.0:
				_pack.direction = sideways
			var rip := maxf(absf(sideways), up)
			_set_tear(clampf(_drag_value + rip / RIP_DRAG, 0.0, 1.0))
			if _tear >= float(_cfg.rip_pop_at):
				_dragging = false
				_rip_off(_run)
		Stage.PULL:
			_set_pull(clampf(_drag_value + up / PULL_DRAG, 0.0, 1.0))
			if _pull >= float(_cfg.pull_pop_at):
				_dragging = false
				_pop_pet(_run)
		Stage.RITUAL:
			_blocker_offset = _drag_offset_start + (pos - _drag_from)
			_set_pull(_pull)
			if _blocker_offset.length() > MIST_THROW:
				_dragging = false
				_clear_mist(_run)


func _end_drag() -> void:
	_dragging = false
	var flick := _velocity.length() > FLICK_SPEED
	match _stage:
		Stage.RIP:
			pass  # a half-ripped strip stays half ripped
		Stage.PULL:
			if flick and _velocity.y < 0.0:
				_pop_pet(_run)
		Stage.RITUAL:
			if flick:
				_clear_mist(_run)


# ---- helpers --------------------------------------------------------------

func _process(delta: float) -> void:
	var jitter := Vector2.ZERO
	if _shake > 0.05:
		jitter = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake = move_toward(_shake, 0.0, delta * 20.0 * Settings.reveal_speed)
	_scene.position = _base_position() + jitter
	# the pack rattles while something big is waiting inside
	var rattling := _effects.has_layer("pack_shake") and _stage in [Stage.CLIMB, Stage.PEEK, Stage.PULL]
	_pack.rotation = sin(Time.get_ticks_msec() * 0.05) * 0.02 if rattling else 0.0
	_pack.back.position = _pack.position
	_pack.back.rotation = _pack.rotation


func _layout() -> void:
	_scene.position = _base_position()


func _base_position() -> Vector2:
	return Vector2(size.x / 2.0, size.y * 0.78)


func _say(text: String) -> void:
	_hint.text = text
	_hint.visible = text != ""


func _pop_in(label: Label) -> void:
	label.visible = true
	label.pivot_offset = label.size / 2.0
	label.scale = Vector2(0.3, 0.3)
	_tween().tween_property(label, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A tween that runs at the reveal speed setting and dies on skip/reset.
func _tween() -> Tween:
	var t := create_tween()
	t.set_speed_scale(Settings.reveal_speed)
	_tweens.append(t)
	return t


func _wait(seconds: float) -> Signal:
	return get_tree().create_timer(seconds / Settings.reveal_speed).timeout


func _kill_tweens() -> void:
	for t in _tweens:
		if t.is_valid():
			t.kill()
	_tweens.clear()
