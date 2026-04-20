class_name LightSwitchInteractable
extends Node3D

const LIGHT_SWITCH_GROUP := &"light_switch_interactable"
const SIGNAL_LIGHT_SWITCH_GROUP := &"signal_light_switch"
const SONAR_REVEAL_GROUP := &"sonar_reveal"
const BUTTON_ANIMATION_NAME := &"switch-down"
const SFX_BUS_NAME := &"SFX"
const LIGHT_SWITCH_SFX := preload("res://assets/audio/sfx/switch_1.wav")

@export var prompt_turn_on_text: String = "Press E to turn lights on"
@export var prompt_turn_off_text: String = "Press E to turn lights off"
@export_range(-1.0, 1.0, 0.01) var facing_threshold: float = 0.65
@export var target_light_path: NodePath
@export_group("Startup")
@export var apply_initial_state := false
@export var initial_on := false
@export_group("")
@export var toggle_debounce_seconds: float = 0.25

@onready var switch_root: Node3D = $"light-switch"
@onready var interaction_area: Area3D = $InteractionArea

var animation_player: AnimationPlayer
var sfx_player: AudioStreamPlayer
var target_light: OmniLight3D
var toggle_cooldown_remaining := 0.0


func _ready() -> void:
	add_to_group(LIGHT_SWITCH_GROUP)
	add_to_group(SIGNAL_LIGHT_SWITCH_GROUP)
	if switch_root != null:
		switch_root.add_to_group(SONAR_REVEAL_GROUP)

	animation_player = _find_animation_player(switch_root)
	target_light = _resolve_target_light()
	if target_light == null:
		push_warning("LightSwitchInteractable target light is missing for %s." % [name])
	elif apply_initial_state:
		target_light.visible = initial_on

	_sync_visual_state()

	if DisplayServer.get_name() == "headless":
		return

	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "LightSwitchPlayer"
	sfx_player.bus = SFX_BUS_NAME
	sfx_player.stream = LIGHT_SWITCH_SFX
	add_child(sfx_player)


func _process(delta: float) -> void:
	if toggle_cooldown_remaining <= 0.0:
		return

	toggle_cooldown_remaining = maxf(toggle_cooldown_remaining - delta, 0.0)


func get_prompt_text() -> String:
	return prompt_turn_off_text if _is_light_enabled() else prompt_turn_on_text


func get_signal_source_position() -> Vector3:
	if switch_root != null:
		return switch_root.global_position

	return global_position


func can_player_interact(player: CharacterBody3D, camera: Camera3D) -> bool:
	if toggle_cooldown_remaining > 0.0 or player == null or camera == null:
		return false

	if not _has_target_light() or interaction_area == null or switch_root == null:
		return false

	if not interaction_area.overlaps_body(player):
		return false

	var to_target := (switch_root.global_position - camera.global_position).normalized()
	var camera_forward := -camera.global_transform.basis.z.normalized()
	return camera_forward.dot(to_target) >= facing_threshold


func interact() -> bool:
	if not _has_target_light() or toggle_cooldown_remaining > 0.0:
		return false

	var new_enabled := not target_light.visible
	target_light.visible = new_enabled
	toggle_cooldown_remaining = toggle_debounce_seconds
	_play_toggle_sound()
	_play_toggle_animation(not new_enabled)
	return true


func _is_light_enabled() -> bool:
	return _has_target_light() and target_light.visible


func _has_target_light() -> bool:
	if target_light != null and is_instance_valid(target_light):
		return true

	target_light = _resolve_target_light()
	return target_light != null


func _resolve_target_light() -> OmniLight3D:
	var explicit_target := get_node_or_null(target_light_path) as OmniLight3D
	if explicit_target != null:
		return explicit_target

	var current: Node = get_parent()
	while current != null:
		var candidate := _find_omni_light_in_ancestor(current)
		if candidate != null:
			return candidate

		current = current.get_parent()

	return null


func _find_omni_light_in_ancestor(root: Node) -> OmniLight3D:
	if root == null:
		return null

	for child in root.get_children():
		if child == self:
			continue

		if child is OmniLight3D:
			return child as OmniLight3D

	for child in root.get_children():
		if child == self:
			continue

		var candidate := _find_omni_light_recursive(child)
		if candidate != null:
			return candidate

	return null


func _find_omni_light_recursive(root: Node) -> OmniLight3D:
	if root == null:
		return null

	if root is OmniLight3D:
		return root as OmniLight3D

	for child in root.get_children():
		var candidate := _find_omni_light_recursive(child)
		if candidate != null:
			return candidate

	return null


func _play_toggle_animation(play_forward: bool) -> void:
	if animation_player == null or not animation_player.has_animation(BUTTON_ANIMATION_NAME):
		return

	if play_forward:
		animation_player.play(BUTTON_ANIMATION_NAME)
	else:
		animation_player.play(BUTTON_ANIMATION_NAME, -1.0, -1.0, true)


func _sync_visual_state() -> void:
	if animation_player == null or not animation_player.has_animation(BUTTON_ANIMATION_NAME):
		return

	var switch_animation := animation_player.get_animation(BUTTON_ANIMATION_NAME)
	if switch_animation == null:
		return

	animation_player.play(BUTTON_ANIMATION_NAME)
	animation_player.seek(switch_animation.length if not _is_light_enabled() else 0.0, true)
	animation_player.pause()


func _play_toggle_sound() -> void:
	if sfx_player == null:
		return

	sfx_player.play()


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root == null:
		return null

	if root is AnimationPlayer:
		return root as AnimationPlayer

	for child in root.get_children():
		var candidate := _find_animation_player(child)
		if candidate != null:
			return candidate

	return null
