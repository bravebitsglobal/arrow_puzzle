extends Line2D
class_name Arrow
var COLORS = ["#FF2A4B","#E60039","#FF3366","#FF4081","#FF007F","#FF5252","#D81B60","#FF6D00","#FF8800","#FF5722","#FF9100","#F57C00","#FF7043","#E65100","#FFC400","#FFB300","#FFD600","#FFCA28","#FFA000","#FBC02D","#76FF03","#00E676","#00C853","#4CAF50","#AEEA00","#1DE9B6","#2E7D32","#00B0FF","#00E5FF","#2979FF","#2962FF","#1E88E5","#00BFA5","#0D47A1","#AA00FF","#651FFF","#3D5AFE","#D500F9","#8E24AA","#4A148C","#795548","#A1887F","#5D4037","#D84315","#78909C","#455A64","#263238","#1A1A2E","#212121","#0F0F1A"]
@export var PATTERNS: Array[Texture2D] = []
@onready var head: Node2D = $Head
const ROTATES = [0, 180, -90, 90]
const CELL_SIZE = 50
var data
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#modulate = Color(COLORS[randi_range(0, COLORS.size()-1)])
	#texture = PATTERNS[randi_range(0, PATTERNS.size()-1)]
	area_2d.input_event.connect(_on_area_2d_input_event)
	#var c1 = Color(COLORS[randi_range(0, COLORS.size()-1)])
	#var c2 = Color(COLORS[randi_range(0, COLORS.size()-1)])
	#gradient = Gradient.new()
	#gradient.colors = [c1, c2]
	# 2. Tạo khung va chạm tự động theo nét vẽ của Line2D
	update_line_collision()
	render()

@onready var area_2d: Area2D = $Area2D
@onready var collision_polygon: CollisionPolygon2D = $Area2D/CollisionPolygon2D

func update_line_collision() -> void:
	if points.size() < 2:
		return
		
	# Geometry2D giúp phóng to (offset) đường Line2D thành một dải PolygonalPolygon
	# dựa trên độ rộng (width) của Line2D
	var polygons = Geometry2D.offset_polyline(points, width / 2.0)
	
	if polygons.size() > 0:
		collision_polygon.polygon = polygons[0]

func _on_area_2d_input_event(viewport: Node, event: InputEvent, shape_idx: int) -> void:
	print("clicked")
	# Kiểm tra nếu người dùng nhấn chuột trái vào Line
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		print("Đã click vào Line2D!")
func set_data(_data):
	data = _data
func render():
	var pos: Vector2i = Vector2.ZERO
	for c in data.cells:
		pos = Utils.to_xy(c)
		add_point(Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE))
	head.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	head.rotation_degrees = ROTATES[data.exit_dir]
