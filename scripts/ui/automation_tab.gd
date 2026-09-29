class_name AutomationTab
extends VBoxContainer
## Automation: your pet does one job for you (data/automation.json, Automation, GameState's
## automation part). A card per job that's there yet: crank its own little machine, run
## adventures, open boxes. Your pet sits in the card of the job it's doing; the others say "nobody
## here". Tap a card to see it on the side card: teach it (coins), move your pet there or take it
## off, the party (adventures) and the job's tools. Moving your pet stops the job it left: the tab
## never explains that, the pet just says so.
## Once your pet has taught the others a job, a second page appears: WORKERS. A card per job with
## its machines (tables, parties) and the pets working them; the side card buys more, puts resting
## pets on or takes them off, sets each party's place and size, and holds the workers' tools.
## Once a pet brings the whistle home, a third page: THE WHISTLE (managing the workers is your pet's
## one job). A clipboard with a to-do row per job taught to the others: how many are home and still
## out there, a tiny crowd, and two ticks (haul them home / start new ones, keep them full). The side
## card moves your pet there, sets the coins set aside (− / +) and holds the whistle's tools.
## Once the school is open (past the edge), a school page too: SCHOOL (SchoolView), classes of spare
## herd pets that make every worker quicker. A "pets a minute" pill shows once box workers exist.
## Design: design/mockups/screens/automation.html (C: cards, and ?page=workers),
## design/mockups/screens/automation-layers.html (look A: the to-do list), past-the-edge.html look A
## (the school).

const SIDE_WIDTH := 236
const CARD_WIDTH := 172  # three cards and the side card fit the window

var _where := Label.new()
var _where_pet := PetPortrait.new(1, false)
var _cards := HBoxContainer.new()
var _card := VBoxContainer.new()
var _picked := ""
var _dirty := true
var _last := ""
var _scenes := {}  # job id -> JobScene, for the capsules popping out of your pet's machine
var _page := "pet"  # pet (your pet), workers, whistle or school
var _pages: Array[String] = ["pet"]  # the pages there are now, in the switch's order
var _shown := "pet"  # the page the switch shows picked (an unlock's show me can move _page under it)
var _mode: PanelContainer  # the your pet | workers | whistle | school switch (there once there's a second page)
var _bar := HBoxContainer.new()
var _body := HBoxContainer.new()
var _pill := PanelContainer.new()  # where your pet is / how many workers
var _pace := PanelContainer.new()  # pets a minute (once box workers exist)
var _pace_n := UiTheme.title("", 15, UiTheme.TEXT)
var _pace_face := PetPortrait.new(1, false)
var school_view := SchoolView.new()

const PAGE_NAMES := { "pet": "your pet", "workers": "workers", "whistle": "whistle", "school": "school" }
const PAGE_LINES := { "pet": "automation", "workers": "automation_workers", "whistle": "automation_whistle" }


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL

	_bar.add_theme_constant_override("separation", 8)
	_mode = _switch()
	_bar.add_child(_mode)
	_bar.add_child(UiTheme.spacer())
	# pets a minute: a face, the number, the words
	var psb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 999, 2, 3)
	psb.content_margin_left = 6
	psb.content_margin_right = 12
	_pace.add_theme_stylebox_override("panel", psb)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	prow.add_child(_pace_face)
	_pace_n.size_flags_vertical = SIZE_SHRINK_CENTER
	prow.add_child(_pace_n)
	var words := UiTheme.label("pets a minute", UiTheme.MUTED, UiTheme.SMALL)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	prow.add_child(words)
	_pace.add_child(prow)
	_pace.visible = false
	_bar.add_child(_pace)
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 999, 2, 3)
	sb.content_margin_left = 6
	sb.content_margin_right = 12
	_pill.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_where_pet)
	_where.add_theme_font_size_override("font_size", UiTheme.SMALL)
	_where.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_where)
	_pill.add_child(row)
	_bar.add_child(_pill)
	add_child(_bar)

	_body.add_theme_constant_override("separation", 14)
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(_body)
	school_view.visible = false
	add_child(school_view)
	_cards.add_theme_constant_override("separation", 12)
	_cards.size_flags_horizontal = SIZE_EXPAND_FILL
	_cards.alignment = BoxContainer.ALIGNMENT_BEGIN
	_body.add_child(_cards)
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	side.clip_contents = true
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	_card.add_theme_constant_override("separation", 8)
	side.add_child(_card)
	_body.add_child(side)

	GameState.changed.connect(func(): _dirty = true)
	GameState.automation_changed.connect(func(): _dirty = true)
	GameState.unlocked.connect(func(_e): _dirty = true)
	GameState.dungeon_changed.connect(func(): _dirty = true)  # the army's job card says where it is
	GameState.collection.active_changed.connect(func(_p): _dirty = true)
	GameState.pet_cranked.connect(_on_cranked)
	GameState.school_changed.connect(func(): _dirty = true)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_dirty = true
			speak()
		elif _page == "whistle":
			GameState.whistle_seen())


## An unlock popup's "show me" brought you here (`opens` is what the unlock opened): the
## whistle's and the school's land on their page.
func show_unlock(opens: Array) -> void:
	var page := ""
	if ("feature:" + Automation.WHISTLE) in opens:
		page = Automation.WHISTLE
	elif "feature:school" in opens:
		page = "school"
	if page != "":
		_page = page
		_dirty = true
		speak()


## The your pet | workers | whistle | school switch for the pages there are now.
func _switch() -> PanelContainer:
	var names := _pages.map(func(p): return PAGE_NAMES[p])
	_shown = _page
	var seg := UiTheme.segmented(names, maxi(0, _pages.find(_page)), func(i): _on_page(_pages[i]))
	var w := _pages.find("whistle")
	if w >= 0:
		var wb: Button = seg.get_child(0).get_child(w)
		wb.icon = UiTheme.icon("whistle", 15, UiTheme.PINK)
		wb.add_theme_constant_override("h_separation", 5)
	# the school's button has its little house
	var i := _pages.find("school")
	if i >= 0:
		var b: Button = seg.get_child(0).get_child(i)
		b.icon = UiTheme.icon("school", 14, UiTheme.MUTED)
		b.add_theme_constant_override("icon_max_width", 14)
	seg.visible = _pages.size() > 1
	return seg


## Switches to a page (pet, workers, whistle, school), as a tap on the switch would.
func show_page(page: String) -> void:
	var i := _pages.find(page)
	if i >= 0:
		(_mode.get_child(0).get_child(i) as Button).pressed.emit()


func _on_page(page: String) -> void:
	if _page == "whistle" and page != "whistle":
		GameState.whistle_seen()
	_page = page
	_shown = page
	_dirty = true
	PetBubble.say_line(self, SchoolView.line_key() if page == "school" else str(PAGE_LINES.get(page, "automation")))


## Rebuilds the switch when a page turns up (workers, the school) or goes.
func _refresh_pages() -> void:
	var pages: Array[String] = ["pet"]
	var workers := GameState.worker_jobs()
	if not workers.is_empty():
		pages.append("workers")
		if GameState.feature_on(Automation.WHISTLE):
			pages.append("whistle")
	if GameState.school_open():
		pages.append("school")
	if not _page in pages:
		_page = "pet"
	if pages == _pages and _shown == _page and _mode.get_child(0).get_child_count() == pages.size():
		_mode.visible = pages.size() > 1
		return
	_pages = pages
	var at := _mode.get_index()
	_mode.queue_free()
	_bar.remove_child(_mode)
	_mode = _switch()
	_bar.add_child(_mode)
	_bar.move_child(_mode, at)


