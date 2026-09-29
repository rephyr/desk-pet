class_name PawsView
extends Node2D
## Draws the props for quiet paws (QuietPaws) round the desktop pet, at its size: the pile of packs
## and the pack in its paws, the pop, the tiny capsule machine, the sparkles round a good pull, the
## dust of a foot tap, and presents (the dirt it digs one up from, the present on its head, what
## hops out when you tap it). Two of these sit on the desktop pet, one behind it (`front` false: the
## pile, the machine) and one in front (the pack in its paws, the puff, sparkles, dust). The origin
## is at the pet's feet. Drawn in the corner panel's units (PetAtWork, a pet at 3 px per art
## pixel), scaled up to the desktop pet's pixel size. Like the desktop pet's hearts it keeps its
## own colours (no UiTheme: the headless tests load it, and they have no autoloads).

const PROP_AT := 38.0  # how far beside the pet the pile or machine stands (corner panel units)
const MACHINE_SIZE := 1.4  # the tiny machine, a bit bigger than the corner panel's units
const SQUISH := 0.12  # how much the tiny machine squishes wide when a capsule comes out
const PINK := Color("ff79c6")
const PINK_SEAM := Color("a64f81")
const LILAC := Color("c9a0ff")
const GLASS := Color("c9a0ff", 0.35)
const MUTED := Color("9a88ad")
const DEEP := Color("120a19")
const GOLD := Color("ffe08a")
const CYAN := Color("8be9fd")
const MINT := Color("8fe8c0")
const FOIL := Color("6b4fa0")
const FOIL_LIGHT := Color("8e6fd0")
const PAPER_LIGHT := Color("ffb3dd")  # a present's lid
const DIRT := Color("a57c5c")
const DIRT_LIGHT := Color("d9b08c")
const PRESENT_H := 15.0  # a present's height, bow and all, in its own pixels (see draw_present)

var paws: QuietPaws
var front := false
var pixel := 4
var side := 1  # which side of the pet the pile or machine stands on
var facing := 1
var held_at := Vector2.ZERO  # where the held pet's feet are (for the sparkles)
var head := Vector2.ZERO  # where a present on its head stands: the top of the pet's art (DesktopPet sets it every frame)


func _init(p_paws: QuietPaws = null, p_front := false) -> void:
	paws = p_paws
	front = p_front
	texture_filter = TEXTURE_FILTER_NEAREST


## How far out from the pet's middle a prop reaches, in corner panel units: the pile (its outer
## pack, tilted) or the tiny machine (its handle tip, squished wide by a hop).
static func reach(pose: QuietPaws.Pose) -> float:
	match pose:
		QuietPaws.Pose.BOXES:
			return PROP_AT + 7.0 + 6.0 * cos(0.15) + 8.0 * sin(0.15)
		QuietPaws.Pose.MACHINE:
			return PROP_AT + 4.0 + (9.0 + 6.0 + 2.0) * MACHINE_SIZE * (1.0 + SQUISH)
	return 0.0


## The reach of the biggest prop: a stint can switch from the pile to the machine where it stands.
static func widest() -> float:
	return maxf(reach(QuietPaws.Pose.BOXES), reach(QuietPaws.Pose.MACHINE))


## Screen pixels per corner panel unit.
func unit() -> float:
	return pixel / 3.0


## Screen pixels per pixel of a present (whole pixels, so it stays crisp): 3 at the usual size.
static func present_zoom(pet_pixel: int) -> float:
	return maxf(1.0, roundf(pet_pixel * 0.75))


func _draw() -> void:
	if paws == null:
		return
	var k := unit()
	match paws.pose:
		QuietPaws.Pose.BOXES:
			if front:
				_front_boxes(k)
			else:
				for i in 3:
					draw_pack(self, Vector2(side * PROP_AT + (i - 1) * 7.0, -8.0 - i * 3.0) * k, (i - 1) * 0.15, k)
		QuietPaws.Pose.MACHINE:
			if not front:
				_machine(k)
		QuietPaws.Pose.HOLD:
			if front:
				_sparkles(k)
		QuietPaws.Pose.WAIT:
			if front and paws.dust > 0.0:
				# two puffs of dust kicked up at its front foot
				var rise := (1.0 - paws.dust) * 5.0 * k
				var c := Color(LILAC, paws.dust)
				var foot := Vector2(facing * 12.0 * k, -2.0 * k - rise)
				draw_rect(Rect2(foot + Vector2(facing * 2.0 * k, 0), Vector2(k * 2.0, k * 2.0)), c)
				draw_rect(Rect2(foot + Vector2(facing * 6.0 * k, -3.0 * k), Vector2(k * 2.0, k * 2.0)), c)
		QuietPaws.Pose.DIG:
			_dig(k)
	if front and paws.worn:
		draw_present(self, head, sin(paws.time * 3.0) * 0.04, present_zoom(pixel))
	if front and paws.pop > 0.0:
		_pop(k)
	if front and paws.puff > 0.0:
		for i in 6:
			var a := TAU * i / 6.0
			var r := ((1.0 - paws.puff) * 26.0 + 6.0) * k
			draw_circle(Vector2(0, -22.0 * k) + Vector2(cos(a), sin(a)) * r, 3.0 * k * paws.puff, Color(LILAC, paws.puff))


