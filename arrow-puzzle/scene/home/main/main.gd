extends Control
class_name Main
@onready var label_level: Label = $PanelBottom/ButtonPlay/LabelLevel
@onready var button_play: TextureButton = $PanelBottom/ButtonPlay
@onready var label_coins: Label = $PanelTop/Coin/LabelCoins

func _ready() -> void:
	Global.game_data.level.subscribe(func (level):
		label_level.text = "Level " + str(level)
		label_level.visible = level > 0
		)
	button_play.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/game/game.tscn")
		Global.game_data.level.value = Global.game_data.level.value + 1
		)
	Global.game_data.coins.subscribe(func (coins):
		label_coins.text = str(coins)
		)
