class_name HouseDrawing
extends Control
## The cut-away house on the house card (HouseCard): one house that grows a step at a time (the
## room steps in data/herd.json). Built steps are drawn solid with tiny pets in them (your real
## pets' looks), the next step in pencil (dashed, no pets; coral for a squeeze-in step), and a step
## that was just built gets sparkles while its pets hop in. Each endless step tucks one more tiny
## pet somewhere in the house. Drawn from the mockup's coordinates (260 x 220, 1:1): the lines are
## an SVG made in code and turned into a picture (twice the size, so they stay smooth), the tiny
## pets are pasted in pixel-sharp. The SVG is turned into a picture in as few pieces as it can: only
## a pet that a later shape covers (`under`: blankets, hammocks, the drawer front, the teapot, the
## rug) splits it; every other pet is pasted in one go just before the roof seam.
## Design: design/mockups/screens/room-house.html (look A, the dollhouse).

const SIZE := Vector2(260, 220)
const SCALE := 2  # the picture is made at twice the size
const HOP := 0.7  # seconds for a new step's pets to hop in
## Where the endless steps tuck their tiny pet (top-left of a 16 x 18 pet, flipped), in order.
## A step in data/herd.json that has no drawing of its own takes these spots from the end.
const TUCKS := [[70, 46, false], [78, 139, true], [4, 188, false], [214, 71, true], [122, 53, false],
	[164, 146, false], [188, 24, false], [28, 139, false], [240, 188, true], [42, 63, false],
	[158, 110, true], [60, 79, false], [122, 10, false]]

var _level := 0  # steps built
var _ghost := -1  # the step drawn in pencil (-1: none)
var _fresh := -1  # the step that was just built (its pets hop in)
var _looks: Array[Image] = []
var _tex: Texture2D  # everything, pets and all
var _tex_before: Texture2D  # everything but the fresh step's pets (they hop in on top)
var _hoppers: Array = []  # the fresh step's pets: [position, texture]
var _t := 0.0

# while building the SVG
var _ops: Array = []  # ["svg", text] or ["pet", Vector2, flipped, look index, step index, under]
var _mode := ""  # "on" or "ghost"
var _pencil := Color.WHITE
var _step_i := -1
var _pet_n := 0
var _odd_n := 0  # listed steps with no drawing of their own so far


func _init() -> void:
	custom_minimum_size = SIZE
	mouse_filter = MOUSE_FILTER_IGNORE
	texture_filter = TEXTURE_FILTER_LINEAR
	set_process(false)


## Shows the house with `level` steps built, `ghost` in pencil (-1: nothing next) and `fresh` just
## built (-1: none). `faces`: pet uids for the tiny pets' looks (cycled).
func show_house(level: int, ghost: int, fresh: int, faces: Array) -> void:
	_level = level
	_ghost = ghost
	_fresh = fresh
	_looks.clear()
	for uid in faces:
		var pet := GameState.collection.get_pet(str(uid))
		if pet:
			_looks.append(PetLook.texture_for(pet.parts, false, pet.sewn).get_image())
	_build()
	_t = 0.0
	set_process(_fresh >= 0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if _t > HOP + 0.6:
		_fresh = -1
		set_process(false)
	queue_redraw()


func _draw() -> void:
	if _fresh >= 0 and _tex_before:
		draw_texture_rect(_tex_before, Rect2(Vector2.ZERO, SIZE), false)
		# the new step's pets hop in, one after another
		for i in _hoppers.size():
			var h: Array = _hoppers[i]
			var k := clampf((_t - i * 0.08) / HOP, 0.0, 1.0)
			if k <= 0.0:
				continue
			var up := (1.0 - k) * 14.0 + sin(k * PI) * 4.0
			draw_texture_rect(h[1], Rect2(h[0] - Vector2(0, floorf(up)), Vector2(16, 18)), false, Color(1, 1, 1, minf(1.0, k * 1.6)))
		# sparkles rise and fade
		for j in 3:
			var s := clampf((_t - j * 0.15) / 1.1, 0.0, 1.0)
			if s <= 0.0 or s >= 1.0:
				continue
			var at: Vector2 = [Vector2(70, 120), Vector2(140, 96), Vector2(196, 140)][j] + Vector2(0, 6.0 - 16.0 * s)
			MachineTab.MachineStage.draw_sparkle(self, at, 6.0, Color(UiTheme.GOLD, sin(s * PI)))
	elif _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, SIZE), false)


# ---- building the picture ----------------------------------------------------

