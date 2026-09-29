class_name MachineTab
extends VBoxContainer
## The capsule machine: pull the lever towards you; every chute drops a capsule with one prize
## (data/machine.json, Machine, GameState.pull_lever). Two pages: the machine itself (with the
## upgrades you can work on right now next to it) and its upgrade tree (MachineTreeView): you're
## fixing up an old broken machine with coins and bits (pets bring bits home from adventures). Your
## lever is never automated (later your pet cranks a little machine of its own, much slower, see the
## automation tab), so pulling has to feel good forever: the lever is the whole point of this tab.
## Later map pages bring more GLOBES home (Machine): the two newest stand side by side on one stage,
## you pull the newest one that works, and your pet and workers crank the one behind it. While the
## newest globe still has repairs left, its fixes list takes the place of "next up".
## Design: design/mockups/screens/capsules.html, machine-tree.html, globes.html (look A).

const NEXT_UP := 3  # upgrades shown next to the machine
const MAX_PILLS := 4  # bits pills at the top (more would push past the window)

## The two globe stages. A stage keeps its globe while that globe stays on show (so capsules on
## their way out of it aren't lost when a new globe comes home); the older globe stands on the left.
var stages: Array[MachineStage] = [MachineStage.new(), MachineStage.new()]
## The globe you pull by hand (the dev driver, the tutorial and pet boxes use it).
var stage: MachineStage:
	get:
		for s in stages:
			if s.visible and s.hand:
				return s
		return stages[1] if stages[1].visible else stages[0]
var upgrades := MachineTreeView.new()
## The prize card in the stage's top right corner (hidden in the tutorial: capsules only hold coins then).
var odds := OddsCard.new()
var _holder := StageHolder.new()
var _machine_page := HBoxContainer.new()
var _next_side := VBoxContainer.new()
var _next := VBoxContainer.new()
var _fixes := FixList.new()
var _bits_row := HBoxContainer.new()
var _mode: PanelContainer
var _last := ""
var _table := PanelContainer.new()  # where a pet box out of a capsule gets opened
var _opening := PackOpening.new()
var _box_coming := false  # a pet box popped out and its opening is about to start


func _init() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	_mode = UiTheme.segmented(["machine", "upgrades"], 0, func(i): _show_page(i))
	bar.add_child(_mode)
	bar.add_child(UiTheme.spacer())
	_bits_row.add_theme_constant_override("separation", 6)
	bar.add_child(_bits_row)
	add_child(bar)

	_machine_page.add_theme_constant_override("separation", 14)
	_machine_page.size_flags_vertical = SIZE_EXPAND_FILL
	_holder.size_flags_horizontal = SIZE_EXPAND_FILL
	_holder.size_flags_vertical = SIZE_EXPAND_FILL
	_machine_page.add_child(_holder)
	for s in stages:
		s.size_flags_horizontal = SIZE_EXPAND_FILL
		s.size_flags_vertical = SIZE_EXPAND_FILL
		_holder.row.add_child(s)
		s.pet_box.connect(_open_box)
	stages[0].visible = false
	stages[0].setup("", false, false)
	_holder.add_child(odds)
	_holder.resized.connect(func(): odds.place(_holder.size))
	_next_side.custom_minimum_size = Vector2(236, 0)
	_next_side.add_theme_constant_override("separation", 8)
	_next_side.add_child(UiTheme.title("next up", 16, UiTheme.LILAC))
	_next.add_theme_constant_override("separation", 8)
	_next_side.add_child(_next)
	_next_side.add_child(UiTheme.button("all upgrades →", func(): show_page(1)))
	_machine_page.add_child(_next_side)
	_fixes.visible = false
	_machine_page.add_child(_fixes)
	add_child(_machine_page)
	upgrades.visible = false
	add_child(upgrades)
	# a box with a pet inside, out of a capsule: opened right here, with the real ritual
	_table.size_flags_vertical = SIZE_EXPAND_FILL
	_table.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 14))
	_table.visible = false
	_opening.allow_again = false  # there's no pile to open another from here
	_opening.closed.connect(_close_box)
	_table.add_child(_opening)
	add_child(_table)

	GameState.changed.connect(_refresh)
	GameState.machine_pulled.connect(_on_pulled)
	GameState.machine_upgraded.connect(_on_upgraded)
	GameState.pet_cranked.connect(_on_cranked)
	GameState.toys_changed.connect(func():
		for s in stages:
			s.refresh_state())
	GameState.globe_arrived.connect(func(_g):
		_last = ""
		_refresh()
		_greet.call_deferred())
	visibility_changed.connect(func():
		if is_visible_in_tree():
			_last = ""
			_refresh()
			speak()
			_greet())
	_layout()


## A pet box popped out of a capsule: after a moment the machine steps aside and the box lands
## to be ripped open.
func _open_box(pet: Pet, box_id: String) -> void:
	_box_coming = true
	await get_tree().create_timer(0.8).timeout
	_box_coming = false
	_machine_page.visible = false
	upgrades.visible = false
	_mode.visible = false
	_table.visible = true
	_opening.play(pet, box_id)


func _close_box() -> void:
	_table.visible = false
	_mode.visible = true
	_show_page(0)
	PetBubble.say_line(self, "machine_pet_box_done")
	_greet()


## Whether something at the machine is still being shown (your capsules opening, a prize's card, a
## pet box): unlock popups wait for it. The globe behind yours (the workers' capsules) never holds them.
func busy() -> bool:
	return is_visible_in_tree() and (stage.showing_prize() or _box_coming or _table.visible)


func speak() -> void:
	PetBubble.say_line(self, "machine_first" if int(GameState.machine.pulls) == 0 else "machine")


## 0 the machine, 1 its upgrade tree (flips the switch at the top too).
func show_page(page: int) -> void:
	(_mode.get_child(0).get_child(page) as Button).pressed.emit()


func _show_page(page: int) -> void:
	_machine_page.visible = page == 0
	upgrades.visible = page == 1


## For the tutorial: the lever (while a pull is what it wants).
func tutorial_target() -> Control:
	return stage.lever_target


## Pulls the lever all the way, as if you did (the dev driver's "pull" step).
func pull() -> void:
	show_page(0)
	stage.pull_by_itself()


## Which globes stand on the stage: the newest two you have (the one you pull always among them),
## side by side; just the one while it's the only globe.
func _layout() -> void:
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.machine
	var home := Machine.home(state, catalog)
	var hand := Machine.hand(state, catalog)
	var shown: Array[String] = []
	shown.assign(home.slice(maxi(0, home.size() - 2)))
	if not shown.has(hand):
		shown = [hand, home.back()]
	var two := shown.size() == 2
	# a stage that already shows one of these globes keeps it; the other stage takes the rest
	var by_globe := {}
	var free: Array[MachineStage] = []
	for s in stages:
		if s.visible and shown.has(s.globe) and not by_globe.has(s.globe):
			by_globe[s.globe] = s
		else:
			free.append(s)
	for g in shown:
		if not by_globe.has(g):
			by_globe[g] = free.pop_front()
	for s in free:
		s.visible = false
		s.setup("", false, false)
	for i in shown.size():
		var s: MachineStage = by_globe[shown[i]]
		s.visible = true
		s.setup(shown[i], shown[i] == hand, two)
		s.size_flags_stretch_ratio = 0.8 if two and i == 0 else 1.0
		_holder.row.move_child(s, i)
	_holder.two = two
	_holder.queue_redraw()


## Shows a new globe arriving once (it slides in, your pet says its line): waits for a pet box.
func _greet() -> void:
	var g := GameState.globe_news()
	if g == "" or not is_visible_in_tree() or _table.visible or _box_coming:
		return
	_layout()
	for s in stages:
		if s.visible and s.globe == g:
			s.arrive()
	var line := str(Machine.globe(Catalog.shared(), g).get("arrives", ""))
	PetBubble.say(self, line)
	GameState.greet_globe(g)


func _on_pulled(result: Dictionary) -> void:
	var g := str(result.get("globe", ""))
	for s in stages:
		if s.visible and s.hand and (g == "" or s.globe == g):
			s.show_pull(result)
			return


func _on_upgraded(id: String) -> void:
	var g := Machine.globe_of(Catalog.shared(), Machine.node(Catalog.shared(), id))
	var hand_was := stage.globe
	_layout()
	if Machine.hand(GameState.machine, Catalog.shared()) != hand_was:
		_last = ""  # the hand moved to the new globe
	for s in stages:
		if s.visible and s.globe == g:
			s.fixed(id)


## Your pet's (or a worker's) crank: the globe behind yours shows it, when it's on the stage.
func _on_cranked(result: Dictionary) -> void:
	if not is_visible_in_tree():
		return
	for s in stages:
		if s.visible and not s.hand and s.globe == Machine.behind(GameState.machine, Catalog.shared()):
			s.show_crank(result)


func _refresh() -> void:
	if not is_visible_in_tree():
		return
	for s in stages:
		s.refresh_state()  # what the stages draw from (a toy's boost can change what a capsule's worth)
	var catalog := Catalog.shared()
	var state: Dictionary = GameState.machine
	var key := "%d|%s|%s|%s|%s|%s" % [GameState.coins, str(GameState.bits), str(state.bought), str(state.get("globes", [])),
		str(GameState.automation.workers.get("machine", [])), GameState.automation.task]
	if key == _last:
		return
	_last = key
	_layout()
	# a new globe's repairs, while it has any left; otherwise the upgrades you can work on right now
	var newest := Machine.newest(state, catalog)
	var fixing := newest != Machine.first_globe(catalog) and Machine.repairs_left(state, catalog, newest)
	var open: Array = catalog.machine_tree.nodes.filter(func(n):
		var look := Machine.look(state, catalog, n.id)
		return (look == "next" or look == "owned") and not Machine.maxed(state, catalog, n.id))
	_build_bits(_pill_bits(fixing, newest, open))
	_fixes.visible = fixing
	_next_side.visible = not fixing
	if fixing:
		_fixes.build(newest)
		return
	UiTheme.clear(_next)
	open.sort_custom(func(a, b): return Machine.cost(state, catalog, a.id) < Machine.cost(state, catalog, b.id))
	for n in open.slice(0, NEXT_UP):
		_next.add_child(NodeCard.new(n))
	if open.is_empty():
		_next.add_child(UiTheme.label("everything's fixed! for now…", UiTheme.MUTED, UiTheme.SMALL + 1))


## Which bits the pills at the top show: the newest globe's while you're fixing it; with just the
## first globe home, its bits (as always); after that, the bits the upgrades you can work on ask for
## (or, when none of them asks for any, the bits you have). In the data's order.
func _pill_bits(fixing: bool, newest: String, open: Array) -> Array[String]:
	var catalog := Catalog.shared()
	if fixing or newest == Machine.first_globe(catalog):
		return Machine.bits_of(catalog, newest)
	var wanted := {}
	for n in open:
		for b in Machine.bits_cost(catalog, n.id):
			wanted[b] = true
	var out: Array[String] = []
	for b in Machine.all_bits(catalog):
		if out.size() < MAX_PILLS and (wanted.has(b) or (wanted.is_empty() and int(GameState.bits.get(b, 0)) > 0)):
			out.append(b)
	return out


func _build_bits(bits: Array[String]) -> void:
	var catalog := Catalog.shared()
	UiTheme.clear(_bits_row)
	for b in bits:
		var n := int(GameState.bits.get(b, 0))
		var chip := UiTheme.chip("bit_" + b, "%d %s" % [n, Machine.bit_name(catalog, b, n)], UiTheme.TEXT if n > 0 else UiTheme.LOCKED)
		chip.name = "bits_" + b
		chip.tooltip_text = "machine bits: pets find them on adventures"
		_bits_row.add_child(chip)


## The prize card's columns: a plain capsule, and a lucky one once the lucky lights work.
## `odds` is any capsule's; `pull` the pull's first capsule's, the only one a pet box can be in
## (the same as `odds` while a pull drops one capsule). The globe you pull by hand.
## [ { name, lucky, odds: { prize id: chance }, pull: { prize id: chance } } ]
static func odds_columns() -> Array:
	var many := Machine.many_capsules(GameState.machine, Catalog.shared())
	var cols := []
	for lucky in [false, true]:
		if lucky and not Machine.lights_on(GameState.machine, Catalog.shared()):
			continue
		cols.append({ "name": "lucky" if lucky else "a capsule", "lucky": lucky,
			"odds": GameState.machine_odds(lucky, not many), "pull": GameState.machine_odds(lucky, true) })
	return cols


