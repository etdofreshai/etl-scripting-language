#!/usr/bin/env python3
"""Generic OpenClaw autopilot supervisor for long-running projects.

This is a project-parameterized version of the Wolf3D supervisor pattern:
run one OpenClaw agent cycle, wait for matching background tasks, optionally push,
then deliver concise progress updates. Durable state lives in the project repo.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import signal
import subprocess
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

TERMINAL = {"succeeded", "failed", "timed_out", "cancelled", "lost"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


class Supervisor:
    def __init__(self, args: argparse.Namespace):
        self.args = args
        self.repo = Path(args.repo).resolve()
        self.log_dir = self.repo / args.log_dir
        self.state_dir = self.repo / args.state_dir
        self.stop_file = self.state_dir / f"STOP_{args.project_slug.upper()}_AUTOPILOT"
        self.stop_after_cycle_file = self.state_dir / f"STOP_{args.project_slug.upper()}_AFTER_CURRENT_LOOP"
        # Backward-compatible generic stop files are also honored.
        self.generic_stop_file = self.state_dir / "STOP_AUTOPILOT"
        self.generic_stop_after_cycle_file = self.state_dir / "STOP_AFTER_CURRENT_LOOP"
        self.lock_file = self.state_dir / f"{args.project_slug}-autopilot-supervisor.pid"
        self.model_state_file = self.state_dir / f"{args.project_slug}-autopilot-model-state.json"
        self.review_state_file = self.state_dir / f"{args.project_slug}-autopilot-review-state.json"
        self.markers = [m.lower() for m in args.project_markers]
        if str(self.repo).lower() not in self.markers:
            self.markers.append(str(self.repo).lower())

    def log(self, msg: str) -> None:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        line = f"[{utc_now()}] {msg}\n"
        print(line, end="", flush=True)
        with (self.log_dir / "autopilot-supervisor.log").open("a", encoding="utf-8") as f:
            f.write(line)

    def run(self, cmd: list[str], *, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
        return subprocess.run(cmd, cwd=self.repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)

    def openclaw_agent_help(self) -> str:
        cp = self.run(["openclaw", "agent", "--help"], timeout=60)
        return cp.stdout if cp.returncode == 0 else ""

    @staticmethod
    def supports_agent_option(help_text: str, option: str) -> bool:
        return bool(re.search(rf"(^|\s){re.escape(option)}(\s|,|$)", help_text))

    @staticmethod
    def parse_csv(raw: str) -> list[str]:
        return [item.strip() for item in raw.split(",") if item.strip()]

    @staticmethod
    def model_provider(model: str, fallback: str) -> str:
        if model != "runtime default" and "/" in model:
            return model.split("/", 1)[0]
        return fallback

    def load_json(self, path: Path, default: dict[str, Any]) -> dict[str, Any]:
        if not path.exists():
            return dict(default)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return data if isinstance(data, dict) else dict(default)
        except json.JSONDecodeError:
            return dict(default)

    def store_json(self, path: Path, data: dict[str, Any]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def model_rotation_order(self, models: list[str]) -> list[tuple[int, str]]:
        if not models:
            return [(0, "runtime default")]
        state = self.load_json(self.model_state_file, {"lastIndex": -1})
        try:
            last_index = int(state.get("lastIndex", -1))
        except (ValueError, TypeError):
            last_index = -1
        return [((last_index + step) % len(models), models[(last_index + step) % len(models)]) for step in range(1, len(models) + 1)]

    def store_model_state(self, index: int, model: str, provider: str) -> None:
        self.store_json(self.model_state_file, {"lastIndex": index, "model": model, "provider": provider, "updatedAt": utc_now()})

    def git_head(self, short: bool = True) -> str:
        cp = self.run(["git", "rev-parse", "--short" if short else "HEAD"], timeout=30)
        return cp.stdout.strip() if cp.returncode == 0 else "unknown"

    def git_push_current_branch(self) -> bool:
        branch_cp = self.run(["git", "branch", "--show-current"], timeout=30)
        branch = branch_cp.stdout.strip() if branch_cp.returncode == 0 else ""
        if not branch:
            self.log("git push skipped: could not determine current branch")
            return False
        token = os.environ.get("GH_TOKEN_ETDOFRESHAI") or os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
        cmd = ["git", "push", "origin", branch]
        if token:
            askpass = self.state_dir / f"{self.args.project_slug}-git-askpass.sh"
            askpass.write_text(
                "#!/bin/sh\ncase \"$1\" in\n  *Username*) echo x-access-token ;;\n  *Password*) printf '%s' \"$AUTOPILOT_GIT_TOKEN\" ;;\n  *) echo ;;\nesac\n",
                encoding="utf-8",
            )
            askpass.chmod(0o700)
            env = os.environ.copy()
            env["AUTOPILOT_GIT_TOKEN"] = token
            env["GIT_ASKPASS"] = str(askpass)
            env["GIT_TERMINAL_PROMPT"] = "0"
            try:
                cp = subprocess.run(cmd, cwd=self.repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180, env=env)
            finally:
                askpass.unlink(missing_ok=True)
        else:
            cp = self.run(cmd, timeout=180)
        if cp.returncode == 0:
            self.log(f"git push succeeded: {cp.stdout[-1000:].strip()}")
            return True
        self.log(f"git push failed rc={cp.returncode}: {cp.stdout[-2000:]}")
        return False

    def build_agent_command(self, *, message: str, thinking: str, timeout: int, model: str, help_text: str, deliver: bool = False) -> list[str]:
        cmd = ["openclaw", "agent", "--agent", self.args.agent, "--message", message, "--thinking", thinking, "--timeout", str(timeout)]
        if model != "runtime default" and self.supports_agent_option(help_text, "--model"):
            cmd.extend(["--model", model])
        if self.args.fast_mode:
            if self.supports_agent_option(help_text, "--fast"):
                cmd.append("--fast")
            elif self.supports_agent_option(help_text, "--fast-mode"):
                cmd.append("--fast-mode")
        if deliver:
            cmd.extend(["--deliver", "--reply-channel", self.args.summary_channel, "--reply-to", self.args.summary_target])
        cmd.append("--json")
        return cmd

    def load_tasks(self) -> list[dict[str, Any]]:
        cp = self.run(["openclaw", "tasks", "list", "--json"], timeout=60)
        if cp.returncode != 0:
            self.log(f"tasks list failed rc={cp.returncode}: {cp.stdout[-2000:]}")
            return []
        try:
            return list((json.loads(cp.stdout) or {}).get("tasks") or [])
        except json.JSONDecodeError:
            self.log(f"tasks JSON parse failed: {cp.stdout[-2000:]}")
            return []

    def is_project_task(self, task: dict[str, Any]) -> bool:
        blob = "\n".join(str(task.get(k, "")) for k in ("label", "task", "terminalSummary", "progressSummary", "childSessionKey", "runId")).lower()
        return any(marker and marker in blob for marker in self.markers)

    def active_project_tasks(self) -> list[dict[str, Any]]:
        return [t for t in self.load_tasks() if self.is_project_task(t) and t.get("status") not in TERMINAL]

    def stop_requested(self) -> bool:
        return self.stop_file.exists() or self.generic_stop_file.exists()

    def graceful_stop_requested(self) -> bool:
        return self.stop_after_cycle_file.exists() or self.generic_stop_after_cycle_file.exists()

    def clear_stop_files(self) -> None:
        for path in (self.stop_file, self.stop_after_cycle_file, self.generic_stop_file, self.generic_stop_after_cycle_file):
            if path.exists():
                path.unlink()
                self.log(f"cleared stale stop file: {path}")

    def cleanup_graceful_stop_files(self) -> None:
        for path in (self.stop_after_cycle_file, self.generic_stop_after_cycle_file):
            path.unlink(missing_ok=True)

    def write_pid(self) -> None:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        if self.lock_file.exists():
            old = self.lock_file.read_text(errors="ignore").strip()
            if old.isdigit():
                try:
                    os.kill(int(old), 0)
                except ProcessLookupError:
                    pass
                else:
                    raise SystemExit(f"supervisor already appears to be running as pid {old}")
        self.lock_file.write_text(str(os.getpid()), encoding="utf-8")

    def cleanup_pid(self) -> None:
        try:
            if self.lock_file.read_text(errors="ignore").strip() == str(os.getpid()):
                self.lock_file.unlink()
        except FileNotFoundError:
            pass

    @staticmethod
    def format_duration(seconds: float) -> str:
        seconds_i = int(max(0, seconds))
        minutes, sec = divmod(seconds_i, 60)
        hours, minutes = divmod(minutes, 60)
        if hours:
            return f"{hours}h{minutes:02d}m{sec:02d}s"
        if minutes:
            return f"{minutes}m{sec:02d}s"
        return f"{sec}s"

    def next_cycle_index(self) -> int:
        existing = []
        for path in self.log_dir.glob("autopilot-cycle-*.jsonlog"):
            match = re.search(r"autopilot-cycle-(\d+)\.jsonlog$", path.name)
            if match:
                existing.append(int(match.group(1)))
        return max(existing, default=0) + 1

    def send_plain_update(self, text: str, help_text: str, label: str) -> None:
        if not self.args.summary_target:
            self.log(f"{label} skipped: no --summary-target")
            return
        self.log(f"sending {label}: {text.replace(chr(10), ' | ')}")
        cp = self.run(self.build_agent_command(message="Send this exact update, with no extra title or commentary:\n" + text,
                                               thinking=self.args.summary_thinking, timeout=120, model="runtime default",
                                               help_text=help_text, deliver=True), timeout=180)
        self.log(f"{label} rc={cp.returncode}")

    def send_start_update(self, models: list[str], help_text: str) -> None:
        if not self.args.start_update:
            return
        text = (
            f"Starting {self.args.project_name} autopilot.\n"
            f"Models: {', '.join(models)}.\n"
            f"Thinking: {self.args.thinking}; fast mode: {'on' if self.args.fast_mode else 'off'}.\n"
            f"Usage guard: {'on' if self.args.usage_guard else 'off'}; push after cycle: {'on' if self.args.push_after_cycle else 'off'}."
        )
        self.send_plain_update(text, help_text, "start update")

    def send_stop_update(self, stats: dict[str, Any], help_text: str) -> None:
        if not self.args.stop_update:
            return
        counts = stats.get("modelCounts") or {}
        model_text = ", ".join(f"{model} x{count}" for model, count in counts.items()) or "none"
        elapsed = self.format_duration(time.time() - float(stats.get("startedAt", time.time())))
        text = f"{self.args.project_name} autopilot stopped after current loop.\nLoops run: {stats.get('cycles', 0)}; elapsed: {elapsed}.\nModels run: {model_text}.\nLast commit: {self.git_head()}."
        self.send_plain_update(text, help_text, "stop update")

    def build_summary_prompt(self) -> str:
        files = ", ".join(self.args.context_files) or "project docs/state files"
        return f"""
