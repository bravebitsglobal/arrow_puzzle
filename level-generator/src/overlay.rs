//! Obstacle overlay config for L1-350 (GDD sheet "06 Obstacle Overlay 1-350").
//! The JSON comes from `scripts/extract_overlay.py`.

use serde::Deserialize;
use std::collections::HashMap;
use std::path::Path;

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Counted {
    pub count: u32,
    pub n_list: Vec<u32>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct LockConfig {
    pub groups: u32,
    pub locks_per_group: Vec<u32>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct OverlayConfig {
    pub level: u32,
    #[serde(default)]
    pub role: String,
    pub forced_tutorial: Option<String>,
    pub frozen: Counted,
    pub bomb: Counted,
    pub lock: LockConfig,
    pub hidden: Counted,
    #[serde(rename = "crate")]
    pub crates: Counted,
    pub max_types: u32,
}

impl OverlayConfig {
    /// Step 3 "Config complete": every count matches its N list.
    pub fn check(&self) -> Result<(), String> {
        let lists = [
            ("Frozen", self.frozen.count, self.frozen.n_list.len()),
            ("Bomb", self.bomb.count, self.bomb.n_list.len()),
            ("Lock", self.lock.groups, self.lock.locks_per_group.len()),
            ("Hidden", self.hidden.count, self.hidden.n_list.len()),
            ("Crate", self.crates.count, self.crates.n_list.len()),
        ];
        for (name, count, len) in lists {
            if count as usize != len {
                return Err(format!("{name} count {count} but {len} values in its list"));
            }
        }
        if self.lock.locks_per_group.contains(&0) {
            return Err("Lock group with 0 locks".into());
        }
        Ok(())
    }
}

#[derive(Deserialize)]
struct OverlayFile {
    levels: Vec<OverlayConfig>,
}

pub fn load(path: &Path) -> Result<HashMap<u32, OverlayConfig>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
    let file: OverlayFile =
        serde_json::from_str(&text).map_err(|e| format!("{}: invalid overlay config ({e})", path.display()))?;
    Ok(file.levels.into_iter().map(|c| (c.level, c)).collect())
}
