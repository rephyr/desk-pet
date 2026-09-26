class_name RevealEffects
extends Node2D
## The light and particles coming out of the pack. Effects are layers that stack: each rarity
## step adds its layers (from data/reveal.json) on top of the ones already running.
## Place this node at the pack's mouth.

const GLOW_SIZE := 420.0
const BEAMS := 9
const BEAM_LENGTH := 520.0
const SHOCK_EVERY := 0.9
const SHAFT_HEIGHT := 300.0
const SOURCE_DEPTH := 48.0  # how far below the opening the light comes from

var color := Color("8a7f99"):
	set(value):
		color = value
		for p in [_sparkles, _fountain, _burst]:
			p.color = value
## 0..1: how far the light is out (used while the pack is still being ripped).
var leak := 0.0
## Width of the opening the light comes out of.
var opening_width := 110.0

var _layers := {}  # layer name -> strength 0..1
var _time := 0.0
var _glow_tex := _make_glow_texture()
var _beam_tex := _make_beam_texture()
var _dome_tex := _make_dome_texture()
var _sparkles := _particles(40, 1.6)
var _fountain := _particles(50, 1.4)
var _burst := _particles(60, 0.9)
var _shock_rings: Array[float] = []  # ages of the rings on screen
var _shock_timer := 0.0


func _init() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add  # light adds up instead of covering things
	texture_filter = TEXTURE_FILTER_LINEAR  # light is soft, unlike the pixel art around it

	_sparkles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_sparkles.emission_rect_extents = Vector2(50, 4)
	_sparkles.direction = Vector2.UP
	_sparkles.spread = 20.0
	_sparkles.gravity = Vector2(0, -40)
	_sparkles.initial_velocity_min = 40.0
	_sparkles.initial_velocity_max = 110.0
	_sparkles.scale_amount_min = 2.0
	_sparkles.scale_amount_max = 4.0

	_fountain.direction = Vector2.UP
	_fountain.spread = 28.0
	_fountain.gravity = Vector2(0, 700)
	_fountain.initial_velocity_min = 300.0
	_fountain.initial_velocity_max = 470.0
	_fountain.scale_amount_min = 4.0
	_fountain.scale_amount_max = 6.0

	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.direction = Vector2.UP
	_burst.spread = 60.0  # sprays up out of the pack
	_burst.gravity = Vector2(0, 300)
	_burst.initial_velocity_min = 120.0
	_burst.initial_velocity_max = 380.0
	_burst.scale_amount_min = 3.0
	_burst.scale_amount_max = 6.0
	for p in [_sparkles, _fountain, _burst]:
		add_child(p)


func has_layer(layer: String) -> bool:
	return _layers.has(layer)


## Adds effect layers; they fade in over `fade` seconds.
func add_layers(layers: Array, fade := 0.3) -> void:
	for layer in layers:
		if _layers.has(layer):
			continue
		_layers[layer] = 0.0
		create_tween().tween_method(func(v): _layers[layer] = v, 0.0, 1.0, fade) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		match layer:
			"sparkles": _sparkles.emitting = true
			"fountain": _fountain.emitting = true


## A one-off explosion of `amount` particles.
func burst(amount: int) -> void:
	_burst.amount = maxi(1, amount)
	_burst.restart()


## Speeds every effect up or down (the reveal speed setting).
func set_speed(speed: float) -> void:
	for p in [_sparkles, _fountain, _burst]:
		p.speed_scale = speed


func clear() -> void:
	_layers.clear()
	_shock_rings.clear()
	leak = 0.0
	for p in [_sparkles, _fountain]:
		p.emitting = false
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if _layers.has("shockwave"):
		_shock_timer -= delta
		if _shock_timer <= 0.0:
			_shock_timer = SHOCK_EVERY
			_shock_rings.append(0.0)
	for i in range(_shock_rings.size() - 1, -1, -1):
		_shock_rings[i] += delta
		if _shock_rings[i] > 1.2:
			_shock_rings.remove_at(i)
	queue_redraw()