func _build() -> void:
	_ops.clear()
	_pet_n = 0
	_odd_n = 0
	var c := _colors()
	_raw('<path d="M24 204 L24 100 L130 32 L236 100 L236 204 Z" fill="%s"/>' % c.wall)
	_mode = "on"
	_step_i = -1
	_line("M50 200 L50 86 M76 200 L76 70 M102 200 L102 52 M158 200 L158 52 M184 200 L184 70 M210 200 L210 86", c.stripe, 2.0)
	_line("M52 138 L72 138 L72 154 L52 154 Z", c.lilac_seam, 2.0)
	_raw('<path d="M62 151 Q55.5 146.5 57.2 143 Q59.4 140.6 62 143.4 Q64.6 140.6 66.8 143 Q68.5 146.5 62 151 Z" fill="%s"/>' % c.pink)
	_line("M188 64 L188 42 L204 42 L204 74")
	_line("M4 206 Q70 202 130 205 T256 205", c.mint, 2.5)
	_line("M8 205 L10 199 L12 205 M244 205 L247 198 L250 205 M16 205 L17 201", c.mint, 2.0)
	_line("M24 204 L24 100 M236 100 L236 204")
	_line("M24 204 L236 204", c.lilac_seam, 3.0)
	_part("base", c)
	var listed: int = GameState.catalog.herd.get("room", {}).get("steps", []).size()
	for i in maxi(_level, _ghost + 1):
		var mode := "on" if i < _level else ("ghost" if i == _ghost else "")
		if mode == "":
			continue
		var s := Herd.room_step(GameState.catalog, i)
		_mode = mode
		_step_i = i
		_pencil = UiTheme.WISP if s.has("wisps") else UiTheme.MUTED
		if i < listed:
			_part(str(s.id), c)
		else:
			_tuck(i - listed, c)
	_mode = "on"
	_step_i = -1
	_ops.append(["top"])  # the pets nothing else covers go in here, under the roof seam
	_line("M12 106 L130 28 L248 106", c.pink_seam, 3.2)
	_bake()
	_hoppers.clear()
	if _fresh >= 0 and not _looks.is_empty():
		for op in _ops:
			if op[0] == "pet" and op[4] == _fresh:
				_hoppers.append([op[1], ImageTexture.create_from_image(_pet_image(op[3], op[2], SCALE))])


## Turns _ops into the picture (_tex) and, when a step was just built, the picture without its pets
## (_tex_before), in one go: each piece of SVG is made once and pasted into both.
func _bake() -> void:
	var full := Image.create_empty(int(SIZE.x) * SCALE, int(SIZE.y) * SCALE, false, Image.FORMAT_RGBA8)
	var before: Image = Image.create_empty(full.get_width(), full.get_height(), false, Image.FORMAT_RGBA8) if _fresh >= 0 else null
	var blank := true
	var chunk := ""
	var on_top: Array = []  # pets only the roof seam covers: pasted just before it
	for op in _ops + [["end"]]:
		if op[0] == "svg":
			chunk += op[1]
			continue
		if op[0] == "pet" and not op[5]:
			on_top.append(op)
			continue
		if chunk != "":
			var img := Image.new()
			img.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">%s</svg>' % [SIZE.x, SIZE.y, SIZE.x, SIZE.y, chunk], SCALE)
			img.convert(Image.FORMAT_RGBA8)
			if blank:  # the first piece is the picture so far
				full = img
				if before:
					before = img.duplicate()
				blank = false
			else:  # later pieces are small: paste only where they drew
				var r := img.get_used_rect()
				if r.has_area():
					full.blend_rect(img, r, r.position)
					if before:
						before.blend_rect(img, r, r.position)
			chunk = ""
		if op[0] == "pet":
			_paste(op, full, before)
		elif op[0] == "top":
			for pet in on_top:
				_paste(pet, full, before)
	_tex = ImageTexture.create_from_image(full)
	_tex_before = ImageTexture.create_from_image(before) if before else null


## Pastes a tiny pet into the picture (and into the one without the fresh step's pets, unless it's one).
func _paste(op: Array, full: Image, before: Image) -> void:
	if _looks.is_empty():
		return
	var p := _pet_image(op[3], op[2], SCALE)
	var r := Rect2i(Vector2i.ZERO, p.get_size())
	full.blend_rect(p, r, Vector2i(op[1] * SCALE))
	if before and op[4] != _fresh:
		before.blend_rect(p, r, Vector2i(op[1] * SCALE))


func _pet_image(look: int, flipped: bool, scale: int) -> Image:
	var img: Image = _looks[look % _looks.size()].duplicate()
	img.convert(Image.FORMAT_RGBA8)
	if scale != 1:
		img.resize(img.get_width() * scale, img.get_height() * scale, Image.INTERPOLATE_NEAREST)
	if flipped:
		img.flip_x()
	return img


