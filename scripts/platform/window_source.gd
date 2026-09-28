class_name WindowSource
extends RefCounted
## Tells the pet where the other windows on the desktop are.
## One subclass per platform; the pet only talks to this interface.


## Called once with the game's windows so a backend can set itself up.
func setup(_home: Window, _overlay: Window) -> void:
	pass


## Visible windows as Rect2 in the overlay's local pixels, front-most first.
## Our own overlay is left out; the home window is included so the pet can sit on it.
func get_windows(_overlay: Window) -> Array[Rect2]:
	return []


## Where the home window (the corner panel or the full game) is, in the overlay's local pixels.
func home_rect(home: Window, overlay: Window) -> Rect2:
	if home == null or overlay == null:
		return Rect2()
	return Rect2(Vector2(home.position - overlay.position), Vector2(home.size))


## Makes the overlay cover the screen the home window is on.
func place_overlay(home: Window, overlay: Window) -> void:
	var screen := DisplayServer.window_get_current_screen(home.get_window_id())
	overlay.position = DisplayServer.screen_get_position(screen)
	overlay.size = DisplayServer.screen_get_size(screen)


## The mouse cursor in the overlay's local pixels.
func mouse_position(overlay: Window) -> Vector2:
	return Vector2(DisplayServer.mouse_get_position() - overlay.position)


## How many real pixels one UI pixel should be on the home window's screen.
func ui_scale(home: Window) -> float:
	# TODO(windows): check this against real DPI settings once the Windows port starts
	var screen := DisplayServer.window_get_current_screen(home.get_window_id())
	return maxf(1.0, snappedf(DisplayServer.screen_get_scale(screen), 0.25))


## How much room the home window's screen has (minus panels and bars), in the same UI pixels
## set_home_size takes.
func room(home: Window) -> Vector2i:
	var screen := DisplayServer.window_get_current_screen(home.get_window_id())
	return Vector2i((Vector2(DisplayServer.screen_get_usable_rect(screen).size) / ui_scale(home)).floor())


## Resizes the home window to `logical_size` UI pixels, growing away from the screen corner
## it sits nearest to, so it expands towards the middle and shrinks back to the same spot.
func set_home_size(home: Window, logical_size: Vector2i) -> void:
	var screen := DisplayServer.window_get_current_screen(home.get_window_id())
	var target := anchored_rect(Rect2i(home.position, home.size), DisplayServer.screen_get_usable_rect(screen),
		Vector2i((Vector2(logical_size) * ui_scale(home)).round()))
	home.size = target.size
	home.position = target.position


## `current` resized to `new_size`, keeping the corner nearest the screen corner fixed,
## and kept inside `bounds`.
static func anchored_rect(current: Rect2i, bounds: Rect2i, new_size: Vector2i) -> Rect2i:
	var pos := current.position
	var centre := current.get_center()
	var middle := bounds.get_center()
	if centre.x > middle.x:
		pos.x = current.end.x - new_size.x
	if centre.y > middle.y:
		pos.y = current.end.y - new_size.y
	pos.x = clampi(pos.x, bounds.position.x, maxi(bounds.position.x, bounds.end.x - new_size.x))
	pos.y = clampi(pos.y, bounds.position.y, maxi(bounds.position.y, bounds.end.y - new_size.y))
	return Rect2i(pos, new_size)


## True when the home window has moved to a different screen than the overlay covers.
func overlay_misplaced(home: Window, overlay: Window) -> bool:
	return DisplayServer.window_get_current_screen(home.get_window_id()) != overlay.current_screen


## True when something fullscreen (a game, a video) covers the screen this window is on.
func is_fullscreen_active(_win: Window) -> bool:
	return false


static func create() -> WindowSource:
	if OS.get_name() == "Linux" and OS.has_environment("HYPRLAND_INSTANCE_SIGNATURE"):
		return HyprlandWindowSource.new()
	# Windows backend: a GDExtension using EnumWindows / DwmGetWindowAttribute (not written yet).
	# Until then the pet just walks on the bottom of the screen.
	return WindowSource.new()
