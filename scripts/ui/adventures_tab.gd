class_name AdventuresTab
extends VBoxContainer
## Sending pets on adventures ("trips"). Up to three pages, switched at the top: adventures,
## upgrades (gear for the trips, bought with xp: GearView; once the first xp is home) and the
## dungeon (the old well, all the way down: DungeonView; once the rope find opens it).
## Your pet's crayon map of the world (MapView) fills the
## left; tapping a place sticks a card onto the map for picking who goes there. A hands-on trip
## can be watched up close on the trail (TrailView), in the map's place. The trips that are away
## are stickers on the right: one waiting at an event shows its options, one that's back shows
## what it brought. Your active pet talks about it all in the shared bubble (PetBubble).
## All the rules live in AdventureRunner; this only shows them and passes on clicks.

const PAGE_SIZE := 12
const QUICK_PICK := 10

var _location_id := ""
var _map := MapView.new()
var _trail := TrailView.new()  # a hands-on trip up close, see TrailView
var _picker := PanelContainer.new()
var _place_title := UiTheme.title("", 18)
var _place_note := UiTheme.label("", UiTheme.GOLD, UiTheme.SMALL + 1)
var _facts := HFlowContainer.new()
var _lights := Control.new()  # next door: the little windows of the house behind the place, lit ones still to go
var _stuck: Tilted  # holds the place card on the map (it moves to the left on the street when the garden is on the right)
var _odds := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
## Why you'd send more than one pet, in plain words (shown once parties are open)
var _send: Button
var _picked := {}  # uid -> true
var _picked_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _quick := GridContainer.new()
var _grid := GridContainer.new()
var _page := 0
var _pager := HBoxContainer.new()
var _page_label := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
var _runs := VBoxContainer.new()
var _run_rows: Array[Dictionary] = []  # { run, bar, time } or { run, countdown }
var _postcard := Postcard.new()  # what a trip brought home, after "welcome back"
var _dirty := true
var _nudge_at := 0  # ticks (ms) before your pet asks again for another party (see _nudge_more)
const NUDGE_EVERY_MS := 300000
var _estimate_key := ""  # which picks the cached estimate is for
var _knacks_key := ""  # which picks (and knacks) the cached trip knacks are for (see _trip_key)
var _knacks := {}  # what the picked pets would pack (GameState.trip_knacks), kept for big swarms
var _estimate := 1.0
var _tick := 0.0
var _voice_rng := RandomNumberGenerator.new()
var gear_view := GearView.new()  # the upgrades page
var dungeon_view := DungeonView.new()  # the dungeon page
var _wisp_chip: PanelContainer  # the darker currency, by the switch on the dungeon page
var _wisp_label: Label
var _perks: Button  # "perks" by the wisps: the well wall's sheet over the dungeon page (a gold dot: one you can afford)
var _perks_dot := false
var _main := HBoxContainer.new()  # the adventures page: the map (or trail) and the trips away
var _bar := HBoxContainer.new()
var _mode: PanelContainer
var _quiet := false  # the page is being flipped for you (to the trail, to a place): your pet says nothing
var edge_card := EdgeCard.new()  # the edge's shelves, once its signpost on the map is tapped
var _shop := WorkshopCard.new()  # the shed workshop, stuck on the map instead of the shed's place card
var _shop_stuck: Tilted
var _to_shop: Button  # on the shed's place card: back to the workshop


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	_voice_rng.randomize()
	# adventures | upgrades | dungeon, like machine | upgrades (each hidden until it's there)
	_mode = UiTheme.segmented(["adventures", "upgrades", "dungeon"], 0, func(i): _show_page(i))
	_bar.add_child(_mode)
	_bar.add_child(UiTheme.spacer())
	_wisp_chip = PanelContainer.new()
	var chip_sb := UiTheme.box(UiTheme.DEEP, UiTheme.WISP.lerp(UiTheme.LINE, 0.6), 999, 2, 0)
	chip_sb.content_margin_left = 8
	chip_sb.content_margin_right = 14
	chip_sb.content_margin_top = 2
	chip_sb.content_margin_bottom = 2
	_wisp_chip.add_theme_stylebox_override("panel", chip_sb)
	_wisp_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 7)
	chip_row.add_child(UiTheme.icon_rect("lantern", 20, UiTheme.WISP))
	_wisp_label = UiTheme.title("0", 18, UiTheme.WISP)
	chip_row.add_child(_wisp_label)
	_wisp_chip.add_child(chip_row)
	_wisp_chip.tooltip_text = str(Catalog.shared().dungeon.get("currency", {}).get("word", "wisps"))
	_wisp_chip.visible = false
	_bar.add_child(_wisp_chip)
	_perks = Button.new()
	_perks.name = "perks"
	_perks.text = "perks"
	_perks.focus_mode = FOCUS_NONE
	_perks.icon = PerkNail.texture("bow", "on", 16)
	_perks.add_theme_constant_override("h_separation", 5)
	_perks.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	var pk := UiTheme.stitched(UiTheme.WISP.lerp(UiTheme.LINE, 0.5), UiTheme.DEEP, 999, 3)
	pk.content_margin_left = 9
	pk.content_margin_right = 12
	var pk_on := UiTheme.stitched(UiTheme.WISP, UiTheme.DEEP.lerp(UiTheme.WISP, 0.16), 999, 3)
	pk_on.content_margin_left = 9
	pk_on.content_margin_right = 12
	var pk_hover := pk.duplicate()
	pk_hover.dash_color = UiTheme.PINK
	_perks.add_theme_stylebox_override("normal", pk)
	_perks.add_theme_stylebox_override("hover", pk_hover)
	_perks.add_theme_stylebox_override("pressed", pk_on)
	_perks.add_theme_stylebox_override("hover_pressed", pk_on)
	_perks.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_perks.add_theme_color_override("font_color", UiTheme.TEXT)
	_perks.add_theme_color_override("font_hover_color", UiTheme.PINK)
	_perks.add_theme_color_override("font_pressed_color", UiTheme.TEXT)
	_perks.toggle_mode = true
	_perks.size_flags_vertical = SIZE_SHRINK_CENTER
	_perks.visible = false
	_perks.toggled.connect(func(on: bool):
		dungeon_view.show_wall(on)
		_perks.set_pressed_no_signal(dungeon_view.wall_open()))
	_perks.draw.connect(func():  # the gold dot: a perk you can afford
		if _perks_dot:
			_perks.draw_circle(Vector2(_perks.size.x - 3.0, 3.0), 4.0, UiTheme.GOLD))
	_bar.add_child(_perks)
	_refresh_bar()
	add_child(_bar)
	_main.add_theme_constant_override("separation", 14)
	_main.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_main)
	gear_view.visible = false
	add_child(gear_view)
	dungeon_view.visible = false
	add_child(dungeon_view)
	_location_id = GameState.open_locations()[0].id

	# the map, with the place card stuck onto it and the trail in its place when watching
	var area := Control.new()
	area.size_flags_horizontal = SIZE_EXPAND_FILL
	area.size_flags_vertical = SIZE_EXPAND_FILL
	_main.add_child(area)
	for c in [_map, _trail]:
		c.set_anchors_preset(PRESET_FULL_RECT)
		area.add_child(c)
	_trail.visible = false
	_trail.back_to_map.connect(func(): _show_map(true))
	_trail.welcome_back.connect(_collect)
	_postcard.set_anchors_preset(PRESET_FULL_RECT)
	_postcard.visible = false
	_postcard.closed.connect(func():
		_postcard.visible = false
		_show_map(true))
	_build_picker()
	_picker.visible = false
	# the card sticks onto the map's top right, a little crooked
	_stuck = Tilted.new(_picker, 1.0)
	_stick_card(false)
	area.add_child(_stuck)
	# the workshop card sticks onto the map's top left, crooked the other way (the shed is on the right)
	_shop_stuck = Tilted.new(_shop, -1.0)
	_shop_stuck.set_anchors_preset(PRESET_TOP_LEFT)
	_shop_stuck.offset_left = 12
	_shop_stuck.offset_top = 46
	_shop_stuck.visible = false
	area.add_child(_shop_stuck)
	_shop.closed.connect(func():
		_show_map(true)
		PetBubble.say(self, str(Catalog.shared().workshop.get("close_say", ""))))
	_shop.to_place.connect(func(): _choose_place("shed", true))
	area.add_child(_postcard)  # over the map and the place card
	_main.add_child(_runs_column())

	_map.place_picked.connect(func(id): _choose_place(id))
	_map.letter_picked.connect(_open_letterbox)
	_map.lead_picked.connect(func(id): GameState.follow_lead(id))
	_map.rumour_picked.connect(func(id): GameState.follow_rumour(id))
	_map.edge_picked.connect(_pick_edge)
	_map.page_changed.connect(func(_p): _refresh_edge_card())
	edge_card.target = _map.edge_point
	edge_card.fly_host = self
	# not GameState.changed: that also fires on every passive coin
	GameState.adventures_changed.connect(func():
		_dirty = true
		# a trip your pet sent was welcomed back by itself: nothing left to watch
		if _trail.visible and _trail.run != null and _trail.run.auto and not _trail.run in GameState.runs:
			_show_map(true))
	GameState.collection.pets_added.connect(func(_p): _dirty = true)
	GameState.collection.pets_removed.connect(func(_u): _dirty = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	visibility_changed.connect(func():
		_rebuild_if_dirty()
		_drop_stale_trail()
		_watch()
		if not is_visible_in_tree():
			return
		# back on the upgrades or dungeon page: stay there (the trip can be watched from the adventures page)
		if gear_view.visible:
			gear_view.speak()
			return
		if dungeon_view.visible:
			dungeon_view.speak()
			return
		speak()
		# a hands-on trip is out: go along with it
		for run in GameState.runs:
			if _watchable(run) and run.status != RunState.Status.DONE:
				_show_trail(run)
				break)


## The active pet says something about what's going on; news of a trip it's talking about is
## used up, so it doesn't repeat itself next time.
func speak() -> void:
	var pet := GameState.collection.active()
	if pet == null:
		return
	var catalog := Catalog.shared()
	# big news first: something found, something new opened up
	var news := GameState.take_announcement()
	if news != "":
		PetBubble.say_all(self, [news, GameState.take_announcement()])
		return
	var what := PetVoice.situation(GameState.news, GameState.rumours, GameState.runs, catalog)
	GameState.news = {}
	PetBubble.say(self, PetVoice.line(pet, what, _voice_rng, catalog))


## 0 the adventures (map and trips), 1 the upgrades (gear), 2 the dungeon; flips the switch at the top too.
## `quiet`: flipped for you on the way to something else, so your pet doesn't talk over it.
func show_page(page: int, quiet := false) -> void:
	_quiet = quiet
	(_mode.get_child(0).get_child(page) as Button).pressed.emit()
	_quiet = false


## A page by its name ("dungeon", "upgrades"), for an unlock's "show me".
func show_named_page(page_name: String) -> void:
	var i := ["adventures", "upgrades", "dungeon"].find(page_name)
	if i >= 0:
		show_page(i)


func _show_page(page: int) -> void:
	_main.visible = page == 0
	gear_view.visible = page == 1
	dungeon_view.visible = page == 2
	_refresh_bar()
	_watch()
	if _quiet:
		return
	match page:
		1: gear_view.speak()
		2: dungeon_view.speak()
		_: speak()


## The switch shows once there's more than one page; each page's button only once it's there, and
## the wisps by it on the dungeon page.
func _refresh_bar() -> void:
	var row := _mode.get_child(0)
	var gear_on := GameState.gear_page_open()
	var dungeon_on := GameState.dungeon_open()
	(row.get_child(1) as Control).visible = gear_on
	(row.get_child(2) as Control).visible = dungeon_on
	_bar.visible = gear_on or dungeon_on
	_wisp_chip.visible = dungeon_view.visible
	_wisp_label.text = UiTheme.num(GameState.wisps)
	_perks.visible = dungeon_view.visible and not GameState.perks_shown().is_empty()
	_perks.set_pressed_no_signal(_perks.visible and dungeon_view.wall_open())
	var dot := _perks.visible and GameState.perks_affordable()
	if dot != _perks_dot:
		_perks_dot = dot
		_perks.queue_redraw()
	if (gear_view.visible and not gear_on) or (dungeon_view.visible and not dungeon_on):
		show_page(0, true)


## The signpost at the edge was tapped: its card turns up in the right column.
func _pick_edge() -> void:
	_picker.visible = false
	_refresh_edge_card()
	PetBubble.say_line(self, "edge_cheer")


## The edge's card shows while its signpost is picked (on its page, with pets still to go).
func _refresh_edge_card() -> void:
	edge_card.visible = _map.visible and _map.selected == MapView.EDGE_ID and GameState.edge_open()


## Shows a page of the map (the dev driver's "map-page").
func show_map_page(page_id: String) -> void:
	if not _main.visible:
		show_page(0, true)
	_show_map(true)
	_map.show_map_page(page_id)


## As if the signpost at the edge was tapped (the dev driver's "edge").
func pick_edge() -> void:
	_map.pick_edge()


## Opens a place's card, as if it was tapped on the map (dev flag --pick).
func pick_place(location_id: String) -> void:
	if not _main.visible:
		show_page(0, true)
	_choose_place(location_id)


## The place card sticks onto the map's top right, a little crooked; on next door's street it goes
## top left when the garden you picked is on the right, so it doesn't cover it.
func _stick_card(left: bool) -> void:
	if left:
		_stuck.set_anchors_preset(PRESET_TOP_LEFT)
		_stuck.grow_horizontal = GROW_DIRECTION_END
		_stuck.offset_left = 12
		_stuck.offset_right = 12
		_stuck.offset_top = 52
		_stuck.degrees = -1.0
	else:
		_stuck.set_anchors_preset(PRESET_TOP_RIGHT)
		_stuck.grow_horizontal = GROW_DIRECTION_BEGIN
		_stuck.offset_left = -14
		_stuck.offset_right = -14
		_stuck.offset_top = 40
		_stuck.degrees = 1.0
	_stuck.reset_size()


## A place on the map was tapped: stick its card onto the map to pick who goes. The old shed, once
## the workshop is open, sticks the workshop card instead (`as_place`: its place card after all).
func _choose_place(location_id: String, as_place := false) -> void:
	if location_id == "shed" and not as_place and GameState.workshop_shown():
		_location_id = location_id
		_map.selected = location_id
		_map.queue_redraw()
		_show_map(false)
		_picker.visible = false
		_shop_stuck.visible = true
		_shop.open()
		return
	_shop_stuck.visible = false
	var location := Catalog.shared().location(location_id)
	var street := str(Catalog.shared().page_info(str(location.get("page", ""))).get("layout", "")) == "street"
	_stick_card(street and not StreetPage.in_fence(location) and int(location.get("map", {}).get("x", 0)) >= 2)
	_location_id = location_id
	_map.selected = location_id
	_map.queue_redraw()
	_refresh_edge_card()
	_trim_to_party_size()
	_show_map(false)
	_rebuild_picker()


func _show_map(on: bool) -> void:
	_map.visible = true
	_picker.visible = not on
	_trail.visible = false
	if on:
		_shop_stuck.visible = false
		_map.selected = ""
		_map.refresh()
	_refresh_edge_card()
	_watch()


## The trip on the trail is the one you're watching (the bell rope and the weather vane leave it
## to you), while the trail shows.
func _watch() -> void:
	GameState.watching = _trail.run if _trail.is_visible_in_tree() and _trail.run != null else null


## The trip on the trail was welcomed back while you were away (the bell rope): back to the map,
## where its postcard pops up.
func _drop_stale_trail() -> void:
	if _trail.visible and (_trail.run == null or not _trail.run in GameState.runs):
		_show_map(true)


## Up close on a hands-on trip: the trail, where you click it along.
func _show_trail(run: RunState) -> void:
	if not _main.visible:
		show_page(0, true)
	_trail.show_run(run)
	_postcard.visible = false
	_map.visible = false
	_picker.visible = false
	_shop_stuck.visible = false
	_trail.visible = true
	_refresh_edge_card()
	_watch()


# ---- the place card ----------------------------------------------------------------

func _build_picker() -> void:
	_picker.custom_minimum_size = Vector2(256, 0)
	_picker.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	_picker.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	_place_title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(_place_title)
	_to_shop = UiTheme.small_button("workshop ›", func(): _choose_place("shed"))
	_to_shop.add_theme_font_size_override("font_size", UiTheme.SMALL)
	_to_shop.add_theme_color_override("font_color", UiTheme.MUTED)
	_to_shop.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_to_shop)
	col.add_child(head)
	col.add_child(_place_note)
	_lights.draw.connect(_draw_lights)
	col.add_child(_lights)
	_facts.add_theme_constant_override("h_separation", 5)
	_facts.add_theme_constant_override("v_separation", 5)
	col.add_child(_facts)
	_odds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_odds)

	var who := HBoxContainer.new()
	who.add_child(UiTheme.label("who's going?", UiTheme.MUTED, UiTheme.SMALL))
	who.add_child(UiTheme.spacer())
	who.add_child(_picked_label)
	col.add_child(who)

	_quick.columns = 3
	_quick.add_theme_constant_override("h_separation", 4)
	_quick.add_theme_constant_override("v_separation", 4)
	var catalog := Catalog.shared()
	for tier in catalog.tiers:
		var b := UiTheme.filter_chip("+%d %s" % [QUICK_PICK, tier.name], catalog.tier_color(tier.id))
		b.toggle_mode = false
		b.pressed.connect(_quick_pick.bind(tier.id))
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		_quick.add_child(b)
	var clear := UiTheme.filter_chip("clear", UiTheme.MUTED)
	clear.toggle_mode = false
	clear.pressed.connect(func():
		_picked.clear()
		_rebuild_picker())
	clear.size_flags_horizontal = SIZE_EXPAND_FILL
	_quick.add_child(clear)
	col.add_child(_quick)

	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	col.add_child(_grid)
	_pager.add_child(UiTheme.spacer())
	_pager.add_child(UiTheme.small_button("‹", func(): _turn(-1)))
	_pager.add_child(_page_label)
	_pager.add_child(UiTheme.small_button("›", func(): _turn(1)))
	col.add_child(_pager)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var not_yet := UiTheme.button("not yet", func(): _show_map(true))
	not_yet.size_flags_horizontal = SIZE_EXPAND_FILL
	buttons.add_child(not_yet)
	_send = UiTheme.button("send them", _send_picked)
	_send.icon = UiTheme.icon("heart", 14)
	_send.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_send.add_theme_constant_override("icon_max_width", 14)
	_send.add_theme_color_override("icon_normal_color", Color.WHITE)
	_send.add_theme_color_override("icon_hover_color", Color.WHITE)
	_send.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))
	_send.size_flags_horizontal = SIZE_EXPAND_FILL
	_send.size_flags_stretch_ratio = 1.5
	buttons.add_child(_send)
	col.add_child(buttons)


