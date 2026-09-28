class_name DungeonView
extends HBoxContainer
## The dungeon page in adventures (adventures | upgrades | dungeon), look A: the old well as a
## tall drawn cross-section on the left (WellColumn, in a scroll), the army in the middle (the front
## row of card pets with your pet's flag, the herd taken by the shelf, the entrance), the orders
## card and the last run on the right. Floor strength is never a number, only a feeling word; pets
## that don't come back are never named. Rules in Dungeon, state in GameState: this only shows them
## and passes on clicks.

const PICK_PAGE := 20
const PICK_COLUMNS := 5
const HERD_STEP := 10

var _column := WellColumn.new()
var _scroll := ScrollContainer.new()
var _mid := VBoxContainer.new()
var _side := VBoxContainer.new()
var _picking := false
var _page := 0
var _dirty := true  # the dungeon itself changed: rebuild
var _maybe := false  # pets came or went: rebuild only if something the page shows changed (_key)
var _last_key := ""
var _check := 0.0
var _followed := false  # scrolled to where the army is since the page was shown
var _running := false
var _tick := 0.0
var _follow_floor := -1  # the landing the scroll last followed the army to (you can scroll away in between)


func _init() -> void:
	add_theme_constant_override("separation", 12)
	size_flags_vertical = SIZE_EXPAND_FILL
	# the well
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(224, 0)
	well.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 12, 2, 0))
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 0)
	well.add_child(wcol)
	var head := MarginContainer.new()
	for side in [["left", 12], ["top", 8], ["right", 12], ["bottom", 4]]:
		head.add_theme_constant_override("margin_" + side[0], side[1])
	head.add_child(UiTheme.title("the old well", 18))
	wcol.add_child(head)
	wcol.add_child(UiTheme.stitch_line())
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_column.size_flags_vertical = SIZE_EXPAND_FILL  # the soil goes all the way down
	_scroll.add_child(_column)
	wcol.add_child(_scroll)
	add_child(well)
	_mid.size_flags_horizontal = SIZE_EXPAND_FILL
	_mid.add_theme_constant_override("separation", 12)
	add_child(_mid)
	_side.custom_minimum_size = Vector2(262, 0)
	_side.add_theme_constant_override("separation", 14)
	add_child(_side)
	GameState.dungeon_changed.connect(func():
		_dirty = true
		if is_visible_in_tree() and not GameState.dungeon_news.is_empty():
			speak())
	# workers add pets many times a second later on: these only rebuild when the page would look different
	GameState.collection.herd_changed.connect(func(_k): _maybe = true)
	GameState.collection.pets_added.connect(func(_p): _maybe = true)
	GameState.collection.pets_removed.connect(func(_u): _maybe = true)
	GameState.jobs_changed.connect(func(): _maybe = true)
	GameState.adventures_changed.connect(func(): _maybe = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_followed = false
			_picking = false
			_rebuild())


## Your pet says something about the dungeon: news first, then how the army's doing.
func speak() -> void:
	var news := GameState.take_announcement()
	if news != "":
		PetBubble.say(self, news)
		return
	var n := GameState.take_dungeon_news()
	if not n.is_empty():
		var key := "dungeon_deepest" if n.deepest else ("dungeon_home_early" if n.early else "dungeon_home")
		PetBubble.say_line(self, key, { "got": UiTheme.num(int(n.got)), "floor": int(n.floor) })
		return
	if GameState.dungeon_running():
		PetBubble.say_line(self, "dungeon_running", { "floor": maxi(1, ceili(GameState.dungeon_floor_now())) })
	elif int(GameState.army().sent) == 0:
		PetBubble.say_line(self, "dungeon_empty")
	else:
		PetBubble.say_line(self, "dungeon")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_check -= delta
	if _dirty:
		_rebuild()
	elif _maybe and _check <= 0.0 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):  # never under a click
		_maybe = false
		_check = 0.5
		if _key(GameState.army()) != _last_key:
			_rebuild()
	if GameState.dungeon_running():
		_column.tick()
		var at := floori(GameState.dungeon_floor_now())
		if at != _follow_floor:
			_follow_floor = at
			_follow()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		if GameState.dungeon_running() != _running:
			_rebuild()


## Keeps the walking army in view (and on first show, the deepest lit landing).
func _follow() -> void:
	var h := _scroll.size.y
	if h <= 0.0:
		return
	var want := _column.party_y() - h / 2.0 if GameState.dungeon_running() else _column.y_at(maxi(int(GameState.dungeon.deep), 1)) - h * 0.6
	_scroll.scroll_vertical = int(clampf(want, 0.0, maxf(0.0, _column.custom_minimum_size.y - h)))


