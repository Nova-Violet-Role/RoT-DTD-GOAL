---
description: Resume a paused or human-escalated goal (resets iteration budget and stall detector)
---

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" resume
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" status --brief
```

If the goal had escalated (`awaiting_human`), incorporate the user's guidance
BEFORE continuing — that guidance is the entire point of the escalation.
Then continue toward the failing criteria.
