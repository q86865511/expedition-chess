"""分片 screening 的進度網頁伺服器（Python 3.14, localhost:8765）。

    python tools/balance/screening-server.py [--port 8765]

提供：

    GET  /                      進度頁（tools/balance/screening-progress.html）
    GET  /status                逐案 checkpoint 的精確進度（JSON）
    GET  /artifacts/<name>      artifacts/test 底下的唯讀靜態檔（合併報告等）
    POST /pause                 建立暫停旗標；分片跑完手上的 case 就收工
    POST /resume                呼叫 screening-ctl.ps1 resume 續跑

進度來源是 artifacts/test/screening-checkpoint/shard-NN.jsonl 的逐案記錄（精確），
不再靠數 log 行估算。JSONL 只讀新增的位元組（每片記住 offset），所以 30k case 的
輪詢成本仍然是常數級。

只綁 127.0.0.1；/pause 與 /resume 只接受 POST，且不吃任何請求內容。
"""

from __future__ import annotations

import argparse
import json
import mimetypes
import subprocess
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACT_ROOT = REPO_ROOT / "artifacts" / "test"
CHECKPOINT_ROOT = ARTIFACT_ROOT / "screening-checkpoint"
PAGE_PATH = Path(__file__).resolve().parent / "screening-progress.html"
CTL_SCRIPT = Path(__file__).resolve().parent / "screening-ctl.ps1"
STRATEGY_IDS = ("tempo", "economy", "synergy")

_lock = threading.Lock()
# path -> {"offset": int, "cases": int, "elapsed_ms": int, "strategies": {id: [cases, wins]}}
_shard_cache: dict[str, dict] = {}


def _shard_seed_count(seed_count: int, shard_count: int, shard_index: int) -> int:
    """與 tools/balance/screening-checkpoint.ps1 的 Get-ScreeningShardSeedCount 同一條公式。"""
    if shard_count <= 0 or shard_index >= seed_count:
        return 0
    return (seed_count - 1 - shard_index) // shard_count + 1


