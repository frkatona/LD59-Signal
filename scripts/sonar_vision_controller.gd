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
const DEATH_SFX_PATH := "res://assets/audio/sfx/oof.mp3"
const DEBUG_TOGGLE_KEY := KEY_QUOTELEFT
const DEBUG_SAMPLE_WINDOW := 5.0
const DEBUG_REFRESH_INTERVAL := 0.2
const PING_SPEED_STEP := 5.0
const PING_SPEED_MIN_LIMIT := 5.0
const PING_SPEED_MAX_LIMIT := 50.0
const PING_SPEED_UI_MIN := 1
const PING_SPEED_UI_MAX := 10
const PING_SOUND_MIN_PITCH := 0.85
const PING_SOUND_MAX_PITCH := 1.35
const DOOR_FACING_THRESHOLD := 0.72
const DOOR_BUTTON_GROUP := &"door_button"
const WORLD_ENERGY_DISABLED_MULTIPLIER := 0.0
const WORLD_ENERGY_ENABLED_MULTIPLIER := 1.0
const DEFAULT_MASTER_VOLUME_LINEAR := 0.1
const AUTO_PERFORMANCE_PIXEL_THRESHOLD := 5_000_000
const HIGH_MAIN_3D_SCALE := 1.0
const PERFORMANCE_MAIN_3D_SCALE := 0.67
const HIGH_SONAR_VIEWPORT_SCALE := 1.0
const PERFORMANCE_SONAR_VIEWPORT_SCALE := 0.5
const DEFAULT_MOUSE_SENSITIVITY := 0.0025
const MOUSE_SENSITIVITY_MIN := 0.0005
const MOUSE_SENSITIVITY_MAX := 0.01
const MOUSE_SENSITIVITY_STEP := 0.0001
const UI_REFERENCE_SIZE := Vector2(1280.0, 720.0)
const UI_MIN_SCALE := 1.0
const DEBUG_PANEL_BASE_POSITION := Vector2(12.0, 12.0)
const MIN_VOLUME_DB := -80.0
const WIN_ORB_PROMPT_TEXT := "Press E to touch the sphere"
const ACHIEVEMENT_TITLE_TEXT := "Achievement Unlocked"
const GERONIMO_ACHIEVEMENT_TEXT := "Geronimo!"
const ACHIEVEMENT_NOTIFICATION_DURATION := 4.0
const LIGHT_SWITCH_GROUP := &"light_switch_interactable"
const GAME_CONTROLLER_GROUP := &"game_controller"

enum GraphicsQualityMode {
	AUTO,
	HIGH,
	PERFORMANCE,
}

@export var ping_cooldown_seconds: float = 0.6
@export_range(5.0, 50.0, 5.0) var ping_speed: float = 20.0
@export_group("Ping Speed Limits")
@export_range(5.0, 50.0, 5.0) var ping_speed_floor: float = 5.0
@export_range(5.0, 50.0, 5.0) var ping_speed_ceiling: float = 50.0
@export_group("")
@export var ping_max_radius: float = 18.0
@export var ping_band_width: float = 0.9
@export var ping_band_fade: float = 0.2

@onready var player: Player = $Player
@onready var player_camera: Camera3D = $Player/CameraPivot/Camera3D
@onready var kill_floor: Area3D = $Environment/KillFloor
@onready var sonar_viewport: SubViewport = $Player/SonarViewport
@onready var sonar_camera: Camera3D = $Player/SonarViewport/SonarCamera
@onready var reveal_proxy_root: Node3D = $Player/SonarViewport/RevealProxies
@onready var occluder_proxy_root: Node3D = $Player/SonarViewport/OccluderProxies
@onready var overlay_root: Control = $Player/VisionOverlay/OverlayRoot
@onready var static_rect: ColorRect = $Player/VisionOverlay/OverlayRoot/StaticRect
@onready var sonar_rect: TextureRect = $Player/VisionOverlay/OverlayRoot/SonarRect
@onready var world_environment: WorldEnvironment = $Environment/WorldEnvironment
@onready var room_omni_light: OmniLight3D = $Room1/OmniLight3D
@onready var win_orb_body: StaticBody3D = $EndGame/WinOrb/OrbBody
@onready var win_orb_omni_light: OmniLight3D = $EndGame/WinOrb/OrbBody/OmniLight3D
@onready var win_orb_interaction_area: Area3D = $EndGame/WinOrb/InteractionArea
@onready var prompt_root: Control = $Player/InteractionUI/PromptRoot
@onready var interaction_prompt: Label = $Player/InteractionUI/PromptRoot/InteractionPrompt
@onready var fan_root: Node = $Room1/Props/fan

var sonar_mode_enabled := false
var ping_active := false
var ping_frozen := false
var ping_radius := 0.0
var ping_origin_ws := Vector3.ZERO
var ping_cooldown_remaining := 0.0
var ping_cooldown_duration := 0.0
var last_sonar_viewport_size := Vector2i.ZERO
var last_ui_viewport_size := Vector2i.ZERO
var last_quality_viewport_size := Vector2i.ZERO
var current_ui_scale := 0.0
var selected_graphics_quality_mode := GraphicsQualityMode.AUTO
var effective_graphics_quality_mode := GraphicsQualityMode.HIGH
var graphics_quality_dirty := true

var reveal_proxy_pairs: Array = []
var occluder_proxy_pairs: Array = []

