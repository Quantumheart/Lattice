#!/usr/bin/env python3
"""Generate Kohera app icons for all platforms from a single source rendering."""

import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG_COLOR = (25, 118, 210, 255)  # #1976D2 — default accent blue
FG_COLOR = (255, 255, 255, 255)  # white


def draw_hub_icon(size, mode="rounded"):
    """Render the hub icon at the given size.

    Modes:
      rounded  — rounded corners, transparent background (Android, macOS, web standard)
      square   — no rounding, no transparency, solid background (iOS)
      maskable — full bleed background, icon in safe zone (40% padding), no rounding (web maskable)
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if mode == "square":
        draw.rectangle([0, 0, size - 1, size - 1], fill=BG_COLOR)
    elif mode == "maskable":
        draw.rectangle([0, 0, size - 1, size - 1], fill=BG_COLOR)
    else:
        cr = int(size * 0.22)
        draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=cr, fill=BG_COLOR)

    if mode == "maskable":
        padding = size * 0.30
    else:
        padding = size * 0.22

    icon_area = size - 2 * padding
    cx, cy = size / 2, size / 2

    center_r = icon_area * 0.12
    outer_r = icon_area * 0.08
    spoke_dist = icon_area * 0.38

    angles = [90, 30, 330, 210, 150]
    nodes = []
    for angle_deg in angles:
        angle_rad = math.radians(angle_deg)
        nx = cx + spoke_dist * math.cos(angle_rad)
        ny = cy - spoke_dist * math.sin(angle_rad)
        nodes.append((nx, ny))

    line_width = max(2, int(size * 0.03))
    for nx, ny in nodes:
        draw.line([(cx, cy), (nx, ny)], fill=FG_COLOR, width=line_width)

    draw.ellipse(
        [cx - center_r, cy - center_r, cx + center_r, cy + center_r], fill=FG_COLOR
    )
    for nx, ny in nodes:
        draw.ellipse(
            [nx - outer_r, ny - outer_r, nx + outer_r, ny + outer_r], fill=FG_COLOR
        )

    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print(f"  {os.path.relpath(path, ROOT)}")


def generate_android():
    print("Android:")
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for density, size in densities.items():
        img = draw_hub_icon(size, mode="rounded")
        save(img, os.path.join(ROOT, f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"))


def generate_ios():
    print("iOS:")
    sizes = [20, 40, 60, 29, 58, 87, 40, 80, 120, 120, 180, 76, 152, 167, 1024]
    filenames = [
        "Icon-App-20x20@1x.png", "Icon-App-20x20@2x.png", "Icon-App-20x20@3x.png",
        "Icon-App-29x29@1x.png", "Icon-App-29x29@2x.png", "Icon-App-29x29@3x.png",
        "Icon-App-40x40@1x.png", "Icon-App-40x40@2x.png", "Icon-App-40x40@3x.png",
        "Icon-App-60x60@2x.png", "Icon-App-60x60@3x.png",
        "Icon-App-76x76@1x.png", "Icon-App-76x76@2x.png",
        "Icon-App-83.5x83.5@2x.png", "Icon-App-1024x1024@1x.png",
    ]
    base = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for size, fname in zip(sizes, filenames):
        img = draw_hub_icon(size, mode="square")
        img = img.convert("RGB")
        save(img, os.path.join(base, fname))


def generate_macos():
    print("macOS:")
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    base = os.path.join(ROOT, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
    for size in sizes:
        img = draw_hub_icon(size, mode="rounded")
        save(img, os.path.join(base, f"app_icon_{size}.png"))


def generate_web():
    print("Web:")
    web = os.path.join(ROOT, "web")

    favicon = draw_hub_icon(32, mode="rounded")
    save(favicon, os.path.join(web, "favicon.png"))

    for size in [192, 512]:
        img = draw_hub_icon(size, mode="rounded")
        save(img, os.path.join(web, f"icons/Icon-{size}.png"))

    for size in [192, 512]:
        img = draw_hub_icon(size, mode="maskable")
        save(img, os.path.join(web, f"icons/Icon-maskable-{size}.png"))


def generate_windows():
    print("Windows:")
    ico_sizes = [16, 32, 48, 64, 128, 256]
    images = []
    for size in ico_sizes:
        img = draw_hub_icon(size, mode="rounded")
        img = img.convert("RGBA")
        images.append(img)

    ico_path = os.path.join(ROOT, "windows/runner/resources/app_icon.ico")
    images[0].save(ico_path, format="ICO", sizes=[(s, s) for s in ico_sizes], append_images=images[1:])
    print(f"  {os.path.relpath(ico_path, ROOT)}")


if __name__ == "__main__":
    print(f"Generating Kohera app icons (bg={BG_COLOR[:3]}, fg=white)\n")
    generate_android()
    generate_ios()
    generate_macos()
    generate_web()
    generate_windows()
    print("\nDone!")
