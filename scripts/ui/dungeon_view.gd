class_name DungeonView
extends HBoxContainer
## The dungeon page in adventures (adventures | upgrades | dungeon), look A: the old well as a
## tall drawn cross-section on the left (WellColumn, in a scroll), the army in the middle (the front
## row of card pets with your pet's flag, the herd taken by the shelf, the entrance), the orders
## card and the last run on the right. Floor strength is never a number, only a feeling word; pets
## that don't come back are never named. Rules in Dungeon, state in GameState: this only shows them
## and passes on clicks.
## Once the tiny key is found, the well's floor 20 has a little pink door: tapping it slides the column
## over to the sewing room (SewingRoom, header "‹ the sewing room"; ‹ slides back). The front row's
## cards that match the room's chalk lock get a chalk tick then.
## The wisps perks hang on nails down the well's left lane (WellColumn, PerkNail): tapping one puts
## its card where "last time" sits (the thing, level pips, what it does as a number, the buy button
## with its wisps price); ✕ brings "last time" back.
## Held landings (HoldSpot on the column, every 10th landing cleared): tapping one puts the hold card
## there instead ("landing 20" + ✕, a coral pennant once it's held, the crowd, how many, what they
## hold; while it fills a meter, a ‹ n › per shelf with pets that may go, "hold on tight!"). Once a
## landing is fully held the orders card gets "start from ‹the top | landing N›".

const PICK_PAGE := 20
const PICK_COLUMNS := 5
const HERD_STEP := 10

var _column := WellColumn.new()
var _scroll := ScrollContainer.new()
var _pan := Control.new()  # the column: the well, and the sewing room slid in beside it
var _rooms := SewingRoom.new()
var _title: Label
var _back: Button
var _in_rooms := false  # the column shows the sewing room
var _slide := 0.0  # 0 = the well, 1 = the sewing room
var _tween: Tween
var _mid := VBoxContainer.new()
var _side := VBoxContainer.new()
var _picking := false
var _page := 0
var _dirty := true  # the dungeon itself changed: rebuild
var _maybe := false  # pets came or went: rebuild only if something the page shows changed (_key)
var _last_key := ""
var _check := 0.0
var _followed := false  # scrolled to where the army is since the page was shown
var _door_seen := false  # the sewing room's door was there at the last rebuild
var _show_door := false  # the door just turned up: the next follow scrolls to it
var _built := false  # the page has been built once (the door seen then isn't new)
var _running := false
var _tick := 0.0
var _follow_floor := -1  # the landing the scroll last followed the army to (you can scroll away in between)
var _nail := ""  # the perk whose card is open in the side column ("" = the last run's card)
var _reveal := ""  # a perk's nail to scroll into view after the next rebuild
var _hold_f := 0  # the held landing whose card is open (0: none)
var _send := {}  # the hold card's steppers: rarity -> how many to send
var _reveal_hold := 0  # a held landing to scroll into view after the next rebuild
var _hold_scroll: ScrollContainer = null  # the open hold card's shelf list (its scroll is kept across rebuilds)
var _hold_scroll_f := 0  # the landing that list belongs to


