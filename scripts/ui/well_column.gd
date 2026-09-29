class_name WellColumn
extends Control
## The old well as a tall drawn cross-section (the dungeon page's left column, in a scroll): the
## well mouth on the grass, then the bands the army has reached. Rope floors in the well, doors in
## the cellar (tiny doors, knock-back doors with their boings), stairs further down with a guard
## every 10th. Lit landings (floors cleared) have a lamp; the next few floors carry a feeling word
## (never a number); the target has a pink flag; while the army is down there it walks down.
## Once the tiny key is found, a little pink door (SewDoor) is cut through the right wall of floor 20:
## the sewing room (see Sewing). Drawn from GameState.dungeon, see Dungeon for the rules.
## Down the left lane of the soil hang the wisps perks (PerkNail, see Perks): coral things on nails,
## one per landing, the bow on the roof post first, joined by a coral thread (solid down to the last
## one bought, dashed chalk after); the 2 endless tips hang at the bottom once the chain is done.
## Nails deeper than the army has been stay hidden.
## Every 10th landing the army has cleared can be held (HoldSpot): a crowd holding the rope, propping
## the door or sitting on the stairs, with a coral count pill ('N/M' dashed while it fills). A fully held
## stairs landing has no guard any more.

signal door_pressed  # the sewing room's door was tapped
signal nail_pressed(id: String)  # a perk's nail was tapped
signal hold_pressed(f: int)  # a held landing (its crowd or its pill) was tapped

const GROUND := 70.0  # the grass line
const TAIL := 26.0  # the shaft fades out below the last floor drawn
const FLOOR_H := { "rope": 18.0, "doors": 23.0, "stairs": 19.0 }
const WIDTH := { "rope": 58.0, "doors": 98.0, "stairs": 80.0 }
const WORDS_AHEAD := 6  # floors past the deepest that get a feeling word
const MORE_BELOW := 8  # floors drawn past the deepest one in a band that goes on forever
const LANE_X := 40.0  # the nails' lane down the left of the soil
const LANE := Vector2(20, 62)  # the lane's left and right edge (no pebbles in it)
const TIPS_H := 56.0  # room for the 2 tips under the last floor drawn

var _ys: Array[float] = [GROUND]  # floor -> the y of its landing (0 is the grass)
var _to := 10  # the last floor drawn
var _words := {}  # floor -> [word, heat]
var _party: Array[Texture2D] = []  # the army's first few faces while it's down there
var _pos := -1.0  # where the army is (floors), -1 when home
var _sew_door := SewDoor.new()
var _nails := {}  # perk id -> PerkNail
var _shown: Array[String] = []  # the perks on the wall, in order (see GameState.perks_shown)
var _picked := ""  # the perk whose card is open
var _tips_y := -1.0  # where the tips hang (-1: not yet)
var _holds := {}  # landing -> HoldSpot
var _hold_picked := 0  # the landing whose card is open (0: none)


func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_NEAREST
	_sew_door.visible = false
	_sew_door.pressed.connect(func(): door_pressed.emit())
	add_child(_sew_door)
	resized.connect(_place_door)
	resized.connect(_place_nails)
	resized.connect(_place_holds)


