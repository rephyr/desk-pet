class_name BoxesTab
extends HBoxContainer
## Box shop on the left (price, odds, open buttons), the reveal on the right:
## one box gets the card pack ritual (PackOpening), several get the quick grid (BoxReveal).

const OPEN_MANY := 10
const OPEN_MAX_LIMIT := 500  # "open max" stops here so one click can't hang the game

var _reveal := BoxReveal.new()
var _opening := PackOpening.new()
var _buttons := {}  # box id -> { "one": Button, "many": Button, "max": Button }


func _init() -> void:
	add_theme_constant_override("separation", 14)
	var shop := VBoxContainer.new()
	shop.custom_minimum_size = Vector2(290, 0)
	shop.add_theme_constant_override("separation", 10)
	add_child(shop)
	for box in Catalog.shared().boxes:
		shop.add_child(_offer(box))
	if OS.is_debug_build():
		shop.add_child(_dev_buttons())
	add_child(_reveal)
	add_child(_opening)
	_opening.open_again.connect(func(box_id): open(box_id, 1))
	_show_opening(true)
	GameState.changed.connect(_refresh)
	_refresh()


func _offer(box: Dictionary) -> PanelContainer:
	var catalog := Catalog.shared()
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.BG_RAISED, UiTheme.LILAC.darkened(0.4), 10, 2, 10))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)

	var top := HBoxContainer.new()
	top.add_child(UiTheme.label(box.name, UiTheme.PINK))
	top.add_child(UiTheme.spacer())
	top.add_child(UiTheme.label("◆ %d" % box.price, UiTheme.CYAN))
	col.add_child(top)

	# odds: rarity on the left, finishes on the right
	var odds := GridContainer.new()
	odds.columns = 4
	odds.add_theme_constant_override("h_separation", 10)
	odds.add_theme_constant_override("v_separation", 0)
	var tiers := Weighted.chances(box.tiers)
	var finishes := Weighted.chances(box.finishes)
	var finish_ids := finishes.keys().filter(func(id): return id != "normal")
	for i in maxi(tiers.size(), finish_ids.size()):
		if i < tiers.size():
			var tier_id: String = tiers.keys()[i]
			odds.add_child(UiTheme.tier_label(tier_id))
			odds.add_child(UiTheme.label(UiTheme.percent(tiers[tier_id]), UiTheme.MUTED, UiTheme.SMALL))
		else:
			odds.add_child(Control.new())
			odds.add_child(Control.new())
		if i < finish_ids.size():
			var f: Dictionary = catalog.finish(finish_ids[i])
			odds.add_child(UiTheme.label(f.name, catalog.tier_color(f.rarity), UiTheme.SMALL))
			odds.add_child(UiTheme.label(UiTheme.percent(finishes[f.id]), UiTheme.MUTED, UiTheme.SMALL))
		else:
			odds.add_child(Control.new())
			odds.add_child(Control.new())
	col.add_child(odds)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 6)
	var one := UiTheme.button("open 1", open.bind(box.id, 1))
	var many := UiTheme.button("open %d" % OPEN_MANY, open.bind(box.id, OPEN_MANY))
	var most := UiTheme.button("open max", func(): open(box.id, mini(GameState.affordable(box.id), OPEN_MAX_LIMIT)))
	for b in [one, many, most]:
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		buttons.add_child(b)
	col.add_child(buttons)
	_buttons[box.id] = { "one": one, "many": many, "max": most }
	return panel


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
	var pulled := GameState.open_boxes(box_id, count, force_tier)
	if pulled.is_empty():
		return
	_show_opening(pulled.size() == 1)
	if pulled.size() == 1:
		_opening.play(pulled[0], box_id)
	else:
		_reveal.play(pulled)


func _show_opening(single: bool) -> void:
	_opening.visible = single
	_reveal.visible = not single


func _refresh() -> void:
	for box_id in _buttons:
		var b: Dictionary = _buttons[box_id]
		var can := GameState.affordable(box_id)
		b.one.disabled = can < 1
		b.many.disabled = can < OPEN_MANY
		b.max.disabled = can < 2
		b.max.text = "open %d" % mini(can, OPEN_MAX_LIMIT) if can >= 2 else "open max"
