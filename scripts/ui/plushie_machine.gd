class_name PlushieMachine
extends MarginContainer
## The plushie machine, the workbench's third page (F1/F2; look A, the cabinet, in
## design/mockups/screens/sacrifice-reels.html): a pink toy slot machine with a hopper funnel on
## top, a reel for each of the keeper's parts, the lever beside it; the keeper, the hopper, wisps
## and the shop on a card next to it. The rules are Plushie's (through GameState.plushie_*); this
## shows them and plays the reels: they roll and land one by one, a button sparkles, a miss puffs
## coral fluff (wisps), a crack rips. Your pet cheers every spin.

const REEL_W := 62
const REEL_H := 120
const GAP := 8
const LAND_FIRST := 0.38  # seconds before the first reel lands
const LAND_EVERY := 0.17  # and between the next ones
const WILD := 5  # the wild reel's index for effects
const NUDGE_ROLL := 0.22  # a nudged reel's short roll
const CARD_PAGE := 20  # card pets the picker shows at once (‹ › pages through the rest)

var _body := HBoxContainer.new()
var _fx := Fx.new()
var _hopper := Hopper.new()
var _bulbs := Bulbs.new()
var _head_names: Array[Label] = []
var _reels: Array[ReelView] = []
var _marks: Array[Marks] = []
var _odds: Array[Array] = []  # per reel: [button label, blank label, crack label]
var _odds_box: Array[Control] = []
var _full: Array[Label] = []
var _bank: Array[Button] = []
var _hold: Array[Button] = []
var _kept: Array[Label] = []
var _wild_parts: Array[Control] = []  # the wild reel's column pieces (and the gaps before them)
var _wild_name: Label
var _wild_reel := ReelView.new()
var _wild_odds: Array[Label] = []
var _lever := Lever.new()
var _spin: Button
# the side card
var _keeper_face := PetPortrait.new(3, true)
var _keeper_frame := PanelContainer.new()
var _keeper_name: Label
var _keeper_total: Label
var _prev: Button
var _next: Button
var _rows := VBoxContainer.new()
var _cards_button: Button
var _wisps: Label
var _nudge_dots := Dots.new()
var _hold_dots := Dots.new()
var _buy := {}  # what -> its buy button
var _wild_row: Array[Control] = []

var _picking := false  # the card pets picker is showing instead of the hopper rows
var _card_page := 0
var _dirty := true
var _rows_dirty := true  # the hopper rows (or the picker) have to be worked out again
var _tier_rows := {}  # rarity -> { row, count, waiting, plus }: the hopper rows, updated in place
var _rows_shown := ""  # what _rows holds now: the rarities shown, or the picker page's pets
var _t := 0.0
var _busy_until := 0.0
var _landing := {}  # reel index (WILD for the wild reel) -> [time it lands, symbol, wisps puffed]
var _pending_wisps := 0  # puffed by reels still rolling (the number catches up as they land)
var _was_busy := false


func _init() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		add_theme_constant_override("margin_" + side, 0)
	_body.add_theme_constant_override("separation", 14)
	add_child(_body)
	_body.add_child(_build_stage())
	_body.add_child(_build_side())
	_fx.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_fx)
	GameState.plushie_changed.connect(_rows_changed)
	GameState.changed.connect(func(): _dirty = true)
	GameState.plushie_spun.connect(_on_spun)
	# the hopper rows and the picker only change with the herd, the cards and who's busy
	var c := GameState.collection
	c.pet_changed.connect(func(_p): _rows_changed())
	c.pets_added.connect(func(_p): _rows_changed())
	c.pets_removed.connect(func(_u): _rows_changed())
	c.pets_folded.connect(func(_u, _k): _rows_changed())
	c.herd_changed.connect(func(_k): _rows_changed())
	c.active_changed.connect(func(_p): _rows_changed())
	GameState.jobs_changed.connect(_rows_changed)
	GameState.automation_changed.connect(_rows_changed)
	GameState.adventures_changed.connect(_rows_changed)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_refresh()
			speak())


func speak() -> void:
	var st: Dictionary = GameState.plushie
	PetBubble.say_line(self, "plushie" if not st.hopper.is_empty() or not Plushie.fed(st).is_empty() else "plushie_empty")


## Whether reels are still rolling (the dev driver waits for this).
func busy() -> bool:
	return _t < _busy_until or not _landing.is_empty()


func _process(delta: float) -> void:
	_t += delta
	for i in _landing.keys():
		var l: Array = _landing[i]
		if _t >= float(l[0]):
			_landing.erase(i)
			_land(i, str(l[1]), int(l[2]))
	var now_busy := busy()
	_bulbs.lit = now_busy
	if _was_busy and not now_busy:
		_dirty = true
	_was_busy = now_busy
	if _dirty and is_visible_in_tree() and not now_busy:
		_refresh()


# ---- building --------------------------------------------------------------------------------

