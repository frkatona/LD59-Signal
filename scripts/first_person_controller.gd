extends CharacterBody3D

const LEFT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_2.wav")
const RIGHT_FOOTSTEP_STREAM := preload("res://assets/audio/sfx/fist_3.wav")
const JUMP_STREAM := preload("res://assets/audio/sfx/fist_5.wav")
const LANDING_STREAM := preload("res://assets/audio/sfx/fist_4.wav")
const PUSH_STREAM := preload("res://assets/audio/sfx/fist_1.wav")
const SIGNAL_SCOPE_SHADER := preload("res://shaders/oscilloscope_signal.gdshader")
const DEFAULT_FOOTSTEP_BUS := &"SFX"
const SIGNAL_ENEMY_GROUP := &"signal_enemy"
const SIGNAL_SCOPE_RESPONSE_SPEED := 2.8
const PUSH_HIT_PITCH := 1.0
const PUSH_MISS_PITCH := 1.3

@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var ground_acceleration: float = 20.0
@export var air_acceleration: float = 8.0
@export var push_velocity: float = 6
@export var push_cooldown_seconds: float = 5.0
@export var footstep_interval_seconds: float = 0.45
@export var footstep_speed_threshold: float = 0.15
@export var signal_scope_min_distance: float = 1.25
@export var signal_scope_max_distance: float = 18.0
@export_group("Signal Scope")
@export var signal_scope_local_position: Vector3 = Vector3(0.345, -0.165, -0.68)
@export var signal_scope_local_rotation_degrees: Vector3 = Vector3(-8.0, -18.0, 0.0)
@export var signal_scope_size: Vector2 = Vector2(0.16, 0.1)
@export_range(0.0, 0.5, 0.005) var signal_scope_corner_radius: float = 0.08
@export_range(0.001, 0.1, 0.001) var signal_scope_corner_softness: float = 0.015
@export var signal_scope_overlay_padding: Vector2 = Vector2(56.0, 42.0)
@export_group("")

@onready var camera_pivot: Node3D = $CameraPivot
@onready var player_camera: Camera3D = $CameraPivot/Camera3D
@onready var push_area: Area3D = %PushArea
@onready var oscilloscope_model: Node3D = get_node_or_null("oscilloscope")

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
var push_player: AudioStreamPlayer
var signal_scope_display: MeshInstance3D
var signal_scope_material: ShaderMaterial
var signal_scope_strength: float = 0.0
var push_cooldown_remaining: float = 0.0


func _ready() -> void:
	respawn_pitch = camera_pivot.rotation.x
	_create_footstep_players()
	_attach_oscilloscope_model_to_camera()
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
	if push_cooldown_remaining > 0.0:
		push_cooldown_remaining = maxf(push_cooldown_remaining - delta, 0.0)

	_sync_signal_scope_display_configuration()
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
	
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		do_push()


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

	push_player = AudioStreamPlayer.new()
	push_player.name = "PushPlayer"
	push_player.stream = PUSH_STREAM
	push_player.bus = _resolve_footstep_bus()
	add_child(push_player)


func _create_signal_scope_display() -> void:
	if DisplayServer.get_name() == "headless" or player_camera == null:
		return

	var scope_parent: Node3D = oscilloscope_model if oscilloscope_model != null else player_camera
	signal_scope_display = MeshInstance3D.new()
	signal_scope_display.name = "SignalScopeDisplay"
	signal_scope_display.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	signal_scope_display.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	scope_parent.add_child(signal_scope_display)

	var scope_mesh := QuadMesh.new()
	signal_scope_display.mesh = scope_mesh

	signal_scope_material = ShaderMaterial.new()
	signal_scope_material.shader = SIGNAL_SCOPE_SHADER
	signal_scope_material.set_shader_parameter("signal_strength", 0.0)
	signal_scope_display.material_override = signal_scope_material
	_sync_signal_scope_display_configuration()


func _attach_oscilloscope_model_to_camera() -> void:
	if oscilloscope_model == null or player_camera == null:
		return

	if oscilloscope_model.get_parent() == player_camera:
		return

	oscilloscope_model.reparent(player_camera, true)


func _sync_signal_scope_display_configuration() -> void:
	if signal_scope_display == null:
		return

	signal_scope_display.position = signal_scope_local_position
	signal_scope_display.rotation_degrees = signal_scope_local_rotation_degrees
	if signal_scope_material != null:
		signal_scope_material.set_shader_parameter("corner_radius", signal_scope_corner_radius)
		signal_scope_material.set_shader_parameter("corner_softness", signal_scope_corner_softness)

	var scope_mesh := signal_scope_display.mesh as QuadMesh
	if scope_mesh == null:
		return

	scope_mesh.size = signal_scope_size


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


