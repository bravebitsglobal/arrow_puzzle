//! GDD sheet 07 "L1-350 Pipeline": load the locked benchmark base, attach the sheet-06 obstacle
//! overlay (Frozen, Bomb, Lock, Hidden, Crate), check the safety formulas and prove the level with
//! an obstacle-aware solver. The base (grid, arrows, cells) is never changed; when an overlay can't
//! be made to pass, the level is flagged for GD to lower N/count.
//!
//! Rules (sheet 01/04): every valid Arrow removal ticks Frozen/Hidden/Crate N by 1 and every
//! other ACTIVE Bomb by 1. Frozen/Hidden become ACTIVE at N=0, a Crate disappears at N=0, a
//! Locked group opens when its Key is cleared, and a Bomb still on the board at N=0 explodes (fail).
//! All of this depends only on which arrows are removed, so a solver state is the removed set.

use crate::overlay::OverlayConfig;
use rand::Rng;
use rand::seq::SliceRandom;
use serde_json::{Value, json};
use std::collections::HashSet;

const ASSIGN_RETRIES: usize = 20;
const OVERLAY_RETRIES: usize = 20;
const SOLVER_NODE_LIMIT: usize = 200_000;
const INACTIVE_RATIO_MAX: f64 = 0.35;
const CRATE_BLOCK_SHARE_MAX: f64 = 0.40;
const BOMB_SLACK_PREFERRED: i64 = 3;

/// Benchmark base as built by tools/build_300.py: 1-based [x, y] cells, tail first, head last.
pub struct Base {
    pub width: usize,
    pub height: usize,
    pub difficulty: u8,
    pub points: Vec<Vec<[usize; 2]>>,
}

impl Base {
    pub fn from_json(v: &Value) -> Result<Base, String> {
        let dim = |k: &str| v.get(k).and_then(Value::as_u64).map(|n| n as usize).ok_or(format!("missing {k}"));
        let points = serde_json::from_value(v.get("points").cloned().unwrap_or(Value::Null))
            .map_err(|e| format!("invalid points ({e})"))?;
        Ok(Base {
            width: dim("width")?,
            height: dim("height")?,
            difficulty: v.get("difficulty").and_then(Value::as_u64).unwrap_or(1) as u8,
            points,
        })
    }

    /// FNV-1a over the locked fields (grid + every arrow cell).
    pub fn checksum(&self) -> u64 {
        let mut h: u64 = 0xcbf29ce484222325;
        let mut eat = |n: usize| {
            for b in (n as u64).to_le_bytes() {
                h = (h ^ b as u64).wrapping_mul(0x100000001b3);
            }
        };
        eat(self.width);
        eat(self.height);
        for arrow in &self.points {
            eat(arrow.len());
            for &[x, y] in arrow {
                eat(x);
                eat(y);
            }
        }
        h
    }
}

#[derive(Clone)]
pub struct LockGroup {
    pub key: usize,
    pub locked: Vec<usize>,
}

/// Obstacles on one level; arrows are indices into `points`, crates are cells.
#[derive(Clone, Default)]
pub struct Overlay {
    pub frozen: Vec<(usize, u32)>,
    pub bomb: Vec<(usize, u32)>,
    pub locks: Vec<LockGroup>,
    pub hidden: Vec<(usize, u32)>,
    pub crates: Vec<(usize, u32)>,
}

impl Overlay {
    /// One primary state per arrow; a Key also stays a plain arrow.
    fn special(&self, a: usize) -> bool {
        [&self.frozen, &self.bomb, &self.hidden].iter().any(|l| l.iter().any(|&(x, _)| x == a))
            || self.locks.iter().any(|g| g.key == a || g.locked.contains(&a))
    }

