class_name Utils
const grid_width = 100
static func to_xy(cell: int) -> Vector2i:
	return Vector2i(cell % grid_width, cell / grid_width)
