extends Node3D

const STATIC_SHADER := preload("res://shaders/sonar_static_overlay.gdshader")
const COMPOSITE_SHADER := preload("res://shaders/sonar_composite.gdshader")
const REVEAL_SHADER := preload("res://shaders/sonar_reveal.gdshader")
const MASTER_BUS_NAME := &"Master"
const MUSIC_BUS_NAME := &"Music"
const SFX_BUS_NAME := &"SFX"
const NORMAL_MUSIC_PATH := "res://assets/audio/music/menu-loop.mp3"
const SONAR_MUSIC_PATH := "res://assets/audio/music/menu_static-loop.mp3"
const SONAR_PING_SFX_PATH := "res://assets/audio/sfx/ping_2.mp3"
const DEBUG_TOGGLE_KEY := KEY_QUOTELEFT
const DEBUG_SAMPLE_WINDOW := 5.0
const DEBUG_REFRESH_INTERVAL := 0.2
const DOOR_OPEN_ANGLE := deg_to_rad(100.0)
const DOOR_OPEN_DURATION := 0.45
const DOOR_FACING_THRESHOLD := 0.72
const MIN_VOLUME_DB := -80.0
const DOOR_PROMPT_TEXT := "Press E to open door"
const WIN_ORB_PROMPT_TEXT := "Press E to touch the sphere"

@export var ping_cooldown_seconds: float = 0.6
@export var ping_speed: float = 18.0
@export var ping_max_radius: float = 18.0
@export var ping_band_width: float = 0.9
@export var ping_band_fade: float = 0.2

@onready var player: CharacterBody3D = $Player
@onready var player_camera: Camera3D = $Player/CameraPivot/Camera3D
@onready var kill_floor: Area3D = $Environment/KillFloor
@onready var sonar_viewport: SubViewport = $SonarViewport
@onready var sonar_camera: Camera3D = $SonarViewport/SonarCamera
@onready var reveal_proxy_root: Node3D = $SonarViewport/RevealProxies
@onready var occluder_proxy_root: Node3D = $SonarViewport/OccluderProxies
@onready var overlay_root: Control = $VisionOverlay/OverlayRoot
@onready var static_rect: ColorRect = $VisionOverlay/OverlayRoot/StaticRect
@onready var sonar_rect: TextureRect = $VisionOverlay/OverlayRoot/SonarRect
@onready var door_pivot: Node3D = $Room/Doorway/DoorPivot
@onready var door_body: StaticBody3D = $Room/Doorway/DoorPivot/Door
@onready var door_interaction_area: Area3D = $Room/Doorway/InteractionArea
@onready var win_orb_body: StaticBody3D = $Props/WinOrb/OrbBody
@onready var win_orb_interaction_area: Area3D = $Props/WinOrb/InteractionArea
@onready var prompt_root: Control = $InteractionUI/PromptRoot
@onready var interaction_prompt: Label = $InteractionUI/PromptRoot/InteractionPrompt
@onready var fan_root: Node = $Props/fan

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
var door_closed_rotation_y := 0.0
var door_is_open := false
var door_is_animating := false
var door_open_tween: Tween
var player_spawn_transform := Transform3D.IDENTITY
var gameplay_started := false
var pause_menu_visible := false
var win_screen_visible := false
var game_won := false
var debug_overlay_visible := false
var debug_elapsed := 0.0
var debug_overlay_timer := 0.0
var frame_sample_total := 0.0
var frame_samples: Array = []
var menus_layer: CanvasLayer
var menus_root: Control
var menu_backdrop: ColorRect
var start_menu_panel: PanelContainer
var pause_menu_panel: PanelContainer
var win_menu_panel: PanelContainer
var debug_layer: CanvasLayer
var debug_panel: PanelContainer
var debug_label: Label
var volume_sliders: Dictionary = {}
var volume_value_labels: Dictionary = {}