func _build_stage() -> Control:
	var stage := PanelContainer.new()
	stage.size_flags_horizontal = SIZE_EXPAND_FILL
	stage.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 16, 2, 10))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 0)
	stage.add_child(col)
	_hopper.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(_hopper)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	col.add_child(row)
	var cabinet := PanelContainer.new()
	var cab := UiTheme.box(UiTheme.PAGE.lerp(UiTheme.PINK, 0.16), UiTheme.PINK, 28, 3, 0)
	cab.corner_radius_bottom_left = 18
	cab.corner_radius_bottom_right = 18
	cab.content_margin_left = 12
	cab.content_margin_right = 12
	cab.content_margin_top = 10
	cab.content_margin_bottom = 10
	cab.shadow_color = UiTheme.SHADOW
	cab.shadow_size = 6
	cab.shadow_offset = Vector2(0, 4)
	cabinet.add_theme_stylebox_override("panel", cab)
	row.add_child(cabinet)
	var inside := VBoxContainer.new()
	inside.add_theme_constant_override("separation", 4)
	cabinet.add_child(inside)
	_bulbs.size_flags_horizontal = SIZE_EXPAND_FILL
	inside.add_child(_bulbs)
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", GAP)
	heads.alignment = BoxContainer.ALIGNMENT_CENTER
	inside.add_child(heads)
	var window := PanelContainer.new()
	window.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 14, 2, 7))
	window.draw.connect(func():
		# the little pink arrows either side, pointing at the middle row
		var y := window.size.y / 2.0
		window.draw_colored_polygon(PackedVector2Array([Vector2(1, y - 7), Vector2(8, y), Vector2(1, y + 7)]), UiTheme.PINK)
		var x := window.size.x - 1.0
		window.draw_colored_polygon(PackedVector2Array([Vector2(x, y - 7), Vector2(x - 7, y), Vector2(x, y + 7)]), UiTheme.PINK))
	inside.add_child(window)
	var reels := HBoxContainer.new()
	reels.add_theme_constant_override("separation", GAP)
	reels.alignment = BoxContainer.ALIGNMENT_CENTER
	window.add_child(reels)
	var under := HBoxContainer.new()
	under.add_theme_constant_override("separation", GAP)
	under.alignment = BoxContainer.ALIGNMENT_CENTER
	inside.add_child(under)
	for i in Catalog.SLOTS.size():
		heads.add_child(_head(i))
		var reel := ReelView.new()
		reel.nudge.pressed.connect(_nudge.bind(i))
		_reels.append(reel)
		reels.add_child(reel)
		under.add_child(_under(i))
	# the wild 6th reel, only for a pet it was bought for
	for holder: HBoxContainer in [heads, reels, under]:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(4, 0)
		gap.mouse_filter = MOUSE_FILTER_IGNORE
		holder.add_child(gap)
		_wild_parts.append(gap)
	var wild_head := VBoxContainer.new()
	wild_head.custom_minimum_size = Vector2(REEL_W, 0)
	wild_head.add_theme_constant_override("separation", -2)
	var wild_word := UiTheme.label("wild", UiTheme.WISP, UiTheme.SMALL - 1)
	wild_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wild_head.add_child(wild_word)
	var pick := HBoxContainer.new()
	pick.add_theme_constant_override("separation", 0)
	pick.add_child(_arrow("‹", func(): GameState.plushie_wild_step(-1)))
	_wild_name = UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL)
	_wild_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wild_name.size_flags_horizontal = SIZE_EXPAND_FILL
	_wild_name.clip_text = true
	pick.add_child(_wild_name)
	pick.add_child(_arrow("›", func(): GameState.plushie_wild_step(1)))
	wild_head.add_child(pick)
	heads.add_child(wild_head)
	_wild_parts.append(wild_head)
	_wild_reel.wild = true
	reels.add_child(_wild_reel)
	_wild_parts.append(_wild_reel)
	var wild_under := VBoxContainer.new()
	wild_under.custom_minimum_size = Vector2(REEL_W, 0)
	wild_under.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	wild_under.add_child(spacer)
	for sym in Plushie.SYMBOLS:
		var o := _odds_row(sym)
		wild_under.add_child(o[0])
		_wild_odds.append(o[1])
	under.add_child(wild_under)
	_wild_parts.append(wild_under)

	_lever.custom_minimum_size = Vector2(40, 170)
	_lever.size_flags_vertical = SIZE_SHRINK_CENTER
	_lever.pulled.connect(func(): spin())
	row.add_child(_lever)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 10)
	col.add_child(pad)
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_CENTER
	_spin = UiTheme.button("spin!", func(): spin())
	_spin.custom_minimum_size = Vector2(140, 0)
	_spin.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	_spin.add_theme_font_size_override("font_size", 17)
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 10, 2, 5)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	_spin.add_theme_stylebox_override("normal", sb)
	go.add_child(_spin)
	col.add_child(go)
	return stage


func _head(i: int) -> Control:
	var head := VBoxContainer.new()
	head.custom_minimum_size = Vector2(REEL_W, 0)
	head.add_theme_constant_override("separation", -2)
	var slot := UiTheme.label(Catalog.SLOTS[i], UiTheme.MUTED, UiTheme.SMALL - 1)
	slot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(slot)
	var name_label := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.custom_minimum_size = Vector2(REEL_W, 0)
	head.add_child(name_label)
	_head_names.append(name_label)
	return head


