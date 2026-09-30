extends CanvasLayer
class_name LoadingScene
@onready var texture_progress_bar: TextureProgressBar = $VBoxContainer/Panel/TextureProgressBar
const LOADING_TIME: float = 0.5
@onready var label: Label = $VBoxContainer/Panel/TextureProgressBar/Label

func _ready() -> void:
	var tween = create_tween()
	tween.tween_property(texture_progress_bar, "value", 100, LOADING_TIME)
	texture_progress_bar.value_changed.connect(func (value: float):
		label.text = str(value) + "%")
	tween.finished.connect(func():
		get_tree().change_scene_to_file("res://scene/home/home.tscn"))
