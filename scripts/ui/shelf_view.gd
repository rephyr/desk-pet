class_name ShelfView
extends HBoxContainer
## One rarity's shelf, opened: the herd as chips (plain and shiny, each a little pile and its
## count), the pets that are always cards (your active pet, favourites, holo and better, new parts),
## a stitched line, then the newest plain ones. The chosen pet's sticker is on the right, with the
## heart (favourite) and make active.
## Design: design/mockups/screens/pets-shelves.html (look A, "a shelf opened").

signal closed

const CARD_WIDTH := 80

var rarity := ""
var details := PetDetails.new()
var _box := PanelContainer.new()
var _head := HBoxContainer.new()
var _chips := HBoxContainer.new()
var _scroll := ScrollContainer.new()
var _list := VBoxContainer.new()
var _selected := ""
var _page := 0


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	var sb := UiTheme.box(UiTheme.PAPER, UiTheme.LILAC_SEAM, 14, 2, 10)
	sb.content_margin_bottom = 8
	_box.add_theme_stylebox_override("panel", sb)
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(_box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_box.add_child(col)
	_head.add_theme_constant_override("separation", 10)
	col.add_child(_head)
	_chips.add_theme_constant_override("separation", 10)
	col.add_child(_chips)
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_right", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_child(_list)
	_scroll.add_child(pad)
	col.add_child(_scroll)
	add_child(details)


## Opens a rarity's shelf, with `pet` chosen (or its first card).
func open(p_rarity: String, pet: Pet = null) -> void:
	if p_rarity != rarity:
		_page = 0
	rarity = p_rarity
	_selected = pet.uid if pet else ""
	rebuild()
	_scroll.scroll_vertical = 0


func rebuild() -> void:
	var catalog := Catalog.shared()
	var c := GameState.collection
	var color := catalog.tier_color(rarity)
	UiTheme.clear(_head)
	var back := UiTheme.small_button("‹ shelves", func(): closed.emit())
	back.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	back.add_theme_color_override("font_color", UiTheme.MUTED)
	back.add_theme_color_override("font_hover_color", UiTheme.PINK)
	_head.add_child(back)
	var tier_name := UiTheme.title(catalog.tier_at(catalog.rank(rarity)).name, 20, color)
	tier_name.size_flags_vertical = SIZE_SHRINK_CENTER
	_head.add_child(tier_name)
	var total := UiTheme.title(ExpandedView._thousands(c.count_of(rarity)), 20, UiTheme.TEXT)
	total.size_flags_vertical = SIZE_SHRINK_CENTER
	_head.add_child(total)

	# the herd: a chip per plain finish that has anyone folded into it
	UiTheme.clear(_chips)
	for f in catalog.finishes:
		var k := Herd.key(rarity, f.id)
		var n := c.herd_count(k)
		if n <= 0 or not Herd.plain(catalog, f.id):
			continue
		var shiny: bool = f.id != "normal"
		_chips.add_child(_chip(GameState.herd_faces({ k: n }, 12, 40 + catalog.rank(rarity)), n,
			"✦ " + str(f.name) if shiny else "plain", UiTheme.GOLD if shiny else UiTheme.MUTED, 34.0 if shiny else 46.0, 8 if shiny else 12))
	_chips.visible = _chips.get_child_count() > 0

	# the cards: always-cards first, then the newest plain ones
	var split := GameState.shelf_split(rarity)
	var always: Array[Pet] = split[0]
	var newest: Array[Pet] = split[1]
	var per := int(catalog.herd.get("shelf_page", 30))
	var pages := maxi(1, ceili(always.size() / float(per)))
	_page = clampi(_page, 0, pages - 1)
	var shown_always := always.slice(_page * per, (_page + 1) * per)
	if _selected == "" or c.get_pet(_selected) == null or c.get_pet(_selected).rarity != rarity:
		_selected = shown_always[0].uid if not shown_always.is_empty() else (newest[0].uid if not newest.is_empty() else "")

	UiTheme.clear(_list)
	if not shown_always.is_empty():
		_list.add_child(_flow(shown_always, 0))
	if pages > 1:
		var pager := HBoxContainer.new()
		pager.alignment = BoxContainer.ALIGNMENT_CENTER
		pager.add_theme_constant_override("separation", 8)
		pager.add_child(UiTheme.small_button("‹", func():
			_page = maxi(0, _page - 1)
			rebuild()))
		pager.add_child(UiTheme.label("%d of %d" % [_page + 1, pages], UiTheme.MUTED, UiTheme.SMALL))
		pager.add_child(UiTheme.small_button("›", func():
			_page = mini(pages - 1, _page + 1)
			rebuild()))
		_list.add_child(pager)
	if not shown_always.is_empty() and not newest.is_empty():
		_list.add_child(UiTheme.stitch_line())
	if not newest.is_empty():
		_list.add_child(_flow(newest, shown_always.size()))
	details.show_pet(c.get_pet(_selected) if _selected != "" else null)


## The pet on the shelf that's chosen (its sticker is showing), or "".
func selected() -> String:
	return _selected


func _flow(pets: Array[Pet], start: int) -> Control:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 12)
	flow.size_flags_horizontal = SIZE_EXPAND_FILL
	for i in pets.size():
		var mini := MiniCard.new(pets[i], CARD_WIDTH)
		mini.set_selected(pets[i].uid == _selected)
		mini.pressed.connect(_pick)
		flow.add_child(Tilted.new(mini, [-2.0, 1.5, -1.0, 2.0, -1.5, 1.0][(start + i) % 6]))
	return flow


func _pick(pet: Pet) -> void:
	_selected = pet.uid
	for flow in _list.get_children():
		for holder in flow.get_children():
			if holder is Tilted and holder.get_child(0) is MiniCard:
				var mini: MiniCard = holder.get_child(0)
				mini.set_selected(mini.pet.uid == pet.uid)
	details.show_pet(pet)


static func _chip(faces: Array, n: int, text: String, color: Color, pile_w: float, pile_max: int) -> Control:
	var chip := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 12
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	var pile := Mound.new(faces, Herd.mound_size(Catalog.shared(), n, pile_max), pile_w, 26.0)
	pile.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(pile)
	var words := UiTheme.label(text, color, UiTheme.SMALL)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(words)
	var count := UiTheme.title(ExpandedView._thousands(n), 16, UiTheme.TEXT)
	count.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(count)
	return chip
