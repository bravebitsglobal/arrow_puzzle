extends Control
class_name PopupPause
@onready var button_quit: Button = $NinePatchRect/ButtonQuit
@onready var button_resume: Button = $NinePatchRect/ButtonResume
func _ready() -> void:
	button_quit.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Pause, false)
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
	button_resume.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Pause, false)
		)
