#!/usr/bin/env python3
import argparse
from pathlib import Path
from typing import Optional, Tuple

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


CANVAS = (3200, 1800)
PREVIEW = (1600, 900)
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "docs/preview/github-card-statistics-current.png"
DEFAULT_PREVIEW = ROOT / "docs/preview/github-card-statistics-current-preview.png"
DEFAULT_LOGO = ROOT / "Govorun/Assets.xcassets/AppIcon.appiconset/icon_256x256.png"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build a local GitHub preview card from current Govorun screenshots."
    )
    parser.add_argument("--settings", required=True, help="Screenshot of the settings/statistics window.")
    parser.add_argument("--light-card", help="Small light-theme stats popover screenshot.")
    parser.add_argument("--dark-card", help="Small dark-theme stats popover screenshot.")
    parser.add_argument("--out", default=str(DEFAULT_OUT), help="Output PNG path, 3200x1800.")
    parser.add_argument("--preview-out", default=str(DEFAULT_PREVIEW), help="Preview PNG path, 1600x900.")
    parser.add_argument("--logo", default=str(DEFAULT_LOGO), help="App icon PNG path.")
    parser.add_argument("--title", default="Говорун")
    parser.add_argument("--subtitle", default="Оффлайн-голосовой ввод на русском.")
    parser.add_argument("--feature", action="append", default=None, help="Feature line. Can be repeated.")
    parser.add_argument("--no-trim", action="store_true", help="Do not trim black desktop padding from screenshots.")
    return parser.parse_args()


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont:
    candidates = {
        "regular": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Supplemental/Arial.ttf",
        ],
        "bold": [
            "/System/Library/Fonts/SFNS.ttf",
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
        ],
    }[weight]
    for path in candidates:
        try:
            return ImageFont.truetype(path, size=size)
        except OSError:
            pass
    return ImageFont.load_default()


def load_image(path: str, trim: bool = True) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    return trim_desktop_padding(image) if trim else image


def trim_desktop_padding(image: Image.Image, threshold: int = 12, margin: int = 12) -> Image.Image:
    bg = image.getpixel((0, 0))
    flat = Image.new("RGBA", image.size, bg)
    diff = ImageChops.difference(image, flat).convert("L")
    mask = diff.point(lambda p: 255 if p > threshold else 0)
    bbox = mask.getbbox()
    if not bbox:
        return image
    left, top, right, bottom = bbox
    left = max(0, left - margin)
    top = max(0, top - margin)
    right = min(image.width, right + margin)
    bottom = min(image.height, bottom + margin)
    return image.crop((left, top, right, bottom))


def rounded_mask(size: Tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def fit_contain(image: Image.Image, box: Tuple[int, int]) -> Image.Image:
    ratio = min(box[0] / image.width, box[1] / image.height)
    size = (max(1, int(image.width * ratio)), max(1, int(image.height * ratio)))
    return image.resize(size, Image.Resampling.LANCZOS)


def paste_shadowed(
    canvas: Image.Image,
    image: Image.Image,
    xy: Tuple[int, int],
    radius: int,
    shadow: Tuple[int, int, int, int] = (0, 0, 0, 120),
    blur: int = 34,
    offset: Tuple[int, int] = (0, 24),
) -> None:
    mask = image.getchannel("A")
    shadow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_image = Image.new("RGBA", image.size, shadow)
    shadow_layer.paste(shadow_image, (xy[0] + offset[0], xy[1] + offset[1]), mask)
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow_layer)
    canvas.alpha_composite(image, xy)