## Works the drawing out again from the game (the army, its orders, what's lit). `a` and `rules`
## from GameState.army() and army_rules() when the page has them already.
func refresh(a: Dictionary = {}, rules: Dictionary = {}) -> void:
	var catalog := GameState.catalog
	var state: Dictionary = GameState.dungeon
	var shown := Dungeon.shown_to(catalog, state)
	var deep := int(state.deep)
	if shown >= 1 << 20:
		shown = maxi(maxi(deep, int(state.target)), int(Dungeon.data(catalog).bands.back().from)) + MORE_BELOW
	_to = maxi(shown, 1)
	_ys = [GROUND]
	for f in range(1, _to + 1):
		_ys.append(_ys[f - 1] + float(FLOOR_H.get(str(Dungeon.band_of(catalog, f).kind), 20.0)))
	_shown = GameState.perks_shown()
	var tips := _shown.any(func(id): return Perks.is_tip(catalog, id))
	_tips_y = _ys[_to] + 14.0 if tips else -1.0
	custom_minimum_size = Vector2(200, _ys[_to] + TAIL + (TIPS_H if tips else 0.0))
	# feeling words on the next few floors (and the target), for the army lined up (none: no words)
	_words = {}
	if a.is_empty():
		a = GameState.army()
	if not GameState.dungeon_running() and int(a.sent) > 0:
		if rules.is_empty():
			rules = GameState.army_rules(a)
		_words = GameState.floor_words(deep + 1, mini(_to, deep + WORDS_AHEAD), rules)
		var target := int(state.target)
		if target > deep and target <= _to and not _words.has(target):
			_words.merge(GameState.floor_words(target, target, rules))
	_party.clear()
	if GameState.dungeon_running():
		var faces: Array = []
		if GameState.collection.active():
			faces.append(GameState.collection.active())
		faces.append_array(a.cards.slice(0, 2))
		if faces.size() < 3:
			for uid in GameState.herd_faces(a.keys, 3 - faces.size(), 5):
				faces.append(GameState.collection.get_pet(str(uid)))
		for pet in faces:
			if pet:
				_party.append(PetLook.texture_for(pet.parts, false, pet.sewn))
	_pos = GameState.dungeon_floor_now()
	_place_door()
	_build_nails()
	_build_holds()
	queue_redraw()


## The held landing whose card is open (0 for none): its pill lights up.
func set_hold_picked(f: int) -> void:
	_hold_picked = f
	for k in _holds:
		_holds[k].picked = k == f
		_holds[k].queue_redraw()


## A held landing's spot (null when it isn't there).
func hold_spot(f: int) -> HoldSpot:
	return _holds.get(f)


## One spot per landing a crowd can hold (made once each, kept while they show).
func _build_holds() -> void:
	var spots := GameState.hold_spots()
	for f in _holds.keys():
		if not f in spots or f > _to:
			_holds[f].queue_free()
			_holds.erase(f)
	for f in spots:
		if f > _to or _holds.has(f):
			continue
		var h := HoldSpot.new()
		h.pressed.connect(func(): hold_pressed.emit(h.landing))
		add_child(h)
		_holds[f] = h
	_place_holds()


func _place_holds() -> void:
	var catalog := GameState.catalog
	var most := Dungeon.hold_int(catalog, "faces", 14)
	var looks := Dungeon.hold_int(catalog, "looks", 8)
	for f: int in _holds:
		var n := Dungeon.held_n(GameState.dungeon, f)
		var shown := Herd.mound_size(catalog, n, most)
		var kind := str(Dungeon.band_of(catalog, f).kind)
		var hw := _half(f)
		var cx := _cx()
		var y := _ys[f]
		var geo := { "y": y, "y0": _ys[f - 1], "l": cx - hw, "r": cx + hw, "cx": cx, "kind": kind,
			"dip": (y - _ys[f - 1]) * 0.55, "down_right": f % 2 == 1, "door_x": -1.0 }
		if kind == "doors" and Dungeon.floor_kind(catalog, f) in ["door", "tiny", "knock"]:
			var dw := 6.0 if Dungeon.floor_kind(catalog, f) == "tiny" else 9.0
			geo.door_x = cx - hw + 4.0 if f % 2 == 1 else cx + hw - 4.0 - dw
			geo.door_h = minf(13.0, y - _ys[f - 1] - 4.0)
		_holds[f].setup(f, n, Dungeon.hold_need(catalog, f), GameState.hold_faces(f, mini(shown, looks)), shown, geo)
		_holds[f].picked = f == _hold_picked


## The perk whose card is open gets a ring ("" for none).
func set_picked(id: String) -> void:
	if id == _picked:
		return
	_picked = id
	for k in _nails:
		_nails[k].show_state(_nails[k].look, _nails[k].level, k == _picked)


## A perk's nail (null when it isn't on the wall).
func nail(id: String) -> PerkNail:
	return _nails.get(id)


## A perk's nail wiggles (just bought).
func pop(id: String) -> void:
	if _nails.has(id):
		_nails[id].pop()