## One pet you could send: a little tile with its picture; picked ones are stitched and tilted.
func _chip(pet: Pet) -> Control:
	var catalog := Catalog.shared()
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(50, 46)
	b.tooltip_text = "%s (%s)" % [pet.display_name(catalog), catalog.tier_at(catalog.rank(pet.rarity)).name]
	var picked := _picked.has(pet.uid)
	var sb: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.PINK_PRESSED, 8, 2) if picked else UiTheme.box(UiTheme.DEEP, catalog.tier_color(pet.rarity).lerp(UiTheme.LINE, 0.5), 8, 2, 2)
	var hover := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 2)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb if picked else hover)
	b.add_theme_stylebox_override("pressed", sb)
	var portrait := PetPortrait.new(2, false)
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_pet(pet)
	b.add_child(portrait)
	b.resized.connect(func(): portrait.position = b.size / 2.0 - portrait.custom_minimum_size / 2.0)
	b.pressed.connect(_toggle.bind(pet))
	b.set_meta("pet", pet)
	return Tilted.new(b, -3.0 if picked else 0.0)


# ---- trips that are away ----------------------------------------------------------

func _runs_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(252, 0)
	col.add_theme_constant_override("separation", 8)
	edge_card.visible = false
	col.add_child(edge_card)
	col.add_child(UiTheme.title("away", 17))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_runs.size_flags_horizontal = SIZE_EXPAND_FILL
	_runs.add_theme_constant_override("separation", 12)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_bottom", 8)
	pad.add_child(_runs)
	scroll.add_child(pad)
	col.add_child(scroll)
	if OS.is_debug_build():
		for dev in [["dev: skip the walking", func(): GameState.debug_finish_runs()],
				["dev: unlock everything", func(): GameState.debug_unlock_all()],
				["dev: lock everything", func(): GameState.debug_lock_all()]]:
			var b := UiTheme.button(dev[0], dev[1])
			b.add_theme_font_size_override("font_size", UiTheme.SMALL)
			col.add_child(b)
	return col


