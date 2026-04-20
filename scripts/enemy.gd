class_name Enemy
extends CharacterBody3D

const SIGNAL_ENEMY_GROUP := &"signal_enemy"
const MAIN_PLAYER_GROUP := &"main_player"
const INDICATOR_PUSH_DURATION_SECONDS := 2.0

@export var nav_mesh: NavigationRegion3D
@export var player: CharacterBody3D

@export_group("Settings")
@export var ai : EnemyAI
@export var move_speed: float = 3.0
@export var turn_speed: float = 8.0
@export_range(-180.0, 180.0, 0.1) var facing_yaw_offset_degrees: float = 0.0
@export var normal_color: Color = Color(0.20241532, 0.17677477, 0.4619112, 1.0)
@export var pushed_color: Color = Color(1.0, 0.25, 0.25, 1.0)
@export_group("Indicator Light")
@export var indicator_default_color: Color = Color(0.6089677, 0.1788316, 0.18341184, 1.0)
@export var indicator_patrolling_color: Color = Color(0.98, 0.62, 0.14, 1.0)
@export var indicator_chasing_color: Color = Color(0.12, 0.92, 1.0, 1.0)
@export var indicator_searching_color: Color = Color(0.62, 0.46, 1.0, 1.0)
@export var indicator_returning_color: Color = Color(0.38, 0.78, 1.0, 1.0)
@export var indicator_pushed_color: Color = Color(1.0, 0.92, 0.2, 1.0)

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D
@onready var enemy_rigid_body: RigidBody3D = %EnemyRigidBody
@onready var enemy_mesh: MeshInstance3D = $MeshInstance3D
@onready var indicator_light: MeshInstance3D = $dalek2/IndicatorLight
@onready var debug_label: Label3D = $Label3D

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))

var is_being_pushed: bool = false
var enemy_material: StandardMaterial3D
var indicator_light_material: StandardMaterial3D
var indicator_push_remaining: float = 0.0

var player_position: Vector3 = Vector3.ZERO
var player_visible: bool = false

func _ready() -> void:
	add_to_group(SIGNAL_ENEMY_GROUP)
	_resolve_player()
	assert(player, "Player node could not be resolved. Expected an explicit assignment or a node in group 'main_player'.")
	#assert(nav_mesh, "NavigationRegion3D not assigned.")
	assert(navigation_agent_3d, "NavigationAgent3D node not found in the scene tree.")
	assert(enemy_mesh, "MeshInstance3D node not found in the scene tree.")
	assert(indicator_light, "IndicatorLight node not found in the scene tree.")
	assert(debug_label, "Label3D node not found in the scene tree.")
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

	indicator_light_material = _duplicate_standard_material(indicator_light)
	_update_color()
	_update_indicator_light()
	set_debug_label_visible(false)

	ai.state_changed.connect(_on_enemy_ai_state_changed)
	_on_enemy_ai_state_changed(ai.current_state)


func _resolve_player() -> void:
	if player != null:
		return

	player = get_tree().get_first_node_in_group(MAIN_PLAYER_GROUP) as CharacterBody3D

func _physics_process(_delta: float) -> void:
	_update_color()
	_update_indicator_push_timer(_delta)
	_update_indicator_light()

	if is_being_pushed:
		global_position = enemy_rigid_body.global_position

		if enemy_rigid_body.linear_velocity.length() < 0.1:
			velocity = Vector3.ZERO
			is_being_pushed = false
		return
	else:
		enemy_rigid_body.linear_velocity = Vector3.ZERO
		enemy_rigid_body.global_position = global_position

	if not nav_mesh:
		_stop_navigation(_delta)
		return

	if not navigation_agent_3d.get_navigation_map():
		navigation_agent_3d.set_navigation_map(nav_mesh)

	if not ai.should_move():
		_stop_navigation(_delta)
		return

	_move_toward_target(ai.get_movement_target_position(), _delta)

