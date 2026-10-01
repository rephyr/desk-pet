class_name DungeonView
extends Control
## The dungeon page in adventures (adventures | upgrades | dungeon), look A of
## design/mockups/screens/dungeon-redo.html: the old well as a slim drawn column on the left
## (WellColumn, in a scroll; tap a floor to move the flag there) and a roomy desk beside it.
## Ready: the army card (how many go of what fits, the entrance by shelf, "fill up" and "empty", the
## front row with your pet's flag, the pets walking behind and a 10-pip slider + "all" per shelf), the
## orders as rows of choices (start from, down to floor ‹ › with its feeling word, come home when,
## who goes first) with "down we go!", and a line about last time. While the army is down there: the
## floor it's on of the target with a walking bar, counters (walking, bumped, stayed below, wisps so
## far), the front row's faces and a log row per floor as it happens (faded faces of front-row pets
## that stayed below, never names). Home again: the "came home" report (4 numbers, the front row's
## faces: faded = stayed below, a plaster = bumped; by shelf, floor by floor, the best bit, "same
## again!"). Floor strength is never a number, only a feeling word. Rules in Dungeon, state in
## GameState: this only shows them and passes on clicks.
## The perks hang on the well wall (WellWall), a sheet over the whole page from the "perks" button by
## the wisps (AdventuresTab).
## Once the tiny key is found, the well's floor 20 has a little pink door: tapping it slides the column
## over to the sewing room (SewingRoom, header "‹ the sewing room"; ‹ slides back; the column is wider
## there). The front row's cards that match the room's chalk lock get a chalk tick then.
## Held landings (HoldSpot on the column, every 10th landing cleared): tapping one puts the hold card
## in the army card's place ("landing 20" + ✕, a coral pennant once it's held, the crowd, how many,
## what they hold; while it fills a meter, a ‹ n › per shelf with pets that may go, "hold on tight!").
## Once a landing is fully held the orders get "start from ‹the top | landing N›".

signal door_opened  # the sewing room's door was tapped: the adventures tab shows the sewing room (SewingPage)

const PICK_PAGE := 30
const PICK_COLUMNS := 10
const WELL_W := 180.0  # the well's column (look A: slim)
const ROOMS_W := 236.0  # the column while it shows the sewing room
const TIER_W := 118.0  # a shelf's name on the army card

var _body := HBoxContainer.new()
var _well := PanelContainer.new()
var _column := WellColumn.new()
var _scroll := ScrollContainer.new()
var _pan := Control.new()  # the column: the well, and the sewing room slid in beside it
var _rooms := SewingRoom.new()
var _title: Label
var _back: Button
var _in_rooms := false  # the column shows the sewing room
var _slide := 0.0  # 0 = the well, 1 = the sewing room
var _tween: Tween
var _desk := VBoxContainer.new()
var _wall := WellWall.new()
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
var _hold_f := 0  # the held landing whose card is open (0: none)
var _send := {}  # the hold card's steppers: rarity -> how many to send
var _reveal_hold := 0  # a held landing to scroll into view after the next rebuild
var _hold_scroll: ScrollContainer = null  # the open hold card's shelf list (its scroll is kept across rebuilds)
var _hold_scroll_f := 0  # the landing that list belongs to
var _done_shown := -1  # the run's floors behind the army at the last rebuild
var _walk_bar: ProgressBar = null  # the run card's walking bar and floor number (moved every frame)
var _floor_label: Label = null
var _floor_done := false  # a floor of the run just finished: the desk (not the wall) builds again


func _init() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	_body.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_body.add_theme_constant_override("separation", 12)
	add_child(_body)
	# the well
	_well.custom_minimum_size = Vector2(WELL_W, 0)
	_well.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 12, 2, 0))
	var wcol := VBoxContainer.new()
	wcol.add_theme_constant_override("separation", 0)
	_well.add_child(wcol)
	var head := MarginContainer.new()
	for side in [["left", 12], ["top", 7], ["right", 10], ["bottom", 4]]:
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
	_title = UiTheme.title("the old well", 16)
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
	_body.add_child(_well)
	_column.door_pressed.connect(func(): door_opened.emit())
	_column.hold_pressed.connect(pick_hold)
	_column.floor_pressed.connect(func(f: int): GameState.set_order_to("target", f))
	_desk.size_flags_horizontal = SIZE_EXPAND_FILL
	_desk.add_theme_constant_override("separation", 10)
	_body.add_child(_desk)
	# the well wall, over the whole page
	_wall.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_wall.visible = false
	_wall.closed.connect(func(): show_wall(false))
	add_child(_wall)
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
			_drop_hold()
			show_wall(false)
			if not GameState.sewing_open():
				show_rooms(false, false)
			_rebuild())


## The well wall's sheet over the page (the perks button), or back to the page.
func show_wall(on: bool) -> void:
	on = on and not GameState.perks_shown().is_empty()
	if on:
		_wall.refresh()
	_wall.visible = on


func wall_open() -> bool:
	return _wall.visible


## A tap on floor `f` of the well (for flows): the flag moves there if the orders may aim for it.
func tap_floor(f: int) -> bool:
	return _column.tap_floor(f)


## The well wall (for flows).
func wall() -> WellWall:
	return _wall


## The column slides over to the sewing room (or back to the well).
func show_rooms(on: bool, animate := true) -> void:
	on = on and GameState.sewing_open()
	if on == _in_rooms:
		return
	_in_rooms = on
	_hold()
	if on:
		_rooms.to_next()
		_drop_hold()
	_back.visible = on
	_title.text = "the sewing room" if on else "the old well"
	_well.custom_minimum_size = Vector2(ROOMS_W if on else WELL_W, 0)
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
		if _wall.visible:
			_wall.refresh()
	elif _floor_done:  # a floor of the run is behind the army: only the desk changes
		_floor_done = false
		_build_desk(GameState.army(), {})
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
		_tick_run()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		if GameState.dungeon_running() != _running:
			_rebuild()


## Keeps the walking army in view (and on first show, the target's flag).
func _follow() -> void:
	var h := _scroll.size.y
	if h <= 0.0:
		return
	var want := _column.party_y() - h / 2.0 if GameState.dungeon_running() else _column.y_at(maxi(int(GameState.dungeon.target), 1)) - h * 0.65
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


## Whether the army is down the well (not in a sewing room).
func _well_run() -> bool:
	return GameState.dungeon_running() and not GameState.dungeon.run.has("room")


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
	_build_desk(a, rules)
	var door := GameState.sewing_open()
	if door and not _door_seen and (_built or int(GameState.sewing.cleared) == 0):
		_followed = false  # the door just turned up (or nobody's been in yet this time): show it
		_show_door = true
	_door_seen = door
	_built = true
	if _reveal_hold > 0:
		_show_hold.call_deferred(_reveal_hold)
		_reveal_hold = 0


