class_name SewingPage
extends VBoxContainer
## The sewing room (E3, redone in P4, look A: the seats): its own page in the adventures tab's
## dungeon area, through the little pink door on the well's floor 20 (DungeonView.door_opened);
## "‹ the old well" goes back, the wisps chip sits top right.
## A strip of the rooms you know as picture tiles: cleared ones with a coral pennant, the next one
## to clear on a pink stitched patch, the one after it as a dashed carrot (nothing past that). The
## picked room's card: its name, "→ the next room", a feeling word, its drawing in an arched
## chamber, and "who's going in": a seat per chalk mark. Tap a seat, then a pet that fits in the
## picker on the right (fitting pets light up, the others dim; "where from? ›" has your pet say
## where they come from); a pet sits on every empty seat it fits. The army lined up on the well page
## walks in behind them ("and 2,860 more"), then "in we go!". During the run the chamber has a
## clock and tiny pets walking through; then the result (wisps, who came home, again / next room ›).
## Rules in Sewing, seats and runs in GameState (sew_*): this only shows them and passes on clicks.
## Design: design/mockups/screens/sewing-redo.html (look A).

signal back  # ‹ the old well

const PICK_COLS := 4
const PICK_ROWS := 3
const SCENE_H := 118
const PIC := Vector2(196, 97)

## Each room's line drawing (150 x 74): lilac lines, {P} pink ones, {C} coral ones, {F} a lilac tint.
const PICS := {
	"tin": '<ellipse{F} cx="75" cy="30" rx="44" ry="11"/><path d="M31 30 L31 56 Q75 72 119 56 L119 30"/><path d="M31 42 Q75 56 119 42"/><circle{P} cx="60" cy="27" r="6"/><circle{P} cx="57.6" cy="25.6" r=".6"/><circle{P} cx="62.4" cy="28.4" r=".6"/><circle{C} cx="84" cy="31" r="5"/><circle cx="96" cy="26" r="4"/><circle cx="72" cy="22" r="3.4"/><circle{C} cx="18" cy="62" r="5"/><circle{P} cx="134" cy="64" r="4"/>',
	"cushion": '<path{F} d="M34 60 Q24 34 52 26 Q75 20 98 26 Q126 34 116 60 Q75 72 34 60 Z"/><path d="M75 22 Q70 44 75 68 M52 26 Q48 46 55 64 M98 26 Q102 46 95 64"/><path d="M62 24 L56 6 M86 24 L94 8 M76 22 L77 4"/><circle{P} cx="56" cy="5" r="3"/><circle{C} cx="94" cy="7" r="3"/><circle{P} cx="77" cy="3" r="3"/><path{P} d="M128 62 L140 44"/><path d="M14 64 Q22 56 30 64"/>',
	"maze": '<path d="M10 60 Q30 20 52 50 Q66 70 80 36 Q92 10 110 40 Q124 62 140 26"/><path{P} d="M16 30 Q40 64 64 30 Q86 4 98 50 Q106 70 134 58"/><path{C} d="M26 12 Q52 36 44 58 M120 10 Q100 30 124 50"/><rect{F} x="66" y="40" width="18" height="20" rx="3"/><path d="M64 40 L86 40 M64 60 L86 60"/>',
	"ribbons": '<rect{F} x="30" y="32" width="90" height="36" rx="4"/><path d="M30 46 L120 46"/><circle{C} cx="75" cy="57" r="3"/><path d="M44 32 Q42 18 32 13 Q23 10 20 18"/><path{P} d="M62 32 Q68 13 85 10 Q99 9 101 20 Q102 28 93 27"/><path d="M102 32 Q113 23 124 26 Q135 30 131 41"/><path{P} d="M20 18 Q14 26 22 31"/><path{C} d="M126 62 Q134 57 139 63 Q134 69 126 65 Z M126 62 Q118 56 113 63 Q119 69 126 65"/>',
	"thimbles": '<path{F} d="M58 70 L60 50 Q75 44 90 50 L92 70 Z"/><path d="M62 50 L64 32 Q75 27 86 32 L88 50"/><path d="M66 32 L68 16 Q75 11 82 16 L84 32"/><circle cx="70" cy="61" r="1.2"/><circle cx="78" cy="58" r="1.2"/><circle cx="85" cy="62" r="1.2"/><circle cx="72" cy="41" r="1.2"/><circle cx="80" cy="43" r="1.2"/><circle cx="75" cy="23" r="1.2"/><path{P} d="M26 70 L29 58 Q36 55 43 58 L46 70 Z"/><path{C} d="M112 70 L126 50"/><circle{C} cx="127" cy="48" r="2.4"/>',
	"patterns": '<path{F} d="M18 20 Q46 12 75 22 L75 68 Q46 58 18 66 Z"/><path d="M132 20 Q104 12 75 22 L75 68 Q104 58 132 66 Z"/><path{P} d="M28 30 Q40 24 54 32 Q62 38 58 48 Q52 56 36 52" stroke-dasharray="3 3"/><path{C} d="M92 28 L120 28 L120 50 L92 50 Z" stroke-dasharray="3 3"/><path d="M98 62 L110 44 M104 62 L94 46"/>',
	"needles": '<rect{F} x="36" y="38" width="78" height="30" rx="6"/><path d="M36 50 L114 50"/><path d="M50 38 L44 10 M62 38 L60 8 M76 38 L80 8 M90 38 L98 12"/><circle cx="44" cy="12" r="1.6"/><circle cx="98" cy="14" r="1.6"/><path{P} d="M60 8 Q40 2 30 18 Q22 32 34 38"/><path{C} d="M98 14 Q118 6 128 22 Q136 36 120 46"/>',
	"scissors": '<circle{F} cx="34" cy="55" r="11"/><circle{F} cx="34" cy="21" r="11"/><path d="M44 26 L134 52"/><path d="M44 50 L134 24"/><circle{C} cx="89" cy="38" r="2.6"/><path{P} d="M12 72 Q40 64 64 71 Q88 77 114 69"/>',
	"basket": '<path{F} d="M28 36 L122 36 L112 70 L38 70 Z"/><path d="M32 48 Q75 53 118 48 M35 59 Q75 64 115 59"/><path d="M52 38 L53 46 M75 40 L75 49 M98 38 L97 46 M58 51 L59 57 M88 51 L87 57 M64 62 L65 68 M84 62 L83 68" opacity=".7"/><path d="M40 36 Q75 6 110 36"/><circle{P} cx="60" cy="26" r="10"/><path{P} d="M52 22 Q60 28 68 20 M51 29 Q60 34 69 28"/><path{C} d="M88 32 L110 8"/><circle{C} cx="111" cy="6" r="2"/>',
}

