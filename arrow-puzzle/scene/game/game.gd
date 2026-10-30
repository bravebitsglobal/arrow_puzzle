extends Node2D
class_name Game
@onready var line_container: Node2D = $MapContainer/LineContainer
var used_cells: Dictionary = {}
@export var dot_scene: PackedScene
var level_generator = LevelGenerator.new()
@onready var dot_container: Node2D = $MapContainer/DotContainer
@onready var camera_2d: CameraController = $Camera2D
@export var arrow_scene: PackedScene
@onready var button_auto_play: Button = $UI/PanelGame/TopPanel/ButtonAutoPlay
var tap_count:int = 0
var blocked_tap_count: int = 0
# idx cac arrow da bi tru live do bi block trong game hien tai
var penalized_arrows: Dictionary = {}
var start_time: int = 0
var remain_magic_glasses: int = 0
var level
var arrows: Array[Arrow] = []
# cell index -> Dot
var dots: Dictionary = {}
# Toc do lan toa khi an dot luc thang (px/s)
const DISSOLVE_SPEED: float = 600
const DotScript = preload("res://dot/dot.gd")
var total_line: int = 0
var is_using_eraser: bool = false
var is_focus: bool = false
var is_animating: bool = false
var is_finish: bool = false
class ExitPathResult:
	var can_exit: bool
	var exit_path: Array[PackedInt32Array]
	# idx arrow bi dam vao khi khong thoat duoc, -1 neu thoat duoc
	var blocked_idx: int = -1
func _ready() -> void:
	next_level()
	Global.game_event.game_start.connect(func():
		next_level())
	Global.game_event.game_restart.connect(func():
		restart())
	Global.game_event.user_action.connect(_on_user_action)
	button_auto_play.pressed.connect(auto_play)
func auto_play()->void:
	for i in range(level.size()):
		var idx = get_hint_idx()
		_on_arrow_clicked(idx)
		await get_tree().create_timer(0.01).timeout
func render_ruler()->void:
	if !level:
		return
	Global.game_data.is_ruler.value = true
	for i in range(level.size()):
		if arrows[i].is_exit:
			continue
		arrows[i].set_ruler()
func clear_ruler()->void:
	Global.game_data.is_ruler.value = false
	for a in arrows:
		a.clear_ruler()
func render_level():
	is_finish = false
	Global.game_data.is_ruler.value = false
	start_time = Time.get_unix_time_from_system() * 1000
	tap_count = 0
	blocked_tap_count = 0
	penalized_arrows.clear()
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
	dots.clear()
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
			dots[Utils.to_index(c)] = dot
			used_cells[Utils.to_index(c)] = arrow_idx
		arrow.tail_passed.connect(_on_arrow_tail_passed)
		arrow.on_click.connect(func ():
			_on_arrow_clicked(arrow_idx))
	Global.game_event.user_action.emit.call_deferred(GameEnum.UserAction.LevelStart, {"game": self})
func _on_arrow_tail_passed(cell: PackedInt32Array, color: Color) -> void:
	var dot = dots.get(Utils.to_index(cell))
	if dot:
		dot.pulse(color)
func _on_user_action(action: GameEnum.UserAction, data: Dictionary)->void:
	match action:
		GameEnum.UserAction.ActiveBooster:
			var booster = data.booster
			match(booster):
				GameEnum.Booster.Hint:
					_active_hint()
				GameEnum.Booster.Eraser:
					_active_eraser()
				GameEnum.Booster.MagicGlasses:
					_active_magic_glasses()
				GameEnum.Booster.Ruler:
					render_ruler()
func _active_hint()->void:
	var idx = get_hint_idx()
	arrows[idx].active_highlight()
	move_camera_to_arrow(idx)
func get_hint_idx()->int:
	for i in range(level.size()):
		if arrows[i].is_exit:
			continue
		var exit_path = calculate_exit_path(level[i])
		if exit_path.can_exit:
			return i
	return 0
func get_hint_node()->Node2D:
	var idx = get_hint_idx()
	return arrows[idx]
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
				remove_arrow(i)
				await get_tree().create_timer(1).timeout
				break
	Global.game_data.animating.value = false