func _build_desk(a: Dictionary, rules: Dictionary) -> void:
	var keep := 0  # (the open hold card's shelf list stays where it was scrolled to)
	if is_instance_valid(_hold_scroll) and _hold_scroll_f == _hold_f:
		keep = _hold_scroll.scroll_vertical
	_hold_scroll = null
	_walk_bar = null
	_floor_label = null
	UiTheme.clear(_desk)
	if _hold_f > 0 and not _hold_f in GameState.hold_spots():
		_drop_hold()
	if _hold_f > 0:
		_desk.add_child(_hold_card(_hold_f, keep))
		_desk.add_child(_orders(a, rules))
		return
	if _well_run():
		_done_shown = Dungeon.floors_done(GameState.catalog, GameState.dungeon.run, _run_seconds())
		_desk.add_child(_run_card(a))
		return
	_done_shown = -1
	if not _running and not GameState.dungeon_report.is_empty():
		_desk.add_child(_home_card(GameState.dungeon_report))
		return
	_desk.add_child(_picker(a) if _picking else _army_card(a))
	_desk.add_child(_orders(a, rules))
	var last: Control = _last_line()
	if last:
		_desk.add_child(last)


# ---- the army card ---------------------------------------------------------------------

func _army_card(a: Dictionary) -> Control:
	var catalog := GameState.catalog
	var card := _sticker(9)
	card.size_flags_vertical = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	card.add_child(col)
	var sent := int(a.sent)
	var room := int(a.entrance)
	var full := sent >= room
	# the head: the army, how many of what fits, the entrance by shelf, fill up and empty
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_h3("the army"))
	var count := HBoxContainer.new()
	count.add_theme_constant_override("separation", 4)
	count.add_child(UiTheme.title(UiTheme.num(sent), 22, UiTheme.PINK if full else UiTheme.TEXT))
	var of := UiTheme.label("/ %s" % UiTheme.num(room), UiTheme.MUTED, UiTheme.SMALL + 1)
	of.size_flags_vertical = SIZE_SHRINK_END
	count.add_child(of)
	head.add_child(count)
	var front_n := GameState.front_row_size()
	var gate := _Gate.new(mini(a.cards.size(), room), a.herd, room)
	gate.size_flags_horizontal = SIZE_EXPAND_FILL
	gate.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(gate)
	var fill := UiTheme.button("fill up", func():
		var had := int(GameState.army().sent)
		GameState.army_fill_up()
		var now := int(GameState.army().sent)
		if now >= int(GameState.army().entrance) and now > had:
			PetBubble.say_line(self, "dungeon_full"))
	fill.name = "fill_up"
	fill.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	fill.disabled = full or _running
	head.add_child(fill)
	var empty := _link("empty", func(): GameState.army_empty())
	empty.name = "empty_army"
	empty.disabled = a.herd.is_empty() or _running
	head.add_child(empty)
	col.add_child(head)
	# the front row: your pet's flag, the strongest front_n; best ones, pick
	var front := HBoxContainer.new()
	front.add_theme_constant_override("separation", 14)
	var ticks: Array = Sewing.ticks(GameState.sew_room(_rooms.room), a.cards.slice(0, front_n)) if _in_rooms else []
	var row := FrontRow.new(GameState.collection.active(), a.cards, not _running, front_n, ticks, 11)
	row.pressed.connect(_open_picker)
	front.add_child(row)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.add_child(UiTheme.title("front row", 13, UiTheme.LILAC))
	if a.cards.size() > front_n:
		side.add_child(UiTheme.label("+%s walking behind" % UiTheme.num(a.cards.size() - front_n), UiTheme.MUTED, UiTheme.SMALL - 1))
	var best := _link("best ones", func():
		GameState.army_best()
		PetBubble.say_line(self, "dungeon_best"))
	best.disabled = _running
	side.add_child(best)
	var pick := _link("pick ›", _open_picker)
	pick.disabled = _running
	side.add_child(pick)
	front.add_child(side)
	col.add_child(front)
	# walking behind: how many, a mound of them
	var herd_n := Herd.total(a.keys)
	var behind := HBoxContainer.new()
	behind.add_theme_constant_override("separation", 8)
	var bt := UiTheme.title("walking behind", 13, UiTheme.LILAC)
	bt.size_flags_vertical = SIZE_SHRINK_END
	behind.add_child(bt)
	var bn := UiTheme.label(UiTheme.num(herd_n), UiTheme.MUTED, UiTheme.SMALL)
	bn.size_flags_vertical = SIZE_SHRINK_END
	behind.add_child(bn)
	behind.add_child(UiTheme.spacer())
	if herd_n > 0:
		var mound := Mound.new(GameState.herd_faces(a.keys, 24, 3), Herd.mound_size(catalog, herd_n, 30), 200.0, 26.0)
		mound.size_flags_vertical = SIZE_SHRINK_END
		behind.add_child(mound)
	else:
		behind.custom_minimum_size = Vector2(0, 18)
	col.add_child(behind)
	# a shelf per rarity that has pets that may go: a slider of 10 pips, how many, all
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 5)
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	for tier in catalog.tiers:
		var id := str(tier.id)
		var have := GameState.army_herd_room(id)
		var on := int(a.herd.get(id, 0))
		if have <= 0 and on <= 0:
			continue
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 10)
		var tn := HBoxContainer.new()
		tn.add_theme_constant_override("separation", 6)
		tn.custom_minimum_size = Vector2(TIER_W, 0)
		tn.add_child(UiTheme.label(str(tier.name), catalog.tier_color(id), UiTheme.SMALL + 1))
		var tof := UiTheme.label("of %s" % UiTheme.num(have), UiTheme.MUTED, UiTheme.SMALL - 1)
		tof.size_flags_vertical = SIZE_SHRINK_END
		tn.add_child(tof)
		r.add_child(tn)
		var pips := _PipSlider.new(catalog.tier_color(id), on, have, func(n: int): _herd(id, n))
		pips.name = "pips_" + id
		pips.size_flags_horizontal = SIZE_EXPAND_FILL
		pips.size_flags_vertical = SIZE_SHRINK_CENTER
		pips.mouse_filter = MOUSE_FILTER_IGNORE if _running else MOUSE_FILTER_STOP
		r.add_child(pips)
		var n := UiTheme.title(UiTheme.num(on), 15, UiTheme.TEXT if on > 0 else UiTheme.MUTED)
		n.custom_minimum_size = Vector2(50, 0)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		r.add_child(n)
		var all_on := on >= have and have > 0
		var all := _chip_button("all", all_on, func(): _herd(id, 0 if all_on else have))
		all.name = "all_" + id
		all.custom_minimum_size = Vector2(40, 0)
		all.disabled = _running
		r.add_child(all)
		rows.add_child(r)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows)
	col.add_child(scroll)
	return card


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
	_dirty = true


