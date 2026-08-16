# EVIDENCE

Everything in this directory is a **run**, not a claim. It is committed on
purpose: a plugin that asks to be trusted with your Stop hook owes you the
material it was judged on — including the parts that went badly.

Nothing here is required to *use* the plugin. It is here so you do not have to
take the README's word for anything.

| file | what it is | what it proves — and what it does not |
|---|---|---|
| `differential.log` | the acceptance suite run against the **previous** release tree | Six differentials exit **1** on v3.5.0 and **0** here, with the failure counts (16 / 16 / 14 / 31 / 4 / 4). A test that passes on the old code as well tests nothing; these are the ones that do not. The log also labels the **non-differential** cases honestly — v2's five outcomes exit 0 on both trees. |
| `mutation-shell.log` | ten deliberate defects injected into the engine's own scripts | **10/10 killed.** Each needle was counted in the file *before* building, so "did not apply" can never be recorded as "survived". M9 initially SURVIVED — that is in the log — which exposed a weak fixture that was then strengthened. |
| `mutation-lean.log` | eight deliberate defects injected into the Lean modules | **8/8 killed**, with one run discarded and redone because a needle matched 257 places. A theorem no mutation kills is decorative; these are not. |
| `flaky-policy-experiment.log` | 60 gate cycles across three arms | The measurement that changed a default. The old flake definition accused an ordinary work loop **5 times out of 5**; the new one accuses it **0/20**, while a genuinely random criterion is refused **4/20**. `GATE_FLAKY=strict` became the default *because of this file*, not despite it. |
| `lean-instruments.log` | `lake build` + `#print axioms` + `leanchecker` over all four modules | Exit 0 each, zero bytes from the kernel re-check, and the negative control (a module with no oleans) exiting 1 — which is the only reason the green counts. No `sorry`, no `native_decide`. |
| `bench.log` | what the engine costs per stop, measured | Median over repetitions, with a bare process spawn as the baseline. Its first draft was **wrong in the flattering direction**; the self-check that caught it now fails the run. See `tests/experiments/bench.sh`. |
| `suite-tail.log` | the tail of a full local suite run | One machine, one platform. Deliberately the *weakest* item here — CI runs the same suite on ubuntu, macOS and Windows on every push, and those tails are attached to the workflow run. |
| `dogfood/` | the engine's own journal, ledger, timings and queue from a real session | It was used to ship itself: goals queued with dependencies, criteria sealed, a red-team warning raised against a real criterion. The ledger's fifth column is the seal generation the flake scope depends on. |
| `lean/` | the four Lean 4 sources | Published so the transcript above can be re-run rather than believed. They import Mathlib; see docs/REVIEW.md for the exact commands. **CI does not verify them and does not claim to.** |

## What this evidence does not cover

- **No Linux or macOS suite tail produced by the author.** There is no Linux
  runtime on the author's machine. CI produces those on every push; until a run
  exists, treat those platforms as verified by CI alone.
- **The attestation is not a signature.** It binds a *tree*, not an author.
- **`GATE_MUTATE` is off by default** — the mutation probe is opt-in, because
  it damages a working copy of your files to prove a check can fail.
- **A fail→pass transition is not flagged as flaky.** It is indistinguishable
  from work that got finished. Stated, not hidden.
