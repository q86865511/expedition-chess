from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Iterable

import numpy as np
import PIL
from PIL import Image, ImageDraw


TOKENS = [
    *(f"slice_monster_{index:02d}" for index in range(12)),
    *(f"slice_player_{index:02d}" for index in range(32)),
]
DIRECTIONS = ("n", "e", "s", "w")
PALETTE = (
    (47, 154, 150),
    (169, 77, 88),
    (118, 83, 155),
    (105, 113, 123),
    (215, 155, 58),
    (76, 132, 92),
)
MASTER_CALL_ID = "call_zIAbU7Ezj77PG2kvaep0fEbC"
MASTER_SEED = "not_exposed_by_builtin_image_gen"
LOCAL_SEED_BASE = 0x47325052


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def transparent_master(source: Image.Image) -> Image.Image:
    image = source.convert("RGBA")
    width, height = image.size
    x_fractions = (0.0, 0.1994, 0.3995, 0.5997, 0.7998, 1.0)
    y_fractions = (0.0, 0.1715, 0.3365, 0.5279, 0.7049, 1.0)
    normalized = Image.new("RGBA", (1280, 1280), (0, 0, 0, 0))
    for row in range(5):
        for column in range(5):
            left = round(width * x_fractions[column]) + 3
            right = round(width * x_fractions[column + 1]) - 3
            top = round(height * y_fractions[row]) + 3
            bottom = round(height * y_fractions[row + 1]) - 3
            cell = image.crop((left, top, right, bottom)).resize(
                (256, 256), Image.Resampling.NEAREST
            )
            normalized.alpha_composite(cell, (column * 256, row * 256))
    array = np.asarray(normalized).copy()
    chroma = (
        (array[:, :, 0] >= 220)
        & (array[:, :, 1] <= 90)
        & (array[:, :, 2] >= 220)
    )
    array[chroma, 3] = 0
    return Image.fromarray(array, "RGBA")


def recolor_subject(image: Image.Image, palette_index: int) -> Image.Image:
    array = np.asarray(image).copy()
    rgb = array[:, :, :3]
    alpha = array[:, :, 3] > 0
    cloth = (
        alpha
        & (rgb[:, :, 1] > rgb[:, :, 0] * 0.75)
        & (rgb[:, :, 2] > rgb[:, :, 0] * 0.70)
        & (rgb.max(axis=2) - rgb.min(axis=2) > 18)
    )
    target = np.array(PALETTE[palette_index % len(PALETTE)], dtype=np.float32)
    luminance = (
        rgb[:, :, 0].astype(np.float32) * 0.25
        + rgb[:, :, 1].astype(np.float32) * 0.55
        + rgb[:, :, 2].astype(np.float32) * 0.20
    )
    scale = np.clip(luminance / 120.0, 0.35, 1.45)
    colored = np.clip(target[None, None, :] * scale[:, :, None], 0, 255).astype(
        np.uint8
    )
    rgb[cloth] = colored[cloth]
    array[:, :, :3] = rgb
    return Image.fromarray(array, "RGBA")


def variant_sheet(master: Image.Image, index: int) -> Image.Image:
    result = Image.new("RGBA", (1280, 1280), (0, 0, 0, 0))
    width_factor = (0.90, 0.96, 1.0, 1.04, 1.08)[index % 5]
    for row in range(5):
        for column in range(5):
            cell = master.crop(
                (column * 256, row * 256, (column + 1) * 256, (row + 1) * 256)
            )
            cell = recolor_subject(cell, index % len(PALETTE))
            bounds = cell.getbbox()
            if bounds:
                subject = cell.crop(bounds)
                target_width = max(1, round(subject.width * width_factor))
                subject = subject.resize(
                    (target_width, subject.height), Image.Resampling.NEAREST
                )
                x = column * 256 + (256 - subject.width) // 2
                y = row * 256 + (256 - subject.height) // 2
                result.alpha_composite(subject, (x, y))
            draw_unit_emblem(result, index, column * 256 + 226, row * 256 + 24)
    return result


def draw_unit_emblem(image: Image.Image, index: int, x: int, y: int) -> None:
    draw = ImageDraw.Draw(image)
    color = (237, 228, 208, 255)
    outline = (8, 15, 25, 255)
    kind = index % 4
    if kind == 0:
        points = [(x, y - 8), (x + 8, y + 7), (x - 8, y + 7)]
    elif kind == 1:
        points = [(x, y - 8), (x + 8, y), (x, y + 8), (x - 8, y)]
    elif kind == 2:
        points = [
            (x - 7, y - 7),
            (x + 7, y - 7),
            (x + 7, y + 7),
            (x - 7, y + 7),
        ]
    else:
        points = [
            (x, y - 9),
            (x + 9, y - 3),
            (x + 5, y + 8),
            (x - 5, y + 8),
            (x - 9, y - 3),
        ]
    draw.polygon(points, fill=outline)
    inner = [(round((px + x) / 2), round((py + y) / 2)) for px, py in points]
    draw.polygon(inner, fill=color)