## The prize card's rows, in the order data/machine.json lists the prizes, each with its chance in
## every column; then shiny balls once they're fixed. A pet box only comes in a pull's first
## capsule, so once a pull drops more than one it gets its own "a pull" part at the end (a header
## row, then its chance a pull). [ { name, chances: [..], shiny?, header? } ]
static func odds_rows(cols: Array) -> Array:
	var catalog := Catalog.shared()
	var rows := []
	var per_pull := []
	for p: Dictionary in catalog.machine.prizes:
		var chances := cols.map(func(c): return float(c.odds.get(p.id, 0.0)))
		if chances.any(func(x): return x > 0.0):
			rows.append({ "name": prize_name(p), "chances": chances })
		elif str(p.kind) == "pet_box":
			var pull := cols.map(func(c): return float(c.get("pull", {}).get(p.id, 0.0)))
			if pull.any(func(x): return x > 0.0):
				per_pull.append({ "name": prize_name(p), "chances": pull })
	var shiny := Machine.shiny_chance(GameState.machine, catalog)
	if shiny > 0.0:
		rows.append({ "name": "shiny", "shiny": true, "chances": cols.map(func(_c): return shiny) })
	if not per_pull.is_empty():
		rows.append({ "name": "a pull", "header": true, "chances": cols.map(func(_c): return 0.0) })
		rows.append_array(per_pull)
	return rows


## How a prize reads on the prize card: its "name" (data/machine.json), a box the box tier the
## globe you pull gives.
static func prize_name(p: Dictionary) -> String:
	if p.has("name"):
		return str(p.name)
	if str(p.kind) == "box":
		return str(Catalog.shared().box(Machine.box_of(GameState.machine, Catalog.shared())).get("name", p.id))
	return str(p.id)


## The prize card as plain lines, for the tag's hover (like the back of a pack).
static func odds_text() -> String:
	var cols := odds_columns()
	var lines: Array[String] = []
	for i in cols.size():
		lines.append(str(cols[i].name))
		for row in odds_rows(cols):
			if row.get("header", false):
				lines.append(str(row.name))
			elif float(row.chances[i]) > 0.0:
				lines.append("  %s  %s" % [row.name, UiTheme.percent(row.chances[i])])
	return "\n".join(lines)


static func bit_name(bit: String, n: int) -> String:
	return Machine.bit_name(Catalog.shared(), bit, n)


## A globe's colour (its "color", for signs and its nodes).
static func globe_color(g: String) -> Color:
	return UiTheme.named_color(str(Machine.globe(Catalog.shared(), g).get("color", "gold")), UiTheme.GOLD)


## A little fanfare when something on the machine gets fixed or upgraded.
static func cheer(from: Node, id: String) -> void:
	Sfx.play(from, _sound("light"), 7.0)
	Sfx.play(from, _sound("prize"))
	PetBubble.say_line(from, "machine_fix_" + id if Catalog.shared().voice.get("ui", {}).has("machine_fix_" + id) else "machine_fix")


static func _sound(key: String) -> Dictionary:
	return Sfx.sound("machine", key)


## A capsule toy on a prize card: its picture, big, with "new!" if it's one you didn't have, its
## sound, and your pet saying so (the machine's capsules and presents, see GameState.open_gift).
static func show_toy(owner: Node, popup: PrizePopup, toy: Dictionary) -> void:
	var catalog := Catalog.shared()
	var info := Toys.toy(catalog, toy.id)
	var fin := Toys.finish(catalog, toy.finish)
	var special: bool = toy.finish != "normal"
	var tier := str(info.get("tier", "common"))
	var color := UiTheme.LILAC if special else MachineStage._tier_color(tier)
	var title := ("%s %s!" % [fin.name, info.name]) if special else "%s!" % info.name
	var owned: Dictionary = GameState.toys.owned.get(Toys.key(toy.id, toy.finish), {})
	var sub := "a new toy!" if toy.new else "one more for the workbench (%d spare)" % int(owned.get("spares", 0))
	popup.show_prize(ToyView.new(toy.id, toy.finish, 7), title, sub, str(fin.name) if special else tier, color, toy.new)
	Sfx.play(owner, _sound("jackpot" if special or tier in ["rare", "secret"] else "prize"), 0.0 if special else 3.0)
	PetBubble.say_line(owner, "machine_toy_new" if toy.new else "machine_toy")


## Where the globes stand: the paper panel, the floor across it (both globes stand on it) and a
## row with the globe stages; the odds card goes on top. While there's one globe its stage draws
## all of that itself, as it always did.
class StageHolder extends Control:
	var row := HBoxContainer.new()
	var two := false

	func _init() -> void:
		clip_contents = true
		row.set_anchors_preset(PRESET_FULL_RECT)
		row.add_theme_constant_override("separation", 0)
		add_child(row)

	func _draw() -> void:
		if not two:
			return
		draw_style_box(UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0), Rect2(Vector2.ZERO, size))
		var floor_y := size.y - MachineStage.BOTTOM
		var fl := StyleBoxFlat.new()
		fl.bg_color = UiTheme.PAGE
		fl.corner_radius_bottom_left = 12
		fl.corner_radius_bottom_right = 12
		draw_style_box(fl, Rect2(2, floor_y, size.x - 4, size.y - floor_y - 2))
		draw_line(Vector2(2, floor_y), Vector2(size.x - 2, floor_y), UiTheme.LILAC_SEAM, 3.0)

	func _process(_delta: float) -> void:
		var tab := get_parent().get_parent() as MachineTab
		if tab and is_visible_in_tree():
			tab.odds.visible = not GameState.tutorial_active()


## The newest globe's repairs (look A's "sunset fixes"): a row per repair (its disc, name, and what
## it needs, or "fixed ✓"); the picked one opens up with what your pet says about it, what it gives,
## and fix it / not yet.
class FixList extends PanelContainer:
	var globe := ""
	var picked := ""
	var _col := VBoxContainer.new()
	var _built := ""  # what the rows were last built from (they're rebuilt only when it changes)

	func _init() -> void:
		custom_minimum_size = Vector2(236, 0)
		add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
		_col.add_theme_constant_override("separation", 6)
		add_child(_col)

	func build(g: String) -> void:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		if g != globe:
			picked = ""
		globe = g
		var list := Machine.repairs(catalog, g)
		if picked == "" or Machine.maxed(state, catalog, picked):
			for n in list:
				if not Machine.maxed(state, catalog, n.id):
					picked = str(n.id)
					break
		# rows change with the pick, what's fixed and what you can pay for (not every coin coming in)
		var key := "%s|%s" % [g, picked]
		for n in list:
			var need := Machine.bits_cost(catalog, n.id)
			key += "|%s:%d:%s:%s" % [n.id, Machine.owned(state, n.id), Machine.look(state, catalog, n.id), GameState.coins >= Machine.cost(state, catalog, n.id)]
			for b in need:
				key += ":%s" % (int(GameState.bits.get(b, 0)) >= int(need[b]))
		if key == _built:
			return
		_built = key
		UiTheme.clear(_col)
		var color := MachineTab.globe_color(g)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 7)
		head.add_child(UiTheme.icon_rect(str(Machine.globe(catalog, g).get("icon", "globe_sunny")), 20, color))
		var name_str := str(Machine.globe(catalog, g).get("name", g)).trim_suffix(" globe")
		head.add_child(UiTheme.title("%s fixes" % name_str, 17, color))
		_col.add_child(head)
		for n in list:
			_col.add_child(_row(n, color))
		_col.add_child(UiTheme.spacer())
		var all := UiTheme.button("all upgrades →", func():
			var tab := get_parent().get_parent() as MachineTab
			if tab:
				tab.show_page(1))
		_col.add_child(all)

	func _row(n: Dictionary, color: Color) -> Control:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		var look := Machine.look(state, catalog, n.id)
		var done := Machine.maxed(state, catalog, n.id)
		var open: bool = n.id == picked and not done
		var row := PanelContainer.new()
		row.name = "fix_row_" + str(n.id)
		row.mouse_filter = MOUSE_FILTER_STOP
		row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		var style: StyleBox = UiTheme.stitched(UiTheme.PINK, UiTheme.RAISED, 10, 7) if open else UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 10, 2, 7)
		row.add_theme_stylebox_override("panel", style)
		row.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				picked = str(n.id)
				build(globe))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 5)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(col)
		var top := HBoxContainer.new()
		top.add_theme_constant_override("separation", 9)
		top.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(top)
		top.add_child(Disc.new(str(n.icon), color, "owned" if done else look))
		var text := VBoxContainer.new()
		text.add_theme_constant_override("separation", 2)
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.mouse_filter = MOUSE_FILTER_IGNORE
		top.add_child(text)
		var name_label := UiTheme.label(str(n.name), UiTheme.TEXT if look in ["next", "owned"] else UiTheme.MUTED, UiTheme.SMALL + 1)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.custom_minimum_size.x = 150
		text.add_child(name_label)
		if done:
			text.add_child(UiTheme.label("fixed ✓", UiTheme.MINT, UiTheme.SMALL))
		else:
			text.add_child(MachineTab.needs_row(n, 12))
		if open:
			var says := UiTheme.label(str(n.says), UiTheme.TEXT, UiTheme.SMALL)
			says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			says.custom_minimum_size.x = 190
			col.add_child(says)
			var gain := UiTheme.label(str(n.gain), UiTheme.MINT, UiTheme.SMALL)
			gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gain.custom_minimum_size.x = 190
			col.add_child(gain)
			var why := Machine.blocker(state, catalog, n.id, GameState.coins, GameState.bits)
			var go := UiTheme.small_button("fix it" if why == "" else "not yet", func():
				if GameState.buy_machine_upgrade(str(n.id)):
					MachineTab.cheer(self, str(n.id)))
			go.disabled = why != ""
			col.add_child(go)
		for c in [top, text] + top.get_children() + text.get_children():
			if c is Control:
				c.mouse_filter = MOUSE_FILTER_IGNORE
		return row


## What a node needs, in a row: its price in coins (cyan, or muted when you're short) and each bit
## (pink when you're short of it).
static func needs_row(n: Dictionary, size: int) -> HBoxContainer:
	var catalog := Catalog.shared()
	var cost := HBoxContainer.new()
	cost.add_theme_constant_override("separation", 3)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost.add_child(UiTheme.icon_rect("coin", size, UiTheme.CYAN))
	var price := Machine.cost(GameState.machine, catalog, n.id)
	cost.add_child(UiTheme.label(UiTheme.num(price), UiTheme.CYAN if GameState.coins >= price else UiTheme.MUTED, UiTheme.SMALL))
	var need := Machine.bits_cost(catalog, n.id)
	for b in need:
		var gap := Control.new()
		gap.custom_minimum_size.x = 3
		cost.add_child(gap)
		cost.add_child(UiTheme.icon_rect("bit_" + b, size + 1))
		var have := int(GameState.bits.get(b, 0)) >= int(need[b])
		cost.add_child(UiTheme.label("%d" % int(need[b]), UiTheme.TEXT if have else UiTheme.PINK, UiTheme.SMALL))
	for c in cost.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cost


## A node's disc, as on the tree: filled with a tick once fixed, dashed and breathing when it's next,
## dark when it's still to come.
class Disc extends Control:
	var icon := ""
	var color := Color.WHITE
	var look := ""

	func _init(icon_id: String, c: Color, how: String) -> void:
		icon = icon_id
		color = c
		look = how
		custom_minimum_size = Vector2(34, 34)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		if look == "next" and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := 15.0
		match look:
			"owned":
				draw_circle(c, r, UiTheme.PAGE.lerp(color, 0.3))
				draw_arc(c, r, 0, TAU, 32, color, 3.0, true)
			"next":
				# on the game's clock, so a rebuilt row doesn't start its breath over
				var breathe := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
				draw_arc(c, r + 2.0 + breathe * 3.0, 0, TAU, 32, Color(color, 0.5 - breathe * 0.35), 2.0, true)
				draw_circle(c, r, UiTheme.RAISED)
				for i in 12:
					var a := TAU * i / 12.0
					draw_arc(c, r, a, a + TAU / 24.0, 4, color, 3.0, true)
			_:
				draw_circle(c, r, UiTheme.DEEP)
				draw_arc(c, r, 0, TAU, 32, UiTheme.LINE, 3.0, true)
		var tint := color if look != "dim" and look != "hidden" else UiTheme.LOCKED
		draw_texture_rect(UiTheme.icon("tree_" + icon, 20, tint), Rect2(c - Vector2(10, 10), Vector2(20, 20)), false)
		if look == "owned":
			draw_circle(c + Vector2(11, 11), 7.0, UiTheme.MINT)
			draw_polyline(PackedVector2Array([c + Vector2(8, 11), c + Vector2(10.5, 13.5), c + Vector2(14, 8.5)]), UiTheme.DEEP, 1.8, true)


