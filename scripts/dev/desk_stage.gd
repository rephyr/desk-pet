class_name DeskStage
extends Control
## Debug builds: a pretend desktop over the full game, for flows (DevDriver "desk on"). One fake
## window and a fake corner panel, with the real DesktopPet walking on them in stage mode, so its
## quiet paws can be seen and shot without anything going onto the real desktop.

const WINDOW := Rect2(90, 280, 480, 330)  # the fake window (its top edge is where the pet works)
const PANEL := Rect2(700, 420, 196, 156)  # the fake corner panel

var pet := DesktopPet.new()
var source := StageSource.new()


func _init() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP  # the game underneath doesn't get clicks meant for the desktop
	source.windows = [WINDOW]
	source.home = PANEL


func _ready() -> void:
	pet.source = source
	pet.stage = self
	pet.pixel = 4
	pet.set_pet(GameState.collection.active())
	add_child(pet)
	pet.drop_at(Vector2(WINDOW.position.x + 160.0, WINDOW.position.y - 120.0))
	GameState.collection.active_changed.connect(func(p): pet.set_pet(p))


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	# a soft wallpaper, darker at the top
	var top := UiTheme.DEEP
	var low := UiTheme.DEEP.lerp(UiTheme.LILAC_SEAM, 0.35)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), r.end, Vector2(0, r.end.y)]),
		PackedColorArray([top, top, low, low]))
	_window(WINDOW, "notes.txt")
	# the corner panel: the game's own small window
	draw_style_box(UiTheme.box(UiTheme.PAGE, UiTheme.PINK_SEAM, 10, 2, 0), PANEL)
	draw_rect(Rect2(PANEL.position + Vector2(12, 14), Vector2(60, 8)), UiTheme.PINK_SEAM)
	draw_rect(Rect2(PANEL.position + Vector2(12, 30), Vector2(120, 6)), UiTheme.MUTED_SEAM)
	draw_rect(Rect2(PANEL.position + Vector2(12, 42), Vector2(90, 6)), UiTheme.MUTED_SEAM)


func _window(w: Rect2, title: String) -> void:
	draw_style_box(UiTheme.box(UiTheme.RAISED, UiTheme.LILAC_SEAM, 8, 2, 0), w)
	draw_rect(Rect2(w.position + Vector2(2, 2), Vector2(w.size.x - 4, 22)), UiTheme.PAGE)
	draw_string(get_theme_default_font(), w.position + Vector2(12, 18), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.MUTED)
	for i in 6:
		draw_rect(Rect2(w.position + Vector2(16, 40 + i * 18), Vector2(w.size.x * (0.4 + 0.08 * (i % 4)), 6)), UiTheme.MUTED_SEAM)

