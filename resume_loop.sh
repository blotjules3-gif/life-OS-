#!/bin/bash
rm -f STATUS.txt
while true; do
  if grep -q DONE STATUS.txt 2>/dev/null; then
    echo "[$(date '+%H:%M')] every section DONE or BLOCKED. stopping."
    break
  fi
  echo "[$(date '+%H:%M')] running..."
  OUT=$(claude -p --continue "Continue building LifeOS. Scope locked to TWO areas only: Home screen and Category sections. Never touch onboarding, settings, profile, or anything else; note issues there in CHANGELOG.md and move on. Goal: make every Home and Category section 100 percent complete and shippable. A section is DONE only when ALL are true: UI fully built matching the existing bubble design system (Metal shader bubbles, spacing, type, color tokens already in the project); loading, empty, and error states handled; navigation in and out wired; data populated (real source if available, clearly marked stub if not); and the project compiles with zero errors using the xcodebuild command saved at the top of CHANGELOG.md, which you must run and confirm before marking anything DONE. Each pass: read COMPLETION.md and CHANGELOG.md, pick the highest priority section still TODO (Home before Category), build it to the DONE bar, run the build check, fix any failure before moving on, then update COMPLETION.md and append one line to CHANGELOG.md as [section] | what changed | builds yes/no. Two hard rules: never mark a section DONE that does not compile or is unfinished, and if a section truly cannot be completed from here (needs a real API key, an owner only design decision, HealthKit entitlements, or device only testing) mark it BLOCKED with one line on what unblocks it, never fake completion, never churn cosmetic edits to look busy; and never break a section that already works just to invent progress. Never stop to ask whether to proceed and never hand over a to do list, just do everything you can reach inside Home and Category end to end in priority order. When every section is DONE or BLOCKED, write the word DONE to STATUS.txt." 2>&1)
  echo "$OUT"
  if echo "$OUT" | grep -qiE "limit|quota|try again"; then
    echo "[$(date '+%H:%M')] capped. waiting 5 min."
    sleep 300
  else
    sleep 15
  fi
done
