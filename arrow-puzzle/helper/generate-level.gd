class_name LevelGenerator
extends RefCounted
## Luong moi:
## B1: n mui huong ra ngoai (tia thoang).
## B2: voi moi mui cha, tao mui con co tia thoat di qua than cha
##     (con phu thuoc cha -> giai cha truoc, con sau). Lap BFS den khi khong con cho.
## B3: ra soat o trong: 2 o ke nhau -> 1 mui, 1 o le -> bo qua.
## B4: kiem tra loi giai bang mo phong thao lan luot.

enum Difficulty { EASY, MEDIUM, HARD }

enum Dir { UP, DOWN, LEFT, RIGHT }

const DIR_VECTORS := {
	Dir.UP: Vector2i(0, -1),
	Dir.DOWN: Vector2i(0, 1),
	Dir.LEFT: Vector2i(-1, 0),
	Dir.RIGHT: Vector2i(1, 0),
}

var grid_width: int = 100
var grid_height: int = 100

var difficulty: Difficulty = Difficulty.MEDIUM
var min_arrow_length: int = 2
var max_arrow_length: int = 12
var first_straight_min: int = 1
var first_straight_max: int = 3
var max_board_restarts: int = 80
var max_generate_ms: int = 1500
var fill_min_ratio: float = 0.88
var fill_target_ratio: float = 0.96
var fill_max_arrows: int = 250
var placement_samples: int = 8
var max_stall_rounds: int = 20
var max_build_tries: int = 2

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

func _dir_between(from_cell: int, to_cell: int) -> int:
	var a: Vector2i = to_xy(from_cell)
	var b: Vector2i = to_xy(to_cell)
	var d: Vector2i = b - a
	if d == Vector2i(0, -1):
		return Dir.UP
	if d == Vector2i(0, 1):
		return Dir.DOWN
	if d == Vector2i(-1, 0):
		return Dir.LEFT
	if d == Vector2i(1, 0):
		return Dir.RIGHT
	return -1

func _exit_matches_body(body: PackedInt32Array, exit_dir: int) -> bool:
	if body.size() < 2:
		return false
	var tail_dir: int = _dir_between(body[body.size() - 2], body[body.size() - 1])
	return tail_dir == exit_dir

## Tham so theo do kho n: n = so mui huong ra ngoai ban dau.
func _params_for(diff: int) -> Dictionary:
	match diff:
		Difficulty.EASY:
			return {"n": 3, "turn_chance": 0.30, "fs_min": 1, "fs_max": 2}
		Difficulty.HARD:
			return {"n": 1, "turn_chance": 0.50, "fs_min": 1, "fs_max": 3}
	return {"n": 2, "turn_chance": 0.40, "fs_min": 1, "fs_max": 3}

## Ham sinh level chinh.
## n: so mui huong ra ngoai ban dau (neu < 0 thi dung difficulty mac dinh)
func generate_level(usable_cells: Array, n: int = -1, turn_chance: float = 0.4) -> Array:
	if _has_seed:
		_rng.seed = _seed_value
	else:
		_rng.randomize()

	var params: Dictionary
	if n < 0:
		# Dung difficulty mac dinh
		params = _params_for(difficulty)
	else:
		# Dung tham so truc tiep
		params = {"n": n, "turn_chance": turn_chance, "fs_min": first_straight_min, "fs_max": first_straight_max}

	var usable_set := {}
	for c in usable_cells:
		var idx: int = int(c)
		if is_inside_grid(idx):
			usable_set[idx] = true
	if usable_set.is_empty():
		push_error("LevelGenerator: usable_cells rong.")
		return []

	var total: int = usable_set.size()
	var best_board: Array = []
	var best_ratio: float = -1.0
	var attempt_count: int = 0

	# Lap cho den khi tao duoc level hop le
	while attempt_count < 10:  # Gioi han 10 lan thu de tranh vo han
		attempt_count += 1
		var t0: int = Time.get_ticks_msec()

		for _restart in range(max_board_restarts):
			if Time.get_ticks_msec() - t0 > max_generate_ms:
				break

			var board: Array = _build_board(usable_set, params, total)
			if board.is_empty():
				continue

			# board da xu ly 2-o ke nhau ben trong _try_build_once,
			# nhung van goi them de an toan cho truong hop le
			_collect_isolated_cells(board, usable_set)
			_fill_gaps(board, usable_set)

			# Thu tu giai tu nhien la thu tu dat (cha truoc con sau) vi con bi cha chan.
			var solve_order: Array = board.duplicate()

			var ratio: float = float(_coverage_of(solve_order)) / float(total) if total > 0 else 0.0
			if ratio > best_ratio:
				best_ratio = ratio
				best_board = solve_order

			# Kiem tra nhanh truoc khi verify day du
			if ratio < fill_min_ratio:
				continue

			if not verify_solution(solve_order):
				continue

			print("LevelGenerator: thanh cong sau %d lan thu." % attempt_count)
			return solve_order

		# Neu khong thanh cong, thu lai voi seed moi
		if not best_board.is_empty() and best_ratio >= fill_min_ratio * 0.95 and verify_solution(best_board):
			push_warning("LevelGenerator: dung board tot nhat fill %.1f%% sau %d lan thu." % [best_ratio * 100, attempt_count])
			return best_board

		push_warning("LevelGenerator: lan thu %d khong thanh cong (best: %.1f%%), thu lai..." % [attempt_count, best_ratio * 100])
		_rng.randomize()  # Thay doi seed de thu cach khac

	# Neu het 10 lan, tra ve best co the
	if not best_board.is_empty():
		push_warning("LevelGenerator: tra ve best board sau 10 lan thu, fill %.1f%%." % (best_ratio * 100))
		return best_board

	return []

