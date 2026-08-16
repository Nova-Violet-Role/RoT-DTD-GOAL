/-
    This file is part of goal-forge.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
    Authors: Saimonokuma
-/
import Proofs.GoalForge.LearnedTimeout

/-! # goal-forge: more than one goal, and the scheduler that orders them

Every version through v3.5 assumed **exactly one goal per session**. Nobody
wrote that down, which is how an assumption becomes a wall: one state file, one
criteria set, one ledger, and a gate that ends the loop the moment that single
goal completes.

v3.6 queues goals with dependencies (`scripts/lib.sh:gf_queue_next`,
`scripts/goal.sh:cmd_queue_advance`). The gate now advances the queue instead of
stopping, so a session can carry a sequence — or a DAG — of goals.

The scheduling rule is deliberately the dullest one that works, because the gate
applies it **unattended**, with no human reading the result:

    eligible q r  :=  r.status = pending ∧ (r.after = none ∨ dependency is done)
    next q        :=  the FIRST eligible row in file order

What is proved here is what would be expensive to learn from a stuck loop at
three in the morning:

* `next_is_eligible` / `next_respects_dependencies` — the scheduler never starts
  a goal whose predecessor has not finished. This is the multi-goal form of the
  engine's oldest rule: nothing proceeds on a promise.
* `none_means_nothing_eligible` — when the scheduler returns nothing, that is a
  statement about the queue, not a shrug. The shell turns it into a printed
  reason (`gf_queue_blocked_reason`); a queue that stalls silently would be the
  same defect as a gate that completes silently.
* `cycle_never_runs` — a dependency cycle is refused rather than scheduled. The
  shell also forbids cycles by construction (a dependency must already be
  queued, so dependencies point strictly backwards), but the scheduler must be
  safe even against a hand-edited queue file.
* `advance_decreases_pending` — every advance strictly reduces the number of
  pending goals, so the multi-goal loop terminates. That is invariant 4 (*every
  loop has an exit*) applied to the queue itself, and it is the property that
  makes it safe for the gate to run this automatically.

WHAT IS PROVED: properties of the scheduling function.
WHAT IS NOT: that bash implements it. `test_many_goals_run_in_order` binds the
two by running the real gate through a three-goal chain, including the case
where a dependent goal must NOT jump the line.

In the shared tree this module is `Proofs.GoalForge.GoalQueue`.
-/

set_option linter.hashCommand false

namespace GoalForge.GoalQueue

/-- A queued goal's lifecycle. `blocked` is not a state the scheduler writes;
it is what the report calls a pending row whose dependency cannot complete. -/
inductive Status where
  /-- queued, not started -/
  | pending : Status
  /-- currently being verified by the gate -/
  | active : Status
  /-- verified complete; its records are archived -/
  | done : Status
deriving DecidableEq, Repr

/-- One row of `queue.tsv`. `after` is the name of the goal this one waits for;
`none` models the `-` that the file uses for "no dependency". -/
structure Row where
  /-- the goal's name, unique within the queue -/
  name : Nat
  /-- where it is in its lifecycle -/
  status : Status
  /-- the goal that must be `done` before this one may start -/
  after : Option Nat
deriving DecidableEq, Repr

/-- The queue is an ordered list: file order is the tiebreak, so the schedule is
deterministic and a human can predict it by reading top to bottom. -/
abbrev Queue := List Row

/-- The status recorded for a name, if the queue mentions it at all. -/
def statusOf (q : Queue) (n : Nat) : Option Status :=
  (q.find? (fun r => r.name == n)).map (·.status)

/-- May this row start right now? -/
def eligible (q : Queue) (r : Row) : Bool :=
  match r.status, r.after with
  | Status.pending, none   => true
  | Status.pending, some d => statusOf q d == some Status.done
  | _, _ => false

/-- The scheduler: the first eligible row, or nothing. -/
def next (q : Queue) : Option Row :=
  q.find? (eligible q)

/-- How much work is left. The termination measure, written recursively so the
induction that uses it is the obvious one. -/
def pendingCount : Queue → Nat
  | [] => 0
  | r :: t => (if r.status = Status.pending then 1 else 0) + pendingCount t

/-- Start a goal: exactly what `cmd_queue_advance` writes back. -/
def start (q : Queue) (n : Nat) : Queue :=
  q.map (fun r => if r.name = n then { r with status := Status.active } else r)

/-- Finish the active goal, as the gate does before advancing. -/
def finish (q : Queue) (n : Nat) : Queue :=
  q.map (fun r => if r.name = n then { r with status := Status.done } else r)

/-! ## The scheduler only ever schedules something it may -/

/-- Whatever `next` returns is a row of the queue, and it is eligible. -/
theorem next_is_eligible {q : Queue} {r : Row} (h : next q = some r) :
    r ∈ q ∧ eligible q r = true := by
  have := List.find?_some h
  exact ⟨List.mem_of_find?_eq_some h, this⟩

/-- A scheduled goal is pending, and its dependency — if it has one — is done.
The multi-goal form of "nothing proceeds on a promise". -/
theorem next_respects_dependencies {q : Queue} {r : Row} (h : next q = some r) :
    r.status = Status.pending ∧
      (r.after = none ∨ ∃ d, r.after = some d ∧ statusOf q d = some Status.done) := by
  have he : eligible q r = true := (next_is_eligible h).2
  cases hs : r.status with
  | pending =>
    refine ⟨rfl, ?_⟩
    cases ha : r.after with
    | none => exact Or.inl rfl
    | some d =>
      refine Or.inr ⟨d, rfl, ?_⟩
      have hb : (statusOf q d == some Status.done) = true := by
        simpa [eligible, hs, ha] using he
      simpa using hb
  | active => exfalso; simp [eligible, hs] at he
  | done => exfalso; simp [eligible, hs] at he