def _read_json(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def _scan_shard(path: Path) -> dict:
    """只讀自上次以來新增的完整行；檔案變小（重開新一輪）就重來。"""
    key = str(path)
    entry = _shard_cache.get(key)
    try:
        size = path.stat().st_size
    except OSError:
        _shard_cache.pop(key, None)
        return {"cases": 0, "elapsed_ms": 0, "strategies": {}}
    if entry is None or size < entry["offset"]:
        entry = {"offset": 0, "cases": 0, "elapsed_ms": 0, "strategies": {}}
        _shard_cache[key] = entry
    if size > entry["offset"]:
        with path.open("rb") as handle:
            handle.seek(entry["offset"])
            chunk = handle.read(size - entry["offset"])
        consumed = chunk.rfind(b"\n") + 1  # 尾端未完成的半行留到下次
        for raw in chunk[:consumed].split(b"\n"):
            if not raw.strip():
                continue
            try:
                record = json.loads(raw.decode("utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
            entry["cases"] += 1
            entry["elapsed_ms"] += int(record.get("primary_elapsed_ms", 0))
            strategy = str(record.get("strategy_id", "?"))
            case = record.get("case") or {}
            row = entry["strategies"].setdefault(strategy, [0, 0])
            row[0] += 1
            if bool(case.get("won")):
                row[1] += 1
        entry["offset"] += consumed
    return entry


def build_status() -> dict:
    meta = _read_json(CHECKPOINT_ROOT / "meta.json")
    state = _read_json(CHECKPOINT_ROOT / "state.json")
    pause_flag = (CHECKPOINT_ROOT / "pause.flag").exists()
    status = {
        "ok": True,
        "meta": meta,
        "state": state,
        "pause_flag": pause_flag,
        "shards": [],
        "strategies": [],
        "completed_cases": 0,
        "expected_cases": 0,
        "mean_elapsed_ms": 0,
        "eta_seconds": None,
        "merged": None,
        "updated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if meta is None:
        return status
    seed_count = int(meta.get("seed_count", 0))
    shard_count = int(meta.get("shard_count", 0))
    totals: dict[str, list[int]] = {}
    elapsed_ms = 0
    running_shards = 0
    with _lock:
        for shard_index in range(shard_count):
            path = CHECKPOINT_ROOT / f"shard-{shard_index:02d}.jsonl"
            entry = _scan_shard(path)
            shard_status = _read_json(CHECKPOINT_ROOT / f"shard-{shard_index:02d}.status.json")
            expected = _shard_seed_count(seed_count, shard_count, shard_index) * len(STRATEGY_IDS)
            state_name = str(shard_status.get("status")) if shard_status else "running"
            if state_name == "running":
                running_shards += 1
            status["shards"].append({
                "shard_index": shard_index,
                "cases": entry["cases"],
                "expected_cases": expected,
                "status": state_name,
            })
            status["completed_cases"] += entry["cases"]
            status["expected_cases"] += expected
            elapsed_ms += entry["elapsed_ms"]
            for strategy, row in entry["strategies"].items():
                total = totals.setdefault(strategy, [0, 0])
                total[0] += row[0]
                total[1] += row[1]
    status["strategies"] = [
        {
            "strategy_id": strategy,
            "cases": totals.get(strategy, [0, 0])[0],
            "wins": totals.get(strategy, [0, 0])[1],
        }
        for strategy in STRATEGY_IDS
    ]
    if status["completed_cases"] > 0:
        status["mean_elapsed_ms"] = elapsed_ms // status["completed_cases"]
        remaining = max(0, status["expected_cases"] - status["completed_cases"])
        lanes = max(1, running_shards)
        if remaining > 0 and not pause_flag:
            status["eta_seconds"] = int(remaining * (elapsed_ms / status["completed_cases"]) / lanes / 1000)
    merged_name = (
        "balance-playtest.json"
        if str(meta.get("gate_mode")) == "Final"
        else "balance-playtest-screening.json"
    )
    merged = _read_json(ARTIFACT_ROOT / merged_name)
    # 同一個 candidate 的上一輪報告會留在原地：只有「這一輪開跑之後才寫出的」才算
    # 本輪結果，否則跑到一半的畫面會顯示舊輪的 gate。
    if (
        merged is not None
        and str(merged.get("candidate_id")) == str(meta.get("candidate_id"))
        and str(merged.get("finished_at_utc", "")) >= str(meta.get("started_at_utc", ""))
    ):
        status["merged"] = {
            "artifact": merged_name,
            "gate": merged.get("gate"),
            "gate_reasons": merged.get("gate_reasons", []),
            "candidate_id": merged.get("candidate_id"),
            "finished_at_utc": merged.get("finished_at_utc"),
        }
    return status


def request_pause() -> dict:
    if not (CHECKPOINT_ROOT / "meta.json").exists():
        return {"ok": False, "detail": "no checkpoint found; nothing to pause"}
    CHECKPOINT_ROOT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    (CHECKPOINT_ROOT / "pause.flag").write_text(stamp + "\n", encoding="utf-8")
    return {"ok": True, "detail": f"pause requested at {stamp}"}


def request_resume() -> dict:
    if not (CHECKPOINT_ROOT / "meta.json").exists():
        return {"ok": False, "detail": "no checkpoint found; start a cohort first"}
    command = [
        "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
        "-File", str(CTL_SCRIPT), "resume",
    ]
    # 輸出必須導到檔案而不是 pipe：協調行程（screening-ctl 的 Start-Process 背景子代）
    # 會繼承 pipe，capture_output 會一路等到整輪跑完才回應，暫停／續跑按鈕就卡死了。
    log_path = ARTIFACT_ROOT / "balance-screening-ctl-resume.log"
    ARTIFACT_ROOT.mkdir(parents=True, exist_ok=True)
    try:
        with log_path.open("w", encoding="utf-8", errors="replace") as handle:
            completed = subprocess.run(
                command, cwd=str(REPO_ROOT), stdin=subprocess.DEVNULL,
                stdout=handle, stderr=subprocess.STDOUT, timeout=120
            )
    except (OSError, subprocess.SubprocessError) as error:
        return {"ok": False, "detail": f"resume failed to launch: {error}"}
    detail = log_path.read_text(encoding="utf-8", errors="replace").strip()
    return {"ok": completed.returncode == 0, "detail": detail, "exit_code": completed.returncode}


class ScreeningHandler(BaseHTTPRequestHandler):
    server_version = "BalanceScreeningProgress/1.0"

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, payload: dict, code: int = 200) -> None:
        self._send(code, json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8")

    def do_GET(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html", "/screening-progress.html"):
            try:
                body = PAGE_PATH.read_bytes()
            except OSError:
                self._send(500, b"progress page missing", "text/plain; charset=utf-8")
                return
            self._send(200, body, "text/html; charset=utf-8")
            return
        if path == "/status":
            self._send_json(build_status())
            return
        if path.startswith("/artifacts/"):
            name = path[len("/artifacts/"):]
            target = (ARTIFACT_ROOT / name).resolve()
            if not str(target).startswith(str(ARTIFACT_ROOT.resolve())) or not target.is_file():
                self._send(404, b"not found", "text/plain; charset=utf-8")
                return
            guessed = mimetypes.guess_type(target.name)[0] or "application/octet-stream"
            self._send(200, target.read_bytes(), guessed)
            return
        self._send(404, b"not found", "text/plain; charset=utf-8")

    def do_POST(self) -> None:  # noqa: N802 (BaseHTTPRequestHandler API)
        path = self.path.split("?", 1)[0]
        if path == "/pause":
            self._send_json(request_pause())
            return
        if path == "/resume":
            self._send_json(request_resume())
            return
        self._send(404, b"not found", "text/plain; charset=utf-8")

    def log_message(self, format: str, *args) -> None:  # noqa: A002 (BaseHTTPRequestHandler API)
        sys.stderr.write("%s %s\n" % (time.strftime("%H:%M:%S"), format % args))


def main() -> int:
    parser = argparse.ArgumentParser(description="Balance screening progress server")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--host", default="127.0.0.1")
    arguments = parser.parse_args()
    server = ThreadingHTTPServer((arguments.host, arguments.port), ScreeningHandler)
    print(f"screening progress on http://{arguments.host}:{arguments.port}/ "
          f"(checkpoint: {CHECKPOINT_ROOT})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
