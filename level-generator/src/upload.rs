//! Upload level files to GameHub (POST /api/upload/levels, header x-upload-key).
//! HTTP goes through the system `curl` so no TLS crate (and C toolchain) is needed.

use serde_json::{Value, json};
use std::io::Write;
use std::path::Path;
use std::process::{Command, Stdio};

/// The API accepts at most this many levels per bulk request.
const BATCH: usize = 500;
/// The server's nginx rejects bigger bodies with 413 (default limit is 1 MB).
const MAX_BODY: usize = 900_000;

/// Collect `<dir>/level_<N>.json` (or `<N>.json`) files as (levelId, data), sorted by id.
pub fn collect(dir: &Path) -> Result<Vec<(u32, Value)>, String> {
    let entries = std::fs::read_dir(dir).map_err(|e| format!("cannot read {}: {e}", dir.display()))?;
    let mut levels = Vec::new();
    for entry in entries.flatten() {
        let path = entry.path();
        if path.extension().is_none_or(|e| e != "json") {
            continue;
        }
        let Some(id) = level_id(&path) else {
            eprintln!("skip {}: name is not level_<N>.json", path.display());
            continue;
        };
        let text = std::fs::read_to_string(&path).map_err(|e| format!("cannot read {}: {e}", path.display()))?;
        let data: Value = serde_json::from_str(&text).map_err(|e| format!("{}: invalid JSON ({e})", path.display()))?;
        if !data.get("points").is_some_and(Value::is_array) {
            return Err(format!("{}: missing \"points\" array", path.display()));
        }
        levels.push((id, data));
    }
    levels.sort_by_key(|l| l.0);
    if let Some(w) = levels.windows(2).find(|w| w[0].0 == w[1].0) {
        return Err(format!("level {} appears twice in {}", w[0].0, dir.display()));
    }
    Ok(levels)
}

fn level_id(path: &Path) -> Option<u32> {
    let stem = path.file_stem()?.to_str()?;
    let digits = stem.strip_prefix("level_").unwrap_or(stem);
    digits.parse().ok().filter(|&n| (1..=1_000_000).contains(&n))
}

pub fn upload(api_url: &str, key: &str, levels: &[(u32, Value)]) -> Result<(), String> {
    let url = format!("{}/api/upload/levels", api_url.trim_end_matches('/'));
    let items: Vec<(u32, String)> =
        levels.iter().map(|(id, data)| (*id, json!({"levelId": id, "data": data}).to_string())).collect();
    let mut start = 0;
    while start < items.len() {
        // Grow the batch until the count or body size limit (always at least one level).
        let mut end = start + 1;
        let mut size = items[start].1.len();
        while end < items.len() && end - start < BATCH && size + items[end].1.len() + 1 <= MAX_BODY {
            size += items[end].1.len() + 1;
            end += 1;
        }
        let chunk = &items[start..end];
        let parts: Vec<&str> = chunk.iter().map(|i| i.1.as_str()).collect();
        let body = format!("{{\"levels\":[{}]}}", parts.join(","));
        let response = post(&url, key, &body)?;
        println!("uploaded levels {}..{} ({}): {response}", chunk[0].0, chunk[chunk.len() - 1].0, chunk.len());
        start = end;
    }
    Ok(())
}

/// POST JSON (body via stdin, so size is not limited by the command line) and return the response body.
fn post(url: &str, key: &str, body: &str) -> Result<String, String> {
    let mut child = Command::new("curl")
        .args(["-sS", "-X", "POST", url, "-H", "Content-Type: application/json"])
        .args(["-H", &format!("x-upload-key: {key}")])
        .args(["--data-binary", "@-", "-w", "\n%{http_code}"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("cannot run curl: {e}"))?;
    child.stdin.take().unwrap().write_all(body.as_bytes()).map_err(|e| format!("curl stdin: {e}"))?;
    let out = child.wait_with_output().map_err(|e| format!("curl: {e}"))?;
    if !out.status.success() {
        return Err(format!("curl failed: {}", String::from_utf8_lossy(&out.stderr).trim()));
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let (resp, code) = text.rsplit_once('\n').unwrap_or(("", &text));
    match code.trim().parse::<u16>() {
        Ok(c) if (200..300).contains(&c) => Ok(resp.trim().to_string()),
        _ => Err(format!("HTTP {}: {}", code.trim(), resp.trim())),
    }
}
