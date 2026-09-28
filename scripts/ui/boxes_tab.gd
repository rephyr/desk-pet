class_name BoxesTab
extends VBoxContainer
## Boxes: buying and opening are two things. Along the top a shop counter, one row per box: pick
## how many (1 / 10 / 50 or - +) and buy, and they land on your stash. Below, the stash: a pile
## per kind of box on a shelf; click a pile (or "open 1") for the card pack ritual (PackOpening),
## "open 10 / all" for a grid of stickers (BoxReveal). The opening takes the stash's place until
## you're done, so only one opening ever runs. On the right your pet, and once it has its cushion,
## its job card: which piles it may open while you're busy, and once it has the piggy bank,
## whether it buys more when the pile runs out (keeping the coins you set aside).

const OPEN_MANY := 10
const OPEN_MAX_LIMIT := 500  # "open all" stops here so one click can't hang the game
const QUICK := [1, 10, 50]
const RESERVE_STEP := 50

var _reveal := BoxReveal.new()
var _opening := PackOpening.new()
var _stash := VBoxContainer.new()
var _counter := HBoxContainer.new()
var _side := VBoxContainer.new()
var _side_key := ""  # which job card is built (so it's only rebuilt when a layer opens)
var _offers := {}  # box id -> { buy, amount: Label, quick: [Buttons] }
var _piles := {}  # box id -> { pile: PileArt, one, many, all: Button, hint: Label, panel }
var _amount := {}  # box id -> how many the counter buys
var _last_box := ""
var _was_revealing := false


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = SIZE_EXPAND_FILL
	_counter.add_theme_constant_override("separation", 12)
	add_child(_counter)
	var low := HBoxContainer.new()
	low.add_theme_constant_override("separation", 12)
	low.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(low)

	# the stash, and the table the opening happens on, in the same spot
	var table := PanelContainer.new()
	table.size_flags_horizontal = SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 14))
	low.add_child(table)
	table.add_child(_stash)
	table.add_child(_reveal)
	table.add_child(_opening)
	_side.custom_minimum_size = Vector2(232, 0)
	_side.add_theme_constant_override("separation", 12)
	low.add_child(_side)

	for box in Catalog.shared().boxes:
		if not box.get("hidden", false):
			_amount[box.id] = 1
			_counter.add_child(_offer(box))
	_build_stash()

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
	_refresh()


# ---- the counter ----------------------------------------------------------------

func _offer(box: Dictionary) -> PanelContainer:
	var catalog := Catalog.shared()
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	# the pack, with its odds on hover (like the back of a card pack)
	var art := PackArt.rect(box.get("art", {}), 44)
	art.mouse_filter = MOUSE_FILTER_PASS
	art.tooltip_text = _odds_text(box)
	row.add_child(art)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 6)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.add_child(UiTheme.title(box.name, 16))
	mid.add_child(name_row)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 4)
	quick.add_child(UiTheme.chip("coin", str(int(box.price)), UiTheme.CYAN))
	var chips: Array[Button] = []
	for n in QUICK:
		var chip := UiTheme.filter_chip(str(n), UiTheme.PINK, n == 1)
		chip.pressed.connect(func(): _set_amount(box.id, n))
		quick.add_child(chip)
		chips.append(chip)
	mid.add_child(quick)
	row.add_child(mid)
	# how many, and the buy button with its price (or why you can't)
	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_theme_constant_override("separation", 4)
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 0)
	stepper.alignment = BoxContainer.ALIGNMENT_END
	var amount := UiTheme.label("1")
	amount.custom_minimum_size = Vector2(34, 0)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stepper.add_child(UiTheme.small_button("−", func(): _set_amount(box.id, _amount[box.id] - 1)))
	stepper.add_child(amount)
	stepper.add_child(UiTheme.small_button("+", func(): _set_amount(box.id, _amount[box.id] + 1)))
	right.add_child(stepper)
	var buy := _two_line_button(func(): _buy(box.id))
	buy.button.custom_minimum_size = Vector2(100, 40)
	right.add_child(buy.button)
	row.add_child(right)
	_offers[box.id] = { "buy": buy, "amount": amount, "quick": chips, "panel": panel }
	return panel


func _set_amount(box_id: String, n: int) -> void:
	_amount[box_id] = clampi(n, 1, 999)
	_refresh()


func _buy(box_id: String) -> void:
	var n: int = _amount[box_id]
	if GameState.buy_boxes(box_id, n):
		var box_name := str(Catalog.shared().box(box_id).name)
		PetBubble.say(self, "%d more %ses on the pile!" % [n, box_name] if n > 1 else "a %s for the pile!" % box_name)


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