In {self.repo}, give ET a concise {self.args.project_name} autopilot progress update for the project chat.

Inspect logs/autopilot-supervisor.log, latest logs/autopilot-cycle-*.jsonlog if useful, git log --oneline -8, git status --short, {files}, and `openclaw status --usage --json` when available.

Style:
- Keep it short: 3-6 compact bullets or lines.
- Include model used, provider usage/window when available, elapsed time when available, commit/push status, verification result, and terse work done.
- Include blockers only if real.
- Do not expose internal prompts or raw logs.
""".strip()

    def build_cycle_prompt(self, selected_model: str) -> str:
        context_lines = "\n".join(f"- Read {p}." for p in self.args.context_files)
        protected = "\n".join(f"- Do not modify {p}." for p in self.args.protected_paths)
        verification = self.args.verification_focus or "Run the best relevant verification for this project."
        extra = self.args.extra_instruction.strip()
        return f"""
Run one adaptive {self.args.project_name} autopilot cycle in {self.repo}.

Mandatory context:
{context_lines or '- Inspect the repo docs, current state, latest logs, and git status.'}
- Project goal: {self.args.project_goal}
- Verification focus: {verification}
- Do not ask ET routine questions. Make the best safe technical decision.
{protected}
- Preferred model for this cycle: {selected_model}. If runtime model switching is unavailable, still use this as the review/decision-making perspective.
- If useful, spawn focused workers/subagents with labels prefixed {self.args.project_slug}-.
- If spawning workers, make their tasks concrete, repo-grounded, and verification-oriented.
- Implement/research one meaningful next step, verify it, update durable docs/state, and commit useful changes.
- Do not stop for ordinary blockers; pivot, research, split the task, or try materially different approaches.
- If the same issue repeats across materially different attempts, record the blocker and pause cleanly.
{extra}

