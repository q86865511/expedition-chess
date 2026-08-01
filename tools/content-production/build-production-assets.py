from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import sys
from datetime import datetime
from pathlib import Path

import numpy as np
import PIL
from PIL import Image, ImageDraw, ImageOps


TOKENS = [
    *(f"slice_monster_{index:02d}" for index in range(12)),
    *(f"slice_player_{index:02d}" for index in range(32)),
]
DIRECTIONS = ("n", "e", "s", "w")
ACTION_SPECS = (
    ("idle", 2, 4.0, True),
    ("move", 4, 8.0, True),
    ("attack", 4, 10.0, False),
    ("cast", 4, 10.0, False),
    ("hit", 2, 8.0, False),
    ("death", 4, 8.0, False),
)
SHARED_NAMES = ("trait", "ability", "status_damage", "combat_vfx", "core_ui")
BADGE_ACCENTS = (
    (55, 214, 190, 255),
    (244, 177, 72, 255),
    (144, 112, 255, 255),
    (239, 89, 122, 255),
    (106, 181, 255, 255),
    (135, 201, 91, 255),
)
LOCAL_SEED_BASE = 0x47325052
REVIEW_RELATIVE_PATH = ".pipeline/content-production/reviews/t18a-full-batch-claude-review.md"
PRIOR_REVIEW_RELATIVE_PATH = ".pipeline/content-production/reviews/t18a-player-batch-001.md"
LEDGER_RELATIVE_PATH = "assets/production/production-asset-attempts.json"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def relative(repo: Path, path: Path) -> str:
    return str(path.relative_to(repo)).replace("\\", "/")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def write_text_lf(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(value)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=False, compress_level=9)


def is_chroma(pixel: tuple[int, ...]) -> bool:
    red, green, blue = pixel[:3]
    return red >= 160 and blue >= 160 and green <= 150 and min(red, blue) - green >= 45


def clear_connected_chroma(image: Image.Image) -> Image.Image:
    result = image.convert("RGBA")
    width, height = result.size
    seeds = (
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    )
    pixels = result.load()
    assert pixels is not None
    for seed in seeds:
        if is_chroma(pixels[seed[0], seed[1]]):
            ImageDraw.floodfill(result, seed, (0, 0, 0, 0), thresh=135)
    array = np.asarray(result).copy()
    strict_chroma = (
        (array[:, :, 0] >= 145)
        & (array[:, :, 1] <= 150)
        & (array[:, :, 2] >= 145)
        & (
            np.minimum(array[:, :, 0], array[:, :, 2]).astype(np.int16)
            - array[:, :, 1]
            >= 45
        )
        & (np.abs(array[:, :, 0].astype(np.int16) - array[:, :, 2]) <= 70)
    )
    array[strict_chroma, 3] = 0
    return Image.fromarray(array, "RGBA")


def normalize_generated_sheet(source: Image.Image) -> Image.Image:
    """Normalize each independent 5x5 ImageGen cell without identity reuse."""
    source = source.convert("RGBA")
    width, height = source.size
    normalized = Image.new("RGBA", (1280, 1280), (0, 0, 0, 0))
    for row in range(5):
        for column in range(5):
            left = round(width * column / 5.0)
            right = round(width * (column + 1) / 5.0)
            top = round(height * row / 5.0)
            bottom = round(height * (row + 1) / 5.0)
            margin = max(3, round(min(right - left, bottom - top) * 0.018))
            cell = source.crop(
                (left + margin, top + margin, right - margin, bottom - margin)
            ).resize((256, 256), Image.Resampling.NEAREST)
            normalized.alpha_composite(clear_connected_chroma(cell), (column * 256, row * 256))
    return normalized


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
        subject,
        ((size[0] - target[0]) // 2, (size[1] - target[1]) // 2),
    )
    return output


