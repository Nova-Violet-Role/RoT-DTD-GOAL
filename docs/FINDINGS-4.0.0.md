<!--
    This file is part of RoT DTD GOAL.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
-->

# Findings toward 4.0.0

Everything flagged during the 3.0.0 bench campaign (two real-work bench runs,
headless sessions, strict gates) that is **not yet fixed**. Each entry says
what was observed, why it matters, and the proposed fix. Items get struck out
only by a commit that closes them with a test.

## Engine

1. **Mutation probe: symmetric-damage blind spot.** The probe damages every
   dependency of a criterion *simultaneously*. For checks shaped
   `diff <(tool input) expected`, damage that preserves structure commutes
   through the check: letters-only corruption (rot13) maps field values but
   not commas/quotes/newlines, so extracting a column of the corrupted input
   equals the corrupted expected file — the mutant survives. Truncation
   empties both sides of the diff — survives. Observed live in bench run 2
   (`MUTATE ops=delete,truncate,corrupt survived=6 killed=0`), reproduced and
   root-caused on a replay copy. *Proposed fix: mutate one dependency at a
   time (per-dep rounds), falling back to all-at-once only above a size
   budget; at minimum, name the symmetric case in the report.*

2. **Dependency inference misses process-substitution tokens.** Inference
   tokenizes the verify command and keeps tokens that are existing files —
   but `<(./csvq.sh …` glues the tool path to the substitution syntax, so
   `./csvq.sh` is never inferred and never damaged. The tool under test is
   invisible to the probe for every criterion of this shape. *Proposed fix:
   strip leading `<(`, `$(`, `(`, and quotes from tokens before the
   file-existence test; a test with a process-substitution criterion must see
   the tool in the inferred set.*

3. **Queue spec `CRIT` rows cannot declare deps.** The TSV grammar is
   `CRIT<TAB>id<TAB>desc<TAB>verify` — no deps field — so every queued goal's
   criteria fall back to inference (finding 2 makes that worse). *Proposed
   fix: optional field 5 `deps` (semicolon-separated globs), declared in both
   halves of the trust contract per the append-only discipline; absent field
   keeps today's behavior.*

4. **Gate policies reset on queue advance.** `GATE_REDTEAM`/`GATE_FLAKY`/
   `GATE_MUTATE` live in the per-goal `state.env`, and `queue advance`
   re-inits them to defaults — a strict bench had to re-`set` all three after
   every advance, from inside the working session. *Proposed fix: carry gate
   policies across `queue advance` (they are session posture, not goal
   content); or accept gate flags in the GOAL line's init options.*

5. **`goal.sh init --help` creates a draft goal named `--help`.** No help
   path on `init`; the flag is consumed as goal text. Observed in bench run 1
   — the session had to abort the accidental draft. *Proposed fix: `--help`
   (and `-h`) on every subcommand prints usage and exits 0, never parsed as
   an argument.*

6. **Journal `MUTATE` line is easy to misread.** `survived=6 killed=0`
   counts *criteria with at least one surviving operator*, not operator
   outcomes — it was misread as "nothing was killed" live, during the bench,
   by the person running it. *Proposed fix: journal
   `criteria_with_survivors=` / `criteria_all_killed=`, or add the
   per-criterion fractions.*

7. **Add-time lint for self-comparing criteria.** Both bench runs shipped an
   author-written vacuous criterion of the same class (`diff` whose every
   file argument is a process substitution or `/dev/null`), and both were
   caught only at completion by the red team (H2 in run 1, R4 in run 2 — the
   latter under strict, costing an escalation). The class is detectable at
   `add` time. *Proposed fix: `cmd_add` warns (not refuses) when no ordinary
   file path appears among the verify command's arguments — same spirit as
   the existing `can-never-fail` refusal, weaker verdict.*

## Agents / dispatch

8. **Guard denials during agent fan-out need a look.** Four
   `GUARD denied tool=Bash reason=bash-mutation` events fired while the
   seven-agent swarm reviewed a spec (read-only roster). Either agents
   attempt state writes they should not (prompt gap in the agent files), or
   the guard's `bash-mutation` matcher is over-broad for read-only commands
   (false positives). The stream logs from bench run 2 carry the exact
   commands — classify them, then fix the right side. *Deferred analysis:
   `bench2-csvq/bench-turns.jsonl`.*

9. **`effort=` pass-through is prose-only today.** The current harness Task
   tool has no effort parameter, so `/goal-agent`/`/goal-swarm` fall back to
   a `requested effort:` line in the prompt (as documented). When the harness
   grows the parameter, wire it and add the conformance check. *Tracking
   item, not a defect.*

## Docs / harness notes

10. **Headless sessions need the namespaced command form.**
    `claude -p "/goal-status"` is not resolved; only
    `/rot-dtd-goal:goal-status` works headless (interactive sessions resolve
    unambiguous short names). Harness behavior, not plugin code — but the
    README should say so where it teaches the commands.

---

Findings 1–7 carry proposed tests by construction (each names the observable
that must flip). Anything the DTD-conformance matrix or the command sweep
flags before this file is closed gets appended here, not fixed silently.
