"""Build levels from docs/300level.xlsx.

Rows without a shape note are cloned from docs/lessmore or docs/easybrain.
Rows whose note asks for a new shape ("grid WxH, N arrow, đổi shape thành ...") get a mask
(from LEVEL_SHAPES: a formula, a built-in generator shape, or an image embedded in the xlsx)
and are generated with level-generator.exe.

Usage: python tools/build_300.py [first] [last]     (default: every row)
       python tools/build_300.py --preview [first] [last]   (only render shape masks to target/shapes.png)
"""
import json
import re
import subprocess
import sys
import tempfile
import zipfile
from io import BytesIO
from pathlib import Path

import numpy as np
import openpyxl
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"
XLSX = DOCS / "300level.xlsx"
OUT = ROOT / "output" / "300"
EXE = ROOT / "target" / "release" / "level-generator.exe"


# ----------------------------------------------------------------
# Output / validation
# ----------------------------------------------------------------

def solvable(width, height, arrows):
    """arrows: lists of 1-based (x, y), tail first, head last."""
    owner = {}
    for i, a in enumerate(arrows):
        for c in a:
            if c in owner or not (1 <= c[0] <= width and 1 <= c[1] <= height):
                return False
            owner[c] = i
    alive = set(range(len(arrows)))
    progress = True
    while alive and progress:
        progress = False
        for i in list(alive):
            a = arrows[i]
            (x0, y0), (x1, y1) = a[-2], a[-1]
            dx, dy = x1 - x0, y1 - y0
            x, y = x1 + dx, y1 + dy
            free = True
            while 1 <= x <= width and 1 <= y <= height:
                o = owner.get((x, y))
                if o is not None and o in alive:
                    free = False
                    break
                x, y = x + dx, y + dy
            if free:
                alive.remove(i)
                progress = True
    return not alive


def write_level(path, width, height, difficulty, arrows):
    level = {"width": width, "height": height, "difficulty": difficulty,
             "points": [[list(c) for c in a] for a in arrows]}
    path.write_text(json.dumps(level, indent=4), encoding="utf-8")


# ----------------------------------------------------------------
# Source loaders -> (width, height, difficulty, arrows tail->head, 1-based)
# ----------------------------------------------------------------

