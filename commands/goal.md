---
description: Pursue a goal to verified completion via the RoT DTD GOAL state machine (verification-owned, no promise strings, no blind loops)
argument-hint: <goal description>
---

# /goal — verification-driven goal execution (bash engine)

The user's goal: **$ARGUMENTS**

You are operating under RoT DTD GOAL v3. Completion is EARNED by verify
commands exiting 0 — you cannot declare it. The tamper guard blocks *writes*
to `.claude/goal/*` (reads are fine), and behind it the integrity ledger
re-hashes every criterion before the gate trusts it, so editing a check into
a pass is not merely discouraged, it is detected. All state changes go
through the CLI: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" ...`

## Phase 1 — Forge the spec (before touching any code)

1. Check nothing is live: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh" status --brief`.
   If a goal is active/paused/awaiting_human, tell the user; they must
   /goal-abort first.
2. Restate the goal in one sentence. If it is ambiguous or unverifiable as
   stated, ask targeted questions FIRST.
3. Use the **goal-planner** subagent to decompose the goal into 3–10
   **machine-checkable criteria**, each with a single-line shell `verify`
   command that exits 0 iff the criterion truly holds (tests, linters,
   builds, grep -q, curl checks, small assert scripts you write). No
   vibes-based criteria, and never a command that merely echoes success.
4. Show the user the criteria table and chosen budget (default 8; 4 for
   small goals, 12 for large). Confirm only if anything is risky.

## Phase 2 — Activate

```bash
G="${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh"
bash "$G" init "<one-sentence goal>" --budget 8      # or --budget auto, if
                                                     # this repo has history
bash "$G" add C1 "unit tests pass" 'npm test'       --deps 'src/*;test/*'
bash "$G" add C2 "no lint errors"  'npx eslint .'   --deps 'src/*;*.js'
bash "$G" activate        # seals the ledger, red-teams every criterion
bash "$G" mutate          # optional, strongest: does each check DIE when the
                          # files it declares in --deps are deleted?
```

`--deps` is not decoration: it scopes which edits invalidate a passing
criterion, and it is the claim the mutation probe falsifies. `add` will
outright refuse a check that cannot fail (`true`, `... || true`, a bare
`echo`), so do not try to smuggle one past it.

## Phase 3 — Execute

Work the goal directly. Use **goal-verifier** for read-only spot checks and
**goal-critic** when progress stalls. Prefer the smallest fix over rewrites.

## Phase 4 — The gate does the looping, not you

When you believe you are done, simply **stop responding**. The Stop hook
runs every criterion for real:

- All pass → goal marked complete, you are released.
- Some fail → you get back ONLY the failing criteria with their real
  output. Fix exactly those, then stop again.
- Identical failures repeat *without progress*, or the budget runs out → the
  gate escalates to the human instead of looping. Do not fight the
  escalation; summarize what you tried and what you recommend.
- The criteria no longer match their sealed hashes → INTEGRITY DRIFT. The
  gate refuses completion and escalates. If the change was legitimate, say so
  and let the human run `goal.sh seal --reason "..."`.
- A criterion turns out to pass even in an empty directory → red-team
  warning (or refusal under `GATE_REDTEAM=strict`). Replace it with
  `goal.sh sharpen`, which cannot weaken a check and cannot touch one that
  already passed.

If a criterion is genuinely wrong (not merely inconvenient), sharpen it with
a stated reason — the old command is preserved in the journal for the human
to read. Never edit `.claude/goal/*` yourself and never claim completion —
the gate decides, based on evidence.
