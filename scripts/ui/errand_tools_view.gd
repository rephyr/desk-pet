class_name ErrandToolsView
extends HBoxContainer
## The errands' upgrades page: a pegboard of tools you buy with coins (data/errands.json "tools",
## Jobs, GameState.buy_errand_tool). A shelf per open job with its sign and level, one for
## everyone, and each tool hanging from a hook on a little tilted tag with its level and price.
## Tap a tag to see it on the card on the right (what it does, the coins a minute before and
## after, the job's goals), tap it again or the card's button to buy. `buy_n` is how many levels a
## tap buys (1, 10, or -1: as many as you can afford), from the switch at the top of the tab.
## Design: design/mockups/screens/errands-upgrades.html (A: the pegboard).

const TAG_WIDTH := 124
const TILTS := [-3.0, 2.5, -1.5, 3.0]

var buy_n := 1:
	set(value):
		buy_n = value
		_dirty = true
var _picked := "noses"
var _tapped := false  # you tapped the picked tag yourself (a second tap buys it)
var _shelves := VBoxContainer.new()
var _card := VBoxContainer.new()
var _dirty := true
var _last := ""


func _init() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = SIZE_EXPAND_FILL
	var peg := PanelContainer.new()
	peg.size_flags_horizontal = SIZE_EXPAND_FILL
	var sb := UiTheme.box(UiTheme.PAPER.lerp(UiTheme.LILAC, 0.04), UiTheme.LINE, 14, 2, 12)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	peg.add_theme_stylebox_override("panel", sb)
	peg.draw.connect(func(): _draw_holes(peg))
	add_child(peg)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	peg.add_child(scroll)
	_shelves.size_flags_horizontal = SIZE_EXPAND_FILL
	_shelves.add_theme_constant_override("separation", 12)
	scroll.add_child(_shelves)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(220, 0)
	side.clip_contents = true
	side.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 14))
	_card.add_theme_constant_override("separation", 9)
	side.add_child(_card)
	add_child(side)

	GameState.changed.connect(func(): _dirty = true)
	GameState.jobs_changed.connect(func(): _dirty = true)
	visibility_changed.connect(func():
		_dirty = true
		_tapped = false)


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not _dirty:
		return
	_dirty = false
	# coins tick up every few seconds: only rebuild when something you'd see changed
	var key := "%s|%s|%s|%d|%s|%s|%s" % [str(GameState.errand_tools), _picked, str(GameState.open_jobs().size()), buy_n,
		_affordable(), str(GameState.machine.bought), UiTheme.num(GameState.errands_per_minute())]
	if key == _last:
		return
	_last = key
	_rebuild()


## Buys what a tap buys of a tool; the pet cheers, or says what's missing.
func buy(id: String) -> void:
	var tool := Jobs.tool(GameState.catalog, id)
	var why := GameState.errand_tool_block(id)
	if why == "max":
		PetBubble.say_line(self, "errands_tool_max")
		return
	if why != "":
		return
	var job_id := str(tool.job)
	var goal_before := GameState.job_level(job_id) if job_id != "" else 0
	var got := GameState.buy_errand_tool(id, buy_n)
	if got <= 0:
		PetBubble.say_line(self, "errands_tool_poor")
		return
	Sfx.play(self, MachineTab._sound("prize"), 2.0)
	var reached := {}
	if job_id != "":
		var job := GameState.catalog.job(job_id)
		for g in job.get("goals", []):
			if goal_before < int(g.at) and GameState.job_level(job_id) >= int(g.at):
				reached = g
		if not reached.is_empty():
			PetBubble.say_line(self, "errands_goal", { "goal": Jobs.goal_words(job, reached) })
			Sfx.play(self, MachineTab._sound("jackpot"), -3.0)
	if reached.is_empty():
		var key := "errands_tool_" + id
		PetBubble.say_line(self, key if Catalog.shared().voice.get("ui", {}).has(key) else "errands_tool")
	_last = ""
	_dirty = true


## What a tap of each tool buys right now: whether you can afford it (and, buying as many as you
## can, how many levels that is), so the prices shown never go stale.
func _affordable() -> String:
	var out := ""
	for t in Jobs.all_tools(GameState.catalog):
		var plan := GameState.errand_tool_plan(t.id, buy_n)
		out += "%d," % plan[0] if buy_n < 0 else ("1" if GameState.coins >= plan[1] else "0")
	return out


# ---- building it ----------------------------------------------------------------

func _rebuild() -> void:
	UiTheme.clear(_shelves)
	var catalog := GameState.catalog
	var open := GameState.open_jobs()
	for job in catalog.jobs:
		if job.get("tools", []).is_empty():
			continue
		var is_open := open.any(func(j): return j.id == job.id)
		var wait := ErrandsTab.level_wait(job)
		if not is_open and wait.is_empty():
			continue  # jobs that come much later don't show their tools yet
		var sub := "lv %d" % GameState.job_level(job.id) if is_open else "opens at %s lv %d" % [wait.job.name, wait.level]
		_shelves.add_child(_shelf(str(job.name), sub, ErrandsTab._color(job), job.tools.map(func(t):
			var tool: Dictionary = t.duplicate()
			tool.job = str(job.id)
			return tool), is_open))
	var everyone: Array = Jobs.all_tools(catalog).filter(func(t): return t.job == "")
	_shelves.add_child(_shelf("for everyone", "", UiTheme.LILAC, everyone, true))
	var all := Jobs.all_tools(catalog)
	if not all.any(func(t): return t.id == _picked and GameState.errand_tool_block(t.id) != "closed"):
		_picked = str(all[0].id)
	_rebuild_card()