var static_material: ShaderMaterial
var composite_material: ShaderMaterial
var reveal_material: ShaderMaterial
var occluder_material: StandardMaterial3D
var normal_music_player: AudioStreamPlayer
var sonar_music_player: AudioStreamPlayer
var sonar_ping_player: AudioStreamPlayer
var death_sound_player: AudioStreamPlayer
var world_energy_enabled := false
var player_spawn_transform := Transform3D.IDENTITY
var gameplay_started := false
var pause_menu_visible := false
var win_screen_visible := false
var death_screen_visible := false
var game_won := false
var audio_playback_unlocked := false
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
var pause_menu_tabs: TabContainer
var win_menu_panel: PanelContainer
var death_menu_panel: PanelContainer
var debug_layer: CanvasLayer
var debug_panel: PanelContainer
var debug_label: Label
var hud_layer: CanvasLayer
var ping_hud_panel: PanelContainer
var ping_speed_label: Label
var ping_cooldown_label: Label
var ping_cooldown_bar: ProgressBar
var push_cooldown_label: Label
var push_cooldown_bar: ProgressBar
var tutorial_hint_label: Label
var tutorial_hint_remaining := 0.0
var achievement_notification_panel: PanelContainer
var achievement_title_label: Label
var achievement_message_label: Label
var achievement_notification_remaining := 0.0
var mouse_sensitivity_slider: HSlider
var mouse_sensitivity_value_label: Label
var quality_mode_selector: OptionButton
var volume_sliders: Dictionary = {}
var volume_value_labels: Dictionary = {}
var authored_glow_enabled := false
var authored_room_light_shadow_enabled := false
var authored_win_orb_light_shadow_enabled := false


func _ready() -> void:
	add_to_group(GAME_CONTROLLER_GROUP)
	_ensure_input_actions()
	_normalize_ping_speed_settings()
	_configure_audio_buses()
	_create_music_players()
	_create_sfx_players()
	_update_ping_sound_pitch()
	_create_materials()
	_start_fan_animation()
	_configure_overlay()
	_configure_interaction_prompt()
	_build_menu_ui()
	_build_ping_hud()
	_build_debug_overlay()
	_cache_graphics_quality_baseline()
	_configure_sonar_viewport()
	_configure_kill_floor()
	_configure_player_signals()
	_rebuild_proxy_scene()
	_sync_sonar_camera()
	_sync_proxy_transforms()
	_sync_world_environment_energy_state()
	player_spawn_transform = player.global_transform
	_set_sonar_mode(false)
	_update_shader_state()
	_refresh_graphics_quality_profile(true)
	_update_ui_scale()
	_show_start_menu()


func _exit_tree() -> void:
	_release_music_players()
	_release_sfx_players()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return

	if _should_resume_pause_menu_from_event(event):
		_resume_game_from_input_event()
		get_viewport().set_input_as_handled()
		return

	if _is_audio_unlock_event(event):
		_ensure_audio_playback_unlocked()

	if _can_start_game_from_event(event):
		_start_game_from_input_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.echo:
		return

	if _is_debug_toggle_event(event):
		_toggle_debug_overlay()
		return

	if event.is_action_pressed("toggle_world_energy"):
		_toggle_world_environment_energy()
		return

	if event.is_action_pressed("pause_menu"):
		if not gameplay_started or win_screen_visible or death_screen_visible:
			return

		if pause_menu_visible:
			_resume_game_from_input_event()
		else:
			_pause_game()
		return

	if _is_menu_open():
		return

	if _is_ping_speed_adjust_event(event):
		var mouse_button_event := event as InputEventMouseButton
		_adjust_ping_speed(PING_SPEED_STEP if mouse_button_event.button_index == MOUSE_BUTTON_WHEEL_UP else -PING_SPEED_STEP)
		return

	if event.is_action_pressed("interact"):
		if _can_trigger_win():
			_show_win_screen()
			return

		var light_switch := _get_interactable_light_switch()
		if light_switch != null:
			light_switch.interact()
			interaction_prompt.visible = false
			return

		var door_button := _get_interactable_door_button()
		if door_button != null:
			door_button.interact()
			interaction_prompt.visible = false
			return

	if event.is_action_pressed("toggle_sonar_mode"):
		_set_sonar_mode(not sonar_mode_enabled)
		return

	if event.is_action_pressed("sonar_ping") and sonar_mode_enabled:
		_handle_sonar_ping_input()
		return


func _process(delta: float) -> void:
	_refresh_graphics_quality_profile()
	_record_frame_sample(delta)
	_update_debug_overlay(delta)
	_update_ui_scale()
	_sync_signal_scope_overlay_cutout()

	if _is_menu_open():
		interaction_prompt.visible = false
		_update_tutorial_hint()
		_update_achievement_notification()
		_update_ping_hud()
		return

	_sync_sonar_camera()
	_sync_proxy_transforms()
	_update_interaction_prompt()

	if tutorial_hint_remaining > 0.0:
		tutorial_hint_remaining = maxf(tutorial_hint_remaining - delta, 0.0)
	_update_tutorial_hint()

	if achievement_notification_remaining > 0.0:
		achievement_notification_remaining = maxf(achievement_notification_remaining - delta, 0.0)
	_update_achievement_notification()

	if ping_cooldown_remaining > 0.0 and not ping_frozen:
		ping_cooldown_remaining = maxf(ping_cooldown_remaining - delta, 0.0)

	if ping_active and not ping_frozen:
		ping_radius += ping_speed * delta
		if ping_radius > ping_max_radius:
			_clear_ping()
		else:
			ping_cooldown_remaining = maxf(ping_cooldown_remaining, _get_ping_remaining_travel_duration())
			ping_cooldown_duration = maxf(ping_cooldown_duration, ping_cooldown_remaining)

	_update_shader_state()
	_update_ping_hud()


func _ensure_input_actions() -> void:
	_ensure_key_action("toggle_sonar_mode", KEY_G)
	_ensure_key_action("sonar_ping", KEY_F)
	_ensure_key_action("interact", KEY_E)
	_ensure_key_action("toggle_world_energy", KEY_BACKSPACE)
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


func _normalize_ping_speed_settings() -> void:
	ping_speed_floor = _sanitize_ping_speed_limit(ping_speed_floor)
	ping_speed_ceiling = _sanitize_ping_speed_limit(ping_speed_ceiling)
	if ping_speed_floor > ping_speed_ceiling:
		var previous_floor := ping_speed_floor
		ping_speed_floor = ping_speed_ceiling
		ping_speed_ceiling = previous_floor

	ping_speed = _clamp_ping_speed(ping_speed)


func _sanitize_ping_speed_limit(value: float) -> float:
	var snapped_value: float = roundf(value / PING_SPEED_STEP) * PING_SPEED_STEP
	return clampf(snapped_value, PING_SPEED_MIN_LIMIT, PING_SPEED_MAX_LIMIT)


