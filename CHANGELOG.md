# Changelog

All notable changes to **RoT DTD GOAL** (formerly `goal-forge`).

Version numbers restarted at `1.0.0` for publication. The engine's development
line ran `v2 → v3.6`; **the v3.6 development line is what shipped as 1.0.0**, so
a comment in the source that says "closed in v3.6" and a tag that says `v1.0.0`
describe the same code. That mapping lives here, on purpose: the reviewer's
point was that an artefact should carry the version it *is*, and the lineage
should be somewhere a stranger can look it up.

Each entry names the **question** the release answers, because that is how this
project has always been built — one adversarial question at a time, each raised
by a review that tried to break the previous answer.

---

## [4.0.0] — 2026-08-16

*The question: **who gates the gate?***

The 3.0.0 bench campaign put the engine under strict gates on real work and
then audited the auditor. Fourteen findings came back
([`docs/FINDINGS-4.0.0.md`](docs/FINDINGS-4.0.0.md) keeps each with its
closure); this release fixes every code-caused one, and none of the fixes
buys correctness with engine speed — the one probe that got smarter spends
its extra copies only on survivors.

**The lead finding, and LAW.18.** Claude Code kills a hook at its timeout and
treats the death as ALLOW. Bench 2 measured it: a completion pipeline needing
~7 minutes was killed at 300s and the session ended with **no verdict at
all**. The gate now watches its own clock (`GF_GATE_BUDGET`, default 540s
under the shipped hook timeout of 600s) and blocks with `VERIFICATION
INCOMPLETE` and the next step instead of dying silently — a slow gate costs
an iteration, never a verdict. New law, new invariant row, new enforcing case
with an in-budget control.

* **The tamper guard no longer denies reads.** Seven bench denials, every one
  a read-only `cat`/`ls`/`find`/`status` whose `2>/dev/null` or `2>&1`
  matched the bare `>` rule. Read-posture redirects are scrubbed before the
  test; a real redirect beside them still denies.
* **The mutation probe re-probes survivors one dependency at a time.**
  Symmetric damage commutes through comparison-shaped checks (truncate
  empties both sides of a diff; an emptied bash tool exits 0) — every bench-2
  criterion read "blind to truncate" while being sound. Isolation kills what
  symmetry spares, and the report names the isolating dependency. The journal
  line now counts what it counts: `criteria_with_survivors=`.
* **Queued goals grew deps and keep their gates.** CRIT rows take an optional
  fourth field of deps globs, and `queue advance` carries
  `GATE_REDTEAM`/`GATE_FLAKY`/`GATE_MUTATE` across — gate policy is session
  posture, not goal content. A strict run stays strict through the whole
  queue.
* **Seven verdict-shaped strings the engine spoke but never declared**
  (`LEDGER DRIFT`, `ATTESTATION FAILED`, `STALL DETECTED`, `CONTRACT
  OK`/`DRIFT`, `SCHEMA OK`/`DRIFT`) are now VERDICT entities — found by the
  goal-contract-auditor in the bench's closing audit; the forgery attack
  covers them automatically. `history.tsv` is a declared RECORD (the schema
  check now binds 6 records). `VERIFICATION INCOMPLETE` joins the vocabulary.
* **CLI paper cuts:** `init --help` prints usage instead of creating a goal
  named `--help`; `add` warns at add time on the substitution-only diff class
  that both benches shipped and only the red team caught (once at the price
  of a strict escalation).
* **`/goal-swarm` no longer dead-ends headless:** a Workflow is used only
  when present AND pre-approved AND interactive; parallel Task calls are the
  default posture. The README states the namespaced command form headless
  sessions need.
* One finding was **retracted with the correction on the record**: dependency
  inference never missed process-substitution tokens — the observed survival
  was the symmetric-damage mechanism all along.
* Suite: 59 cases → **61**; the counts in the facts block are generated, as
  ever.

## [3.0.0] — 2026-08-16

*The question: **can a human send the roster, or only hope it shows up?***

