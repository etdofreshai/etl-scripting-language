#!/usr/bin/env python3
"""Run one or more parallel OpenClaw autopilot waves using git worktrees.

Each worker gets an isolated worktree/branch, makes a small verified commit, and
this script merges successful branches back into the main worktree sequentially.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import time
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[1]
WORKTREES_DIR = REPO / ".worktrees"
LOG_DIR = REPO / "logs"
STATE_DIR = REPO / "state"
WAVE_STATE_FILE = STATE_DIR / "parallel-wave-state.json"


def run(cmd: list[str], *, cwd: Path = REPO, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)


def parse_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def slug(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip("-").lower() or "worker"


def git_head(full: bool = False) -> str:
    cmd = ["git", "rev-parse", "HEAD"] if full else ["git", "rev-parse", "--short", "HEAD"]
    cp = run(cmd)
    return cp.stdout.strip() if cp.returncode == 0 else "unknown"


def next_wave_number() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    if WAVE_STATE_FILE.exists():
        try:
            state = json.loads(WAVE_STATE_FILE.read_text(encoding="utf-8"))
            last = int(state.get("lastWaveNumber", 0))
        except Exception:
            last = 0
    else:
        last = 0
    number = last + 1
    WAVE_STATE_FILE.write_text(json.dumps({"lastWaveNumber": number, "updatedAt": time.time()}, indent=2) + "\n", encoding="utf-8")
    return number


def extract_text(json_text: str) -> str:
    try:
        data = json.loads(json_text)
        payloads = (((data.get("result") or {}).get("payloads")) or [])
        texts = [p.get("text", "") for p in payloads if isinstance(p, dict) and p.get("text")]
        return "\n".join(texts) if texts else json_text
    except Exception:
        return json_text


def short_summary(json_text: str) -> str:
    text = extract_text(json_text)
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    for line in lines:
        if line.startswith("-"):
            return line.lstrip("- ")[:180]
    return (lines[0] if lines else "no summary")[:180]


def branch_has_commits(branch: str, base: str) -> bool:
    cp = run(["git", "rev-list", "--count", f"{base}..{branch}"])
    return cp.returncode == 0 and cp.stdout.strip() not in ("", "0")


def create_worktree(branch: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        run(["git", "worktree", "remove", "--force", str(path)], timeout=120)
    cp = run(["git", "worktree", "add", "-B", branch, str(path), "HEAD"], timeout=180)
    if cp.returncode != 0:
        raise RuntimeError(cp.stdout)


def build_prompt(args: argparse.Namespace, model: str, wave_id: str, worktree: Path) -> str:
    context_lines = "\n".join(f"- Read {p}." for p in args.context_files)
    return f"""
Run one parallel-wave {args.project_name} autopilot task in this isolated git worktree: {worktree}

Wave: {wave_id}
Preferred model for this worker: {model}. If runtime model switching is unavailable, use this as your review/decision-making perspective.

Rules:
- Work only inside this worktree: {worktree}
- Do not edit the main worktree at {REPO}.
{context_lines}
- Project goal: {args.project_goal}
- Verification focus: {args.verification_focus}
- Keep work small and low-conflict with other parallel workers.
- Do not edit merge-hot `state/autopilot.md` directly in parallel wave mode unless essential.
- Record worker notes under `state/parallel-wave-notes/{wave_id}-{slug(model)}.md`.
- Prefer different areas than other likely workers: docs/spec, lexer/parser tests, codegen tests, compiler implementation, build tooling.
- Run the best relevant verification.
- Commit useful changes locally on this worktree branch.
- Do not push.
{args.extra_instruction}

