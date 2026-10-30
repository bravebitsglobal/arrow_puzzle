# level-generator

The user writes in Vietnamese and expects replies in Vietnamese.

This is a Rust CLI that generates arrow-puzzle levels for the Godot game in `../arrow-puzzle`. It is a port of `docs/generate-level.gd`. Output JSON matches `docs/output-sample.json`:
- `{width, height, difficulty 0-2, points}`
- `points` holds one list per arrow, with 1-based `[x, y]` cells ordered tail first, head last.
- The exit direction is the direction of the last segment.

## Build (Windows)

- **Toolchain:** use `stable-x86_64-pc-windows-gnu`. MSVC fails because `link.exe` is broken on the original machine.
- **clap:** it must stay `default-features = false`. Its default features pull in windows-sys, which needs `dlltool.exe`.
- **Rust edition 2024:** `gen` is a reserved keyword, so write `rng.r#gen()`.
- **Build:** `cargo build --release` produces `target/release/level-generator.exe`. See `-h` for options.
  - Main flags: shape, difficulty, `-a` target arrow count, `-p` custom board cells (file or `-` for stdin).
- **Upload:** `--upload <DIR>` sends every `DIR/level_<N>.json` to GameHub as level N.
  - It uses `POST /api/upload/levels` (upsert, max 500 per request, header `x-upload-key`). Batches are also capped at ~900 KB, because nginx returns 413 above 1 MB. API spec: `https://gamehub.bravebits.ai/api/docs-json`.
  - The key comes from `--upload-key` or `$GAMEHUB_UPLOAD_KEY`. Never commit it.
  - `--dry-run` lists the levels without sending anything.
  - HTTP goes through the system `curl`, because TLS crates (ring) need gcc, which this machine lacks.
  - The game reads levels with `GET /api/levels/{id}` and uses `data.points` (see `../arrow-puzzle/scene/global/api.gd`).
- **Challenge:** `--challenge <START_ID> -c <COUNT> --api-key <KEY> [--game-id G]` generates COUNT levels and uploads them as challenge levels START_ID…
  - Each level uses a random large board (`--min-size`..`--max-size`, default 40..50) and a random built-in shape.
  - Files go to `output/challenge/<G>/level_<N>.json`. Default difficulty is hard; `-a` and `--seed` work too.
  - It uses `POST /api/upload/challenges`, the same body as levels. The game reads `GET /api/challenges/daily` or `/api/challenges/levels/{id}`.
  - The upload key decides the game on the server. The upload API has no gameId parameter (only the admin JWT API does), so `--game-id` only names the folder.
  - `--dry-run` generates without uploading.
- **Levels:** `--levels FROM TO --api-key <KEY>` generates main levels FROM..TO and uploads them via `POST /api/upload/levels` (overwrites existing ids; 1–350 are the xlsx levels).
  - Board sides grow linearly with the id from `--size-from` to `--size-to` (aliases of `--min-size`/`--max-size`, default 30..60), each side jittered by ±max(2, span/10). Random built-in shape per level.
  - Files go to `output/levels/level_<N>.json`. Default difficulty is medium; `-d`, `-a`, `--seed`, `--dry-run` work too.
  - Shared code: `run_challenge` and `run_levels` both call `run_batch` in `src/main.rs`.

## Python tooling

- **Packages:** `pip install openpyxl pillow numpy`.
- **Vietnamese output:** set `PYTHONIOENCODING=utf-8` when printing it.
- **Temp files:** Python can't see Git Bash `/tmp`, so put temp files under `target/`.

## 300-level task (done; all 350 rows)

Goal: produce the game's 300 levels from `docs/300level.xlsx`. Its columns are Level, Source, Ghi chú. Source reads like "Level N Lessmore/Easybrain".
- **No note:** clone the level from `docs/lessmore/OG_LevelN.json` or `docs/easybrain/level_NNNN.json`.
- **Note "đổi shape thành X (grid WxH, N arrow)":** build an X-shaped mask and run `level-generator.exe -p board.json -a N`.

