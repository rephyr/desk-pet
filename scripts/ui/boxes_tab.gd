class_name BoxesTab
extends VBoxContainer
## Boxes: buying and opening are two things. On the left the shop counter, one row per box tier
## in the shop (sunny, sunset, midnight: data/boxes.json), the newest on top: its map page's stamp,
## the pack (odds on hover), the looks only this tier holds, how many pets are inside, how many to
## buy (1 / 10 / 50 or - +) and buy. A tier comes into the shop when its map page opens, with a gold
## "new!" tag until you buy one, and pops in once with a sparkle while your pet says so. Below, the
## stash: a pile per kind of box on a shelf; click a pile (or "open 1") for the card pack ritual
## (PackOpening; a box with 2-3 pets plays it for the best one, the others are "also inside"),
## "open 10 / all" for a grid of stickers (BoxReveal). The opening takes the counter's and stash's
## place until you're done, so only one opening ever runs. On the right your pet, and once it knows
## the boxes job, its job card: a switch per tier (on: it opens them while you're busy, off: they're
## saved for you), and once it has the piggy bank, whether it buys more when the pile runs out.

const OPEN_MANY := 10
const OPEN_MAX_LIMIT := 500  # "open all" stops here so one click can't hang the game
const QUICK := [1, 10, 50]
const RESERVE_STEP := 50
const STICKER_TILT := [-5.0, 3.0, -2.0]
static var _plain := {}


## The plain pet the "new looks" stickers put each look on (and the "inside" outline): the first
## common part in every slot (data/parts.json).
static func plain() -> Dictionary:
	if _plain.is_empty():
		var catalog := Catalog.shared()
		for slot in Catalog.SLOTS:
			_plain[slot] = catalog.default_part(slot)
	return _plain

var _reveal := BoxReveal.new()
var _opening := PackOpening.new()
var _left := VBoxContainer.new()
var _stash := VBoxContainer.new()
var _counter := VBoxContainer.new()
var _shelf := HBoxContainer.new()
var _side := VBoxContainer.new()
var _sparks := Sparks.new()
var _side_key := ""  # which job card is built (so it's only rebuilt when a layer or a tier opens)
var _shelf_key := ""  # which piles are on the shelf
var _offers := {}  # box id -> { buy, amount: Label, quick: [Buttons], panel, new_tag }
var _piles := {}  # box id -> { pile: PileArt, one, many, all: Button, panel }
var _amount := {}  # box id -> how many the counter buys
var _last_box := ""
var _was_revealing := false
var _greet_pending := true  # check for a tier to greet next frame (set whenever something changed)
var _styles: Array[StyleBoxFlat] = [_offer_style(false), _offer_style(true)]  # an offer row: plain, glowing


func _init() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(cols)
	_left.add_theme_constant_override("separation", 10)
	_left.size_flags_horizontal = SIZE_EXPAND_FILL
	cols.add_child(_left)
	_counter.add_theme_constant_override("separation", 8)
	_left.add_child(_counter)

	# the stash, and the table the opening happens on, in the same spot
	var table := PanelContainer.new()
	table.size_flags_vertical = SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 12))
	_left.add_child(table)
	table.add_child(_stash)
	table.add_child(_reveal)
	table.add_child(_opening)
	_side.custom_minimum_size = Vector2(232, 0)
	_side.add_theme_constant_override("separation", 10)
	cols.add_child(_side)

	# newest tier on top: the one you just earned is the first thing you see
	var tiers := Catalog.shared().shop_boxes()
	tiers.reverse()
	for box in tiers:
		_amount[box.id] = 1
		_counter.add_child(_offer(box))
	_build_stash()
	_sparks.top_level = true  # over everything, placed by hand (not laid out by this box)
	add_child(_sparks)

	_opening.open_again.connect(func(box_id): open(box_id, 1))
	_opening.closed.connect(_show_stash)
	_reveal.again.connect(func(count):
		var box_id: String = _last_box if _last_box != "" else Catalog.shared().boxes[0].id
		var n := mini(mini(count, GameState.in_bag(box_id)), OPEN_MAX_LIMIT)
		if n > 0:
			open(box_id, n))
	_reveal.done.connect(_show_stash)
	_show_stash()
	GameState.changed.connect(_refresh)
	GameState.tutorial_changed.connect(_refresh)
	visibility_changed.connect(func(): _greet_pending = true)
	_refresh()