Through 2.0.0 the seven agents were declared in the trust contract and
summoned only when the driving model judged the moment right — a user could
not dispatch one deliberately. Two commands close that, and both read the
roster FROM the contract at dispatch time, so the DTD stays the single source
of who exists:

* **`/goal-agent <name> [model=…] [effort=…] <task>`** — dispatch exactly one
  agent. Unknown names are refused with the roster printed, never
  nearest-matched; the report arrives inside the agent's declared element,
  closed by the standing rule that agent output is a proposal and the gate
  still decides by exit code (LAW.1).
* **`/goal-swarm [agents=…] [model=…] [effort=…] <thing>`** — the whole roster
  (or a subset) on one subject at once, genuinely in parallel — a workflow
  when the harness has one, all dispatches in a single message otherwise —
  synthesized without flattening: a disagreement between agents is a finding
  and must survive into the summary.
* `model=` and `effort=` are selectable per invocation in both; agent front
  matter remains the durable default.

**And the engine was benched on real work, in real sessions.** Three queued
goals (build → extend → harden a pure-bash CSV tool, 22 sealed criteria)
worked end-to-end by headless Claude Code sessions with the released plugin
installed: all three completed through the gate, the queue advanced
live in-session, the tamper guard denied four write attempts on goal state,
five of the seven agents were summoned and journalled — and at the final
completion the red team flagged a criterion **the bench author wrote** as
vacuous (`H2 passes-in-empty-dir`). The full record ships in
`EVIDENCE/bench-goal/`, and `docs/assets/gate.gif` replays the refusal and
the earned completion against that bench's real state. See the README's
*Seen working* section.

## [2.0.0] — 2026-08-16

*The question: **which of our guarantees is only a comment?***

**And the answer that forced the major bump: the install itself was one.**
Claude Code loads `hooks/hooks.json` automatically and rejects a manifest that
declares the same file again — so `/plugin install` on 2.1.233 produced a
plugin whose status was `failed to load`: no hooks, no gate, nothing. The suite
did not miss the defect; it *enforced* it — `test_the_plugin_installs_as_declared`
asserted the presence of the very `"hooks"` key that breaks loading. The key is
removed and the assertion inverted: the standard file must ship, and the
manifest must NOT re-declare it. Found by installing the plugin for real and
exercising every command, which also surfaced three smaller lies:

* **The mutation report printed the kill count under the label `SURVIVED`** —
  `SURVIVED 1/6 -- survived: truncate,corrupt,constflip,negate,hunk` showed
  five survivors labelled as one. The number is now the survivor count, the
  same thing the list beside it names. Verdict logic unchanged.
* **The docs told the reader to verify `EVIDENCE/ATTESTATION.txt`**; the file
  ships at the repository root, so the documented command exited 2 for every
  reader who tried it.
* **`lint_workflows.sh` assumed the Go `yq`.** On a machine with the Python
  jq-wrapper of the same name, `eval` is read as the filter and the parse
  "fails" on YAML that is fine. The flavor is now probed and each gets its own
  invocation.

The public version 2.0.0 deliberately does not collide with the internal `v2`
development line — the mapping between public numbers and the dev line is this
file's job, stated at the top. The suite guard that forbade the number is
replaced by a shape check plus the existing binding of every shipped version to
a CHANGELOG entry.

Answered by making the shell mutation campaign re-runnable and then running it.
The 1.0.0 evidence log listed ten mutations and their killers **by hand** — a
claim nobody could re-check, and two of its attributions turned out to be
guesses. `tests/mutate/mutate-shell.sh` now applies the same ten to the real
tree, counts the needle before (must be 1) and after (must be 0), reads the
killer from the suite's own output, and restores the tree.

It found one. **M8 — the flaky gate's default flipping from `strict` to `off` —
survived the entire suite**, the only survivor of ten.