def screenshot_panel(image: Image.Image, box: Tuple[int, int], radius: int) -> Image.Image:
    fitted = fit_contain(image, box)
    panel = Image.new("RGBA", fitted.size, (0, 0, 0, 0))
    mask = rounded_mask(fitted.size, radius)
    panel.paste(fitted, (0, 0), mask)
    outline = Image.new("RGBA", fitted.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(outline)
    draw.rounded_rectangle(
        (1, 1, fitted.width - 2, fitted.height - 2),
        radius=radius,
        outline=(255, 255, 255, 62),
        width=2,
    )
    panel.alpha_composite(outline)
    return panel


def gradient_background() -> Image.Image:
    width, height = CANVAS
    image = Image.new("RGBA", CANVAS, (0, 0, 0, 255))
    pixels = image.load()
    left = (45, 38, 35)
    right = (12, 16, 50)
    for x in range(width):
        t = x / (width - 1)
        r = int(left[0] * (1 - t) + right[0] * t)
        g = int(left[1] * (1 - t) + right[1] * t)
        b = int(left[2] * (1 - t) + right[2] * t)
        for y in range(height):
            pixels[x, y] = (r, g, b, 255)

    glow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((-300, 250, 760, 1840), fill=(220, 128, 45, 46))
    draw.ellipse((1760, 300, 3400, 1600), fill=(35, 84, 170, 42))
    glow = glow.filter(ImageFilter.GaussianBlur(120))
    image.alpha_composite(glow)
    return image


def draw_text(draw: ImageDraw.ImageDraw, xy: Tuple[int, int], text: str, size: int, weight: str, fill) -> None:
    draw.text(xy, text, font=font(size, weight), fill=fill)


def draw_bullet(draw: ImageDraw.ImageDraw, x: int, y: int, text: str) -> None:
    draw.ellipse((x, y + 10, x + 14, y + 24), fill=(238, 161, 42, 255))
    draw_text(draw, (x + 28, y), text, 31, "bold", (239, 240, 248, 238))


def draw_pill(draw: ImageDraw.ImageDraw, x: int, y: int, text: str, fill: Tuple[int, int, int, int]) -> None:
    text_font = font(28, "bold")
    bbox = draw.textbbox((0, 0), text, font=text_font)
    width = bbox[2] - bbox[0] + 44
    height = 50
    draw.rounded_rectangle((x, y, x + width, y + height), radius=25, fill=fill, outline=(255, 255, 255, 42), width=1)
    draw.text((x + 22, y + 9), text, font=text_font, fill=(255, 255, 255, 235))


def paste_app_logo(canvas: Image.Image, path: str, xy: Tuple[int, int]) -> None:
    logo_path = Path(path)
    if not logo_path.exists():
        return

    logo = Image.open(logo_path).convert("RGBA").resize((108, 108), Image.Resampling.LANCZOS)
    shadow = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    shadow_mask = logo.getchannel("A").filter(ImageFilter.GaussianBlur(16))
    shadow.paste(Image.new("RGBA", logo.size, (0, 0, 0, 96)), (xy[0], xy[1] + 12), shadow_mask)
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(logo, xy)


def draw_feature_box(canvas: Image.Image, features: list[str]) -> None:
    x, y, w, h = 2140, 1308, 900, 178
    layer = Image.new("RGBA", CANVAS, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle((x, y, x + w, y + h), radius=24, fill=(13, 20, 40, 214), outline=(255, 255, 255, 42), width=2)
    accents = [
        (75, 149, 255, 255),
        (238, 161, 42, 255),
        (91, 201, 128, 255),
        (235, 86, 86, 255),
    ]
    rows = features[:2]
    for index, item in enumerate(rows):
        line_y = y + 42 + index * 62
        draw.rounded_rectangle((x + 30, line_y + 4, x + 36, line_y + 42), radius=3, fill=accents[index % len(accents)])
        draw_text(draw, (x + 58, line_y - 2), item, 32, "bold", (255, 255, 255, 245))
    canvas.alpha_composite(layer)


def build_card(args: argparse.Namespace) -> Image.Image:
    settings = load_image(args.settings, trim=not args.no_trim)
    light = load_image(args.light_card, trim=not args.no_trim) if args.light_card else None
    dark = load_image(args.dark_card, trim=not args.no_trim) if args.dark_card else None

    canvas = gradient_background()
    draw = ImageDraw.Draw(canvas)

    paste_app_logo(canvas, args.logo, (210, 76))
    draw_text(draw, (344, 88), args.title, 76, "bold", (255, 255, 255, 248))
    draw_text(draw, (348, 176), args.subtitle, 34, "regular", (235, 236, 245, 220))

    settings_panel = screenshot_panel(settings, (1810, 1450), radius=34)
    paste_shadowed(canvas, settings_panel, (180, 280), radius=34, blur=46, offset=(0, 32))

    right_x = 2140

    if light:
        draw_pill(draw, right_x, 338, "Дневная тема", (238, 161, 42, 210))
        panel = screenshot_panel(light, (760, 350), radius=40)
        paste_shadowed(canvas, panel, (2258, 416), radius=40, blur=42, offset=(0, 24))

    if dark:
        draw_pill(draw, right_x, 778, "Ночная тема", (62, 82, 126, 210))
        panel = screenshot_panel(dark, (760, 350), radius=40)
        paste_shadowed(canvas, panel, (2258, 856), radius=40, blur=42, offset=(0, 24))

    features = args.feature or [
        "Офлайн на вашем Mac",
        "Напоминание об отдыхе",
    ]
    draw_feature_box(canvas, features)
    return canvas.convert("RGB")


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    preview_out = Path(args.preview_out)
    out.parent.mkdir(parents=True, exist_ok=True)
    preview_out.parent.mkdir(parents=True, exist_ok=True)

    card = build_card(args)
    card.save(out, "PNG", optimize=True)
    card.resize(PREVIEW, Image.Resampling.LANCZOS).save(preview_out, "PNG", optimize=True)
    print(f"wrote {out}")
    print(f"wrote {preview_out}")


if __name__ == "__main__":
    main()