    fn locked(&self) -> impl Iterator<Item = (usize, usize)> + '_ {
        self.locks.iter().enumerate().flat_map(|(g, l)| l.locked.iter().map(move |&a| (a, g)))
    }

    fn type_count(&self) -> usize {
        [!self.frozen.is_empty(), !self.bomb.is_empty(), !self.locks.is_empty(), !self.hidden.is_empty(), !self.crates.is_empty()]
            .iter()
            .filter(|&&b| b)
            .count()
    }

    fn inactive_count(&self) -> usize {
        self.frozen.len() + self.hidden.len() + self.locked().count()
    }
}

/// Base geometry plus the blocking graph of the benchmark layout.
pub struct Board {
    width: usize,
    arrows: Vec<Vec<usize>>,
    /// Cells on each arrow's exit ray, head excluded, up to the grid edge.
    rays: Vec<Vec<usize>>,
    owner: Vec<Option<usize>>,
    /// anc[a][b]: b must be removed before a can exit (transitive blockers).
    anc: Vec<Vec<bool>>,
    anc_count: Vec<usize>,
    dependents: Vec<usize>,
    /// Arrows whose exit ray passes each cell.
    ray_hits: Vec<Vec<usize>>,
    playable: Vec<bool>,
}

impl Board {
    /// Step 1/2: load the base and check it is a valid board.
    pub fn new(base: &Base) -> Result<Board, String> {
        let (w, h) = (base.width, base.height);
        let mut owner = vec![None; w * h];
        let mut arrows = Vec::with_capacity(base.points.len());
        for (i, p) in base.points.iter().enumerate() {
            if p.len() < 2 {
                return Err(format!("arrow {i} has fewer than 2 cells"));
            }
            let mut cells = Vec::with_capacity(p.len());
            for &[x, y] in p {
                if x == 0 || y == 0 || x > w || y > h {
                    return Err(format!("arrow {i}: cell [{x}, {y}] is outside the {w}x{h} grid"));
                }
                let c = (y - 1) * w + (x - 1);
                if let Some(o) = owner[c] {
                    return Err(format!("arrows {o} and {i} overlap at [{x}, {y}]"));
                }
                owner[c] = Some(i);
                cells.push(c);
            }
            if p.windows(2).any(|s| s[0][0].abs_diff(s[1][0]) + s[0][1].abs_diff(s[1][1]) != 1) {
                return Err(format!("arrow {i} is not a connected path"));
            }
            arrows.push(cells);
        }

        let n = arrows.len();
        let rays: Vec<Vec<usize>> = arrows.iter().map(|c| ray(w, h, c)).collect();
        let mut blockers = vec![Vec::new(); n];
        let mut ray_hits = vec![Vec::new(); w * h];
        for (i, r) in rays.iter().enumerate() {
            for &c in r {
                ray_hits[c].push(i);
                match owner[c] {
                    Some(o) if o == i => return Err(format!("arrow {i} crosses its own exit ray")),
                    Some(o) if !blockers[i].contains(&o) => blockers[i].push(o),
                    _ => {}
                }
            }
        }
        let anc: Vec<Vec<bool>> = (0..n)
            .map(|a| {
                let mut seen = vec![false; n];
                let mut stack = blockers[a].clone();
                while let Some(b) = stack.pop() {
                    if !seen[b] {
                        seen[b] = true;
                        stack.extend(&blockers[b]);
                    }
                }
                seen
            })
            .collect();
        let anc_count = anc.iter().map(|s| s.iter().filter(|&&b| b).count()).collect();
        let dependents = (0..n).map(|t| (0..n).filter(|&a| a != t && anc[a][t]).count()).collect();

        // Empty cells count as playable when they sit inside the shape's row and column spans.
        let (mut rows, mut cols) = (vec![(usize::MAX, 0); h], vec![(usize::MAX, 0); w]);
        for c in (0..w * h).filter(|&c| owner[c].is_some()) {
            let (x, y) = (c % w, c / w);
            rows[y] = (rows[y].0.min(x), rows[y].1.max(x));
            cols[x] = (cols[x].0.min(y), cols[x].1.max(y));
        }
        let playable = (0..w * h)
            .map(|c| {
                let (x, y) = (c % w, c / w);
                (rows[y].0..=rows[y].1).contains(&x) && (cols[x].0..=cols[x].1).contains(&y)
            })
            .collect();

        Ok(Board { width: w, arrows, rays, owner, anc, anc_count, dependents, ray_hits, playable })
    }

