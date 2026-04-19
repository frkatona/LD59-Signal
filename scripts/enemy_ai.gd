class_name EnemyAI
extends Node

signal state_changed(new_state: State)

enum State {
	IDLE,
	PATROLLING,
	CHASING,
	CHASING_LAST_KNOWN_POSITION,
	STUNNED
}

@export var enemy: Enemy
@export var ray: RayCast3D

var think_timer: Timer
var current_state: State = State.IDLE

func _ready():
	assert(enemy != null, "Enemy node is not assigned.")
	assert(ray != null, "RayCast3D node is not assigned.")
	
	think_timer = Timer.new()
	add_child(think_timer)
	think_timer.timeout.connect(_think)
	think_timer.start(1.0)

func _think():
	print("Enemy is thinking...")
	
	ray.transform = Transform3D(Basis().rotated(Vector3.UP, -enemy.rotation.y), ray.transform.origin)
	# Check if the enemy can see the player using the raycast
	ray.target_position = (enemy.player.global_position - enemy.global_position).normalized() * 100.0
	ray.force_raycast_update()
	# If the ray hits the player, move towards the player
	if ray.is_colliding() and ray.get_collider() == enemy.player:
		print("Enemy sees the player! Moving towards the player.")
		current_state = State.CHASING
		enemy.player_position = enemy.player.global_position
		enemy.player_visible = true
	else:
		print("Enemy does not see the player. Patrolling.")
		current_state = State.CHASING_LAST_KNOWN_POSITION
		enemy.player_visible = false

	state_changed.emit(current_state)
	think_timer.start(1.0)

func _process(_delta):
	pass