## What the page shows that pets coming and going can change: the army, what each shelf has room
## for, your pet, the cards to pick from.
func _key(a: Dictionary) -> String:
	var key := "%s|%s|%s|%d|%s|%s" % [str(a.cards.map(func(p): return p.uid)), str(a.keys), str(GameState.dungeon.cards),
		int(a.sent), GameState.collection.active_uid, str(GameState.dungeon_running())]
	for tier in GameState.catalog.tiers:
		key += "|%d" % GameState.army_herd_room(tier.id)
	if _picking:
		key += "|%d" % GameState.resting_cards().size()
	return key


func _rebuild() -> void:
	_dirty = false
	_running = GameState.dungeon_running()
	if _running:
		_picking = false
	var a := GameState.army()
	var rules := GameState.army_rules(a) if int(a.sent) > 0 else {}
	_last_key = _key(a)
	_column.refresh(a, rules)
	_build_mid(a)
	_build_side(a, rules)
	if not _followed:
		_followed = true
		_follow.call_deferred()


# ---- the army ------------------------------------------------------------------------

func _build_mid(a: Dictionary) -> void:
	UiTheme.clear(_mid)
	if _picking:
		_mid.add_child(_picker(a))
		return
	var front_n := int(GameState.catalog.dungeon.get("front_row", 20))
	var cards: Array = a.cards
	# the front row: your pet's flag, then the strongest front_n; the rest walk behind
	var front := _sticker()
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 9)
	front.add_child(fcol)
	var head := HBoxContainer.new()
	head.add_child(_h3("front row"))
	head.add_child(UiTheme.spacer())
	if cards.size() > front_n:
		head.add_child(UiTheme.label("+%s" % UiTheme.num(cards.size() - front_n), UiTheme.MUTED, UiTheme.SMALL))
	fcol.add_child(head)
	var row := FrontRow.new(GameState.collection.active(), cards, not _running, front_n)
	row.pressed.connect(_open_picker)
	fcol.add_child(row)
	_mid.add_child(front)

	# the herd: a mound, a stepper per shelf, the entrance
	var herd := _sticker()
	herd.size_flags_vertical = SIZE_EXPAND_FILL
	var hcol := VBoxContainer.new()
	hcol.add_theme_constant_override("separation", 8)
	herd.add_child(hcol)
	var top := HBoxContainer.new()
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 6)
	names.add_child(_h3("the herd"))
	var total := Herd.total(GameState.army_herd_keys())
	names.add_child(UiTheme.title(UiTheme.num(total), 22, UiTheme.TEXT))
	top.add_child(names)
	top.add_child(UiTheme.spacer())
	var faces := GameState.herd_faces(GameState.army_herd_keys(), 24, 3)
	var mound := Mound.new(faces, Herd.mound_size(GameState.catalog, total, 40), 120.0, 40.0)
	mound.size_flags_vertical = SIZE_SHRINK_END
	top.add_child(mound)
	hcol.add_child(top)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	var catalog := GameState.catalog
	for tier in catalog.tiers:
		var room := GameState.army_herd_room(tier.id)
		var have := int(a.herd.get(tier.id, 0))
		if room <= 0 and have <= 0:
			continue
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var tname := VBoxContainer.new()
		tname.add_theme_constant_override("separation", -2)
		tname.add_child(UiTheme.label(str(tier.name), catalog.tier_color(tier.id), UiTheme.SMALL + 1))
		tname.add_child(UiTheme.label("of %s" % UiTheme.num(room), UiTheme.MUTED, UiTheme.SMALL - 1))
		tname.size_flags_horizontal = SIZE_EXPAND_FILL
		r.add_child(tname)
		var full := int(a.sent) >= int(a.entrance)
		r.add_child(_stepper(UiTheme.num(have), func(): _herd(tier.id, have - HERD_STEP), func(): _herd(tier.id, have + HERD_STEP),
			have > 0 and not _running, have < room and not full and not _running, 48))
		rows.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	hcol.add_child(scroll)
	hcol.add_child(UiTheme.stitch_line())
	var gate := HBoxContainer.new()
	gate.add_theme_constant_override("separation", 8)
	gate.add_child(UiTheme.label("the entrance", UiTheme.MUTED, UiTheme.SMALL))
	var full := int(a.sent) >= int(a.entrance)
	var meter := UiTheme.bar(UiTheme.PINK if full else UiTheme.LILAC)
	meter.max_value = float(a.entrance)
	meter.value = float(a.sent)
	gate.add_child(meter)
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 3)
	count.add_child(UiTheme.title(UiTheme.num(int(a.sent)), 15, UiTheme.PINK if full else UiTheme.TEXT))
	var of := UiTheme.label("/ %s" % UiTheme.num(int(a.entrance)), UiTheme.MUTED, UiTheme.SMALL)
	of.size_flags_vertical = SIZE_SHRINK_END
	count.add_child(of)
	gate.add_child(count)
	hcol.add_child(gate)
	_mid.add_child(herd)


