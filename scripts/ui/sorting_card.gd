class_name SortingCard
extends PanelContainer
## The sorting rule, a little index card under the new homes stall: off | on, "new pets below
## ‹rare› go to ‹new homes›", and what's always kept (a finish and up, new parts, favourites).
## Steppers, never dropdowns. It only touches pets pulled after it's switched on (GameState._sorter).
## The keeps work whether it's on or off: pets kept there never go anywhere (GameState.spare_pick).
## Once the sewing room's button tin is cleared, keep lines go under the keeps: "keep ‹halos›" keeps
## the newest matching pets from boxes as cards (n/50), whether the rule is on or off (see Sewing).
## Hold it in a Tilted.
## Design: design/mockups/screens/new-homes.html (look A, the rule as an index card).

const EM_W := 44
const STEP_W := 78
const KEEP_W := 84

var _switch: PanelContainer
var _head: HBoxContainer
var _lines := VBoxContainer.new()
var _keeps := HFlowContainer.new()
var _keep_lines := VBoxContainer.new()
var _today := PanelContainer.new()
var _today_n := UiTheme.label("0", UiTheme.LILAC, UiTheme.SMALL - 1)
var _key := ""
var _places: Array[String] = []  # where the rule could send pets when the steppers were built


func _init() -> void:
	var sb := UiTheme.sticker(UiTheme.LILAC.lerp(UiTheme.LINE, 0.55), 10, UiTheme.RAISED, 12)
	sb.border_width_top = 6
	sb.content_margin_top = 10
	add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var name_label := UiTheme.title("sorting", 16, UiTheme.LILAC)
	name_label.size_flags_horizontal = SIZE_EXPAND_FILL
	name_label.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(name_label)
	_head = head
	col.add_child(head)

	_lines.add_theme_constant_override("separation", 4)
	col.add_child(_lines)
	_keeps.add_theme_constant_override("h_separation", 5)
	_keeps.add_theme_constant_override("v_separation", 5)
	col.add_child(_keeps)
	_keep_lines.add_theme_constant_override("separation", 4)
	col.add_child(_keep_lines)

	var sorted := StitchBox.new()
	sorted.bg_color = UiTheme.DEEP
	sorted.dash_color = UiTheme.LILAC.lerp(UiTheme.LINE, 0.6)
	sorted.radius = 999
	sorted.content_margin_left = 8
	sorted.content_margin_right = 8
	sorted.content_margin_top = 1
	sorted.content_margin_bottom = 1
	_today.add_theme_stylebox_override("panel", sorted)
	_today.size_flags_horizontal = SIZE_SHRINK_END
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 5)
	trow.add_child(UiTheme.label("sorted today", UiTheme.MUTED, UiTheme.SMALL - 1))
	trow.add_child(_today_n)
	_today.add_child(trow)
	col.add_child(_today)

	GameState.changed.connect(_tick)
	# the steppers only change with the rule, or when a new rarity or finish turns up
	GameState.homes_rule_changed.connect(_refresh)
	GameState.new_game.connect(_refresh)
	GameState.collection.pets_added.connect(_on_pets_added)
	visibility_changed.connect(_refresh)
	_refresh()


func _on_pets_added(_pets: Array[Pet]) -> void:
	_refresh()


## The "sorted today" count, on every change.
func _tick() -> void:
	if not is_visible_in_tree():
		return
	var text := UiTheme.num(GameState.sorted_today())
	if _today_n.text != text:
		_today_n.text = text
	if GameState.rule_destinations() != _places:  # a new place to send them opened (the school)
		_refresh()