func _clamp_ping_speed(value: float) -> float:
	var snapped_value: float = roundf(value / PING_SPEED_STEP) * PING_SPEED_STEP
	return clampf(snapped_value, ping_speed_floor, ping_speed_ceiling)


func _get_ping_travel_duration() -> float:
	var clamped_ping_speed: float = maxf(ping_speed, 0.001)
	var clamped_ping_radius: float = maxf(ping_max_radius, 0.0)
	return clamped_ping_radius / clamped_ping_speed


func _get_effective_ping_cooldown_duration() -> float:
	return maxf(ping_cooldown_seconds, _get_ping_travel_duration())


func _get_ping_remaining_travel_duration() -> float:
	var clamped_ping_speed: float = maxf(ping_speed, 0.001)
	var remaining_distance: float = maxf(ping_max_radius - ping_radius, 0.0)
	return remaining_distance / clamped_ping_speed


func _configure_audio_buses() -> void:
	_ensure_audio_bus(MUSIC_BUS_NAME, MASTER_BUS_NAME)
	_ensure_audio_bus(SFX_BUS_NAME, MASTER_BUS_NAME)
	_set_initial_master_volume()


func _set_initial_master_volume() -> void:
	var master_bus_index := AudioServer.get_bus_index(MASTER_BUS_NAME)
	if master_bus_index == -1:
		return

	AudioServer.set_bus_volume_db(master_bus_index, linear_to_db(DEFAULT_MASTER_VOLUME_LINEAR))


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

	death_sound_player = AudioStreamPlayer.new()
	death_sound_player.name = "DeathSoundPlayer"
	death_sound_player.bus = SFX_BUS_NAME
	death_sound_player.stream = load(DEATH_SFX_PATH)
	add_child(death_sound_player)


func _release_sfx_players() -> void:
	for player in [sonar_ping_player, death_sound_player]:
		if player == null:
			continue

		player.stop()
		player.stream = null


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


func _sync_signal_scope_overlay_cutout() -> void:
	if static_material == null or composite_material == null or player == null:
		return

	var cutout_enabled := false
	var cutout_center := Vector2(0.0, 0.0)
	var cutout_half_size := Vector2(0.0, 0.0)
	var cutout_corner_radius := 0.03
	var cutout_softness := 0.012

	if player.has_method("get_signal_scope_overlay_cutout"):
		var viewport_size := get_viewport().get_visible_rect().size
		var cutout: Dictionary = player.call("get_signal_scope_overlay_cutout", viewport_size)
		if not cutout.is_empty():
			cutout_enabled = true
			cutout_center = cutout.get("center_uv", cutout_center)
			cutout_half_size = cutout.get("half_size_uv", cutout_half_size)
			cutout_corner_radius = cutout.get("corner_radius_uv", cutout_corner_radius)
			cutout_softness = cutout.get("corner_softness_uv", cutout_softness)

	for material in [static_material, composite_material]:
		material.set_shader_parameter("scope_cutout_enabled", cutout_enabled)
		material.set_shader_parameter("scope_cutout_center", cutout_center)
		material.set_shader_parameter("scope_cutout_half_size", cutout_half_size)
		material.set_shader_parameter("scope_cutout_corner_radius", cutout_corner_radius)
		material.set_shader_parameter("scope_cutout_softness", cutout_softness)


func _configure_interaction_prompt() -> void:
	prompt_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	prompt_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	interaction_prompt.visible = false
	interaction_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interaction_prompt.text = ""
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

	tutorial_hint_label = Label.new()
	tutorial_hint_label.name = "TutorialHint"
	tutorial_hint_label.visible = false
	tutorial_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_hint_label.text = ""
	tutorial_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_hint_label.anchor_left = 0.5
	tutorial_hint_label.anchor_right = 0.5
	tutorial_hint_label.anchor_top = 1.0
	tutorial_hint_label.anchor_bottom = 1.0
	tutorial_hint_label.offset_left = -220.0
	tutorial_hint_label.offset_right = 220.0
	tutorial_hint_label.offset_top = -124.0
	tutorial_hint_label.offset_bottom = -68.0
	tutorial_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_hint_label.label_settings = label_settings
	prompt_root.add_child(tutorial_hint_label)

	achievement_notification_panel = PanelContainer.new()
	achievement_notification_panel.name = "AchievementNotification"
	achievement_notification_panel.visible = false
	achievement_notification_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_notification_panel.anchor_left = 1.0
	achievement_notification_panel.anchor_right = 1.0
	achievement_notification_panel.anchor_top = 0.0
	achievement_notification_panel.anchor_bottom = 0.0
	achievement_notification_panel.offset_left = -280.0
	achievement_notification_panel.offset_right = -24.0
	achievement_notification_panel.offset_top = 24.0
	achievement_notification_panel.offset_bottom = 96.0
	prompt_root.add_child(achievement_notification_panel)

	var achievement_style := StyleBoxFlat.new()
	achievement_style.bg_color = Color(0.08, 0.16, 0.07, 0.96)
	achievement_style.border_width_left = 1
	achievement_style.border_width_top = 1
	achievement_style.border_width_right = 1
	achievement_style.border_width_bottom = 1
	achievement_style.border_color = Color(0.52, 0.92, 0.44, 0.95)
	achievement_style.corner_radius_top_left = 3
	achievement_style.corner_radius_top_right = 3
	achievement_style.corner_radius_bottom_right = 3
	achievement_style.corner_radius_bottom_left = 3
	achievement_style.content_margin_left = 14
	achievement_style.content_margin_top = 10
	achievement_style.content_margin_right = 14
	achievement_style.content_margin_bottom = 10
	achievement_notification_panel.add_theme_stylebox_override("panel", achievement_style)

	var achievement_content := VBoxContainer.new()
	achievement_content.add_theme_constant_override("separation", 2)
	achievement_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_notification_panel.add_child(achievement_content)

	achievement_title_label = Label.new()
	achievement_title_label.name = "AchievementTitle"
	achievement_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_title_label.text = ACHIEVEMENT_TITLE_TEXT
	achievement_title_label.add_theme_font_size_override("font_size", 12)
	achievement_title_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.62, 1.0))
	achievement_content.add_child(achievement_title_label)

	achievement_message_label = Label.new()
	achievement_message_label.name = "AchievementMessage"
	achievement_message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	achievement_message_label.text = ""
	achievement_message_label.add_theme_font_size_override("font_size", 22)
	achievement_message_label.add_theme_color_override("font_color", Color(0.97, 1.0, 0.96, 1.0))
	achievement_content.add_child(achievement_message_label)

	_update_achievement_notification()


