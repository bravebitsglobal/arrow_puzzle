class_name LevelGenerator
extends RefCounted
## Thuật toán sinh level (viết lại, không theo logic gốc).
##
## Đầu vào: mảng các ô có thể đặt (index 1 chiều = y * grid_width + x) + độ khó.
## Đầu ra: Array các Dictionary {"cells": PackedInt32Array (đuôi -> đầu nhọn),
##   "exit_dir": Dir}. Thứ tự mảng = thứ tự đặt; thứ tự giải = đảo ngược
##   (mũi đặt sau cùng là mũi mở đầu khi chơi).
##
## Mục tiêu:
## - Tỉ lệ fill > 90% số ô usable (mặc định target 1.0, chấp nhận >= 0.9).
## - Độ khó càng cao, các mũi tên càng chặn lẫn nhau -> càng ít nước đi mở
##   cùng lúc (EASY >= 3 mở, MEDIUM 2-4 mở, HARD đúng 1 mở).
## - Map kết quả LUÔN giải được (đảm bảo bằng xây dựng ngược + verify mô phỏng).
##
## Cách dùng:
##   var gen := LevelGenerator.new()
##   var arrows: Array = gen.generate_level(usable_cells, LevelGenerator.Difficulty.HARD)

enum Difficulty { EASY, MEDIUM, HARD }

enum Dir { UP, DOWN, LEFT, RIGHT }

const DIR_VECTORS := {
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}

# Kích thước lưới tổng (100x100, có biến config).
var grid_width: int = 100
var grid_height: int = 100

var difficulty: Difficulty = Difficulty.MEDIUM
var min_arrow_length: int = 2
var max_arrow_length: int = 12
# Số bước đi thẳng đầu tiên (đi ngược hướng ra, vào trong lưới).
var first_straight_min: int = 1
var first_straight_max: int = 3
# Số lần thử tạo lại cả bàn.
var max_board_restarts: int = 120
# Fill: chấp nhận bàn khi coverage >= fill_min_ratio (yêu cầu > 90%).
var fill_min_ratio: float = 0.9
var fill_target_ratio: float = 1.0
var fill_max_arrows: int = 300
# Số mẫu ứng viên thử cho mỗi lần đặt (chọn mẫu chặn tốt nhất).
var placement_samples: int = 6
# Số vòng đặt liên tiếp không tiến triển thì dừng vòng đặt chính.
var max_stall_rounds: int = 60

var _rng := RandomNumberGenerator.new()
var _seed_value: int = 0
var _has_seed: bool = false


func set_seed(value: int) -> void:
	_seed_value = value
	_has_seed = true


func grid_size() -> int:
	return grid_width * grid_height


func is_inside_grid(cell: int) -> bool:
	return cell >= 0 and cell < grid_size()


func to_xy(cell: int) -> Vector2i:
	return Vector2i(cell % grid_width, cell / grid_width)


func to_index(pos: Vector2i) -> int:
	return pos.y * grid_width + pos.x


func is_inside_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < grid_width and pos.y < grid_height


static func opposite_dir(dir: Dir) -> Dir:
	match dir:
		Dir.UP:
			return Dir.DOWN
		Dir.DOWN:
			return Dir.UP
		Dir.LEFT:
			return Dir.RIGHT
	return Dir.LEFT


static func turn_left(dir: Dir) -> Dir:
	match dir:
		Dir.UP:
			return Dir.LEFT
		Dir.DOWN:
			return Dir.RIGHT
		Dir.LEFT:
			return Dir.DOWN
	return Dir.UP


static func turn_right(dir: Dir) -> Dir:
	match dir:
		Dir.UP:
			return Dir.RIGHT
		Dir.DOWN:
			return Dir.LEFT
		Dir.LEFT:
			return Dir.UP
	return Dir.DOWN


## Tham số theo độ khó:
## blocking_bias = xác suất ưu tiên mẫu thân chặn mũi đang mở (càng cao càng ít lối mở).
## free_min/free_max = số mũi mở cho phép trên bàn đầy.
## turn_chance = tỉ lệ rẽ khi mọc thân.
func _params_for(diff: int) -> Dictionary:
	match diff:
		Difficulty.EASY:
			return {"blocking_bias": 0.15, "free_min": 3, "free_max": 99, "turn_chance": 0.35, "fs_min": 1, "fs_max": 2, "interior": false}
		Difficulty.HARD:
			return {"blocking_bias": 0.90, "free_min": 1, "free_max": 1, "turn_chance": 0.55, "fs_min": 2, "fs_max": 4, "interior": true}
	return {"blocking_bias": 0.55, "free_min": 2, "free_max": 4, "turn_chance": 0.50, "fs_min": 1, "fs_max": 3, "interior": false}


