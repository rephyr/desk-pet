class_name SewingRoom
extends PanelContainer
## The sewing room, through the little pink door on the well's floor 20 (the dungeon page's column
## slides over to it, DungeonView): the tunnel in, ‹ the room's name ›, a dot per room shown (the
## ones cleared and the next one, no more), the room as an arched chamber with its line drawing and
## a chalkboard lock (ChalkMark: dashed until a front-row pet matches, then filled in), and at the
## foot a feeling word (or a coral pennant once it's cleared) and "in we go!". Rules in Sewing,
## state in GameState: this only shows them and passes on clicks.
## Design: lanes/mockups2 design/mockups/screens/well-additions.html (the sewing room, look A).

signal room_changed  # ‹ › showed another room: the page rebuilds (the front row's ticks follow it)

const MAX_DOTS := 9
const PIC := Vector2(176, 87)

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
const TUNNEL := '<path d="M0 16 L150 16 Q170 16 176 22"/><path d="M0 6 L148 6 Q182 6 190 22"/><path d="M3 16 L3 7 A5 5 0 0 1 13 7 L13 16 Z" fill="{pinkfill}" stroke="{pink}" stroke-dasharray="none"/><circle cx="10.4" cy="12" r="1.3" fill="{wisp}" stroke="none"/>'

var room := 0  # the room shown (0 = the first)
var _col := VBoxContainer.new()
var _pics := {}  # pic id -> texture


func _init() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UiTheme.DEEP.lerp(UiTheme.PAPER, 0.6)
	add_theme_stylebox_override("panel", sb)
	clip_contents = true
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_col.add_theme_constant_override("separation", 0)
	_col.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_col)
	add_child(scroll)


## Shows the next room to clear (when the door is opened).
func to_next() -> void:
	room = int(GameState.sewing.cleared)


