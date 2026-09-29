class_name HomeTab
extends Control
## The first thing you see in the full game: your active pet's room, a crayon drawing on the page.
## A window with the night outside, a rug, and your pet in the middle. Special things pets bring
## home from trips become furniture (the cushion it sits on, the basket, the little cart). What
## needs you is pinned to the wall as sticky notes (trips, boxes, parts, the map), each a shortcut.
## A card on the floor has its name, food and mood, feed and pat. It talks in the shared bubble.
## Boxes you bought sit in a pile by the wall; once your pet has its cushion it opens them right
## here while you watch (PackJob, the same routine as the corner panel): fetch one, shake it on the
## cushion, pop! Good pulls are held up for a few seconds.
## Around the room are spots it can rummage through (RummageSpot, data/rummage.json): they twinkle
## when something's in there, and tapping one sends your pet over to dig it out. Tap a few and it
## goes through them in turn.
## Presents (Gifts): while one's waiting your pet holds it wrapped in its paws (on the floor by its
## spot while it's busy, more stacked small beside it). Tap: a shake, a pop, the boxes fly to the
## pile; a toy capsule shows its prize card.

signal go(tab_name: String)  # a note was tapped: show that tab
signal open_box(box_id: String)

const FLOOR := 0.64  # where the floor starts, as a share of the height
const PILE_SHOWN := 9  # packs drawn on the pile at most (the badge counts the rest)
const PACK_W := 40
const DIG_WALK := 260.0  # px per second: it hurries over to rummage
const DIG_HOP := 0.35  # seconds to hop in (and out)
const DIG_TIME := 1.3  # seconds of rummaging
const FLOAT_TIME := 1.4
const GIFT_SHAKE := 0.4  # seconds a present shakes before it pops open
const GIFT_FLY := 0.6  # seconds a box from a present takes to fly to the pile
const GIFT_ZOOM := 3.0  # screen pixels per pixel of a present (2 for the small ones beside it)

var _pet := PetPortrait.new(6, true)
var _name := UiTheme.title("", 18)
var _food := UiTheme.bar(UiTheme.PINK, Care.line(Catalog.shared(), "food"))
var _mood := UiTheme.bar(UiTheme.LILAC, Care.line(Catalog.shared(), "mood"))
var _feed: Button
var _card := PanelContainer.new()
var _notes := GridContainer.new()
var _note_parts := {}  # name -> { panel, line, hint, accent }
var _finds := {}  # find id -> an invisible control over its drawing, for the tooltip
var _rng := RandomNumberGenerator.new()
var _dirty := true
var _doing := UiTheme.label("", UiTheme.MINT, UiTheme.SMALL)  # on the card: what your pet is up to
var _work := PackJob.new()
var _held := PetView.new()  # the pet that just came out of a pack
var _front := Node2D.new()  # over your pet: the pack in its paws, the pop, sparkles
var _paw_box := ""  # which kind of box it's carrying
var _said := ""
var _spots := {}  # rummage spot id -> RummageSpot
var _digs: Array[RummageSpot] = []  # spots you tapped, waiting for your pet
var _dig: RummageSpot  # the spot it's rummaging through now
var _dig_phase := ""  # walk, in, dig, out, back
var _dig_t := 0.0
var _dig_feet := Vector2.ZERO  # where your pet's feet are while it's off its spot
var _floaters: Array[Dictionary] = []  # { text, at, age, color }: what it found, floating up
var _gift_spot := Control.new()  # over the presents on the floor, for taps
var _gift_shake := 0.0  # > 0 while a present shakes before it opens
var _gift_at := Vector2.ZERO  # where the present being opened is (its bottom middle)
var _gift_from_paws := false  # the one being opened was in its paws (its paws stay empty till it pops)
var _gift_puff := 0.0  # 1 right after a present pops, fading
var _gift_time := 0.0
var _flying: Array[Dictionary] = []  # { from, age, box }: boxes out of a present, flying to the pile
var _prize := MachineTab.PrizePopup.new()  # a toy out of a present


