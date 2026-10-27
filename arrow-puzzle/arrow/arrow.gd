extends Node2D
class_name Arrow
# 7 màu đậm, bão hòa cao để nổi trên nền sáng #edebfe (tương phản >= ~3:1).
var COLORS = [
	"#E8202A", # đỏ
	"#F05A00", # cam
	"#0E9A3E", # xanh lá
	"#008C99", # xanh ngọc
	"#1F5FFF", # xanh dương
	"#8E2BD9", # tím
	"#E8197F", # hồng
]
@onready var head_down: Sprite2D = $Head/Down
@onready var head_left: Sprite2D = $Head/Left
@onready var head_right: Sprite2D = $Head/Right
enum Face{
	Open,
	Close,
	Stun
}
# Right dung chung anh voi Left (sprite Right da flip_h trong scene)
# TODO: arrow/head/head-left-open.png dang 1254px nen trang, tam dung texture/2.png (cung hinh, 256px trong suot)
const HEAD_DOWN_TEXTURES = {
	Face.Open: preload("res://arrow/head/head-down-open.png"),
	Face.Close: preload("res://arrow/head/head-down-close.png"),
	Face.Stun: preload("res://arrow/head/head-down-stun.png"),
}
const HEAD_SIDE_TEXTURES = {
	Face.Open: preload("res://arrow/texture/2.png"),
	Face.Close: preload("res://arrow/head/head-left-close.png"),
	Face.Stun: preload("res://arrow/head/head-left-stun.png"),
}
const STUN_TIME: float = 3
var is_stunned: bool = false
# Tang moi lan bi stun, de timer cua lan stun cu khong ket thuc stun moi
var _stun_id: int = 0

@export var PATTERNS: Array[Texture2D] = []
const ROTATES = [0, 180, -90, 90]
const CELL_SIZE = 50
const RULER_MAX_CELLS = 10
var data: Array[PackedInt32Array]
@onready var head: Node2D = $Head
@onready var foot_1: Node2D = $Foot1
@onready var foot_2: Node2D = $Foot2

@onready var line_2d: Line2D = $Line2D
@onready var collision_polygon_2d: CollisionPolygon2D = $Area2D/CollisionPolygon2D
@onready var highlight: Line2D = $Highlight
@onready var highlight_animation_player: AnimationPlayer = $HighlightAnimationPlayer
@onready var ruler: Line2D = $Ruler
@onready var tail: Node2D = $Tail

@onready var area_2d: Area2D = $Area2D
var joint_material: ShaderMaterial
const JOINT_BASE_BISECTOR := Vector2(1, -1)
const MAX_JOINTS = 64 # phải bằng MAX_JOINTS trong joint_overlay.gdshader
enum Action{
	Idle,
	GoingIn,
	GoingOut,
	Exited
}
var action: Action = Action.Idle
var tween: Tween
var shake_tween: Tween
const SHAKE_AMPLITUDE: float = 8
const SHAKE_STEP_TIME: float = 0.05
const SPEED: float = 1500
const GO_IN_SPEED: float = 1000
var exit_path: Array[PackedInt32Array]
var tail_progress: float = 0
var head_progress: float = 0
signal on_click
var is_exit: bool = false
var _mouse_pressed_pos: Vector2 = Vector2.ZERO
var _is_mouse_pressed: bool = false
const CLICK_THRESHOLD: float = 5.0  # Nguong phan biet click va drag (pixels)
var highlight_tween: Tween
const HIGHLIGHT_TIME = 10
var enable: bool = true
@export var min_blink_interval: float = 2.0  # Tối thiểu 2 giây chớp 1 lần
@export var max_blink_interval: float = 6.0  # Tối đa 6 giây chớp 1 lần
# Thời gian nhắm mắt (chớp cực nhanh)
@export var blink_duration: float = 0.12     # Khoảng 0.12 giây
@onready var blink_timer: Timer = $BlinkTimer
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	blink_timer.timeout.connect(_on_blink_timer_timeout)
	set_random_color()
	render()
	schedule_next_blink()