func speak() -> void:
	if _page == "school":
		PetBubble.say_line(self, SchoolView.line_key())
	elif _page == "whistle":
		PetBubble.say_line(self, "automation_whistle")
	elif GameState.automation.task == "" and not GameState.automation.taught.is_empty():
		PetBubble.say_line(self, "automation_free")
	else:
		PetBubble.say_line(self, "automation")


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_pace()
	if not _dirty:
		return
	_dirty = false
	_refresh_pages()
	_body.visible = _page != "school"
	school_view.visible = _page == "school"
	_pill.visible = _page != "school"
	if _page == "school":
		_last = ""
		return
	# coins tick up every few seconds: only rebuild when something you'd see changed
	var jobs := GameState.auto_jobs()
	var afford := ""
	for j in jobs:
		afford += "1" if GameState.coins >= int(j.coins) else "0"
	for t in Automation.all_tools(GameState.catalog):
		afford += "1" if GameState.coins >= GameState.auto_tool_cost(t.id) else "0"
	var run := GameState.auto_run()
	var key := "%s|%s|%s|%s|%s|%s" % [str(GameState.automation.taught), str(GameState.automation.tools), GameState.automation.task,
		str(GameState.auto_party()), _picked, afford]
	var pet := GameState.collection.active()
	key += "|%d|%s|%s|%s" % [jobs.size(), run.location_id if run else "", str(GameState.can_auto_open()), pet.display_name(GameState.catalog) if pet else ""]
	if not GameState.can_auto_open():  # the box job then shows the pile count (or the squish)
		key += "|%d|%s" % [GameState.boxes_on_pile(), str(GameState.room_is_full())]
	key += "|%s|%d" % [str(GameState.dungeon.run.get("target", -1)), int(GameState.army().sent)]  # the army's job card
	# the workers page: what's taught, bought and who's on it, and what you can afford there
	var a: Dictionary = GameState.automation
	key += "|%s|%s|%s|%s|%s|%s|%s" % [_page, str(a.others), str(a.spots), str(a.parties), str(a.workers), str(a.get("wherd", {})), str(a.get("wjoin", {}))]
	if _page == "workers" or _page == "whistle":  # changes every time a box worker opens a box: only the workers pages show it
		key += "|%d" % GameState.resting_count()
	key += "|%s|%s|%d|%d" % [str(a.get("whistle", {}).get("ticks", {})), str(a.get("whistle", {}).get("keep", -1)),
		GameState.party_places().size(), GameState.open_pages().size()]
	if _page == "whistle":
		key += "|%s" % str(GameState.whistle_since)
	for j in jobs:
		key += "1" if GameState.coins >= GameState.teach_others_cost(j.id) else "0"
		key += "1" if GameState.coins >= int(GameState.spot_plan(j.id, 1)[1]) else "0"
	if key == _last:
		return
	_last = key
	_rebuild()


## The pets a minute pill (while box workers have boxes to open and room for the pets; a pet a box).
func _refresh_pace() -> void:
	var per := GameState.pets_a_minute()
	_pace.visible = per > 0.0
	if per > 0.0:
		var text := UiTheme.num(per) if per >= 10.0 else str(snappedf(per, 0.1))
		if _pace_n.text != text:
			_pace_n.text = text
		if _pace_face.view.pet == null:
			var faces := GameState.worker_faces("boxes", 1)
			_pace_face.set_pet(GameState.collection.get_pet(str(faces[0])) if not faces.is_empty() else GameState.collection.active())


# ---- doing things ------------------------------------------------------------------

func pick(id: String) -> void:
	if _picked == id:
		return
	_picked = id
	_dirty = true


func _teach(id: String) -> void:
	if not GameState.teach_job(id):
		PetBubble.say_line(self, "automation_poor")
		return
	Sfx.play(self, Sfx.sound("machine", "prize"), 2.0)
	PetBubble.say_line(self, "automation_do_" + id if GameState.automation.task == id else "automation_teach")


func _move(id: String) -> void:
	var from := str(GameState.automation.task)
	GameState.set_task(id)
	if id == "":
		PetBubble.say_line(self, "automation_free")
		return
	# it says what it stopped doing, then what it's doing now
	var stop := PetBubble.line("automation_stop_" + from) + " " if from != "" else ""
	PetBubble.say(self, stop + PetBubble.line("automation_do_" + id))


func _buy_tool(id: String) -> void:
	if GameState.auto_tool_block(id) != "":
		return
	if not GameState.buy_auto_tool(id):
		PetBubble.say_line(self, "automation_poor")
		return
	Sfx.play(self, Sfx.sound("machine", "prize"), 2.0)
	var key := "automation_tool_" + id
	PetBubble.say_line(self, key if Catalog.shared().voice.get("ui", {}).has(key) else "automation_tool")


func _change_party(step_place: int, step_n: int) -> void:
	var party := GameState.auto_party()
	var places := GameState.auto_places()
	var i := maxi(0, places.find(GameState.catalog.location(str(party.place))))
	var place := str(places[wrapi(i + step_place, 0, places.size())].id) if not places.is_empty() else ""
	GameState.set_auto_party(place, int(party.n) + step_n)
	var now := GameState.auto_party()
	if step_place != 0:
		PetBubble.say_line(self, "automation_party", { "place": GameState.catalog.location(str(now.place)).get("name", ""), "count": now.n })


## Your pet's machine gave a capsule: it pops out of the machine on its card.
func _on_cranked(result: Dictionary) -> void:
	if not is_visible_in_tree() or not _scenes.has("machine"):
		return
	var loot: Dictionary = result.get("loot", {})
	var text := ""
	var color := UiTheme.CYAN
	if loot.has("coins"):
		text = "+" + UiTheme.num(int(loot.coins))
	if not result.get("toy", {}).is_empty():
		text = "a toy!"
		color = UiTheme.PINK
		PetBubble.say_line(self, "automation_cranked_toy")
	elif Rewards.total(loot, "box") > 0:
		text = "a box!"
		color = UiTheme.GOLD
		PetBubble.say_line(self, "automation_cranked_box")
	if result.get("shiny", false):
		color = UiTheme.GOLD
	(_scenes.machine as JobScene).pop(text, color)


# ---- building it ------------------------------------------------------------------

static func color_of(job: Dictionary) -> Color:
	return UiTheme.named_color(str(job.get("color", "")))


static func doing(task: String) -> String:
	match task:
		"machine": return "cranking"
		"adventures": return "on adventures"
		"boxes": return "opening boxes"
		Automation.WHISTLE: return "managing"
		"army": return "leading the army"
	return "free"


