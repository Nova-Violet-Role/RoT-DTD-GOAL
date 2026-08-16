/-
    This file is part of goal-forge.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
    Authors: Saimonokuma
-/
import Proofs.GoalForge.LearnedTimeout

/-! # goal-forge: flake history is scoped to the SEAL, and the scope has no clock

v3.4 shipped flake detection: a criterion that has both passed and failed
against *the same sealed check* is reported, because such a pass is luck rather
than evidence. Dogfooding found the scope was wrong — history was keyed by
criterion id alone, so a previous goal's failures were charged to the current
goal. That was fixed by scoping to the goal (`CREATED_ISO`).

The v2 author's second review found the residual defect, and was right: the
goal is still the wrong unit. A criterion that failed, was **sharpened**, and
then passed has not given two answers to one question — it was asked a new
question, and the old answer belongs to a check that no longer exists.

v3.5 scoped each criterion's history to **its own ledger seal**, comparing the
row's timestamp against the seal's timestamp.

## The hole the third review found, and what it cost this model

That comparison assumed something nobody wrote down: **that the machine agrees
with itself about time.** A clock that jumps backwards, a re-seal written by a
fast host, a VM restored from a snapshot — any of these puts the seal *ahead*
of rows genuinely recorded after it. Both halves of a real fail→pass flip then
fall outside the window, the alarm returns nothing, and `GATE_FLAKY=strict`
completes in silence.

`narrowing_only_removes` and `seal_scope_never_invents` are true, and they did
not catch it. They are theorems about *narrowing the window*, and this was a
defect in *choosing the cutoff* — one layer below where they were looking. A
model with no clock in it cannot see a clock going wrong. That is the honest
lesson and it is why the timestamp is now modelled as data the verdict must
never read.

v3.6 scopes by **seal generation**: an integer that only counts up, written by
the same code that writes the seal (`scripts/lib.sh:gf_seal_one`,
`gf_seal_gen`), and recorded on every timings row. `ts` remains in the file for
humans and is read by nothing.

* `clock_scope_can_hide_a_flip` — the hole, as a kernel-checked counterexample.
* `gen_scope_ignores_the_clock` — the replacement verdict is unchanged when
  *every timestamp in the history is rewritten by an arbitrary function*. No
  clock assumption can be hiding in it, because no clock value can move it.
* `ts_scope_needs_a_monotone_clock` — the two agree exactly when the assumption
  v3.5 never stated happens to hold. That is the assumption, made explicit.
* `legacy_rows_are_never_hidden` — a row from a v3.5 state directory has no
  generation, and is INCLUDED. The upgrade may over-report; it may not hide.

## The second v3.6 change: a flake is a REGRESSION

Measured, not reasoned. `tests/experiments/flaky_policy.sh` ran goals under
`GATE_FLAKY=strict` against the old "has both passed and failed" definition: the
ordinary loop — the gate reports a criterion failing, the work gets done, the
criterion passes — was refused as a coin flip in **5 goals out of 5**. Every goal
that does not pass on the first try is most goals, so the policy was unusable and
the `warn` default was hiding that rather than measuring it.

Order is the distinction the old definition threw away:

* fail, then pass — the world changed. That is the loop working.
* pass, then fail — the *same sealed check*, unsharpened, answering differently.

`flakyGen` is now `regressed`: a pass followed later by a failure, inside one
generation. After the change: 0 refusals in 40 goals across the two false-alarm
arms, and 4 refusals plus 6 escalations in 20 goals carrying a genuinely random
check. That measurement is why `GATE_FLAKY` now defaults to `strict`.

`fail_then_pass_is_not_accused` is the price, stated as a theorem: a random check
seen only as failure-then-pass is not reported, and cannot be, because that
history is exactly what completed work looks like.

WHAT IS PROVED: properties of the model — soundness of narrowing, that a
re-seal clears the history, that the generation verdict is clock-independent,
that legacy rows survive the upgrade, and that progress is never accused.
WHAT IS NOT: that awk implements this model. `test_flaky_detection` and
`test_clock_cannot_hide_a_flip` bind the two by running the REAL `gf_flaky_ids`
over fixtures — including a future-dated seal, which is the differential that
fails on v3.5.0.

