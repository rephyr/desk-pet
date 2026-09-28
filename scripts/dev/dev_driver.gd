class_name DevDriver
extends Node
## Debug builds: plays a test flow, a small text file with one step per line, like a player would:
##   godot . -- --from=new --play=res://tests/flows/tutorial.flow   (tools/play.py does this)
## Steps (a line starting with #, or " #" and on, is a comment):
##   from <save>           which test save to start from (read by tools/play.py, see DevProfile)
##   flags <--flag ...>    dev flags to start the game with, e.g. flags --autoplay (read by tools/play.py)
##   view full | corner    the full game or the small corner panel
##   tab <id>              show a tab straight away (home, boxes, collection, adventures, ...)
##   page <tab> <n>        flips a tab's page switch (machine | upgrades, adventures | upgrades) to page n
##                         (0 or 1), like a click on it (the spine's tab has the same name as page 0)
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
##   place <id>            opens that place's card on the map, as if you tapped it (like --pick)
##   pull <n> [seconds]    pulls the capsule machine's lever n times (each once the last capsule
##                         has opened; waits 0.6 s after each, or that long)
##   toy <id> [finish] [n] you get that capsule toy (n copies: the rest are spares)
##   fix <node> [levels]   a node on the machine's upgrade tree, for free (data/machine_tree.json)
##   bits <id> <n>         n machine bits (gear, spring, bolt, glass)
##   coins <n>             you have exactly n coins
##   tool <id> [levels]    levels of an errand tool (data/errands.json "tools"), for free
##   next-prize <id>       the next capsule from the machine is this prize (e.g. toy, golden)
##   teach <job>           your pet knows an automation job (data/automation.json), for free
##   task <job | none>     your pet does that automation job (or nothing)
##   auto-tool <id> [n]    levels of an automation tool, for free
##   crank <n>             your pet's own machine gives n capsules right away
##   unlock <id>           opens that unlock id straight away (e.g. feature:packs), no popup
##   spots <job> <n>       n more machines (tables, parties) for a job's workers, for free
##   xp <n>                you have exactly n xp
##   gear <id> [levels]    levels of a gear upgrade (data/gear.json), for free
##   herd <rarity> <finish> <n>  n plain pets straight into the herd (fast: for thousands or millions)
##   room <level>          the room is at that upgrade level (data/herd.json "room")
##   fill-room             plain commons into the herd until the room is exactly full
##   fav <n>               the newest n cards become favourites
##   shelf <rarity>        opens that shelf on the pets tab (collectibles)
##   give-box <id> <n>     n boxes of that kind on your pile, for free
##   boosts                logs every boost kind's total and its parts (data/boosts.json)
##   dress <slot>=<id> ... [finish=<id>]   your active pet gets these parts (and finish), e.g.
##                         dress body=bunny eyes=cyclops finish=holo (for knacks, data/knacks.json)
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
	# flows run quietly, so they don't play over whatever you're doing ("flags --music" to listen)
	AudioServer.set_bus_mute(0, not DevArgs.has("music"))
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
		if line == "" or line.begins_with("from ") or line.begins_with("flags "):
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
		"page":  # page <tab> <n>: the tab's page switch to page n, as a click would
			match w[1]:
				"machine": home.full_game().machine.show_page(int(w[2]))
				"adventures": home.full_game().adventures.show_page(int(w[2]))
				_: return "no page switch on %s" % w[1]
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
		"place":  # place <id>: its card on the map, as if tapped
			if Catalog.shared().location(w[1]).is_empty():
				return "unknown place %s" % w[1]
			home.full_game().show_tab("adventures")
			home.full_game().adventures.pick_place(w[1])
		"pull":  # pull <n> [seconds]: pulls the machine's lever n times, waiting that long after each
			home.full_game().show_tab("machine")
			var stage: MachineTab.MachineStage = home.full_game().machine.stage
			for i in int(w[1]) if w.size() > 1 else 1:
				var waited := 0.0
				while not stage.ready_to_pull() and waited < 5.0:  # the last capsule is still opening
					await get_tree().create_timer(0.05).timeout
					waited += 0.05
				home.full_game().machine.pull()
				await get_tree().create_timer(float(w[2]) if w.size() > 2 else 0.6).timeout
		"toy":  # toy <id> [finish] [n]: you get that toy, n times (the first is the toy, the rest spares)
			for i in int(w[3]) if w.size() > 3 else 1:
				Toys.add(GameState.toys, w[1], w[2] if w.size() > 2 else "normal")
			GameState.toys_changed.emit()
		"fix":  # fix <node> [levels]: that machine tree node, for free (skips the building-up)
			GameState.machine.bought[w[1]] = Machine.owned(GameState.machine, w[1]) + (int(w[2]) if w.size() > 2 else 1)
			GameState._knack_gates_changed()  # like a real fix (no sparkles: machine_upgraded isn't sent)
			GameState.changed.emit()
		"coins":  # coins <n>: you have exactly n coins
			GameState.coins = int(w[1])
			GameState.changed.emit()
		"tool":  # tool <id> [levels]: levels of an errand tool (data/errands.json), for free
			if Jobs.tool(GameState.catalog, w[1]).is_empty():
				return "unknown tool %s" % w[1]
			GameState.set_errand_tool_level(w[1], GameState.errand_tool_level(w[1]) + (int(w[2]) if w.size() > 2 else 1))
		"bits":  # bits <id> <n>: n machine bits of that kind (gear, spring, bolt, glass)
			GameState.grant({ "bit:" + w[1]: int(w[2]) })
		"next-prize":  # next-prize <id>: the next capsule is this prize (data/machine.json)
			GameState.debug_next_prize = w[1]
		"teach":  # teach <job>: your pet knows that automation job, for free
			if Automation.job(GameState.catalog, w[1]).is_empty():
				return "unknown job %s" % w[1]
			GameState.automation.taught[w[1]] = true
			GameState.check_unlocks()
			GameState.automation_changed.emit()
			GameState.changed.emit()
		"task":  # task <job | none>: your pet does that job
			GameState.set_task("" if w[1] == "none" else w[1])
			if w[1] != "none" and GameState.automation.task != w[1]:
				return "your pet doesn't know %s" % w[1]
		"auto-tool":  # auto-tool <id> [levels]: levels of an automation tool, for free
			if Automation.tool(GameState.catalog, w[1]).is_empty():
				return "unknown tool %s" % w[1]
			GameState.automation.tools[w[1]] = Automation.tool_level(GameState.automation, w[1]) + (int(w[2]) if w.size() > 2 else 1)
			GameState.automation_changed.emit()
		"crank":  # crank <n>: your pet's machine gives n capsules now
			GameState._pet_cranks(int(w[1]))
		"unlock":  # unlock <id>: opens it (no popup: what earns it is skipped)
			GameState.unlock(w[1])
		"spots":  # spots <job> <n>: more spots for a job's workers, for free
			GameState.automation.spots[w[1]] = Automation.spots(GameState.automation, w[1]) + int(w[2])
			if w[1] == "adventures":
				while GameState.automation.parties.size() < Automation.spots(GameState.automation, w[1]):
					GameState.automation.parties.append({ "place": "", "n": 0 })
			GameState.automation_changed.emit()
		"xp":  # xp <n>: you have exactly n xp
			GameState.xp = int(w[1])
			GameState.changed.emit()
		"gear":  # gear <id> [levels]: levels of a gear upgrade, for free
			if Gear.info(GameState.catalog, w[1]).is_empty():
				return "unknown gear %s" % w[1]
			GameState.set_gear_level(w[1], GameState.gear_level(w[1]) + (int(w[2]) if w.size() > 2 else 1))
		"herd":  # herd <rarity> <finish> <n>: n plain pets straight into a count
			var key := Herd.key(w[1], w[2])
			if not Herd.valid_key(GameState.catalog, key) or not Herd.plain(GameState.catalog, w[2]):
				return "no plain count %s" % key
			GameState.collection.add_plain(key, int(w[3]))
			GameState.changed.emit()
		"room":  # room <level>: the room's upgrade level
			GameState.room = maxi(0, int(w[1]))
			GameState.changed.emit()
		"fill-room":  # plain commons into the herd until the room is exactly full
			GameState.collection.add_plain(Herd.key(GameState.catalog.tiers[0].id, "normal"), GameState.room_left())
			GameState.changed.emit()
		"fav":  # fav <n>: the newest n cards become favourites
			var cards := GameState.collection.pets
			for i in mini(int(w[1]), cards.size()):
				GameState.collection.set_fav(cards[cards.size() - 1 - i].uid, true)
		"shelf":  # shelf <rarity>: opens that shelf on the pets tab
			home.full_game().show_tab("collection")
			home.full_game().collection.show_mode(0)
			home.full_game().collection.open_shelf(w[1])
		"give-box":  # give-box <id> <n>: boxes on your pile
			if GameState.catalog.box(w[1]).is_empty():
				return "unknown box %s" % w[1]
			GameState.bag[w[1]] = GameState.in_bag(w[1]) + int(w[2])
			GameState.changed.emit()
		"boosts":  # boosts: every boost kind's total and parts, in the log
			for k in Boosts.kinds(GameState.catalog):
				var parts := GameState.boost_parts(k)
				var bits: Array[String] = []
				for p in parts:
					bits.append("%s %s x%.3f" % [p.source, p.id, float(p.x)])
				_write(("boost %s x%.3f %s" % [k, Boosts.total(parts), ", ".join(bits)]).strip_edges())
		"dress":  # dress body=bunny eyes=cyclops finish=holo: your active pet's parts and finish
			var pet := GameState.collection.active()
			if pet == null:
				return "no active pet"
			for pair in w.slice(1):
				var kv := pair.split("=")
				if kv.size() != 2:
					return "dress wants slot=id, not %s" % pair
				if kv[0] == "finish":
					if GameState.catalog.finish(kv[1]).id != kv[1]:
						return "unknown finish %s" % kv[1]
					pet.finish = kv[1]
				elif not kv[0] in Catalog.SLOTS or GameState.catalog.part(kv[0], kv[1]).is_empty():
					return "unknown part %s" % pair
				else:
					pet.parts[kv[0]] = kv[1]
			GameState.collection.pet_changed.emit(pet)
			GameState.collection.active_changed.emit(pet)
			GameState.save_game()
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