def badge_icon(subject: Image.Image, seed: int, shape: str) -> Image.Image:
    badge = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    draw = ImageDraw.Draw(badge)
    accent = BADGE_ACCENTS[seed % len(BADGE_ACCENTS)]
    ink = (8, 15, 25, 238)
    ivory = (237, 228, 208, 255)
    if shape == "circle":
        draw.ellipse((25, 25, 231, 231), fill=ink, outline=ivory, width=8)
        draw.ellipse((37, 37, 219, 219), outline=accent, width=7)
    else:
        outer = [(128, 18), (231, 82), (210, 220), (128, 242), (46, 220), (25, 82)]
        inner = [(128, 34), (214, 88), (195, 207), (128, 225), (61, 207), (42, 88)]
        draw.polygon(outer, fill=ivory)
        draw.polygon(inner, fill=ink, outline=accent)
    badge.alpha_composite(fit_rgba(subject, (256, 256), 34))
    return badge


def portrait_from_raw(source: Image.Image) -> Image.Image:
    source = source.convert("RGBA")
    cell_width = round(source.width / 5.0)
    cell_height = round(source.height / 5.0)
    margin = 5
    cell = source.crop(
        (
            margin,
            4 * cell_height + margin,
            cell_width - margin,
            5 * cell_height - margin,
        )
    ).resize((248, 248), Image.Resampling.NEAREST)
    cell = clear_connected_chroma(cell)
    output = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    output.alpha_composite(cell, (4, 4))
    return output