func _update_ui_scale() -> void:
	var visible_size: Vector2 = get_viewport().get_visible_rect().size
	var viewport_size := Vector2i(int(visible_size.x), int(visible_size.y))
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var ui_scale: float = maxf(
		minf(visible_size.x / UI_REFERENCE_SIZE.x, visible_size.y / UI_REFERENCE_SIZE.y),
		UI_MIN_SCALE
	)
	if viewport_size == last_ui_viewport_size and is_equal_approx(ui_scale, current_ui_scale):
		return

	last_ui_viewport_size = viewport_size
	current_ui_scale = ui_scale

	_apply_centered_ui_scale(menus_root, ui_scale, visible_size * 0.5)
	_apply_centered_ui_scale(prompt_root, ui_scale, visible_size * 0.5)
	_apply_bottom_left_ui_scale(ping_hud_panel, ui_scale)
	_apply_top_left_ui_scale(debug_panel, ui_scale, DEBUG_PANEL_BASE_POSITION * ui_scale)


func _apply_centered_ui_scale(control: Control, scale_factor: float, pivot: Vector2) -> void:
	if control == null:
		return

	control.pivot_offset = pivot
	control.scale = Vector2.ONE * scale_factor


func _apply_bottom_left_ui_scale(control: Control, scale_factor: float) -> void:
	if control == null:
		return

	control.pivot_offset = Vector2(0.0, control.size.y)
	control.scale = Vector2.ONE * scale_factor


func _apply_top_left_ui_scale(control: Control, scale_factor: float, target_position: Vector2) -> void:
	if control == null:
		return

	control.pivot_offset = Vector2.ZERO
	control.position = target_position
	control.scale = Vector2.ONE * scale_factor


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

	death_menu_panel = _create_death_menu_panel()
	menus_root.add_child(death_menu_panel)


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


func _build_ping_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "PingHUD"
	hud_layer.layer = 110
	add_child(hud_layer)

	ping_hud_panel = PanelContainer.new()
	ping_hud_panel.name = "PingHUDPanel"
	ping_hud_panel.anchor_left = 0.0
	ping_hud_panel.anchor_right = 0.0
	ping_hud_panel.anchor_top = 1.0
	ping_hud_panel.anchor_bottom = 1.0
	ping_hud_panel.offset_left = 16.0
	ping_hud_panel.offset_top = -190.0
	ping_hud_panel.offset_right = 252.0
	ping_hud_panel.offset_bottom = -16.0
	ping_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(ping_hud_panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.02, 0.05, 0.72)
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.3, 0.85, 1.0, 0.7)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 10
	ping_hud_panel.add_theme_stylebox_override("panel", panel_style)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ping_hud_panel.add_child(content)

	ping_speed_label = Label.new()
	ping_speed_label.name = "PingSpeedLabel"
	ping_speed_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ping_speed_label.add_theme_font_size_override("font_size", 22)
	content.add_child(ping_speed_label)

	ping_cooldown_label = Label.new()
	ping_cooldown_label.name = "PingCooldownLabel"
	ping_cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ping_cooldown_label.add_theme_font_size_override("font_size", 13)
	content.add_child(ping_cooldown_label)

	ping_cooldown_bar = _create_hud_progress_bar(Color(0.2, 0.92, 1.0, 0.95))
	ping_cooldown_bar.name = "PingCooldownBar"
	content.add_child(ping_cooldown_bar)

	push_cooldown_label = Label.new()
	push_cooldown_label.name = "PushCooldownLabel"
	push_cooldown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	push_cooldown_label.add_theme_font_size_override("font_size", 13)
	content.add_child(push_cooldown_label)

	push_cooldown_bar = _create_hud_progress_bar(Color(1.0, 0.55, 0.2, 0.95))
	push_cooldown_bar.name = "PushCooldownBar"
	content.add_child(push_cooldown_bar)

	_update_ping_hud()


func _create_hud_progress_bar(fill_color: Color) -> ProgressBar:
	var progress_bar := ProgressBar.new()
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_bar.show_percentage = false
	progress_bar.custom_minimum_size = Vector2(0.0, 20.0)
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(0.08, 0.12, 0.16, 0.95)
	bar_background.border_width_left = 1
	bar_background.border_width_top = 1
	bar_background.border_width_right = 1
	bar_background.border_width_bottom = 1
	bar_background.border_color = Color(0.18, 0.42, 0.52, 0.95)
	bar_background.corner_radius_top_left = 3
	bar_background.corner_radius_top_right = 3
	bar_background.corner_radius_bottom_right = 3
	bar_background.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("background", bar_background)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = fill_color
	bar_fill.corner_radius_top_left = 3
	bar_fill.corner_radius_top_right = 3
	bar_fill.corner_radius_bottom_right = 3
	bar_fill.corner_radius_bottom_left = 3
	progress_bar.add_theme_stylebox_override("fill", bar_fill)

	return progress_bar


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
	subtitle.text = "Goal: Escape to the next room\n\nPress `Tab` to change settings."
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
	_set_centered_panel_rect(panel, Vector2(500.0, 560.0))

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

	pause_menu_tabs = TabContainer.new()
	pause_menu_tabs.name = "PauseMenuTabs"
	pause_menu_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_menu_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(pause_menu_tabs)

	var pause_tab := VBoxContainer.new()
	pause_tab.name = "Pause"
	pause_tab.add_theme_constant_override("separation", 14)
	pause_menu_tabs.add_child(pause_tab)

	var resume_button := Button.new()
	resume_button.text = "Resume"
	resume_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume_button.pressed.connect(_resume_game)
	pause_tab.add_child(resume_button)

	var return_button := Button.new()
	return_button.text = "Return to Main Menu"
	return_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return_button.pressed.connect(_return_to_main_menu)
	pause_tab.add_child(return_button)

	pause_tab.add_child(HSeparator.new())

	var goal_title := Label.new()
	goal_title.text = "Goal: Escape to the next room"
	goal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_tab.add_child(goal_title)

	# var goal_label := Label.new()
	# goal_label.text = "Escape the building."
	# goal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# goal_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# pause_tab.add_child(goal_label)

	pause_tab.add_child(HSeparator.new())

	var controls_title := Label.new()
	controls_title.text = "Controls"
	controls_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_tab.add_child(controls_title)

	var controls_label := Label.new()
	controls_label.text = "Jump: Space\nSwing: Mouse2\nStatic Vision: G\nSonar Ping: F\nPing Speed: Mouse Wheel\nPause: Tab"
	controls_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pause_tab.add_child(controls_label)

	var settings_tab := VBoxContainer.new()
	settings_tab.name = "Settings"
	settings_tab.add_theme_constant_override("separation", 14)
	pause_menu_tabs.add_child(settings_tab)

	var volume_title := Label.new()
	volume_title.text = "Volume"
	volume_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_tab.add_child(volume_title)

	_add_volume_slider(settings_tab, "Master", MASTER_BUS_NAME)
	_add_volume_slider(settings_tab, "Music", MUSIC_BUS_NAME)
	_add_volume_slider(settings_tab, "SFX", SFX_BUS_NAME)
	_add_mouse_sensitivity_slider(settings_tab)
	_add_graphics_quality_selector(settings_tab)

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


