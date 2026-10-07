extends Control
class_name Tutorial
@onready var background: ColorRect = $Background
var node_parent: Node
var current_node: Node
var target_node: Dictionary[String, TutorialTarget] = {}
const TUTORIAL_STEPS = [{
	"level": 1,
	"action": "focus_anrrow"
}, {
	"level": 5,
	"action": "focus_button",
	"button":"game.hint"
},{
	"level": 6,
	"action": "show_rating",
},{
	"level": 7,
	"action": "focus_button",
	"button":"game.ruler"
},{
	"level": 8,
	"action": "focus_button",
	"button":"game.eraser"
},{
	"level": 12,
	"action": "focus_button",
	"button":"game.magicglasses"
}]
func highlight_node(node)->void:
	current_node = node
	current_node.get_parent().reparent(self, true)
	background.visible = true
	node.z_index = 10000
func _ready() -> void:
	Global.game_event.user_action.connect(_on_game_action)
	Global.game_event.register_tutorial_target.connect(func (id: String, node: Node):
		target_node[id] = node
		)
func tutorial_done()->void:
	Global.game_data.is_tutorial.value = false
	current_node.get_parent().reparent(node_parent, true)
	background.visible = false
func _on_game_action(action: GameEvent.UserAction, data: Dictionary)->void:
	match action:
		GameEvent.UserAction.GameStart:
			var step_idx = TUTORIAL_STEPS.find_custom(func (i): return i.level == Global.game_data.level.value)
			if step_idx == -1:
				return
			var game: Game = data['game']
			run_step(TUTORIAL_STEPS[step_idx], {"game": game})
		GameEvent.UserAction.FirstArrow:
			match Global.game_data.tutorial_step.value:
				0:
					Global.game_data.tutorial_step.value += 1
					Global.game_data.save_data()
					print("step ", Global.game_data.tutorial_step.value)
func run_step(step, _data)->void:
	match step.action:
		"focus_button":
			if not target_node.has(step.button):
				return
			Global.game_data.is_tutorial.value = true
			highlight_node(target_node[step.button])
			target_node[step.button].pressed.connect(tutorial_done, CONNECT_ONE_SHOT)