func _init() -> void:
	add_theme_constant_override("separation", 10)  # (12 before the well got its nails lane)
	size_flags_vertical = SIZE_EXPAND_FILL
	# the well
	var well := PanelContainer.new()
	well.custom_minimum_size = Vector2(236, 0)  # the nails' lane down the left, the well right of the middle
	well.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 12, 2, 0))
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 0)
	well.add_child(wcol)
	var head := MarginContainer.new()
	for side in [["left", 12], ["top", 8], ["right", 12], ["bottom", 4]]:
		head.add_theme_constant_override("margin_" + side[0], side[1])
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 2)
	_back = UiTheme.small_button("‹", func(): show_rooms(false))
	_back.custom_minimum_size = Vector2(14, 0)
	_back.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	_back.add_theme_color_override("font_color", UiTheme.MUTED)
	_back.add_theme_color_override("font_hover_color", UiTheme.PINK)
	for state in ["normal", "hover", "pressed", "focus"]:
		_back.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_back.visible = false
	hrow.add_child(_back)
	_title = UiTheme.title("the old well", 18)
	hrow.add_child(_title)
	head.add_child(hrow)
	wcol.add_child(head)
	wcol.add_child(UiTheme.stitch_line())
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.size_flags_horizontal = SIZE_EXPAND_FILL
	_column.size_flags_vertical = SIZE_EXPAND_FILL  # the soil goes all the way down
	_scroll.add_child(_column)
	_pan.size_flags_vertical = SIZE_EXPAND_FILL
	_pan.clip_contents = true
	_pan.add_child(_scroll)
	_pan.add_child(_rooms)
	_pan.resized.connect(_lay_pan)
	_rooms.room_changed.connect(func(): _dirty = true)
	wcol.add_child(_pan)
	add_child(well)
	_column.door_pressed.connect(func():
		show_rooms(true)
		PetBubble.say_line(self, "sewing_door"))
	_column.nail_pressed.connect(pick_nail)
	_column.hold_pressed.connect(pick_hold)
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
	tree_exiting.connect(func(): GameState.army_held = false)
	visibility_changed.connect(func():
		_hold()
		if is_visible_in_tree():
			_followed = false
			_picking = false
			_drop_nail()
			if not GameState.sewing_open():
				show_rooms(false, false)
			_rebuild())


## The column slides over to the sewing room (or back to the well).
func show_rooms(on: bool, animate := true) -> void:
	on = on and GameState.sewing_open()
	if on == _in_rooms:
		return
	_in_rooms = on
	_hold()
	if on:
		_rooms.to_next()
		_drop_nail()
	_back.visible = on
	_title.text = "the sewing room" if on else "the old well"
	_dirty = true
	if _tween:
		_tween.kill()
	if animate and is_visible_in_tree():
		_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_tween.tween_method(func(t: float):
			_slide = t
			_lay_pan(), _slide, 1.0 if on else 0.0, 0.45)
	else:
		_slide = 1.0 if on else 0.0
		_lay_pan()


## While the sewing room shows, your pet leading the army waits at home instead of taking it down
## the well again (so there's a turn for the room).
func _hold() -> void:
	GameState.army_held = _in_rooms and is_visible_in_tree()


## Whether the column shows the sewing room.
func in_rooms() -> bool:
	return _in_rooms


## The sewing room pane (for flows).
func rooms() -> SewingRoom:
	return _rooms


## The well and the sewing room side by side in the column, slid `_slide` of the way over.
func _lay_pan() -> void:
	var sz := _pan.size
	_scroll.size = sz
	_rooms.size = sz
	_scroll.position = Vector2(-_slide * sz.x, 0)
	_rooms.position = Vector2((1.0 - _slide) * sz.x, 0)
	_scroll.visible = _slide < 0.999
	_rooms.visible = _slide > 0.001


## Your pet says something about the dungeon: news first, then how the army's doing.
func speak() -> void:
	var news := GameState.take_announcement()
	if news != "":
		PetBubble.say(self, news)
		return
	var n := GameState.take_dungeon_news()
	if bool(n.get("nail", false)):
		PetBubble.say_line(self, "perk_nail")
		return
	if n.has("room"):
		var key := "sewing_stuck" if not n.cleared else ("sewing_again" if n.again else "sewing_home")
		PetBubble.say_line(self, key, { "got": UiTheme.num(int(n.got)), "room": str(n.room) })
		return
	if GameState.dungeon_running() and GameState.dungeon.run.has("room"):
		PetBubble.say_line(self, "sewing_running", { "room": str(GameState.sew_room(int(GameState.dungeon.run.room)).name) })
		return
	if _in_rooms and n.is_empty() and not GameState.dungeon_running():
		PetBubble.say_line(self, "sewing")
		return
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
	if not _followed and _scroll.size.y > 0.0 and _column.size.y >= _column.custom_minimum_size.y - 0.5:
		_followed = true  # once the column has its size: scroll to where the army is
		_follow()
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
	if _show_door and _column.door_y() >= 0.0:
		want = _column.door_y() - h * 0.5
	_show_door = false
	_scroll.scroll_vertical = int(clampf(want, 0.0, maxf(0.0, _column.custom_minimum_size.y - h)))


