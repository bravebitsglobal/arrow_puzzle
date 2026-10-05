extends SceneTree
func _init() -> void:
	var gen: LevelGenerator = LevelGenerator.new()
	gen.max_board_restarts = 30
	var usable: PackedInt32Array = PackedInt32Array()
	for y in range(2, 18):
		for x in range(17, 27):
			usable.append(y * gen.grid_width + x)
	# Debug: run _try_place_all_arrows + _fill_remaining stats
	gen.set_seed(7)
	# Instrument: monkey patch by checking how many merges fail
	# Instead just check raw _try_place_all_arrows coverage
	quit()
