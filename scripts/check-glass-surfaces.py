#!/usr/bin/env python3
"""Prevent the legacy card fill from bypassing the shared glass surfaces again."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
failures = []
for path in (root / "LifeOS").rglob("*.swift"):
    if path.name in {"Theme.swift", "GlassGallery.swift"}:
        continue
    for line_number, line in enumerate(path.read_text().splitlines(), 1):
        if line.lstrip().startswith("//"):
            continue
        if "Theme.cardFill" in line or re.search(r"\.background\(Theme\.card\s*,", line):
            failures.append(f"{path.relative_to(root)}:{line_number}: use raisedSurface/glassControl")
if failures:
    raise SystemExit("\n".join(failures))
print("Glass surface guard: no legacy card-fill bypasses")
