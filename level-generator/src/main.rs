mod generator;
mod shapes;
mod upload;

use clap::{Parser, ValueEnum};
use generator::{Difficulty, LevelGenerator};
use rand::seq::SliceRandom;
use rand::{Rng, SeedableRng};
use serde::{Deserialize, Serialize};
use shapes::Shape;
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Clone, Copy, ValueEnum)]
enum DifficultyArg {
    Easy,
    Medium,
    Hard,
}

#[derive(Parser)]
#[command(
    about = "Generate arrow puzzle levels as JSON",
    after_help = "\
Shapes by board size (min of width/height):
  any   square, circle, triangle, diamond
  >= 9  trapezoid, pentagon, hexagon, shield, leaf, popsicle
  >= 14 flower, star, gourd
  >= 18 watering-can, hand

Custom board (--points): JSON with 1-based [x, y] cells, either
  [[1, 1], [2, 1], ...]
  or {\"width\": 10, \"height\": 10, \"points\": [[1, 1], [2, 1], ...]}
  WIDTH/HEIGHT may be omitted; they fall back to the file's values or the max x/y.

Output: <output>/level_<w>x<h>_<shape>_<seed>.json

Upload (--upload DIR): sends every DIR/level_<N>.json (or <N>.json) to GameHub as level N
  via POST <api-url>/api/upload/levels (upsert, 500 per request). The key comes from
  --upload-key (alias --api-key) or the GAMEHUB_UPLOAD_KEY environment variable. Needs curl on PATH.

Challenge (--challenge START_ID -c COUNT): generates COUNT levels on random large boards
  (--min-size..--max-size per side, default 40..50) with random shapes, saves them to
  <output>/challenge/<game-id>/level_<N>.json and uploads them as challenge levels
  START_ID..START_ID+COUNT-1 via POST <api-url>/api/upload/challenges (upsert).
  The upload key decides which game they go to; --game-id only names the output folder.
  Default difficulty is hard. --dry-run generates and saves without uploading.

Examples:
  level-generator 10 10                     one 10x10 level, random simple shape
  level-generator 24 24 -s star -d hard     24x24 star, hard difficulty
  level-generator 30 30 -a 80 -c 5          5 levels with ~80 arrows each
  level-generator 20 25 --seed 42 -o out    reproducible level written to ./out
  level-generator -p board.json -a 40       level on cells from another tool
  cat board.json | level-generator -p -     same, reading the cells from stdin
  level-generator --upload output/300       upload level_001.json.. as levels 1..
  level-generator --challenge 1 -c 30 --api-key KEY --game-id arrow
                                            30 random large challenge levels as ids 1..30"
)]
struct Cli {
    /// Level width (cells). Optional with --points
    width: Option<usize>,
    /// Level height (cells). Optional with --points
    height: Option<usize>,
    /// JSON file with the board cells (1-based [x, y]) instead of a generated shape; '-' = stdin
    #[arg(short, long, conflicts_with = "shape")]
    points: Option<PathBuf>,
    /// Force a shape (square, circle, triangle, diamond, trapezoid, pentagon, hexagon, shield,
    /// leaf, popsicle, flower, star, gourd, watering-can, hand). Random by size if omitted.
    #[arg(short, long)]
    shape: Option<String>,
    /// Difficulty (written to JSON as 0/1/2) [default: medium, hard with --challenge]
    #[arg(short, long, value_enum)]
    difficulty: Option<DifficultyArg>,
    /// Random seed (random if omitted)
    #[arg(long)]
    seed: Option<u64>,
    /// Desired number of arrows per level (the generator gets as close as it can)
    #[arg(short, long)]
    arrows: Option<usize>,
    /// Number of levels to generate
    #[arg(short, long, default_value_t = 1)]
    count: usize,
    /// Output directory
    #[arg(short, long, default_value = "output")]
    output: PathBuf,
    /// Upload the level_<N>.json files in this directory to GameHub instead of generating
    #[arg(long, value_name = "DIR", conflicts_with_all = ["width", "height", "points", "shape"])]
    upload: Option<PathBuf>,
    /// GameHub base URL for --upload
    #[arg(long, default_value = "https://gamehub.bravebits.ai")]
    api_url: String,
    /// Upload key (x-upload-key) for --upload/--challenge; defaults to $GAMEHUB_UPLOAD_KEY
    #[arg(long, alias = "api-key")]
    upload_key: Option<String>,
    /// With --upload: only list what would be sent. With --challenge: generate and save, no upload
    #[arg(long)]
    dry_run: bool,
    /// Generate COUNT (-c) random large levels and upload them as challenge levels from this id
    #[arg(long, value_name = "START_ID", conflicts_with_all = ["width", "height", "points", "shape", "upload"])]
    challenge: Option<u32>,
    /// Game id for --challenge (names the output folder; the upload key picks the game on the server)
    #[arg(long, requires = "challenge")]
    game_id: Option<String>,
    /// Smallest board side for --challenge
    #[arg(long, default_value_t = 40)]
    min_size: usize,
    /// Largest board side for --challenge
    #[arg(long, default_value_t = 50)]
    max_size: usize,
}

