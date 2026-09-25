class_name Utils
const grid_width = 100
const cell_size = 50
static func to_xy(cell: int) -> Vector2i:
	return Vector2i(cell % grid_width, cell / grid_width)
static func to_index(pos: Vector2i) -> int:
	return pos.y * grid_width + pos.x
static func index_to_pos(cell: int)->Vector2:
	var xy = to_xy(cell)
	return Vector2(xy.x * cell_size, xy.y * cell_size)