func _init() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	size_flags_horizontal = SIZE_EXPAND_FILL
	clip_contents = true
	_rng.randomize()

	for id in ["cushion", "basket", "cart"]:
		var spot := Control.new()
		spot.mouse_filter = MOUSE_FILTER_STOP
		spot.visible = false
		add_child(spot)
		_finds[id] = spot

	_pet.clicked.connect(func():
		if _dig != null:
			return  # busy rummaging
		if _work.tap():
			return  # seen it! the good pull goes to the collection
		if _gift_in_paws():
			tap_gift()
			return
		GameState.pat()
		_pet.view.squash = 0.6
		PetBubble.say_line(self, "pat"))
	_pet.tooltip_text = "pat me!"
	add_child(_pet)
	# rummage spots go over your pet, so it can dive into them
	for spot_data in Catalog.shared().rummage_spots:
		var spot := RummageSpot.new(spot_data)
		spot.visible = false
		spot.tapped.connect(_on_spot)
		add_child(spot)
		_spots[spot_data.id] = spot
	_work.speed = 90.0
	_held.pixel = 4
	_held.visible = false
	add_child(_held)
	_front.draw.connect(_draw_front)
	add_child(_front)
	_gift_spot.mouse_filter = MOUSE_FILTER_STOP
	_gift_spot.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_gift_spot.visible = false
	_gift_spot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			tap_gift())
	add_child(_gift_spot)

	# the card on the floor: name, food and mood, feed and pat
	_card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	_card.custom_minimum_size = Vector2(200, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_card.add_child(col)
	col.add_child(_name)
	col.add_child(_doing)
	for row in [["food", _food], ["mood", _mood]]:
		var line := HBoxContainer.new()
		var label := UiTheme.label(row[0], UiTheme.MUTED, UiTheme.SMALL)
		label.custom_minimum_size = Vector2(38, 0)
		line.add_child(label)
		line.add_child(row[1])
		col.add_child(line)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	_feed = UiTheme.button(feed_text(), func(): GameState.feed())
	_feed.icon = UiTheme.icon("coin", 14)
	_feed.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_theme_constant_override("icon_max_width", 14)
	_feed.add_theme_color_override("icon_normal_color", Color.WHITE)
	_feed.add_theme_color_override("icon_hover_color", Color.WHITE)
	buttons.add_child(_feed)
	buttons.add_child(UiTheme.button("pat", func():
		GameState.pat()
		_pet.view.squash = 0.6))
	col.add_child(buttons)
	add_child(Tilted.new(_card, -1.5))

	# sticky notes on the wall
	_notes.columns = 2
	_notes.add_theme_constant_override("h_separation", 12)
	_notes.add_theme_constant_override("v_separation", 16)
	add_child(_notes)
	var tilts := { "adventures": -2.0, "boxes": 1.5, "parts": 2.0, "map": -1.5 }
	for n in ["adventures", "boxes", "parts", "map"]:
		_notes.add_child(Tilted.new(_note(n), tilts[n]))
	add_child(_prize)  # a toy out of a present: over everything in the room

	resized.connect(_layout)
	GameState.changed.connect(func(): _dirty = true)
	GameState.adventures_changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.gifts_changed.connect(func(): _dirty = true)
	GameState.unlocked.connect(func(_id): _dirty = true)  # a note goes up with its tab
	GameState.tutorial_changed.connect(func(): _dirty = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_refresh()
			speak())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	show_care(_food, _mood)
	if _dirty:
		_refresh()
	for f in _floaters:
		f.age += delta
	_floaters = _floaters.filter(func(f): return f.age < FLOAT_TIME)
	_step_work(delta)
	_step_gifts(delta)


# ---- your pet opening the pile ------------------------------------------------------

func _step_work(delta: float) -> void:
	if _pet.view.pet == null or size.x <= 0.0:
		return
	if _dig == null and not _digs.is_empty() and _work.job == PackJob.Job.SIT and GameState.pinned.is_empty():
		_start_dig()
	if _dig != null:
		GameState.pack_job_seen()  # the pile waits while it rummages
		_step_dig(delta)
		queue_redraw()
		_front.queue_redraw()
		return
	var feet := _feet()
	_work.step(delta, feet.x, _pile_spot().x - 70.0)
	_pet.view.walking = _work.walking
	_pet.view.facing = _work.facing
	if _work.squash > 0.0:
		_pet.view.squash = _work.squash
		_work.squash = 0.0
	_pet.position.x = _work.x - _pet.size.x / 2.0
	if _work.pack_in_paws and _paw_box == "":
		_paw_box = GameState.next_pet_box()
	elif not _work.pack_in_paws:
		_paw_box = ""
	# the new pet: hopping off toward the window, or held up high
	if _held.pet != _work.held:
		_held.pet = _work.held
	_held.visible = _work.held != null
	var pet_h := PetView.size_for(_pet.view.pixel).y
	if _work.job == PackJob.Job.SHOW:
		_held.facing = 1
		_held.modulate.a = 1.0  # a hop before it faded out
		_held.position = Vector2(_work.x, feet.y - pet_h - 4.0 + sin(_work.time * 4.0) * 3.0)
	elif _work.job == PackJob.Job.HOP:
		var t := _work.hop_progress()
		_held.facing = -1
		_held.position = Vector2(lerpf(_work.x - 50.0, 200.0, t), feet.y - absf(sin(t * PI * 3.0)) * 24.0)
		_held.modulate.a = 1.0 if t < 0.8 else (1.0 - t) * 5.0
	if _work.said != _said:
		_said = _work.said
		if _said != "":
			PetBubble.say(self, _said)
	_doing.visible = _work.job != PackJob.Job.SIT or GameState.can_auto_open()
	_doing.text = "opening your pile" if _doing.visible else ""
	queue_redraw()
	_front.queue_redraw()


## Where the pile of boxes stands: by the wall, right of the rug.
func _pile_spot() -> Vector2:
	var floor_y := size.y * FLOOR
	return Vector2(size.x * 0.8, floor_y + 30.0)


## The boxes on your pile, a few of each kind drawn, and a badge with how many.
func _draw_pile() -> void:
	var kinds: Array[Dictionary] = []
	var total := 0
	for box in Catalog.shared().boxes:
		var n := GameState.in_bag(box.id)
		if n > 0:
			kinds.append(box)
			total += n
	if total == 0:
		return
	var at := _pile_spot()
	var pack := Vector2(PACK_W, PACK_W * 1.3)
	var shown := mini(total, PILE_SHOWN)
	for i in shown:
		var box: Dictionary = kinds[i % kinds.size()]
		var col := i % 3
		var row := i / 3
		var p := at + Vector2((col - 1) * 30.0 + (row % 2) * 12.0, -pack.y / 2.0 - row * 24.0)
		draw_set_transform(p, [-0.14, 0.09, -0.05, 0.12, -0.1, 0.03, -0.07, 0.1, 0.0][i])
		draw_texture_rect(PackArt.texture(box.get("art", {}), PACK_W), Rect2(-pack / 2.0, pack), false)
	draw_set_transform(Vector2.ZERO)
	var badge := "×%d" % total
	var w := UiTheme.DISPLAY_FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
	var r := Rect2(at + Vector2(36, -pack.y - (ceili(shown / 3.0) - 1) * 24.0 - 12.0), Vector2(w, 22))
	draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.PINK_SEAM, 11, 2, 0), r)
	draw_string(UiTheme.DISPLAY_FONT, r.position + Vector2(9, 16), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)