func _ready() -> void:
	_ensure_input_actions()
	_configure_audio_buses()
	_create_music_players()
	_create_sfx_players()
	_create_materials()
	_start_fan_animation()
	_configure_overlay()
	_configure_interaction_prompt()
	_build_menu_ui()
	_build_debug_overlay()
	_configure_sonar_viewport()
	_configure_kill_floor()
	_rebuild_proxy_scene()
	_sync_sonar_camera()
	_sync_proxy_transforms()
	door_closed_rotation_y = door_pivot.rotation.y
	player_spawn_transform = player.global_transform
	_set_sonar_mode(false)
	_update_shader_state()
	_show_start_menu()


func _exit_tree() -> void:
	_release_music_players()
	_release_sfx_players()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return

	if _is_debug_toggle_event(event):
		_toggle_debug_overlay()
		return

	if event.is_action_pressed("pause_menu"):
		if not gameplay_started or win_screen_visible:
			return

		if pause_menu_visible:
			_resume_game()
		else:
			_pause_game()
		return

	if _is_menu_open():
		return

	if event.is_action_pressed("interact"):
		if _can_trigger_win():
			_show_win_screen()
			return

		if _can_open_door():
			_open_door()
			return

	if event.is_action_pressed("toggle_sonar_mode"):
		_set_sonar_mode(not sonar_mode_enabled)
		return

	if event.is_action_pressed("sonar_ping") and sonar_mode_enabled and ping_cooldown_remaining <= 0.0:
		_start_ping()


func _process(delta: float) -> void:
	_record_frame_sample(delta)
	_update_debug_overlay(delta)
	_resize_sonar_viewport()

	if _is_menu_open():
		interaction_prompt.visible = false
		return

	_sync_sonar_camera()
	_sync_proxy_transforms()
	_update_interaction_prompt()

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
	_ensure_key_action("interact", KEY_E)
	_replace_key_action("pause_menu", KEY_TAB)


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


func _replace_key_action(action_name: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)

	for event in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			InputMap.action_erase_event(action_name, event)

	var input_event := InputEventKey.new()
	input_event.keycode = keycode
	input_event.physical_keycode = keycode
	InputMap.action_add_event(action_name, input_event)


func _configure_audio_buses() -> void:
	_ensure_audio_bus(MUSIC_BUS_NAME, MASTER_BUS_NAME)
	_ensure_audio_bus(SFX_BUS_NAME, MASTER_BUS_NAME)


func _ensure_audio_bus(bus_name: StringName, send_bus_name: StringName) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		bus_index = AudioServer.get_bus_count()
		AudioServer.add_bus(bus_index)
		AudioServer.set_bus_name(bus_index, bus_name)

	AudioServer.set_bus_send(bus_index, send_bus_name)


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


func _start_fan_animation() -> void:
	if fan_root == null:
		return

	var animation_player := _find_animation_player(fan_root)
	if animation_player == null:
		return

	for animation_name in animation_player.get_animation_list():
		if String(animation_name).containsn("bladespin"):
			animation_player.play(animation_name)
			return


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root

	for child in root.get_children():
		var animation_player := _find_animation_player(child)
		if animation_player != null:
			return animation_player

	return null


func _create_music_players() -> void:
	if DisplayServer.get_name() == "headless":
		return

	normal_music_player = AudioStreamPlayer.new()
	normal_music_player.name = "NormalMusicPlayer"
	normal_music_player.bus = MUSIC_BUS_NAME
	normal_music_player.stream = load(NORMAL_MUSIC_PATH)
	add_child(normal_music_player)

	sonar_music_player = AudioStreamPlayer.new()
	sonar_music_player.name = "SonarMusicPlayer"
	sonar_music_player.bus = MUSIC_BUS_NAME
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
	sonar_ping_player.bus = SFX_BUS_NAME
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


