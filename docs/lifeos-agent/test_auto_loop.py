"""Free orchestration tests: fake model responses, real state/file transitions."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("loop", Path(__file__).with_name("auto_loop.py"))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def scenario(verdicts, initial_calls=1, marker="ready_for_review", missing=False):
    with tempfile.TemporaryDirectory() as directory:
        m.HERE = Path(directory)
        m.ROOT = m.HERE
        job = m.HERE / "jobs" / "sample"
        job.mkdir(parents=True)
        if not missing:
            (job / "HANDOFF.md").write_text("Mock build evidence")
            (job / "result-status.json").write_text(json.dumps({"status": marker}))
        m.save(job / "loop-state.json", {"phase": "waiting_claude", "builder_calls": initial_calls,
               "reviews": 0, "background_id": "fake", "claude_session": "fake", "wait_deadline": 99999999999})
        reviewed, corrected = [], []

        def review(j, n):
            reviewed.append(n)
            return {"verdict": verdicts[n-1], "summary": "mock", "correction_prompt": "fix mock", "unverified": []}

        def correct(j, state, result):
            corrected.append(state["builder_calls"])

        with patch.object(sys, "argv", ["auto_loop.py", "--job", str(job)]), \
             patch.object(m.subprocess, "check_output", return_value='[]'), \
             patch.object(m.subprocess, "run"), \
             patch.object(m, "review_once", side_effect=review), \
             patch.object(m, "correct_once", side_effect=correct):
            m.main()
        return json.loads((job / "loop-state.json").read_text()), reviewed, corrected


s,r,c = scenario(["changes_required", "changes_required", "accepted"])
assert s["phase"] == "accepted" and r == [1,2,3] and c == [2,3]
s,r,c = scenario(["changes_required"], initial_calls=3)
assert s["phase"] == "correction_limit" and len(r) == 1 and c == []
s,r,c = scenario([], marker="blocked")
assert s["phase"] == "blocked" and not r and not c
s,r,c = scenario([], missing=True)
assert s["phase"] == "blocked" and not r and not c
s,r,c = scenario(["blocked"])
assert s["phase"] == "blocked" and len(r) == 1 and not c
print("PASS: handoff→review→two corrections→accepted; cap; blocked builder; missing handoff; blocked reviewer. No AI calls.")