## One upgrade you can work on, next to the machine: its icon, name, what it gives, what it costs
## (coins and bits). Tap to buy it when you can.
class NodeCard extends Button:
	var info: Dictionary

	func _init(n: Dictionary) -> void:
		info = n
		focus_mode = FOCUS_NONE
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		var why := Machine.blocker(state, catalog, n.id, GameState.coins, GameState.bits)
		var color := MachineTreeView.node_color(n)
		disabled = why != ""
		mouse_default_cursor_shape = CURSOR_ARROW if disabled else CURSOR_POINTING_HAND
		var normal := UiTheme.box(UiTheme.RAISED, UiTheme.LINE, 10, 2, 0)
		for s in ["normal", "disabled", "focus"]:
			add_theme_stylebox_override(s, normal)
		add_theme_stylebox_override("hover", UiTheme.box(UiTheme.RAISED, color, 10, 2, 0))
		add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.RAISED.lerp(color, 0.12), color, 10, 2, 0))
		var row := HBoxContainer.new()
		row.set_anchors_preset(PRESET_FULL_RECT)
		row.offset_left = 12
		row.offset_right = -12
		row.offset_top = 9
		row.offset_bottom = -9
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(row)
		var icon := UiTheme.icon_rect("tree_" + str(n.icon), 26, color)
		row.add_child(icon)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 1)
		row.add_child(col)
		var name_label := UiTheme.label(str(n.name), color, 14)
		name_label.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		col.add_child(name_label)
		var gain := UiTheme.label(str(n.gain), UiTheme.MUTED, UiTheme.SMALL + 1)
		gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(gain)
		var cost := MachineTab.needs_row(n, 12)
		col.add_child(cost)
		for c in [row, icon, col, name_label, gain, cost]:
			c.mouse_filter = MOUSE_FILTER_IGNORE
		row.minimum_size_changed.connect(func(): custom_minimum_size.y = row.get_combined_minimum_size().y + 18.0)
		pressed.connect(func():
			if GameState.buy_machine_upgrade(info.id):
				MachineTab.cheer(self, info.id))