func _under(i: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(REEL_W, 0)
	col.add_theme_constant_override("separation", 3)
	var marks := Marks.new()
	marks.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(marks)
	_marks.append(marks)
	var odds := VBoxContainer.new()
	odds.add_theme_constant_override("separation", 0)
	var labels := []
	for sym in Plushie.SYMBOLS:
		var o := _odds_row(sym)
		odds.add_child(o[0])
		labels.append(o[1])
	_odds.append(labels)
	_odds_box.append(odds)
	col.add_child(odds)
	var full := UiTheme.label("full!", UiTheme.PINK, UiTheme.SMALL)
	full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(full)
	_full.append(full)
	var bank := _tiny_button("bank", func(): bank(i))
	col.add_child(bank)
	_bank.append(bank)
	var hold := _tiny_button("hold", func(): GameState.plushie_hold(i))
	col.add_child(hold)
	_hold.append(hold)
	var kept := UiTheme.label("kept!", UiTheme.PINK, UiTheme.SMALL)
	kept.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(kept)
	_kept.append(kept)
	return col


## One line of a reel's odds: the symbol and its %. Returns [the row, the % label].
func _odds_row(sym: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := UiTheme.icon_rect(_icon_of(sym), 11)
	icon.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(icon)
	var l := UiTheme.label("", _odds_color(sym), UiTheme.SMALL - 1)
	l.custom_minimum_size = Vector2(26, 0)
	row.add_child(l)
	return [row, l]


static func _icon_of(sym: String) -> String:
	return { Plushie.BUTTON: "button", Plushie.BLANK: "reel_blank", Plushie.CRACK: "reel_crack" }.get(sym, "reel_blank")


static func _odds_color(sym: String) -> Color:
	return { Plushie.BUTTON: UiTheme.PINK, Plushie.BLANK: UiTheme.MUTED, Plushie.CRACK: UiTheme.TEXT }.get(sym, UiTheme.MUTED)


func _tiny_button(text: String, on_pressed: Callable) -> Button:
	var b := UiTheme.button(text, on_pressed)
	b.add_theme_font_size_override("font_size", UiTheme.SMALL - 1)
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		var edge := UiTheme.LILAC_SEAM
		if state in ["hover", "pressed", "hover_pressed"]:
			edge = UiTheme.PINK
		elif state == "disabled":
			edge = UiTheme.MUTED_SEAM
		var sb := UiTheme.box(UiTheme.DEEP, edge, 7, 2, 1)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		b.add_theme_stylebox_override(state, sb)
	return b


func _arrow(text: String, on_pressed: Callable) -> Button:
	var b := UiTheme.button(text, on_pressed)
	b.flat = true
	b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	var sb := StyleBoxEmpty.new()
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	for state in ["normal", "hover", "pressed", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(state, sb)
	return b


func _build_side() -> Control:
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(240, 0)
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	side.add_child(col)
	col.add_child(UiTheme.title("keeper", 14, UiTheme.LILAC))
	var keeper := HBoxContainer.new()
	keeper.add_theme_constant_override("separation", 10)
	col.add_child(keeper)
	_keeper_frame.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 14, 2, 3))
	_keeper_face.mouse_filter = MOUSE_FILTER_IGNORE
	_keeper_frame.add_child(_keeper_face)
	keeper.add_child(Tilted.new(_keeper_frame, -3.0))
	var who := VBoxContainer.new()
	who.size_flags_horizontal = SIZE_EXPAND_FILL
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	who.add_theme_constant_override("separation", 2)
	keeper.add_child(who)
	_keeper_name = UiTheme.label("", UiTheme.PINK, 15)
	_keeper_name.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	_keeper_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keeper_name.custom_minimum_size = Vector2(120, 0)
	who.add_child(_keeper_name)
	var total := HBoxContainer.new()
	total.add_theme_constant_override("separation", 4)
	total.add_child(UiTheme.icon_rect("button", 14))
	_keeper_total = UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
	total.add_child(_keeper_total)
	who.add_child(total)
	var flip := HBoxContainer.new()
	flip.add_theme_constant_override("separation", 4)
	_prev = _tiny_button("‹", func(): _swap(-1))
	_next = _tiny_button("›", func(): _swap(1))
	for b in [_prev, _next]:
		b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		flip.add_child(b)
	who.add_child(flip)
	col.add_child(UiTheme.stitch_line())
	var hop_head := HBoxContainer.new()
	hop_head.add_child(UiTheme.title("hopper", 14, UiTheme.LILAC))
	hop_head.add_child(UiTheme.spacer())
	_cards_button = _tiny_button("card pets", func():
		_picking = not _picking
		_card_page = 0
		_rows_changed())
	_cards_button.size_flags_vertical = SIZE_SHRINK_CENTER
	hop_head.add_child(_cards_button)
	col.add_child(hop_head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 2)
	scroll.add_child(_rows)
	col.add_child(scroll)
	col.add_child(UiTheme.stitch_line())
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 8)
	big.add_child(UiTheme.icon_rect("wisp", 24))
	_wisps = UiTheme.label("0", UiTheme.WISP, 20)
	_wisps.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	big.add_child(_wisps)
	col.add_child(big)
	var shop := GridContainer.new()
	shop.columns = 2
	shop.add_theme_constant_override("h_separation", 8)
	shop.add_theme_constant_override("v_separation", 4)
	col.add_child(shop)
	for what in Plushie.SHOP:
		var name_row := HBoxContainer.new()
		name_row.size_flags_horizontal = SIZE_EXPAND_FILL
		name_row.add_theme_constant_override("separation", 6)
		name_row.add_child(UiTheme.label({ "nudge": "nudges", "hold": "holds", "wild": "wild reel" }[what], UiTheme.TEXT, UiTheme.SMALL + 1))
		if what == "nudge":
			_nudge_dots.color = UiTheme.LILAC
			name_row.add_child(_nudge_dots)
		elif what == "hold":
			_hold_dots.color = UiTheme.PINK
			name_row.add_child(_hold_dots)
		shop.add_child(name_row)
		var buy := _tiny_button("", func(): _buy_one(what))
		buy.icon = UiTheme.icon("wisp", 13)
		buy.add_theme_color_override("font_color", UiTheme.WISP)
		buy.add_theme_font_size_override("font_size", UiTheme.SMALL)
		buy.size_flags_vertical = SIZE_SHRINK_CENTER
		shop.add_child(buy)
		_buy[what] = buy
		if what == "wild":
			_wild_row.append(name_row)
			_wild_row.append(buy)
	return side


# ---- showing the state -----------------------------------------------------------------------

func _refresh() -> void:
	_dirty = false
	var catalog := Catalog.shared()
	var st: Dictionary = GameState.plushie
	var keeper := GameState.plushie_keeper()
	var t: Dictionary = st.try
	var fed := Plushie.fed(st)
	_hopper.show_fed(fed, int(t.spins), int(t.spins_max), int(st.nudges))
	for i in Catalog.SLOTS.size():
		if not _landing.has(i):
			_refresh_reel(i, keeper)
	var wild: Dictionary = t.wild
	for c in _wild_parts:
		c.visible = not wild.is_empty()
	if not wild.is_empty() and keeper != null:
		var slot := str(wild.slot)
		_wild_name.text = str(catalog.part(slot, keeper.parts[slot]).get("name", keeper.parts[slot]))
		_wild_name.tooltip_text = slot
		if not _landing.has(WILD):
			_wild_reel.show_strip(wild.strip, false, Plushie.full(catalog, keeper, slot))
		var o := Plushie.odds_for(catalog, Plushie.buttons(keeper, slot), fed.get("traits", []))
		for k in Plushie.SYMBOLS.size():
			_wild_odds[k].text = "%d%%" % int(o.get(Plushie.SYMBOLS[k], 0))
	# the big button
	if fed.is_empty() and st.hopper.is_empty():
		_spin.text = "empty!"
		_spin.disabled = true
	else:
		_spin.text = "next!" if Plushie.needs_next(st) else "spin!"
		_spin.disabled = busy() or keeper == null
	_lever.enabled = not _spin.disabled
	_refresh_side(keeper, st)