## Rebuilds the steppers when the rule (or what they offer) changed.
func _refresh() -> void:
	if not is_visible_in_tree() and _key != "":
		return
	var rule: Dictionary = GameState.homes.rule
	_today_n.text = UiTheme.num(GameState.sorted_today())
	var rarities := GameState.rule_rarities()
	var finishes := GameState.rule_finishes()
	var places := GameState.rule_destinations()
	_places = places
	var keep_on := GameState.keep_lines_on()
	var picks: Array[String] = []
	var options: Array[String] = []
	if keep_on:
		picks = GameState.keep_lines()
		options = GameState.keep_line_options()
	var key := "%s|%s|%s|%s|%s|%s|%s" % [str(rule), str(rarities), str(finishes), str(places), str(picks), str(options), str(picks.map(func(p): return GameState.kept_count(p)))]
	if key == _key:
		return
	_key = key
	var catalog := GameState.catalog
	if _switch:
		_head.remove_child(_switch)
		_switch.queue_free()
	_switch = UiTheme.segmented(["off", "on"], 1 if rule.on else 0, func(i):
		if (i == 1) == bool(GameState.homes.rule.on):
			return
		GameState.set_rule("on", i == 1)
		PetBubble.say_line(self, "sorting_on" if i == 1 else "sorting_off"))
	for b in _switch.get_child(0).get_children():
		(b as Button).add_theme_font_size_override("font_size", UiTheme.SMALL)
	_head.add_child(_switch)
	UiTheme.clear(_lines)
	var below := stepper(catalog.tier_at(catalog.rank(str(rule.below))).name, catalog.tier_color(str(rule.below)),
		func(d): _step("below", rarities, str(rule.below), d))
	if keep_on:  # keep lines need the room: "new pets below" goes on one line
		var first := _row("new pets below", below)
		first.get_child(0).custom_minimum_size = Vector2(0, 0)
		_lines.add_child(first)
	else:
		_lines.add_child(_em("new pets"))
		_lines.add_child(_row("below", below))
	var to_names := { "homes": "new homes", "work": "work", "school": "school" }
	_lines.add_child(_row("go to", stepper(to_names.get(str(rule.to), str(rule.to)), UiTheme.TEXT,
		func(d): _step("to", places, str(rule.to), d))))
	UiTheme.clear(_keeps)
	var keep := HBoxContainer.new()
	keep.add_theme_constant_override("separation", 3)
	keep.add_child(UiTheme.icon_rect("xp", 12))
	keep.add_child(stepper(str(catalog.finish(str(rule.keep)).name), UiTheme.GOLD, func(d): _step("keep", finishes, str(rule.keep), d), 46))
	keep.add_child(UiTheme.label("and up", UiTheme.TEXT, UiTheme.SMALL))
	_keeps.add_child(_chip(keep))
	if keep_on:  # keep lines need the room: the always-kept ones as their icons, on the same line
		for pair in [["new_part", UiTheme.LILAC, "new parts"], ["heart", UiTheme.PINK, "favourites"]]:
			var icon_chip := _chip(UiTheme.icon_rect(pair[0], 12, pair[1]))
			icon_chip.tooltip_text = pair[2]
			icon_chip.mouse_filter = MOUSE_FILTER_PASS
			_keeps.add_child(icon_chip)
	else:
		_keeps.add_child(_chip(_icon_words("new_part", UiTheme.LILAC, "new parts")))
		_keeps.add_child(_chip(_icon_words("heart", UiTheme.PINK, "favourites")))
	UiTheme.clear(_keep_lines)
	_keep_lines.visible = keep_on
	var cap := Sewing.keep_cap(catalog)
	for i in picks.size():
		var pick: String = picks[i]
		var line := i
		var row := _row("keep", stepper(Sewing.keep_word(catalog, pick), UiTheme.TEXT if pick != "" else UiTheme.MUTED,
			func(d): _step_keep(line, options, pick, d), KEEP_W))
		if pick != "":
			var n := UiTheme.label("%d/%d" % [GameState.kept_count(pick), cap], UiTheme.MUTED, UiTheme.SMALL - 1)
			n.size_flags_vertical = SIZE_SHRINK_CENTER
			row.add_child(n)
		_keep_lines.add_child(row)
	var dim := 1.0 if rule.on else 0.55
	_lines.modulate.a = dim
	_today.modulate.a = dim  # (the keeps stay lit: they keep pets everywhere, the rule on or off)


func _step(key: String, options: Array, now: String, d: int) -> void:
	if options.is_empty():
		return
	var i := options.find(now)
	GameState.set_rule(key, options[clampi(i + d, 0, options.size() - 1)] if i >= 0 else options[0])


func _step_keep(line: int, options: Array, now: String, d: int) -> void:
	var i := options.find(now)
	GameState.set_keep_line(line, options[clampi(i + d, 0, options.size() - 1)] if i >= 0 else options[0])


func _em(text: String) -> Label:
	var l := UiTheme.label(text, UiTheme.MUTED, UiTheme.SMALL)
	return l


func _row(em: String, stepper: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var l := _em(em)
	l.custom_minimum_size = Vector2(EM_W, 0)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(l)
	row.add_child(stepper)
	return row


## ‹ value ›: a stepper (tap the arrows to go through the choices).
## A ‹ value › stepper (the errands' "up to" line uses it too).
static func stepper(value: String, color: Color, on_step: Callable, width := STEP_W) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 8, 2, 1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	p.add_child(row)
	for d in [-1, 1]:
		var b := UiTheme.small_button("‹" if d < 0 else "›", on_step.bind(d))
		b.custom_minimum_size = Vector2(18, 20)
		b.add_theme_font_size_override("font_size", UiTheme.SMALL + 1)
		b.add_theme_color_override("font_color", UiTheme.MUTED)
		b.add_theme_color_override("font_hover_color", UiTheme.PINK)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 0))
		if d > 0:
			var l := UiTheme.label(value, color, UiTheme.SMALL)
			l.custom_minimum_size = Vector2(width, 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l.size_flags_vertical = SIZE_SHRINK_CENTER
			row.add_child(l)
		row.add_child(b)
	return p


func _icon_words(icon: String, color: Color, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(UiTheme.icon_rect(icon, 12, color))
	var l := UiTheme.label(text, UiTheme.TEXT, UiTheme.SMALL)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


func _chip(inner: Control) -> Control:
	var p := PanelContainer.new()
	var sb := UiTheme.box(UiTheme.DEEP, UiTheme.LINE, 999, 2, 0)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(inner)
	return p