var room := 0  # the room picked
var _sel := ""  # the seat tapped (its mark)
var _page := 0  # the pet picker's page
var _dirty := true
var _maybe := false  # pets came or went: rebuild if something the page shows changed (_key)
var _check := 0.0
var _last_key := ""
var _filled := ""  # the seat just filled (its chalk pops)
var _wisps: Label
var _strip := RoomStrip.new()
var _strip_scroll := ScrollContainer.new()
var _body := HBoxContainer.new()
var _pics := {}  # "id|w" -> texture
var _scroll_frames := 0  # frames left to keep the picked tile in view
var _scrolled_for := ""  # the picked room and the strip's size the strip last scrolled for
static var _flags := {}  # px -> the coral pennant


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	# ‹ the old well, the sewing room, the wisps
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.custom_minimum_size = Vector2(0, 32)  # (its things sit low: a two-line bubble above stays clear)
	var b := UiTheme.small_button("‹ the old well", func(): back.emit())
	b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.size_flags_vertical = SIZE_SHRINK_END
	bar.add_child(b)
	var t := UiTheme.title("the sewing room", 20, UiTheme.PINK)
	t.size_flags_vertical = SIZE_SHRINK_END
	bar.add_child(t)
	bar.add_child(UiTheme.spacer())
	var chip := PanelContainer.new()
	var chip_sb := UiTheme.box(UiTheme.DEEP, UiTheme.WISP.lerp(UiTheme.LINE, 0.6), 999, 2, 0)
	chip_sb.content_margin_left = 8
	chip_sb.content_margin_right = 14
	chip_sb.content_margin_top = 2
	chip_sb.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", chip_sb)
	chip.size_flags_vertical = SIZE_SHRINK_END
	chip.tooltip_text = str(Catalog.shared().dungeon.get("currency", {}).get("word", "wisps"))
	var chip_row := HBoxContainer.new()
	chip_row.add_theme_constant_override("separation", 7)
	chip_row.add_child(UiTheme.icon_rect("lantern", 20, UiTheme.WISP))
	_wisps = UiTheme.title("0", 18, UiTheme.WISP)
	chip_row.add_child(_wisps)
	chip.add_child(chip_row)
	bar.add_child(chip)
	add_child(bar)
	# the strip of rooms
	var strip := PanelContainer.new()
	var ssb := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0)
	ssb.content_margin_left = 6
	ssb.content_margin_right = 6
	ssb.content_margin_top = 4
	ssb.content_margin_bottom = 4
	strip.add_theme_stylebox_override("panel", ssb)
	_strip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_strip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_strip_scroll.custom_minimum_size = Vector2(0, RoomStrip.H)
	_strip_scroll.add_child(_strip)
	strip.add_child(_strip_scroll)
	_strip.picked.connect(pick_room)
	add_child(strip)
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_body)
	GameState.dungeon_changed.connect(func():
		_dirty = true
		if is_visible_in_tree() and not GameState.dungeon_news.is_empty():
			speak())
	GameState.collection.pets_added.connect(func(_p): _maybe = true)
	GameState.collection.pets_removed.connect(func(_u): _maybe = true)
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.jobs_changed.connect(func(): _maybe = true)
	GameState.adventures_changed.connect(func(): _maybe = true)
	visibility_changed.connect(func():
		GameState.army_held = is_visible_in_tree()  # your pet leading the army waits at home while this shows
		if is_visible_in_tree():
			_dirty = true)
	tree_exiting.connect(func(): GameState.army_held = false)


## The door was opened: the room running, else the one just done, else the next one to clear.
func open() -> void:
	var run: Dictionary = GameState.dungeon.run
	if GameState.dungeon_running() and run.has("room"):
		room = int(run.room)
	elif not GameState.sew_last.is_empty():
		room = int(GameState.sew_last.room)
	else:
		room = int(GameState.sewing.cleared)
	room = clampi(room, 0, Sewing.shown(GameState.sewing) - 1)
	GameState.sew_pick_room(room)
	_sel = _first_open()
	_page = 0
	_dirty = true


## Picks a room on the strip (one that shows, not while a room's run is on). The seats start empty.
func pick_room(i: int) -> void:
	if i < 0 or i >= Sewing.shown(GameState.sewing) or _room_running():
		return
	if i != room:
		GameState.sew_last = {}
	room = i
	GameState.sew_pick_room(i)
	_sel = _first_open()
	_page = 0
	_dirty = true


## Taps a seat (its mark): the picker shows who fits.
func pick_seat(mark: String) -> void:
	if _room_running() or not _result().is_empty():
		return
	_sel = mark
	_page = 0
	_dirty = true


## Taps a pet in the picker: it sits on the tapped seat if it fits (and on every empty seat it fits).
func pick_pet(pet: Pet) -> bool:
	if _sel == "" or not GameState.sew_seat(room, _sel, pet.uid):
		return false
	_filled = _sel
	if pet.uid == GameState.collection.active_uid:
		PetBubble.say_line(self, "sewing_me")
	_sel = _first_open()
	_page = 0
	_dirty = true
	return true