func _refresh_reel(i: int, keeper: Pet) -> void:
	var catalog := Catalog.shared()
	var st: Dictionary = GameState.plushie
	var slot: String = Catalog.SLOTS[i]
	var r: Dictionary = st.try.reels[i]
	var full := keeper != null and Plushie.full(catalog, keeper, slot)
	var part_id := str(keeper.parts[slot]) if keeper else ""
	_head_names[i].text = str(catalog.part(slot, part_id).get("name", part_id)) if keeper else ""
	_head_names[i].tooltip_text = _head_names[i].text
	_reels[i].show_strip(r.strip, r.banked, full)
	_reels[i].nudge.visible = keeper != null and Plushie.can_nudge(catalog, st, keeper, i) and not busy()
	_marks[i].set_marks(Plushie.buttons(keeper, slot), int(r.held), Plushie.max_buttons(catalog))
	var o := Plushie.odds(catalog, st, keeper, i) if keeper else {}
	_odds_box[i].visible = not full
	_full[i].visible = full
	for k in Plushie.SYMBOLS.size():
		_odds[i][k].text = "%d%%" % int(o.get(Plushie.SYMBOLS[k], 0))
	var going: bool = not full and not r.banked
	_bank[i].visible = going
	_hold[i].visible = going
	_kept[i].visible = r.banked and not full
	_bank[i].disabled = int(r.held) <= 0 or busy()
	_hold[i].disabled = busy() or not Plushie.can_hold(catalog, st, i, GameState.perk_holds())
	_set_on(_hold[i], r.hold)


## A tiny button that looks pressed while it's on (a reel on hold).
func _set_on(b: Button, on: bool) -> void:
	var sb := UiTheme.box(UiTheme.PINK_PRESSED if on else UiTheme.DEEP, UiTheme.PINK if on else UiTheme.LILAC_SEAM, 7, 2, 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	b.add_theme_stylebox_override("normal", sb)
	var dis := sb.duplicate()
	if not on:
		dis.border_color = UiTheme.MUTED_SEAM
	b.add_theme_stylebox_override("disabled", dis)


func _refresh_side(keeper: Pet, st: Dictionary) -> void:
	var catalog := Catalog.shared()
	_keeper_face.set_pet(keeper)
	_keeper_frame.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, catalog.tier_color(keeper.rarity) if keeper else UiTheme.LINE, 14, 2, 3))
	_keeper_name.text = keeper.display_name(catalog) if keeper else ""
	var n := Plushie.total(keeper)
	_keeper_total.text = "%d button%s" % [n, "" if n == 1 else "s"]
	var can_swap := not busy() and GameState.plushie_can_swap()
	_prev.disabled = not can_swap
	_next.disabled = not can_swap
	if _rows_dirty:
		_rows_dirty = false
		_refresh_rows(st)
	_wisps.text = UiTheme.num(GameState.wisps - _pending_wisps)
	_nudge_dots.set_dots(int(st.nudges), int(st.nudges))
	var holds := Plushie.holds_max(catalog, st, GameState.perk_holds())
	_hold_dots.set_dots(holds - Plushie.holds_used(st), holds)
	for what in Plushie.SHOP:
		var price := GameState.plushie_price(what)
		var b: Button = _buy[what]
		b.text = "+%s" % UiTheme.num(price) if price >= 0 else ("on!" if what == "wild" and not st.try.wild.is_empty() else "")
		b.disabled = price < 0 or GameState.wisps < price or busy()
	# the wild reel shows while it's on, or while it can be bought for the pet in the machine
	var wild_shown: bool = not st.try.wild.is_empty() or Plushie.wild_available(catalog, st, keeper)
	for c in _wild_row:
		c.visible = wild_shown


func _rows_changed() -> void:
	_rows_dirty = true
	_dirty = true


## The hopper rows by rarity (updated in place; only built again when the rarities shown change), or
## a page of the card pets picker.
func _refresh_rows(st: Dictionary) -> void:
	var catalog := Catalog.shared()
	var has_cards := GameState.plushie_has_cards()
	if not has_cards:
		_picking = false
	_cards_button.visible = has_cards
	_cards_button.text = "done" if _picking else "card pets"
	if _picking:
		var cards := GameState.plushie_cards()
		var pages := maxi(1, ceili(cards.size() / float(CARD_PAGE)))
		_card_page = clampi(_card_page, 0, pages - 1)
		var page := cards.slice(_card_page * CARD_PAGE, (_card_page + 1) * CARD_PAGE)
		var shown := "cards %d/%d:" % [_card_page, pages] + ",".join(PackedStringArray(page.map(func(p): return p.uid)))
		if shown != _rows_shown:
			_rows_shown = shown
			_tier_rows.clear()
			UiTheme.clear(_rows)
			if pages > 1:
				_rows.add_child(_pager(pages))
			_rows.add_child(_card_grid(page))
		return
	var herds := {}
	var waiting := {}
	for p in st.hopper:
		var r := str(p.get("rarity", ""))
		waiting[r] = int(waiting.get(r, 0)) + 1
	var tiers: Array[String] = []
	for tier in catalog.tiers:
		herds[tier.id] = GameState.plushie_herd(tier.id)
		if int(herds[tier.id]) > 0 or int(waiting.get(tier.id, 0)) > 0:
			tiers.append(tier.id)
	var shown := "rows:" + ",".join(PackedStringArray(tiers))
	if shown != _rows_shown:
		_rows_shown = shown
		_tier_rows.clear()
		UiTheme.clear(_rows)
		for id in tiers:
			var row := _hopper_row(id)
			_tier_rows[id] = row
			_rows.add_child(row.row)
	var room: bool = st.hopper.size() < Plushie.hopper_max(catalog)
	for id in tiers:
		var row: Dictionary = _tier_rows[id]
		row.count.text = UiTheme.num(int(herds[id]))
		row.waiting.text = str(int(waiting.get(id, 0)))
		row.plus.disabled = int(herds[id]) <= 0 or not room


