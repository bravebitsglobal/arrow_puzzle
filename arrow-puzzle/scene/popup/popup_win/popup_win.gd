extends Control
class_name PopupWin
@onready var button_x_2: Button = $TextureRect/ButtonX2
@onready var button_continue: Button = $TextureRect/ButtonContinue
@onready var label_coin: Label = $TextureRect/Coin/LabelCoin
@onready var button_close: TextureButton = $TextureRect/ButtonClose

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	label_coin.text = str(Global.COINS_PER_LEVEL)
	button_continue.pressed.connect(_on_button_claim_pressed)
	button_x_2.pressed.connect(_on_claim_x2_pressed)
	button_close.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.GameWin, false)
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
func _on_button_claim_pressed()->void:
	
	Global.game_data.coins.value = Global.game_data.coins.value + Global.COINS_PER_LEVEL
	Global.game_data.save_data()
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.GameWin, false)
	Global.game_event.game_start.emit()
		
func _on_claim_x2_pressed()->void:
	var is_reward = await Global.ad_manager.show_user_reward()
	if !is_reward:
		return
	Global.game_data.coins.value = 	Global.game_data.coins.value + Global.COINS_PER_LEVEL * 2
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.GameWin, false)
	Global.game_event.game_start.emit()
	Global.game_data.save_data()
