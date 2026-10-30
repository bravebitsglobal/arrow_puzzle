extends Game
## Test headless: choi tu dong cac level co obstacle bang hint, kiem tra logic obstacle.
## Chay: godot --headless --path . res://scene/test/obstacle_sim.tscn -- <thu muc level json>
func _ready() -> void:
	arrow_scene = load("res://arrow/arrow.tscn")
	dot_scene = load("res://dot/dot.tscn")
	var dir: String = OS.get_cmdline_user_args()[0]
	var solutions := {}
	var report = JSON.parse_string(FileAccess.get_file_as_string(OS.get_cmdline_user_args()[1]))
	for r in (report if report is Array else report.get("levels", [])):
		if r.has("solution"):
			solutions[int(r.level)] = r.solution
	var ok := 0
	var fails: Array = []
	for id in range(1, 351):
		var text := FileAccess.get_file_as_string("%s/level_%d.json" % [dir, id])
		if text.is_empty():
			continue
		var data = JSON.parse_string(text)
		var obs: Dictionary = data.get("obstacles", {})
		if obs.values().all(func(v): return v.is_empty()):
			continue
		data.points = Api.new()._deep_floats_to_int(data.points)
		set_level_data(data)
		used_cells.clear()
		await render_level()
		var err := _play(solutions.get(id, []))
		if err.is_empty():
			ok += 1
		else:
			fails.append("L%d: %s" % [id, err])
	print("obstacle sim: %d ok, %d fail" % [ok, fails.size()])
	for f in fails:
		print(f)
	get_tree().quit()
## Choi theo loi giai cua generator (neu co), khong thi theo hint.
func _play(solution: Array) -> String:
	var step := 0
	while used_cells.size():
		if is_finish:
			return "bomb exploded (%d left)" % used_cells.size()
		var idx: int = int(solution[step]) if step < solution.size() else get_hint_idx()
		step += 1
		if arrows[idx].is_exit or !is_arrow_active(idx) or !calculate_exit_path(level[idx]).can_exit:
			return "stuck: no exitable arrow (%d left, frozen %s hidden %s locked %s crates %s)" % [used_cells.size(), frozen_n, hidden_n, locked_group.keys(), crates.size()]
		_on_arrow_clicked(idx)
		if Global.game_data.lives.value < Global.game_data.MAX_LIVE:
			return "lost a life tapping arrow %d" % idx
	if frozen_n.size() or hidden_n.size() or bomb_n.size() or locked_group.size():
		return "board cleared but obstacle state left"
	return ""