    fn n(&self) -> usize {
        self.arrows.len()
    }

    fn xy(&self, c: usize) -> (usize, usize) {
        (c % self.width + 1, c / self.width + 1)
    }

    // ---------------------------------------------------------------- safety formulas

    /// FrozenPreUnlockSafety = reachable_other_removals_before_target - FrozenN.
    fn frozen_safety(&self, t: usize, n: u32) -> i64 {
        (self.n() - 1 - self.dependents[t]) as i64 - n as i64
    }

    /// HiddenPreRevealSafety = reachable_non_hidden_removals - HiddenN, per Hidden arrow.
    fn hidden_safety(&self, ov: &Overlay) -> Vec<i64> {
        let hidden: Vec<usize> = ov.hidden.iter().map(|h| h.0).collect();
        let reachable = (0..self.n())
            .filter(|&a| !hidden.contains(&a) && !hidden.iter().any(|&h| self.anc[a][h]))
            .count() as i64;
        ov.hidden.iter().map(|&(_, n)| reachable - n as i64).collect()
    }

    /// BombMoveSlack = BombN - min_required_other_removals_before_bomb_can_exit.
    /// The required set is the bomb's blockers, plus Key (and its blockers) of any Locked
    /// blocker; Frozen/Hidden/Crate gates on that chain raise the minimum to their N.
    fn bomb_slack(&self, ov: &Overlay, b: usize, n: u32) -> i64 {
        let mut need = self.anc[b].clone();
        for (a, g) in ov.locked() {
            if need[a] {
                let key = ov.locks[g].key;
                need[key] = true;
                for (x, &y) in need.iter_mut().zip(&self.anc[key]) {
                    *x |= y;
                }
            }
        }
        let mut required = need.iter().filter(|&&x| x).count() as u32;
        let chain = |a: usize| a == b || need[a];
        for &(a, gn) in ov.frozen.iter().chain(&ov.hidden) {
            if chain(a) {
                required = required.max(gn);
            }
        }
        for &(c, cn) in &ov.crates {
            if self.ray_hits[c].iter().any(|&a| chain(a)) {
                required = required.max(cn);
            }
        }
        n as i64 - required as i64
    }

    fn bomb_slacks(&self, ov: &Overlay) -> Vec<i64> {
        ov.bomb.iter().map(|&(b, n)| self.bomb_slack(ov, b, n)).collect()
    }

    /// Share of arrows whose exit ray starts out blocked by a Crate.
    fn crate_block_share(&self, ov: &Overlay) -> f64 {
        let blocked = (0..self.n())
            .filter(|&a| ov.crates.iter().any(|&(c, _)| self.ray_hits[c].contains(&a)))
            .count();
        blocked as f64 / self.n() as f64
    }

    /// CrateMeaningfulUnlock: plain arrows the crate gates that can have every other blocker
    /// removed within N removals, i.e. arrows that become legal the moment the crate breaks
    /// in some reachable state.
    fn crate_unlock(&self, ov: &Overlay, cell: usize, n: u32) -> i64 {
        self.ray_hits[cell].iter().filter(|&&a| !ov.special(a) && self.anc_count[a] <= n as usize).count() as i64
    }

    fn crate_unlocks(&self, ov: &Overlay) -> Vec<i64> {
        ov.crates.iter().map(|&(c, n)| self.crate_unlock(ov, c, n)).collect()
    }

    // ---------------------------------------------------------------- solver