func _configure_interaction_prompt() -> void:
	prompt_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	interaction_prompt.visible = false
	interaction_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_prompt.text = DOOR_PROMPT_TEXT
	interaction_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interaction_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	interaction_prompt.anchor_left = 0.5
	interaction_prompt.anchor_right = 0.5
	interaction_prompt.anchor_top = 1.0
	interaction_prompt.anchor_bottom = 1.0
	interaction_prompt.offset_left = -140.0
	interaction_prompt.offset_right = 140.0
	interaction_prompt.offset_top = -74.0
	interaction_prompt.offset_bottom = -38.0

	var label_settings := LabelSettings.new()
	label_settings.font_size = 18
	label_settings.font_color = Color(0.96, 0.96, 0.98, 1.0)
	label_settings.outline_size = 4
	label_settings.outline_color = Color(0.0, 0.0, 0.0, 0.9)
	interaction_prompt.label_settings = label_settings


func _build_menu_ui() -> void:
	menus_layer = CanvasLayer.new()
	menus_layer.name = "MenuUI"
	menus_layer.layer = 120
	add_child(menus_layer)

	menus_root = Control.new()
	menus_root.name = "MenusRoot"
	menus_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menus_root.mouse_filter = Control.MOUSE_FILTER_STOP
	menus_layer.add_child(menus_root)

	menu_backdrop = ColorRect.new()
	menu_backdrop.name = "MenuBackdrop"
	menu_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_backdrop.color = Color(0.0, 0.0, 0.0, 0.72)
	menu_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	menus_root.add_child(menu_backdrop)

	start_menu_panel = _create_start_menu_panel()
	menus_root.add_child(start_menu_panel)

	pause_menu_panel = _create_pause_menu_panel()
	menus_root.add_child(pause_menu_panel)

	win_menu_panel = _create_win_menu_panel()
	menus_root.add_child(win_menu_panel)


func _build_debug_overlay() -> void:
	debug_layer = CanvasLayer.new()
	debug_layer.name = "DebugOverlay"
	debug_layer.layer = 130
	add_child(debug_layer)

	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugPanel"
	debug_panel.position = Vector2(12.0, 12.0)
	debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_panel.visible = false
	debug_layer.add_child(debug_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.72)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.85, 1.0, 0.7)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 8
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 8
	debug_panel.add_theme_stylebox_override("panel", panel_style)

	debug_label = Label.new()
	debug_label.name = "DebugLabel"
	debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	debug_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	debug_panel.add_child(debug_label)