Final output: commit hash, files changed, verification, blockers, and next suggestion.
""".strip()


def launch_worker(args: argparse.Namespace, model: str, wave_id: str, branch: str, worktree: Path) -> subprocess.Popen[str]:
    prompt = build_prompt(args, model, wave_id, worktree)
    cmd = [
        "openclaw", "agent",
        "--agent", args.agent,
        "--session-id", f"{args.project_slug}-wave-{wave_id}-{slug(model)}",
        "--message", prompt,
        "--thinking", args.thinking,
        "--timeout", str(args.timeout),
        "--json",
    ]
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"parallel-wave-{wave_id}-{slug(model)}.jsonlog"
    f = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(cmd, cwd=worktree, text=True, stdout=f, stderr=subprocess.STDOUT)
    proc._openclaw_log_file = f  # type: ignore[attr-defined]
    proc._openclaw_log_path = log_path  # type: ignore[attr-defined]
    proc._openclaw_branch = branch  # type: ignore[attr-defined]
    proc._openclaw_model = model  # type: ignore[attr-defined]
    proc._openclaw_started = time.time()  # type: ignore[attr-defined]
    return proc


def run_wave(args: argparse.Namespace) -> int:
    status = run(["git", "status", "--porcelain"])
    if status.stdout.strip():
        raise SystemExit("main worktree is dirty; commit/stash before running a parallel wave")
    base = git_head(full=True)
    wave_no = next_wave_number()
    wave_id = f"{wave_no:04d}"
    models = parse_csv(args.models)[: args.parallel_max_models]
    if not models:
        raise SystemExit("no models configured")
    procs: list[subprocess.Popen[str]] = []
    for model in models:
        branch = f"autopilot/{args.project_slug}-wave-{wave_id}-{slug(model)}"
        worktree = WORKTREES_DIR / f"{args.project_slug}-wave-{wave_id}-{slug(model)}"
        create_worktree(branch, worktree)
        procs.append(launch_worker(args, model, wave_id, branch, worktree))
        print(f"launched {model} on {branch}")
    results: list[dict[str, Any]] = []
    deadline = time.time() + args.timeout + 300
    for proc in procs:
        remaining = max(1, int(deadline - time.time()))
        try:
            rc = proc.wait(timeout=remaining)
        except subprocess.TimeoutExpired:
            proc.kill()
            rc = proc.wait(timeout=30)
        try:
            proc._openclaw_log_file.close()  # type: ignore[attr-defined]
        except Exception:
            pass
        log_path = proc._openclaw_log_path  # type: ignore[attr-defined]
        text = Path(log_path).read_text(encoding="utf-8", errors="replace") if Path(log_path).exists() else ""
        results.append({
            "model": proc._openclaw_model,  # type: ignore[attr-defined]
            "branch": proc._openclaw_branch,  # type: ignore[attr-defined]
            "rc": rc,
            "elapsed": int(time.time() - proc._openclaw_started),  # type: ignore[attr-defined]
            "summary": short_summary(text),
            "log": str(Path(log_path).relative_to(REPO)),
        })
    merged: list[str] = []
    issues: list[str] = []
    for item in results:
        branch = item["branch"]
        if item["rc"] != 0:
            issues.append(f"{branch} worker rc={item['rc']}")
            continue
        if not branch_has_commits(branch, base):
            issues.append(f"{branch} produced no commit")
            continue
        cp = run(["git", "merge", "--no-ff", branch, "-m", f"Merge {branch}"], timeout=240)
        if cp.returncode == 0:
            merged.append(branch)
        else:
            issues.append(f"merge failed for {branch}: {cp.stdout[-500:]}")
            run(["git", "merge", "--abort"], timeout=120)
            break
    verify = run(parse_csv(args.verify_cmd), timeout=args.verify_timeout) if args.verify_cmd else run(["make", "test"], timeout=args.verify_timeout)
    summary = {
        "wave": wave_id,
        "base": base[:12],
        "head": git_head(),
        "results": results,
        "merged": merged,
        "issues": issues,
        "verificationRc": verify.returncode,
        "verificationTail": verify.stdout[-1000:],
    }
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    (LOG_DIR / f"parallel-wave-{wave_id}-summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))
    if verify.returncode != 0:
        return verify.returncode
    return 1 if issues and not merged else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Run parallel OpenClaw project autopilot workers in git worktrees.")
    ap.add_argument("--project-name", default="ETL")
    ap.add_argument("--project-slug", default="etl")
    ap.add_argument("--project-goal", default="minimal LLM-oriented self-hosting scripting language and compiler")
    ap.add_argument("--context-files", default="docs/AUTOPILOT.md,state/autopilot.md,docs/SPEC.md", type=parse_csv)
    ap.add_argument("--verification-focus", default="Run parser/compiler tests and any bootstrap smoke test.")
    ap.add_argument("--extra-instruction", default="Keep ETL v0 minimal; first backend is C; WASM/ASM/mobile come later.")
    ap.add_argument("--agent", default="main")
    ap.add_argument("--thinking", default="low")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--models", default="anthropic/claude-opus-4.7,zai/glm-5.1")
    ap.add_argument("--parallel-max-models", type=int, default=2)
    ap.add_argument("--verify-cmd", default="make,test", help="comma-separated command, default: make,test")
    ap.add_argument("--verify-timeout", type=int, default=300)
    return run_wave(ap.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