## The cards to pick from, in the army card's place: resting cards and the army's, strongest first.
func _picker(a: Dictionary) -> Control:
	var panel := _sticker(9)
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
		_dirty = true)
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
	grid.columns = PICK_COLUMNS - (1 if _in_rooms else 0)
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 6)
	for pet in choices.slice(_page * PICK_PAGE, (_page + 1) * PICK_PAGE):
		grid.add_child(_chip(pet, in_army.has(pet.uid)))
	col.add_child(grid)
	if pages > 1:
		var pager := HBoxContainer.new()
		pager.add_child(UiTheme.spacer())
		pager.add_child(UiTheme.small_button("‹", func():
			_page -= 1
			_dirty = true))
		pager.add_child(UiTheme.label("%d of %d" % [_page + 1, pages], UiTheme.MUTED, UiTheme.SMALL))
		pager.add_child(UiTheme.small_button("›", func():
			_page += 1
			_dirty = true))
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
		_dirty = true)
	return Tilted.new(b, -3.0 if picked else 0.0)


# ---- the orders, as rows of choices ------------------------------------------------------

func _orders(a: Dictionary, rules: Dictionary) -> Control:
	var catalog := GameState.catalog
	var state: Dictionary = GameState.dungeon
	var card := PanelContainer.new()
	var sb := UiTheme.sticker(UiTheme.LINE, 12, UiTheme.RAISED, 9)
	sb.border_width_top = 6
	sb.border_color = UiTheme.LILAC.lerp(UiTheme.LINE, 0.55)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 9
	card.add_theme_stylebox_override("panel", sb)
	var grid: BoxContainer = VBoxContainer.new() if _in_rooms else HBoxContainer.new()  # (the narrow desk by the sewing room: "down we go!" under the lines)
	grid.add_theme_constant_override("separation", 4 if _in_rooms else 14)
	card.add_child(grid)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	lines.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(lines)
	var off := _running
	var head_used := false
	var starts := Dungeon.starts(catalog, state)
	var start := int(state.start)
	if starts.size() > 1:  # once a landing is fully held
		var line0 := _line(_order_head())
		head_used = true
		line0.add_child(_word("start from"))
		var names: Array = starts.map(func(f): return ("landing %d" % f if starts.size() <= 4 else str(f)) if f > 0 else "the top")
		line0.add_child(_pick(names, starts.find(start), func(i): GameState.set_order_to("start", starts[i]), off, "start"))
		lines.add_child(line0)
	var target := int(state.target)
	var line1 := _line(null if head_used else _order_head())
	if head_used:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(62, 0)
		line1.add_child(pad)
	line1.add_child(_word("down to floor"))
	line1.add_child(_stepper(str(target), func(): GameState.set_order("target", -1), func(): GameState.set_order("target", 1),
		target > start + 1 and not off, target < Dungeon.target_max(catalog, state) and not off, 26))
	var words := GameState.floor_words(target, target, rules) if not rules.is_empty() else {}
	if words.has(target):
		line1.add_child(_feel(words[target], target <= int(state.deep)))
	lines.add_child(line1)
	var home_steps: Array = catalog.dungeon.home_at.map(func(v): return int(v))
	var line2 := _line()
	line2.add_child(_word("come home when"))
	line2.add_child(_pick(home_steps.map(func(v): return "%d%%" % v), home_steps.find(int(state.home_at)),
		func(i): GameState.set_order_to("home", home_steps[i]), off, "home"))
	line2.add_child(_word("are gone"))
	lines.add_child(line2)
	if Dungeon.first_earned(catalog, state):
		var first_lines: Array = catalog.dungeon.first.lines
		var line3 := _line()
		line3.add_child(_word("who goes first"))
		line3.add_child(_pick(first_lines, first_lines.find(str(state.first)), func(i): GameState.set_order_to("first", first_lines[i]), off, "first"))
		lines.add_child(line3)
	var go := UiTheme.button("on the way…" if _running else "down we go!", _go)
	go.name = "go_down"
	go.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	go.add_theme_font_size_override("font_size", 16)
	go.disabled = _running or int(a.sent) == 0
	var go_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 8)
	go_sb.content_margin_left = 16
	go_sb.content_margin_right = 16
	go.add_theme_stylebox_override("normal", go_sb)
	go.add_theme_stylebox_override("disabled", go_sb)
	var go_hover := go_sb.duplicate()
	go_hover.border_color = UiTheme.PINK
	go.add_theme_stylebox_override("hover", go_hover)
	if _running:
		go.add_theme_color_override("font_disabled_color", UiTheme.PINK)
	go.size_flags_vertical = SIZE_SHRINK_CENTER
	var go_tilt := Tilted.new(go, -2.0)
	go_tilt.size_flags_horizontal = SIZE_SHRINK_END
	grid.add_child(go_tilt)
	return card


func _order_head() -> Control:
	var h := UiTheme.title("orders", 15, UiTheme.LILAC)
	h.custom_minimum_size = Vector2(62, 0)
	return h


func _go() -> void:
	var from := int(GameState.dungeon.start)
	if GameState.send_army():
		if from > 0:
			PetBubble.say_line(self, "dungeon_go_from", { "f": from })
		else:
			PetBubble.say_line(self, "dungeon_go")


