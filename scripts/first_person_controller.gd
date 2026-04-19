extends CharacterBody3D

const LEFT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_2.wav")
const RIGHT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_3.wav")
const DEFAULT_FOOTSTEP_BUS := &"SFX"

@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var ground_acceleration: float = 20.0
@export var air_acceleration: float = 8.0
@export var footstep_interval_seconds: float = 0.45
@export var footstep_speed_threshold: float = 0.15

@onready var camera_pivot: Node3D = $CameraPivot

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var pitch: float = 0.0
var respawn_pitch: float = 0.0
var controls_enabled := true
var footstep_interval_remaining := 0.0
var play_left_footstep_next := true
var left_footstep_player: AudioStreamPlayer
var right_footstep_player: AudioStreamPlayer


func _ready() -> void:
	respawn_pitch = camera_pivot.rotation.x
	_create_footstep_players()
	set_controls_enabled(true)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		_reset_footstep_cycle()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func respawn_at(target_transform: Transform3D) -> void:
	global_transform = target_transform
	velocity = Vector3.ZERO
	pitch = respawn_pitch
	camera_pivot.rotation.x = respawn_pitch
	_reset_footstep_cycle()


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-85.0), deg_to_rad(85.0))
		camera_pivot.rotation.x = pitch
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity

	var input_vector := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		input_vector.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		input_vector.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		input_vector.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		input_vector.x += 1.0

	input_vector = input_vector.normalized()

	var direction := (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var target_velocity := direction * move_speed
	var acceleration := ground_acceleration if is_on_floor() else air_acceleration

	velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	move_and_slide()
	_update_footsteps(delta)


func _create_footstep_players() -> void:
	if DisplayServer.get_name() == "headless":
		return

	left_footstep_player = AudioStreamPlayer.new()
	left_footstep_player.name = "LeftFootstepPlayer"
	left_footstep_player.stream = LEFT_FOOTSTEP_STREAM
	left_footstep_player.bus = _resolve_footstep_bus()
	add_child(left_footstep_player)

	right_footstep_player = AudioStreamPlayer.new()
	right_footstep_player.name = "RightFootstepPlayer"
	right_footstep_player.stream = RIGHT_FOOTSTEP_STREAM
	right_footstep_player.bus = _resolve_footstep_bus()
	add_child(right_footstep_player)


func _resolve_footstep_bus() -> StringName:
	return DEFAULT_FOOTSTEP_BUS if AudioServer.get_bus_index(DEFAULT_FOOTSTEP_BUS) != -1 else &"Master"


func _update_footsteps(delta: float) -> void:
	if not is_on_floor():
		footstep_interval_remaining = 0.0
		return

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < footstep_speed_threshold:
		footstep_interval_remaining = 0.0
		return

	footstep_interval_remaining -= delta
	if footstep_interval_remaining > 0.0:
		return

	_play_footstep()
	footstep_interval_remaining = footstep_interval_seconds


func _play_footstep() -> void:
	var player := left_footstep_player if play_left_footstep_next else right_footstep_player
	if player == null:
		return

	player.bus = _resolve_footstep_bus()
	player.play()
	play_left_footstep_next = not play_left_footstep_next


func _reset_footstep_cycle() -> void:
	footstep_interval_remaining = 0.0
	play_left_footstep_next = true
	if left_footstep_player != null:
		left_footstep_player.stop()
	if right_footstep_player != null:
		right_footstep_player.stop()