func _create_death_menu_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "DeathMenu"
	_set_centered_panel_rect(panel, Vector2(420.0, 250.0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(content)

	var title := Label.new()
	title.text = "Signal Lost"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	content.add_child(title)

	var message := Label.new()
	message.text = "You collided with an enemy."
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(message)

	var respawn_button := Button.new()
	respawn_button.text = "Respawn"
	respawn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	respawn_button.pressed.connect(_respawn_from_death_screen)
	content.add_child(respawn_button)

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


func _add_graphics_quality_selector(parent: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	# row.add_theme_constant_override("separation", 4)
	# parent.add_child(row)

	# var label := Label.new()
	# label.text = "Graphics Quality"
	# row.add_child(label)

	# quality_mode_selector = OptionButton.new()
	# quality_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# quality_mode_selector.add_item("Auto", GraphicsQualityMode.AUTO)
	# quality_mode_selector.add_item("High", GraphicsQualityMode.HIGH)
	# quality_mode_selector.add_item("Performance", GraphicsQualityMode.PERFORMANCE)
	# quality_mode_selector.item_selected.connect(_on_graphics_quality_selected)
	# row.add_child(quality_mode_selector)

	# _sync_graphics_quality_control()


func _add_mouse_sensitivity_slider(parent: VBoxContainer) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)

	var label := Label.new()
	label.text = "Mouse Sensitivity"
	row.add_child(label)

	var slider_row := HBoxContainer.new()
	slider_row.add_theme_constant_override("separation", 12)
	row.add_child(slider_row)

	mouse_sensitivity_slider = HSlider.new()
	mouse_sensitivity_slider.min_value = MOUSE_SENSITIVITY_MIN
	mouse_sensitivity_slider.max_value = MOUSE_SENSITIVITY_MAX
	mouse_sensitivity_slider.step = MOUSE_SENSITIVITY_STEP
	mouse_sensitivity_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_changed)
	slider_row.add_child(mouse_sensitivity_slider)

	mouse_sensitivity_value_label = Label.new()
	mouse_sensitivity_value_label.custom_minimum_size = Vector2(56.0, 0.0)
	mouse_sensitivity_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider_row.add_child(mouse_sensitivity_value_label)

	_sync_mouse_sensitivity_control()


func _show_start_menu() -> void:
	gameplay_started = false
	pause_menu_visible = false
	win_screen_visible = false
	death_screen_visible = false
	game_won = false
	_set_player_controls_enabled(false)
	interaction_prompt.visible = false
	menus_root.visible = true
	start_menu_panel.visible = true
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	death_menu_panel.visible = false
	_sync_volume_controls()
	_sync_mouse_sensitivity_control()
	_sync_graphics_quality_control()


func _start_game() -> void:
	if gameplay_started:
		return

	_start_game_internal(false)


func _start_game_from_input_event() -> void:
	if gameplay_started:
		return

	_ensure_audio_playback_unlocked()
	_start_game_internal(true)
	get_viewport().set_input_as_handled()


func _start_game_internal(capture_mouse: bool) -> void:
	gameplay_started = true
	pause_menu_visible = false
	win_screen_visible = false
	death_screen_visible = false
	menus_root.visible = false
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	death_menu_panel.visible = false
	_set_player_controls_enabled(true, capture_mouse)


func _pause_game() -> void:
	pause_menu_visible = true
	interaction_prompt.visible = false
	_set_player_controls_enabled(false)
	menus_root.visible = true
	start_menu_panel.visible = false
	pause_menu_panel.visible = true
	win_menu_panel.visible = false
	death_menu_panel.visible = false
	_sync_volume_controls()
	_sync_mouse_sensitivity_control()
	_sync_graphics_quality_control()
	_reset_pause_menu_tab()


func _resume_game() -> void:
	_resume_game_internal(false)


func _resume_game_from_input_event() -> void:
	_resume_game_internal(true)


func _resume_game_internal(capture_mouse: bool) -> void:
	pause_menu_visible = false
	menus_root.visible = false
	pause_menu_panel.visible = false
	death_menu_panel.visible = false
	_set_player_controls_enabled(true, capture_mouse)


func _return_to_main_menu() -> void:
	get_tree().reload_current_scene()


func _restart_game() -> void:
	get_tree().reload_current_scene()


func _show_win_screen() -> void:
	gameplay_started = false
	pause_menu_visible = false
	win_screen_visible = true
	death_screen_visible = false
	game_won = true
	_set_player_controls_enabled(false)
	interaction_prompt.visible = false
	_set_sonar_mode(false)
	menus_root.visible = true
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = true
	death_menu_panel.visible = false


func _show_death_screen() -> void:
	if death_screen_visible:
		return

	gameplay_started = false
	pause_menu_visible = false
	win_screen_visible = false
	death_screen_visible = true
	_set_player_controls_enabled(false)
	interaction_prompt.visible = false
	_set_sonar_mode(false)
	if death_sound_player != null:
		death_sound_player.stop()
		death_sound_player.play()
	menus_root.visible = true
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	death_menu_panel.visible = true


func _respawn_from_death_screen() -> void:
	if player == null:
		return

	player.call("respawn_at", player_spawn_transform)
	gameplay_started = true
	pause_menu_visible = false
	win_screen_visible = false
	death_screen_visible = false
	menus_root.visible = false
	start_menu_panel.visible = false
	pause_menu_panel.visible = false
	win_menu_panel.visible = false
	death_menu_panel.visible = false
	_set_player_controls_enabled(true, false)


func _set_player_controls_enabled(enabled: bool, capture_mouse: bool = true) -> void:
	if player == null:
		return

	player.call("set_controls_enabled", enabled, capture_mouse)


func _can_start_game_from_event(event: InputEvent) -> bool:
	return not gameplay_started and not win_screen_visible and not death_screen_visible and start_menu_panel != null and start_menu_panel.visible and _is_audio_unlock_event(event)


func _is_menu_open() -> bool:
	return not gameplay_started or pause_menu_visible or win_screen_visible or death_screen_visible


func _should_resume_pause_menu_from_event(event: InputEvent) -> bool:
	return pause_menu_visible and gameplay_started and not win_screen_visible and not death_screen_visible and event.is_action_pressed("pause_menu")


func _reset_pause_menu_tab() -> void:
	if pause_menu_tabs == null:
		return

	pause_menu_tabs.current_tab = 0


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


func _sync_graphics_quality_control() -> void:
	if quality_mode_selector == null:
		return

	quality_mode_selector.select(selected_graphics_quality_mode)


func _sync_mouse_sensitivity_control() -> void:
	if mouse_sensitivity_slider == null:
		return

	var value: float = _get_player_mouse_sensitivity()
	mouse_sensitivity_slider.set_value_no_signal(value)
	_update_mouse_sensitivity_label(value)


func _on_mouse_sensitivity_changed(value: float) -> void:
	var clamped_value: float = clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)
	_set_player_mouse_sensitivity(clamped_value)
	_update_mouse_sensitivity_label(clamped_value)


