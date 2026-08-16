---
description: Show the RoT DTD GOAL goal, criteria pass/fail, iteration budget, and journal tail
---

Run these and present the results clearly:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" status
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" journal 15
```

If status is `awaiting_human`, explain WHY it escalated (budget vs stall —
the journal shows which), summarize the persistent failures, and offer three
paths: give guidance then /goal-resume, /goal-abort + a better-specified
/goal, or stop here.