func _rebuild() -> void:
	var catalog := GameState.catalog
	var pet := GameState.collection.active()
	var who := pet.display_name(catalog) if pet else "your pet"
	var workers := GameState.worker_jobs()
	_where_pet.visible = _page != "workers"
	_where_pet.set_pet(pet)
	_where.text = "%s is %s" % [who, doing(str(GameState.automation.task))]
	UiTheme.clear(_cards)
	_scenes.clear()
	if _page == "workers":
		var total := 0
		for j in workers:
			total += GameState.workers_count(j.id)
		_where.text = "%s %s" % [UiTheme.num(total), "worker" if total == 1 else "workers"]
		_rebuild_workers(workers)
		return
	if _page == "whistle":
		_rebuild_whistle(workers, pet, who)
		return
	var jobs := GameState.auto_jobs()
	if jobs.is_empty():
		return
	if not jobs.any(func(j): return j.id == _picked):
		var task := str(GameState.automation.task)
		_picked = task if jobs.any(func(j): return j.id == task) else str(jobs[0].id)
	for j in jobs:
		var card := JobCard.new(j, j.id == _picked, self)
		_scenes[j.id] = card.scene
		_cards.add_child(card)
	_rebuild_side(Automation.job(catalog, _picked), pet, who)


## What a job's card says under its picture.
static func rate_line(job: Dictionary) -> String:
	var catalog := GameState.catalog
	var task := str(GameState.automation.task)
	if not GameState.knows_job(job.id):
		return str(job.brings)
	if task != job.id:
		return "nobody here"
	match str(job.id):
		"machine":
			return "a pull every %ds" % roundi(Automation.crank_seconds(catalog, GameState.automation) / GameState.boost("automation"))
		"adventures":
			var run := GameState.auto_run()
			var party := GameState.auto_party()
			var place := catalog.location(str(run.location_id if run else party.place))
			var n: int = run.party.setting_out() if run else int(party.n)
			return "%d %s to %s" % [n, "pet" if n == 1 else "pets", place.get("name", "somewhere")]
		"boxes":
			if GameState.can_auto_open():
				return "opening your pile"
			var boxes := GameState.boxes_on_pile()
			if boxes <= 0:
				return "the pile is empty"
			var pile := "a box on your pile" if boxes == 1 else "%s boxes on your pile" % UiTheme.num(boxes)
			return "squish! " + pile if GameState.room_is_full() else pile
		"army":
			if GameState.dungeon_running() and GameState.dungeon.run.has("room"):
				return "in %s" % str(GameState.sew_room(int(GameState.dungeon.run.room)).name)
			if GameState.dungeon_running():
				return "down to floor %d" % int(GameState.dungeon.run.get("target", GameState.dungeon.target))
			return "waiting by the well" if int(GameState.army().sent) == 0 else "back up the rope"
	return ""


func _rebuild_side(job: Dictionary, pet: Pet, who: String) -> void:
	UiTheme.clear(_card)
	var color := color_of(job)
	var id := str(job.id)
	var here := str(GameState.automation.task) == id
	var knows := GameState.knows_job(id)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(str(job.icon), 22, color))
	var name_label := UiTheme.title(str(job.name), 17, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(name_label)
	_card.add_child(head)
	_card.add_child(ErrandToolsView._wrapped(str(job.what), UiTheme.MUTED, UiTheme.SMALL + 1))

	# your pet: teach it, move it here, or take it off
	var you := PanelContainer.new()
	you.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if here else UiTheme.LINE, 10, 2, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	you.add_child(col)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var portrait := PetPortrait.new(2, false)
	portrait.set_pet(pet)
	line.add_child(portrait)
	var words := "teach %s" % who
	if knows:
		words = "%s is here ♡\n%s" % [who, rate_line(job)] if here else "nobody here"
	var words_label := ErrandToolsView._wrapped(words, UiTheme.TEXT, UiTheme.SMALL + 1)
	words_label.size_flags_horizontal = SIZE_EXPAND_FILL
	words_label.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(words_label)
	col.add_child(line)
	var button: Button
	if not knows:
		button = UiTheme.button("teach for %s" % UiTheme.num(int(job.coins)), func(): _teach(id))
		button.icon = UiTheme.icon("coin", 14, UiTheme.CYAN)
		button.disabled = GameState.coins < int(job.coins)
	elif here:
		button = UiTheme.button("take it off", func(): _move(""))
	else:
		button = UiTheme.button("move it here", func(): _move(id))
	if not here:
		button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6))
	col.add_child(button)
	_card.add_child(you)

	if id == "adventures" and knows:
		_card.add_child(_party_row())
	var tools := Automation.all_tools(GameState.catalog).filter(func(t): return t.job == id and not t.workers)
	var teach := GameState.teach_others_block(id) == ""
	if knows and (not tools.is_empty() or teach):
		_card.add_child(UiTheme.title("upgrades", 13, UiTheme.LILAC))
		for t in tools:
			_card.add_child(ToolRow.new(t, color, self))
		if teach:
			_card.add_child(ToolRow.teach(id, color, self))


## Where the adventures job's party goes and how many: ‹ place › and − n + (no dropdowns: their
## popups open behind the always-on-top window).
func _party_row() -> Control:
	var party := GameState.auto_party()
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 6))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	box.add_child(col)
	var place_row := HBoxContainer.new()
	place_row.add_child(UiTheme.small_button("‹", func(): _change_party(-1, 0)))
	var place := UiTheme.label(str(GameState.catalog.location(str(party.place)).get("name", "")), UiTheme.TEXT, UiTheme.SMALL + 1)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.size_flags_horizontal = SIZE_EXPAND_FILL
	place.clip_text = true
	place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place.custom_minimum_size = Vector2(40, 0)
	place_row.add_child(place)
	place_row.add_child(UiTheme.small_button("›", func(): _change_party(1, 0)))
	col.add_child(place_row)
	var n_row := HBoxContainer.new()
	n_row.add_child(UiTheme.small_button("−", func(): _change_party(0, -1)))
	var n := UiTheme.label("%d %s" % [int(party.n), "pet" if int(party.n) == 1 else "pets"], UiTheme.MINT, UiTheme.SMALL + 1)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	n_row.add_child(n)
	n_row.add_child(UiTheme.small_button("+", func(): _change_party(0, 1)))
	col.add_child(n_row)
	return box


# ---- the workers page -----------------------------------------------------------------

func _teach_others(id: String) -> void:
	if not GameState.teach_others(id):
		PetBubble.say_line(self, "automation_poor")
		return
	Sfx.play(self, Sfx.sound("machine", "jackpot"), -3.0)
	PetBubble.say_line(self, "automation_teach_others")


func _buy_spot(id: String) -> void:
	if GameState.buy_spots(id, 1) <= 0:
		PetBubble.say_line(self, "automation_poor")
		return
	Sfx.play(self, Sfx.sound("machine", "prize"), 2.0)
	PetBubble.say_line(self, "automation_spot", { "spot": Automation.job(GameState.catalog, id).get("spot", {}).get("name", "spot") })


func _put_workers(id: String, count: int) -> void:
	if Automation.spots(GameState.automation, id) <= GameState.workers_count(id):
		PetBubble.say_line(self, "automation_workers_full", { "spots": Automation.job(GameState.catalog, id).get("spot", {}).get("names", "spots") })
		return
	if GameState.put_workers(id, count) <= 0:
		PetBubble.say_line(self, "automation_workers_nobody")
		return
	PetBubble.say_line(self, "automation_workers_on")


func _take_off_workers(id: String, count: int) -> void:
	if GameState.take_off_workers(id, count) > 0:
		PetBubble.say_line(self, "automation_workers_off")