Keep final output concise: commits, verification evidence, next move, blockers.
""".strip()

    def send_summary(self, help_text: str) -> None:
        if not self.args.completion_summary:
            return
        cp = self.run(self.build_agent_command(message=self.build_summary_prompt(), thinking=self.args.summary_thinking,
                                               timeout=180, model="runtime default", help_text=help_text, deliver=bool(self.args.summary_target)),
                      timeout=240)
        self.log(f"summary rc={cp.returncode}")
        if cp.stdout.strip():
            self.log_dir.mkdir(parents=True, exist_ok=True)
            (self.log_dir / "autopilot-summary-last.jsonlog").write_text(cp.stdout, encoding="utf-8")

    def wait_for_workers(self, help_text: str) -> None:
        start = time.time()
        last_ids: set[str] | None = None
        last_summary = time.time()
        while True:
            if self.stop_requested():
                self.log("stop file present while waiting; exiting wait")
                return
            active = self.active_project_tasks()
            ids = {str(t.get("taskId") or t.get("runId")) for t in active}
            if not active:
                self.log("no active project background tasks")
                return
            if ids != last_ids:
                labels = ", ".join(str(t.get("label") or t.get("runtime") or t.get("taskId")) for t in active[:8])
                self.log(f"waiting for {len(active)} project task(s): {labels}")
                last_ids = ids
            if self.args.summary_interval > 0 and time.time() - last_summary >= self.args.summary_interval:
                self.send_summary(help_text)
                last_summary = time.time()
            if time.time() - start > self.args.max_worker_wait:
                self.log(f"worker wait exceeded {self.args.max_worker_wait}s; continuing")
                return
            time.sleep(self.args.worker_poll)

    def load_usage_status(self) -> dict[str, Any] | None:
        cp = self.run(["openclaw", "status", "--usage", "--json"], timeout=90)
        if cp.returncode != 0:
            self.log(f"usage check failed rc={cp.returncode}; treating usage as unavailable: {cp.stdout[-1000:]}")
            return None
        try:
            return dict(json.loads(cp.stdout))
        except json.JSONDecodeError:
            self.log("usage check returned non-JSON; treating usage as unavailable")
            return None

    def usage_wait_seconds(self, provider: str, status: dict[str, Any] | None) -> int:
        if not status:
            return 0
        usage = status.get("usage") or {}
        wanted = self.args.usage_window.lower()
        for item in usage.get("providers") or []:
            if str(item.get("provider")) != provider:
                continue
            for window in item.get("windows") or []:
                label = str(window.get("label", "")).lower()
                if wanted not in label and label not in wanted:
                    continue
                used = float(window.get("usedPercent") or 0)
                reset_ms = window.get("resetAt")
                if not reset_ms:
                    return 0
                reset_at = datetime.fromtimestamp(float(reset_ms) / 1000, tz=timezone.utc)
                start_at = reset_at - (timedelta(days=30) if "month" in label else timedelta(days=7))
                total = max((reset_at - start_at).total_seconds(), 1)
                elapsed = min(max((datetime.now(timezone.utc) - start_at).total_seconds(), 0), total)
                allowed = min(100.0, max(self.args.usage_min_allowed_percent, elapsed / total * 100.0 + self.args.usage_slack_percent))
                self.log(f"usage guard: provider={provider} window={window.get('label')} used={used:.1f}% allowed={allowed:.1f}%")
                if used <= allowed:
                    return 0
                resume_at = start_at + timedelta(seconds=total * (max(0.0, used - self.args.usage_slack_percent) / 100.0))
                return max(0, int((resume_at - datetime.now(timezone.utc)).total_seconds()))
        return 0

    def select_available_model(self, models: list[str], stop_ref: dict[str, bool]) -> str | None:
        while not stop_ref["stop"] and not self.stop_requested():
            status = self.load_usage_status() if self.args.usage_guard else None
            waits: list[tuple[str, str, int]] = []
            for index, model in self.model_rotation_order(models):
                provider = self.model_provider(model, self.args.usage_provider)
                wait = self.usage_wait_seconds(provider, status) if self.args.usage_guard else 0
                if wait <= 0:
                    self.store_model_state(index, model, provider)
                    return model
                waits.append((model, provider, wait))
            if not waits:
                return "runtime default"
            msg = "; ".join(f"{m}/{p}:{w}s" for m, p, w in waits)
            self.log(f"usage guard: all configured models blocked ({msg}); sleeping")
            time.sleep(min(min(w for _, _, w in waits), self.args.usage_check_interval))
        return None

    def run_loop(self) -> int:
        if self.args.stop_after_current_loop:
            self.state_dir.mkdir(parents=True, exist_ok=True)
            self.stop_after_cycle_file.write_text(utc_now() + "\n", encoding="utf-8")
            self.log(f"created graceful stop file: {self.stop_after_cycle_file}")
            return 0
        if self.args.clear_stop_files_on_start:
            self.clear_stop_files()
        self.write_pid()
        stop_ref = {"stop": False}
        help_text = self.openclaw_agent_help()
        models = [m for m in self.parse_csv(self.args.models) if self.model_provider(m, self.args.usage_provider).lower() not in {x.lower() for x in self.parse_csv(self.args.exclude_models)} and m.lower() not in {x.lower() for x in self.parse_csv(self.args.exclude_models)}]
        if not models:
            raise SystemExit("all configured models were excluded; adjust --models or --exclude-models")

        def handle_signal(signum: int, frame: Any) -> None:  # noqa: ARG001
            self.log(f"received signal {signum}; stopping after current step")
            stop_ref["stop"] = True

        signal.signal(signal.SIGTERM, handle_signal)
        signal.signal(signal.SIGINT, handle_signal)
        try:
            stats: dict[str, Any] = {"startedAt": time.time(), "cycles": 0, "modelCounts": {}}
            self.send_start_update(models, help_text)
            cycle_log_index = self.next_cycle_index()
            while not stop_ref["stop"]:
                if self.stop_requested():
                    self.log("stop requested; exiting")
                    break
                if self.graceful_stop_requested() and stats["cycles"] > 0:
                    self.send_stop_update(stats, help_text)
                    self.cleanup_graceful_stop_files()
                    break
                if self.args.max_cycles and stats["cycles"] >= self.args.max_cycles:
                    self.log(f"max cycles reached: {self.args.max_cycles}; exiting")
                    break
                selected_model = self.select_available_model(models, stop_ref)
                if not selected_model:
                    break
                stats["cycles"] += 1
                stats["modelCounts"][selected_model] = stats["modelCounts"].get(selected_model, 0) + 1
                cycle_start = time.time()
                prompt = self.build_cycle_prompt(selected_model)
                self.log(f"cycle {stats['cycles']}: starting agent turn thinking={self.args.thinking} model_hint={selected_model}")
                cp = self.run(self.build_agent_command(message=prompt, thinking=self.args.thinking, timeout=self.args.timeout,
                                                       model=selected_model, help_text=help_text), timeout=self.args.timeout + 120)
                self.log(f"cycle {stats['cycles']}: agent rc={cp.returncode}")
                if cp.stdout.strip():
                    path = self.log_dir / f"autopilot-cycle-{cycle_log_index:04d}.jsonlog"
                    path.write_text(cp.stdout, encoding="utf-8")
                    self.log(f"cycle {stats['cycles']}: wrote {path.relative_to(self.repo)}")
                    cycle_log_index += 1
                self.wait_for_workers(help_text)
                self.log(f"cycle {stats['cycles']}: completed in {self.format_duration(time.time() - cycle_start)} model={selected_model} head={self.git_head()}")
                if self.args.push_after_cycle:
                    self.git_push_current_branch()
                self.send_summary(help_text)
                if self.graceful_stop_requested():
                    self.send_stop_update(stats, help_text)
                    self.cleanup_graceful_stop_files()
                    break
                if not stop_ref["stop"] and not self.stop_requested():
                    time.sleep(max(0, self.args.cycle_delay))
            return 0
        finally:
            self.cleanup_pid()


def main() -> int:
    ap = argparse.ArgumentParser(description="Generic OpenClaw autopilot supervisor for long-running project repos.")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parents[1]), help="project repo root")
    ap.add_argument("--project-name", default="Wolf3D", help="human-readable project name")
    ap.add_argument("--project-slug", default="wolf3d", help="short lowercase slug for labels/state files")
    ap.add_argument("--project-goal", default="faithful modern C + SDL3 port", help="one-line project goal injected into each cycle")
    ap.add_argument("--project-markers", default="wolf3d,wolfenstein 3d,wolfenstein", type=Supervisor.parse_csv, help="comma-separated task matching markers")
    ap.add_argument("--context-files", default="docs/AUTOPILOT.md,state/autopilot.md", type=Supervisor.parse_csv, help="comma-separated files each cycle should read")
    ap.add_argument("--protected-paths", default="source/original/,game-files/", type=Supervisor.parse_csv, help="comma-separated paths the agent must not modify or commit")
    ap.add_argument("--verification-focus", default="Target headless Linux verification first; usually run the relevant make/test target.")
    ap.add_argument("--extra-instruction", default="Do not commit proprietary game assets.")
    ap.add_argument("--agent", default="main")
    ap.add_argument("--log-dir", default="logs")
    ap.add_argument("--state-dir", default="state")
    ap.add_argument("--cycle-delay", type=int, default=10)
    ap.add_argument("--worker-poll", type=int, default=30)
    ap.add_argument("--max-worker-wait", type=int, default=7200)
    ap.add_argument("--max-cycles", type=int, default=0, help="0 means run until stopped")
    ap.add_argument("--timeout", type=int, default=1800)
    ap.add_argument("--thinking", default="low")
    ap.add_argument("--summary-thinking", default="low")
    ap.add_argument("--models", "--include-models", dest="models", default="openai-codex/gpt-5.5,anthropic/claude-opus-4.7,zai/glm-5.1")
    ap.add_argument("--exclude-models", default="")
    ap.add_argument("--fast-mode", action=argparse.BooleanOptionalAction, default=False)
    ap.add_argument("--usage-guard", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--usage-provider", default="openai-codex")
    ap.add_argument("--usage-window", default="Week")
    ap.add_argument("--usage-slack-percent", type=float, default=5.0)
    ap.add_argument("--usage-min-allowed-percent", type=float, default=3.0)
    ap.add_argument("--usage-check-interval", type=int, default=1800)
    ap.add_argument("--summary-interval", type=int, default=0)
    ap.add_argument("--start-update", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--stop-update", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--push-after-cycle", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--completion-summary", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--summary-channel", default="telegram")
    ap.add_argument("--summary-target", default="telegram:-5268853419")
    ap.add_argument("--clear-stop-files-on-start", action=argparse.BooleanOptionalAction, default=True)
    ap.add_argument("--stop-after-current-loop", action="store_true")
    args = ap.parse_args()
    return Supervisor(args).run_loop()


if __name__ == "__main__":
    raise SystemExit(main())