## The nails for the perks that show (made once each, kept while they show), and their looks.
func _build_nails() -> void:
	var catalog := GameState.catalog
	for id in _nails.keys():
		if not id in _shown:
			_nails[id].queue_free()
			_nails.erase(id)
	for id in _shown:
		if not _nails.has(id):
			var p := Perks.perk(catalog, id)
			var n := PerkNail.new(id, str(p.get("thing", "bow")), Perks.is_tip(catalog, id))
			n.scale_thing = 0.76 if int(p.get("floor", -1)) == 0 else 0.9
			n.picked.connect(func(which: String): nail_pressed.emit(which))
			add_child(n)
			_nails[id] = n
		var lv := GameState.perk_level(id)
		var look := "on" if lv > 0 or Perks.is_tip(catalog, id) else ("next" if GameState.perk_available(id) else "off")
		_nails[id].show_state(look, lv, id == _picked)
	_place_nails()


## Where a perk's nail head is: the bow on the well's left roof post, the others on their landing
## in the lane, the tips side by side at the bottom.
func nail_at(id: String) -> Vector2:
	var catalog := GameState.catalog
	var p := Perks.perk(catalog, id)
	if Perks.is_tip(catalog, id):
		var i := Perks.tips(catalog).map(func(t): return str(t.id)).find(id)
		return Vector2(LANE_X - 14.0 + i * 30.0, _tips_y)
	var f := int(p.get("floor", 0))
	if f <= 0:
		return Vector2(_cx() - _half(1) - 9.0 - 3.0, GROUND - 30.0)
	return Vector2(LANE_X, _ys[mini(f, _to)] - 20.0)


func _place_nails() -> void:
	for id in _nails:
		_nails[id].hang(nail_at(id))


## The sewing room's door on its floor, through the right wall (only once the key is found).
func _place_door() -> void:
	var f := int(GameState.catalog.sewing.get("door_floor", 20))
	_sew_door.visible = GameState.sewing_open() and f <= _to
	if not _sew_door.visible:
		return
	var wall := _cx() + _half(f)
	_sew_door.place(Vector2(wall + 3.0, _ys[f]), 3.0)


## Where the sewing room's door is in the column (for the scroll to show it), or -1.
func door_y() -> float:
	var f := int(GameState.catalog.sewing.get("door_floor", 20))
	return _ys[f] if GameState.sewing_open() and f <= _to else -1.0


## Moves the walking army along (called often while it's down there).
func tick() -> void:
	var now := GameState.dungeon_floor_now()
	if absf(now - _pos) > 0.01:
		_pos = now
		queue_redraw()


## The y of a landing (fractions walk between them).
func y_at(f: float) -> float:
	var i := clampi(floori(f), 0, _to)
	var next := clampi(i + 1, 0, _to)
	return lerpf(_ys[i], _ys[next], f - floori(f)) if next != i else _ys[i]


## Where the army is drawn, for the scroll to follow.
func party_y() -> float:
	return y_at(maxf(_pos, 0.0))


func _cx() -> float:
	return roundf(size.x * 0.55)  # right of the middle: the nails' lane is down the left


func _half(f: int) -> float:
	return float(WIDTH.get(str(Dungeon.band_of(GameState.catalog, maxi(f, 1)).kind), 70.0)) / 2.0