func _get_player_mouse_sensitivity() -> float:
	if player == null:
		return DEFAULT_MOUSE_SENSITIVITY

	return clampf(float(player.get("mouse_sensitivity")), MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX)


func _set_player_mouse_sensitivity(value: float) -> void:
	if player == null:
		return

	player.set("mouse_sensitivity", clampf(value, MOUSE_SENSITIVITY_MIN, MOUSE_SENSITIVITY_MAX))


func _update_mouse_sensitivity_label(value: float) -> void:
	if mouse_sensitivity_value_label == null:
		return

	mouse_sensitivity_value_label.text = "%.4f" % value


func _on_graphics_quality_selected(index: int) -> void:
	if selected_graphics_quality_mode == index:
		return

	selected_graphics_quality_mode = index
	graphics_quality_dirty = true
	_refresh_graphics_quality_profile(true)


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
	sonar_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_resize_sonar_viewport()
	sonar_camera.current = true


func _configure_kill_floor() -> void:
	if kill_floor == null:
		return

	if not kill_floor.body_entered.is_connected(_on_kill_floor_body_entered):
		kill_floor.body_entered.connect(_on_kill_floor_body_entered)


func _configure_player_signals() -> void:
	if player == null:
		return

	if not player.enemy_touched.is_connected(_on_player_enemy_touched):
		player.enemy_touched.connect(_on_player_enemy_touched)


func _resize_sonar_viewport() -> void:
	var viewport_size := _get_visible_viewport_size()
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var target_size := _get_scaled_sonar_viewport_size(viewport_size)
	if target_size == last_sonar_viewport_size:
		return

	last_sonar_viewport_size = target_size
	sonar_viewport.size = target_size


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
		_clear_ping()

	_sync_sonar_viewport_update_mode()
	_sync_music_players()
	_update_shader_state()


func _handle_sonar_ping_input() -> void:
	if ping_active:
		if ping_frozen:
			ping_frozen = false
			_update_ping_hud()
		else:
			ping_frozen = true
			_update_ping_hud()
		return

	if ping_cooldown_remaining <= 0.0:
		_start_ping()


func _start_ping() -> void:
	ping_active = true
	ping_frozen = false
	ping_radius = 0.0
	ping_origin_ws = player_camera.global_position
	ping_cooldown_duration = _get_effective_ping_cooldown_duration()
	ping_cooldown_remaining = ping_cooldown_duration
	if sonar_ping_player != null:
		_update_ping_sound_pitch()
		sonar_ping_player.play()
	_update_shader_state()


func _clear_ping() -> void:
	ping_active = false
	ping_frozen = false
	ping_radius = 0.0


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


func show_temporary_hint(text: String, duration: float) -> void:
	if tutorial_hint_label == null or text.is_empty():
		return

	tutorial_hint_label.text = text
	tutorial_hint_remaining = maxf(duration, 0.0)
	_update_tutorial_hint()


func _update_tutorial_hint() -> void:
	if tutorial_hint_label == null:
		return

	var should_show := gameplay_started and not pause_menu_visible and not win_screen_visible and tutorial_hint_remaining > 0.0
	tutorial_hint_label.visible = should_show
	if not should_show and tutorial_hint_remaining <= 0.0:
		tutorial_hint_label.text = ""


func show_achievement_notification(message: String, duration: float = ACHIEVEMENT_NOTIFICATION_DURATION) -> void:
	if achievement_message_label == null or message.is_empty():
		return

	achievement_message_label.text = message
	achievement_notification_remaining = maxf(duration, 0.0)
	_update_achievement_notification()


func _update_achievement_notification() -> void:
	if achievement_notification_panel == null or achievement_message_label == null:
		return

	var should_show := gameplay_started and not pause_menu_visible and not win_screen_visible and achievement_notification_remaining > 0.0
	achievement_notification_panel.visible = should_show
	if should_show:
		var alpha := 1.0
		if achievement_notification_remaining < 0.25:
			alpha = achievement_notification_remaining / 0.25
		achievement_notification_panel.self_modulate = Color(1.0, 1.0, 1.0, alpha)
	elif achievement_notification_remaining <= 0.0:
		achievement_message_label.text = ""
		achievement_notification_panel.self_modulate = Color.WHITE


