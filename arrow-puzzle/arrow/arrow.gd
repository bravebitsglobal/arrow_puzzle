extends Node2D
class_name Arrow
var COLORS = ["#FF2A4B","#E60039","#FF3366","#FF4081","#FF007F","#FF5252","#D81B60","#FF6D00","#FF8800","#FF5722","#FF9100","#F57C00","#FF7043","#E65100","#FFC400","#FFB300","#FFD600","#FFCA28","#FFA000","#FBC02D","#76FF03","#00E676","#00C853","#4CAF50","#AEEA00","#1DE9B6","#2E7D32","#00B0FF","#00E5FF","#2979FF","#2962FF","#1E88E5","#00BFA5","#0D47A1","#AA00FF","#651FFF","#3D5AFE","#D500F9","#8E24AA","#4A148C","#795548","#A1887F","#5D4037","#D84315","#78909C","#455A64","#263238","#1A1A2E","#212121","#0F0F1A"]
@export var PATTERNS: Array[Texture2D] = []
@onready var head: Node2D = $Head
const ROTATES = [0, 180, -90, 90]
const CELL_SIZE = 50
var data: Array[PackedInt32Array]
@onready var line_2d: Line2D = $Line2D
@onready var collision_polygon_2d: CollisionPolygon2D = $Area2D/CollisionPolygon2D
@onready var highlight: Line2D = $Highlight
@onready var highlight_animation_player: AnimationPlayer = $HighlightAnimationPlayer
@onready var ruler: Line2D = $Ruler

@onready var area_2d: Area2D = $Area2D
@onready var joints_container: Node2D = $Joints
var joint_material: ShaderMaterial
enum Action{
	Idle,
	GoingIn,
	GoingOut,
	Exited
}
var action: Action = Action.Idle
var tween: Tween
const SPEED: float = 1000
const GO_IN_SPEED: float = 300
var exit_path: Array[PackedInt32Array]
var tail_progress: float = 0
var head_progress: float = 0
signal on_click
var is_exit: bool = false
var _mouse_pressed_pos: Vector2 = Vector2.ZERO
var _is_mouse_pressed: bool = false
const CLICK_THRESHOLD: float = 5.0  # Nguong phan biet click va drag (pixels)
var highlight_tween: Tween
const HIGHLIGHT_TIME = 3
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Load joint overlay material
	joint_material = load("res://arrow/joint_overlay_material.tres")
	render()
func update_line_collision() -> void:
	if line_2d.points.size() < 2:
		return
	var polygons = Geometry2D.offset_polyline(line_2d.points, 20)
	if polygons.size() > 0:
		collision_polygon_2d.polygon = polygons[0]
	area_2d.input_event.connect(_on_area_2d_input_event)
func _on_area_2d_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Luu vi tri nhan chuot
			_mouse_pressed_pos = event.position
			_is_mouse_pressed = true
		elif _is_mouse_pressed:
			# Tha chuot - kiem tra co phai click khong
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
func exit(result: Game.ExitPathResult):
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
func render():
	if !data:
		return
	if !is_node_ready():
		return
	var head_pos = data[data.size()-1]
	head.position = Utils.to_pos(head_pos)
	head.visible = true
	#head.rotation_degrees = ROTATES[Utils.get_exit_dir(data)]
	go_in()
func update_line():
	# Vị trí đuôi/đầu tính theo chỉ số (thực) trên exit_path.
	var tail_index: float = tail_progress / CELL_SIZE
	var head_index: float = head_progress / CELL_SIZE - 1
	line_2d.points = _build_points(tail_index, head_index, line_2d.width / 2)
	highlight.points = _build_points(tail_index, head_index, highlight.width / 2)
	# Đầu đi theo vị trí thật, không theo điểm cuối của line (điểm này có thể bị bỏ ở góc).
	head.position = _path_pos(head_index)
	# Cập nhật joint overlays
	_update_joint_overlays()

func _path_pos(index: float) -> Vector2:
	var i: int = clampi(floori(index), 0, exit_path.size() - 1)
	var next: int = mini(i + 1, exit_path.size() - 1)
	return Utils.to_pos(exit_path[i]).lerp(Utils.to_pos(exit_path[next]), index - i)

