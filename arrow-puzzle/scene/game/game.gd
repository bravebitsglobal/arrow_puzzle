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
# Obstacle (GDD sheet 04), nap tu field "obstacles" cua level
var level_obstacles: Dictionary = {}
# arrow idx -> N con lai truoc khi active
var frozen_n: Dictionary = {}
var hidden_n: Dictionary = {}
# arrow idx -> N con lai truoc khi no (Bomb dang active)
var bomb_n: Dictionary = {}
# arrow idx -> lock group; locked_group la arrow bi khoa, key_group la arrow chia khoa
var locked_group: Dictionary = {}
var key_group: Dictionary = {}
# cell index -> {"n": int, "node": Node2D}
var crates: Dictionary = {}
# Bomb vua no, cho nguoi choi Continue (BOMB_FAIL_PENDING), -1 neu khong co
var bomb_pending: int = -1
const LOCK_COLORS = ["#C9A000", "#7A4CC2", "#2A9D8F", "#D1495B"]
const CRATE_SIZE: float = 44
const CRATE_TEXTURE = preload("res://arrow/texture/crate.png")
class ExitPathResult:
	var can_exit: bool
	var exit_path: Array[PackedInt32Array]
	# idx arrow bi dam vao khi khong thoat duoc, -1 neu thoat duoc hoac bi Crate chan
	var blocked_idx: int = -1
	# cell index cua Crate chan duong, -1 neu khong co
	var blocked_crate: int = -1
func _ready() -> void:
	next_level()
	Global.game_event.game_start.connect(func():
		next_level())
	Global.game_event.game_restart.connect(func():
		restart())
	Global.game_event.user_action.connect(_on_user_action)
	Global.game_event.game_continue.connect(_on_game_continue)
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
		# Hidden chua lo huong, ruler khong duoc tiet lo
		if arrows[i].is_exit or hidden_n.has(i):
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
	bomb_pending = -1
	Global.game_data.bomb_exploded.value = false
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
	load_obstacles()
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
	# Uu tien Bomb sap no nhat neu thoat duoc
	var bombs := bomb_n.keys()
	bombs.sort_custom(func(a, b): return bomb_n[a] < bomb_n[b])
	for i in bombs:
		if is_arrow_active(i) and calculate_exit_path(level[i]).can_exit:
			return i
	for i in range(level.size()):
		if arrows[i].is_exit or !is_arrow_active(i):
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
		if is_finish:
			break
		for i in range(level.size()):
			if arrows[i].is_exit or !is_arrow_active(i):
				continue
			var exit_path = calculate_exit_path(level[i])
			if exit_path.can_exit:
				await move_camera_to_arrow(i)
				arrows[i].active_highlight()
				await get_tree().create_timer(1).timeout
				arrows[i].exit(exit_path)
				remove_arrow(i)
				_on_arrow_cleared(i)
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
		_on_arrow_cleared(idx)
		check_end_game()
		return
	if is_finish:
		return
	# Frozen/Locked/Hidden: phan hoi trung tinh, khong mat live
	if !is_arrow_active(idx):
		arrows[idx].neutral_feedback()
		Global.firebase_manager.log_event("arrow_tap", {"level_id": Global.game_data.level.value, "row_id": idx, "result": "inactive"})
		return
	var rs = calculate_exit_path(level[idx])
	if rs.can_exit:
		remove_arrow(idx)
		if Global.game_data.remain_lines.value == level.size():
			Global.game_event.user_action.emit(GameEnum.UserAction.ResolveArrow, {})
		Global.game_data.remain_lines.value -= 1
		_on_arrow_cleared(idx)
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
	if rs.blocked_crate >= 0:
		_shake_crate(rs.blocked_crate)
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
				if _is_blocked_cell(idx, result):
					break
		Utils.Direction.Down:
			for i in range(head[1]+1, head[1] + out):
				var next_pos = [head[0], i]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if _is_blocked_cell(idx, result):
					break
		Utils.Direction.Left:
			for i in range(head[0]-1, head[0] - out, -1):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if _is_blocked_cell(idx, result):
					break
		Utils.Direction.Right:
			for i in range(head[0]+1, head[0] + out):
				var next_pos = [i, head[1]]
				var idx = Utils.to_index(next_pos)
				exit_path.append(next_pos)
				if _is_blocked_cell(idx, result):
					break
	result.exit_path = exit_path
	return result