func _colors() -> Dictionary:
	var lilac := UiTheme.LILAC
	return {
		"wall": _hex(UiTheme.PAPER.lerp(lilac, 0.07)), "stripe": _hex(UiTheme.PAPER.lerp(lilac, 0.09)),
		"lilac": _hex(lilac), "lilac_seam": _hex(UiTheme.LILAC_SEAM), "pink": _hex(UiTheme.PINK),
		"pink_seam": _hex(UiTheme.PINK_SEAM), "mint": _hex(UiTheme.MINT), "gold": _hex(UiTheme.GOLD),
		"bed": _hex(UiTheme.PINK_PRESSED), "blanket": _hex(UiTheme.PAGE.lerp(lilac, 0.4)),
		"wood": _hex(UiTheme.PAGE.lerp(lilac, 0.22)), "raised": _hex(UiTheme.RAISED),
		"wisp": _hex(UiTheme.WISP), "wisp_fill": _hex(UiTheme.PAGE.lerp(UiTheme.WISP, 0.55)),
		"wisp_soft": _hex(UiTheme.PAGE.lerp(UiTheme.WISP, 0.45)), "rug": _hex(UiTheme.PAGE.lerp(UiTheme.WISP, 0.35)),
		"window": _hex(UiTheme.DEEP.lerp(UiTheme.CYAN, 0.12)), "cushion": _hex(UiTheme.PAGE.lerp(UiTheme.PINK, 0.35)),
	}


