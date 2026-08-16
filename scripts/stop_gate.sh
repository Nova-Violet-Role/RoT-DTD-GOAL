#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# Stop-hook verification gate -- the heart of RoT DTD GOAL (pure bash).
#
# vs ralph-wiggum (the official loop plugin): ralph re-feeds the SAME prompt
# and exits when Claude prints a "completion promise" string -- completion is
# self-declared and gameable. Here, completion is EARNED: every criterion's
# verify command must actually exit 0. Failures come back as targeted,
# per-criterion output. Budget + stall detection + human escalation prevent
# runaway loops. The stop_hook_active guard prevents hook-level recursion.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

PAYLOAD="$(cat 2>/dev/null || true)"

allow_msg() { # optional systemMessage, then exit 0
  if [ -n "${1:-}" ]; then
    printf '{"systemMessage":"%s"}\n' "$(printf '%s' "$1" | gf_json_escape)"
  fi
  exit 0
}

block_msg() { # reason, then exit 0 with a block decision (keep the loop going)
  printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$1" | gf_json_escape)"
  exit 0
}

# No goal / not active -> never interfere with stopping.
[ "$(gf_status || true)" = "active" ] || exit 0

# Recursion guard: one fresh model turn per gate cycle, never chain blocks.
gf_stdin_has_true "$PAYLOAD" stop_hook_active && exit 0

# ---- integrity gate (v3) --------------------------------------------------
# BEFORE trusting any status, audit the criteria against the ledger sealed at
# activation. A criterion rewritten in place -- even by a route the PreToolUse
# guard never saw -- is arithmetic-detectable here. Drift never completes and
# never passes: it escalates to the human, and every drifted criterion is
# forced back to pending so it must be re-earned.
if ! drift="$(gf_ledger_audit)"; then
  for d in $(printf '%s\n' "$drift" | cut -d' ' -f1); do
    [ -f "$GF_CRIT/$d" ] && crit_set_status "$d" pending
  done
  state_set STATUS awaiting_human
  gf_journal "ESCALATE integrity drift: $(printf '%s' "$drift" | tr '\n' ' ')"
  gf_history_append integrity_drift
  allow_msg "RoT DTD GOAL: INTEGRITY DRIFT. The acceptance criteria no longer match the hashes sealed at activation ($(printf '%s' "$drift" | tr '\n' ' ')). Completion is refused and the affected criteria are reset to pending. A human must review: /goal-status, then 'goal.sh seal --reason ...' if the change was legitimate, or /goal-abort."
fi

res="$(gf_verify_all)"
fail="${res#* }"

