#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# Shared audit hook for every lifecycle event that is not the gate itself.
# Builds the forensic trail a blind loop never has: WHERE friction happened,
# WHEN context compacted, WHICH permissions were denied, HOW the session
# ended -- all correlated with gate decisions in one journal.
#
# v3: covers the full 31-event surface, and rate-limits the chatty ones
# (MessageDisplay, PostToolBatch, Notification...) so telemetry can never
# drown the human-readable journal. Rate limiting is per event name, default
# one line per 30s, override with GF_EVENT_MIN_INTERVAL.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
gf_exists || exit 0
EVENT="${1:-unknown}"
PAYLOAD="$(cat 2>/dev/null || true)"
DETAIL=""
CHATTY=""
case "$EVENT" in
  PostToolUseFailure) DETAIL="tool=$(gf_stdin_field "$PAYLOAD" tool_name)" ;;
  SubagentStop|SubagentStart) DETAIL="agent=$(gf_stdin_field "$PAYLOAD" agent_type)" ;;
  SessionEnd)         DETAIL="reason=$(gf_stdin_field "$PAYLOAD" reason)" ;;
  PermissionRequest|PermissionDenied) DETAIL="tool=$(gf_stdin_field "$PAYLOAD" tool_name)" ;;
  TaskCreated|TaskCompleted) DETAIL="task=$(gf_stdin_field "$PAYLOAD" description | head -c 80)" ;;
  CwdChanged|DirectoryAdded) DETAIL="dir=$(gf_stdin_field "$PAYLOAD" path | head -c 120)" ;;
  WorktreeCreate|WorktreeRemove) DETAIL="worktree=$(gf_stdin_field "$PAYLOAD" path | head -c 120)" ;;
  FileChanged)        DETAIL="file=$(gf_stdin_field "$PAYLOAD" file_path | head -c 120)" ;;
  Notification)       DETAIL="msg=$(gf_stdin_field "$PAYLOAD" message | head -c 80)"; CHATTY=1 ;;
  MessageDisplay|PostToolBatch|Elicitation|ElicitationResult|TeammateIdle|InstructionsLoaded|ConfigChange|Setup|UserPromptExpansion) CHATTY=1 ;;
esac
[ -n "$CHATTY" ] && { gf_event_rate_ok "$EVENT" || exit 0; }
counts="$(crit_counts 2>/dev/null || echo '0 0')"
gf_journal "EVENT $EVENT $DETAIL status=$(gf_status) passed=${counts% *}/${counts#* }"
exit 0
