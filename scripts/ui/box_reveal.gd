class_name BoxReveal
extends VBoxContainer
## Shows what came out of the boxes. One pet: a card flip with a glow that hints at the rarity
## and a longer build-up for rare pulls. Many pets: cards pop in one by one, then a summary.

const MAX_CARDS := 60  # beyond this, the summary just counts them
const BASE_SUSPENSE := 0.5
const SUSPENSE_PER_RANK := 0.45

var _summary: Label
var _stage: Control
var _tween: Tween
var _skip := false


func _init() -> void:
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_summary = UiTheme.label("buy a box to see what's inside ✦", UiTheme.MUTED)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	_stage = Control.new()
	_stage.size_flags_vertical = SIZE_EXPAND_FILL
	_stage.mouse_filter = MOUSE_FILTER_STOP
	_stage.gui_input.connect(_on_stage_input)
	add_child(_stage)


func play(pets: Array[Pet]) -> void:
	if _tween:
		_tween.kill()
	_skip = false
	for child in _stage.get_children():
		child.queue_free()
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
		holder.add_child(card)
		_announce([pet]))
	_tween.tween_property(holder, "scale:x", 1.0, 0.16)


func _card_back(glow: Color) -> PanelContainer:
	var back := PanelContainer.new()
	back.set_anchors_preset(PRESET_FULL_RECT)
	var sb := UiTheme.box(UiTheme.BG_DEEP, glow, 12, 3)
	sb.shadow_color = Color(glow, 0.6)
	sb.shadow_size = 14
	back.add_theme_stylebox_override("panel", sb)
	var mark := UiTheme.label("✦", glow, 40)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back.add_child(mark)
	return back


# ---- many pets: pop in, then summary --------------------------------------

func _play_many(pets: Array[Pet]) -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_stage.add_child(scroll)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(flow)

	# show the best pulls first so they're never lost past the card limit
	var shown := _best_first(pets).slice(0, MAX_CARDS)
	_summary.text = "opening %d boxes…" % pets.size()
	_tween = create_tween()
	for pet in shown:
		var card := PetCard.new(pet, 2, false)
		card.modulate.a = 0.0
		flow.add_child(card)
		_tween.tween_property(card, "modulate:a", 1.0, 0.04)
	_tween.tween_callback(_announce.bind(pets))


func _announce(pets: Array[Pet]) -> void:
	var catalog := Catalog.shared()
	var best: Pet = _best_first(pets)[0]
	var text := "✦ %s %s ✦" % [catalog.tier_at(catalog.rank(best.rarity)).name, best.display_name(catalog)]
	if pets.size() > 1:
		var counts := {}
		for pet in pets:
			counts[pet.rarity] = counts.get(pet.rarity, 0) + 1
		var parts: Array[String] = []
		for tier in catalog.tiers:
			if counts.has(tier.id):
				parts.append("%d %s" % [counts[tier.id], tier.name])
		text = "%d pets · best: %s\n%s" % [pets.size(), text, " · ".join(parts)]
	_summary.text = text
	_summary.add_theme_color_override("font_color", catalog.tier_color(best.rarity))


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
