#!/usr/bin/env python3
"""Continuously run project_parallel_wave.py until stopped, with Telegram updates."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

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


def send_update(args: argparse.Namespace, text: str) -> None:
    if not args.telegram_updates or not args.summary_target:
        return
    cmd = [
        "openclaw", "agent",
        "--agent", args.agent,
        "--message", "Send this exact Telegram update, with no extra title or commentary:\n" + text,
        "--thinking", args.summary_thinking,
        "--timeout", "120",
        "--deliver",
        "--reply-channel", args.summary_channel,
        "--reply-to", args.summary_target,
        "--json",
    ]
    cp = subprocess.run(cmd, cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log(f"telegram update rc={cp.returncode}")
    if cp.returncode != 0:
        log(f"telegram update failed: {cp.stdout[-1000:]}")


def extract_wave_json(stdout: str) -> dict[str, Any] | None:
    start = stdout.find("{\n")
    if start < 0:
        return None
    try:
        return json.loads(stdout[start:])
    except json.JSONDecodeError:
        return None


def format_wave_update(wave_count: int, rc: int, stdout: str, elapsed: float) -> str:
    data = extract_wave_json(stdout) or {}
    merged = data.get("merged") or []
    issues = data.get("issues") or []
    results = data.get("results") or []
    result_bits = []
    for item in results[:4]:
        model = str(item.get("model", "model")).split("/")[-1]
        summary = str(item.get("summary", "done"))
        result_bits.append(f"{model}: {summary}")
    head = data.get("head") or git_head()
    verify = data.get("verificationRc", rc)
    lines = [
        f"ETL parallel wave {wave_count} finished rc={rc} in {format_duration(elapsed)}.",
        f"Merged: {len(merged)} branch(es); tests rc={verify}; head={head}.",
    ]
    if result_bits:
        lines.append("Work: " + " | ".join(result_bits))
    if issues:
        lines.append("Issues: " + "; ".join(str(i) for i in issues[:3]))
    return "\n".join(lines)


def git_head() -> str:
    cp = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    return cp.stdout.strip() if cp.returncode == 0 else "unknown"


def format_duration(seconds: float) -> str:
    total = int(max(0, seconds))
    minutes, sec = divmod(total, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h{minutes:02d}m{sec:02d}s"
    if minutes:
        return f"{minutes}m{sec:02d}s"
    return f"{sec}s"


def main() -> int:
    ap = argparse.ArgumentParser(description="Run ETL parallel waves continuously until a stop file appears.")
    ap.add_argument("--models", default="anthropic/claude-opus-4.7,zai/glm-5.1")
    ap.add_argument("--parallel-max-models", type=int, default=2)
    ap.add_argument("--thinking", default="low")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--delay", type=int, default=15, help="seconds between successful waves")
    ap.add_argument("--clear-stop-files-on-start", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--continue-after-failed-wave", action=argparse.BooleanOptionalAction, default=False)
    ap.add_argument("--telegram-updates", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--summary-channel", default="telegram")
    ap.add_argument("--summary-target", default="telegram:-5117917229")
    ap.add_argument("--summary-thinking", default="low")
    ap.add_argument("--agent", default="main")
    args = ap.parse_args()

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(str(os.getpid()) + "\n", encoding="utf-8")
    if args.clear_stop_files_on_start:
        clear_stop_files()

    wave_count = 0
    started = time.time()
    start_text = f"Starting continuous ETL parallel autopilot. Models: {args.models}. Workers: {args.parallel_max_models}. Telegram updates: on."
    log(start_text)
    send_update(args, start_text)
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
            wave_start = time.time()
            cp = subprocess.run(cmd, cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            elapsed = time.time() - wave_start
            wave_log = LOG_DIR / f"parallel-autopilot-wave-{wave_count:04d}.stdout"
            wave_log.write_text(cp.stdout, encoding="utf-8")
            log(f"wave {wave_count} finished rc={cp.returncode}; output={wave_log.relative_to(REPO)}")
            send_update(args, format_wave_update(wave_count, cp.returncode, cp.stdout, elapsed))
            if cp.returncode != 0 and not args.continue_after_failed_wave:
                log("stopping because wave failed; inspect logs before continuing")
                send_update(args, f"ETL parallel autopilot paused after failed wave {wave_count}. Check {wave_log.relative_to(REPO)}.")
                return cp.returncode
            for _ in range(max(0, args.delay)):
                if stop_requested():
                    break
                time.sleep(1)
        stop_text = f"ETL parallel autopilot stopped cleanly after {wave_count} wave(s), elapsed {format_duration(time.time() - started)}. Head={git_head()}."
        log("stop file detected; exiting continuous ETL parallel autopilot")
        send_update(args, stop_text)
        return 0
    finally:
        try:
            if PID_FILE.read_text(encoding="utf-8").strip() == str(os.getpid()):
                PID_FILE.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())