# ---- the counter ----------------------------------------------------------------

func _offer(box: Dictionary) -> PanelContainer:
	var id: String = box.id
	var panel := PanelContainer.new()
	panel.name = "offer_" + id
	panel.add_theme_stylebox_override("panel", _styles[0])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	# the map page it comes from, as a crayon stamp
	var stamp := Stamp.new(str(box.get("stamp", "house")), 30)
	stamp.tooltip_text = _page_name(str(box.get("page", "")))
	stamp.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(stamp)
	# the pack, with its odds on hover (like the back of a card pack)
	var art := PackArt.rect(box.get("art", {}), 40)
	art.mouse_filter = MOUSE_FILTER_PASS
	art.tooltip_text = _odds_text(box)
	art.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(art)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 5)
	row.add_child(mid)
	# its name (a gold "new!" while it's new), and the looks only this tier holds
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	var title := UiTheme.title(box.name, 16)
	title.size_flags_vertical = SIZE_SHRINK_CENTER
	name_row.add_child(title)
	var new_tag := _new_tag()
	name_row.add_child(new_tag)
	name_row.add_child(UiTheme.spacer())
	var looks := Catalog.shared().new_looks(id)
	if not looks.is_empty():
		for i in looks.size():
			name_row.add_child(_look_sticker(looks[i], STICKER_TILT[i % STICKER_TILT.size()]))
	mid.add_child(name_row)
	# the price, how many to buy at once, and how many pets are inside one
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	quick.add_child(UiTheme.chip("coin", UiTheme.num(int(box.price)), UiTheme.CYAN))
	var chips: Array[Button] = []
	for n in QUICK:
		var chip := UiTheme.filter_chip(str(n), UiTheme.PINK, n == 1)
		chip.name = "amount_%s_%d" % [id, n]
		chip.pressed.connect(func(): _set_amount(id, n))
		quick.add_child(chip)
		chips.append(chip)
	quick.add_child(UiTheme.spacer())
	quick.add_child(Inside.new(box.get("pets", [1, 1])))
	mid.add_child(quick)
	# how many, and the buy button with its price (or why you can't)
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 0)
	stepper.size_flags_vertical = SIZE_SHRINK_CENTER
	var amount := UiTheme.label("1")
	amount.custom_minimum_size = Vector2(28, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stepper.add_child(UiTheme.small_button("−", func(): _set_amount(id, _amount[id] - 1)))
	stepper.add_child(amount)
	stepper.add_child(UiTheme.small_button("+", func(): _set_amount(id, _amount[id] + 1)))
	row.add_child(stepper)
	var buy := _two_line_button(func(): _buy(id))
	buy.button.name = "buy_" + id
	buy.button.custom_minimum_size = Vector2(90, 40)
	buy.button.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(buy.button)
	_offers[id] = { "buy": buy, "amount": amount, "quick": chips, "panel": panel, "new_tag": new_tag, "glow": false }
	return panel


## A new tier's row glows gold until you buy one.
static func _offer_style(glow: bool) -> StyleBoxFlat:
	var sb := UiTheme.sticker(UiTheme.GOLD.lerp(UiTheme.LILAC_SEAM, 0.35) if glow else UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 7)
	sb.content_margin_left = 10
	sb.content_margin_right = 12
	if glow:
		sb.shadow_color = Color(UiTheme.GOLD, 0.3)
		sb.shadow_size = 10
		sb.shadow_offset = Vector2.ZERO
	return sb


## The gold "new!" tag, stuck on a little crooked.
static func _new_tag() -> Control:
	var tag := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 999, 0, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	tag.add_theme_stylebox_override("panel", sb)
	tag.add_child(UiTheme.label("new!", UiTheme.DEEP, UiTheme.SMALL))
	var tilted := Tilted.new(tag, -6.0)
	tilted.size_flags_vertical = SIZE_SHRINK_CENTER
	return tilted


## A tiny sticker of a plain pet wearing one of the looks only this tier holds, named on hover.
static func _look_sticker(look: Dictionary, tilt: float) -> Control:
	var catalog := Catalog.shared()
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 7, 2, 2))
	tile.custom_minimum_size = Vector2(22, 22)
	var parts := plain().duplicate()
	parts[look.slot] = look.id
	var pic := TextureRect.new()
	pic.texture = PetLook.texture_for(parts)
	pic.texture_filter = TEXTURE_FILTER_NEAREST
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	tile.add_child(pic)
	var part := catalog.part(look.slot, look.id)
	tile.tooltip_text = "%s %s" % [part.get("name", look.id), "colours" if look.slot == "palette" else look.slot]
	tile.mouse_filter = MOUSE_FILTER_STOP
	var tilted := Tilted.new(tile, tilt)
	tilted.size_flags_vertical = SIZE_SHRINK_CENTER
	return tilted


