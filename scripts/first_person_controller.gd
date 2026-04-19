extends CharacterBody3D

@export var move_speed: float = 5.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var ground_acceleration: float = 20.0
@export var air_acceleration: float = 8.0
@export var push_velocity: float = 6

@onready var camera_pivot: Node3D = $CameraPivot
@onready var push_area: Area3D = %PushArea

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var pitch: float = 0.0
var respawn_pitch: float = 0.0
var controls_enabled := true


func _ready() -> void:
	respawn_pitch = camera_pivot.rotation.x
	set_controls_enabled(true)


func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	if not enabled:
		velocity = Vector3.ZERO
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return

	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func respawn_at(target_transform: Transform3D) -> void:
	global_transform = target_transform
	velocity = Vector3.ZERO
	pitch = respawn_pitch
	camera_pivot.rotation.x = respawn_pitch


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

func do_push() -> void:
	print("Attacking!")
	# Get all bodies overlapping with the push area
	var overlapping_bodies = push_area.get_overlapping_bodies()
	print("Overlapping bodies: ", overlapping_bodies.size())

	var direction: Vector3 = -global_transform.basis.z
	direction.y = 0.0
	direction = direction.normalized()
	print("Push direction: ", direction, "with cardinal direction: ", get_cardinal_direction(direction))

	for body in overlapping_bodies:
		if body is RigidBody3D:
			body.get_parent().do_push(direction * push_velocity)
			print ("Pushing body: ", body.name)

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
