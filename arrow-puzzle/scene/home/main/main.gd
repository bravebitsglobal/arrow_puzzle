extends Control
class_name Main
@onready var button_play: TextureButton = $PanelBottom/ButtonPlay
@onready var label_coins: Label = $PanelTop/Coin/LabelCoins
@onready var button_developer: Button = $PanelTop/ButtonDeveloper
@onready var label_level: Label = $PanelBottom/Level/LabelLevel
@onready var button_setting: TextureButton = $PanelTop/ButtonSetting
@onready var avatar: Avatar = $Avatar
@onready var animation_button: Button = $AnimationButton
@onready var spine_sprite: SpineSprite = $AnimationButton/SpineSprite

func _ready() -> void:
	animation_button.pressed.connect(func ():
		spine_sprite.get_animation_state().set_animation('action')
		spine_sprite.animation_completed.connect(func (spine, state, track):
			spine_sprite.get_animation_state().set_animation('idle')
			, CONNECT_ONE_SHOT)
		)
	spine_sprite.get_animation_state().set_animation('idle')
	avatar.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.SelectAvatar, true)
		)
	Global.game_data.avatar.subscribe(func (id):
		avatar.set_avatar(id)
		)
	button_setting.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Setting, true)
		)
	button_developer.pressed.connect(func():
		get_tree().change_scene_to_file("res://scene/developer/developer.tscn")
		)
	Global.game_data.level.subscribe(func (level):
		label_level.text = "Level " + str(level)
		label_level.visible = level > 0
		)
	button_play.pressed.connect(func():
		Global.game_data.current_challenge.value = []
		get_tree().change_scene_to_file("res://scene/game/game.tscn")
		)
	Global.game_data.coins.subscribe(func (coins):
		label_coins.text = str(coins)
		)
