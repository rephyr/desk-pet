class_name BoxesTab
extends HBoxContainer
## The box shop on the left: each box a pack sticker with its price, how many you have in your bag,
## and open 1 / 10 / all; "odds" flips it over to the odds printed on its back, like a card pack.
## On the right the table where boxes get opened: one box gets the card pack ritual
## (PackOpening), several get a grid of stickers (BoxReveal).

const OPEN_MANY := 10
const OPEN_MAX_LIMIT := 500  # "open all" stops here so one click can't hang the game

var _reveal := BoxReveal.new()
var _opening := PackOpening.new()
var _buttons := {}  # box id -> { one, many, max (Buttons and their small labels), bag: Label, panel }


func _init() -> void:
	add_theme_constant_override("separation", 16)
	var shop := VBoxContainer.new()
	shop.custom_minimum_size = Vector2(268, 0)
	shop.add_theme_constant_override("separation", 14)
	add_child(shop)
	for box in Catalog.shared().boxes:
		if not box.get("hidden", false):
			shop.add_child(_offer(box))
	if OS.is_debug_build():
		shop.add_child(_dev_buttons())
	# the table: a dashed spot on the page where the opening happens
	var table := PanelContainer.new()
	table.size_flags_horizontal = SIZE_EXPAND_FILL
	table.add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.LINE, UiTheme.PAPER, 14, 12))
	add_child(table)
	table.add_child(_reveal)
	table.add_child(_opening)
	_opening.open_again.connect(func(box_id): open(box_id, 1))
	_reveal.again.connect(func(count):
		var box_id: String = _last_box if _last_box != "" else Catalog.shared().boxes[0].id
		var n := mini(mini(count, GameState.affordable(box_id)), OPEN_MAX_LIMIT)
		if n > 0:
			open(box_id, n))
	_reveal.done.connect(func(): _show_opening(true))
	_show_opening(true)
	GameState.changed.connect(_refresh)
	GameState.tutorial_changed.connect(_refresh)
	_refresh()


var _last_box := ""


func _offer(box: Dictionary) -> PanelContainer:
	var catalog := Catalog.shared()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	top.add_child(PackArt.rect(box.get("art", {}), 60))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.alignment = BoxContainer.ALIGNMENT_CENTER
	var name_row := HBoxContainer.new()
	var title := UiTheme.title(box.name, 17)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	name_row.add_child(title)
	var flip := UiTheme.small_button("odds")
	flip.add_theme_font_size_override("font_size", UiTheme.SMALL)
	flip.add_theme_color_override("font_color", UiTheme.MUTED)
	name_row.add_child(flip)
	info.add_child(name_row)
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 8)
	facts.add_child(UiTheme.chip("coin", str(int(box.price)), UiTheme.CYAN))
	var in_bag := UiTheme.label("", UiTheme.MINT, UiTheme.SMALL)
	facts.add_child(in_bag)
	info.add_child(facts)
	top.add_child(info)
	col.add_child(top)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var one := _open_button("open 1", func(): open(box.id, 1))
	var many := _open_button("open %d" % OPEN_MANY, func(): open(box.id, OPEN_MANY))
	var most := _open_button("open all", func(): open(box.id, mini(GameState.affordable(box.id), OPEN_MAX_LIMIT)))
	for b in [one, many, most]:
		buttons.add_child(b.button)
	col.add_child(buttons)

	# the back of the pack: its odds, rarity on the left, finishes on the right
	var odds := HBoxContainer.new()
	odds.add_theme_constant_override("separation", 18)
	odds.visible = false
	odds.add_child(_odds_column("rarity", Weighted.chances(box.tiers), func(id): return catalog.tier_at(catalog.rank(id)).name, func(id): return catalog.tier_color(id)))
	var finishes := Weighted.chances(box.finishes)
	finishes.erase("normal")
	odds.add_child(_odds_column("finish", finishes, func(id): return catalog.finish(id).name, func(_id): return UiTheme.TEXT))
	var back := VBoxContainer.new()
	back.add_child(UiTheme.stitch_line())
	back.add_child(odds)
	back.visible = false
	col.add_child(back)
	flip.pressed.connect(func():
		back.visible = not back.visible
		buttons.visible = not back.visible
		odds.visible = back.visible
		flip.text = "back" if back.visible else "odds")
	_buttons[box.id] = { "one": one, "many": many, "max": most, "bag": in_bag, "panel": panel }
	return panel