## "last time": the floor, the wisps, how many came home (of how many went, when that's known).
func _last_line() -> Control:
	var last: Dictionary = GameState.dungeon.last
	if last.is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 4)
	m.add_child(row)
	row.add_child(UiTheme.label("last time", UiTheme.MUTED, UiTheme.SMALL))
	if last.has("room"):
		row.add_child(UiTheme.title(str(GameState.sew_room(int(last.room)).name), 13, UiTheme.TEXT))
	else:
		row.add_child(_pair("floor", UiTheme.title(str(int(last.floor)), 13, UiTheme.TEXT), true))
	var got := HBoxContainer.new()
	got.add_theme_constant_override("separation", 3)
	got.add_child(UiTheme.title("+%s" % UiTheme.num(int(last.got)), 13, UiTheme.WISP))
	got.add_child(UiTheme.label("wisps", UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(got)
	var back := UiTheme.title(UiTheme.num(int(last.back)), 13, UiTheme.TEXT)
	row.add_child(_pair("of %s came home" % UiTheme.num(int(last.sent)) if last.has("sent") else "came home", back, false))
	return m


## A number with its words: "floor 14" (before) or "1,118 came home" (after).
func _pair(words: String, value: Control, before: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var w := UiTheme.label(words, UiTheme.MUTED, UiTheme.SMALL)
	if before:
		row.add_child(w)
	row.add_child(value)
	if not before:
		row.add_child(w)
	return row


# ---- the run, floor by floor --------------------------------------------------------------

func _run_seconds() -> float:
	return Time.get_unix_time_from_system() - float(GameState.dungeon.run.get("at", 0.0))


## The run card: the floor the army is on of the target, its walking bar, the counters so far, the
## front row's faces and a row per floor behind it, newest first.
func _run_card(a: Dictionary) -> Control:
	var catalog := GameState.catalog
	var run: Dictionary = GameState.dungeon.run
	var done := _done_shown
	var tally := Dungeon.run_tally(run, done)
	var card := _sticker(12)
	card.size_flags_vertical = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	# floor N of M, the band, the feeling word, the walking bar
	var at := _run_at(run)
	var now := HBoxContainer.new()
	now.add_theme_constant_override("separation", 14)
	var big := HBoxContainer.new()
	big.add_theme_constant_override("separation", 6)
	_floor_label = UiTheme.title("floor %d" % at, 28, UiTheme.PINK)
	big.add_child(_floor_label)
	var of := UiTheme.label("of %d" % int(run.get("target", at)), UiTheme.MUTED, UiTheme.SMALL + 1)
	of.size_flags_vertical = SIZE_SHRINK_END
	big.add_child(of)
	now.add_child(big)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 5)
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.size_flags_vertical = SIZE_SHRINK_CENTER
	var line1 := HBoxContainer.new()
	line1.add_theme_constant_override("separation", 8)
	line1.add_child(UiTheme.label(str(Dungeon.band_of(catalog, at).name), UiTheme.MUTED, UiTheme.SMALL + 1))
	var fl := _floor_entry(run, at)
	if not fl.is_empty():
		line1.add_child(_feel(Dungeon.word(catalog, float(fl.get("ratio", 1.0))), false))
	right.add_child(line1)
	var known := at <= int(run.get("known", 0))
	_walk_bar = UiTheme.bar(UiTheme.WISP if known else UiTheme.LILAC)
	_walk_bar.max_value = 1.0
	_walk_bar.step = 0.0
	_walk_bar.value = _walk_frac(run)
	right.add_child(_walk_bar)
	now.add_child(right)
	col.add_child(now)
	# the counters so far
	var tallies := PanelContainer.new()
	var tsb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 8)
	tsb.content_margin_left = 12
	tsb.content_margin_right = 12
	tallies.add_theme_stylebox_override("panel", tsb)
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 12)
	tallies.add_child(trow)
	trow.add_child(_tally(UiTheme.num(int(tally.walking)), "walking", UiTheme.TEXT))
	trow.add_child(_tally(UiTheme.num(int(tally.hurt)), "bumped", UiTheme.TEXT, true))
	trow.add_child(_tally(UiTheme.num(int(tally.lost)), "stayed below", UiTheme.MUTED))
	var so_far := _tally("+%s" % UiTheme.num(int(tally.got)), "so far", UiTheme.WISP, false, true)
	trow.add_child(so_far)
	col.add_child(tallies)
	# the front row's faces: faded once they stayed below, a plaster when bumped
	col.add_child(_faces(a.cards.slice(0, GameState.front_row_size()), tally, 20 if _in_rooms else 22))
	# a row per floor behind them, newest first
	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 5)
	rows_box.size_flags_horizontal = SIZE_EXPAND_FILL
	var floors: Array = run.get("floors", [])
	var front := {}
	for pet in a.cards.slice(0, GameState.front_row_size()):
		front[pet.uid] = pet
	for i in range(done - 1, -1, -1):
		rows_box.add_child(_floor_row(floors[i], front, run))
	if done == 0:
		var start := int(run.get("start", 0))
		rows_box.add_child(UiTheme.label("landing %d, everyone holding on" % start if start > 0 else "down the rope", UiTheme.MUTED, UiTheme.SMALL + 1))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(rows_box)
	col.add_child(scroll)
	return card


## The floor the army is walking (or the last one it reached).
func _run_at(run: Dictionary) -> int:
	var pos := Dungeon.run_floor(GameState.catalog, run, _run_seconds())
	var start := int(run.get("start", 0))
	var last: int = start + run.get("floors", []).size()
	if int(run.get("turned", 0)) > last:
		last = int(run.turned)
	return clampi(floori(pos) + 1, start + 1, maxi(last, start + 1))


## How far across the floor it's on the army is (0..1).
func _walk_frac(run: Dictionary) -> float:
	var pos := Dungeon.run_floor(GameState.catalog, run, _run_seconds())
	var at := _run_at(run)
	return clampf(pos - float(at - 1), 0.0, 1.0)


func _floor_entry(run: Dictionary, f: int) -> Dictionary:
	for fl in run.get("floors", []):
		if fl is Dictionary and int(fl.f) == f:
			return fl
	return {}


## Moves the walking bar along every frame; a new floor behind the army rebuilds the card.
func _tick_run() -> void:
	if not _well_run():
		return
	var run: Dictionary = GameState.dungeon.run
	var done := Dungeon.floors_done(GameState.catalog, run, _run_seconds())
	if done != _done_shown:
		_floor_done = true
		return
	if is_instance_valid(_walk_bar):
		_walk_bar.value = _walk_frac(run)
	if is_instance_valid(_floor_label):
		_floor_label.text = "floor %d" % _run_at(run)


