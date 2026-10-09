//! Port of docs/generate-level.gd.
//!
//! Flow:
//! B1: n arrows pointing outward (clear exit ray).
//! B2: for each parent arrow, create a child whose exit ray passes through the parent's body
//!     (child depends on parent -> solve parent first). BFS until nothing more fits.
//! B3: leftover cells: 2 adjacent cells -> 1 arrow, single cell -> skip.
//! B4: verify the level by simulating removal.

use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::{Rng, SeedableRng};
use std::time::Instant;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Dir {
    Up,
    Down,
    Left,
    Right,
}

const ALL_DIRS: [Dir; 4] = [Dir::Up, Dir::Down, Dir::Left, Dir::Right];

impl Dir {
    fn delta(self) -> (i32, i32) {
        match self {
            Dir::Up => (0, -1),
            Dir::Down => (0, 1),
            Dir::Left => (-1, 0),
            Dir::Right => (1, 0),
        }
    }

    fn opposite(self) -> Dir {
        match self {
            Dir::Up => Dir::Down,
            Dir::Down => Dir::Up,
            Dir::Left => Dir::Right,
            Dir::Right => Dir::Left,
        }
    }

    fn turn_left(self) -> Dir {
        match self {
            Dir::Up => Dir::Left,
            Dir::Down => Dir::Right,
            Dir::Left => Dir::Down,
            Dir::Right => Dir::Up,
        }
    }

