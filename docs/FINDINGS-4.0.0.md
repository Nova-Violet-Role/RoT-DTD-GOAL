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

11. **A gate slower than the hook timeout is an open gate.** Measured, not
    theorized: bench run 2's final completion pipeline (two verify sweeps over
    a goal with a 100k-row performance criterion, plus a warn-mode mutation
    probe copying the tree per operator per criterion) exceeded the Stop
    hook's `timeout: 300`, the harness killed the hook mid-verdict — journal
    ends at `CONFIRM`, no verdict line — and **the session was allowed to end
    unverified**, five minutes to the second after the sweep began.
    Completion cannot be self-declared, but it can be out-waited. *Proposed
    fix: the gate watches its own elapsed time against a budget below the
    hook timeout; when the pipeline cannot finish in budget it emits a
    `block` — "verification incomplete (out of time at <stage>): stop again"
    — so a timeout costs an iteration, never a verdict. Plus: scale the
    shipped `timeout` to the measured cost, and document that hook timeouts
    fail OPEN in Claude Code.*

12. **Five verdict-shaped strings the contract never declares.** Found by the
    goal-contract-auditor in the bench's closing audit: `LEDGER DRIFT` (vs
    declared `INTEGRITY DRIFT`), `ATTESTATION FAILED`, `STALL DETECTED`,
    `CONTRACT OK`/`CONTRACT DRIFT`, `SCHEMA OK`/`SCHEMA DRIFT` are all
    emitted by the engine but absent from the DTD's verdict entities — so the
    forgery test, which loops over declared `VERDICT.*` only, has never
    proven a hostile criterion cannot speak them. *Proposed fix: declare them
    (or rename to declared forms), and the forgery attack then covers them
    automatically.*

13. **`history.tsv` is an unregistered record.** `gf_history_append()` writes
    a real 8-field TSV that is not among the `RECORD.*` entities, so
    `schema --verify` cannot see a column change there — the exact defect
    class the record schema exists to close. *Proposed fix: declare it in
    both halves of the contract; the existing cross-check then binds it.*

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