    fn legal(&self, r: &Rules, removed: &[bool], count: usize, a: usize) -> bool {
        !removed[a]
            && r.gate[a] as usize <= count
            && r.lock[a].is_none_or(|g| removed[r.keys[g]])
            && self.rays[a].iter().all(|&c| {
                self.owner[c].is_none_or(|o| removed[o])
                    && r.crate_n[c] as usize <= count
            })
    }

    /// Step 10: find a removal order that clears the board with no booster and no Bomb explosion.
    /// Without an ACTIVE Bomb a removal never hurts (legal moves only grow), so the search only
    /// branches while Bombs are counting down.
    pub fn solve(&self, ov: &Overlay) -> Option<(Vec<usize>, usize)> {
        let rules = Rules::new(self, ov);
        let mut s = Search { removed: vec![false; self.n()], trace: Vec::new(), dead: HashSet::new(), nodes: 0 };
        self.dfs(&rules, &mut s).then(|| (s.trace, s.nodes))
    }

    fn dfs(&self, r: &Rules, s: &mut Search) -> bool {
        let count = s.trace.len();
        if count == self.n() {
            return true;
        }
        s.nodes += 1;
        if s.nodes > SOLVER_NODE_LIMIT {
            return false;
        }
        let active: Vec<(usize, u32)> = r.bombs.iter().filter(|b| !s.removed[b.0]).copied().collect();
        // A Bomb must exit before N removals, and all its remaining blockers must go first.
        for &(b, n) in &active {
            let blockers_left = (0..self.n()).filter(|&a| self.anc[b][a] && !s.removed[a]).count();
            if count + blockers_left >= n as usize {
                return false;
            }
        }
        let key: Vec<u64> = s.removed.chunks(64).map(|ch| ch.iter().fold(0, |k, &x| k << 1 | x as u64)).collect();
        if s.dead.contains(&key) {
            return false;
        }

        let mut moves: Vec<(u64, usize)> = (0..self.n())
            .filter(|&a| self.legal(r, &s.removed, count, a))
            .map(|a| {
                let urgency = active.iter().filter(|b| self.anc[b.0][a]).map(|b| b.1 as u64).min();
                let pri = match (r.bomb[a], urgency) {
                    (Some(n), _) => n as u64,
                    (None, Some(n)) => 1_000 + n as u64,
                    (None, None) => 1_000_000 + self.dependents[a] as u64,
                };
                (pri, a)
            })
            .collect();
        moves.sort();
        if active.is_empty() {
            moves.truncate(1);
        }
        for (_, a) in moves {
            s.removed[a] = true;
            s.trace.push(a);
            if self.dfs(r, s) {
                return true;
            }
            s.trace.pop();
            s.removed[a] = false;
            if s.nodes > SOLVER_NODE_LIMIT {
                return false;
            }
        }
        s.dead.insert(key);
        false
    }

    // ---------------------------------------------------------------- assignment steps 4-8

    /// Free arrows (no state yet), shallowest first so the obstacle actually gates an early move.
    fn shallow_pool(&self, ov: &Overlay, rng: &mut impl Rng, filter: impl Fn(usize) -> bool) -> Vec<usize> {
        let mut pool: Vec<usize> = (0..self.n()).filter(|&a| !ov.special(a) && filter(a)).collect();
        pool.sort_by_key(|&a| self.anc_count[a]);
        pool.truncate(pool.len().div_ceil(3).max(8));
        pool.shuffle(rng);
        pool.truncate(ASSIGN_RETRIES);
        pool
    }

    /// Step 4: Frozen with FrozenPreUnlockSafety >= 1; prefer arrows that block others.
    fn assign_frozen(&self, ov: &mut Overlay, ns: &[u32], rng: &mut impl Rng) -> Result<(), String> {
        for &n in ns {
            let mut pool = self.shallow_pool(ov, rng, |a| self.dependents[a] > 0);
            if pool.is_empty() {
                pool = self.shallow_pool(ov, rng, |_| true);
            }
            let t = pool.into_iter().find(|&a| self.frozen_safety(a, n) >= 1).ok_or(format!("no Frozen target for N={n}"))?;
            ov.frozen.push((t, n));
        }
        Ok(())
    }

