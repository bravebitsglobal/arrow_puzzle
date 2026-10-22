extends Control
class_name Main
@onready var button_play: TextureButton = $PanelBottom/ButtonPlay
@onready var label_coins: Label = $PanelTop/Coin/LabelCoins
@onready var button_developer: Button = $PanelTop/ButtonDeveloper
@onready var label_level: Label = $PanelBottom/Level/LabelLevel
@onready var button_setting: TextureButton = $PanelTop/ButtonSetting

func _ready() -> void:
	button_setting.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Setting, true)
		)
	button_developer.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/developer/developer.tscn")
		)
	Global.game_data.level.subscribe(func (level):
		label_level.text = "Level " + str(level)
		label_level.visible = level > 0
		)
	button_play.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/game/game.tscn")
		)
	Global.game_data.coins.subscribe(func (coins):
		label_coins.text = str(coins)
		)