## Over your pet: the pack in its paws (shaking), the puff when it pops, sparkles round a good pull.
func _draw_front() -> void:
	var feet := _feet()
	var pet_h := PetView.size_for(_pet.view.pixel).y
	if _work.pack_in_paws and _paw_box != "":
		var shake := _work.job == PackJob.Job.SHAKE
		var tex := PackArt.texture(Catalog.shared().box(_paw_box).get("art", {}), 34)
		var size_ := Vector2(34, 34 * 1.3)
		_front.draw_set_transform(Vector2(_work.x + (sin(_work.time * 50.0) * 3.0 if shake else 0.0), feet.y - pet_h - 12.0),
			sin(_work.time * 40.0) * 0.2 if shake else -0.1)
		_front.draw_texture_rect(tex, Rect2(-size_ / 2.0, size_), false)
		_front.draw_set_transform(Vector2.ZERO)
	if _work.puff > 0.0:
		var center := Vector2(_work.x, feet.y - pet_h * 0.6)
		_front.draw_arc(center, 20.0 + (1.0 - _work.puff) * 70.0, 0.0, TAU, 32, Color(UiTheme.GOLD, _work.puff), 4.0 * _work.puff, true)
	if _work.job == PackJob.Job.SHOW and _work.held:
		var center := _held.position - Vector2(0, PetView.size_for(_held.pixel).y / 2.0)
		var color := Catalog.shared().tier_color(_work.held.rarity)
		_front.draw_circle(center, 44.0 + sin(_work.time * 4.0) * 3.0, Color(color, 0.18))
		for i in 5:
			var a := TAU * i / 5.0 + _work.time * 1.5
			var at := center + Vector2(cos(a) * 52.0, sin(a) * 40.0)
			var twinkle := 3.0 + 3.0 * absf(sin(_work.time * 5.0 + i))
			_front.draw_line(at - Vector2(twinkle, 0), at + Vector2(twinkle, 0), UiTheme.GOLD, 2.0)
			_front.draw_line(at - Vector2(0, twinkle), at + Vector2(0, twinkle), UiTheme.GOLD, 2.0)
	_draw_gifts_front()
	for f in _floaters:
		var c: Color = f.color
		c.a = 1.0 - maxf(0.0, f.age - FLOAT_TIME * 0.5) / (FLOAT_TIME * 0.5)
		var w := UiTheme.DISPLAY_FONT.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_front.draw_string(UiTheme.DISPLAY_FONT, f.at + Vector2(-w / 2.0, -maxf(0.0, f.age) * 36.0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, c)


# ---- presents ------------------------------------------------------------------

## Whether your pet is holding a present in its paws: one's waiting and it's sitting on its spot
## (not off at the pile, rummaging or holding up a good pull).
func _gift_in_paws() -> bool:
	if _gift_shake > 0.0 and _gift_from_paws:
		return false
	return GameState.gifts_waiting() - (1 if _gift_shake > 0.0 else 0) > 0 and _sitting()


## Your pet is on its spot with its paws free (not working the pile, even resting between packs,
## rummaging or showing a pull).
func _sitting() -> bool:
	return _dig == null and _work.job == PackJob.Job.SIT and not _work.walking and _work.held == null \
		and not GameState.can_auto_open()


## Where your pet's feet really are on its spot (a little higher on the cushion).
func _pet_feet() -> Vector2:
	return _feet() - Vector2(0, 10.0 if GameState.finds.has("cushion") else 0.0)


## The present in its paws: in front of its tummy, on the side it faces (its bottom middle).
func _paws_gift_at() -> Vector2:
	return Vector2(_work.x + _work.facing * 22.0, _pet_feet().y - 8.0)


## The presents on the floor by its spot: [bottom middle, zoom] for each (the first is the
## big one when it isn't in its paws, the rest are small, stacked beside it).
func _floor_gifts() -> Array:
	var n := GameState.gifts_waiting() - (1 if _gift_shake > 0.0 else 0)
	var big := not _sitting()  # busy: the present it would hold waits big on the floor
	if _gift_in_paws():
		n -= 1
	var out := []
	var base := _feet() + Vector2(-100, 22)
	var slots := [Vector2.ZERO, Vector2(-30, 0), Vector2(-15, -30)] if not big else [Vector2.ZERO, Vector2(-40, 0), Vector2(-24, -30)]
	var skip := 1 if _gift_shake > 0.0 and not _gift_from_paws else 0  # the one shaking open keeps its spot
	for i in range(skip, mini(n + skip, 3)):
		out.append([base + slots[i], GIFT_ZOOM if big and i == 0 else 2.0])
	return out


## A present is opening or its toy card is up (unlock popups wait for it, like at the machine).
func busy() -> bool:
	return is_visible_in_tree() and (_gift_shake > 0.0 or _prize.visible)


## You tapped a present (the one in its paws, or on the floor): it shakes, then pops open.
func tap_gift() -> void:
	if _gift_shake > 0.0 or GameState.gifts_waiting() <= 0:
		return
	var lying := _floor_gifts()
	_gift_from_paws = _gift_in_paws() or lying.is_empty()
	_gift_at = _paws_gift_at() if _gift_from_paws else lying[0][0]
	_gift_shake = GIFT_SHAKE
	_pet.view.squash = 0.4
	_dirty = true


func _step_gifts(delta: float) -> void:
	_gift_time += delta
	_gift_puff = move_toward(_gift_puff, 0.0, delta * 2.0)
	for f in _flying:
		f.age += delta
	_flying = _flying.filter(func(f): return f.age < GIFT_FLY)
	if _gift_shake > 0.0:
		_gift_shake -= delta
		if _gift_shake <= 0.0:
			_gift_shake = 0.0
			_open_gift()
	# taps on the floor presents
	var lying := _floor_gifts()
	_gift_spot.visible = not lying.is_empty()
	if _gift_spot.visible:
		var r := Rect2(lying[0][0], Vector2.ZERO)
		for g in lying:
			var w: float = 7.0 * float(g[1])
			r = r.merge(Rect2(g[0] - Vector2(w, PawsView.PRESENT_H * float(g[1])), Vector2(w * 2.0, PawsView.PRESENT_H * float(g[1]))))
		_gift_spot.position = r.position - Vector2(4, 4)
		_gift_spot.size = r.size + Vector2(8, 8)
	if _prize.visible:
		_prize.position = Vector2(size.x * 0.5 - _prize.size.x / 2.0, maxf(12.0, _pet_feet().y - PetView.size_for(_pet.view.pixel).y - _prize.size.y - 24.0))


## The present pops: the boxes fly to the pile, a toy shows its card.
func _open_gift() -> void:
	var got := GameState.open_gift()
	if got.is_empty():
		return
	_gift_puff = 1.0
	_pet.view.squash = 0.6
	for i in int(got.boxes):
		_flying.append({ "from": _gift_at + Vector2(i * 14.0, -20.0), "age": -0.12 * i, "box": str(got.box) })
	var n := int(got.boxes)
	_floaters.append({ "text": "+%d box%s" % [n, "es" if n > 1 else ""], "at": _pile_spot() + Vector2(0, -96), "age": 0.0, "color": UiTheme.PINK })
	if not (got.toy as Dictionary).is_empty():
		MachineTab.show_toy(self, _prize, got.toy)
	_dirty = true


## A present: its paper, lid, ribbon and bow in the page's colours.
func _present(on: CanvasItem, at: Vector2, zoom: float, tilt := 0.0) -> void:
	PawsView.draw_present(on, at.round(), tilt, zoom, UiTheme.PINK, UiTheme.PINK_SEAM, UiTheme.LILAC, UiTheme.PINK.lerp(UiTheme.TEXT, 0.35))


## Presents on the floor by your pet's spot (under the pet and its props).
func _draw_gifts_floor() -> void:
	for g in _floor_gifts():
		_present(self, g[0], g[1])


## Over your pet: the present in its paws (a small wobble now and then), the one shaking open, the
## pop, and boxes flying to the pile.
func _draw_gifts_front() -> void:
	if _gift_in_paws():
		var wobble := sin(_gift_time * 14.0) * 0.08 if fmod(_gift_time, 4.0) < 0.6 else 0.0
		_present(_front, _paws_gift_at(), GIFT_ZOOM, wobble)
	if _gift_shake > 0.0:
		var t := _gift_time * 50.0
		_present(_front, _gift_at + Vector2(sin(t) * 3.0, 0), GIFT_ZOOM, sin(t * 0.8) * 0.18)
	if _gift_puff > 0.0:
		var center := _gift_at - Vector2(0, PawsView.PRESENT_H * GIFT_ZOOM * 0.5)
		_front.draw_arc(center, 14.0 + (1.0 - _gift_puff) * 56.0, 0.0, TAU, 32, Color(UiTheme.GOLD, _gift_puff), 4.0 * _gift_puff, true)
	var to := _pile_spot() - Vector2(0, 60)
	for f in _flying:
		if f.age < 0.0:
			continue
		var t: float = f.age / GIFT_FLY
		var at: Vector2 = (f.from as Vector2).lerp(to, t) - Vector2(0, sin(t * PI) * 70.0)
		var tex := PackArt.texture(Catalog.shared().box(f.box).get("art", {}), 30)
		var pack := Vector2(30, 39)
		_front.draw_set_transform(at, t * TAU * 0.5)
		_front.draw_texture_rect(tex, Rect2(-pack / 2.0, pack), false)
		_front.draw_set_transform(Vector2.ZERO)


# ---- rummaging ------------------------------------------------------------------

func _on_spot(spot: RummageSpot) -> void:
	if spot == _dig or spot in _digs:
		return
	if not spot.is_ready():
		PetBubble.say_line(self, "rummage_empty", { "spot": spot.spot.name })
		return
	_digs.append(spot)
	_pet.view.squash = 0.4


func _start_dig() -> void:
	_dig = _digs.pop_front()
	if not _dig.is_ready():
		_dig = null
		return
	_dig_phase = "walk"
	_dig_t = 0.0
	_dig_feet = Vector2(_work.x if _work.x >= 0.0 else _feet().x, _feet().y)


## Where your pet stands next to a spot before it hops in: on the side facing its rug.
func _stand_at(spot: RummageSpot) -> Vector2:
	var base := spot.position + Vector2(spot.size.x / 2.0, spot.size.y)
	var side := 1.0 if _feet().x > base.x else -1.0
	return Vector2(base.x + side * (spot.size.x / 2.0 + 26.0), maxf(base.y + 4.0, size.y * FLOOR + 16.0))


## Where the middle of your pet goes when it's standing with its feet at `feet`.
func _middle(feet: Vector2) -> Vector2:
	return feet + Vector2(0, 6.0 - _pet.size.y / 2.0)


## Upside down, head in the spot.
func _dive_middle() -> Vector2:
	return _dig.dive_point() + Vector2(0, 26.0 - _pet.size.y / 2.0)


func _pose(middle: Vector2, turn: float) -> void:
	_pet.pivot_offset = _pet.size / 2.0
	_pet.rotation = turn
	_pet.position = middle - _pet.size / 2.0


func _step_dig(delta: float) -> void:
	match _dig_phase:
		"walk", "back":
			var to := _stand_at(_dig) if _dig_phase == "walk" else _feet()
			var d := to - _dig_feet
			_pet.view.walking = d.length() > 1.0
			if absf(d.x) > 1.0:
				_pet.view.facing = 1 if d.x > 0.0 else -1
			_dig_feet = _dig_feet.move_toward(to, DIG_WALK * delta)
			_pose(_middle(_dig_feet), 0.0)
			if _dig_feet.distance_to(to) < 1.0:
				_pet.view.walking = false
				if _dig_phase == "walk":
					_pet.view.facing = 1 if _dig.dive_point().x > _dig_feet.x else -1
					_dig_phase = "in"
					_dig_t = 0.0
				else:
					_end_dig()
		"in", "out":
			_dig_t += delta / DIG_HOP
			var t := minf(_dig_t, 1.0)
			if _dig_phase == "out":
				t = 1.0 - t
			var hop := Vector2(0, -sin(t * PI) * 46.0)
			_pose(_middle(_stand_at(_dig)).lerp(_dive_middle(), t) + hop, t * PI * _pet.view.facing)
			if _dig_t >= 1.0:
				_dig_t = 0.0
				if _dig_phase == "in":
					_dig_phase = "dig"
					_dig.digging = true
				else:
					_dig_feet = _stand_at(_dig)
					_dig_phase = "back"
		"dig":
			_dig_t += delta
			_pose(_dive_middle() + Vector2(sin(_dig_t * 30.0) * 3.0, 0), PI * _pet.view.facing)
			if _dig_t >= DIG_TIME:
				_dig.digging = false
				_dig.queue_redraw()
				_found(GameState.rummage(_dig.spot.id))
				_dig_phase = "out"
				_dig_t = 0.0


## What came out of the spot floats up, and your pet says so.
func _found(found: Dictionary) -> void:
	var at := _dig.dive_point() + Vector2(0, -70)
	var lines: Array[Array] = []
	if found.has("coins"):
		lines.append(["+%d coins" % found.coins, UiTheme.CYAN])
	if found.has("xp"):
		lines.append(["+%d xp" % found.xp, UiTheme.GOLD])
	if found.has("part"):
		lines.append(["a part!", UiTheme.LILAC])
	for i in lines.size():
		_floaters.append({ "text": lines[i][0], "at": at + Vector2(0, -22.0 * i), "age": -0.12 * i, "color": lines[i][1] })
	var spot_name: String = _dig.spot.name
	if found.has("part"):
		var bits := str(found.part).split(":")  # part, slot, id
		var part_name := "a %s %s" % [Catalog.shared().part(bits[1], bits[2]).get("name", bits[2]), bits[1]]
		PetBubble.say_line(self, "rummage_part", { "spot": spot_name, "part": part_name })
	elif found.has("xp"):
		PetBubble.say_line(self, "rummage_xp", { "spot": spot_name })
	elif not found.is_empty():
		PetBubble.say_line(self, "rummage_coins", { "spot": spot_name })


func _end_dig() -> void:
	_dig = null
	_pet.rotation = 0.0
	_work.x = _dig_feet.x
	_layout()


## A spot with something in it, if there is one.
func _ready_spot() -> RummageSpot:
	for id in _spots:
		if _spots[id].visible and _spots[id].is_ready():
			return _spots[id]
	return null


# ---- the room -----------------------------------------------------------------

func _layout() -> void:
	var floor_y := size.y * FLOOR
	var feet := _feet()
	_pet.size = _pet.custom_minimum_size
	# the portrait draws its pet standing on its bottom edge (less a pixel of margin)
	if _dig == null:
		_pet.position = feet - Vector2(_pet.size.x / 2.0, _pet.size.y - 6.0 + (10.0 if GameState.finds.has("cushion") else 0.0))
	var card_holder := _card.get_parent() as Control
	card_holder.position = Vector2(20, size.y - card_holder.get_combined_minimum_size().y - 18)
	card_holder.size = card_holder.get_combined_minimum_size()
	_notes.position = Vector2(size.x - _notes.get_combined_minimum_size().x - 18, 18)
	_notes.size = _notes.get_combined_minimum_size()
	var basket := Vector2(size.x * 0.8, floor_y + (size.y - floor_y) * 0.62)
	_finds.cushion.position = feet - Vector2(62, 18)
	_finds.cushion.size = Vector2(124, 34)
	_finds.basket.position = basket - Vector2(40, 44)
	_finds.basket.size = Vector2(80, 50)
	_finds.cart.position = basket + Vector2(58, -34)
	_finds.cart.size = Vector2(90, 44)
	# rummage spots, placed by their bottom middle
	var card_right := card_holder.position.x + card_holder.size.x
	var bases := {
		"dresser": Vector2(size.x * 0.3, floor_y + 8.0),
		"plant": Vector2(size.x * 0.93, floor_y + 10.0),
		"socks": Vector2(maxf(card_right + 60.0, feet.x - 190.0), size.y - 30.0),
		"toybox": Vector2(minf(feet.x + 200.0, size.x * 0.8 - 110.0), feet.y + 64.0),
	}
	for id in _spots:
		var spot: RummageSpot = _spots[id]
		spot.position = bases.get(spot.spot.draw, feet) - Vector2(spot.size.x / 2.0, spot.size.y)
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), r)
	var floor_y := size.y * FLOOR
	# the floor and the crayon line where it meets the wall
	var line := PackedVector2Array()
	for i in 21:
		var x := size.x * i / 20.0
		line.append(Vector2(x, floor_y + sin(i * 1.3) * 2.0))
	var floor_poly := line.duplicate()
	floor_poly.append(Vector2(size.x, size.y - 2))
	floor_poly.append(Vector2(0, size.y - 2))
	draw_colored_polygon(floor_poly, UiTheme.PAGE)
	draw_polyline(line, UiTheme.LILAC_SEAM, 3.0, true)
	_draw_window(Rect2(40, 44, 136, 140))
	# the rug, stitched round the edge
	var feet := _feet()
	var rug := PackedVector2Array()
	for i in 49:
		var a := TAU * i / 48.0
		rug.append(feet + Vector2(cos(a) * 140.0, sin(a) * 36.0))
	draw_colored_polygon(rug, UiTheme.PAGE.lerp(UiTheme.PINK, 0.14))
	for i in range(0, 48, 2):
		draw_line(rug[i], rug[i + 1], UiTheme.PINK_SEAM, 2.5)
	if GameState.finds.has("cushion"):
		var c := Rect2(feet - Vector2(60, 16), Vector2(120, 32))
		draw_style_box(UiTheme.box(UiTheme.PINK_SEAM, UiTheme.PINK, 16, 2, 0), c)
		var x := c.position.x + 12
		while x < c.end.x - 12:
			draw_line(Vector2(x, c.get_center().y), Vector2(x + 4, c.get_center().y), UiTheme.PINK, 2.0)
			x += 8
	_draw_pile()
	_draw_gifts_floor()
	var basket := Vector2(size.x * 0.8, floor_y + (size.y - floor_y) * 0.62)
	if GameState.finds.has("basket"):
		_draw_basket(basket)
	if GameState.finds.has("cart"):
		_draw_cart(basket + Vector2(100, 6))


