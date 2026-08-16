/-
    This file is part of goal-forge.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
    Authors: Saimonokuma
-/
import Mathlib

/-! # goal-forge: the learned per-criterion timeout is a safe clamp

`scripts/lib.sh:gf_criterion_timeout` grows a verify budget from measured
history. Growing a timeout can only remove false failures; SHRINKING one can
invent failures that are not real, and a verifier that manufactures failures is
worse than a slow one. The shell says so in a comment. This file settles it.

The model mirrors the awk `END` block one line at a time:

```awk
t = base
if (killed  > 0 && killed  * 2 > t) t = killed  * 2   -- a timeout doubles
if (slowest > 0 && slowest * 3 > t) t = slowest * 3   -- a pass gets 3x headroom
if (t > cap)  t = cap                                  -- bounded growth
if (t < base) t = base                                 -- never below configured
```

The last line did not exist until this file was written: modelling the clamp
exposed that `GF_TIMEOUT_MAX=60` with `CMD_TIMEOUT=300` handed every criterion
60s, i.e. the one direction the design forbids. `learned_never_below_base` is
the theorem that would have caught it, and does catch it now (mutation M16).

WHAT IS PROVED: properties of the model below.
WHAT IS NOT: that awk implements this model. That binding is mechanical but
empirical -- the `#guard` corpus at the bottom is the same corpus
`tests/run_tests.sh` runs the real shell against (`tests/timeout_corpus.tsv`),
so a divergence between model and implementation turns one of them red.
-/

-- `#guard` IS the point here (it executes the model), so the mathlib style
-- linter that bans `#`-commands is switched off for this file only.
set_option linter.hashCommand false

namespace GoalForge.LearnedTimeout

/-- One recorded verify run: what it was allowed, what it took, how it ended.
Mirrors a row of `.claude/goal/timings.tsv`. -/
structure Obs where
  /-- seconds the run was allowed -/
  allowed : Nat
  /-- seconds the run actually took -/
  duration : Nat
  /-- true when the watchdog killed it -/
  timedOut : Bool
deriving Repr, DecidableEq

/-- Largest budget that was ever killed (0 if none). Mirrors awk's `killed`. -/
def killedMax : List Obs → Nat
  | [] => 0
  | o :: t => if o.timedOut then max o.allowed (killedMax t) else killedMax t

/-- Slowest run that ever succeeded (0 if none). Mirrors awk's `slowest`.
Note `timedOut = false` covers both `pass` and `fail` rows in the model; the
shell records duration for both and only `pass` rows feed `slowest`, so this
over-approximates in the safe (larger) direction. -/
def slowestOk : List Obs → Nat
  | [] => 0
  | o :: t => if o.timedOut then slowestOk t else max o.duration (slowestOk t)

/-- The uncapped candidate: the three `if` lines before the clamp. -/
def raw (base : Nat) (os : List Obs) : Nat :=
  max base (max (2 * killedMax os) (3 * slowestOk os))

/-- The learned timeout: candidate, capped above, floored at the configured
value. This is `gf_criterion_timeout`. -/
def learned (base cap : Nat) (os : List Obs) : Nat :=
  max base (min cap (raw base os))

/-! ## The two safety properties -/

/-- **Never shrinks.** Whatever the history and whatever the cap, a criterion is
never given less than its configured `CMD_TIMEOUT`. This is the property that
forbids inventing failures, and it holds unconditionally -- including when the
cap is smaller than the base, which is the case the shell got wrong. -/
theorem learned_never_below_base (base cap : Nat) (os : List Obs) :
    base ≤ learned base cap os := by
  unfold learned; omega

/-- **Bounded growth.** Learning can never produce an unbounded hang: the budget
stays within `max base cap`, so with a sane `cap` it is `cap`. -/
theorem learned_bounded (base cap : Nat) (os : List Obs) :
    learned base cap os ≤ max base cap := by
  unfold learned raw; omega

