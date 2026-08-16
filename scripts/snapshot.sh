#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# PreCompact snapshot -- the one hook event where losing context is CERTAIN.
#
# v3.0 journalled a line here ("PreCompact happened") which is forensics, not
# recovery. v3.1 writes a real, human-readable snapshot to
# .claude/goal/snapshot.md: what the goal is, which criteria pass, which fail,
# the exact verify commands, and the head of each failing output. After
# compaction the model has lost the transcript but not the evidence -- the
# PostCompact hook re-injects the goal context, and this file is what it points
# at when the detail matters.
#
# Invariant 4 (state stays inspectable) is the point: a human with `cat` gets
# the same recovery view the model does.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

case "$(gf_status || true)" in
  active|paused|awaiting_human) ;;
  *) exit 0 ;;
esac

PAYLOAD="$(cat 2>/dev/null || true)"   # drained so the hook never blocks a pipe
SNAP="$GF_DIR/snapshot.md"
counts="$(crit_counts)"; passed="${counts% *}"; total="${counts#* }"

{
  printf '# RoT DTD GOAL snapshot (written at PreCompact %s)\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '**Goal:** %s\n\n' "$(state_get GOAL)"
  printf '**Status:** %s | %s/%s criteria passed | iteration %s/%s\n\n' \
    "$(gf_status)" "$passed" "$total" "$(state_get ITERATION)" "$(state_get MAX_ITERATIONS)"
  if drift="$(gf_ledger_audit)"; then
    printf '**Integrity:** ledger OK\n\n'
  else
    printf '**Integrity:** DRIFT -- %s\n\n' "$(printf '%s' "$drift" | tr '\n' ' ')"
  fi
  printf '## Criteria\n\n'
  for id in $(crit_ids); do
    st="$(crit_field "$id" status)"
    printf -- '- [%s] **%s** %s\n' \
      "$(case "$st" in passed) echo PASS;; failed) echo FAIL;; *) echo '----';; esac)" \
      "$id" "$(crit_field "$id" desc)"
    printf -- '  - verify: `%s`\n' "$(crit_field "$id" verify)"
    [ -n "$(crit_field "$id" deps || true)" ] && printf -- '  - deps: `%s`\n' "$(crit_field "$id" deps)"
  done
  failing="$(gf_failed_ids)"
  if [ -n "$failing" ]; then
    printf '\n## Failing output (head)\n\n'
    for id in $failing; do
      printf '### %s\n\n```\n' "$id"
      head -c 600 "$GF_OUT/$id.log" 2>/dev/null
      printf '\n```\n\n'
    done
  fi
  printf '\n## Recovery\n\n'
  printf 'Do NOT restart the goal. Re-read this file, fix only the failing criteria above,\n'
  printf 'then stop -- the gate re-verifies for real. Never edit .claude/goal/* by hand;\n'
  printf 'the ledger will catch it and refuse the completion.\n'
} > "$SNAP" 2>/dev/null

# ---- the ring (v3.4) ------------------------------------------------------
# v3.1-v3.3 kept exactly ONE slot: the second compaction of a session erased
# the first. A long goal compacts repeatedly, so the single slot systematically
# destroyed the EARLY context -- the part describing what the goal was before
# the model drifted, which is precisely what a recovering session needs most.
# snapshot.md stays as the "latest" pointer every doc and hook already names;
# snapshots/<ts>.md accumulates, bounded by GF_SNAPSHOT_KEEP (default 5).
KEEP="${GF_SNAPSHOT_KEEP:-5}"
[ "$KEEP" -gt 0 ] 2>/dev/null || KEEP=5
RING="$GF_DIR/snapshots"
mkdir -p "$RING" 2>/dev/null
STAMP="$(date '+%Y%m%d-%H%M%S')"
RING_FILE="$RING/$STAMP.md"
# Collision-safe: two compactions inside one second must not overwrite.
if [ -e "$RING_FILE" ]; then
  n=2
  while [ -e "$RING/$STAMP-$n.md" ]; do n=$((n + 1)); done
  RING_FILE="$RING/$STAMP-$n.md"
fi
if cp "$SNAP" "$RING_FILE" 2>/dev/null; then
  ring_ok=1
else
  ring_ok=0
  gf_journal "SNAPSHOT-RING-ERROR could not write $RING_FILE"
fi
# Prune oldest beyond KEEP. Sorted by name, which is sorted by time.
pruned=0
if [ "$ring_ok" -eq 1 ]; then
  total_ring="$(ls -1 "$RING"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$total_ring" -gt "$KEEP" ]; then
    for old in $(ls -1 "$RING"/*.md 2>/dev/null | sort | head -n "$((total_ring - KEEP))"); do
      rm -f "$old" && pruned=$((pruned + 1))
    done
  fi
fi

gf_journal "SNAPSHOT written passed=$passed/$total bytes=$(wc -c < "$SNAP" 2>/dev/null | tr -d ' ') ring=$(ls -1 "$RING"/*.md 2>/dev/null | wc -l | tr -d ' ')/$KEEP pruned=$pruned"
exit 0