func _change_worker_party(slot: int, step_place: int, step_n: int) -> void:
	var party := GameState.auto_party(slot)
	var places := GameState.auto_places()
	var i := maxi(0, places.find(GameState.catalog.location(str(party.place))))
	var place := str(places[wrapi(i + step_place, 0, places.size())].id) if not places.is_empty() else ""
	GameState.set_auto_party(place, int(party.n) + step_n, slot)


func _rebuild_workers(jobs: Array[Dictionary]) -> void:
	if not jobs.any(func(j): return j.id == _picked):
		_picked = str(jobs[0].id)
	for j in jobs:
		_cards.add_child(WorkerCard.new(j, j.id == _picked, self))
	_rebuild_worker_side(Automation.job(GameState.catalog, _picked))


## How a job's spots read: "3 machines", "1 party".
static func spots_words(job: Dictionary, n: int) -> String:
	var spot: Dictionary = job.get("spot", {})
	return "%s %s" % [UiTheme.num(n), spot.get("name", "spot") if n == 1 else spot.get("names", "spots")]


func _rebuild_worker_side(job: Dictionary) -> void:
	UiTheme.clear(_card)
	var id := str(job.id)
	var color := color_of(job)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(str(job.icon), 22, color))
	var name_label := UiTheme.title(str(job.name), 17, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(name_label)
	_card.add_child(head)

	var spots := Automation.spots(GameState.automation, id)
	var working := GameState.workers_count(id)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	var counts := GridContainer.new()
	counts.columns = 2
	counts.add_theme_constant_override("h_separation", 10)
	ErrandToolsView._add_row(counts, str(job.spot.get("names", "spots")), UiTheme.num(spots), UiTheme.TEXT)
	ErrandToolsView._add_row(counts, "working", UiTheme.num(working), color if working > 0 else UiTheme.MUTED)
	ErrandToolsView._add_row(counts, "resting pets", UiTheme.num(GameState.resting_count()), UiTheme.MUTED)
	col.add_child(counts)
	var plan := GameState.spot_plan(id, 1)
	if int(plan[0]) > 0:  # none left out there: the button is simply gone
		var buy := UiTheme.button("+1 %s for %s" % [job.spot.get("name", "spot"), UiTheme.num(int(plan[1]))], func(): _buy_spot(id))
		buy.icon = UiTheme.icon("coin", 14, UiTheme.CYAN)
		buy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buy.custom_minimum_size = Vector2(60, 0)
		buy.disabled = GameState.coins < int(plan[1])
		buy.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6))
		col.add_child(buy)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var off := UiTheme.small_button("−", func(): _take_off_workers(id, 1))
	off.disabled = working == 0
	row.add_child(off)
	var on := UiTheme.small_button("+", func(): _put_workers(id, 1))
	on.disabled = working >= spots
	row.add_child(on)
	var fill := UiTheme.small_button("fill up", func(): _put_workers(id, -1))
	fill.disabled = working >= spots
	fill.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(fill)
	col.add_child(row)
	if id != "adventures" and GameState.spare_count() > ErrandsTab.STEPS_AFTER:  # busy paws: new pets start here
		col.add_child(ErrandsTab.join_switch(GameState.worker_joins(id), func(on):
			GameState.set_worker_join(id, on)
			PetBubble.say_line(self, "join_on" if on else "join_off")))
	_card.add_child(box)

	if id == "adventures" and spots > 0:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		var list := VBoxContainer.new()
		list.add_theme_constant_override("separation", 4)
		list.size_flags_horizontal = SIZE_EXPAND_FILL
		scroll.add_child(list)
		var leaders := GameState.workers_of(id)
		for slot in spots:
			list.add_child(_worker_party_row(slot, str(leaders[slot]) if slot < leaders.size() else ""))
		_card.add_child(scroll)
	var tools := Automation.all_tools(GameState.catalog).filter(func(t): return t.job == id and t.workers)
	if not tools.is_empty():
		_card.add_child(UiTheme.title("upgrades", 13, UiTheme.LILAC))
		for t in tools:
			_card.add_child(ToolRow.new(t, color, self))


## One of the workers' parties: who leads it (nobody: it waits), where it goes, how many go.
func _worker_party_row(slot: int, leader: String) -> Control:
	var party := GameState.auto_party(slot)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 4))
	if leader == "":
		panel.modulate.a = 0.55
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	col.add_child(row)
	var portrait := PetPortrait.new(1, false)
	portrait.set_pet(GameState.collection.get_pet(leader) if leader != "" else null)
	portrait.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(portrait)
	row.add_child(UiTheme.small_button("‹", func(): _change_worker_party(slot, -1, 0)))
	var place := UiTheme.label(str(GameState.catalog.location(str(party.place)).get("name", "")), UiTheme.TEXT, UiTheme.SMALL)
	place.size_flags_horizontal = SIZE_EXPAND_FILL
	place.clip_text = true
	place.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place.custom_minimum_size = Vector2(30, 0)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(place)
	row.add_child(UiTheme.small_button("›", func(): _change_worker_party(slot, 1, 0)))
	var n_row := HBoxContainer.new()
	n_row.add_theme_constant_override("separation", 2)
	n_row.alignment = BoxContainer.ALIGNMENT_CENTER
	n_row.add_child(UiTheme.small_button("−", func(): _change_worker_party(slot, 0, -1)))
	n_row.add_child(UiTheme.label("%d %s" % [int(party.n), "pet" if int(party.n) == 1 else "pets"], UiTheme.MINT, UiTheme.SMALL))
	n_row.add_child(UiTheme.small_button("+", func(): _change_worker_party(slot, 0, 1)))
	col.add_child(n_row)
	return panel


# ---- the whistle page: your pet's to-do list ------------------------------------------

func _rebuild_whistle(jobs: Array[Dictionary], pet: Pet, who: String) -> void:
	_where.text = "%s is %s" % [who, doing(str(GameState.automation.task))]
	var board := Clipboard.new()
	board.size_flags_horizontal = SIZE_EXPAND_FILL
	_cards.add_child(board)
	var col := board.paper_column
	col.add_child(UiTheme.title("%s's list" % who, 18, UiTheme.PINK))
	for j in jobs:
		col.add_child(TodoRow.new(j, self))
	var resting_n := GameState.resting_count()
	var note := PanelContainer.new()
	note.size_flags_horizontal = SIZE_SHRINK_BEGIN
	note.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.RAISED.lerp(UiTheme.MINT, 0.1), UiTheme.LINE.lerp(UiTheme.MINT, 0.4), 6, 2, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	note.add_child(row)
	var n := UiTheme.label(UiTheme.num(resting_n), UiTheme.MINT, UiTheme.SMALL)
	n.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(n)
	var words := UiTheme.label("pets resting", UiTheme.TEXT, UiTheme.SMALL)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(words)
	if resting_n > 0:
		row.add_child(TinyCrowd.new(GameState.resting_faces(6), 3))
	col.add_child(note)
	_rebuild_whistle_side(pet, who)


