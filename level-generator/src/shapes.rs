//! Board shape masks. Each shape is defined in normalized coordinates (u, v) in [0, 1]
//! (v grows downward) and rasterized by testing each cell center.

use std::collections::VecDeque;
use std::f64::consts::PI;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Shape {
    Square,
    Circle,
    Triangle,
    Diamond,
    Trapezoid,
    Pentagon,
    Hexagon,
    Shield,
    Leaf,
    Popsicle,
    Flower,
    Star,
    Gourd,
    WateringCan,
    Hand,
}

pub const ALL_SHAPES: [Shape; 15] = [
    Shape::Square,
    Shape::Circle,
    Shape::Triangle,
    Shape::Diamond,
    Shape::Trapezoid,
    Shape::Pentagon,
    Shape::Hexagon,
    Shape::Shield,
    Shape::Leaf,
    Shape::Popsicle,
    Shape::Flower,
    Shape::Star,
    Shape::Gourd,
    Shape::WateringCan,
    Shape::Hand,
];

impl Shape {
    pub fn name(self) -> &'static str {
        match self {
            Shape::Square => "square",
            Shape::Circle => "circle",
            Shape::Triangle => "triangle",
            Shape::Diamond => "diamond",
            Shape::Trapezoid => "trapezoid",
            Shape::Pentagon => "pentagon",
            Shape::Hexagon => "hexagon",
            Shape::Shield => "shield",
            Shape::Leaf => "leaf",
            Shape::Popsicle => "popsicle",
            Shape::Flower => "flower",
            Shape::Star => "star",
            Shape::Gourd => "gourd",
            Shape::WateringCan => "watering-can",
            Shape::Hand => "hand",
        }
    }

    pub fn from_name(name: &str) -> Option<Shape> {
        ALL_SHAPES.into_iter().find(|s| s.name() == name)
    }

    /// Smallest min(width, height) at which the shape still reads well.
    pub fn min_size(self) -> usize {
        match self {
            Shape::Square | Shape::Circle | Shape::Triangle | Shape::Diamond => 0,
            Shape::Trapezoid | Shape::Pentagon | Shape::Hexagon | Shape::Shield | Shape::Leaf | Shape::Popsicle => 9,
            Shape::Flower | Shape::Star | Shape::Gourd => 14,
            Shape::WateringCan | Shape::Hand => 18,
        }
    }

    fn contains(self, u: f64, v: f64) -> bool {
        match self {
            Shape::Square => true,
            Shape::Circle => circle(u, v, 0.5, 0.5, 0.5),
            Shape::Triangle => in_polygon(u, v, &[(0.5, 0.0), (1.0, 1.0), (0.0, 1.0)]),
            Shape::Diamond => (u - 0.5).abs() + (v - 0.5).abs() <= 0.5,
            Shape::Trapezoid => in_polygon(u, v, &[(0.22, 0.0), (0.78, 0.0), (1.0, 1.0), (0.0, 1.0)]),
            Shape::Pentagon => in_polygon(u, v, &regular_polygon(5, -PI / 2.0, 1.0)),
            Shape::Hexagon => in_polygon(u, v, &regular_polygon(6, 0.0, 1.0)),
            Shape::Shield => in_polygon(
                u,
                v,
                &[
                    (0.0, 0.1),
                    (0.5, 0.0),
                    (1.0, 0.1),
                    (1.0, 0.5),
                    (0.92, 0.7),
                    (0.72, 0.88),
                    (0.5, 1.0),
                    (0.28, 0.88),
                    (0.08, 0.7),
                    (0.0, 0.5),
                ],
            ),
            Shape::Leaf => {
                // Lens (intersection of two circles) along the diagonal, plus a short stem.
                let (ru, rv) = rotate(u - 0.5, v - 0.5, PI / 4.0);
                let lens = circle(ru, rv, 0.0, 0.38, 0.62) && circle(ru, rv, 0.0, -0.38, 0.62);
                lens || capsule(u, v, (0.2, 0.8), (0.03, 0.97), 0.05)
            }
            Shape::Popsicle => {
                let body = (u >= 0.18 && u <= 0.82 && v >= 0.32 && v <= 0.72) || circle(u, v, 0.5, 0.32, 0.32);
                body || (u >= 0.41 && u <= 0.59 && v >= 0.7)
            }
            Shape::Flower => {
                // Five rounded petals around a center.
                let (x, y) = (u - 0.5, v - 0.5);
                let r = (x * x + y * y).sqrt();
                let theta = y.atan2(x) + PI / 2.0; // first petal points up
                r <= 0.5 * (0.35 + 0.65 * (2.5 * theta).cos().abs().powf(0.7)) || r <= 0.25
            }
            Shape::Star => in_polygon(u, v, &star_polygon(5, 0.42)),
            Shape::Gourd => {
                circle(u, v, 0.5, 0.36, 0.2)
                    || circle(u, v, 0.5, 0.68, 0.32)
                    || (u >= 0.42 && u <= 0.58 && v >= 0.36 && v <= 0.55)
                    || (u >= 0.45 && u <= 0.55 && v <= 0.2)
            }
            Shape::WateringCan => {
                let body = (u >= 0.32 && u <= 0.8 && v >= 0.42) || ellipse(u, v, 0.56, 0.42, 0.24, 0.08);
                let spout = capsule(u, v, (0.36, 0.78), (0.1, 0.26), 0.06);
                let rose = circle(u, v, 0.08, 0.22, 0.09);
                let side = annulus(u, v, 0.8, 0.66, 0.1, 0.2) && u >= 0.8;
                let top = annulus(u, v, 0.56, 0.36, 0.14, 0.24) && v <= 0.36;
                body || spout || rose || side || top
            }
            Shape::Hand => {
                let palm = (u >= 0.2 && u <= 0.82 && v >= 0.45 && v <= 0.88) || ellipse(u, v, 0.51, 0.88, 0.31, 0.12);
                let fingers = [(0.27, 0.12), (0.42, 0.02), (0.58, 0.04), (0.74, 0.16)]
                    .iter()
                    .any(|&(x, top)| capsule(u, v, (x, 0.5), (x, top + 0.07), 0.07));
                let thumb = capsule(u, v, (0.28, 0.75), (0.07, 0.42), 0.075);
                palm || fingers || thumb
            }
        }
    }
}

