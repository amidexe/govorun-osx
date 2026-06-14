#!/usr/bin/env python3
"""
Generate macOS AppIcon.appiconset PNG files from the canonical vector source.

macOS app bundles ultimately use raster icon representations inside AppIcon.icns,
but the editable source of truth must stay vector. The bird geometry comes from
govorun-lite's launcher foreground vector.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE_SVG = ROOT / "assets/app-icon/govorun-app-icon.svg"
OUT = ROOT / "Govorun/Assets.xcassets/AppIcon.appiconset"

# macOS icon slots: (point size, scale)
SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]


def render_svg(size: int, output: Path) -> None:
    renderer = shutil.which("rsvg-convert")
    if renderer is None:
        raise SystemExit(
            "rsvg-convert is required to render the vector app icon. "
            "Install librsvg, for example: brew install librsvg"
        )

    subprocess.run(
        [
            renderer,
            "--width", str(size),
            "--height", str(size),
            "--format", "png",
            "--output", str(output),
            str(SOURCE_SVG),
        ],
        check=True,
    )


def main() -> None:
    if not SOURCE_SVG.exists():
        raise SystemExit(f"Missing source icon: {SOURCE_SVG}")

    OUT.mkdir(parents=True, exist_ok=True)

    seen: set[int] = set()
    for point_size, scale in SIZES:
        pixels = point_size * scale
        if pixels in seen:
            continue
        seen.add(pixels)

        filename = f"icon_{pixels}x{pixels}.png"
        render_svg(pixels, OUT / filename)
        print(f"  {filename}")

    contents = {
        "images": [
            {
                "filename": f"icon_{point_size * scale}x{point_size * scale}.png",
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{point_size}x{point_size}",
            }
            for point_size, scale in SIZES
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    (OUT / "Contents.json").write_text(
        json.dumps(contents, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Done - icons in {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