func _rebuild_whistle_side(pet: Pet, who: String) -> void:
	UiTheme.clear(_card)
	var job := Automation.job(GameState.catalog, Automation.WHISTLE)
	var color := color_of(job)
	var here := str(GameState.automation.task) == Automation.WHISTLE
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(str(job.icon), 22, color))
	head.add_child(UiTheme.title(str(job.name), 17, color))
	_card.add_child(head)

	var you := PanelContainer.new()
	you.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM if here else UiTheme.LINE, 10, 2, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	you.add_child(col)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var portrait := PetPortrait.new(2, false)
	portrait.set_pet(pet)
	line.add_child(portrait)
	var words_label := ErrandToolsView._wrapped("%s is here ♡\nmanaging" % who if here else "nobody here", UiTheme.TEXT, UiTheme.SMALL + 1)
	words_label.size_flags_horizontal = SIZE_EXPAND_FILL
	words_label.size_flags_vertical = SIZE_SHRINK_CENTER
	line.add_child(words_label)
	col.add_child(line)
	var button := UiTheme.button("take it off" if here else "move it here", func(): _move("" if here else Automation.WHISTLE))
	if not here:
		button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 6))
	col.add_child(button)
	_card.add_child(you)

	# set aside: − 250k +
	var step := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 6, 2, 3)
	sb.content_margin_left = 8
	step.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	step.add_child(row)
	var aside := UiTheme.label("set aside", UiTheme.TEXT, UiTheme.SMALL)
	aside.size_flags_horizontal = SIZE_EXPAND_FILL
	aside.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(aside)
	var keep := Automation.keep(GameState.catalog, GameState.automation)
	var steps: Array = job.get("keep_steps", [0])
	var less := UiTheme.small_button("−", func(): _step_keep(-1))
	less.disabled = keep <= int(steps[0])
	row.add_child(less)
	var price := UiTheme.label(UiTheme.num(keep), UiTheme.CYAN, UiTheme.SMALL)
	price.custom_minimum_size = Vector2(44, 0)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price.size_flags_vertical = SIZE_SHRINK_CENTER
	var coin := UiTheme.icon_rect("coin", 13, UiTheme.CYAN)
	row.add_child(coin)
	row.add_child(price)
	var more := UiTheme.small_button("+", func(): _step_keep(1))
	more.disabled = keep >= int(steps[steps.size() - 1])
	row.add_child(more)
	_card.add_child(step)

	var tools := Automation.all_tools(GameState.catalog).filter(func(t): return t.job == Automation.WHISTLE)
	if not tools.is_empty():
		_card.add_child(UiTheme.title("upgrades", 13, UiTheme.LILAC))
		for t in tools:
			_card.add_child(ToolRow.new(t, UiTheme.LILAC, self))

	# since you looked: what it did while you watched (or were away), only when it did something
	var since: Dictionary = GameState.whistle_since
	var lines: Array[String] = []
	for j in GameState.worker_jobs():
		var got := int(since.hauled.get(j.id, 0))
		if got > 0:
			lines.append("+%s %s %s" % [UiTheme.num(got), j.spot.get("name", "spot") if got == 1 else j.spot.get("names", "spots"),
				"started" if j.spot.has("per_place") else "hauled home"])
	if int(since.put) > 0:
		lines.append("%s %s put to work" % [UiTheme.num(int(since.put)), "pet" if int(since.put) == 1 else "pets"])
	if not lines.is_empty():
		var gap := Control.new()
		gap.size_flags_vertical = SIZE_EXPAND_FILL
		_card.add_child(gap)
		var foot := DashedTop.new()
		foot.add_theme_constant_override("separation", 1)
		foot.add_child(UiTheme.label("since you looked:", UiTheme.MUTED, UiTheme.SMALL))
		for l in lines:
			var got_label := ErrandToolsView._wrapped(l, UiTheme.MINT, UiTheme.SMALL)
			foot.add_child(got_label)
		_card.add_child(foot)


func _step_keep(d: int) -> void:
	GameState.step_whistle_keep(d)
	PetBubble.say_line(self, "automation_keep")


func _tick(job_id: String, key: String) -> void:
	var on := not Automation.tick(GameState.automation, job_id, key)
	GameState.set_whistle_tick(job_id, key, on)
	PetBubble.say_line(self, "automation_tick_on" if on else "automation_tick_off")


## The whistle's clipboard: a lilac board with a clip on top and a sheet of paper on it (a pink
## margin line down the left), holding `paper_column`.
class Clipboard extends PanelContainer:
	var paper_column := VBoxContainer.new()

	func _init() -> void:
		var sb := UiTheme.box(UiTheme.DEEP.lerp(UiTheme.LILAC, 0.12), UiTheme.LILAC_SEAM, 16, 2, 12)
		sb.content_margin_top = 22
		sb.shadow_color = UiTheme.SHADOW
		sb.shadow_size = 7
		sb.shadow_offset = Vector2(0, 5)
		add_theme_stylebox_override("panel", sb)
		var paper := Paper.new()
		paper.add_theme_stylebox_override("panel", _paper_box())
		add_child(paper)
		paper_column.add_theme_constant_override("separation", 0)
		paper.add_child(paper_column)

	static func _paper_box() -> StyleBoxFlat:
		var sb := UiTheme.box(UiTheme.PAPER, UiTheme.PAPER, 6, 0, 0)
		sb.content_margin_left = 20
		sb.content_margin_right = 14
		sb.content_margin_top = 14
		sb.content_margin_bottom = 10
		return sb

	func _draw() -> void:
		# the clip: a rounded bar over the top edge with a slot in it
		var w := 112.0
		var clip := Rect2(size.x / 2.0 - w / 2.0, -8, w, 28)
		var fill := UiTheme.box(UiTheme.RAISED, UiTheme.LILAC, 9, 2, 0)
		draw_style_box(fill, clip)
		var slot := UiTheme.box(UiTheme.DEEP, UiTheme.LILAC_SEAM, 5, 2, 0)
		draw_style_box(slot, Rect2(size.x / 2.0 - 14, -3, 28, 10))

	class Paper extends PanelContainer:
		func _draw() -> void:
			draw_line(Vector2(9, 4), Vector2(9, size.y - 4), Color(UiTheme.PINK, 0.22), 2.0)


## One job on the whistle's list: its name, how many work there and a tiny crowd; how many are home
## and still out there; the two ticks.
class TodoRow extends HBoxContainer:
	func _init(job: Dictionary, tab: AutomationTab) -> void:
		var id := str(job.id)
		var color := AutomationTab.color_of(job)
		var spot: Dictionary = job.get("spot", {})
		add_theme_constant_override("separation", 10)
		size_flags_vertical = SIZE_EXPAND_FILL
		custom_minimum_size = Vector2(0, 76)

		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 8)
		name_box.custom_minimum_size = Vector2(150, 0)
		name_box.add_child(UiTheme.icon_rect(str(job.icon), 22, color))
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_vertical = SIZE_SHRINK_CENTER
		words.add_child(UiTheme.title(str(spot.get("names", "spots")), 16, color))
		var working := GameState.workers_count(id)
		words.add_child(UiTheme.label("%s working" % UiTheme.num(working), UiTheme.MUTED, UiTheme.SMALL))
		var crew := GameState.worker_faces(id, 5) if id != "adventures" else GameState.workers_of(id).filter(func(uid): return str(uid) != "").slice(0, 5)
		if not crew.is_empty():
			words.add_child(TinyCrowd.new(crew, 3))
		name_box.add_child(words)
		add_child(name_box)

		var counts := VBoxContainer.new()
		counts.add_theme_constant_override("separation", 0)
		counts.custom_minimum_size = Vector2(130, 0)
		counts.size_flags_vertical = SIZE_SHRINK_CENTER
		var home := Automation.spots(GameState.automation, id)
		counts.add_child(UiTheme.title(UiTheme.num(home), 26, UiTheme.TEXT))
		var sub := HBoxContainer.new()
		sub.add_theme_constant_override("separation", 4)
		var left := GameState.spot_room(id)
		if spot.has("per_place"):
			sub.add_child(UiTheme.label("of", UiTheme.MUTED, UiTheme.SMALL))
			var places := GameState.party_places().size()
			sub.add_child(UiTheme.label("%s %s" % [UiTheme.num(places), "place" if places == 1 else "places"], color, UiTheme.SMALL))
		else:
			sub.add_child(UiTheme.label("home,", UiTheme.MUTED, UiTheme.SMALL))
			sub.add_child(UiTheme.label("%s out there" % (UiTheme.num(left) if left > 0 else "none"), color, UiTheme.SMALL))
		counts.add_child(sub)
		add_child(counts)

		var ticks := VBoxContainer.new()
		ticks.add_theme_constant_override("separation", 6)
		ticks.size_flags_horizontal = SIZE_EXPAND_FILL
		ticks.size_flags_vertical = SIZE_SHRINK_CENTER
		ticks.add_child(Tick.new("start new ones" if spot.has("per_place") else "haul them home", Automation.tick(GameState.automation, id, "haul"), func(): tab._tick(id, "haul")))
		ticks.add_child(Tick.new("keep them full", Automation.tick(GameState.automation, id, "fill"), func(): tab._tick(id, "fill")))
		add_child(ticks)

	func _draw() -> void:  # a dashed line under the row
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, size.y - 1), Vector2(minf(x + 6.0, size.x), size.y - 1), UiTheme.LINE, 2.0)
			x += 11.0