    /// Step 5: Bomb on a plain ACTIVE arrow with BombMoveSlack >= 1, preferring >= 3 and a
    /// bomb that has at least one blocker (else it is cleared on the first tap).
    fn assign_bomb(&self, ov: &mut Overlay, ns: &[u32], rng: &mut impl Rng) -> Result<(), String> {
        for &n in ns {
            let mut cands: Vec<(i64, usize)> = (0..self.n())
                .filter(|&a| !ov.special(a))
                .map(|a| (self.bomb_slack(ov, a, n), a))
                .filter(|&(s, _)| s >= 1)
                .collect();
            cands.shuffle(rng);
            let score = |&(s, a): &(i64, usize)| (s < BOMB_SLACK_PREFERRED, self.anc_count[a] == 0);
            cands.sort_by_key(score);
            let &(_, b) = cands.first().ok_or(format!("no Bomb target with slack >= 1 for N={n}"))?;
            ov.bomb.push((b, n));
        }
        Ok(())
    }

    /// Step 6: one Key per group plus its Locked arrows. A Key never depends on any Locked arrow
    /// and no Locked arrow blocks any Key, so every Key can exit without opening a group
    /// (KeyExitReachable, acyclic graph).
    fn assign_lock(&self, ov: &mut Overlay, sizes: &[u32], rng: &mut impl Rng) -> Result<(), String> {
        for &k in sizes {
            let mut placed = false;
            for _ in 0..ASSIGN_RETRIES {
                let locked: Vec<usize> = ov.locked().map(|l| l.0).collect();
                let keys = self.shallow_pool(ov, rng, |a| !locked.iter().any(|&l| self.anc[a][l]));
                let Some(&key) = keys.iter().max_by_key(|&&a| self.anc_count[a].min(4)) else { break };
                let mut trial = ov.clone();
                trial.locks.push(LockGroup { key, locked: Vec::new() });
                let free = self.shallow_pool(&trial, rng, |a| trial.locks.iter().all(|g| !self.anc[g.key][a]));
                if free.len() < k as usize {
                    continue;
                }
                trial.locks.last_mut().unwrap().locked = free[..k as usize].to_vec();
                if self.bomb_slacks(&trial).iter().all(|&s| s >= 1) {
                    *ov = trial;
                    placed = true;
                    break;
                }
            }
            if !placed {
                return Err(format!("no Lock group with {k} locks"));
            }
        }
        Ok(())
    }

    /// Step 7: Hidden with HiddenPreRevealSafety >= 1 for every Hidden arrow.
    fn assign_hidden(&self, ov: &mut Overlay, ns: &[u32], rng: &mut impl Rng) -> Result<(), String> {
        for &n in ns {
            let found = self.shallow_pool(ov, rng, |_| true).into_iter().find(|&a| {
                let mut trial = ov.clone();
                trial.hidden.push((a, n));
                self.hidden_safety(&trial).iter().all(|&s| s >= 1) && self.bomb_slacks(&trial).iter().all(|&s| s >= 1)
            });
            ov.hidden.push((found.ok_or(format!("no Hidden target for N={n}"))?, n));
        }
        Ok(())
    }

