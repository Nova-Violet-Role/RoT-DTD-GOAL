#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# Context injection. Modes:
#   session -> SessionStart: full resume awareness after restart/clear
#   prompt  -> UserPromptSubmit: one-line status pin on every prompt
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

MODE="${1:-prompt}"
ST="$(gf_status || true)"

emit() { # eventname text
  printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
    "$1" "$(printf '%s' "$2" | gf_json_escape)"
}

counts="$(crit_counts 2>/dev/null || echo '0 0')"
passed="${counts% *}"; total="${counts#* }"

if [ "$MODE" = "prompt" ]; then
  [ "$ST" = "active" ] || exit 0
  emit "UserPromptSubmit" "[RoT DTD GOAL active] $passed/$total criteria passed, iteration $(state_get ITERATION)/$(state_get MAX_ITERATIONS). Goal: $(state_get GOAL | head -c 160)"
  exit 0
fi

# session mode
case "$ST" in active|paused|awaiting_human) ;; *) exit 0 ;; esac
failing="$(gf_failed_ids | tr '\n' ' ')"
ctx="RoT DTD GOAL: a persisted goal exists for this project.
  Goal: $(state_get GOAL)
  Status: $ST | $passed/$total criteria passed | iteration $(state_get ITERATION)/$(state_get MAX_ITERATIONS)"
[ -n "$failing" ] && ctx="$ctx
  Currently failing: $failing"
if ! drift="$(gf_ledger_audit)"; then
  ctx="$ctx
  INTEGRITY DRIFT since the last seal: $(printf '%s' "$drift" | tr '\n' ' ')
  The gate will refuse completion until a human re-seals (goal.sh seal --reason) or aborts."
fi
[ -s "$GF_DIR/snapshot.md" ] && ctx="$ctx
  A pre-compaction snapshot exists at .claude/goal/snapshot.md (goal, per-criterion
  state, and the head of every failing output). Read it before re-deriving anything."
case "$ST" in
  awaiting_human) ctx="$ctx
  It escalated for human review (budget/stall). Ask the user how to proceed before resuming." ;;
  paused) ctx="$ctx
  It is paused; do not work on it unless the user runs /goal-resume." ;;
  *) ctx="$ctx
  Continue from current state; never redo work for criteria that already pass." ;;
esac
emit "SessionStart" "$ctx"
exit 0
