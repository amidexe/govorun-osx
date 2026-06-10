#!/usr/bin/env python3
import argparse
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "docs/banner.svg"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate the README banner SVG.")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--title", default="Говорун")
    parser.add_argument("--platform", default="для macOS")
    parser.add_argument("--subtitle", default="Оффлайн-голосовой ввод на русском.")
    return parser.parse_args()


def esc(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def build_svg(title: str, platform: str, subtitle: str) -> str:
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 400" width="1280" height="400" role="img" aria-label="{esc(title)} {esc(platform)} — {esc(subtitle)}">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#1C1718"/>
      <stop offset="58%" stop-color="#121723"/>
      <stop offset="100%" stop-color="#101013"/>
    </linearGradient>
    <linearGradient id="accent" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#F0A22E"/>
      <stop offset="100%" stop-color="#3579E8"/>
    </linearGradient>
    <filter id="softShadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="18" stdDeviation="20" flood-color="#000000" flood-opacity="0.35"/>
    </filter>
  </defs>

  <rect width="1280" height="400" rx="32" fill="url(#bg)"/>
  <path d="M0 339 C160 304 288 318 441 353 C597 389 737 387 904 344 C1056 305 1163 302 1280 323 L1280 400 L0 400 Z" fill="#FFFFFF" opacity="0.035"/>
  <path d="M0 76 C187 117 334 108 503 73 C681 36 813 26 986 66 C1098 92 1198 98 1280 82" fill="none" stroke="#FFFFFF" stroke-opacity="0.075" stroke-width="2"/>
  <path d="M1 34 L1 366" stroke="url(#accent)" stroke-width="6" stroke-linecap="round" opacity="0.95"/>

  <g filter="url(#softShadow)">
    <rect x="90" y="78" width="244" height="244" rx="58" fill="#F7F7FA" opacity="0.96"/>
    <rect x="90.75" y="78.75" width="242.5" height="242.5" rx="57.25" fill="none" stroke="#FFFFFF" stroke-opacity="0.5" stroke-width="1.5"/>
  </g>

  <!-- Bird mark (24×24 viewport, same as app icon) -->
  <g transform="translate(120 106) scale(7.65)" stroke="#1D1D20" fill="none" stroke-linecap="round" stroke-linejoin="round">
    <path stroke-width="0.52" d="M21.5,10.5 L17.5,9 C14.5,5.5 9,5.5 6,9.5 L3,8.5 L4,12.5 C5.5,15.5 9,17.5 13,17.5 C16,17.5 18,15.5 18,13 L21.5,11.5 Z"/>
    <path stroke-width="0.42" d="M7.5,11.5 C9.5,13.5 12,14.5 15,14"/>
    <circle cx="15.2" cy="9" r="0.76" fill="#1D1D20" stroke="none"/>
  </g>

  <g font-family="'Inter Display', Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif">
    <text x="430" y="164" font-size="82" font-weight="800" letter-spacing="0" fill="#F7F8FB">{esc(title)}</text>
    <text x="434" y="211" font-size="28" font-weight="600" letter-spacing="0" fill="#AEB6C3">{esc(platform)}</text>
    <text x="434" y="260" font-size="28" font-weight="500" letter-spacing="0" fill="#ECEEF4">{esc(subtitle)}</text>

    <g transform="translate(434 302)" font-size="15" font-weight="600" fill="#DDE3EC">
      <g>
        <rect width="122" height="36" rx="18" fill="#FFFFFF" fill-opacity="0.07" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="1.5"/>
        <text x="61" y="23.5" text-anchor="middle">macOS 13+</text>
      </g>
      <g transform="translate(138 0)">
        <rect width="148" height="36" rx="18" fill="#FFFFFF" fill-opacity="0.07" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="1.5"/>
        <text x="74" y="23.5" text-anchor="middle">Apple Silicon</text>
      </g>
      <g transform="translate(302 0)">
        <rect width="108" height="36" rx="18" fill="#FFFFFF" fill-opacity="0.07" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="1.5"/>
        <text x="54" y="23.5" text-anchor="middle">GigaAM v3</text>
      </g>
      <g transform="translate(426 0)">
        <rect width="100" height="36" rx="18" fill="#FFFFFF" fill-opacity="0.07" stroke="#FFFFFF" stroke-opacity="0.2" stroke-width="1.5"/>
        <text x="50" y="23.5" text-anchor="middle">офлайн</text>
      </g>
    </g>
  </g>
</svg>
'''


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(build_svg(args.title, args.platform, args.subtitle), encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