    /// Step 8: Crates on empty playable cells with CrateMeaningfulUnlock >= 1, most meaningful
    /// first. Initial crate block share <= 40%.
    fn assign_crate(&self, ov: &mut Overlay, ns: &[u32], rng: &mut impl Rng) -> Result<(), String> {
        for &n in ns {
            let mut cells: Vec<usize> = (0..self.playable.len())
                .filter(|&c| self.playable[c] && self.owner[c].is_none() && self.crate_unlock(ov, c, n) >= 1)
                .filter(|&c| ov.crates.iter().all(|&(x, _)| x != c))
                .collect();
            cells.shuffle(rng);
            cells.sort_by_key(|&c| std::cmp::Reverse(self.crate_unlock(ov, c, n).min(3)));
            let found = cells.into_iter().take(ASSIGN_RETRIES).find(|&c| {
                let mut trial = ov.clone();
                trial.crates.push((c, n));
                self.crate_block_share(&trial) <= CRATE_BLOCK_SHARE_MAX && self.bomb_slacks(&trial).iter().all(|&s| s >= 1)
            });
            ov.crates.push((found.ok_or(format!("no empty playable cell where Crate N={n} is meaningful"))?, n));
        }
        Ok(())
    }

    /// Steps 4-10 once. Returns the overlay, solution trace and solver node count.
    fn attempt(&self, cfg: &OverlayConfig, rng: &mut impl Rng) -> Result<(Overlay, Vec<usize>, usize), String> {
        let mut ov = Overlay::default();
        self.assign_frozen(&mut ov, &cfg.frozen.n_list, rng)?;
        self.assign_bomb(&mut ov, &cfg.bomb.n_list, rng)?;
        self.assign_lock(&mut ov, &cfg.lock.locks_per_group, rng)?;
        self.assign_hidden(&mut ov, &cfg.hidden.n_list, rng)?;
        self.assign_crate(&mut ov, &cfg.crates.n_list, rng)?;

        // Step 9: mix cap + InactiveRatio.
        let types = ov.type_count();
        if types > cfg.max_types as usize || (cfg.forced_tutorial.is_some() && types != 1) {
            return Err(format!("{types} obstacle types, level allows {}", cfg.max_types));
        }
        let inactive = ov.inactive_count() as f64 / self.n() as f64;
        if inactive > INACTIVE_RATIO_MAX {
            return Err(format!("InactiveRatio {:.0}% > 35%", inactive * 100.0));
        }

        // Step 10: combined solver; later assignments must not have made a crate cosmetic.
        let (trace, nodes) = self.solve(&ov).ok_or("combined solver found no win")?;
        if let Some(c) = self.crate_unlocks(&ov).iter().position(|&u| u < 1) {
            let (x, y) = self.xy(ov.crates[c].0);
            return Err(format!("crate at [{x}, {y}] unlocks nothing"));
        }
        Ok((ov, trace, nodes))
    }
}

/// Per-arrow view of an overlay for the solver.
struct Rules {
    /// Frozen/Hidden N (0 = no gate).
    gate: Vec<u32>,
    lock: Vec<Option<usize>>,
    keys: Vec<usize>,
    bomb: Vec<Option<u32>>,
    bombs: Vec<(usize, u32)>,
    /// Crate N per cell (0 = no crate).
    crate_n: Vec<u32>,
}

impl Rules {
    fn new(board: &Board, ov: &Overlay) -> Rules {
        let n = board.n();
        let mut r = Rules {
            gate: vec![0; n],
            lock: vec![None; n],
            keys: ov.locks.iter().map(|g| g.key).collect(),
            bomb: vec![None; n],
            bombs: ov.bomb.clone(),
            crate_n: vec![0; board.owner.len()],
        };
        for &(a, gn) in ov.frozen.iter().chain(&ov.hidden) {
            r.gate[a] = gn;
        }
        for (a, g) in ov.locked() {
            r.lock[a] = Some(g);
        }
        for &(b, bn) in &ov.bomb {
            r.bomb[b] = Some(bn);
        }
        for &(c, cn) in &ov.crates {
            r.crate_n[c] = cn;
        }
        r
    }
}

struct Search {
    removed: Vec<bool>,
    trace: Vec<usize>,
    dead: HashSet<Vec<u64>>,
    nodes: usize,
}

