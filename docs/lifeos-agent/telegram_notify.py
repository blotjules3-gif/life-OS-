"""Reuse the existing private Claude Telegram configuration; never copy its token."""
import ast
import fcntl
import hashlib
import json
from pathlib import Path
import urllib.parse
import urllib.request


def send_once(job, event, message):
    job = Path(job)
    with (job / ".telegram.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        statefile = job / "telegram-sent.json"
        sent = json.loads(statefile.read_text()) if statefile.exists() else {}
        key = hashlib.sha256(event.encode()).hexdigest()
        if key in sent:
            return True
        try:
            tree = ast.parse((Path.home() / ".claude/hooks/stop-telegram-notify.py").read_text())
            config = {}
            for node in tree.body:
                if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
                    for target in node.targets:
                        if isinstance(target, ast.Name) and target.id in {"BOT_TOKEN", "CHAT_ID"}:
                            config[target.id] = node.value.value
            body = urllib.parse.urlencode({"chat_id": config["CHAT_ID"], "text": message[:3500]}).encode()
            request = urllib.request.Request("https://api.telegram.org/bot" + config["BOT_TOKEN"] + "/sendMessage", data=body)
            with urllib.request.urlopen(request, timeout=10) as response:
                result = json.load(response)
            if not result.get("ok"):
                raise RuntimeError("Telegram did not accept notification")
            sent[key] = {"event": event, "message_id": result["result"]["message_id"]}
            temp = statefile.with_suffix(".tmp")
            temp.write_text(json.dumps(sent, indent=2) + "\n")
            temp.replace(statefile)
            return True
        except Exception as error:
            # Never log exception strings: URL errors may include the bot token.
            (job / "telegram-error.txt").write_text(type(error).__name__ + "\n")
            return False


def notify_state(job, state):
    phase = state.get("phase", "unknown")
    summary = state.get("last_review", {}).get("summary", "")
    if phase == "accepted":
        title = "✅ Lot terminé — revue acceptée"
    elif phase == "correction_limit":
        title = "⚠️ Lot arrêté — corrections encore nécessaires, plafond atteint"
    elif phase in {"blocked", "error"}:
        title = "🚨 Agent bloqué / erreur"
    elif phase == "stopped":
        title = "⏹ Agent arrêté"
    else:
        return False
    # Share status/summary only, never raw logs, source code or credentials.
    text = f"LifeOS · {Path(job).name}\n{title}\n{summary[:900]}\nDétails : LOOP-RESULT.md dans le dossier du lot."
    if phase in {"blocked", "error"}:
        text += "\nLe rapport local précise la cause et l’action nécessaire."
    return send_once(job, "terminal:" + phase, text)
