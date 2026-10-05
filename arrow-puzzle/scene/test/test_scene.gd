extends Control
class_name TestScene
@onready var button_reward: Button = $VBoxContainer/ButtonReward
@onready var ad_manager: AdManager = $AdManager
@onready var button_register: Button = $VBoxContainer/ButtonRegister
@onready var button_get_level: Button = $VBoxContainer/ButtonGetLevel

func _ready() -> void:
	button_reward.pressed.connect(_on_button_reward_pressed)
	button_register.pressed.connect(func():
		var rs = await Global.api.device_register("device_1", "vn", "tung beo")
		)
	button_get_level.pressed.connect(func():
		var rs = await Global.api.get_level(50)
		)
func _on_button_reward_pressed()->void:
	var is_rewarded = await ad_manager.show_user_reward()