fn ray(w: usize, h: usize, cells: &[usize]) -> Vec<usize> {
    let (head, prev) = (cells[cells.len() - 1], cells[cells.len() - 2]);
    let (dx, dy) = ((head % w) as i64 - (prev % w) as i64, (head / w) as i64 - (prev / w) as i64);
    let (mut x, mut y) = ((head % w) as i64, (head / w) as i64);
    let mut out = Vec::new();
    loop {
        x += dx;
        y += dy;
        if x < 0 || y < 0 || x >= w as i64 || y >= h as i64 {
            return out;
        }
        out.push(y as usize * w + x as usize);
    }
}

/// Result of the pipeline for one level: the final level JSON (when it passed) and its
/// generation_result report row.
pub struct Outcome {
    pub level: Option<Value>,
    pub report: Value,
}

/// Run steps 1-11 for one level. `cfg` is None when sheet 06 has no row for it.
pub fn run_level(id: u32, base: &Base, cfg: Option<&OverlayConfig>, rng: &mut impl Rng) -> Outcome {
    let fail = |status: &str, reason: String| Outcome {
        level: None,
        report: json!({"level": id, "status": status, "reason": reason}),
    };
    // Steps 1-2: locked base must load and be solvable on its own.
    let checksum = base.checksum();
    let board = match Board::new(base) {
        Ok(b) => b,
        Err(e) => return fail("CONTENT_ERROR", format!("benchmark base invalid: {e}")),
    };
    if board.solve(&Overlay::default()).is_none() {
        return fail("CONTENT_ERROR", "benchmark base fails the core solver".into());
    }
    // Step 3: overlay row; missing is only allowed before the first obstacle (L16).
    let cfg = match cfg {
        Some(c) => c.clone(),
        None if id < 16 => OverlayConfig { level: id, ..Default::default() },
        None => return fail("CONTENT_ERROR", "no sheet-06 overlay row".into()),
    };
    if let Err(e) = cfg.check() {
        return fail("CONTENT_ERROR", format!("overlay config incomplete: {e}"));
    }

    // Steps 4-10 with retries; the base is never touched.
    let mut last_err = String::new();
    for attempt in 1..=OVERLAY_RETRIES {
        let (ov, trace, nodes) = match board.attempt(&cfg, rng) {
            Ok(r) => r,
            Err(e) => {
                last_err = e;
                continue;
            }
        };
        // Step 11: audit. Base fields must be unchanged; outliers go to manual review.
        if base.checksum() != checksum {
            return fail("CONTENT_ERROR", "benchmark base changed during overlay".into());
        }
        let bomb_slack = board.bomb_slacks(&ov);
        let mut review = Vec::new();
        if bomb_slack.iter().any(|&s| s < BOMB_SLACK_PREFERRED) {
            review.push("bomb_slack_below_preferred");
        }
        let report = json!({
            "level": id,
            "status": "OK",
            "role": cfg.role,
            "attempts": attempt,
            "benchmark_checksum": format!("{checksum:016x}"),
            "arrow_count": board.n(),
            "obstacle_types": ov.type_count(),
            "inactive_ratio": ov.inactive_count() as f64 / board.n() as f64,
            "frozen_safety": ov.frozen.iter().map(|&(a, n)| board.frozen_safety(a, n)).collect::<Vec<_>>(),
            "bomb_slack": bomb_slack,
            "hidden_safety": board.hidden_safety(&ov),
            "crate_unlock": board.crate_unlocks(&ov),
            "crate_block_share": board.crate_block_share(&ov),
            "solver_nodes": nodes,
            "solution": trace,
            "review": review,
        });
        return Outcome { level: Some(level_json(id, base, &board, &cfg, &ov, checksum)), report };
    }
    fail("FLAG_GD_LOWER_N", format!("overlay failed {OVERLAY_RETRIES} attempts, last: {last_err}"))
}

