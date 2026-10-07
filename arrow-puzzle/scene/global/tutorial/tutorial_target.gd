extends Control
class_name TutorialTarget
@export var id: String
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_event.register_tutorial_target.emit(id, get_parent())
func _exit_tree() -> void:
	Global.game_event.unregister_tutorial_target.emit(id)
