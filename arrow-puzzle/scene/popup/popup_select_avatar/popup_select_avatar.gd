extends Control
class_name PopupSelectAvatar
@onready var button_confirm: Button = $TextureRect/ButtonConfirm
@onready var indicator: NinePatchRect = $TextureRect/ScrollContainer/Control/Indicator
@onready var avatar_container: GridContainer = $TextureRect/ScrollContainer/Control/AvatarContainer
@onready var button_close: TextureButton = $TextureRect/ButtonClose

var selected: int = -1
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_confirm.pressed.connect(_on_button_confirm)
	button_close.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.SelectAvatar, false)
		)
	for i: int in range(avatar_container.get_children().size()):
		var a: Avatar = avatar_container.get_child(i)
		a.set_avatar(i)
		a.pressed.connect(func ():
			_on_avatar_click(i))
	Global.game_data.avatar.subscribe(func (id):
		_on_avatar_click(id)
		)

func _on_avatar_click(id: int)->void:
	var item = avatar_container.get_child(id)
	indicator.position = item.position
	selected = id
func _on_button_confirm()->void:
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.SelectAvatar, false)
	if selected == -1:
		return
	Global.game_data.avatar.value = selected
	Global.api.save_profile()
	Global.game_data.save_data()
