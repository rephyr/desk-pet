class_name KnackBadge
extends Control
## A knack as a round sewn-on badge (look C in design/mockups/screens/knacks.html): a tinted fill
## and a thick edge in the part's rarity colour, a dashed stitch ring inside, the knack's doodle in
## the middle. The chosen one tilts, grows a little and gets a pink ring. Tap it to read it
## (the pet details show the card).

signal pressed(knack: Dictionary)

var knack := {}
var chosen := false:
	set(v):
		chosen = v
		queue_redraw()
var _lift := 0.0
var _px := 32
var _tween: Tween


## `px`: how wide it is (the pet details use 32; a shelf card draws its 20 px corner badge itself
## with draw_badge).
func _init(p_knack: Dictionary, px := 32) -> void:
	knack = p_knack
	_px = px
	custom_minimum_size = Vector2(px, px)
	size_flags_vertical = SIZE_SHRINK_CENTER
	tooltip_text = str(knack.get("name", ""))
	mouse_filter = MOUSE_FILTER_STOP
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _hover(true))
	mouse_exited.connect(func(): _hover(false))


func _hover(on: bool) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_lift, _lift, 2.0 if on else 0.0, 0.2)


func _set_lift(v: float) -> void:
	_lift = v
	queue_redraw()


func _draw() -> void:
	var grow := 1.12 if chosen else 1.0
	draw_badge(self, knack, size / 2.0 - Vector2(0, 0.0 if chosen else _lift), _px * grow, -8.0 if chosen else 0.0, chosen)


## Draws a knack badge `px` wide centred on `centre` of `item` (MiniCard draws its corner badge
## with this). `ring`: the chosen badge's pink ring.
static func draw_badge(item: CanvasItem, k: Dictionary, centre: Vector2, px: float, tilt := 0.0, ring := false) -> void:
	var tier := Catalog.shared().tier_color(str(k.get("tier", "common")))
	var r := px / 2.0
	item.draw_set_transform(centre, deg_to_rad(tilt), Vector2.ONE)
	if ring:
		item.draw_circle(Vector2.ZERO, r + 5.0, UiTheme.PINK)
		item.draw_circle(Vector2.ZERO, r + 3.0, UiTheme.RAISED)
	var edge := 3.0 if px >= 28 else 2.0
	item.draw_circle(Vector2.ZERO, r, tier)
	item.draw_circle(Vector2.ZERO, r - edge, UiTheme.DEEP.lerp(tier, 0.14))
	# the stitches just inside the edge
	var ring_r := r - edge - 2.0
	var stitches := int(ring_r * 1.1)
	for i in stitches:
		var a0 := TAU * i / stitches
		item.draw_arc(Vector2.ZERO, ring_r, a0, a0 + TAU / stitches * 0.55, 3, Color(tier, 0.55), 1.5, true)
	var icon_px := int(px * 0.56)
	var tex := UiTheme.icon(str(k.get("icon", "")), icon_px, UiTheme.TEXT)
	if tex:
		item.draw_texture_rect(tex, Rect2(Vector2(-icon_px, -icon_px) / 2.0, Vector2(icon_px, icon_px)), false)
	item.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(knack)
		accept_event()