/-- With a cap at or above the configured budget -- the ordinary configuration,
`CMD_TIMEOUT=120` and `GF_TIMEOUT_MAX=1800` -- the bound is exactly the cap. -/
theorem learned_le_cap (base cap : Nat) (os : List Obs) (h : base ≤ cap) :
    learned base cap os ≤ cap := by
  unfold learned raw; omega

/-! ## The properties that make it useful rather than merely safe -/

/-- **No history means no change.** A fresh criterion runs on exactly the
configured budget: the feature is dormant until it has measured something.

Stated first as `base ≤ cap → …`; the hypothesis turned out to be unnecessary
(the linter flagged it as unreferenced) and is dropped, which strengthens the
theorem: an empty history yields `base` for EVERY cap, sane or not. -/
theorem learned_nil (base cap : Nat) : learned base cap [] = base := by
  unfold learned raw killedMax slowestOk; omega

/-- **A timeout buys real headroom.** If a run was killed at `a` seconds and the
cap allows it, the next budget is strictly greater than `a` -- so retrying is
progress, not the same wall twice. Without this the gate would loop forever
re-killing a criterion at an unchanged budget. -/
theorem timeout_grows_strictly
    (base cap a d : Nat) (os : List Obs) (ha : 0 < a) (hc : 2 * a ≤ cap) :
    a < learned base cap (⟨a, d, true⟩ :: os) := by
  -- keep `killedMax` OPAQUE for omega: unfolding it leaves an `if` that omega
  -- cannot see through. Bound it once, then the arithmetic is linear.
  have h1 : a ≤ killedMax (⟨a, d, true⟩ :: os) := by simp [killedMax]
  unfold learned raw
  omega

/-- **Monotone in the cap.** Raising `GF_TIMEOUT_MAX` never lowers a budget. -/
theorem learned_mono_cap (base c₁ c₂ : Nat) (os : List Obs) (h : c₁ ≤ c₂) :
    learned base c₁ os ≤ learned base c₂ os := by
  unfold learned; omega

/-- **Monotone in the configured budget.** Raising `CMD_TIMEOUT` never lowers a
learned budget either, so the operator knob still works after learning starts. -/
theorem learned_mono_base (b₁ b₂ cap : Nat) (os : List Obs) (h : b₁ ≤ b₂) :
    learned b₁ cap os ≤ learned b₂ cap os := by
  unfold learned raw; omega

/-! ## Executable corpus -- the binding to the shell

Every row below is a value `tests/run_tests.sh` measures from the real
`gf_criterion_timeout`. The suite drives the shell over
`tests/timeout_corpus.tsv`; these `#guard`s drive the model over the same rows.
If the awk and the model ever disagree, one side goes red. -/

-- nothing measured, base 2, cap 1800
#guard learned 2 1800 [] = 2
-- one kill at 2s -> doubled to 4s.  (suite: "budget doubles")
#guard learned 2 1800 [⟨2, 2, true⟩] = 4
-- a 3s pass -> 3x headroom = 9s.  (suite: "3x headroom")
#guard learned 2 1800 [⟨2, 2, true⟩, ⟨4, 3, false⟩] = 9
-- the cap bites.  (suite: "growth is capped by GF_TIMEOUT_MAX")
#guard learned 2 3 [⟨2, 2, true⟩] = 3
-- a fast pass never shrinks the budget.  (suite: "never shrinks")
#guard learned 2 1800 [⟨2, 0, false⟩] = 2
-- THE DEFECT: a cap below the configured budget must not shrink it. Before the
-- fix the shell returned 60 here; model and shell now agree on 300.
#guard learned 300 60 [] = 300

-- The same rows as theorems, so the corpus is kernel-checked and not merely
-- elaborated away: `decide` on a decidable equality of naturals.
example : learned 2 1800 [] = 2 := by decide
example : learned 2 1800 [⟨2, 2, true⟩] = 4 := by decide
example : learned 2 3 [⟨2, 2, true⟩] = 3 := by decide
example : learned 300 60 [] = 300 := by decide

end GoalForge.LearnedTimeout