func _draw() -> void:
	var catalog := GameState.catalog
	var state: Dictionary = GameState.dungeon
	var deep := int(state.deep)
	var parts_on := GameState.feature_on("parts")
	# landings light up as the army passes them (a floor it turns back at never lights)
	var lit_to := maxi(deep, mini(floori(_pos), Dungeon.cleared_to(state.run))) if _pos >= 0.0 else deep
	var cx := _cx()
	var w := size.x
	var bottom := _ys[_to] + TAIL
	var font := UiTheme.BODY_FONT if UiTheme.BODY_FONT else get_theme_default_font()
	var display := UiTheme.DISPLAY_FONT if UiTheme.DISPLAY_FONT else font
	var seam := UiTheme.LILAC_SEAM
	var lamp := UiTheme.WISP

	# soil, pebbles and roots (all the way down, past the last floor drawn)
	var soil_end := maxf(bottom, size.y)
	draw_rect(Rect2(0, GROUND, w, soil_end - GROUND), UiTheme.DEEP.lerp(UiTheme.PAPER, 0.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var pebbles := int((soil_end - GROUND) / 6.0)
	for i in pebbles:
		var p := Vector2(rng.randf() * w, GROUND + 10.0 + rng.randf() * (soil_end - GROUND - 14.0))
		var root := rng.randf() >= 0.8
		var rx := 2.0 + rng.randf() * 2.0
		var ry := 1.5 + rng.randf()
		var f_here := _floor_at(p.y)
		if (absf(p.x - cx) < _half(f_here) + 10.0 and p.y < bottom + 6.0) or p.x < LANE.y:
			continue
		if root:
			_curve(p, p + Vector2(6, 4), p + Vector2(3, 10), UiTheme.LINE, 2.0)
			_curve(p, p + Vector2(-5, 3), p + Vector2(-8, 2), UiTheme.LINE, 2.0)
		else:
			_ellipse(p, rx, ry, UiTheme.LINE, 1.6)

	# the shaft: narrow for the rope, wide for the cellar, a bit narrower for the stairs
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var f0 := 1
	while f0 <= _to:
		var b := Dungeon.band_of(catalog, f0)
		var last := mini(_to, int(b.get("to", _to)))
		var hw := _half(f0)
		var top := GROUND if f0 == 1 else _ys[f0 - 1]
		var end := _ys[last] if last < _to else bottom
		left.append_array([Vector2(cx - hw, top), Vector2(cx - hw, end)])
		right.append_array([Vector2(cx + hw, top), Vector2(cx + hw, end)])
		f0 = last + 1
	var shaft := left.duplicate()
	var back := right.duplicate()
	back.reverse()
	shaft.append_array(back)
	draw_colored_polygon(shaft, UiTheme.DEEP)
	var cut := _ys[_to] + 4.0
	for side in [left, right]:
		var solid := PackedVector2Array()
		for pt in side:
			solid.append(Vector2(pt.x, minf(pt.y, cut)))
		draw_polyline(solid, seam, 2.5, true)
		var x: float = side[side.size() - 1].x
		_dashed([Vector2(x, cut), Vector2(x, bottom)], Color(seam, 0.6), 2.5, 3.0, 5.0)
	# bricks down the well's walls
	var well_end := _ys[mini(_to, int(Dungeon.band_of(catalog, 1).get("to", 10)))]
	var k := 0
	var yy := GROUND + 5.0
	while yy < well_end - 2.0:
		var off := 2.0 if k % 2 == 1 else 0.0
		var hw1 := _half(1)
		draw_line(Vector2(cx - hw1 - 8 + off, yy), Vector2(cx - hw1 - 2, yy), Color(seam, 0.5), 2.0)
		draw_line(Vector2(cx + hw1 + 2, yy + 3), Vector2(cx + hw1 + 8 - off, yy + 3), Color(seam, 0.5), 2.0)
		yy += 7.0
		k += 1
	# the rope, down the rope floors
	_curve(Vector2(cx, GROUND - 36.0), Vector2(cx + 4, (GROUND + well_end) / 2.0), Vector2(cx, well_end - 3.0), UiTheme.MUTED, 2.0)

	# the floors
	for f in range(1, _to + 1):
		var y := _ys[f]
		var h := y - _ys[f - 1]
		var hw := _half(f)
		var l := cx - hw
		var r := cx + hw
		var lit := f <= lit_to
		var line_color := lamp if lit else Color(seam, 0.75)
		var line_w := 2.4 if lit else 2.0
		var kind := Dungeon.floor_kind(catalog, f)
		var lamp_x := l + 6.0
		match kind:
			"rope":
				var pts := _quad(Vector2(l + 1, y - 1), Vector2(cx, y + h * 0.55), Vector2(r - 1, y - 1), 10)
				if lit:
					draw_polyline(pts, line_color, line_w, true)
				else:
					_dashed(pts, line_color, line_w)
			"door", "tiny", "knock":
				if lit:
					draw_line(Vector2(l + 1, y), Vector2(r - 1, y), line_color, line_w, true)
				else:
					_dashed([Vector2(l + 1, y), Vector2(r - 1, y)], line_color, line_w)
				var on_left := f % 2 == 1
				var dw := 6.0 if kind == "tiny" else 9.0
				var dh := 8.0 if kind == "tiny" else minf(13.0, h - 4.0)
				var x0 := l + 4.0 if on_left else r - 4.0 - dw
				_door(Vector2(x0, y), dw, dh)
				if kind == "knock":
					var bx := x0 + dw + 3.0 if on_left else x0 - 3.0
					var sgn := 1.0 if on_left else -1.0
					var my := y - dh / 2.0
					_curve(Vector2(bx, my - 3), Vector2(bx + 2 * sgn, my), Vector2(bx, my + 3), Color(UiTheme.LILAC, 0.8), 1.5)
					_curve(Vector2(bx + 3 * sgn, my - 5), Vector2(bx + 6 * sgn, my), Vector2(bx + 3 * sgn, my + 5), Color(UiTheme.LILAC, 0.8), 1.5)
				lamp_x = r - 7.0 if on_left else l + 7.0
			_:  # stairs (and a guard every 10th)
				var y0 := _ys[f - 1]
				var down_right := f % 2 == 1
				var xs := l + 4.0 if down_right else r - 4.0
				var xe := r - 4.0 if down_right else l + 4.0
				var steps := PackedVector2Array([Vector2(xs, y0)])
				var n := 4
				for i in n:
					var p: Vector2 = steps[steps.size() - 1]
					steps.append(Vector2(p.x + (xe - xs) / n, p.y))
					steps.append(Vector2(p.x + (xe - xs) / n, p.y + (y - y0) / n))
				if lit:
					draw_polyline(steps, line_color, line_w, true)
				else:
					_dashed(steps, line_color, line_w)
				lamp_x = l + 6.0 if down_right else r - 6.0
				if kind == "guard" and not Dungeon.is_held(catalog, state, f):  # (a held landing's guard is gone)
					_guard(Vector2(r - 14.0 if down_right else l + 14.0, y))
			# (nothing else is drawn on a floor until it's found)
		if lit and h >= 8.0 and not (_holds.has(f) and Dungeon.held_n(state, f) > 0):  # (a crowd stands there)
			var ly := y - minf(8.0, h - 3.0)
			draw_circle(Vector2(lamp_x, ly), minf(7.0, h / 2.0 + 1.0), Color(lamp, 0.17))
			draw_line(Vector2(lamp_x, ly - 4), Vector2(lamp_x, ly - 2), UiTheme.MUTED, 1.4)
			draw_rect(Rect2(lamp_x - 2, ly - 2, 4, 5), lamp)
		# what a floor gives the first time glints until it's taken (floor 20's key stays hidden; a
		# part only once parts are open, it waits for a clear after that)
		var first: Dictionary = Dungeon.data(catalog).get("firsts", {}).get(str(f), {})
		if first.has("part") and not state.firsts.has(str(f)) and parts_on:
			_spark(Vector2(r - 9.0, y - minf(7.0, h - 4.0)), true)
		# the floor's number, and a feeling word on the next few floors
		var num := str(f)
		var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, Vector2(l - 5.0 - nw, y + 3.0), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, lamp if lit else UiTheme.MUTED)
		if _words.has(f) and (h >= 12.0 or f == int(state.target)):
			var word: Array = _words[f]
			var color := UiTheme.MUTED
			match str(word[1]):
				"mid": color = UiTheme.TEXT
				"hot": color = UiTheme.PINK
			draw_string(font, Vector2(r + 6.0, y + 3.0), str(word[0]), HORIZONTAL_ALIGNMENT_LEFT, w - r - 8.0, 10, color)

	# the target: a pink flag on its landing
	var target := int(state.target)
	if target >= 1 and target <= _to:
		var ty := _ys[target]
		var px := cx + _half(target) - 6.0
		draw_line(Vector2(px, ty - 1), Vector2(px, ty - 13), UiTheme.PINK, 2.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(px, ty - 13), Vector2(px - 8, ty - 10), Vector2(px, ty - 7)]), UiTheme.PINK)

	# band names, up the left edge (only the bands reached)
	for b in Dungeon.data(catalog).bands:
		var from := int(b.from)
		if from > _to:
			continue
		var top := GROUND if from == 1 else _ys[from - 1]
		var end := _ys[mini(_to, int(b.get("to", _to)))]
		var name := str(b.name)
		var nw2 := display.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if end - top < nw2 + 6.0:
			continue
		draw_set_transform(Vector2(16, (top + end) / 2.0), -PI / 2.0)
		draw_string(display, Vector2(-nw2 / 2.0, 0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.LILAC)
		draw_set_transform(Vector2.ZERO)

	_well_mouth(cx, w)
	_thread()

	# the army on its way down: your pet leads
	if _pos >= 0.0 and not _party.is_empty():
		var py := y_at(_pos) - 18.0
		for i in _party.size():
			draw_texture_rect(_party[i], Rect2(Vector2(cx - 22.0 + i * 12.0, py), Vector2(16, 18)), false)


## The coral thread from nail to nail down the lane: solid into a thing that's bought, dashed chalk
## into one that isn't; from the last nail on to each tip.
func _thread() -> void:
	var catalog := GameState.catalog
	var links: Array[String] = []
	var tips: Array[String] = []
	for id in _shown:
		if Perks.is_tip(catalog, id):
			tips.append(id)
		else:
			links.append(id)
	if links.is_empty():
		return
	var on := Color(UiTheme.WISP, 0.55)
	var off := Color(UiTheme.LILAC_SEAM, 0.8)
	var prev := nail_at(links[0])
	for id in links.slice(1):
		var p := nail_at(id)
		var pts := _quad(prev, Vector2((prev.x + p.x) / 2.0 - 8.0, (prev.y + p.y) / 2.0), p, 12)
		if GameState.perk_level(id) > 0:
			draw_polyline(pts, on, 1.6, true)
		else:
			_dashed(pts, off, 1.6, 2.0, 4.0)
		prev = p
	for id in tips:
		var t := nail_at(id)
		draw_polyline(_quad(prev, Vector2(prev.x, t.y - 20.0), t, 12), on, 1.6, true)


func _floor_at(y: float) -> int:
	for f in range(1, _to + 1):
		if _ys[f] >= y:
			return f
	return _to


func _well_mouth(cx: float, w: float) -> void:
	var g := GROUND
	var hw := _half(1)
	var rl := cx - hw - 9.0
	var rr := cx + hw + 9.0
	var mint := UiTheme.MINT
	var grass := PackedVector2Array()
	for i in 41:
		var x := w * i / 40.0
		grass.append(Vector2(x, g - 1.5 * sin(i / 40.0 * TAU * 2.0)))
	draw_polyline(grass, mint, 2.5, true)
	for i in 9:
		var tx := 10.0 + i * (w - 20.0) / 8.0 + (7.0 if i % 2 == 1 else -4.0)
		if tx > rl - 20.0 and tx < rr + 20.0:
			continue
		for d in [Vector2(-3, -6), Vector2(0, -8), Vector2(3, -6)]:
			draw_line(Vector2(tx, g), Vector2(tx, g) + d, Color(mint, 0.8), 2.0, true)
	var lilac := UiTheme.LILAC
	# posts, the roof, the crank
	draw_line(Vector2(rl + 4, g - 12), Vector2(rl + 4, g - 40), lilac, 2.4, true)
	draw_line(Vector2(rr - 4, g - 12), Vector2(rr - 4, g - 40), lilac, 2.4, true)
	var roof := PackedVector2Array([Vector2(rl - 10, g - 38), Vector2(cx, g - 58), Vector2(rr + 10, g - 38)])
	draw_colored_polygon(roof, UiTheme.RAISED.lerp(UiTheme.PINK_SEAM, 0.4))
	roof.append(roof[0])
	draw_polyline(roof, UiTheme.PINK_SEAM, 2.4, true)
	draw_line(Vector2(rl + 4, g - 34), Vector2(rr - 4, g - 34), lilac, 2.4, true)
	draw_circle(Vector2(cx, g - 34), 3.2, UiTheme.RAISED)
	draw_arc(Vector2(cx, g - 34), 3.2, 0, TAU, 16, lilac, 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(rr - 4, g - 34), Vector2(rr + 3, g - 34), Vector2(rr + 3, g - 27)]), lilac, 2.4, true)
	# the stone rim
	var rim := Rect2(rl, g - 14, rr - rl, 14)
	var sb := UiTheme.box(UiTheme.RAISED, lilac, 4, 2, 0)
	draw_style_box(sb, rim)
	for x in [rl + 10.0, rr - 10.0]:
		draw_line(Vector2(x, g - 14), Vector2(x, g - 7), Color(UiTheme.LILAC_SEAM, 0.5), 2.0)
	draw_line(Vector2(cx, g - 7), Vector2(cx, g), Color(UiTheme.LILAC_SEAM, 0.5), 2.0)