## One floor in the log: its number, how it felt, the faces of front-row pets that stayed below
## (faded, never named) and how many, how many got bumped, the wisps it paid.
func _floor_row(fl: Dictionary, front: Dictionary, run: Dictionary) -> Control:
	var catalog := GameState.catalog
	var known := int(fl.f) <= int(run.get("known", 0))
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(0, 24 if known else 30)
	if known:
		p.modulate = Color(1, 1, 1, 0.72)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	p.add_child(row)
	var num := UiTheme.title(str(int(fl.f)), 14, UiTheme.WISP)
	num.custom_minimum_size = Vector2(26, 0)
	row.add_child(num)
	var feel := _feel(Dungeon.word(catalog, float(fl.get("ratio", 1.0))), false)
	var feel_box := HBoxContainer.new()
	feel_box.custom_minimum_size = Vector2(78, 0)
	feel_box.add_child(feel)
	row.add_child(feel_box)
	var c := Dungeon.floor_counts(fl)
	var ghosts := HBoxContainer.new()
	ghosts.add_theme_constant_override("separation", 2)
	ghosts.size_flags_horizontal = SIZE_EXPAND_FILL
	ghosts.clip_contents = true
	if int(c.lost) == 0:
		ghosts.add_child(UiTheme.label("everyone", UiTheme.MUTED, UiTheme.SMALL))
	else:
		var looks: Array[Texture2D] = []
		for uid in fl.get("lost_cards", []):
			if front.has(str(uid)) and looks.size() < 8:
				var pet: Pet = front[str(uid)]
				looks.append(PetLook.texture_for(pet.parts, false, pet.sewn))
		if looks.is_empty():  # nobody from the front row: a few of the shelves' faces
			var lh: Dictionary = fl.get("lost_herd", {})
			var keys := lh.keys()
			keys.sort()
			for k in keys:
				for i in mini(int(lh[k]), 3 - looks.size()):
					var face := Herd.stand_in(catalog, Herd.uid(str(k), 800000 + int(fl.f) * 31 + i))
					if face:
						looks.append(PetLook.texture_for(face.parts, false, face.sewn))
				if looks.size() >= 3:
					break
		var faded := _Ghosts.new(looks)
		faded.size_flags_vertical = SIZE_SHRINK_CENTER
		ghosts.add_child(faded)
		ghosts.add_child(UiTheme.label("%s stayed below" % UiTheme.num(int(c.lost)), UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(ghosts)
	var bumps := HBoxContainer.new()
	bumps.add_theme_constant_override("separation", 4)
	bumps.custom_minimum_size = Vector2(70, 0)
	if int(c.hurt) > 0:
		var pl := _Plaster.new()
		pl.size_flags_vertical = SIZE_SHRINK_CENTER
		bumps.add_child(pl)
		bumps.add_child(UiTheme.label(UiTheme.num(int(c.hurt)), UiTheme.MUTED, UiTheme.SMALL))
	row.add_child(bumps)
	var pay := HBoxContainer.new()
	pay.add_theme_constant_override("separation", 3)
	pay.custom_minimum_size = Vector2(64, 0)
	pay.alignment = BoxContainer.ALIGNMENT_END
	if bool(fl.get("cleared", true)):
		pay.add_child(UiTheme.title("+%s" % UiTheme.num(int(fl.get("pay", 0))), 13, UiTheme.WISP))
		var icon := UiTheme.icon_rect("lantern", 13, UiTheme.WISP)
		icon.size_flags_vertical = SIZE_SHRINK_CENTER
		pay.add_child(icon)
	row.add_child(pay)
	return p


## A counter on the run card or the report: a big number over its words.
func _tally(value: String, words: String, color: Color, plaster := false, right := false) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	if plaster:
		var pl := _Plaster.new()
		pl.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(pl)
	row.add_child(UiTheme.title(value, 20, color))
	if right:
		row.alignment = BoxContainer.ALIGNMENT_END
		var icon := UiTheme.icon_rect("lantern", 17, UiTheme.WISP)
		icon.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(icon)
	col.add_child(row)
	var w := UiTheme.label(words, UiTheme.MUTED, UiTheme.SMALL)
	if right:
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(w)
	return col


## The front row as small faces (your pet first with its flag): faded once it stayed below, a
## plaster when it got bumped.
func _faces(cards: Array, tally: Dictionary, cols: int, lead: Pet = null) -> Control:
	var cells: Array = []
	if lead == null:
		lead = GameState.collection.active()
	var catalog := GameState.catalog
	if lead:
		cells.append([PetLook.texture_for(lead.parts, false, lead.sewn), catalog.tier_color(lead.rarity), false, false, true])
	for pet: Pet in cards:
		var gone: bool = tally.lost_cards.has(pet.uid)
		cells.append([PetLook.texture_for(pet.parts, false, pet.sewn), catalog.tier_color(pet.rarity), gone,
			not gone and tally.hurt_cards.has(pet.uid), false])
	return _Faces.new(cells, cols)


# ---- came home ----------------------------------------------------------------------------

## The "came home" report: home! (or home early) and the deepest yet tag, 4 numbers, the front row's
## faces and the shelves' losses, floor by floor, the best bit, same again! / change the army.
func _home_card(r: Dictionary) -> Control:
	var catalog := GameState.catalog
	var run: Dictionary = r.run
	var tally: Dictionary = r.tally
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.WISP.lerp(UiTheme.LINE, 0.6), 12, UiTheme.RAISED, 12))
	card.size_flags_vertical = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var hh := HBoxContainer.new()
	hh.add_theme_constant_override("separation", 12)
	hh.add_child(UiTheme.title("home early" if str(run.get("why", "")) != "target" else "home!", 22, UiTheme.PINK))
	if bool(r.new_deep):
		var tag := PanelContainer.new()
		var tsb := UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 6, 0, 2)
		tsb.content_margin_left = 10
		tsb.content_margin_right = 10
		tsb.shadow_color = Color(UiTheme.GOLD, 0.4)
		tsb.shadow_size = 8
		tag.add_theme_stylebox_override("panel", tsb)
		tag.add_child(UiTheme.title("deepest yet: floor %d" % int(r.deepest), 12, UiTheme.DEEP))
		var tilt := Tilted.new(tag, 4.0)
		tilt.size_flags_vertical = SIZE_SHRINK_CENTER
		hh.add_child(tilt)
	hh.add_child(UiTheme.spacer())
	var start := int(run.get("start", 0))
	var route := UiTheme.label(("landing %d" % start if start > 0 else "the top") + " to floor %d" % int(r.deepest), UiTheme.MUTED, UiTheme.SMALL + 1)
	route.size_flags_vertical = SIZE_SHRINK_CENTER
	hh.add_child(route)
	col.add_child(hh)
	# the 4 numbers
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 10)
	var sent := int(run.get("sent", 0))
	stats.add_child(_stat("+%s" % UiTheme.num(int(r.got)), "wisps", UiTheme.WISP, "lantern"))
	stats.add_child(_stat(UiTheme.num(maxi(0, sent - int(tally.lost))), "came home of %s" % UiTheme.num(sent), UiTheme.TEXT))
	stats.add_child(_stat(UiTheme.num(int(tally.hurt)), "bumped", UiTheme.TEXT, "plaster"))
	stats.add_child(_stat(UiTheme.num(int(tally.lost)), "stayed below", UiTheme.MUTED))
	col.add_child(stats)
	# the front row's faces, and by shelf
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	var fcol := VBoxContainer.new()
	fcol.add_theme_constant_override("separation", 6)
	fcol.add_child(UiTheme.title("front row", 13, UiTheme.LILAC))
	fcol.add_child(_faces(r.front, tally, 11, r.lead))
	who.add_child(fcol)
	var scol := VBoxContainer.new()
	scol.add_theme_constant_override("separation", 4)
	scol.size_flags_horizontal = SIZE_EXPAND_FILL
	scol.add_child(UiTheme.title("by shelf", 13, UiTheme.LILAC))
	var any_shelf := false
	for tier in catalog.tiers:
		var id := str(tier.id)
		var lost := int(tally.lost_rarity.get(id, 0))
		var hurt := int(tally.hurt_rarity.get(id, 0))
		if lost <= 0 and hurt <= 0:
			continue
		any_shelf = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var tn := UiTheme.label(str(tier.name), catalog.tier_color(id), UiTheme.SMALL)
		tn.custom_minimum_size = Vector2(74, 0)
		row.add_child(tn)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.custom_minimum_size = Vector2(64, 0)
		var pl := _Plaster.new()
		pl.size_flags_vertical = SIZE_SHRINK_CENTER
		hb.add_child(pl)
		hb.add_child(UiTheme.label(UiTheme.num(hurt), UiTheme.TEXT, UiTheme.SMALL))
		row.add_child(hb)
		if lost > 0:
			row.add_child(UiTheme.label("%s stayed below" % UiTheme.num(lost), UiTheme.MUTED, UiTheme.SMALL))
		scol.add_child(row)
	if not any_shelf:
		scol.add_child(UiTheme.label("everyone came home", UiTheme.MUTED, UiTheme.SMALL))
	who.add_child(scol)
	col.add_child(who)
	# floor by floor
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 4)
	bcol.add_child(UiTheme.title("floor by floor", 13, UiTheme.LILAC))
	bcol.add_child(_Bars.new(run.get("floors", []), int(run.get("known", 0)), catalog))
	col.add_child(bcol)
	var best := _best(r.best)
	if best:
		col.add_child(best)
	var spring := Control.new()
	spring.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(spring)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	var again := UiTheme.button("same again!", func():
		if not GameState.send_army():
			GameState.drop_dungeon_report()
			return
		PetBubble.say_line(self, "dungeon_go"))
	again.name = "same_again"
	again.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
	again.add_theme_font_size_override("font_size", 16)
	var asb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 7)
	asb.content_margin_left = 16
	asb.content_margin_right = 16
	again.add_theme_stylebox_override("normal", asb)
	again.disabled = int(GameState.army().sent) == 0
	foot.add_child(again)
	var change := UiTheme.button("change the army", func():
		GameState.drop_dungeon_report()
		PetBubble.say_line(self, "dungeon"))
	change.name = "change_army"
	change.size_flags_vertical = SIZE_SHRINK_CENTER
	foot.add_child(change)
	col.add_child(foot)
	return card