## The seats changed from elsewhere (dev steps): the next empty seat is the tapped one.
func refresh_seats() -> void:
	_sel = _first_open()
	_page = 0
	_dirty = true


## Your pet says something about the sewing room: news first, then how a run's doing.
func speak() -> void:
	var news := GameState.take_announcement()
	if news != "":
		PetBubble.say(self, news)
		return
	var n := GameState.take_dungeon_news()
	if n.has("room"):
		var key := "sewing_stuck" if not n.cleared else ("sewing_again" if n.again else "sewing_home")
		PetBubble.say_line(self, key, { "got": UiTheme.num(int(n.got)), "room": str(n.room) })
	elif not n.is_empty() and not bool(n.get("nail", false)):
		var key := "dungeon_deepest" if n.deepest else ("dungeon_home_early" if n.early else "dungeon_home")
		PetBubble.say_line(self, key, { "got": UiTheme.num(int(n.got)), "floor": int(n.floor) })
	elif _room_running():
		PetBubble.say_line(self, "sewing_running", { "room": str(GameState.sew_room(room).name) })
	else:
		PetBubble.say_line(self, "sewing")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if not GameState.sewing_open():
		return
	if _dirty:
		_rebuild()
	if _scroll_frames > 0:
		_scroll_frames -= 1
		_show_tile()
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_wisps.text = UiTheme.num(GameState.wisps)
		if _maybe and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):  # never under a click
			_maybe = false
			if _key() != _last_key:
				_rebuild()


func _room_running() -> bool:
	return GameState.dungeon_running() and GameState.dungeon.run.has("room")


## The result to show for the room picked ({} for none).
func _result() -> Dictionary:
	var last: Dictionary = GameState.sew_last
	return last if not GameState.dungeon_running() and int(last.get("room", -1)) == room else {}


func _first_open() -> String:
	var r := GameState.sew_room(room)
	var on := GameState.sew_marks(room)
	for k in r.marks.size():
		if not bool(on[k]):
			return str(r.marks[k])
	return ""


## What pets coming and going can change here: the picker's pets, the army walking in.
func _key() -> String:
	return "%d|%d|%d|%d" % [GameState.collection.pets.size(), GameState.runs.size(), int(GameState.sew_party(room).sent), GameState.sew_seated(room).size()]


func _rebuild() -> void:
	_dirty = false
	_last_key = _key()
	_wisps.text = UiTheme.num(GameState.wisps)
	var shown := Sewing.shown(GameState.sewing)
	if _room_running():
		room = int(GameState.dungeon.run.room)
	room = clampi(room, 0, shown - 1)
	GameState.sew_pick_room(room)
	var r := GameState.sew_room(room)
	if _sel != "" and (not _sel in r.marks or bool(GameState.sew_marks(room)[r.marks.find(_sel)])):
		_sel = _first_open()
	_build_strip(shown)
	UiTheme.clear(_body)
	_body.add_child(_room_card(r))
	_body.add_child(_picker(r))
	_filled = ""


# ---- the strip of rooms ------------------------------------------------------------------

func _build_strip(shown: int) -> void:
	var cleared := int(GameState.sewing.cleared)
	var tiles: Array = []
	for i in shown + 1:  # the rooms you know and the next one, as a carrot
		var r := GameState.sew_room(i)
		var state := "done" if i < cleared else ("cur" if i == cleared else "next")
		tiles.append({ "i": i, "state": state, "name": str(r.name), "pic": _pic(str(r.pic), 36) })
	_strip.set_tiles(tiles, room, _room_running())
	var at := "%d|%d" % [room, tiles.size()]
	if at != _scrolled_for:  # (only when the picked room or the rooms change: a scroll by hand stays)
		_scrolled_for = at
		_scroll_frames = 3  # (once the strip is laid out)


## Keeps the picked tile (and the carrot after it) in view.
func _show_tile() -> void:
	var w := _strip_scroll.size.x
	if w <= 0.0:
		return
	var right := RoomStrip.x_of(mini(room + 2, _strip.count())) + RoomStrip.PAD
	_strip_scroll.scroll_horizontal = int(maxf(0.0, right - w))


# ---- the room's card ------------------------------------------------------------------