## A tick box on the to-do list: a little tilted square, ticked in pink when on.
class Tick extends Button:
	var on := true

	func _init(words: String, is_on: bool, on_pressed: Callable) -> void:
		text = words
		on = is_on
		focus_mode = FOCUS_NONE
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		alignment = HORIZONTAL_ALIGNMENT_LEFT
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = 26
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			add_theme_stylebox_override(state, sb)
		add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		add_theme_color_override("font_color", UiTheme.TEXT if on else UiTheme.MUTED)
		add_theme_color_override("font_hover_color", UiTheme.PINK)
		add_theme_color_override("font_pressed_color", UiTheme.PINK)
		size_flags_horizontal = SIZE_SHRINK_BEGIN
		pressed.connect(on_pressed)

	func _draw() -> void:
		var c := Vector2(10, size.y / 2.0)
		draw_set_transform(c, deg_to_rad(-3.0), Vector2.ONE)
		var box := UiTheme.box(UiTheme.DEEP, UiTheme.LILAC_SEAM, 4, 2, 0)
		draw_style_box(box, Rect2(-8.5, -8.5, 17, 17))
		if on:  # the tick: a short stroke and a long one, a bit past the box like a pen would
			draw_polyline(PackedVector2Array([Vector2(-4.5, -0.5), Vector2(-0.5, 4.5), Vector2(7.5, -9.5)]), UiTheme.PINK, 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A handful of pets in a little huddle, bobbing (a tiny crowd on the to-do list).
class TinyCrowd extends Control:
	var _views: Array[PetView] = []
	var _time := 0.0
	var _overlap := 3

	func _init(uids: Array, overlap := 3) -> void:
		_overlap = overlap
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(uids.size() * (PetLook.W - overlap) + overlap + 4, PetLook.H + 4)
		for i in uids.size():
			var view := PetView.new()
			view.pixel = 1
			view.animated = false
			view.pet = GameState.collection.get_pet(str(uids[i]))
			view.position = Vector2(2 + i * (PetLook.W - overlap) + PetLook.W / 2.0, PetLook.H + 3)
			view.set_meta("y", view.position.y)
			add_child(view)
			_views.append(view)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
			set_process(is_visible_in_tree())

	func _process(delta: float) -> void:
		_time += delta
		for i in _views.size():
			_views[i].position.y = _views[i].get_meta("y") - roundf(absf(sin(_time * 4.0 + i * 1.3)) * 2.0)


## A column with a dashed line along its top (the side card's foot).
class DashedTop extends VBoxContainer:
	func _init() -> void:
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 6)
		add_child(pad)

	func _draw() -> void:
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(minf(x + 6.0, size.x), 0), UiTheme.LINE, 2.0)
			x += 11.0


## A job on the workers page: its machines (tables, parties) with the pets working them. Past a
## handful it shows how many more there are.
class WorkerCard extends PanelContainer:
	const SHOWN := 6
	var _id := ""
	var _tab: AutomationTab

	func _init(job: Dictionary, picked: bool, tab: AutomationTab) -> void:
		_id = str(job.id)
		_tab = tab
		custom_minimum_size = Vector2(AutomationTab.CARD_WIDTH, 0)
		mouse_filter = MOUSE_FILTER_STOP
		var color := AutomationTab.color_of(job)
		if picked:
			add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 12, 10))
		else:
			add_theme_stylebox_override("panel", UiTheme.sticker(color.lerp(UiTheme.LINE, 0.55), 12, UiTheme.RAISED, 10))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.mouse_filter = MOUSE_FILTER_IGNORE
		head.add_child(UiTheme.icon_rect(str(job.icon), 20, color))
		var title := UiTheme.title(str(job.name), 15, color)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(60, 0)
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(title)
		col.add_child(head)

		var well := PanelContainer.new()
		well.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 6))
		well.size_flags_vertical = SIZE_EXPAND_FILL
		well.mouse_filter = MOUSE_FILTER_IGNORE
		var flow := HFlowContainer.new()
		flow.alignment = FlowContainer.ALIGNMENT_CENTER
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 6)
		flow.mouse_filter = MOUSE_FILTER_IGNORE
		well.add_child(flow)
		var spots := Automation.spots(GameState.automation, _id)
		var working := GameState.workers_count(_id)
		var shown := mini(spots, SHOWN if spots <= SHOWN else SHOWN - 1)
		var workers := GameState.worker_faces(_id, shown) if _id != "adventures" else GameState.workers_of(_id)
		for i in shown:
			flow.add_child(WorkerSpot.new(_id, str(workers[i]) if i < workers.size() else "", i))
		if spots > shown:
			var more := UiTheme.title("+%s" % UiTheme.num(spots - shown), 16, color)
			more.size_flags_vertical = SIZE_SHRINK_CENTER
			flow.add_child(more)
		col.add_child(well)
		var words := "%s working" % UiTheme.num(working)
		if spots == 0:
			words = "no %s yet" % job.get("spot", {}).get("names", "spots")
		elif working < spots:
			words = "%s, %s working" % [AutomationTab.spots_words(job, spots), UiTheme.num(working)]
		var rate := UiTheme.label(words, color if working > 0 else UiTheme.MUTED, UiTheme.SMALL)
		rate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate.custom_minimum_size = Vector2(60, 0)
		col.add_child(rate)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tab.pick(_id)
			accept_event()


## One machine (table, party gate) on the workers page, with its worker if it has one.
class WorkerSpot extends HBoxContainer:
	func _init(job_id: String, uid: String, index: int) -> void:
		add_theme_constant_override("separation", -6)
		mouse_filter = MOUSE_FILTER_IGNORE
		var scene := AutomationTab.JobScene.new(job_id, uid != "", 0.6, index * 0.37)
		scene.size_flags_vertical = SIZE_SHRINK_END
		add_child(scene)
		if uid != "":
			var portrait := PetPortrait.new(2)
			portrait.set_pet(GameState.collection.get_pet(uid))
			portrait.size_flags_vertical = SIZE_SHRINK_END
			portrait.mouse_filter = MOUSE_FILTER_IGNORE
			add_child(portrait)


