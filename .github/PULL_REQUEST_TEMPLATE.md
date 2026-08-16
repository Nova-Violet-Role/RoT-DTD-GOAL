<!-- Delete any section that genuinely does not apply, and say why it does not. -->

## What this changes, and what question it answers

<!-- One paragraph. This project's changelog is organised by the adversarial
     question each change answers — "can a check pass while the thing it checks
     is broken?" — so state yours. -->

## The evidence

```
bash tests/run_tests.sh; echo "exit=$?"
```

<!-- Paste the tail and the exit code, read DIRECTLY and not through a pipe. -->

## Checklist

- [ ] The suite exits **0** on my machine, and I read the exit code directly.
- [ ] Behavioural change ships with a test **that I have watched fail** — I
      broke the code on purpose and saw the assertion fire.
- [ ] If the test carries a negative control, it asserts the mutation is
      **present in the file** before running, so "did not apply" cannot be
      mistaken for "survived".
- [ ] New test case is registered in the `ALL` list (closing quote on its own
      line).
- [ ] No new carriage returns: `git ls-files -z | xargs -0 grep -lI $'\r'`
      prints nothing.
- [ ] New scripts are executable **in the git index**:
      `git ls-files -s scripts/ | grep -v '^100755'` prints nothing.
- [ ] Record layout changes are declared in both halves of
      `hooks/trust_contract.dtd`, and `goal.sh schema --verify` and
      `goal.sh contract --verify` both exit 0.
- [ ] Any refusal message I added carries a **next step** (LAW.17).
- [ ] Docs regenerated if the tree changed: `bash scripts/attest.sh --write-docs`.
- [ ] I did not edit a check's expected value merely to make it pass; any
      changed expectation is justified from first principles in this PR.

## What I could not verify

<!-- Say it plainly. "I have no macOS machine; CI covers it" is a fine answer
     and a far better one than silence. An honest gap is a result; a fabricated
     green is not. -->