In the shared tree this module is `Proofs.GoalForge.FlakyScope`.
-/

set_option linter.hashCommand false

namespace GoalForge.FlakyScope

/-- One row of `timings.tsv`, reduced to what the flake verdict reads.

`ts` models the fixed-width `YYYY-mm-dd HH:MM:SS` timestamp; the shell compares
those as strings, which is chronological precisely because the format is fixed
width, and `Nat` is that same total order. `gen` is the seal generation the row
was written under: `none` models a row from a v3.5 state directory, which has
no such column. -/
structure Row where
  /-- when the verification ran — for humans; the v3.6 verdict never reads it -/
  ts : Nat
  /-- which criterion it belongs to -/
  cid : Nat
  /-- `true` for outcome `pass`; `false` models both `fail` and `timeout` -/
  passed : Bool
  /-- the seal generation in force when the row was written; `none` = legacy row -/
  gen : Option Nat
deriving DecidableEq, Repr

/-! ## The two windows

`afterSeal` is v3.5: rows at or after a timestamp. `sameGen` is v3.6: rows of
the criterion's current seal generation, plus every row whose generation is
unknown. Both are here so the difference can be stated as a theorem instead of
a comment. -/

/-- The v3.5 window: rows recorded at or after the seal *time*. -/
def afterSeal (cutoff : Nat) (rows : List Row) : List Row :=
  rows.filter (fun r => decide (cutoff ≤ r.ts))

/-- Is this row inside the current generation? A row with no recorded
generation is included — the upgrade must never silently drop history. -/
def inGen (g : Nat) (r : Row) : Bool :=
  match r.gen with
  | none   => true
  | some k => decide (g ≤ k)

/-- The v3.6 window: rows of the current seal generation. -/
def sameGen (g : Nat) (rows : List Row) : List Row :=
  rows.filter (inGen g)

/-- Did this criterion ever pass in the given window? -/
def sawPass (cid : Nat) (rows : List Row) : Bool :=
  rows.any (fun r => r.cid == cid && r.passed)

/-- Did this criterion ever fail (or time out) in the given window? -/
def sawFail (cid : Nat) (rows : List Row) : Bool :=
  rows.any (fun r => r.cid == cid && !r.passed)

/-- The v3.5 verdict: both answers, about the same sealed check, by timestamp. -/
def flaky (cutoff cid : Nat) (rows : List Row) : Bool :=
  sawPass cid (afterSeal cutoff rows) && sawFail cid (afterSeal cutoff rows)

/-- Was there a pass, and then LATER a failure? The v3.6 definition of a flake.

Measured, not reasoned: under the old definition (`sawPass && sawFail`), the
ordinary loop — the gate reports a criterion failing, the work gets done, the
criterion passes — was refused as a coin flip in 5 goals out of 5
(`tests/experiments/flaky_policy.sh`). Order is what distinguishes progress from
randomness: fail-then-pass is the world changing, pass-then-fail is the same
sealed check answering differently about the same question. -/
def regressed (cid : Nat) : List Row → Bool
  | [] => false
  | r :: t =>
    if r.cid == cid && r.passed then
      sawFail cid t || regressed cid t
    else
      regressed cid t

/-- The v3.6 verdict: a regression, inside the current generation. -/
def flakyGen (g cid : Nat) (rows : List Row) : Bool :=
  regressed cid (sameGen g rows)

/-- The v3.5 verdict, kept so the change can be compared rather than asserted. -/
def flakyBoth (g cid : Nat) (rows : List Row) : Bool :=
  sawPass cid (sameGen g rows) && sawFail cid (sameGen g rows)

/-! ## Membership in the scoped window -/

/-- A row is in the v3.5 window exactly when it is a row at all and is not older
than the seal. -/
theorem mem_afterSeal {cutoff : Nat} {rows : List Row} {r : Row} :
    r ∈ afterSeal cutoff rows ↔ r ∈ rows ∧ cutoff ≤ r.ts := by
  simp [afterSeal, List.mem_filter]

/-- A row is in the v3.6 window exactly when it is a row at all and its
generation is current (or unknown). -/
theorem mem_sameGen {g : Nat} {rows : List Row} {r : Row} :
    r ∈ sameGen g rows ↔ r ∈ rows ∧ inGen g r = true := by
  simp [sameGen, List.mem_filter]

