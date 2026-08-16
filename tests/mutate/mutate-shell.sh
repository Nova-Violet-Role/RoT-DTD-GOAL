#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL.
#
# SHELL MUTATION HARNESS -- the re-runnable form of EVIDENCE/mutation-shell.log.
#
# The log that shipped with 1.0.0 recorded ten mutations and the case that
# killed each one. It was true when it was written and there was no way for
# anyone -- including its author -- to run it again. A mutation campaign you
# cannot re-run is a claim, not a measurement: it decays silently the moment
# the code it attacked moves, and the reader has no instrument to notice.
#
# This is the same shape as lean/mutate/mutate-lean.sh, aimed at the shell:
# break the engine on purpose, run the suite, and require the suite to NOTICE.
# A mutation nothing catches is a hole in the tests, and it is reported as one.
#
#   bash tests/mutate/mutate-shell.sh            # the campaign
#   GF_MUTATE_SELFTEST=1 bash tests/mutate/mutate-shell.sh   # prove the alarm works
#
# EXIT CODES -- distinct on purpose, because "nothing failed" has four very
# different meanings and folding them together is how a harness lies:
#   0  every mutation was applied, verified present, and KILLED by the suite
#   1  at least one mutation SURVIVED -- the suite has a blind spot
#   2  a mutation could not be applied, or the tree did not restore  (DISCARDED)
#   3  preflight failed -- NOT RUN, and no conclusion may be drawn
#
# THE RULE THAT MAKES THE RESULT MEAN ANYTHING: the needle is counted in the
# file BEFORE the edit (must be exactly 1) and AFTER it (must be 0). A patch
# that silently failed to apply produces a green suite and reads exactly like
# a robust code path. It is DISCARDED, never counted as survived.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUITE="$ROOT/tests/run_tests.sh"
WORK="${TMPDIR:-/tmp}/gf-mutate-shell.$$"
LOG="${GF_MUTATE_LOG:-$ROOT/tests/mutate/mutation-shell.log}"

# Plain strings, not arrays: bash 3.2 (stock macOS) errors on the expansion of
# an EMPTY array under `set -u`, and the empty case is the one this harness is
# supposed to report as success.
killed=0; survived=0; discarded=0; total=0
SURVIVORS=""

say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------------------
# preflight -- exit 3 means NOT RUN. A harness that reports "all killed"
# because it never found the files it was supposed to break is worse than one
# that refuses to start.
# ---------------------------------------------------------------------------
preflight() {
  local missing=0 f
  for f in "$SUITE" "$ROOT/scripts/lib.sh" "$ROOT/scripts/stop_gate.sh" "$ROOT/scripts/goal.sh"; do
    [ -f "$f" ] || { say "PREFLIGHT: missing $f"; missing=1; }
  done
  command -v awk  >/dev/null 2>&1 || { say "PREFLIGHT: awk not found";  missing=1; }
  command -v grep >/dev/null 2>&1 || { say "PREFLIGHT: grep not found"; missing=1; }
  [ "$missing" -eq 0 ] || return 1
  return 0
}

# Count LITERAL occurrences of a needle. Not a regex: several needles here
# contain [ ] * $ \ and | , and a regex read of them would either miss or
# over-match. awk index() is the only honest counter for this.
# MEASURED DEFECT, first campaign run: this passed the needle with `awk -v`,
# and awk PROCESSES ESCAPE SEQUENCES inside a -v value. The needle
#     | sed -e 's/\]\]>/]]\&gt;/g' \
# arrived at awk as `]]>` and `&gt;` -- it no longer matched the file, so a
# real mutation was recorded as DISCARDED. awk even warned about it
# ("escape sequence `\]' treated as plain `]'") and the warning went to
# stderr while the harness read stdout. ENVIRON is not escape-processed.
count_needle() { # file needle -> integer on stdout
  GF_NEEDLE="$2" awk '
    BEGIN { needle = ENVIRON["GF_NEEDLE"] }
    { line = $0; n = 0
      while ((p = index(line, needle)) > 0) { n++; line = substr(line, p + length(needle)) }
      total += n }
    END { print total + 0 }
  ' "$1"
}

# Replace the FIRST literal occurrence. Literal on both sides -- a needle with
# a backslash in it is exactly what broke the first version of this file.
apply_needle() { # file needle replacement
  local tmp="$WORK/apply.$$"
  GF_NEEDLE="$2" GF_REPL="$3" awk '
    BEGIN { needle = ENVIRON["GF_NEEDLE"]; repl = ENVIRON["GF_REPL"] }
    done_flag == 0 {
      p = index($0, needle)
      if (p > 0) {
        $0 = substr($0, 1, p - 1) repl substr($0, p + length(needle))
        done_flag = 1
      }
    }
    { print }
  ' "$1" > "$tmp" && cat "$tmp" > "$1" && rm -f "$tmp"
}