## Xay dung ban theo luong moi
func _build_board(usable_set: Dictionary, params: Dictionary, total: int) -> Array:
	var n: int = int(params.get("n", 2))
	var turn_chance: float = float(params.get("turn_chance", 0.4))
	if params.has("fs_min"):
		first_straight_min = int(params["fs_min"])
		first_straight_max = int(params["fs_max"])

	var best: Array = []
	var best_cov: int = -1
	for _try in range(max_build_tries):
		var attempt: Array = _try_build_once(usable_set, params, n, turn_chance, total)
		var cov: int = _coverage_of(attempt)
		if cov > best_cov:
			best_cov = cov
			best = attempt
		if cov >= total or cov >= int(ceil(float(total) * fill_target_ratio)):
			return attempt
	return best

func _try_build_once(usable_set: Dictionary, params: Dictionary, n: int, turn_chance: float, total: int) -> Array:
	var placed: Array = []
	var occupied := {}

	# --- Buoc 1: n mui huong ra ngoai ---
	for _i in range(n):
		if _coverage_of(placed) >= total:
			break
		var arrow: Dictionary = _pick_outward(usable_set, occupied, turn_chance)
		if arrow.is_empty():
			break
		var cells: PackedInt32Array = arrow["cells"]
		for c in cells:
			occupied[c] = true
		placed.append(arrow)

	# --- Buoc 2: mo rong BFS - con phu thuoc cha (tia con di qua than cha) ---
	var queue: Array = []
	for a in placed:
		queue.append(a)
	var q_idx: int = 0
	var stall: int = 0
	while _coverage_of(placed) < total and placed.size() < fill_max_arrows:
		if q_idx >= queue.size():
			stall += 1
			if stall >= 2:
				break
			queue.shuffle()
			q_idx = 0
			continue
		var parent: Dictionary = queue[q_idx]
		q_idx += 1
		var child: Dictionary = _pick_child_blocking(parent, placed, usable_set, occupied, turn_chance)
		if child.is_empty():
			continue
		stall = 0
		var ccells: PackedInt32Array = child["cells"]
		for c in ccells:
			occupied[c] = true
		placed.append(child)
		queue.append(child)

	# --- Buoc 2b: fallback fill tu do neu BFS khong du ---
	stall = 0
	while _coverage_of(placed) < total and placed.size() < fill_max_arrows:
		var candidates: Array = _candidates_with_clear_ray(usable_set, occupied)
		if candidates.is_empty():
			break
		var arrow2: Dictionary = _pick_best(candidates, placed, usable_set, occupied, turn_chance, false)
		if arrow2.is_empty():
			stall += 1
			if stall >= max_stall_rounds:
				break
			continue
		stall = 0
		var acells: PackedInt32Array = arrow2["cells"]
		for c in acells:
			occupied[c] = true
		placed.append(arrow2)

	# --- Buoc 3: xu ly o trong con lai ---
	_handle_leftovers(placed, usable_set)

	return placed