## One step's part of the house (the mockup's drawings, plus the teapot and the rug).
func _part(id: String, c: Dictionary) -> void:
	match id:
		"base":  # the room before any step: one low bookcase
			_line("M34 204 L34 178 M96 204 L96 178")
			_line("M31 178 L99 178", c.lilac, 3.0)
			_pet(40, 184)
			_pet(57, 184, true)
			_pet(74, 184)
		"plank":
			_line("M34 178 L34 158 M96 178 L96 158")
			_line("M31 158 L99 158", c.lilac, 3.0)
			_pet(38, 160)
			_pet(56, 160, true)
			_pet(74, 160)
		"bunks":
			_line("M108 204 L108 156 M160 204 L160 156")
			_rect(108, 194, 52, 5, c.bed, c.pink_seam)
			_rect(108, 172, 52, 5, c.bed, c.pink_seam)
			_line("M108 162 L160 162", c.lilac, 2.0)
			_pet(114, 176, false, true)
			_pet(136, 176, true, true)
			_pet(116, 154, true, true)
			_pet(138, 154, false, true)
			if _mode != "ghost":  # tucked in
				_rect(112, 188, 44, 6, c.blanket, c.lilac_seam, 3.0)
				_rect(112, 166, 44, 6, c.blanket, c.lilac_seam, 3.0)
		"loft":
			_line("M166 204 L166 128 M177 204 L177 128")
			_line("M166 192 L177 192 M166 180 L177 180 M166 168 L177 168 M166 156 L177 156 M166 144 L177 144", c.lilac, 2.0)
			_rect(24, 128, 156, 5, c.wood)
			if _mode != "ghost":
				_raw('<ellipse cx="62" cy="126" rx="18" ry="3.5" fill="%s"/>' % c.cushion)
			_pet(36, 110)
			_pet(54, 110, true)
			_pet(72, 110, false, true)  # the teapot's handle
			_pet(118, 110, true, true)  # the teapot's spout
			_pet(138, 110)
		"attic":
			_rect(34, 97, 192, 4, c.wood)
			_shape('<circle cx="130" cy="62" r="10" fill="%s" stroke="%s" stroke-width="2.4"/>' % [c.window, c.lilac])
			_line("M130 52 L130 72 M120 62 L140 62", c.lilac, 1.8)
			if _mode != "ghost":  # fairy lights
				var dots := ""
				for d in [[58, 84, c.gold], [80, 70, c.pink], [102, 56, c.gold], [158, 56, c.pink], [180, 70, c.gold], [202, 84, c.pink]]:
					dots += '<circle cx="%d" cy="%d" r="1.8" fill="%s"/>' % d
				_raw(dots)
			_pet(76, 79)
			_pet(96, 79, true, true)  # the rug
			_pet(150, 79)
		"three":
			_line("M108 156 L108 136 M160 156 L160 136")
			_rect(108, 150, 52, 5, c.bed, c.wisp)
			_line("M108 140 L160 140", c.lilac, 2.0)
			_pet(114, 132, false, true)
			_pet(136, 132, true, true)
			if _mode != "ghost":
				_rect(112, 144, 44, 6, c.wisp_soft, c.wisp, 3.0)
		"hammocks":
			_line("M182 128 L182 102", c.lilac, 2.4)
			_pet(194, 101, false, true)
			_pet(212, 101, true, true)
			_shape('<path d="M184 106 Q209 132 234 106 Q209 122 184 106 Z" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [c.wisp_fill, c.wisp])
			_pet(172, 70, false, true)
			_shape('<path d="M160 76 Q182 96 204 82 Q182 88 160 76 Z" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [c.wisp_fill, c.wisp])
		"drawers":
			_rect(186, 160, 44, 44, c.raised)
			_line("M188 188 L228 188", c.lilac, 2.0)
			_shape('<circle cx="208" cy="196" r="1.8" fill="%s" stroke="none"/><circle cx="208" cy="182" r="1.8" fill="%s" stroke="none"/>' % [c.lilac, c.lilac])
			_pet(190, 146, false, true)
			_pet(209, 146, true, true)
			_rect(182, 160, 52, 13, c.raised, c.wisp, 2.0)
			_shape('<circle cx="208" cy="166.5" r="1.8" fill="%s" stroke="none"/>' % c.wisp)
			_rect(186, 174, 44, 14, c.raised)
			_line("M230 179 Q236 178 235 184", c.pink, 2.4)
		"teapot":  # on the loft floor, a pet peeking out under the lid
			_pet(95, 99, false, true)
			_shape('<path d="M92 114 Q90 128 104 128 Q118 128 116 114 Z" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [c.wisp_soft, c.lilac])
			_line("M92 117 Q84 114 86 122 Q88 126 92 124", c.lilac, 2.0)
			_line("M116 118 Q122 118 124 111", c.lilac, 2.0)
			_line("M91 114 L117 114", c.wisp, 2.4)
			if _mode != "ghost":
				_raw('<circle cx="104" cy="122" r="1.6" fill="%s"/><circle cx="98" cy="121" r="1.2" fill="%s"/>' % [c.pink, c.pink])
		"rug":  # on the attic floor, two pets peeking out from under it
			_pet(116, 80, false, true)
			_pet(132, 80, true, true)
			_shape('<path d="M110 97 Q112 88 130 88.5 Q148 88 150 97 Z" fill="%s" stroke="%s" stroke-width="2" stroke-linejoin="round"/>' % [c.rug, c.wisp])
			_line("M116 93 L144 93", c.pink, 1.6)
		_:  # a step with no drawing of its own yet: one more tiny pet, from the tuck spots' far end
			_odd_n += 1
			_tuck(TUCKS.size() - _odd_n, c)


## An endless step: one more tiny pet tucked in somewhere (in pencil: a dashed pet-sized outline).
func _tuck(n: int, c: Dictionary) -> void:
	if n < 0 or n >= TUCKS.size():
		return
	var t: Array = TUCKS[n]
	if _mode == "ghost":
		_shape('<rect x="%d" y="%d" width="16" height="18" rx="5" fill="none" stroke="%s" stroke-width="2"/>' % [t[0], t[1], c.wisp])
	else:
		_pet(t[0], t[1], t[2], t.size() > 3 and t[3])


# ---- SVG pieces (in pencil they turn dashed and empty) ------------------------

func _raw(svg: String) -> void:
	_ops.append(["svg", svg])


func _pencil_attrs() -> String:
	return 'stroke="%s" stroke-dasharray="4 3"' % _hex(_pencil)


func _line(d: String, color := "", width := 2.6) -> void:
	if color == "":
		color = _hex(UiTheme.LILAC)
	var stroke := _pencil_attrs() if _mode == "ghost" else 'stroke="%s"' % color
	_raw('<path d="%s" fill="none" %s stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"/>' % [d, stroke, width])


func _rect(x: float, y: float, w: float, h: float, fill: String, stroke := "", rx := 1.5) -> void:
	if stroke == "":
		stroke = _hex(UiTheme.LILAC)
	if _mode == "ghost":
		_raw('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="none" %s stroke-width="2"/>' % [x, y, w, h, rx, _pencil_attrs()])
	else:
		_raw('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s" stroke="%s" stroke-width="2"/>' % [x, y, w, h, rx, fill, stroke])


## A filled shape: in pencil its fill goes and its outline turns dashed (shapes with no outline go).
func _shape(svg: String) -> void:
	if _mode != "ghost":
		_raw(svg)
		return
	var out := RegEx.create_from_string('fill="[^"]*"').sub(svg, 'fill="none"', true)
	out = RegEx.create_from_string('stroke="(?!none)[^"]*"').sub(out, _pencil_attrs(), true)
	if not out.contains("stroke-dasharray"):
		return
	_raw(out)


## A tiny pet. `under`: a shape drawn after it covers part of it (so the lines split there).
func _pet(x: float, y: float, flipped := false, under := false) -> void:
	if _mode == "ghost":
		return
	_ops.append(["pet", Vector2(x, y), flipped, _pet_n, _step_i, under])
	_pet_n += 1


static func _hex(color: Color) -> String:
	return "#" + color.to_html(false)
