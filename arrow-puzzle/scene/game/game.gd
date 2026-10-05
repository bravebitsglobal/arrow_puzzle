extends Node2D
class_name Game
@onready var line_container: Node2D = $MapContainer/LineContainer
var used_cells: Dictionary = {}
@export var dot_scene: PackedScene
var level_generator = LevelGenerator.new()
@onready var dot_container: Node2D = $MapContainer/DotContainer
@onready var camera_2d: CameraController = $Camera2D
@export var arrow_scene: PackedScene
var remain_magic_glasses: int = 0
var level
var arrows: Array[Arrow] = []
var total_line: int = 0
var is_using_eraser: bool = false
class ExitPathResult:
	var can_exit: bool
	var exit_path: Array[PackedInt32Array]
func _ready() -> void:
	next_level()
	Global.game_event.game_start.connect(func():
		next_level())
	Global.game_event.game_restart.connect(func():
		restart())
	Global.game_event.active_game_booster.connect(_on_active_booster)
	Global.game_data.is_ruler.subscribe(func (value):
		render_ruler())
func render_ruler()->void:
	if !Global.game_data.is_ruler.value:
		return
	if !level:
		return
	for i in range(level.size()):
		if arrows[i].is_exit:
			continue
		var exit_path = calculate_exit_path(level[i])
		if exit_path.can_exit:
			arrows[i].set_ruler(exit_path)
func render_level():
	Global.game_data.lives.value = Global.game_data.MAX_LIVE
	total_line = level.size()
	Global.game_data.remain_lines.value = total_line
	for c in line_container.get_children():
		c.queue_free()
	for a in arrows:
		a.queue_free()
	arrows.clear()
	for d in dot_container.get_children():
		d.queue_free()
	await get_tree().process_frame
	for arrow_idx in range(level.size()):
		var points = level[arrow_idx]
		var a: Array[PackedInt32Array] = [];
		for p in points:
			a.append(p)
		var arrow: Arrow = arrow_scene.instantiate()
		line_container.add_child(arrow)
		arrow.set_data(a)
		arrows.append(arrow)
		for c in a:
			var pos = Utils.to_pos(c)
			var dot = dot_scene.instantiate()
			dot.position = pos
			dot_container.add_child(dot)
			used_cells[Utils.to_index(c)] = true
		arrow.on_click.connect(func ():
			_on_arrow_clicked(arrow_idx))
func _on_active_booster(booster: Global.Booster)->void:
	match(booster):
		Global.Booster.Hint:
			_active_hint()
		Global.Booster.Eraser:
			_active_eraser()
		Global.Booster.MagicGlasses:
			_active_magic_glasses()
func _active_hint()->void:
	for i in range(level.size()):
		if arrows[i].is_exit:
			continue
		var exit_path = calculate_exit_path(level[i])
		if exit_path.can_exit:
			arrows[i].active_highlight()
			move_camera_to_arrow(i)
			break
func move_camera_to_arrow(idx)->void:
	var tw = create_tween()
	tw.tween_property(camera_2d, "position", Utils.get_center(level[idx]), 0.5)
	await get_tree().create_timer(0.5).timeout
func _active_eraser()->void:
	Global.game_data.animating.value = true
	is_using_eraser = true
func _active_magic_glasses()->void:
	remain_magic_glasses = Global.MAGIC_GLASSES_QUANTITY
	Global.game_data.animating.value = true
	for glass in range(remain_magic_glasses):
		if !used_cells.size():
			check_end_game()
			break
		for i in range(level.size()):
			if arrows[i].is_exit:
				continue
			var exit_path = calculate_exit_path(level[i])
			if exit_path.can_exit:
				await move_camera_to_arrow(i)
				arrows[i].active_highlight()
				await get_tree().create_timer(1).timeout
				arrows[i].exit(exit_path)
				await get_tree().create_timer(1).timeout
				break
	Global.game_data.animating.value = false
func _on_arrow_clicked(idx: int):
	if is_using_eraser:
		arrows[idx].erase()
		remove_arrow(idx)
		is_using_eraser = false
		Global.game_event.game_booster_done.emit(Global.Booster.Eraser)
		Global.game_data.animating.value = false
		return
	var rs = calculate_exit_path(level[idx])
	if rs.can_exit:
		remove_arrow(idx)
		Global.game_data.remain_lines.value = Global.game_data.remain_lines.value - 1
	else:
		Global.game_data.lives.value = Global.game_data.lives.value - 1
	arrows[idx].exit(rs)
	check_end_game()
	await get_tree().create_timer(1).timeout
	Global.game_data.animating.value = false
func move_camera_to_center()->void:
	var left_top = level[0][0].duplicate()
	var right_bottom = level[0][0].duplicate()
	for arrow in level:
		for cell in arrow:
			if left_top[0] > cell[0]:
				left_top[0] = cell[0]
			if left_top[1] > cell[1]:
				left_top[1] = cell[1]
			if right_bottom[0] < cell[0]:
				right_bottom[0] = cell[0]
			if right_bottom[1] < cell[1]:
				right_bottom[1] = cell[1]
	var center = Vector2(
		(left_top[0] + right_bottom[0]) / 2 * Utils.cell_size, 
		(left_top[1] + right_bottom[1]) / 2 * Utils.cell_size)
	camera_2d.position = center
func check_end_game():
	if !Global.game_data.lives.value:
		await get_tree().create_timer(1).timeout
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.GameTryAgain, true)
		return
	if !used_cells.size():
		await get_tree().create_timer(1).timeout
		Global.game_event.request_visible_popup.emit(PopupManager.PopupType.GameWin, true)
func remove_arrow(idx: int):
	for c in level[idx]:
		used_cells.erase(Utils.to_index(c))
	render_ruler()
func calculate_exit_path(data)->ExitPathResult:
	var result = ExitPathResult.new()
	var exit_path:Array[PackedInt32Array]
	for d in data:
		exit_path.append(d)
	var head = data[data.size() - 1]
	var out = 100
	result.can_exit = true
	match(Utils.get_exit_dir(data)):
		Utils.Direction.Up:
			for i in range(head[1]-1, head[1] - out, -1):
				var next_pos = [head[0], i]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					break
		Utils.Direction.Down:
			for i in range(head[1]+1, head[1] + out):
				var next_pos = [head[0], i]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					break
		Utils.Direction.Left:
			for i in range(head[0]-1, head[0] - out, -1):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					break
		Utils.Direction.Right:
			for i in range(head[0]+1, head[0] + out):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					break
	result.exit_path = exit_path
	return result
func next_level()->void:
	level = await Global.api.get_level(Global.game_data.level.value)
	Global.game_data.lives.value = Global.game_data.MAX_LIVE
	move_camera_to_center()
	render_level()
func restart()->void:
	Global.game_data.is_ruler.value = false
	Global.game_data.lives.value = Global.game_data.MAX_LIVE
	move_camera_to_center()
	render_level()