## One of the report's 4 numbers, with its words under it.
func _stat(value: String, words: String, color: Color, icon := "") -> Control:
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 7)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_horizontal = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	p.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	if icon == "plaster":
		var pl := _Plaster.new()
		pl.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(pl)
	row.add_child(UiTheme.title(value, 21, color))
	if icon == "lantern":
		var ic := UiTheme.icon_rect("lantern", 18, UiTheme.WISP)
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(ic)
	col.add_child(row)
	var w := UiTheme.label(words, UiTheme.MUTED, UiTheme.SMALL)
	w.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	w.clip_text = true
	w.custom_minimum_size = Vector2(40, 0)
	col.add_child(w)
	return p


## The best bit of the run: a first find, else the deepest yet, else the glowiest floor.
func _best(b: Dictionary) -> Control:
	if b.is_empty():
		return null
	var text := ""
	match str(b.kind):
		"find":
			text = "%s!" % str(b.what)
		"part":
			text = "a shiny %s part to keep!" % str(b.what)
		"deep":
			text = "nobody had been past floor %d before!" % int(b.was) if int(b.was) > 0 else "the very first floors, all lit up!"
		_:
			text = "the glowiest floor: +%s wisps" % UiTheme.num(int(b.get("pay", 0)))
	var p := PanelContainer.new()
	var sb := UiTheme.stitched(UiTheme.GOLD.lerp(UiTheme.LINE, 0.55), UiTheme.DEEP, 10, 6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	p.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	row.add_child(UiTheme.title("best bit", 13, UiTheme.GOLD))
	var spark := _Spark.new()
	spark.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(spark)
	var t := UiTheme.label(text, UiTheme.TEXT, UiTheme.SMALL + 1)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	row.add_child(t)
	row.add_child(UiTheme.label("floor %d" % int(b.f), UiTheme.MUTED, UiTheme.SMALL))
	return p


# ---- held landings -----------------------------------------------------------------------------

## Opens a held landing's card in the army card's place (a tap on its crowd or pill), or closes it with 0.
func pick_hold(f: int) -> void:
	if f != _hold_f:
		_send = {}
	_hold_f = f
	_column.set_hold_picked(f)
	_reveal_hold = f
	_dirty = true


## No landing card open, and no ring on any pill.
func _drop_hold() -> void:
	_hold_f = 0
	_send = {}
	_column.set_hold_picked(0)


## Scrolls the well so a held landing's crowd and pill are in the middle (its card just opened).
func _show_hold(f: int) -> void:
	await get_tree().process_frame
	var spot := _column.hold_spot(f)
	var h := _scroll.size.y
	if spot == null or h <= 0.0:
		return
	var want := spot.position.y + spot.size.y / 2.0 - h / 2.0
	_scroll.scroll_vertical = int(clampf(want, 0.0, maxf(0.0, _column.custom_minimum_size.y - h)))


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
	card.size_flags_vertical = SIZE_SHRINK_BEGIN if full else SIZE_EXPAND_FILL
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
		var tname := HBoxContainer.new()
		tname.add_theme_constant_override("separation", 6)
		tname.add_child(UiTheme.label(str(tier.name), catalog.tier_color(tier.id), UiTheme.SMALL + 1))
		var tof := UiTheme.label("of %s" % UiTheme.num(GameState.homes_can_go(tier.id)), UiTheme.MUTED, UiTheme.SMALL - 1)
		tof.size_flags_vertical = SIZE_SHRINK_END
		tname.add_child(tof)
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
	go.size_flags_horizontal = SIZE_SHRINK_END
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
	_build_desk(a, GameState.army_rules(a) if int(a.sent) > 0 else {})


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


# ---- little pieces --------------------------------------------------------------------------

## An orders line: words and choices that wrap if they have to (never past the card).
func _line(head: Control = null) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 6)
	f.add_theme_constant_override("v_separation", 4)
	if head:
		f.add_child(head)
	return f


func _word(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.TEXT, UiTheme.SMALL + 1)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	return l