func _set_amount(box_id: String, n: int) -> void:
	_amount[box_id] = clampi(n, 1, 999)
	_refresh()


func _buy(box_id: String) -> void:
	var n: int = _amount[box_id]
	if GameState.buy_boxes(box_id, n):
		var box_name := str(Catalog.shared().box(box_id).name)
		PetBubble.say(self, "%d more %ses on the pile!" % [n, box_name] if n > 1 else "a %s for the pile!" % box_name)


static func _page_name(page_id: String) -> String:
	for p in Catalog.shared().pages:
		if p.id == page_id:
			return str(p.name)
	return ""


## What's printed on the back of the pack: the chance of each rarity, then of each finish.
static func _odds_text(box: Dictionary) -> String:
	var catalog := Catalog.shared()
	var lines: Array[String] = ["rarity"]
	var tiers := Weighted.chances(box.tiers)
	for id: String in tiers:
		lines.append("  %s  %s" % [catalog.tier_at(catalog.rank(id)).name, UiTheme.percent(tiers[id])])
	var finishes := Weighted.chances(box.finishes)
	finishes.erase("normal")
	lines.append("finish")
	for id: String in finishes:
		lines.append("  %s  %s" % [catalog.finish(id).name, UiTheme.percent(finishes[id])])
	return "\n".join(lines)


# ---- a tier arriving -------------------------------------------------------------

## A tier that came into the shop pops in with a sparkle the first time you see it, and your pet
## says so (boxes.json "arrives"). Waits while an opening runs or an unlock card is up (returns
## false: try again later).
func _greet_new_tiers() -> bool:
	if not is_visible_in_tree() or not _counter.visible or UnlockPopup.up or is_revealing():
		return false
	for box in GameState.shop_boxes():
		if GameState.boxes_greeted.has(box.id) or Catalog.shared().box_rank(box.id) == 0:
			continue
		GameState.greet_box(box.id)
		var panel: Control = _offers[box.id].panel
		panel.pivot_offset = panel.size / 2.0
		panel.scale = Vector2(0.8, 0.8)
		panel.modulate = Color(1.6, 1.5, 1.2, 0.0)
		var tw := panel.create_tween().set_parallel()
		tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "modulate", Color.WHITE, 0.6)
		_sparks.burst(panel.get_global_rect().get_center(), 18)
		var line := str(box.get("arrives", ""))
		if line != "":
			PetBubble.say(self, line)
		return false  # one at a time: look again for the next one
	return true


# ---- the stash ------------------------------------------------------------------

func _build_stash() -> void:
	_stash.add_theme_constant_override("separation", 2)
	_stash.add_child(UiTheme.title("your stash", 18))
	var grow := Control.new()
	grow.size_flags_vertical = SIZE_EXPAND_FILL
	_stash.add_child(grow)
	_shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	_shelf.add_theme_constant_override("separation", 28)
	_stash.add_child(_shelf)
	# the shelf the piles stand on
	var plank := Control.new()
	plank.custom_minimum_size = Vector2(0, 12)
	plank.draw.connect(func(): plank.draw_line(Vector2(0, 7), Vector2(plank.size.x, 7), UiTheme.PINK_SEAM, 4.0))
	_stash.add_child(plank)


## Puts a pile on the shelf for every kind of box on the stash (rebuilt when one comes or goes).
func _build_shelf() -> void:
	var stash := GameState.stash_boxes()
	var key := str(stash.map(func(b): return b.id))
	if key == _shelf_key:
		return
	_shelf_key = key
	UiTheme.clear(_shelf)
	_piles.clear()
	var small := stash.size() > 1
	for box in stash:
		_shelf.add_child(_pile(box, small))