func _shelf(title: String, sub: String, color: Color, tools: Array, is_open: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	var sign := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.RAISED, color.lerp(UiTheme.LINE, 0.55), 6, 2, 4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sign.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(UiTheme.title(title, 14, color))
	if sub != "":
		var s := UiTheme.label(sub, UiTheme.MUTED, UiTheme.SMALL)
		s.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(s)
	sign.add_child(row)
	if not is_open:
		sign.modulate.a = 0.6
	var tilted := Tilted.new(sign, -1.5)
	tilted.size_flags_horizontal = SIZE_SHRINK_BEGIN
	tilted.z_index = 1
	col.add_child(tilted)
	var hooks := HFlowContainer.new()  # more tags than fit go on a second row
	hooks.add_theme_constant_override("h_separation", 10)
	hooks.add_theme_constant_override("v_separation", 4)
	for i in tools.size():
		hooks.add_child(ToolTag.new(tools[i], color, TILTS[i % TILTS.size()], is_open, tools[i].id == _picked, self))
	col.add_child(hooks)
	return col


## The card on the right: the picked tool, what a tap buys and what it does to the coins a minute.
func _rebuild_card() -> void:
	UiTheme.clear(_card)
	var catalog := GameState.catalog
	var tool := Jobs.tool(catalog, _picked)
	var job := catalog.job(str(tool.job)) if tool.job != "" else {}
	var color := ErrandsTab._color(job) if not job.is_empty() else UiTheme.LILAC
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect(str(tool.icon), 24, color))
	var name_label := UiTheme.title(str(tool.name), 17, color)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(name_label)
	_card.add_child(head)
	_card.add_child(_wrapped(str(tool.what) + ".", UiTheme.TEXT, UiTheme.SMALL + 1))

	var why := GameState.errand_tool_block(_picked)
	var plan := GameState.errand_tool_plan(_picked, buy_n)
	var have := GameState.errand_tool_level(_picked)
	var now := GridContainer.new()
	now.columns = 2
	now.add_theme_constant_override("h_separation", 10)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 8))
	box.add_child(now)
	_add_row(now, "level", "%d%s" % [have, " of %d" % int(tool.max) if int(tool.get("max", 0)) > 0 else ""], UiTheme.TEXT)
	if why != "max":
		if tool.each.has("away_hours"):
			var h := GameState.errands_away_hours()
			_add_row(now, "full speed away", "%s h → %s h" % [UiTheme.num(h), UiTheme.num(h + float(tool.each.away_hours) * plan[0])], UiTheme.MINT)
		else:
			var before := GameState.errands_per_minute()
			var after := GameState.errands_per_minute_with(_picked, plan[0])
			_add_row(now, "a minute", UiTheme.num(before) + (" → " + UiTheme.num(after) if after > before + 0.5 else ""), UiTheme.MINT if after > before + 0.5 else UiTheme.TEXT)
	_card.add_child(box)

	var label := "all done! ♡"
	if why == "":
		label = "buy %s\nfor %s" % ["it" if plan[0] == 1 else "%s levels" % UiTheme.num(plan[0]), UiTheme.num(plan[1])]
	elif why != "max":
		label = why
	var button := UiTheme.button(label, func(): buy(_picked))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART  # long prices wrap instead of widening the card
	button.custom_minimum_size = Vector2(60, 0)
	button.disabled = why != "" or GameState.coins < plan[1]
	button.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.DEEP, UiTheme.PINK_SEAM, 8, 2, 8))
	if why == "":
		button.icon = UiTheme.icon("coin", 14, UiTheme.CYAN)
	_card.add_child(button)

	var fill := Control.new()
	fill.size_flags_vertical = SIZE_EXPAND_FILL
	_card.add_child(fill)
	var goals_job: Dictionary = job if not job.is_empty() else catalog.job("coin_hunt")
	if not goals_job.get("goals", []).is_empty():
		_card.add_child(UiTheme.label("%s goals" % goals_job.name, UiTheme.MUTED, UiTheme.SMALL))
		_card.add_child(ErrandsTab.GoalTrack.new(goals_job, ErrandsTab._color(goals_job)))
		_card.add_child(_wrapped(ErrandsTab.goal_line(goals_job), UiTheme.TEXT, UiTheme.SMALL))


func pick(id: String) -> void:
	if _picked == id and _tapped:
		buy(id)
		return
	_picked = id
	_tapped = true
	_last = ""
	_dirty = true
	var tool := Jobs.tool(GameState.catalog, id)
	PetBubble.say(self, "%s: %s." % [tool.name, tool.what])