The default was not decoration; the *test coverage* was. `goal.sh init` always
writes `GATE_FLAKY=strict`, so `stop_gate.sh`'s `${fpolicy:-strict}` fallback is
unreachable for any goal this version creates. It is reachable for exactly one
thing, and it is the one that matters: **a state file written by an older
version, before the key existed.** On upgrade, that goal would have lost its
flake gate in silence — green suite, no alarm, completions decided by a coin
flip. Closed by `test_the_flaky_default_survives_an_upgrade`, which deletes the
key, asserts the deletion *landed*, and requires the refusal anyway. Re-running
M8 alone against it: **KILLED**.

* **`tests/lint_workflows.sh` + a `workflow-lint` CI job** — seven checks over
  `.github/workflows/`, run *before* the matrix: tabs, CR bytes, unpinned
  `uses:`, jobs without `runs-on`, verdict-bearing pipes, a real YAML parse, and
  **every repo-relative path named in a workflow must exist** — the defect that
  cost a red release run. Five controls prove each check can fail.
* **The release job no longer verifies through a pipe.** `run_tests.sh | tail -5`
  reported `tail`'s status; it now captures the exit code directly and refuses to
  publish on non-zero. The artefact about to be published must not be verified
  correctly only because of a default declared 200 lines away.
* **`lean/Proofs/FenceQuarantine.lean`** — the untrusted-output fence, proved
  rather than sampled. `quarantined_never_equals_engine_line` holds for **every**
  output a criterion can emit, not the strings someone thought to test.
  Mutation **L9** kills it. The `]]>` escaping remains **MEASURED** (shell M4),
  not proved — stated in the module header, because the honest half of a
  specification is what it does *not* cover.
**And M8 was not special — it was a class.** The campaign was extended to the
gate's two sibling fallbacks, and **both survived too**:

| mutation | fallback | flipped to | first run |
|---|---|---|---|
| M8 | `GATE_FLAKY` `${fpolicy:-strict}` | `:-off` | SURVIVED |
| M11 | `GATE_REDTEAM` `${policy:-warn}` | `:-off` | SURVIVED |
| M12 | `LAST_PASSED` `${last_passed:-0}` | `:-999` | SURVIVED |

Every key `goal.sh init` writes has a gate-side default that no goal created by
this version can reach, and none of the three was tested. Under M11 a completion
whose criteria also pass in an empty directory stops saying so; under M12 real
progress never registers, so a goal that is advancing escalates as stalled. The
case is now named for the class — `test_gate_defaults_survive_an_upgrade`, one
legacy state, every default exercised. **All three: KILLED.**

* **macOS caught a defect in the new lint controls, and caught it honestly.**
  They used `sed -i 's|…|…|'`; BSD sed reads the script as the backup *suffix*,
  edits nothing, and exits noisily — so the fixture stayed intact. The control
  reported **DISCARDED, not survived**, which is exactly the distinction that
  check exists to make. Both call sites moved to `sed … > f.t && mv f.t f`, and
  `gf_scan_sed_i` now refuses a bare `sed -i` anywhere in a shipped script, with
  controls proving it fires on the bare form and stays quiet on `-i.bak`.
* Lean: 4 modules → **5**, 65 theorems → **73**, mutations 8/8 → **9/9 killed**.
* Suite: 58 cases / 677 assertions → **59 / 694**.

## [1.0.0] — 2026-08-16

**The first public release.** Two questions, answered in one version because
nothing before this was ever published: *how many goals, and who may speak?*
— and then, after the fourth review, *is it true on a machine the author does
not own?*

The fourth review ran the suite on Linux and macOS. The engine held; the
*repository* did not. None of the repository work below changes a decision the
engine makes — it changes whether a stranger can reach the engine at all.

### Fixed — the fourth review's blockers
- **`test_every_law_is_enforced` crashed on Linux and macOS.** It read `$TMP`,
  a MINGW-only variable; with `set -u` the case died. Now `${TMPDIR:-/tmp}`,
  which every other line in the suite already used. The harness behaved
  correctly throughout — it reported a CRASH, never a pass — which is the only
  reason this was a one-line fix instead of a false green.