## Buoc 1: chon 1 mui huong ra ngoai (tia thoang)
func _pick_outward(usable_set: Dictionary, occupied: Dictionary, turn_chance: float) -> Dictionary:
	var cells_list: Array = usable_set.keys()
	cells_list.shuffle()
	var tries: int = mini(placement_samples * 2, cells_list.size())
	for i in range(tries):
		var head: int = cells_list[i]
		if occupied.has(head):
			continue
		for dir in [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]:
			if not _is_exit_clear(head, dir, occupied):
				continue
			if _hits_another_usable_on_ray(head, dir, occupied, usable_set):
				continue
			var body: PackedInt32Array = _grow_body(head, dir, usable_set, occupied, turn_chance)
			if body.size() < min_arrow_length:
				continue
			if not _exit_matches_body(body, dir):
				continue
			if _body_self_crosses_ray(body, dir):
				continue
			return {"cells": body, "exit_dir": dir}
	var candidates: Array = _candidates_with_clear_ray(usable_set, occupied)
	if candidates.is_empty():
		return {}
	return _pick_best(candidates, [], usable_set, occupied, turn_chance, false)

## Tia tu head theo dir co di qua o usable trong nao khong?
func _hits_another_usable_on_ray(head: int, exit_dir: Dir, occupied: Dictionary, usable_set: Dictionary) -> bool:
	var step: Vector2i = DIR_VECTORS[exit_dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		var idx: int = to_index(pos)
		if usable_set.has(idx):
			return true
		pos += step
	return false

## Buoc 2: chon 1 mui con co tia thoat di qua than cha
## Con bi cha chan -> cha phai thoat truoc con moi thoat duoc.
func _pick_child_blocking(parent: Dictionary, placed: Array, usable_set: Dictionary, occupied: Dictionary, turn_chance: float) -> Dictionary:
	var pcells: PackedInt32Array = parent["cells"]
	var parent_set := {}
	for c in pcells:
		parent_set[c] = true

	# Liet ke toan bo (head, dir) thoa: tia head->dir di qua than cha va chua bi occupied chan truoc
	var cands: Array = []
	for cell in usable_set.keys():
		if occupied.has(cell):
			continue
		for dir in [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]:
			if not _ray_hits_set(cell, dir, parent_set):
				continue
			if _ray_blocked_before_hit(cell, dir, parent_set, occupied):
				continue
			cands.append([cell, dir])
	if cands.is_empty():
		return {}
	cands.shuffle()
	# Thu huu han ung vien, uu tien body dai
	var best: Dictionary = {}
	var cap: int = mini(cands.size(), placement_samples * 2)
	for i in range(cap):
		var head: int = cands[i][0]
		var dir: Dir = cands[i][1]
		var body: PackedInt32Array = _grow_body(head, dir, usable_set, occupied, turn_chance)
		if body.size() < min_arrow_length:
			continue
		if not _exit_matches_body(body, dir):
			continue
		if _body_self_crosses_ray(body, dir):
			continue
		if best.is_empty() or body.size() > best["cells"].size():
			best = {"cells": body, "exit_dir": dir}
	return best

## Tia tu head theo dir co di qua tap set khong
func _ray_hits_set(head: int, dir: Dir, target_set: Dictionary) -> bool:
	var step: Vector2i = DIR_VECTORS[dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		var idx: int = to_index(pos)
		if target_set.has(idx):
			return true
		pos += step
	return false

## Tia tu head co bi occupied chan truoc khi cham target_set khong
func _ray_blocked_before_hit(head: int, dir: Dir, target_set: Dictionary, occupied: Dictionary) -> bool:
	var step: Vector2i = DIR_VECTORS[dir]
	var pos: Vector2i = to_xy(head) + step
	while is_inside_pos(pos):
		var idx: int = to_index(pos)
		if target_set.has(idx):
			return false
		if occupied.has(idx):
			return true
		pos += step
	return false

## Chon mui tot nhat trong so cac ung vien (dung cho buoc 1 va fallback)
func _pick_best(candidates: Array, placed: Array, usable_set: Dictionary, occupied: Dictionary, turn_chance: float, require_dependent: bool) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = -1
	var best_len: int = -1
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
		if not _exit_matches_body(body, ex):
			continue
		if _body_self_crosses_ray(body, ex):
			continue
		var dep: int = _block_score(body, placed, usable_set)
		if require_dependent and dep == 0:
			continue
		var score: int = dep * 100 + body.size()
		if score > best_score or (score == best_score and body.size() > best_len):
			best_score = score
			best_len = body.size()
			best = {"cells": body, "exit_dir": ex}
	return best

func _coverage_of(placed: Array) -> int:
	var cov: int = 0
	for arrow in placed:
		var cells: PackedInt32Array = arrow["cells"]
		cov += cells.size()
	return cov

## Ung vien: moi o trong chua occupied + moi huong co tia ra trong
func _candidates_with_clear_ray(usable_set: Dictionary, occupied: Dictionary) -> Array:
	var out: Array = []
	for cell in usable_set.keys():
		if occupied.has(cell):
			continue
		for dir in [Dir.UP, Dir.DOWN, Dir.LEFT, Dir.RIGHT]:
			if not _is_exit_clear(cell, dir, occupied):
				continue
			out.append([cell, dir])
	out.shuffle()
	return out

## Diem phu thuoc: than moi dam vao tia ra cua bao nhieu mui da dat (dung cho fallback)
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

## Xu ly o trong con lai sau khi fill
func _handle_leftovers(placed: Array, usable_set: Dictionary) -> bool:
	var occupied := {}
	for arrow in placed:
		var cells: PackedInt32Array = arrow["cells"]
		for c in cells:
			occupied[c] = true
	var pending: Array = []
	for cell in usable_set.keys():
		if not occupied.has(cell):
			pending.append(cell)
	if pending.is_empty():
		return true
	if pending.size() == 1:
		return true
	if pending.size() == 2:
		var a: int = pending[0]
		var b: int = pending[1]
		var pa: Vector2i = to_xy(a)
		var pb: Vector2i = to_xy(b)
		if absi(pa.x - pb.x) + absi(pa.y - pb.y) != 1:
			return false
		var opt1: PackedInt32Array = PackedInt32Array([a, b])
		var opt2: PackedInt32Array = PackedInt32Array([b, a])
		for trial in [opt1, opt2]:
			var ex: int = _dir_between(trial[0], trial[1])
			if ex < 0:
				continue
			if not _exit_matches_body(trial, ex):
				continue
			if _body_self_crosses_ray(trial, ex):
				continue
			var head: int = trial[trial.size() - 1]
			if not _is_exit_clear(head, ex, occupied):
				continue
			placed.append({"cells": trial, "exit_dir": ex})
			return true
		return false
	return false

func _collect_isolated_cells(placed: Array, usable_set: Dictionary) -> void:
	pass

func _fill_gaps(placed: Array, usable_set: Dictionary) -> void:
	_handle_leftovers(placed, usable_set)

## Mo phong giai: thu lan luot cac mui cho den khi thoat het
func verify_solution(arrows_in_solve_order: Array) -> bool:
	var occupied := {}
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		if cells.size() < 2:
			return false
		if not _exit_matches_body(cells, arrow["exit_dir"]):
			return false
		for c in cells:
			if occupied.has(c):
				return false
			occupied[c] = true

	# Early exit: dem so mui co the thoat ngay
	var free_count: int = 0
	for arrow in arrows_in_solve_order:
		var cells: PackedInt32Array = arrow["cells"]
		var head: int = cells[cells.size() - 1]
		var ex: Dir = arrow["exit_dir"]
		if _is_exit_clear(head, ex, occupied):
			free_count += 1

	# Neu khong co mui nao thoat duoc thi ko hop le
	if free_count == 0:
		return false

	var remaining: Array = arrows_in_solve_order.duplicate()
	var progress: bool = true
	while not remaining.is_empty() and progress:
		progress = false
		for i in range(remaining.size()):
			var arrow: Dictionary = remaining[i]
			var cells: PackedInt32Array = arrow["cells"]
			var head: int = cells[cells.size() - 1]
			var ex: Dir = arrow["exit_dir"]
			if _is_exit_clear(head, ex, occupied):
				for c in cells:
					occupied.erase(c)
				remaining.remove_at(i)
				progress = true
				break
	return remaining.is_empty() and occupied.is_empty()

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
	if cov == total - 1:
		return float(cov) / float(total) >= ratio or ratio <= 0.95
	return float(cov) / float(total) >= ratio

func _shuffle_dirs(dirs: Array) -> void:
	for i in range(dirs.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp: Dir = dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp

# ----------------------------------------------------------------
# Moc than + kiem tra duong ra
# ----------------------------------------------------------------

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

	if path.size() < 2:
		var fail := PackedInt32Array()
		fail.append(head)
		return fail

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

func make_rect_cells(x: int, y: int, w: int, h: int) -> PackedInt32Array:
	var cells := PackedInt32Array()
	for j in range(h):
		for i in range(w):
			var pos := Vector2i(x + i, y + j)
			if is_inside_pos(pos):
				cells.append(to_index(pos))
	return cells