## What the page shows that pets coming and going can change: the army, what each shelf has room
## for, your pet, the cards to pick from.
func _key(a: Dictionary) -> String:
	var key := "%s|%s|%s|%d|%s|%s|%s" % [str(a.cards.map(func(p): return p.uid)), str(a.keys), str(GameState.dungeon.cards),
		int(a.sent), GameState.collection.active_uid, str(GameState.dungeon_running()), str(GameState.sewing_open())]
	var hold_open := _hold_f > 0 and not Dungeon.is_held(GameState.catalog, GameState.dungeon, _hold_f)
	for tier in GameState.catalog.tiers:
		key += "|%d" % GameState.army_herd_room(tier.id)
		if hold_open:  # (capped at what the landing still needs: steady once the herd outgrows it)
			key += "/%d" % GameState.hold_can_go(_hold_f, tier.id)
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
	if not GameState.sewing_open() and _in_rooms:
		show_rooms(false, false)
	_rooms.refresh(a, rules)
	_build_mid(a)
	_build_side(a, rules)
	var door := GameState.sewing_open()
	if door and not _door_seen and (_built or int(GameState.sewing.cleared) == 0):
		_followed = false  # the door just turned up (or nobody's been in yet this time): show it
		_show_door = true
	_door_seen = door
	_built = true
	if _reveal != "":
		_show_nail.call_deferred(_reveal)
		_reveal = ""
	elif _reveal_hold > 0:
		_show_hold.call_deferred(_reveal_hold)
		_reveal_hold = 0


# ---- the army ------------------------------------------------------------------------

func _build_mid(a: Dictionary) -> void:
	UiTheme.clear(_mid)
	if _picking:
		_mid.add_child(_picker(a))
		return
	var front_n := GameState.front_row_size()
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
	var ticks: Array = Sewing.ticks(GameState.sew_room(_rooms.room), cards.slice(0, front_n)) if _in_rooms else []
	var row := FrontRow.new(GameState.collection.active(), cards, not _running, front_n, ticks)
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
	grid.add_theme_constant_override("h_separation", 5)  # (6 before the well got its nails lane)
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
	var keep := 0  # (the open hold card's shelf list stays where it was scrolled to)
	if is_instance_valid(_hold_scroll) and _hold_scroll_f == _hold_f:
		keep = _hold_scroll.scroll_vertical
	_hold_scroll = null
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
	var starts := Dungeon.starts(catalog, state)
	var start := int(state.start)
	if starts.size() > 1:  # once a landing is fully held
		var si := starts.find(start)
		var line0 := _line()
		line0.add_child(UiTheme.label("start from", UiTheme.TEXT, UiTheme.SMALL))
		line0.add_child(_stepper("landing %d" % start if start > 0 else "the top", func(): GameState.set_order("start", -1),
			func(): GameState.set_order("start", 1), si > 0 and not _running, si < starts.size() - 1 and not _running, 64))
		col.add_child(line0)
	var target := int(state.target)
	var line1 := _line()
	line1.add_child(UiTheme.label("go down to floor", UiTheme.TEXT, UiTheme.SMALL))
	line1.add_child(_stepper(str(target), func(): GameState.set_order("target", -1), func(): GameState.set_order("target", 1),
		target > start + 1 and not _running, target < Dungeon.target_max(catalog, state) and not _running, 22))
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
		var from := int(GameState.dungeon.start)
		if GameState.send_army():
			if from > 0:
				PetBubble.say_line(self, "dungeon_go_from", { "f": from })
			else:
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

	if _nail != "" and _nail in GameState.perks_shown():
		_side.add_child(_nail_card(_nail))
		return
	if _hold_f > 0 and _hold_f in GameState.hold_spots():
		_side.add_child(_hold_card(_hold_f, keep))
		return
	_drop_nail()  # (the nail or the landing stopped showing: its ring goes too)
	var last: Dictionary = state.last
	if last.is_empty():
		return
	var lastc := _sticker()
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 6)
	lastc.add_child(lcol)
	lcol.add_child(_h3("last time"))
	var where := str(GameState.sew_room(int(last.room)).name) if last.has("room") else "floor %d" % int(last.floor)
	var where_label := UiTheme.title(where, 16, UiTheme.TEXT)
	lcol.add_child(_last_row("went to" if last.has("room") else "got to", where_label))
	var got := HBoxContainer.new()
	got.add_theme_constant_override("separation", 5)
	got.add_child(UiTheme.icon_rect("lantern", 15, UiTheme.WISP))
	got.add_child(UiTheme.title(UiTheme.num(int(last.got)), 16, UiTheme.WISP))
	lcol.add_child(_last_row("brought home", got))
	lcol.add_child(_last_row("came home", UiTheme.title(UiTheme.num(int(last.back)), 16, UiTheme.TEXT)))
	_side.add_child(lastc)