digest() { # file -> a stable digest, whatever hash tool this machine has
  if   command -v sha256sum >/dev/null 2>&1; then sha256sum   < "$1" | cut -d' ' -f1
  elif command -v shasum    >/dev/null 2>&1; then shasum -a 256 < "$1" | cut -d' ' -f1
  elif command -v openssl   >/dev/null 2>&1; then openssl dgst -sha256 < "$1" | awk '{print $NF}'
  else wc -c < "$1" | tr -d ' '    # last resort: size. Weak, and it says so.
  fi
}

# Run the suite and report WHICH CASES failed. Attribution comes from the run,
# not from a declared expectation -- a hand-written "killed by X" is a guess,
# and this campaign exists because a guess was all the old log had.
#   stdout: the failing case names, space separated ("" if the suite is green)
#   return: 0 if the suite passed, 1 if it failed
run_suite() { # outfile -> writes full output there
  local out="$1" rc named
  # The per-case watchdog defaults to 900s. Under a mutation a case can hang,
  # and one 15-minute wait per mutant makes a 10-mutation campaign unrunnable
  # -- measured: the first run took over an hour and had to be abandoned. 120s
  # is ~30x the whole suite's green runtime, so it cannot cut off honest work.
  ( cd "$ROOT" && GF_CASE_TIMEOUT="${GF_CASE_TIMEOUT:-120}" bash "$SUITE" ) > "$out" 2>&1
  rc=$?
  # Attribution, primary source: the suite's own summary line. The earlier
  # version scanned "[n/57] test_x" headers and FAIL lines, and reported
  # "<no case attributed>" for six of nine mutants -- a harness that knows
  # something broke but not what is only half an instrument.
  named="$(sed -n 's/^failing tests: //p' "$out" | tr '\n' ' ')"
  if [ -z "$named" ]; then
    named="$(awk '
      /^\[[0-9]+\/[0-9]+\] test_/ { case_name = $2 }
      /^ *FAIL / { if (case_name != "" && !(case_name in seen)) { seen[case_name]; printf "%s ", case_name } }
    ' "$out")"
  fi
  printf '%s' "$named"
  return $rc
}