## One job's card: its name, a little picture of it (with your pet in it when it's doing it), what
## it's doing, its level.
class JobCard extends PanelContainer:
	var scene: JobScene
	var _id := ""
	var _tab: AutomationTab

	func _init(job: Dictionary, picked: bool, tab: AutomationTab) -> void:
		_id = str(job.id)
		_tab = tab
		custom_minimum_size = Vector2(CARD_WIDTH, 0)
		mouse_filter = MOUSE_FILTER_STOP
		var color := AutomationTab.color_of(job)
		if picked:
			add_theme_stylebox_override("panel", UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 12, 10))
		else:
			add_theme_stylebox_override("panel", UiTheme.sticker(color.lerp(UiTheme.LINE, 0.55), 12, UiTheme.RAISED, 10))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(col)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 6)
		head.mouse_filter = MOUSE_FILTER_IGNORE
		head.add_child(UiTheme.icon_rect(str(job.icon), 20, color))
		var title := UiTheme.title(str(job.name), 15, color)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size = Vector2(60, 0)
		title.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(title)
		col.add_child(head)

		var knows := GameState.knows_job(_id)
		var here := str(GameState.automation.task) == _id
		var seat := PanelContainer.new()
		seat.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 6))
		seat.custom_minimum_size = Vector2(0, 112)
		seat.mouse_filter = MOUSE_FILTER_IGNORE
		var inside := HBoxContainer.new()
		inside.alignment = BoxContainer.ALIGNMENT_CENTER
		inside.add_theme_constant_override("separation", 0)
		inside.mouse_filter = MOUSE_FILTER_IGNORE
		seat.add_child(inside)
		scene = JobScene.new(_id, here)
		scene.size_flags_vertical = SIZE_SHRINK_END
		inside.add_child(scene)
		if here:
			var portrait := PetPortrait.new(3)
			portrait.set_pet(GameState.collection.active())
			portrait.size_flags_vertical = SIZE_SHRINK_END
			portrait.mouse_filter = MOUSE_FILTER_IGNORE
			inside.add_child(portrait)
		col.add_child(seat)

		var rate := UiTheme.label(AutomationTab.rate_line(job), color if here else UiTheme.MUTED, UiTheme.SMALL)
		rate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rate.custom_minimum_size = Vector2(60, 0)
		col.add_child(rate)
		var fill := Control.new()
		fill.size_flags_vertical = SIZE_EXPAND_FILL
		fill.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(fill)
		var lv := 0
		for t in Automation.all_tools(GameState.catalog):
			if t.job == _id and not t.workers:
				lv += Automation.tool_level(GameState.automation, t.id)
		if knows and lv > 0:
			var tag := ErrandsTab.pill("lv %d" % lv, UiTheme.GOLD)
			tag.size_flags_horizontal = SIZE_SHRINK_BEGIN
			col.add_child(tag)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_tab.pick(_id)
			accept_event()