# ---- picking ----------------------------------------------------------------

func _max_party() -> int:
	return GameState.max_party(_location_id)


## Pets you could send, weakest first (so quick picks never grab your best ones). A place for
## one pet lists the strongest first instead: that's the one you'd take yourself.
func _available() -> Array[Pet]:
	var catalog := Catalog.shared()
	var strongest_first := _max_party() == 1
	var pets := GameState.sendable_pets()
	var busy := {}  # on an errand or working in automation: picked last
	for p in pets:
		if GameState.job_of(p.uid) != "" or GameState.worker_job(p.uid) != "" or (Herd.is_stand_in(p.uid) and not GameState.resting_herd().has(Herd.key_of(p.uid))):
			busy[p.uid] = true
	pets.sort_custom(func(a: Pet, b: Pet):
		if busy.has(a.uid) != busy.has(b.uid):
			return not busy.has(a.uid)
		var ra := catalog.rank(a.rarity)
		var rb := catalog.rank(b.rarity)
		if ra != rb:
			return ra > rb if strongest_first else ra < rb
		var pa := int(a.stats.get("power", 0))
		var pb := int(b.stats.get("power", 0))
		return pa > pb if strongest_first else pa < pb)
	return pets


func _quick_pick(tier_id: String) -> void:
	var added := 0
	for pet in _available():
		if added >= QUICK_PICK:
			break
		if _picked.size() >= _max_party():
			break
		if pet.rarity == tier_id and not _picked.has(pet.uid):
			_picked[pet.uid] = true
			added += 1
	_rebuild_picker()


