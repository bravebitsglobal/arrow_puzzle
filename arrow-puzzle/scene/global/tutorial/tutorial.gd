extends Control
class_name Tutorial
@onready var background: ColorRect = $Background
var node_parent: Node
var current_node: Node
var target_node: Dictionary = {}

func highlight_node(node)->void:
	return
	current_node = node
	current_node.reparent(self, true)
	background.visible = true
	node.z_index = 10000
func _ready() -> void:
	Global.game_event.user_action.connect(_on_game_action)
	Global.game_event.register_tutorial_target.connect(func (id: String, node: Node):
		target_node[id] = node
		)
	Global.game_event.unregister_tutorial_target.connect(func (id: String):
		if not target_node.has(id):
			return
		target_node.erase(id)
		)
func _on_game_action(action: GameEvent.UserAction, data: Dictionary)->void:
	match action:
		GameEvent.UserAction.GameStart:
			print("level ", Global.game_data.level.value)
			match Global.game_data.level.value:
				1:
					var game: Game = data['game']
					var hint_idx = game.get_hint_idx()
					game.focus_arrow(hint_idx)
				5:
					print("highlight hint")
					if target_node.has('game.hint'):
						highlight_node(target_node['game.hint'])
		GameEvent.UserAction.FirstArrow:
			print("First arrow")
			match Global.game_data.tutorial_step.value:
				0:
					Global.game_data.tutorial_step.value += 1
					Global.game_data.save_data()
					print("step ", Global.game_data.tutorial_step.value)
