class_name Utils
const grid_width = 100
const cell_size = 50
enum Direction{
	Up,
	Down,
	Left, 
	Right
}
static func to_xy(cell: int) -> Vector2i:
	return Vector2i(cell % grid_width, cell / grid_width)
static func to_index(pos: Vector2i) -> int:
	return pos.y * grid_width + pos.x
static func index_to_pos(cell: int)->Vector2:
	var xy = to_xy(cell)
	return Vector2(xy.x * cell_size, xy.y * cell_size)
static func convert_level(level: Array)->Array[PackedInt32Array]:
	var rs: Array[PackedInt32Array]
	for a in level:
		rs.append(a.cells)
	return rs
static func get_exit_dir(arrow: Array)->Direction:
	var a = to_xy(arrow[arrow.size()-2])
	var b = to_xy(arrow[arrow.size()-1])
	if b.y - a.y == -1:
		return Direction.Up
	if b.y - a.y == 1:
		return Direction.Down
	if b.x - a.x == -1:
		return Direction.Left
	return Direction.Right