def load_lessmore(n):
    d = json.loads((DOCS / "lessmore" / f"OG_Level{n}.json").read_text())
    w, h = d["XSize"], d["YSize"]
    arrows = []
    for a in d["Arrows"]:
        # Indices are row-major (y * XSize + x) and Indices[0] is the head (X, Y), so reverse.
        cells = [(i % w + 1, i // w + 1) for i in reversed(a["Indices"])]
        arrows.append(cells)
    return w, h, None, arrows


def load_easybrain(n):
    d = json.loads((DOCS / "easybrain" / f"level_{n:04d}.json").read_text())
    arrows = []
    for a in d["arrows"]:
        pts = a["points"]
        cells = [tuple(pts[0])]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            dx, dy = (x1 > x0) - (x1 < x0), (y1 > y0) - (y1 < y0)
            x, y = x0, y0
            while (x, y) != (x1, y1):
                x, y = x + dx, y + dy
                cells.append((x, y))
        arrows.append(cells)
    return d["width"], d["height"], d.get("difficulty"), arrows


def load_raw(source):
    m = re.search(r"(\d+)\s*(lessmore|easybrain)", source, re.I)
    if not m:
        raise ValueError(f"cannot parse source '{source}'")
    n, kind = int(m.group(1)), m.group(2).lower()
    return (load_lessmore if kind == "lessmore" else load_easybrain)(n)


def load_source(source):
    w, h, diff, arrows = load_raw(source)
    if diff is not None:
        diff = min(diff, 2)  # easybrain uses 1-4, we use 0-2
    # Head is the last point; if that does not solve, the source stores it the other way round.
    if not solvable(w, h, arrows):
        flipped = [a[::-1] for a in arrows]
        # Neither works: e.g. lessmore lets an arrow slide over its own body, our game does not.
        arrows = flipped if solvable(w, h, flipped) else None
    return w, h, diff, arrows


# ----------------------------------------------------------------
# Formula shapes. contains(u, v), u/v in [0, 1] over the whole grid, v down.
# ----------------------------------------------------------------

def circle(u, v, cx, cy, r):
    return (u - cx) ** 2 + (v - cy) ** 2 <= r * r


def ellipse(u, v, cx, cy, rx, ry):
    return ((u - cx) / rx) ** 2 + ((v - cy) / ry) ** 2 <= 1


def rect(u, v, x0, y0, x1, y1):
    return x0 <= u <= x1 and y0 <= v <= y1


def capsule(u, v, a, b, r):
    dx, dy = b[0] - a[0], b[1] - a[1]
    t = max(0.0, min(1.0, ((u - a[0]) * dx + (v - a[1]) * dy) / (dx * dx + dy * dy)))
    return circle(u, v, a[0] + t * dx, a[1] + t * dy, r)


def in_polygon(u, v, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > v) != (yj > v) and u < (xj - xi) * (v - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def gem(u, v):
    # Cut gemstone: flat table on top, crown, pointed pavilion at the bottom.
    return in_polygon(u, v, [(0.25, 0.0), (0.75, 0.0), (1.0, 0.32), (0.5, 1.0), (0.0, 0.32)])


def peanut(u, v):
    # Two lobes with a narrow waist, slightly offset like a real peanut shell.
    return (ellipse(u, v, 0.52, 0.26, 0.46, 0.26) or ellipse(u, v, 0.48, 0.74, 0.5, 0.26)
            or ellipse(u, v, 0.5, 0.5, 0.33, 0.14))


def panda_head(u, v):
    ears = circle(u, v, 0.17, 0.17, 0.17) or circle(u, v, 0.83, 0.17, 0.17)
    face = ellipse(u, v, 0.5, 0.58, 0.48, 0.42)
    return ears or face


def pointed_shield(u, v):
    # Pyramid-like top peak, straight sides, long pointed bottom.
    return in_polygon(u, v, [(0.5, 0.0), (1.0, 0.18), (1.0, 0.55), (0.5, 1.0), (0.0, 0.55), (0.0, 0.18)])


def panda_body(u, v):
    ears = circle(u, v, 0.27, 0.07, 0.09) or circle(u, v, 0.73, 0.07, 0.09)
    head = ellipse(u, v, 0.5, 0.25, 0.3, 0.22)
    body = ellipse(u, v, 0.5, 0.66, 0.4, 0.3)
    arms = ellipse(u, v, 0.14, 0.58, 0.14, 0.09) or ellipse(u, v, 0.86, 0.58, 0.14, 0.09)
    legs = ellipse(u, v, 0.27, 0.9, 0.17, 0.1) or ellipse(u, v, 0.73, 0.9, 0.17, 0.1)
    return ears or head or body or arms or legs


def full(u, v):
    return True


def oval(u, v):
    return ellipse(u, v, 0.5, 0.5, 0.5, 0.5)


def triangle(u, v):
    return in_polygon(u, v, [(0.5, 0.0), (1.0, 1.0), (0.0, 1.0)])


def rhombus(u, v):
    return abs(u - 0.5) + abs(v - 0.5) <= 0.5


def half_moon(u, v):
    return ellipse(u, v, 0.5, 1.0, 0.5, 1.0)


def split_rect(u, v):
    return not 0.485 <= u <= 0.515


def letter_n(u, v):
    return u <= 0.28 or u >= 0.72 or in_polygon(u, v, [(0.0, 0.0), (0.3, 0.0), (1.0, 1.0), (0.7, 1.0)])


def snowman(u, v):
    hat = rect(u, v, 0.36, 0.0, 0.64, 0.08) or rect(u, v, 0.28, 0.07, 0.72, 0.1)
    return (hat or ellipse(u, v, 0.5, 0.2, 0.2, 0.11) or ellipse(u, v, 0.5, 0.44, 0.3, 0.17)
            or ellipse(u, v, 0.5, 0.77, 0.42, 0.23))


def suitcase(u, v):
    handle = rect(u, v, 0.33, 0.0, 0.67, 0.16) and not rect(u, v, 0.43, 0.07, 0.57, 0.16)
    return handle or rect(u, v, 0.0, 0.16, 1.0, 0.96) or rect(u, v, 0.08, 0.96, 0.2, 1) or rect(u, v, 0.8, 0.96, 0.92, 1)


def vase(u, v):
    return (rect(u, v, 0.28, 0.0, 0.72, 0.05) or rect(u, v, 0.37, 0.05, 0.63, 0.3)
            or ellipse(u, v, 0.5, 0.6, 0.48, 0.34) or rect(u, v, 0.28, 0.88, 0.72, 1.0))


def v_sign(u, v):
    fingers = capsule(u, v, (0.42, 0.55), (0.24, 0.07), 0.09) or capsule(u, v, (0.58, 0.55), (0.76, 0.07), 0.09)
    thumb = capsule(u, v, (0.3, 0.72), (0.5, 0.58), 0.08)
    return fingers or thumb or ellipse(u, v, 0.5, 0.75, 0.3, 0.25)


# ----------------------------------------------------------------
# Image shapes: silhouette of a picture embedded in the xlsx (xl/media/imageN.png).
# ----------------------------------------------------------------

_media = {}


def media(n):
    if not _media:
        with zipfile.ZipFile(XLSX) as z:
            for name in z.namelist():
                m = re.fullmatch(r"xl/media/image(\d+)\.\w+", name)
                if m:
                    _media[int(m.group(1))] = z.read(name)
    return Image.open(BytesIO(_media[n]))


def silhouette(n, close=70, crop=None, thresh=40):
    """Boolean pixel mask of the main object: anything unlike the border colors, holes filled.
    close: gap-closing kernel is image size / close (smaller = fills more of open line art).
    crop: optional (x0, y0, x1, y1) fractions of the picture to keep.
    thresh: color distance from the background that counts as the object."""
    im = media(n).convert("RGBA")
    if crop:
        im = im.crop(tuple(round(f * d) for f, d in zip(crop, im.size * 2)))
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    im = Image.alpha_composite(bg, im).convert("RGB")
    im.thumbnail((400, 400))
    a = np.asarray(im).astype(int)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    # Background palette: border colors covering >= 20% of the border (handles checkerboards,
    # ignores objects that touch the edge).
    q = border // 24
    keys, counts = np.unique(q, axis=0, return_counts=True)
    palette = [border[(q == k).all(axis=1)].mean(axis=0) for k, c in zip(keys, counts) if c >= 0.2 * len(border)]
    dist = np.min([np.abs(a - p).max(axis=2) for p in palette], axis=0)
    fg = Image.fromarray(((dist > thresh) * 255).astype(np.uint8))
    # Close gaps in line art, fill everything not reachable from outside, then shrink back.
    k = max(3, (min(im.size) // close) | 1)
    closed = fg.filter(ImageFilter.MaxFilter(k))
    padded = Image.new("L", (closed.width + 2, closed.height + 2), 0)
    padded.paste(closed, (1, 1))
    ImageDraw.floodfill(padded, (0, 0), 128)
    inside = Image.fromarray(((np.asarray(padded)[1:-1, 1:-1] != 128) * 255).astype(np.uint8))
    return inside.filter(ImageFilter.MinFilter(k))


def image_points(spec, w, h):
    n, opts = (spec, {}) if isinstance(spec, int) else spec
    opts = dict(opts)
    cover = opts.pop("cover", 0.5)  # share of a cell the picture must fill; lower keeps thin parts
    stretch = opts.pop("stretch", 1.0)  # allowed vertical stretch when the picture is wider than the grid
    mirror = opts.pop("mirror", False)  # symmetric picture: OR with its mirror image
    sil = silhouette(n, **opts)
    if mirror:
        box = sil.getbbox()
        sil = sil.crop(box)
        sil = Image.fromarray(np.maximum(np.asarray(sil), np.asarray(sil)[:, ::-1]))
    box = sil.getbbox()
    sil = sil.crop(box)
    s = min(w / sil.width, h / sil.height)
    sw, sh = max(1, round(sil.width * s)), max(1, round(min(h, sil.height * s * stretch)))
    cells = np.asarray(sil.resize((sw, sh), Image.BOX)) >= 255 * cover
    grid = np.zeros((h, w), bool)
    ox, oy = (w - sw) // 2, (h - sh) // 2
    grid[oy:oy + sh, ox:ox + sw] = cells
    return [[int(x) + 1, int(y) + 1] for y, x in zip(*np.nonzero(drop_specks(grid)))]


def drop_specks(grid):
    """Remove components smaller than 10% of the largest one (stray decorations, watermarks)."""
    h, w = grid.shape
    comp = -np.ones((h, w), int)
    sizes = []
    for y0, x0 in zip(*np.nonzero(grid)):
        if comp[y0, x0] >= 0:
            continue
        cid, stack, size = len(sizes), [(y0, x0)], 0
        comp[y0, x0] = cid
        while stack:
            y, x = stack.pop()
            size += 1
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and grid[ny, nx] and comp[ny, nx] < 0:
                    comp[ny, nx] = cid
                    stack.append((ny, nx))
        sizes.append(size)
    if not sizes:
        return grid
    keep = {i for i, s in enumerate(sizes) if s >= max(4, 0.1 * max(sizes))}
    return np.isin(comp, list(keep))


# level -> (name, kind, arg). kind: "fn" formula, "builtin" generator -s shape,
# "image" xlsx media number (or (number, silhouette options)).
LEVEL_SHAPES = {
    6: ("gem", "fn", gem), 10: ("peanut", "fn", peanut), 21: ("panda-head", "fn", panda_head),
    23: ("pointed-shield", "fn", pointed_shield), 26: ("panda", "fn", panda_body),
    32: ("deer-head", "image", (7, {"close": 10})), 38: ("snowman", "fn", snowman), 41: ("leaf", "builtin", "leaf"),
    43: ("suitcase", "fn", suitcase), 44: ("gourd", "builtin", "gourd"),
    46: ("watering-can", "builtin", "watering-can"), 48: ("vase", "fn", vase), 52: ("square", "fn", full),
    53: ("butterfly", "image", (2, {"close": 16, "crop": (0, 0, 0.9, 1), "mirror": True})), 55: ("circle", "fn", oval), 56: ("v-sign", "fn", v_sign),
    59: ("mushroom", "image", 3), 61: ("coffee-cup", "image", 4), 64: ("oval", "fn", oval),
    66: ("pumpkin", "image", 8), 68: ("circle", "fn", oval), 72: ("square", "fn", full),
    73: ("clover", "image", 9), 79: ("robot", "image", 10), 80: ("cake", "image", 11),
    83: ("book", "image", 13), 86: ("lantern", "image", 12), 88: ("soap-bottle", "image", 14),
    89: ("circle", "fn", oval), 90: ("petals", "image", 15), 92: ("circle-pattern", "image", 16),
    93: ("elephant", "image", 17), 94: ("fish", "image", (6, {"close": 25, "thresh": 90})), 95: ("rectangle", "fn", full),
    96: ("ice-cream-cup", "image", (5, {"close": 25, "thresh": 90})), 98: ("ice-cream-cone", "image", 18), 99: ("heart-pattern", "image", 19),
    101: ("flower", "image", 20), 104: ("square-pattern", "image", 21), 105: ("oval-pattern", "image", 22),
    107: ("drop", "image", 23), 108: ("yin-yang", "image", 24), 110: ("squirrel", "image", (1, {"close": 25, "thresh": 90})),
    115: ("split-rectangle", "fn", split_rect), 116: ("wine-bottle", "image", 25), 117: ("gold-ingot", "image", 26),
    119: ("tv", "image", 27), 122: ("hat", "image", 29), 124: ("cat", "image", (30, {"close": 10})), 125: ("oval", "fn", oval),
    126: ("teapot", "image", 31), 127: ("square", "fn", full), 129: ("circle-pattern", "image", 32),
    132: ("triangle", "fn", triangle), 133: ("star-4", "image", 33), 136: ("dumbbell", "image", (34, {"stretch": 2.0})),
    137: ("maple-leaf", "image", 35), 139: ("hammer", "image", 36), 143: ("eye", "image", 37),
    144: ("lightning", "image", 38), 146: ("castle", "image", 39), 147: ("flower-pattern", "image", 40),
    150: ("castle-flag", "image", 41), 151: ("owl", "image", 42), 152: ("square", "fn", full),
    155: ("boot-flowers", "image", 43), 156: ("wings", "image", (44, {"crop": (0, 0.2, 0.8, 1)})), 161: ("rectangle", "fn", full),
    162: ("square", "fn", full), 165: ("flame", "image", 45), 169: ("lotus", "image", 46),
    175: ("guitar", "image", 47), 182: ("rectangle", "fn", full), 186: ("umbrella", "image", 48),
    188: ("beer", "image", 49), 189: ("rectangle", "fn", full), 193: ("whale", "image", 50),
    196: ("car", "image", 51), 202: ("saxophone", "image", 52), 203: ("bat", "image", (53, {"stretch": 2.0, "cover": 0.35})),
    204: ("bow", "image", 54), 207: ("tulip", "image", 55), 211: ("circle", "fn", oval),
    213: ("half-moon", "fn", half_moon), 216: ("oval", "fn", oval), 217: ("frog", "image", 56),
    219: ("oval", "fn", oval), 220: ("circle", "fn", oval), 223: ("mango", "image", (57, {"crop": (0, 0, 0.85, 0.95)})),
    226: ("cupcake", "image", 59), 230: ("popsicle", "image", 61), 234: ("crab", "image", 62),
    235: ("rhombus", "fn", rhombus), 236: ("question-mark", "image", 63), 238: ("raspberry", "image", 58),
    239: ("smiley", "image", 64), 242: ("bird", "image", 65), 244: ("lollipop", "image", 60),
    246: ("turtle", "image", 66), 249: ("hedgehog", "image", 67), 254: ("banana", "image", 68),
    256: ("strawberry", "image", 69), 262: ("avocado", "image", 70), 279: ("letter-n", "fn", letter_n),
    283: ("witch-hat", "image", (71, {"crop": (0, 0, 0.8, 1)})), 292: ("star-6", "image", 72), 297: ("crescent", "image", 73),
    298: ("eagle", "image", 74), 303: ("finger-heart", "image", (75, {"close": 20})), 305: ("penguin", "image", 76),
    316: ("twitter-bird", "image", 77), 319: ("fox", "image", 78), 323: ("hot-air-balloon", "image", 79),
    325: ("palm-trees", "image", (80, {"cover": 0.3, "stretch": 1.8})), 327: ("alarm-clock", "image", 81), 331: ("clock-tower", "image", 82),
    335: ("rocking-horse", "image", (83, {"cover": 0.25})), 338: ("spinning-top", "image", 84), 344: ("statue-of-liberty", "image", 85),
    349: ("coffee-steam", "image", 86),
}


def shape_points(level, w, h):
    """Board cells for a shape level, or None for built-in generator shapes."""
    name, kind, arg = LEVEL_SHAPES[level]
    if kind == "builtin":
        return None
    if kind == "image":
        return image_points(arg, w, h)
    return [[x + 1, y + 1] for y in range(h) for x in range(w) if arg((x + 0.5) / w, (y + 0.5) / h)]


def parse_note(note):
    """'grid WxH, N arrow' (typos like 'gid', 'arrrow', 'line' included) -> (w, h, n) or None."""
    grid = re.search(r"(\d+)\s*x\s*(\d+)", note)
    count = re.search(r"(\d+)\s*(?:a+r+o+w+|line)", note, re.I)
    if not (grid and count):
        return None
    return int(grid.group(1)), int(grid.group(2)), int(count.group(1))


def render(pts, w, h):
    s = {tuple(p) for p in pts}
    return "\n".join("".join("#" if (x, y) in s else "." for x in range(1, w + 1)) for y in range(1, h + 1))


# ----------------------------------------------------------------
# Main
# ----------------------------------------------------------------

def run_generator(level, args, arrows, diff, out_path, board=None):
    with tempfile.TemporaryDirectory(dir=ROOT / "target") as tmp:
        tmp = Path(tmp)
        if board is not None:
            (tmp / "board.json").write_text(json.dumps(board))
            args = ["-p", str(tmp / "board.json")] + args
        # Fixed seed per level so reruns are reproducible.
        cmd = [str(EXE), *args, "-a", str(arrows), "-d", ["easy", "medium", "hard"][diff],
               "--seed", str(level), "-o", str(tmp / "out")]
        res = subprocess.run(cmd, capture_output=True, text=True)
        files = list((tmp / "out").glob("*.json")) if (tmp / "out").exists() else []
        if res.returncode != 0 or not files:
            raise RuntimeError(f"generator failed: {res.stderr.strip()}")
        out_path.write_text(files[0].read_text(encoding="utf-8"), encoding="utf-8")
    return len(json.loads(out_path.read_text())["points"])


def shape_grid(level, note, source):
    w, h, arrows = parse_note(note)
    sw, sh, _, _ = load_raw(source)
    if w * h < 2 * arrows:  # typo in the sheet (e.g. "34x3"): fall back to the source grid
        w, h = sw, sh
    return w, h, arrows


def generate_shape(level, note, source, diff, out_path):
    w, h, arrows = shape_grid(level, note, source)
    name, kind, arg = LEVEL_SHAPES[level]
    if kind == "builtin":
        got = run_generator(level, ["-s", arg, str(w), str(h)], arrows, diff, out_path)
        return f"generated {name} {w}x{h}, target {arrows} arrows -> {got}"
    pts = shape_points(level, w, h)
    got = run_generator(level, [], arrows, diff, out_path, {"width": w, "height": h, "points": pts})
    return f"generated {name} {w}x{h}, {len(pts)} cells, target {arrows} arrows -> {got}"


def rows(first, last):
    ws = openpyxl.load_workbook(XLSX).active
    for row in ws.iter_rows(min_row=2, values_only=True):
        level, source, note = row[0], row[1], (row[2] or "").strip()
        if isinstance(level, int) and first <= level <= last:
            yield level, source, note


def preview(first, last):
    """Render every shape mask into one image for a visual check."""
    tiles = []
    for level, source, note in rows(first, last):
        if level not in LEVEL_SHAPES or LEVEL_SHAPES[level][1] == "builtin":
            continue
        w, h, _ = shape_grid(level, note, source)
        tile = Image.new("L", (w, h), 0)
        for x, y in shape_points(level, w, h):
            tile.putpixel((x - 1, y - 1), 255)
        tiles.append((f"L{level} {LEVEL_SHAPES[level][0]}", tile.resize((w * 3, h * 3), Image.NEAREST)))
    cols, cw, ch = 10, 160, 200
    sheet = Image.new("L", (cols * cw, ((len(tiles) + cols - 1) // cols) * ch), 40)
    draw = ImageDraw.Draw(sheet)
    for i, (label, tile) in enumerate(tiles):
        x, y = (i % cols) * cw, (i // cols) * ch
        sheet.paste(tile, (x + 2, y + 14))
        draw.text((x + 2, y + 1), label, fill=200)
    sheet.save(ROOT / "target" / "shapes.png")
    print(f"{len(tiles)} shapes -> target/shapes.png")


def main():
    args = sys.argv[1:]
    if args and args[0] == "--preview":
        first, last = (int(args[1]), int(args[2])) if len(args) == 3 else (1, 10**6)
        return preview(first, last)
    first, last = (int(args[0]), int(args[1])) if len(args) == 2 else (1, 10**6)
    OUT.mkdir(parents=True, exist_ok=True)
    failures = 0
    for level, source, note in rows(first, last):
        out_path = OUT / f"level_{level:03d}.json"
        try:
            w, h, diff, arrows = load_source(source)
            if re.fullmatch(r"\d+\s*easy", note, re.I):
                diff = 0
            diff = 1 if diff is None else diff
            if parse_note(note):
                if level not in LEVEL_SHAPES:
                    raise ValueError("note asks for a new shape but LEVEL_SHAPES has no entry")
                msg = generate_shape(level, note, source, diff, out_path)
            elif arrows is None:
                # Source not playable under our rules: same board cells and arrow count, new arrows.
                w, h, _, raw = load_raw(source)
                board = {"width": w, "height": h, "points": [list(c) for a in raw for c in a]}
                got = run_generator(level, [], len(raw), diff, out_path, board)
                msg = f"regenerated {w}x{h} on source cells (source not solvable in our game), {len(raw)} -> {got} arrows, difficulty {diff}"
            else:
                write_level(out_path, w, h, diff, arrows)
                msg = f"cloned {w}x{h}, {len(arrows)} arrows, difficulty {diff}"
            print(f"L{level:3d} [{source}] {msg}" + (f"  (note: {note})" if note else ""), flush=True)
        except Exception as e:
            failures += 1
            print(f"L{level:3d} [{source}] FAILED: {e}", flush=True)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
