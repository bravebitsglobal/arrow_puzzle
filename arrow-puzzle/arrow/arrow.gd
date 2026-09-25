extends Node2D
class_name Arrow
var COLORS = ["#FF2A4B","#E60039","#FF3366","#FF4081","#FF007F","#FF5252","#D81B60","#FF6D00","#FF8800","#FF5722","#FF9100","#F57C00","#FF7043","#E65100","#FFC400","#FFB300","#FFD600","#FFCA28","#FFA000","#FBC02D","#76FF03","#00E676","#00C853","#4CAF50","#AEEA00","#1DE9B6","#2E7D32","#00B0FF","#00E5FF","#2979FF","#2962FF","#1E88E5","#00BFA5","#0D47A1","#AA00FF","#651FFF","#3D5AFE","#D500F9","#8E24AA","#4A148C","#795548","#A1887F","#5D4037","#D84315","#78909C","#455A64","#263238","#1A1A2E","#212121","#0F0F1A"]
@export var PATTERNS: Array[Texture2D] = []
@onready var head: Node2D = $Head
const ROTATES = [0, 180, -90, 90]
const CELL_SIZE = 50
var data
@onready var line_2d: Line2D = $Line2D
@onready var collision_polygon_2d: CollisionPolygon2D = $Area2D/CollisionPolygon2D
@onready var area_2d: Area2D = $Area2D
var tween: Tween
const SPEED = 10
var exit_path: PackedInt32Array
var move_progress: float = 0
var moving: bool = false
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
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		moving = true
		if !tween:
			tween = create_tween()
		tween.tween_property(self, 'move_progress', exit_path.size() * CELL_SIZE, 3)
		tween.finished.connect(func():
			moving = false)
		tween.tween_callback(update_line)
func set_data(_data):
	data = _data
	render()
func render():
	if !data:
		return
	var pos: Vector2i = Vector2.ZERO
	for i in range(data.cells.size()):
		var c = data.cells[i]
		pos = Utils.to_xy(c)
		var point = Utils.index_to_pos(c)
		var path_follow = PathFollow2D.new()
		path_follow.progress = i * CELL_SIZE
		line_2d.add_point(point)
	head.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	head.rotation_degrees = ROTATES[data.exit_dir]
	head.visible = true
	calculate_exit_path()
	update_line_collision()
func calculate_exit_path():
	exit_path = data.cells.duplicate()
	var head_index = data.cells[data.cells.size()-1]
	var head_pos = Utils.to_xy(head_index)
	match(data.exit_dir):
		0:
			for i in range(head_pos.y-1, 0, -1):
				exit_path.append(Utils.to_index(Vector2(head_pos.x, i)))
		1:
			for i in range(head_pos.y+1, Utils.grid_width):
				exit_path.append(Utils.to_index(Vector2(head_pos.x, i)))
		2:
			for i in range(head_pos.x-1, 0, -1):
				exit_path.append(Utils.to_index(Vector2(i, head_pos.y)))
		3:
			for i in range(head_pos.x+1, Utils.grid_width):
				exit_path.append(Utils.to_index(Vector2(i, head_pos.y)))
func update_line():
	if !moving:
		return
	var start = int(move_progress / CELL_SIZE)
	var end = start + data.cells.size()-1
	
	if end >= exit_path.size()-2:
		return
	var weight = float((int(move_progress) % CELL_SIZE) / float(CELL_SIZE))
	line_2d.set_point_position(0, Utils.index_to_pos(exit_path[start]).lerp(Utils.index_to_pos(exit_path[start+1]),weight))
	line_2d.set_point_position(data.cells.size()-1, Utils.index_to_pos(exit_path[end]).lerp(Utils.index_to_pos(exit_path[end+1]),weight))
	for i in range(start+1, start + data.cells.size()-1):
		if i > exit_path.size()-1:
			return
		var xy = Utils.to_xy(exit_path[i])
		if xy.x > Utils.grid_width || xy.y > Utils.grid_width:
			return
		var pos = Vector2(xy.x * CELL_SIZE, xy.y * CELL_SIZE)
		line_2d.set_point_position(i - start, pos)
	head.position = line_2d.points[line_2d.points.size()-1]
	
func _process(_delta: float) -> void:
	update_line()