func _toggle(pet: Pet) -> void:
	if _picked.has(pet.uid):
		_picked.erase(pet.uid)
	else:
		if _max_party() == 1:
			_picked.clear()
		if _picked.size() >= _max_party():
			return
		_picked[pet.uid] = true
	_rebuild_picker()


func _trim_to_party_size() -> void:
	if _picked.size() > _max_party():
		_picked.clear()


func _picked_pets() -> Array[Pet]:
	var out: Array[Pet] = []
	for pet in GameState.sendable_pets():
		if _picked.has(pet.uid):
			out.append(pet)
	return out


## For the tutorial: the place on the map, then a pet to pick for the trip, then the send button.
func tutorial_target() -> Control:
	if not _picker.visible:
		return _map.hotspot(_location_id)
	if not _picked.is_empty():
		return _send
	for holder in _grid.get_children():
		return holder
	return null


func _turn(step: int) -> void:
	_page += step
	_rebuild_picker()


## Trips you can watch on the trail: one pet or a small party (big swarms follow their rules).
static func _watchable(run: RunState) -> bool:
	return run.chooser in ["player", "timeout"]


func _send_picked() -> void:
	var run := GameState.send_on_adventure(_location_id, _picked_pets())
	if run != null:
		_picked.clear()
		if run.scouted:
			PetBubble.say_line(self, "trip_scouted", { "trip": run.party.who() })
		else:
			_nudge_more()
		# small parties go along with you on the trail; big swarms get on by themselves
		if _watchable(run):
			_show_trail(run)
		else:
			_show_map(true)
		_rebuild()


