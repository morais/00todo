#!/usr/bin/env python3
"""Frame verified simulator captures in the 00Widget editorial screenshot style."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "artifacts/screenshots/raw"
PROMOTIONAL = ROOT / "artifacts/screenshots/promotional"
FONT = "/System/Library/Fonts/SFNS.ttf"
SIZES = {"iphone-6.3": (1206, 2622), "ipad": (2064, 2752)}
SCREENS = (
    ("01-available.png", "Only what's ready.", "Tasks from every project, all in one place."),
    ("02-upcoming.png", "Future work, on time.", "Start dates keep later tasks out of today's way."),
    ("03-project.png", "Lists that stay simple.", "A project keeps related tasks together."),
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verified_sources(device_set: str) -> dict[str, Path]:
    directory = RAW / device_set
    manifest = json.loads((directory / ".capture-manifest.json").read_text())
    expected = {name for name, _, _ in SCREENS}
    if set(manifest["files"]) != expected or tuple(manifest["dimensions"]) != SIZES[device_set]:
        raise ValueError(f"incomplete or wrong-size capture manifest: {directory}")
    sources = {}
    for name in expected:
        path = directory / name
        if digest(path) != manifest["files"][name]:
            raise ValueError(f"capture checksum mismatch: {path}")
        with Image.open(path) as image:
            if image.size != SIZES[device_set]:
                raise ValueError(f"capture dimensions changed: {path}")
        sources[name] = path
    return sources


def gradient(size: tuple[int, int]) -> Image.Image:
    width, height = size
    top, bottom = (255, 252, 247), (241, 239, 251)
    strip = Image.new("RGB", (1, height))
    pixels = strip.load()
    for y in range(height):
        t = y / (height - 1)
        pixels[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize(size).convert("RGBA")


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    result = ImageFont.truetype(FONT, size)
    if bold:
        result.set_variation_by_name("Bold")
    return result


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius, fill=255)
    result = image.convert("RGBA")
    result.putalpha(mask)
    return result


def device_frame(canvas: Image.Image, source: Image.Image, device_set: str) -> None:
    width, height = canvas.size
    ipad = device_set == "ipad"
    outer_width = round(width * 0.90)
    chrome = round(width * (0.006 if ipad else 0.0085))
    bezel = round(width * (0.0305 if ipad else 0.0105))
    screen_width = outer_width - 2 * (chrome + bezel)
    scale = screen_width / source.width
    screen_height = round(source.height * scale)
    top = round(height * (0.215 if ipad else 0.205))
    x = (width - outer_width) // 2
    outer_height = screen_height + 2 * (chrome + bezel)
    corner = round(60 * scale) if ipad else round(screen_width * 0.074)

    # Simulator screenshots omit the physical iPhone Island; 00Widget's
    # compositor restores it at its native 6.3-inch framebuffer coordinates.
    screen = source.convert("RGBA")
    if not ipad:
        ImageDraw.Draw(screen).rounded_rectangle((414, 42, 792, 153), radius=56, fill=(0, 0, 0))
    screen = rounded(screen.resize((screen_width, screen_height), Image.Resampling.LANCZOS), corner)

    shadow = Image.new("RGBA", canvas.size)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, top + round(height * 0.012), x + outer_width, top + outer_height + round(height * 0.012)),
        radius=corner + chrome + bezel,
        fill=(31, 23, 48, 100),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(round(width * 0.017))))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle((x, top, x + outer_width, top + outer_height),
                           radius=corner + chrome + bezel, fill=(47, 45, 53))
    draw.rounded_rectangle((x + chrome, top + chrome,
                            x + outer_width - chrome, top + outer_height - chrome),
                           radius=corner + bezel, fill=(7, 7, 10))
    canvas.alpha_composite(screen, (x + chrome + bezel, top + chrome + bezel))
    if not ipad:
        button_width = max(6, round(width * 0.006))
        for fraction, length in ((0.16, 0.035), (0.225, 0.06), (0.31, 0.06)):
            start = top + round(outer_height * fraction)
            draw.rounded_rectangle((x - button_width, start, x + 1, start + round(outer_height * length)),
                                   radius=button_width // 2, fill=(53, 52, 59))


def compose(source: Path, device_set: str, headline: str, supporting: str, output: Path) -> None:
    size = SIZES[device_set]
    canvas = gradient(size)
    draw = ImageDraw.Draw(canvas)
    width, height = size
    left = round(width * 0.06)
    ipad = device_set == "ipad"
    headline_font = font(round(width * (0.057 if ipad else 0.066)), bold=True)
    support_font = font(round(width * (0.028 if ipad else 0.032)))
    draw.text((left, round(height * 0.047)), headline, font=headline_font, fill=(25, 26, 33))
    draw.text((left, round(height * 0.107)), supporting, font=support_font, fill=(67, 66, 78))
    rule_y = round(height * 0.165)
    draw.rounded_rectangle((left, rule_y, left + round(width * 0.14), rule_y + round(width * 0.006)),
                           radius=round(width * 0.003), fill=(121, 54, 184))
    with Image.open(source) as screenshot:
        device_frame(canvas, screenshot, device_set)
    output.parent.mkdir(parents=True, exist_ok=True)
    canvas.convert("RGB").save(output, "PNG", optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", choices=("all", "iphone", "ipad"), default="all")
    args = parser.parse_args()
    sets = ("iphone-6.3", "ipad") if args.set == "all" else (("iphone-6.3",) if args.set == "iphone" else ("ipad",))
    for device_set in sets:
        sources = verified_sources(device_set)
        output_dir = PROMOTIONAL / device_set
        files = {}
        for name, headline, supporting in SCREENS:
            output = output_dir / name
            compose(sources[name], device_set, headline, supporting, output)
            files[name] = {"sourceSha256": digest(sources[name]), "sha256": digest(output)}
            print(output)
        (output_dir / ".composition-manifest.json").write_text(
            json.dumps({"deviceSet": device_set, "files": files}, indent=2, sort_keys=True) + "\n"
        )


if __name__ == "__main__":
    main()