## A two-line open button: what it does, and under it the cost (coins, "from bag", how many).
func _open_button(text: String, on_pressed: Callable) -> Dictionary:
	var b := UiTheme.button("", on_pressed)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 42)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", -2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.set_anchors_preset(PRESET_FULL_RECT)
	var top := UiTheme.label(text, UiTheme.TEXT, UiTheme.SMALL + 1)
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(top)
	var small := UiTheme.label("", UiTheme.CYAN, UiTheme.SMALL)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(small)
	b.add_child(col)
	return { "button": b, "small": small, "top": top }


func _odds_column(head: String, chances: Dictionary, name_of: Callable, color_of: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 0)
	grid.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(UiTheme.label(head, UiTheme.MUTED, UiTheme.SMALL))
	grid.add_child(Control.new())
	for id: String in chances:
		grid.add_child(UiTheme.label(name_of.call(id), color_of.call(id), UiTheme.SMALL))
		var pct := UiTheme.label(UiTheme.percent(chances[id]), UiTheme.MUTED, UiTheme.SMALL)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_child(pct)
	return grid


## Debug only: open one box at a chosen rarity, to test each reveal.
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
		var b := UiTheme.button(tier.name, open.bind(box_id, 1, tier.id))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", catalog.tier_color(tier.id))
		grid.add_child(b)
	col.add_child(grid)
	return col


## Buys and opens boxes, then plays the reveal. `force_tier` is for testing (debug builds only).
func open(box_id: String, count: int, force_tier := "") -> void:
	_last_box = box_id
	var pulled := GameState.open_boxes(box_id, count, force_tier)
	if pulled.is_empty():
		return
	_show_opening(pulled.size() == 1)
	if pulled.size() == 1:
		# in the tutorial the pet inside talks while you open its box
		var talk: Array = Catalog.shared().tutorial.box_talk
		var nth := GameState.collection.pets.size() - 1
		_opening.box_talk = talk[nth] if GameState.tutorial_active() and nth < talk.size() else []
		_opening.play(pulled[0], box_id)
	else:
		_reveal.play(pulled)


## Whether a box is being opened right now (the pack is mid-ritual).
func is_revealing() -> bool:
	return _opening.visible and _opening.is_busy()


## The tutorial's "open a box" button.
func tutorial_target() -> Control:
	return _buttons[Catalog.shared().boxes[0].id].one.button


func _show_opening(single: bool) -> void:
	_opening.visible = single
	_reveal.visible = not single


func _refresh() -> void:
	for box_id in _buttons:
		var b: Dictionary = _buttons[box_id]
		var can := GameState.affordable(box_id)
		var owned := GameState.in_bag(box_id)
		var price := GameState.box_price(box_id)
		b.one.button.disabled = can < 1
		b.many.button.disabled = can < OPEN_MANY
		b.max.button.disabled = can < 2
		b.one.small.text = "from your bag" if owned > 0 else "%d coins" % price
		b.one.small.add_theme_color_override("font_color", UiTheme.MINT if owned > 0 else UiTheme.CYAN)
		b.many.small.text = "from your bag" if owned >= OPEN_MANY else "%d coins" % (price * (OPEN_MANY - owned))
		b.max.small.text = "%d boxes" % mini(can, OPEN_MAX_LIMIT) if can >= 2 else ""
		b.max.small.add_theme_color_override("font_color", UiTheme.MUTED)
		b.bag.text = "%d in your bag" % owned if owned > 0 else "none in your bag"
		b.bag.add_theme_color_override("font_color", UiTheme.MINT if owned > 0 else UiTheme.MUTED)
		# the tutorial is one starter box at a time
		var learning := GameState.tutorial_active()
		b.panel.visible = not learning or box_id == Catalog.shared().boxes[0].id
		b.many.button.visible = not learning
		b.max.button.visible = not learning
	if _last_box != "":
		_reveal.set_can_open(GameState.affordable(_last_box))