## Builds the pane again for the army lined up now (`a`, `rules` from GameState.army() / army_rules()).
func refresh(a: Dictionary, rules: Dictionary) -> void:
	UiTheme.clear(_col)
	if not GameState.sewing_open():
		return
	var shown := Sewing.shown(GameState.sewing)
	room = clampi(room, 0, shown - 1)
	var r := GameState.sew_room(room)
	var cleared := room < int(GameState.sewing.cleared)
	var running := GameState.dungeon_running() and int(GameState.dungeon.run.get("room", -1)) == room  # this room's run, not the well's

	# the tunnel in from the door
	var tunnel := TextureRect.new()
	tunnel.texture = _svg('<svg xmlns="http://www.w3.org/2000/svg" width="220" height="22" viewBox="0 0 220 22" fill="none" stroke="%s" stroke-width="1.6" stroke-dasharray="3 3">%s</svg>' % [
		_hex(UiTheme.LILAC_SEAM), TUNNEL.replace("{pinkfill}", _hex(UiTheme.RAISED.lerp(UiTheme.PINK, 0.22))).replace("{pink}", _hex(UiTheme.PINK)).replace("{wisp}", _hex(UiTheme.WISP))], 220, 22)
	tunnel.stretch_mode = TextureRect.STRETCH_KEEP
	tunnel.custom_minimum_size = Vector2(0, 22)
	var tm := MarginContainer.new()
	tm.add_theme_constant_override("margin_top", 8)
	tm.add_theme_constant_override("margin_left", 2)
	tm.add_child(tunnel)
	tm.mouse_filter = MOUSE_FILTER_IGNORE
	tunnel.mouse_filter = MOUSE_FILTER_IGNORE
	_col.add_child(tm)

	# ‹ the room's name ›
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	var tmar := MarginContainer.new()
	for side in [["left", 8], ["right", 8], ["top", 4]]:
		tmar.add_theme_constant_override("margin_" + side[0], side[1])
	tmar.add_child(top)
	top.add_child(_arrow("‹", room > 0, func(): _go(-1)))
	var name_label := UiTheme.title(str(r.name), 15, UiTheme.PINK)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top.add_child(name_label)
	top.add_child(_arrow("›", room < shown - 1, func(): _go(1)))
	_col.add_child(tmar)
	_col.add_child(_dots(shown))

	# the chamber: the room's drawing and its chalkboard
	var chamber := Chamber.new()
	var ccol := VBoxContainer.new()
	ccol.add_theme_constant_override("separation", 8)
	chamber.add_child(ccol)
	var pic := TextureRect.new()
	pic.texture = _pic(str(r.pic))
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pic.custom_minimum_size = PIC
	pic.mouse_filter = MOUSE_FILTER_IGNORE
	ccol.add_child(pic)
	var board := PanelContainer.new()
	var bsb := UiTheme.box(UiTheme.DEEP.lerp(UiTheme.MINT, 0.07), UiTheme.LINE.lerp(ChalkMark.chalk(), 0.3), 10, 2, 0)
	bsb.content_margin_left = 8
	bsb.content_margin_right = 8
	bsb.content_margin_top = 7
	bsb.content_margin_bottom = 6
	board.add_theme_stylebox_override("panel", bsb)
	var marks := HFlowContainer.new()
	marks.alignment = FlowContainer.ALIGNMENT_CENTER
	marks.add_theme_constant_override("h_separation", 8)
	marks.add_theme_constant_override("v_separation", 4)
	var on := Sewing.marks_on(r, GameState.sew_front())
	for k in r.marks.size():
		var m := ChalkMark.new(str(r.marks[k]), bool(on[k]))
		var mark_id := str(r.marks[k])
		m.pressed.connect(func():
			if not m.on:
				PetBubble.say(self, GameState.sew_hint(mark_id)))
		marks.add_child(m)
	board.add_child(marks)
	ccol.add_child(board)
	var cm := MarginContainer.new()
	for side in [["left", 10], ["right", 10], ["top", 10]]:
		cm.add_theme_constant_override("margin_" + side[0], side[1])
	cm.add_child(chamber)
	_col.add_child(cm)

	# a feeling word (or the coral pennant once cleared) and in we go!
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	var fm := MarginContainer.new()
	for side in [["left", 12], ["right", 12], ["top", 14], ["bottom", 10]]:
		fm.add_theme_constant_override("margin_" + side[0], side[1])
	fm.add_child(foot)
	if cleared:
		foot.add_child(_pennant())
	else:
		var word := GameState.sew_word(room) if int(a.get("sent", 0)) > 0 else []
		if not word.is_empty():
			foot.add_child(_feel(word))
	foot.add_child(UiTheme.spacer())
	var go := UiTheme.button("on the way…" if running else "in we go!", func():
		if GameState.send_to_room(room):
			PetBubble.say_line(self, "sewing_go"))
	go.disabled = not GameState.sew_can_go(room)
	var go_sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6)
	go_sb.content_margin_left = 12
	go_sb.content_margin_right = 12
	go.add_theme_stylebox_override("normal", go_sb)
	go.add_theme_stylebox_override("disabled", go_sb)
	go.add_theme_color_override("font_disabled_color", UiTheme.PINK if running else Color(UiTheme.MUTED, 0.8))
	foot.add_child(go)
	_col.add_child(fm)


func _go(d: int) -> void:
	room = clampi(room + d, 0, Sewing.shown(GameState.sewing) - 1)
	room_changed.emit()


func _arrow(text: String, can: bool, on_press: Callable) -> Button:
	var b := UiTheme.small_button(text, on_press)
	b.custom_minimum_size = Vector2(24, 24)
	b.disabled = not can
	b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.PINK)
	b.add_theme_color_override("font_disabled_color", Color(UiTheme.MUTED, 0.3))
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 0)
	for state in ["normal", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 0))
	var off := UiTheme.box(Color(UiTheme.DEEP, 0.3), Color(UiTheme.LINE, 0.3), 8, 2, 0)
	b.add_theme_stylebox_override("disabled", off)
	return b


## A dot per room shown (at most MAX_DOTS, around the one shown): pink for this one, coral rings for
## cleared ones, lilac for the next.
func _dots(shown: int) -> Control:
	var first := clampi(room - MAX_DOTS / 2, 0, maxi(0, shown - MAX_DOTS))
	var n := mini(shown, MAX_DOTS)
	var dots := Dots.new(first, n, room, int(GameState.sewing.cleared))
	return dots


func _pennant() -> Control:
	var t := TextureRect.new()
	t.texture = _svg('<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14" fill="none" stroke-linecap="round"><path d="M3 13 L3 1.5" stroke="%s" stroke-width="2"/><path d="M3.5 2 L12 4.6 L3.5 7.4 Z" fill="%s" stroke="%s" stroke-width="1" stroke-linejoin="round"/></svg>' % [
		_hex(UiTheme.WISP), _hex(UiTheme.WISP), _hex(UiTheme.WISP)], 14, 14)
	t.custom_minimum_size = Vector2(14, 14)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.size_flags_vertical = SIZE_SHRINK_CENTER
	return t


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
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	p.add_theme_stylebox_override("panel", sb)
	p.size_flags_vertical = SIZE_SHRINK_CENTER
	p.add_child(UiTheme.label(str(word[0]), color, UiTheme.SMALL))
	return p


