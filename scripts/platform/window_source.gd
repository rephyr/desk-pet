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


## Makes the overlay cover the screen the home window is on.
func place_overlay(home: Window, overlay: Window) -> void:
	var screen := DisplayServer.window_get_current_screen(home.get_window_id())
	overlay.position = DisplayServer.screen_get_position(screen)
	overlay.size = DisplayServer.screen_get_size(screen)


## The mouse cursor in the overlay's local pixels.
func mouse_position(overlay: Window) -> Vector2:
	return Vector2(DisplayServer.mouse_get_position() - overlay.position)


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
