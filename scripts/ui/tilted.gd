class_name Tilted
extends Container
## Holds one child at a small angle, like a sticker stuck on a little crooked. Other containers
## reset their children's rotation whenever they lay them out; this one puts it back each time.

var degrees := 0.0:
	set(value):
		degrees = value
		queue_sort()


func _init(child: Control = null, angle := 0.0) -> void:
	degrees = angle
	mouse_filter = MOUSE_FILTER_PASS
	if child:
		add_child(child)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for c in get_children():
			if c is Control:
				fit_child_in_rect(c, Rect2(Vector2.ZERO, size))
				c.pivot_offset = size / 2.0
				c.rotation_degrees = degrees


func _get_minimum_size() -> Vector2:
	var m := Vector2.ZERO
	for c in get_children():
		if c is Control and c.visible:
			m = m.max(c.get_combined_minimum_size())
	return m