- **`attest.sh` could not verify on stock macOS.** It called `sha256sum`
  directly while `lib.sh` already fell back to `shasum`. An attestation only
  the author's platform can check is an attestation of nothing. Now falls back
  `sha256sum → shasum -a 256 → openssl dgst`, and the digest is unchanged on
  platforms that have GNU coreutils.
- **The environment block cried wolf on macOS.** It printed
  `tool.sha256sum=MISSING` and `tool.timeout=MISSING` on a platform that is
  fully supported, teaching a reader to ignore the block. It now reports
  *which* implementation was found (`hash.tool=`, `watchdog=`).

### Added
- **`.gitattributes` with `* text=auto eol=lf`.** Every archive this project
  ever shipped measured **zero** carriage returns — re-measured across
  v3.3.0, v3.4.0, v3.5.0 and 1.0.0 — and the reviewer still received 77 CRLF
  lines in 7 files. The tree was clean; the *transit* was not. This is the
  layer that governs transit.
- **`test_portable_to_a_stranger_machine`** — the class, not the instance:
  Windows-only environment variables, carriage returns in any shipped file,
  GNU-only tools used without a fallback in the same file, the repository
  files a stranger's tooling expects, and the exec bit (read from the git
  index, because MINGW reports every file as `755` and cannot answer honestly).
  Both scanners have negative controls that run the *same functions* the real
  check runs.
- **`.github/workflows/ci.yml`** — the suite on `ubuntu-latest` and
  `macos-latest` on every push, with the run tail uploaded as an artefact, so
  green stops being a memory of one machine. Includes a control job proving
  the `| tee` in the suite step does **not** swallow a failure.
- **`.gitignore`** — starting with `.claude/goal/`, the live per-session state
  that once swept into a release archive.
- **`tests/experiments/bench.sh`** — what the engine costs per stop, measured.
  Its first draft was wrong in the flattering direction (it reused one goal
  across samples, so four of five samples timed the dormant hook and reported
  a gate cycle as 115 ms next to a single sweep of 1546 ms). The fixture is now
  rebuilt per sample, and the contradiction that exposed it is a self-check
  that fails the run.
- `ATTESTATION.txt` now ships **in the repository**, not only in a release
  archive, so `attest.sh --verify` works on a fresh `git clone`.

### Added — the declaration layer earns its name

The three markup shapes were being used as *instruments*; now they are the
engine's grammar, and each is machine-checked.

- **A record schema in Protobuf's discipline** (`goal.sh schema --verify`).
  Every file the engine writes is declared twice: numbered append-only fields
  (`1=id:PCDATA@v2 … 5=seal_gen:PCDATA@1.0.0`) **and** an ordinary DTD sequence
  content model (`<!ELEMENT ledger (id, hash, sealed_epoch, sealed_iso,
  seal_gen)>`). The two are cross-checked, so a typo in either is caught by the
  other. Enforced: dense numbering, `since` never decreasing with field number
  (which *is* append-only), narrow legacy rows tolerated and named, a row wider
  than the declaration refused. This closes the defect class that bit this
  project three times.
- **`<!ATTLIST gate>` binds the gate policies to the code.** The declared
  default is checked against the default `cmd_init` writes — a README saying
  "default warn" over code writing "off" now fails the build.
- **`<!NOTATION>` declares every unparsed channel** — verify output, hook
  payloads, queue specs, the journal — and marks which are untrusted, so a
  third rendering site added later cannot skip the fence. The verify command
  *text* is declared `trusted-by-provenance`: a soft edge the fourth review
  named, now written into the contract instead of a review note.
- **Four new agents** (`goal-redteam`, `goal-forensic`, `goal-queue-architect`,
  `goal-contract-auditor`), and all seven are declared in the contract with the
  element they may speak in and the one thing they may never do. Checked both
  directions; every agent must declare a model, a tool boundary and a
  prohibition. The planner shipped without a tool boundary until the assertion
  was written.
