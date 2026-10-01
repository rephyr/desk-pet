class_name PetView
extends Node2D
## Draws a pet with its finish effect and a bit of life (idle bob, blinking, squash).
## The origin is at the pet's feet, centred.

const FINISH_SHADER := preload("res://shaders/finish.gdshader")
const SILHOUETTE_MODE := 6  # see shaders/finish.gdshader

## Pixel size on screen for one art pixel.
@export var pixel := 4
## Draw as a dark shape only (undiscovered entries in the book).
@export var silhouette := false:
	set(value):
		silhouette = value
		_refresh()
## Set false for still pictures (e.g. lots of cards): no per-frame work at all.
@export var animated := true:
	set(value):
		animated = value
		set_process(value and is_visible_in_tree())

var pet: Pet:
	set(value):
		pet = value
		_refresh()

var facing := 1  # 1 right, -1 left
var walking := false
var squash := 0.0  # 0..1, springs back on its own

var _time := randf() * 10.0
var _blink := randf_range(1.0, 4.0)
var _material := _make_material()
var _texture: Texture2D
var _blink_texture: Texture2D
var _top_row := -1  # the first row of its picture with anything in it (-1: not looked up yet)


static func size_for(pixel_size: int) -> Vector2:
	return Vector2(PetLook.W, PetLook.H) * pixel_size


## Where the top of its picture is right now, from its feet (negative: up), with the bob and the
## squash (for things it wears on its head).
func top() -> float:
	var bob := 0.0
	if animated:
		bob = roundf(-absf(sin(_time * 12.0)) * pixel if walking else sin(_time * 2.0) * 0.5 * pixel)
	if _top_row < 0:
		_top_row = PetLook.top_row(pet.parts, pet.sewn) if pet != null else 0
	return bob - (size_for(pixel).y - _top_row * pixel) * (1.0 - squash * 0.3)


static func _make_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FINISH_SHADER
	m.set_shader_parameter("seed", randf() * 10.0)
	return m


func _init() -> void:
	# pixel art: always sharp, even in windows that don't use the project's default filter
	# (like the desktop overlay, which is its own viewport)
	texture_filter = TEXTURE_FILTER_NEAREST


func _ready() -> void:
	set_process(animated and is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:  # hidden (its tab closed): it stops bobbing and redrawing
		set_process(animated and is_visible_in_tree())


func _process(delta: float) -> void:
	if pet == null:
		return
	_time += delta
	_blink -= delta
	if _blink < -0.12:
		_blink = randf_range(2.0, 5.0)
	squash = move_toward(squash, 0.0, delta * 4.0)
	queue_redraw()


func _refresh() -> void:
	if pet == null:
		queue_redraw()  # clear the old picture (e.g. after a new game)
		return
	_texture = PetLook.texture_for(pet.parts, false, pet.sewn)
	_blink_texture = PetLook.texture_for(pet.parts, true, pet.sewn)
	_top_row = -1
	var mode: int = SILHOUETTE_MODE if silhouette else int(Catalog.shared().finish(pet.finish).shader)
	_material.set_shader_parameter("mode", mode)
	material = _material if mode != 0 else null
	queue_redraw()


func _draw() -> void:
	if pet == null:
		return
	var tex := _blink_texture if animated and _blink < 0.0 else _texture
	var s := size_for(pixel)
	var bob := 0.0
	if animated:
		bob = -absf(sin(_time * 12.0)) * pixel if walking else sin(_time * 2.0) * 0.5 * pixel
		bob = roundf(bob)
	draw_set_transform(Vector2(0, bob), 0.0, Vector2((1.0 + squash * 0.25) * facing, 1.0 - squash * 0.3))
	draw_texture_rect(tex, Rect2(Vector2(-s.x / 2.0, -s.y), s), false)