func _create_start_menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "StartMenu"
	_set_centered_panel_rect(panel, Vector2(420.0, 240.0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Signal"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Explore the room. Use G for static vision, F for sonar ping, and Tab for pause."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(subtitle)

	var start_button := Button.new()
	start_button.text = "Start Game"
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(_start_game)
	content.add_child(start_button)

	return panel


func _create_pause_menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "PauseMenu"
	_set_centered_panel_rect(panel, Vector2(460.0, 360.0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	content.add_child(title)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_button.pressed.connect(_resume_game)
	content.add_child(resume_button)

	var return_button := Button.new()
	return_button.text = "Return to Main Menu"
	return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_button.pressed.connect(_return_to_main_menu)
	content.add_child(return_button)

	content.add_child(HSeparator.new())

	var volume_title := Label.new()
	volume_title.text = "Volume"
	volume_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(volume_title)

	_add_volume_slider(content, "Master", MASTER_BUS_NAME)
	_add_volume_slider(content, "Music", MUSIC_BUS_NAME)
	_add_volume_slider(content, "SFX", SFX_BUS_NAME)

	return panel


func _create_win_menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "WinMenu"
	_set_centered_panel_rect(panel, Vector2(480.0, 320.0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)

	var title := Label.new()
	title.text = "You Did The Thing!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)

	var credits := Label.new()
	credits.text = "Placeholder Credits\n Auteur: FRK"
	credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(credits)

	var play_again_button := Button.new()
	play_again_button.text = "Play Again?"
	play_again_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_again_button.pressed.connect(_restart_game)
	content.add_child(play_again_button)

	return panel


func _set_centered_panel_rect(panel: Control, size: Vector2) -> void:
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -size.x * 0.5
	panel.offset_right = size.x * 0.5
	panel.offset_top = -size.y * 0.5
	panel.offset_bottom = size.y * 0.5


func _add_volume_slider(parent: VBoxContainer, label_text: String, bus_name: StringName) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	row.add_child(label)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 12)
	row.add_child(slider_row)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value = _get_bus_slider_value(bus_name)
	slider.value_changed.connect(_on_volume_slider_changed.bind(bus_name))
	slider_row.add_child(slider)

	var value_label := Label.new()
	value_label.custom_minimum_size = Vector2(48.0, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider_row.add_child(value_label)

	volume_sliders[bus_name] = slider
	volume_value_labels[bus_name] = value_label
	_update_volume_label(bus_name, slider.value)


func _show_start_menu() -> void:
	gameplay_started = false
	pause_menu_visible = false
	win_screen_visible = false
	game_won = false
	_set_player_controls_enabled(false)
	interaction_prompt.visible = false
	menus_root.visible = true
	start_menu_panel.visible = true
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	_sync_volume_controls()


func _start_game() -> void:
	gameplay_started = true
	pause_menu_visible = false
	win_screen_visible = false
	menus_root.visible = false
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	_set_player_controls_enabled(true)


func _pause_game() -> void:
	pause_menu_visible = true
	interaction_prompt.visible = false
	_set_player_controls_enabled(false)
	menus_root.visible = true
	start_menu_panel.visible = false
	pause_menu_panel.visible = true
	win_menu_panel.visible = false
	_sync_volume_controls()


func _resume_game() -> void:
	pause_menu_visible = false
	menus_root.visible = false
	pause_menu_panel.visible = false
	_set_player_controls_enabled(true)


func _return_to_main_menu() -> void:
	get_tree().reload_current_scene()


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _show_win_screen() -> void:
	gameplay_started = false
	pause_menu_visible = false
	win_screen_visible = true
	game_won = true
	_set_player_controls_enabled(false)
	interaction_prompt.visible = false
	_set_sonar_mode(false)
	menus_root.visible = true
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = true


func _set_player_controls_enabled(enabled: bool) -> void:
	if player == null:
		return

	player.call("set_controls_enabled", enabled)


func _is_menu_open() -> bool:
	return not gameplay_started or pause_menu_visible or win_screen_visible


func _on_volume_slider_changed(value: float, bus_name: StringName) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	var bus_volume_db := MIN_VOLUME_DB if value <= 0.0 else linear_to_db(value)
	AudioServer.set_bus_volume_db(bus_index, bus_volume_db)
	_update_volume_label(bus_name, value)


func _sync_volume_controls() -> void:
	for bus_name in volume_sliders.keys():
		var slider := volume_sliders[bus_name] as HSlider
		if slider == null:
			continue

		var value := _get_bus_slider_value(bus_name)
		slider.set_value_no_signal(value)
		_update_volume_label(bus_name, value)


func _get_bus_slider_value(bus_name: StringName) -> float:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return 1.0

	var bus_volume_db := AudioServer.get_bus_volume_db(bus_index)
	if bus_volume_db <= MIN_VOLUME_DB:
		return 0.0

	return clamp(db_to_linear(bus_volume_db), 0.0, 1.0)


func _update_volume_label(bus_name: StringName, value: float) -> void:
	var value_label := volume_value_labels.get(bus_name) as Label
	if value_label == null:
		return

	value_label.text = "%d%%" % int(round(value * 100.0))


func _configure_sonar_viewport() -> void:
	sonar_viewport.own_world_3d = true
	sonar_viewport.transparent_bg = false
	_resize_sonar_viewport()
	sonar_camera.current = true


func _configure_kill_floor() -> void:
	if kill_floor == null:
		return

	if not kill_floor.body_entered.is_connected(_on_kill_floor_body_entered):
		kill_floor.body_entered.connect(_on_kill_floor_body_entered)


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


func _update_interaction_prompt() -> void:
	var prompt_text := _get_interaction_prompt_text()
	interaction_prompt.text = prompt_text
	interaction_prompt.visible = not prompt_text.is_empty()


func _get_interaction_prompt_text() -> String:
	if _can_trigger_win():
		return WIN_ORB_PROMPT_TEXT

	if _can_open_door():
		return DOOR_PROMPT_TEXT

	return ""


func _can_open_door() -> bool:
	return not door_is_open and not door_is_animating and _player_is_near_door() and _player_is_facing_door()


func _player_is_near_door() -> bool:
	return player != null and door_interaction_area != null and door_interaction_area.overlaps_body(player)


func _player_is_facing_door() -> bool:
	return _player_is_facing_target(door_body.global_position)


func _can_trigger_win() -> bool:
	return not game_won and _player_is_near_win_orb() and _player_is_facing_target(win_orb_body.global_position)


func _player_is_near_win_orb() -> bool:
	return player != null and win_orb_interaction_area != null and win_orb_interaction_area.overlaps_body(player)


func _player_is_facing_target(target_position: Vector3) -> bool:
	var to_target := (target_position - player_camera.global_position).normalized()
	var camera_forward := -player_camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target) >= DOOR_FACING_THRESHOLD


func _open_door() -> void:
	door_is_animating = true
	interaction_prompt.visible = false

	if is_instance_valid(door_open_tween):
		door_open_tween.kill()

	door_open_tween = create_tween()
	door_open_tween.tween_property(door_pivot, "rotation:y", door_closed_rotation_y - DOOR_OPEN_ANGLE, DOOR_OPEN_DURATION).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	door_open_tween.finished.connect(_on_door_open_finished, CONNECT_ONE_SHOT)


func _on_door_open_finished() -> void:
	door_is_animating = false
	door_is_open = true


func _on_kill_floor_body_entered(body: Node) -> void:
	if body != player:
		return

	player.call("respawn_at", player_spawn_transform)


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


func _record_frame_sample(delta: float) -> void:
	debug_elapsed += delta
	frame_samples.append({
		"time": debug_elapsed,
		"delta": delta,
	})
	frame_sample_total += delta

	while frame_samples.size() > 0 and debug_elapsed - frame_samples[0]["time"] > DEBUG_SAMPLE_WINDOW:
		frame_sample_total -= frame_samples[0]["delta"]
		frame_samples.pop_front()


func _update_debug_overlay(delta: float) -> void:
	if not debug_overlay_visible or debug_label == null:
		return

	debug_overlay_timer += delta
	if debug_overlay_timer < DEBUG_REFRESH_INTERVAL:
		return

	debug_overlay_timer = 0.0

	var avg_fps := 0.0
	var avg_frame_ms := 0.0
	var sample_count := frame_samples.size()
	if frame_sample_total > 0.0 and sample_count > 0:
		avg_fps = sample_count / frame_sample_total
		avg_frame_ms = (frame_sample_total / sample_count) * 1000.0

	var current_fps := Engine.get_frames_per_second()
	var current_frame_ms := get_process_delta_time() * 1000.0
	var total_objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var total_nodes := get_tree().get_node_count()
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)

	debug_label.text = "Debug\nFPS: %d\nFPS avg (5s): %.1f\nFrame ms: %.2f\nFrame ms avg (5s): %.2f\nNodes: %d\nObjects: %d\nDraw calls: %d" % [
		current_fps,
		avg_fps,
		current_frame_ms,
		avg_frame_ms,
		total_nodes,
		total_objects,
		draw_calls,
	]


func _toggle_debug_overlay() -> void:
	debug_overlay_visible = not debug_overlay_visible
	if debug_panel != null:
		debug_panel.visible = debug_overlay_visible

	if debug_overlay_visible:
		debug_overlay_timer = DEBUG_REFRESH_INTERVAL
		_update_debug_overlay(0.0)


func _is_debug_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	return event.pressed and not event.echo and (
		event.keycode == DEBUG_TOGGLE_KEY or event.physical_keycode == DEBUG_TOGGLE_KEY
	)