## A party just left and others are still at home: now and then your pet says one wants to go too
## (nothing ever tells you more than one party can be out at once, so a pet asks).
func _nudge_more() -> void:
	var now := Time.get_ticks_msec()
	if now < _nudge_at:
		return
	var home := GameState.sendable_pets()
	if home.is_empty():
		return
	_nudge_at = now + NUDGE_EVERY_MS
	PetBubble.say_line(self, "send_more", { "who": home[0].display_name(GameState.catalog) })


# ---- building -----------------------------------------------------------------

func _rebuild_if_dirty() -> void:
	if _dirty and is_visible_in_tree():
		_rebuild()


func _rebuild() -> void:
	_dirty = false
	if not GameState.open_locations().any(func(l): return l.id == _location_id):
		_location_id = GameState.open_locations()[0].id
		_show_map(true)
	_map.refresh()
	_rebuild_picker()
	_rebuild_runs()


func _rebuild_picker() -> void:
	UiTheme.clear(_grid)
	var pets := _available()
	var still := {}  # forget picks of pets that are gone or already sent
	for pet in pets:
		if _picked.has(pet.uid):
			still[pet.uid] = true
	_picked = still
	_quick.visible = _max_party() > Chooser.SMALL_PARTY
	var pages := maxi(1, ceili(pets.size() / float(PAGE_SIZE)))
	_page = clampi(_page, 0, pages - 1)
	_page_label.text = "%d of %d" % [_page + 1, pages]
	_pager.visible = pages > 1
	for pet in pets.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		_grid.add_child(_chip(pet))
	_refresh_send()


