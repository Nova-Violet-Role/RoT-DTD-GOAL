---
description: Fan out ALL the DTD-declared agents (or an agents= subset) on one thing at once — a workflow when the harness has one, parallel dispatches otherwise — model and effort selectable
argument-hint: [agents=redteam,critic,…] [model=sonnet|opus|haiku|inherit] [effort=low|medium|high|max] <the one thing…>
---

Put the whole roster on one problem at the same time. Seven perspectives, one
subject, one synthesized answer — with every agent still inside its declared
boundary.

**1 — read the roster from the contract** (never hardcode it):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" contract
```

**2 — parse the arguments.** `agents=` (comma-separated, `goal-` prefix
optional) narrows the fan-out; absent means ALL declared agents. `model=` and
`effort=` apply to every dispatch in this swarm, same pass-through rules as
`/goal-agent`: `model=` rides the Task call and overrides front matter for
this swarm only; `effort=` rides the call where the harness accepts it and is
otherwise stated as `requested effort: <level>` at the top of each prompt —
say which happened, never silently drop it. Everything else is the one thing
being examined. An unknown name in `agents=` refuses the whole swarm with the
roster printed — a swarm that silently drops an agent looks complete and is
not.

**3 — fan out, genuinely in parallel.** Parallel Task calls are the default
posture; a Workflow is an upgrade, never a wall. Use the Workflow tool ONLY
when it is present AND already approved for this session — in a headless or
non-interactive run, or whenever a permission prompt would be needed, do NOT
reach for it: a workflow waiting on an approval nobody can give produces no
agent reports at all (measured in the 3.0.0 bench). In every other case issue
ALL the Task calls in a SINGLE message
(one call per agent, `subagent_type: "rot-dtd-goal:<agent>"`) so they run
concurrently — never one-at-a-time in sequence, which is just `/goal-agent`
seven slow times. Each agent receives the same subject, framed for its
charter (the red team attacks it, the planner decomposes it, the forensic
reads its records, the auditor checks its contract face…), with its "may
never" line restated in the prompt.

**4 — synthesize without flattening.** Per agent: its report inside its
declared element (`<gf:attack>`, `<gf:strategy>`, …). Then the combined read:
where the perspectives agree, where they disagree — a disagreement between
agents is a finding, not noise, and must survive into the summary. Close with
the standing rule: the swarm produces **proposals**. No agent, and no
synthesis of agents, marks a criterion passed or a goal complete — the Stop
gate decides by exit code, never by prose (LAW.1).
