# `lean/` — the parts where being *nearly* right is the same as being wrong

```
lean/
  README.md      <- what this subject is, and WHAT THE MUTATIONS KILLED
  Proofs/        <- the .lean modules
  mutate/        <- the mutation suite that attacked them
```

**The plugin never invokes Lean.** It runs on bash and coreutils, with no Lean
toolchain installed, and CI does not verify these modules and does not claim
to. They exist because four decisions inside the engine are the kind where a
test that samples a few inputs is not evidence: a monotonicity, a rotation, a
scoping rule and a scheduler's termination. **A test samples; a theorem
settles.**

---

## What each module is about

| module | the engine question it answers | theorems |
|--------|-------------------------------|----------|
| [`Proofs/FlakyScope.lean`](Proofs/FlakyScope.lean) | *When is a "flake" real?* Scoping the flake window by **seal generation** rather than by any clock, and defining a flake as a **pass-then-fail regression** rather than mere disagreement. | 38 |
| [`Proofs/GoalQueue.lean`](Proofs/GoalQueue.lean) | *Does the queue always finish?* The scheduler only starts eligible rows, respects dependencies, and strictly decreases a termination measure — so a cycle can never run. | 11 |
| [`Proofs/TimingsRotation.lean`](Proofs/TimingsRotation.lean) | *Can pruning history change a verdict?* Rotating the timings file must not shrink a learned budget — the oldest row can be the determining one. | 10 |
| [`Proofs/LearnedTimeout.lean`](Proofs/LearnedTimeout.lean) | *Is the learned timeout safe?* It never drops below the base, never exceeds the cap, and grows monotonically in both. | 7 |

Two of these carry theorems whose whole job is to state what is **not** true,
which is the honest half of a specification:
`clock_scope_can_hide_a_flip`, `ts_scope_needs_a_monotone_clock`,
`naive_rotation_can_shrink`, `oldest_row_can_be_the_determining_row`.
Each proves the *old* design was wrong, rather than asserting the new one is
right.

---

## The three instruments

A build exiting 0 means the file **elaborated**. That is not the same as the
theorems being true of anything, so all three are run:

```sh
lake build Proofs.GoalForge.GoalQueue      # 1. it elaborates -- read $? DIRECTLY
#print axioms next_is_eligible             # 2. what it rests on
lake env leanchecker Proofs.GoalForge.GoalQueue   # 3. the KERNEL re-checks the proof term
```

Measured, and recorded in [`../EVIDENCE/lean-instruments.log`](../EVIDENCE/lean-instruments.log):

* `lake build` → **exit 0** for all four modules.
* `#print axioms` → `propext`, `Classical.choice`, `Quot.sound` only. **No
  `sorryAx`.** Zero `sorry`, zero `native_decide` in the tree.
* `leanchecker` → **exit 0, zero bytes** for each module. The negative control
  — a module with no oleans — exits **1**. That control is the only reason the
  silence counts as a pass.

---

## What the mutations killed

`lake build` going green proves the files elaborate. It does not prove the
theorems are load-bearing: a theorem that no broken definition can falsify is
**decoration**. So each definition below was broken on purpose, the stale
`.olean` deleted, and the build re-run. **The run passes only if the build
then fails.**

Latest run — [`mutate/mutation-lean.log`](mutate/mutation-lean.log),
**8 applied, 8 killed, 0 survived, 0 discarded**:

| # | what was broken | theorems that died |
|---|-----------------|--------------------|
| **L1** | a row with **no generation** is dropped instead of kept | `sameGen_mono`, `legacy_rows_are_never_hidden`, `fail_then_pass_is_not_accused` |
| **L2** | the **pass-then-fail** check removed from `regressed` | `regressed_imp`, `clock_scope_can_hide_a_flip`, `regressed_append_other`, `real_flake_survives_the_narrowing` |
| **L3** | the **generation comparison flipped** (`g ≤ k` → `k ≤ g`) | `sameGen_mono`, `sameGen_eq_nil`, `goal_scope_can_overreport`, `fail_then_pass_is_not_accused` |
| **L4** | the **seal window dropped** — `afterSeal` becomes the identity | `mem_afterSeal`, `clock_scope_can_hide_a_flip`, `ts_scope_needs_a_monotone_clock`, `afterSeal_eq_nil` |
| **L5** | the **dependency check removed** from `eligible` | `next_respects_dependencies`, `cycle_never_runs`, `longer_cycle_never_runs`, `missing_dependency_never_runs` |
| **L6** | the **scheduler ignores eligibility** (`find? (eligible q)` → `head?`) | `next_is_eligible`, `none_means_nothing_eligible`, `cycle_never_runs`, `longer_cycle_never_runs` |
| **L7** | the **progress measure flattened** to zero | `advance_decreases_pending`, `dependent_waits_for_done` |
| **L8** | **starting a goal does not advance it** (`active` → `pending`) | `start_pending_le`, `advance_decreases_pending`, `dependent_waits_for_done` |

Attribution is by **dependency** — the declaration enclosing each error Lean
reported — not by which line happened to be edited.

### Re-run it yourself

```sh
GF_LEAN_WS=/path/to/a/mathlib/project bash lean/mutate/mutate-lean.sh
echo "exit=$?"
```

Copy `lean/Proofs/*.lean` into that workspace first (default location
`Proofs/GoalForge/`). The harness mutates in place, restores, and **verifies
the restored files hash identically** before reporting.

Exit codes are deliberately distinct, because they are different findings:

| exit | meaning |
|------|---------|
| `0` | every mutation applied and **killed** |
| `1` | something **SURVIVED** — a theorem is not load-bearing |
| `2` | a mutation was **DISCARDED** (never applied), or the tree was not restored — a defect in the *harness*, not the proofs |
| `3` | **NOT RUN** — no Lean workspace. Absence is reported, never passed off as success |

`survived` and `discarded` are counted separately on purpose. They read
identically in a summary and mean opposite things: one is a claim about the
theorem, the other is a confession about the harness.

### The harness has its own negative control

A mutation runner that has never reported a survivor is an untested alarm — it
would print `8/8 killed` just as cheerfully if it had silently stopped
building. So:

```sh
GF_MUTATE_SELFTEST=1 bash lean/mutate/mutate-lean.sh; echo "exit=$?"
```

rewords a **doc comment** — something no theorem could possibly notice.
Measured: `S1 … SURVIVED`, `killed: 0 survived: 1`, **exit 1**. The alarm
fires when it should, and only then.

---

## What these proofs do NOT claim

* **They do not verify the shell.** They specify the *logic* of four decisions;
  `scripts/lib.sh` is the implementation, and nothing mechanically binds the
  Lean definitions to the bash. The binding is the acceptance suite, and it is
  a weaker instrument than a proof. Stated plainly rather than blurred.
* **They say nothing about the gate as a whole**, about prompt injection, or
  about whether your criteria are good ones.
* **`clock_scope_can_hide_a_flip` is a theorem about the OLD design.** It is
  evidence that the change was necessary, not that the new one is complete.
* The modules **import Mathlib**, so reproducing them needs a Mathlib workspace
  with the cache fetched. That is why CI does not run them: a job the author
  cannot rehearse would go red for reasons unrelated to the proofs, and a green
  tick reading "Lean checked" while no Lean ran would be exactly the overclaim
  this project exists to refuse.