def chroma_sheet(transparent: Image.Image) -> Image.Image:
    background = Image.new("RGB", transparent.size, (255, 0, 255))
    background.paste(transparent, mask=transparent.getchannel("A"))
    return background


def fit_rgba(image: Image.Image, size: tuple[int, int], padding: int = 8) -> Image.Image:
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    bounds = image.getbbox()
    if not bounds:
        return output
    subject = image.crop(bounds)
    ratio = min(
        (size[0] - padding * 2) / max(1, subject.width),
        (size[1] - padding * 2) / max(1, subject.height),
    )
    target = (
        max(1, round(subject.width * ratio)),
        max(1, round(subject.height * ratio)),
    )
    subject = subject.resize(target, Image.Resampling.NEAREST)
    output.alpha_composite(
        subject, ((size[0] - target[0]) // 2, (size[1] - target[1]) // 2)
    )
    return output


def quadrant_frames(sheet: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for action in range(20):
        row, column = divmod(action, 5)
        cell = sheet.crop(
            (column * 256, row * 256, (column + 1) * 256, (row + 1) * 256)
        )
        quadrants = [
            cell.crop((0, 0, 128, 128)),
            cell.crop((128, 0, 256, 128)),
            cell.crop((128, 128, 256, 256)),
            cell.crop((0, 128, 128, 256)),
        ]
        populated = [quadrant for quadrant in quadrants if quadrant.getbbox()]
        fallback = populated[0] if populated else cell
        for quadrant in quadrants:
            selected = quadrant if quadrant.getbbox() else fallback
            frames.append(fit_rgba(selected, (64, 64), 4))
    return frames


def star_frame(base: Image.Image, star: int) -> Image.Image:
    frame = base.copy()
    draw = ImageDraw.Draw(frame)
    color = (245, 240, 223, 255)
    outline = (8, 15, 25, 255)
    for index in range(star):
        x = 52 - index * 9
        y = 55
        draw.polygon(
            [(x, y - 5), (x + 5, y), (x, y + 5), (x - 5, y)],
            fill=outline,
        )
        draw.polygon(
            [(x, y - 3), (x + 3, y), (x, y + 3), (x - 3, y)],
            fill=color,
        )
    return frame


def build_atlas(frames: list[Image.Image]) -> Image.Image:
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    output_frames: list[Image.Image] = []
    for star in range(1, 4):
        for frame in frames:
            output_frames.append(star_frame(frame, star))
    for index, frame in enumerate(output_frames):
        x = (index % 16) * 64
        y = (index // 16) * 64
        atlas.alpha_composite(frame, (x, y))
    return atlas


def sprite_frames_text(token: str) -> str:
    lines = [
        '[gd_resource type="SpriteFrames" load_steps=242 format=3]',
        "",
        (
            '[ext_resource type="Texture2D" '
            f'path="res://assets/production/atlases/{token}.png" id="1_atlas"]'
        ),
        "",
    ]
    for index in range(240):
        x = (index % 16) * 64
        y = (index // 16) * 64
        lines.extend(
            [
                f'[sub_resource type="AtlasTexture" id="AtlasTexture_{index:03d}"]',
                'atlas = ExtResource("1_atlas")',
                f"region = Rect2({x}, {y}, 64, 64)",
                "",
            ]
        )
    animations = []
    frame_index = 0
    for star in range(1, 4):
        for action in range(20):
            for direction in DIRECTIONS:
                animations.append(
                    "{\n"
                    '"frames": [{\n'
                    '"duration": 1.0,\n'
                    f'"texture": SubResource("AtlasTexture_{frame_index:03d}")\n'
                    "}],\n"
                    '"loop": true,\n'
                    f'"name": &"action_{action:02d}_{direction}_star_{star}",\n'
                    '"speed": 8.0\n'
                    "}"
                )
                frame_index += 1
    lines.extend(["[resource]", "animations = [" + ",\n".join(animations) + "]", ""])
    return "\n".join(lines)


def shared_atlas(name: str, palette_offset: int) -> Image.Image:
    atlas = Image.new("RGBA", (1024, 1024), (8, 15, 25, 0))
    draw = ImageDraw.Draw(atlas)
    for row in range(8):
        for column in range(8):
            x, y = column * 128, row * 128
            fill = PALETTE[(row + column + palette_offset) % len(PALETTE)] + (255,)
            border = (8, 15, 25, 255)
            draw.rounded_rectangle(
                (x + 12, y + 12, x + 116, y + 116),
                radius=14,
                fill=(20, 38, 58, 255),
                outline=border,
                width=6,
            )
            kind = (row * 8 + column + palette_offset) % 4
            center_x, center_y = x + 64, y + 64
            radius = 24 + ((row + column) % 3) * 4
            points = []
            count = 3 + kind
            for point in range(count):
                angle = -math.pi / 2 + point * math.tau / count
                points.append(
                    (
                        center_x + round(math.cos(angle) * radius),
                        center_y + round(math.sin(angle) * radius),
                    )
                )
            draw.polygon(points, fill=fill, outline=(237, 228, 208, 255))
            draw.line(
                (x + 28, y + 100, x + 100, y + 100),
                fill=(237, 228, 208, 255),
                width=5,
            )
    return atlas


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def build(args: argparse.Namespace) -> None:
    repo = args.repo.resolve()
    production = repo / "assets" / "production"
    master_path = production / "source" / "master_arcane_vanguard.png"
    master = transparent_master(Image.open(master_path))
    inventory: list[dict[str, object]] = []
    for index, token in enumerate(TOKENS):
        local_seed = LOCAL_SEED_BASE + index
        sheet = variant_sheet(master, index)
        source_path = production / "source_sheets" / f"{token}.png"
        portrait_path = production / "portraits" / f"{token}.png"
        board_path = production / "icons" / "board" / f"{token}.png"
        ability_path = production / "icons" / "abilities" / f"{token}.png"
        atlas_path = production / "atlases" / f"{token}.png"
        frames_path = production / "units" / f"{token}.tres"
        save_png(chroma_sheet(sheet), source_path)
        portrait = fit_rgba(sheet.crop((0, 1024, 256, 1280)), (256, 256), 8)
        board = fit_rgba(sheet.crop((0, 0, 128, 128)), (256, 256), 24)
        ability = fit_rgba(sheet.crop((512, 1024, 768, 1280)), (256, 256), 16)
        frames = quadrant_frames(sheet)
        atlas = build_atlas(frames)
        save_png(portrait, portrait_path)
        save_png(board, board_path)
        save_png(ability, ability_path)
        save_png(atlas, atlas_path)
        frames_path.parent.mkdir(parents=True, exist_ok=True)
        frames_path.write_text(sprite_frames_text(token), encoding="utf-8")
        outputs = {
            "source_sheet": source_path,
            "portrait": portrait_path,
            "board_icon": board_path,
            "ability_icon": ability_path,
            "atlas": atlas_path,
            "sprite_frames": frames_path,
        }
        hashes = {
            key: sha256(path) for key, path in outputs.items()
        }
        provenance = {
            "schema_version": 1,
            "unit_id": f"unit.{token}",
            "status": "adopted",
            "source_master": "res://assets/production/source/master_arcane_vanguard.png",
            "source_master_sha256": sha256(master_path),
            "imagegen_call_id": MASTER_CALL_ID,
            "model_native_seed": MASTER_SEED,
            "local_processing_seed": local_seed,
            "processing": {
                "script": "res://tools/content-production/build-production-assets.py",
                "pillow": PIL.__version__,
                "numpy": np.__version__,
                "canvas": [1280, 1280],
                "cell": [256, 256],
                "frame": [64, 64],
                "atlas": [1024, 1024],
                "sampling": "nearest",
                "chroma": "#ff00ff",
                "star_overlay": "non-color diamond count 1/2/3",
            },
            "outputs_sha256": hashes,
        }
        provenance_path = production / "provenance" / f"{token}.json"
        write_json(provenance_path, provenance)
        inventory.append(
            {
                "unit_id": f"unit.{token}",
                "local_processing_seed": local_seed,
                "outputs": {
                    key: str(path.relative_to(repo)).replace("\\", "/")
                    for key, path in outputs.items()
                },
                "sha256": hashes,
                "provenance": str(provenance_path.relative_to(repo)).replace(
                    "\\", "/"
                ),
            }
        )
    shared_names = (
        "trait",
        "ability",
        "status_damage",
        "combat_vfx",
        "core_ui",
    )
    shared_hashes: dict[str, str] = {}
    for index, name in enumerate(shared_names):
        path = production / "shared" / f"{name}.png"
        save_png(shared_atlas(name, index), path)
        shared_hashes[name] = sha256(path)
    camp_source = Image.open(repo / "assets" / "pilot" / "camp-corner.png").convert(
        "RGB"
    )
    camp = camp_source.resize((1280, 720), Image.Resampling.NEAREST)
    camp_path = production / "environment" / "camp.png"
    save_png(camp, camp_path)
    write_json(
        production / "inventory.json",
        {
            "schema_version": 1,
            "slice": "content-production",
            "status": "generated",
            "unit_count": len(inventory),
            "frames_per_unit": 240,
            "imagegen_call_id": MASTER_CALL_ID,
            "model_native_seed": MASTER_SEED,
            "units": inventory,
            "shared_atlases": shared_hashes,
            "camp": {
                "path": str(camp_path.relative_to(repo)).replace("\\", "/"),
                "sha256": sha256(camp_path),
            },
        },
    )
    print(f"built production raster assets for {len(inventory)} units")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
