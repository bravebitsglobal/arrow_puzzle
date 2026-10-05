class_name Utils
const grid_width = 1000
const cell_size = 50
enum Direction{
	Up,
	Down,
	Left, 
	Right
}

static func to_index(data: Array) -> int:
	return data[1] * grid_width + data[0]
static func to_pos(data: PackedInt32Array)->Vector2:
	return Vector2(data[0] * cell_size, data[1] * cell_size)
static func convert_level(level: Array)->Array[PackedInt32Array]:
	var rs: Array[PackedInt32Array]
	for a in level:
		rs.append(a.cells)
	return rs
static func get_exit_dir(arrow: Array)->Direction:
	var a = arrow[arrow.size()-2]
	var b = arrow[arrow.size()-1]
	if b[1] - a[1] == -1:
		return Direction.Up
	if b[1] - a[1] == 1:
		return Direction.Down
	if b[0] - a[0] == -1:
		return Direction.Left
	return Direction.Right
static func get_center(data)->Vector2:
	var left_top = data[0].duplicate()
	var right_bottom = data[0].duplicate()
	for cell in data:
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
	return center
