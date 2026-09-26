extends SceneTree
## Renders every part and finish into one picture to eyeball the placeholder art.
##   godot -s tests/look_sheet.gd -- out.png

const PIXEL := 4
const CELL := Vector2(80, 96)

var _canvas: SubViewport


func _init() -> void:
	var catalog := Catalog.shared()
	_canvas = SubViewport.new()
	_canvas.size = Vector2i(720, 600)
	_canvas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_canvas)
	var bg := ColorRect.new()
	bg.color = Color("1a1024")
	bg.size = Vector2(_canvas.size)
	_canvas.add_child(bg)

	var base := { "body": "cat", "palette": "lilac", "pattern": "plain", "eyes": "round", "accessory": "none" }
	var row := 0
	for slot in Catalog.SLOTS:
		var col := 0
		for part in catalog.slots[slot]:
			var parts := base.duplicate()
			parts[slot] = part.id
			_add(parts, "normal", Vector2(col, row), part.id, catalog.tier_color(part.rarity))
			col += 1
		row += 1
	var col := 0
	for f in catalog.finishes:
		_add(base, f.id, Vector2(col, row), f.id, catalog.tier_color(f.rarity))
		col += 1

	for i in 30:
		await process_frame
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://look_sheet.png"
	_canvas.get_texture().get_image().save_png(out)
	quit()


func _add(parts: Dictionary, finish: String, cell: Vector2, label: String, color: Color) -> void:
	var pet := Pet.new()
	pet.parts = parts
	pet.finish = finish
	var view := PetView.new()
	view.pixel = PIXEL
	view.pet = pet
	view.position = cell * CELL + Vector2(CELL.x / 2.0 + 10, CELL.y - 18)
	_canvas.add_child(view)
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 11)
	l.position = cell * CELL + Vector2(14, CELL.y - 16)
	_canvas.add_child(l)
