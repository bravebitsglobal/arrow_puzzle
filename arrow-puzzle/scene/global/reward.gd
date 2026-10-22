extends Control
class_name Reward
@export var images: Dictionary[GameEnum.RewardType, Texture2D]
@onready var image: TextureRect = $TextureRect/Image
@onready var label: Label = $TextureRect/Label


# Called when the node enters the scene tree for the first time.
func set_data(reward)->void:
	image.texture = images[reward.reward_type]
	label.text = str(reward.quantity)