## ‹ page › over the card pets picker.
func _pager(pages: int) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	var turn := func(d: int):
		_card_page = posmod(_card_page + d, pages)
		_rows_changed()
	row.add_child(_tiny_button("‹", turn.bind(-1)))
	row.add_child(UiTheme.label("%d/%d" % [_card_page + 1, pages], UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(_tiny_button("›", turn.bind(1)))
	return row


## One hopper row: a face, the rarity and the shelf's herd count, how many wait, +. Returns
## { row, count, waiting, plus } (the numbers are filled in by _refresh_rows).
func _hopper_row(rarity: String) -> Dictionary:
	var catalog := Catalog.shared()
	var color := catalog.tier_color(rarity)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var face := PetPortrait.new(2, false)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	face.set_pet(Herd.stand_in(catalog, Herd.uid(Herd.key(rarity, "normal"), 0)))
	row.add_child(face)
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_col.add_theme_constant_override("separation", -3)
	name_col.add_child(UiTheme.label(catalog.tier_at(catalog.rank(rarity)).name, color, UiTheme.SMALL + 1))
	var count := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL - 1)
	name_col.add_child(count)
	row.add_child(name_col)
	var n := UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
	n.custom_minimum_size = Vector2(22, 0)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(n)
	var plus := _tiny_button("+", func(): feed_herd(rarity))
	plus.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	plus.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(plus)
	return { "row": row, "count": count, "waiting": n, "plus": plus }


func _card_grid(cards: Array) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var catalog := Catalog.shared()
	for pet: Pet in cards:
		var b := Button.new()
		b.focus_mode = FOCUS_NONE
		b.custom_minimum_size = Vector2(46, 48)
		b.tooltip_text = pet.display_name(catalog)
		b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var color := catalog.tier_color(pet.rarity)
		b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, color.lerp(UiTheme.LINE, 0.4), 10, 2, 2))
		b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.DEEP, UiTheme.PINK, 10, 2, 2))
		b.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.PINK_PRESSED, UiTheme.PINK, 10, 2, 2))
		var face := PetPortrait.new(2, false)
		face.mouse_filter = MOUSE_FILTER_IGNORE
		face.set_pet(pet)
		face.position = Vector2(7, 4)
		b.add_child(face)
		var uid := pet.uid
		b.pressed.connect(func(): feed_card(uid))
		grid.add_child(b)
	return grid


# ---- doing things ----------------------------------------------------------------------------

## Pulls the lever (the spin button does the same): a spin, or the next pet hops in. Returns what
## happened (see GameState.plushie_spin), {} when nothing could.
func spin() -> Dictionary:
	if busy():
		return {}
	var result := GameState.plushie_spin()
	if not result.is_empty():
		_lever.pull()
	return result


func bank(i: int) -> void:
	if not busy():
		GameState.plushie_bank(i)


func _nudge(i: int) -> void:
	if not busy():
		GameState.plushie_nudge(i)


func _swap(d: int) -> void:
	if not busy() and GameState.plushie_swap(d):
		PetBubble.say_line(self, "plushie_keeper")


func feed_herd(rarity: String) -> bool:
	if busy() or not GameState.plushie_feed_herd(rarity):
		return false
	PetBubble.say_line(self, "plushie_fed")
	return true


func feed_card(uid: String) -> bool:
	if busy() or not GameState.plushie_feed_card(uid):
		return false
	PetBubble.say_line(self, "plushie_fed")
	return true


## Opens the card pets picker (the dev driver's "cards").
func show_cards(on: bool) -> void:
	_picking = on
	_card_page = 0
	_rows_changed()
	_refresh()


## Feeds the nth card pet (the dev driver's "feed-card"; counts across the picker's pages). False
## if there's none.
func pick_card(n: int) -> bool:
	var cards := GameState.plushie_cards()
	if n < 1 or n > cards.size():
		return false
	return feed_card(cards[n - 1].uid)


func _buy_one(what: String) -> void:
	if not busy() and GameState.plushie_buy(what):
		PetBubble.say_line(self, "plushie_bought")


## What the machine just did (GameState.plushie_spun): the reels roll and land one by one.
func _on_spun(result: Dictionary) -> void:
	if not is_visible_in_tree():
		return
	var catalog := Catalog.shared()
	var sewn: Dictionary = result.get("sewn", {})
	if result.has("next"):
		for slot in sewn:
			_sparks(Catalog.SLOTS.find(slot), int(sewn[slot]))
		var fed: Dictionary = result.get("fed", {})
		if fed.is_empty():
			PetBubble.say_line(self, "plushie_done")
		else:
			PetBubble.say_line(self, "plushie_hop", { "name": Pet.from_dict(fed, catalog).display_name(catalog) })
		_dirty = true
		return
	if result.has("banked"):
		_sparks(int(result.banked), int(sewn.values()[0]) if not sewn.is_empty() else 0)
		PetBubble.say_line(self, "plushie_kept")
		_dirty = true
		return
	if result.has("nudged"):
		var ni := int(result.nudged)
		_busy_until = _t + NUDGE_ROLL + 0.05
		_reels[ni].start_roll()
		_landing[ni] = [_t + NUDGE_ROLL, str(result.landed[ni]), 0]
		return
	# a spin: reels that banked by themselves sparkle now, the rest roll and land in turn
	var wild: Dictionary = result.get("wild", {})
	for slot in sewn:
		var auto := int(sewn[slot]) - (int(wild.get("sewn", 0)) if str(wild.get("slot", "")) == slot else 0)
		if auto > 0:
			_sparks(Catalog.SLOTS.find(slot), auto)
	var landed: Dictionary = result.get("landed", {})
	var puffed: Dictionary = result.get("puffed", {})
	var k := 0
	_pending_wisps = int(result.get("wisps", 0))
	for i in range(Catalog.SLOTS.size()):
		if landed.has(i):
			_reels[i].start_roll()
			_landing[i] = [_t + LAND_FIRST + k * LAND_EVERY, str(landed[i]), int(puffed.get(i, 0))]
			k += 1
	if not wild.is_empty():
		_wild_reel.start_roll()
		_landing[WILD] = [_t + LAND_FIRST + k * LAND_EVERY, str(wild.symbol), int(wild.get("wisps", 0))]
		k += 1
	_busy_until = _t + LAND_FIRST + maxi(k - 1, 0) * LAND_EVERY + 0.35
	for b in _bank + _hold:
		b.disabled = true
	for what in _buy:
		_buy[what].disabled = true
	_prev.disabled = true
	_next.disabled = true
	_spin.disabled = true
	_lever.enabled = false
	PetBubble.say_line(self, "plushie_cheer")