func _room_card(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var cleared := int(GameState.sewing.cleared)
	var running := _room_running()
	var result := _result()
	var cur := room == cleared

	# the room's name, → the next one, a feeling word
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.title(str(r.name), 18, UiTheme.PINK))
	if cur and result.is_empty():
		head.add_child(_carrot("→ " + str(GameState.sew_room(room + 1).name)))
	elif room < cleared and result.is_empty():
		head.add_child(_pennant(13))
	head.add_child(UiTheme.spacer())
	var word := GameState.sew_word(room)
	if not word.is_empty():
		head.add_child(_feel(word))
	col.add_child(head)

	# the chamber: the room's drawing (and the run going through it)
	var scene := Scene.new(_pic(str(r.pic), int(PIC.x)), running)
	if running:
		var faces: Array[Texture2D] = []
		for pet in GameState.army_cards().slice(0, 4):
			faces.append(PetLook.texture_for(pet.parts, false, pet.sewn))
		for uid in GameState.herd_faces(GameState.dungeon.run.get("herd", {}), 2, 5):
			var p := GameState.collection.get_pet(str(uid))
			if p:
				faces.append(PetLook.texture_for(p.parts, false, p.sewn))
		scene.faces = faces
	col.add_child(scene)

	if not result.is_empty():
		col.add_child(_result_board(result))
		return card

	# who's going in: a seat per mark
	col.add_child(_h3("who's going in"))
	var board := PanelContainer.new()
	board.add_theme_stylebox_override("panel", _board_box(10))
	var seats := HBoxContainer.new()
	seats.add_theme_constant_override("separation", 8)
	var pets := GameState.sew_seat_pets(room)
	var seen := {}
	for k in r.marks.size():
		var mark := str(r.marks[k])
		var pet: Pet = pets.get(mark)
		var again: bool = pet != null and seen.has(pet.uid)  # the same pet on another seat: faded there
		if pet != null:
			seen[pet.uid] = true
		var seat := Seat.new(mark, pet, again, _sel == mark and not running, not running, mark == _filled)
		seat.name = "SewSeat%d" % (k + 1)
		seat.pressed.connect(func(): pick_seat(mark))
		seat.off.connect(func():
			GameState.sew_unseat(room, mark)
			_sel = mark
			_dirty = true)
		seats.add_child(seat)
	board.add_child(seats)
	col.add_child(board)

	# the army walking in behind, and in we go!
	var push := Control.new()
	push.size_flags_vertical = SIZE_EXPAND_FILL
	push.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(push)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	var party := GameState.sew_party(room)
	var more := int(party.more)
	if more > 0:
		var seated := GameState.sew_seated(room)
		var faces: Array = party.cards.filter(func(p): return not seated.has(p)).slice(0, 8).map(func(p): return p.uid)
		faces.append_array(GameState.herd_faces(party.keys, 16, 3))
		var mound := Mound.new(faces, Herd.mound_size(GameState.catalog, more, 12), 56.0, 32.0)
		mound.size_flags_vertical = SIZE_SHRINK_CENTER
		foot.add_child(mound)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.size_flags_vertical = SIZE_SHRINK_CENTER
		line.add_child(UiTheme.label("and", UiTheme.MUTED, UiTheme.SMALL + 1))
		line.add_child(UiTheme.title(UiTheme.full_num(more), 15, UiTheme.TEXT))
		line.add_child(UiTheme.label("more", UiTheme.MUTED, UiTheme.SMALL + 1))
		foot.add_child(line)
	foot.add_child(UiTheme.spacer())
	var go := UiTheme.button("on the way…" if running else "in we go!", func():
		if GameState.send_to_room(room):
			_sel = ""
			PetBubble.say_line(self, "sewing_go"))
	go.disabled = not GameState.sew_can_go(room)
	go.size_flags_vertical = SIZE_SHRINK_CENTER
	var on_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 0)
	var off_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if running else UiTheme.MUTED_SEAM, 8, 2, 0)
	var hover_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK, 8, 2, 0)
	for s in [on_sb, off_sb, hover_sb]:
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 7
		s.content_margin_bottom = 7
	go.add_theme_stylebox_override("normal", on_sb)
	go.add_theme_stylebox_override("hover", hover_sb)
	go.add_theme_stylebox_override("pressed", hover_sb)
	go.add_theme_stylebox_override("disabled", off_sb)
	go.add_theme_color_override("font_disabled_color", UiTheme.PINK if running else Color(UiTheme.MUTED, 0.8))
	foot.add_child(go)
	col.add_child(foot)
	return card


## Back from the room: a pennant, the wisps, who came home; again, or on to the next room.
func _result_board(res: Dictionary) -> Control:
	var board := PanelContainer.new()
	var sb := _board_box(14)
	board.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	board.add_child(col)
	if bool(res.get("cleared", false)):
		var flag := _pennant(30)
		flag.size_flags_horizontal = SIZE_SHRINK_CENTER
		col.add_child(flag)
	var got := HBoxContainer.new()
	got.add_theme_constant_override("separation", 6)
	got.alignment = BoxContainer.ALIGNMENT_CENTER
	got.add_child(UiTheme.icon_rect("lantern", 22, UiTheme.WISP))
	got.add_child(UiTheme.title("+" + UiTheme.num(int(res.get("got", 0))), 20, UiTheme.WISP))
	col.add_child(got)
	var home := HBoxContainer.new()
	home.add_theme_constant_override("separation", 0)
	home.alignment = BoxContainer.ALIGNMENT_CENTER
	home.add_child(UiTheme.label(UiTheme.full_num(int(res.get("back", 0))), UiTheme.TEXT, UiTheme.SMALL + 1))
	home.add_child(UiTheme.label(" of %s came home" % UiTheme.full_num(int(res.get("sent", 0))), UiTheme.MUTED, UiTheme.SMALL + 1))
	col.add_child(home)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_child(UiTheme.button("again", func():
		GameState.sew_last = {}
		_sel = _first_open()
		_dirty = true))
	var next_i := int(res.room) + 1
	if bool(res.get("first", false)) and next_i < Sewing.shown(GameState.sewing):
		var nb := UiTheme.button("%s ›" % str(GameState.sew_room(next_i).name), func(): pick_room(next_i))
		nb.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6))
		btns.add_child(nb)
	col.add_child(btns)
	return board


# ---- the pet picker ------------------------------------------------------------------

