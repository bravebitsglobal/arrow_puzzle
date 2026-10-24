extends Control
@onready var input_level: LineEdit = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/InputLevel
@onready var input_coins: LineEdit = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/InputCoins
@onready var button_clear_user_data: Button = $ScrollContainer/VBoxContainer/Control/ButtonClearUserData
@onready var button_back: Button = $ButtonBack
@onready var button_edit_player_data: Button = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/ButtonEditPlayerData
@onready var input_tutorial_step: LineEdit = $ScrollContainer/VBoxContainer/Tutorial/HBoxContainer/InputTutorialStep
@onready var button_edit_tutorial_step: Button = $ScrollContainer/VBoxContainer/Tutorial/HBoxContainer/ButtonEditTutorialStep
@onready var input_hint: LineEdit = $ScrollContainer/VBoxContainer/Booster/HBoxContainer/InputHint
@onready var input_eraser: LineEdit = $ScrollContainer/VBoxContainer/Booster/HBoxContainer/InputEraser
@onready var input_magic_glasses: LineEdit = $ScrollContainer/VBoxContainer/Booster/HBoxContainer/InputMagicGlasses
@onready var input_ruler: LineEdit = $ScrollContainer/VBoxContainer/Booster/HBoxContainer/InputRuler
@onready var button_edit_booster: Button = $ScrollContainer/VBoxContainer/Booster/HBoxContainer/ButtonEditBooster


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_clear_user_data.pressed.connect(clear_user_data)
	button_back.pressed.connect(func ():
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
	button_edit_player_data.pressed.connect(edit_player_data)
	button_edit_tutorial_step.pressed.connect(edit_tutorial_step)
	button_edit_booster.pressed.connect(edit_booster)
	# Hien so luong booster hien tai de sua
	input_hint.text = str(Global.game_data.booster_hint.value)
	input_eraser.text = str(Global.game_data.booster_eraser.value)
	input_magic_glasses.text = str(Global.game_data.booster_magic_glasses.value)
	input_ruler.text = str(Global.game_data.booster_ruler.value)
func edit_booster()->void:
	Global.game_data.booster_hint.value = int(input_hint.text)
	Global.game_data.booster_eraser.value = int(input_eraser.text)
	Global.game_data.booster_magic_glasses.value = int(input_magic_glasses.text)
	Global.game_data.booster_ruler.value = int(input_ruler.text)
	Global.game_data.save_data()
func edit_tutorial_step()->void:
	Global.game_data.tutorial_step.value = int(input_tutorial_step.text)
	Global.game_data.save_data()
func clear_user_data()->void:
	var file_path = "user://player_data.tres"
	# Kiểm tra xem file có tồn tại hay không trước khi xóa
	if FileAccess.file_exists(file_path):
		var err = DirAccess.remove_absolute(file_path)
		if err == OK:
			print("Xóa file thành công!")
		else:
			print("Xóa file thất bại, mã lỗi: ", err)
	else:
		print("File không tồn tại.")
func edit_player_data()->void:
	Global.game_data.level.value = int(input_level.text)
	Global.game_data.coins.value = int(input_coins.text)
	Global.game_data.save_data()