func _pile(box: Dictionary, small: bool) -> Control:
	var id: String = box.id
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	var pile := PileArt.new(box, 48 if small else 64)
	pile.name = "pile_" + id
	pile.size_flags_horizontal = SIZE_SHRINK_CENTER
	pile.clicked.connect(func(): open(id, 1))
	col.add_child(pile)
	var title := UiTheme.title(box.name, 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var word := UiTheme.label("open", UiTheme.MUTED, UiTheme.SMALL)
	word.size_flags_vertical = SIZE_SHRINK_CENTER
	buttons.add_child(word)
	var one := UiTheme.button("1", func(): open(id, 1))
	var many := UiTheme.button(str(OPEN_MANY), func(): open(id, OPEN_MANY))
	var all := UiTheme.button("all", func(): open(id, mini(GameState.in_bag(id), OPEN_MAX_LIMIT)))
	one.name = "open_%s_1" % id
	many.name = "open_%s_%d" % [id, OPEN_MANY]
	all.name = "open_%s_all" % id
	for b in [one, many, all]:
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		b.custom_minimum_size = Vector2(30, 0)
		buttons.add_child(b)
	col.add_child(buttons)
	_piles[id] = { "pile": pile, "one": one, "many": many, "all": all, "panel": col, "word": word }
	return col


## A pile of card packs on the shelf, as many as you have (a few drawn, the rest counted). Empty,
## it's a dashed spot. A pile your pet leaves for you has a "saved for you" tag.
class PileArt extends Control:
	signal clicked

	const SHOWN := 6
	const TILTS := [-0.1, 0.07, -0.04, 0.12, -0.07, 0.03]
	const SHIFT := [-8.0, 7.0, -3.0, 9.0, -5.0, 0.0]

	var box: Dictionary
	var count := 0
	var saved := false
	var w := 64

	func _init(for_box: Dictionary, pack_width := 64) -> void:
		box = for_box
		w = pack_width
		custom_minimum_size = Vector2(w * 2.0, w * 1.3 + (SHOWN - 1) * w / 8.0 + 16.0)
		mouse_filter = MOUSE_FILTER_STOP

	func set_state(n: int, is_saved: bool) -> void:
		count = n
		saved = is_saved
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if n > 0 else CURSOR_ARROW
		tooltip_text = "open one" if n > 0 else ""
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if count > 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()

	func _draw() -> void:
		var font := UiTheme.BODY_FONT
		var k := w / 64.0
		var step := w / 8.0
		if count <= 0:
			var r := Rect2(size.x / 2.0 - 40.0 * k, size.y - 104.0 * k, 80.0 * k, 100.0 * k)
			draw_style_box(UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 10, 0), r)
			var t := "none yet"
			var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x
			draw_string(font, Vector2(size.x / 2.0 - tw / 2.0, r.get_center().y + 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.MUTED)
			return
		var tex := PackArt.texture(box.get("art", {}), w)
		var pack := Vector2(w, w * 1.3)
		for i in mini(count, SHOWN):
			var at := Vector2(size.x / 2.0 + SHIFT[i] * k, size.y - pack.y / 2.0 - 2.0 - i * step)
			draw_set_transform(at, TILTS[i])
			draw_texture_rect(tex, Rect2(-pack / 2.0, pack), false)
		draw_set_transform(Vector2.ZERO)
		# how many, as a badge on the top pack
		var badge := "×%s" % UiTheme.num(count)
		var fs := 14 if w >= 60 else 13
		var bw := UiTheme.DISPLAY_FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
		var top := size.y - pack.y - 2.0 - (mini(count, SHOWN) - 1) * step
		var br := Rect2(minf(size.x / 2.0 + 18.0 * k, size.x - bw), maxf(top - 8.0, 0.0), bw, 21.0)
		draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.PINK_SEAM, 11, 2, 0), br)
		draw_string(UiTheme.DISPLAY_FONT, br.position + Vector2(8, 15), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
		if saved:
			var tag := "saved for you"
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x + 16.0
			draw_set_transform(Vector2(0, top + pack.y * 0.5 + 8.0), -0.14)
			var tr := Rect2(0, 0, tw, 18.0)
			draw_style_box(UiTheme.stitched(UiTheme.GOLD, UiTheme.DEEP, 9, 0), tr)
			draw_string(font, Vector2(8, 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.GOLD)
			draw_set_transform(Vector2.ZERO)


## A map page's crayon doodle in a dashed circle, stuck on a little crooked (a tier's stamp).
class Stamp extends Control:
	var kind := ""
	var d := 30.0

	func _init(doodle: String, diameter := 30.0) -> void:
		kind = doodle
		d = diameter
		custom_minimum_size = Vector2(d, d)
		mouse_filter = MOUSE_FILTER_STOP

	func _draw() -> void:
		var c := size / 2.0
		var color := UiTheme.LILAC
		# the dashed ring
		var n := 14
		for i in n:
			var a0 := TAU * i / n - 0.14
			draw_arc(c, d / 2.0 - 1.5, a0, a0 + TAU / n * 0.55, 4, UiTheme.LILAC_SEAM, 2.0, true)
		# the doodle, drawn big and scaled down so its crayon lines stay thin
		var k := (d * 0.62) / 48.0
		draw_set_transform(c, deg_to_rad(-8.0), Vector2(k, k))
		Crayon.doodle(self, kind, Vector2.ZERO, 1.0, color, 7)
		draw_set_transform(Vector2.ZERO)


## How many pets are in one box, as little pet shapes: the ones there might not be are fainter.
class Inside extends Control:
	var _shape: ImageTexture
	var least := 1
	var most := 1

	func _init(pets: Array) -> void:
		least = int(pets[0])
		most = int(pets[pets.size() - 1])
		custom_minimum_size = Vector2(most * 15 + 2, 20)
		mouse_filter = MOUSE_FILTER_STOP
		tooltip_text = ("%d pets inside" % least if least == most else "%d-%d pets inside" % [least, most]) if most > 1 else "a pet inside"

	func _draw() -> void:
		var tex := _silhouette()
		for i in most:
			var a := 0.42 if i < least else 0.2
			draw_texture(tex, Vector2(i * 15, size.y - tex.get_height()), Color(UiTheme.TEXT, a))

	## A plain pet's outline, filled flat white (tinted when drawn).
	func _silhouette() -> ImageTexture:
		if _shape == null:
			var img := PetLook.texture_for(BoxesTab.plain()).get_image()
			img.convert(Image.FORMAT_RGBA8)
			for y in img.get_height():
				for x in img.get_width():
					if img.get_pixel(x, y).a > 0.1:
						img.set_pixel(x, y, Color.WHITE)
			_shape = ImageTexture.create_from_image(img)
		return _shape


## A little burst of sparkles, drawn over the tab.
class Sparks extends Control:
	var _bits: Array[Dictionary] = []  # { at, v, age }

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		set_process(false)

	func burst(at: Vector2, n: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		size = get_viewport_rect().size
		for i in n:
			var a := rng.randf() * TAU
			_bits.append({ "at": at, "v": Vector2(cos(a), sin(a)) * rng.randf_range(40.0, 110.0), "age": 0.0 })
		set_process(true)

	func _process(delta: float) -> void:
		for b in _bits:
			b.age += delta
			b.at += b.v * delta
			b.v *= 0.93
		_bits = _bits.filter(func(b): return b.age < 0.9)
		if _bits.is_empty():
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		for b in _bits:
			var t: float = b.age / 0.9
			var r := 3.5 * (1.0 - t) + 1.0
			var col := Color(UiTheme.GOLD, 1.0 - t)
			draw_line(b.at - Vector2(r, 0), b.at + Vector2(r, 0), col, 2.0)
			draw_line(b.at - Vector2(0, r), b.at + Vector2(0, r), col, 2.0)


# ---- your pet and its job -------------------------------------------------------

## Builds the right column for what your pet can do: just watching, opening the pile, or buying too.
func _build_side() -> void:
	var tiers := GameState.stash_boxes().map(func(b): return b.id)
	var key := "%s|%s|%s|%s" % [GameState.knows_job("boxes"), GameState.feature_on("shopping"), GameState.packs_on, str(tiers)]
	if key == _side_key:
		return
	_side_key = key
	UiTheme.clear(_side)
	var pet := GameState.collection.active()
	var who := pet.display_name(Catalog.shared()) if pet else "your pet"
	if not GameState.knows_job("boxes"):
		var portrait := PetPortrait.new(5)
		portrait.set_pet(pet)
		portrait.size_flags_horizontal = SIZE_SHRINK_CENTER
		_side.add_child(portrait)
		var line := UiTheme.label("so many boxes!! open one, open one!", UiTheme.MUTED, UiTheme.SMALL + 1)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_side.add_child(line)
	else:
		_side.add_child(_job_card(pet, who))
	if OS.is_debug_build():
		_side.add_child(_dev_buttons())


func _job_card(pet: Pet, who: String) -> PanelContainer:
	var shopping := GameState.feature_on("shopping")
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var portrait := PetPortrait.new(2)
	portrait.set_pet(pet)
	head.add_child(portrait)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	var who_label := UiTheme.label(who, UiTheme.PINK)
	who_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	who_label.clip_text = true
	words.add_child(who_label)
	var does := UiTheme.label("buying and opening boxes" if shopping else "opening boxes", UiTheme.MUTED, UiTheme.SMALL)
	does.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(does)
	head.add_child(words)
	var on := CheckButton.new()
	on.name = "boxes_job"
	on.focus_mode = FOCUS_NONE
	on.button_pressed = GameState.packs_on
	on.toggled.connect(func(v): GameState.set_job("packs", v))
	head.add_child(on)
	col.add_child(head)
	# a switch per tier: on, your pet opens them; off, they wait on the pile for you
	var lets := PanelContainer.new()
	lets.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 6))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	lets.add_child(rows)
	for box in GameState.stash_boxes():
		var id: String = box.id
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var sw := CheckButton.new()
		sw.name = "let_" + id
		sw.focus_mode = FOCUS_NONE
		sw.button_pressed = GameState.pet_opens(id)
		sw.toggled.connect(func(v): GameState.save_for_me(id, not v))
		row.add_child(sw)
		var stamp := Stamp.new(str(box.get("stamp", "house")), 22)
		stamp.size_flags_vertical = SIZE_SHRINK_CENTER
		stamp.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(stamp)
		var name_label := UiTheme.label(box.name, UiTheme.TEXT, UiTheme.SMALL + 1)
		name_label.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(name_label)
		rows.add_child(row)
	col.add_child(lets)
	if shopping:
		col.add_child(UiTheme.stitch_line())
		var buys := CheckButton.new()
		buys.text = "buy more when the pile runs out"
		buys.focus_mode = FOCUS_NONE
		buys.button_pressed = GameState.buying_on
		buys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buys.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		buys.toggled.connect(func(v): GameState.set_job("buying", v))
		col.add_child(buys)
		var keep := HBoxContainer.new()
		keep.add_theme_constant_override("separation", 4)
		keep.add_child(UiTheme.label("keep at least", UiTheme.TEXT, UiTheme.SMALL + 1))
		keep.add_child(UiTheme.spacer())
		var kept := UiTheme.label(str(GameState.coin_reserve), UiTheme.CYAN)
		kept.custom_minimum_size = Vector2(44, 0)
		kept.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var step := func(d: int):
			GameState.coin_reserve = maxi(0, GameState.coin_reserve + d)
			kept.text = str(GameState.coin_reserve)
			GameState.save_game()
		keep.add_child(UiTheme.small_button("−", step.bind(-RESERVE_STEP)))
		keep.add_child(kept)
		keep.add_child(UiTheme.small_button("+", step.bind(RESERVE_STEP)))
		col.add_child(keep)
	return card


## Debug only: open one box at a chosen rarity, to test each reveal (puts a box on the pile first).
func _dev_buttons() -> VBoxContainer:
	var catalog := Catalog.shared()
	var box_id: String = catalog.boxes[0].id
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.add_child(UiTheme.label("dev: open one %s at" % catalog.boxes[0].name, UiTheme.MUTED, UiTheme.SMALL))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for tier in catalog.tiers:
		var b := UiTheme.button(tier.name, func():
			GameState.debug_give_box(box_id)
			open(box_id, 1, tier.id))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		b.add_theme_color_override("font_color", catalog.tier_color(tier.id))
		grid.add_child(b)
	col.add_child(grid)
	return col


# ---- opening --------------------------------------------------------------------

## Opens boxes from your stash, then plays the reveal. `force_tier` is for testing (debug builds only).
func open(box_id: String, count: int, force_tier := "") -> void:
	# one opening at a time: starting another mid-ritual would cut the first one off
	if is_revealing():
		return
	_last_box = box_id
	var pulled := GameState.open_boxes(box_id, count, force_tier)
	if pulled.is_empty():
		return
	_stash.visible = false
	_counter.visible = false  # the opening gets the whole height, so its light has room
	_opening.visible = count == 1
	_reveal.visible = count > 1
	if count == 1:
		# one box: the ritual for the best pet in it, the others show on its result card
		var best := BoxShop.best_first(pulled, Catalog.shared())
		# in the tutorial the pet inside talks while you open its box
		var talk: Array = Catalog.shared().tutorial.box_talk
		var nth := GameState.collection.pets.size() - 1
		_opening.box_talk = talk[nth] if GameState.tutorial_active() and nth < talk.size() else []
		_opening.play(best[0], box_id, best.slice(1))
	else:
		_reveal.play(pulled, count)


func _show_stash() -> void:
	_stash.visible = true
	_opening.visible = false
	_reveal.visible = false
	_refresh()


## Whether a box is being opened right now (the pack is mid-ritual).
func is_revealing() -> bool:
	return _opening.visible and _opening.is_busy()


## The tutorial's "open a box" button: the starter pile's "open 1".
func tutorial_target() -> Control:
	_build_shelf()
	return _piles[Catalog.shared().boxes[0].id].one


func _process(_delta: float) -> void:
	var busy := is_revealing()
	if busy != _was_revealing:
		_was_revealing = busy
		_refresh()
	if _greet_pending:
		_greet_pending = not _greet_new_tiers()


func _refresh() -> void:
	_build_side()
	_build_shelf()
	var learning := GameState.tutorial_active()
	# hidden while opening (the opening gets the whole height), and in the tutorial: its two boxes
	# are a gift, nothing to buy yet
	_counter.visible = _stash.visible and not learning
	for box_id in _offers:
		var o: Dictionary = _offers[box_id]
		var in_shop := GameState.box_in_shop(box_id)
		o.panel.visible = in_shop
		if not in_shop:
			continue
		var is_new := GameState.box_is_new(box_id)
		o.new_tag.visible = is_new
		if is_new != o.glow:
			o.glow = is_new
			o.panel.add_theme_stylebox_override("panel", _styles[1 if is_new else 0])
		var n: int = _amount[box_id]
		o.amount.text = str(n)
		for i in QUICK.size():
			o.quick[i].set_pressed_no_signal(QUICK[i] == n)
		var short := GameState.coins_short(box_id, n)
		o.buy.top.text = "buy %d" % n
		o.buy.button.disabled = short > 0
		o.buy.button.tooltip_text = "you need %s more coins" % UiTheme.num(short) if short > 0 else ""
		o.buy.small.text = "need %s more" % UiTheme.num(short) if short > 0 else "%s coins" % UiTheme.num(GameState.box_price(box_id, n))
		o.buy.small.add_theme_color_override("font_color", UiTheme.LILAC if short > 0 else UiTheme.CYAN)
	for box_id in _piles:
		var p: Dictionary = _piles[box_id]
		var have := GameState.in_bag(box_id)
		p.pile.set_state(have, GameState.knows_job("boxes") and not GameState.pet_opens(box_id))
		p.one.disabled = have < 1
		p.many.disabled = have < OPEN_MANY
		p.all.disabled = have < 2
		for b in [p.one, p.many, p.all]:
			b.tooltip_text = "only %d on the pile" % have if b.disabled and have > 0 else ""
		# the tutorial is one starter box at a time
		p.panel.visible = not learning or box_id == Catalog.shared().boxes[0].id
		p.many.visible = not learning
		p.all.visible = not learning
	if _last_box != "":
		_reveal.set_can_open(GameState.in_bag(_last_box))
	_greet_pending = true


## A two-line button: what it does, and under it the cost (or why you can't).
func _two_line_button(on_pressed: Callable) -> Dictionary:
	var b := UiTheme.button("", on_pressed)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.set_anchors_preset(PRESET_FULL_RECT)
	var top := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	var small := UiTheme.label("", UiTheme.CYAN, UiTheme.SMALL)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	b.add_child(col)
	return { "button": b, "small": small, "top": top }
