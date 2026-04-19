class_name Enemy
extends CharacterBody3D

const SIGNAL_ENEMY_GROUP := &"signal_enemy"
const NAV_MESH_OFFSET := Vector3(0, 0.5, 0)

@export var nav_mesh: NavigationRegion3D
@export var player: CharacterBody3D

@export_group("Settings")
@export var ai : EnemyAI
@export var move_speed: float = 3.0
@export var turn_speed: float = 8.0
@export_range(-180.0, 180.0, 0.1) var facing_yaw_offset_degrees: float = 0.0
@export var normal_color: Color = Color(0.20241532, 0.17677477, 0.4619112, 1.0)
@export var pushed_color: Color = Color(1.0, 0.25, 0.25, 1.0)

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var enemy_rigid_body: RigidBody3D = %EnemyRigidBody
@onready var enemy_mesh: MeshInstance3D = $MeshInstance3D

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var is_being_pushed: bool = false
var enemy_material: StandardMaterial3D

var player_position: Vector3 = Vector3.ZERO
var player_visible: bool = false

func _ready() -> void:
	add_to_group(SIGNAL_ENEMY_GROUP)
	assert(player, "Player node not found in the scene tree.")
	assert(nav_mesh, "NavigationRegion3D not assigned.")
	assert(navigation_agent_3d, "NavigationAgent3D node not found in the scene tree.")
	assert(enemy_mesh, "MeshInstance3D node not found in the scene tree.")
	assert(ai, "EnemyAI node not assigned.")

	enemy_rigid_body.top_level = true
	enemy_rigid_body.global_position = global_position
	enemy_rigid_body.add_collision_exception_with(self)

	# Duplicate material so each enemy can change color independently at runtime.
	if enemy_mesh.material_override is StandardMaterial3D:
		enemy_material = (enemy_mesh.material_override as StandardMaterial3D).duplicate()
		enemy_mesh.material_override = enemy_material
	else:
		enemy_material = StandardMaterial3D.new()
		enemy_mesh.material_override = enemy_material

	_update_color()

	ai.state_changed.connect(_on_enemy_ai_state_changed)

func _physics_process(_delta: float) -> void:
	_update_color()

	if is_being_pushed:
		global_position = enemy_rigid_body.global_position

		if enemy_rigid_body.linear_velocity.length() < 0.1:
			velocity = Vector3.ZERO
			is_being_pushed = false
		return
	else:
		enemy_rigid_body.linear_velocity = Vector3.ZERO
		enemy_rigid_body.global_position = global_position

	if ai.current_state != EnemyAI.State.CHASING:
		return

	if not nav_mesh:
		return
	elif not navigation_agent_3d.get_navigation_map():
		navigation_agent_3d.set_navigation_map(nav_mesh)

	navigation_agent_3d.target_position = player.global_transform.origin
	_face_player(_delta)

	if navigation_agent_3d.is_navigation_finished():
		return
	else:
		var next_path_position: Vector3 = navigation_agent_3d.get_next_path_position()
		var direction: Vector3 = (next_path_position - global_transform.origin).normalized()
		velocity = direction - NAV_MESH_OFFSET * move_speed

		# Apply gravity
		velocity.y -= gravity * _delta
		move_and_slide()

func _update_color() -> void:
	if not enemy_material:
		return

	var target_color: Color = pushed_color if is_being_pushed else normal_color
	enemy_material.albedo_color = target_color
	enemy_material.emission_enabled = true
	enemy_material.emission = target_color


func _face_player(delta: float) -> void:
	if player == null:
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	if to_player.length_squared() <= 0.0001:
		return

	var target_yaw: float = atan2(to_player.x, to_player.z) + PI + deg_to_rad(facing_yaw_offset_degrees)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))
		
func do_push(direction: Vector3) -> void:
	print("Enemy is being pushed!")
	is_being_pushed = true
	enemy_rigid_body.linear_velocity = direction
	print("Push velocity applied to enemy: ", direction)


func _on_enemy_ai_state_changed(new_state: EnemyAI.State) -> void:
	print("Enemy state changed to: ", new_state)
	match new_state:
		EnemyAI.State.IDLE:
			$Label3D.text = "Idle"
		EnemyAI.State.PATROLLING:
			$Label3D.text = "Patrolling"
		EnemyAI.State.CHASING:
			$Label3D.text = "Chasing"
		EnemyAI.State.CHASING_LAST_KNOWN_POSITION:
			$Label3D.text = "Chasing Last Known Position"
		EnemyAI.State.STUNNED:
			$Label3D.text = "Stunned"
		_:
			$Label3D.text = "Unknown State"