func _refresh_send() -> void:
	var catalog := Catalog.shared()
	var d := catalog.location(_location_id)
	_place_title.text = d.name
	_to_shop.visible = _location_id == "shed" and GameState.workshop_shown()
	_place_note.text = str(d.get("map", {}).get("note", ""))
	_place_note.visible = _place_note.text != ""
	var ours := GameState.is_ours(_location_id)
	var lights := Ours.lights(d)
	_lights.visible = lights > 0 and not ours
	_lights.custom_minimum_size = Vector2(lights * (LIGHT + 5.0) + 4.0, LIGHT * 1.25 + 4.0)
	_lights.queue_redraw()
	var pets := _picked_pets()
	var most := _max_party()
	UiTheme.clear(_facts)
	var packed := GameState.trip_gear(_location_id)
	# what they'd pack: your active pet's knacks and their own (walking big swarms is slow, so kept)
	var key := _trip_key(packed)
	if key != _knacks_key:
		_knacks_key = key
		_knacks = GameState.trip_knacks(pets)
	var knacks := _knacks
	var walk := AdventureRunner.walk_of(catalog, packed, knacks)
	_facts.add_child(UiTheme.tag(_about(float(d.minutes) * (1.0 - walk))))
	_facts.add_child(UiTheme.tag("1 pet" if most == 1 else ("as many as you like" if most > 999 else "up to %d pets" % most)))
	for bit in MapView.bits_of(d):
		var brings := UiTheme.chip("bit_" + bit, "brings home %s" % MachineTab.bit_name(bit, 2), MapView.bit_color(bit))
		(brings.find_child("Amount", true, false) as Label).add_theme_font_size_override("font_size", UiTheme.SMALL)
		_facts.add_child(brings)
	# what a trip here works towards (Goals): the carrot, with how far along it is
	for g in Goals.at_place(GameState, _location_id):
		for st in g.steps:
			if st.place == _location_id and float(st.have) < float(st.need):
				var count := "  %d/%d" % [int(st.have), int(st.need)] if float(st.need) > 1.0 else ""
				_facts.add_child(UiTheme.tag("→ %s%s" % [g.name, count], UiTheme.GOLD))
				break
	if d.get("risky", false) and not ours:
		_facts.add_child(UiTheme.tag("risky", UiTheme.PINK))
	if ours:
		var more := UiTheme.chip("coin", "×%s" % str(snappedf(float(catalog.ours.get("loot", 1.0)), 0.01)), UiTheme.CYAN)
		(more.find_child("Amount", true, false) as Label).add_theme_font_size_override("font_size", UiTheme.SMALL)
		_facts.add_child(more)
	if most == 1:
		_picked_label.text = "%d of 1" % pets.size()
	elif most <= Chooser.SMALL_PARTY:
		_picked_label.text = "%d of %d" % [pets.size(), most]
	else:
		_picked_label.text = "%d picked" % pets.size()
	_send.disabled = pets.is_empty()
	_send.tooltip_text = "pick who's going first" if pets.is_empty() else ""
	_send.text = "send %s" % pets[0].display_name(catalog) if pets.size() == 1 else "send them"
	if pets.is_empty():
		_odds.text = ""
		return
	var time := _duration(AdventureRunner.duration(d, Party.make(pets, catalog), walk))
	match Chooser.kind_for(pets.size()):
		"player":
			_odds.text = "about %s there and back. you choose the way!" % time
		"timeout":
			_odds.text = "about %s there and back. they'll ask you along the way." % time
		_:
			# trial runs are slow for big swarms: only redo them when the picks change
			var est_key := key + ":" + str(ours)
			if est_key != _estimate_key:
				_estimate_key = est_key
				_estimate = AdventureRunner.estimate_return(_location_id, pets, catalog, 30, packed, knacks, ours)
			_odds.text = "about %s there and back. about %d%% come home." % [time, roundi(_estimate * 100.0)]


