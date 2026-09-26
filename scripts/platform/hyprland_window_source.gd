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
var _styled := {}  # window address -> true once styled
var _zero_scaling := false  # XWayland windows get real pixels on scaled monitors


func setup(home: Window, overlay: Window) -> void:
	_home = home
	_overlay = overlay
	var option = JSON.parse_string(_run(["getoption", "xwayland:force_zero_scaling", "-j"]))
	_zero_scaling = typeof(option) == TYPE_DICTIONARY and (option.get("int", 0) == 1 or option.get("bool", false) == true)
	_poll()


## Godot runs through XWayland here. With force_zero_scaling it gets real pixels, so the UI has
## to scale itself up by the monitor's scale; without it Hyprland scales the window for us.
func ui_scale(home: Window) -> float:
	if not _zero_scaling:
		return 1.0
	_poll()
	var h = _find_own(home)
	var m = _monitor_of(h) if h != null else null
	return float(m.scale) if m != null else 1.0


func set_home_size(home: Window, logical_size: Vector2i) -> void:
	_poll(true)
	var h = _find_own(home)
	var m = _monitor_of(h) if h != null else null
	if m == null:
		super(home, logical_size)
		return
	var target := anchored_rect(Rect2i(h.at[0], h.at[1], h.size[0], h.size[1]), _usable_rect(m), logical_size)
	# only Hyprland moves it: Godot's own resize also sends a position, in the wrong coordinates
	var w := "address:%s" % h.address
	_dispatch("hl.dsp.window.resize({ x = %d, y = %d, window = '%s' })" % [target.size.x, target.size.y, w])
	_dispatch("hl.dsp.window.move({ x = %d, y = %d, window = '%s' })" % [target.position.x, target.position.y, w])
	_raise(w)


## Styles our windows once each time they appear (window rules can't catch them: Godot sets
## the title after the window opens). Float on every workspace above everything, with no
## border, shadow, blur or fade. The overlay also never takes focus.
func _style_new_windows() -> void:
	for win in [_home, _overlay]:
		var c = _find_own(win)
		if c == null or _styled.has(c.address):
			continue
		_styled[c.address] = true
		var w := "address:%s" % c.address
		_dispatch("hl.dsp.window.float({ action = 'enable', window = '%s' })" % w)
		_dispatch("hl.dsp.window.pin({ action = 'enable', window = '%s' })" % w)
		# the override flags stop your "fade unfocused windows" setting from applying to us
		var props := [["border_size", "0"], ["rounding", "0"], ["no_shadow", "1"], ["no_blur", "1"],
			["no_anim", "1"], ["opacity", "1"], ["opacity_override", "1"], ["opacity_inactive", "1"],
			["opacity_inactive_override", "1"]]
		if win == _overlay:
			props.append(["no_focus", "1"])
		for prop in props:
			_dispatch("hl.dsp.window.set_prop({ window = '%s', prop = '%s', value = '%s' })"
				% [w, prop[0], prop[1]])
		_raise(w)


## Pinned windows can end up drawn under tiled ones; this puts ours back on top.
func _raise(window: String) -> void:
	_dispatch("hl.dsp.window.alter_zorder({ mode = 'top', window = '%s' })" % window)


## Godot and Hyprland disagree on coordinates with mixed monitor scaling,
## so Hyprland itself moves the overlay onto the home window's monitor.
func place_overlay(_home_win: Window, _overlay_win: Window) -> void:
	_overlay_pending = true
	_poll(true)


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
	_raise(w)
	_overlay_pending = false


## The monitor under a window's centre, or the nearest one if it's off-screen
## (the client's own "monitor" field lags behind moves).
func _monitor_of(c: Dictionary):
	var centre := Vector2(c.at[0] + c.size[0] / 2.0, c.at[1] + c.size[1] / 2.0)
	var nearest = null
	var best := INF
	for m in _monitors:
		var r := Rect2(_monitor_rect(m))
		if r.has_point(centre):
			return m
		var d := centre.distance_to(centre.clamp(r.position, r.end))
		if d < best:
			best = d
			nearest = m
	return nearest


## The monitor minus bars and other reserved space.
func _usable_rect(m: Dictionary) -> Rect2i:
	var r := _monitor_rect(m)
	var reserved: Array = m.get("reserved", [0, 0, 0, 0])  # left, top, right, bottom
	return Rect2i(r.position.x + reserved[0], r.position.y + reserved[1],
		r.size.x - reserved[0] - reserved[2], r.size.y - reserved[1] - reserved[3])


func _monitor_rect(m: Dictionary) -> Rect2i:
	# monitor sizes are in real pixels before rotation; window positions are in scaled (logical) units
	var size: Vector2 = Vector2(m.width, m.height) / m.scale
	if int(m.get("transform", 0)) % 2 == 1:  # rotated 90 or 270 degrees
		size = Vector2(size.y, size.x)
	return Rect2i(Vector2i(m.x, m.y), Vector2i(size.round()))


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


func _poll(force := false) -> void:
	# get_windows and is_fullscreen_active share one read per frame
	var now := Time.get_ticks_msec() / 1000.0
	if not force and now - _last_poll < 0.05:
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
	_style_new_windows()
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


func _dispatch(lua: String) -> void:
	_run(["dispatch", lua])