/// --points input: a bare list of cells, or an object that also carries the board size.
#[derive(Deserialize)]
#[serde(untagged)]
enum PointsInput {
    List(Vec<[usize; 2]>),
    Board {
        width: Option<usize>,
        height: Option<usize>,
        points: Vec<[usize; 2]>,
    },
}

#[derive(Serialize)]
struct LevelJson {
    width: usize,
    height: usize,
    difficulty: u8,
    points: Vec<Vec<[usize; 2]>>,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    if let Some(dir) = &cli.upload {
        return run_upload(&cli, dir);
    }
    if let Some(start) = cli.challenge {
        return run_challenge(&cli, start);
    }
    let custom =match &cli.points {
        Some(path) => match load_points(path, cli.width, cli.height) {
            Ok(board) => Some(board),
            Err(e) => {
                eprintln!("{e}");
                return ExitCode::FAILURE;
            }
        },
        None => None,
    };
    let (width, height) = match (&custom, cli.width, cli.height) {
        (Some((w, h, _)), _, _) => (*w, *h),
        (None, Some(w), Some(h)) => (w, h),
        _ => {
            eprintln!("WIDTH and HEIGHT are required unless --points is given (see -h)");
            return ExitCode::FAILURE;
        }
    };
    if custom.is_none() && (width < 3 || height < 3) {
        eprintln!("width and height must be >= 3");
        return ExitCode::FAILURE;
    }
    let forced = match cli.shape.as_deref().map(|n| (n, Shape::from_name(n))) {
        Some((n, None)) => {
            eprintln!("unknown shape '{n}'");
            return ExitCode::FAILURE;
        }
        Some((_, s)) => s,
        None => None,
    };
    let (difficulty, difficulty_id) = difficulty(cli.difficulty.unwrap_or(DifficultyArg::Medium));
    if let Err(e) = std::fs::create_dir_all(&cli.output) {
        eprintln!("cannot create {}: {e}", cli.output.display());
        return ExitCode::FAILURE;
    }

    let mut rng = match cli.seed {
        Some(s) => rand::rngs::StdRng::seed_from_u64(s),
        None => rand::rngs::StdRng::from_entropy(),
    };
    let candidates = shapes::shapes_for_size(width, height);
    let mut failures = 0;

    for _ in 0..cli.count {
        let (name, mask) = match &custom {
            Some((_, _, mask)) => ("custom", mask.clone()),
            None => {
                let shape = forced.unwrap_or_else(|| *candidates.choose(&mut rng).unwrap());
                (shape.name(), shapes::build_mask(shape, width, height))
            }
        };
        println!("Shape: {name} ({width}x{height})\n{}", shapes::render_ascii(&mask, width));

        let target_arrows = clamp_target(cli.arrows, &mask);
        let Some((seed, arrows, total)) = generate(width, height, &mask, difficulty, target_arrows, &mut rng) else {
            eprintln!("Failed to generate a valid level for shape {name}");
            failures += 1;
            continue;
        };

        let covered: usize = arrows.iter().map(|a| a.cells.len()).sum();
        let level = to_json(width, height, difficulty_id, &arrows);

        let path = cli.output.join(format!("level_{width}x{height}_{name}_{seed}.json"));
        if let Err(e) = write_json(&path, &level) {
            eprintln!("cannot write {}: {e}", path.display());
            return ExitCode::FAILURE;
        }
        if let Some(t) = target_arrows {
            println!("-> target {t} arrows, got {} (diff {})", arrows.len(), arrows.len().abs_diff(t));
        }
        println!(
            "-> {} arrows, fill {}/{} ({:.1}%), saved {}\n",
            arrows.len(),
            covered,
            total,
            covered as f64 * 100.0 / total as f64,
            path.display()
        );
    }