/// Shapes that fit a board of the given size: simple ones for small boards, complex ones for larger.
pub fn shapes_for_size(width: usize, height: usize) -> Vec<Shape> {
    let s = width.min(height);
    ALL_SHAPES.into_iter().filter(|sh| s >= sh.min_size()).collect()
}

/// Rasterize the shape into a width*height mask (row-major).
/// Aspect ratio is kept within 1.25 so shapes don't get too distorted; the shape is centered.
pub fn build_mask(shape: Shape, width: usize, height: usize) -> Vec<bool> {
    let (w, h) = (width as f64, height as f64);
    let (sw, sh) = if shape == Shape::Square {
        (w, h)
    } else {
        (w.min(h * 1.25), h.min(w * 1.25))
    };
    let (ox, oy) = ((w - sw) / 2.0, (h - sh) / 2.0);

    let mut mask = vec![false; width * height];
    for y in 0..height {
        for x in 0..width {
            let u = (x as f64 + 0.5 - ox) / sw;
            let v = (y as f64 + 0.5 - oy) / sh;
            if (0.0..=1.0).contains(&u) && (0.0..=1.0).contains(&v) {
                mask[y * width + x] = shape.contains(u, v);
            }
        }
    }
    keep_largest_component(&mut mask, width, height);
    mask
}

fn keep_largest_component(mask: &mut [bool], width: usize, height: usize) {
    let mut comp = vec![usize::MAX; mask.len()];
    let mut best = (0, 0); // (id, size)
    let mut id = 0;
    for start in 0..mask.len() {
        if !mask[start] || comp[start] != usize::MAX {
            continue;
        }
        let mut size = 0;
        let mut queue = VecDeque::from([start]);
        comp[start] = id;
        while let Some(c) = queue.pop_front() {
            size += 1;
            let (x, y) = (c % width, c / width);
            let mut neigh = Vec::with_capacity(4);
            if x > 0 {
                neigh.push(c - 1);
            }
            if x + 1 < width {
                neigh.push(c + 1);
            }
            if y > 0 {
                neigh.push(c - width);
            }
            if y + 1 < height {
                neigh.push(c + width);
            }
            for n in neigh {
                if mask[n] && comp[n] == usize::MAX {
                    comp[n] = id;
                    queue.push_back(n);
                }
            }
        }
        if size > best.1 {
            best = (id, size);
        }
        id += 1;
    }
    for (m, c) in mask.iter_mut().zip(comp) {
        *m = *m && c == best.0;
    }
}