if [ "$fail" -eq 0 ]; then
  counts="$(crit_counts)"
  # ---- completion red team (v3) -------------------------------------------
  # All checks pass. Before calling that a win, attack the checks themselves:
  # any criterion that also passes inside an EMPTY directory did not measure
  # this project. GATE_REDTEAM=strict refuses such a completion outright.
  policy="$(state_get GATE_REDTEAM)"; policy="${policy:-warn}"
  weak=""
  if [ "$policy" != "off" ]; then
    weak="$(gf_redteam_all | grep ' WEAK ' || true)"
  fi
  if [ -n "$weak" ] && [ "$policy" = "strict" ]; then
    for d in $(printf '%s\n' "$weak" | cut -d' ' -f1); do crit_set_status "$d" pending; done
    state_set STATUS awaiting_human
    gf_journal "ESCALATE redteam-strict weak=$(printf '%s' "$weak" | tr '\n' ' ')"
    gf_history_append redteam_refused
    allow_msg "RoT DTD GOAL: COMPLETION REFUSED (red team, strict). These criteria pass even in an empty directory, so they prove nothing about this project: $(printf '%s' "$weak" | tr '\n' ' '). Replace them with checks that can fail -- goal.sh sharpen <ID> \"<desc>\" '<verify>' --reason \"...\" -- then stop again."
  fi
  # ---- completion mutation probe (v3.2) -----------------------------------
  # The red team asks "is this check bound to the project at all?". This asks
  # the sharper question at the only moment it is decisive: does each check
  # still FAIL when the files it claims to cover are damaged? It is OFF by
  # default and that is a cost decision, not a confidence one -- it copies the
  # tree once per operator per criterion. GATE_MUTATE=warn reports, strict
  # refuses. GF_GATE_MUTATE_OPS narrows the operator set for speed.
  mpolicy="$(state_get GATE_MUTATE)"; mpolicy="${mpolicy:-off}"
  blind=""
  if [ "$mpolicy" != "off" ]; then
    GF_MUTATE_OPS="${GF_GATE_MUTATE_OPS:-$GF_MUTATE_OPS}"
    blind="$(gf_mutate_all | grep ' SURVIVED ' || true)"
  fi
  if [ -n "$blind" ] && [ "$mpolicy" = "strict" ]; then
    for d in $(printf '%s\n' "$blind" | cut -d' ' -f1); do crit_set_status "$d" pending; done
    state_set STATUS awaiting_human
    gf_journal "ESCALATE mutate-strict blind=$(printf '%s' "$blind" | tr '\n' ' ')"
    gf_history_append mutate_refused
    allow_msg "RoT DTD GOAL: COMPLETION REFUSED (mutation probe, strict). These criteria kept passing after the files they declare in --deps were damaged, so they do not measure what they claim: $(printf '%s' "$blind" | tr '\n' ' '). A score like 2/3 means the check notices the file vanishing but never reads what is inside it -- replace it with one that reads content (goal.sh sharpen <ID> \"<desc>\" '<verify>' --reason \"...\"), then stop again."
  fi
  # ---- flaky gate (v3.4) --------------------------------------------------
  # The last question before calling it done: has any of these criteria ever
  # given a DIFFERENT answer about the same sealed check? A criterion that has
  # both passed and failed is a coin flip, and a goal completed on a coin flip
  # is not verified -- it is lucky. GATE_FLAKY=warn reports, strict refuses.
  # DEFAULT: strict, decided by measurement (since 1.0.0). tests/experiments/
  # flaky_policy.sh ran 60 goals: 0 refusals in 40 goals that were clean or that
  # simply took more than one iteration (the false-alarm arms), and 4 refusals
  # plus 6 escalations out of 20 goals carrying a genuinely random check. Zero
  # measured cost, real measured benefit -- so it is on by default, and the
  # number is written beside it in README rather than the word "conservative".
  fpolicy="$(state_get GATE_FLAKY)"; fpolicy="${fpolicy:-strict}"
  flaky=""
  if [ "$fpolicy" != "off" ]; then
    flaky="$(gf_flaky_ids)"
  fi
  if [ -n "$flaky" ] && [ "$fpolicy" = "strict" ]; then
    for d in $(printf '%s\n' "$flaky" | cut -d' ' -f1); do crit_set_status "$d" pending; done
    state_set STATUS awaiting_human
    gf_journal "ESCALATE flaky-strict flaky=$(printf '%s' "$flaky" | tr '\n' ' ')"
    gf_history_append flaky_refused
    # The refusal carries its evidence. "<id> <passes> <failures>" is the
    # recorded tally inside the current seal generation, and the two files
    # naming it are on disk -- a reader can check the verdict instead of
    # taking it, which is the same standard this gate holds criteria to.
    allow_msg "RoT DTD GOAL: COMPLETION REFUSED (flaky, strict). EVIDENCE -- these criteria PASSED and then FAILED against the same sealed check, with nobody re-sealing them in between. Recorded as 'id passes failures' inside the current seal generation: $(printf '%s' "$flaky" | tr '\n' ' '). Read it yourself: '.claude/goal/timings.tsv' has one row per verification with its generation in the last column, '.claude/goal/ledger' has each criterion's current generation, '.claude/goal/journal.log' has the ESCALATE line, and 'goal.sh flaky' renders all three. A pass recorded before a failure of the same sealed check is not evidence that the check passes -- it is evidence that the check disagrees with itself. Make it deterministic (remove the timing dependence, the network call, the shared temp path), or sharpen it into a different question with 'goal.sh sharpen <ID> \"<desc>\" '\''<verify>'\'' --reason \"...\"' which re-seals it and starts a fresh generation. Then stop again."
  fi
  state_set STATUS complete
  gf_journal "COMPLETE all ${counts#* } criteria passed${weak:+ (WEAK: $(printf '%s' "$weak" | tr '\n' ' '))}${blind:+ (BLIND: $(printf '%s' "$blind" | tr '\n' ' '))}${flaky:+ (FLAKY: $(printf '%s' "$flaky" | tr '\n' ' '))}"
  gf_history_append complete
  # ---- the queue (since 1.0.0) ---------------------------------------------------
  # A completed goal is the end of the session only if nothing else is queued.
  # The warnings above are attached to the goal that just finished, so they are
  # repeated here rather than dropped: advancing must not become a way to lose
  # a red-team, mutation or flake finding.
  #
  # Note the ordering. The queue advances only AFTER completion has been earned
  # by the same checks as ever, and a strict refusal above has already exited.
  # No queued goal can start on the strength of an unverified predecessor.
  if [ -f "$GF_QUEUE" ]; then
    # No swallowing here. If the advance fails while goals are still pending,
    # that is a fact the operator must see -- a queue that quietly stops being
    # a queue is worse than no queue, because the session ends looking finished.
    qerr="$GF_DIR/queue-advance.err"
    nextgoal="$(bash "$SCRIPT_DIR/goal.sh" queue advance 2>"$qerr")" || nextgoal=""
    if [ -z "$nextgoal" ] && [ "$(gf_queue_pending_count)" -gt 0 ]; then
      gf_journal "QUEUE-STUCK pending=$(gf_queue_pending_count) err=$(head -c 200 "$qerr" 2>/dev/null | tr '\n' ' ')"
      allow_msg "RoT DTD GOAL: GOAL COMPLETE. All ${counts#* } acceptance criteria verified passing. QUEUE STUCK: $(gf_queue_pending_count) goal(s) are still pending but none could start -- $(gf_queue_blocked_reason | tr '\n' ' '). Nothing was lost; 'goal.sh queue list' shows the state, and the queue can be repaired and advanced by hand."
    fi
    if [ -n "$nextgoal" ]; then
      # The verdict is reported; the next step is INSTRUCTED. Those are two
      # different speech acts and the transcript marks them as two, so nobody
      # has to infer from prose which sentences are a record of what happened
      # and which are a task. The tag is declared in hooks/trust_contract.dtd.
      # The row just started is ACTIVE, not done, so the step it represents is
      # the one after everything already finished.
      qdone="$(gf_queue_rows | awk -F'\t' '$2 == "done" { n++ } END { print n+1 }')"
      qall="$(gf_queue_rows | wc -l | tr -d ' ')"
      block_msg "RoT DTD GOAL: GOAL COMPLETE -- all ${counts#* } criteria verified passing (every verify command exited 0).${weak:+ RED TEAM WARNING: $(printf '%s' "$weak" | tr '\n' ' ').}${blind:+ MUTATION WARNING: $(printf '%s' "$blind" | tr '\n' ' ').}${flaky:+ FLAKY WARNING: $(printf '%s' "$flaky" | tr '\n' ' ').} That goal's records are archived under .claude/goal/archive/.