# ---------------------------------------------------------------------------
# THE MUTATIONS -- five-line records, terminated by a line containing only --
#
#   1 id
#   2 what it breaks, in one line
#   3 file, relative to the repo root
#   4 needle   (literal, must occur EXACTLY once)
#   5 replacement (literal)
#
# A |-delimited table was tried first and is impossible here: the needles
# contain | and || and [ ] and \ . Line-oriented records have no separator to
# collide with, which is the whole reason for the shape.
# ---------------------------------------------------------------------------
mutations() {
cat <<'RECORDS'
M1
flaky detector: the generation filter is inverted, so rows from a retired seal come back
scripts/lib.sh
      if (rowg != -1 && rowg < g) next
      if (rowg != -1 && rowg > g) next
--
M2
flaky detector: a fail after a pass is counted but never marked as a regression
scripts/lib.sh
    $5 == "fail" || $5 == "timeout"     { f[$2]++ ; if ($2 in seenPass) regressed[$2] = 1 }
    $5 == "fail" || $5 == "timeout"     { f[$2]++ }
--
M3
seal generation is always reported as 0, so every historical row looks current
scripts/lib.sh
  printf '%s' "$g" | grep -Eq '^[0-9]+$' || g=0
  g=0
--
M4
the untrusted fence stops escaping its own terminator, so output can close the frame
scripts/lib.sh
    | sed -e 's/\]\]>/]]\&gt;/g' \
    | sed -e 's/GF_NEVER_MATCHES_THIS/x/g' \
--
M5
fenced output loses its per-line prefix, so a printed line looks like engine text
scripts/lib.sh
          -e 's/^/  | /'
          -e 's/^//'
--
M6
the queue stops checking dependencies: everything pending is eligible at once
scripts/lib.sh
  depst="$(gf_queue_status "$dep")"
  depst=done
--
M7
the gate completes even when criteria are failing
scripts/stop_gate.sh
if [ "$fail" -eq 0 ]; then
if [ "$fail" -ge 0 ]; then
--
M8
the flaky gate's default flips from strict back to off
scripts/stop_gate.sh
fpolicy="$(state_get GATE_FLAKY)"; fpolicy="${fpolicy:-strict}"
fpolicy="$(state_get GATE_FLAKY)"; fpolicy="${fpolicy:-off}"
--
M9
the completion red team stops running, so a check that passes in an empty dir completes
scripts/stop_gate.sh
    weak="$(gf_redteam_all | grep ' WEAK ' || true)"
    weak=""
--
M10
the ledger hash is never compared, so an edited criterion is never detected as drift
scripts/lib.sh
gf_ledger_hash() { # id -> sealed hash ("" if unsealed)
gf_ledger_hash() { echo ""; } ; gf_ledger_hash_unused() { # id -> sealed hash ("" if unsealed)
--
RECORDS
}

# The self-test mutation: reword a COMMENT. It changes nothing the engine does,
# so the suite must stay green and this harness must report SURVIVED and exit 1.
# An alarm nobody has deliberately tripped is an untested alarm.
selftest_mutation() {
cat <<'RECORDS'
S1
SELF-TEST: rewords a comment. The suite MUST stay green -- this proves the harness can say SURVIVED.
scripts/lib.sh
# JSON-escape stdin into a single JSON string body (no surrounding quotes).
# JSON-escape stdin into one JSON string body, no surrounding quotes at all.
--
RECORDS
}

# ---------------------------------------------------------------------------
main() {
  preflight || { say "RESULT: NOT RUN (preflight failed)"; exit 3; }
  mkdir -p "$WORK" || { say "RESULT: NOT RUN (cannot create $WORK)"; exit 3; }

  local mode="campaign"
  [ "${GF_MUTATE_SELFTEST:-0}" = "1" ] && mode="selftest"

  say "SHELL MUTATION CAMPAIGN -- RoT DTD GOAL"
  say "date: $(date '+%Y-%m-%d %H:%M:%S')"
  say "mode: $mode"
  say "rule: the needle is counted BEFORE (must be 1) and AFTER (must be 0)."
  say "      A patch that did not apply is DISCARDED, never reported as survived."
  say ""

  # baseline -- if the suite is already red, nothing after this means anything
  local base_out="$WORK/baseline.log" base_fail
  base_fail="$(run_suite "$base_out")"; local base_rc=$?
  if [ "$base_rc" -ne 0 ]; then
    say "BASELINE RED -- suite exits $base_rc before any mutation. Cases: $base_fail"
    say "RESULT: NOT RUN (no usable baseline)"
    rm -rf "$WORK"; exit 3
  fi
  say "baseline: suite green (exit 0)"
  say ""

  local id what rel file needle repl before after pristine mut_out failing rc dig_before dig_after

  while IFS= read -r id && IFS= read -r what && IFS= read -r rel \
     && IFS= read -r needle && IFS= read -r repl && IFS= read -r _sep; do
    # GF_MUTATE_ONLY=M8 runs one mutant. A full campaign is ~40 minutes here
    # because several cases hang under a broken gate and wait out the watchdog,
    # and re-running all ten to re-check one fix is how a survivor stops being
    # re-checked at all.
    if [ -n "${GF_MUTATE_ONLY:-}" ] && [ "$GF_MUTATE_ONLY" != "$id" ]; then
      continue
    fi
    total=$((total + 1))
    file="$ROOT/$rel"
    pristine="$WORK/pristine.$id"
    cp "$file" "$pristine"
    dig_before="$(digest "$file")"

    before="$(count_needle "$file" "$needle")"
    if [ "$before" -ne 1 ]; then
      say "$id DISCARDED  needle occurs $before times in $rel (expected exactly 1)"
      say "    $what"
      discarded=$((discarded + 1))
      continue
    fi

    apply_needle "$file" "$needle" "$repl"
    after="$(count_needle "$file" "$needle")"
    if [ "$after" -ne 0 ]; then
      say "$id DISCARDED  patch did not land ($after occurrences remain)"
      cat "$pristine" > "$file"
      discarded=$((discarded + 1))
      continue
    fi

    mut_out="$WORK/$id.log"
    failing="$(run_suite "$mut_out")"; rc=$?

    if [ "$rc" -ne 0 ]; then
      killed=$((killed + 1))
      say "$id KILLED     by ${failing:-<suite failed with no case attributed>}"
    else
      survived=$((survived + 1))
      SURVIVORS="$SURVIVORS $id"
      say "$id SURVIVED   the whole suite stayed green with this defect in place"
    fi
    say "    $what"

    cat "$pristine" > "$file"
    dig_after="$(digest "$file")"
    if [ "$dig_before" != "$dig_after" ]; then
      say "$id NOT RESTORED -- $rel differs after restore. STOPPING."
      rm -rf "$WORK"; exit 2
    fi
    rm -f "$pristine"
  done < <(if [ "$mode" = selftest ]; then selftest_mutation; else mutations; fi)

  say ""
  say "applied and verified present: $((killed + survived))"
  say "KILLED:    $killed"
  say "SURVIVED:  $survived$SURVIVORS"
  say "DISCARDED: $discarded  (patch did not apply -- NOT counted as survived)"
  say "total records: $total"

  # final baseline: the tree must be back where it started
  local final_fail final_rc
  final_fail="$(run_suite "$WORK/final.log")"; final_rc=$?
  if [ "$final_rc" -ne 0 ]; then
    say "TREE NOT RESTORED -- suite is red after the campaign. Cases: $final_fail"
    rm -rf "$WORK"; exit 2
  fi
  say "TREE RESTORED -- suite green again (exit 0)"

  if [ "$discarded" -gt 0 ] || [ "$survived" -gt 0 ]; then
    # Keep every per-mutant suite log. The first run reported six mutants as
    # "no case attributed" and the evidence had already been deleted, which
    # made the finding unusable until the whole campaign was re-run.
    say "per-mutant logs kept in: $WORK"
    [ "$discarded" -gt 0 ] && exit 2
    exit 1
  fi
  rm -rf "$WORK"
  exit 0
}

main "$@" 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
