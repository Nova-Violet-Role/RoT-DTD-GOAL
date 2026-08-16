---
description: Attack the goal's own acceptance criteria — ledger integrity, negative control, and mutation probe (does not consume an iteration)
---

```bash
G="${CLAUDE_PLUGIN_ROOT}/scripts/goal.sh"
bash "$G" audit    ; echo "audit exit=$?"
bash "$G" redteam  ; echo "redteam exit=$?"
bash "$G" mutate   ; echo "mutate exit=$?"
```

Three different questions, in increasing strength:

1. **audit** — do the criteria still hash to what was sealed at activation?
   Drift means someone edited a check after the goal started; the Stop gate
   will refuse completion until a human re-seals with a stated reason.
2. **redteam** — does any criterion still pass inside an *empty directory*?
   Such a check never measured this project at all.
3. **mutate** — does each criterion FAIL when the files it declares in
   `--deps` are damaged in a sandbox copy? Three structural operators run by
   default (`delete`, `truncate`, `corrupt`); `--ops all` adds the three
   semantic ones (`constflip`, `negate`, `hunk`). The score is reported per
   criterion: `n/n` is `KILLED`, anything less is `SURVIVED` with the surviving
   operators named. Read the survivors as a diagnosis:
   - survived `corrupt` → the check notices the file vanishing but never reads
     what is inside it. Fix: grep for content, not for existence.
   - survived `constflip` → it does not care what the constants *are*. Fix:
     assert the value, not the key.
   - survived `negate` → it does not care which way the decision goes.
   - survived `hunk` → it only looks at the head or tail of the file.

   `SKIPPED` means the criterion declared no deps, and is never a pass.

If the goal is important enough to enforce this rather than merely report it:

```bash
bash "$G" set GATE_MUTATE strict   # a surviving mutant now refuses completion
```

Report the verdicts verbatim. For anything weak or surviving, propose a
stronger check and apply it with:

```bash
bash "$G" sharpen <ID> "<desc>" '<stronger verify>' --reason "<why>"
```

Sharpening is refused on a criterion that already passed, refused if the
replacement could not fail, and budgeted — say so plainly if the budget is
spent rather than working around it.