func update_line_collision() -> void:
	if line_2d.points.size() < 2:
		return
	var polygons = Geometry2D.offset_polyline(line_2d.points, 20)
	if polygons.size() > 0:
		collision_polygon_2d.polygon = polygons[0]
	if !area_2d.input_event.is_connected(_on_area_2d_input_event):
		area_2d.input_event.connect(_on_area_2d_input_event)
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if !enable:
		return
	var is_mouse_left = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	# Touch tren mobile
	var is_touch = event is InputEventScreenTouch and event.index == 0
	if !is_mouse_left and !is_touch:
		return
	if event.pressed:
		# Luu vi tri nhan
		_mouse_pressed_pos = event.position
		_is_mouse_pressed = true
	elif _is_mouse_pressed:
		# Tha ra - kiem tra co phai click khong.
		# Dung chung co _is_mouse_pressed nen neu ca mouse va touch gia lap cung toi thi chi emit 1 lan.
		var distance = event.position.distance_to(_mouse_pressed_pos)
		if distance < CLICK_THRESHOLD and action == Action.Idle:
			on_click.emit()
		_is_mouse_pressed = false
func set_data(_data: Array[PackedInt32Array]):
	data = _data
	render()
func is_going_out():
	return tween && tween.is_running() && action==Action.GoingOut
func go_in():
	exit_path = data
	tail_progress = 0
	head_progress = CELL_SIZE
	action = Action.GoingIn
	var arrow_size = data.size() * CELL_SIZE
	var dur = float(arrow_size) / GO_IN_SPEED
	if tween:
		tween.kill()
	tween = create_tween()
	tween.tween_property(self, 'head_progress', arrow_size, dur)
	tween.finished.connect(func():
		update_line()
		action = Action.Idle
		update_line_collision()
		)
func exit(result: Game.ExitPathResult, blocked_arrow: Arrow = null):
	if result.can_exit:
		ruler.visible = false
	exit_path = result.exit_path
	is_exit = result.can_exit
	var arrow_size = data.size() * CELL_SIZE
	tail_progress = 0
	head_progress = arrow_size
	action = Action.GoingOut
	if tween:
		tween.kill()
	tween = create_tween()
	var move_distance = (exit_path.size() - data.size()) * CELL_SIZE
	var dur = float(move_distance) / SPEED
	tween.tween_property(self, 'tail_progress', move_distance, dur)
	tween.parallel().tween_property(self, 'head_progress', move_distance + arrow_size, dur)
	if !result.can_exit:
		set_stun()
		if blocked_arrow:
			var hit_dir := Utils.to_pos(exit_path[exit_path.size() - 1]) - Utils.to_pos(exit_path[exit_path.size() - 2])
			tween.tween_callback(blocked_arrow.shake.bind(hit_dir.normalized()))
		tween.tween_property(self, 'tail_progress', 0, dur)
		tween.parallel().tween_property(self, 'head_progress', arrow_size, dur)
	tween.finished.connect(func():
		update_line()
		if result.can_exit:
			action = Action.Exited
			self.visible = false
		else:
			action = Action.Idle
		)
## Rung theo huong bi dam: day lui theo dir roi dao dong tat dan ve vi tri cu.
func shake(dir: Vector2) -> void:
	if shake_tween:
		shake_tween.kill()
	position = Vector2.ZERO
	shake_tween = create_tween()
	var amps := [SHAKE_AMPLITUDE, -SHAKE_AMPLITUDE * 0.6, SHAKE_AMPLITUDE * 0.35, -SHAKE_AMPLITUDE * 0.15]
	for a in amps:
		shake_tween.tween_property(self, 'position', dir * a, SHAKE_STEP_TIME).set_trans(Tween.TRANS_SINE)
	shake_tween.tween_property(self, 'position', Vector2.ZERO, SHAKE_STEP_TIME).set_trans(Tween.TRANS_SINE)
func set_face(face: Face) -> void:
	head_down.texture = HEAD_DOWN_TEXTURES[face]
	head_left.texture = HEAD_SIDE_TEXTURES[face]
	head_right.texture = HEAD_SIDE_TEXTURES[face]
func set_stun() -> void:
	is_stunned = true
	_stun_id += 1
	var id := _stun_id
	set_face(Face.Stun)
	await get_tree().create_timer(STUN_TIME).timeout
	if id != _stun_id:
		return
	is_stunned = false
	set_face(Face.Open)
func render():
	if !data:
		return
	if !is_node_ready():
		return
	var head_pos = data[data.size()-1]
	head.position = Utils.to_pos(head_pos)
	head.visible = true
	tail.visible = true
	tail.position = Utils.to_pos(data[0])
	var tail_dir = Utils.get_dir(data[1], data[0])
	tail.rotation_degrees = ROTATES[tail_dir]
	var head_dir = Utils.get_exit_dir(data)
	#head.rotation_degrees = ROTATES[Utils.get_exit_dir(data)]
	head.get_child(head_dir).visible = true
	go_in()
