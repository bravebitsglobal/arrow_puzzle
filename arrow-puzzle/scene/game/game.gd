extends Node2D
class_name Game
var grid = [4248,4249,4250,4251,4252,4253,4348,4349,4350,4351,4352,4353,4448,4449,4450,4451,4452,4453,4548,4549,4550,4551,4552,4553,4648,4649,4650,4651,4652,4653,4748,4749,4750,4751,4752,4753,4848,4849,4850,4851,4852,4853,4948,4949,4950,4951,4952,4953,5048,5049,5050,5051,5052,5053,5148,5149,5150,5151,5152,5153,5248,5249,5250,5251,5252,5253,5348,5349,5350,5351,5352,5353,5448,5449,5450,5451,5452,5453,5548,5549,5550,5551,5552,5553]
@onready var line_container: Node2D = $MapContainer/LineContainer
@onready var button_restart: Button = $UI/PanelLose/ButtonRestart
@onready var button_next_level: Button = $UI/PanelWin/ButtonNextLevel

var used_cells: Dictionary = {}
@export var dot_scene: PackedScene
var level_generator = LevelGenerator.new()
@onready var dot_container: Node2D = $MapContainer/DotContainer
@onready var live_container: HBoxContainer = $UI/PanelGame/TopPanel/HBoxContainer/LiveContainer
@onready var label_line: Label = $UI/PanelGame/TopPanel/Panel/TextureRect/LabelLine
@onready var camera_2d: CameraController = $Camera2D
@onready var button_claim: TextureButton = $UI/PanelWin/HBoxContainer/ButtonClaim
@onready var button_claimx_2: TextureButton = $UI/PanelWin/HBoxContainer/ButtonClaimx2
@onready var label_level: Label = $UI/PanelGame/TopPanel/HBoxContainer/Level/LabelLevel
@onready var label_coin: Label = $UI/PanelGame/TopPanel/HBoxContainer/Coin/LabelCoin

@export var arrow_scene: PackedScene
var level: Array
var arrows: Array[Arrow] = []
var total_line: int = 0
var remain_line: int = 0:
	set(value):
		remain_line = value
		label_line.text = str(remain_line)
const MAX_LIVE = 3
var live: int:
	set(value):
		live = value
		render_live()
class ExitPathResult:
	var can_exit: bool
	var exit_path: PackedInt32Array
func _ready() -> void:
	next_level()
	Global.game_data.level.subscribe(func(lvl):
		label_level.text = str(lvl))
	Global.game_data.coins.subscribe(func(coins):
		label_coin.text = str(coins))
	Global.game_event.game_next_level.connect(func():
		next_level())
func render_live()->void:
	if !live_container:
		return
	for i in range(MAX_LIVE):
		live_container.get_child(i).get_child(0).visible = i < live
func render_level():
	live = MAX_LIVE
	total_line = level.size()
	remain_line = total_line
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
		remain_line = remain_line - 1
	else:
		live = live - 1
	arrows[idx].exit(rs)
func move_camera_to_center()->void:
	var left_top: Vector2 = Utils.to_xy(level[0].cells[0])
	var right_bottom: Vector2 = Utils.to_xy(level[0].cells[0])
	for arrow in level:
		for cell in arrow.cells:
			var xy = Utils.to_xy(cell)
			if left_top.x > xy.x:
				left_top.x = xy.x
			if left_top.y > xy.y:
				left_top.y = xy.y
			if right_bottom.x < xy.x:
				right_bottom.x = xy.x
			if right_bottom.y < xy.y:
				right_bottom.y = xy.y
	var center = Vector2(
		(left_top.x + right_bottom.x) / 2 * Utils.cell_size, 
		(left_top.y + right_bottom.y) / 2 * Utils.cell_size)
	camera_2d.position = center
	print("move camera to ", center)
func on_move_finish():
	if !live:
		Global.game_event.request_visible_game_panel.emit("panel_game_try_again", true)
		return
	if !used_cells.size():
		var is_done = true
		for a in arrows:
			if a.action != Arrow.Action.Exited:
				is_done = false
		if is_done:
			Global.game_event.request_visible_game_panel.emit("panel_game_win", true)
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
func next_level()->void:
	level = level_generator.generate_level(grid, 3)
	live = 2
	move_camera_to_center()
	render_level()