- **The gate speaks in all three shapes at a refusal**: a `<!DOCTYPE
  gf-session [ … ]>` declaration of the governing laws, a `<gf:instruction>`
  carrying the task, and the command output fenced as data. The law text is
  *read from the contract* — proved by planting a sentinel law in a copy of the
  DTD and asserting it appears in the gate's output and nowhere in the script.
- **`LAW.17: a refusal always carries a task`** — enforced by
  `test_a_refusal_always_carries_a_way_forward`, which reads every outbound
  message the gate can emit and fails on any that offers no next step. This is
  the built-in loop's failure mode written down as something that can fail.
- **`test_the_plugin_installs_as_declared`** — the marketplace manifest, the
  hook targets, every shipped script parsing under `bash -n`, and the evidence
  being present and non-empty.

### Fixed — what CI found, and no local run could

Six defects, none of which this machine could see. This is the entry that
justifies the CI job existing. Two of them were *capabilities the engine
claimed and did not have on macOS* — restored rather than downgraded to a
skipped test.

- **The acceptance suite had no per-case watchdog on macOS at all.** Stock
  macOS ships neither `timeout` nor `gtimeout`, and `run_isolated` fell back to
  running each case unguarded *while the header still printed
  `per-case watchdog: 900s`*. A hanging case did not fail; it hung the run, and
  the case that exists to prove a hang cannot freeze the suite failed after
  120 seconds having demonstrated the opposite. There is now a portable
  watchdog (detached watcher, marker file, normalised to exit 124 so a timeout
  is never reported as an anonymous crash), and `GF_FORCE_PORTABLE_WATCHDOG=1`
  exercises that path **on every platform** — because a fallback that can only
  run where nobody is watching is how this defect survived in the first place.
- **The event rate limiter silently degraded on every macOS machine.** It used
  `date -d`, which is GNU coreutils; macOS has neither that nor `gdate`, so the
  limiter took its "no date arithmetic" branch and journalled 3 records where
  1 is declared. BSD `date -j -f` does the same job, so `gf_iso_to_epoch` now
  tries both and the capability is restored. The degraded path is still
  reachable, still journals *more* rather than less, and is still tested via
  `GF_NO_DATE_D=1`.

- **The gate did not parse on macOS at all.** Stock macOS ships bash 3.2.57,
  and bash 3.2 does not suspend quote parsing inside a comment that sits inside
  a command substitution. One possessive apostrophe in a comment inside
  `stop_gate.sh` swallowed the remaining lines of the file; `bash -n` reported
  `unexpected EOF` pointing 33 lines *below* the real cause, and every gate
  assertion in the suite failed at once. Fixed, and the class is now scanned
  tree-wide by `gf_scan_bash32` with the real macOS parser as the CI oracle.
- **The CI's own CRLF check was broken, in the reassuring-looking direction.**
  It used `grep -lU $'\r'`, which on the Windows runner matched the **empty
  string** and so reported all 33 text files as CRLF — while a byte scan of the
  same checkout found zero `0x0d`. The tree was clean; the checker was wrong.
  It now uses two independent instruments (a byte scan and `git ls-files
  --eol`) and **proves on planted files that each can fire before trusting
  either**. A broken instrument exits 2; a dirty tree exits 1. Those are
  different findings and no longer share an exit code.
- **12 generated `.codemap/` artefacts were committed and pushed**, CRLF and
  all, despite being listed in `.gitignore`. The reason is worth writing down:
  `git check-ignore` **skips files that are in the index** unless `--no-index`
  is passed, so the obvious way to ask "is anything ignored also tracked?"
  answers *no* precisely when the answer is *yes*. Now asserted with
  `--no-index`, as a property that names no directory.

### Added — the mutation suite ships, runnable

- **`lean/` moved to the repository root and gained the suite that attacks it.**
  `lean/Proofs/` holds the four modules, `lean/mutate/mutate-lean.sh` is the
  eight-mutation harness, and `lean/README.md` says what each module proves and
  **which theorems each mutation killed**. Previously the modules lived under
  `EVIDENCE/` and the mutation record was a log with no way to re-run it — that
  is a claim, not an instrument.