/-- `any` transports along any membership-preserving map between lists. The one
lemma every monotonicity result below is built from. -/
theorem any_mono {p : Row → Bool} {l₁ l₂ : List Row}
    (h : ∀ r ∈ l₁, r ∈ l₂) (hp : l₁.any p = true) : l₂.any p = true := by
  rw [List.any_eq_true] at hp ⊢
  obtain ⟨r, hr, hpr⟩ := hp
  exact ⟨r, h r hr, hpr⟩

/-- Widening the window (an earlier seal) keeps every row it already had. -/
theorem afterSeal_mono {s₁ s₂ : Nat} (h : s₁ ≤ s₂) (rows : List Row) :
    ∀ r ∈ afterSeal s₂ rows, r ∈ afterSeal s₁ rows := by
  intro r hr
  rw [mem_afterSeal] at hr ⊢
  exact ⟨hr.1, Nat.le_trans h hr.2⟩

/-- The same, one generation earlier: an older generation number is a wider
window. -/
theorem sameGen_mono {g₁ g₂ : Nat} (h : g₁ ≤ g₂) (rows : List Row) :
    ∀ r ∈ sameGen g₂ rows, r ∈ sameGen g₁ rows := by
  intro r hr
  rw [mem_sameGen] at hr ⊢
  refine ⟨hr.1, ?_⟩
  have := hr.2
  cases hg : r.gen with
  | none   => simp [inGen, hg]
  | some k =>
    rw [inGen, hg] at this ⊢
    simp only [decide_eq_true_eq] at this ⊢
    exact Nat.le_trans h this

/-! ## Soundness of narrowing (unchanged from v3.5, and still true)

A narrower window never invents a flake the wider window did not see. These
theorems are correct; the third review's finding was that they are also *not
enough*, because they say nothing about whether the cutoff itself is right. -/

/-- Narrowing the window can only remove flake reports, never add one. -/
theorem narrowing_only_removes {s₁ s₂ cid : Nat} (h : s₁ ≤ s₂) (rows : List Row)
    (hf : flaky s₂ cid rows = true) : flaky s₁ cid rows = true := by
  rw [flaky, Bool.and_eq_true] at hf ⊢
  exact ⟨any_mono (afterSeal_mono h rows) hf.1, any_mono (afterSeal_mono h rows) hf.2⟩

/-- The seal-scoped verdict never accuses a criterion the unscoped verdict
would have cleared. -/
theorem seal_scope_never_invents (cutoff cid : Nat) (rows : List Row)
    (hf : flaky cutoff cid rows = true) : flaky 0 cid rows = true :=
  narrowing_only_removes (Nat.zero_le cutoff) rows hf

/-- A pass anywhere in the tail is a pass in the list. -/
theorem sawPass_cons (r : Row) {cid : Nat} {t : List Row} (h : sawPass cid t = true) :
    sawPass cid (r :: t) = true := by
  rw [sawPass] at h ⊢; simp [h]

/-- A failure anywhere in the tail is a failure in the list. -/
theorem sawFail_cons (r : Row) {cid : Nat} {t : List Row} (h : sawFail cid t = true) :
    sawFail cid (r :: t) = true := by
  rw [sawFail] at h ⊢; simp [h]

/-- A passing head is a pass. -/
theorem sawPass_head {cid : Nat} {r : Row} {t : List Row}
    (h : (r.cid == cid && r.passed) = true) : sawPass cid (r :: t) = true := by
  rw [sawPass]; simp [h]

/-- A reported regression really contains a pass and a failure. -/
theorem regressed_imp (cid : Nat) (l : List Row) (h : regressed cid l = true) :
    sawPass cid l = true ∧ sawFail cid l = true := by
  induction l with
  | nil => simp [regressed] at h
  | cons r t ih =>
    by_cases hc : (r.cid == cid && r.passed) = true
    · rw [regressed, if_pos hc, Bool.or_eq_true] at h
      refine ⟨sawPass_head hc, ?_⟩
      rcases h with hf | hr
      · exact sawFail_cons r hf
      · exact sawFail_cons r (ih hr).2
    · rw [regressed, if_neg hc] at h
      exact ⟨sawPass_cons r (ih h).1, sawFail_cons r (ih h).2⟩