## The machine itself, drawn: a glass globe full of capsules on a pink body, the lucky lights on
## its front, the flap a capsule rolls out of, and the lever on its side. Drawn in a 520 x 470
## "design" space (like the mockup) and scaled to fit.
##
## The lever: grab the knob and drag down. It swings towards you (the knob grows as it comes
## closer), clicking past each notch; at the bottom it clunks, the machine jolts, the capsules in
## the globe jump, and one capsule drops out of the flap, bounces and pops open. Let go and the
## lever springs back up with a little wobble.
##
## Each stage is one GLOBE (Machine): its colours and what's still broken come from it. Only the
## globe you pull by hand (`hand`) takes the mouse and shows the counter; the one behind it has
## your pet or a worker hanging off its lever while they crank it. Side by side (`compact`) the
## stage frames just the machine, standing on the holder's floor, with a sign above it and a stat
## line under it.
class MachineStage extends Control:
	signal pet_box(pet: Pet, box_id: String)  # a capsule held a box with a pet inside, for the tab to open
	const DESIGN := Vector2(520, 470)
	const TOP := 62.0  # side by side: room above the machine for its sign
	const BOTTOM := 46.0  # side by side: room under the floor for its stat line
	const SAG := 0.5  # where a sagging lever (before its pulley) droops to when you let go
	const GLOBE := Vector2(200, 150)
	const GLOBE_R := 118.0
	const PIVOT := Vector2(335, 329)
	const ARM := 110.0
	const FLAP := Vector2(200, 372)
	const REST_Y := 418.0  # where a capsule rests on the rug
	const NOTCHES := 6
	const FIRE_AT := 0.96  # pulled this far, the lever clunks and the capsule comes out
	const DRAG_LENGTH := 150.0  # design px of dragging for a full pull
	const RESTS := [[130,210],[172,222],[214,218],[256,212],[110,172],[150,184],[194,182],[238,178],[276,152],[124,134],[166,146],[210,142],[252,120],[146,106],[190,104],[230,84],[172,68],[232,238]]

	var _pull := 0.0  # 0 standing up .. 1 pulled all the way towards you (drawn)
	var _want := 0.0  # where your hand has it
	var _held := false
	var _latched := false  # it clunked: stays down until you let go
	var _spring_t := -1.0  # seconds into springing back, or -1
	var _spring_from := 0.0
	var _grab_y := 0.0
	var _notch := 0
	var _hover := false
	var _time := 0.0
	var _idle := 0.0  # seconds since the last pull (the knob starts to beg after a while)
	var _shake := 0.0
	var _jolt := 0.0  # the machine squashing down on a clunk
	var _balls: Array = []  # capsules in the globe: { rest, off, vel, rot, spin, color }
	var _out: Array = []  # capsules rolling out: { pos, vel, rot, spin, color, t, result, bounces, gold }
	var _bits: Array = []  # confetti: { pos, vel, rot, color, t, life, size }
	var _floats: Array = []  # rising "+3": { pos, text, color, t, size, icon }
	var _flying: Array = []  # coins flying up to the counter: { from, to, t, delay, amount }
	var _popup := PrizePopup.new()  # a good prize's picture, over the globe
	var _pips_pop: Array[float] = []  # each light's pop (1 -> 0) when it lights
	var _shown_coins := -1.0  # the counter, catching up with the real coins as they fly in
	var _counter_pop := 0.0
	var _flap := 0.0  # the flap swinging open (1) and shut
	var _fever_was := false
	var _fever_music: AudioStreamPlayer
	var _fever_level := 0.0
	var _rng := RandomNumberGenerator.new()
	var _auto := false  # pulling by itself (dev driver)
	var _refused := 0.0  # the knob shaking "not yet" (1 -> 0)
	var _halves: Array = []  # the two halves of a capsule that just popped: { pos, vel, rot, spin, color, top, t }
	## Sits over the lever, for the tutorial to point at (drawing is all in _draw).
	var lever_target := Control.new()
	## "why so much?" at the end of the "N coins a capsule" line, once upgrades multiply it.
	var why_tape := WhyTape.new(GameState.capsule_why)
	var _line := ""  # the "N coins a capsule" line under the counter (see _counter_line)
	var _line_check := 0.0
	var _placed_for := ""  # the line the tape was last put at the end of
	## The globe this stage shows (Machine), whether you pull it, and whether it stands beside another.
	var globe := ""
	var hand := true
	var compact := false
	var _arrive := 0.0  # sliding in from the side as it comes home (1 -> 0)
	var _crank_t := -1.0  # your pet or a worker pulling this lever: 0..1 through one pull, or -1
	var _crank_result := {}  # what that pull gives (GameState.pet_cranked)
	var _crew: Array[TextureRect] = []  # who's cranking it: one on the lever, two waiting below
	var _cranking := false  # someone cranks this globe: its lever keeps going
	var _crank_wait := 0.0  # seconds since its lever last went down
	# what it draws from, worked out when something changes (refresh_state), never every frame
	var _fix_state := {}  # what's on its picture to fix -> still broken?
	var _works := false
	var _is_behind := false  # the globe your pet and workers crank
	var _lights := false
	var _hatch := false
	var _chutes := 1
	var _per := 0.0  # coins a capsule
	var _crew_n := 0  # workers on the machine
	var _pet_cranks := false  # your pet's job is the machine
	var _is_first := false  # the first globe (the sunny one): candy capsules, its own hatch and sign tilt
	var _glass_c := UiTheme.LILAC  # its colours (machine_tree.json "globes")
	var _body_c := UiTheme.PINK
	var _seam_c := UiTheme.PINK_SEAM

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		clip_contents = true
		_rng.randomize()
		_fill_balls()
		_fever_music = AudioStreamPlayer.new()
		_fever_music.bus = "Music"
		var loop := Sfx.stream_of(MachineTab._sound("fever_loop"))
		if loop is AudioStreamOggVorbis:
			(loop as AudioStreamOggVorbis).loop = true
		_fever_music.stream = loop
		_fever_music.volume_db = -60.0
		add_child(_fever_music)
		lever_target.mouse_filter = MOUSE_FILTER_IGNORE
		add_child(lever_target)
		_popup.z_index = UiTheme.Z_PRIZE  # a prize lands over an open "why so much?" slip
		add_child(_popup)
		for i in 3:
			var t := TextureRect.new()
			t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_SCALE
			t.mouse_filter = MOUSE_FILTER_IGNORE
			t.visible = false
			add_child(t)
			_crew.append(t)
		why_tape.also = func(): return hand and not GameState.tutorial_active() and GameState.fever_left() <= 0.0
		add_child(why_tape)
		add_child(why_tape.slip)
		why_tape.visibility_changed.connect(_place_tape)

	## Shows `g`: `is_hand` you pull it, `side_by_side` it stands beside another globe.
	func setup(g: String, is_hand: bool, side_by_side: bool) -> void:
		var changed := g != globe
		globe = g
		hand = is_hand
		compact = side_by_side
		mouse_filter = MOUSE_FILTER_STOP if hand else MOUSE_FILTER_IGNORE
		clip_contents = not compact
		if not hand:
			_held = false
			_latched = false
			_hover = false
		refresh_state()
		if changed:
			_fill_balls()
			_out.clear()
			_halves.clear()
		queue_redraw()

	## Works out what the stage draws from (what's broken, chutes, lights, coins a capsule, who's
	## cranking it): on setup and whenever the game changes, so drawing only reads these.
	func refresh_state() -> void:
		var catalog := Catalog.shared()
		var state: Dictionary = GameState.machine
		_fix_state.clear()
		for t in _crew:
			t.texture = null
		_cranking = false
		_is_first = globe == Machine.first_globe(catalog)
		var info := _info()
		_glass_c = UiTheme.named_color(str(info.get("glass", "lilac")), UiTheme.LILAC)
		_body_c = UiTheme.named_color(str(info.get("body", "pink")), UiTheme.PINK)
		_seam_c = UiTheme.named_color(str(info.get("seam", "pink_seam")), UiTheme.PINK_SEAM)
		if globe == "":
			_works = false
			return
		for n in catalog.machine_tree.nodes:
			var fix := str(n.get("fixes", ""))
			if fix != "" and Machine.globe_of(catalog, n) == globe:
				_fix_state[fix] = bool(_fix_state.get(fix, false)) or Machine.owned(state, n.id) <= 0
		_works = Machine.works(state, catalog, globe)
		_is_behind = globe == Machine.behind(state, catalog)
		_lights = Machine.lights_on(state, catalog, globe)
		_hatch = Machine.hatch_open(state, catalog, globe)
		_chutes = Machine.chutes(state, catalog, globe)
		_per = Machine.coin_value(state, catalog, globe) * GameState.boost("coins")
		_crew_n = GameState.workers_count("machine")
		_pet_cranks = GameState.automation.task == "machine"
		# who cranks it (only the one behind your hand, beside it): the first worker (or your pet,
		# when that's its job) hangs off the lever, two more wait at its feet
		if not compact or hand or not _works or not _is_behind:
			return
		var pets: Array[Pet] = []
		if _pet_cranks and GameState.collection.active():
			pets.append(GameState.collection.active())
		for uid in GameState.worker_faces("machine", _crew.size()):  # cards first, then stand-ins for the herd
			if pets.size() >= _crew.size():
				break
			var p: Pet = GameState.collection.get_pet(str(uid))
			if p:
				pets.append(p)
		for i in pets.size():
			_crew[i].texture = PetLook.texture_for(pets[i].parts)
		_cranking = not pets.is_empty()

	## It just came home: it slides in from the side.
	func arrive() -> void:
		_arrive = 1.0

	func _fill_balls() -> void:
		_balls.clear()
		var colors := _colors()
		for i in RESTS.size():
			_balls.append({ "rest": Vector2(RESTS[i][0], RESTS[i][1]), "off": Vector2.ZERO, "vel": Vector2.ZERO,
				"rot": _rng.randf() * TAU, "spin": 0.0, "color": colors[i % colors.size()] })

	## The capsules' colours: the sunny globe's candy colours, a later globe's own (its glass colour
	## and warm ones).
	func _colors() -> Array:
		if _is_first:
			return [UiTheme.PINK, UiTheme.CYAN, UiTheme.MINT, UiTheme.GOLD, UiTheme.LILAC]
		return [_glass_color(), UiTheme.GOLD, UiTheme.PINK, _glass_color().lerp(UiTheme.GOLD, 0.5), UiTheme.TEXT.lerp(_glass_color(), 0.6)]

	func _info() -> Dictionary:
		return Machine.globe(Catalog.shared(), globe)

	func _glass_color() -> Color:
		return _glass_c

	func _body_color() -> Color:
		return _body_c

	func _seam_color() -> Color:
		return _seam_c

	## Whether something on this globe's picture is still broken (Machine.broken), or was there to fix.
	func _broken(fix: String) -> bool:
		return bool(_fix_state.get(fix, false))

	func _mended(fix: String) -> bool:
		return _fix_state.has(fix) and not _fix_state[fix]

	## Where the lever rests: straight up, or drooping while it sags (before its pulley).
	func _rest() -> float:
		return SAG if _broken("sag") else 0.0

	# ---- where things are ----------------------------------------------------------

	func _scale() -> float:
		if compact:
			return minf(size.x / 330.0, (size.y - TOP - BOTTOM) / 385.0)
		return minf(size.x / 560.0, size.y / 540.0)

	func _origin() -> Vector2:
		var s := _scale()
		var shake := Vector2(sin(_time * 90.0), cos(_time * 77.0)) * _shake * 3.0
		var slide := Vector2(size.x * 1.1 * _arrive * _arrive, 0)
		if compact:
			return Vector2(size.x / 2.0 - 222.0 * s, size.y - BOTTOM - 400.0 * s) + shake + slide
		return size / 2.0 + Vector2(0, 20) - Vector2(260, 235) * s + shake + slide

	func _to_screen(p: Vector2) -> Vector2:
		return _origin() + p * _scale()

	func _to_design(p: Vector2) -> Vector2:
		return (p - _origin()) / _scale()

	## The lever's knob (design space) and how big it is, for `pull` 0..1.
	func _knob(pull: float) -> Array:
		var phi := pull * 1.95  # swings past flat, towards you
		var tip := PIVOT + Vector2(0, -ARM * cos(phi))
		var near := sin(minf(phi, PI / 2.0)) + maxf(0.0, phi - PI / 2.0) * 0.4  # how close to you it is
		return [tip, 17.0 * (1.0 + near * 0.75), near]

	## The coin counter, in the stage's top left corner (side by side: the holder's top left corner).
	func _counter_at() -> Vector2:
		return Vector2(34, 32) - (position if compact else Vector2.ZERO)

	# ---- input -----------------------------------------------------------------------

	func _gui_input(event: InputEvent) -> void:
		if not hand:
			return
		if event is InputEventMouseMotion:
			var d := _to_design(event.position)
			var k: Array = _knob(_pull)
			_hover = d.distance_to(k[0]) < k[1] + 16.0 or (absf(d.x - PIVOT.x) < 22.0 and d.y > k[0].y - 10.0 and d.y < PIVOT.y + 12.0)
			mouse_default_cursor_shape = CURSOR_DRAG if _held else (CURSOR_POINTING_HAND if _hover and _out.is_empty() else CURSOR_ARROW)
			if _held:
				_want = clampf((event.position.y - _grab_y) / (DRAG_LENGTH * _scale()), 0.0, 1.0)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and _hover and not _can_grab() and not _out.is_empty():
				# still waiting for the capsule: the knob won't budge
				_refused = 1.0
				Sfx.play(self, MachineTab._sound("tick"), -9.0)
			elif event.pressed and _hover and _can_grab():
				_held = true
				_spring_t = -1.0
				_grab_y = event.position.y - _pull * DRAG_LENGTH * _scale()
				_want = _pull
				mouse_default_cursor_shape = CURSOR_DRAG
				accept_event()
			elif not event.pressed and _held:
				_let_go()

	func _can_grab() -> bool:
		# one pull at a time: wait for the capsule to pop open; you can catch the lever on its way
		# back up once it's most of the way there
		return hand and not _auto and _out.is_empty() and (_spring_t < 0.0 or _pull < _rest() + 0.35)

	## Whether the lever can be pulled right now (the dev driver waits for this).
	func ready_to_pull() -> bool:
		return hand and _out.is_empty() and not _held and not _auto and (_spring_t < 0.0 or _pull < _rest() + 0.35)

	func _let_go() -> void:
		_held = false
		_latched = false
		_spring_from = _pull
		_spring_t = 0.0
		mouse_default_cursor_shape = CURSOR_POINTING_HAND if _hover else CURSOR_ARROW
		if _pull > 0.3:
			Sfx.play(self, MachineTab._sound("spring"), _rng.randf_range(-1.0, 1.0))

	## The dev driver's pull: the lever goes down and comes back by itself.
	func pull_by_itself() -> void:
		if _auto:
			return
		_auto = true
		_held = true
		_spring_t = -1.0
		var tw := create_tween()
		tw.tween_property(self, "_want", 1.0, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.15)
		tw.tween_callback(func():
			if not _latched:
				# a slow frame can end the tween before the lever reached the bottom: clunk anyway
				_pull = 1.0
				_latched = true
				_fire()
			_auto = false
			_let_go())

	# ---- every frame -------------------------------------------------------------------

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_time += delta
		_idle += delta
		_line_check -= delta
		if _line_check <= 0.0 or _line == "":
			_line_check = 0.2
			_line = _counter_line()
		_place_tape()
		_shake = move_toward(_shake, 0.0, delta * 4.0)
		_arrive = move_toward(_arrive, 0.0, delta * 1.1)
		_refused = move_toward(_refused, 0.0, delta * 3.0)
		_jolt = move_toward(_jolt, 0.0, delta * 5.0)
		_counter_pop = move_toward(_counter_pop, 0.0, delta * 4.0)
		_flap = move_toward(_flap, 0.0, delta * 2.2)

		# the lever: follows your hand with a little weight, heavier near the bottom (and much heavier
		# while it sags)
		var rest := _rest()
		var heavy := 0.4 if rest > 0.0 else 1.0
		if _held:
			var target := _want if not _latched else 1.0
			_pull = lerpf(_pull, target, 1.0 - exp(-delta * lerpf(28.0, 16.0, _pull) * heavy))
			var notch := int(floor(_pull * NOTCHES + 0.001))
			if notch > _notch and not _latched:
				for n in range(_notch + 1, notch + 1):
					Sfx.play(self, MachineTab._sound("tick"), n * 1.5 - 2.0)
					_nudge_balls(10.0 + n * 3.0)
				_shake = maxf(_shake, 0.12)
			_notch = notch if not _latched else NOTCHES
			if _pull >= FIRE_AT and not _latched:
				_latched = true
				_fire()
		elif _spring_t >= 0.0:
			# springs back with a wobble past the top (a sagging lever creeps back slowly and droops)
			_spring_t += delta
			var dur := Machine.spring_seconds(GameState.machine, Catalog.shared()) / heavy
			var k := _spring_t / dur
			_pull = rest + (_spring_from - rest) * exp(-k * 4.2) * cos(k * (7.5 if rest <= 0.0 else 2.0))
			if k >= 1.6:
				_pull = rest
				_spring_t = -1.0
			_notch = int(floor(maxf(_pull, 0.0) * NOTCHES))
		elif _crank_t < 0.0 and _cranking:
			# someone's on it: the lever keeps going down and up, whether a capsule's due or not
			_pull = rest
			_crank_wait += delta
			if _crank_wait > 1.2 and _out.is_empty():
				_crank_wait = 0.0
				_crank_t = 0.0
		elif _crank_t >= 0.0:
			# your pet or a worker pulls it: down, a clunk, back up
			_crank_t += delta / 1.1
			var was := _pull
			_pull = sin(minf(_crank_t, 1.0) * PI) if _crank_t < 0.5 else maxf(0.0, sin(_crank_t * PI))
			if was < FIRE_AT and _pull >= FIRE_AT - 0.02 and not _crank_result.is_empty():
				_crank_fire()
			if _crank_t >= 1.0:
				_crank_t = -1.0
				_pull = rest
		else:
			_pull = rest

		_popup.position = _to_screen(GLOBE + Vector2(0, 30)) - _popup.size / 2.0
		var knob: Array = _knob(rest)
		lever_target.position = _to_screen(knob[0] - Vector2(24, 24))
		lever_target.size = Vector2(48, PIVOT.y - knob[0].y + 44) * _scale()
		_move_balls(delta)
		_move_out(delta)
		_move_bits(delta)
		for f in _floats:
			f.t += delta
		_floats = _floats.filter(func(f): return f.t < 1.0)
		for i in _pips_pop.size():
			_pips_pop[i] = move_toward(_pips_pop[i], 0.0, delta * 3.0)
		_move_flying(delta)
		_place_crew()
		if _shown_coins < 0.0:
			_shown_coins = GameState.coins
		elif _flying.is_empty() and _out.is_empty():
			# nothing on its way: catch up with coins spent or earned elsewhere
			_shown_coins = move_toward(_shown_coins, GameState.coins, maxf(1.0, absf(GameState.coins - _shown_coins)) * delta * 8.0)
		_fever(delta)
		queue_redraw()

	func _fever(delta: float) -> void:
		var on := hand and GameState.fever_left() > 0.0
		if on and not _fever_was:
			Sfx.play(self, MachineTab._sound("fever"))
			PetBubble.say_line(self, "machine_fever")
		_fever_was = on
		_fever_level = move_toward(_fever_level, 1.0 if on else 0.0, delta * (2.0 if on else 1.0))
		if _fever_music.stream == null:
			return
		if _fever_level > 0.0 and not _fever_music.playing:
			_fever_music.play()
		_fever_music.volume_db = lerpf(-50.0, 0.0, sqrt(_fever_level))
		_duck(_fever_level > 0.3)
		if _fever_level <= 0.0 and _fever_music.playing:
			_fever_music.stop()

	var _ducking := false

	## The room music steps back under the fever tune (and comes back after).
	func _duck(on: bool) -> void:
		if on != _ducking:
			_ducking = on
			Music.ducked = on

	func _notification(what: int) -> void:
		if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
			# left the tab: the fever tune stops with it
			_fever_music.stop()
			_fever_level = 0.0
			_duck(false)
			_held = false
			_latched = false

	# ---- a pull ---------------------------------------------------------------------------

	## The lever hit the bottom: clunk, jolt, and a capsule comes out.
	func _fire() -> void:
		_idle = 0.0
		Sfx.play(self, MachineTab._sound("clunk"), _rng.randf_range(-0.6, 0.6))
		Sfx.play(self, MachineTab._sound("rattle"), _rng.randf_range(-1.5, 1.5))
		_shake = 1.0
		_jolt = 1.0
		_flap = 1.0
		for b in _balls:
			b.vel += Vector2(_rng.randf_range(-120.0, 120.0), _rng.randf_range(-260.0, -120.0))
			b.spin += _rng.randf_range(-8.0, 8.0)
		GameState.pull_lever()  # comes back through show_pull()

	## Whether capsules are still opening or a good prize's card is up (unlock popups wait for it).
	func showing_prize() -> bool:
		return is_visible_in_tree() and (_popup.visible or not _out.is_empty())

	## Something on the machine got fixed: a puff of sparkles where it is, and a little jolt.
	func fixed(id: String) -> void:
		var where := { "tape": Vector2(260, 100), "glass": GLOBE, "oil": Vector2(335, 330), "flap": Vector2(200, 370),
			"wires": Vector2(200, 309), "drops": Vector2(200, 31), "chute2": Vector2(200, 370), "chute3": Vector2(200, 370), "chute4": Vector2(200, 370),
			"nest": Vector2(200, 60), "cork": GLOBE, "pulley": Vector2(335, 220), "amber": GLOBE, "hatch": Vector2(200, 31) }
		var at: Vector2 = where.get(id, GLOBE)
		_shake = 0.6
		_jolt = 0.6
		var colors := _colors()
		for i in 18:
			var a := _rng.randf() * TAU
			_bits.append({ "pos": at, "vel": Vector2(cos(a), sin(a)) * _rng.randf_range(80.0, 220.0), "rot": _rng.randf() * TAU,
				"color": UiTheme.GOLD if i % 2 == 0 else colors[i % colors.size()], "t": 0.0, "life": _rng.randf_range(0.5, 0.9), "size": _rng.randf_range(4.0, 7.0) })

	## The capsules the machine just gave (GameState.machine_pulled): one out of each chute (two or
	## three with extra balls), popping open one after another.
	func show_pull(result: Dictionary) -> void:
		var colors := _colors()
		var capsules: Array = result.capsules
		var n := Machine.chutes(GameState.machine, Catalog.shared(), globe)
		for i in capsules.size():
			var cap: Dictionary = capsules[i]
			var gold: bool = cap.prize.kind == "golden" or result.lucky
			var from := Vector2(_chute_x(i % n, n), FLAP.y - 10.0)
			_out.append({ "pos": from, "vel": Vector2(_rng.randf_range(-70.0, 70.0), 40.0 + 30.0 * (i / n)), "rot": 0.0,
				"spin": _rng.randf_range(-10.0, 10.0), "color": UiTheme.GOLD if gold else colors[(int(GameState.machine.pulls) + i) % colors.size()],
				"t": -0.08 * i, "result": cap, "fever": result.fever, "bounces": 0, "gold": gold, "shiny": cap.shiny,
				"reveal": GameState.capsule_seconds() * (1.25 if gold else 1.0) })
		if not Machine.lights_on(GameState.machine, Catalog.shared(), globe):
			return
		# the lucky light that just came on (or all of them, flashing, for a lucky pull)
		var lit := int(GameState.machine.lit)
		var need := Machine.lights_needed(GameState.machine, Catalog.shared())
		_pips_pop.resize(need)
		if result.lucky:
			for i in need:
				_pips_pop[i] = 1.0
		elif lit > 0:
			_pips_pop[lit - 1] = 1.0
			Sfx.play(self, MachineTab._sound("light"), (lit - 1) * 12.0 / need)

	## Your pet or a worker cranked this globe (GameState.pet_cranked): if it isn't busy, its lever
	## goes down by itself and one capsule comes out with what they got (just the little "+coins").
	func show_crank(result: Dictionary) -> void:
		if hand or not _out.is_empty() or not is_visible_in_tree() or not Machine.works(GameState.machine, Catalog.shared(), globe):
			return
		if _crank_result.is_empty():
			_crank_result = result  # comes out on the lever's next clunk
		if _crank_t < 0.0:
			_crank_t = 0.0

	func _crank_fire() -> void:
		var result := _crank_result
		_crank_result = {}
		_shake = 0.5
		_jolt = 0.6
		_flap = 1.0
		Sfx.play(self, MachineTab._sound("clunk"), -6.0)
		for b in _balls:
			b.vel += Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-140.0, -60.0))
		var colors := _colors()
		_out.append({ "pos": Vector2(_chute_x(0, 1), FLAP.y - 10.0), "vel": Vector2(_rng.randf_range(-50.0, 50.0), 40.0), "rot": 0.0,
			"spin": _rng.randf_range(-10.0, 10.0), "color": colors[_rng.randi() % colors.size()], "t": 0.0, "result": result,
			"fever": false, "bounces": 0, "gold": false, "shiny": bool(result.get("shiny", false)), "reveal": 0.9, "crank": true })

	## Moves the crew (refresh_state picked them): one on the lever, two bobbing at its feet.
	func _place_crew() -> void:
		var s := _scale()
		for i in _crew.size():
			var t := _crew[i]
			t.visible = t.texture != null
			if not t.visible:
				continue
			var sz := Vector2(40, 40) * s
			t.size = sz
			if i == 0:
				var k: Array = _knob(_pull)
				t.position = _to_screen(k[0] + Vector2(-8, 4))
			else:
				var bob := sin(_time * 3.0 + i * 1.7) * 3.0
				t.position = _to_screen(Vector2(260 + i * 42, 360 + bob)) if i == 1 else _to_screen(Vector2(64, 360 + bob))

	## Where chute `i` of `n` is along the front (design space).
	static func _chute_x(i: int, n: int) -> float:
		var gap := minf(70.0, 180.0 / n)
		return FLAP.x + (i - (n - 1) / 2.0) * gap

	func _pop(c: Dictionary) -> void:
		var result: Dictionary = c.result
		var prize: Dictionary = result.prize
		var loot: Dictionary = result.loot
		var at: Vector2 = c.pos
		Sfx.play(self, MachineTab._sound("pop"), _rng.randf_range(-1.0, 1.5))
		var colors := _colors()
		var burst := 22 if c.gold or c.shiny else 12
		for i in burst:
			var a := _rng.randf() * TAU
			var sp := _rng.randf_range(90.0, 260.0 if c.gold else 190.0)
			_bits.append({ "pos": at, "vel": Vector2(cos(a), sin(a) - 0.8) * sp, "rot": _rng.randf() * TAU,
				"color": UiTheme.GOLD if c.gold and i % 2 == 0 else colors[i % colors.size()], "t": 0.0, "life": _rng.randf_range(0.5, 0.9), "size": _rng.randf_range(4.0, 7.0) })
		var coins := int(loot.get("coins", 0))
		if c.get("crank", false):
			# a worker's capsule: just what it held, floating up
			var text := "+%s" % UiTheme.num(coins) if coins > 0 else ""
			if not result.get("toy", {}).is_empty():
				text = "a toy!"
			elif Rewards.total(loot, "box") > 0:
				text = "a box!"
			if text != "":
				_floats.append({ "pos": at + Vector2(0, -26), "text": text, "color": UiTheme.GOLD if c.shiny else UiTheme.CYAN, "t": 0.0, "size": 16, "icon": coins > 0 })
			return
		match str(prize.kind):
			"coins":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "+%s%s" % [UiTheme.num(coins), "  shiny!" if c.shiny else ""], "color": UiTheme.GOLD if c.shiny else UiTheme.CYAN, "t": 0.0, "size": 22 if c.fever or c.shiny else 18, "icon": true })
				_send_coins(at, coins)
				if _rng.randf() < 0.12:
					PetBubble.say_line(self, "machine_coins")
			"golden":
				_popup.show_prize(UiTheme.icon_rect("coin", 64, UiTheme.CYAN), "a golden capsule!", "%s coins!!" % UiTheme.num(coins), "", UiTheme.GOLD)
				_send_coins(at, coins)
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_golden")
			"xp":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "+%d xp" % int(loot.get("xp", 1)), "color": UiTheme.GOLD, "t": 0.0, "size": 18, "icon": false })
				Sfx.play(self, MachineTab._sound("light"), 7.0)
			"part":
				var key: String = loot.keys()[0]
				var bits := key.split(":")
				var part := Catalog.shared().part(bits[1], bits[2])
				var portrait := PetPortrait.new(3, false)
				portrait.set_pet(InventoryTab.part_preview(bits[1], bits[2]))
				_popup.show_prize(portrait, "a part!", "%s, %s" % [str(part.get("name", bits[2])), bits[1]], str(part.get("rarity", "common")), Catalog.shared().tier_color(str(part.get("rarity", "common"))))
				Sfx.play(self, MachineTab._sound("prize"), 2.0)
				PetBubble.say_line(self, "machine_part")
			"box":
				var box := TextureRect.new()
				var box_id := str(prize.get("box", "starter"))
				box.texture = PackArt.texture(Catalog.shared().box(box_id).get("art", {}), 56)
				box.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
				_popup.show_prize(box, "a whole box!!", "it's on your pile", str(Catalog.shared().box(box_id).get("name", "")), UiTheme.PINK)
				Sfx.play(self, MachineTab._sound("jackpot"), -3.0)
				PetBubble.say_line(self, "machine_box")
			"toy":
				_show_toy(result.toy)
			"pet":
				_show_pet(result.pet)
			"pet_box":
				_floats.append({ "pos": at + Vector2(0, -26), "text": "a box!!", "color": UiTheme.PINK, "t": 0.0, "size": 22, "icon": false })
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_pet_box")
				if result.pet:
					pet_box.emit(result.pet, str(prize.get("box", "starter")))
			"intel":
				_popup.show_prize(MapScrap.new(), "a scrap of a map!", "someone drew what's past the fence…", "intel", UiTheme.GOLD, true)
				Sfx.play(self, MachineTab._sound("jackpot"))
				PetBubble.say_line(self, "machine_intel")
		if c.shiny and str(prize.kind) != "coins":
			PetBubble.say_line(self, "machine_shiny")

	## A pet out of the machine (the start of the game): its picture, big, and its name.
	func _show_pet(pet: Pet) -> void:
		if pet == null:
			return
		var portrait := PetPortrait.new(5, true)
		portrait.set_pet(pet)
		var second := GameState.collection.count() >= 2
		_popup.show_prize(portrait, "%s!" % pet.display_name(Catalog.shared()), "and it's holding a scribbled map…" if second else "a pet came out of the machine!!", "new friend", UiTheme.PINK, true)
		Sfx.play(self, MachineTab._sound("jackpot"))
		PetBubble.say_line(self, "machine_pet_map" if second else "machine_pet")

	## A toy out of a capsule: its picture, big, with "new!" if it's one you didn't have.
	func _show_toy(toy: Dictionary) -> void:
		MachineTab.show_toy(self, _popup, toy)

	static func _tier_color(tier: String) -> Color:
		match tier:
			"uncommon": return Catalog.shared().tier_color("uncommon")
			"rare": return Catalog.shared().tier_color("rare")
			"secret": return Catalog.shared().tier_color("mythic")
		return Catalog.shared().tier_color("common")

	## A few coins fly from the capsule up to the counter; the counter counts as they land.
	func _send_coins(from_design: Vector2, amount: int) -> void:
		var n := clampi(amount, 1, 7)
		var each := float(amount) / n
		for i in n:
			_flying.append({ "from": _to_screen(from_design), "t": 0.0, "delay": i * 0.05, "amount": each,
				"bend": Vector2(_rng.randf_range(-60.0, 60.0), _rng.randf_range(-90.0, -40.0)) })

	func _move_flying(delta: float) -> void:
		var landed: Array = []
		for f in _flying:
			if f.delay > 0.0:
				f.delay -= delta
				continue
			f.t += delta / 0.5
			if f.t >= 1.0:
				landed.append(f)
		for f in landed:
			_flying.erase(f)
			_shown_coins = minf(_shown_coins + f.amount, GameState.coins)
			_counter_pop = 1.0
			Sfx.play(self, MachineTab._sound("coin"), _rng.randf_range(0.0, 3.0))

	# ---- little physics ------------------------------------------------------------------

	func _nudge_balls(power: float) -> void:
		for b in _balls:
			b.vel += Vector2(_rng.randf_range(-power, power), _rng.randf_range(-power * 1.4, 0.0))

	func _move_balls(delta: float) -> void:
		for b in _balls:
			# each capsule is on a soft spring back to where it sits in the pile
			var acc: Vector2 = -b.off * 90.0 - b.vel * 7.0
			b.vel += acc * delta
			b.off += b.vel * delta
			b.off = b.off.limit_length(26.0)
			b.rot += b.spin * delta
			b.spin = move_toward(b.spin, 0.0, delta * 10.0)

	func _move_out(delta: float) -> void:
		var popped: Array = []
		for c in _out:
			c.t += delta
			c.vel.y += 1400.0 * delta
			c.pos += c.vel * delta
			c.rot += c.spin * delta
			var rest_y := 382.0 if compact else REST_Y  # side by side, capsules stop on the floor, clear of the stat line
			if c.pos.y > rest_y:
				c.pos.y = rest_y
				if c.vel.y > 120.0:
					c.vel.y *= -0.42
					c.vel.x *= 0.7
					c.bounces += 1
					if c.bounces == 1:
						Sfx.play(self, MachineTab._sound("plonk"), _rng.randf_range(-1.0, 1.0))
				else:
					c.vel.y = 0.0
					c.vel.x *= 0.9
			c.pos.x = clampf(c.pos.x, 80.0, 350.0) if compact else clampf(c.pos.x, 60.0, 460.0)
			if c.t > c.reveal:
				popped.append(c)
		for c in popped:
			_out.erase(c)
			_split(c)
			_pop(c)
		for h in _halves:
			h.t += delta
			h.vel.y += 1100.0 * delta
			h.pos += h.vel * delta
			h.rot += h.spin * delta
		_halves = _halves.filter(func(h): return h.t < 0.6)

	## The capsule breaks into its two halves: the top flies off, the bottom tips over.
	func _split(c: Dictionary) -> void:
		_halves.append({ "pos": c.pos, "vel": Vector2(_rng.randf_range(-80.0, 80.0), -420.0), "rot": c.rot, "spin": _rng.randf_range(-12.0, 12.0), "color": c.color, "top": true, "t": 0.0 })
		_halves.append({ "pos": c.pos, "vel": Vector2(_rng.randf_range(-40.0, 40.0), -120.0), "rot": c.rot, "spin": _rng.randf_range(-5.0, 5.0), "color": c.color, "top": false, "t": 0.0 })

	func _move_bits(delta: float) -> void:
		for b in _bits:
			b.t += delta
			b.vel.y += 700.0 * delta
			b.vel *= 0.985
			b.pos += b.vel * delta
			b.rot += delta * 9.0
		_bits = _bits.filter(func(b): return b.t < b.life)

	# ---- drawing -------------------------------------------------------------------------

	func _draw() -> void:
		var s := _scale()
		var o := _origin()
		if not compact:
			var bg := UiTheme.box(UiTheme.PAPER, UiTheme.LINE, 14, 2, 0)
			draw_style_box(bg, Rect2(Vector2.ZERO, size))
			# the floor, across the whole stage (side by side, the holder draws it)
			var floor_y := o.y + 400.0 * s
			var fl := StyleBoxFlat.new()
			fl.bg_color = UiTheme.PAGE
			fl.corner_radius_bottom_left = 12
			fl.corner_radius_bottom_right = 12
			draw_style_box(fl, Rect2(2, floor_y, size.x - 4, size.y - floor_y - 2))
			draw_line(Vector2(2, floor_y), Vector2(size.x - 2, floor_y), UiTheme.LILAC_SEAM, 3.0)

		draw_set_transform(o, 0.0, Vector2(s, s))
		_draw_rays()
		if compact:
			_ellipse(Vector2(206, 406), 150, 9, Color(UiTheme.DEEP, 0.8), UiTheme.DEEP, false)
		else:
			_ellipse(Vector2(210, 428), 190, 30, UiTheme.PAGE.lerp(UiTheme.LILAC, 0.12), UiTheme.LILAC_SEAM, true)
		# the machine squashes down a little on a clunk
		var squash := sin(_jolt * PI) * _jolt
		draw_set_transform(o + Vector2(0, 410.0 * s * squash * 0.025), 0.0, Vector2(s * (1.0 + squash * 0.015), s * (1.0 - squash * 0.025)))
		_draw_globe()
		_draw_body()
		var pulled_past := _pull > 0.5
		if not pulled_past:
			_draw_lever()
		_draw_flap()
		if pulled_past:
			_draw_lever()
		draw_set_transform(o, 0.0, Vector2(s, s))
		for c in _out:
			# the last part before it opens: it wobbles harder and harder, then puffs up
			var left: float = c.reveal - c.t
			var wob := 0.0
			var puff := 1.0
			if left < 0.55:
				var k := 1.0 - left / 0.55
				wob = sin(c.t * 38.0) * 0.35 * k
				puff = 1.0 + 0.12 * k * k
			if c.gold or c.shiny:
				draw_circle(c.pos, 34.0 * puff, Color(UiTheme.GOLD, 0.12 + 0.06 * sin(_time * 12.0)))
			if c.shiny:
				draw_sparkle(self, c.pos + Vector2(16, -18), 6.0 + 2.0 * sin(_time * 9.0), UiTheme.GOLD)
			draw_set_transform(o + c.pos * s, 0.0, Vector2(s, s) * puff)
			draw_capsule(self, Vector2.ZERO, 20.0, c.color, c.rot + wob)
			draw_set_transform(o, 0.0, Vector2(s, s))
		for h in _halves:
			var a: float = 1.0 - maxf(0.0, h.t - 0.3) / 0.3
			draw_set_transform(o + h.pos * s, h.rot, Vector2(s, s))
			_draw_half(20.0, h.color if h.top else UiTheme.TEXT.lerp(UiTheme.PAGE, 0.12), h.top, a)
			draw_set_transform(o, 0.0, Vector2(s, s))
		for b in _bits:
			var a: float = 1.0 - b.t / b.life
			draw_set_transform(o + b.pos * s, b.rot, Vector2(s, s))
			draw_rect(Rect2(Vector2(-b.size, -b.size) / 2.0, Vector2(b.size, b.size)), Color(b.color, a))
		draw_set_transform(o, 0.0, Vector2(s, s))
		if hand and not compact and int(GameState.machine.pulls) == 0 and not _held and not GameState.tutorial_active():
			_draw_hint()
		for f in _floats:
			_draw_float(f)
		if _popup.visible:
			_draw_prize_rays()
		draw_set_transform(Vector2.ZERO)
		for f in _flying:
			if f.delay > 0.0:
				continue
			var t: float = f.t
			var to := _counter_at()
			var mid: Vector2 = (f.from + to) / 2.0 + f.bend
			var p: Vector2 = f.from.lerp(mid, t).lerp(mid.lerp(to, t), t)
			draw_texture_rect(UiTheme.icon("coin", 16, UiTheme.CYAN), Rect2(p - Vector2(8, 8), Vector2(16, 16)), false)
		if compact:
			_draw_sign()
			_draw_stat()
		if hand:
			_draw_counter()

	## Side by side: the globe's name on a tilted sign above it.
	func _draw_sign() -> void:
		var info := _info()
		var color := MachineTab.globe_color(globe)
		var font := UiTheme.DISPLAY_FONT
		var text := str(info.get("name", globe))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 36.0
		var at := Vector2(_to_screen(Vector2(200, 0)).x, _to_screen(Vector2(0, 8)).y - 20.0)
		var tilt := -0.035 if _is_first else 0.035
		draw_set_transform(at, tilt, Vector2.ONE)
		var rect := Rect2(Vector2(-w / 2.0, -13), Vector2(w, 26))
		var sb := UiTheme.box(UiTheme.RAISED, color, 6, 2, 0)
		sb.shadow_color = UiTheme.SHADOW
		sb.shadow_size = 3
		sb.shadow_offset = Vector2(0, 2)
		draw_style_box(sb, rect)
		draw_texture_rect(UiTheme.icon(str(info.get("icon", "globe_sunny")), 16, color), Rect2(Vector2(-w / 2.0 + 8, -8), Vector2(16, 16)), false)
		draw_string(font, Vector2(-w / 2.0 + 28, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
		draw_set_transform(Vector2.ZERO)

	## Side by side: what it's doing, under it (workers and coins a capsule for the one behind yours;
	## coins a capsule and chutes, or the fever, for yours; nothing for one that doesn't work yet).
	func _draw_stat() -> void:
		var catalog := Catalog.shared()
		if not _works:
			return
		var per := _per
		var coins_line := [[UiTheme.num(per), UiTheme.CYAN], [" coin%s a capsule" % ("" if per < 1.5 else "s"), UiTheme.MUTED]]
		var lines: Array = []
		if hand:
			var left := GameState.fever_left()
			if left > 0.0:
				lines.append([["fever! x%d for %d s" % [int(catalog.machine.fever_pay), ceili(left)], UiTheme.GOLD]])
			else:
				lines.append(coins_line)
			lines.append([["%d chute%s" % [_chutes, "" if _chutes == 1 else "s"], UiTheme.MUTED]])
		else:
			var crew := _crew_n
			if _is_behind and crew > 0:
				lines.append([["%d worker%s" % [crew, "" if crew == 1 else "s"], UiTheme.TEXT]])
			elif _is_behind and _pet_cranks:
				lines.append([["your pet's cranking", UiTheme.TEXT]])
			lines.append(coins_line)
		var font := UiTheme.BODY_FONT
		var cx := _to_screen(Vector2(200, 0)).x
		var y := size.y - BOTTOM + 21.0
		for parts in lines:
			var w := 0.0
			for part in parts:
				w += font.get_string_size(str(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var x := cx - w / 2.0
			for part in parts:
				draw_string(font, Vector2(x, y), str(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, part[1])
				x += font.get_string_size(str(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			y += 15.0

	func _draw_rays() -> void:
		if _fever_level <= 0.0:
			return
		var c := GLOBE + Vector2(0, 60)
		for i in 12:
			var a := _time * 0.6 + TAU * i / 12.0
			var pts := PackedVector2Array([c, c + Vector2(cos(a - 0.09), sin(a - 0.09)) * 330.0, c + Vector2(cos(a + 0.09), sin(a + 0.09)) * 330.0])
			draw_colored_polygon(pts, Color(UiTheme.GOLD, 0.07 * _fever_level))

	func _draw_globe() -> void:
		var tint := _glass_color()
		var glass := UiTheme.PAGE.lerp(tint, 0.09)
		if _fever_level > 0.0:
			draw_circle(GLOBE, GLOBE_R + 14.0, Color(UiTheme.GOLD, 0.10 * _fever_level + 0.04 * sin(_time * 8.0) * _fever_level))
		draw_circle(GLOBE, GLOBE_R, glass)
		if _mended("amber"):
			# amber glass: the whole globe glows warm, like the sky just before bedtime
			draw_circle(GLOBE, GLOBE_R, Color(tint.lerp(UiTheme.GOLD, 0.45), 0.11 + 0.03 * sin(_time * 1.5)))
			draw_circle(GLOBE + Vector2(0, 50), GLOBE_R * 0.7, Color(UiTheme.PINK, 0.05))
		if _broken("nest"):
			_draw_nest_inside()
		for b in _balls:
			draw_capsule(self, b.rest + b.off, 20.0, b.color, b.rot)
		# hides capsules poking out past the glass
		draw_arc(GLOBE, GLOBE_R + 13.0, 0, TAU, 72, UiTheme.PAPER, 26.0, true)
		if _fever_level > 0.0:
			draw_circle(GLOBE, GLOBE_R + 14.0, Color(UiTheme.GOLD, 0.10 * _fever_level))
		draw_arc(GLOBE, GLOBE_R, 0, TAU, 72, tint.lerp(UiTheme.GOLD, _fever_level), 3.5, true)
		var old_glass := _broken("glass")
		var cloudy := old_glass or _broken("amber")
		var shine := Color(UiTheme.TEXT, 0.15 if cloudy else 0.35)
		draw_polyline(_quad(Vector2(126, 96), Vector2(140, 66), Vector2(172, 52), 12), shine, 4.0, true)
		draw_polyline(_quad(Vector2(112, 128), Vector2(113, 118), Vector2(116, 110), 6), shine, 4.0, true)
		if cloudy:
			# old glass: cloudy and scratched
			for h in [[Vector2(150, 110), 60.0], [Vector2(240, 170), 70.0], [Vector2(190, 210), 50.0]]:
				draw_circle(h[0], h[1], Color(UiTheme.TEXT, 0.06))
			for sc in [[Vector2(140, 150), Vector2(170, 138)], [Vector2(230, 90), Vector2(252, 102)], [Vector2(150, 200), Vector2(168, 206)]]:
				draw_line(sc[0], sc[1], Color(UiTheme.MUTED, 0.45), 1.5, true)
		if old_glass:
			# and cracked (taped up once you've fixed that)
			var crack := PackedVector2Array([Vector2(262, 56), Vector2(252, 84), Vector2(266, 104), Vector2(254, 132), Vector2(270, 158)])
			draw_polyline(crack, Color(UiTheme.MUTED, 0.9), 2.5, true)
			draw_line(Vector2(252, 84), Vector2(238, 92), Color(UiTheme.MUTED, 0.7), 1.8, true)
			if _mended("crack"):
				for y in [78.0, 122.0]:
					_tape(Vector2(260, y), -0.5)
		# little holes all over the glass (a capsule keeps dribbling out of one), corked once fixed
		if _broken("holes") or _mended("holes"):
			for h in HOLES:
				if _broken("holes"):
					_ellipse(h, 9.0, 7.0, UiTheme.DEEP, tint, false)
				else:
					_ellipse(h, 9.0, 7.0, CORK, CORK.darkened(0.35), false)
					draw_circle(h + Vector2(-3, -1), 1.3, CORK.darkened(0.35))
			if _broken("holes"):
				var drip := fmod(_time * 0.7, 1.0)
				if drip < 0.8:
					draw_capsule(self, HOLES[1] + Vector2(8.0 + drip * 10.0, 6.0 + drip * 70.0), 9.0, _colors()[1], drip * 3.0)
		_draw_hatch()
		if _broken("nest"):
			_draw_leaves()

	const RUST := Color("8a6448")
	const CORK := Color("d9a066")
	const HOLES := [Vector2(128, 116), Vector2(284, 168), Vector2(180, 238)]

	## The hatch on top: rusted shut until the globe's hatch repair opens it (the sunny globe's is
	## pink; a later globe's hangs crooked and rusty until then).
	func _draw_hatch() -> void:
		var open := _hatch
		var body := _body_color()
		if _is_first or open:
			_rounded(Rect2(160, 22, 80, 18), 7, UiTheme.PAGE.lerp(body, 0.4), body if open else _seam_color(), 3.0)
			if open:
				draw_circle(Vector2(200, 31), 6.0 + sin(_time * 4.0), Color(UiTheme.GOLD, 0.5))
			else:
				for x in [170.0, 230.0]:
					draw_circle(Vector2(x, 31), 3.0, RUST)
					draw_circle(Vector2(x, 31), 1.2, UiTheme.DEEP)
			return
		var pts := _rot_rect(Vector2(200, 30), Vector2(84, 18), -0.08)
		_poly(pts, UiTheme.PAGE.lerp(RUST, 0.45), RUST, 3.0)
		for d in [[Vector2(172, 32), 3.0], [Vector2(222, 27), 3.5], [Vector2(198, 33), 2.0], [Vector2(238, 24), 2.0]]:
			draw_circle(d[0], d[1], RUST.darkened(0.3))

	func _rot_rect(c: Vector2, sz: Vector2, angle: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			pts.append(c + (corner * sz / 2.0).rotated(angle))
		return pts

	## A bird's nest of twigs in the bottom of the globe (before it's shooed out).
	func _draw_nest_inside() -> void:
		var twig := RUST.lightened(0.1)
		for i in 7:
			var y := 246.0 - i * 3.0
			draw_polyline(_quad(Vector2(120 + i * 4, y), Vector2(200, y + 16 - i), Vector2(280 - i * 4, y), 10), twig, 3.0, true)
		draw_line(Vector2(170, 228), Vector2(214, 236), Color(UiTheme.TEXT, 0.7), 2.0, true)  # a feather
		draw_line(Vector2(178, 226), Vector2(182, 234), Color(UiTheme.TEXT, 0.5), 1.5, true)
		draw_line(Vector2(190, 228), Vector2(194, 236), Color(UiTheme.TEXT, 0.5), 1.5, true)

	## Leaves sticking out of the top and the chute (before the nest is shooed out).
	func _draw_leaves() -> void:
		var greens := [UiTheme.MINT.darkened(0.25), UiTheme.GOLD.darkened(0.2), RUST.lightened(0.2), UiTheme.MINT.darkened(0.45)]
		var leaves := [[Vector2(176, 18), -0.9], [Vector2(214, 14), 0.5], [Vector2(236, 22), 1.1], [Vector2(192, 10), -0.2],
			[Vector2(96, 150), 2.4], [Vector2(310, 120), 0.8], [Vector2(214, 404), 0.3], [Vector2(180, 408), -0.6]]
		for i in leaves.size():
			var at: Vector2 = leaves[i][0]
			var ang: float = leaves[i][1] + sin(_time * 1.3 + i) * 0.06
			var pts := PackedVector2Array()
			for k in 12:
				var t := TAU * k / 12.0
				pts.append(at + Vector2(cos(t) * 11.0, sin(t) * 4.5).rotated(ang))
			draw_colored_polygon(pts, greens[i % greens.size()])
			draw_line(at - Vector2(10, 0).rotated(ang), at + Vector2(10, 0).rotated(ang), UiTheme.DEEP, 1.2, true)

	## A strip of tape across the crack.
	func _tape(at: Vector2, angle: float) -> void:
		var d := Vector2(cos(angle), sin(angle))
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([at - d * 22 - n * 7, at + d * 22 - n * 7, at + d * 22 + n * 7, at - d * 22 + n * 7])
		draw_colored_polygon(pts, Color(UiTheme.GOLD.lerp(UiTheme.TEXT, 0.4), 0.75))
		draw_line(pts[1], pts[2], Color(UiTheme.GOLD, 0.6), 1.5)
		draw_line(pts[3], pts[0], Color(UiTheme.GOLD, 0.6), 1.5)

	func _draw_body() -> void:
		var trim := PackedVector2Array()
		trim.append_array(_quad(Vector2(82, 262), Vector2(200, 250), Vector2(318, 262), 14))
		trim.append(Vector2(318, 280))
		trim.append_array(_quad(Vector2(318, 280), Vector2(200, 270), Vector2(82, 280), 14))
		var tone := _body_color()
		_poly(trim, UiTheme.PAGE.lerp(tone, 0.4), tone, 3.0)
		var body := PackedVector2Array()
		body.append_array(_quad(Vector2(92, 278), Vector2(200, 268), Vector2(308, 278), 14))
		body.append(Vector2(322, 408))
		body.append_array(_quad(Vector2(322, 408), Vector2(200, 418), Vector2(78, 408), 14))
		_poly(body, UiTheme.PAGE.lerp(tone, 0.22), tone, 3.5)
		# the lucky lights
		_rounded(Rect2(136, 294, 128, 30), 8, UiTheme.RAISED, UiTheme.GOLD, 2.5)
		var need := Machine.lights_needed(GameState.machine, Catalog.shared())
		var lit := int(GameState.machine.lit)
		if _pips_pop.size() != need:
			_pips_pop.resize(need)
		var w := 112.0 / need
		var r := minf(5.0, w / 2.0 - 1.5)
		var working := _lights
		for i in need:
			var at := Vector2(144.0 + w * (i + 0.5), 309)
			if not working:
				# chewed wires: dead little bulbs until they're rewired
				draw_circle(at, r, UiTheme.DEEP)
				draw_arc(at, r, 0, TAU, 16, UiTheme.LINE, 1.8, true)
				continue
			var on := i < lit and hand
			if _fever_level > 0.0:
				on = int(_time * 14.0) % need == i or int(_time * 14.0 + need / 2.0) % need == i
			var pop: float = _pips_pop[i]
			if on or pop > 0.0:
				draw_circle(at, r + 3.0 + pop * 5.0, Color(UiTheme.GOLD, 0.25 * maxf(pop, 0.5)))
			draw_circle(at, r * (1.0 + pop * 0.5), UiTheme.GOLD if on or pop > 0.0 else UiTheme.DEEP)
			draw_arc(at, r * (1.0 + pop * 0.5), 0, TAU, 16, UiTheme.GOLD, 1.8, true)
		if _broken("lights"):
			# the chewed wire hanging off the lights
			draw_polyline(_quad(Vector2(262, 318), Vector2(282, 330), Vector2(272, 346), 8), UiTheme.MUTED, 2.0, true)
			draw_line(Vector2(272, 346), Vector2(268, 350), UiTheme.GOLD, 2.0, true)
			draw_line(Vector2(272, 346), Vector2(277, 350), UiTheme.GOLD, 2.0, true)
		var rusty := _broken("rust") or _broken("nest")
		if rusty:
			for r_at in [[Vector2(108, 300), 6.0], [Vector2(118, 312), 3.5], [Vector2(292, 388), 5.0], [Vector2(96, 392), 4.0], [Vector2(300, 296), 3.0]]:
				draw_circle(r_at[0], r_at[1], RUST)
		# the lever's mount on the side
		_rounded(Rect2(318, 306, 34, 46), 9, UiTheme.RAISED, RUST if rusty else UiTheme.GOLD, 3.0)

	## One flap per chute along the front (bent-shut chutes aren't there until they're fixed).
	func _draw_flap() -> void:
		var n := _chutes
		var half := minf(32.0, 180.0 / n / 2.0 - 3.0)
		for i in n:
			_draw_one_flap(_chute_x(i, n), half)
		if _broken("flap"):
			var x := _chute_x(0, n)
			draw_capsule(self, Vector2(x + 6, 388), 12.0, UiTheme.MINT, 0.6)
			draw_line(Vector2(x - half + 4, 360), Vector2(x + half - 6, 372), _seam_color(), 3.0, true)

	func _draw_one_flap(x: float, half: float) -> void:
		var slot := PackedVector2Array()
		slot.append_array(_quad(Vector2(x - half, 348), Vector2(x, 342), Vector2(x + half, 348), 8))
		slot.append(Vector2(x + half, 392))
		slot.append_array(_quad(Vector2(x + half, 392), Vector2(x, 396), Vector2(x - half, 392), 8))
		var seam := _seam_color()
		_poly(slot, UiTheme.DEEP, seam, 2.5)
		# the flap: hinged at the top, it swings up towards you as a capsule comes through (its
		# bottom edge rises and it catches the light)
		var open := sin(minf(_flap, 1.0) * PI * 0.5)
		var bottom := lerpf(388.0, 356.0, open)
		var lid := PackedVector2Array()
		var in_half := half - 3.0
		lid.append_array(_quad(Vector2(x - in_half, 353), Vector2(x, 347), Vector2(x + in_half, 353), 8))
		lid.append(Vector2(x + in_half + open * 5.0, bottom))
		lid.append_array(_quad(Vector2(x + in_half + open * 5.0, bottom), Vector2(x, bottom + 4.0), Vector2(x - in_half - open * 5.0, bottom), 8))
		draw_colored_polygon(lid, UiTheme.PAGE.lerp(_body_color(), lerpf(0.14, 0.34, open)))
		draw_line(Vector2(x - minf(10.0, half / 2.0), bottom - 5.0), Vector2(x + minf(10.0, half / 2.0), bottom - 5.0), seam, 2.5, true)
		draw_polyline(_quad(Vector2(x - in_half + 1.0, 354), Vector2(x, 348), Vector2(x + in_half - 1.0, 354), 8), seam, 2.0, true)

	func _draw_lever() -> void:
		var k: Array = _knob(_pull)
		var tip: Vector2 = k[0]
		var r: float = k[1]
		var near: float = k[2]
		# begs a little when it's been a while
		var beg := 0.0
		if hand and _idle > 6.0 and not _held and _spring_t < 0.0:
			beg = maxf(0.0, sin(_time * 5.0)) * 2.5
		tip.y += beg
		if _mended("sag"):
			# the pulley that holds the heavy lever up
			var wheel := Vector2(PIVOT.x + 26.0, PIVOT.y - ARM - 44.0)
			draw_line(wheel + Vector2(-9, 0), tip, Color(UiTheme.PINK, 0.8), 2.0, true)
			draw_line(wheel + Vector2(9, 0), wheel + Vector2(9, 52), Color(UiTheme.PINK, 0.8), 2.0, true)
			draw_arc(wheel, 10.0, 0, TAU, 20, UiTheme.LILAC, 3.0, true)
			draw_circle(wheel, 3.0, UiTheme.LILAC)
			draw_line(wheel + Vector2(0, -10), wheel + Vector2(0, -22), UiTheme.LILAC, 2.5, true)
		draw_line(PIVOT, tip, UiTheme.GOLD, 9.0 * (1.0 + near * 0.5), true)
		draw_circle(PIVOT, 7.0, UiTheme.GOLD)
		draw_arc(PIVOT, 7.0, 0, TAU, 16, UiTheme.DEEP, 2.0, true)
		tip.x += sin(_time * 60.0) * 3.0 * _refused
		var waiting := hand and not _out.is_empty() and not _held
		var knob := UiTheme.PINK.lerp(UiTheme.TEXT, 0.2 if (_hover or _held) and not waiting else 0.0)
		if waiting:
			knob = knob.lerp(UiTheme.PINK_SEAM, 0.55)
		if _hover and not _held and not waiting:
			draw_circle(tip, r + 6.0, Color(UiTheme.PINK, 0.15))
		draw_circle(tip + Vector2(0, r * 0.12), r, UiTheme.DEEP)
		draw_circle(tip, r, knob)
		draw_arc(tip, r, 0, TAU, 32, UiTheme.DEEP, 2.5, true)
		draw_circle(tip - Vector2(r, r) * 0.35, r * 0.26, Color(UiTheme.TEXT, 0.55))

	## Half a capsule, open side down (top) or up (bottom), centred on the origin.
	func _draw_half(r: float, color: Color, top: bool, alpha: float) -> void:
		var pts := PackedVector2Array()
		for i in 17:
			var ang := (PI + PI * i / 16.0) if top else (PI * i / 16.0)
			pts.append(Vector2(cos(ang), sin(ang)) * r)
		draw_colored_polygon(pts, Color(color, alpha))
		var outline := pts.duplicate()
		outline.append(pts[0])
		draw_polyline(outline, Color(UiTheme.DEEP, alpha), 2.0, true)

	func _draw_hint() -> void:
		var font := UiTheme.DISPLAY_FONT
		var bob := sin(_time * 4.0) * 5.0
		draw_string(font, Vector2(368, 222), "pull me!", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiTheme.PINK)
		var x := 392.0
		var y0 := 234.0 + bob
		draw_line(Vector2(x, y0), Vector2(x, y0 + 38), UiTheme.PINK, 2.5, true)
		draw_polyline(PackedVector2Array([Vector2(x - 10, y0 + 28), Vector2(x, y0 + 40), Vector2(x + 10, y0 + 28)]), UiTheme.PINK, 2.5, true)

	func _draw_float(f: Dictionary) -> void:
		var t: float = f.t
		var p: Vector2 = f.pos + Vector2(0, -40.0 * (1.0 - pow(1.0 - t, 3.0)))
		var a := 1.0 if t < 0.6 else (1.0 - t) / 0.4
		var font := UiTheme.DISPLAY_FONT
		var sz: int = f.size
		var w := font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var left := p.x - (w + (18.0 if f.icon else 0.0)) / 2.0
		draw_string_outline(font, Vector2(left, p.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(UiTheme.DEEP, a))
		draw_string(font, Vector2(left, p.y), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(f.color, a))
		if f.icon:
			draw_texture_rect(UiTheme.icon("coin", 16, UiTheme.CYAN), Rect2(Vector2(left + w + 3.0, p.y - 14.0), Vector2(16, 16)), false, Color(1, 1, 1, a))

	## Soft rays turning behind a good prize.
	func _draw_prize_rays() -> void:
		var c := GLOBE + Vector2(0, 30)
		var col := Color(_popup.color, 0.14 * _popup.modulate.a)
		for i in 14:
			var a := _time * 0.8 + TAU * i / 14.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a - 0.1), sin(a - 0.1)) * 170.0, c + Vector2(cos(a + 0.1), sin(a + 0.1)) * 170.0]), col)

	func _draw_counter() -> void:
		var at := _counter_at()
		var pop := sin(_counter_pop * PI) * _counter_pop
		var font := UiTheme.DISPLAY_FONT
		var sz := int(26.0 * (1.0 + pop * 0.12))
		draw_texture_rect(UiTheme.icon("coin", 22, UiTheme.CYAN), Rect2(at + Vector2(-16, -12 - pop * 2.0), Vector2(22, 22)), false)
		draw_string(font, at + Vector2(12, 8), UiTheme.num(_shown_coins), HORIZONTAL_ALIGNMENT_LEFT, -1, sz, UiTheme.TEXT.lerp(UiTheme.CYAN, pop * 0.6))
		if compact:
			return  # side by side, each globe says what a capsule's worth under it
		var left := GameState.fever_left()
		draw_string(UiTheme.BODY_FONT, at + Vector2(-16, 30), _line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.GOLD if left > 0.0 else UiTheme.MUTED)

	## The tape sits at the end of the capsule line, its slip under the line (moved only when the
	## line changes). Side by side there's no line under the counter: it sits after the counter.
	func _place_tape() -> void:
		if not why_tape.visible:
			_placed_for = ""
			return
		var at := _counter_at()
		var key := ("side %d %s" % [UiTheme.num(_shown_coins).length(), at]) if compact else _line
		if key == _placed_for:
			return
		_placed_for = key
		why_tape.size = why_tape.get_combined_minimum_size()
		if compact:
			var num_w := UiTheme.DISPLAY_FONT.get_string_size(UiTheme.num(_shown_coins), HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			why_tape.position = Vector2(at.x + 12.0 + num_w + 12.0, at.y - why_tape.size.y / 2.0)
			why_tape.slip.position = Vector2(at.x - 16.0, at.y + 22.0)
			return
		var line_w := UiTheme.BODY_FONT.get_string_size(_line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		why_tape.position = Vector2(at.x - 16.0 + line_w + 10.0, at.y + 30.0 - why_tape.size.y + 4.0)
		why_tape.slip.position = Vector2(at.x - 16.0, at.y + 42.0)

	## "12 coins a capsule, 2 chutes" under the counter (or the fever's countdown).
	func _counter_line() -> String:
		var left := GameState.fever_left()
		if left > 0.0:
			return "fever! every capsule x%d for %d more seconds" % [int(Catalog.shared().machine.fever_pay), ceili(left)]
		var per := Machine.coin_value(GameState.machine, Catalog.shared(), globe) * GameState.boost("coins")
		var chutes := Machine.chutes(GameState.machine, Catalog.shared(), globe)
		return "%s coin%s a capsule%s" % [UiTheme.num(per), "" if per < 1.5 else "s", ", %d chutes" % chutes if chutes > 1 else ""]

	# ---- drawing helpers ------------------------------------------------------------------

	## A two-tone capsule: a coloured top half and a cream bottom, with a shine.
	static func draw_capsule(ci: CanvasItem, at: Vector2, r: float, color: Color, rot: float) -> void:
		ci.draw_circle(at, r, UiTheme.TEXT.lerp(UiTheme.PAGE, 0.12))
		var half := PackedVector2Array()
		for i in 17:
			var a := rot + PI + PI * i / 16.0
			half.append(at + Vector2(cos(a), sin(a)) * r)
		ci.draw_colored_polygon(half, color)
		ci.draw_line(half[0], half[16], UiTheme.DEEP, 2.0, true)
		ci.draw_arc(at, r, 0, TAU, 28, UiTheme.DEEP, 2.0, true)
		ci.draw_arc(at, r * 0.62, rot + PI * 1.15, rot + PI * 1.55, 8, Color(UiTheme.TEXT, 0.6), 2.2, true)

	static func draw_sparkle(ci: CanvasItem, at: Vector2, r: float, color: Color) -> void:
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI / 2.0
			pts.append(at + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.3))
		ci.draw_colored_polygon(pts, color)

	func _quad(a: Vector2, c: Vector2, b: Vector2, steps: int) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in steps + 1:
			var t := float(i) / steps
			pts.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
		return pts

	func _poly(pts: PackedVector2Array, fill: Color, line: Color, width: float) -> void:
		draw_colored_polygon(pts, fill)
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, line, width, true)

	func _rounded(rect: Rect2, radius: int, fill: Color, line: Color, width: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = fill
		sb.border_color = line
		sb.set_border_width_all(int(round(width)))
		sb.set_corner_radius_all(radius)
		sb.anti_aliasing = true
		draw_style_box(sb, rect)

	func _ellipse(c: Vector2, rx: float, ry: float, fill: Color, line: Color, dashed: bool) -> void:
		var pts := PackedVector2Array()
		for i in 49:
			var a := TAU * i / 48.0
			pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts.slice(0, 48), fill)
		if dashed:
			for i in 48:
				if i % 2 == 0:
					draw_line(pts[i], pts[i + 1], line, 2.5, true)
		else:
			draw_polyline(pts, line, 2.5, true)


## The machine's prize card, taped up next to it like the back of a box: a little "prizes" tag
## (the odds on hover, like a pack in the boxes tab) that flips over into a card of everything a
## capsule can hold and how likely it is (GameState.machine_odds), a lucky capsule's once the
## lights work, and shiny balls once they're fixed. Tap the card to flip it back.
class OddsCard extends Control:
	var tag := Button.new()
	var card := PanelContainer.new()
	var _tween: Tween

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		z_index = UiTheme.Z_CARD  # over the "why so much?" tape at the end of the capsule line
		tag.name = "odds_tag"
		tag.text = "prizes"
		tag.focus_mode = FOCUS_NONE
		tag.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		tag.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		tag.add_theme_font_size_override("font_size", 14)
		for state in ["normal", "hover", "pressed"]:
			var sb := UiTheme.sticker(UiTheme.LILAC if state == "hover" else UiTheme.LILAC_SEAM, 6, UiTheme.RAISED, 0)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 6
			sb.content_margin_bottom = 4
			tag.add_theme_stylebox_override(state, sb)
		for key in ["font_color", "font_hover_color", "font_pressed_color"]:
			tag.add_theme_color_override(key, UiTheme.LILAC)
		tag.rotation_degrees = 4.0
		tag.pressed.connect(func(): flip(true))
		tag.mouse_entered.connect(func(): tag.tooltip_text = MachineTab.odds_text())
		add_child(tag)
		card.name = "odds_card"
		card.visible = false
		card.mouse_filter = MOUSE_FILTER_STOP
		card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		card.add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 8, UiTheme.RAISED, 12))
		card.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				flip(false))
		add_child(card)

	func _ready() -> void:
		# refill while it's open when what it shows changes (a fix, a boost source, a new kind opening)
		GameState.machine_upgraded.connect(_refresh.unbind(1))
		GameState.toys_changed.connect(_refresh)
		GameState.sticker_opened.connect(_refresh.unbind(1))
		GameState.knacks_changed.connect(_refresh)
		GameState.collection.active_changed.connect(_refresh.unbind(1))
		GameState.unlocked.connect(_refresh.unbind(1))
		GameState.tutorial_changed.connect(_refresh)
		_refit.call_deferred()

	func _refresh() -> void:
		if card.visible:
			_fill()

	func _refit() -> void:
		var stage := get_parent() as Control
		if stage:
			place(stage.size)

	func is_open() -> bool:
		return card.visible

	## Flips the tag over into the card (`open`) or back.
	func flip(open: bool) -> void:
		if open == card.visible and (_tween == null or not _tween.is_running()):
			return
		if open:
			_fill()
		var from: Control = card if not open else tag
		var to: Control = tag if not open else card
		from.pivot_offset = from.size / 2.0
		if _tween:
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(from, "scale:x", 0.0, 0.1)
		_tween.tween_callback(func():
			from.visible = false
			from.scale.x = 1.0
			to.visible = true
			to.scale.x = 0.0
			to.pivot_offset = to.get_combined_minimum_size() / 2.0)
		_tween.tween_property(to, "scale:x", 1.0, 0.14)
		Sfx.play(self, MachineTab._sound("tick"), 4.0)

	## Keeps the tag in the top right corner of the stage, and the card inside the stage.
	func place(room: Vector2) -> void:
		size = room
		tag.size = tag.get_combined_minimum_size()
		tag.position = Vector2(room.x - tag.size.x - 16, 14)
		tag.pivot_offset = tag.size / 2.0
		card.size = card.get_combined_minimum_size()
		card.position = Vector2(maxf(8.0, room.x - card.size.x - 10), 10)

	func _fill() -> void:
		UiTheme.clear(card)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.mouse_filter = MOUSE_FILTER_IGNORE
		card.add_child(col)
		col.add_child(UiTheme.title("prizes", 16, UiTheme.LILAC))
		var cols := MachineTab.odds_columns()
		var grid := GridContainer.new()
		grid.columns = 1 + cols.size()
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 3)
		grid.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(grid)
		grid.add_child(Control.new())
		for c in cols:
			grid.add_child(_cell(str(c.name), UiTheme.GOLD if c.lucky else UiTheme.MUTED, true))
		for row in MachineTab.odds_rows(cols):
			var head: bool = row.get("header", false)
			grid.add_child(_cell(str(row.name), UiTheme.GOLD if row.get("shiny", false) else (UiTheme.MUTED if head else UiTheme.TEXT), false))
			for chance in row.chances:
				grid.add_child(_cell(UiTheme.percent(chance) if chance > 0.0 else "", UiTheme.MUTED, true))
		for c in col.get_children() + grid.get_children():
			if c is Control:
				c.mouse_filter = MOUSE_FILTER_IGNORE
		_refit()
		_refit.call_deferred()

	static func _cell(text: String, color: Color, right: bool) -> Label:
		var l := UiTheme.label(text, color, UiTheme.SMALL + 1)
		if right:
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		return l


