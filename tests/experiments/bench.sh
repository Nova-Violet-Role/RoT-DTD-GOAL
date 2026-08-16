#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
#
# BENCH: what does this engine cost, per stop?
#
# Every number in the README's bench table comes from running this file. It is
# shipped so the table can be re-measured rather than believed -- the same rule
# the rest of the project lives by.
#
# HOW TO READ IT, and why the first row exists.
#
# The engine is a set of hooks. A hook's cost is dominated by process startup,
# not by anything this project wrote, so the first row measures a BARE BASH
# SPAWN on the machine doing the measuring. Every other row should be read as a
# multiple of that baseline; an absolute millisecond count from someone else's
# laptop tells you nothing about yours.
#
# The criteria used here are deliberately trivial (`true`, `test -f`). That
# isolates the ENGINE's overhead. In real use the verify commands dominate
# completely: a gate cycle costs the engine's overhead plus your test suite,
# and your test suite is not a few milliseconds.
#
#   usage: bash tests/experiments/bench.sh [output-file]
#          R=9 bash tests/experiments/bench.sh      # repetitions, default 5
set -u
R="${R:-5}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$ROOT/scripts"
OUT="${1:-/tmp/rot-dtd-goal-bench.log}"

now_ms() { date +%s%3N; }

# median of the samples in $SAMPLES (space separated), integer ms
median() {
  printf '%s\n' $1 | sort -n | awk '{ a[NR] = $1 } END { print (NR % 2) ? a[(NR+1)/2] : int((a[NR/2] + a[NR/2+1]) / 2) }'
}

bench() { # label  command-to-time (run R times, reported as median)
  local label="$1"; shift
  local i s e samples=""
  for i in $(seq 1 "$R"); do
    s=$(now_ms); "$@" > /dev/null 2>&1; e=$(now_ms)
    samples="$samples $((e - s))"
  done
  LAST_MS="$(median "$samples")"
  printf '%-46s %6s ms   (median of %s)\n' "$label" "$LAST_MS" "$R"
}

# A GATE CYCLE NEEDS A FRESH GOAL PER SAMPLE, and this is not a detail.
#
# The first draft of this file timed the gate R times against one goal. The
# first call completed the goal; every call after it hit the gate's own
# "no active goal -> exit immediately" guard and returned in a few
# milliseconds. The median then reported the DORMANT path as if it were a full
# gate cycle: 115 ms next to a single verify sweep measured at 1707 ms in the
# row below it -- arithmetically impossible, and it would have been published
# as a flattering number if the two rows had not contradicted each other.
#
# So the fixture is rebuilt, untimed, before every sample.
bench_fresh() { # label  setup-fn  n_criteria  [failing]
  local label="$1" setup="$2" n="$3" failing="${4:-}"
  local i s e samples=""
  for i in $(seq 1 "$R"); do
    "$setup" "$n" "$failing"
    s=$(now_ms); gate > /dev/null 2>&1; e=$(now_ms)
    samples="$samples $((e - s))"
    drop_goal
  done
  LAST_MS="$(median "$samples")"
  printf '%-46s %6s ms   (median of %s)\n' "$label" "$LAST_MS" "$R"
}

# ---- fixtures --------------------------------------------------------------
make_goal() { # n_criteria [failing]
  D="$(mktemp -d)"; export CLAUDE_PROJECT_DIR="$D"
  ( cd "$D" && printf 'x\n' > FILE )
  bash "$S/goal.sh" init "bench" --budget 99 --stall 99 > /dev/null
  local i
  for i in $(seq 1 "$1"); do
    bash "$S/goal.sh" add "C$i" "criterion $i" 'test -f FILE' --deps FILE > /dev/null
  done
  [ "${2:-}" = "failing" ] && bash "$S/goal.sh" add "CX" "the failing one" 'test -f ABSENT' > /dev/null
  bash "$S/goal.sh" activate > /dev/null
}
drop_goal() { rm -rf "$D"; unset CLAUDE_PROJECT_DIR; }

gate() { echo '{}' | bash "$S/stop_gate.sh"; }
spawn() { bash -c 'exit 0'; }