<gf:instruction goal=\"$nextgoal\" step=\"$qdone of $qall\">
THE QUEUE HAS ADVANCED. [$nextgoal] is now the active goal and its criteria are already sealed. Do not stop: work on [$nextgoal] now, then stop again so the gate can verify it. 'goal.sh status' shows the new criteria; 'goal.sh queue list' shows what remains.
</gf:instruction>"
    fi
  fi
  if [ -n "$weak" ]; then
    allow_msg "RoT DTD GOAL: GOAL COMPLETE -- all ${counts#* } criteria verified passing (every verify command exited 0). RED TEAM WARNING: $(printf '%s' "$weak" | tr '\n' ' ') -- those checks also pass in an empty directory, so treat them as weak evidence. Set GATE_REDTEAM=strict to make that fatal."
  fi
  if [ -n "$blind" ]; then
    allow_msg "RoT DTD GOAL: GOAL COMPLETE -- all ${counts#* } criteria verified passing (every verify command exited 0). MUTATION WARNING: $(printf '%s' "$blind" | tr '\n' ' ') -- those checks kept passing after their declared dependencies were damaged, so they are blind to that damage. Set GATE_MUTATE=strict to make that fatal."
  fi
  if [ -n "$flaky" ]; then
    allow_msg "RoT DTD GOAL: GOAL COMPLETE -- all ${counts#* } criteria verified passing (every verify command exited 0). FLAKY WARNING: $(printf '%s' "$flaky" | tr '\n' ' ') -- those criteria have both passed and failed against the same sealed check, so this pass may be luck rather than evidence. Set GATE_FLAKY=strict to make that fatal."
  fi
  allow_msg "RoT DTD GOAL: GOAL COMPLETE. All ${counts#* } acceptance criteria verified passing (not self-declared -- every verify command exited 0, and each one FAILS when the project is absent). /goal-status for the report."
fi

# ---- failures: continue with feedback, or escalate ------------------------
iter=$(( $(state_get ITERATION) + 1 ))
state_set ITERATION "$iter"
max="$(state_get MAX_ITERATIONS)"

sig="$(gf_failure_signature)"
if [ "$sig" = "$(state_get LAST_SIG)" ]; then
  streak=$(( $(state_get SIG_STREAK) + 1 ))
else
  streak=1
fi

