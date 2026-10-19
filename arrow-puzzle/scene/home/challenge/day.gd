extends Button
class_name Day
@onready var label_selected: Label = $CenterContainer/TextureSelected/LabelSelected
@onready var label_disable: Label = $CenterContainer/TextureDisable/LabelDisable
@onready var label_enable: Label = $CenterContainer/LabelEnable
@onready var texture_selected: TextureRect = $CenterContainer/TextureSelected
@onready var texture_completed: TextureRect = $CenterContainer/TextureCompleted


signal clicked(date: int)
var date
var is_enable: bool
var state: String
func _ready() -> void:
	pressed.connect(func ():
		if date && is_enable:
			clicked.emit(date)
		)
func set_date(_date: int)->void:
	date = _date
	label_selected.text = str(date)
	label_disable.text = str(date)
	label_enable.text = str(date)
func set_state(_state: String)->void:
	state = _state
	texture_completed.visible = false
	texture_selected.visible = false
	label_disable.get_parent().visible = false
	label_enable.visible = false
	match state:
		'enable':
			is_enable = true
			label_enable.visible = true
		'disable':
			is_enable = false
			label_disable.get_parent().visible = true
		'resolved':
			texture_completed.visible = true
		'selected':
			texture_selected.visible = true
			