## A good prize out of the machine, as a picture: a card over the globe with the thing itself (a
## toy, a part, a box, the xp star, a golden coin), its name, a line under it, and a coloured tag.
## "new!" on a toy you didn't have. Pops in, stays a moment, fades.
class PrizePopup extends PanelContainer:
	var color := UiTheme.PINK
	var _col := VBoxContainer.new()
	var _holder := CenterContainer.new()
	var _title := Label.new()
	var _sub := Label.new()
	var _tag := PanelContainer.new()
	var _tag_label := Label.new()
	var _new := Label.new()
	var _tween: Tween

	func _init() -> void:
		visible = false
		mouse_filter = MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(200, 0)
		_col.alignment = BoxContainer.ALIGNMENT_CENTER
		_col.add_theme_constant_override("separation", 4)
		add_child(_col)
		_holder.custom_minimum_size = Vector2(0, 104)
		_col.add_child(_holder)
		_title.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		_title.add_theme_font_size_override("font_size", 20)
		_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_title)
		_sub.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		_sub.add_theme_color_override("font_color", UiTheme.MUTED)
		_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_col.add_child(_sub)
		_tag.size_flags_horizontal = SIZE_SHRINK_CENTER
		_tag_label.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		_tag_label.add_theme_color_override("font_color", UiTheme.DEEP)
		_tag.add_child(_tag_label)
		_col.add_child(_tag)
		_new.text = "new!"
		_new.add_theme_font_override("font", UiTheme.DISPLAY_FONT)
		_new.add_theme_font_size_override("font_size", 15)
		_new.add_theme_color_override("font_color", UiTheme.DEEP)
		var sticker := UiTheme.box(UiTheme.GOLD, UiTheme.GOLD, 8, 0, 0)
		sticker.content_margin_left = 9
		sticker.content_margin_right = 9
		sticker.content_margin_top = 3
		sticker.content_margin_bottom = 3
		_new.add_theme_stylebox_override("normal", sticker)
		_new.rotation_degrees = 10.0
		_new.top_level = false
		add_child(_new)
		for c in [_col, _holder, _title, _sub, _tag, _tag_label, _new]:
			c.mouse_filter = MOUSE_FILTER_IGNORE

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			_new.position = Vector2(size.x - _new.size.x + 12, -12)

	func show_prize(picture: Control, title: String, sub: String, tag: String, tint: Color, is_new := false) -> void:
		color = tint
		for old in _holder.get_children():
			old.queue_free()
		picture.mouse_filter = MOUSE_FILTER_IGNORE
		_holder.add_child(picture)
		_title.text = title
		_title.add_theme_color_override("font_color", tint)
		_sub.text = sub
		_sub.visible = sub != ""
		_tag.visible = tag != ""
		_tag_label.text = tag
		var tag_box := UiTheme.box(tint, tint, 9, 0, 0)
		tag_box.content_margin_left = 10
		tag_box.content_margin_right = 10
		tag_box.content_margin_top = 1
		tag_box.content_margin_bottom = 1
		_tag.add_theme_stylebox_override("panel", tag_box)
		_new.visible = is_new
		var card := UiTheme.box(UiTheme.RAISED, tint, 16, 3, 14)
		card.shadow_color = Color(tint, 0.18)
		card.shadow_size = 10
		add_theme_stylebox_override("panel", card)
		visible = true
		reset_size()
		pivot_offset = size / 2.0
		rotation_degrees = -2.0
		if _tween:
			_tween.kill()
		scale = Vector2(0.5, 0.5)
		modulate.a = 0.0
		_tween = create_tween()
		_tween.set_parallel()
		_tween.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tween.tween_property(self, "modulate:a", 1.0, 0.15)
		_tween.chain().tween_interval(2.6 if is_new else 2.0)
		_tween.chain().tween_property(self, "modulate:a", 0.0, 0.4)
		_tween.chain().tween_callback(func(): visible = false)