## Digging up a present (in front): dirt flung out behind it, and the present rising out of a
## little heap in front of its paws near the end.
func _dig(k: float) -> void:
	var t := paws.dig_progress()
	if not front:
		return
	for i in 9:  # flung out behind it, over its back
		var ph := fmod(paws.time * 2.4 + i / 9.0, 1.0)
		var at := Vector2(-facing * (6.0 + ph * (32.0 + (i % 3) * 6.0)), -6.0 - sin(ph * PI) * (18.0 + (i % 2) * 8.0)) * k
		draw_rect(Rect2(at.round(), Vector2(3.0, 3.0) * k), Color(DIRT if i % 2 == 0 else DIRT_LIGHT, 1.0 - ph * 0.5))
	var heap := Vector2(facing * 15.0, 0.0) * k
	draw_rect(Rect2(heap + Vector2(-8.0, -3.0) * k, Vector2(16.0, 3.0) * k), DIRT)
	draw_rect(Rect2(heap + Vector2(-5.0, -6.0) * k, Vector2(10.0, 3.0) * k), DIRT_LIGHT)
	if t > 0.6:
		var rise := (t - 0.6) / 0.4
		var z := present_zoom(pixel)
		draw_set_transform(heap + Vector2(0, -2.0 * k), 0.0, Vector2(z, z * rise))
		draw_present(self, Vector2.ZERO, 0.0, 1.0, PINK, PINK_SEAM, LILAC, PAPER_LIGHT, false)
		draw_set_transform(Vector2.ZERO)