static func _add_row(grid: GridContainer, left: String, right: String, color: Color) -> void:
	grid.add_child(UiTheme.label(left, UiTheme.MUTED, UiTheme.SMALL + 1))
	var r := UiTheme.label(right, color, UiTheme.SMALL + 1)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(r)


static func _wrapped(text: String, color: Color, size: int) -> Label:
	var l := UiTheme.label(text, color, size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(60, 0)
	return l


## The pegboard: rows of little holes.
static func _draw_holes(peg: Control) -> void:
	var y := 11.0
	while y < peg.size.y - 6.0:
		var x := 11.0
		while x < peg.size.x - 6.0:
			peg.draw_circle(Vector2(x, y), 2.2, UiTheme.DEEP)
			x += 22.0
		y += 22.0


## One tool on the pegboard: a hook, a bit of string and a tilted tag with its icon, name, level
## and price (or, not yet: dashed, with what it waits for).
class ToolTag extends MarginContainer:
	var _id := ""
	var _view: ErrandToolsView

	func _init(tool: Dictionary, color: Color, tilt: float, job_open: bool, picked: bool, view: ErrandToolsView) -> void:
		_id = str(tool.id)
		_view = view
		custom_minimum_size = Vector2(TAG_WIDTH, 84)
		add_theme_constant_override("margin_top", 16)  # room for the hook and its string
		mouse_filter = MOUSE_FILTER_STOP
		var why := GameState.errand_tool_block(_id) if job_open else "closed"
		var locked := why != "" and why != "max"
		mouse_default_cursor_shape = CURSOR_ARROW if locked else CURSOR_POINTING_HAND
		var tag := PanelContainer.new()
		var sb: StyleBox
		if locked:
			sb = UiTheme.stitched(color.lerp(UiTheme.LINE, 0.5), Color(0, 0, 0, 0), 8, 7)
		else:
			sb = UiTheme.box(UiTheme.RAISED, UiTheme.PINK if picked else color.lerp(UiTheme.LINE, 0.55), 8, 2, 7)
			if picked:
				sb = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 8, 7)
		tag.add_theme_stylebox_override("panel", sb)
		tag.mouse_filter = MOUSE_FILTER_IGNORE
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		tag.add_child(col)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 6)
		top.mouse_filter = MOUSE_FILTER_IGNORE
		top.add_child(UiTheme.icon_rect(str(tool.icon), 22, UiTheme.LOCKED if locked else color))
		var name_label := UiTheme.label("???" if why == "closed" else str(tool.name), UiTheme.LOCKED if locked else UiTheme.TEXT, UiTheme.SMALL + 1)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.size_flags_horizontal = SIZE_EXPAND_FILL
		name_label.custom_minimum_size = Vector2(60, 0)
		name_label.add_theme_constant_override("line_spacing", -2)
		top.add_child(name_label)
		col.add_child(top)
		var fill := Control.new()
		fill.size_flags_vertical = SIZE_EXPAND_FILL
		col.add_child(fill)
		var foot := HBoxContainer.new()
		foot.mouse_filter = MOUSE_FILTER_IGNORE
		if locked:
			if why != "closed":
				foot.add_child(UiTheme.label(why, UiTheme.LOCKED, UiTheme.SMALL - 1))
		else:
			var have := GameState.errand_tool_level(_id)
			foot.add_child(ErrandsTab.pill("max" if why == "max" else "lv %d" % have, UiTheme.MINT if why == "max" else UiTheme.GOLD))
			foot.add_child(UiTheme.spacer())
			if why != "max":
				var plan := GameState.errand_tool_plan(_id, view.buy_n)
				var price := HBoxContainer.new()
				price.add_theme_constant_override("separation", 3)
				var can: bool = GameState.coins >= plan[1]
				price.add_child(UiTheme.icon_rect("coin", 12, UiTheme.CYAN))
				price.add_child(UiTheme.label(UiTheme.num(plan[1]), UiTheme.CYAN if can else UiTheme.MUTED, UiTheme.SMALL))
				foot.add_child(price)
				if not can:
					tag.modulate.a = 0.75
		col.add_child(foot)
		for c in [top, foot] + top.get_children() + foot.get_children():
			if c is Control:
				c.mouse_filter = MOUSE_FILTER_IGNORE
		var tilted := Tilted.new(tag, tilt)
		tilted.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(tilted)
		if not locked:
			tooltip_text = str(tool.what)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			if mouse_default_cursor_shape == CURSOR_POINTING_HAND:
				_view.pick(_id)

	func _draw() -> void:
		var hook := Vector2(size.x / 2.0, 6.0)
		draw_line(hook + Vector2(0, 4), Vector2(size.x / 2.0, 18.0), UiTheme.LILAC_SEAM, 2.0)
		draw_circle(hook, 5.0, UiTheme.LILAC_SEAM)
		draw_circle(hook, 3.0, UiTheme.DEEP)
