from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PINNED_PACKAGE_ROOT = REPO_ROOT / ".pipeline" / "content-production" / "python-packages"
if PINNED_PACKAGE_ROOT.is_dir():
    sys.path.insert(0, str(PINNED_PACKAGE_ROOT))

import numpy as np
import soundfile as sf


SAMPLE_RATE = 48_000
CHANNELS = 2
MUSIC_SECONDS = 24
VORBIS_QUALITY = 0.5
TRUE_PEAK_TARGET_DBFS = -3.0
LOOP_SEAM_SECONDS = 0.05
LOCAL_SEED_BASE = 0x47324155
SOUNDFILE_WHEEL_SHA256 = (
    "1e70a05a0626524a69e9f0f4dd2ec174b4e9567f4d8b6c11d38b5c289be36ee9"
)
MUSIC = {
    "menu": (55.0, (0, 4, 7, 11)),
    "camp": (65.406, (0, 3, 7, 10)),
    "expedition": (73.416, (0, 5, 7, 12)),
    "combat": (82.407, (0, 2, 7, 10)),
    "results": (61.735, (0, 4, 7, 12)),
}
SFX = (
    "ui_confirm",
    "ui_cancel",
    "ui_focus",
    "ui_error",
    "shop_buy",
    "shop_sell",
    "shop_refresh",
    "forge",
    "equip",
    "reward_select",
    "event_select",
    "combat_cast",
    "combat_melee_hit",
    "combat_defeat",
    "combat_shield",
    "combat_heal",
    "combat_death",
    "combat_ranged_attack",
    "combat_magic_hit",
    "combat_boss_warning",
    "combat_victory",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def dbfs(peak: float) -> float:
    return 20.0 * math.log10(max(peak, 1.0e-12))


def oversampled_true_peak(samples: np.ndarray, factor: int = 4) -> float:
    decoded = np.asarray(samples, dtype=np.float64)
    if decoded.ndim == 1:
        decoded = decoded[:, None]
    source = np.arange(decoded.shape[0], dtype=np.float64)
    target = np.linspace(
        0.0,
        float(decoded.shape[0] - 1),
        (decoded.shape[0] - 1) * factor + 1,
        dtype=np.float64,
    )
    peak = 0.0
    for channel in range(decoded.shape[1]):
        peak = max(peak, float(np.max(np.abs(np.interp(target, source, decoded[:, channel])))))
    return peak


def normalize_true_peak(samples: np.ndarray) -> np.ndarray:
    peak = oversampled_true_peak(samples)
    target = 10.0 ** (TRUE_PEAK_TARGET_DBFS / 20.0)
    if peak <= target:
        return samples.astype(np.float32)
    return (samples * (target / peak)).astype(np.float32)


def synth_music(index: int, root: float, intervals: tuple[int, ...]) -> np.ndarray:
    sample_count = SAMPLE_RATE * MUSIC_SECONDS
    time = np.arange(sample_count, dtype=np.float64) / SAMPLE_RATE
    phase = math.tau * index / len(MUSIC)
    left = np.zeros(sample_count, dtype=np.float64)
    right = np.zeros(sample_count, dtype=np.float64)
    for voice, semitones in enumerate(intervals):
        frequency = root * (2.0 ** (semitones / 12.0))
        periodic_frequency = round(frequency * MUSIC_SECONDS) / MUSIC_SECONDS
        amplitude = 0.13 / (voice + 1) ** 0.55
        left += amplitude * np.sin(math.tau * periodic_frequency * time + phase)
        right += amplitude * np.sin(
            math.tau * periodic_frequency * time + phase + 0.18 * (voice + 1)
        )
    pulse = 0.82 + 0.18 * np.sin(math.tau * 2.0 * time + phase)
    shimmer = 0.025 * np.sin(
        math.tau * (round((root * 4.0) * MUSIC_SECONDS) / MUSIC_SECONDS) * time
    )
    stereo = np.column_stack(((left + shimmer) * pulse, (right - shimmer) * pulse))
    stereo = np.tanh(stereo * 1.15)
    seam_frames = round(SAMPLE_RATE * LOOP_SEAM_SECONDS)
    transition_start = stereo.shape[0] - seam_frames * 2
    transition_end = stereo.shape[0] - seam_frames
    fade = np.linspace(0.0, 1.0, seam_frames, endpoint=False, dtype=np.float64)[:, None]
    stereo[transition_start:transition_end] = (
        stereo[transition_start:transition_end] * (1.0 - fade)
        + stereo[:seam_frames] * fade
    )
    stereo[-seam_frames:] = stereo[:seam_frames]
    return normalize_true_peak(stereo)


def synth_sfx(index: int) -> np.ndarray:
    duration = 0.22 + (index % 5) * 0.055
    sample_count = round(SAMPLE_RATE * duration)
    time = np.arange(sample_count, dtype=np.float64) / SAMPLE_RATE
    rng = np.random.default_rng(LOCAL_SEED_BASE + 100 + index)
    base = 170.0 + index * 23.0
    sweep = base * (1.0 + (0.8 if index % 2 == 0 else -0.35) * time / duration)
    phase = math.tau * np.cumsum(sweep) / SAMPLE_RATE
    tonal = np.sin(phase) + 0.35 * np.sin(phase * 2.01)
    noise = rng.normal(0.0, 1.0, sample_count)
    attack = np.minimum(1.0, time / 0.008)
    release = np.maximum(0.0, 1.0 - time / duration) ** (1.8 + index % 3)
    mix = (0.72 * tonal + 0.18 * noise) * attack * release
    if "combat" in SFX[index]:
        mix += 0.10 * np.sin(phase * 0.5) * release
    mono = np.tanh(mix * 0.62)
    delay = 7 + index % 11
    delayed = np.roll(mono, delay)
    delayed[:delay] = 0.0
    stereo = np.column_stack((mono, 0.94 * mono + 0.06 * delayed))
    return normalize_true_peak(stereo)


def write_ogg(path: Path, samples: np.ndarray) -> dict[str, object]:
    path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(
        path,
        samples,
        SAMPLE_RATE,
        format="OGG",
        subtype="VORBIS",
        compression_level=VORBIS_QUALITY,
    )
    info = sf.info(path)
    decoded, decoded_rate = sf.read(path, dtype="float32", always_2d=True)
    peak = oversampled_true_peak(decoded)
    return {
        "path": path,
        "sha256": sha256(path),
        "sample_rate": decoded_rate,
        "channels": info.channels,
        "frames": info.frames,
        "duration_seconds": round(info.duration, 6),
        "format": info.format,
        "subtype": info.subtype,
        "true_peak_dbfs": round(dbfs(peak), 4),
        "decoded": decoded,
    }


def loop_seam_rms_dbfs(decoded: np.ndarray) -> float:
    seam_frames = round(SAMPLE_RATE * LOOP_SEAM_SECONDS)
    difference = decoded[:seam_frames] - decoded[-seam_frames:]
    rms = float(np.sqrt(np.mean(np.square(difference, dtype=np.float64))))
    return dbfs(rms)


def audio_resource_text(token: str, relative_path: str, bus: str, loop: bool) -> str:
    return (
        '[gd_resource type="Resource" script_class="AudioCueDef" format=3]\n\n'
        '[ext_resource type="Script" '
        'path="res://content/definitions/audio_cue_def.gd" id="1_audio"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_audio")\n'
        f'bus = &"{bus}"\n'
        f'stream_path = "res://{relative_path}"\n'
        f"loop = {str(loop).lower()}\n"
        f'id = &"audio.{token}"\n'
        f'display_name_key = &"loc.audio_{token}"\n'
    )


def public_entry(raw: dict[str, object], repo: Path, bus: str, loop: bool) -> dict:
    path = raw["path"]
    assert isinstance(path, Path)
    return {
        "cue_id": f"audio.{path.stem}",
        "path": str(path.relative_to(repo)).replace("\\", "/"),
        "sha256": raw["sha256"],
        "bus": bus,
        "loop": loop,
        "sample_rate": raw["sample_rate"],
        "channels": raw["channels"],
        "frames": raw["frames"],
        "duration_seconds": raw["duration_seconds"],
        "container": raw["format"],
        "codec": raw["subtype"],
        "true_peak_dbfs": raw["true_peak_dbfs"],
    }


def build(repo: Path) -> None:
    audio_root = repo / "assets" / "production" / "audio"
    cue_root = repo / "content" / "packs" / "vertical_slice" / "audio_cues"
    music_entries: list[dict] = []
    sfx_entries: list[dict] = []
    for index, (token, (root, intervals)) in enumerate(MUSIC.items()):
        raw = write_ogg(audio_root / "music" / f"{token}.ogg", synth_music(index, root, intervals))
        entry = public_entry(raw, repo, "Music", True)
        entry["local_processing_seed"] = LOCAL_SEED_BASE + index
        entry["loop_seam_rms_dbfs"] = round(loop_seam_rms_dbfs(raw["decoded"]), 4)
        music_entries.append(entry)
        relative = str(raw["path"].relative_to(repo)).replace("\\", "/")
        with (cue_root / f"{token}.tres").open(
            "w", encoding="utf-8", newline="\n"
        ) as handle:
            handle.write(audio_resource_text(token, relative, "Music", True))
    for index, token in enumerate(SFX):
        raw = write_ogg(audio_root / "sfx" / f"{token}.ogg", synth_sfx(index))
        bus = "UI" if token.startswith("ui_") else "SFX"
        entry = public_entry(raw, repo, bus, False)
        entry["local_processing_seed"] = LOCAL_SEED_BASE + 100 + index
        sfx_entries.append(entry)
        relative = str(raw["path"].relative_to(repo)).replace("\\", "/")
        with (cue_root / f"{token}.tres").open(
            "w", encoding="utf-8", newline="\n"
        ) as handle:
            handle.write(audio_resource_text(token, relative, bus, False))
    inventory = {
        "schema_version": 1,
        "slice": "content-production",
        "status": "adopted",
        "sample_rate": SAMPLE_RATE,
        "channels": CHANNELS,
        "container": "OGG",
        "codec": "VORBIS",
        "encoder": {
            "soundfile_version": sf.__version__,
            "libsndfile_version": sf.__libsndfile_version__,
            "wheel": "soundfile-0.13.1-py2.py3-none-win_amd64.whl",
            "wheel_sha256": SOUNDFILE_WHEEL_SHA256,
            "python": sys.version.split()[0],
            "vorbis_quality": VORBIS_QUALITY,
            "compression_level": VORBIS_QUALITY,
        },
        "synthesis": {
            "script": "tools/content-production/generate-production-audio.py",
            "local_seed_base": LOCAL_SEED_BASE,
            "music_seconds": MUSIC_SECONDS,
            "loop_seam_window_ms": round(LOOP_SEAM_SECONDS * 1000),
            "true_peak_oversample": 4,
            "music_recipe": "periodic additive synthesis with exact integer loop cycles",
            "sfx_recipe": "seeded tonal sweep plus shaped noise",
        },
        "music": music_entries,
        "sfx": sfx_entries,
    }
    inventory_path = audio_root / "inventory.json"
    with inventory_path.open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(json.dumps(inventory, ensure_ascii=False, indent=2) + "\n")
    print(
        f"generated {len(music_entries)} loop music and {len(sfx_entries)} semantic SFX"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args().repo.resolve())
