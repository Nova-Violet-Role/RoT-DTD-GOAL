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

### Changed
- Version labels in shipped artefacts say `1.0.0`; the `v2 → v3.6` lineage is mapped below.
- **`REVIEW.md` moved to `docs/`; `AMPLIFY.md` removed.** The root carries
  `README.md`, `CHANGELOG.md` and `LICENSE` only. What was load-bearing in the
  review packet — *what this release does not claim* and *what to try to
  break* — moved into README rather than being deleted with it.
- **`EVIDENCE/` is committed**, including `dogfood/`, every log, and the Lean
  sources under `EVIDENCE/lean/`. `lean/`, `.claude/`, `.codemap/` and
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

### Not done, and why
- **No Linux or macOS suite tail from the author's machine.** There is no
  Linux runtime reachable here: the only WSL distro is Docker Desktop's
  LinuxKit VM (no bash, no DNS to install one) and the Docker engine is not
  running. Starting it would be a background service launch, which the
  operator forbade. CI produces those tails on push; until a CI run exists,
  **Linux and macOS are UNVERIFIED by the author's own hardware** and are
  labelled that way rather than assumed.
- **The mutation suite was not re-run for the repository work.** The
  `EVIDENCE/mutation-*.log` files come from the engine's own mutation
  campaign; the repository fixes above are covered instead by the nine
  applied-and-verified controls inside the new test cases.

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