pub fn render_ascii(mask: &[bool], width: usize) -> String {
    mask.chunks(width)
        .map(|row| row.iter().map(|&b| if b { '#' } else { '.' }).collect::<String>())
        .collect::<Vec<_>>()
        .join("\n")
}

// ----------------------------------------------------------------
// Geometry helpers
// ----------------------------------------------------------------

fn circle(u: f64, v: f64, cx: f64, cy: f64, r: f64) -> bool {
    (u - cx).powi(2) + (v - cy).powi(2) <= r * r
}

fn ellipse(u: f64, v: f64, cx: f64, cy: f64, rx: f64, ry: f64) -> bool {
    ((u - cx) / rx).powi(2) + ((v - cy) / ry).powi(2) <= 1.0
}

fn annulus(u: f64, v: f64, cx: f64, cy: f64, r_in: f64, r_out: f64) -> bool {
    circle(u, v, cx, cy, r_out) && !circle(u, v, cx, cy, r_in)
}

fn rotate(x: f64, y: f64, a: f64) -> (f64, f64) {
    (x * a.cos() - y * a.sin(), x * a.sin() + y * a.cos())
}

/// Thick line segment with round ends.
fn capsule(u: f64, v: f64, a: (f64, f64), b: (f64, f64), r: f64) -> bool {
    let (dx, dy) = (b.0 - a.0, b.1 - a.1);
    let len2 = dx * dx + dy * dy;
    let t = if len2 == 0.0 { 0.0 } else { (((u - a.0) * dx + (v - a.1) * dy) / len2).clamp(0.0, 1.0) };
    circle(u, v, a.0 + t * dx, a.1 + t * dy, r)
}

fn in_polygon(u: f64, v: f64, poly: &[(f64, f64)]) -> bool {
    let mut inside = false;
    let mut j = poly.len() - 1;
    for i in 0..poly.len() {
        let (xi, yi) = poly[i];
        let (xj, yj) = poly[j];
        if (yi > v) != (yj > v) && u < (xj - xi) * (v - yi) / (yj - yi) + xi {
            inside = !inside;
        }
        j = i;
    }
    inside
}

/// Scale points so their bounding box becomes the unit square.
fn normalize(points: Vec<(f64, f64)>) -> Vec<(f64, f64)> {
    let min_x = points.iter().map(|p| p.0).fold(f64::INFINITY, f64::min);
    let max_x = points.iter().map(|p| p.0).fold(f64::NEG_INFINITY, f64::max);
    let min_y = points.iter().map(|p| p.1).fold(f64::INFINITY, f64::min);
    let max_y = points.iter().map(|p| p.1).fold(f64::NEG_INFINITY, f64::max);
    points
        .into_iter()
        .map(|(x, y)| ((x - min_x) / (max_x - min_x), (y - min_y) / (max_y - min_y)))
        .collect()
}

fn regular_polygon(sides: usize, start: f64, radius: f64) -> Vec<(f64, f64)> {
    normalize(
        (0..sides)
            .map(|i| {
                let a = start + 2.0 * PI * i as f64 / sides as f64;
                (radius * a.cos(), radius * a.sin())
            })
            .collect(),
    )
}

fn star_polygon(points: usize, inner_ratio: f64) -> Vec<(f64, f64)> {
    normalize(
        (0..points * 2)
            .map(|i| {
                let r = if i % 2 == 0 { 1.0 } else { inner_ratio };
                let a = -PI / 2.0 + PI * i as f64 / points as f64;
                (r * a.cos(), r * a.sin())
            })
            .collect(),
    )
}
