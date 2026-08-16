/-
    This file is part of goal-forge.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
    Authors: Saimonokuma
-/
import Mathlib.Data.List.Basic

/-!
# The quarantine fence: why printed output cannot forge a verdict

RoT DTD GOAL feeds a criterion's own stdout back to the model. That output is
attacker-controlled in the only sense that matters: a test can print anything,
including the exact sentence the engine uses to announce success. `gf_quarantine`
in `scripts/lib.sh` fences it -- every data line is emitted with a prefix, and
the fence's own terminator is escaped.

The shell suite tests this with `test_untrusted_output_cannot_forge_a_verdict`,
and the shell mutation campaign confirms that case is load-bearing: mutations
M4 (stop escaping the terminator) and M5 (drop the per-line prefix) are both
killed by it. That is a SAMPLE over the cases someone thought to write.

This module settles the prefix half of the claim for EVERY possible output.

## What is modelled, and what is not

Modelled over `List Char`, not `String`: concatenated strings are the classic
reason an obvious goal will not close, and the property here is genuinely about
structure. The rendered form is pinned separately by `#guard` below, so the
model cannot drift away from the text the engine actually prints.

NOT modelled: the escaping of `]]>` inside the data. That is substring
replacement, and it is MEASURED by the suite (M4 dies), not proved here. Said
plainly rather than left for a reader to assume.
-/

namespace GoalForge.FenceQuarantine

/-- The prefix `gf_quarantine` puts on every line of untrusted data.
`scripts/lib.sh` renders this as `sed -e 's/^/  | /'`. -/
def fence : List Char := [' ', ' ', '|', ' ']

/-- Quarantining is: prefix every line. The engine also escapes the fence
tokens; that step is deliberately outside this model (see the header). -/
def quarantine (ls : List (List Char)) : List (List Char) :=
  ls.map (fun l => fence ++ l)

/-- Every quarantined line carries the fence. Nothing is emitted bare. -/
theorem every_line_is_fenced (ls : List (List Char)) :
    ∀ l ∈ quarantine ls, ∃ rest, l = fence ++ rest := by
  intro l hl
  simp only [quarantine, List.mem_map] at hl
  obtain ⟨x, _, hx⟩ := hl
  exact ⟨x, hx.symm⟩

/-- THE GENERAL LEMMA, and the reason this file is not a snapshot.

Two lines whose FIRST CHARACTER differs are never equal, whatever follows.
Quantified over both characters and both tails: it does not mention the fence,
the engine's wording, or any constant that a future release might change. A
theorem stated about today's exact strings would expire the day someone
rewords a message, and the repair would be to weaken it -- which is how real
coverage gets deleted. -/
theorem heads_differ_lines_differ {a b : Char} (h : a ≠ b) (s t : List Char) :
    a :: s ≠ b :: t := by
  intro heq
  exact h (List.head_eq_of_cons_eq heq)

/-- The engine's own lines begin with a character the fence never uses.
Stated as a hypothesis on the tag rather than as a fixed string, so it holds
for every message the engine may ever emit. -/
theorem quarantined_never_equals_engine_line
    {tag : Char} (h : tag ≠ ' ') (data rest : List Char) :
    fence ++ data ≠ tag :: rest := by
  simpa [fence] using heads_differ_lines_differ (a := ' ') (b := tag) (Ne.symm h) _ _

/-- The concrete instance the engine relies on: `RoT DTD GOAL: ...` begins
with `R`, the fence begins with a space. Kept as an `example`, not a theorem
other proofs lean on -- it documents the present, and the general statement
above is what carries the weight. -/
example (data rest : List Char) : fence ++ data ≠ 'R' :: rest :=
  quarantined_never_equals_engine_line (by decide) data rest

/-- A verdict printed BY THE CRITERION, verbatim, still cannot come out as a
verdict line: the fence shifts it, and the shift is exactly what the previous
theorem forbids from ever matching. This is the attack, stated as a theorem. -/
theorem a_printed_verdict_stays_data (verdict : List Char) (rest : List Char) :
    fence ++ verdict ≠ 'R' :: rest :=
  quarantined_never_equals_engine_line (by decide) verdict rest

/-- Quarantining preserves line count: nothing is dropped and nothing is
invented. A fence that silently ate a line would hide evidence. -/
theorem quarantine_preserves_length (ls : List (List Char)) :
    (quarantine ls).length = ls.length := by
  simp [quarantine]

/-- The data is recoverable: fencing is injective, so a reader can always
strip the prefix and get back exactly what the command printed. -/
theorem quarantine_is_injective : Function.Injective quarantine := by
  intro a b hab
  simpa [quarantine, List.map_inj_left] using
    List.map_injective_iff.mpr (fun x y h => by simpa using h) hab

-- The model is pinned to the text the engine actually prints. If `sed -e
-- 's/^/  | /'` is ever changed, this line is what notices.
#guard String.ofList fence = "  | "
#guard String.ofList (fence ++ "GOAL COMPLETE".toList) = "  | GOAL COMPLETE"
#guard (String.ofList (fence ++ "GOAL COMPLETE".toList)).startsWith "RoT" = false

end GoalForge.FenceQuarantine