## Reel i (or the wild reel) lands on `sym`.
func _land(i: int, sym: String, puffed: int) -> void:
	var st: Dictionary = GameState.plushie
	if i == WILD:
		var wild: Dictionary = st.try.wild
		_wild_reel.show_strip(wild.get("strip", [sym, sym, sym]), false, false)
		_wild_reel.landed()
	else:
		_refresh_reel(i, GameState.plushie_keeper())
		_bank[i].disabled = true
		_hold[i].disabled = true
		_reels[i].nudge.visible = false
		_reels[i].landed()
	if sym == Plushie.BUTTON:
		_sparks(i, 1 if i == WILD else 0)
	elif puffed > 0 or sym == Plushie.CRACK:
		_puffs(i, puffed, sym == Plushie.CRACK)
	if _landing.is_empty():
		var any_button := false
		for r in st.try.reels:
			any_button = any_button or (r.fresh and str(r.strip[1]) == Plushie.BUTTON)
		if not st.try.wild.is_empty() and str(st.try.wild.strip[1]) == Plushie.BUTTON:
			any_button = true
		PetBubble.say_line(self, "plushie_yay" if any_button else "plushie_fluff")


# ---- effects ---------------------------------------------------------------------------------

func _reel_centre(i: int) -> Vector2:
	var reel: Control = _wild_reel if i == WILD else _reels[clampi(i, 0, _reels.size() - 1)]
	return _fx.get_global_transform().affine_inverse() * reel.get_global_rect().get_center()


func _sparks(i: int, got: int) -> void:
	if i < 0:
		return
	var at := _reel_centre(i)
	_fx.burst(at, "bit", 10, UiTheme.PINK)
	if got > 0:
		_fx.float_text(at + Vector2(0, -30), "+%d" % got, "button", UiTheme.PINK)


func _puffs(i: int, n: int, crack: bool) -> void:
	var at := _reel_centre(i)
	_fx.burst(at, "puff", 7, UiTheme.WISP)
	if n > 0:
		_fx.float_text(at + Vector2(0, -26), "+%s" % UiTheme.num(n), "wisp", UiTheme.WISP)
		_pending_wisps = maxi(0, _pending_wisps - n)
		_wisps.text = UiTheme.num(GameState.wisps - _pending_wisps)
	if crack:
		(_wild_reel if i == WILD else _reels[i]).rip()


# ---- pieces ----------------------------------------------------------------------------------

## The hopper funnel on top of the cabinet: the fed pet bobbing in it, its spins and the nudge pool
## on the left, who it is on the right.
class Hopper extends Control:
	var _face := PetPortrait.new(3, true)
	var _spins := Dots.new()
	var _nudges := Dots.new()
	var _name: Label
	var _tier: Label
	var _trait: Label
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(470, 74)
		mouse_filter = MOUSE_FILTER_IGNORE
		_face.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(_face)
		var left := VBoxContainer.new()
		left.add_theme_constant_override("separation", 3)
		left.position = Vector2(0, 14)
		left.size = Vector2(140, 40)
		for pair in [["spins", _spins, UiTheme.PINK], ["nudges", _nudges, UiTheme.LILAC]]:
			var row := HBoxContainer.new()
			row.alignment = BoxContainer.ALIGNMENT_END
			row.add_theme_constant_override("separation", 6)
			row.add_child(UiTheme.label(pair[0], UiTheme.MUTED, UiTheme.SMALL))
			pair[1].color = pair[2]
			row.add_child(pair[1])
			left.add_child(row)
		add_child(left)
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", -2)
		right.position = Vector2(334, 8)
		_name = UiTheme.label("", UiTheme.TEXT, UiTheme.SMALL + 1)
		_name.clip_text = true
		_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_name.custom_minimum_size = Vector2(136, 0)
		right.add_child(_name)
		_tier = UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
		right.add_child(_tier)
		_trait = UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
		right.add_child(_trait)
		add_child(right)

	func show_fed(fed: Dictionary, spins: int, spins_max: int, nudges: int) -> void:
		var catalog := Catalog.shared()
		_spins.set_dots(spins, spins_max)
		_nudges.set_dots(nudges, nudges)
		if fed.is_empty():
			_face.visible = false
			_name.text = "…"
			_tier.text = ""
			_trait.text = ""
			return
		var pet := Pet.from_dict(fed, catalog)
		_face.visible = true
		_face.set_pet(pet)
		_name.text = pet.display_name(catalog)
		var f := catalog.finish(pet.finish)
		_tier.text = catalog.tier_at(catalog.rank(pet.rarity)).name + ("" if f.id == "normal" else " " + str(f.name))
		_tier.add_theme_color_override("font_color", catalog.tier_color(pet.rarity))
		_trait.text = " ".join(PackedStringArray(pet.traits.map(func(t): return str(catalog.trait_info(t).get("name", t)))))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_t += delta
		_face.position = Vector2(size.x / 2.0 - _face.size.x / 2.0, 2.0 - absf(sin(_t * 2.2)) * 3.0)
		_face.rotation = sin(_t * 2.2) * 0.04

	func _draw() -> void:
		var c := size.x / 2.0
		var pts := PackedVector2Array()
		# the funnel: a wide curved top, narrowing into the cabinet
		for i in 9:
			pts.append(Vector2(lerpf(c - 90.0, c + 90.0, i / 8.0), 10.0 - sin(PI * i / 8.0) * 4.0))
		pts.append(Vector2(c + 36.0, size.y + 3.0))
		pts.append(Vector2(c - 36.0, size.y + 3.0))
		draw_colored_polygon(pts, UiTheme.PAGE.lerp(UiTheme.LILAC, 0.14))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, UiTheme.LILAC_SEAM, 3.0, true)


