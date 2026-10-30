extends "res://scene/test/obstacle_sim.gd"
## Chup man hinh 1 level de xem visual obstacle. Args: <file level json> <file png ra>
func _ready() -> void:
	arrow_scene = load("res://arrow/arrow.tscn")
	dot_scene = load("res://dot/dot.tscn")
	var args := OS.get_cmdline_user_args()
	var data = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	data.points = Api.new()._deep_floats_to_int(data.points)
	set_level_data(data)
	move_camera_to_center()
	camera_2d.zoom = Vector2(0.9, 0.9)
	if args.size() > 2:
		camera_2d.position = Vector2(float(args[2]), float(args[3])) * Utils.cell_size
	await render_level()
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png(args[1])
	get_tree().quit()
