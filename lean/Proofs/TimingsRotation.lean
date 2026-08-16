/-
    This file is part of goal-forge.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
    Authors: Saimonokuma
-/
import Proofs.GoalForge.LearnedTimeout

/-! # goal-forge: rotating the timings ledger cannot change a learned budget

v3.3 shipped `timings.tsv` as an append-only file with no rotation. Its own
review flagged it; the v2 author's review flagged it again as defect 3.

The obvious fix is the dangerous one. `gf_criterion_timeout` reads the LARGEST
killed budget and the LARGEST passing duration for a criterion, so a rotation
that simply keeps the most recent N rows can drop the row that determines the
budget — and the budget then SHRINKS. Shrinking is the single direction the
learned-timeout feature promises never to move in, because a shorter budget
invents failures that never happened. A naive rotation would therefore have
been a silent regression of the guarantee proved in `LearnedTimeout.lean`,
disguised as housekeeping.

`scripts/lib.sh:gf_timing_rotate` keeps, per criterion, the row carrying its
largest killed `allowed` and the row carrying its largest passing `duration`,
plus the newest `GF_TIMINGS_MAX` rows. This file proves that any rotation with
those two properties leaves every learned budget bit-identical, and that
without them the budget really can shrink (`naive_rotation_can_shrink` — the
negative control, in Lean rather than in prose).

WHAT IS PROVED: properties of the model.
WHAT IS NOT: that awk implements it. `test_timings_rotation` binds the two by
reading the REAL `gf_criterion_timeout` on both sides of a real rotation and
demanding the same number, with a naive-rotation control that must differ.

In the shared tree this module is `Proofs.GoalForge.TimingsRotation`.
-/

set_option linter.hashCommand false

namespace GoalForge.TimingsRotation

open GoalForge.LearnedTimeout

/-! ## Bounding lemmas

Both statistics the clamp reads are maxima over a filtered list, so each needs
the same two facts: a maximum is below any bound that holds for every element,
and dropping elements can only lower it. -/

/-- If every killed row in `os` is bounded by `b`, so is `killedMax os`. -/
theorem killedMax_le_of_bound (b : Nat) (os : List Obs)
    (h : ∀ o ∈ os, o.timedOut = true → o.allowed ≤ b) : killedMax os ≤ b := by
  induction os with
  | nil => simp [killedMax]
  | cons o t ih =>
    have ht : killedMax t ≤ b := ih (fun x hx => h x (by simp [hx]))
    by_cases ho : o.timedOut
    · have h1 : o.allowed ≤ b := h o (by simp) ho
      simp [killedMax, ho]
      omega
    · simpa [killedMax, ho] using ht

/-- Same, for the slowest successful run. -/
theorem slowestOk_le_of_bound (b : Nat) (os : List Obs)
    (h : ∀ o ∈ os, o.timedOut = false → o.duration ≤ b) : slowestOk os ≤ b := by
  induction os with
  | nil => simp [slowestOk]
  | cons o t ih =>
    have ht : slowestOk t ≤ b := ih (fun x hx => h x (by simp [hx]))
    by_cases ho : o.timedOut
    · simpa [slowestOk, ho] using ht
    · have h1 : o.duration ≤ b := h o (by simp) (by simp [ho])
      simp [slowestOk, ho]
      omega

/-- **Dropping rows can only lower the killed maximum.** This is the half that
makes a naive rotation unsafe. -/
theorem killedMax_le_of_sublist {os' os : List Obs} (hs : os'.Sublist os) :
    killedMax os' ≤ killedMax os := by
  induction hs with
  | slnil => simp [killedMax]
  | cons a _ ih => by_cases ha : a.timedOut <;> simp [killedMax, ha] <;> omega
  | cons_cons a _ ih => by_cases ha : a.timedOut <;> simp [killedMax, ha] <;> omega

/-- Same, for the slowest successful run. -/
theorem slowestOk_le_of_sublist {os' os : List Obs} (hs : os'.Sublist os) :
    slowestOk os' ≤ slowestOk os := by
  induction hs with
  | slnil => simp [slowestOk]
  | cons a _ ih => by_cases ha : a.timedOut <;> simp [slowestOk, ha] <;> omega
  | cons_cons a _ ih => by_cases ha : a.timedOut <;> simp [slowestOk, ha] <;> omega

/-! ## What retention has to guarantee -/