- The harness reports **per-theorem attribution** (the declaration enclosing
  each error Lean reported, not the line that was edited), counts the needle
  before patching, deletes the stale `.olean` before each rebuild, restores the
  tree and verifies the restored files hash identically.
- Its exit codes separate findings that are usually conflated: `0` all killed,
  `1` something **survived**, `2` a mutation was **discarded** or the tree was
  not restored — a defect in the harness, not the proofs — and `3` **not run**,
  because no Lean workspace is not a pass.
- **The harness has its own negative control**: `GF_MUTATE_SELFTEST=1` rewords a
  doc comment, which must SURVIVE and exit 1. Measured, it does. A mutation
  runner that has never reported a survivor would print "8/8 killed" just as
  cheerfully if it had silently stopped building anything.
- Re-run for this release: **8 applied, 8 killed, 0 survived, 0 discarded**,
  baseline green before and after.

### Fixed — a fourth thing CI found

- **`contract --verify` was off the air on macOS, silently, while exiting 0.**
  `gf_contract_policies` used `\(a\|b\)` alternation in a `sed` BRE — a GNU
  extension that BSD sed does not implement and simply does not match. No
  policy was extracted, so policy drift could not be detected and the check's
  own negative control could not fail. Rewritten in POSIX awk; it was the only
  such construct in the tree, and `test_portable_to_a_stranger_machine` now
  scans for the class with a planted control.
- The scanner for that class needed **two greps**, because a single BRE cannot
  say "contains `sed` and contains a literal backslash-pipe" without the
  backslash-pipe being read as alternation — whose empty branch matches every
  line of every file. Its first version flagged `set -u`. That is the third
  empty-match defect in this release, all of the same shape.

### Changed
- Version labels in shipped artefacts say `1.0.0`; the `v2 → v3.6` lineage is mapped below.
- **`REVIEW.md` moved to `docs/`; `AMPLIFY.md` removed.** The root carries
  `README.md`, `CHANGELOG.md` and `LICENSE` only. What was load-bearing in the
  review packet — *what this release does not claim* and *what to try to
  break* — moved into README rather than being deleted with it.
- **`EVIDENCE/` is committed**, including `dogfood/`, every log, and the Lean
  sources under `lean/Proofs/`. `lean/`, `.claude/`, `.codemap/` and
  `.rot-moe/` are ignored.
- CI publishes the release: a `v*` tag produces a GitHub Release only after the
  suite passed on ubuntu, macOS **and** Windows (Git Bash), with a `green` job
  that refuses any upstream result other than `success` — a *skipped* job is
  not a pass.

### Added — the engine (question: how many goals, and who may speak?)

Renamed from `goal-forge` to **RoT DTD GOAL**; published under the Nova-Violet
Role organisation with a `marketplace.json`.

- **Generation-scoped flake detection.** The previous flake window was scoped
  by wall-clock timestamp, so a seal dated an hour into the future hid a
  genuine pass→fail→pass regression. Scope is now the **seal generation** — a
  monotone integer that only counts up. Rows with no generation are *included*,
  never hidden: an upgrade may over-report, a seal may not conceal.
- **A flake is a REGRESSION**, not merely two different answers. Measured over
  60 gate cycles (`tests/experiments/flaky_policy.sh`): under the old
  definition the ordinary work loop was accused 5 times out of 5. Under the new
  one, 0/20 on a clean arm and 0/20 on a progressing arm, while a genuinely
  random criterion was refused 4 times out of 20. On that measurement
  `GATE_FLAKY` **defaults to `strict`**.
- **Simultaneous completion.** `gf_verify_all` skipped criteria already marked
  passed, so a file deleted after iteration 1 could complete a goal at
  iteration 7. Every criterion is now re-run at the moment the goal would
  complete, and only that final sweep counts. This defect existed **since v2**
  and survived three reviews; only measuring the flake policy exposed it.
