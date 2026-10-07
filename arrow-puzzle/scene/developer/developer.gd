extends Control
@onready var input_level: LineEdit = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/InputLevel
@onready var input_coins: LineEdit = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/InputCoins
@onready var button_clear_user_data: Button = $ScrollContainer/VBoxContainer/Control/ButtonClearUserData
@onready var button_back: Button = $ButtonBack
@onready var button_edit_player_data: Button = $ScrollContainer/VBoxContainer/Control2/HBoxContainer/ButtonEditPlayerData
@onready var input_tutorial_step: LineEdit = $ScrollContainer/VBoxContainer/Tutorial/HBoxContainer/InputTutorialStep
@onready var button_edit_tutorial_step: Button = $ScrollContainer/VBoxContainer/Tutorial/HBoxContainer/ButtonEditTutorialStep


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_clear_user_data.pressed.connect(clear_user_data)
	button_back.pressed.connect(func ():
		get_tree().change_scene_to_file("res://scene/home/home.tscn")
		)
	button_edit_player_data.pressed.connect(edit_player_data)
	button_edit_tutorial_step.pressed.connect(edit_tutorial_step)
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