## A row of choices (never a dropdown: their popups open behind the always-on-top window).
## on_pick(index) when one is tapped; `key` names the buttons for flows (order_<key>_<i>).
func _pick(options: Array, current: int, on_pick: Callable, off: bool, key: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 2))
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	p.add_child(row)
	for i in options.size():
		var on := i == current
		var b := Button.new()
		b.name = "order_%s_%d" % [key, i]
		b.text = str(options[i])
		b.focus_mode = FOCUS_NONE
		b.disabled = off and not on
		b.add_theme_font_size_override("font_size", UiTheme.SMALL)
		var st := UiTheme.box(UiTheme.PINK_PRESSED if on else Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 1)
		st.content_margin_left = 4
		st.content_margin_right = 4
		for s in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			b.add_theme_stylebox_override(s, st)
		b.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.MUTED)
		b.add_theme_color_override("font_hover_color", UiTheme.TEXT if on else UiTheme.PINK)
		b.add_theme_color_override("font_disabled_color", Color(UiTheme.MUTED, 0.5))
		if not on and not off:
			b.pressed.connect(func(): on_pick.call(i))
		row.add_child(b)
	return p


## A flat little link ("empty", "best ones", "pick ›").
func _link(text: String, on_pressed: Callable) -> Button:
	var b := UiTheme.small_button(text, on_pressed)
	b.add_theme_font_size_override("font_size", UiTheme.SMALL)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	b.add_theme_color_override("font_disabled_color", Color(UiTheme.MUTED, 0.4))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.size_flags_horizontal = SIZE_SHRINK_BEGIN
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	return b


## A small sunk button that lights pink while it's on ("all").
func _chip_button(text: String, on: bool, on_pressed: Callable) -> Button:
	var b := UiTheme.button(text, on_pressed)
	b.add_theme_font_size_override("font_size", UiTheme.SMALL)
	var sb := UiTheme.box(UiTheme.PINK_PRESSED if on else UiTheme.DEEP, UiTheme.PINK if on else UiTheme.LINE, 8, 2, 1)
	var hover := sb.duplicate()
	hover.border_color = UiTheme.PINK_SEAM if not on else UiTheme.PINK
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", sb)
	b.add_theme_stylebox_override("disabled", sb)
	b.add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	return b


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
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.size_flags_horizontal = SIZE_SHRINK_BEGIN
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


func _sticker(margin := 11) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.sticker(UiTheme.LINE, 12, UiTheme.RAISED, margin)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	p.add_theme_stylebox_override("panel", sb)
	return p


func _h3(text: String) -> Label:
	return UiTheme.title(text, 15, UiTheme.LILAC)


## A little coral pennant on a pole: this landing is held.
class _Pennant extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(14, 16)
		size_flags_vertical = SIZE_SHRINK_CENTER
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(3, 1), Vector2(3, 15), UiTheme.MUTED, 1.6, true)
		draw_colored_polygon(PackedVector2Array([Vector2(3.5, 2), Vector2(13, 5), Vector2(3.5, 8)]), UiTheme.WISP)


## A sticking plaster (bumped).
class _Plaster extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(16, 12)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		paint(self, size / 2.0, 1.0)

	static func paint(ci: CanvasItem, c: Vector2, s: float) -> void:
		ci.draw_set_transform(c, deg_to_rad(-20.0), Vector2(s, s))
		ci.draw_style_box(UiTheme.box(UiTheme.TEXT, UiTheme.TEXT, 3, 0, 0), Rect2(-7, -3.5, 14, 7))
		ci.draw_rect(Rect2(-2, -1.5, 4, 3), UiTheme.MUTED.lerp(UiTheme.TEXT, 0.3))
		ci.draw_set_transform(Vector2.ZERO)


## A little gold sparkle (the best bit).
class _Spark extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(18, 18)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size / 2.0
		var pts := PackedVector2Array()
		for i in 8:
			var a := -PI / 2.0 + i * PI / 4.0
			pts.append(c + Vector2(cos(a), sin(a)) * (8.0 if i % 2 == 0 else 2.0))
		draw_colored_polygon(pts, UiTheme.GOLD)


## Faded faces in a row (pets that stayed below: never named).
class _Ghosts extends Control:
	var _looks: Array[Texture2D] = []

	func _init(looks: Array[Texture2D]) -> void:
		_looks = looks
		custom_minimum_size = Vector2(maxi(looks.size(), 1) * 18 - 2, 18)
		texture_filter = TEXTURE_FILTER_NEAREST
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in _looks.size():
			draw_texture_rect(_looks[i], Rect2(Vector2(i * 18, 0), Vector2(16, 18)), false, Color(1, 1, 1, 0.24))


## Small faces of the front row: [texture, tier colour, gone, bumped, leads], `cols` to a row.
class _Faces extends Control:
	const CELL := Vector2(22, 24)
	const GAP := 3.0
	var _cells: Array = []
	var _cols := 10

	func _init(cells: Array, cols: int) -> void:
		_cells = cells
		_cols = maxi(cols, 1)
		var rows := maxi(1, ceili(cells.size() / float(_cols)))
		var across := mini(cells.size(), _cols)
		custom_minimum_size = Vector2(maxi(across, 1) * (CELL.x + GAP) - GAP, rows * (CELL.y + GAP) - GAP + 4.0)
		texture_filter = TEXTURE_FILTER_NEAREST
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for i in _cells.size():
			var c: Array = _cells[i]
			var at := Vector2(i % _cols * (CELL.x + GAP), 4.0 + i / _cols * (CELL.y + GAP))
			var r := Rect2(at, CELL)
			var tint: Color = (c[1] as Color).lerp(UiTheme.DEEP, 0.3)
			if c[2]:  # stayed below: faded, dashed
				var sb := StitchBox.new()
				sb.bg_color = Color(UiTheme.DEEP, 0.4)
				sb.dash_color = Color(tint, 0.35)
				sb.radius = 6
				sb.dash = 3.0
				sb.gap = 3.0
				draw_style_box(sb, r)
				draw_texture_rect(c[0], Rect2(at + Vector2(3, 5), Vector2(16, 18)), false, Color(1, 1, 1, 0.25))
				continue
			draw_style_box(UiTheme.box(UiTheme.DEEP, tint, 6, 2, 0), r)
			draw_texture_rect(c[0], Rect2(at + Vector2(3, 5), Vector2(16, 18)), false)
			if c[3]:  # bumped: a plaster
				_Plaster.paint(self, at + Vector2(CELL.x - 3.0, 2.0), 0.75)
			if c[4]:  # your pet leads: a tiny pink flag
				var f := at + Vector2(-3, -4)
				draw_line(f + Vector2(2, 9), f + Vector2(2, 0), UiTheme.PINK, 1.6, true)
				draw_colored_polygon(PackedVector2Array([f + Vector2(2.5, 0.5), f + Vector2(8, 2.5), f + Vector2(2.5, 4.5)]), UiTheme.PINK)


