extends Button
class_name Avatar
@onready var texture_rect: TextureRect = $TextureRect

@export var images: Array[Texture] = []
func set_avatar(id: int)->void:
	texture_rect.texture = images[id]