func get_signal_scope_overlay_cutout(viewport_size: Vector2) -> Dictionary:
	if player_camera == null:
		return {}

	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return {}

	var projected_bounds: Dictionary = {}
	if oscilloscope_model != null:
		projected_bounds = _get_projected_screen_bounds(oscilloscope_model)

	if projected_bounds.is_empty() and signal_scope_display != null:
		projected_bounds = _get_projected_screen_bounds(signal_scope_display)

	if projected_bounds.is_empty():
		return {}

	var min_screen: Vector2 = projected_bounds["min"]
	var max_screen: Vector2 = projected_bounds["max"]

	min_screen -= signal_scope_overlay_padding
	max_screen += signal_scope_overlay_padding

	var rect_center := (min_screen + max_screen) * 0.5
	var rect_half_size := (max_screen - min_screen) * 0.5

	return {
		"center_uv": Vector2(
			clampf(rect_center.x / viewport_size.x, 0.0, 1.0),
			clampf(rect_center.y / viewport_size.y, 0.0, 1.0)
		),
		"half_size_uv": Vector2(
			clampf(rect_half_size.x / viewport_size.x, 0.0, 0.5),
			clampf(rect_half_size.y / viewport_size.y, 0.0, 0.5)
		),
		"corner_radius_uv": _get_signal_scope_overlay_corner_radius_uv(rect_half_size, viewport_size),
		"corner_softness_uv": _get_signal_scope_overlay_corner_softness_uv(rect_half_size, viewport_size),
	}


func _get_projected_screen_bounds(root: Node3D) -> Dictionary:
	var mesh_instances: Array[MeshInstance3D] = []
	_collect_mesh_instances(root, mesh_instances)
	if mesh_instances.is_empty():
		return {}

	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	var has_visible_point := false

	for mesh_instance in mesh_instances:
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue

		for corner in _get_aabb_corners(mesh.get_aabb()):
			var world_point := mesh_instance.to_global(corner)
			if player_camera.is_position_behind(world_point):
				continue

			var screen_point := player_camera.unproject_position(world_point)
			min_screen.x = minf(min_screen.x, screen_point.x)
			min_screen.y = minf(min_screen.y, screen_point.y)
			max_screen.x = maxf(max_screen.x, screen_point.x)
			max_screen.y = maxf(max_screen.y, screen_point.y)
			has_visible_point = true

	if not has_visible_point:
		return {}

	return {
		"min": min_screen,
		"max": max_screen,
	}


func _collect_mesh_instances(root: Node, target: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D:
		target.append(root)

	for child in root.get_children():
		_collect_mesh_instances(child, target)


func _get_aabb_corners(aabb: AABB) -> Array[Vector3]:
	var position := aabb.position
	var size := aabb.size
	return [
		position,
		position + Vector3(size.x, 0.0, 0.0),
		position + Vector3(0.0, size.y, 0.0),
		position + Vector3(0.0, 0.0, size.z),
		position + Vector3(size.x, size.y, 0.0),
		position + Vector3(size.x, 0.0, size.z),
		position + Vector3(0.0, size.y, size.z),
		position + size,
	]


func _get_signal_scope_overlay_corner_radius_uv(rect_half_size: Vector2, viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0.0

	var half_size_uv := Vector2(
		rect_half_size.x / viewport_size.x,
		rect_half_size.y / viewport_size.y
	)
	return clampf(minf(half_size_uv.x, half_size_uv.y) * 2.0 * signal_scope_corner_radius, 0.0, 0.5)


func _get_signal_scope_overlay_corner_softness_uv(rect_half_size: Vector2, viewport_size: Vector2) -> float:
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 0.0

	var half_size_uv := Vector2(
		rect_half_size.x / viewport_size.x,
		rect_half_size.y / viewport_size.y
	)
	return clampf(minf(half_size_uv.x, half_size_uv.y) * 2.0 * signal_scope_corner_softness, 0.0001, 0.5)


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


func _play_push_sound(hit_enemy: bool) -> void:
	if push_player == null:
		return

	push_player.bus = _resolve_footstep_bus()
	push_player.pitch_scale = PUSH_HIT_PITCH if hit_enemy else PUSH_MISS_PITCH
	push_player.play()


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
	if push_player != null:
		push_player.stop()


func get_push_cooldown_state() -> Dictionary:
	var cooldown_duration: float = maxf(push_cooldown_seconds, 0.001)
	return {
		"duration": cooldown_duration,
		"remaining": minf(push_cooldown_remaining, cooldown_duration),
	}


func do_push() -> void:
	if push_cooldown_remaining > 0.0:
		return

	push_cooldown_remaining = maxf(push_cooldown_seconds, 0.0)
	print("Attacking!")
	# Get all bodies overlapping with the push area
	var overlapping_bodies = push_area.get_overlapping_bodies()
	print("Overlapping bodies: ", overlapping_bodies.size())

	var direction: Vector3 = -global_transform.basis.z
	direction.y = 0.0
	direction = direction.normalized()
	print("Push direction: ", direction, "with cardinal direction: ", get_cardinal_direction(direction))

	var hit_enemy := false
	for body in overlapping_bodies:
		if body is RigidBody3D:
			var target := body.get_parent()
			if target == null or not target.has_method("do_push"):
				continue

			target.do_push(direction * push_velocity)
			hit_enemy = hit_enemy or target.is_in_group(SIGNAL_ENEMY_GROUP)
			print ("Pushing body: ", body.name)

	_play_push_sound(hit_enemy)

func get_cardinal_direction(direction: Vector3) -> String:
	var angle = atan2(direction.x, direction.z)
	if angle < 0:
		angle += 2 * PI

	if angle >= 0 and angle < PI / 4:
		return "North"
	elif angle >= PI / 4 and angle < 3 * PI / 4:
		return "East"
	elif angle >= 3 * PI / 4 and angle < 5 * PI / 4:
		return "South"
	elif angle >= 5 * PI / 4 and angle < 7 * PI / 4:
		return "West"
	else:
		return "North"