# ---- the wisps perks on the well wall ------------------------------------------------------

## Opens a perk's card in the side column (a tap on its nail), or closes it with "".
func pick_nail(id: String) -> void:
	_hold_f = 0
	_column.set_hold_picked(0)
	_nail = id
	_column.set_picked(id)
	_reveal = id
	_dirty = true


## Opens a held landing's card in the side column (a tap on its crowd or pill), or closes it with 0.
func pick_hold(f: int) -> void:
	_nail = ""
	_column.set_picked("")
	if f != _hold_f:
		_send = {}
	_hold_f = f
	_column.set_hold_picked(f)
	_reveal_hold = f
	_dirty = true


## No perk or landing card open, and no ring on any nail or pill ("last time" is back).
func _drop_nail() -> void:
	_nail = ""
	_column.set_picked("")
	_hold_f = 0
	_send = {}
	_column.set_hold_picked(0)


## Scrolls the well so a perk's nail is in view (a picked one, or the tips when they first hang).
func _show_nail(id: String) -> void:
	await get_tree().process_frame  # the column has its new size by then
	_show_in_well(_column.nail(id))


## Scrolls the well so a held landing's crowd and pill are in the middle (its card just opened).
func _show_hold(f: int) -> void:
	await get_tree().process_frame
	var spot := _column.hold_spot(f)
	var h := _scroll.size.y
	if spot == null or h <= 0.0:
		return
	var want := spot.position.y + spot.size.y / 2.0 - h / 2.0
	_scroll.scroll_vertical = int(clampf(want, 0.0, maxf(0.0, _column.custom_minimum_size.y - h)))


func _show_in_well(thing: Control) -> void:
	var h := _scroll.size.y
	if thing == null or h <= 0.0:
		return
	var top := thing.position.y - 16.0
	var bottom := thing.position.y + thing.size.y + 16.0
	var at := float(_scroll.scroll_vertical)
	if top < at:
		at = top
	elif bottom > at + h:
		at = bottom - h
	_scroll.scroll_vertical = int(clampf(at, 0.0, maxf(0.0, _column.custom_minimum_size.y - h)))