    if failures > 0 {
        ExitCode::FAILURE
    } else {
        ExitCode::SUCCESS
    }
}

fn difficulty(arg: DifficultyArg) -> (Difficulty, u8) {
    match arg {
        DifficultyArg::Easy => (Difficulty::Easy, 0),
        DifficultyArg::Medium => (Difficulty::Medium, 1),
        DifficultyArg::Hard => (Difficulty::Hard, 2),
    }
}

/// Every arrow needs at least 2 cells, so at most usable/2 arrows fit.
fn clamp_target(arrows: Option<usize>, mask: &[bool]) -> Option<usize> {
    let usable = mask.iter().filter(|&&b| b).count();
    arrows.map(|a| {
        let clamped = a.clamp(1, (usable / 2).max(1));
        if clamped != a {
            eprintln!("arrow count {a} not possible for {usable} cells, using {clamped}");
        }
        clamped
    })
}

/// Up to 5 attempts with fresh seeds; returns (seed, arrows, usable cell count).
fn generate(
    width: usize,
    height: usize,
    mask: &[bool],
    difficulty: Difficulty,
    target_arrows: Option<usize>,
    rng: &mut impl Rng,
) -> Option<(u64, Vec<generator::Arrow>, usize)> {
    for _ in 0..5 {
        let seed: u64 = rng.r#gen();
        let mut level_gen = LevelGenerator::new(width, height, mask.to_vec(), seed);
        level_gen.target_arrows = target_arrows;
        if let Some(arrows) = level_gen.generate(difficulty) {
            return Some((seed, arrows, level_gen.total_usable()));
        }
    }
    None
}

fn to_json(width: usize, height: usize, difficulty: u8, arrows: &[generator::Arrow]) -> LevelJson {
    LevelJson {
        width,
        height,
        difficulty,
        // 1-based [x, y]; tail first, head last.
        points: arrows
            .iter()
            .map(|a| a.cells.iter().map(|&c| [c % width + 1, c / width + 1]).collect())
            .collect(),
    }
}

fn upload_key(cli: &Cli) -> Option<String> {
    cli.upload_key.clone().or_else(|| std::env::var("GAMEHUB_UPLOAD_KEY").ok())
}

