class_name HyprlandWindowSource
extends WindowSource
## Hyprland backend: reads windows from `hyprctl clients -j`.
## Positions come in Hyprland's logical layout coordinates, so everything is mapped
## through where Hyprland placed our overlay.

var _clients: Array = []
var _monitors: Array = []
var _overlay: Window
var _overlay_pending := false
var _visible_workspaces := {}  # workspace id -> true
var _last_poll := -1.0
var _home: Window
var _home_styled := false


func setup(home: Window, overlay: Window) -> void:
	_home = home
	_overlay = overlay
	# The overlay opens later, so a runtime-only rule (gone after a Hyprland reload) can catch it:
	# float above everything on every workspace, no border/shadow/blur/fade, never takes focus.
	_eval("hl.window_rule({ name = 'desk-pets-overlay', match = { title = '%s' }, " % _title_regex(overlay.title)
		+ "float = true, pin = true, no_focus = true, border_size = 0, rounding = 0, no_shadow = true, "
		+ "no_blur = true, no_anim = true, opacity = '1.0 override 1.0 override' })")
	_poll()


## The home window is already open before rules could apply, so style it directly once it shows up.
func _style_home() -> void:
	var c = _find_own(_home)
	if c == null:
		return
	var w := "address:%s" % c.address
	_dispatch("hl.dsp.window.float({ action = 'enable', window = '%s' })" % w)
	_dispatch("hl.dsp.window.pin({ action = 'enable', window = '%s' })" % w)
	for prop in [["border_size", "0"], ["rounding", "0"], ["no_shadow", "1"], ["no_blur", "1"],
			["opacity", "1.0 override 1.0 override"]]:
		_dispatch("hl.dsp.window.set_prop({ window = '%s', prop = '%s', value = '%s' })"
			% [w, prop[0], prop[1]])
	_home_styled = true


## Godot and Hyprland disagree on coordinates with mixed monitor scaling,
## so Hyprland itself moves the overlay onto the home window's monitor.
func place_overlay(_home_win: Window, _overlay_win: Window) -> void:
	_overlay_pending = true
	_last_poll = -1.0
	_poll()


func overlay_misplaced(home: Window, overlay: Window) -> bool:
	_poll()
	var h = _find_own(home)
	var o = _find_own(overlay)
	if h == null or o == null or _overlay_pending:
		return false
	var hm = _monitor_of(h)
	var om = _monitor_of(o)
	return hm != null and om != null and hm.id != om.id


func _try_place_overlay() -> void:
	var h = _find_own(_home)
	var o = _find_own(_overlay)
	if h == null or o == null:
		return  # the overlay is not on screen yet; try again next poll
	var m = _monitor_of(h)
	if m == null:
		return
	var w := "address:%s" % o.address
	var r := _monitor_rect(m)
	# resize first: resizing a floating window keeps its centre, which would undo the move
	_dispatch("hl.dsp.window.resize({ x = %d, y = %d, window = '%s' })" % [r.size.x, r.size.y, w])
	_dispatch("hl.dsp.window.move({ x = %d, y = %d, window = '%s' })" % [r.position.x, r.position.y, w])
	_overlay_pending = false


## The monitor under a window's centre (the client's own "monitor" field lags behind moves).
func _monitor_of(c: Dictionary):
	var centre := Vector2(c.at[0] + c.size[0] / 2.0, c.at[1] + c.size[1] / 2.0)
	for m in _monitors:
		if _monitor_rect(m).has_point(centre):
			return m
	return null


func _monitor_rect(m: Dictionary) -> Rect2i:
	# monitor sizes are in real pixels; window positions are in scaled (logical) units
	return Rect2i(m.x, m.y, roundi(m.width / m.scale), roundi(m.height / m.scale))


func get_windows(overlay: Window) -> Array[Rect2]:
	_poll()
	var result: Array[Rect2] = []
	var me = _find_own(overlay)
	if me == null:
		return result
	var ordered := _clients.filter(func(c): return _is_visible(c) and c != me)
	# hyprctl has no stacking order; floating windows sit above tiled ones,
	# and among floats the most recently focused is on top
	ordered.sort_custom(func(a, b):
		if a.floating != b.floating:
			return a.floating
		return a.focusHistoryID < b.focusHistoryID)
	for c in ordered:
		result.append(_to_local(Rect2(c.at[0], c.at[1], c.size[0], c.size[1]), me, overlay))
	return result


func is_fullscreen_active(win: Window) -> bool:
	_poll()
	var me = _find_own(win)
	if me == null:
		return false
	var mine = _monitor_of(me)
	if mine == null:
		return false
	for c in _clients:
		if not _is_visible(c) or c.fullscreen == 0:
			continue
		var theirs = _monitor_of(c)
		if theirs != null and theirs.id == mine.id:
			return true
	return false


func _poll() -> void:
	# get_windows and is_fullscreen_active share one read per frame
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_poll < 0.05:
		return
	_last_poll = now
	var clients = JSON.parse_string(_run(["clients", "-j"]))
	var monitors = JSON.parse_string(_run(["monitors", "-j"]))
	if typeof(clients) != TYPE_ARRAY or typeof(monitors) != TYPE_ARRAY:
		return
	_clients = clients
	_monitors = monitors
	_visible_workspaces.clear()
	for m in monitors:
		_visible_workspaces[int(m.activeWorkspace.id)] = true
		if m.has("specialWorkspace") and int(m.specialWorkspace.id) != 0:
			_visible_workspaces[int(m.specialWorkspace.id)] = true
	if not _home_styled:
		_style_home()
	if _overlay_pending:
		_try_place_overlay()


func _is_visible(c: Dictionary) -> bool:
	if not c.mapped or c.hidden:
		return false
	return c.pinned or _visible_workspaces.has(int(c.workspace.id))


## Our own window's client entry (debug builds add " (DEBUG)" to the title).
func _find_own(win: Window):
	var pid := OS.get_process_id()
	for c in _clients:
		if int(c.pid) == pid and (c.title == win.title or c.title == win.title + " (DEBUG)"):
			return c
	return null


func _to_local(r: Rect2, me: Dictionary, overlay: Window) -> Rect2:
	# logical size of the overlay vs its real pixel size (differs on scaled monitors)
	var origin := Vector2(me.at[0], me.at[1])
	var scale := Vector2(overlay.size) / Vector2(maxf(1, me.size[0]), maxf(1, me.size[1]))
	return Rect2((r.position - origin) * scale, r.size * scale)


func _run(args: Array) -> String:
	var out := []
	OS.execute("hyprctl", args, out)
	return out[0] if out.size() > 0 else ""


func _eval(lua: String) -> void:
	_run(["eval", lua])


func _dispatch(lua: String) -> void:
	_run(["dispatch", lua])


func _title_regex(title: String) -> String:
	# match the title literally, plus the " (DEBUG)" Godot adds to non-release builds,
	# then escape it for the Lua string literal
	var s := title
	for ch in ["\\", "(", ")", "[", "]", ".", "*", "+", "?", "^", "$", "|"]:
		s = s.replace(ch, "\\" + ch)
	s = "^" + s + "( \\(DEBUG\\))?$"
	return s.replace("\\", "\\\\").replace("'", "\\'")