func _picker(r: Dictionary) -> Control:
	var card := PanelContainer.new()
	var sb := UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 12
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(318, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)
	var running := _room_running()
	var picking := _sel != "" and not running and _result().is_empty()
	var going := {}
	if running:
		for uid in GameState.dungeon.run.get("cards", []):
			going[str(uid)] = true
	else:
		for pet in GameState.sew_seated(room):
			going[pet.uid] = true

	# the pets, the ones that fit the seat first
	var pets := GameState.sew_pickable()
	if running:
		var gone: Array[Pet] = GameState.army_cards()
		gone.append_array(pets)
		pets = gone
	var fit := {}
	if picking:
		# the ones that fit the seat first: the ones that would fill the most empty seats, then the strongest
		var open: Array = []
		var on := GameState.sew_marks(room)
		for k in r.marks.size():
			if not bool(on[k]) and str(r.marks[k]) != _sel:
				open.append(str(r.marks[k]))
		var yes: Array[Pet] = []
		var no: Array[Pet] = []
		var by_fills := {}
		for pet in pets:
			if Sewing.mark_matches(_sel, pet):
				fit[pet.uid] = true
				var n := open.filter(func(m): return Sewing.mark_matches(m, pet)).size()
				if not by_fills.has(n):
					by_fills[n] = []
				by_fills[n].append(pet)
			else:
				no.append(pet)
		for n in range(open.size(), -1, -1):
			for pet in by_fills.get(n, []):
				yes.append(pet)
		var both: Array[Pet] = []
		both.append_array(yes)
		both.append_array(no)
		pets = both
	var per := PICK_COLS * PICK_ROWS
	var pages := maxi(1, ceili(pets.size() / float(per)))
	_page = clampi(_page, 0, pages - 1)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.custom_minimum_size = Vector2(0, 26)
	if picking:
		var chalk := TextureRect.new()
		chalk.texture = ChalkMark.texture(_sel, false, _chalk_color(_sel), 22)
		chalk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chalk.custom_minimum_size = Vector2(22, 22)
		chalk.size_flags_vertical = SIZE_SHRINK_CENTER
		head.add_child(chalk)
		var h := _h3(Sewing.ones(GameState.catalog, _sel))
		h.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.clip_text = true
		h.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(h)
	else:
		var h := _h3("pets")
		h.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(h)
	if pages > 1:
		var pager := HBoxContainer.new()
		pager.add_theme_constant_override("separation", 2)
		pager.add_child(_page_button("‹", _page > 0, -1))
		var at := UiTheme.label("%d of %d" % [_page + 1, pages], UiTheme.MUTED, UiTheme.SMALL)
		at.size_flags_vertical = SIZE_SHRINK_CENTER
		pager.add_child(at)
		pager.add_child(_page_button("›", _page < pages - 1, 1))
		head.add_child(pager)
	col.add_child(head)

	var grid := GridContainer.new()
	grid.columns = PICK_COLS
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 12)
	var keeper := str(GameState.plushie.keeper) if GameState.plushie_open() else ""
	var page_pets := pets.slice(_page * per, (_page + 1) * per)
	for k in page_pets.size():
		var pet: Pet = page_pets[k]
		var look := ""
		if picking:
			look = "fit" if fit.has(pet.uid) else "dim"
		elif running and not going.has(pet.uid):
			look = "dim"
		var pick := Pick.new(pet, look, going.has(pet.uid), pet.uid == GameState.collection.active_uid, pet.uid == keeper)
		pick.name = "SewPick%d" % (k + 1)
		pick.pressed.connect(func(): pick_pet(pet))
		grid.add_child(pick)
	col.add_child(grid)

	# where the tapped seat's pets come from (your pet says it)
	var foot := VBoxContainer.new()
	foot.size_flags_vertical = SIZE_EXPAND_FILL
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 6)
	if picking:
		foot.add_child(UiTheme.stitch_line())
		var row := HBoxContainer.new()
		var from := UiTheme.button("where from? ›", func(): PetBubble.say(self, GameState.sew_hint(_sel)))
		from.add_theme_font_size_override("font_size", UiTheme.SMALL)
		var fsb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 999, 2, 0)
		fsb.content_margin_left = 9
		fsb.content_margin_right = 9
		fsb.content_margin_top = 1
		fsb.content_margin_bottom = 1
		var fsb_h := fsb.duplicate()
		fsb_h.border_color = UiTheme.PINK_SEAM
		from.add_theme_stylebox_override("normal", fsb)
		from.add_theme_stylebox_override("hover", fsb_h)
		from.add_theme_stylebox_override("pressed", fsb_h)
		from.add_theme_color_override("font_hover_color", UiTheme.PINK)
		row.add_child(from)
		foot.add_child(row)
	col.add_child(foot)
	return card


func _page_button(text: String, can: bool, d: int) -> Button:
	var b := UiTheme.small_button(text, func():
		_page += d
		_dirty = true)
	b.disabled = not can
	b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	b.add_theme_color_override("font_disabled_color", Color(UiTheme.MUTED, 0.3))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 3
		e.content_margin_right = 3
		b.add_theme_stylebox_override(state, e)
	return b


# ---- bits ------------------------------------------------------------------------

func _h3(text: String) -> Label:
	return UiTheme.title(text, 14, UiTheme.LILAC)


func _board_box(margin: int) -> StyleBoxFlat:
	return UiTheme.box(UiTheme.DEEP.lerp(UiTheme.MINT, 0.07), UiTheme.LINE.lerp(ChalkMark.chalk(), 0.3), 12, 2, margin)


static func _chalk_color(mark: String) -> Color:
	return GameState.catalog.tier_color(mark.get_slice(":", 1)) if mark.begins_with("tier:") else ChalkMark.chalk()


## "→ the pin cushion": the room after this one, a dashed lilac pill.
func _carrot(text: String) -> Control:
	var p := PanelContainer.new()
	var sb := UiTheme.stitched(UiTheme.LILAC_SEAM, Color(0, 0, 0, 0), 9, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	sb.dash = 4.0
	sb.gap = 3.0
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(text, UiTheme.LILAC, UiTheme.SMALL))
	return p


## The feeling word for the room, as a little pill (like the orders card's).
func _feel(word: Array) -> Control:
	var p := PanelContainer.new()
	var color := UiTheme.MUTED
	var border := UiTheme.LINE
	match str(word[1]):
		"mid":
			color = UiTheme.TEXT
			border = UiTheme.LILAC.lerp(UiTheme.LINE, 0.65)
		"hot":
			color = UiTheme.PINK
			border = UiTheme.PINK_SEAM
	var sb := UiTheme.box(UiTheme.DEEP, border, 999, 2, 0)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(str(word[0]), color, UiTheme.SMALL))
	return p


func _pennant(px: int) -> Control:
	var t := TextureRect.new()
	t.texture = pennant(px)
	t.custom_minimum_size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	t.mouse_filter = MOUSE_FILTER_IGNORE
	return t