/-- **The killed maximum survives.** A rotation that keeps a subset of the rows
AND keeps at least one row carrying the maximum killed budget reports exactly
the same maximum. This is the retention rule `gf_timing_rotate` implements. -/
theorem killed_preserved {os' os : List Obs} (hsub : os'.Sublist os)
    (hkeep : ∀ o ∈ os, o.timedOut = true → o.allowed ≤ killedMax os') :
    killedMax os' = killedMax os :=
  le_antisymm (killedMax_le_of_sublist hsub) (killedMax_le_of_bound _ os hkeep)

/-- **The slowest pass survives**, under the matching retention rule. -/
theorem slowest_preserved {os' os : List Obs} (hsub : os'.Sublist os)
    (hkeep : ∀ o ∈ os, o.timedOut = false → o.duration ≤ slowestOk os') :
    slowestOk os' = slowestOk os :=
  le_antisymm (slowestOk_le_of_sublist hsub) (slowestOk_le_of_bound _ os hkeep)

/-- **The budget is a function of those two statistics alone.** Anything else a
rotation throws away is genuinely free to discard. -/
theorem learned_stable_under_retention (base cap : Nat) {os' os : List Obs}
    (hk : killedMax os' = killedMax os) (hs : slowestOk os' = slowestOk os) :
    learned base cap os' = learned base cap os := by
  unfold learned raw
  rw [hk, hs]

/-- **The theorem the shell relies on.** Rotate however you like: as long as you
keep a subset of the rows, and keep the two extremes per criterion, EVERY
learned budget is unchanged. Bounding the file therefore costs nothing in
safety — which is the claim `test_timings_rotation` measures on the real awk. -/
theorem rotation_preserves_budget (base cap : Nat) {os' os : List Obs}
    (hsub : os'.Sublist os)
    (hk : ∀ o ∈ os, o.timedOut = true → o.allowed ≤ killedMax os')
    (hs : ∀ o ∈ os, o.timedOut = false → o.duration ≤ slowestOk os') :
    learned base cap os' = learned base cap os :=
  learned_stable_under_retention base cap (killed_preserved hsub hk) (slowest_preserved hsub hs)

/-! ## The negative control, as a theorem

A preservation theorem is worth nothing if preservation were automatic. It is
not: retention is exactly what buys it. -/

/-- **Retention is necessary, not decorative.** There is a rotation that keeps a
subset of the rows and STRICTLY shrinks the budget — the naive "keep the last N
rows" that this release deliberately did not ship. 800s of earned headroom
collapses to the configured 10s, and every subsequent run gets killed at a wall
it had already proved it needed to pass. -/
theorem naive_rotation_can_shrink :
    ∃ (base cap : Nat) (os' os : List Obs),
      os'.Sublist os ∧ learned base cap os' < learned base cap os :=
  ⟨10, 1800, [], [⟨400, 400, true⟩], List.nil_sublist _, by decide⟩

/-- The same fact in the form the suite measures: the row that determines the
budget is the one an age-based rotation would delete first, because it is the
OLDEST. Old is not the same as irrelevant. -/
theorem oldest_row_can_be_the_determining_row (base : Nat) (a d : Nat)
    (h : base < 2 * a) (hcap : 2 * a ≤ 1800) :
    learned base 1800 [] < learned base 1800 [⟨a, d, true⟩] := by
  have h1 : a ≤ killedMax [(⟨a, d, true⟩ : Obs)] := by simp [killedMax]
  unfold learned raw
  simp [killedMax, slowestOk]
  omega

/-! ## Executable corpus — the binding to `test_timings_rotation`

These are the exact numbers the suite reads out of the real shell. -/

-- the suite's fixture: base 10 (`--timeout 10`), one old 400s kill -> 800s
#guard learned 10 1800 [⟨400, 400, true⟩] = 800
-- ...and after rotation the shell must still say 800 (same list, extreme kept)
#guard learned 10 1800 [⟨400, 400, true⟩, ⟨10, 1, false⟩] = 800
-- the second criterion in the same fixture: a 900s kill -> 1800s
#guard learned 10 1800 [⟨900, 900, true⟩] = 1800
-- what a naive tail-only rotation would have produced instead: the floor
#guard learned 10 1800 [⟨10, 1, false⟩] = 10

example : learned 10 1800 [⟨400, 400, true⟩] = 800 := by decide
example : learned 10 1800 [⟨900, 900, true⟩] = 1800 := by decide
example : learned 10 1800 [⟨10, 1, false⟩] = 10 := by decide

end GoalForge.TimingsRotation