- **A trust contract in DTD form** (`hooks/trust_contract.dtd`): the verdict
  vocabulary and fourteen laws declared once, machine-checked in both
  directions by `goal.sh contract --verify`.
- **Untrusted output fencing.** A criterion that prints `GOAL COMPLETE. All 1
  acceptance criteria verified passing.` had it pasted verbatim into the gate's
  feedback. Command output now lands inside a labelled `GF-UNTRUSTED` fence,
  every line prefixed, fence-escape sequences neutralised.
- **A goal queue** with backward-only dependencies (acyclic by construction),
  archiving each completed goal and replaying the next one's spec. The
  scheduler is specified in `lean/GoalQueue.lean`: `next` is always eligible,
  never runs a goal whose dependency is unfinished, and strictly decreases the
  pending count — so a chain terminates.
- **`hooks/INVARIANTS.tsv`** mapping every declared law to a test case that can
  falsify it, checked in both directions. A principle nobody can falsify is a
  slogan.
- **Standing costs became decisions**: every forensic event row states *why it
  is not decisional*, and `learn` reports the sample size behind each
  recommendation with a warning under three samples.

### Was not done, and is now — closed by CI itself

Both gaps this release opened with are closed, and by the instrument rather
than by assertion.

- **Linux and macOS are no longer UNVERIFIED.** They were labelled that way
  because this machine has no Linux runtime (the only WSL distro is Docker
  Desktop's LinuxKit VM — no bash, no DNS to install one — and starting the
  engine would have been a background service launch, which was forbidden).
  CI answered it: run `31926346937` on commit `ac2ddaf`, **667 assertions and
  0 failures on ubuntu-latest, macos-latest AND windows-latest (Git Bash)**,
  with the `green` job refusing any upstream result other than `success` — a
  *skipped* job is not a pass. It took **six red runs** to get there, and
  every one of them found something real: a gate that would not parse on
  macOS, a CRLF checker matching the empty string, build artefacts committed
  past `.gitignore`, a policy check silently off the air on BSD sed, and a
  path destroyed by a blanket rename. None of those was visible from here.
  That is the entire argument for the job existing.
- **The mutation campaign was re-run, and now ships as a runnable suite.**
  `lean/mutate/mutate-lean.sh`: **8 applied, 8 killed, 0 survived, 0
  discarded**, with per-theorem attribution and its own negative control. See
  `lean/README.md`.

### Still not done, and why
- **The shell mutation campaign (`EVIDENCE/mutation-shell.log`) was not
  re-run** and has no runnable harness yet — only the Lean one does. Its ten
  results stand from the engine work; the repository fixes in this release are
  covered instead by the **21 applied-and-verified controls** inside the test
  cases — counted from the run, not from memory, each one a check that plants
  a defect and requires the assertion to fail. Stated as a gap rather than
  folded into the green.
- **CI does not verify the Lean modules**, on purpose, and claims nothing about
  them. See the header of `.github/workflows/ci.yml`.

---

## v2 → v3.6 (development line, unpublished)

The questions, in order, each raised by a review of the previous answer:

| line | question answered |
|------|-------------------|
| v2   | who decides a goal is done? (the gate, by re-running criteria — not the model) |
| v3.0 | who checks the checks? (a red team that refuses a criterion which also passes in an empty directory) |
| v3.1 | can a check pass while the thing it checks is broken? (a six-operator mutation probe) |
| v3.2 | what survives a compaction? (snapshot ring, criteria sharpening) |
| v3.3 | what does a hostile shell do to a verifier? (per-case watchdog, detached stdin, learned timeouts) |
| v3.4 | when is a pass not evidence? (seal-scoped flake detection, ledger integrity) |
| v3.5 | what is the gate's word worth outside this room? (attestation, forensic surfacing) |
| v3.6 | how many goals, and who may speak? (queue, trust contract, fencing) → **released as 1.0.0** |