func _draw() -> void:
	# The light source sits inside the pack, below the opening (y = 0 here). Everything is drawn
	# from there; the front of the pack hides what's still inside, so rays leave the opening at
	# the angles the opening lets through.
	var source := Vector2(0, SOURCE_DEPTH)
	var half := opening_width / 2.0
	var spread := atan2(half, SOURCE_DEPTH)  # widest angle that still gets out of the opening

	var glow: float = maxf(leak * 0.7, _layers.get("glow", 0.0))
	if glow > 0.0:
		var pulse := 1.0 + sin(_time * 3.0) * 0.05
		# soft ambient dome above the pack
		var s := GLOW_SIZE * pulse * lerpf(0.5, 1.0, glow)
		draw_texture_rect(_dome_tex, Rect2(-s / 2.0, -s / 2.0, s, s / 2.0), false, Color(color, 0.5 * glow))
		# the shaft: everything the opening lets through, widening as it rises
		var h := SHAFT_HEIGHT * pulse * lerpf(0.4, 1.0, glow)
		var top_half := (h + SOURCE_DEPTH) * tan(spread) * 0.85
		_draw_ray(source, Vector2(0, -h), top_half, Color(color, 0.5 * glow))
		# the bright slit itself
		var slit := Color(color.lerp(Color.WHITE, 0.6), minf(1.0, glow * 1.2))
		draw_texture_rect(_glow_tex, Rect2(-half * 1.1, -10, half * 2.2, 20), false, slit)

	var beams: float = _layers.get("beams", 0.0)
	if beams > 0.0:
		var sway: float = _layers.get("rotate", 0.0)
		for i in BEAMS:
			var t := (i + 0.5) / BEAMS
			# rays fill the opening's cone; with "rotate" they sweep side to side inside it
			var offset := (t - 0.5) * 2.0 * spread * 0.9 + sin(_time * 0.9 + i * 0.4) * 0.25 * sway
			var angle := -PI / 2.0 + clampf(offset, -spread, spread)
			# each ray breathes a little on its own so they never look ruler-straight
			var wobble := sin(_time * (1.3 + i * 0.37) + i * 2.1)
			var width := 22.0 + 8.0 * sin(i * 1.7) + 5.0 * wobble
			var length := BEAM_LENGTH * (0.75 + 0.2 * sin(i * 2.3) + 0.05 * wobble) + SOURCE_DEPTH
			var alpha := 0.3 * beams * (0.8 + 0.2 * wobble)
			_draw_beam(source, angle, width * 2.6, length * 0.9, Color(color, alpha * 0.35))  # soft halo
			_draw_beam(source, angle, width, length, Color(color, alpha))

	for age in _shock_rings:
		var r := 30.0 + age * 380.0
		draw_arc(Vector2(0, -20), r, PI, TAU, 48, Color(color, (1.0 - age / 1.2) * 0.8), 6.0 - age * 4.0)


## One ray from `from` at `angle`: a point at the light, `width` either side of its middle at
## the far end, soft at the edges and fading out towards the tip (the texture does that).
func _draw_beam(from: Vector2, angle: float, width: float, length: float, c: Color) -> void:
	_draw_ray(from, from + Vector2.from_angle(angle) * length, width, c)


## Drawn as two mirrored triangles sharing the middle line, so the soft texture stays
## symmetric (a single stretched quad skews to one side).
func _draw_ray(from: Vector2, tip: Vector2, half_width: float, c: Color) -> void:
	var side := (tip - from).normalized().orthogonal() * half_width
	var colors := PackedColorArray([c, c, c])
	draw_polygon(PackedVector2Array([from, tip + side, tip]), colors,
		PackedVector2Array([Vector2(0.5, 0), Vector2(1, 1), Vector2(0.5, 1)]), _beam_tex)
	draw_polygon(PackedVector2Array([from, tip, tip - side]), colors,
		PackedVector2Array([Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0, 1)]), _beam_tex)


func _particles(amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.use_parent_material = true
	p.color = color
	return p


## Soft ray texture: u runs across the ray (bright middle, see-through edges),
## v runs along it (full at the light, fading out at the tip).
static func _make_beam_texture() -> ImageTexture:
	var img := Image.create_empty(32, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var along := 1.0 - y / 63.0
		along = along * along * (3.0 - 2.0 * along)  # smoothstep
		for x in 32:
			var across := 1.0 - absf(x / 31.0 * 2.0 - 1.0)
			across = pow(across, 1.6)
			img.set_pixel(x, y, Color(1, 1, 1, across * along))
	return ImageTexture.create_from_image(img)


## Half a glow, brightest just above its bottom middle, fading out towards its base line too
## so it has no hard edge where it meets the pack's top.
static func _make_dome_texture() -> ImageTexture:
	var img := Image.create_empty(128, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		var up := (63.0 - y) / 63.0  # 0 at the base, 1 at the top
		var base_fade := smoothstep(0.0, 0.35, up)
		for x in 128:
			var d := Vector2((x - 63.5) / 64.0, up).length()
			var a := pow(maxf(0.0, 1.0 - d), 1.5) * base_fade
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


static func _make_glow_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 128
	tex.height = 128
	return tex