## A coral pennant: a cleared room.
static func pennant(px: int) -> Texture2D:
	var key := "%d|%s" % [px, UiTheme.WISP.to_html()]  # (another look has another coral)
	if _flags.has(key):
		return _flags[key]
	var hex := "#" + UiTheme.WISP.to_html(false)
	_flags[key] = _svg('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke-linecap="round"><path d="M3 13 L3 1.5" stroke="%s" stroke-width="2"/><path d="M3.5 2 L12 4.6 L3.5 7.4 Z" fill="%s" stroke="%s" stroke-width="1" stroke-linejoin="round"/></svg>' % [hex, hex, hex], px)
	return _flags[key]


## A room's drawing `w` px wide (its lines thicker when small, so they still read).
func _pic(id: String, w: int) -> Texture2D:
	var key := "%s|%d" % [id, w]
	if _pics.has(key):
		return _pics[key]
	var body := str(PICS.get(id, PICS.tin)).replace("{P}", ' stroke="#%s"' % UiTheme.PINK.to_html(false)).replace("{C}", ' stroke="#%s"' % UiTheme.WISP.to_html(false)) \
		.replace("{F}", ' fill="#%s" fill-opacity="0.18"' % UiTheme.LILAC.to_html(false))
	var tex := _svg('<svg xmlns="http://www.w3.org/2000/svg" width="150" height="74" viewBox="0 0 150 74" fill="none" stroke="#%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [
		UiTheme.LILAC.to_html(false), "4" if w < 80 else "2", body], w)
	_pics[key] = tex
	return tex


## An SVG drawn `w` px wide (at 2x: crisp on scaled screens; draw it at its half size).
static func _svg(svg: String, w: int) -> Texture2D:
	var img := Image.new()
	var vb := svg.get_slice('width="', 1).get_slice('"', 0).to_float()
	img.load_svg_from_string(svg, 2.0 * w / maxf(vb, 1.0))
	return ImageTexture.create_from_image(img)


## The strip of rooms: a picture tile per room you know, the next one as a dashed carrot. Drawn in
## one go; a tap picks a room (not the carrot).
class RoomStrip extends Control:
	signal picked(i: int)

	const TILE := Vector2(46, 42)
	const GAP := 5.0
	const PAD := 4.0
	const H := 52.0

	var _tiles: Array = []  # { i, state: done | cur | next, name, pic }
	var _view := 0
	var _locked := false
	var _hover := -1

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		custom_minimum_size = Vector2(0, H)

	func set_tiles(tiles: Array, view: int, locked: bool) -> void:
		_tiles = tiles
		_view = view
		_locked = locked
		custom_minimum_size = Vector2(x_of(tiles.size()) + PAD, H)
		tooltip_text = " "
		queue_redraw()

	func count() -> int:
		return _tiles.size()

	static func x_of(k: int) -> float:
		return PAD + k * (TILE.x + GAP) - (GAP if k > 0 else 0.0)

	func _rect(k: int) -> Rect2:
		return Rect2(Vector2(PAD + k * (TILE.x + GAP), (H - TILE.y) / 2.0), TILE)

	func _at(pos: Vector2) -> int:
		for k in _tiles.size():
			if _rect(k).grow(2).has_point(pos):
				return k
		return -1

	func _get_tooltip(at: Vector2) -> String:
		var k := _at(at)
		return str(_tiles[k].name) if k >= 0 else ""

	func _draw() -> void:
		for k in _tiles.size():
			var t: Dictionary = _tiles[k]
			var r := _rect(k)
			var clickable: bool = t.state != "next" and not _locked
			if k == _hover and clickable and t.state != "cur":
				r.position.y -= 2.0
			var center := r.get_center()
			if t.state == "cur":  # the next to clear: a pink stitched patch, a little crooked
				draw_set_transform(center, deg_to_rad(-3.0), Vector2.ONE)
				r.position -= center
			if t.i == _view and t.state != "cur":
				var ring := StyleBoxFlat.new()
				ring.draw_center = false
				ring.border_color = UiTheme.PINK_SEAM
				ring.set_border_width_all(2)
				ring.set_corner_radius_all(12)
				ring.anti_aliasing = true
				draw_style_box(ring, r.grow(4))
			match str(t.state):
				"done":
					draw_style_box(UiTheme.box(UiTheme.DEEP, UiTheme.WISP.lerp(UiTheme.LINE, 0.6), 9, 2, 0), r)
				"cur":
					var sb := UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 9, 0)
					sb.dash = 5.0
					sb.gap = 3.0
					draw_style_box(sb, r)
				_:
					var sb := UiTheme.stitched(UiTheme.LILAC_SEAM, Color(0, 0, 0, 0), 9, 0)
					sb.dash = 5.0
					sb.gap = 3.0
					draw_style_box(sb, r)
			var pic: Texture2D = t.pic
			var ps := pic.get_size() / 2.0
			draw_texture_rect(pic, Rect2(r.get_center() - ps / 2.0, ps), false, Color(1, 1, 1, 0.35 if t.state == "next" else 1.0))
			if t.state == "done":
				var flag := SewingPage.pennant(13)
				draw_texture_rect(flag, Rect2(Vector2(r.end.x - 10.0, r.position.y - 5.0), Vector2(13, 13)), false)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion:
			var k := _at(event.position)
			if k != _hover:
				_hover = k
				mouse_default_cursor_shape = CURSOR_POINTING_HAND if k >= 0 and _tiles[k].state != "next" and not _locked else CURSOR_ARROW
				queue_redraw()
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var k := _at(event.position)
			if k >= 0 and _tiles[k].state != "next" and not _locked:
				picked.emit(int(_tiles[k].i))
				accept_event()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and _hover >= 0:
			_hover = -1
			queue_redraw()