/-- Nothing scheduled is a fact about the queue: every row is ineligible. The
shell prints why; this says there is a why. -/
theorem none_means_nothing_eligible {q : Queue} (h : next q = none) :
    ∀ r ∈ q, eligible q r = false := by
  intro r hr
  have := List.find?_eq_none.mp h r hr
  simpa using this

/-! ## Progress, and its absence -/

/-- If any row is eligible, the scheduler returns one. No deadlock while work
is ready: silence from `next` always means the queue is genuinely stuck. -/
theorem eligible_means_progress {q : Queue} {r : Row}
    (hr : r ∈ q) (he : eligible q r = true) : ∃ s, next q = some s := by
  cases h : next q with
  | none => exact absurd he (by simp [none_means_nothing_eligible h r hr])
  | some s => exact ⟨s, rfl⟩

/-- Starting a goal never creates pending work. The half of termination that
holds for every queue, unconditionally. -/
theorem start_pending_le (q : Queue) (n : Nat) :
    pendingCount (start q n) ≤ pendingCount q := by
  induction q with
  | nil => simp [start, pendingCount]
  | cons a t ih =>
    by_cases hname : a.name = n <;>
      cases hs : a.status <;>
      simp [start, pendingCount, hname, hs] at ih ⊢ <;>
      omega

/-- Starting a goal strictly reduces the pending count, so the multi-goal loop
terminates: invariant 4 applied to the queue.

No uniqueness of names is assumed. `start` flips *every* row with that name, and
the scheduled row was pending, so at least one pending row leaves the count and
none enters it. -/
theorem advance_decreases_pending {q : Queue} {r : Row} (h : next q = some r) :
    pendingCount (start q r.name) < pendingCount q := by
  have hmem : r ∈ q := (next_is_eligible h).1
  have hst : r.status = Status.pending := (next_respects_dependencies h).1
  clear h
  revert hmem
  induction q with
  | nil => intro hmem; cases hmem
  | cons a t ih =>
    intro hmem
    rcases List.mem_cons.mp hmem with rfl | htail
    · have := start_pending_le t r.name
      simp [start, pendingCount, hst] at this ⊢
      omega
    · by_cases hname : a.name = r.name
      · cases hs : a.status with
        | pending =>
          have := start_pending_le t r.name
          simp [start, pendingCount, hname, hs] at this ⊢
          omega
        | active =>
          have := ih htail
          simp [start, pendingCount, hname, hs] at this ⊢
          omega
        | done =>
          have := ih htail
          simp [start, pendingCount, hname, hs] at this ⊢
          omega
      · have := ih htail
        cases hs : a.status <;>
          simp [start, pendingCount, hname, hs] at this ⊢ <;>
          omega

/-! ## Cycles -/

/-- Two goals waiting on each other are never scheduled: the queue reports
blocked rather than choosing one. Checked by the kernel on the witness. -/
theorem cycle_never_runs :
    next [⟨1, Status.pending, some 2⟩, ⟨2, Status.pending, some 1⟩] = none := by
  decide

/-- A three-goal cycle likewise. -/
theorem longer_cycle_never_runs :
    next [⟨1, Status.pending, some 3⟩, ⟨2, Status.pending, some 1⟩,
          ⟨3, Status.pending, some 2⟩] = none := by
  decide

/-- A dependency that was never queued blocks rather than running: `statusOf`
returns `none`, which is not `done`. A missing predecessor is the same as an
unfinished one, which is the safe reading. -/
theorem missing_dependency_never_runs :
    next [⟨1, Status.pending, some 99⟩] = none := by
  decide

/-! ## The straight-line case, which is the common one -/

/-- A chain runs in order: with nothing done yet, only the head is eligible. -/
theorem chain_starts_at_the_head :
    next [⟨1, Status.pending, none⟩, ⟨2, Status.pending, some 1⟩] =
      some ⟨1, Status.pending, none⟩ := by
  decide

/-- And the dependent goal becomes eligible exactly when its predecessor is
done — not when it is merely active. -/
theorem dependent_waits_for_done :
    next [⟨1, Status.active, none⟩, ⟨2, Status.pending, some 1⟩] = none ∧
    next [⟨1, Status.done, none⟩, ⟨2, Status.pending, some 1⟩] =
      some ⟨2, Status.pending, some 1⟩ := by
  exact ⟨by decide, by decide⟩

/-! ## Corpus — the same shapes the shell fixture uses -/

-- a two-goal chain: head first, dependent second, and only once the head is done
private def chain (s : Status) : Queue := [⟨1, s, none⟩, ⟨2, Status.pending, some 1⟩]

#guard next (chain Status.pending) == some ⟨1, Status.pending, none⟩
#guard next (chain Status.active) == none
#guard next (chain Status.done) == some ⟨2, Status.pending, some 1⟩
#guard next [⟨1, Status.pending, some 2⟩, ⟨2, Status.pending, some 1⟩] == none
#guard pendingCount [⟨1, Status.done, none⟩, ⟨2, Status.pending, some 1⟩] = 1
#guard pendingCount (start [⟨1, Status.pending, none⟩] 1) = 0

end GoalForge.GoalQueue