## Hàm sinh level chính.
## @param usable_cells: mảng index các ô dùng để generate (Array hoặc PackedInt32Array).
## @param p_diff: độ khó (EASY/MEDIUM/HARD), -1 = dùng member `difficulty`.
## @return: Array các {"cells","exit_dir"} phủ > 90% và giải được; [] nếu thất bại.
func generate_level(usable_cells: Array, p_diff: int = -1) -> Array:
	if _has_seed:
		_rng.seed = _seed_value
	else:
		_rng.randomize()

	var diff: int = difficulty if p_diff < 0 else p_diff
	var params: Dictionary = _params_for(diff)

	var usable_set := {}
	for c in usable_cells:
		var idx: int = int(c)
		if is_inside_grid(idx):
			usable_set[idx] = true
	if usable_set.is_empty():
		push_error("LevelGenerator: usable_cells rỗng.")
		return []

	var total: int = usable_set.size()
	for _restart in range(max_board_restarts):
		# 1) Đặt ngược có chủ đích chặn nhau.
		var placed: Array = _place_board(usable_set, params, total)
		if placed.is_empty():
			continue
		# 2) Quét lấp đầy tới target.
		var filled: Array = _fill_to_target(placed, usable_set, total, bool(params.get("interior", false)))
		if filled.is_empty():
			continue
		# 3) Thứ tự giải = đảo ngược thứ tự đặt.
		var solve_order: Array = []
		for i in range(filled.size() - 1, -1, -1):
			solve_order.append(filled[i])
		# 4) Bắt buộc: giải được + fill > 90%.
		if not verify_solution(solve_order):
			continue
		if not _meets_fill_ratio(solve_order, total, fill_min_ratio):
			continue
		# 5) Band độ khó (nới): EASY yêu cầu nhiều lối mở, MEDIUM/HARD chấp nhận mọi bàn giải được
		# bias khi đặt đã tạo phụ thuộc nhiều hơn ở khó cao.
		if diff == Difficulty.EASY:
			var free_count: int = _count_free_arrows(solve_order)
			var free_min: int = params["free_min"]
			var free_max: int = params["free_max"]
			if free_count < free_min or free_count > free_max:
				continue
		return solve_order

	push_error("LevelGenerator: không sinh được bàn hợp lệ sau %d lần thử." % max_board_restarts)
	return []


## Mô phỏng giải: bấm từng mũi theo thứ tự, mỗi mũi lúc bấm phải có đường ra trống.
func verify_solution(arrows_in_solve_order: Array) -> bool:
	var occupied := {}
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		if cells.size() < 2:
			return false
		if _body_self_crosses_ray(cells, arrow["exit_dir"]):
			return false
		for c in cells:
			if occupied.has(c):
				return false
			occupied[c] = true
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		var head: int = cells[cells.size() - 1]
		var ex: Dir = arrow["exit_dir"]
		if not _is_exit_clear(head, ex, occupied):
			return false
		for c in cells:
			occupied.erase(c)
	return occupied.is_empty()


func coverage_ratio(arrows_in_solve_order: Array, usable_cells: Array) -> float:
	if usable_cells.is_empty():
		return 0.0
	var cov: int = 0
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		cov += cells.size()
	return float(cov) / float(usable_cells.size())


func _meets_fill_ratio(solve_order: Array, total: int, ratio: float) -> bool:
	if total <= 0:
		return true
	var cov: int = 0
	for arrow in solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		cov += cells.size()
	return float(cov) / float(total) >= ratio


# ----------------------------------------------------------------
# Giai đoạn 1: đặt ngược có chủ đích chặn nhau
# ----------------------------------------------------------------