/// --challenge: generate cli.count random large levels and upload them as challenge levels start...
fn run_challenge(cli: &Cli, start: u32) -> ExitCode {
    let last = start as u64 + cli.count as u64 - 1;
    if start == 0 || cli.count == 0 || last > 1_000_000 {
        eprintln!("challenge ids must be within 1..=1000000 (got {start}..{last})");
        return ExitCode::FAILURE;
    }
    if cli.min_size < 3 || cli.min_size > cli.max_size {
        eprintln!("need 3 <= --min-size <= --max-size");
        return ExitCode::FAILURE;
    }
    // Check the key before spending time on generation.
    let key = upload_key(cli);
    if key.is_none() && !cli.dry_run {
        eprintln!("missing upload key: pass --api-key/--upload-key or set GAMEHUB_UPLOAD_KEY");
        return ExitCode::FAILURE;
    }
    let dir = cli.output.join("challenge").join(cli.game_id.as_deref().unwrap_or("default"));
    if let Err(e) = std::fs::create_dir_all(&dir) {
        eprintln!("cannot create {}: {e}", dir.display());
        return ExitCode::FAILURE;
    }
    let (difficulty, difficulty_id) = difficulty(cli.difficulty.unwrap_or(DifficultyArg::Hard));
    let mut rng = match cli.seed {
        Some(s) => rand::rngs::StdRng::seed_from_u64(s),
        None => rand::rngs::StdRng::from_entropy(),
    };

    let mut levels = Vec::new();
    for id in start..=last as u32 {
        // A shape can fail on an unlucky board; retry with a new size and shape.
        let mut generated = None;
        for _ in 0..5 {
            let width = rng.gen_range(cli.min_size..=cli.max_size);
            let height = rng.gen_range(cli.min_size..=cli.max_size);
            let shape = *shapes::shapes_for_size(width, height).choose(&mut rng).unwrap();
            let mask = shapes::build_mask(shape, width, height);
            let target = clamp_target(cli.arrows, &mask);
            if let Some((_, arrows, total)) = generate(width, height, &mask, difficulty, target, &mut rng) {
                generated = Some((shape, width, height, arrows, total));
                break;
            }
        }
        let Some((shape, width, height, arrows, total)) = generated else {
            eprintln!("challenge {id}: failed to generate a level");
            return ExitCode::FAILURE;
        };
        let level = to_json(width, height, difficulty_id, &arrows);
        let path = dir.join(format!("level_{id}.json"));
        if let Err(e) = write_json(&path, &level) {
            eprintln!("cannot write {}: {e}", path.display());
            return ExitCode::FAILURE;
        }
        let covered: usize = arrows.iter().map(|a| a.cells.len()).sum();
        println!(
            "challenge {id}: {} {width}x{height}, {} arrows, fill {:.1}%",
            shape.name(),
            arrows.len(),
            covered as f64 * 100.0 / total as f64
        );
        levels.push((id, serde_json::to_value(&level).unwrap()));
    }
    println!("saved {} levels to {}", levels.len(), dir.display());
    if cli.dry_run {
        return ExitCode::SUCCESS;
    }
    match upload::upload(&cli.api_url, &key.unwrap(), "challenges", &levels) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("upload failed: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run_upload(cli: &Cli, dir: &PathBuf) -> ExitCode {
    let levels = match upload::collect(dir) {
        Ok(l) if l.is_empty() => {
            eprintln!("no level_<N>.json files in {}", dir.display());
            return ExitCode::FAILURE;
        }
        Ok(l) => l,
        Err(e) => {
            eprintln!("{e}");
            return ExitCode::FAILURE;
        }
    };
    let ids: Vec<String> = levels.iter().map(|l| l.0.to_string()).collect();
    println!("{} levels in {}: {}", levels.len(), dir.display(), ids.join(", "));
    if cli.dry_run {
        return ExitCode::SUCCESS;
    }
    let Some(key) = upload_key(cli) else {
        eprintln!("missing upload key: pass --upload-key or set GAMEHUB_UPLOAD_KEY");
        return ExitCode::FAILURE;
    };
    match upload::upload(&cli.api_url, &key, "levels", &levels) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("upload failed: {e}");
            ExitCode::FAILURE
        }
    }
}

/// Read the board cells for --points and build a width*height mask.
/// CLI width/height win over the file's, which win over the max x/y of the points.
fn load_points(path: &PathBuf, cli_w: Option<usize>, cli_h: Option<usize>) -> Result<(usize, usize, Vec<bool>), String> {
    let text = if path.as_os_str() == "-" {
        std::io::read_to_string(std::io::stdin()).map_err(|e| format!("cannot read stdin: {e}"))?
    } else {
        std::fs::read_to_string(path).map_err(|e| format!("cannot read {}: {e}", path.display()))?
    };
    let input: PointsInput = serde_json::from_str(&text).map_err(|e| {
        format!("invalid points JSON ({e}); expected [[x, y], ...] or {{\"width\", \"height\", \"points\"}}")
    })?;
    let (file_w, file_h, points) = match input {
        PointsInput::List(points) => (None, None, points),
        PointsInput::Board { width, height, points } => (width, height, points),
    };
    if points.len() < 2 {
        return Err("points must contain at least 2 cells".into());
    }
    if let Some(&[x, y]) = points.iter().find(|p| p[0] == 0 || p[1] == 0) {
        return Err(format!("point [{x}, {y}] is invalid: coordinates are 1-based"));
    }
    let width = cli_w.or(file_w).unwrap_or_else(|| points.iter().map(|p| p[0]).max().unwrap());
    let height = cli_h.or(file_h).unwrap_or_else(|| points.iter().map(|p| p[1]).max().unwrap());
    let mut mask = vec![false; width * height];
    for &[x, y] in &points {
        if x > width || y > height {
            return Err(format!("point [{x}, {y}] is outside the {width}x{height} board"));
        }
        mask[(y - 1) * width + (x - 1)] = true;
    }
    Ok((width, height, mask))
}

fn write_json(path: &PathBuf, level: &LevelJson) -> std::io::Result<()> {
    let mut buf = Vec::new();
    let mut ser = serde_json::Serializer::with_formatter(&mut buf, serde_json::ser::PrettyFormatter::with_indent(b"    "));
    level.serialize(&mut ser)?;
    std::fs::write(path, buf)
}
