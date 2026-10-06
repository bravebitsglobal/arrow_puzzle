extends Control
class_name PanelOutOfLive
@onready var label_title: Label = $Window/LabelTitle
@onready var button_close: TextureButton = $Window/ButtonClose
@onready var button_get_free: TextureButton = $Window/Content/HBoxContainer/ButtonGetFree
@onready var button_buy: TextureButton = $Window/Content/HBoxContainer/ButtonBuy

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_close.pressed.connect(func():
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.OutOfLive, false)
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.GameTryAgain, true)
		)
	button_get_free.pressed.connect(func ():
		var is_reward = await Global.ad_manager.show_user_reward()
		if !is_reward:
			return
		Global.game_data.lives.value = 1
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.OutOfLive, false)
		)
	button_buy.pressed.connect(func ():
		if Global.game_data.coins.value < 900:
			Global.popup_manager.show_toast("Not enough coins")
			return
		Global.game_data.coins.value = Global.game_data.coins.value - 900
		Global.game_data.lives.value = 3
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.OutOfLive, false)
		)
