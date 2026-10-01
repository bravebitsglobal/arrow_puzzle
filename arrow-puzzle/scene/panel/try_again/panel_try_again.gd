extends PanelBase
class_name PanelTryAgain
@onready var label_title: Label = $Background/Window/LabelTitle
@onready var button_close: TextureButton = $Background/Window/ButtonClose
@onready var button_try_again: TextureButton = $Background/Window/Content/ButtonTryAgain
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	super()
	panel_name = 'panel_game_try_again'
	button_close.pressed.connect(func():
		Global.game_event.request_visible_game_panel.emit(panel_name, false)
		)
	button_try_again.pressed.connect(func ():
		Global.game_event.game_retry.emit()
		)
	Global.game_data.level.subscribe(func (lvl):
		label_title.text = "Level " + str(lvl)
		)