## Where your pet's feet go: on the rug, a little right of the middle.
func _feet() -> Vector2:
	var floor_y := size.y * FLOOR
	return Vector2(size.x * 0.55, floor_y + (size.y - floor_y) * 0.4)


func _draw_window(w: Rect2) -> void:
	draw_rect(w, UiTheme.SKY)
	for p in [Vector2(28, 30), Vector2(88, 18), Vector2(56, 76), Vector2(110, 104), Vector2(20, 116)]:
		draw_rect(Rect2(w.position + p, Vector2(2, 2)), Color(UiTheme.TEXT, 0.5))
	# a crescent moon
	var moon := w.position + Vector2(106, 50)
	draw_circle(moon, 15.0, UiTheme.GOLD)
	draw_circle(moon + Vector2(-7, -3), 13.0, UiTheme.SKY)
	var frame := UiTheme.box(Color(0, 0, 0, 0), UiTheme.LILAC_SEAM, 3, 3, 0)
	draw_style_box(frame, w)
	draw_line(Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y), UiTheme.LILAC_SEAM, 3.0)
	draw_line(Vector2(w.position.x, w.get_center().y), Vector2(w.end.x, w.get_center().y), UiTheme.LILAC_SEAM, 3.0)
	draw_line(Vector2(w.position.x - 8, w.end.y + 6), Vector2(w.end.x + 8, w.end.y + 6), UiTheme.LINE, 2.5)