## The room's chamber: an arched doorway of dashed stitches with the room's drawing; during a run a
## clock in the corner and tiny pets walking through.
class Scene extends Control:
	var faces: Array[Texture2D] = []
	var _pic: Texture2D
	var _running := false

	func _init(pic: Texture2D, running: bool) -> void:
		_pic = pic
		_running = running
		custom_minimum_size = Vector2(0, SewingPage.SCENE_H)
		mouse_filter = MOUSE_FILTER_IGNORE
		texture_filter = TEXTURE_FILTER_LINEAR

	func _process(_delta: float) -> void:
		if _running and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := minf(60.0, minf(w, h) / 2.0)
		var pts := PackedVector2Array()
		for i in 9:  # round top corners, small bottom ones
			var a := PI + PI / 2.0 * i / 8.0
			pts.append(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
		for i in 9:
			var a := PI * 1.5 + PI / 2.0 * i / 8.0
			pts.append(Vector2(w - r, r) + Vector2(cos(a), sin(a)) * r)
		for i in 5:
			var a := PI / 2.0 * i / 4.0
			pts.append(Vector2(w - 12, h - 12) + Vector2(cos(a), sin(a)) * 12.0)
		for i in 5:
			var a := PI / 2.0 + PI / 2.0 * i / 4.0
			pts.append(Vector2(12, h - 12) + Vector2(cos(a), sin(a)) * 12.0)
		draw_colored_polygon(pts, UiTheme.DEEP)
		pts.append(pts[0])
		_dashed(pts, UiTheme.LILAC_SEAM, 2.0)
		var ps := _pic.get_size() / 2.0
		draw_texture_rect(_pic, Rect2(Vector2(w, h) / 2.0 - ps / 2.0, ps), false)
		if not _running:
			return
		var run: Dictionary = GameState.dungeon.run
		var total := maxf(1.0, float(run.get("seconds", 60.0)))
		var left := GameState.dungeon_left()
		var f := clampf(1.0 - left / total, 0.0, 1.0)
		# the clock
		var font := UiTheme.DISPLAY_FONT if UiTheme.DISPLAY_FONT else get_theme_default_font()
		var secs := ceili(left)
		var clock := "%d:%02d" % [secs / 60, secs % 60]
		var cw := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, Vector2(w - 20.0 - cw, 38.0), clock, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiTheme.TEXT)
		# tiny pets tiptoeing through
		if faces.is_empty():
			return
		var step := 11.0
		var mw := step * (faces.size() - 1) + 16.0
		var x0 := 14.0 + f * (w - 28.0 - mw)
		var t := Time.get_ticks_msec() / 1000.0
		for k in faces.size():
			var hop := absf(sin(t * TAU + k * 1.7)) * 3.0
			draw_texture_rect(faces[k], Rect2(Vector2(x0 + k * step, h - 8.0 - 18.0 - hop).round(), Vector2(16, 18)), false)

	func _dashed(points: PackedVector2Array, color: Color, width: float) -> void:
		var on := true
		var left := 5.0
		for i in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var d := a.distance_to(b)
			var s := 0.0
			while d - s > 0.001:
				var step := minf(left, d - s)
				if on:
					draw_line(a.lerp(b, s / d), a.lerp(b, (s + step) / d), color, width, true)
				s += step
				left -= step
				if left <= 0.001:
					on = not on
					left = 5.0 if on else 3.5


