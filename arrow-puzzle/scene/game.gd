extends Node2D
class_name Game
var grid = [4248,4249,4250,4251,4252,4253,4348,4349,4350,4351,4352,4353,4448,4449,4450,4451,4452,4453,4548,4549,4550,4551,4552,4553,4648,4649,4650,4651,4652,4653,4748,4749,4750,4751,4752,4753,4848,4849,4850,4851,4852,4853,4948,4949,4950,4951,4952,4953,5048,5049,5050,5051,5052,5053,5148,5149,5150,5151,5152,5153,5248,5249,5250,5251,5252,5253,5348,5349,5350,5351,5352,5353,5448,5449,5450,5451,5452,5453,5548,5549,5550,5551,5552,5553]
@onready var line_container: Node2D = $MapContainer/LineContainer
@onready var button_start_game: Button = $UI/PanelWelcome/ButtonStartGame
@onready var panel_welcome: Panel = $UI/PanelWelcome
@onready var panel_lose: Panel = $UI/PanelLose
@onready var button_restart: Button = $UI/PanelLose/ButtonRestart
@onready var label_live: Label = $UI/PanelGame/LabelLive
@onready var button_next_level: Button = $UI/PanelWin/ButtonNextLevel
@onready var panel_win: Panel = $UI/PanelWin

var used_cells: Dictionary = {}
@export var dot_scene: PackedScene
var level_generator = LevelGenerator.new()
@onready var dot_container: Node2D = $MapContainer/DotContainer

@export var arrow_scene: PackedScene
var level
var arrows: Array[Arrow] = []
const MAX_LIVE = 3
var live: int = MAX_LIVE
class ExitPathResult:
	var can_exit: bool
	var exit_path: PackedInt32Array
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	button_start_game.pressed.connect(_on_button_start_game_click)
	button_restart.pressed.connect(_on_button_restart_game_click)
	label_live.text = "LIVE: " + str(live)
	button_next_level.pressed.connect(_on_button_start_game_click)
func render_level():
	live = MAX_LIVE
	label_live.text = "LIVE: " + str(live)
	for c in line_container.get_children():
		c.queue_free()
	for a in arrows:
		a.queue_free()
	arrows.clear()
	for d in dot_container.get_children():
		d.queue_free()
	for arrow_idx in range(level.size()):
		var a = level[arrow_idx]
		var arrow: Arrow = arrow_scene.instantiate()
		line_container.add_child(arrow)
		arrow.set_data(a)
		arrow.move_finish.connect(on_move_finish)
		arrows.append(arrow)
		for c in a.cells:
			var pos = Utils.index_to_pos(c)
			var dot = dot_scene.instantiate()
			dot.position = pos
			dot_container.add_child(dot)
		arrow.on_click.connect(func ():
			_on_arrow_clicked(arrow_idx))
		for i in a.cells:
			used_cells[i] = true
func _on_arrow_clicked(idx: int):
	var rs = calculate_exit_path(level[idx])
	if rs.can_exit:
		remove_arrow(idx)
	else:
		live = live - 1
		label_live.text = "LIVE: " + str(live)
	arrows[idx].exit(rs)
	if !used_cells.size():
		panel_win.visible = true
func on_move_finish():
	if !live:
		panel_lose.visible = true
func remove_arrow(idx: int):
	for c in level[idx].cells:
		used_cells.erase(c)
func calculate_exit_path(data)->ExitPathResult:
	var result = ExitPathResult.new()
	var exit_path = data.cells.duplicate()
	var head_index = data.cells[data.cells.size()-1]
	var head_pos = Utils.to_xy(head_index)
	result.can_exit = true
	match(data.exit_dir):
		0:
			for i in range(head_pos.y-1, 0, -1):
				var idx = Utils.to_index(Vector2(head_pos.x, i))
				exit_path.append(idx)
				if used_cells.has(idx):
					result.can_exit = false
					break
		1:
			for i in range(head_pos.y+1, Utils.grid_width):
				var idx = Utils.to_index(Vector2(head_pos.x, i))
				exit_path.append(idx)
				if used_cells.has(idx):
					result.can_exit = false
					break
		2:
			for i in range(head_pos.x-1, 0, -1):
				var idx = Utils.to_index(Vector2(i, head_pos.y))
				exit_path.append(idx)
				if used_cells.has(idx):
					result.can_exit = false
					break
		3:
			for i in range(head_pos.x+1, Utils.grid_width):
				var idx = Utils.to_index(Vector2(i, head_pos.y))
				exit_path.append(idx)
				if used_cells.has(idx):
					result.can_exit = false
					break
	result.exit_path = exit_path
	return result
func _on_button_start_game_click():
	level = level_generator.generate_level(grid, 3)
	render_level()
	panel_welcome.visible = false
	panel_win.visible = false
func _on_button_restart_game_click():
	render_level()
	panel_lose.visible = false