func _herd(rarity: String, n: int) -> void:
	var a := GameState.army()
	var had := int(a.sent)
	GameState.set_army_herd(rarity, n)
	if n > int(a.herd.get(rarity, 0)) and int(GameState.army().sent) == had and had >= int(a.entrance):
		PetBubble.say_line(self, "dungeon_full")


func _open_picker() -> void:
	if _running:
		return
	_picking = true
	_page = 0
	_build_mid(GameState.army())


## The cards to pick from, over the middle column: resting cards and the army's, strongest first.
func _picker(a: Dictionary) -> Control:
	var panel := _sticker()
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_h3("front row"))
	head.add_child(UiTheme.spacer())
	var best := UiTheme.button("best ones", func():
		GameState.army_best()
		PetBubble.say_line(self, "dungeon_best"))
	best.add_theme_font_size_override("font_size", UiTheme.SMALL)
	head.add_child(best)
	var done := UiTheme.button("done", func():
		_picking = false
		_rebuild())
	done.add_theme_font_size_override("font_size", UiTheme.SMALL)
	head.add_child(done)
	col.add_child(head)
	var choices := GameState.army_choices()
	var in_army := {}
	for pet in a.cards:
		in_army[pet.uid] = true
	var pages := maxi(1, ceili(choices.size() / float(PICK_PAGE)))
	_page = clampi(_page, 0, pages - 1)
	var grid := GridContainer.new()
	grid.columns = PICK_COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for pet in choices.slice(_page * PICK_PAGE, (_page + 1) * PICK_PAGE):
		grid.add_child(_chip(pet, in_army.has(pet.uid)))
	col.add_child(grid)
	if pages > 1:
		var pager := HBoxContainer.new()
		pager.add_child(UiTheme.spacer())
		pager.add_child(UiTheme.small_button("‹", func():
			_page -= 1
			_build_mid(GameState.army())))
		pager.add_child(UiTheme.label("%d of %d" % [_page + 1, pages], UiTheme.MUTED, UiTheme.SMALL))
		pager.add_child(UiTheme.small_button("›", func():
			_page += 1
			_build_mid(GameState.army())))
		col.add_child(pager)
	return panel


## One card you could put in the army: picked ones are stitched and tilted.
func _chip(pet: Pet, picked: bool) -> Control:
	var catalog := GameState.catalog
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(50, 46)
	b.tooltip_text = "%s (%s)" % [pet.display_name(catalog), catalog.tier_at(catalog.rank(pet.rarity)).name]
	var sb: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.PINK_PRESSED, 8, 2) if picked else UiTheme.box(UiTheme.DEEP, catalog.tier_color(pet.rarity).lerp(UiTheme.LINE, 0.5), 8, 2, 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb if picked else UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 2))
	b.add_theme_stylebox_override("pressed", sb)
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet)
	b.add_child(portrait)
	b.resized.connect(func(): portrait.position = b.size / 2.0 - portrait.custom_minimum_size / 2.0)
	b.pressed.connect(func():
		if not GameState.set_army_card(pet.uid, not picked) and not picked:
			PetBubble.say_line(self, "dungeon_full")
		_build_mid(GameState.army()))
	return Tilted.new(b, -3.0 if picked else 0.0)


# ---- the orders and the last run --------------------------------------------------------