func _door(at: Vector2, dw: float, dh: float) -> void:
	var pts := PackedVector2Array([at, Vector2(at.x, at.y - dh + dw / 2.0)])
	for i in range(1, 8):
		var a := PI + PI * i / 8.0
		pts.append(Vector2(at.x + dw / 2.0, at.y - dh + dw / 2.0) + Vector2(cos(a), sin(a)) * dw / 2.0)
	pts.append(Vector2(at.x + dw, at.y - dh + dw / 2.0))
	pts.append(Vector2(at.x + dw, at.y))
	draw_colored_polygon(pts, UiTheme.RAISED)
	pts.append(at)
	draw_polyline(pts, UiTheme.LILAC, 1.7, true)


func _guard(at: Vector2) -> void:
	var body := _quad(Vector2(at.x - 7, at.y), Vector2(at.x - 8, at.y - 13), Vector2(at.x, at.y - 14), 6)
	body.append_array(_quad(Vector2(at.x, at.y - 14), Vector2(at.x + 8, at.y - 13), Vector2(at.x + 7, at.y), 6))
	draw_colored_polygon(body, UiTheme.RAISED)
	body.append(body[0])
	draw_polyline(body, UiTheme.MUTED, 1.7, true)
	draw_line(Vector2(at.x, at.y - 14), Vector2(at.x, at.y - 18), UiTheme.MUTED, 1.4)
	draw_circle(Vector2(at.x - 2.6, at.y - 8), 1.3, UiTheme.PINK)
	draw_circle(Vector2(at.x + 2.6, at.y - 8), 1.3, UiTheme.PINK)