## A row of little dots: `n` lit out of `most` (at most 8 drawn, then a number).
class Dots extends Control:
	var color := UiTheme.PINK
	var n := 0
	var most := 0

	func _init() -> void:
		custom_minimum_size = Vector2(10, 10)
		size_flags_vertical = SIZE_SHRINK_CENTER
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_dots(p_n: int, p_most: int) -> void:
		n = p_n
		most = maxi(p_most, p_n)
		custom_minimum_size = Vector2(maxf(10.0, mini(most, 8) * 10.0 + (24.0 if most > 8 else 0.0)), 10)
		queue_redraw()

	func _draw() -> void:
		for i in mini(most, 8):
			var at := Vector2(5 + i * 10, 5)
			if i < n:
				draw_circle(at, 3.6, color)
			else:
				draw_arc(at, 3.2, 0, TAU, 12, UiTheme.MUTED_SEAM, 1.6, true)
		if most > 8:
			draw_string(UiTheme.BODY_FONT, Vector2(8 * 10 + 2, 9), "×%d" % n, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.SMALL - 1, color)


## A part's buttons under its reel: sewn on (pink), held on the reel (pink rings), room for more.
class Marks extends Control:
	var have := 0
	var held := 0
	var most := 5

	func _init() -> void:
		custom_minimum_size = Vector2(56, 11)
		mouse_filter = MOUSE_FILTER_IGNORE

	func set_marks(p_have: int, p_held: int, p_most: int) -> void:
		have = p_have
		held = p_held
		most = maxi(1, p_most)
		queue_redraw()

	func _draw() -> void:
		var step := size.x / most
		for i in most:
			var at := Vector2(step * (i + 0.5), size.y / 2.0)
			if i < have:
				draw_circle(at, 4.4, UiTheme.PINK)
				draw_circle(at + Vector2(-1.3, -1.3), 0.8, UiTheme.DEEP)
				draw_circle(at + Vector2(1.3, 1.3), 0.8, UiTheme.DEEP)
			elif i < have + held:
				draw_circle(at, 4.2, Color(UiTheme.PINK, 0.25))
				draw_arc(at, 3.7, 0, TAU, 14, UiTheme.PINK, 1.6, true)
			else:
				draw_circle(at, 3.0, UiTheme.DEEP)
				draw_arc(at, 3.0, 0, TAU, 12, UiTheme.LINE, 1.4, true)


## The row of bulbs across the top of the cabinet: they blink while the reels roll.
class Bulbs extends Control:
	var lit := false:
		set(v):
			if v != lit:
				lit = v
				queue_redraw()
	var _t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 10)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if lit:
			_t += delta
			queue_redraw()

	func _draw() -> void:
		var n := 18
		var span := size.x - 32.0
		var blink := int(_t * 4.0) % 2 == 0
		for i in n:
			var at := Vector2(16.0 + span * i / (n - 1), 5)
			var c := UiTheme.LILAC_SEAM
			if lit:
				c = UiTheme.PINK if i % 2 == 1 else (UiTheme.LILAC if blink else UiTheme.LILAC_SEAM)
			draw_circle(at, 4.0, c)


## One reel: three cells (above, the middle it landed on, below). It rolls, lands with a little
## bounce, rips on a crack; a banked reel gets a dashed pink edge, a full part shows one big button.
## The ▼ tab on top nudges it.
class ReelView extends Control:
	const SEQ := ["button", "blank", "crack", "blank", "blank", "button", "blank", "crack"]
	var nudge := Button.new()
	var wild := false
	var _strip: Array = ["blank", "blank", "blank"]
	var _banked := false
	var _full := false
	var _rolling := false
	var _roll := 0.0
	var _land := 0.0  # counts down after landing (the bounce)
	var _rip := 0.0  # counts down after a crack

	func _init() -> void:
		custom_minimum_size = Vector2(PlushieMachine.REEL_W, PlushieMachine.REEL_H)
		clip_contents = true
		mouse_filter = MOUSE_FILTER_IGNORE
		nudge.text = "▼"
		nudge.focus_mode = FOCUS_NONE
		nudge.tooltip_text = "nudge"
		nudge.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		nudge.add_theme_font_size_override("font_size", 9)
		for state in ["normal", "hover", "pressed"]:
			var sb := UiTheme.box(UiTheme.LILAC if state == "normal" else UiTheme.PINK, UiTheme.DEEP, 6, 1, 0)
			sb.corner_radius_top_left = 0
			sb.corner_radius_top_right = 0
			sb.content_margin_left = 7
			sb.content_margin_right = 7
			nudge.add_theme_stylebox_override(state, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color"]:
			nudge.add_theme_color_override(c, UiTheme.DEEP)
		nudge.visible = false
		add_child(nudge)

	func show_strip(strip: Array, banked: bool, full: bool) -> void:
		_strip = strip.duplicate()
		_banked = banked
		_full = full
		_rolling = false
		queue_redraw()

	func start_roll() -> void:
		_rolling = true
		nudge.visible = false
		queue_redraw()

	func landed() -> void:
		_rolling = false
		_land = 0.25
		queue_redraw()

	func rip() -> void:
		_rip = 0.9
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if _rolling:
			_roll += delta * 620.0
			queue_redraw()
		if _land > 0.0 or _rip > 0.0:
			_land = maxf(0.0, _land - delta)
			_rip = maxf(0.0, _rip - delta)
			queue_redraw()
		nudge.position = Vector2(size.x / 2.0 - nudge.size.x / 2.0, 0)

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		var edge := UiTheme.WISP if wild else (UiTheme.PINK_SEAM if _full else UiTheme.LINE)
		draw_style_box(UiTheme.box(UiTheme.RAISED.lerp(UiTheme.TEXT, 0.05), edge, 10, 2, 0), rect)
		var cell := size.y / 3.0
		var mid_px := 32
		var side_px := 24
		if _rolling:
			var span := cell * SEQ.size()
			var off := fmod(_roll, span)
			for k in SEQ.size() + 4:
				var y := k * cell - off
				if y > -cell and y < size.y:
					_symbol(str(SEQ[k % SEQ.size()]), Vector2(size.x / 2.0, y + cell / 2.0), side_px, 0.8)
		elif _full:
			_symbol("button", size / 2.0, mid_px + 6, 1.0)
		else:
			var bounce := sin(_land / 0.25 * PI) * 5.0 if _land > 0.0 else 0.0
			for k in 3:
				var a := 1.0 if k == 1 else (0.12 if _banked else 0.35)
				_symbol(str(_strip[k]), Vector2(size.x / 2.0, cell * (k + 0.5) + bounce), mid_px if k == 1 else side_px, a)
			if _rip > 0.0:
				# the crack tears across the middle, a little fluff pokes out
				var y := size.y / 2.0
				var a := minf(1.0, _rip * 2.0)
				var pts := PackedVector2Array()
				for i in 7:
					pts.append(Vector2(4.0 + (size.x - 8.0) * i / 6.0, y + (6.0 if i % 2 == 0 else -6.0)))
				draw_polyline(pts, Color(UiTheme.TEXT, a), 2.0, true)
				draw_circle(Vector2(size.x * 0.4, y + 9), 4.0, Color(UiTheme.WISP, a))
				draw_circle(Vector2(size.x * 0.55, y + 11), 3.0, Color(UiTheme.WISP, a))
		if _banked:
			draw_style_box(UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 10, 0), rect)

	func _symbol(sym: String, centre: Vector2, px: int, alpha: float) -> void:
		var tex := UiTheme.icon(PlushieMachine._icon_of(sym), px)
		if tex:
			draw_texture_rect(tex, Rect2(centre - Vector2(px, px) / 2.0, Vector2(px, px)), false, Color(1, 1, 1, alpha))


