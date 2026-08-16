<!--
    This file is part of RoT DTD GOAL.
    SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
    Copyright 2026 Saimonokuma.
-->

# How this calculator was built — by the plugin it ships beside

trinum was not written and then verified; it was **driven** into existence by
`/rot-dtd-goal:goal`, the way any user's project can be. This file is the
record of that build, and every number in it comes from the journal shipped
at [`EVIDENCE/extra/build-journal.log`](../../EVIDENCE/extra/build-journal.log).

## The goal, as sealed

One sentence — *build trinum per SPEC.md: a Rust calculator engine + Slint UI
across Greek, Egyptian and Roman numerals* — became **ten sealed criteria**:
the workspace build, four `cargo test` families (roman, greek, egyptian,
mixed-system eval), three CLI answers checked byte-for-byte (`XIV + VI` in
Roman is `XX`, `X * X` in Greek is `ρ`, `V + V` in Egyptian is `𓎆`), the
error path (`XIIII` must be refused **by name**), and `cargo check` on the
Slint UI. Each criterion was hashed into the integrity ledger
([`EVIDENCE/extra/build-ledger`](../../EVIDENCE/extra/build-ledger)) before
any code existed. The Slint criterion was sealed only after a probe proved
Slint compiles in the build environment — a criterion the environment cannot
satisfy is a wall, not a check.

## The build, as the journal tells it

- **The planner went first.** `goal-planner` was summoned on SPEC.md before
  a line of Rust was written — `SubagentStart` at 18:31:16 in the journal.
- **The gate refused the empty start.** At 18:31:25: `BLOCK iter=1/10
  fail=10` — a stop attempt with nothing built got back all ten failures and
  the instruction to fix only what is listed.
- **The engine grew test-first**: 42 engine tests across the three numeral
  systems and the evaluator, then the CLI, then the Slint window — a thin
  shell over an engine that holds all logic.
- **At all-green the roster attacked it.** `goal-redteam` re-ran the sealed
  criteria against an empty directory: `REDTEAM manual weak=0` — every
  criterion genuinely measures this project. `goal-contract-auditor` closed
  the session with a records audit.
- **Completion was earned, not announced.** `COMPLETE all 10 criteria
  passed` at 18:47:58 — and per the engine's law, every criterion was re-run
  at that exact moment. The gate let the session end only then.

## Verify it yourself

```sh
cargo build --locked --workspace
cargo test  --locked -p trinum-engine        # 42 tests
echo "MCMXCIV + VI" | ./target/debug/trinum --out roman      # MM
echo "͵α - I"       | ./target/debug/trinum --out egyptian   # 999, in glyphs
echo "XIIII"        | ./target/debug/trinum --out roman      # refused, by name
```

The three-OS claim is measured, not promised: the **plugin-extra-gift**
workflow (`.github/workflows/ci2.yml`) builds this workspace and runs these
exact checks on ubuntu, macOS and Windows — deliberately separate from the
plugin's own CI, so a gift can never redden the gate.
