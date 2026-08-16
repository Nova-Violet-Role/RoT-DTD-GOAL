# Contributing to RoT DTD GOAL

The shortest useful contribution to this project is **a way to break it**.

This is a plugin whose entire claim is that it refuses to let a session end on
an unverified goal. If you can make it say *complete* when it should not, that
bug report is worth more than a feature.

---

## The one rule that is not negotiable

**No claim without a green run.** Not "this should work". Not "the change is
obviously safe". You ran the suite, it exited 0 → say it passes. Non-zero →
say it fails and paste the real output.

```bash
bash tests/run_tests.sh; echo "exit=$?"
```

Read that exit code **directly**. Never through a pipe:

```bash
bash tests/run_tests.sh | tail -5     # WRONG: $? is tail's status, not the suite's
bash tests/run_tests.sh | tee /tmp/run.log; echo "exit=${PIPESTATUS[0]}"   # right
```

The repository has a CI job (`pipefail-control`) whose only purpose is to prove
that this mistake would be caught. It exists because it was nearly made.

A pull request is merged when CI is green on **ubuntu, macOS and Windows**, and
`green` counts a *skipped* job as a failure.

---

## What a good pull request contains

### 1. A test that can fail

Every behavioural change ships with a case in `tests/run_tests.sh`. The bar is
not "the test passes" — a test that cannot fail proves nothing. The bar is:

* the assertion **fires** when the behaviour is wrong, and
* you have **seen it fire**, by breaking the code on purpose.

That second half is the whole discipline. Several cases in this suite carry an
explicit *negative control* — they plant the defect, assert the needle is
present in the file, run the check, and require it to fail. Copy that pattern:

```bash
# assert the mutation actually landed before you trust the result
needles=$(grep -c 'the_broken_thing' "$fixture")
[ "$needles" -eq 1 ] || { echo "control did not apply"; return 1; }
```

A mutation that silently failed to apply looks exactly like a robust code path.
It is not the same thing, and a harness that cannot tell them apart is lying in
the reassuring direction.

### 2. Registration

If you add a case, add its name to the `ALL` list. Note the formatting quirk
that has bitten this file once already: **the closing quote goes on its own
line**, or the last entry silently never matches and the case never runs.

### 3. The declaration, if you touched a record

Every file the engine writes is declared twice in `hooks/trust_contract.dtd` —
as numbered append-only fields *and* as a DTD sequence content model. If you add
a column, add it in both places, with a `@since` no lower than the field before
it, then:

```bash
bash scripts/goal.sh schema --verify;   echo "exit=$?"
bash scripts/goal.sh contract --verify; echo "exit=$?"
```

Records are **append-only** (LAW.15). Renaming or reordering an existing field
is a breaking change and will be refused by `schema --verify`, on purpose.

### 4. Line endings and the exec bit

`.gitattributes` normalises everything to LF. Before you push:

```bash
git ls-files -z | xargs -0 grep -lI $'\r' && echo "CR FOUND"   # expect no output
```

New scripts need the exec bit **in the git index**, which is the only place that
answers honestly — MINGW reports every file as `755` regardless:

```bash
git update-index --chmod=+x scripts/your_script.sh
git ls-files -s scripts/ | grep -v '^100755' && echo "NOT EXECUTABLE"
```

### 5. A regenerated attestation, if you changed the tree

```bash
bash scripts/attest.sh --write-docs      # refreshes the fact blocks in the docs
bash scripts/attest.sh --verify ATTESTATION.txt; echo "exit=$?"
```

---

## What a good issue contains

Best case, in order:

1. **A reproduction** — the exact `goal` invocation, the criteria, and what the
   gate did instead of what it should have done.
2. **The platform**: `uname -a`, `bash --version`, and whether GNU coreutils are
   present. Half of the portability bugs this project has fixed were "it works
   on the author's machine" in disguise.
3. **The relevant log**: `.claude/goal/journal.jsonl` and the gate's own output.
   Redact anything private first — those files contain your commands.

If you are reporting that a **claim in the README is false**, say which claim
and paste the measurement that contradicts it. That is the most valuable issue
this repository can receive, and it will be treated as a defect in the README
rather than an inconvenience.

---

## What will get a change rejected

* **A blocking pattern with no way forward.** LAW.17: every refusal the engine
  emits must carry a task or a remedy. A message that says "cannot continue" and
  stops is the failure mode this project exists to avoid, and there is a test
  that reads every outbound message and enforces it.
* **`sorry` or `native_decide`** in the Lean sources under `EVIDENCE/lean/`.
  The first is an admission, the second trusts the compiler binary instead of
  the kernel.
* **A theorem or test whose name promises more than it checks.** A statement
  weaker than its title launders an assumption into an apparent guarantee.
* **A spec edited to match the code.** If a check fails, fix the code or justify
  the new expected value from first principles. Quietly changing the expectation
  to whatever makes it green destroys the only thing the check was for.
* **A snapshot where a property belongs.** `assert "version is 1.0.0"` expires
  the day it is bumped. `assert "CHANGELOG has an entry for the shipped
  version"` does not. Prefer the second; a spec that forbids a correct future
  is a defect, not a safeguard.

---

## Development layout

| path | what it is |
|------|------------|
| `scripts/` | the engine — `lib.sh` is shared, `goal.sh` is the CLI, `stop_gate.sh` is the gate |
| `hooks/` | `hooks.json` (31 wired events), the trust contract DTD, the invariant map |
| `tests/run_tests.sh` | the suite; every case is a function, registered in `ALL` |
| `tests/experiments/` | the bench and the flaky-policy harness |
| `agents/`, `commands/` | the sub-agent and slash-command surface |
| `EVIDENCE/` | committed logs, the dogfood transcript, the Lean sources |
| `docs/REVIEW.md` | the standing review packet: what is *not* claimed |

Run a single case while iterating:

```bash
bash tests/run_tests.sh test_the_gate_refuses_a_failing_criterion; echo "exit=$?"
```

---

## Licence

By contributing you agree that your contribution is licensed under the same
terms as the project — see [`LICENSE`](../LICENSE).
