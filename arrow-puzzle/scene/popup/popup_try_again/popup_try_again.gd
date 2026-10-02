extends Control
class_name PanelTryAgain
@onready var label_title: Label = $Window/LabelTitle
@onready var button_close: TextureButton = $Window/ButtonClose
@onready var button_try_again: TextureButton = $Window/Content/ButtonTryAgain
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_close.pressed.connect(func():
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.GameTryAgain, false)
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
	button_try_again.pressed.connect(func ():
		Global.game_event.game_restart.emit()
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.GameTryAgain, false)
		)
	Global.game_data.level.subscribe(func (lvl):
		label_title.text = "Level " + str(lvl)
		)
