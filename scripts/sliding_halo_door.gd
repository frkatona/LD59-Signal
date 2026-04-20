class_name SlidingHaloDoor
extends Node3D

const SLIDING_DOOR_GROUP := &"sliding_door"
const SONAR_REVEAL_GROUP := &"sonar_reveal"
const SONAR_OCCLUDER_GROUP := &"sonar_occluder"

@export var prompt_text: String = "Press E to open door"
@export var open_animation_name: StringName = &"open"
@export_range(-1.0, 1.0, 0.01) var facing_threshold: float = 0.65

@onready var door_root: Node3D = $door2
@onready var door_panel: MeshInstance3D = $door2/door
@onready var door_frame: MeshInstance3D = $door2/doorframe
@onready var animation_player: AnimationPlayer = $door2/AnimationPlayer
@onready var interaction_area: Area3D = $InteractionArea

var is_open := false
var is_animating := false


func _ready() -> void:
	add_to_group(SLIDING_DOOR_GROUP)
	door_root.add_to_group(SONAR_REVEAL_GROUP)
	door_panel.add_to_group(SONAR_OCCLUDER_GROUP)
	door_frame.add_to_group(SONAR_OCCLUDER_GROUP)

	assert(animation_player != null, "Halo door AnimationPlayer is missing.")
	assert(animation_player.has_animation(open_animation_name), "Halo door open animation is missing.")
	assert(door_panel != null, "Halo door panel mesh is missing.")
	assert(interaction_area != null, "Halo door interaction area is missing.")

	if not animation_player.animation_finished.is_connected(_on_animation_finished):
		animation_player.animation_finished.connect(_on_animation_finished)


func get_prompt_text() -> String:
	return prompt_text


func get_interaction_target_position() -> Vector3:
	return door_panel.global_position


func can_player_interact(player: CharacterBody3D, camera: Camera3D) -> bool:
	if is_open or is_animating or player == null or camera == null:
		return false

	if not interaction_area.overlaps_body(player):
		return false

	var to_target := (get_interaction_target_position() - camera.global_position).normalized()
	var camera_forward := -camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target) >= facing_threshold


func interact() -> void:
	if is_open or is_animating:
		return

	is_animating = true
	animation_player.play(open_animation_name)


func can_open_from_button() -> bool:
	return not is_open and not is_animating


func open_from_button() -> bool:
	if not can_open_from_button():
		return false

	interact()
	return true


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != open_animation_name:
		return

	is_animating = false
	is_open = true
	interaction_area.monitoring = false
	interaction_area.monitorable = false
