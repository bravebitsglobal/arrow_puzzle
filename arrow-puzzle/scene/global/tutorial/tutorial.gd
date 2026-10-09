extends Control
class_name Tutorial
@onready var background: ColorRect = $Background
var node_parent: Node
var current_node: Node
var target_node: Dictionary[String, TutorialTarget] = {}
@onready var panel_message: PanelContainer = $PanelMessage
@onready var label_message: Label = $PanelMessage/MarginContainer/VBoxContainer/LabelMessage
var TUTORIAL_STEPS = [{
	"trigger": GameEnum.UserAction.LevelStart,
	"level": 1,
	"action": "focus_an_arrow",
	"end_trigger": GameEnum.UserAction.ResolveArrow,
}, {
	"trigger":GameEnum.UserAction.LevelStart,
	"level": 5,
	"action": "focus_booster_button",
	"button":"game.hint",
	"message":"Suggest an arrow",
	"end_trigger": GameEnum.UserAction.ActiveBooster,
},{
	"trigger":GameEnum.UserAction.LevelStart,
	"level": 6,
	"action": "show_rating",
},{
	"trigger":GameEnum.UserAction.LevelStart,
	"level": 7,
	"action": "focus_booster_button",
	"button":"game.ruler",
	"message":"Draw exit path",
	"end_trigger": GameEnum.UserAction.ActiveBooster,
},{
	"trigger":GameEnum.UserAction.LevelStart,
	"level": 8,
	"action": "focus_booster_button",
	"button":"game.eraser",
	"message":"Erase an arrow",
	"end_trigger": GameEnum.UserAction.ActiveBooster,
},{
	"trigger":GameEnum.UserAction.LevelStart,
	"level": 12,
	"action": "focus_booster_button",
	"button":"game.magicglasses",
	"message":"Resolve 5 arrows",
	"end_trigger": GameEnum.UserAction.ActiveBooster,
}]
func highlight_node(node)->void:
	current_node = node
	var parent = current_node.get_parent()
	node_parent = parent.get_parent()
	parent.reparent(self, true)
	background.visible = true
func _ready() -> void:
	Global.game_event.user_action.connect(_on_game_action)
	Global.game_event.register_tutorial_target.connect(func (id: String, node: Node):
		target_node[id] = node
		)
	Global.game_data.active_tutorial.subscribe(func (step):
		if step && step.has('message'):
			panel_message.visible = true
		else:
			panel_message.visible = false
		)
		
func check_tutorial_done(action, _data)->void:
	if !Global.game_data.active_tutorial.value:
		return
	var step = Global.game_data.active_tutorial.value
	if not (step.has('end_trigger') and step.end_trigger == action):
		return
	if current_node:
		current_node.get_parent().reparent(node_parent, true)
		current_node = null
	background.visible = false
	Global.game_data.active_tutorial.value = null
func _on_game_action(action: GameEnum.UserAction, data: Dictionary)->void:
	check_tutorial(action, data)
	check_tutorial_done(action, data)
func check_tutorial(action, data)->void:
	var level = Global.game_data.level.value
	var step = get_step(level, action)
	if !step:
		return
	run_step(step, data)
func get_step(level: int, action: GameEnum.UserAction):
	var step_idx = TUTORIAL_STEPS.find_custom(func (i): 
		return i.level == Global.game_data.level.value && i.trigger == action
		)
	if step_idx == -1:
		return null
	return TUTORIAL_STEPS[step_idx]
func run_step(step, data)->void:
	Global.game_data.active_tutorial.value = step
	match step.action:
		"focus_booster_button":
			if not target_node.has(step.button):
				return
			highlight_node(target_node[step.button])
			if step['message']:
				label_message.text = step.message
		"focus_an_arrow":
			var game:Game = data['game']
			game.focus_arrow(game.get_hint_idx())