## What came out of the present on its head: a tiny pack or a capsule, hopping up and fading.
func _pop(k: float) -> void:
	var t := 1.0 - paws.pop
	if t < 0.5:  # bits of wrapping paper burst off where the present was
		for i in 8:
			var ang := TAU * i / 8.0 + 0.3
			var bit := head + Vector2(0, -7.0 * k) + Vector2(cos(ang), sin(ang) * 0.7) * (4.0 + t * 44.0) * k
			draw_rect(Rect2(bit.round(), Vector2(3.0, 3.0) * k), Color(PINK if i % 2 == 0 else LILAC, 1.0 - t * 2.0))
	var at := head + Vector2(0, -8.0 - sin(minf(t * 1.6, 1.0) * PI * 0.5) * 22.0) * k
	var a := minf(1.0, paws.pop * 2.0)
	if paws.pop_toy:
		var r := 5.0 * k
		draw_circle(at, r, Color(CYAN, a))
		var low := PackedVector2Array()
		for i in 9:
			var ang := PI * i / 8.0
			low.append(at + Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(low, Color(Color.WHITE, a))
		draw_line(at - Vector2(r, 0), at + Vector2(r, 0), Color(DEEP, a * 0.6), maxf(1.0, k * 0.8))
	else:
		var tilt := sin(t * 9.0) * 0.2
		draw_pack(self, at, tilt, k * 1.4, false, PINK, a)
		draw_set_transform(at, tilt, Vector2(k * 1.4, k * 1.4))
		draw_rect(Rect2(-6, -8, 12, 16), Color(LILAC, a), false, 1.0)  # so it shows on a dark desktop
		draw_set_transform(Vector2.ZERO)


## The pack in its paws: held, then shaken.
func _front_boxes(k: float) -> void:
	if paws.phase == QuietPaws.Phase.REACH or paws.puff > 0.5:
		return
	var wiggle := sin(paws.time * 30.0) * 0.25 if paws.phase == QuietPaws.Phase.SHAKE else 0.0
	draw_pack(self, Vector2(facing * 14.0, -13.0) * k, wiggle, k)


## Gold sparkles round the good pull over its head.
func _sparkles(k: float) -> void:
	for i in 5:
		var a := TAU * i / 5.0 + paws.time * 1.5
		var at := held_at + Vector2(cos(a) * 26.0, -18.0 + sin(a) * 16.0) * k
		var twinkle := (2.0 + 2.0 * absf(sin(paws.time * 5.0 + i))) * k
		draw_line(at - Vector2(twinkle, 0), at + Vector2(twinkle, 0), GOLD, 1.5 * k)
		draw_line(at - Vector2(0, twinkle), at + Vector2(0, twinkle), GOLD, 1.5 * k)


## A tiny card pack, like the big one you rip open yourself (12 x 16 at `zoom` 1), drawn on `on`
## centred at `at`, with a `mark` in the middle. Also the corner panel's pile (PetAtWork).
static func draw_pack(on: CanvasItem, at: Vector2, tilt: float, zoom := 1.0, empty := false, mark := PINK, alpha := 1.0) -> void:
	on.draw_set_transform(at, tilt, Vector2(zoom, zoom))
	if empty:
		# a dotted outline where the packs will be once there are coins for them
		on.draw_rect(Rect2(-6, -8, 12, 16), Color(FOIL_LIGHT, 0.35), false, 1.0)
		on.draw_set_transform(Vector2.ZERO)
		return
	on.draw_rect(Rect2(-6, -8, 12, 16), Color(FOIL, alpha))
	on.draw_rect(Rect2(-6, -8, 12, 3), Color(FOIL_LIGHT, alpha))
	on.draw_rect(Rect2(-2, -1, 4, 3), Color(mark, alpha))
	on.draw_set_transform(Vector2.ZERO)


## A wrapped present (12 wide, PRESENT_H tall with its bow, at `zoom` 1), standing on `at` (its
## bottom middle): paper, a lid, a ribbon down the middle and a bow on top. Also the home tab's
## (it passes its own theme colours). `own_transform` false: drawn in the transform already set.
static func draw_present(on: CanvasItem, at: Vector2, tilt: float, zoom := 1.0, paper := PINK, shade := PINK_SEAM,
		ribbon := LILAC, lid := PAPER_LIGHT, own_transform := true) -> void:
	if own_transform:
		on.draw_set_transform(at, tilt, Vector2(zoom, zoom))
	var knot := ribbon.darkened(0.3)
	on.draw_rect(Rect2(-6, -10, 12, 10), paper)  # the box
	on.draw_rect(Rect2(3, -10, 3, 10), shade)  # its shady side
	on.draw_rect(Rect2(-6, -1, 12, 1), shade)
	on.draw_rect(Rect2(-7, -12, 14, 3), lid)  # the lid, sticking out a pixel
	on.draw_rect(Rect2(3, -12, 4, 3), paper)
	on.draw_rect(Rect2(-7, -10, 14, 1), shade)
	on.draw_rect(Rect2(-1, -12, 2, 12), ribbon)  # the ribbon
	on.draw_rect(Rect2(-5, -15, 4, 3), ribbon)  # the bow's two loops and its knot
	on.draw_rect(Rect2(1, -15, 4, 3), ribbon)
	on.draw_rect(Rect2(-4, -14, 2, 1), knot)
	on.draw_rect(Rect2(2, -14, 2, 1), knot)
	on.draw_rect(Rect2(-1, -14, 2, 2), knot)
	if own_transform:
		on.draw_set_transform(Vector2.ZERO)


## A tiny capsule machine, like the one your pet brought home: a glass globe on a body, a chute,
## and a handle on the far side that turns as it cranks. It hops when a capsule comes out.
func _machine(k: float) -> void:
	var hop := absf(sin(paws.bounce * PI * 2.0)) * paws.bounce * 5.0
	var squish := paws.bounce * SQUISH
	var base := Vector2(side * (PROP_AT + 4.0), -hop) * k
	var m := k * MACHINE_SIZE
	draw_set_transform(base, 0.0, Vector2(m * (1.0 + squish), m * (1.0 - squish)))
	# the handle, behind the body on the far side
	var pivot := Vector2(side * 9.0, -11.0)
	var ang := paws.crank * TAU
	var tip := pivot + Vector2(cos(ang), sin(ang)) * 6.0
	draw_line(pivot, tip, MUTED, 2.0)
	draw_circle(tip, 2.0, PINK)
	# body, chute and a coin slot
	draw_rect(Rect2(-9, -16, 18, 16), PINK_SEAM)
	draw_rect(Rect2(-9, -16, 18, 3), PINK)
	draw_rect(Rect2(-4, -9, 8, 6), DEEP)
	draw_rect(Rect2(3, -14, 3, 1), DEEP)
	# the globe with a few capsules in it
	draw_circle(Vector2(0, -24), 9.0, GLASS)
	for c in [[Vector2(-3, -21), CYAN], [Vector2(3, -22), GOLD], [Vector2(0, -26), PINK], [Vector2(-4, -27), MINT]]:
		draw_circle(c[0], 2.2, c[1])
	draw_arc(Vector2(0, -24), 9.0, 0.0, TAU, 20, Color(LILAC, 0.8), 1.0)
	draw_rect(Rect2(-5, -32, 3, 2), Color(1, 1, 1, 0.6))  # a glint
	# a capsule rolling out of the chute right after a crank
	if paws.bounce > 0.2:
		var out := (1.0 - paws.bounce) * 8.0
		draw_circle(Vector2(-side * out, -5), 2.2, GOLD)
	draw_set_transform(Vector2.ZERO)