    fn turn_right(self) -> Dir {
        match self {
            Dir::Up => Dir::Right,
            Dir::Down => Dir::Left,
            Dir::Left => Dir::Up,
            Dir::Right => Dir::Down,
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Difficulty {
    Easy,
    Medium,
    Hard,
}

/// Arrow body; the head is the last cell.
#[derive(Clone, Debug)]
pub struct Arrow {
    pub cells: Vec<usize>,
    pub exit: Dir,
}

struct Params {
    n: usize,
    turn_chance: f64,
    fs_min: usize,
    fs_max: usize,
}

fn params_for(diff: Difficulty) -> Params {
    match diff {
        Difficulty::Easy => Params { n: 3, turn_chance: 0.30, fs_min: 1, fs_max: 2 },
        Difficulty::Medium => Params { n: 2, turn_chance: 0.40, fs_min: 1, fs_max: 3 },
        Difficulty::Hard => Params { n: 1, turn_chance: 0.50, fs_min: 1, fs_max: 3 },
    }
}

struct Board {
    arrows: Vec<Arrow>,
    occupied: Vec<bool>,
    /// Index of the arrow covering each cell (usize::MAX if free).
    owner: Vec<usize>,
    /// Arrows whose exit ray passes through each cell.
    ray_owners: Vec<Vec<usize>>,
    coverage: usize,
}

pub struct LevelGenerator {
    width: i32,
    height: i32,
    usable: Vec<bool>,
    usable_list: Vec<usize>,
    rng: StdRng,

    pub min_arrow_length: usize,
    pub max_arrow_length: usize,
    first_straight_min: usize,
    first_straight_max: usize,
    pub max_board_restarts: usize,
    pub max_generate_ms: u128,
    pub fill_min_ratio: f64,
    pub fill_target_ratio: f64,
    pub fill_max_arrows: usize,
    pub placement_samples: usize,
    pub max_stall_rounds: usize,
    pub max_build_tries: usize,
    /// Desired number of arrows; arrow lengths adapt to it and the closest board wins.
    pub target_arrows: Option<usize>,
}

impl LevelGenerator {
    pub fn new(width: usize, height: usize, usable: Vec<bool>, seed: u64) -> Self {
        assert_eq!(usable.len(), width * height);
        let usable_list = (0..usable.len()).filter(|&i| usable[i]).collect::<Vec<_>>();
        let fill_max_arrows = 250.max(usable_list.len() / 2);
        Self {
            width: width as i32,
            height: height as i32,
            usable,
            usable_list,
            rng: StdRng::seed_from_u64(seed),
            min_arrow_length: 2,
            max_arrow_length: 12,
            first_straight_min: 1,
            first_straight_max: 3,
            max_board_restarts: 80,
            max_generate_ms: 1500,
            fill_min_ratio: 0.88,
            fill_target_ratio: 0.96,
            fill_max_arrows,
            placement_samples: 8,
            max_stall_rounds: 20,
            max_build_tries: 2,
            target_arrows: None,
        }
    }

    pub fn total_usable(&self) -> usize {
        self.usable_list.len()
    }

    fn size(&self) -> usize {
        (self.width * self.height) as usize
    }

    fn xy(&self, cell: usize) -> (i32, i32) {
        (cell as i32 % self.width, cell as i32 / self.width)
    }

    fn step(&self, cell: usize, dir: Dir) -> Option<usize> {
        let (x, y) = self.xy(cell);
        let (dx, dy) = dir.delta();
        let (nx, ny) = (x + dx, y + dy);
        if nx < 0 || ny < 0 || nx >= self.width || ny >= self.height {
            return None;
        }
        Some((ny * self.width + nx) as usize)
    }

    /// Cells on the ray from `head` (exclusive) in `dir` to the grid border.
    fn ray(&self, head: usize, dir: Dir) -> impl Iterator<Item = usize> + '_ {
        std::iter::successors(self.step(head, dir), move |&c| self.step(c, dir))
    }

    fn dir_between(&self, from: usize, to: usize) -> Option<Dir> {
        ALL_DIRS.into_iter().find(|&d| self.step(from, d) == Some(to))
    }

    fn exit_matches_body(&self, body: &[usize], exit: Dir) -> bool {
        body.len() >= 2 && self.dir_between(body[body.len() - 2], body[body.len() - 1]) == Some(exit)
    }

    fn is_exit_clear(&self, head: usize, exit: Dir, occupied: &[bool]) -> bool {
        self.ray(head, exit).all(|c| !occupied[c])
    }

    fn hits_usable_on_ray(&self, head: usize, exit: Dir) -> bool {
        self.ray(head, exit).any(|c| self.usable[c])
    }

    fn body_self_crosses_ray(&self, body: &[usize], exit: Dir) -> bool {
        if body.len() < 2 {
            return false;
        }
        let head = body[body.len() - 1];
        body[..body.len() - 1].iter().any(|&c| self.on_ray(head, exit, c))
    }

    /// Is `cell` on the exit ray from `head`?
    fn on_ray(&self, head: usize, exit: Dir, cell: usize) -> bool {
        let (hx, hy) = self.xy(head);
        let (cx, cy) = self.xy(cell);
        match exit {
            Dir::Up => cx == hx && cy < hy,
            Dir::Down => cx == hx && cy > hy,
            Dir::Left => cy == hy && cx < hx,
            Dir::Right => cy == hy && cx > hx,
        }
    }

    fn body_ok(&self, body: &[usize], exit: Dir) -> bool {
        body.len() >= self.min_arrow_length
            && self.exit_matches_body(body, exit)
            && !self.body_self_crosses_ray(body, exit)
    }

    /// Arrows placed so far plus the "blocks" graph used to keep the level solvable.
    /// Arrow `a` blocks arrow `b` when a cell of `a` lies on `b`'s exit ray.
    fn new_board(&self) -> Board {
        Board {
            arrows: Vec::new(),
            occupied: vec![false; self.size()],
            owner: vec![usize::MAX; self.size()],
            ray_owners: vec![Vec::new(); self.size()],
            coverage: 0,
        }
    }

    fn place(&self, board: &mut Board, arrow: Arrow) {
        let id = board.arrows.len();
        for &c in &arrow.cells {
            board.occupied[c] = true;
            board.owner[c] = id;
        }
        let head = arrow.cells[arrow.cells.len() - 1];
        for c in self.ray(head, arrow.exit) {
            if self.usable[c] {
                board.ray_owners[c].push(id);
            }
        }
        board.coverage += arrow.cells.len();
        board.arrows.push(arrow);
    }

    /// Would placing (body, exit) create a deadlock cycle?
    /// New arrow X is blocked by every arrow on its ray (P) and blocks every arrow whose ray
    /// crosses its body (Q). Since the board is acyclic, a cycle appears iff some arrow in P is
    /// reachable from some arrow in Q.
    fn creates_cycle(&self, board: &Board, body: &[usize], exit: Dir) -> bool {
        let head = body[body.len() - 1];
        let mut is_blocker = vec![false; board.arrows.len()];
        let mut any_blocker = false;
        for c in self.ray(head, exit) {
            if board.occupied[c] {
                is_blocker[board.owner[c]] = true;
                any_blocker = true;
            }
        }
        any_blocker && self.blocked_reaches(board, body, &is_blocker)
    }

    /// Starting from the arrows whose rays cross `cells`, follow "blocks" edges and report
    /// whether any arrow marked in `targets` is reached.
    fn blocked_reaches(&self, board: &Board, cells: &[usize], targets: &[bool]) -> bool {
        let mut visited = vec![false; board.arrows.len()];
        let mut stack: Vec<usize> = Vec::new();
        for &c in cells {
            for &q in &board.ray_owners[c] {
                if !visited[q] {
                    visited[q] = true;
                    stack.push(q);
                }
            }
        }
        while let Some(a) = stack.pop() {
            if targets[a] {
                return true;
            }
            for &c in &board.arrows[a].cells {
                for &n in &board.ray_owners[c] {
                    if !visited[n] {
                        visited[n] = true;
                        stack.push(n);
                    }
                }
            }
        }
        false
    }

    /// Grow arrows backwards from their tails into free neighbouring cells. Head and exit stay
    /// the same, so leftover holes get absorbed without adding arrows.
    fn extend_tails(&self, board: &mut Board) {
        let mut changed = true;
        while changed {
            changed = false;
            for id in 0..board.arrows.len() {
                loop {
                    let arrow = &board.arrows[id];
                    let head = arrow.cells[arrow.cells.len() - 1];
                    let exit = arrow.exit;
                    let tail = arrow.cells[0];
                    let mut targets = vec![false; board.arrows.len()];
                    targets[id] = true;
                    // Prefer the tightest spot so the remaining free area stays in one piece.
                    let next = ALL_DIRS
                        .into_iter()
                        .filter_map(|d| self.step(tail, d))
                        .filter(|&c| self.usable[c] && !board.occupied[c] && !self.on_ray(head, exit, c))
                        .filter(|&c| !self.blocked_reaches(board, &[c], &targets))
                        .min_by_key(|&c| self.free_degree(c, &board.occupied, &[]));
                    let Some(c) = next else { break };
                    board.arrows[id].cells.insert(0, c);
                    board.occupied[c] = true;
                    board.owner[c] = id;
                    board.coverage += 1;
                    changed = true;
                }
            }
        }
    }

    fn free_degree(&self, cell: usize, occupied: &[bool], path: &[usize]) -> usize {
        ALL_DIRS
            .into_iter()
            .filter_map(|d| self.step(cell, d))
            .filter(|&n| self.can_enter(n, occupied, path))
            .count()
    }

    fn acceptable(&self, board: &Board, body: &[usize], exit: Dir) -> bool {
        self.body_ok(body, exit) && !self.creates_cycle(board, body, exit)
    }

    // ----------------------------------------------------------------
    // Main entry
    // ----------------------------------------------------------------

    /// Returns arrows in solve order (parent first), or None if no valid level was found.
    pub fn generate(&mut self, difficulty: Difficulty) -> Option<Vec<Arrow>> {
        let params = params_for(difficulty);
        self.first_straight_min = params.fs_min;
        self.first_straight_max = params.fs_max;

        let total = self.usable_list.len();
        if total == 0 {
            return None;
        }

        // Lower cost is better. Without a target the first board that fills enough wins;
        // with a target, keep searching for the board whose arrow count is closest to it.
        let tolerance = self.target_arrows.map_or(0, |t| (t / 50).max(1));
        let mut best: Option<(f64, Vec<Arrow>)> = None;

        for attempt in 0..10 {
            let t0 = Instant::now();
            for _ in 0..self.max_board_restarts {
                if t0.elapsed().as_millis() > self.max_generate_ms {
                    break;
                }
                let board = self.build_board(&params, total);
                if board.arrows.is_empty() || !self.verify_solution(&board.arrows) {
                    continue;
                }
                let ratio = board.coverage as f64 / total as f64;
                if ratio < self.fill_min_ratio * 0.95 {
                    continue;
                }
                let fill_penalty = (self.fill_min_ratio - ratio).max(0.0);
                let mut arrows = board.arrows;
                if let Some(t) = self.target_arrows {
                    if arrows.len().abs_diff(t) > tolerance {
                        arrows = self.adjust_count(arrows, t);
                    }
                }
                let cost = match self.target_arrows {
                    None if fill_penalty == 0.0 => return Some(arrows),
                    None => fill_penalty,
                    Some(t) => {
                        let diff = arrows.len().abs_diff(t);
                        if diff <= tolerance && fill_penalty == 0.0 {
                            return Some(arrows);
                        }
                        diff as f64 / t as f64 + fill_penalty * 10.0
                    }
                };
                if best.as_ref().map_or(true, |(c, _)| cost < *c) {
                    best = Some((cost, arrows));
                }
            }
            // With a target, spend a few rounds looking for a closer count before settling.
            if best.is_some() && (self.target_arrows.is_none() || attempt >= 2) {
                break;
            }
        }
        best.map(|(_, arrows)| arrows)
    }

    fn build_board(&mut self, params: &Params, total: usize) -> Board {
        let mut best: Option<Board> = None;
        let target = (total as f64 * self.fill_target_ratio).ceil() as usize;
        for _ in 0..self.max_build_tries {
            let attempt = self.try_build_once(params, total);
            if attempt.coverage >= target {
                return attempt;
            }
            if best.as_ref().map_or(true, |b| attempt.coverage > b.coverage) {
                best = Some(attempt);
            }
        }
        best.unwrap_or_else(|| self.new_board())
    }

    fn try_build_once(&mut self, params: &Params, total: usize) -> Board {
        let mut board = self.new_board();

        // --- B1: n outward arrows ---
        for _ in 0..params.n {
            if board.coverage >= total {
                break;
            }
            match self.pick_outward(&board, params.turn_chance) {
                Some(a) => self.place(&mut board, a),
                None => break,
            }
        }

        // --- B2: BFS expansion - child's exit ray passes through parent body ---
        let mut queue: Vec<usize> = (0..board.arrows.len()).collect();
        let mut q_idx = 0;
        let mut stall = 0;
        while board.coverage < total && board.arrows.len() < self.fill_max_arrows {
            if q_idx >= queue.len() {
                stall += 1;
                if stall >= 2 {
                    break;
                }
                queue.shuffle(&mut self.rng);
                q_idx = 0;
                continue;
            }
            let parent = queue[q_idx];
            q_idx += 1;
            if let Some(child) = self.pick_child_blocking(parent, &board, params.turn_chance) {
                stall = 0;
                self.place(&mut board, child);
                queue.push(board.arrows.len() - 1);
            }
        }

        // --- B2b: free fill fallback if BFS was not enough ---
        // Once the target count is reached, absorb free cells into existing tails first.
        let target = self.target_arrows.unwrap_or(usize::MAX);
        stall = 0;
        while board.coverage < total && board.arrows.len() < self.fill_max_arrows {
            if board.arrows.len() >= target {
                self.extend_tails(&mut board);
                if board.coverage >= total {
                    break;
                }
            }
            let cands = self.candidates_with_clear_ray(&board.occupied);
            if cands.is_empty() {
                break;
            }
            match self.pick_best(&cands, &board, params.turn_chance, false) {
                Some(a) => {
                    stall = 0;
                    self.place(&mut board, a);
                }
                None => {
                    stall += 1;
                    if stall >= self.max_stall_rounds {
                        break;
                    }
                }
            }
        }

        // --- B3: leftover cells ---
        self.handle_leftovers(&mut board);
        if self.target_arrows.is_some() {
            self.extend_tails(&mut board);
        }
        board
    }

    /// B1: pick an arrow pointing outward (nothing usable on its exit ray).
    fn pick_outward(&mut self, board: &Board, turn_chance: f64) -> Option<Arrow> {
        let mut cells = self.usable_list.clone();
        cells.shuffle(&mut self.rng);
        let tries = (self.placement_samples * 2).min(cells.len());
        for &head in &cells[..tries] {
            if board.occupied[head] {
                continue;
            }
            for dir in ALL_DIRS {
                if !self.is_exit_clear(head, dir, &board.occupied) || self.hits_usable_on_ray(head, dir) {
                    continue;
                }
                let len = self.sample_len(board);
                let body = self.grow_body(head, dir, len, &board.occupied, turn_chance);
                if self.acceptable(board, &body, dir) {
                    return Some(Arrow { cells: body, exit: dir });
                }
            }
        }
        let cands = self.candidates_with_clear_ray(&board.occupied);
        if cands.is_empty() {
            return None;
        }
        self.pick_best(&cands, board, turn_chance, false)
    }

    /// B2: pick a child whose exit ray hits the parent's body first.
    /// The child is blocked by the parent -> parent must leave before the child can.
    fn pick_child_blocking(&mut self, parent: usize, board: &Board, turn_chance: f64) -> Option<Arrow> {
        let mut cands: Vec<(usize, Dir)> = Vec::new();
        for &cell in &self.usable_list {
            if board.occupied[cell] {
                continue;
            }
            for dir in ALL_DIRS {
                if let Some(first) = self.ray(cell, dir).find(|&c| board.occupied[c]) {
                    if board.owner[first] == parent {
                        cands.push((cell, dir));
                    }
                }
            }
        }
        if cands.is_empty() {
            return None;
        }
        cands.shuffle(&mut self.rng);
        let cap = cands.len().min(self.placement_samples * 2);
        let mut best: Option<Arrow> = None;
        for &(head, dir) in &cands[..cap] {
            let len = self.sample_len(board);
            let body = self.grow_body(head, dir, len, &board.occupied, turn_chance);
            if !self.acceptable(board, &body, dir) {
                continue;
            }
            if best.as_ref().map_or(true, |b| body.len() > b.cells.len()) {
                best = Some(Arrow { cells: body, exit: dir });
            }
        }
        best
    }

    /// Pick the best arrow among sampled candidates (used by B1 and fallback).
    fn pick_best(
        &mut self,
        cands: &[(usize, Dir)],
        board: &Board,
        turn_chance: f64,
        require_dependent: bool,
    ) -> Option<Arrow> {
        let mut best: Option<Arrow> = None;
        let mut best_score: i64 = -1;
        let mut best_len = 0;
        for _ in 0..self.placement_samples {
            let (head, ex) = cands[self.rng.gen_range(0..cands.len())];
            if board.occupied[head] || !self.is_exit_clear(head, ex, &board.occupied) {
                continue;
            }
            let len = self.sample_len(board);
            let body = self.grow_body(head, ex, len, &board.occupied, turn_chance);
            if !self.acceptable(board, &body, ex) {
                continue;
            }
            let dep = self.block_score(&body, &board.arrows);
            if require_dependent && dep == 0 {
                continue;
            }
            let score = (dep * 100 + body.len()) as i64;
            if score > best_score || (score == best_score && body.len() > best_len) {
                best_score = score;
                best_len = body.len();
                best = Some(Arrow { cells: body, exit: ex });
            }
        }
        best
    }

    /// Free cells + every direction whose exit ray is clear.
    fn candidates_with_clear_ray(&mut self, occupied: &[bool]) -> Vec<(usize, Dir)> {
        let mut out = Vec::new();
        for &cell in &self.usable_list {
            if occupied[cell] {
                continue;
            }
            for dir in ALL_DIRS {
                if self.is_exit_clear(cell, dir, occupied) {
                    out.push((cell, dir));
                }
            }
        }
        out.shuffle(&mut self.rng);
        out
    }

    /// Number of placed arrows whose exit ray is crossed by the new body.
    fn block_score(&self, body: &[usize], placed: &[Arrow]) -> usize {
        placed
            .iter()
            .filter(|a| {
                let head = a.cells[a.cells.len() - 1];
                self.ray(head, a.exit).any(|c| self.usable[c] && body.contains(&c))
            })
            .count()
    }

    /// Leftover cells: 2 adjacent free cells -> one 2-cell arrow, a lone cell is skipped.
    fn handle_leftovers(&self, board: &mut Board) {
        for &a in &self.usable_list {
            if board.occupied[a] {
                continue;
            }
            'pair: for d in ALL_DIRS {
                let Some(b) = self.step(a, d) else { continue };
                if !self.usable[b] || board.occupied[b] {
                    continue;
                }
                for trial in [[a, b], [b, a]] {
                    let ex = self.dir_between(trial[0], trial[1]).unwrap();
                    if self.acceptable(board, &trial, ex) {
                        self.place(board, Arrow { cells: trial.to_vec(), exit: ex });
                        break 'pair;
                    }
                }
            }
        }
    }

    /// Nudge the arrow count toward the target: merge an arrow into the one whose tail touches
    /// its head when there are too many, split long arrows when there are too few.
    /// Every step is re-verified, so the level stays solvable.
    fn adjust_count(&self, mut arrows: Vec<Arrow>, target: usize) -> Vec<Arrow> {
        while arrows.len() > target {
            let mut tail_of = vec![usize::MAX; self.size()];
            for (i, a) in arrows.iter().enumerate() {
                tail_of[a.cells[0]] = i;
            }
            let mut merges: Vec<(usize, usize)> = Vec::new();
            for (i, a) in arrows.iter().enumerate() {
                let head = a.cells[a.cells.len() - 1];
                for n in ALL_DIRS.into_iter().filter_map(|d| self.step(head, d)) {
                    let j = tail_of[n];
                    if j != usize::MAX && j != i {
                        merges.push((i, j));
                    }
                }
            }
            merges.sort_by_key(|&(i, j)| arrows[i].cells.len() + arrows[j].cells.len());
            let merged = merges.into_iter().find_map(|(i, j)| {
                let mut cells = arrows[i].cells.clone();
                cells.extend_from_slice(&arrows[j].cells);
                let exit = arrows[j].exit;
                if !self.body_ok(&cells, exit) {
                    return None;
                }
                let mut next: Vec<Arrow> = arrows
                    .iter()
                    .enumerate()
                    .filter(|&(k, _)| k != i && k != j)
                    .map(|(_, a)| a.clone())
                    .collect();
                next.push(Arrow { cells, exit });
                self.verify_solution(&next).then_some(next)
            });
            match merged {
                Some(next) => arrows = next,
                None => break,
            }
        }

        while arrows.len() < target {
            let mut order: Vec<usize> = (0..arrows.len()).filter(|&i| arrows[i].cells.len() >= 4).collect();
            order.sort_by_key(|&i| std::cmp::Reverse(arrows[i].cells.len()));
            let split = order.into_iter().find_map(|i| {
                let cells = &arrows[i].cells;
                let mid = cells.len() / 2;
                // Try split points from the middle outward; both parts need >= 2 cells.
                (0..cells.len()).map(|o| if o % 2 == 0 { mid + o / 2 } else { mid - o / 2 - 1 })
                    .filter(|&k| k >= 2 && k + 2 <= cells.len())
                    .find_map(|k| {
                        let front = cells[..k].to_vec();
                        let exit = self.dir_between(front[k - 2], front[k - 1])?;
                        if !self.body_ok(&front, exit) {
                            return None;
                        }
                        let mut next = arrows.clone();
                        next[i].cells = cells[k..].to_vec();
                        next.push(Arrow { cells: front, exit });
                        self.verify_solution(&next).then_some(next)
                    })
            });
            match split {
                Some(next) => arrows = next,
                None => break,
            }
        }
        arrows
    }

    /// Simulate solving: repeatedly remove any arrow whose exit is clear.
    pub fn verify_solution(&self, arrows: &[Arrow]) -> bool {
        let mut occupied = vec![false; self.size()];
        for a in arrows {
            if a.cells.len() < 2 || !self.exit_matches_body(&a.cells, a.exit) {
                return false;
            }
            for &c in &a.cells {
                if occupied[c] {
                    return false;
                }
                occupied[c] = true;
            }
        }

        let mut remaining: Vec<&Arrow> = arrows.iter().collect();
        loop {
            let free = remaining
                .iter()
                .position(|a| self.is_exit_clear(a.cells[a.cells.len() - 1], a.exit, &occupied));
            match free {
                Some(i) => {
                    for &c in &remaining[i].cells {
                        occupied[c] = false;
                    }
                    remaining.remove(i);
                }
                None => break,
            }
        }
        remaining.is_empty()
    }

    // ----------------------------------------------------------------
    // Body growth
    // ----------------------------------------------------------------

    /// Length to aim for when growing the next arrow.
    /// With a target arrow count, aim at the average length still needed:
    /// remaining cells / remaining arrows (+-30% jitter), so the count converges to the target.
    fn sample_len(&mut self, board: &Board) -> usize {
        let Some(target) = self.target_arrows else {
            return self.rng.gen_range(self.min_arrow_length..=self.max_arrow_length);
        };
        let remaining_cells = self.usable_list.len() - board.coverage;
        let remaining_arrows = target.saturating_sub(board.arrows.len()).max(1);
        let avg = remaining_cells as f64 / remaining_arrows as f64;
        let len = (avg * self.rng.gen_range(0.7..1.3)).round() as usize;
        len.max(self.min_arrow_length)
    }

    /// Grow a body inward from `head`; returned cells are ordered tail -> head.
    fn grow_body(&mut self, head: usize, exit: Dir, target_len: usize, occupied: &[bool], turn_chance: f64) -> Vec<usize> {
        let mut path = vec![head];
        let mut move_dir = exit.opposite();
        // Long bodies (target mode) hug walls/other arrows so they don't trap themselves.
        let compact = target_len > self.max_arrow_length;

        let first_steps = self.rng.gen_range(self.first_straight_min..=self.first_straight_max);
        for _ in 0..first_steps {
            if path.len() >= target_len {
                break;
            }
            match self.step(path[path.len() - 1], move_dir) {
                Some(n) if self.can_enter(n, occupied, &path) => path.push(n),
                _ => break,
            }
        }
        if path.len() < 2 {
            return vec![head];
        }

        while path.len() < target_len {
            let cur = path[path.len() - 1];
            let options: Vec<Dir> = [move_dir, move_dir.turn_left(), move_dir.turn_right()]
                .into_iter()
                .filter(|&d| {
                    self.step(cur, d)
                        .is_some_and(|n| self.can_enter(n, occupied, &path) && !self.on_ray(head, exit, n))
                })
                .collect();
            if options.is_empty() {
                break;
            }
            if compact {
                let degree = |d: Dir| {
                    let n = self.step(cur, d).unwrap();
                    self.free_degree(n, occupied, &path)
                };
                let min = options.iter().map(|&d| degree(d)).min().unwrap();
                let tight: Vec<Dir> = options.iter().copied().filter(|&d| degree(d) == min).collect();
                if !tight.contains(&move_dir) || self.rng.r#gen::<f64>() < turn_chance {
                    move_dir = tight[self.rng.gen_range(0..tight.len())];
                }
                path.push(self.step(cur, move_dir).unwrap());
                continue;
            }
            let has_straight = options.contains(&move_dir);
            let sides: Vec<Dir> = options.iter().copied().filter(|&d| d != move_dir).collect();
            if !sides.is_empty() && (!has_straight || self.rng.r#gen::<f64>() < turn_chance) {
                move_dir = sides[self.rng.gen_range(0..sides.len())];
            } else if !has_straight {
                move_dir = options[self.rng.gen_range(0..options.len())];
            }
            path.push(self.step(cur, move_dir).unwrap());
        }

        path.reverse();
        path
    }

    fn can_enter(&self, cell: usize, occupied: &[bool], path: &[usize]) -> bool {
        self.usable[cell] && !occupied[cell] && !path.contains(&cell)
    }
}