func update_line():
	# Vị trí đuôi/đầu tính theo chỉ số (thực) trên exit_path.
	var tail_index: float = tail_progress / CELL_SIZE
	var head_index: float = head_progress / CELL_SIZE - 1
	line_2d.points = _build_points(tail_index, head_index)
	highlight.points = line_2d.points
	head.position = _path_pos(head_index)
	_update_tail()
	update_foot()
func _update_tail()->void:
	if line_2d.points.size()<2:
		return
	tail.position = line_2d.points[0]
	tail.rotation_degrees = ROTATES[Utils.get_dir([line_2d.points[1].x, line_2d.points[1].y], [line_2d.points[0].x,line_2d.points[0].y])]
func _path_pos(index: float) -> Vector2:
	var i: int = clampi(floori(index), 0, exit_path.size() - 1)
	var next: int = mini(i + 1, exit_path.size() - 1)
	return Utils.to_pos(exit_path[i]).lerp(Utils.to_pos(exit_path[next]), index - i)
# Dựng toàn bộ điểm của thân: đuôi nội suy, các ô lưới nằm giữa, đầu nội suy.
# Đuôi/đầu luôn được giữ (kể cả sát khớp) để thân trượt mượt; khớp do shader mask xử lý.
# Chỉ bỏ điểm gần như trùng với điểm kề (đoạn dài 0 làm Line2D tính sai hướng).
func _build_points(tail_index: float, head_index: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(_path_pos(tail_index))
	for i in range(floori(tail_index) + 1, ceili(head_index)):
		_append_distinct(pts, Utils.to_pos(exit_path[i]))
	_append_distinct(pts, _path_pos(head_index))
	return pts
func _append_distinct(pts: PackedVector2Array, p: Vector2) -> void:
	if pts[pts.size() - 1].distance_to(p) > 0.5:
		pts.append(p)
func _physics_process(_delta: float) -> void:
	if action != Action.Idle:
		update_line()
func active_highlight()->void:
	highlight.visible = true
	highlight_animation_player.play("highlight")
	await get_tree().create_timer(HIGHLIGHT_TIME).timeout
	highlight.visible = false
func erase()->void:
	is_exit = true
	self.visible = false
func set_ruler()->void:
	ruler.clear_points()
	ruler.visible = true
	# Ke thang tu dau arrow theo huong thoat RULER_MAX_CELLS o, khong dung lai khi cham arrow khac
	var head_pos := Utils.to_pos(data[data.size() - 1])
	var dir := head_pos - Utils.to_pos(data[data.size() - 2])
	for i in range(RULER_MAX_CELLS + 1):
		ruler.add_point(head_pos + dir * i)
func clear_ruler()->void:
	ruler.visible = false
	ruler.clear_points()
## Đổi màu cả arrow (thân, đầu, đuôi). Nhận Color hoặc chuỗi hex như trong COLORS.
func set_color(color: Variant) -> void:
	var c: Color = Color(color) if color is String else color
	(material as ShaderMaterial).set_shader_parameter("target_color", c)
func set_random_color() -> void:
	set_color(COLORS.pick_random())
func set_enable(is_enable)->void:
	enable = is_enable
	if enable:
		modulate = Color(1,1,1,1)
	else:
		modulate = Color(0,0,0,0.2)
func schedule_next_blink() -> void:
	# Chọn ngẫu nhiên thời gian cho lần chớp mắt tiếp theo
	var random_time = randf_range(min_blink_interval, max_blink_interval)
	blink_timer.start(random_time)
func _on_blink_timer_timeout() -> void:
	# Thực hiện chớp mắt
	blink_eye()
func blink_eye() -> void:
	if !is_stunned:
		set_face(Face.Close)
		await get_tree().create_timer(blink_duration).timeout
		if !is_stunned:
			set_face(Face.Open)
	schedule_next_blink()
func get_dir(index: float)->int:
	var i = exit_path[floor(index)]
	var next = exit_path[floor(index)+1]
	var dir = Utils.get_dir(i, next)
	return dir
func update_foot()->void:
	var head_index: float = head_progress / CELL_SIZE
	var total = line_2d.points.size()
	foot_1.position = _path_pos(head_index - 2)
	foot_1.rotation_degrees = ROTATES[get_dir(head_index - 2)]
	if total >= 3:
		foot_2.position = _path_pos(head_index - 3)
		foot_2.rotation_degrees = ROTATES[get_dir(head_index - 3)]
	else:
		foot_2.visible = false