func _spark(c: Vector2, dim: bool) -> void:
	var pts := PackedVector2Array()
	for i in 8:
		var a := -PI / 2.0 + i * PI / 4.0
		pts.append(c + Vector2(cos(a), sin(a)) * (5.0 if i % 2 == 0 else 1.1))
	if dim:
		pts.append(pts[0])
		draw_polyline(pts, Color(UiTheme.GOLD, 0.75), 1.4, true)
	else:
		draw_colored_polygon(pts, UiTheme.GOLD)


func _quad(a: Vector2, c: Vector2, b: Vector2, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


func _curve(a: Vector2, c: Vector2, b: Vector2, color: Color, width: float) -> void:
	draw_polyline(_quad(a, c, b, 8), color, width, true)


func _ellipse(c: Vector2, rx: float, ry: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var a := TAU * i / 12.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, color, width, true)


## A dashed line along points (3 on, 4 off).
func _dashed(points, color: Color, width: float, dash := 3.0, gap := 4.0) -> void:
	var on := true
	var left := dash
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		var d := a.distance_to(b)
		var s := 0.0
		while s < d:
			var step := minf(left, d - s)
			if on:
				draw_line(a.lerp(b, s / d), a.lerp(b, (s + step) / d), color, width)
			s += step
			left -= step
			if left <= 0.001:
				on = not on
				left = dash if on else gap
