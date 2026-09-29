class_name FrontRow
extends Control
## The front row: your pet with its flag, then up to `front_n` (data/dungeon.json front_row, the pinwheel perk more) little
## card pets in a 7-wide grid, as many rows as that takes; empty places are dashed. Tap it to pick the cards (the dungeon page, DungeonView).
## In the sewing room, cards that match a mark of the room's chalk lock get a chalk tick.

signal pressed

const CELL := Vector2(36, 42)
const GAP := Vector2(3, 6)  # (4 wide before the well got its nails lane)
const COLS := 7

var _cells: Array = []  # [texture, tier colour, lead, chalk tick]
var _places := 1  # your pet's and the front row's


func _init(lead: Pet, cards: Array, clickable: bool, front_n: int, ticks: Array = []) -> void:
	_places = maxi(front_n, 0) + 1
	var rows := ceili(_places / float(COLS))
	custom_minimum_size = Vector2(COLS * CELL.x + (COLS - 1) * GAP.x, rows * CELL.y + (rows - 1) * GAP.y)
	texture_filter = TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_STOP if clickable else MOUSE_FILTER_IGNORE
	mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var catalog := GameState.catalog
	if lead:
		_cells.append([PetLook.texture_for(lead.parts, false, lead.sewn), catalog.tier_color(lead.rarity), true, false])
	var front := cards.slice(0, front_n)
	for k in front.size():
		var pet: Pet = front[k]
		_cells.append([PetLook.texture_for(pet.parts, false, pet.sewn), catalog.tier_color(pet.rarity), false, k < ticks.size() and bool(ticks[k])])


func _draw() -> void:
	var step := Vector2((size.x - CELL.x) / (COLS - 1), CELL.y + GAP.y)
	for i in _places:
		var at := Vector2(i % COLS * step.x, i / COLS * step.y).round()
		var r := Rect2(at, CELL)
		if i < _cells.size():
			var c: Array = _cells[i]
			var sb := UiTheme.box(UiTheme.RAISED, (c[1] as Color).lerp(UiTheme.DEEP, 0.2), 8, 2, 0)
			sb.shadow_color = UiTheme.SHADOW
			sb.shadow_size = 3
			sb.shadow_offset = Vector2(0, 2)
			draw_style_box(sb, r)
			draw_texture_rect(c[0], Rect2(at + Vector2(2, CELL.y - 38), Vector2(32, 36)), false)
			if c[2]:  # your pet leads: a little pink flag on its card
				var f := at + Vector2(-3, -6)
				draw_line(f + Vector2(2, 12), f + Vector2(2, 0), UiTheme.PINK, 2.0, true)
				draw_colored_polygon(PackedVector2Array([f + Vector2(2.5, 0.5), f + Vector2(11, 3), f + Vector2(2.5, 6)]), UiTheme.PINK)
			if c[3]:  # it matches the sewing room's chalk lock: a chalk tick in the corner
				var chalk := Color(UiTheme.TEXT, 0.72)
				var t := at + Vector2(CELL.x - 2.0, 2.0)
				draw_circle(t, 7.0, UiTheme.DEEP)
				draw_arc(t, 7.0, 0, TAU, 20, chalk, 2.0, true)
				draw_polyline(PackedVector2Array([t + Vector2(-3.2, 0.4), t + Vector2(-1.0, 2.6), t + Vector2(3.0, -2.2)]), chalk, 1.8, true)
		else:
			var sb := StitchBox.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.dash_color = UiTheme.LINE
			sb.radius = 8
			draw_style_box(sb, r)


func _gui_input(event: InputEvent) -> void:
	# on letting go: the page is rebuilt with the picker, this row included
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
