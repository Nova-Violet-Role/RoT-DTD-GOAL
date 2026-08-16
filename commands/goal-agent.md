---
description: Dispatch ONE of the DTD-declared agents on a task — agent name validated against the trust contract, model and effort selectable per call
argument-hint: <agent> [model=sonnet|opus|haiku|inherit] [effort=low|medium|high|max] <task…>
---

Dispatch exactly one RoT DTD GOAL agent. The roster is never hardcoded here:
the trust contract is the single source of who exists and what each may never
do.

**1 — read the roster from the contract, not from memory:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" contract
```

The `declared and bounded` lines are the roster: seven agents, each with the
element it speaks in (`gf:spec`, `gf:criterion`, `gf:strategy`, `gf:attack`,
`gf:finding`, `gf:queue`, `gf:audit`).

**2 — parse the arguments.** The first token is the agent (with or without the
`goal-` prefix — `redteam` means `goal-redteam`). Optional `model=` and
`effort=` tokens may appear anywhere; everything else is the task. If the agent
is not in the roster, REFUSE and print the roster with each agent's one-line
charter — do not guess a nearest match.

**3 — dispatch it** with the Task tool, `subagent_type:
"rot-dtd-goal:<agent>"`, and the task as the prompt:

- `model=` given → pass it through in the Task call so it overrides the
  agent's front-matter pin for this one dispatch. Absent → the agent's own
  front matter decides (that is what `inherit` is for).
- `effort=` given → pass it through if this harness's Task tool accepts an
  effort parameter; if it does not, put a single line at the top of the task
  prompt — `requested effort: <level>` — and say in your summary that effort
  was requested as guidance, not enforced. Never silently drop it.

**4 — present the report inside the agent's declared element**, e.g.
`<gf:attack>…</gf:attack>`, exactly as the contract declares it, and close
with the standing rule: an agent's output is a **proposal**. Nothing it says
marks a criterion passed or a goal complete — the Stop gate decides by exit
code, never by prose (LAW.1), and each agent's "may never" line still binds.
