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
@onready var area_2d: Area2D = $Area2D
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

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
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
	exit_path = result.exit_path
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
		else:
			action = Action.Idle
		)
func render():
	if !data:
		return
	if !is_node_ready():
		return
	for i in data:
		line_2d.add_point(Vector2(0,0))
	var head_pos = data[data.size()-1]
	head.position = Utils.to_pos(head_pos)
	head.visible = true
	go_in()
func update_line():
	var start: int = floor(tail_progress / CELL_SIZE)
	var end:int = floor(head_progress / CELL_SIZE) - 1
	var tail_weight = float((int(tail_progress) % CELL_SIZE) / float(CELL_SIZE))
	line_2d.set_point_position(0, Utils.to_pos(exit_path[start]).lerp(Utils.to_pos(exit_path[start+1]), tail_weight))
	for i in range(start+1, start + data.size()):
		if i > exit_path.size() - 1:
			break
		var e = exit_path[i]
		if e[0] > Utils.grid_width || e[1] > Utils.grid_width:
			break
		var pos: Vector2
		if i > end:
			pos = line_2d.points[i-start-1]
		else:
			pos = Utils.to_pos(exit_path[i])
		line_2d.set_point_position(i - start, pos)
	if end < exit_path.size() - 1:
		var head_weight = float((int(head_progress) % CELL_SIZE) / float(CELL_SIZE))
		line_2d.set_point_position(data.size()-1, Utils.to_pos(exit_path[end]).lerp(Utils.to_pos(exit_path[end+1]),head_weight))
	else:
		line_2d.set_point_position(data.size()-1, Utils.to_pos(exit_path[end]))
	head.position = line_2d.points[line_2d.points.size()-1]
	if start > data.size() && !is_exit:
		is_exit = true
func _physics_process(_delta: float) -> void:
	if action != Action.Idle:
		update_line()
