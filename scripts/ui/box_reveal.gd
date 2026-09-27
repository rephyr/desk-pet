class_name BoxReveal
extends VBoxContainer
## Shows what came out of the boxes. One pet: a card flip with a glow that hints at the rarity
## and a longer build-up for rare pulls. Many pets: cards pop in one by one, then a summary.

const MAX_CARDS := 60  # beyond this, the summary just counts them
const BASE_SUSPENSE := 0.5
const SUSPENSE_PER_RANK := 0.45

signal again(count: int)
signal done

var _summary: Label
var _head := HBoxContainer.new()
var _title := UiTheme.title("", 22)
var _best := UiTheme.label("", UiTheme.MUTED, UiTheme.SMALL + 1)
var _counts := HBoxContainer.new()
var _actions := HBoxContainer.new()
var _count := 0
var _again: Button
var _can := 0  # boxes left on the pile, for "open N more"
var _stage: Control
var _tween: Tween
var _skip := false


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_summary = UiTheme.label("", UiTheme.MUTED)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.visible = false
	add_child(_summary)
	_head.add_theme_constant_override("separation", 12)
	_head.add_child(_title)
	_best.size_flags_vertical = SIZE_SHRINK_END
	_head.add_child(_best)
	add_child(_head)
	_counts.add_theme_constant_override("separation", 6)
	add_child(_counts)
	_stage = Control.new()
	_stage.size_flags_vertical = SIZE_EXPAND_FILL
	_stage.mouse_filter = MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	add_child(_stage)
	_actions.alignment = BoxContainer.ALIGNMENT_END
	_actions.add_theme_constant_override("separation", 8)
	add_child(_actions)


func play(pets: Array[Pet]) -> void:
	if _tween:
		_tween.kill()
	_skip = false
	UiTheme.clear(_stage)
	if pets.size() == 1:
		_play_single(pets[0])
	elif not pets.is_empty():
		_play_many(pets)


# ---- one pet: suspense, then flip ------------------------------------------

func _play_single(pet: Pet) -> void:
	var catalog := Catalog.shared()
	var rank := catalog.rank(pet.rarity)
	var glow := catalog.tier_color(pet.rarity)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	_stage.add_child(center)
	var holder := Control.new()  # flips around its middle
	holder.custom_minimum_size = Vector2(150, 200)
	holder.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(holder)
	holder.resized.connect(func(): holder.pivot_offset = holder.size / 2.0)

	var back := _card_back(glow)
	holder.add_child(back)
	_summary.text = "opening…"
	_summary.add_theme_color_override("font_color", UiTheme.MUTED)

	_tween = create_tween()
	# the card back pulses brighter the rarer it is; rare pulls make you wait longer
	var suspense := BASE_SUSPENSE + rank * SUSPENSE_PER_RANK
	_tween.tween_property(back, "modulate", Color(1.4, 1.4, 1.4), suspense / 2.0)
	_tween.tween_property(back, "modulate", Color.WHITE, suspense / 2.0)
	_tween.tween_property(holder, "scale:x", 0.0, 0.12)
	_tween.tween_callback(func():
		back.queue_free()
		var card := PetCard.new(pet, 5, true)
		card.set_anchors_preset(PRESET_FULL_RECT)
		card.mouse_filter = MOUSE_FILTER_IGNORE
		holder.add_child(card)
		_announce([pet]))
	_tween.tween_property(holder, "scale:x", 1.0, 0.16)


func _card_back(glow: Color) -> PanelContainer:
	var back := PanelContainer.new()
	back.set_anchors_preset(PRESET_FULL_RECT)
	back.mouse_filter = MOUSE_FILTER_IGNORE  # clicks go to the stage, which skips
	var sb := UiTheme.box(UiTheme.BG_DEEP, glow, 12, 3)
	sb.shadow_color = Color(glow, 0.6)
	sb.shadow_size = 14
	back.add_theme_stylebox_override("panel", sb)
	var mark := UiTheme.icon_rect("boxes", 40, glow)
	mark.size_flags_horizontal = SIZE_SHRINK_CENTER
	back.add_child(mark)
	return back


# ---- many pets: pop in, then summary --------------------------------------

func _play_many(pets: Array[Pet]) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stage.add_child(scroll)
	var flow := GridContainer.new()
	flow.columns = 5
	flow.size_flags_horizontal = SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	pad.add_child(flow)
	scroll.add_child(pad)
	_count = pets.size()
	_title.text = "opening %d boxes…" % pets.size()
	_best.text = ""
	UiTheme.clear(_counts)
	UiTheme.clear(_actions)

	# show the best pulls first so they're never lost past the card limit
	var shown := _best_first(pets).slice(0, MAX_CARDS)
	_tween = create_tween()
	for pet in shown:
		var card := PetCard.new(pet, 3, false)
		card.mouse_filter = MOUSE_FILTER_PASS  # still shows its tooltip, and lets clicks skip
		card.modulate.a = 0.0
		flow.add_child(card)
		_tween.tween_property(card, "modulate:a", 1.0, 0.07)
	_tween.tween_callback(_announce.bind(pets))


func _announce(pets: Array[Pet]) -> void:
	var catalog := Catalog.shared()
	var best: Pet = _best_first(pets)[0]
	var tier_name: String = catalog.tier_at(catalog.rank(best.rarity)).name
	_title.text = "%d pets!" % pets.size() if pets.size() > 1 else best.display_name(catalog)
	_best.text = "best: %s (%s)" % [best.display_name(catalog), tier_name]
	UiTheme.clear(_counts)
	var counts := {}
	for pet in pets:
		counts[pet.rarity] = counts.get(pet.rarity, 0) + 1
	for tier in catalog.tiers:
		if counts.has(tier.id):
			var color := catalog.tier_color(tier.id)
			_counts.add_child(UiTheme.tag("%d %s" % [counts[tier.id], tier.name], color, color.lerp(UiTheme.LINE, 0.55)))
	UiTheme.clear(_actions)
	_again = UiTheme.button("open %d more" % _count, func(): again.emit(_count))
	_actions.add_child(_again)
	set_can_open(_can)
	_actions.add_child(UiTheme.button("lovely!", func(): done.emit()))
	var says: Array = Catalog.shared().reveal.get("pet_says", {}).get("many", [])
	if not says.is_empty():
		var line: String = says[randi() % says.size()]
		PetBubble.say(self, line.replace("{count}", str(pets.size())).replace("{name}", best.display_name(catalog)))


## How many more boxes are on the pile: "open N more" shrinks to fit, or greys out.
func set_can_open(can: int) -> void:
	_can = can
	if _again == null or not is_instance_valid(_again):
		return
	var n := mini(_count, can)
	_again.disabled = n < 1
	_again.text = "open %d more" % n if n > 1 else ("open 1 more" if n == 1 else "the pile is empty")
	_again.tooltip_text = "buy more at the counter" if n < 1 else ""


## Rarest first, then by finish.
static func _best_first(pets: Array[Pet]) -> Array[Pet]:
	var catalog := Catalog.shared()
	var sorted := pets.duplicate()
	sorted.sort_custom(func(a: Pet, b: Pet):
		var ra := catalog.rank(a.rarity)
		var rb := catalog.rank(b.rarity)
		if ra != rb:
			return ra > rb
		return catalog.finish_rank(a.finish) > catalog.finish_rank(b.finish))
	return sorted


func _on_stage_input(event: InputEvent) -> void:
	# click to skip the animation
	if event is InputEventMouseButton and event.pressed and _tween and _tween.is_running():
		_tween.custom_step(60.0)