## Blocker tren exit ray: Arrow hoac Crate.
func _is_blocked_cell(cell: int, result: ExitPathResult) -> bool:
	if used_cells.has(cell):
		result.can_exit = false
		result.blocked_idx = used_cells[cell]
		return true
	if crates.has(cell):
		result.can_exit = false
		result.blocked_crate = cell
		return true
	return false
func next_level()->void:
	Global.popup_manager.show_loading()
	if Global.game_data.current_challenge.value.size():
		set_level_data(await Global.api.get_challenge_by_date(
			Global.game_data.current_challenge.value[0],
			Global.game_data.current_challenge.value[1],
			Global.game_data.current_challenge.value[2]))
	else:
		set_level_data(await Global.api.get_level(Global.game_data.level.value))
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
func set_level_data(data) -> void:
	level = data.points if data else null
	level_obstacles = data.get("obstacles", {}) if data else {}
# ----------------------------------------------------------------
# Obstacle (GDD sheet 01/04)
# ----------------------------------------------------------------
## Nap trang thai obstacle tu level_obstacles. Arrow la idx trong points, Crate la o [x, y].
func load_obstacles() -> void:
	frozen_n.clear()
	hidden_n.clear()
	bomb_n.clear()
	locked_group.clear()
	key_group.clear()
	crates.clear()
	for o in level_obstacles.get("frozen", []):
		frozen_n[int(o.arrow)] = int(o.n)
	for o in level_obstacles.get("hidden", []):
		hidden_n[int(o.arrow)] = int(o.n)
	for o in level_obstacles.get("bomb", []):
		bomb_n[int(o.arrow)] = int(o.n)
	for g in level_obstacles.get("lock", []):
		key_group[int(g.key)] = int(g.group)
		for a in g.locked:
			locked_group[int(a)] = int(g.group)
		# Key va Locked cung group dung chung mau group de nguoi choi nhan ra
		for a in [g.key] + g.locked:
			arrows[int(a)].set_color(LOCK_COLORS[int(g.group) % LOCK_COLORS.size()])
	for o in level_obstacles.get("crate", []):
		var cell: Array = [int(o.x), int(o.y)]
		crates[Utils.to_index(cell)] = {"n": int(o.n), "node": _make_crate(cell, int(o.n))}
	_refresh_obstacles()
## Arrow co the tap de thoat (khong Frozen/Locked/Hidden).
func is_arrow_active(idx: int) -> bool:
	return !frozen_n.has(idx) and !locked_group.has(idx) and !hidden_n.has(idx)
## OnArrowCleared theo thu tu GDD: (occupancy da xoa) -> defuse Bomb -> Key -> progress -> Bomb countdown.
## Goi cho moi lan xoa hop le: tap thoat, Eraser, Magic Glasses.
func _on_arrow_cleared(idx: int) -> void:
	bomb_n.erase(idx)
	if key_group.has(idx):
		var group = key_group[idx]
		key_group.erase(idx)
		for a in locked_group.keys():
			if locked_group[a] == group:
				locked_group.erase(a)
	frozen_n.erase(idx)
	hidden_n.erase(idx)
	locked_group.erase(idx)
	for a in frozen_n.keys():
		frozen_n[a] -= 1
		if frozen_n[a] <= 0:
			frozen_n.erase(a)
	for a in hidden_n.keys():
		hidden_n[a] -= 1
		if hidden_n[a] <= 0:
			hidden_n.erase(a)
	for c in crates.keys():
		crates[c]["n"] -= 1
		if crates[c]["n"] <= 0:
			_break_crate(c)
		else:
			crates[c].node.get_child(1).text = str(crates[c]["n"])
	var exploded := -1
	for b in bomb_n.keys():
		bomb_n[b] -= 1
		if bomb_n[b] <= 0 and exploded < 0:
			exploded = b
	_refresh_obstacles()
	if exploded >= 0:
		_explode_bomb(exploded)
