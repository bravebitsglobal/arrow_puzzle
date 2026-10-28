extends Node2D
## Arrow chay vong quanh theo duong chu nhat bo goc (tam la vi tri node), dung cho popup loading.
@export var path_size: Vector2 = Vector2(440, 170)
@export var corner_radius: float = 60
@export var body_length: float = 260
@export var speed: float = 450
const CORNER_SEGMENTS = 8
const BODY_STEP: float = 10
@onready var line_2d: Line2D = $Line2D
@onready var head: Node2D = $Head
@onready var head_sprites: Array[Node] = [$Head/Up, $Head/Down, $Head/Left, $Head/Right]
var path := PackedVector2Array()
# Do dai cong don tai moi diem cua path (path[0] -> path[i])
var path_dist := PackedFloat32Array()
var path_length: float = 0
var progress: float = 0
var color_index: int = -1
# Dung de phat hien luc popup vua hien lai -> doi mau moi
var _was_visible: bool = false
func _ready() -> void:
	_build_path()
	progress = body_length
	_update()
func _process(delta: float) -> void:
	if !is_visible_in_tree():
		_was_visible = false
		return
	if !_was_visible:
		_was_visible = true
		_random_color()
	progress = fmod(progress + speed * delta, path_length)
	_update()
## Doi sang mau ngau nhien khac voi mau hien tai.
func _random_color() -> void:
	var idx: int
	if color_index < 0:
		idx = randi_range(0, Arrow.COLORS.size() - 1)
	else:
		idx = randi_range(0, Arrow.COLORS.size() - 2)
		if idx >= color_index:
			idx += 1
	color_index = idx
	(material as ShaderMaterial).set_shader_parameter("target_color", Color(Arrow.COLORS[idx]))
## Duong chu nhat bo goc, chay theo chieu kim dong ho bat dau tu goc tren ben trai.
func _build_path() -> void:
	var half := path_size / 2
	var r := minf(corner_radius, minf(half.x, half.y))
	# Tam 4 goc bo tron va goc bat dau cua cung (tren-phai, duoi-phai, duoi-trai, tren-trai)
	var corners = [
		[Vector2(half.x - r, -half.y + r), -PI / 2],
		[Vector2(half.x - r, half.y - r), 0.0],
		[Vector2(-half.x + r, half.y - r), PI / 2],
		[Vector2(-half.x + r, -half.y + r), PI],
	]
	path.clear()
	for c in corners:
		for i in range(CORNER_SEGMENTS + 1):
			var angle: float = c[1] + PI / 2 * i / CORNER_SEGMENTS
			path.append(c[0] + Vector2(cos(angle), sin(angle)) * r)
	path.append(path[0])
	path_dist.clear()
	path_dist.append(0)
	for i in range(1, path.size()):
		path_dist.append(path_dist[i - 1] + path[i - 1].distance_to(path[i]))
	path_length = path_dist[path_dist.size() - 1]
func _sample(d: float) -> Vector2:
	d = fposmod(d, path_length)
	var i := path_dist.bsearch(d) - 1
	i = clampi(i, 0, path.size() - 2)
	var seg := path_dist[i + 1] - path_dist[i]
	return path[i].lerp(path[i + 1], (d - path_dist[i]) / seg if seg > 0 else 0.0)
func _update() -> void:
	var pts := PackedVector2Array()
	var d := progress - body_length
	while d < progress:
		pts.append(_sample(d))
		d += BODY_STEP
	var head_pos := _sample(progress)
	pts.append(head_pos)
	line_2d.points = pts
	head.position = head_pos
	_update_head_dir(head_pos - _sample(progress - BODY_STEP))
## Chon sprite dau theo truc chinh cua huong di (giong Arrow: Up, Down, Left, Right)
func _update_head_dir(dir: Vector2) -> void:
	var idx: int
	if absf(dir.y) > absf(dir.x):
		idx = Utils.Direction.Up if dir.y < 0 else Utils.Direction.Down
	else:
		idx = Utils.Direction.Left if dir.x < 0 else Utils.Direction.Right
	for i in range(head_sprites.size()):
		head_sprites[i].visible = i == idx