def quadrant_frames(sheet: Image.Image) -> list[Image.Image]:
    frames: list[Image.Image] = []
    for action in range(20):
        row, column = divmod(action, 5)
        cell = sheet.crop(
            (column * 256, row * 256, (column + 1) * 256, (row + 1) * 256)
        )
        margin = 5
        quadrants = (
            cell.crop((margin, margin, 128 - margin, 128 - margin)),
            cell.crop((128 + margin, margin, 256 - margin, 128 - margin)),
            cell.crop((128 + margin, 128 + margin, 256 - margin, 256 - margin)),
            cell.crop((margin, 128 + margin, 128 - margin, 256 - margin)),
        )
        for direction_index, quadrant in enumerate(quadrants):
            if not quadrant.getbbox():
                raise ValueError(
                    f"action cell {action} direction {DIRECTIONS[direction_index]} is empty"
                )
            frames.append(fit_rgba(quadrant, (64, 64), 4))
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
    if len(frames) != 80:
        raise ValueError(f"expected 80 base frames, got {len(frames)}")
    atlas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    output_frames = [star_frame(frame, star) for star in range(1, 4) for frame in frames]
    for index, frame in enumerate(output_frames):
        atlas.alpha_composite(frame, ((index % 16) * 64, (index // 16) * 64))
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
    animations: list[str] = []
    for star in range(1, 4):
        for direction_index, direction in enumerate(DIRECTIONS):
            action_offset = 0
            for action, frame_count, speed, loop in ACTION_SPECS:
                animation_frames = []
                for local_frame in range(frame_count):
                    source_action = action_offset + local_frame
                    frame_index = (star - 1) * 80 + source_action * 4 + direction_index
                    animation_frames.append(
                        "{\n"
                        '"duration": 1.0,\n'
                        f'"texture": SubResource("AtlasTexture_{frame_index:03d}")\n'
                        "}"
                    )
                animations.append(
                    "{\n"
                    f'"frames": [{",".join(animation_frames)}],\n'
                    f'"loop": {str(loop).lower()},\n'
                    f'"name": &"{action}_{direction}_star{star}",\n'
                    f'"speed": {speed:.1f}\n'
                    "}"
                )
                action_offset += frame_count
    lines.extend(["[resource]", "animations = [" + ",\n".join(animations) + "]", ""])
    return "\n".join(lines)


def adopt_reviewed_attempts(repo: Path, review_sha: str) -> tuple[dict, dict[str, dict]]:
    ledger_path = repo / LEDGER_RELATIVE_PATH
    ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
    attempts: list[dict] = ledger.get("attempts", [])
    reviewed_at = datetime.now().astimezone().isoformat(timespec="seconds")
    adopted_now = 0
    for attempt in attempts:
        if attempt.get("status") != "generated":
            continue
        attempt["status"] = "adopted"
        attempt["review"] = {
            "reviewer": "claude:independent-t18a-reviewer",
            "decision": "adopted",
            "reviewed_at": reviewed_at,
            "review_record_sha256": review_sha,
            "reason": "Adopted by the aggregate T18A review; no rejection recorded.",
        }
        adopted_now += 1
    if adopted_now not in (0, 40):
        raise ValueError(f"expected to adopt 40 pending attempts, adopted {adopted_now}")
    ledger["updated_at"] = reviewed_at
    active: dict[str, dict] = {}
    for attempt in attempts:
        if attempt.get("status") != "adopted":
            continue
        unit_id = str(attempt.get("unit_id", ""))
        if unit_id in active:
            raise ValueError(f"multiple adopted attempts for {unit_id}")
        active[unit_id] = attempt
    if set(active) != {f"unit.{token}" for token in TOKENS}:
        raise ValueError("ledger does not contain exactly one adopted attempt for every unit")
    write_json(ledger_path, ledger)
    return ledger, active


def build(args: argparse.Namespace) -> None:
    repo = args.repo.resolve()
    production = repo / "assets" / "production"
    review_path = repo / REVIEW_RELATIVE_PATH
    if not review_path.is_file():
        raise FileNotFoundError(f"missing aggregate review: {review_path}")
    review_text = review_path.read_text(encoding="utf-8")
    if "全部 adopted" not in review_text or "退件:無" not in review_text:
        raise ValueError("aggregate review does not record an all-adopted/no-rejection verdict")
    review_sha = sha256(review_path)
    prior_review_path = repo / PRIOR_REVIEW_RELATIVE_PATH
    prior_review_sha = sha256(prior_review_path)
    ledger, adopted = adopt_reviewed_attempts(repo, review_sha)
    ledger_path = repo / LEDGER_RELATIVE_PATH
    processor_sha = sha256(Path(__file__).resolve())
    tool_versions = {
        "python": platform.python_version(),
        "python_implementation": platform.python_implementation(),
        "pillow": PIL.__version__,
        "numpy": np.__version__,
        "script": "tools/content-production/build-production-assets.py",
        "script_sha256": processor_sha,
    }
    inventory_units: list[dict[str, object]] = []
    for index, token in enumerate(TOKENS):
        unit_id = f"unit.{token}"
        attempt = adopted[unit_id]
        raw_path = repo / str(attempt["raw_source"]["path"])
        if sha256(raw_path) != attempt["raw_source"]["sha256"]:
            raise ValueError(f"raw source hash mismatch: {attempt['attempt_id']}")
        with Image.open(raw_path) as raw:
            sheet = normalize_generated_sheet(raw)
            portrait = portrait_from_raw(raw)
        source_path = production / "source_sheets" / f"{token}.png"
        portrait_path = production / "portraits" / f"{token}.png"
        board_path = production / "icons" / "board" / f"{token}.png"
        ability_path = production / "icons" / "abilities" / f"{token}.png"
        atlas_path = production / "atlases" / f"{token}.png"
        frames_path = production / "units" / f"{token}.tres"
        provenance_path = production / "provenance" / f"{token}.json"
        save_png(chroma_sheet(sheet), source_path)
        save_png(portrait, portrait_path)
        save_png(badge_icon(sheet.crop((5, 5, 123, 123)), index, "circle"), board_path)
        save_png(badge_icon(sheet.crop((520, 1032, 760, 1272)), index + 2, "shield"), ability_path)
        frames = quadrant_frames(sheet)
        save_png(build_atlas(frames), atlas_path)
        write_text_lf(frames_path, sprite_frames_text(token))
        outputs = {
            "source_sheet": source_path,
            "portrait": portrait_path,
            "board_icon": board_path,
            "ability_icon": ability_path,
            "atlas": atlas_path,
            "sprite_frames": frames_path,
        }
        hashes = {name: sha256(path) for name, path in outputs.items()}
        local_seed = LOCAL_SEED_BASE + index
        attempt_review_sha = attempt["review"]["review_record_sha256"]
        if attempt_review_sha == review_sha:
            attempt_review_path = REVIEW_RELATIVE_PATH
        elif attempt_review_sha == prior_review_sha:
            attempt_review_path = PRIOR_REVIEW_RELATIVE_PATH
        else:
            raise ValueError(f"unknown review record SHA for {attempt['attempt_id']}")
        provenance = {
            "schema_version": 2,
            "unit_id": unit_id,
            "status": "adopted",
            "adopted_attempt_id": attempt["attempt_id"],
            "source_attempt": {
                "path": attempt["raw_source"]["path"],
                "sha256": attempt["raw_source"]["sha256"],
                "imagegen_output_id": attempt["generation"]["imagegen_output_id"],
                "call_id": attempt["generation"].get("call_id"),
                "call_id_exposure": attempt["generation"].get("call_id_exposure"),
                "model_native_seed": attempt["generation"]["model_native_seed"],
                "prompt": attempt["generation"]["prompt"],
            },
            "review": {
                "path": attempt_review_path,
                "sha256": attempt_review_sha,
                "reviewer": attempt["review"]["reviewer"],
                "decision": attempt["review"]["decision"],
            },
            "local_processing_seed": local_seed,
            "processing": {
                **tool_versions,
                "canvas": [1280, 1280],
                "grid": [5, 5],
                "action_cells": 20,
                "directions": list(DIRECTIONS),
                "frame": [64, 64],
                "atlas": [1024, 1024],
                "sampling": "nearest",
                "chroma": "#ff00ff",
                "star_overlay": "non-color diamond count 1/2/3",
                "icon_badges": "deterministic non-color circle/shield backing",
            },
            "outputs_sha256": hashes,
        }
        write_json(provenance_path, provenance)
        inventory_units.append(
            {
                "unit_id": unit_id,
                "status": "adopted",
                "adopted_attempt_id": attempt["attempt_id"],
                "source": {
                    "path": attempt["raw_source"]["path"],
                    "sha256": attempt["raw_source"]["sha256"],
                },
                "local_processing_seed": local_seed,
                "outputs": {name: relative(repo, path) for name, path in outputs.items()},
                "sha256": hashes,
                "provenance": relative(repo, provenance_path),
            }
        )

    shared_inventory: dict[str, dict[str, str]] = {}
    for name in SHARED_NAMES:
        source = production / "shared_attempts" / "attempt-001" / f"{name}.png"
        destination = production / "shared" / f"{name}.png"
        if not source.is_file():
            raise FileNotFoundError(f"missing adopted shared atlas candidate: {source}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        shared_inventory[name] = {
            "status": "adopted",
            "adopted_attempt_id": "shared-atlas-attempt-001",
            "source_path": relative(repo, source),
            "source_sha256": sha256(source),
            "path": relative(repo, destination),
            "sha256": sha256(destination),
            "review_record_sha256": review_sha,
        }

    camp_source = production / "camp_attempts" / "attempt-001" / "raw.png"
    camp_path = production / "environment" / "camp.png"
    with Image.open(camp_source) as raw_camp:
        camp = ImageOps.fit(
            raw_camp.convert("RGB"),
            (1280, 720),
            method=Image.Resampling.NEAREST,
            centering=(0.5, 0.5),
        )
    save_png(camp, camp_path)

    inventory = {
        "schema_version": 2,
        "slice": "content-production",
        "status": "adopted",
        "unit_count": len(inventory_units),
        "frames_per_unit": 240,
        "animations_per_unit": 72,
        "attempt_ledger": {
            "path": LEDGER_RELATIVE_PATH,
            "sha256": sha256(ledger_path),
            "attempt_count": len(ledger["attempts"]),
        },
        "review_record": {"path": REVIEW_RELATIVE_PATH, "sha256": review_sha},
        "processor": tool_versions,
        "units": inventory_units,
        "shared_atlases": shared_inventory,
        "camp": {
            "status": "adopted",
            "adopted_attempt_id": "camp-attempt-001",
            "source_path": relative(repo, camp_source),
            "source_sha256": sha256(camp_source),
            "path": relative(repo, camp_path),
            "sha256": sha256(camp_path),
            "review_record_sha256": review_sha,
        },
    }
    write_json(production / "inventory.json", inventory)
    print(
        f"adopted and built production raster assets for {len(inventory_units)} units "
        f"from {len(ledger['attempts'])} preserved attempts"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