func _pic(id: String) -> Texture2D:
	if _pics.has(id):
		return _pics[id]
	var body := str(PICS.get(id, PICS.tin)).replace("{P}", ' stroke="%s"' % _hex(UiTheme.PINK)).replace("{C}", ' stroke="%s"' % _hex(UiTheme.WISP)) \
		.replace("{F}", ' fill="%s" fill-opacity="0.18"' % _hex(UiTheme.LILAC))
	var tex := _svg('<svg xmlns="http://www.w3.org/2000/svg" width="150" height="74" viewBox="0 0 150 74" fill="none" stroke="%s" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">%s</svg>' % [
		_hex(UiTheme.LILAC), body], int(PIC.x), int(PIC.y))
	_pics[id] = tex
	return tex


## An SVG drawn at `w` x `h` (at 2x, shown at 1x: crisp on scaled screens).
static func _svg(svg: String, w: int, _h: int) -> Texture2D:
	var img := Image.new()
	var vb := svg.get_slice('width="', 1).get_slice('"', 0).to_float()
	img.load_svg_from_string(svg, 2.0 * w / maxf(vb, 1.0))
	img.resize(int(img.get_width() / 2.0), int(img.get_height() / 2.0), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


static func _hex(c: Color) -> String:
	return "#" + c.to_html(false)


## The room's chamber: an arched doorway of dashed stitches (round on top), deep inside.
class Chamber extends MarginContainer:
	func _init() -> void:
		for side in [["left", 10], ["right", 10], ["top", 18], ["bottom", 14]]:
			add_theme_constant_override("margin_" + side[0], side[1])

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var r := minf(w / 2.0, 70.0)
		var pts := PackedVector2Array([Vector2(0, h - 12)])
		for i in 9:  # the round top: a quarter each side, flat between
			var a := PI + PI / 2.0 * i / 8.0
			pts.append(Vector2(r, r) + Vector2(cos(a), sin(a)) * r)
		for i in 9:
			var a := PI * 1.5 + PI / 2.0 * i / 8.0
			pts.append(Vector2(w - r, r) + Vector2(cos(a), sin(a)) * r)
		for i in 5:  # rounded bottom corners
			var a := PI / 2.0 * i / 4.0
			pts.append(Vector2(w - 12, h - 12) + Vector2(cos(a), sin(a)) * 12.0)
		for i in 4:
			var a := PI / 2.0 + PI / 2.0 * i / 4.0
			pts.append(Vector2(12, h - 12) + Vector2(cos(a), sin(a)) * 12.0)
		draw_colored_polygon(pts, UiTheme.DEEP)
		pts.append(pts[0])
		_dashed(pts, UiTheme.LILAC_SEAM, 2.0)

	func _dashed(points: PackedVector2Array, color: Color, width: float) -> void:
		var on := true
		var left := 4.0
		for i in points.size() - 1:
			var a: Vector2 = points[i]
			var b: Vector2 = points[i + 1]
			var d := a.distance_to(b)
			var s := 0.0
			while s < d:
				var step := minf(left, d - s)
				if on:
					draw_line(a.lerp(b, s / d), a.lerp(b, (s + step) / d), color, width)
				s += step
				left -= step
				if left <= 0.001:
					on = not on
					left = 4.0


## The dots under the room's name.
class Dots extends Control:
	var _first := 0
	var _n := 0
	var _at := 0
	var _cleared := 0

	func _init(first: int, n: int, at: int, cleared: int) -> void:
		_first = first
		_n = n
		_at = at
		_cleared = cleared
		custom_minimum_size = Vector2(0, 15)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var gap := 12.0
		var x0 := size.x / 2.0 - (_n - 1) * gap / 2.0
		for k in _n:
			var i := _first + k
			var c := Vector2(x0 + k * gap, 10.0)
			if i == _at:
				draw_circle(c, 4.5, UiTheme.PINK)
			else:
				draw_arc(c, 3.5, 0, TAU, 16, UiTheme.WISP if i < _cleared else UiTheme.LILAC_SEAM, 2.0, true)
