extends Control
@onready var check_music: CheckButton = $NinePatchRect/CheckMusic
@onready var check_sfx: CheckButton = $NinePatchRect/CheckSFX
@onready var button_confirm: Button = $NinePatchRect/ButtonConfirm


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if Global.game_data.player_data.setting_enable_sound