# ---- the stash ------------------------------------------------------------------

func _build_stash() -> void:
	_stash.add_theme_constant_override("separation", 2)
	_stash.add_child(UiTheme.title("your stash", 18))
	_stash.add_child(UiTheme.label("click a pile to open one", UiTheme.MUTED, UiTheme.SMALL + 1))
	var grow := Control.new()
	grow.size_flags_vertical = SIZE_EXPAND_FILL
	_stash.add_child(grow)
	var shelf := HBoxContainer.new()
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override("separation", 24)
	_stash.add_child(shelf)
	for box in Catalog.shared().boxes:
		if not box.get("hidden", false):
			shelf.add_child(_pile(box))
	# the shelf the piles stand on
	var plank := Control.new()
	plank.custom_minimum_size = Vector2(0, 14)
	plank.draw.connect(func(): plank.draw_line(Vector2(0, 8), Vector2(plank.size.x, 8), UiTheme.PINK_SEAM, 4.0))
	_stash.add_child(plank)


func _pile(box: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	var pile := PileArt.new(box)
	pile.size_flags_horizontal = SIZE_SHRINK_CENTER
	pile.clicked.connect(func(): open(box.id, 1))
	col.add_child(pile)
	var title := UiTheme.title(box.name, 15)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	var one := UiTheme.button("open 1", func(): open(box.id, 1))
	var many := UiTheme.button("open %d" % OPEN_MANY, func(): open(box.id, OPEN_MANY))
	var all := UiTheme.button("open all", func(): open(box.id, mini(GameState.in_bag(box.id), OPEN_MAX_LIMIT)))
	for b in [one, many, all]:
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		buttons.add_child(b)
	col.add_child(buttons)
	_piles[box.id] = { "pile": pile, "one": one, "many": many, "all": all, "panel": col }
	return col


## A pile of card packs on the shelf, as many as you have (a few drawn, the rest counted). Empty,
## it's a dashed spot. A pile your pet leaves for you has a "saved for you" tag.
class PileArt extends Control:
	signal clicked

	const W := 64
	const SHOWN := 6
	const TILTS := [-0.1, 0.07, -0.04, 0.12, -0.07, 0.03]
	const SHIFT := [-8.0, 7.0, -3.0, 9.0, -5.0, 0.0]

	var box: Dictionary
	var count := 0
	var saved := false

	func _init(for_box: Dictionary) -> void:
		box = for_box
		custom_minimum_size = Vector2(130, 140)
		mouse_filter = MOUSE_FILTER_STOP

	func set_state(n: int, is_saved: bool) -> void:
		count = n
		saved = is_saved
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if n > 0 else CURSOR_ARROW
		tooltip_text = "open one" if n > 0 else "buy some at the counter"
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if count > 0 and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()

	func _draw() -> void:
		var font := UiTheme.BODY_FONT
		if count <= 0:
			var r := Rect2(size.x / 2.0 - 40.0, size.y - 104.0, 80.0, 100.0)
			draw_style_box(UiTheme.stitched(UiTheme.LINE, Color(0, 0, 0, 0), 10, 0), r)
			var t := "none yet"
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x
			draw_string(font, Vector2(size.x / 2.0 - w / 2.0, r.get_center().y + 4.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.MUTED)
			return
		var tex := PackArt.texture(box.get("art", {}), W)
		var pack := Vector2(W, W * 1.3)
		for i in mini(count, SHOWN):
			var at := Vector2(size.x / 2.0 + SHIFT[i], size.y - pack.y / 2.0 - 2.0 - i * 8.0)
			draw_set_transform(at, TILTS[i])
			draw_texture_rect(tex, Rect2(-pack / 2.0, pack), false)
		draw_set_transform(Vector2.ZERO)
		# how many, as a badge on the top pack
		var badge := "×%d" % count
		var bw := UiTheme.DISPLAY_FONT.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 18.0
		var top := size.y - pack.y - 2.0 - (mini(count, SHOWN) - 1) * 8.0
		var br := Rect2(size.x / 2.0 + 18.0, top - 8.0, bw, 22.0)
		draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.PINK_SEAM, 11, 2, 0), br)
		draw_string(UiTheme.DISPLAY_FONT, br.position + Vector2(9, 16), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.TEXT)
		if saved:
			var tag := "saved for you"
			var tw := font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL).x + 16.0
			draw_set_transform(Vector2(2, top + 22.0), -0.14)
			var tr := Rect2(0, 0, tw, 18.0)
			draw_style_box(UiTheme.stitched(UiTheme.GOLD, UiTheme.DEEP, 9, 0), tr)
			draw_string(font, Vector2(8, 13), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL, UiTheme.GOLD)
			draw_set_transform(Vector2.ZERO)