## The lever on the cabinet's side: tap it to spin; it swings down and back.
class Lever extends Control:
	signal pulled
	var enabled := true:
		set(v):
			if v != enabled:
				enabled = v
				queue_redraw()
	var _pull := 0.0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		tooltip_text = "spin"

	func pull() -> void:
		_pull = 0.26

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and enabled:
			accept_event()
			pulled.emit()

	func _process(delta: float) -> void:
		if _pull > 0.0:
			_pull = maxf(0.0, _pull - delta)
			queue_redraw()

	func _draw() -> void:
		var base := Vector2(12, size.y - 44)
		draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.LILAC_SEAM, 10, 3, 0), Rect2(base + Vector2(-8, -12), Vector2(30, 42)))
		var down := sin(_pull / 0.26 * PI) if _pull > 0.0 else 0.0
		var length := lerpf(100.0, -50.0, down)
		var top := base + Vector2(7, -length)
		draw_line(base + Vector2(7, 0), top, UiTheme.LILAC, 5.0, true)
		draw_circle(top, 12.0, UiTheme.DEEP)
		draw_circle(top, 10.0, UiTheme.PINK if enabled else UiTheme.PINK_SEAM)


## The effects over the whole page: sparkles, puffs of fluff, numbers floating up.
class Fx extends Control:
	var _bits: Array[Dictionary] = []
	var _floats: Array[Dictionary] = []

	func burst(at: Vector2, kind: String, n: int, color: Color) -> void:
		for i in n:
			var a := -PI / 2.0 + randf_range(-1.2, 1.2) if kind == "puff" else randf() * TAU
			var d := randf_range(22.0, 52.0) if kind == "puff" else randf_range(18.0, 48.0)
			_bits.append({ "from": at, "to": at + Vector2(cos(a), sin(a)) * d, "t": 0.0, "life": 1.0 if kind == "puff" else 0.7,
				"kind": kind, "color": color, "spin": randf() * TAU })

	func float_text(at: Vector2, text: String, icon: String, color: Color) -> void:
		_floats.append({ "at": at, "text": text, "icon": icon, "color": color, "t": 0.0 })

	func _process(delta: float) -> void:
		if _bits.is_empty() and _floats.is_empty():
			return
		for b in _bits:
			b.t += delta
		for f in _floats:
			f.t += delta
		_bits = _bits.filter(func(b): return b.t < b.life)
		_floats = _floats.filter(func(f): return f.t < 1.1)
		queue_redraw()

	func _draw() -> void:
		for b in _bits:
			var k := float(b.t) / float(b.life)
			var ease := 1.0 - pow(1.0 - k, 3.0)
			var at: Vector2 = b.from.lerp(b.to, ease)
			var c: Color = b.color
			if b.kind == "puff":
				var s := lerpf(0.4, 1.1, ease)
				var a := minf(0.95, 1.0 - k)
				draw_circle(at, 6.0 * s, Color(c, a))
				draw_circle(at + Vector2(-5, 4) * s, 4.5 * s, Color(c, a))
				draw_circle(at + Vector2(6, 5) * s, 4.0 * s, Color(c, a))
			else:
				draw_set_transform(at, float(b.spin) + k * PI, Vector2.ONE)
				draw_rect(Rect2(-3, -3, 6, 6), Color(c, 1.0 - k))
				draw_set_transform(Vector2.ZERO)
		for f in _floats:
			var k := float(f.t) / 1.1
			var ease := 1.0 - pow(1.0 - k, 3.0)
			var font := UiTheme.DISPLAY_FONT
			var text: String = f.text
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 17.0
			var at: Vector2 = f.at + Vector2(-w / 2.0, -34.0 * ease)
			var tex := UiTheme.icon(str(f.icon), 14)
			if tex:
				draw_texture_rect(tex, Rect2(at + Vector2(0, -12), Vector2(14, 14)), false, Color(1, 1, 1, 1.0 - k))
			draw_string(font, at + Vector2(17, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiTheme.DEEP, 1.0 - k))
			draw_string(font, at + Vector2(17, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(f.color, 1.0 - k))