# Progress telemetry, and a belt-and-braces stall guard (v3).
#
# HONEST LABEL, measured by mutation M5: this streak reset is REDUNDANT today.
# gf_failure_signature hashes the failed IDs and their logs, so any criterion
# that starts passing necessarily changes the signature and resets the streak
# on its own -- there is no reachable state where the passing count grows while
# the signature stays identical. Disabling this branch killed exactly one
# assertion (the journal line), not the stall behaviour.
#
# It is kept for two reasons, both stated rather than implied: it emits the
# PROGRESS trajectory that `goal.sh learn` can mine, and it keeps the stall
# rule correct if the signature definition is ever narrowed (e.g. to hash only
# the error text). It is NOT the thing that prevents a stall -- the signature
# comparison is. Do not sell it as more than that.
counts="$(crit_counts)"; now_passed="${counts% *}"
last_passed="$(state_get LAST_PASSED)"; last_passed="${last_passed:-0}"
if [ "$now_passed" -gt "$last_passed" ]; then
  streak=1
  gf_journal "PROGRESS passed $last_passed -> $now_passed (stall streak reset)"
fi
state_set LAST_PASSED "$now_passed"
state_set LAST_SIG "$sig"
state_set SIG_STREAK "$streak"

if [ "$iter" -gt "$max" ]; then
  state_set STATUS awaiting_human
  gf_journal "ESCALATE budget exhausted at iteration $iter"
  gf_history_append awaiting_human
  allow_msg "RoT DTD GOAL: iteration budget ($max) exhausted with $fail criteria still failing. Escalating to you. Review with /goal-status, then /goal-resume or /goal-abort. (goal.sh learn now has one more sample to size the next budget from.)"
fi

if [ "$streak" -ge "$(state_get STALL_THRESHOLD)" ]; then
  state_set STATUS awaiting_human
  gf_journal "ESCALATE stalled (sig $sig x$streak)"
  gf_history_append awaiting_human
  allow_msg "RoT DTD GOAL: STALL DETECTED -- identical failures repeated $streak times. Blind iteration will not fix this (the classic Ralph-loop failure). Escalating to you: /goal-status to inspect, /goal-resume after guidance, or /goal-abort."
fi

gf_journal "BLOCK iter=$iter/$max fail=$fail sig=$sig"

counts="$(crit_counts)"; total="${counts#* }"
reason="$(
  {
    echo "RoT DTD GOAL verification gate: $fail of $total acceptance criteria are FAILING (iteration $iter/$max)."
    echo
    # THREE SHAPES, ON PURPOSE, in the one message that decides what happens
    # next. Each addresses a different question and they are not
    # interchangeable:
    #
    #   DECLARATION (this block)  -- the laws of this session. Not an opinion,
    #                                not addressed to anyone; a schema to
    #                                validate against.
    #   INSTRUCTION (<gf:...>)    -- the task, tagged as a task.
    #   DATA (<![GF-UNTRUSTED[)   -- what a command printed. Never executed,
    #                                never in the engine's voice.
    #
    # The refusal is the moment this matters. A bare "no" invites argument, a
    # re-run, or an edited criterion; a declaration plus a task invites work.
    # The laws are read from hooks/trust_contract.dtd, so editing the contract
    # changes what the gate says -- they are never restated here.
    gf_law_block 1 3 9 12
    echo
    echo "<gf:instruction goal=\"$(state_get GOAL)\" iteration=\"$iter of $max\">"
    echo "  Fix only what is listed below. Do not restart from scratch, do not"
    echo "  edit the criteria to match the code, then stop again to re-verify."
    echo "</gf:instruction>"
    echo
    for id in $(gf_failed_ids); do
      echo "[FAIL] $id: $(crit_field "$id" desc)"
      echo "  verify command: $(crit_field "$id" verify)"
      echo "  output:"
      gf_quarantine "$GF_OUT/$id.log" "output of $id"
      echo
    done
    passed_list="$(gf_passed_ids | tr '\n' ' ')"
    [ -n "$passed_list" ] && echo "Already passing (do not break these): $passed_list"
    # The 31 events stop being decoration here (v3.4, invariant 8): if this
    # cycle was full of denied permissions or failing tools, the model is being
    # blocked by the ENVIRONMENT, not by its own code, and that needs a
    # different fix. Silent when there is no friction to report.
    friction="$(gf_friction_since_last_cycle)"
    [ -n "$friction" ] && { echo; echo "$friction"; }
  } | gf_json_escape
)"
# Marks where this cycle ended, so the next one measures friction from here.
gf_journal "GATE-CYCLE end iter=$iter"

printf '{"decision":"block","reason":"%s"}\n' "$reason"
exit 0