func _get_interaction_prompt_text() -> String:
	if _can_trigger_win():
		return WIN_ORB_PROMPT_TEXT

	var light_switch := _get_interactable_light_switch()
	if light_switch != null:
		return light_switch.get_prompt_text()

	var door_button := _get_interactable_door_button()
	if door_button != null:
		return door_button.get_prompt_text()

	return ""


func _get_interactable_door_button() -> DoorButton:
	for node in get_tree().get_nodes_in_group(DOOR_BUTTON_GROUP):
		var door_button := node as DoorButton
		if door_button == null:
			continue

		if door_button.can_player_interact(player, player_camera):
			return door_button

	return null


func _get_interactable_light_switch() -> LightSwitchInteractable:
	for node in get_tree().get_nodes_in_group(LIGHT_SWITCH_GROUP):
		var light_switch := node as LightSwitchInteractable
		if light_switch == null:
			continue

		if light_switch.can_player_interact(player, player_camera):
			return light_switch

	return null


func _can_trigger_win() -> bool:
	return not game_won and _player_is_near_win_orb() and _player_is_facing_target(win_orb_body.global_position)


func _player_is_near_win_orb() -> bool:
	return player != null and win_orb_interaction_area != null and win_orb_interaction_area.overlaps_body(player)


func _player_is_facing_target(target_position: Vector3) -> bool:
	var to_target := (target_position - player_camera.global_position).normalized()
	var camera_forward := -player_camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target) >= DOOR_FACING_THRESHOLD


func _toggle_world_environment_energy() -> void:
	world_energy_enabled = not world_energy_enabled
	_sync_world_environment_energy_state()


func _sync_world_environment_energy_state() -> void:
	if world_environment == null or world_environment.environment == null:
		return

	world_environment.environment.background_energy_multiplier = (
		WORLD_ENERGY_ENABLED_MULTIPLIER if world_energy_enabled else WORLD_ENERGY_DISABLED_MULTIPLIER
	)


func _on_kill_floor_body_entered(body: Node) -> void:
	if body == player:
		player.call("respawn_at", player_spawn_transform)
		return

	var enemy := _resolve_enemy_from_kill_floor_body(body)
	if enemy != null:
		_despawn_enemy_from_kill_floor(enemy)


func _on_player_enemy_touched(_enemy: Enemy) -> void:
	if not gameplay_started or win_screen_visible or death_screen_visible:
		return

	_show_death_screen()


func _resolve_enemy_from_kill_floor_body(body: Node) -> Enemy:
	var current: Node = body
	while current != null:
		var enemy := current as Enemy
		if enemy != null:
			return enemy
		current = current.get_parent()

	return null


func _despawn_enemy_from_kill_floor(enemy: Enemy) -> void:
	if enemy == null or enemy.is_queued_for_deletion():
		return
	if enemy.has_meta("kill_floor_despawned"):
		return

	enemy.set_meta("kill_floor_despawned", true)
	enemy.queue_free()
	show_achievement_notification(GERONIMO_ACHIEVEMENT_TEXT)


func _sync_music_players() -> void:
	var target_player := sonar_music_player if sonar_mode_enabled else normal_music_player
	var source_player := normal_music_player if sonar_mode_enabled else sonar_music_player

	if not audio_playback_unlocked or target_player == null or source_player == null:
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


func _ensure_audio_playback_unlocked() -> void:
	if audio_playback_unlocked:
		return

	audio_playback_unlocked = true
	_sync_music_players()