func _draw_basket(at: Vector2) -> void:
	var fill := UiTheme.PAGE.lerp(UiTheme.GOLD, 0.3)
	draw_arc(at + Vector2(0, -24), 26.0, PI, TAU, 16, UiTheme.GOLD, 2.5, true)
	var body := PackedVector2Array([at + Vector2(-38, -24), at + Vector2(38, -24), at + Vector2(30, 14), at + Vector2(-30, 14)])
	draw_colored_polygon(body, fill)
	body.append(body[0])
	draw_polyline(body, UiTheme.GOLD, 2.5, true)
	for y in [-10.0, 2.0]:
		draw_line(at + Vector2(-34, y), at + Vector2(34, y), Color(UiTheme.GOLD, 0.6), 1.8)


func _draw_cart(at: Vector2) -> void:
	var fill := UiTheme.PAGE.lerp(UiTheme.LILAC, 0.25)
	var box := Rect2(at + Vector2(-40, -30), Vector2(80, 30))
	draw_rect(box, fill)
	draw_style_box(UiTheme.box(Color(0, 0, 0, 0), UiTheme.LILAC, 4, 2, 0), box)
	draw_line(at + Vector2(40, -24), at + Vector2(58, -38), UiTheme.LILAC, 2.5)
	for x in [-24.0, 24.0]:
		draw_circle(at + Vector2(x, 4), 8.0, UiTheme.PAGE)
		draw_arc(at + Vector2(x, 4), 8.0, 0.0, TAU, 16, UiTheme.LILAC, 2.5, true)