## What the trip preview depends on, without working any knacks out: the place, the picks, the
## packed gear, your active pet, the boosts on trip kinds and the knack version.
func _trip_key(packed: Dictionary) -> String:
	var boosts: Array[String] = []
	for kind: String in Boosts.trip_kinds(GameState.catalog):
		boosts.append(str(GameState.boost(kind)))
	return "%s:%s:%s:%s:%s:%d" % [_location_id, ",".join(_picked.keys()), str(packed), GameState.collection.active_uid,
		",".join(boosts), GameState.knack_version]


const LIGHT := 14.0  # a window on the place card


## The house's windows on the place card: lit ones first, the dark ones after (one per visit).
func _draw_lights() -> void:
	var d := Catalog.shared().location(_location_id)
	var on := GameState.lights_left(_location_id)
	for i in Ours.lights(d):
		StreetPage.window(_lights, Vector2(2.0 + i * (LIGHT + 5.0), 2.0 + LIGHT * 0.25), LIGHT, i < on)


func _rebuild_runs() -> void:
	UiTheme.clear(_runs)
	_run_rows.clear()
	var catalog := Catalog.shared()
	for run in GameState.runs:
		var d := catalog.location(run.location_id)
		var border := UiTheme.LILAC_SEAM
		match run.status:
			RunState.Status.WAITING: border = UiTheme.GOLD
			RunState.Status.DONE: border = UiTheme.MINT
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", UiTheme.sticker(border, 12, UiTheme.RAISED, 11))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		panel.add_child(col)

		# who and where, and "watch" for a hands-on trip
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 8)
		var first: Pet = GameState.collection.get_pet(run.party.uids[0]) if not run.party.uids.is_empty() else null
		if first:
			var face := PetPortrait.new(2, false)
			face.set_pet(first)
			face.mouse_filter = MOUSE_FILTER_IGNORE
			top.add_child(face)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = SIZE_EXPAND_FILL
		names.add_child(UiTheme.label(d.name, UiTheme.PINK, UiTheme.SMALL + 1))
		var who := run.party.who() if run.party.setting_out() == 1 else "%d pets" % run.party.setting_out()
		names.add_child(UiTheme.label(who, UiTheme.MUTED, UiTheme.SMALL))
		top.add_child(names)
		if run.scouted:  # it took the scouts' note along
			var note := UiTheme.icon_rect("job_scout", 16, UiTheme.LILAC)
			note.size_flags_vertical = SIZE_SHRINK_CENTER
			note.mouse_filter = MOUSE_FILTER_IGNORE
			top.add_child(note)
		if _watchable(run) and run.status != RunState.Status.DONE:
			var watch := UiTheme.small_button("watch ›", _show_trail.bind(run))
			watch.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
			top.add_child(watch)
		col.add_child(top)

		# a single pet's trip reads like a little story, told by your active pet: how it's feeling,
		# what came up and what it spotted (never any numbers), the choices, then what happened
		var speaker := GameState.collection.active()
		var solo := run.party.setting_out() == 1 and speaker != null
		if solo and run.status != RunState.Status.DONE:
			col.add_child(_wrapped(PetVoice.feeling(speaker, run.party, run.history, catalog), UiTheme.TEXT))
		match run.status:
			RunState.Status.WAITING:
				var event := run.current_event(catalog)
				var options := AdventureRunner.options_of(event, d)
				var allowed := AdventureRunner.allowed_options(event, run.party, d)
				col.add_child(_wrapped(event.title, UiTheme.GOLD))
				var scene := str(event.text)
				if solo:
					scene += " " + PetVoice.spotted(speaker, event, run.party, d, catalog, Rewards.depth_boost(run.history.size()),
						Gear.value(catalog, run.gear, "luck"))
				col.add_child(_wrapped(scene, UiTheme.TEXT))
				for i in allowed:
					var option: Dictionary = options[i]
					var b := UiTheme.button(option.label, GameState.answer_event.bind(run, i))
					b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
					col.add_child(b)
				if run.chooser == "timeout":
					var countdown := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
					countdown.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					col.add_child(countdown)
					_run_rows.append({ "run": run, "countdown": countdown, "default": options[Chooser.default_option(event, allowed)].label })
			RunState.Status.DONE:
				col.add_child(_wrapped(AdventureRunner.summary(run), UiTheme.TEXT))
				var back := UiTheme.button("welcome back", _collect.bind(run))
				back.name = "welcome_" + run.location_id  # for test flows (click name:welcome_<place>)
				back.icon = UiTheme.icon("heart", 14)
				back.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				back.add_theme_constant_override("icon_max_width", 14)
				back.add_theme_color_override("icon_normal_color", Color.WHITE)
				back.add_theme_color_override("icon_hover_color", Color.WHITE)
				col.add_child(back)
			_:
				var bar := UiTheme.bar(UiTheme.LILAC)
				bar.max_value = 1.0
				bar.step = 0.0
				col.add_child(bar)
				var when := HBoxContainer.new()
				var where := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
				when.add_child(where)
				when.add_child(UiTheme.spacer())
				var time := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL)
				when.add_child(time)
				col.add_child(when)
				_run_rows.append({ "run": run, "bar": bar, "time": time, "where": where })
		# what happened so far, newest on top
		for i in range(run.history.size() - 1, -1, -1):
			col.add_child(_wrapped(str(run.history[i].text), UiTheme.MUTED))
		_runs.add_child(panel)
	if GameState.runs.is_empty():
		_runs.add_child(UiTheme.label("nobody's away", UiTheme.MUTED, UiTheme.SMALL))
	_refresh_runs()


