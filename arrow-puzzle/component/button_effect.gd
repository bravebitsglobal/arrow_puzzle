extends Control
class_name ButtonEffect
var color_tween: Tween
var scale_tween: Tween
const EFFECT_TIME = 0.2
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var parent_node: Control = get_parent()
	parent_node.pivot_offset_ratio = Vector2(0.5, 0.5)
	parent_node.pressed.connect(func():
		if scale_tween:
			scale_tween.kill()
		scale_tween = create_tween()
		scale_tween.tween_property(parent_node, "scale", Vector2(1.1, 1.1), EFFECT_TIME/2)
		scale_tween.tween_property(parent_node, "scale", Vector2.ONE, EFFECT_TIME/2)
		)
	parent_node.mouse_entered.connect(func():
		if color_tween:
			color_tween.kill()
		color_tween = create_tween()
		color_tween.tween_property(parent_node, "modulate", Color("#cecece"), EFFECT_TIME)
		)
	parent_node.mouse_exited.connect(func():
		if color_tween:
			color_tween.kill()
		color_tween = create_tween()
		color_tween.tween_property(parent_node, "modulate", Color("#ffffff"), EFFECT_TIME)
		)
