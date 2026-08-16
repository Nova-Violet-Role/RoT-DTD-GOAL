---
description: Abort the active goal (state kept on disk for post-mortem)
---

If there is meaningful progress (check `status --brief` first), confirm the
user really wants to abort. Then:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" abort
```

Offer a short post-mortem from `goal.sh status` + `goal.sh journal 30`: what
passed, what never passed, and what a better spec would look like.