## Moves the walking runs' bars and timers along.
func _refresh_runs() -> void:
	var now := Time.get_unix_time_from_system()
	var catalog := Catalog.shared()
	for row in _run_rows:
		var run: RunState = row.run
		if row.has("countdown"):
			row.countdown.text = "if nobody picks, it's %s in %s" % [row.default, _duration(TimeoutChooser.deadline(run) - now)]
			continue
		var gap := AdventureRunner.run_gap(run, catalog)
		var within := clampf(1.0 - (run.next_at - now) / gap, 0.0, 1.0)
		row.bar.value = (run.step + within) / (run.events.size() + 1.0)
		var heading_home := run.step >= run.events.size()
		row.where.text = "heading home" if heading_home else "on the way"
		row.time.text = ("back in %s" if heading_home else "next in %s") % _duration(run.next_at - now)


func _collect(run: RunState) -> void:
	var trip := GameState.collect_run(run)
	if trip.is_empty():
		return
	if _trail.visible and _trail.run == run:
		_show_map(true)
	_show_postcard(trip)


## A trip's postcard over the map (welcomed back by you, or by the bell rope and waiting).
func _show_postcard(trip: Dictionary) -> void:
	_picker.visible = false
	_shop_stuck.visible = false
	_postcard.show_trip(trip)
	_postcard.visible = true
	_rebuild()
	# a trip the bell rope welcomed back: your pet talks about this one (its news waited with it)
	if trip.has("news"):
		GameState.news = trip.news
		var told: Array = trip.get("announce", [])
		for i in range(told.size() - 1, -1, -1):
			GameState.announcements.push_front(str(told[i]))
	speak()


## A trip's postcard is up: unlock popups wait until it's closed.
func busy() -> bool:
	return _postcard.is_visible_in_tree()


## The letterbox on the map was tapped: the oldest postcard waiting in it.
func _open_letterbox() -> void:
	var trip := GameState.take_postcard()
	if not trip.is_empty():
		_show_postcard(trip)


func _wrapped(text: String, color: Color) -> Label:
	var l := UiTheme.label(text, color, UiTheme.SMALL + 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(210, 0)
	return l


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_rebuild_if_dirty()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.5
		_refresh_runs()
		_refresh_bar()
		_refresh_edge_card()
		_drop_stale_trail()
		if _shop_stuck.visible and not GameState.workshop_shown():
			_show_map(true)  # the last drawing is built: the shed is just the shed again
		# trips the bell rope welcomed back: their postcards, one at a time, when you're not busy on a
		# card (with the letterbox built they wait in it for you)
		if _main.visible and not _postcard.visible and not _trail.visible and not _picker.visible and not _shop_stuck.visible \
				and not GameState.postcards.is_empty() and not GameState.built("letter"):
			_show_postcard(GameState.take_postcard())


static func _about(minutes: float) -> String:
	var hours := snappedf(minutes / 60.0, 0.5)
	if minutes < 60.0:
		return "about %d min" % roundi(minutes)
	return "about %d h" % hours if hours == floorf(hours) else "about %.1f h" % hours


static func _duration(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