/-- The generation-scoped verdict cannot invent one either: every flake it
reports is a genuine pass and a genuine failure among the actual rows. -/
theorem gen_scope_never_invents (g cid : Nat) (rows : List Row)
    (hf : flakyGen g cid rows = true) :
    sawPass cid rows = true ∧ sawFail cid rows = true := by
  rw [flakyGen] at hf
  have h := regressed_imp cid (sameGen g rows) hf
  have hsub : ∀ r ∈ sameGen g rows, r ∈ rows := by
    intro r hr; exact (mem_sameGen.mp hr).1
  exact ⟨any_mono hsub h.1, any_mono hsub h.2⟩

/-! ## The clock hole, and its repair

The three theorems the third review asked for. The first is the defect; the
second is why the replacement cannot repeat it; the third names the assumption
v3.5 was making without saying so. -/

/-- **The hole.** A seal timestamp ahead of the rows it scopes — a clock that
jumped backwards — hides a genuine regression from the v3.5 verdict, while the
v3.6 verdict reports it. Both halves by `decide`: the kernel checks the witness
rather than a comment asserting it.

A pass at time 1 and a failure at time 2, both of generation 1, with the seal
stamped at 100. -/
theorem clock_scope_can_hide_a_flip :
    ∃ (rows : List Row) (cutoff g cid : Nat),
      flaky cutoff cid rows = false ∧ flakyGen g cid rows = true :=
  ⟨[⟨1, 7, true, some 1⟩, ⟨2, 7, false, some 1⟩], 100, 1, 7, by decide, by decide⟩

/-- The window, one row at a time. Stated as an equation so later proofs never
have to unfold `sameGen` — unfolding it is what makes `simp` rewrite the very
hypotheses it is given. -/
theorem sameGen_cons (g : Nat) (r : Row) (t : List Row) :
    sameGen g (r :: t) = if inGen g r then r :: sameGen g t else sameGen g t := by
  simp [sameGen, List.filter_cons]

/-- The failure check, one row at a time. -/
theorem sawFail_cons_eq (cid : Nat) (r : Row) (t : List Row) :
    sawFail cid (r :: t) = ((r.cid == cid && !r.passed) || sawFail cid t) := by
  simp [sawFail]

/-- Rewriting a timestamp cannot move a row in or out of the window. -/
theorem inGen_map_ts (g : Nat) (f : Nat → Nat) (r : Row) :
    inGen g { r with ts := f r.ts } = inGen g r := by
  cases hx : r.gen <;> simp [inGen, hx]

theorem sameGen_map_ts (g : Nat) (f : Nat → Nat) (l : List Row) :
    sameGen g (l.map (fun r => { r with ts := f r.ts }))
      = (sameGen g l).map (fun r => { r with ts := f r.ts }) := by
  induction l with
  | nil => rfl
  | cons r t ih =>
    rw [List.map_cons, sameGen_cons, sameGen_cons, inGen_map_ts]
    cases hc : inGen g r <;> simp [hc, ih]

/-- Neither can it change whether a failure was seen. -/
theorem sawFail_map_ts (cid : Nat) (f : Nat → Nat) (l : List Row) :
    sawFail cid (l.map (fun r => { r with ts := f r.ts })) = sawFail cid l := by
  induction l with
  | nil => rfl
  | cons r t ih => rw [List.map_cons, sawFail_cons_eq, sawFail_cons_eq, ih]

/-- Nor whether a pass was later contradicted. -/
theorem regressed_map_ts (cid : Nat) (f : Nat → Nat) (l : List Row) :
    regressed cid (l.map (fun r => { r with ts := f r.ts })) = regressed cid l := by
  induction l with
  | nil => rfl
  | cons r t ih =>
    by_cases hc : (r.cid == cid && r.passed) = true
    · simp [regressed, hc, Function.comp_def, ih, sawFail_map_ts]
    · simp [regressed, hc, Function.comp_def, ih]