## A torn scrap of paper with a crayon map on it: the fence, a gate, and places past it with a "?"
## (the intel that comes out of the machine, opening the next map page).
class MapScrap extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(120, 96)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var paper := PackedVector2Array([Vector2(8, 10), Vector2(40, 4), Vector2(72, 12), Vector2(110, 6), Vector2(114, 40),
			Vector2(108, 70), Vector2(112, 90), Vector2(70, 86), Vector2(44, 92), Vector2(10, 86), Vector2(14, 50)])
		draw_colored_polygon(paper, UiTheme.RAISED.lerp(UiTheme.GOLD, 0.18))
		var edge := paper.duplicate()
		edge.append(paper[0])
		draw_polyline(edge, UiTheme.GOLD, 2.0, true)
		# the fence, with a gate in it
		for x in range(18, 104, 9):
			if x > 52 and x < 70:
				continue
			draw_line(Vector2(x, 70), Vector2(x, 58), UiTheme.MUTED, 2.0, true)
		draw_line(Vector2(16, 64), Vector2(52, 64), UiTheme.MUTED, 2.0, true)
		draw_line(Vector2(70, 64), Vector2(106, 64), UiTheme.MUTED, 2.0, true)
		# a dotted path out through the gate, to places with question marks
		for i in 6:
			draw_circle(Vector2(61, 78) + Vector2(i * 4, -i * 9), 1.6, UiTheme.PINK)
		draw_arc(Vector2(84, 26), 9.0, 0, TAU, 20, UiTheme.MINT, 2.0, true)
		draw_arc(Vector2(34, 30), 7.0, 0, TAU, 20, UiTheme.LILAC, 2.0, true)
		draw_string(UiTheme.DISPLAY_FONT, Vector2(80, 31), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiTheme.MINT)
		draw_string(UiTheme.DISPLAY_FONT, Vector2(30, 35), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiTheme.LILAC)
