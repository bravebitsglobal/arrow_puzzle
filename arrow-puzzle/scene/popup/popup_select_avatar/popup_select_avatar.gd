extends Control
class_name PopupSelectAvatar
@onready var avatar_container: GridContainer = $TextureRect/ScrollContainer/AvatarContainer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for i: int in range(avatar_container.get_children().size()):
		var a: Avatar = avatar_container.get_child(i)
		a.set_avatar(i)
		a.pressed.connect(func ():
			_on_avatar_click(i))

func _on_avatar_click(id: int)->void:
	print("avatar click ", id)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