/-- **The repair.** Rewrite every timestamp in the history by an arbitrary
function — run the clock backwards, forwards, or set every row to the same
instant — and the generation-scoped verdict does not move. No assumption about
time can be hiding in a verdict that no time value can change. -/
theorem gen_scope_ignores_the_clock (g cid : Nat) (f : Nat → Nat) (rows : List Row) :
    flakyGen g cid (rows.map (fun r => { r with ts := f r.ts })) = flakyGen g cid rows := by
  rw [flakyGen, flakyGen, sameGen_map_ts, regressed_map_ts]

/-- **The assumption, named.** The timestamp window and the generation window
coincide exactly when the clock was monotone with respect to the seal: every row
of the current generation stamped at or after the seal, and every older row
stamped before it. v3.5 relied on this and never said so; v3.6 does not rely on
it at all — `gen_scope_ignores_the_clock` is that independence. -/
theorem ts_scope_needs_a_monotone_clock (cutoff g cid : Nat) (rows : List Row)
    (h₁ : ∀ r ∈ rows, inGen g r = true → cutoff ≤ r.ts)
    (h₂ : ∀ r ∈ rows, inGen g r = false → r.ts < cutoff) :
    flaky cutoff cid rows = flakyBoth g cid rows := by
  have hfil : afterSeal cutoff rows = sameGen g rows := by
    rw [afterSeal, sameGen]
    apply List.filter_congr
    intro r hr
    cases hi : inGen g r with
    | true  => simp [h₁ r hr hi]
    | false => simp [Nat.not_le.mpr (h₂ r hr hi)]
  rw [flaky, flakyBoth, hfil]

/-- A row written by v3.5 — no generation column — is never hidden by the
upgrade. The direction matters: this verdict may over-report after an upgrade,
and must never under-report. -/
theorem legacy_rows_are_never_hidden (g : Nat) (rows : List Row) :
    ∀ r ∈ rows, r.gen = none → r ∈ sameGen g rows := by
  intro r hr hnone
  exact mem_sameGen.mpr ⟨hr, by simp [inGen, hnone]⟩

/-! ## What a re-seal does -/

/-- Every row older than the seal is outside the v3.5 window. -/
theorem afterSeal_eq_nil (cutoff : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, r.ts < cutoff) : afterSeal cutoff rows = [] := by
  induction rows with
  | nil => rfl
  | cons r t ih =>
    have hr : ¬ (cutoff ≤ r.ts) := Nat.not_le.mpr (h r (by simp))
    have ht : ∀ x ∈ t, x.ts < cutoff := fun x hx => h x (by simp [hx])
    simpa [afterSeal, hr] using ih ht

/-- Every row of an older generation is outside the v3.6 window. -/
theorem sameGen_eq_nil (g : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, ∃ k, r.gen = some k ∧ k < g) : sameGen g rows = [] := by
  induction rows with
  | nil => rfl
  | cons r t ih =>
    obtain ⟨k, hk, hlt⟩ := h r (by simp)
    have hr : inGen g r = false := by
      simp [inGen, hk, Nat.not_le.mpr hlt]
    have ht : ∀ x ∈ t, ∃ k, x.gen = some k ∧ k < g := fun x hx => h x (by simp [hx])
    simpa [sameGen, hr] using ih ht

/-- Sharpening a criterion re-seals it, which advances its generation past its
whole history, and the flake verdict for it is cleared. The v3.5 guarantee,
re-established without a clock. -/
theorem resealing_clears_history_gen (g cid : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, ∃ k, r.gen = some k ∧ k < g) : flakyGen g cid rows = false := by
  rw [flakyGen, sameGen_eq_nil g rows h]; rfl

/-- The same statement for the v3.5 window, kept so the two models can be
compared rather than swapped silently. -/
theorem resealing_clears_history (cutoff cid : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, r.ts < cutoff) : flaky cutoff cid rows = false := by
  simp [flaky, sawPass, afterSeal_eq_nil cutoff rows h]