func _on_arrow_clicked(idx: int):
	tap_count += 1
	if Global.game_data.animating.value and not is_using_eraser:
		return
	if Global.game_data.is_ruler.value:
		clear_ruler()
	if is_using_eraser:
		arrows[idx].erase()
		Global.game_data.remain_lines.value -= 1
		remove_arrow(idx)
		is_using_eraser = false
		Global.game_event.game_booster_done.emit(GameEnum.Booster.Eraser)
		Global.game_data.animating.value = false
		return
	var rs = calculate_exit_path(level[idx])
	if rs.can_exit:
		remove_arrow(idx)
		if Global.game_data.remain_lines.value == level.size():
			Global.game_event.user_action.emit(GameEnum.UserAction.ResolveArrow, {})
		Global.game_data.remain_lines.value -= 1
		Global.firebase_manager.log_event("arrow_tap", {"level_id": Global.game_data.level.value, "row_id": idx, "result": "success"})
	else:
		blocked_tap_count += 1
		# Moi arrow chi bi tru live 1 lan khi bi block trong mot game
		if !penalized_arrows.has(idx):
			penalized_arrows[idx] = true
			Global.game_data.lives.value -= 1
			Global.firebase_manager.log_event("life_lost", {
				"level_id": Global.game_data.level.value,
				"row_id": idx, "result": "fail", "reason":"blocked",
				"live_before": Global.game_data.lives.value + 1,
				"live_after": Global.game_data.lives.value})
		Global.firebase_manager.log_event("arrow_tap", {"level_id": Global.game_data.level.value, "row_id": idx, "result": "fail"})
	arrows[idx].exit(rs, arrows[rs.blocked_idx] if rs.blocked_idx >= 0 else null)
	check_end_game()
	await get_tree().create_timer(1).timeout
	Global.game_data.animating.value = false
	if is_focus:
		clear_focus()
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
	if is_finish:
		return
	if !Global.game_data.lives.value:
		is_finish = true
		await get_tree().create_timer(1).timeout
		Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, true)
		Global.firebase_manager.log_event("level_fail", {
				"level_id": Global.game_data.level.value - 1,
				"active_duration_ms": Time.get_unix_time_from_system() * 1000- start_time,
				"tap_count": tap_count,
				"blocked_tap_count": blocked_tap_count,
				"reason":"out_of_live"
			})
		return
	if !used_cells.size():
		is_finish = true
		# Doi arrow cuoi roi khoi o cuoi cung, roi an cac dot lan toa tu giua ra
		for a in arrows:
			if !a.has_left_cells:
				await a.left_cells
		await dissolve_dots()
		await get_tree().create_timer(0.3).timeout
		if Global.game_data.current_challenge.value.size():
			Global.game_data.player_data.set_challenge_resolved(
				Global.game_data.current_challenge.value[0],
				Global.game_data.current_challenge.value[1],
				Global.game_data.current_challenge.value[2])
			Global.game_data.home_tab.value = 2
			Global.game_data.current_challenge.value = []
			get_tree().change_scene_to_file("res://scene/home/home.tscn")
		else:
			Global.game_event.request_visible_popup.emit(GameEnum.PopupType.GameWin, true)
			Global.game_event.game_resolved.emit(Global.game_data.level.value)
			Global.game_data.level.value += 1
			Global.firebase_manager.log_event("level_complete", {
				"level_id": Global.game_data.level.value - 1,
				"active_duration_ms": Time.get_unix_time_from_system() * 1000- start_time,
				"tap_count": tap_count,
				"blocked_tap_count": blocked_tap_count
			})
## An tat ca dot theo hieu ung lan toa tu tam ban ra xung quanh, doi den khi xong.
func dissolve_dots() -> void:
	if !dots.size():
		return
	var rect := Rect2(dots.values()[0].position, Vector2.ZERO)
	for dot in dots.values():
		rect = rect.expand(dot.position)
	var center := rect.get_center()
	var max_delay: float = 0
	for dot in dots.values():
		var delay: float = dot.position.distance_to(center) / DISSOLVE_SPEED
		max_delay = maxf(max_delay, delay)
		dot.dissolve(delay)
	await get_tree().create_timer(max_delay + DotScript.DISSOLVE_TIME).timeout
func remove_arrow(idx: int):
	for c in level[idx]:
		used_cells.erase(Utils.to_index(c))
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
					result.blocked_idx = used_cells[idx]
					break
		Utils.Direction.Down:
			for i in range(head[1]+1, head[1] + out):
				var next_pos = [head[0], i]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					result.blocked_idx = used_cells[idx]
					break
		Utils.Direction.Left:
			for i in range(head[0]-1, head[0] - out, -1):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					result.blocked_idx = used_cells[idx]
					break
		Utils.Direction.Right:
			for i in range(head[0]+1, head[0] + out):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if used_cells.has(idx):
					result.can_exit = false
					result.blocked_idx = used_cells[idx]
					break
	result.exit_path = exit_path
	return result
func next_level()->void:
	Global.popup_manager.show_loading()
	if Global.game_data.current_challenge.value.size():
		level = await Global.api.get_challenge_by_date(
			Global.game_data.current_challenge.value[0],
			Global.game_data.current_challenge.value[1],
			Global.game_data.current_challenge.value[2])
	else:
		level = await Global.api.get_level(Global.game_data.level.value)
		Global.firebase_manager.log_event("level_start", {
			"level_id": Global.game_data.level.value,
			})
		
	Global.popup_manager.hide_loading()
	Global.game_data.lives.value = Global.game_data.MAX_LIVE
	move_camera_to_center()
	render_level()
func restart()->void:
	Global.firebase_manager.log_event("level_start")
	Global.game_data.lives.value = Global.game_data.MAX_LIVE
	move_camera_to_center()
	render_level()
func focus_arrow(idx: int)->void:
	is_focus = true
	move_camera_to_arrow(idx)
	for i in range(arrows.size()):
		arrows[i].set_enable(i == idx)
func clear_focus()->void:
	is_focus = false
	for i in range(arrows.size()):
		arrows[i].set_enable(true)