Script: `python tools/build_300.py [first last]` (default: all rows). It writes `output/300/level_NNN.json` and checks that every level is solvable.
`python tools/build_300.py --preview` renders every shape mask to `target/shapes.png` for a visual check.

Status (2026-10-09):
- All 350 rows are generated and solvable. Levels 1–30 are unchanged from the trial.
- The levels were uploaded to GameHub as levels 1–350.
- Shape rows are mapped in the `LEVEL_SHAPES` table (level → name, kind, arg). There are three kinds:
  - `fn`: a formula mask.
  - `builtin`: a generator `-s` shape (leaf, gourd, watering-can).
  - `image`: the silhouette of an xlsx picture `xl/media/imageN`.
    - Options: `close` (gap closing), `crop`, `thresh`, `cover`, `stretch`, `mirror`.
- **Grid typo:** if a note's grid is too small for its arrow count (e.g. L68 "34x3"), the source's grid is used.
- **New shape notes:** a note with a grid but no `LEVEL_SHAPES` entry fails loudly; add an entry for it.

Decisions made:
- **Images in the xlsx:** the note text names the shape. A matching xlsx picture was picked by hand for each row where one exists; otherwise the shape is drawn with a formula.
- **Note "8 Easy":** means difficulty easy (0).
- **Note "Hiện tutorial…":** this is game-side only; the level is just cloned.
- **Easybrain:**
  - Coordinates are 1-based.
  - `points` lists polyline corners only; they are expanded into cells.
  - Difficulty 1–4 is clamped to 0–2.
- **Lessmore:**
  - `Indices` are row-major `y*XSize+x`, and `Indices[0]` is the head. They are reversed into tail→head order.
- **Sources our game can't play:** some Lessmore levels (e.g. 40) let an arrow pass over its own body, which our game forbids. These are regenerated on the same cells with the same arrow count.

Open questions for the user:
- **Lessmore Y axis:** it is read top-down. This is unverified, because a vertical mirror is still solvable. If levels look upside down in game, change `load_lessmore`.
- **Shapes not yet approved:** gem (L6), peanut (L10), panda head (L21), pointed shield (L23), panda (L26).

## Obstacle overlay (GDD sheet 07 L1–350 pipeline)

The base levels in `output/300` are BENCHMARK_LOCKED: grid, arrows and cells are never changed. The overlay step only adds obstacles to them.
1. `python scripts/extract_overlay.py ../document/Arrow_Puzzle_GDD_V4.5_Interstitial_Retry_Continue.xlsm docs/overlay_config.json` extracts GDD sheet 06 (counts and N lists per level).
2. `level-generator --overlay output/300 [--seed S]` runs `src/pipeline.rs`. Steps:
   - checksum the base and run the core solver;
   - assign Frozen, Bomb, Lock/Key, Hidden and Crate;
   - check the mix cap and InactiveRatio;
   - run the combined solver;
   - audit the result.
   It writes `output/overlay/level_<N>.json` and `output/overlay/report.json`.
   - The output keeps the base fields and adds `obstacles`: arrow indices into `points`, crates as 1-based `{x, y, n}`, and locks as `{group, key, locked}`.
   - A level that can't pass after 20 retries is reported `FLAG_GD_LOWER_N`, which is the GDD fallback.
- **Solver state:** the state is just the set of removed arrows, because every counter depends only on the removal count. The search branches only while a Bomb is ACTIVE.
- **Playable mask:** it is not stored in the base, so an empty cell counts as playable when it lies inside the shape's row and column spans.
- **CrateMeaningfulUnlock:** it counts plain arrows whose ray passes the crate and that have at most N transitive blockers.
- **Status (2026-10-30):** 225/350 levels pass. All 125 failures are Crate levels: the benchmark boards are ~99% full, so no interior hole has a meaningful ray. GD needs to decide what to do with these.
- **Uploaded (2026-10-30):** levels 1–350 were uploaded from `output/upload350`.
  - That folder holds the 225 overlay levels.
  - The 125 failed Crate levels fall back to their `output/300` base level, with no obstacles.
- **Not done yet:** the Godot game does not implement the obstacles.