/-- A criterion whose every failure predates the seal is not flaky, even though
it has both passed and failed in its lifetime. -/
theorem fixed_before_seal_is_not_flaky (cutoff cid : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, r.passed = false → r.ts < cutoff) : flaky cutoff cid rows = false := by
  have hno : ¬ (sawFail cid (afterSeal cutoff rows) = true) := by
    intro hc
    rw [sawFail, List.any_eq_true] at hc
    obtain ⟨r, hr, hpr⟩ := hc
    rw [mem_afterSeal] at hr
    have hp : r.passed = false := by
      rcases hp' : r.passed with _ | _
      · rfl
      · simp [hp'] at hpr
    exact absurd hr.2 (Nat.not_le.mpr (h r hr.1 hp))
  have hfalse : sawFail cid (afterSeal cutoff rows) = false := by
    cases h' : sawFail cid (afterSeal cutoff rows) with
    | false => rfl
    | true  => exact absurd h' hno
  simp [flaky, hfalse]

/-! ## The verdict is per criterion -/

/-- A row belonging to another criterion cannot change this one's verdict —
the awk keys every counter by id, and this is that claim, for both scopes. -/
theorem other_ids_do_not_matter (cutoff cid : Nat) (rows : List Row) (r : Row)
    (hne : ¬ (r.cid = cid)) : flaky cutoff cid (rows ++ [r]) = flaky cutoff cid rows := by
  have hbeq : (r.cid == cid) = false := by
    simpa using beq_eq_false_iff_ne.mpr hne
  by_cases hts : cutoff ≤ r.ts <;>
    simp [flaky, sawPass, sawFail, afterSeal, List.filter_append, List.any_append, hts, hbeq]

/-- Appending another criterion's row changes neither whether this one failed… -/
theorem sawFail_append_other (cid : Nat) (l : List Row) (r : Row)
    (hbeq : (r.cid == cid) = false) : sawFail cid (l ++ [r]) = sawFail cid l := by
  simp [sawFail, List.any_append, hbeq]

/-- …nor whether it regressed. -/
theorem regressed_append_other (cid : Nat) (l : List Row) (r : Row)
    (hbeq : (r.cid == cid) = false) : regressed cid (l ++ [r]) = regressed cid l := by
  induction l with
  | nil => simp [regressed, hbeq]
  | cons a t ih =>
    by_cases hc : (a.cid == cid && a.passed) = true
    · rw [List.cons_append, regressed, if_pos hc, regressed, if_pos hc,
        sawFail_append_other cid t r hbeq, ih]
    · rw [List.cons_append, regressed, if_neg hc, regressed, if_neg hc, ih]

/-- The same, generation-scoped. -/
theorem other_ids_do_not_matter_gen (g cid : Nat) (rows : List Row) (r : Row)
    (hne : ¬ (r.cid = cid)) : flakyGen g cid (rows ++ [r]) = flakyGen g cid rows := by
  have hbeq : (r.cid == cid) = false := by
    simpa using beq_eq_false_iff_ne.mpr hne
  have hsplit : sameGen g (rows ++ [r]) = sameGen g rows ++ (if inGen g r then [r] else []) := by
    simp [sameGen, List.filter_append, List.filter_cons]
  rw [flakyGen, flakyGen, hsplit]
  cases hin : inGen g r with
  | true  => simpa [hin] using regressed_append_other cid (sameGen g rows) r hbeq
  | false => simp [hin]

/-- Neither can a criterion that only ever passed be flaky. -/
theorem all_pass_is_not_flaky (cutoff cid : Nat) (rows : List Row)
    (h : ∀ r ∈ rows, r.passed = true) : flaky cutoff cid rows = false :=
  fixed_before_seal_is_not_flaky cutoff cid rows (fun r hr hf => by
    rw [h r hr] at hf; exact absurd hf (by simp))

/-! ## The negative controls, and the blind spot, in Lean

The v3.6 definition earns its place by two measurements and pays for it with one
disclosed blind spot. All three are kernel-checked witnesses rather than prose. -/

/-- **Why the definition changed.** A criterion that failed, was worked on, and
then passed is condemned by the old "both answers" rule and cleared by the
regression rule. Measured cost of the old rule: 5 refusals in 5 ordinary goals
(`tests/experiments/flaky_policy.sh`). -/
theorem progress_is_not_a_coin_flip :
    ∃ (rows : List Row) (g cid : Nat),
      flakyBoth g cid rows = true ∧ flakyGen g cid rows = false :=
  ⟨[⟨1, 7, false, some 1⟩, ⟨5, 7, true, some 1⟩], 1, 7, by decide, by decide⟩

/-- A failure, then a sharpen (generation 2), then a pass: the unscoped verdict
still condemns it, the generation scope clears it. The v3.5 finding, preserved. -/
theorem goal_scope_can_overreport :
    ∃ (rows : List Row) (g cid : Nat),
      flakyBoth 0 cid rows = true ∧ flakyBoth g cid rows = false :=
  ⟨[⟨1, 7, false, some 1⟩, ⟨5, 7, true, some 2⟩], 2, 7, by decide, by decide⟩

/-- **The alarm still fires.** A pass and then a failure, inside one generation,
with nobody having re-sealed: reported. A definition that silenced this would be
the reassuring lie the whole feature exists to prevent. -/
theorem real_flake_survives_the_narrowing :
    ∃ (rows : List Row) (g cid : Nat),
      flakyBoth g cid rows = true ∧ flakyGen g cid rows = true :=
  ⟨[⟨4, 7, true, some 2⟩, ⟨5, 7, false, some 2⟩], 2, 7, by decide, by decide⟩

/-- **The blind spot, disclosed.** A genuinely random check observed only as
failure-then-pass is NOT reported, because that history is exactly what completed
work looks like. This is the price of the definition, and it is stated here as a
theorem rather than left for someone to discover: the same rows that clear
`progress_is_not_a_coin_flip` would clear a coin flip that landed the same way. -/
theorem fail_then_pass_is_not_accused (g cid : Nat) (r₁ r₂ : Row)
    (h₁ : r₁.passed = false) (h₂ : r₂.passed = true) :
    flakyGen g cid [r₁, r₂] = false := by
  cases hin₁ : inGen g r₁ <;> cases hin₂ : inGen g r₂ <;>
    simp [flakyGen, sameGen, List.filter_cons, hin₁, hin₂, regressed, h₁, h₂, sawFail]

/-! ## Corpus — the same rows the shell fixtures use -/

-- progress: fail then pass in one generation is NOT a flake (the measured fix)
#guard flakyGen 1 7 [⟨1, 7, false, some 1⟩, ⟨5, 7, true, some 1⟩] = false
#guard flakyBoth 1 7 [⟨1, 7, false, some 1⟩, ⟨5, 7, true, some 1⟩] = true
-- regression: pass then fail in one generation IS a flake
#guard flakyGen 2 7 [⟨4, 7, true, some 2⟩, ⟨5, 7, false, some 2⟩] = true
-- a re-seal (generation 2) clears the older generation's history
#guard flakyGen 2 7 [⟨1, 7, true, some 1⟩, ⟨5, 7, false, some 2⟩] = false
-- THE CLOCK HOLE: seal stamped at 100, rows genuinely after it, same generation.
-- v3.5 sees nothing; v3.6 reports it. This pair is the differential, in the model.
#guard flaky 100 7 [⟨1, 7, true, some 1⟩, ⟨2, 7, false, some 1⟩] = false
#guard flakyGen 1 7 [⟨1, 7, true, some 1⟩, ⟨2, 7, false, some 1⟩] = true
-- a legacy row (no generation column) is included, never hidden
#guard flakyGen 9 7 [⟨1, 7, true, none⟩, ⟨2, 7, false, none⟩] = true
-- one answer only is never a flake, whatever the window
#guard flakyGen 0 7 [⟨4, 7, true, some 1⟩, ⟨5, 7, true, some 1⟩] = false
#guard flakyGen 0 7 [⟨4, 7, false, some 1⟩, ⟨5, 7, false, some 1⟩] = false
-- another criterion's rows are invisible to this one
#guard flakyGen 0 7 [⟨4, 9, true, some 1⟩, ⟨5, 7, false, some 1⟩] = false
-- a timeout counts as a failure (modelled as passed = false)
#guard sawFail 7 [⟨4, 7, false, some 1⟩] = true

example : flakyGen 2 7 [⟨1, 7, true, some 1⟩, ⟨5, 7, false, some 2⟩] = false := by decide
example : flakyGen 1 7 [⟨1, 7, true, some 1⟩, ⟨2, 7, false, some 1⟩] = true := by decide
example : sameGen 2 [⟨1, 7, false, some 1⟩, ⟨5, 7, true, some 2⟩] = [⟨5, 7, true, some 2⟩] := by
  decide

end GoalForge.FlakyScope
