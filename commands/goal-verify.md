---
description: Run all RoT DTD GOAL acceptance criteria right now and report (does not consume an iteration)
---

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" verify
```

Report results. If criteria fail, propose the minimal concrete fix for each
— do not start implementing unless a goal is active or the user asks.
