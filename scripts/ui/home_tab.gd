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

signal go(tab_name: String)  # a note was tapped: show that tab
signal open_box(box_id: String)

const FLOOR := 0.64  # where the floor starts, as a share of the height
const PILE_SHOWN := 9  # packs drawn on the pile at most (the badge counts the rest)
const PACK_W := 40

var _pet := PetPortrait.new(6, true)
var _name := UiTheme.title("", 18)
var _food := UiTheme.bar(UiTheme.PINK)
var _mood := UiTheme.bar(UiTheme.LILAC)
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
		if _work.tap():
			return  # seen it! the good pull goes to the collection
		GameState.pat()
		_pet.view.squash = 0.6
		PetBubble.say_line(self, "pat"))
	_pet.tooltip_text = "pat me!"
	add_child(_pet)
	_work.speed = 90.0
	_held.pixel = 4
	_held.visible = false
	add_child(_held)
	_front.draw.connect(_draw_front)
	add_child(_front)

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
	var feed := UiTheme.button("feed %d" % GameState.FEED_COST, func(): GameState.feed())
	feed.icon = UiTheme.icon("coin", 14)
	feed.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	feed.add_theme_constant_override("icon_max_width", 14)
	feed.add_theme_color_override("icon_normal_color", Color.WHITE)
	feed.add_theme_color_override("icon_hover_color", Color.WHITE)
	buttons.add_child(feed)
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
	var tilts := { "trips": -2.0, "boxes": 1.5, "parts": 2.0, "map": -1.5 }
	for n in ["trips", "boxes", "parts", "map"]:
		_notes.add_child(Tilted.new(_note(n), tilts[n]))

	resized.connect(_layout)
	GameState.changed.connect(func(): _dirty = true)
	GameState.adventures_changed.connect(func(): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_refresh()
			speak())


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_food.value = GameState.hunger
	_mood.value = GameState.happiness
	if _dirty:
		_refresh()
	_step_work(delta)


# ---- your pet opening the pile ------------------------------------------------------

func _step_work(delta: float) -> void:
	if _pet.view.pet == null or size.x <= 0.0:
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


# ---- the room -----------------------------------------------------------------

func _layout() -> void:
	var floor_y := size.y * FLOOR
	var feet := _feet()
	_pet.size = _pet.custom_minimum_size
	# the portrait draws its pet standing on its bottom edge (less a pixel of margin)
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
	var accent: Color = { "trips": UiTheme.MINT, "boxes": UiTheme.CYAN, "parts": UiTheme.LILAC, "map": UiTheme.GOLD }[note_name]
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
		"trips", "map":
			go.emit("adventures")
		"parts":
			go.emit("inventory")
		"boxes":
			var owned := _first_box_in_bag()
			if owned != "":
				open_box.emit(owned)
			else:
				go.emit("boxes")


## What each note says right now; notes with nothing waiting fade back a little.
func _refresh() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	var pet := GameState.collection.active()
	_pet.set_pet(pet)
	_name.text = pet.display_name(catalog) if pet else ""

	var back := GameState.runs.filter(func(r): return r.status == RunState.Status.DONE).size()
	var waiting := GameState.runs.filter(func(r): return r.status == RunState.Status.WAITING).size()
	var away := GameState.runs.size()
	if back > 0:
		_set_note("trips", "%d back home!" % back if back > 1 else "someone's back home!", "say welcome back", true)
	elif waiting > 0:
		_set_note("trips", "%d waiting for you" % waiting, "pick what to do", true)
	elif away > 0:
		_set_note("trips", "%d out and about" % away, "watch them go", false)
	else:
		_set_note("trips", "nobody's away", "send someone", false)

	var boxes := 0
	for box_id in GameState.bag:
		boxes += GameState.in_bag(box_id)
	if GameState.can_auto_open() and boxes > 0:
		_set_note("boxes", "%s is opening the pile" % _name.text, "%d left" % boxes, true)
	else:
		_set_note("boxes", "%d boxes on your pile" % boxes if boxes > 0 else "your pile is empty", "open them" if boxes > 0 else "buy some", boxes > 0)

	var parts := 0
	for key in GameState.parts:
		parts += int(GameState.parts[key])
	_set_note("parts", "%d parts to sew on" % parts if parts > 0 else "no parts yet", "try them on" if parts > 0 else "pets find them on trips", parts > 0)
	_note_parts.parts.panel.get_parent().visible = GameState.tab_open("inventory")

	var ready := GameState.spotted.size() + GameState.rumours.size()
	_set_note("map", "somewhere new to go!" if ready > 0 else "the map", "go and look" if ready > 0 else "plan a trip", ready > 0)

	for id in _finds:
		_finds[id].visible = GameState.finds.has(id)
		_finds[id].tooltip_text = "%s, found on a trip" % catalog.finds.get(id, {}).get("name", id)
	_layout()


func _set_note(note_name: String, line: String, hint: String, waiting: bool) -> void:
	var n: Dictionary = _note_parts[note_name]
	n.line.text = line
	n.hint.text = hint
	n.panel.modulate.a = 1.0 if waiting else 0.62


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
	else:
		var what := PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog)
		GameState.news = {}
		PetBubble.say(self, PetVoice.line(pet, what, _rng, catalog))
	_pet.view.squash = 0.4
