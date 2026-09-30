#!/usr/bin/env python3
"""One bounded Claude Code invocation. Supervisor owns audit/review decisions."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def invoke(brief, timeout=900, executable=None):
    jobs = HERE / "jobs"
    jobs.mkdir(exist_ok=True)
    brief = Path(brief).resolve()
    if not brief.is_relative_to(jobs.resolve()) or brief.name != "brief.md":
        raise ValueError("Expected docs/lifeos-agent/jobs/<batch>/brief.md")
    content = brief.read_text()
    if not content.strip() or len(content) > 24000:
        raise ValueError("Brief must contain 1–24000 characters")
    cli = executable or shutil.which("claude")
    if not cli:
        raise RuntimeError("Claude Code is not installed")
    with (HERE / ".builder.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another LifeOS builder is already running")
        counter = brief.parent / "attempts.json"
        attempts = json.loads(counter.read_text()) if counter.exists() else []
        if len(attempts) >= 3:
            raise RuntimeError("Batch cap reached: initial attempt + two corrections")
        n = len(attempts) + 1
        entry = {"attempt": n, "started": time.time(), "status": "running"}
        attempts.append(entry)

        def persist():
            temporary = counter.with_suffix(".tmp")
            temporary.write_text(json.dumps(attempts, indent=2) + "\n")
            temporary.replace(counter)

        persist()
        prompt = (
            "Implement ONLY this LifeOS batch in the current repository. Read "
            "docs/lifeos-agent/SUPERVISOR.md and REQUIREMENTS-2026-09-30.md. "
            "You are the builder, NOT the supervisor: do not invoke claude_bridge.py, "
            "spawn other agents, start automations, edit their counters or run another "
            "Claude/Codex process. Preserve all existing work. No deployment, push, "
            "secret changes, purchases or user-data deletion. Do not bypass permissions. "
            "If a tool is denied, report the exact unverified step and continue the "
            "unaffected parts. Return changed files, test evidence, unverified flows "
            "and remaining defects. Do not claim the whole app is complete.\n\n" + content
        )
        allowed = ["Read", "Glob", "Grep", "Edit", "Write", "Bash(git diff *)",
                   "Bash(git status *)", "Bash(rg *)", "Bash(xcodebuild *)",
                   "Bash(swift *)", "Bash(swiftc *)",
                   "Bash(python3 scripts/check-glass-surfaces.py)",
                   "Bash(node flights-api/test-flights.mjs)"]
        cmd = [cli, "-p", "--permission-mode", "dontAsk", "--output-format", "json",
               "--allowedTools", ",".join(allowed)]
        output = brief.parent / f"builder-{n}.json"
        errors = brief.parent / f"builder-{n}.stderr.txt"
        try:
            with output.open("w") as out, errors.open("w") as err:
                p = subprocess.Popen(cmd, cwd=ROOT, stdin=subprocess.PIPE, stdout=out,
                                     stderr=err, text=True, start_new_session=True)
                try:
                    p.communicate(prompt, timeout=timeout)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGTERM)
                    try:
                        p.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait()
                    raise RuntimeError("Builder timed out; inspect diff before next attempt")
            entry["exit_code"] = p.returncode
            if p.returncode:
                raise RuntimeError(f"Claude exited {p.returncode}; see {errors}")
            result = json.loads(output.read_text())
            if result.get("is_error"):
                raise RuntimeError("Claude reported an error; see builder output")
            entry["status"] = "awaiting_independent_review"
        except Exception as error:
            entry["status"] = "failed"
            entry["reason"] = str(error)
            raise
        finally:
            entry["finished"] = time.time()
            persist()
        return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--brief", type=Path)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    if not args.execute:
        print(json.dumps({"mode": "preflight_no_model_call", "repo": str(ROOT),
                          "claude": shutil.which("claude"), "max_calls_per_batch": 3,
                          "timeout_seconds_per_call": 900}, indent=2))
    elif not args.brief:
        parser.error("--execute requires --brief")
    else:
        print(invoke(args.brief))
