class_name PetPortrait
extends Control
## A PetView that fits into UI layouts: sized for its pixel scale, pet centred, feet at the bottom.

signal clicked

var view := PetView.new()


func _init(pixel_size := 4, animated := true) -> void:
	view.pixel = pixel_size
	view.animated = animated
	custom_minimum_size = PetView.size_for(pixel_size) + Vector2(0, pixel_size * 2)
	size = custom_minimum_size  # so it's right even where no container sizes it
	mouse_filter = MOUSE_FILTER_PASS
	add_child(view)
	resized.connect(_place)


func _ready() -> void:
	_place()  # a portrait that's never resized still needs its pet placed


func set_pet(pet: Pet, silhouette := false) -> void:
	view.pet = pet
	view.silhouette = silhouette


func _place() -> void:
	view.position = Vector2(size.x / 2.0, size.y - view.pixel)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