## A perk's card: its name and ✕, the thing on its nail, level pips (a tip's level), what it does
## now and next as numbers, and the buy button (none while the one above isn't bought yet).
func _nail_card(id: String) -> Control:
	var catalog := GameState.catalog
	var p := Perks.perk(catalog, id)
	var tip := Perks.is_tip(catalog, id)
	var lv := GameState.perk_level(id)
	var maxed := Perks.maxed(catalog, GameState.perks, id)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.WISP.lerp(UiTheme.LILAC_SEAM, 0.45), 12, UiTheme.RAISED, 11))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_child(_h3(str(p.name)))
	head.add_child(UiTheme.spacer())
	var x := UiTheme.small_button("✕", func(): pick_nail(""))
	x.custom_minimum_size = Vector2(20, 20)
	x.add_theme_color_override("font_color", UiTheme.MUTED)
	x.add_theme_color_override("font_hover_color", UiTheme.PINK)
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	head.add_child(x)
	col.add_child(head)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var big := _BigThing.new(str(p.get("thing", "bow")), "on" if lv > 0 or tip else "next")
	body.add_child(big)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 6)
	info.size_flags_horizontal = SIZE_EXPAND_FILL
	info.size_flags_vertical = SIZE_SHRINK_CENTER
	if tip:
		info.add_child(_lv_pill(lv))
	else:
		info.add_child(_Pips.new(lv, Perks.max_level(p)))
	info.add_child(_effect(p, lv, maxed))
	body.add_child(info)
	col.add_child(body)
	if maxed:
		var done := UiTheme.button("all done!")
		done.disabled = true
		col.add_child(done)
	elif GameState.perk_available(id):
		var price := GameState.perk_price(id)
		var buy := Button.new()
		buy.focus_mode = FOCUS_NONE
		buy.disabled = GameState.wisps < price
		var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		buy.add_theme_stylebox_override("normal", sb)
		buy.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.DEEP, UiTheme.PINK, 8, 2, 6))
		buy.add_theme_stylebox_override("pressed", sb)
		var dis := sb.duplicate()
		dis.border_color = UiTheme.LINE
		buy.add_theme_stylebox_override("disabled", dis)
		buy.custom_minimum_size = Vector2(0, 32)
		var row := HBoxContainer.new()
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		var word := UiTheme.label("one more" if lv > 0 or tip else "hang it up", UiTheme.MUTED if buy.disabled else UiTheme.TEXT, UiTheme.SMALL + 1)
		word.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(word)
		var tint := UiTheme.MUTED if buy.disabled else UiTheme.WISP
		row.add_child(UiTheme.icon_rect("lantern", 15, tint))
		row.add_child(UiTheme.label(UiTheme.num(price), tint, UiTheme.SMALL + 1))
		for c in row.get_children():
			c.mouse_filter = MOUSE_FILTER_IGNORE
		buy.add_child(row)
		buy.text = ""
		buy.pressed.connect(func(): _buy_perk(id))
		col.add_child(buy)
	return card


# ---- held landings -----------------------------------------------------------------------------

## A held landing's card: "landing N" + ✕ (+ a coral pennant once it's held), the crowd, how many,
## what they hold; while it fills a meter, a ‹ n › per shelf that has pets that may go, "hold on tight!".
func _hold_card(f: int, keep := 0) -> Control:
	var catalog := GameState.catalog
	var state: Dictionary = GameState.dungeon
	var n := Dungeon.held_n(state, f)
	var need := Dungeon.hold_need(catalog, f)
	var full := n >= need
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.WISP.lerp(UiTheme.LILAC_SEAM, 0.45), 12, UiTheme.RAISED, 11))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	head.add_child(_h3("landing %d" % f))
	if full:
		head.add_child(_Pennant.new())
	head.add_child(UiTheme.spacer())
	var x := UiTheme.small_button("✕", func(): pick_hold(0))
	x.custom_minimum_size = Vector2(20, 20)
	x.add_theme_color_override("font_color", UiTheme.MUTED)
	x.add_theme_color_override("font_hover_color", UiTheme.PINK)
	for st in ["normal", "hover", "pressed", "focus"]:
		x.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	head.add_child(x)
	col.add_child(head)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var shown := Herd.mound_size(catalog, n, Dungeon.hold_int(catalog, "card_faces", 24))
	var mound := Mound.new(GameState.hold_faces(f, mini(shown, Dungeon.hold_int(catalog, "looks", 8))), shown, 96.0, 32.0)
	mound.size_flags_vertical = SIZE_SHRINK_END
	line.add_child(mound)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 1)
	words.add_child(UiTheme.title(HoldSpot.short(n), 22, UiTheme.TEXT))
	words.add_child(UiTheme.label("holding %s" % Dungeon.hold_what(catalog, f), UiTheme.MUTED, UiTheme.SMALL))
	line.add_child(words)
	col.add_child(line)
	if full:
		return card
	card.size_flags_vertical = SIZE_EXPAND_FILL
	var meter_row := HBoxContainer.new()
	meter_row.add_theme_constant_override("separation", 6)
	var meter := UiTheme.bar(UiTheme.WISP)
	meter.max_value = float(need)
	meter.value = float(n)
	meter.size_flags_vertical = SIZE_SHRINK_CENTER
	meter_row.add_child(meter)
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 3)
	count.add_child(UiTheme.title(HoldSpot.short(n), 15, UiTheme.TEXT))
	var of := UiTheme.label("/ %s" % HoldSpot.short(need), UiTheme.MUTED, UiTheme.SMALL)
	of.size_flags_vertical = SIZE_SHRINK_END
	count.add_child(of)
	meter_row.add_child(count)
	col.add_child(meter_row)
	# a stepper per shelf with pets that may go ("of N": all of them; a stepper goes at most as far as the landing still needs)
	var room := GameState.hold_room(f)
	var step := ceili(need / maxf(1.0, float(catalog.dungeon.get("hold", {}).get("steps_to_fill", 20))))
	var picked := 0
	for k in _send:
		picked += int(_send[k])
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	for tier in catalog.tiers:
		var have := GameState.hold_can_go(f, tier.id)
		var want := mini(int(_send.get(tier.id, 0)), have)
		if have <= 0:
			_send.erase(tier.id)
			continue
		var most := mini(have, room - (picked - want))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var tname := VBoxContainer.new()
		tname.add_theme_constant_override("separation", -2)
		tname.add_child(UiTheme.label(str(tier.name), catalog.tier_color(tier.id), UiTheme.SMALL + 1))
		tname.add_child(UiTheme.label("of %s" % UiTheme.num(int(GameState.homes_pick(tier.id).n)), UiTheme.MUTED, UiTheme.SMALL - 1))
		tname.size_flags_horizontal = SIZE_EXPAND_FILL
		r.add_child(tname)
		var id := str(tier.id)
		r.add_child(_stepper(UiTheme.num(want), func(): _hold_step(id, want - step, most), func(): _hold_step(id, want + step, most),
			want > 0, want < most, 44))
		rows.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	col.add_child(scroll)
	_hold_scroll = scroll
	_hold_scroll_f = f
	if keep > 0:  # back where it was once the list has its size
		var bar := scroll.get_v_scroll_bar()
		var wait := { "keep": keep }
		bar.changed.connect(func():
			if int(wait.keep) > 0 and bar.page > 0.0 and bar.max_value - bar.page >= float(wait.keep):
				bar.value = float(wait.keep)
				wait.keep = 0)
	var go := UiTheme.button("hold on tight!", func(): _send_holders(f))
	go.disabled = picked <= 0
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6)
	go.add_theme_stylebox_override("normal", sb)
	var dis := sb.duplicate()
	dis.border_color = UiTheme.LINE
	go.add_theme_stylebox_override("disabled", dis)
	col.add_child(go)
	return card


