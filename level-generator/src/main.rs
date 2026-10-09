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
  --upload-key or the GAMEHUB_UPLOAD_KEY environment variable. Needs curl on PATH.

Examples:
  level-generator 10 10                     one 10x10 level, random simple shape
  level-generator 24 24 -s star -d hard     24x24 star, hard difficulty
  level-generator 30 30 -a 80 -c 5          5 levels with ~80 arrows each
  level-generator 20 25 --seed 42 -o out    reproducible level written to ./out
  level-generator -p board.json -a 40       level on cells from another tool
  cat board.json | level-generator -p -     same, reading the cells from stdin
  level-generator --upload output/300       upload level_001.json.. as levels 1.."
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
    /// Difficulty (written to JSON as 0/1/2)
    #[arg(short, long, value_enum, default_value = "medium")]
    difficulty: DifficultyArg,
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
    /// Upload key (x-upload-key) for --upload; defaults to $GAMEHUB_UPLOAD_KEY
    #[arg(long)]
    upload_key: Option<String>,
    /// With --upload: only list what would be sent
    #[arg(long, requires = "upload")]
    dry_run: bool,
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
    let (difficulty, difficulty_id) = match cli.difficulty {
        DifficultyArg::Easy => (Difficulty::Easy, 0),
        DifficultyArg::Medium => (Difficulty::Medium, 1),
        DifficultyArg::Hard => (Difficulty::Hard, 2),
    };
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

        // Every arrow needs at least 2 cells, so at most usable/2 arrows fit.
        let usable = mask.iter().filter(|&&b| b).count();
        let target_arrows = cli.arrows.map(|a| {
            let clamped = a.clamp(1, (usable / 2).max(1));
            if clamped != a {
                eprintln!("arrow count {a} not possible for {usable} cells, using {clamped}");
            }
            clamped
        });

        let mut result = None;
        for _ in 0..5 {
            let seed: u64 = rng.r#gen();
            let mut level_gen = LevelGenerator::new(width, height, mask.clone(), seed);
            level_gen.target_arrows = target_arrows;
            if let Some(arrows) = level_gen.generate(difficulty) {
                result = Some((seed, arrows, level_gen.total_usable()));
                break;
            }
        }
        let Some((seed, arrows, total)) = result else {
            eprintln!("Failed to generate a valid level for shape {name}");
            failures += 1;
            continue;
        };

        let covered: usize = arrows.iter().map(|a| a.cells.len()).sum();
        let level = LevelJson {
            width,
            height,
            difficulty: difficulty_id,
            // 1-based [x, y]; tail first, head last.
            points: arrows
                .iter()
                .map(|a| a.cells.iter().map(|&c| [c % width + 1, c / width + 1]).collect())
                .collect(),
        };

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
    let Some(key) = cli.upload_key.clone().or_else(|| std::env::var("GAMEHUB_UPLOAD_KEY").ok()) else {
        eprintln!("missing upload key: pass --upload-key or set GAMEHUB_UPLOAD_KEY");
        return ExitCode::FAILURE;
    };
    match upload::upload(&cli.api_url, &key, &levels) {
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
