
extends SceneTree
func _init():
	var grid: Array = []
	for y in range(2, 18):
		for x in range(17, 27): grid.append(y*100 + x)
	var g = LevelGenerator.new()
	g.set_seed(777)
	var rs = g.generate_level(grid, 2)
	var pairs: int = 0
	for i in range(rs.size()):
		for j in range(rs.size()):
			if i==j: continue
			var ci: PackedInt32Array = rs[i]["cells"]
			var cj: PackedInt32Array = rs[j]["cells"]
			var ah: int = ci[ci.size()-1]
			var aex: int = int(rs[i]["exit_dir"])
			var p: Vector2i = g.to_xy(ah)+g.DIR_VECTORS[aex]
			while g.is_inside_pos(p):
				var idx: int = g.to_index(p)
				if cj.has(idx):
					pairs+=1
					break
			p+=g.DIR_VECTORS[aex]
	var cov: int = 0
	for a in rs: cov+=(a["cells"] as PackedInt32Array).size()
	print("HARD pairs=", pairs, " arrows=", rs.size(), " cov=", cov, " free=", g._count_free_arrows(rs))
	quit()
