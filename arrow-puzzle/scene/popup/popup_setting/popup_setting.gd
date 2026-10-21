extends Control
class_name PopupSetting
@onready var check_music: CheckButton = $NinePatchRect/CheckMusic
@onready var check_sfx: CheckButton = $NinePatchRect/CheckSFX
@onready var button_confirm: Button = $NinePatchRect/ButtonConfirm
@onready var button_close: TextureButton = $NinePatchRect/ButtonClose


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_close.pressed.connect(func ():
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Setting, false)
		)
	button_confirm.pressed.connect(func ():
		confirm_setting()
		)
	check_music.toggled.connect(func (toggle_on: bool):
		Global.game_data.player_data.setting_enable_music = toggle_on
		Global.game_event.on_setting_updated.emit()
		)
	check_sfx.toggled.connect(func (toggle_on: bool):
		Global.game_data.player_data.setting_enable_sfx = toggle_on
		Global.game_event.on_setting_updated.emit()
		)
	check_music.button_pressed = Global.game_data.player_data.setting_enable_music
	check_sfx.button_pressed = Global.game_data.player_data.setting_enable_sfx
func confirm_setting():
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.Setting, false)
	Global.game_data.player_data.setting_enable_music = check_music.button_pressed
	Global.game_data.player_data.setting_enable_sfx = check_sfx.button_pressed
	Global.game_data.player_data.save()
