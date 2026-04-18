extends Node3D

const STATIC_SHADER := preload("res://shaders/sonar_static_overlay.gdshader")
const COMPOSITE_SHADER := preload("res://shaders/sonar_composite.gdshader")
const REVEAL_SHADER := preload("res://shaders/sonar_reveal.gdshader")
const NORMAL_MUSIC_PATH := "res://assets/audio/music/menu-loop.mp3"
const SONAR_MUSIC_PATH := "res://assets/audio/music/menu_static-loop.mp3"
const SONAR_PING_SFX_PATH := "res://assets/audio/sfx/ping_2.mp3"

@export var ping_cooldown_seconds: float = 0.6
@export var ping_speed: float = 18.0
@export var ping_max_radius: float = 18.0
@export var ping_band_width: float = 0.9
@export var ping_band_fade: float = 0.2

@onready var player_camera: Camera3D = $Player/CameraPivot/Camera3D
@onready var sonar_viewport: SubViewport = $SonarViewport
@onready var sonar_camera: Camera3D = $SonarViewport/SonarCamera
@onready var reveal_proxy_root: Node3D = $SonarViewport/RevealProxies
@onready var occluder_proxy_root: Node3D = $SonarViewport/OccluderProxies
@onready var overlay_root: Control = $VisionOverlay/OverlayRoot
@onready var static_rect: ColorRect = $VisionOverlay/OverlayRoot/StaticRect
@onready var sonar_rect: TextureRect = $VisionOverlay/OverlayRoot/SonarRect

var sonar_mode_enabled := false
var ping_active := false
var ping_radius := 0.0
var ping_origin_ws := Vector3.ZERO
var ping_cooldown_remaining := 0.0
var last_viewport_size := Vector2i.ZERO

var reveal_proxy_pairs: Array = []
var occluder_proxy_pairs: Array = []

var static_material: ShaderMaterial
var composite_material: ShaderMaterial
var reveal_material: ShaderMaterial
var occluder_material: StandardMaterial3D
var normal_music_player: AudioStreamPlayer
var sonar_music_player: AudioStreamPlayer
var sonar_ping_player: AudioStreamPlayer


func _ready() -> void:
	_ensure_input_actions()
	_create_music_players()
	_create_sfx_players()
	_create_materials()
	_configure_overlay()
	_configure_sonar_viewport()
	_rebuild_proxy_scene()
	_sync_sonar_camera()
	_sync_proxy_transforms()
	_set_sonar_mode(false)
	_update_shader_state()


func _exit_tree() -> void:
	_release_music_players()
	_release_sfx_players()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return

	if event.is_action_pressed("toggle_sonar_mode"):
		_set_sonar_mode(not sonar_mode_enabled)
		return

	if event.is_action_pressed("sonar_ping") and sonar_mode_enabled and ping_cooldown_remaining <= 0.0:
		_start_ping()


func _process(delta: float) -> void:
	_resize_sonar_viewport()
	_sync_sonar_camera()
	_sync_proxy_transforms()

	if ping_cooldown_remaining > 0.0:
		ping_cooldown_remaining = max(ping_cooldown_remaining - delta, 0.0)

	if ping_active:
		ping_radius += ping_speed * delta
		if ping_radius > ping_max_radius:
			ping_active = false

	_update_shader_state()


func _ensure_input_actions() -> void:
	_ensure_key_action("toggle_sonar_mode", KEY_G)
	_ensure_key_action("sonar_ping", KEY_F)


func _ensure_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey and event.physical_keycode == keycode:
			return

	var input_event := InputEventKey.new()
	input_event.keycode = keycode
	input_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, input_event)


func _create_materials() -> void:
	static_material = ShaderMaterial.new()
	static_material.shader = STATIC_SHADER

	composite_material = ShaderMaterial.new()
	composite_material.shader = COMPOSITE_SHADER

	reveal_material = ShaderMaterial.new()
	reveal_material.shader = REVEAL_SHADER

	occluder_material = StandardMaterial3D.new()
	occluder_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	occluder_material.albedo_color = Color.BLACK
	occluder_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED


func _create_music_players() -> void:
	if DisplayServer.get_name() == "headless":
		return

	normal_music_player = AudioStreamPlayer.new()
	normal_music_player.name = "NormalMusicPlayer"
	normal_music_player.stream = load(NORMAL_MUSIC_PATH)
	add_child(normal_music_player)

	sonar_music_player = AudioStreamPlayer.new()
	sonar_music_player.name = "SonarMusicPlayer"
	sonar_music_player.stream = load(SONAR_MUSIC_PATH)
	add_child(sonar_music_player)


func _release_music_players() -> void:
	for player in [normal_music_player, sonar_music_player]:
		if player == null:
			continue

		player.stop()
		player.stream = null


func _create_sfx_players() -> void:
	if DisplayServer.get_name() == "headless":
		return

	sonar_ping_player = AudioStreamPlayer.new()
	sonar_ping_player.name = "SonarPingPlayer"
	sonar_ping_player.stream = load(SONAR_PING_SFX_PATH)
	add_child(sonar_ping_player)


func _release_sfx_players() -> void:
	if sonar_ping_player == null:
		return

	sonar_ping_player.stop()
	sonar_ping_player.stream = null


func _configure_overlay() -> void:
	overlay_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_root.visible = false

	static_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_rect.material = static_material

	sonar_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sonar_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sonar_rect.stretch_mode = TextureRect.STRETCH_SCALE
	sonar_rect.material = composite_material
	sonar_rect.texture = sonar_viewport.get_texture()


