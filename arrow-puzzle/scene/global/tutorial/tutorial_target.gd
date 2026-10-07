extends Control
class_name TutorialTarget
@export var id: String
signal pressed
func _ready() -> void:
	Global.game_event.register_tutorial_target.emit(id, self)
	if get_parent().has_signal("pressed"):
		get_parent().pressed.connect(func ():
			pressed.emit())
