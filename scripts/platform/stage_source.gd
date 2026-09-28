class_name StageSource
extends WindowSource
## A pretend desktop for testing the desktop pet inside the game window (DeskStage, tests):
## windows and the home window are just rectangles, in the stage's pixels.

var windows: Array[Rect2] = []  # front-most first; the home rect is added in front of them
var home := Rect2()


func get_windows(_overlay: Window) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if home.has_area():
		out.append(home)
	out.append_array(windows)
	return out


func home_rect(_home: Window, _overlay: Window) -> Rect2:
	return home
