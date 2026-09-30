#!/usr/bin/env python3
"""Local notifications for an already-running loop. No model calls."""
import argparse
import fcntl
import json
import os
import time
from pathlib import Path
from telegram_notify import notify_state, send_once

p = argparse.ArgumentParser()
p.add_argument("--job", required=True, type=Path)
args = p.parse_args()
job = args.job.resolve()
with (job / ".telegram-watcher.lock").open("a") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    until = time.time() + 4 * 3600
    while time.time() < until:
        try:
            state = json.loads((job / "loop-state.json").read_text())
            for report in job.glob("auto-review-*.json"):
                try:
                    r = json.loads(report.read_text())
                except (ValueError, OSError):
                    continue
                if r.get("verdict") == "changes_required":
                    send_once(job, "defect:" + report.name,
                              f"🔎 LifeOS · {job.name}\nDéfauts détectés par la revue.\n{r.get('summary', '')[:900]}")
            if state.get("phase") in {"accepted", "correction_limit", "blocked", "error", "stopped"}:
                if notify_state(job, state):
                    break
            else:
                try:
                    os.kill(state["pid"], 0)
                except ProcessLookupError:
                    if send_once(job, "runner_missing", f"🚨 LifeOS · {job.name}\nLe superviseur local s’est arrêté sans bilan final. Vérifier auto-loop.log avant reprise."):
                        break
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(20)
    else:
        send_once(job, "watch_timeout", f"⚠️ LifeOS · {job.name}\nPas de fin confirmée après quatre heures de surveillance locale. Vérification nécessaire.")