{
  echo "RoT DTD GOAL -- bench"
  echo "build: $(bash "$S/goal.sh" version 2>/dev/null | head -1)"
  echo "date:  $(date '+%Y-%m-%d %H:%M:%S')"
  echo "host:  $(uname -s) $(uname -m)   bash $BASH_VERSION"
  echo "reps:  $R per row, median reported"
  echo
  echo "BASELINE -- read every row below as a multiple of this"
  bench "bare bash process spawn (does nothing)" spawn
  echo

  echo "THE HOOK THAT RUNS WHEN YOU HAVE NO GOAL"
  D="$(mktemp -d)"; export CLAUDE_PROJECT_DIR="$D"
  bench "Stop hook, no goal exists (exits immediately)" gate
  rm -rf "$D"; unset CLAUDE_PROJECT_DIR
  echo

  echo "A GATE CYCLE -- trivial criteria, so this is ENGINE overhead only"
  echo "(fresh goal built untimed before EVERY sample -- see bench_fresh)"
  for n in 1 5 10; do
    bench_fresh "completing gate, $n criteria (2 sweeps + red team)" make_goal "$n"
    [ "$n" = 5 ] && GATE5="$LAST_MS"
  done
  bench_fresh "blocking gate, 5 pass + 1 fail (1 sweep, no red team)" make_goal 5 failing
  echo

  echo "THE PARTS, MEASURED SEPARATELY"
  make_goal 5
  bench "verify all 5 criteria once (gf_verify_all)" bash -c ". $S/lib.sh; gf_verify_all"
  VERIFY5="$LAST_MS"
  bench "red team, 5 criteria (empty-directory re-run)" bash -c ". $S/lib.sh; gf_redteam_all"
  bench "flake scan (gf_flaky_ids)" bash -c ". $S/lib.sh; gf_flaky_ids"
  bench "ledger audit, 5 criteria" bash "$S/goal.sh" audit
  drop_goal
  make_goal 1
  bench "mutation probe, 1 criterion, all six operators" bash "$S/goal.sh" mutate
  drop_goal
  echo

  echo "THE QUEUE"
  D="$(mktemp -d)"; export CLAUDE_PROJECT_DIR="$D"
  ( cd "$D" && printf 'x\n' > FILE && mkdir -p specs \
    && printf 'GOAL\tqueued\t--budget 9\nCRIT\tD1\td\ttest -f FILE\n' > specs/q.tsv )
  bash "$S/goal.sh" init "bench queue" --budget 9 > /dev/null
  bash "$S/goal.sh" add C1 "c" 'test -f FILE' > /dev/null
  bash "$S/goal.sh" activate > /dev/null
  bash "$S/goal.sh" queue add q "$D/specs/q.tsv" > /dev/null
  bench "queue advance (archive + init + add + activate)" bash "$S/goal.sh" queue advance
  rm -rf "$D"; unset CLAUDE_PROJECT_DIR
  echo

  echo "THE INSTRUMENTS A REVIEWER RUNS"
  bench "attestation --facts" bash "$S/attest.sh" --facts
  bench "trust contract --verify" bash "$S/goal.sh" contract --verify
  echo
  echo "SELF-CHECK -- an alarm that has fired for real"
  echo "A completing gate verifies EVERY criterion twice and then red-teams"
  echo "them, so it cannot cost less than one sweep. When this bench was first"
  echo "written it did, because the fixture was reused across samples and four"
  echo "of five samples measured the dormant hook. That bug is now an assertion:"
  if [ "${GATE5:-0}" -ge "${VERIFY5:-0}" ]; then
    echo "  CONSISTENT   completing gate ${GATE5} ms >= one sweep ${VERIFY5} ms"
  else
    echo "  INCONSISTENT completing gate ${GATE5} ms < one sweep ${VERIFY5} ms"
    echo "  The bench is measuring the wrong thing. Do not publish these numbers."
    BENCH_BAD=1
  fi
  echo
  echo "NOT MEASURED HERE: your verify commands. In real use they dominate"
  echo "everything above -- the engine's own overhead is a rounding error next"
  echo "to a test suite, and that is the intended trade."
} | tee "$OUT"

# The block above runs in a pipeline, so its variables die with the subshell.
# The verdict is therefore read back off the file: an inconsistent bench must
# FAIL, not print a warning nobody reads.
if grep -q 'INCONSISTENT' "$OUT"; then
  echo "BENCH FAILED -- self-check tripped, numbers not publishable" >&2
  exit 1
fi
echo "BENCH OK -- $OUT"
exit 0
