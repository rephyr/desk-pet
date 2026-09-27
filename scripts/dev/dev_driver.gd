class_name DevDriver
extends Node
## Debug builds: plays a test flow, a small text file with one step per line, like a player would:
##   godot . -- --from=new --play=res://tests/flows/tutorial.flow   (tools/play.py does this)
## Steps (a line starting with #, or " #" and on, is a comment):
##   from <save>           which test save to start from (read by tools/play.py, see DevProfile)
##   view full | corner    the full game or the small corner panel
##   tab <id>              show a tab straight away (home, boxes, collection, adventures, ...)
##   click <target>        clicks it (see _find, _click): "text", tab:<id>, Class#n, guide
##   key <name>            a key press: space, escape, enter
##   wait <seconds>        or: wait ritual | wait popup | wait text "..." | wait tutorial <step> | wait event
##   expect <what>         tutorial <step> | tab <id> | text "..." | no-text "..." | pile <box> <n>
##                         | fits (the full game fits its window)
##   shot <name>           a screenshot of the game, from inside it (works while it's off-screen)
##   say "<text>"          your pet says it (for testing the bubble)
##   answer                every adventure waiting at an event takes its first choice
##   pets <n>              n more pets from starter boxes (for testing crowds)
##   find <id>             a pet brings home this find (data/unlocks.json), opening what it opens
##   send <place> <n>      the first n spare pets go on an adventure there (and you watch it)
##   quit                  done (it also quits at the end of the file)
## Every step is written to play.log in the profile's folder; a failed step takes a "fail" shot
## and stops the run, and the game quits with 1 (0 when everything passed).

const STEP_PAUSE := 0.35  # seconds after each step, for the UI to catch up
const WAIT_LIMIT := 30.0  # a "wait until" that takes longer than this fails

var _flow := ""
var _log: FileAccess
var _failed := false


func _init(flow_path: String) -> void:
	_flow = flow_path


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DevProfile.folder() + "shots")
	_log = FileAccess.open(DevProfile.folder() + "play.log", FileAccess.WRITE)
	_run.call_deferred()


func _run() -> void:
	await get_tree().create_timer(1.2).timeout  # the window and its layers settle first
	var text := FileAccess.get_file_as_string(_flow)
	if text == "":
		_write("FAIL can't read %s" % _flow)
		_finish()
		return
	var n := 0
	for raw in text.split("\n"):
		n += 1
		# a comment is a whole line starting with #, or " #" and on (PetCard#2 has no space)
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		var comment := RegEx.create_from_string("\\s+#.*$").search(line)
		if comment:
			line = line.substr(0, comment.get_start()).strip_edges()
		if line == "" or line.begins_with("from "):
			continue
		var err: String = await _step(_words(line))
		if err != "":
			_write("FAIL %d: %s  (%s)" % [n, line, err])
			_failed = true
			await _shot("fail")
			break
		_write("ok   %d: %s" % [n, line])
		await get_tree().create_timer(STEP_PAUSE).timeout
	_finish()


func _finish() -> void:
	_write("PASSED" if not _failed else "FAILED")
	_log.close()
	get_tree().quit(1 if _failed else 0)


func _write(line: String) -> void:
	print("[play] ", line)
	_log.store_line(line)
	_log.flush()