## The open hold card's stepper for a shelf goes to `n` (as far as it may), for flows. Returns
## whether there was one.
func hold_pick(rarity: String, n: int) -> bool:
	var have := GameState.hold_can_go(_hold_f, rarity) if _hold_f > 0 else 0
	if have <= 0:
		return false
	var others := 0
	for k in _send:
		if k != rarity:
			others += int(_send[k])
	_hold_step(rarity, n, mini(have, GameState.hold_room(_hold_f) - others))
	return true


## The open hold card's shelf list (null when there's none), for flows.
func hold_list() -> ScrollContainer:
	return _hold_scroll if is_instance_valid(_hold_scroll) else null


func _hold_step(rarity: String, n: int, most: int) -> void:
	n = clampi(n, 0, maxi(0, most))
	if n > 0:
		_send[rarity] = n
	else:
		_send.erase(rarity)
	var a := GameState.army()
	_build_side(a, GameState.army_rules(a) if int(a.sent) > 0 else {})


## "hold on tight!": each shelf's pick goes and holds the landing (for good).
func _send_holders(f: int) -> void:
	var went := 0
	for rarity in _send.keys():
		went += GameState.send_holders(f, str(rarity), int(_send[rarity]))
	_send = {}
	_dirty = true
	if went <= 0:
		return
	if Dungeon.is_held(GameState.catalog, GameState.dungeon, f):
		PetBubble.say_line(self, "hold_full", { "f": f })
	else:
		PetBubble.say_line(self, "hold_send")


## A little coral pennant on a pole: this landing is held.
class _Pennant extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(14, 16)
		size_flags_vertical = SIZE_SHRINK_CENTER
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(3, 1), Vector2(3, 15), UiTheme.MUTED, 1.6, true)
		draw_colored_polygon(PackedVector2Array([Vector2(3.5, 2), Vector2(13, 5), Vector2(3.5, 8)]), UiTheme.WISP)


