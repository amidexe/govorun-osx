#!/usr/bin/env python3
"""
Generate Говорун app icon PNG files for macOS AppIcon.appiconset.

Design:
  - macOS-style rounded-square background
  - Deep red gradient → darker red bottom-right
  - White bird outline (same paths as govorun-lite ic_launcher_foreground)
  - Scales cleanly from 16px to 1024px
"""

import math, os
from PIL import Image, ImageDraw

OUT = "Govorun/Assets.xcassets/AppIcon.appiconset"

# ── macOS icon sizes (size_pt, scale) ───────────────────────────────────────
SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

# ── Brand colors — white bg + dark bird (matches govorun-lite Android icon) ──
BG_TOP    = (255, 255, 255)  # white
BG_BOTTOM = (242, 242, 245)  # very subtle cool-white at bottom
BIRD_COLOR = (31,  31,  31)  # #1F1F1F — same as Android stroke

# ── Rounded-square corner radius (macOS: ~22% of size) ──────────────────────
CORNER_RATIO = 0.22


def rounded_square_mask(size, radius):
    """Returns an RGBA image with a white rounded-square on transparent bg."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def vertical_gradient(size, top_rgb, bottom_rgb):
    """Simple top→bottom linear gradient."""
    img = Image.new("RGB", (size, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(top_rgb[0] + (bottom_rgb[0] - top_rgb[0]) * t)
        g = int(top_rgb[1] + (bottom_rgb[1] - top_rgb[1]) * t)
        b = int(top_rgb[2] + (bottom_rgb[2] - top_rgb[2]) * t)
        for x in range(size):
            img.putpixel((x, y), (r, g, b))
    return img


# ── Bezier helpers ───────────────────────────────────────────────────────────

def lerp(a, b, t):
    return a + (b - a) * t

def cubic_bezier_points(p0, p1, p2, p3, steps=60):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = (lerp(lerp(lerp(p0[0],p1[0],t),lerp(p1[0],p2[0],t),t),
                   lerp(lerp(p1[0],p2[0],t),lerp(p2[0],p3[0],t),t), t))
        y = (lerp(lerp(lerp(p0[1],p1[1],t),lerp(p1[1],p2[1],t),t),
                   lerp(lerp(p1[1],p2[1],t),lerp(p2[1],p3[1],t),t), t))
        pts.append((x, y))
    return pts

def quad_bezier_points(p0, p1, p2, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        x = lerp(lerp(p0[0],p1[0],t), lerp(p1[0],p2[0],t), t)
        y = lerp(lerp(p0[1],p1[1],t), lerp(p1[1],p2[1],t), t)
        pts.append((x, y))
    return pts


def bird_polygons(canvas, bird_size, ox, oy):
    """
    Return the polygons/paths for the bird, scaled to bird_size in a 24x24
    viewport, offset by (ox, oy).

    Paths (from ic_launcher_foreground.xml, 24×24 viewport):
      Body outline: M21.5,10.5 L17.5,9 C14.5,5.5 9,5.5 6,9.5 L3,8.5 L4,12.5
                    C5.5,15.5 9,17.5 13,17.5 C16,17.5 18,15.5 18,13 L21.5,11.5 Z
      Belly:        M7.5,11.5 C9.5,13.5 12,14.5 15,14
      Eye:          circle at (15.2, 9), r=0.7
    """
    s = bird_size / 24.0

    def p(x, y):
        return (ox + x * s, oy + y * s)

    # ── Body outline ─────────────────────────────────────────────────────────
    body = []
    body.append(p(21.5, 10.5))
    body.append(p(17.5, 9.0))
    body += cubic_bezier_points(p(17.5, 9.0), p(14.5, 5.5), p(9.0, 5.5), p(6.0, 9.5))
    body.append(p(3.0, 8.5))
    body.append(p(4.0, 12.5))
    body += cubic_bezier_points(p(4.0, 12.5), p(5.5, 15.5), p(9.0, 17.5), p(13.0, 17.5))
    body += cubic_bezier_points(p(13.0, 17.5), p(16.0, 17.5), p(18.0, 15.5), p(18.0, 13.0))
    body.append(p(21.5, 11.5))
    # close
    body.append(body[0])

    # ── Belly line ────────────────────────────────────────────────────────────
    belly = cubic_bezier_points(p(7.5, 11.5), p(9.5, 13.5), p(12.0, 14.5), p(15.0, 14.0))

    # ── Eye ───────────────────────────────────────────────────────────────────
    ex, ey = p(15.2, 9.0)
    er = 0.7 * s

    return body, belly, (ex, ey, er)


def draw_bird_on(draw, canvas_size, bird_size, stroke_width):
    """Draw the bird centered on the canvas using Pillow's Draw."""
    ox = (canvas_size - bird_size) / 2.0
    oy = (canvas_size - bird_size) / 2.0

    body, belly, (ex, ey, er) = bird_polygons(canvas_size, bird_size, ox, oy)

    w = max(1, stroke_width)
    color = BIRD_COLOR

    # Body (stroke only)
    draw.line(body, fill=color, width=w, joint="curve")

    # Belly
    draw.line(belly, fill=color, width=max(1, int(w * 0.8)), joint="curve")

    # Eye (filled circle)
    bbox = [ex - er, ey - er, ex + er, ey + er]
    draw.ellipse(bbox, fill=color)


def make_icon(px):
    """Create a px×px app icon using 4× supersampling for smooth edges."""
    ss = 4  # supersampling factor
    big = px * ss
    radius_big = int(big * CORNER_RATIO)

    # 1. Background gradient at 4×
    bg = vertical_gradient(big, BG_TOP, BG_BOTTOM)

    # 2. Rounded-square mask at 4×
    mask = rounded_square_mask(big, radius_big)
    result = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    result.paste(bg, mask=mask)

    # 3. Draw bird at 4×
    bird_size = big * 0.62
    stroke = max(1, round(bird_size * 0.045))
    draw = ImageDraw.Draw(result)
    draw_bird_on(draw, big, bird_size, stroke)

    # 4. Downsample to target size
    return result.resize((px, px), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    entries = []
    seen = set()

    for pt, scale in SIZES:
        px = pt * scale
        if px in seen:
            continue
        seen.add(px)

        img = make_icon(px)
        fname = f"icon_{px}x{px}.png"
        img.save(os.path.join(OUT, fname), "PNG")
        print(f"  {fname}")

    # Re-build Contents.json pointing at generated files
    images_json = []
    for pt, scale in SIZES:
        px = pt * scale
        fname = f"icon_{px}x{px}.png"
        images_json.append(
            f'    {{\n'
            f'      "filename" : "{fname}",\n'
            f'      "idiom" : "mac",\n'
            f'      "scale" : "{scale}x",\n'
            f'      "size" : "{pt}x{pt}"\n'
            f'    }}'
        )

    contents = (
        '{\n'
        '  "images" : [\n'
        + ',\n'.join(images_json) + '\n'
        '  ],\n'
        '  "info" : {\n'
        '    "author" : "xcode",\n'
        '    "version" : 1\n'
        '  }\n'
        '}\n'
    )
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        f.write(contents)

    print(f"Done — icons in {OUT}")


if __name__ == "__main__":
    main()