# ---- sticky notes -----------------------------------------------------------------

func _note(note_name: String) -> PanelContainer:
	var accent: Color = { "adventures": UiTheme.MINT, "boxes": UiTheme.CYAN, "parts": UiTheme.LILAC, "map": UiTheme.GOLD }[note_name]
	var panel := PanelContainer.new()
	panel.mouse_filter = MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	panel.custom_minimum_size = Vector2(164, 78)
	var sb := UiTheme.sticker(UiTheme.LINE, 6, UiTheme.RAISED, 12)
	sb.content_margin_top = 14
	sb.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)
	var title := UiTheme.title(note_name, 14, accent)
	var line := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var hint := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
	for l in [title, line, hint]:
		l.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(l)
	# a strip of tape holding it to the wall
	panel.draw.connect(func():
		var tape := Rect2(panel.size.x / 2.0 - 20.0, -8.0, 40.0, 14.0)
		panel.draw_set_transform(tape.get_center(), deg_to_rad(-3.0))
		panel.draw_rect(Rect2(-tape.size / 2.0, tape.size), Color(accent, 0.45))
		panel.draw_set_transform(Vector2.ZERO))
	panel.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tapped(note_name))
	panel.mouse_entered.connect(func(): sb.border_color = accent; panel.queue_redraw())
	panel.mouse_exited.connect(func(): sb.border_color = UiTheme.LINE; panel.queue_redraw())
	_note_parts[note_name] = { "panel": panel, "line": line, "hint": hint }
	return panel