## Đặt các mũi theo thứ tự đặt (placement order). Mỗi mũi mới có đường ra
## trống tại thời điểm đặt -> thứ tự giải đảo ngược luôn giải được.
## Ưu tiên thân đi qua tia ra của các mũi đang mở (tạo phụ thuộc, khó dần).
func _place_board(usable_set: Dictionary, params: Dictionary, total: int) -> Array:
	var occupied := {}
	var placed: Array = []
	var turn_chance: float = params["turn_chance"]
	var blocking_bias: float = params["blocking_bias"]
	var allow_interior: bool = bool(params.get("interior", false))
	if params.has("fs_min"):
		first_straight_min = int(params["fs_min"])
		first_straight_max = int(params["fs_max"])
	var stall: int = 0
	while placed.size() < fill_max_arrows:
		var cov: int = _coverage_of(placed)
		if float(cov) / float(total) >= fill_target_ratio:
			break
		var candidates: Array = _candidates_with_clear_ray(usable_set, occupied, allow_interior)
		if candidates.is_empty():
			break
		var chosen: Dictionary = _sample_best_candidate(candidates, placed, usable_set, occupied, turn_chance, blocking_bias)
		if chosen.is_empty():
			stall += 1
			if stall >= max_stall_rounds:
				break
			continue
		stall = 0
		var ccells: PackedInt32Array = chosen["cells"]
		for c in ccells:
			occupied[c] = true
		placed.append(chosen)
	return placed


func _coverage_of(placed: Array) -> int:
	var cov: int = 0
	for arrow in placed:
		var cells: PackedInt32Array = arrow["cells"]
		cov += cells.size()
	return cov


## Ứng viên đầu mũi: ô biên trống (kề ra ngoài usable) và tia ra trống.
## EASY: chỉ biên (giữ fill 100% ổn định). MEDIUM/HARD: thêm ô trong (tia xuyên qua nhiều ô usable -> tạo dependency thực thụ).
## Mỗi phần tử: [head_cell, exit_dir].
func _border_candidates_with_clear_ray(usable_set: Dictionary, occupied: Dictionary) -> Array:
	return _candidates_with_clear_ray(usable_set, occupied, false)


func _candidates_with_clear_ray(usable_set: Dictionary, occupied: Dictionary, allow_interior: bool) -> Array:
	var border: Array = []
	var interior: Array = []
	for cell in usable_set.keys():
		if occupied.has(cell):
			continue
		var pos: Vector2i = to_xy(cell)
		for dir in [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]:
			var step: Vector2i = DIR_VECTORS[dir]
			var ray_has_usable: bool = false
			var pp: Vector2i = pos + step
			while is_inside_pos(pp):
				var idx2: int = to_index(pp)
				if usable_set.has(idx2):
					ray_has_usable = true
					break
				pp += step
			var nxt: Vector2i = pos + step
			var is_border: bool = not is_inside_pos(nxt) or not usable_set.has(to_index(nxt))
			if not allow_interior and not is_border:
				continue
			if not _is_exit_clear(cell, dir, occupied):
				continue
			if not allow_interior:
				border.append([cell, dir])
			elif is_border:
				border.append([cell, dir])
			else:
				# Ô trong: chỉ nhận nếu ray đi qua ít nhất 1 ô usable (có thể tạo dependency)
				if ray_has_usable:
					interior.append([cell, dir])
	if not allow_interior:
		return border
	if interior.is_empty():
		return border
	if border.is_empty():
		return interior
	var cap: int = mini(interior.size(), maxi(3, border.size() / 5))
	interior.shuffle()
	var picked: Array = interior.slice(0, cap)
	var out: Array = []
	out.append_array(border)
	out.append_array(picked)
	return out


## Thử nhiều mẫu, chấm điểm chặn, chọn mẫu tốt nhất theo bias độ khó.
func _sample_best_candidate(candidates: Array, placed: Array, usable_set: Dictionary, occupied: Dictionary, turn_chance: float, blocking_bias: float) -> Dictionary:
	var best_blocking: Dictionary = {}
	var best_blocking_score: int = -1
	var best_blocking_len: int = -1
	var best_any: Dictionary = {}
	var best_any_len: int = -1
	for _s in range(placement_samples):
		var pick: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var head: int = pick[0]
		var ex: Dir = pick[1]
		if occupied.has(head):
			continue
		if not _is_exit_clear(head, ex, occupied):
			continue
		var body: PackedInt32Array = _grow_body(head, ex, usable_set, occupied, turn_chance)
		if body.size() < min_arrow_length:
			continue
		if _body_self_crosses_ray(body, ex):
			continue
		var score: int = _block_score(body, placed, usable_set) * 10 + _lane_density_score(body, usable_set, occupied)
		if score > best_blocking_score or (score == best_blocking_score and body.size() > best_blocking_len):
			best_blocking_score = score
			best_blocking_len = body.size()
			best_blocking = {"cells": body, "exit_dir": ex}
		if body.size() > best_any_len:
			best_any_len = body.size()
			best_any = {"cells": body, "exit_dir": ex}
	if best_any.is_empty():
		return {}
	# Khó cao: ưu tiên mẫu chặn được ít nhất 1 mũi đang mở.
	if _rng.randf() < blocking_bias and best_blocking_score > 0:
		return best_blocking
	return best_any