func _refresh_obstacles() -> void:
	for i in range(arrows.size()):
		if arrows[i].is_exit:
			continue
		if hidden_n.has(i):
			arrows[i].set_obstacle("? %d" % hidden_n[i], Color("#555555"), Color(0.55, 0.55, 0.55), true)
		elif frozen_n.has(i):
			arrows[i].set_obstacle("%d" % frozen_n[i], Color("#3C8DDB"), Color.WHITE, false)
		elif locked_group.has(i):
			arrows[i].set_obstacle("LOCK", Color(LOCK_COLORS[locked_group[i] % LOCK_COLORS.size()]), Color.WHITE, false)
		elif bomb_n.has(i):
			arrows[i].set_obstacle("%d" % bomb_n[i], Color("#222222") if bomb_n[i] > 3 else Color("#E8202A"), Color.WHITE, false)
		elif key_group.has(i):
			arrows[i].set_obstacle("KEY", Color(LOCK_COLORS[key_group[i] % LOCK_COLORS.size()]), Color.WHITE, false)
		else:
			arrows[i].set_obstacle("", Color.WHITE, Color.WHITE, false)
		var pattern := ""
		if frozen_n.has(i):
			pattern = "frozen"
		elif locked_group.has(i):
			pattern = "lock"
		elif bomb_n.has(i):
			pattern = "bomb"
		elif key_group.has(i):
			pattern = "key"
		arrows[i].set_body_pattern(pattern)
func _explode_bomb(idx: int) -> void:
	is_finish = true
	bomb_pending = idx
	Global.game_data.bomb_exploded.value = true
	arrows[idx].shake(Vector2.UP)
	Global.firebase_manager.log_event("level_fail", {
			"level_id": Global.game_data.level.value,
			"active_duration_ms": Time.get_unix_time_from_system() * 1000- start_time,
			"tap_count": tap_count,
			"blocked_tap_count": blocked_tap_count,
			"reason":"bomb"
		})
	await get_tree().create_timer(1).timeout
	Global.game_event.request_visible_popup.emit(GameEnum.PopupType.OutOfLive, true)
## Continue tu popup fail: Bomb chi mat trang thai Bomb, arrow van o tren ban.
func _on_game_continue() -> void:
	if bomb_pending >= 0:
		bomb_n.erase(bomb_pending)
		bomb_pending = -1
		Global.game_data.bomb_exploded.value = false
		_refresh_obstacles()
	is_finish = false
	check_end_game()
func _make_crate(cell: Array, n: int) -> Node2D:
	var node := Node2D.new()
	node.position = Utils.to_pos(cell)
	node.z_index = 5
	var h := CRATE_SIZE / 2
	var box := Sprite2D.new()
	box.texture = CRATE_TEXTURE
	box.scale = Vector2.ONE * CRATE_SIZE / CRATE_TEXTURE.get_width()
	box.modulate = Color("#9C6B3C")
	node.add_child(box)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(CRATE_SIZE, CRATE_SIZE)
	label.position = Vector2(-h, -h)
	label.text = str(n)
	node.add_child(label)
	line_container.add_child(node)
	return node
func _shake_crate(cell: int) -> void:
	var node: Node2D = crates[cell].node
	var base := node.position
	var tw := create_tween()
	for a in [6.0, -4.0, 2.0, 0.0]:
		tw.tween_property(node, "position", base + Vector2(a, 0), 0.05)
func _break_crate(cell: int) -> void:
	var node: Node2D = crates[cell].node
	crates.erase(cell)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ZERO, 0.2)
	tw.tween_callback(node.queue_free)