func _tapped(note_name: String) -> void:
	match note_name:
		"adventures", "map":
			go.emit("adventures")
		"parts":
			go.emit("inventory")
		"boxes":
			var owned := _first_box_in_bag()
			if owned != "":
				open_box.emit(owned)
			else:
				go.emit("boxes")


## The feed button's words: a snack's price now (it grows with the machine).
static func feed_text() -> String:
	return "feed %s" % UiTheme.num(GameState.snack_price())


## Your pet's food and mood on two bars, lit up while their care buff is on (the name as tooltip).
static func show_care(food: ProgressBar, mood: ProgressBar) -> void:
	var catalog := GameState.catalog
	food.value = GameState.hunger
	mood.value = GameState.happiness
	_light(food, Care.buff_of(catalog, "food"))
	_light(mood, Care.buff_of(catalog, "mood"))


## Lights one care bar while its buff is on.
static func _light(bar: ProgressBar, buff: Dictionary) -> void:
	var lit := not buff.is_empty() and Care.on(buff, GameState.hunger, GameState.happiness)
	UiTheme.light_bar(bar, lit, str(buff.get("name", "")))


## What each note says right now; notes with nothing waiting fade back a little.
func _refresh() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	_feed.text = feed_text()
	var pet := GameState.collection.active()
	_pet.set_pet(pet)
	_name.text = pet.display_name(catalog) if pet else ""

	var back := GameState.runs.filter(func(r): return r.status == RunState.Status.DONE).size()
	var waiting := GameState.runs.filter(func(r): return r.status == RunState.Status.WAITING).size()
	var away := GameState.runs.size()
	if back > 0:
		_set_note("adventures", "%d back home!" % back if back > 1 else "someone's back home!", "", true)
	elif waiting > 0:
		_set_note("adventures", "%d waiting for you" % waiting, "", true)
	elif away > 0:
		_set_note("adventures", "%d out and about" % away, "", false)
	else:
		_set_note("adventures", "nobody's away", "", false)
	_show_note("adventures", _tab_shown("adventures"))

	var boxes := GameState.boxes_on_pile()
	if GameState.can_auto_open() and boxes > 0:
		_set_note("boxes", "%s is opening the pile" % _name.text, "%d left" % boxes, true)
	else:
		_set_note("boxes", "%d boxes on your pile" % boxes if boxes > 0 else "your pile is empty", "", boxes > 0)
	_show_note("boxes", _tab_shown("boxes"))

	var parts := 0
	for key in GameState.parts:
		parts += int(GameState.parts[key])
	_set_note("parts", "%d parts to sew on" % parts if parts > 0 else "no parts yet", "", parts > 0)
	_show_note("parts", _tab_shown("inventory"))

	var ready := GameState.spotted.size() + GameState.rumours.size()
	_set_note("map", "somewhere new to go!" if ready > 0 else "nothing new spotted", "", ready > 0)
	_show_note("map", _tab_shown("adventures"))

	for id in _spots:
		_spots[id].visible = GameState.rummage_open()
	for id in _finds:
		_finds[id].visible = GameState.finds.has(id)
		_finds[id].tooltip_text = "%s, found on an adventure" % catalog.finds.get(id, {}).get("name", id)
	_layout()