func _build_side(a: Dictionary, rules: Dictionary) -> void:
	UiTheme.clear(_side)
	var catalog := GameState.catalog
	var state: Dictionary = GameState.dungeon
	var card := PanelContainer.new()
	var sb := UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 10)
	sb.border_width_top = 6
	sb.border_color = UiTheme.LILAC_SEAM
	sb.content_margin_top = 10
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	card.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	card.add_child(col)
	col.add_child(UiTheme.title("orders", 16, UiTheme.LILAC))
	var target := int(state.target)
	var line1 := _line()
	line1.add_child(UiTheme.label("go down to floor", UiTheme.TEXT, UiTheme.SMALL))
	line1.add_child(_stepper(str(target), func(): GameState.set_order("target", -1), func(): GameState.set_order("target", 1),
		target > 1 and not _running, target < Dungeon.target_max(catalog, state) and not _running, 22))
	var words := GameState.floor_words(target, target, rules) if not rules.is_empty() else {}
	if words.has(target):
		line1.add_child(_feel(words[target], target <= int(state.deep)))
	col.add_child(line1)
	var home_steps: Array = catalog.dungeon.home_at.map(func(v): return int(v))
	var hi := home_steps.find(int(state.home_at))
	var line2 := _line()
	line2.add_child(UiTheme.label("come home when", UiTheme.TEXT, UiTheme.SMALL))
	line2.add_child(_stepper("%d%%" % int(state.home_at), func(): GameState.set_order("home", -1), func(): GameState.set_order("home", 1),
		hi > 0 and not _running, hi < home_steps.size() - 1 and not _running, 30))
	line2.add_child(UiTheme.label("are gone", UiTheme.TEXT, UiTheme.SMALL))
	col.add_child(line2)
	if Dungeon.first_earned(catalog, state):
		var lines: Array = catalog.dungeon.first.lines
		var fi := lines.find(str(state.first))
		var line3 := _line()
		line3.add_child(UiTheme.label("who goes first", UiTheme.TEXT, UiTheme.SMALL))
		line3.add_child(_stepper(str(state.first), func(): GameState.set_order("first", -1), func(): GameState.set_order("first", 1),
			fi > 0 and not _running, fi < lines.size() - 1 and not _running, 76))
		col.add_child(line3)
	var go := UiTheme.button("on the way…" if _running else "down we go!", func():
		if GameState.send_army():
			PetBubble.say_line(self, "dungeon_go"))
	go.disabled = _running or int(a.sent) == 0
	var go_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 7)
	go_sb.content_margin_left = 14
	go_sb.content_margin_right = 14
	go.add_theme_stylebox_override("normal", go_sb)
	go.add_theme_stylebox_override("disabled", go_sb)
	if _running:
		go.add_theme_color_override("font_disabled_color", UiTheme.PINK)
	col.add_child(go)
	_side.add_child(Tilted.new(card, -1.2))

	var last: Dictionary = state.last
	if last.is_empty():
		return
	var lastc := _sticker()
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 6)
	lastc.add_child(lcol)
	lcol.add_child(_h3("last time"))
	lcol.add_child(_last_row("got to", UiTheme.title("floor %d" % int(last.floor), 16, UiTheme.TEXT)))
	var got := HBoxContainer.new()
	got.add_theme_constant_override("separation", 5)
	got.add_child(UiTheme.icon_rect("lantern", 15, UiTheme.WISP))
	got.add_child(UiTheme.title(UiTheme.num(int(last.got)), 16, UiTheme.WISP))
	lcol.add_child(_last_row("brought home", got))
	lcol.add_child(_last_row("came home", UiTheme.title(UiTheme.num(int(last.back)), 16, UiTheme.TEXT)))
	_side.add_child(lastc)


func _last_row(what: String, value: Control) -> Control:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 8)
	var l := UiTheme.label(what, UiTheme.MUTED, UiTheme.SMALL + 1)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	r.add_child(l)
	r.add_child(value)
	return r


## An orders line: words and steppers that wrap if they have to (never past the card).
func _line() -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 4)
	return f


## The feeling word for a floor, as a little pill.
func _feel(word: Array, passed: bool) -> Control:
	var p := PanelContainer.new()
	var color := UiTheme.MUTED
	var border := UiTheme.LINE
	if not passed:
		match str(word[1]):
			"mid":
				color = UiTheme.TEXT
				border = UiTheme.LILAC.lerp(UiTheme.LINE, 0.65)
			"hot":
				color = UiTheme.PINK
				border = UiTheme.PINK_SEAM
	var sb := UiTheme.box(UiTheme.DEEP, border, 999, 2, 0)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(str(word[0]), color, UiTheme.SMALL - 1))
	return p


## ‹ value ›: never a dropdown (their popups open behind the always-on-top window).
func _stepper(text: String, less: Callable, more: Callable, can_less: bool, can_more: bool, min_w := 40) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 1))
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	p.add_child(row)
	for side in [["‹", less, can_less], ["value", Callable(), true], ["›", more, can_more]]:
		if side[0] == "value":
			var v := UiTheme.label(text, UiTheme.TEXT, UiTheme.SMALL)
			v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			v.custom_minimum_size = Vector2(min_w, 0)
			row.add_child(v)
			continue
		var b := UiTheme.small_button(side[0], side[1])
		b.custom_minimum_size = Vector2(16, 20)
		b.disabled = not side[2]
		b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		b.add_theme_color_override("font_color", UiTheme.MUTED)
		b.add_theme_color_override("font_disabled_color", Color(UiTheme.MUTED, 0.35))
		var flat := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(state, flat)
		row.add_child(b)
	return p


func _sticker() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LINE, 12, UiTheme.RAISED, 11))
	return p


func _h3(text: String) -> Label:
	return UiTheme.title(text, 15, UiTheme.LILAC)