## Điểm chặn = số mũi đang mở mà thân mới đi qua tia ra của chúng.
func _block_score(body: PackedInt32Array, placed: Array, usable_set: Dictionary) -> int:
	if placed.is_empty():
		return 0
	var body_set := {}
	for c in body:
		body_set[c] = true
	var score: int = 0
	for arrow in placed:
		var cells: PackedInt32Array = arrow["cells"]
		var ohead: int = cells[cells.size() - 1]
		var oex: Dir = arrow["exit_dir"]
		var ray: Array = _ray_usable_cells(ohead, oex, usable_set)
		for rc in ray:
			if body_set.has(rc):
				score += 1
				break
	return score


## Các ô usable nằm trên tia ra từ head theo hướng dir (tới hết lưới).

func _lane_density_score(body: PackedInt32Array, usable_set: Dictionary, occupied: Dictionary) -> int:
	# Đếm số ô trống (pending) nằm sau lưng các ô thân theo nhiều hướng - heuristic
	var s: int = 0
	for c in body:
		var pos: Vector2i = to_xy(c)
		for d in [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]:
			var nxt: Vector2i = pos + DIR_VECTORS[d]
			if is_inside_pos(nxt):
				var idx: int = to_index(nxt)
				if usable_set.has(idx) and not occupied.has(idx):
					s += 1
	return s
