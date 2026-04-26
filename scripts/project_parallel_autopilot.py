#!/usr/bin/env python3
"""Continuously run project_parallel_wave.py until stopped."""
from __future__ import annotations

import argparse
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STATE_DIR = REPO / "state"
LOG_DIR = REPO / "logs"
STOP_FILES = [
    STATE_DIR / "STOP_ETL_PARALLEL",
    STATE_DIR / "STOP_ETL_AUTOPILOT",
    STATE_DIR / "STOP_AUTOPILOT",
]
PID_FILE = STATE_DIR / "etl-parallel-autopilot.pid"
LOG_FILE = LOG_DIR / "parallel-autopilot.log"


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log(msg: str) -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    line = f"[{now()}] {msg}\n"
    print(line, end="", flush=True)
    with LOG_FILE.open("a", encoding="utf-8") as f:
        f.write(line)


def stop_requested() -> bool:
    return any(path.exists() for path in STOP_FILES)


def clear_stop_files() -> None:
    for path in STOP_FILES:
        path.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser(description="Run ETL parallel waves continuously until a stop file appears.")
    ap.add_argument("--models", default="anthropic/claude-opus-4.7,zai/glm-5.1")
    ap.add_argument("--parallel-max-models", type=int, default=2)
    ap.add_argument("--thinking", default="low")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--delay", type=int, default=15, help="seconds between successful waves")
    ap.add_argument("--clear-stop-files-on-start", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--continue-after-failed-wave", action=argparse.BooleanOptionalAction, default=False)
    args = ap.parse_args()

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(__import__("os").getpid()) + "\n", encoding="utf-8")
    if args.clear_stop_files_on_start:
        clear_stop_files()

    wave_count = 0
    log(f"starting continuous ETL parallel autopilot models={args.models} max={args.parallel_max_models} thinking={args.thinking}")
    try:
        while not stop_requested():
            wave_count += 1
            log(f"starting wave {wave_count}")
            cmd = [
                str(REPO / "scripts" / "project_parallel_wave.py"),
                "--models", args.models,
                "--parallel-max-models", str(args.parallel_max_models),
                "--thinking", args.thinking,
                "--timeout", str(args.timeout),
            ]
            cp = subprocess.run(cmd, cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            wave_log = LOG_DIR / f"parallel-autopilot-wave-{wave_count:04d}.stdout"
            wave_log.write_text(cp.stdout, encoding="utf-8")
            log(f"wave {wave_count} finished rc={cp.returncode}; output={wave_log.relative_to(REPO)}")
            if cp.returncode != 0 and not args.continue_after_failed_wave:
                log("stopping because wave failed; inspect logs before continuing")
                return cp.returncode
            for _ in range(max(0, args.delay)):
                if stop_requested():
                    break
                time.sleep(1)
        log("stop file detected; exiting continuous ETL parallel autopilot")
        return 0
    finally:
        try:
            if PID_FILE.read_text(encoding="utf-8").strip() == str(__import__("os").getpid()):
                PID_FILE.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
