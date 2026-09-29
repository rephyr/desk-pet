class_name EdgeCard
extends PanelContainer
## The edge's side card (C2 look A), at the top of the adventures page's right column once the
## signpost on the beyond map is tapped: the shelves of resting herd pets and 1 / 10 / 100 / all.
## Pets sent fly off towards the signpost and never come back; your pet cheers, always the same.

var target := Callable()  # () -> Vector2: where on screen the pets fly to (the signpost)
var fly_host: Control  # what the flying faces hang off (stays up when a full page hides this card)
var picker := HerdPicker.new()


func _init() -> void:
	add_theme_stylebox_override("panel", UiTheme.sticker(UiTheme.LILAC_SEAM, 12, UiTheme.RAISED, 12))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	head.add_child(UiTheme.icon_rect("sign", 22, UiTheme.PINK))
	head.add_child(UiTheme.title("the edge", 18))
	col.add_child(head)
	col.add_child(picker)
	picker.take.connect(_send)
	visibility_changed.connect(func():
		if is_visible_in_tree():
			refresh())


func refresh() -> void:
	picker.cap = GameState.edge_to_go()
	picker.refresh()


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()  # cheap unless a count changed


func _send(rarity: String, n: int) -> void:
	var from := picker.row_point(rarity)
	var faces: Array[Pet] = []
	for i in 5:
		var p := HerdPicker.face_of(rarity, i * 3 + 1)
		if p:
			faces.append(p)
	var sent := GameState.send_past_edge(rarity, n)
	if sent <= 0:
		return
	PetBubble.say_line(self, "edge_cheer")
	refresh()
	_fly(faces.slice(0, clampi(sent, 1, 5)), from)


## A few faces hop off the shelf towards the signpost and fade.
func _fly(faces: Array[Pet], from: Vector2) -> void:
	var to: Vector2 = target.call() if target.is_valid() else from + Vector2(-200, 0)
	for i in faces.size():
		var face := PetPortrait.new(2, false)
		face.set_pet(faces[i])
		face.top_level = true
		face.mouse_filter = MOUSE_FILTER_IGNORE
		face.z_index = 20
		(fly_host if is_instance_valid(fly_host) else self).add_child(face)
		var half := face.get_combined_minimum_size() / 2.0  # no layout pass yet: size is still zero
		face.global_position = from - half + Vector2(i * 6 - 12, 0)
		var t := face.create_tween().set_parallel()
		var end := to - half + Vector2(randf_range(-10, 10), randf_range(-8, 8))
		t.tween_property(face, "global_position", end, 0.75).set_delay(i * 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		t.tween_property(face, "modulate:a", 0.0, 0.75).set_delay(i * 0.08).set_ease(Tween.EASE_IN)
		t.chain().tween_callback(face.queue_free)