func _buy_perk(id: String) -> void:
	var catalog := GameState.catalog
	var done := Perks.chain_done(catalog, GameState.perks)
	if not GameState.buy_perk(id):
		return
	_column.pop(id)
	if not done and Perks.chain_done(catalog, GameState.perks) and not Perks.tips(catalog).is_empty():
		_reveal = str(Perks.tips(catalog).back().id)  # the tips just hung at the bottom: show them
	if str(Perks.perk(catalog, id).get("count", "")) == "entrance":
		PetBubble.say_line(self, "perk_entrance")
	elif Perks.is_tip(catalog, id):
		PetBubble.say_line(self, "perk_tip")
	else:
		PetBubble.say_line(self, "perk_hang")


## What a perk does now → next, as numbers ("fits 300 → 600", "front row x1.20 → x1.40"); only
## what it does at its max.
func _effect(p: Dictionary, lv: int, maxed: bool) -> Control:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 4)
	f.add_theme_constant_override("v_separation", 2)
	f.add_child(UiTheme.label(str(p.get("what", "")), UiTheme.MUTED, UiTheme.SMALL))
	var now := Perks.card_value(GameState.catalog, p, lv)
	if maxed:
		f.add_child(UiTheme.label(_fmt(p, now), UiTheme.WISP, UiTheme.SMALL))
		return f
	f.add_child(UiTheme.label(_fmt(p, now), UiTheme.TEXT, UiTheme.SMALL))
	f.add_child(UiTheme.label("→", UiTheme.MUTED, UiTheme.SMALL))
	f.add_child(UiTheme.label(_fmt(p, Perks.card_value(GameState.catalog, p, lv + 1)), UiTheme.WISP, UiTheme.SMALL))
	return f


## A perk's number as its card shows it (data/perks.json "fmt").
static func _fmt(p: Dictionary, v: float) -> String:
	match str(p.get("fmt", "x")):
		"num":
			return UiTheme.num(v)
		"cards":
			return "%d cards" % int(v)
		"hours":
			return "%s h" % (str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v)
		"plus":
			return "+%d" % int(v)
	return "x%.2f" % v


func _lv_pill(lv: int) -> Control:
	var pill := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.WISP.lerp(UiTheme.LINE, 0.55), 999, 2, 0)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_horizontal = SIZE_SHRINK_BEGIN
	pill.add_child(UiTheme.label("lv %d" % lv, UiTheme.WISP, UiTheme.SMALL - 1))
	return pill


## The thing on its nail, big, in a little deep box (the nail card).
class _BigThing extends Control:
	var _thing := ""
	var _look := ""

	func _init(thing: String, look: String) -> void:
		_thing = thing
		_look = look
		custom_minimum_size = Vector2(56, 64)
		size_flags_vertical = SIZE_SHRINK_CENTER
		texture_filter = TEXTURE_FILTER_LINEAR
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 0), Rect2(Vector2.ZERO, size))
		draw_circle(Vector2(size.x / 2.0, 8.0), 2.0, UiTheme.MUTED)
		draw_line(Vector2(size.x / 2.0, 8.0), Vector2(size.x / 2.0, 14.0), UiTheme.MUTED, 1.2)
		var px := 36.0
		draw_texture_rect(PerkNail.texture(_thing, _look, int(px), false, false), Rect2(Vector2((size.x - px) / 2.0, 16.0), Vector2(px, px)), false)


## Level pips: one per level, filled coral up to the level bought.
class _Pips extends Control:
	var _on := 0
	var _n := 1

	func _init(on: int, n: int) -> void:
		_on = on
		_n = maxi(n, 1)
		custom_minimum_size = Vector2(_n * 12 - 3, 9)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in _n:
			var c := Vector2(i * 12 + 4.5, 4.5)
			if i < _on:
				draw_circle(c, 4.5, UiTheme.WISP)
			else:
				draw_arc(c, 3.5, 0, TAU, 16, UiTheme.LILAC_SEAM, 2.0, true)


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