## A line as words, "quoted bits" kept together (without the quotes).
static func _words(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string('"([^"]*)"|(\\S+)')
	for m in re.search_all(line):
		out.append(m.get_string(1) if m.get_string(1) != "" or m.get_string(0) == '""' else m.get_string(2))
	return out


## Runs one step. Returns "" when it worked, otherwise what went wrong.
func _step(w: PackedStringArray) -> String:
	var home := get_parent()
	match w[0]:
		"view":
			home.show_full_game(w[1] == "full")
		"tab":
			home.full_game().show_tab(w[1])
		"click":
			var target := _find(w[1])
			if target == null:
				return "nothing to click called %s" % w[1]
			await _click(target)
		"key":
			_key({ "space": KEY_SPACE, "escape": KEY_ESCAPE, "enter": KEY_ENTER }.get(w[1], KEY_SPACE))
		"wait":
			return await _wait(w)
		"expect":
			return _expect(w)
		"shot":
			await _shot(w[1])
		"say":
			PetBubble.say(home, w[1])
		"answer":
			# every adventure waiting at an event takes its first choice
			for run in GameState.runs:
				if run.status == RunState.Status.WAITING:
					var catalog := Catalog.shared()
					GameState.answer_event(run, AdventureRunner.allowed_options(run.current_event(catalog), run.party, catalog.location(run.location_id))[0])
		"pets":
			GameState.debug_give_pets(int(w[1]))
		"find":
			GameState.grant({ "find:" + w[1]: 1 })
		"send":  # send <place> <n>: the first n spare pets go there (the place opens if it wasn't)
			GameState.unlocks["location:" + w[1]] = true
			var going: Array[Pet] = []
			going.assign(GameState.sendable_pets().slice(0, int(w[2])))
			var run := GameState.send_on_adventure(w[1], going)
			if run == null:
				return "couldn't send %d to %s" % [int(w[2]), w[1]]
			home.full_game().show_tab("adventures")
			home.full_game().adventures._show_trail(run)  # go along with it
		"quit":
			_finish()
		_:
			return "unknown step %s" % w[0]
	return ""


func _wait(w: PackedStringArray) -> String:
	if w[1].is_valid_float():
		await get_tree().create_timer(float(w[1])).timeout
		return ""
	var until: Callable
	var limit := WAIT_LIMIT
	match w[1]:
		"ritual":  # no pack being opened any more (the result card may be up)
			until = func(): return not _all(PackOpening).any(func(p): return p.is_visible_in_tree() and p.is_busy())
		"popup":
			until = func(): return _all(UnlockPopup).any(func(p): return p.visible)
		"text":
			until = func(): return _find('"%s"' % w[2]) != null
		"tutorial":
			until = func(): return GameState.tutorial == w[2]
		"event":  # an adventure stopped at an event (trips are slow: this waits longer)
			until = func(): return GameState.runs.any(func(r): return r.status == RunState.Status.WAITING)
			limit = 180.0
		_:
			return "unknown wait %s" % w[1]
	var waited := 0.0
	while not until.call():
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		if waited > limit:
			return "waited %ds" % int(limit)
	return ""


func _expect(w: PackedStringArray) -> String:
	match w[1]:
		"tutorial":
			return "" if GameState.tutorial == w[2] else "tutorial is at %s" % GameState.tutorial
		"tab":
			var tab: String = get_parent().full_game().current_tab()
			return "" if tab == w[2] else "on %s" % tab
		"text":
			return "" if _find('"%s"' % w[2]) != null else "no \"%s\" on screen" % w[2]
		"no-text":
			return "" if _find('"%s"' % w[2]) == null else "\"%s\" is on screen" % w[2]
		"pile":
			var have := GameState.in_bag(w[2])
			return "" if have == int(w[3]) else "%d on the pile" % have
		"fits":
			# nothing on screen needs more room than the window has (it would spill past the edge)
			var game: Control = get_parent().full_game()
			var room := game.get_viewport_rect().size
			var need := game.get_combined_minimum_size()
			return "" if need.x <= room.x + 0.5 and need.y <= room.y + 0.5 else "needs %s, the window is %s" % [need, room]
	return "unknown expect %s" % w[1]


## Finds what to click, among things on screen:
##   guide      whatever the tutorial is pointing at
##   "open 1"   a button or label showing that text (the topmost one); "next treat*" starts with it
##   tab:pets   a tab on the spine, by its id
##   PetCard#2  the 2nd of a kind of control, top-left first
func _find(what: String) -> Control:
	if what == "guide":
		var guides := _all(TutorialGuide)
		return guides[0].current_target() if not guides.is_empty() else null
	var shown := _all(Control).filter(func(c: Control): return c.is_visible_in_tree() and c.get_global_rect().has_area())
	if what.begins_with("tab:"):
		for c in shown:
			if c.is_in_group(Spine.TAB_GROUP) and c.get_meta("tab_id", "") == what.substr(4):
				return c
		return null
	if what.contains("#"):
		var bits := what.split("#")
		var kind := shown.filter(func(c): return c.get_script() and c.get_script().get_global_name() == bits[0])
		kind.sort_custom(func(a: Control, b: Control):
			var pa := a.get_global_rect().position
			var pb := b.get_global_rect().position
			return pa.y < pb.y - 4.0 or (absf(pa.y - pb.y) <= 4.0 and pa.x < pb.x))
		var i := int(bits[1]) - 1
		return kind[i] if i >= 0 and i < kind.size() else null
	var text := what.trim_prefix('"').trim_suffix('"').to_lower()
	var starts := text.ends_with("*")  # "next treat in*": text that starts with this
	text = text.trim_suffix("*")
	var found: Control = null
	for c in shown:
		var t := str(c.text).strip_edges().to_lower() if (c is Button or c is Label) else ""
		if (c is Button or c is Label) and (t.begins_with(text) if starts else t == text):
			found = c  # later in the tree is drawn on top
	return found


## A click on `target`: a button is pressed like a player would (toggles toggle), anything else
## gets a left click at its middle through its own input (the way PetCard, piles and notes listen).
## Straight to the control, so it works however the window is scaled or wherever it's parked.
func _click(target: Control) -> void:
	# a label inside a button (two-line buttons): the button is what gets clicked
	var up: Node = target
	while up is Control and not up is BaseButton and (up as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE:
		up = up.get_parent()
	if up is BaseButton:
		target = up
	# a holder (a tilted sticker) with a button inside: that button is what gets clicked
	if not target is BaseButton:
		var at := target.get_global_rect().get_center()
		for b in _all(BaseButton):
			if target.is_ancestor_of(b) and b.is_visible_in_tree() and b.get_global_rect().has_point(at):
				target = b
				break
	if target is BaseButton:
		if target.disabled:
			return
		if target.toggle_mode:
			target.button_pressed = not target.button_pressed
		target.pressed.emit()
		return
	# a marker that ignores the mouse (the map's places): the click goes to whatever holds it
	var receiver := target
	while receiver.mouse_filter == Control.MOUSE_FILTER_IGNORE and receiver.get_parent() is Control:
		receiver = receiver.get_parent()
	var at := target.get_global_rect().get_center()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = receiver.get_global_transform().affine_inverse() * at
		e.global_position = at
		if receiver.has_method("_gui_input"):
			receiver._gui_input(e)
		receiver.gui_input.emit(e)
		await get_tree().process_frame


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		get_viewport().push_input(e)
		await get_tree().process_frame


## The game's own picture, saved as shots/<name>.png in the profile's folder.
func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := DevProfile.folder() + "shots/%s.png" % shot_name.validate_filename()
	img.save_png(path)
	_write("shot %s" % path)


## Every node in the scene of a kind (a class_name script or a built-in class).
func _all(kind) -> Array:
	var out := []
	var stack: Array[Node] = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if is_instance_of(n, kind):
			out.append(n)
		stack.append_array(n.get_children())
	return out