## A seat: the mark's chalk drawing, its word, and the pet sitting on it (or a dashed place). Tap it
## to pick who sits there; ✕ takes the pet off.
class Seat extends Button:
	signal off

	const SLOT := Vector2(46, 52)

	var _mark := ""
	var _pet: Pet
	var _again := false
	var _selected := false
	var _pet_tex: Texture2D

	func _init(mark: String, pet: Pet, again: bool, selected: bool, editable: bool, filled_now: bool) -> void:
		_mark = mark
		_pet = pet
		_again = again
		_selected = selected
		focus_mode = FOCUS_NONE
		size_flags_horizontal = SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(56, 126)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if editable else CURSOR_ARROW
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "pressed", "focus", "disabled", "hover"]:
			add_theme_stylebox_override(state, empty)
		disabled = not editable
		var on := pet != null
		var col := VBoxContainer.new()
		col.set_anchors_preset(PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 4)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(col)
		var chalk := TextureRect.new()
		chalk.texture = ChalkMark.texture(mark, on, SewingPage._chalk_color(mark), 34)
		chalk.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		chalk.custom_minimum_size = Vector2(34, 34)
		chalk.size_flags_horizontal = SIZE_SHRINK_CENTER
		chalk.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(chalk)
		if filled_now:  # just filled in: the chalk pops
			chalk.pivot_offset = Vector2(17, 17)
			chalk.scale = Vector2(0.4, 0.4)
			chalk.ready.connect(func():
				chalk.create_tween().tween_property(chalk, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
		var word := UiTheme.label(Sewing.one(GameState.catalog, mark), UiTheme.TEXT if on else ChalkMark.chalk(), UiTheme.SMALL)
		word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		word.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		word.clip_text = true
		word.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(word)
		var slot := Control.new()
		slot.custom_minimum_size = SLOT
		slot.size_flags_horizontal = SIZE_SHRINK_CENTER
		slot.mouse_filter = MOUSE_FILTER_IGNORE
		slot.draw.connect(_draw_slot.bind(slot))
		slot.texture_filter = TEXTURE_FILTER_NEAREST
		col.add_child(slot)
		if pet != null:
			_pet_tex = PetLook.texture_for(pet.parts, false, pet.sewn)
			tooltip_text = pet.display_name(GameState.catalog)
			if editable:
				var x := Button.new()
				x.name = "SewOff"
				x.text = "✕"
				x.focus_mode = FOCUS_NONE
				x.tooltip_text = "take off"
				x.add_theme_font_size_override("font_size", UiTheme.SMALL)
				x.add_theme_color_override("font_color", UiTheme.MUTED)
				x.add_theme_color_override("font_hover_color", UiTheme.PINK)
				var xs := StyleBoxEmpty.new()
				var xh := UiTheme.box(UiTheme.DEEP, Color(0, 0, 0, 0), 6, 0, 0)
				x.add_theme_stylebox_override("normal", xs)
				x.add_theme_stylebox_override("pressed", xh)
				x.add_theme_stylebox_override("hover", xh)
				x.add_theme_stylebox_override("focus", xs)
				x.set_anchors_preset(PRESET_TOP_RIGHT)
				x.offset_left = -20
				x.offset_right = -2
				x.offset_top = 2
				x.offset_bottom = 20
				x.pressed.connect(func(): off.emit())
				add_child(x)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _selected:
			draw_style_box(UiTheme.box(Color(UiTheme.PINK, 0.08), Color(0, 0, 0, 0), 10, 0, 0), r)
			var sb := UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 10, 0)
			sb.dash = 5.0
			sb.gap = 3.0
			draw_style_box(sb, r)
		elif is_hovered() and not disabled:
			draw_style_box(UiTheme.box(Color(ChalkMark.chalk(), 0.08), Color(0, 0, 0, 0), 10, 0, 0), r)

	func _draw_slot(slot: Control) -> void:
		var r := Rect2(Vector2.ZERO, slot.size)
		if _pet == null:
			var sb := UiTheme.stitched(Color(ChalkMark.chalk(), 0.45), Color(0, 0, 0, 0), 9, 0)
			sb.dash = 4.0
			sb.gap = 3.0
			slot.draw_style_box(sb, r)
			return
		var color := GameState.catalog.tier_color(_pet.rarity).lerp(UiTheme.DEEP, 0.2)
		var sb := UiTheme.box(UiTheme.RAISED, color, 9, 2, 0)
		sb.shadow_color = UiTheme.SHADOW
		sb.shadow_size = 4
		sb.shadow_offset = Vector2(0, 3)
		slot.draw_style_box(sb, r)
		slot.draw_texture_rect(_pet_tex, Rect2(Vector2((r.size.x - 32.0) / 2.0, r.size.y - 36.0 - 3.0).round(), Vector2(32, 36)), false, Color(1, 1, 1, 0.55 if _again else 1.0))

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER or what == NOTIFICATION_MOUSE_EXIT:
			queue_redraw()


## A pet in the picker: its picture on a sticker outlined in its rarity, your pet's heart or the
## keeper's spool, its buttons and finish. Lit up with a chalk tick when it fits the tapped seat,
## dimmed when it doesn't; a pink stitch round the ones going in.
class Pick extends Button:
	const SIZE := Vector2(64, 74)

	var _pet: Pet
	var _look := ""  # "", "fit" or "dim"
	var _in := false
	var _me := false
	var _keeper := false
	var _tex: Texture2D
	var _fin: Texture2D

	func _init(pet: Pet, look: String, going: bool, me: bool, keeper: bool) -> void:
		_pet = pet
		_look = look
		_in = going
		_me = me
		_keeper = keeper
		focus_mode = FOCUS_NONE
		custom_minimum_size = SIZE
		size_flags_horizontal = SIZE_EXPAND_FILL
		texture_filter = TEXTURE_FILTER_NEAREST
		tooltip_text = pet.display_name(GameState.catalog)
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if look == "fit" else CURSOR_ARROW
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "pressed", "focus", "disabled", "hover"]:
			add_theme_stylebox_override(state, empty)
		if look == "dim":
			modulate = Color(1, 1, 1, 0.3)
		_tex = PetLook.texture_for(pet.parts, false, pet.sewn)
		if pet.finish != "normal":
			_fin = ChalkMark.texture("finish:" + pet.finish, false, UiTheme.LILAC, 13)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if _look == "fit":
			r.position.y -= 3.0
		var tier := GameState.catalog.tier_color(_pet.rarity)
		if _in:
			var ring := UiTheme.stitched(UiTheme.PINK, Color(0, 0, 0, 0), 12, 0)
			ring.dash = 5.0
			ring.gap = 3.0
			draw_style_box(ring, r.grow(3))
		var sb := UiTheme.box(UiTheme.RAISED, tier if _look == "fit" else tier.lerp(UiTheme.DEEP, 0.2), 10, 2, 0)
		sb.shadow_color = UiTheme.SHADOW
		sb.shadow_size = 7 if _look == "fit" else 4
		sb.shadow_offset = Vector2(0, 5 if _look == "fit" else 3)
		draw_style_box(sb, r)
		draw_texture_rect(_tex, Rect2(r.position + Vector2((r.size.x - 48.0) / 2.0, r.size.y - 54.0 - 7.0).round(), Vector2(48, 54)), false)
		if _me:
			draw_texture_rect(UiTheme.icon("heart", 14, UiTheme.PINK), Rect2(r.position + Vector2(4, 3), Vector2(14, 14)), false)
		elif _keeper:
			draw_texture_rect(UiTheme.drawing(SpoolArt.ART, 14, UiTheme.WISP, 4.8), Rect2(r.position + Vector2(4, 3), Vector2(14, 14)), false)
		var n := Plushie.total(_pet)
		for k in mini(n, 5):
			draw_circle(r.position + Vector2(r.size.x - 7.0 - k * 7.0, 7.0), 3.0, UiTheme.WISP)
		if _fin:
			draw_texture_rect(_fin, Rect2(r.position + Vector2(4, r.size.y - 18.0), Vector2(13, 13)), false)
		if _look == "fit":  # a chalk tick on the corner
			var chalk := ChalkMark.chalk()
			var t := r.position + Vector2(r.size.x - 2.0, 2.0)
			draw_circle(t, 8.0, UiTheme.DEEP)
			draw_arc(t, 8.0, 0, TAU, 20, chalk, 2.0, true)
			draw_polyline(PackedVector2Array([t + Vector2(-3.4, 0.4), t + Vector2(-1.0, 2.8), t + Vector2(3.2, -2.4)]), chalk, 2.0, true)


## The keeper's spool, on a 48 sheet (for UiTheme.drawing).
class SpoolArt:
	const ART := '<path d="M10 8 L38 8 M10 40 L38 40"/><path d="M15 8 L15 40 M33 8 L33 40" opacity=".6"/><path d="M15 18 L33 24 M15 28 L33 34"/>'
