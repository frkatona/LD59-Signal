class_name DoorButton
extends Node3D

const DOOR_BUTTON_GROUP := &"door_button"
const SONAR_REVEAL_GROUP := &"sonar_reveal"
const BUTTON_ANIMATION_NAME := &"switch-down"
const SFX_BUS_NAME := &"SFX"
const SWITCH_ACTIVATE_SFX := preload("res://assets/audio/sfx/fist_5.wav")

@export var prompt_text: String = "Press E to open door"
@export_range(-1.0, 1.0, 0.01) var facing_threshold: float = 0.65
@export var target_door_path: NodePath

@onready var interaction_area: Area3D = $InteractionArea

var button_root: Node3D
var animation_player: AnimationPlayer
var target_door: Node
var activate_sfx_player: AudioStreamPlayer3D
var is_pressed := false


func _ready() -> void:
	button_root = _resolve_button_root()
	add_to_group(DOOR_BUTTON_GROUP)
	if button_root != null:
		button_root.add_to_group(SONAR_REVEAL_GROUP)

	animation_player = _find_animation_player(button_root)
	target_door = _resolve_target_door()
	if target_door == null:
		push_warning("DoorButton target door is missing for %s." % [name])

	_configure_activate_sfx()


func get_prompt_text() -> String:
	return prompt_text


func get_signal_source_position() -> Vector3:
	if button_root != null:
		return button_root.global_position

	return global_position


func can_player_interact(player: CharacterBody3D, camera: Camera3D) -> bool:
	if is_pressed or player == null or camera == null or interaction_area == null or button_root == null:
		return false

	if not _can_target_open():
		return false

	if not interaction_area.overlaps_body(player):
		return false

	var to_target := (button_root.global_position - camera.global_position).normalized()
	var camera_forward := -camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target) >= facing_threshold


func interact() -> bool:
	if is_pressed or not _can_target_open():
		return false

	var opened := bool(target_door.call("open_from_button"))
	if not opened:
		return false

	is_pressed = true
	if interaction_area != null:
		interaction_area.monitoring = false
		interaction_area.monitorable = false

	if animation_player != null and animation_player.has_animation(BUTTON_ANIMATION_NAME):
		animation_player.play(BUTTON_ANIMATION_NAME)

	if activate_sfx_player != null:
		activate_sfx_player.play()

	return true


func _can_target_open() -> bool:
	if target_door == null or not is_instance_valid(target_door):
		target_door = _resolve_target_door()
		if target_door == null:
			return false

	if target_door.has_method("can_open_from_button"):
		return bool(target_door.call("can_open_from_button"))

	return false


func _resolve_target_door() -> Node:
	var explicit_target := get_node_or_null(target_door_path)
	if explicit_target != null:
		return explicit_target

	var current: Node = get_parent()
	while current != null:
		var candidate := _find_openable_door(current)
		if candidate != null:
			return candidate

		current = current.get_parent()

	return null


func _find_openable_door(root: Node) -> Node:
	if root == null or root == self:
		return null

	if root.has_method("open_from_button") and root.has_method("can_open_from_button"):
		return root

	for child in root.get_children():
		var candidate := _find_openable_door(child)
		if candidate != null:
			return candidate

	return null


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null

	if root is AnimationPlayer:
		return root as AnimationPlayer

	for child in root.get_children():
		var candidate := _find_animation_player(child)
		if candidate != null:
			return candidate

	return null


func _resolve_button_root() -> Node3D:
	var preferred_names := [&"light-switch", &"blackplasticframe"]
	for node_name in preferred_names:
		var candidate := get_node_or_null(NodePath(String(node_name))) as Node3D
		if candidate != null:
			return candidate

	return self


func _configure_activate_sfx() -> void:
	if DisplayServer.get_name() == "headless":
		return

	var audio_parent := button_root if button_root != null else self
	activate_sfx_player = AudioStreamPlayer3D.new()
	activate_sfx_player.name = "SwitchActivatePlayer3D"
	activate_sfx_player.stream = SWITCH_ACTIVATE_SFX
	activate_sfx_player.bus = SFX_BUS_NAME
	activate_sfx_player.max_distance = 14.0
	activate_sfx_player.unit_size = 3.0
	audio_parent.add_child(activate_sfx_player)