## A little picture of a job, drawn: your pet's capsule machine with its crank going round, the box
## table, the adventure gate with its flag. Still and faded when nobody's doing it.
class JobScene extends Control:
	var kind := ""
	var running := false
	var _time := 0.0
	var _pop_text := ""
	var _pop_color := Color.WHITE
	var _pop_t := -1.0

	var zoom := 1.0

	func _init(job_id: String, is_running: bool, scale_by := 1.0, phase := 0.0) -> void:
		kind = job_id
		running = is_running
		zoom = scale_by
		custom_minimum_size = Vector2(70, 80) * zoom
		_time = phase  # a row of workers' machines don't all crank in step
		mouse_filter = MOUSE_FILTER_IGNORE
		if not running:
			modulate.a = 0.45

	## A little "+12k" rising out of the machine.
	func pop(text: String, color: Color) -> void:
		_pop_text = text
		_pop_color = color
		_pop_t = 0.0

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if running:
			_time += delta
		if _pop_t >= 0.0:
			_pop_t += delta
			if _pop_t > 1.2:
				_pop_t = -1.0
		if running or _pop_t >= 0.0:
			queue_redraw()

	## Seconds a turn of the crank takes on screen: slow when the machine is slow, never frantic.
	func _turn() -> float:
		return clampf(Automation.crank_seconds(GameState.catalog, GameState.automation) / GameState.boost("automation") / 14.0, 1.4, 4.0)

	func _draw() -> void:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
		match kind:
			"machine": _draw_machine()
			"boxes": _draw_boxes()
			"army": _draw_well()
			_: _draw_gate()
		if _pop_t >= 0.0 and _pop_text != "":
			var font := UiTheme.DISPLAY_FONT if UiTheme.DISPLAY_FONT else get_theme_default_font()
			var a := 1.0 - clampf((_pop_t - 0.6) / 0.6, 0.0, 1.0)
			var w := font.get_string_size(_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(font, Vector2(30 - w / 2.0, 30 - _pop_t * 24.0), _pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(_pop_color, a))

	func _draw_machine() -> void:
		var lilac := UiTheme.LILAC
		var pink := UiTheme.PINK
		draw_circle(Vector2(30, 22), 17, UiTheme.PAGE.lerp(lilac, 0.1))
		draw_arc(Vector2(30, 22), 17, 0, TAU, 40, lilac, 2.5, true)
		draw_circle(Vector2(24, 25), 4, Color(pink, 0.85))
		draw_circle(Vector2(34, 18), 4, Color(UiTheme.CYAN, 0.85))
		draw_circle(Vector2(34, 29), 4, Color(UiTheme.GOLD, 0.85))
		var body := PackedVector2Array([Vector2(13, 39), Vector2(47, 39), Vector2(49, 76), Vector2(11, 76)])
		draw_colored_polygon(body, UiTheme.PAGE.lerp(pink, 0.22))
		body.append(body[0])
		draw_polyline(body, pink, 2.5, true)
		draw_rect(Rect2(23, 56, 14, 12), UiTheme.DEEP)
		draw_rect(Rect2(23, 56, 14, 12), UiTheme.PINK_SEAM, false, 2.0)
		# the crank goes round; a capsule drops each time it comes back up
		var turn := fmod(_time, _turn()) / _turn()
		var angle := turn * TAU
		var pivot := Vector2(52, 50)
		var arm := pivot + Vector2(11, 0).rotated(angle)
		var handle := arm + Vector2(0, -9).rotated(angle)
		draw_line(pivot, arm, UiTheme.GOLD, 3.0, true)
		draw_line(arm, handle, UiTheme.GOLD, 3.0, true)
		draw_circle(handle, 3.2, pink)
		draw_circle(pivot, 3.4, UiTheme.GOLD)
		if running and turn > 0.7:
			draw_circle(Vector2(30, 60 + (turn - 0.7) * 20.0), 3.6, Color(UiTheme.MINT, 1.0 - (turn - 0.7) / 0.3))

	func _draw_boxes() -> void:
		var gold := UiTheme.GOLD
		draw_rect(Rect2(44, 28, 18, 14), UiTheme.PAGE.lerp(UiTheme.LILAC, 0.18))
		draw_rect(Rect2(44, 28, 18, 14), UiTheme.LILAC, false, 2.0)
		draw_rect(Rect2(48, 16, 14, 12), UiTheme.PAGE.lerp(UiTheme.CYAN, 0.18))
		draw_rect(Rect2(48, 16, 14, 12), UiTheme.CYAN, false, 2.0)
		draw_rect(Rect2(18, 44, 24, 18), UiTheme.PAGE.lerp(gold, 0.22))
		draw_rect(Rect2(18, 44, 24, 18), gold, false, 2.4)
		# the lid hops off now and then, with a sparkle
		var t := fmod(_time, 2.6) / 2.6
		var hop := sin(clampf((t - 0.6) / 0.3, 0.0, 1.0) * PI) * 7.0 if running else 0.0
		draw_rect(Rect2(16, 39 - hop, 28, 7), UiTheme.PAGE.lerp(gold, 0.34))
		draw_rect(Rect2(16, 39 - hop, 28, 7), gold, false, 2.4)
		if running and t > 0.66 and t < 0.95:
			var c := Vector2(30, 32 - (t - 0.66) * 20.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4), c + Vector2(1.2, -1.2), c + Vector2(4, 0), c + Vector2(1.2, 1.2),
				c + Vector2(0, 4), c + Vector2(-1.2, 1.2), c + Vector2(-4, 0), c + Vector2(-1.2, -1.2)]), gold)
		draw_line(Vector2(6, 62), Vector2(64, 62), UiTheme.PINK, 3.0, true)
		draw_line(Vector2(12, 62), Vector2(10, 78), UiTheme.PINK, 3.0, true)
		draw_line(Vector2(58, 62), Vector2(60, 78), UiTheme.PINK, 3.0, true)

	## The old well: a little roof, the rope going down, a lantern bobbing on it while the army's out.
	func _draw_well() -> void:
		var lilac := UiTheme.LILAC
		draw_line(Vector2(16, 30), Vector2(16, 58), lilac, 2.4, true)
		draw_line(Vector2(54, 30), Vector2(54, 58), lilac, 2.4, true)
		var roof := PackedVector2Array([Vector2(8, 32), Vector2(35, 16), Vector2(62, 32)])
		draw_colored_polygon(roof, UiTheme.PAGE.lerp(UiTheme.PINK_SEAM, 0.4))
		roof.append(roof[0])
		draw_polyline(roof, UiTheme.PINK_SEAM, 2.4, true)
		draw_line(Vector2(16, 36), Vector2(54, 36), lilac, 2.4, true)
		var bob := sin(_time * 2.0) * 4.0 if running else 0.0
		draw_line(Vector2(35, 36), Vector2(35, 60 + bob), UiTheme.MUTED, 2.0, true)
		draw_rect(Rect2(31, 60 + bob, 8, 9), UiTheme.WISP)
		draw_circle(Vector2(35, 64 + bob), 8.0, Color(UiTheme.WISP, 0.18))
		var rim := Rect2(10, 58, 50, 18)
		draw_rect(rim, UiTheme.PAGE.lerp(lilac, 0.15))
		draw_rect(rim, lilac, false, 2.4)
		draw_line(Vector2(22, 58), Vector2(22, 67), Color(UiTheme.LILAC_SEAM, 0.6), 2.0)
		draw_line(Vector2(48, 58), Vector2(48, 67), Color(UiTheme.LILAC_SEAM, 0.6), 2.0)

	func _draw_gate() -> void:
		var mint := UiTheme.MINT
		# the path marches off into the distance while a party is out
		var off := fmod(_time * 10.0, 6.0) if running else 0.0
		var path := [Vector2(8, 76), Vector2(22, 66), Vector2(30, 66), Vector2(42, 64), Vector2(46, 52), Vector2(58, 44)]
		for i in path.size() - 1:
			var a: Vector2 = path[i]
			var b: Vector2 = path[i + 1]
			var d := a.distance_to(b)
			var s := -off
			while s < d:
				var from := a.lerp(b, clampf(s / d, 0.0, 1.0))
				var to := a.lerp(b, clampf((s + 3.0) / d, 0.0, 1.0))
				if s + 3.0 > 0.0:
					draw_line(from, to, UiTheme.MUTED, 2.0)
				s += 6.0
		draw_line(Vector2(8, 34), Vector2(8, 76), mint, 3.0, true)
		draw_line(Vector2(38, 34), Vector2(38, 76), mint, 3.0, true)
		var bar := UiTheme.PAGE.lerp(mint, 0.7)
		draw_line(Vector2(8, 44), Vector2(38, 44), bar, 2.4, true)
		draw_line(Vector2(8, 62), Vector2(38, 62), bar, 2.4, true)
		draw_line(Vector2(8, 44), Vector2(38, 62), bar, 2.4, true)
		draw_line(Vector2(46, 76), Vector2(46, 12), Color(UiTheme.TEXT, 0.8), 2.2, true)
		var wave := sin(_time * 4.0) * 2.0 if running else 0.0
		var flag := PackedVector2Array([Vector2(46, 13), Vector2(56, 10 + wave), Vector2(66, 13), Vector2(66, 27), Vector2(56, 24 + wave), Vector2(46, 27)])
		draw_colored_polygon(flag, UiTheme.PAGE.lerp(UiTheme.PINK, 0.4))
		flag.append(flag[0])
		draw_polyline(flag, UiTheme.PINK, 2.0, true)


## One of a job's tools on the side card: its name, level and what it does, and its price. Tap it
## to buy a level.
class ToolRow extends PanelContainer:
	var _id := ""
	var _tab: AutomationTab

	func _init(t: Dictionary, color: Color, tab: AutomationTab) -> void:
		_id = str(t.id)
		_tab = tab
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 6))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(row)
		var ic := UiTheme.icon_rect(str(t.icon), 18, color)
		ic.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(ic)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		words.size_flags_horizontal = SIZE_EXPAND_FILL
		words.mouse_filter = MOUSE_FILTER_IGNORE
		words.add_child(ErrandToolsView._wrapped(str(t.name), UiTheme.TEXT, UiTheme.SMALL))
		row.add_child(words)
		var cost := GameState.auto_tool_cost(_id)
		var why := GameState.auto_tool_block(_id)
		if _id == "":  # teach the others
			cost = GameState.teach_others_cost(str(t.job))
			why = ""
		else:
			var lv := Automation.tool_level(GameState.automation, _id)
			words.add_child(ErrandToolsView._wrapped("lv %d: %s" % [lv, t.what], UiTheme.MUTED, UiTheme.SMALL - 1))
		var price := UiTheme.label("max" if why == "max" else UiTheme.num(cost), UiTheme.MINT if why == "max" \
			else (UiTheme.CYAN if GameState.coins >= cost else UiTheme.MUTED), UiTheme.SMALL)
		price.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(price)

	## "teach the others" as a row like a tool's: its price, tap to buy.
	static func teach(job_id: String, color: Color, tab: AutomationTab) -> ToolRow:
		var row := ToolRow.new({ "id": "", "icon": "automation", "name": "teach the others", "what": "", "job": job_id }, color, tab)
		row._teach_job = job_id
		return row

	var _teach_job := ""

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _teach_job != "":
				_tab._teach_others(_teach_job)
			else:
				_tab._buy_tool(_id)
			accept_event()
