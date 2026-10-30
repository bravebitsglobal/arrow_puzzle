extends Control
class_name PanelOutOfLive
@onready var button_close: TextureButton = $Window/ButtonClose
@onready var button_get_free: Button = $Window/ButtonGetFree
@onready var button_buy: Button = $Window/ButtonBuy
@onready var button_restart: Button = $Window/ButtonRestart
@onready var label_title: Label = $Window/LabelTitle



# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_data.bomb_exploded.subscribe(func(exploded):
		label_title.text = "Bomb exploded!" if exploded else "Get more live?")
	button_restart.pressed.connect(func():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, false)
		Global.game_event.game_restart.emit()
		)
	button_close.pressed.connect(func():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, false)
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
	button_get_free.pressed.connect(func ():
		var is_reward = await Global.ad_manager.show_user_reward()
		if !is_reward:
			return
		Global.game_data.lives.value = maxi(Global.game_data.lives.value, 1)
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, false)
		Global.game_event.game_continue.emit()
		)
	button_buy.pressed.connect(func ():
		if Global.game_data.coins.value < 900:
			Global.popup_manager.show_toast("Not enough coins")
			return
		Global.game_data.coins.value = Global.game_data.coins.value - 900
		Global.game_data.lives.value = 3
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, false)
		Global.game_event.game_continue.emit()
		)