func _update_color() -> void:
	if not enemy_material:
		return

	var target_color: Color = pushed_color if is_being_pushed else normal_color
	enemy_material.albedo_color = target_color
	enemy_material.emission_enabled = true
	enemy_material.emission = target_color


func _duplicate_standard_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	if mesh_instance == null:
		return null

	var source_material := mesh_instance.material_override as StandardMaterial3D
	if source_material == null:
		source_material = mesh_instance.get_active_material(0) as StandardMaterial3D

	if source_material != null:
		var duplicated_material := source_material.duplicate()
		mesh_instance.material_override = duplicated_material
		return duplicated_material

	var fallback_material := StandardMaterial3D.new()
	mesh_instance.material_override = fallback_material
	return fallback_material


func _update_indicator_push_timer(delta: float) -> void:
	if indicator_push_remaining <= 0.0:
		return

	indicator_push_remaining = maxf(indicator_push_remaining - delta, 0.0)


func _update_indicator_light() -> void:
	if indicator_light_material == null:
		return

	var target_color: Color = indicator_pushed_color if indicator_push_remaining > 0.0 else _get_indicator_state_color()
	indicator_light_material.albedo_color = target_color
	indicator_light_material.emission_enabled = true
	indicator_light_material.emission = target_color


func _get_indicator_state_color() -> Color:
	if ai == null:
		return indicator_default_color

	match ai.current_state:
		EnemyAI.State.PATROLLING:
			return indicator_patrolling_color
		EnemyAI.State.CHASING:
			return indicator_chasing_color
		EnemyAI.State.CHASING_LAST_KNOWN_POSITION:
			return indicator_searching_color
		EnemyAI.State.RETURNING_TO_LEASH:
			return indicator_returning_color
		_:
			return indicator_default_color


func _face_target(target_position: Vector3, delta: float) -> void:
	var to_target: Vector3 = target_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.0001:
		return

	var target_yaw: float = atan2(to_target.x, to_target.z) + PI + deg_to_rad(facing_yaw_offset_degrees)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func _move_toward_target(target_position: Vector3, delta: float) -> void:
	navigation_agent_3d.target_position = target_position

	if navigation_agent_3d.is_navigation_finished():
		_stop_navigation(delta)
		return

	var next_path_position: Vector3 = navigation_agent_3d.get_next_path_position()
	var direction: Vector3 = next_path_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		_stop_navigation(delta)
		return

	direction = direction.normalized()
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	_face_target(target_position, delta)
	_apply_gravity(delta)
	move_and_slide()


func _stop_navigation(delta: float) -> void:
	velocity.x = move_toward(velocity.x, 0.0, move_speed * 4.0 * delta)
	velocity.z = move_toward(velocity.z, 0.0, move_speed * 4.0 * delta)
	_apply_gravity(delta)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
		
func do_push(direction: Vector3) -> void:
	if ai != null:
		ai.stun(INDICATOR_PUSH_DURATION_SECONDS)

	is_being_pushed = true
	indicator_push_remaining = INDICATOR_PUSH_DURATION_SECONDS
	enemy_rigid_body.linear_velocity = direction


func set_debug_label_visible(visible: bool) -> void:
	if debug_label == null:
		return

	debug_label.visible = visible


func _on_enemy_ai_state_changed(new_state: EnemyAI.State) -> void:
	match new_state:
		EnemyAI.State.IDLE:
			debug_label.text = "Idle"
		EnemyAI.State.PATROLLING:
			debug_label.text = "Patrolling"
		EnemyAI.State.CHASING:
			debug_label.text = "Chasing"
		EnemyAI.State.CHASING_LAST_KNOWN_POSITION:
			debug_label.text = "Chasing Last Known Position"
		EnemyAI.State.RETURNING_TO_LEASH:
			debug_label.text = "Returning to Leash"
		EnemyAI.State.STUNNED:
			debug_label.text = "Stunned"
		_:
			debug_label.text = "Unknown State"
