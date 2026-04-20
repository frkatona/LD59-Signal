class_name SwingRoomDoor
extends Node3D

const DOOR_OPEN_ANGLE := deg_to_rad(100.0)
const DOOR_OPEN_DURATION := 0.45

@export var open_angle_radians: float = DOOR_OPEN_ANGLE
@export var open_duration_seconds: float = DOOR_OPEN_DURATION

@onready var door_pivot: Node3D = $DoorPivot
@onready var door_body: StaticBody3D = $DoorPivot/Door

var closed_rotation_y := 0.0
var is_open := false
var is_animating := false
var open_tween: Tween


func _ready() -> void:
	assert(door_pivot != null, "SwingRoomDoor is missing DoorPivot.")
	assert(door_body != null, "SwingRoomDoor is missing Door.")
	closed_rotation_y = door_pivot.rotation.y


func can_open_from_button() -> bool:
	return not is_open and not is_animating


func open_from_button() -> bool:
	if not can_open_from_button():
		return false

	is_animating = true
	if is_instance_valid(open_tween):
		open_tween.kill()

	open_tween = create_tween()
	open_tween.tween_property(
		door_pivot,
		"rotation:y",
		closed_rotation_y - open_angle_radians,
		open_duration_seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	open_tween.finished.connect(_on_open_finished, CONNECT_ONE_SHOT)
	return true


func _on_open_finished() -> void:
	is_animating = false
	is_open = true
