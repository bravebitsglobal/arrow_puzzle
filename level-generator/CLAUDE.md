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