func _set_note(note_name: String, line: String, hint: String, waiting: bool) -> void:
	var n: Dictionary = _note_parts[note_name]
	n.line.text = line
	n.hint.text = hint
	n.hint.visible = hint != ""
	n.panel.modulate.a = 1.0 if waiting else 0.62


## A note is only on the wall once the tab it leads to is (hidden until earned).
func _show_note(note_name: String, on: bool) -> void:
	_note_parts[note_name].panel.get_parent().visible = on


## Whether the spine shows this tab right now: earned, and not held back by the tutorial.
static func _tab_shown(tab_id: String) -> bool:
	return tab_id in ExpandedView.TUTORIAL_TABS.get(GameState.tutorial, [tab_id]) and GameState.tab_open(tab_id)


func _first_box_in_bag() -> String:
	for box in Catalog.shared().boxes:
		if GameState.in_bag(box.id) > 0:
			return box.id
	return ""


## Your pet says what's worth saying: news first, then what it did while you were busy.
func speak() -> void:
	var pet := GameState.collection.active()
	if pet == null:
		return
	var catalog := Catalog.shared()
	var news := GameState.take_announcement()
	if news != "":
		var more := GameState.take_announcement()
		PetBubble.say(self, news + (" " + more if more != "" else ""))
		return
	var work := PetVoice.work_summary(pet, GameState.take_idle_log(), _rng, catalog)
	if work != "":
		PetBubble.say(self, work)
	elif _ready_spot() != null and (GameState.rummaged.is_empty() or _rng.randf() < 0.35):
		PetBubble.say_line(self, "rummage_hint", { "spot": _ready_spot().spot.name })
	else:
		var what := PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog)
		GameState.news = {}
		PetBubble.say(self, PetVoice.line(pet, what, _rng, catalog))
	_pet.view.squash = 0.4