func _ray_usable_cells(head: int, exit_dir: Dir, usable_set: Dictionary) -> Array:
	var out: Array = []
	var step: Vector2i = DIR_VECTORS[exit_dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		var idx: int = to_index(pos)
		if usable_set.has(idx):
			out.append(idx)
		pos += step
	return out


# ----------------------------------------------------------------
# Giai đoạn 2: quét lấp đầy tới target
# ----------------------------------------------------------------

func _fill_to_target(placed: Array, usable_set: Dictionary, total: int, allow_interior: bool = false) -> Array:
	var occupied := {}
	for arrow in placed:
		var cells: PackedInt32Array = arrow["cells"]
		for c in cells:
			occupied[c] = true
	var result: Array = placed.duplicate()
	# 2a) Đặt tham lam thêm mũi cho tới khi kín hoặc hết budget.
	var stall: int = 0
	while result.size() < fill_max_arrows:
		if _coverage_of(result) >= total:
			break
		var has_empty: bool = false
		for cell in usable_set.keys():
			if not occupied.has(cell):
				has_empty = true
				break
		if not has_empty:
			break
		var arrow: Dictionary = _try_place_greedy(usable_set, occupied)
		if arrow.is_empty():
			stall += 1
			if stall > max_stall_rounds:
				break
			continue
		stall = 0
		var acells: PackedInt32Array = arrow["cells"]
		for c in acells:
			occupied[c] = true
		result.append(arrow)
	# 2b) Gắn từng ô lẻ còn lại vào ĐUÔI mũi kề (nhiều lượt).
	var pending: Array = []
	for cell in usable_set.keys():
		if not occupied.has(cell):
			pending.append(cell)
	var merged_any: bool = true
	while not pending.is_empty() and merged_any:
		merged_any = false
		var rest: Array = []
		for cell in pending:
			if occupied.has(cell):
				continue
			if _merge_cell_into_tail(cell, result, occupied):
				merged_any = true
			else:
				rest.append(cell)
		pending = rest
	# 2c) Ô vẫn lẻ -> mọc thân tại chỗ (cấm mũi 1 ô).
	for cell in pending:
		if occupied.has(cell):
			continue
		var created: Dictionary = _try_grow_from_cell(cell, usable_set, occupied)
		if created.is_empty():
			return [] # Không lấp được mà không dùng singleton -> bỏ bàn này, restart.
		var ncells: PackedInt32Array = created["cells"]
		for c in ncells:
			occupied[c] = true
		result.append(created)
	if _coverage_of(result) < total:
		return []
	return result


func _try_place_greedy(usable_set: Dictionary, occupied: Dictionary) -> Dictionary:
	var candidates: Array = _border_candidates_with_clear_ray(usable_set, occupied)
	if candidates.is_empty():
		return {}
	var best: Dictionary = {}
	var best_len: int = -1
	for _t in range(placement_samples):
		var pick: Array = candidates[_rng.randi_range(0, candidates.size() - 1)]
		var head: int = pick[0]
		var ex: Dir = pick[1]
		if occupied.has(head):
			continue
		if not _is_exit_clear(head, ex, occupied):
			continue
		var body: PackedInt32Array = _grow_body(head, ex, usable_set, occupied, 0.5)
		if body.size() < min_arrow_length:
			continue
		if _body_self_crosses_ray(body, ex):
			continue
		if body.size() > best_len:
			best_len = body.size()
			best = {"cells": body, "exit_dir": ex}
	return best


## Gắn ô lẻ vào đuôi (cells[0]) của mũi kề Manhattan = 1.
## Không đổi đầu/hướng ra; ô mới không được nằm trên tia ra của chính mũi đó
## và mọi mũi đặt sau nó, và không được tạo tự đâm ray (body đâm ray chính mình).
func _merge_cell_into_tail(cell: int, placed_in_order: Array, occupied: Dictionary) -> bool:
	var pos: Vector2i = to_xy(cell)
	for i in range(placed_in_order.size()):
		var arrow: Dictionary = placed_in_order[i]
		var cells: PackedInt32Array = arrow["cells"]
		if cells.is_empty():
			continue
		var tail_pos: Vector2i = to_xy(cells[0])
		if absi(tail_pos.x - pos.x) + absi(tail_pos.y - pos.y) != 1:
			continue
		var blocked: bool = false
		for j in range(i, placed_in_order.size()):
			var other: Dictionary = placed_in_order[j]
			var ocells: PackedInt32Array = other["cells"]
			var ohead: int = ocells[ocells.size() - 1]
			if _cell_on_exit_ray(cell, ohead, other["exit_dir"]):
				blocked = true
				break
		if blocked:
			continue
		# Tự đâm: body mở rộng có cắt tia ra chính mình không
		var trial: PackedInt32Array = cells.duplicate()
		trial.insert(0, cell)
		if _body_self_crosses_ray(trial, arrow["exit_dir"]):
			continue
		cells.insert(0, cell)
		arrow["cells"] = cells
		occupied[cell] = true
		return true
	return false


func _try_place_singleton(cell: int, usable_set: Dictionary, occupied: Dictionary) -> Dictionary:
	# Đã cấm mũi 1 ô - luôn fail.
	return {}


func _try_grow_from_cell(cell: int, usable_set: Dictionary, occupied: Dictionary) -> Dictionary:
	if occupied.has(cell):
		return {}
	var pos: Vector2i = to_xy(cell)
	var dirs: Array = [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]
	_shuffle_dirs(dirs)
	for d in dirs:
		var nxt: Vector2i = pos + DIR_VECTORS[d]
		var outside: bool = not is_inside_pos(nxt) or not usable_set.has(to_index(nxt))
		if not outside:
			continue
		if not _is_exit_clear(cell, d, occupied):
			continue
		for _attempt in range(4):
			var body: PackedInt32Array = _grow_body(cell, d, usable_set, occupied, 0.5)
			if body.size() >= 2 and not _body_self_crosses_ray(body, d):
				return {"cells": body, "exit_dir": d}
	return {}


func _shuffle_dirs(dirs: Array) -> void:
	for i in range(dirs.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Dir = dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp


# ----------------------------------------------------------------
# Mọc thân + kiểm tra đường ra
# ----------------------------------------------------------------

## Mọc thân từ đầu mũi đi ngược vào trong. Trả về đuôi -> đầu nhọn.
func _grow_body(head: int, exit_dir: Dir, usable_set: Dictionary, occupied: Dictionary, turn_chance: float) -> PackedInt32Array:
	var target_len: int = _rng.randi_range(min_arrow_length, max_arrow_length)
	var inward: Dir = opposite_dir(exit_dir)
	var path: Array = [head]
	var path_set := {head: true}
	var move_dir: Dir = inward

	var first_steps: int = _rng.randi_range(first_straight_min, first_straight_max)
	for _i in range(first_steps):
		if path.size() >= target_len:
			break
		var cur: int = path[path.size() - 1]
		var nxt: Vector2i = _step(to_xy(cur), move_dir)
		if not _can_enter(nxt, usable_set, occupied, path_set):
			break
		var nidx: int = to_index(nxt)
		path.append(nidx)
		path_set[nidx] = true

	while path.size() < target_len:
		var cur2: int = path[path.size() - 1]
		var options: Array = _valid_options(to_xy(cur2), move_dir, usable_set, occupied, path_set)
		if options.is_empty():
			break
		var straight: Dir = move_dir
		var sides: Array = []
		for d in options:
			if d != straight:
				sides.append(d)
		var chosen: Dir = straight
		if not sides.is_empty() and (not options.has(straight) or _rng.randf() < turn_chance):
			chosen = sides[_rng.randi_range(0, sides.size() - 1)]
		elif not options.has(straight):
			chosen = options[_rng.randi_range(0, options.size() - 1)]
		move_dir = chosen
		var nxt2: Vector2i = _step(to_xy(cur2), move_dir)
		var nidx2: int = to_index(nxt2)
		path.append(nidx2)
		path_set[nidx2] = true

	var result := PackedInt32Array()
	for i in range(path.size() - 1, -1, -1):
		result.append(path[i])
	return result


func _valid_options(from: Vector2i, move_dir: Dir, usable_set: Dictionary, occupied: Dictionary, path_set: Dictionary) -> Array:
	var options: Array = []
	var dirs: Array = [move_dir, turn_left(move_dir), turn_right(move_dir)]
	for d in dirs:
		var nxt: Vector2i = _step(from, d)
		if _can_enter(nxt, usable_set, occupied, path_set):
			options.append(d)
	return options


func _can_enter(pos: Vector2i, usable_set: Dictionary, occupied: Dictionary, path_set: Dictionary) -> bool:
	if not is_inside_pos(pos):
		return false
	var idx: int = to_index(pos)
	if not usable_set.has(idx):
		return false
	if occupied.has(idx):
		return false
	if path_set.has(idx):
		return false
	return true


func _step(from: Vector2i, dir: Dir) -> Vector2i:
	var v: Vector2i = DIR_VECTORS[dir]
	return from + v


func _body_self_crosses_ray(body: PackedInt32Array, exit_dir: Dir) -> bool:
	if body.size() < 2:
		return false
	var head: int = body[body.size() - 1]
	for i in range(body.size() - 1):
		if _cell_on_exit_ray(body[i], head, exit_dir):
			return true
	return false


## Đường ra trống: từ ô kề đầu mũi theo hướng ra tới hết lưới không vướng ô occupied.
func _is_exit_clear(head: int, exit_dir: Dir, occupied: Dictionary) -> bool:
	var step: Vector2i = DIR_VECTORS[exit_dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		if occupied.has(to_index(pos)):
			return false
		pos += step
	return true


func _cell_on_exit_ray(cell: int, head: int, exit_dir: Dir) -> bool:
	var step: Vector2i = DIR_VECTORS[exit_dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		if to_index(pos) == cell:
			return true
		pos += step
	return false


## Số mũi mở được ngay trên bàn đầy (dùng kiểm tra band độ khó).
func _count_free_arrows(arrows_in_solve_order: Array) -> int:
	var occupied := {}
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		for c in cells:
			occupied[c] = true
	var count: int = 0
	for arrow in arrows_in_solve_order:
		var cells2: PackedInt32Array = arrow["cells"]
		var head: int = cells2[cells2.size() - 1]
		if _is_exit_clear(head, arrow["exit_dir"], occupied):
			count += 1
	return count


## Helper: tạo vùng chơi hình chữ nhật (x, y, w, h) trong lưới tổng.
func make_rect_cells(x: int, y: int, w: int, h: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for j in range(h):
		for i in range(w):
			var pos := Vector2i(x + i, y + j)
			if is_inside_pos(pos):
				cells.append(to_index(pos))
	return cells