# Dựng toàn bộ điểm của thân: đuôi nội suy, các ô lưới nằm giữa, đầu nội suy.
# Line2D chỉ bo tròn được khớp khi 2 đoạn kề khớp đều dài >= nửa độ dày (half_width),
# nên ở khớp có rẽ, đoạn đuôi/đầu ngắn hơn half_width bị bỏ (nắp tròn che phần thiếu).
func _build_points(tail_index: float, head_index: float, half_width: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var tail_pos := _path_pos(tail_index)
	var head_pos := _path_pos(head_index)
	var corners := PackedVector2Array()
	for i in range(floori(tail_index) + 1, ceili(head_index)):
		corners.append(Utils.to_pos(exit_path[i]))
	if corners.is_empty():
		pts.append(tail_pos)
		if head_pos.distance_to(tail_pos) > 0.5:
			pts.append(head_pos)
		return pts
	var last := corners.size() - 1
	var after_first: Vector2 = corners[1] if last > 0 else head_pos
	var before_last: Vector2 = corners[last - 1] if last > 0 else tail_pos
	if !_should_drop_end(tail_pos, corners[0], after_first, half_width):
		pts.append(tail_pos)
	pts.append_array(corners)
	if !_should_drop_end(head_pos, corners[last], before_last, half_width):
		pts.append(head_pos)
	return pts

# Bỏ đầu mút end_pos (nối vào khớp corner, phía bên kia khớp là other) khi đoạn quá ngắn:
# luôn bỏ nếu gần như trùng; ngắn hơn half_width thì chỉ bỏ khi tại khớp có rẽ.
func _should_drop_end(end_pos: Vector2, corner: Vector2, other: Vector2, half_width: float) -> bool:
	var length := end_pos.distance_to(corner)
	if length < 0.5:
		return true
	if length >= half_width:
		return false
	var d1 := (corner - end_pos).normalized()
	var d2 := (other - corner).normalized()
	return absf(d1.cross(d2)) > 0.01
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
func set_ruler(exit_rs: Game.ExitPathResult)->void:
	ruler.visible = true
	for i in range(data.size(), exit_rs.exit_path.size()):
		ruler.add_point(Utils.to_pos(exit_rs.exit_path[i]))

# Cập nhật joint overlays tại các vị trí khớp của line2d
func _update_joint_overlays() -> void:
	# Xóa các joint cũ
	if joints_container:
		for child in joints_container.get_children():
			child.queue_free()
	else:
		# Tạo container nếu chưa có
		joints_container = Node2D.new()
		joints_container.name = "Joints"
		add_child(joints_container)

	# Tìm các vị trí khớp trong line2d
	var points = line_2d.points
	if points.size() < 3:
		return

	# Tính scale dựa trên độ rộng của line2d
	# Ảnh có kích thước 247x247, line2d có width = 40
	var image_size = 247.0
	var target_size = line_2d.width
	var scale_factor = target_size / image_size

	# Duyệt qua các điểm trung gian (bỏ qua đầu và cuối)
	for i in range(1, points.size() - 1):
		var prev_point = points[i - 1]
		var current_point = points[i]
		var next_point = points[i + 1]

		# Tính vector hướng
		var dir_in = (current_point - prev_point).normalized()
		var dir_out = (next_point - current_point).normalized()

		# Kiểm tra xem có phải là khớp không (góc rẽ)
		var cross_product = dir_in.cross(dir_out)
		if abs(cross_product) > 0.01:  # Có rẽ góc
			# Tạo sprite overlay tại khớp
			var joint_sprite = Sprite2D.new()

			# Cần set texture trước khi set material để shader có texture để xử lý
			# Dùng texture trắng dummy hoặc alpha.png làm base texture
			joint_sprite.texture = load("res://arrow/alpha.png")

			joint_sprite.material = joint_material.duplicate() if joint_material else null
			joint_sprite.position = current_point
			joint_sprite.scale = Vector2(scale_factor, scale_factor)

			# Tính góc xoay dựa trên hướng vào và ra
			var rotation_angle = _calculate_joint_rotation(dir_in, dir_out)
			if joint_sprite.material:
				joint_sprite.material.set_shader_parameter("rotation_angle", rotation_angle)

			joints_container.add_child(joint_sprite)

# Tính góc xoay cho joint overlay dựa trên hướng vào và ra
func _calculate_joint_rotation(dir_in: Vector2, dir_out: Vector2) -> float:
	# Xác định hướng của khớp dựa trên vector vào và ra
	# Góc chuẩn (0) là khớp hướng L (từ trái sang phải, rẽ xuống)

	# Chuẩn hóa hướng thành 4 hướng chính (0, 90, 180, 270 độ)
	var angle_in = _vector_to_cardinal_angle(dir_in)
	var angle_out = _vector_to_cardinal_angle(dir_out)

	# Tính góc xoay dựa trên tổ hợp hướng vào/ra
	# Khớp chữ L có thể có 4 hướng:
	# 0°: từ trái (180°) rẽ xuống (270°)
	# 90°: từ trên (90°) rẽ phải (0°)
	# 180°: từ phải (0°) rẽ lên (90°)
	# 270°: từ dưới (270°) rẽ trái (180°)

	if angle_in == 180 and angle_out == 270:  # Trái -> Xuống
		return 0.0
	elif angle_in == 90 and angle_out == 0:  # Trên -> Phải
		return PI / 2.0
	elif angle_in == 0 and angle_out == 90:  # Phải -> Lên
		return PI
	elif angle_in == 270 and angle_out == 180:  # Dưới -> Trái
		return 3.0 * PI / 2.0
	elif angle_in == 270 and angle_out == 0:  # Xuống -> Phải
		return 0.0
	elif angle_in == 180 and angle_out == 90:  # Trái -> Lên
		return PI / 2.0
	elif angle_in == 0 and angle_out == 270:  # Phải -> Xuống
		return PI
	elif angle_in == 90 and angle_out == 180:  # Trên -> Trái
		return 3.0 * PI / 2.0

	return 0.0

# Chuyển vector thành góc theo 4 hướng chính (0, 90, 180, 270 độ)
func _vector_to_cardinal_angle(vec: Vector2) -> int:
	var angle_rad = vec.angle()
	var angle_deg = rad_to_deg(angle_rad)

	# Chuẩn hóa về [0, 360)
	if angle_deg < 0:
		angle_deg += 360

	# Làm tròn về 4 hướng chính
	if angle_deg >= 315 or angle_deg < 45:
		return 0  # Phải
	elif angle_deg >= 45 and angle_deg < 135:
		return 90  # Lên
	elif angle_deg >= 135 and angle_deg < 225:
		return 180  # Trái
	else:
		return 270  # Xuống
