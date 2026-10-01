extends Control
class_name TestScene
@onready var button_reward: Button = $VBoxContainer/ButtonReward
@onready var ad_manager: AdManager = $AdManager

func _ready() -> void:
	button_reward.pressed.connect(_on_button_reward_pressed)


func _on_button_reward_pressed()->void:
	var is_rewarded = await ad_manager.show_user_reward()
	print("is rewarded ", is_rewarded)
