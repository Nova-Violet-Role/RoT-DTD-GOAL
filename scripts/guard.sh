#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# PreToolUse tamper guard (matcher: Write|Edit|MultiEdit|NotebookEdit|Bash).
#
# The completion-promise weakness of loop plugins is that the model can
# "declare" success. RoT DTD GOAL closes the equivalent hole: while a goal is
# live, no tool call may WRITE to this project's goal state (e.g. editing
# criteria.d/* to say status=passed, or rewriting a verify command to `true`).
#
# v3 changes two things, and both matter:
#   1. PRECISION -- v2 denied any tool call whose payload merely contained the
#      string ".claude/goal". That blocked read-only inspection (`cat`,
#      `grep`) and, worse, blocked work on *other* projects' goal state. v3
#      denies writes to THIS project's live state dir and lets reads through.
#   2. HONESTY -- a heuristic over a command string is not a security
#      boundary and never was. The real backstop is the integrity ledger:
#      stop_gate.sh re-hashes every criterion before verifying, so a criterion
#      mutated by any route the guard did not anticipate is still caught, and
#      still cannot complete a goal. Guard = friction, ledger = arithmetic.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

case "$(gf_status || true)" in
  active|paused|awaiting_human) ;;   # guard while a goal is live
  *) exit 0 ;;
esac

PAYLOAD="$(cat 2>/dev/null || true)"

# Normalize: JSON escapes backslashes, Windows uses them as separators.
NORM="$(printf '%s' "$PAYLOAD" | tr '\\' '/' | sed 's|//|/|g')"
LIVE="$(gf_norm_path "$GF_DIR" | sed 's|//|/|g')"

references_live_state() {
  # absolute reference to this project's state dir
  printf '%s' "$NORM" | grep -Fq "$LIVE" && return 0
  # relative reference (.claude/goal or ./.claude/goal), not another project's
  printf '%s' "$NORM" | grep -Eq '(^|[^/[:alnum:]_.-])\.claude/goal' && return 0
  printf '%s' "$NORM" | grep -Eq '(^|[^[:alnum:]_-])\./\.claude/goal' && return 0
  return 1
}

# A word boundary that survives being embedded in a JSON payload: the verb may
# be preceded by start-of-string, whitespace, a quote, a pipe, a semicolon...
# anything that is not itself part of a word or a path. v2 of this regex used
# [[:space:]]rm[[:space:]] and therefore missed {"command":"rm -rf .claude/goal"}
# because the quote, not a space, preceded the verb. Caught by the suite.
GF_WB='(^|[^[:alnum:]_./-])'
mutating_bash() {
  printf '%s' "$NORM" | grep -Eq '>' && return 0
  printf '%s' "$NORM" | grep -Eq "${GF_WB}(rm|rmdir|mv|cp|tee|truncate|chmod|chown|touch|dd|ln|shred|unlink|install)[[:space:]]" && return 0
  printf '%s' "$NORM" | grep -Eq "${GF_WB}sed[[:space:]]+-i" && return 0
  return 1
}

TOOL="$(gf_stdin_field "$PAYLOAD" tool_name)"

deny() { # reason
  gf_journal "GUARD denied tool=${TOOL:-?} reason=$2"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' \
    "$(printf '%s' "$1" | gf_json_escape)"
  exit 0
}

references_live_state || exit 0

case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    deny "RoT DTD GOAL tamper guard: writing to .claude/goal/* is blocked while a goal is live. State is verification-owned -- a criterion passes only when its verify command actually exits 0, and every criterion is hashed in the integrity ledger (stop_gate re-audits before it verifies, so an edit here cannot buy a completion). Use the CLI: goal.sh status|verify|audit|redteam|sharpen|journal|set|pause|resume|abort." "write-tool"
    ;;
  Bash|"")
    if mutating_bash; then
      deny "RoT DTD GOAL tamper guard: that command would MUTATE this project's live goal state (.claude/goal/*). Reading it is allowed -- cat/grep/ls the state freely -- but passes are earned by running verify commands, never by writing status=passed. If a criterion genuinely needs to change: goal.sh sharpen <ID> \"<desc>\" '<verify>' --reason \"<why>\"." "bash-mutation"
    fi
    ;;
esac

exit 0