fn level_json(id: u32, base: &Base, board: &Board, cfg: &OverlayConfig, ov: &Overlay, checksum: u64) -> Value {
    let counted = |l: &[(usize, u32)]| l.iter().map(|&(a, n)| json!({"arrow": a, "n": n})).collect::<Vec<_>>();
    let crates: Vec<Value> = ov
        .crates
        .iter()
        .map(|&(c, n)| {
            let (x, y) = board.xy(c);
            json!({"x": x, "y": y, "n": n})
        })
        .collect();
    let locks: Vec<Value> = ov
        .locks
        .iter()
        .enumerate()
        .map(|(g, l)| json!({"group": g, "key": l.key, "locked": l.locked}))
        .collect();
    json!({
        "level": id,
        "width": base.width,
        "height": base.height,
        "difficulty": base.difficulty,
        "points": base.points,
        "role": cfg.role,
        "tutorial": cfg.forced_tutorial,
        "benchmark_checksum": format!("{checksum:016x}"),
        "obstacles": {
            "frozen": counted(&ov.frozen),
            "bomb": counted(&ov.bomb),
            "lock": locks,
            "hidden": counted(&ov.hidden),
            "crate": crates,
        },
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use rand::SeedableRng;

    /// 3x4 box of up-pointing arrows: 0 is blocked by 1, 3 is blocked by 4, 1/2/4 are free.
    fn base() -> Base {
        Base {
            width: 3,
            height: 4,
            difficulty: 1,
            points: vec![
                vec![[1, 4], [1, 3]],
                vec![[1, 2], [1, 1]],
                vec![[2, 4], [2, 3], [2, 2]],
                vec![[3, 4], [3, 3]],
                vec![[3, 2], [3, 1]],
            ],
        }
    }

    #[test]
    fn base_solves() {
        let b = Board::new(&base()).unwrap();
        let (trace, _) = b.solve(&Overlay::default()).unwrap();
        assert_eq!(trace.len(), 5);
    }

    #[test]
    fn bomb_explodes_when_blocked_too_long() {
        let b = Board::new(&base()).unwrap();
        // Arrow 0 is blocked by arrow 1: one removal needed, so N=1 explodes and N=2 passes.
        let ov = |n| Overlay { bomb: vec![(0, n)], ..Default::default() };
        assert!(b.solve(&ov(1)).is_none());
        assert!(b.solve(&ov(2)).is_some());
        assert_eq!(b.bomb_slack(&ov(2), 0, 2), 1);
    }

    #[test]
    fn frozen_waits_for_removals() {
        let b = Board::new(&base()).unwrap();
        let ov = Overlay { frozen: vec![(1, 3)], ..Default::default() };
        let (trace, _) = b.solve(&ov).unwrap();
        assert!(trace.iter().position(|&a| a == 1).unwrap() >= 3);
        // Arrow 1 blocks arrow 0, so 3 others are reachable: safety 3 - 3 = 0.
        assert_eq!(b.frozen_safety(1, 3), 0);
    }

    #[test]
    fn lock_opens_after_key() {
        let b = Board::new(&base()).unwrap();
        let ov = Overlay { locks: vec![LockGroup { key: 2, locked: vec![4] }], ..Default::default() };
        let (trace, _) = b.solve(&ov).unwrap();
        let pos = |x| trace.iter().position(|&a| a == x).unwrap();
        assert!(pos(2) < pos(4));
    }

    #[test]
    fn pipeline_on_tutorial_config() {
        let cfg = OverlayConfig {
            level: 16,
            forced_tutorial: Some("Frozen".into()),
            frozen: crate::overlay::Counted { count: 1, n_list: vec![2] },
            max_types: 1,
            ..Default::default()
        };
        let mut rng = rand::rngs::StdRng::seed_from_u64(1);
        let out = run_level(16, &base(), Some(&cfg), &mut rng);
        assert_eq!(out.report["status"], "OK", "{}", out.report);
    }
}