func _is_audio_unlock_event(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo

	if event is InputEventMouseButton:
		return event.pressed

	return false


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


func _update_ping_hud() -> void:
	if ping_hud_panel == null or ping_speed_label == null or ping_cooldown_label == null or ping_cooldown_bar == null or push_cooldown_label == null or push_cooldown_bar == null:
		return

	ping_hud_panel.visible = gameplay_started and not pause_menu_visible and not win_screen_visible
	ping_hud_panel.self_modulate = Color(1.0, 1.0, 1.0, 1.0 if sonar_mode_enabled else 0.7)

	ping_speed_label.text = "Ping Speed: %d/%d" % [_get_ping_speed_ui_value(), PING_SPEED_UI_MAX]
	ping_cooldown_label.text = "Ping Cooldown (Paused)" if ping_frozen else "Ping Cooldown"

	var cooldown_max: float = maxf(
		ping_cooldown_duration if ping_cooldown_remaining > 0.0 or ping_active else _get_effective_ping_cooldown_duration(),
		0.001
	)
	ping_cooldown_bar.max_value = cooldown_max
	ping_cooldown_bar.value = minf(ping_cooldown_remaining, cooldown_max)

	push_cooldown_label.text = "Swing Cooldown"
	var push_cooldown_duration: float = 5.0
	var push_cooldown_remaining_value: float = 0.0
	if player != null and player.has_method("get_push_cooldown_state"):
		var push_cooldown_state_variant: Variant = player.call("get_push_cooldown_state")
		if push_cooldown_state_variant is Dictionary:
			var push_cooldown_state: Dictionary = push_cooldown_state_variant
			push_cooldown_duration = float(push_cooldown_state.get("duration", push_cooldown_duration))
			push_cooldown_remaining_value = float(push_cooldown_state.get("remaining", push_cooldown_remaining_value))

	push_cooldown_duration = maxf(push_cooldown_duration, 0.001)
	push_cooldown_bar.max_value = push_cooldown_duration
	push_cooldown_bar.value = minf(push_cooldown_remaining_value, push_cooldown_duration)


func _is_ping_speed_adjust_event(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and (
		event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN
	)


func _adjust_ping_speed(delta_amount: float) -> void:
	var next_speed: float = _clamp_ping_speed(ping_speed + delta_amount)
	if is_equal_approx(next_speed, ping_speed):
		return

	ping_speed = next_speed
	_update_ping_sound_pitch()
	_update_ping_hud()


func _get_ping_speed_ui_value() -> int:
	var clamped_speed: float = clampf(ping_speed, PING_SPEED_MIN_LIMIT, PING_SPEED_MAX_LIMIT)
	return int(roundi(clamped_speed / PING_SPEED_STEP))


func _update_ping_sound_pitch() -> void:
	if sonar_ping_player == null:
		return

	var clamped_speed: float = clampf(ping_speed, PING_SPEED_MIN_LIMIT, PING_SPEED_MAX_LIMIT)
	var speed_alpha: float = (clamped_speed - PING_SPEED_MIN_LIMIT) / (PING_SPEED_MAX_LIMIT - PING_SPEED_MIN_LIMIT)
	sonar_ping_player.pitch_scale = lerpf(PING_SOUND_MIN_PITCH, PING_SOUND_MAX_PITCH, speed_alpha)


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
	var root_viewport := get_viewport()
	var sonar_viewport_size := sonar_viewport.size if sonar_viewport != null else Vector2i.ZERO

	debug_label.text = "Debug\nFPS: %d\nFPS avg (5s): %.1f\nFrame ms: %.2f\nFrame ms avg (5s): %.2f\nNodes: %d\nObjects: %d\nDraw calls: %d\nGraphics: %s -> %s | 3D: %.2f | Sonar: %dx%d" % [
		current_fps,
		avg_fps,
		current_frame_ms,
		avg_frame_ms,
		total_nodes,
		total_objects,
		draw_calls,
		_get_graphics_quality_mode_label(selected_graphics_quality_mode),
		_get_graphics_quality_mode_label(effective_graphics_quality_mode),
		root_viewport.scaling_3d_scale,
		sonar_viewport_size.x,
		sonar_viewport_size.y,
	]


func _toggle_debug_overlay() -> void:
	debug_overlay_visible = not debug_overlay_visible
	if debug_panel != null:
		debug_panel.visible = debug_overlay_visible

	get_tree().call_group("signal_enemy", "set_debug_label_visible", debug_overlay_visible)

	if debug_overlay_visible:
		debug_overlay_timer = DEBUG_REFRESH_INTERVAL
		_update_debug_overlay(0.0)


func _is_debug_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false

	return event.pressed and not event.echo and (
		event.keycode == DEBUG_TOGGLE_KEY or event.physical_keycode == DEBUG_TOGGLE_KEY
	)


func _cache_graphics_quality_baseline() -> void:
	if world_environment != null and world_environment.environment != null:
		authored_glow_enabled = world_environment.environment.glow_enabled

	if room_omni_light != null:
		authored_room_light_shadow_enabled = room_omni_light.shadow_enabled

	if win_orb_omni_light != null:
		authored_win_orb_light_shadow_enabled = win_orb_omni_light.shadow_enabled


func _refresh_graphics_quality_profile(force: bool = false) -> void:
	var viewport_size := _get_visible_viewport_size()
	if viewport_size.x <= 0 or viewport_size.y <= 0:
		return

	var next_effective_mode := _get_effective_graphics_quality_mode(viewport_size)
	if not force \
	and not graphics_quality_dirty \
	and viewport_size == last_quality_viewport_size \
	and next_effective_mode == effective_graphics_quality_mode:
		return

	last_quality_viewport_size = viewport_size
	effective_graphics_quality_mode = next_effective_mode
	graphics_quality_dirty = false

	var root_viewport := get_viewport()
	root_viewport.scaling_3d_scale = _get_main_3d_scale_for_quality(effective_graphics_quality_mode)

	_apply_graphics_quality_effect_overrides()
	_resize_sonar_viewport()
	_sync_sonar_viewport_update_mode()
	_sync_graphics_quality_control()


func _get_visible_viewport_size() -> Vector2i:
	var visible_size := get_viewport().get_visible_rect().size
	return Vector2i(int(visible_size.x), int(visible_size.y))


func _get_effective_graphics_quality_mode(viewport_size: Vector2i) -> int:
	if selected_graphics_quality_mode != GraphicsQualityMode.AUTO:
		return selected_graphics_quality_mode

	var pixel_count := viewport_size.x * viewport_size.y
	return GraphicsQualityMode.PERFORMANCE if pixel_count >= AUTO_PERFORMANCE_PIXEL_THRESHOLD else GraphicsQualityMode.HIGH


func _get_main_3d_scale_for_quality(mode: int) -> float:
	return PERFORMANCE_MAIN_3D_SCALE if mode == GraphicsQualityMode.PERFORMANCE else HIGH_MAIN_3D_SCALE


func _get_sonar_viewport_scale_for_quality(mode: int) -> float:
	return PERFORMANCE_SONAR_VIEWPORT_SCALE if mode == GraphicsQualityMode.PERFORMANCE else HIGH_SONAR_VIEWPORT_SCALE


func _get_scaled_sonar_viewport_size(viewport_size: Vector2i) -> Vector2i:
	var scale := _get_sonar_viewport_scale_for_quality(effective_graphics_quality_mode)
	return Vector2i(
		maxi(2, int(roundf(viewport_size.x * scale))),
		maxi(2, int(roundf(viewport_size.y * scale)))
	)


func _apply_graphics_quality_effect_overrides() -> void:
	var use_performance_profile := effective_graphics_quality_mode == GraphicsQualityMode.PERFORMANCE

	if world_environment != null and world_environment.environment != null:
		world_environment.environment.glow_enabled = authored_glow_enabled and not use_performance_profile

	if room_omni_light != null:
		room_omni_light.shadow_enabled = authored_room_light_shadow_enabled and not use_performance_profile

	if win_orb_omni_light != null:
		win_orb_omni_light.shadow_enabled = authored_win_orb_light_shadow_enabled and not use_performance_profile


func _sync_sonar_viewport_update_mode() -> void:
	if sonar_viewport == null:
		return

	sonar_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if sonar_mode_enabled else SubViewport.UPDATE_DISABLED
	)


func _get_graphics_quality_mode_label(mode: int) -> String:
	match mode:
		GraphicsQualityMode.AUTO:
			return "Auto"
		GraphicsQualityMode.HIGH:
			return "High"
		GraphicsQualityMode.PERFORMANCE:
			return "Performance"
		_:
			return "Unknown"