func _configure_sonar_viewport() -> void:
	sonar_viewport.own_world_3d = true
	sonar_viewport.transparent_bg = false
	_resize_sonar_viewport()
	sonar_camera.current = true


func _resize_sonar_viewport() -> void:
	var visible_size := get_viewport().get_visible_rect().size
	var viewport_size := Vector2i(int(visible_size.x), int(visible_size.y))
	if viewport_size == last_viewport_size or viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	last_viewport_size = viewport_size
	sonar_viewport.size = viewport_size


func _sync_sonar_camera() -> void:
	sonar_camera.global_transform = player_camera.global_transform
	sonar_camera.projection = player_camera.projection
	sonar_camera.keep_aspect = player_camera.keep_aspect
	sonar_camera.near = player_camera.near
	sonar_camera.far = player_camera.far
	sonar_camera.fov = player_camera.fov
	sonar_camera.size = player_camera.size
	sonar_camera.frustum_offset = player_camera.frustum_offset
	sonar_camera.h_offset = player_camera.h_offset
	sonar_camera.v_offset = player_camera.v_offset


func _rebuild_proxy_scene() -> void:
	for child in reveal_proxy_root.get_children():
		child.queue_free()
	for child in occluder_proxy_root.get_children():
		child.queue_free()

	reveal_proxy_pairs.clear()
	occluder_proxy_pairs.clear()

	for node in get_tree().get_nodes_in_group("sonar_reveal"):
		if node is Node3D and not sonar_viewport.is_ancestor_of(node):
			_build_proxy_set(node, reveal_proxy_root, reveal_material, reveal_proxy_pairs)

	for node in get_tree().get_nodes_in_group("sonar_occluder"):
		if node is Node3D and not sonar_viewport.is_ancestor_of(node):
			_build_proxy_set(node, occluder_proxy_root, occluder_material, occluder_proxy_pairs)


func _build_proxy_set(group_node: Node3D, target_root: Node3D, material: Material, proxy_pairs: Array) -> void:
	for mesh_instance in _collect_mesh_instances(group_node):
		if mesh_instance.mesh == null:
			continue

		var proxy := MeshInstance3D.new()
		proxy.top_level = true
		proxy.mesh = mesh_instance.mesh
		proxy.material_override = material
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		proxy.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		target_root.add_child(proxy)
		proxy.global_transform = mesh_instance.global_transform
		proxy.visible = mesh_instance.is_visible_in_tree()

		proxy_pairs.append({
			"source": mesh_instance,
			"proxy": proxy,
		})


func _collect_mesh_instances(root: Node) -> Array:
	var mesh_instances: Array = []
	if root is MeshInstance3D:
		mesh_instances.append(root)

	for child in root.get_children():
		mesh_instances.append_array(_collect_mesh_instances(child))

	return mesh_instances


func _sync_proxy_transforms() -> void:
	_sync_proxy_pair_set(reveal_proxy_pairs)
	_sync_proxy_pair_set(occluder_proxy_pairs)


func _sync_proxy_pair_set(proxy_pairs: Array) -> void:
	for pair in proxy_pairs:
		var source: MeshInstance3D = pair["source"]
		var proxy: MeshInstance3D = pair["proxy"]
		if not is_instance_valid(source) or not is_instance_valid(proxy):
			continue

		proxy.global_transform = source.global_transform
		proxy.visible = source.is_visible_in_tree()


func _set_sonar_mode(enabled: bool) -> void:
	sonar_mode_enabled = enabled
	overlay_root.visible = enabled

	if not enabled:
		ping_active = false
		ping_radius = 0.0

	_sync_music_players()
	_update_shader_state()


func _start_ping() -> void:
	ping_active = true
	ping_radius = 0.0
	ping_origin_ws = player_camera.global_position
	ping_cooldown_remaining = ping_cooldown_seconds
	if sonar_ping_player != null:
		sonar_ping_player.play()
	_update_shader_state()


func _update_shader_state() -> void:
	reveal_material.set_shader_parameter("ping_origin_ws", ping_origin_ws)
	reveal_material.set_shader_parameter("ping_radius", ping_radius)
	reveal_material.set_shader_parameter("ping_band_width", ping_band_width)
	reveal_material.set_shader_parameter("ping_band_fade", ping_band_fade)
	reveal_material.set_shader_parameter("pulse_active", sonar_mode_enabled and ping_active)


func _sync_music_players() -> void:
	var target_player := sonar_music_player if sonar_mode_enabled else normal_music_player
	var source_player := normal_music_player if sonar_mode_enabled else sonar_music_player

	if target_player == null or source_player == null:
		return

	if target_player.playing and not source_player.playing:
		return

	var start_position := 0.0
	if source_player.playing:
		start_position = _get_wrapped_playback_position(source_player, target_player.stream)
	elif target_player.playing:
		start_position = _get_wrapped_playback_position(target_player, target_player.stream)

	target_player.play(start_position)
	source_player.stop()


func _get_wrapped_playback_position(player: AudioStreamPlayer, target_stream: AudioStream) -> float:
	var playback_position := player.get_playback_position()
	playback_position += AudioServer.get_time_since_last_mix()
	playback_position -= AudioServer.get_output_latency()
	playback_position = max(playback_position, 0.0)

	if target_stream != null:
		var stream_length := target_stream.get_length()
		if stream_length > 0.0:
			return fposmod(playback_position, stream_length)

	return playback_position
