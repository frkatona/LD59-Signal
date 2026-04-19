extends CharacterBody3D

@export var move_speed: float = 3.0
@export var nav_mesh: NavigationRegion3D
@export var player: CharacterBody3D

@onready var navigation_agent_3d: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	assert(player, "Player node not found in the scene tree.")
	assert(nav_mesh, "NavigationRegion3D not assigned.")
	assert(navigation_agent_3d, "NavigationAgent3D node not found in the scene tree.")

	# Wait for the navigation map to initialize
	await get_tree().physics_frame

func _physics_process(delta: float) -> void:
	if not nav_mesh:
		return
	elif not navigation_agent_3d.get_navigation_map():
		navigation_agent_3d.set_navigation_map(nav_mesh)

	if player:
		navigation_agent_3d.target_position = player.global_transform.origin

	if navigation_agent_3d.is_navigation_finished():
		return
	else:
		var next_path_position: Vector3 = navigation_agent_3d.get_next_path_position()
		var direction: Vector3 = (next_path_position - global_transform.origin).normalized()
		velocity = direction * move_speed
		move_and_slide()	
		
