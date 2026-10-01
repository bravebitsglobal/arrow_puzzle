extends Control
class_name PanelBase
var panel_name: String

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Global.game_event.request_visible_game_panel.connect(check_visible_event)
func check_visible_event(name: String, visible: bool)->void:
	if name != panel_name:
		return
	self.visible = visible
