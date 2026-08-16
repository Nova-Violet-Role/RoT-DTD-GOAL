#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# Freshness tracking. Wired to PostToolUse (Write|Edit|MultiEdit|NotebookEdit)
# and to FileChanged (edits that happen OUTSIDE Claude's tools -- another
# agent, a rebase, the human's editor).
#
# v2 invalidated EVERY passing criterion on EVERY edit: correct but brutal,
# and it made a 10-criterion goal re-run its whole suite after a typo fix.
# v3 keeps the conservative default and adds dependency scoping: a criterion
# declared with --deps 'glob;glob' is only invalidated by an edit that
# actually matches it. Criteria without deps still invalidate on any edit, so
# the safe behaviour is what you get when you say nothing.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"
[ "$(gf_status || true)" = "active" ] || exit 0

PAYLOAD="$(cat 2>/dev/null || true)"
CHANGED="$(gf_stdin_field "$PAYLOAD" file_path)"
[ -n "$CHANGED" ] || CHANGED="$(gf_stdin_field "$PAYLOAD" path)"

kept=0; cleared=0
for id in $(gf_passed_ids); do
  if [ -n "$CHANGED" ] && ! gf_deps_match "$id" "$CHANGED"; then
    kept=$((kept + 1))
    continue
  fi
  crit_set_status "$id" pending
  cleared=$((cleared + 1))
done
[ "$cleared" -gt 0 ] && gf_journal "FRESHNESS cleared=$cleared kept=$kept path=$(printf '%s' "$CHANGED" | head -c 120)"
exit 0