## The entrance as a pill filled by who goes: the front row, then each shelf in its own colour.
class _Gate extends Control:
	var _parts: Array = []  # [n, colour]
	var _room := 1
	var _full := false

	func _init(cards: int, herd: Dictionary, room: int) -> void:
		_room = maxi(room, 1)
		custom_minimum_size = Vector2(60, 14)
		mouse_filter = MOUSE_FILTER_IGNORE
		var total := cards
		_parts.append([cards, UiTheme.PINK_SEAM])
		var catalog := GameState.catalog
		var tiers: Array = catalog.tiers.duplicate()
		tiers.reverse()
		for tier in tiers:
			var n := int(herd.get(tier.id, 0))
			if n > 0:
				_parts.append([n, catalog.tier_color(str(tier.id))])
				total += n
		_full = total >= _room

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if _full else UiTheme.LILAC.lerp(UiTheme.LINE, 0.6), 7, 2, 0), r)
		var inner := r.grow(-3.0)
		var x := inner.position.x
		for p in _parts:
			var w := minf(inner.end.x - x, inner.size.x * float(p[0]) / _room)
			if w <= 0.0:
				continue
			draw_rect(Rect2(Vector2(x, inner.position.y), Vector2(w, inner.size.y)), p[1])
			x += w + (1.0 if w > 2.0 else 0.0)


## A shelf's slider: 10 pips, filled up to how many go (a part-filled pip for the rest). Tap a pip to
## fill to it (the last one on again: one less), or drag along; it's set when you let go.
class _PipSlider extends Control:
	var _color := Color.WHITE
	var _on := 0
	var _have := 0
	var _on_set: Callable
	var _drag := -1.0  # while dragging: the fraction shown

	func _init(color: Color, on: int, have: int, on_set: Callable) -> void:
		_color = color
		_on = on
		_have = maxi(have, 0)
		_on_set = on_set
		custom_minimum_size = Vector2(90, 18)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND

	func _frac() -> float:
		if _drag >= 0.0:
			return _drag
		return clampf(float(_on) / _have, 0.0, 1.0) if _have > 0 else 0.0

	func _pip_at(x: float) -> int:
		return clampi(ceili(x / maxf(size.x, 1.0) * 10.0), 0, 10)

	func _gui_input(event: InputEvent) -> void:
		if _have <= 0:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var k := _pip_at(event.position.x)
				var cur := roundi(_frac() * 10.0)
				_drag = (k - 1) / 10.0 if k == cur else k / 10.0
				queue_redraw()
			elif _drag >= 0.0:
				var n := ceili(_have * _drag - 0.0001) if _have < 10 else roundi(_have * _drag)  # (a small shelf: every pip counts)
				_drag = -1.0
				_on_set.call(n)
			accept_event()
		elif event is InputEventMouseMotion and _drag >= 0.0 and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_drag = _pip_at(event.position.x) / 10.0
			queue_redraw()
			accept_event()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if is_hovered_now() else UiTheme.LINE, 8, 2, 0), r)
		var inner := r.grow(-4.0)
		var gap := 3.0
		var w := (inner.size.x - gap * 9.0) / 10.0
		var on := _frac() * 10.0
		var dim := _color.lerp(UiTheme.DEEP, 0.85)
		var lit := _color.lerp(UiTheme.DEEP, 0.15)
		for k in 10:
			var pr := Rect2(Vector2(inner.position.x + k * (w + gap), inner.position.y), Vector2(w, inner.size.y))
			draw_style_box(UiTheme.box(dim, _color.lerp(UiTheme.LINE, 0.75), 3, 1, 0), pr)
			var fill := clampf(on - k, 0.0, 1.0)
			if fill > 0.0:
				var fr := Rect2(pr.position, Vector2(pr.size.x * fill, pr.size.y))
				draw_style_box(UiTheme.box(lit, _color if fill >= 1.0 else lit, 3, 1, 0), fr)

	func is_hovered_now() -> bool:
		return get_global_rect().has_point(get_global_mouse_position()) and _have > 0

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()


## Floor by floor: a bar per floor, as tall as how many stayed below (pink where it was hot), the
## number over it, the floor under it (gold for new ones) and its feeling word when there's room.
class _Bars extends Control:
	const H := 74.0
	var _floors: Array = []
	var _known := 0
	var _catalog: Catalog

	func _init(floors: Array, known: int, catalog: Catalog) -> void:
		_floors = floors
		_known = known
		_catalog = catalog
		custom_minimum_size = Vector2(0, H)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var n := _floors.size()
		if n == 0:
			return
		var font := UiTheme.BODY_FONT if UiTheme.BODY_FONT else get_theme_default_font()
		var gap := 6.0 if n <= 20 else 2.0
		var bw := (size.x - gap * (n - 1)) / n
		var most := 1
		for fl in _floors:
			most = maxi(most, int(Dungeon.floor_counts(fl).lost))
		var words := bw >= 46.0
		var label_every := maxi(1, ceili(22.0 / maxf(bw + gap, 1.0)))
		var foot := 24.0 if words else 12.0
		var top := 12.0
		for i in n:
			var fl: Dictionary = _floors[i]
			var lost := int(Dungeon.floor_counts(fl).lost)
			var word := Dungeon.word(_catalog, float(fl.get("ratio", 1.0)))
			var x := i * (bw + gap)
			var cw := minf(bw, 34.0)
			var cx := x + (bw - cw) / 2.0
			var base := size.y - foot
			var h := 2.0 if lost == 0 else maxf(3.0, (base - top) * lost / most)
			var col := UiTheme.LINE if lost == 0 else (UiTheme.PINK_SEAM if str(word[1]) != "" else UiTheme.MUTED.lerp(UiTheme.DEEP, 0.5))
			draw_style_box(UiTheme.box(col, col, 3 if h > 6.0 else 1, 0, 0), Rect2(cx, base - h, cw, h))
			if lost > 0 and bw >= 18.0:
				var t := UiTheme.num(lost)
				var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				draw_string(font, Vector2(x + (bw - tw) / 2.0, base - h - 3.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, UiTheme.MUTED)
			if i % label_every == 0 or i == n - 1:
				var f := str(int(fl.f))
				var fw := font.get_string_size(f, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				draw_string(font, Vector2(x + (bw - fw) / 2.0, base + 10.0), f, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
					UiTheme.GOLD if int(fl.f) > _known else UiTheme.MUTED)
			if words:
				var ww := font.get_string_size(str(word[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
				draw_string(font, Vector2(x + maxf(0.0, (bw - ww) / 2.0), base + 21.0), str(word[0]), HORIZONTAL_ALIGNMENT_LEFT, bw, 9,
					UiTheme.PINK if str(word[1]) == "hot" else UiTheme.MUTED)
