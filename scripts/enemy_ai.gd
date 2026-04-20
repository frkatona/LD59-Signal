class_name EnemyAI
extends Node

signal state_changed(new_state: State)

enum State {
	IDLE,
	PATROLLING,
	CHASING,
	CHASING_LAST_KNOWN_POSITION,
	RETURNING_TO_LEASH,
	STUNNED
}

@export var enemy: Enemy
@export var ray: RayCast3D
@export var leash_point: Node3D
@export var think_interval_seconds: float = 0.25
@export var stunned_duration_seconds: float = 2.0
@export var permanently_stunned: bool = false
@export var arrival_distance: float = 0.75
@export var leash_max_distance: float = 12.0
@export var player_disengage_distance: float = 10.0
@export var patrol_points: Array[Node3D] = []

var think_timer: Timer
var current_state: State = State.IDLE
var home_position := Vector3.ZERO
var leash_position := Vector3.ZERO
var patrol_point_index := 0
var stunned_remaining := 0.0

func _ready() -> void:
	assert(enemy != null, "Enemy node is not assigned.")
	assert(ray != null, "RayCast3D node is not assigned.")

	home_position = enemy.global_position
	leash_position = _get_initial_leash_position()
	think_timer = Timer.new()
	think_timer.one_shot = true
	add_child(think_timer)
	think_timer.timeout.connect(_think)
	if permanently_stunned:
		_enter_stunned_state(INF, true)
	else:
		_set_state(State.IDLE, true)
	_restart_think_timer()

func _process(delta: float) -> void:
	if current_state != State.STUNNED:
		return

	if permanently_stunned:
		stunned_remaining = INF
		return

	if _should_return_to_leash():
		_begin_return_to_leash()
		_think()
		return

	stunned_remaining = maxf(stunned_remaining - delta, 0.0)
	if stunned_remaining > 0.0:
		return

	_set_state(State.IDLE)
	_think()


func stun(duration: float = -1.0) -> void:
	var stun_duration := INF if permanently_stunned else (stunned_duration_seconds if duration < 0.0 else duration)
	_enter_stunned_state(stun_duration)


func should_move() -> bool:
	return current_state in [State.PATROLLING, State.CHASING, State.CHASING_LAST_KNOWN_POSITION, State.RETURNING_TO_LEASH]


func get_movement_target_position() -> Vector3:
	match current_state:
		State.CHASING:
			return enemy.player.global_position if enemy.player != null else enemy.global_position
		State.CHASING_LAST_KNOWN_POSITION:
			return enemy.player_position
		State.RETURNING_TO_LEASH:
			return leash_position
		State.PATROLLING:
			return _get_patrol_target_position()
		_:
			return enemy.global_position


func _think() -> void:
	if current_state == State.STUNNED:
		_restart_think_timer()
		return

	if _should_return_to_leash():
		_begin_return_to_leash()
		_restart_think_timer()
		return

	if _can_see_player():
		enemy.player_position = enemy.player.global_position
		enemy.player_visible = true
		_set_state(State.CHASING)
		_restart_think_timer()
		return

	enemy.player_visible = false

	match current_state:
		State.CHASING:
			_set_state(State.CHASING_LAST_KNOWN_POSITION)
		State.CHASING_LAST_KNOWN_POSITION:
			if _has_reached(enemy.player_position):
				_set_state(State.PATROLLING if _has_patrol_points() else State.IDLE)
		State.RETURNING_TO_LEASH:
			if _has_reached(leash_position):
				_set_state(State.PATROLLING if _has_patrol_points() else State.IDLE)
		State.PATROLLING:
			if _has_reached(_get_patrol_target_position()):
				if _has_patrol_points():
					patrol_point_index = (patrol_point_index + 1) % patrol_points.size()
				else:
					_set_state(State.IDLE)
		State.IDLE:
			if _has_patrol_points():
				_set_state(State.PATROLLING)

	_restart_think_timer()


func _set_state(new_state: State, force_emit: bool = false) -> void:
	if not force_emit and current_state == new_state:
		return

	current_state = new_state
	state_changed.emit(current_state)


func _restart_think_timer() -> void:
	think_timer.start(maxf(think_interval_seconds, 0.01))


func _enter_stunned_state(duration: float, force_emit: bool = false) -> void:
	stunned_remaining = duration
	enemy.player_visible = false
	_set_state(State.STUNNED, force_emit)


func _begin_return_to_leash() -> void:
	stunned_remaining = 0.0
	enemy.player_visible = false
	_set_state(State.RETURNING_TO_LEASH)


func _can_see_player() -> bool:
	if enemy.player == null:
		return false

	ray.target_position = ray.to_local(enemy.player.global_position)
	ray.force_raycast_update()
	return ray.is_colliding() and ray.get_collider() == enemy.player


func _has_patrol_points() -> bool:
	return not patrol_points.is_empty()


func _get_patrol_target_position() -> Vector3:
	if patrol_points.is_empty():
		return home_position

	var patrol_point := patrol_points[patrol_point_index]
	return patrol_point.global_position if patrol_point != null else home_position


func _get_initial_leash_position() -> Vector3:
	if leash_point != null:
		return leash_point.global_position

	return home_position


func _should_return_to_leash() -> bool:
	if _distance_from_leash() > leash_max_distance:
		return true

	if current_state in [State.CHASING, State.CHASING_LAST_KNOWN_POSITION, State.STUNNED] and _distance_to_player() > player_disengage_distance:
		return true

	return false


func _distance_from_leash() -> float:
	var current_position_flat := Vector2(enemy.global_position.x, enemy.global_position.z)
	var leash_position_flat := Vector2(leash_position.x, leash_position.z)
	return current_position_flat.distance_to(leash_position_flat)


func _distance_to_player() -> float:
	if enemy.player == null:
		return INF

	var current_position_flat := Vector2(enemy.global_position.x, enemy.global_position.z)
	var player_position_flat := Vector2(enemy.player.global_position.x, enemy.player.global_position.z)
	return current_position_flat.distance_to(player_position_flat)


func _has_reached(target_position: Vector3) -> bool:
	var current_position_flat := Vector2(enemy.global_position.x, enemy.global_position.z)
	var target_position_flat := Vector2(target_position.x, target_position.z)
	return current_position_flat.distance_to(target_position_flat) <= arrival_distance
