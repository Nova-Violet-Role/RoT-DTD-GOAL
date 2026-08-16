#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
#
# EXPERIMENT: should GATE_FLAKY default to strict?
#
# v3.4 shipped flake detection with the default `warn` and the reason "we have
# not measured the false-alarm rate". Three reviews later that was still true,
# which makes it a guess wearing a default's clothing. This script produces the
# number, and it is runnable by anyone: `bash tests/experiments/flaky_policy.sh`.
#
# THREE ARMS, N goals each:
#   clean     the criterion passes on the first try             -> expect no refusal
#   progress  the criterion fails, the work is done, it passes  -> the question
#   coinflip  the criterion passes, then fails, unchanged       -> expect a refusal
#
# The `progress` arm is the whole experiment. It is the ordinary loop: the gate
# says a criterion is failing, the work gets done, the criterion passes. If that
# is reported as a coin flip, then `strict` refuses to complete every goal that
# did not pass first time -- which is most of them -- and the policy is unusable
# no matter how good the detector is.
set -u
N="${N:-10}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
S="$ROOT/scripts"
OUT="${1:-/tmp/gf-flaky-experiment.log}"

run_goal() { # arm -> prints REFUSED or COMPLETED
  local arm="$1" d out
  d="$(mktemp -d)"
  export CLAUDE_PROJECT_DIR="$d"
  ( cd "$d" && printf 'seed\n' > SEED )
  case "$arm" in
    clean)
      ( cd "$d" && printf 'done\n' > WORK )
      bash "$S/goal.sh" init "clean goal" --budget 6 --stall 4 > /dev/null
      bash "$S/goal.sh" add C1 "the work exists" 'test -f WORK' > /dev/null ;;
    progress)
      bash "$S/goal.sh" init "progress goal" --budget 6 --stall 4 > /dev/null
      bash "$S/goal.sh" add C1 "the work exists" 'test -f WORK' > /dev/null ;;
    coinflip)
      # A genuinely random criterion -- the thing the detector exists for. Note
      # what this arm can and cannot show: a check that flips and heals while
      # nobody is running it is invisible to any detector, so the honest test is
      # a check that is random EVERY TIME IT RUNS. The confirmation sweep gives
      # at least two observations on the completing iteration, which is what
      # gives the alarm a chance to see a pass and a fail together.
      ( cd "$d" && printf 'done\n' > WORK )
      bash "$S/goal.sh" init "coinflip goal" --budget 6 --stall 4 > /dev/null
      bash "$S/goal.sh" add C1 "a genuinely random check" 'test $(( RANDOM % 2 )) -eq 0' > /dev/null
      bash "$S/goal.sh" add C2 "the work exists" 'test -f WORK' > /dev/null ;;
  esac
  bash "$S/goal.sh" activate > /dev/null
  bash "$S/goal.sh" set GATE_FLAKY strict > /dev/null
  case "$arm" in
    clean)
      out="$(echo '{}' | bash "$S/stop_gate.sh" 2>&1)" ;;
    progress)
      # iteration 1: the work is not done yet, so the criterion fails
      echo '{}' | bash "$S/stop_gate.sh" > /dev/null 2>&1
      # the agent does the work -- this is the normal loop, not a flake
      ( cd "$d" && printf 'done\n' > WORK )
      out="$(echo '{}' | bash "$S/stop_gate.sh" 2>&1)" ;;
    coinflip)
      # run the loop as the agent would: stop, get told, stop again, until the
      # gate either completes or refuses
      out=""
      for _ in 1 2 3 4 5 6; do
        out="$(echo '{}' | bash "$S/stop_gate.sh" 2>&1)"
        case "$out" in
          *"GOAL COMPLETE"*|*"COMPLETION REFUSED"*|*"ESCALATE"*) break ;;
        esac
      done ;;
  esac
  case "$out" in
    *"COMPLETION REFUSED (flaky, strict)"*) echo REFUSED ;;
    *"GOAL COMPLETE"*)                      echo COMPLETED ;;
    *)                                      echo OTHER ;;
  esac
  rm -rf "$d"
}

{
  echo "GATE_FLAKY policy experiment"
  echo "build under test: $(bash "$S/goal.sh" version 2>/dev/null | head -1)"
  echo "date: $(date '+%Y-%m-%d %H:%M:%S')   N per arm: $N"
  echo
  for arm in clean progress coinflip; do
    refused=0; completed=0; other=0
    for _ in $(seq 1 "$N"); do
      case "$(run_goal "$arm")" in
        REFUSED)   refused=$((refused + 1)) ;;
        COMPLETED) completed=$((completed + 1)) ;;
        *)         other=$((other + 1)) ;;
      esac
    done
    printf '%-9s refused=%-3s completed=%-3s other=%-3s\n' "$arm" "$refused" "$completed" "$other"
  done
  echo
  echo "reading: refusals in 'clean' or 'progress' are FALSE ALARMS."
  echo "         completions in 'coinflip' are MISSES."
} | tee "$OUT"
