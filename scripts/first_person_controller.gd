extends CharacterBody3D

const LEFT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_2.wav")
const RIGHT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_3.wav")
const JUMP_STREAM := preload("res://assets/audio/sfx/fist_5.wav")
const LANDING_STREAM := preload("res://assets/audio/sfx/fist_4.wav")
const SIGNAL_SCOPE_SHADER := preload("res://shaders/oscilloscope_signal.gdshader")
const DEFAULT_FOOTSTEP_BUS := &"SFX"
const SIGNAL_ENEMY_GROUP := &"signal_enemy"
const SIGNAL_SCOPE_RESPONSE_SPEED := 2.8

@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var ground_acceleration: float = 20.0
@export var air_acceleration: float = 8.0
@export var footstep_interval_seconds: float = 0.45
@export var footstep_speed_threshold: float = 0.15
@export var signal_scope_min_distance: float = 1.25
@export var signal_scope_max_distance: float = 18.0

@onready var camera_pivot: Node3D = $CameraPivot
@onready var player_camera: Camera3D = $CameraPivot/Camera3D

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var pitch: float = 0.0
var respawn_pitch: float = 0.0
var controls_enabled := false
var footstep_interval_remaining := 0.0
var play_left_footstep_next := true
var left_footstep_player: AudioStreamPlayer
var right_footstep_player: AudioStreamPlayer
var jump_player: AudioStreamPlayer
var landing_player: AudioStreamPlayer
var signal_scope_display: MeshInstance3D
var signal_scope_material: ShaderMaterial
var signal_scope_strength: float = 0.0


func _ready() -> void:
	respawn_pitch = camera_pivot.rotation.x
	_create_footstep_players()
	_create_signal_scope_display()
	set_controls_enabled(false, false)


func set_controls_enabled(enabled: bool, capture_mouse: bool = true) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		_reset_footstep_cycle()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	if capture_mouse:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(delta: float) -> void:
	_update_signal_scope(delta)


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

	var was_on_floor := is_on_floor()
	if not was_on_floor:
		velocity.y -= gravity * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = jump_velocity
		_play_jump_sound()

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
	if not was_on_floor and is_on_floor():
		_play_landing_sound()
		footstep_interval_remaining = footstep_interval_seconds
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

	jump_player = AudioStreamPlayer.new()
	jump_player.name = "JumpPlayer"
	jump_player.stream = JUMP_STREAM
	jump_player.bus = _resolve_footstep_bus()
	add_child(jump_player)

	landing_player = AudioStreamPlayer.new()
	landing_player.name = "LandingPlayer"
	landing_player.stream = LANDING_STREAM
	landing_player.bus = _resolve_footstep_bus()
	add_child(landing_player)


func _create_signal_scope_display() -> void:
	if DisplayServer.get_name() == "headless" or player_camera == null:
		return

	signal_scope_display = MeshInstance3D.new()
	signal_scope_display.name = "SignalScopeDisplay"
	signal_scope_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	signal_scope_display.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	signal_scope_display.position = Vector3(0.345, -0.165, -0.68)
	signal_scope_display.rotation_degrees = Vector3(-8.0, -18.0, 0.0)

	var scope_mesh := QuadMesh.new()
	scope_mesh.size = Vector2(0.16, 0.1)
	signal_scope_display.mesh = scope_mesh

	signal_scope_material = ShaderMaterial.new()
	signal_scope_material.shader = SIGNAL_SCOPE_SHADER
	signal_scope_material.set_shader_parameter("signal_strength", 0.0)
	signal_scope_display.material_override = signal_scope_material

	player_camera.add_child(signal_scope_display)


func _resolve_footstep_bus() -> StringName:
	return DEFAULT_FOOTSTEP_BUS if AudioServer.get_bus_index(DEFAULT_FOOTSTEP_BUS) != -1 else &"Master"


func _update_signal_scope(delta: float) -> void:
	if signal_scope_material == null:
		return

	var target_strength: float = _get_signal_scope_target_strength()
	signal_scope_strength = move_toward(signal_scope_strength, target_strength, SIGNAL_SCOPE_RESPONSE_SPEED * delta)
	signal_scope_material.set_shader_parameter("signal_strength", signal_scope_strength)


func _get_signal_scope_target_strength() -> float:
	var clamped_min_distance: float = maxf(signal_scope_min_distance, 0.0)
	var clamped_max_distance: float = maxf(signal_scope_max_distance, clamped_min_distance + 0.001)
	var nearest_enemy_distance: float = clamped_max_distance
	var has_enemy := false

	for enemy_node in get_tree().get_nodes_in_group(SIGNAL_ENEMY_GROUP):
		var enemy_body := enemy_node as Node3D
		if enemy_body == null:
			continue

		has_enemy = true
		var enemy_distance: float = global_position.distance_to(enemy_body.global_position)
		nearest_enemy_distance = minf(nearest_enemy_distance, enemy_distance)

	if not has_enemy:
		return 0.0

	if nearest_enemy_distance <= clamped_min_distance:
		return 1.0

	if nearest_enemy_distance >= clamped_max_distance:
		return 0.0

	return 1.0 - inverse_lerp(clamped_min_distance, clamped_max_distance, nearest_enemy_distance)


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


func _play_jump_sound() -> void:
	if jump_player == null:
		return

	jump_player.bus = _resolve_footstep_bus()
	jump_player.play()


func _play_landing_sound() -> void:
	if landing_player == null:
		return

	landing_player.bus = _resolve_footstep_bus()
	landing_player.play()


func _reset_footstep_cycle() -> void:
	footstep_interval_remaining = 0.0
	play_left_footstep_next = true
	if left_footstep_player != null:
		left_footstep_player.stop()
	if right_footstep_player != null:
		right_footstep_player.stop()
	if jump_player != null:
		jump_player.stop()
	if landing_player != null:
		landing_player.stop()
