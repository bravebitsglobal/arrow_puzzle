extends Control
class_name Toast
@onready var label: Label = $PanelContainer/Label
@onready var animation_player: AnimationPlayer = $AnimationPlayer
func _ready() -> void:
	auto_destroy()
func auto_destroy()->void:
	await get_tree().create_timer(5).timeout
	queue_free()
func set_text(text: String)->void:
	label.text = text