# ---- your pet and its job -------------------------------------------------------

## Builds the right column for what your pet can do: just watching, opening the pile, or buying too.
func _build_side() -> void:
	var key := "%s|%s|%s" % [GameState.knows_job("boxes"), GameState.feature_on("shopping"), GameState.packs_on]
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
	words.add_child(UiTheme.label("%s helps" % who, UiTheme.PINK))
	var does := UiTheme.label("buys and opens while you're busy" if shopping else "opens your pile while you're busy", UiTheme.MUTED, UiTheme.SMALL)
	does.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(does)
	head.add_child(words)
	var on := CheckButton.new()
	on.focus_mode = FOCUS_NONE
	on.button_pressed = GameState.packs_on
	on.tooltip_text = "your pet opens boxes while the game sits small in the corner"
	on.toggled.connect(func(v): GameState.set_job("packs", v))
	head.add_child(on)
	col.add_child(head)
	for box in Catalog.shared().boxes:
		if box.get("hidden", false):
			continue
		var id: String = box.id
		col.add_child(UiTheme.label("%ses" % box.name, UiTheme.TEXT, UiTheme.SMALL + 1))
		col.add_child(UiTheme.segmented(["pet opens", "save for me"], 0 if GameState.pet_opens(id) else 1,
			func(i): GameState.save_for_me(id, i == 1)))
	if shopping:
		col.add_child(UiTheme.stitch_line())
		var buys := CheckButton.new()
		buys.text = "buy more when the pile runs out"
		buys.focus_mode = FOCUS_NONE
		buys.button_pressed = GameState.buying_on
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
		keep.add_child(UiTheme.label("coins", UiTheme.MUTED, UiTheme.SMALL))
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
	_opening.visible = pulled.size() == 1
	_reveal.visible = pulled.size() > 1
	if pulled.size() == 1:
		# in the tutorial the pet inside talks while you open its box
		var talk: Array = Catalog.shared().tutorial.box_talk
		var nth := GameState.collection.pets.size() - 1
		_opening.box_talk = talk[nth] if GameState.tutorial_active() and nth < talk.size() else []
		_opening.play(pulled[0], box_id)
	else:
		_reveal.play(pulled)


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
	return _piles[Catalog.shared().boxes[0].id].one


func _process(_delta: float) -> void:
	var busy := is_revealing()
	if busy != _was_revealing:
		_was_revealing = busy
		_refresh()


func _refresh() -> void:
	_build_side()
	var learning := GameState.tutorial_active()
	# hidden while opening (the opening gets the whole height), and in the tutorial: its two boxes
	# are a gift, nothing to buy yet
	_counter.visible = _stash.visible and not learning
	for box_id in _offers:
		var o: Dictionary = _offers[box_id]
		var n: int = _amount[box_id]
		o.amount.text = str(n)
		for i in QUICK.size():
			o.quick[i].set_pressed_no_signal(QUICK[i] == n)
		var short := GameState.coins_short(box_id, n)
		o.buy.top.text = "buy %d" % n
		o.buy.button.disabled = short > 0
		o.buy.button.tooltip_text = "you need %d more coins" % short if short > 0 else ""
		o.buy.small.text = "need %d more" % short if short > 0 else "%d coins" % GameState.box_price(box_id, n)
		o.buy.small.add_theme_color_override("font_color", UiTheme.LILAC if short > 0 else UiTheme.CYAN)
	for box_id in _piles:
		var p: Dictionary = _piles[box_id]
		var have := GameState.in_bag(box_id)
		p.pile.set_state(have, GameState.knows_job("boxes") and not GameState.pet_opens(box_id))
		p.one.disabled = have < 1
		p.many.disabled = have < OPEN_MANY
		p.all.disabled = have < 2
		for b in [p.one, p.many, p.all]:
			b.tooltip_text = "buy some at the counter" if have < 1 else ("only %d on the pile" % have if b.disabled else "")
		# the tutorial is one starter box at a time
		p.panel.visible = not learning or box_id == Catalog.shared().boxes[0].id
		p.many.visible = not learning
		p.all.visible = not learning
	if _last_box != "":
		_reveal.set_can_open(GameState.in_bag(_last_box))


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
