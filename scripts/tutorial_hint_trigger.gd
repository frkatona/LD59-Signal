class_name TutorialHintTrigger
extends Area3D

const MAIN_PLAYER_GROUP := &"main_player"
const GAME_CONTROLLER_GROUP := &"game_controller"

@export_multiline var hint_text: String = ""
@export var hint_duration_seconds: float = 10.0
@export var one_shot: bool = true

var has_triggered := false


func _ready() -> void:
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if has_triggered or not body.is_in_group(MAIN_PLAYER_GROUP):
		return

	var controller := get_tree().get_first_node_in_group(GAME_CONTROLLER_GROUP)
	if controller == null or not controller.has_method("show_temporary_hint"):
		return

	controller.call("show_temporary_hint", hint_text, hint_duration_seconds)
	if one_shot:
		has_triggered = true
		set_deferred("monitoring", false)
		set_deferred("monitorable", false)
