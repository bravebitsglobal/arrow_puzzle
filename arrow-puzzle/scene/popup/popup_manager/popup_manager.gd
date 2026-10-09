extends Control
class_name PopupManager
@onready var popup_loading: Control = $PopupLoading
@onready var toast_container: Control = $ToastContainer

enum PopupType {
	GameWin,
	GameTryAgain,
	OutOfLive
}
@export var popup_scene: Dictionary[PopupType, PackedScene] = {}
@export var toast_scene: PackedScene
var popup_node: Dictionary[PopupType, Control] = {}
var last_z_index: int = 100
const ANIMATION_DURATION: float = 0.2
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_event.request_visible_popup.connect(func (type: PopupType, visible: bool):
		if visible: 
			show_popup(type)
		else:
			hide_popup(type)
		)
func show_loading()->void:
	popup_loading.visible = true
func hide_loading()->void:
	popup_loading.visible = false
func show_popup(type: PopupType)->void:
	last_z_index = last_z_index + 1
	if !popup_node.has(type):
		if popup_scene.has(type):
			var popup_container = ColorRect.new()
			popup_container.set_anchors_preset(Control.PRESET_FULL_RECT)
			popup_container.color = Color(0,0,0,0.9)
			var content: Control = popup_scene[type].instantiate()
			content.offset_transform_enabled = true
			popup_container.add_child(content)
			add_child(popup_container)
			popup_node[type] = popup_container
		else:
			print("[PopupManager] popup not found ", PopupType.keys()[type])
			return
	popup_node[type].z_index = last_z_index
	popup_node[type].visible = true
	popup_node[type].self_modulate = Color(1,1,1,0)
	var tw = create_tween().set_parallel(true)
	tw.tween_property(popup_node[type], 'self_modulate', Color(1,1,1,1), ANIMATION_DURATION)
	var content_node:Control = popup_node[type].get_child(0)
	content_node.offset_transform_position = Vector2(0, 100)
	content_node.modulate = Color(1,1,1,0)
	tw.tween_property(content_node, "offset_transform_position", Vector2.ZERO, ANIMATION_DURATION)
	tw.tween_property(content_node, "modulate", Color(1,1,1,1), ANIMATION_DURATION)
	tw.tween_property(popup_node[type], 'self_modulate', Color(1,1,1,1), ANIMATION_DURATION)
	mouse_filter = Control.MOUSE_FILTER_PASS
func hide_popup(type: PopupType)->void:
	var tw = create_tween().set_parallel(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var content_node:Control = popup_node[type].get_child(0)
	content_node.offset_transform_position = Vector2.ZERO
	tw.tween_property(content_node, 'modulate', Color(1,1,1,0), ANIMATION_DURATION)
	tw.tween_property(popup_node[type], 'self_modulate', Color(1,1,1,0), ANIMATION_DURATION)
	tw.tween_property(content_node, "offset_transform_position", Vector2(0, 100), ANIMATION_DURATION)
	await tw.finished
	popup_node[type].visible = false
func show_toast(content: String)->void:
	var node: Toast = toast_scene.instantiate()
	toast_container.add_child(node)
	node.set_text(content)
