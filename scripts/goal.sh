#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL (formerly goal-forge).
# RoT DTD GOAL CLI. All slash commands and agents talk to state through this.
#
#   goal.sh init "<goal text>" [--budget N|auto] [--stall N] [--timeout SECS]
#   goal.sh add <ID> "<desc>" '<verify cmd>' [--deps 'glob;glob']
#   goal.sh activate                 seals the integrity ledger
#   goal.sh status [--brief] | verify | journal [N] | version
#   goal.sh audit                    ledger integrity check (exit 1 on drift)
#   goal.sh redteam [--strict]       attack the checks (exit 1 if any is weak)
#   goal.sh mutate [--ops LIST]      damage each criterion's deps in a sandbox
#                                    copy; a check that still passes is blind.
#                                    ops: delete truncate corrupt constflip
#                                    negate hunk | aliases: structural semantic all
#   goal.sh sharpen <ID> "<desc>" '<verify cmd>' --reason "<why>"
#   goal.sh seal --reason "<why>"    re-seal after a sanctioned change
#   goal.sh learn | history [N]      cross-goal telemetry -> recommendations
#   goal.sh timings [N]              per-criterion verify durations + the
#                                    learned timeout each one would now get
#   goal.sh flaky                    criteria that PASSED and then FAILED
#                                    against the same sealed check, scoped by
#                                    seal GENERATION, never by a clock
#   goal.sh attest [--facts|--verify F]
#                                    machine-checkable statement of what this
#                                    tree measures, re-verifiable by a stranger
#   goal.sh events                   view of lifecycle events, rendered from
#                                    journal.log -- the single record
#   goal.sh forensics                what every 'forensic' event actually
#                                    surfaced (a classification must earn it)
#   goal.sh pause | resume | abort
#   goal.sh set KEY VALUE  (MAX_ITERATIONS|STALL_THRESHOLD|CMD_TIMEOUT|NOTES|
#                           GATE_REDTEAM|GATE_MUTATE|GATE_FLAKY|MAX_SHARPEN)
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

die() { echo "ERROR: $*" >&2; exit 1; }

cmd_init() {
  [ $# -ge 1 ] || die "usage: goal.sh init \"<goal>\" [--budget N] [--stall N] [--timeout S]"
  local goal="$1"; shift
  local budget=8 stall=2 tmo=120 learned=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --budget)  budget="$2"; shift 2 ;;
      --stall)   stall="$2";  shift 2 ;;
      --timeout) tmo="$2";    shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  # v3: budgets can be learned from this project's own goal history.
  if [ "$budget" = "auto" ]; then
    [ -s "$GF_HISTORY" ] || die "--budget auto needs history; none yet (goal.sh learn)."
    budget="$(gf_learned_value RECOMMENDED_BUDGET)"
    stall="$(gf_learned_value RECOMMENDED_STALL)"
    learned=" (learned from $(gf_learned_value SAMPLES) past goals)"
  fi
  printf '%s' "$budget" | grep -Eq '^[0-9]+$' || die "--budget must be an integer or 'auto'."
  local cur; cur="$(gf_status || true)"
  case "$cur" in
    active|paused|awaiting_human)
      die "a goal is already $cur. Run /goal-abort first." ;;
  esac
  rm -rf "$GF_CRIT" "$GF_OUT"; rm -f "$GF_LEDGER"; gf_ensure_dirs
  : > "$GF_STATE"
  state_set GOAL "$(printf '%s' "$goal" | tr '\n' ' ' | head -c 2000)"
  state_set STATUS draft
  state_set ITERATION 0
  state_set MAX_ITERATIONS "$budget"
  state_set STALL_THRESHOLD "$stall"
  state_set CMD_TIMEOUT "$tmo"
  state_set LAST_SIG ""
  state_set SIG_STREAK 0
  state_set LAST_PASSED 0
  state_set GATE_REDTEAM "${GF_GATE_REDTEAM:-warn}"   # off|warn|strict
  state_set GATE_MUTATE  "${GF_GATE_MUTATE:-off}"     # off|warn|strict (costly)
  # strict since 1.0.0, decided by tests/experiments/flaky_policy.sh: 0 refusals
  # in 40 goals across the two false-alarm arms. It is written into state rather
  # than left implicit so a human with `cat` can see which policy is in force.
  state_set GATE_FLAKY   "${GF_GATE_FLAKY:-strict}"   # off|warn|strict
  state_set MAX_SHARPEN 2
  state_set SHARPEN_COUNT 0
  state_set CREATED_AT "$(date +%s)"
  # Same fixed-width format as timings.tsv's ts column, so flake history can be
  # scoped to THIS goal by string comparison alone.
  state_set CREATED_ISO "$(date '+%Y-%m-%d %H:%M:%S')"
  gf_journal "INIT (draft) goal='$(printf '%s' "$goal" | head -c 80)' budget=$budget stall=$stall"
  echo "Draft goal created$learned. Add criteria with: goal.sh add <ID> \"<desc>\" '<verify cmd>' then: goal.sh activate"
}

cmd_add() {
  [ $# -ge 3 ] || die "usage: goal.sh add <ID> \"<desc>\" '<verify shell command>' [--deps 'glob;glob']"
  local id="$1" desc="$2" verify="$3" deps=""; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --deps) deps="$2"; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ "$(gf_status)" = "draft" ] || die "criteria can only be added to a draft goal (run init first)."
  printf '%s' "$id" | grep -Eq '^[A-Za-z0-9_-]{1,24}$' || die "ID must be alnum/dash/underscore (e.g. C1)."
  [ -n "$verify" ] || die "verify command must be non-empty."
  case "$verify" in *$'\n'*) die "verify must be a single-line shell command (use && or ;)." ;; esac
  # v3 static red team: a check that cannot fail is not a check.
  if gf_vacuous_cmd "$verify"; then
    gf_journal "REJECT vacuous criterion $id verify='$(printf '%s' "$verify" | head -c 60)'"
    die "criterion $id rejected: that verify command can never fail (it exits 0 by construction). A criterion must be able to FAIL. Try a real check (test/grep -q/build/test-suite)."
  fi
  {
    printf 'status=pending\n'
    printf 'desc=%s\n'   "$(printf '%s' "$desc" | tr '\n' ' ' | head -c 300)"
    printf 'verify=%s\n' "$verify"
    printf 'deps=%s\n'   "$(printf '%s' "$deps" | tr '\n' ' ' | head -c 300)"
  } > "$GF_CRIT/$id"
  echo "Added $id.${deps:+ deps=$deps}"
}

cmd_activate() {
  [ "$(gf_status)" = "draft" ] || die "no draft goal to activate."
  local n; n=$(crit_ids | wc -l | tr -d ' ')
  [ "$n" -ge 1 ] || die "add at least one criterion before activating."
  state_set STATUS active
  gf_seal_all
  gf_journal "ACTIVATE criteria=$n budget=$(state_get MAX_ITERATIONS) sealed=$(wc -l < "$GF_LEDGER" | tr -d ' ')"
  echo "Goal ACTIVE with $n verifiable criteria (budget $(state_get MAX_ITERATIONS) iterations)."
  echo "Integrity ledger sealed: every criterion is hashed; the Stop gate audits before it verifies."
  echo "The Stop gate now verifies for real; completion cannot be self-declared."
  local weak; weak="$(gf_redteam_all | grep ' WEAK ' || true)"
  if [ -n "$weak" ]; then
    echo
    echo "RED TEAM WARNING -- these criteria survived no negative control:"
    printf '%s\n' "$weak" | sed 's/^/  /'
    echo "  (gate policy GATE_REDTEAM=$(state_get GATE_REDTEAM); 'strict' refuses to complete on a weak check)"
    gf_journal "REDTEAM activate weak=$(printf '%s' "$weak" | wc -l | tr -d ' ')"
  fi
}

cmd_audit() {
  gf_exists || die "no goal exists."
  local drift; drift="$(gf_ledger_audit)" && { echo "LEDGER OK: $(wc -l < "$GF_LEDGER" | tr -d ' ') criteria match their sealed hashes."; return 0; }
  echo "LEDGER DRIFT detected:"
  printf '%s\n' "$drift" | sed 's/^/  /'
  gf_journal "AUDIT drift: $(printf '%s' "$drift" | tr '\n' ' ')"
  return 1
}

cmd_redteam() {
  gf_exists || die "no goal exists."
  local strict="" out rc=0
  [ "${1:-}" = "--strict" ] && strict=1
  out="$(gf_redteam_all)" || rc=1
  printf '%s\n' "$out"
  gf_journal "REDTEAM manual weak=$(printf '%s' "$out" | grep -c ' WEAK ' || true)"
  if [ "$rc" -ne 0 ]; then
    echo
    echo "At least one criterion cannot distinguish this project from an empty directory."
    echo "Sharpen it: goal.sh sharpen <ID> \"<desc>\" '<stronger verify>' --reason \"...\""
    [ -n "$strict" ] && return 1
    return 1
  fi
  echo
  echo "All criteria survived the negative control (each one FAILS when the project is absent)."
}

cmd_mutate() {
  gf_exists || die "no goal exists."
  local out rc=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --ops) shift; GF_MUTATE_OPS="$(gf_expand_ops "$(printf '%s' "${1:-}" | tr ',' ' ')")"; export GF_MUTATE_OPS ;;
      *) die "unknown flag for mutate: $1" ;;
    esac
    shift
  done
  echo "operators: $GF_MUTATE_OPS"
  out="$(gf_mutate_all)" || rc=1
  printf '%s\n' "$out"
  gf_journal "MUTATE ops=$(printf '%s' "$GF_MUTATE_OPS" | tr ' ' ',') survived=$(printf '%s' "$out" | grep -c ' SURVIVED ' || true) killed=$(printf '%s' "$out" | grep -c ' KILLED ' || true)"
  echo
  if [ "$rc" -ne 0 ]; then
    echo "A criterion kept passing after the files it claims to depend on were damaged."
    echo "Either its --deps are wrong, or the check does not test what its description says."
    echo "A partial score (e.g. 2/3 -- survived: corrupt) means the check notices the file"
    echo "disappearing but not the file LYING. Read the content, not the inode."
    return 1
  fi
  echo "Every probeable criterion FAILED under every operator ($GF_MUTATE_OPS)."
  echo "(SKIPPED lines are not passes -- a criterion without --deps cannot be mutation-probed.)"
}

cmd_sharpen() { # ID desc verify --reason "why"
  [ $# -ge 3 ] || die "usage: goal.sh sharpen <ID> \"<desc>\" '<verify cmd>' --reason \"<why>\""
  local id="$1" desc="$2" verify="$3" reason="" deps="" deps_new=""; shift 3
  while [ $# -gt 0 ]; do
    case "$1" in
      --reason) reason="$2"; shift 2 ;;
      --deps)   deps_new="$2"; shift 2 ;;
      *) die "unknown option: $1" ;;
    esac
  done
  [ -n "$reason" ] || die "sharpen requires --reason (criteria evolution must be human-readable)."
  case "$(gf_status || true)" in active|draft) ;; *) die "criteria can only be sharpened while the goal is draft or active." ;; esac
  [ -f "$GF_CRIT/$id" ] || die "no such criterion: $id"
  [ "$(crit_field "$id" status)" = "passed" ] && die "$id already passed; sharpening a passed criterion would erase proven work. Abort or add a new criterion instead."
  local used max; used="$(state_get SHARPEN_COUNT)"; used="${used:-0}"; max="$(state_get MAX_SHARPEN)"; max="${max:-2}"
  [ "$used" -ge "$max" ] && die "sharpen budget exhausted ($used/$max). Moving the goalposts again needs a human: /goal-status then /goal-abort or raise MAX_SHARPEN deliberately."
  gf_vacuous_cmd "$verify" && die "refused: the replacement check can never fail. Sharpening must strengthen, never weaken."
  local old_desc old_verify old_hash
  old_desc="$(crit_field "$id" desc)"; old_verify="$(crit_field "$id" verify)"; old_hash="$(gf_crit_hash "$id")"
  deps="${deps_new:-$(crit_field "$id" deps)}"
  {
    printf 'status=pending\n'
    printf 'desc=%s\n'   "$(printf '%s' "$desc" | tr '\n' ' ' | head -c 300)"
    printf 'verify=%s\n' "$verify"
    printf 'deps=%s\n'   "$deps"
  } > "$GF_CRIT/$id"
  # The replacement must itself survive the negative control, else revert.
  if gf_probe_control "$id"; then
    {
      printf 'status=pending\n'
      printf 'desc=%s\n'   "$old_desc"
      printf 'verify=%s\n' "$old_verify"
      printf 'deps=%s\n'   "$deps"
    } > "$GF_CRIT/$id"
    gf_journal "SHARPEN refused $id (replacement passes in an empty dir)"
    die "refused: the replacement passes in an empty directory, so it does not test this project. Original restored."
  fi
  gf_seal_one "$id"
  state_set SHARPEN_COUNT $((used + 1))
  gf_journal "SHARPEN $id ($((used + 1))/$max) reason='$(printf '%s' "$reason" | head -c 120)' old_hash=$old_hash old_verify='$(printf '%s' "$old_verify" | head -c 120)' new_verify='$(printf '%s' "$verify" | head -c 120)'"
  echo "Sharpened $id ($((used + 1))/$max used). Old check preserved in the journal; ledger re-sealed; status reset to pending."
}

cmd_seal() {
  local reason=""
  while [ $# -gt 0 ]; do
    case "$1" in --reason) reason="$2"; shift 2 ;; *) die "unknown option: $1" ;; esac
  done
  [ -n "$reason" ] || die "seal requires --reason (a re-seal is a sanctioned change, it must be readable)."
  gf_exists || die "no goal exists."
  local id
  for id in $(crit_ids); do
    [ "$(crit_field "$id" status)" = "passed" ] && [ "$(gf_ledger_hash "$id")" != "$(gf_crit_hash "$id")" ] && crit_set_status "$id" pending
  done
  gf_seal_all
  gf_journal "SEAL manual reason='$(printf '%s' "$reason" | head -c 160)'"
  echo "Ledger re-sealed over $(crit_ids | wc -l | tr -d ' ') criteria. Any changed criterion that was 'passed' is now pending -- a re-seal never grants a pass."
}

cmd_learn() {
  gf_learn
  local n; n="$(gf_learned_value SAMPLES)"
  echo "# source: $GF_HISTORY ($( [ -f "$GF_HISTORY" ] && wc -l < "$GF_HISTORY" | tr -d ' ' || echo 0) rows)"
  echo "# recommended budget $(gf_learned_value RECOMMENDED_BUDGET) -- learned from ${n:-0} past goal(s)"
  echo "# recommended stall  $(gf_learned_value RECOMMENDED_STALL) -- learned from ${n:-0} past goal(s)"
  if [ "${n:-0}" -lt 3 ] 2>/dev/null; then
    echo "# ${n:-0} goals is not a sample. Treat these as defaults with a story, not advice."
  fi
  echo "# use it: goal.sh init \"<goal>\" --budget auto"
}

cmd_history() {
  [ -s "$GF_HISTORY" ] || { echo "(no goal history yet)"; return 0; }
  echo "when                 outcome         iter/max  crit  passed  secs  goal"
  tail -n "${1:-15}" "$GF_HISTORY" | while IFS=$'\t' read -r ts out it mx tot pas dur goal; do
    printf '%-20s %-15s %5s/%-3s %5s %6s %6s  %s\n' \
      "$(date -d "@$ts" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$ts")" \
      "$out" "$it" "$mx" "$tot" "$pas" "$dur" "$goal"
  done
}
cmd_flaky() {
  gf_exists || die "no goal exists."
  echo "FLAKY CRITERIA -- a check that PASSED and then FAILED against the same"
  echo "sealed command has regressed, and that pass is not evidence."
  echo
  gf_flaky_report
  echo
  echo "scope: each criterion's history starts at ITS OWN ledger seal. Sharpening a"
  echo "criterion re-seals it, so a fail -> fix -> pass across a sharpen is not a"
  echo "flake: the old answer belongs to a check that no longer exists."
  echo "The window is scoped by seal GENERATION, not by seal time. A clock that"
  echo "jumps backwards cannot push a real flip outside the window, because no"
  echo "clock is consulted; the time below is shown for you, not used."
  for id in $(crit_ids); do
    printf '  %-10s generation %s   sealed %s\n' "$id" "$(gf_seal_gen "$id")" "$(gf_seal_iso "$id" || true)"
  done
  echo
  echo "policy: GATE_FLAKY=$(state_get GATE_FLAKY || echo strict) (off | warn | strict)"
  echo "strict refuses completion; warn reports it beside GOAL COMPLETE."
  echo
  echo "a flake here means a REGRESSION: a pass followed later by a failure"
  echo "against the same sealed check. A criterion that failed and then passed"
  echo "has progressed -- that is the loop working, not a coin flip. Measured:"
  echo "tests/experiments/flaky_policy.sh, 40 goals in the false-alarm arms, 0"
  echo "refusals; 20 goals with a genuinely random check, 4 refused and 6"
  echo "escalated. A check seen only failing-then-passing is NOT reported here,"
  echo "and cannot be: that history is exactly what completed work looks like."
}


cmd_events() {
  gf_exists || die "no goal exists."
  echo "LIFECYCLE EVENTS -- a VIEW, rendered from journal.log, which is the only"
  echo "record. Nothing here is stored separately, so nothing here can disagree"
  echo "with the journal you can read yourself."
  echo
  echo "count  last seen            event"
  gf_events_view
  echo
  echo "classification lives in hooks/event_consumers.tsv; 'goal.sh forensics'"
  echo "shows what each forensic event actually surfaced."
}

# Validate a queue spec against the grammar DECLARED in trust_contract.dtd.
#
# The verbs and their cardinalities are read from `<!ELEMENT spec (GOAL, CRIT+)>`
# rather than written here. That is the point: a grammar restated in the code
# that enforces it is two grammars, and the second one drifts. Narrow the
# declaration and this function refuses what it used to accept -- which is how
# the test proves the binding is real rather than decorative.
gf_spec_validate() { # specfile -> 0 if it satisfies the declared grammar
  local f="$1" verb rest model tok name card n
  [ -f "$f" ] || { echo "spec not found: $f"; return 1; }
  model="$(gf_spec_model)"
  [ -n "$model" ] || { echo "the spec grammar is not declared in trust_contract.dtd"; return 1; }
  # count each verb actually used
  local counts="" known
  while IFS="$(printf '\t')" read -r verb rest; do
    case "$verb" in ''|'#'*) continue ;; esac
    known=0
    for tok in $model; do
      [ "${tok%[+*]}" = "$verb" ] && known=1
    done
    [ "$known" -eq 1 ] || { echo "unknown verb [$verb] -- the declared grammar is: $model"; return 1; }
    counts="$counts$verb "
  done < "$f"
  for tok in $model; do
    name="${tok%[+*]}"; card="${tok#"$name"}"
    n="$(printf '%s' "$counts" | tr ' ' '\n' | grep -c "^$name$")"
    case "$card" in
      '+') [ "$n" -ge 1 ] || { echo "the grammar needs at least one $name row (found $n)"; return 1; } ;;
      '*') : ;;
      *)   [ "$n" -eq 1 ] || { echo "the grammar needs exactly one $name row (found $n)"; return 1; } ;;
    esac
  done
  return 0
}

cmd_queue() {
  local sub="${1:-list}"; shift || true
  case "$sub" in
    add)
      local name="${1:-}" spec="${2:-}" dep=""
      shift 2 2>/dev/null || true
      while [ $# -gt 0 ]; do
        case "$1" in
          --after) dep="$2"; shift 2 ;;
          *) die "unknown option: $1" ;;
        esac
      done
      [ -n "$name" ] && [ -n "$spec" ] || die "usage: goal.sh queue add <name> <spec.tsv> [--after <name>]"
      printf '%s' "$name" | grep -Eq '^[A-Za-z0-9_-]+$' || die "queue names are [A-Za-z0-9_-]+ so the file stays readable."
      gf_ensure_dirs
      [ -n "$(gf_queue_status "$name")" ] && die "queue already has a goal named [$name]."
      local why; why="$(gf_spec_validate "$spec")" || die "spec rejected: $why"
      # A dependency must ALREADY be queued. Dependencies therefore point
      # strictly backwards, so the queue is acyclic by construction -- the
      # cheapest possible cycle check, and one a human can verify by reading
      # the file top to bottom.
      if [ -n "$dep" ]; then
        [ -n "$(gf_queue_status "$dep")" ] || die "[$dep] is not queued yet; queue it first (dependencies point backwards)."
      fi
      [ -f "$GF_QUEUE" ] || printf '# name\tstatus\tafter\tspec  -- RoT DTD GOAL queue\n' > "$GF_QUEUE"
      printf '%s\t%s\t%s\t%s\n' "$name" "pending" "${dep:--}" "$(cd "$(dirname "$spec")" && pwd)/$(basename "$spec")" >> "$GF_QUEUE"
      gf_journal "QUEUE-ADD $name after=${dep:--}"
      echo "queued [$name]${dep:+ after [$dep]}. 'goal.sh queue list' shows the order."
      ;;
    list)
      [ -f "$GF_QUEUE" ] || { echo "(the queue is empty -- one goal is running)"; return 0; }
      echo "GOAL QUEUE -- one goal at a time, in dependency order."
      echo
      printf '%-16s %-9s %-16s %s\n' "name" "status" "after" "spec"
      local n s a p
      while IFS="$(printf '\t')" read -r n s a p; do
        printf '%-16s %-9s %-16s %s\n' "$n" "$s" "$a" "$p"
      done <<EOF
$(gf_queue_rows)
EOF
      echo
      local nxt; nxt="$(gf_queue_next || true)"
      if [ -n "$nxt" ]; then
        echo "next to start: $nxt"
      else
        echo "next to start: (none)"
        gf_queue_blocked_reason | sed 's/^/  /'
      fi
      echo "pending: $(gf_queue_pending_count)   active: $(gf_queue_active || echo -)"
      ;;
    next)    gf_queue_next || { echo "(none)"; return 1; } ;;
    advance) cmd_queue_advance ;;
    clear)
      rm -f "$GF_QUEUE"; gf_journal "QUEUE-CLEAR"
      echo "queue cleared. Archived goals under .claude/goal/archive/ are untouched." ;;
    *) die "usage: goal.sh queue [add|list|next|advance|clear]" ;;
  esac
}

# Finish the goal that just completed and start the next eligible one.
# Exit 0 = a new goal is now active (its name on stdout); exit 1 = nothing to
# start, and the caller should complete the session as it always did.
cmd_queue_advance() {
  local prev nxt spec verb a b c archdir
  prev="$(gf_queue_active || true)"
  [ -n "$prev" ] && gf_queue_set_status "$prev" done
  nxt="$(gf_queue_next || true)"
  [ -n "$nxt" ] || return 1
  spec="$(gf_queue_field "$nxt" 4)"
  [ -f "$spec" ] || { gf_journal "QUEUE-FAIL $nxt spec-missing"; return 1; }
  # Archive the finished goal's own records. The journal is NOT copied: it is
  # the single record of what happened, and a second copy of it would be the
  # overlapping-truth defect this engine already closed once.
  if gf_exists; then
    archdir="$GF_ARCHIVE/${prev:-goal-$(date +%s)}"
    mkdir -p "$archdir"
    [ -f "$GF_STATE" ]  && cp "$GF_STATE"  "$archdir/state" || true
    [ -f "$GF_LEDGER" ] && cp "$GF_LEDGER" "$archdir/ledger" || true
    [ -d "$GF_CRIT" ]   && cp -r "$GF_CRIT" "$archdir/criteria" || true
  fi
  while IFS="$(printf '\t')" read -r verb a b c; do
    case "$verb" in
      GOAL) # shellcheck disable=SC2086
            cmd_init "$a" $b > /dev/null ;;
      CRIT) cmd_add "$a" "$b" "$c" > /dev/null ;;
      *) continue ;;
    esac
  done < "$spec"
  cmd_activate > /dev/null
  gf_queue_set_status "$nxt" active
  gf_journal "QUEUE-ADVANCE from=${prev:--} to=$nxt criteria=$(crit_ids | wc -l | tr -d ' ')"
  echo "$nxt"
}

cmd_contract() { # [--verify]
  local dtd v tokens=0 missing=0 laws=0 hits
  dtd="$(gf_contract_file)"
  [ -f "$dtd" ] || die "trust_contract.dtd is missing -- the trust boundary is undeclared."
  if [ "${1:-}" != "--verify" ]; then
    cat "$dtd"
    echo
    echo "run 'goal.sh contract --verify' to check the declaration against the code."
    return 0
  fi
  echo "TRUST CONTRACT -- who may speak, checked against the scripts."
  echo
  # Direction 1: every declared verdict is really emitted by a script. A
  # contract may not accumulate vocabulary nobody uses; that is how a
  # declaration turns into decoration.
  while IFS= read -r v; do
    tokens=$((tokens + 1))
    hits="$(grep -lF "$v" "$SCRIPT_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$hits" -gt 0 ]; then
      printf '  declared and emitted   %-22s (%s script(s))\n' "$v" "$hits"
    else
      printf '  DECLARED BUT UNUSED    %-22s <- delete it or emit it\n' "$v"
      missing=$((missing + 1))
    fi
  done <<EOF
$(gf_contract_verdicts)
EOF
  # Direction 3: the agent roster, both ways. An agent is the one component
  # whose output is prose, so it is the one that could sound official without
  # being a decision. Every declared agent must exist; every file in agents/
  # must be declared. A roster nobody checks is a directory listing.
  local a name elem file adrift=0 acount=0
  while IFS='|' read -r name elem _ _; do
    [ -n "$name" ] || continue
    acount=$((acount + 1))
    file="$SCRIPT_DIR/../agents/$name.md"
    if [ ! -f "$file" ]; then
      printf '  DECLARED BUT ABSENT    %-24s <- no agents/%s.md\n' "$name" "$name"
      adrift=$((adrift + 1))
    elif ! grep -qF "$elem" "$file"; then
      printf '  SPEAKS UNDECLARED      %-24s <- never names its element %s\n' "$name" "$elem"
      adrift=$((adrift + 1))
    else
      printf '  declared and bounded   %-24s speaks in %s\n' "$name" "$elem"
    fi
  done <<EOF
$(gf_contract_agents)
EOF
  for a in "$SCRIPT_DIR"/../agents/*.md; do
    [ -f "$a" ] || continue
    name="$(basename "$a" .md)"
    gf_contract_agents | cut -d'|' -f1 | grep -qx "$name" || {
      printf '  UNDECLARED AGENT       %-24s <- exists but the contract never names it\n' "$name"
      adrift=$((adrift + 1))
    }
  done

  # Direction 4: the declared policy DEFAULTS must be the defaults the code
  # writes, and the declared ENUMERATION must be what `set` accepts. A README
  # claiming "default warn" over code that writes "off" is the oldest drift
  # there is; the ATTLIST makes it checkable instead of proofread.
  local pname penum pdef pdrift=0 upper code_def
  while read -r pname penum pdef; do
    [ -n "$pname" ] || continue
    upper="GATE_$(printf '%s' "$pname" | tr '[:lower:]' '[:upper:]')"
    code_def="$(sed -n "s/.*state_set $upper  *\"\${GF_$upper:-\([a-z]*\)}\".*/\1/p" "$SCRIPT_DIR/goal.sh" | head -n1)"
    if [ -z "$code_def" ]; then
      printf '  POLICY UNBOUND         %-24s <- cmd_init does not set it\n' "$upper"; pdrift=$((pdrift + 1))
    elif [ "$code_def" = "$pdef" ]; then
      printf '  declared default holds %-24s %-6s (%s)\n' "$upper" "$pdef" "$penum"
    else
      printf '  POLICY DRIFT           %-24s contract says %s, code writes %s\n' "$upper" "$pdef" "$code_def"
      pdrift=$((pdrift + 1))
    fi
  done <<EOF
$(gf_contract_policies)
EOF

  # Direction 5: every channel declared UNTRUSTED must reach a reader only
  # through the fence. This is the check that scales -- a third call site added
  # next year cannot quietly render raw command output in the engine's voice.
  local cent cpath cnot cdrift=0 fenced_sites
  fenced_sites="$(grep -l 'gf_quarantine' "$SCRIPT_DIR"/*.sh 2>/dev/null | wc -l | tr -d ' ')"
  while read -r cent cpath cnot; do
    [ -n "$cent" ] || continue
    case "$cnot" in
      untrusted-text)
        if [ "${fenced_sites:-0}" -ge 1 ]; then
          printf '  untrusted, fenced      %-24s %s\n' "$cent" "$cnot"
        else
          printf '  UNFENCED CHANNEL       %-24s <- nothing calls gf_quarantine\n' "$cent"
          cdrift=$((cdrift + 1))
        fi ;;
      trusted-by-provenance)
        printf '  trusted by provenance  %-24s %s\n' "$cent" "$cnot" ;;
      *)
        printf '  declared channel       %-24s %s\n' "$cent" "$cnot" ;;
    esac
  done <<EOF
$(gf_contract_channels)
EOF

  laws="$(grep -c '<!ENTITY LAW\.' "$dtd")"
  echo
  echo "verdict strings declared: $tokens   unused: $missing   laws declared: $laws"
  echo "agents declared: $acount   roster drift: $adrift"
  echo "policies bound: $(gf_contract_policies | wc -l | tr -d ' ')   policy drift: $pdrift"
  echo "channels declared: $(gf_contract_channels | wc -l | tr -d ' ')   channel drift: $cdrift"
  echo "records declared: $(gf_schema_records | grep -c '|')"
  echo "untrusted text is fenced with: $GF_FENCE_OPEN ... $GF_FENCE_CLOSE"
  [ "$missing" -eq 0 ] || { echo; echo "CONTRACT DRIFT: $missing declared verdict(s) no script emits."; return 1; }
  [ "$adrift" -eq 0 ] || { echo; echo "CONTRACT DRIFT: $adrift agent(s) undeclared, absent, or speaking out of turn."; return 1; }
  [ "$pdrift" -eq 0 ] || { echo; echo "CONTRACT DRIFT: $pdrift gate policy default(s) disagree with the code."; return 1; }
  [ "$cdrift" -eq 0 ] || { echo; echo "CONTRACT DRIFT: $cdrift untrusted channel(s) reach a reader unfenced."; return 1; }
  echo "CONTRACT OK: every declared verdict is real, every agent is bounded, and untrusted text is fenced."
}

cmd_schema() { # [--verify]
  # THE RECORD SCHEMA -- Protobuf's discipline, over plain TSV.
  #
  # This project's recurring defect has never been logic; it has been COLUMN
  # DRIFT. The ledger grew a fifth column, the timings file a sixth, and each
  # time some reader kept working while meaning something else. Numbered,
  # append-only fields are the fix that serialisation formats settled on
  # decades ago, and nothing about it requires a serialiser: it requires that
  # the numbering be DECLARED and CHECKED.
  local dtd decl name path fields n prev_since drift=0 rec=0
  dtd="$(gf_contract_file)"
  [ -f "$dtd" ] || die "trust_contract.dtd is missing -- the record schema is undeclared."

  if [ "${1:-}" != "--verify" ]; then
    echo "RECORD SCHEMA -- declared in hooks/trust_contract.dtd, read by this command."
    echo
    while IFS= read -r decl; do
      [ -n "$decl" ] || continue
      printf '%s  (%s)\n' "$(gf_schema_name "$decl")" "$(gf_schema_path "$decl")"
      gf_schema_fields "$decl" | while read -r n name model since; do
        printf '    %2s  %-20s %-7s since %s\n' "$n" "$name" "$model" "$since"
      done
      echo
    done <<EOF
$(gf_schema_records)
EOF
    echo "PCDATA = structured text the engine parses.  CDATA = raw text, never interpreted."
    echo "run 'goal.sh schema --verify' to check the declaration and the files on disk."
    return 0
  fi

  echo "RECORD SCHEMA -- append-only discipline, checked."
  echo
  while IFS= read -r decl; do
    [ -n "$decl" ] || continue
    rec=$((rec + 1))
    name="$(gf_schema_name "$decl")"; path="$(gf_schema_path "$decl")"
    # 1. dense numbering from 1, no gaps, no duplicates
    local nums expect=1 dense=1 maxn=0
    nums="$(gf_schema_fields "$decl" | awk '{print $1}')"
    for n in $nums; do
      [ "$n" -eq "$expect" ] || dense=0
      expect=$((expect + 1)); maxn="$n"
    done
    # 2. `since` never decreases as the number grows -- this IS append-only:
    #    inserting or renumbering a field makes an older version appear later.
    local since_list ordered=1
    since_list="$(gf_schema_fields "$decl" | awk '{print $4}')"
    prev_since=""
    for s in $since_list; do
      if [ -n "$prev_since" ]; then
        # Compare by declaration order of known versions, oldest first.
        local pi si i=0
        pi=""; si=""
        for known in v2 v3.0 v3.1 v3.2 v3.3 v3.4 v3.5 1.0.0; do
          [ "$known" = "$prev_since" ] && pi="$i"
          [ "$known" = "$s" ] && si="$i"
          i=$((i + 1))
        done
        [ -n "$pi" ] && [ -n "$si" ] || { echo "  UNKNOWN VERSION in $name: $prev_since or $s"; drift=$((drift + 1)); }
        [ -n "$pi" ] && [ -n "$si" ] && [ "$si" -lt "$pi" ] && ordered=0
      fi
      prev_since="$s"
    done
    # 2b. the two independent declarations must agree, name for name, in order.
    #     One is Protobuf-shaped (numbered, append-only); the other is ordinary
    #     DTD (a sequence content model). Redundancy is only worth having if
    #     something checks it, so this is what checks it.
    local seq_decl numbered_names
    seq_decl="$(gf_schema_sequence "$name")"
    numbered_names="$(gf_schema_fields "$decl" | awk '{print $2}' | tr '\n' ' ' | sed 's/ *$//')"
    seq_decl="$(printf '%s' "$seq_decl" | sed 's/ *$//')"
    if [ -z "$seq_decl" ]; then
      printf '  %-12s NO SEQUENCE MODEL -- declared once, so nothing cross-checks it\n' "$name"
      drift=$((drift + 1))
    elif [ "$seq_decl" = "$numbered_names" ]; then
      printf '  %-12s both declarations agree: (%s)\n' "$name" "$(printf '%s' "$seq_decl" | tr ' ' ',')"
    else
      printf '  %-12s DECLARATIONS DISAGREE\n' "$name"
      printf '  %-12s   numbered: %s\n' "" "$numbered_names"
      printf '  %-12s   sequence: %s\n' "" "$seq_decl"
      drift=$((drift + 1))
    fi
    if [ "$dense" -eq 1 ]; then printf '  %-12s numbering dense 1..%s\n' "$name" "$maxn"
    else printf '  %-12s NUMBERING BROKEN -- gap, duplicate or reorder\n' "$name"; drift=$((drift + 1)); fi
    if [ "$ordered" -eq 1 ]; then printf '  %-12s append-only: no field predates the one before it\n' "$name"
    else printf '  %-12s APPEND-ONLY VIOLATED -- a later field claims an earlier version\n' "$name"; drift=$((drift + 1)); fi

    # 3. if the file exists here, its widest row must match the declaration
    local live="$GF_PROJECT/$path"
    [ -f "$live" ] || live="$SCRIPT_DIR/../$path"
    if [ -f "$live" ]; then
      local widest
      widest="$(awk -F'\t' '!/^#/ && NF > m { m = NF } END { print m+0 }' "$live")"
      # THE DIRECTION MATTERS, and getting it wrong was this command's first
      # bug. Append-only means a reader must TOLERATE a narrower legacy row --
      # a ledger written before the seal-generation field exists with four
      # columns and is deliberately still readable (gf_flaky_ids includes
      # gen-less rows rather than hiding them). What can never happen is a row
      # WIDER than the declaration: that is a field nobody declared, written by
      # code nobody audited. So the rule is `widest <= maxn`, and a narrow file
      # is reported as legacy rather than counted as drift.
      if [ "$widest" -eq 0 ]; then
        printf '  %-12s on disk: empty, nothing to check\n' "$name"
      elif [ "$widest" -eq "$maxn" ]; then
        printf '  %-12s on disk: %s columns, matching field %s\n' "$name" "$widest" "$maxn"
      elif [ "$widest" -lt "$maxn" ]; then
        printf '  %-12s on disk: %s columns -- legacy rows, tolerated by design\n' "$name" "$widest"
      else
        printf '  %-12s ON DISK: %s columns, schema declares only %s -- UNDECLARED FIELD\n' "$name" "$widest" "$maxn"
        drift=$((drift + 1))
      fi
    fi
  done <<EOF
$(gf_schema_records)
EOF
  echo
  echo "records checked: $rec   drift: $drift"
  [ "$drift" -eq 0 ] || { echo; echo "SCHEMA DRIFT: $drift problem(s) above."; return 1; }
  echo "SCHEMA OK: every record is densely numbered and append-only."
}

cmd_forensics() {
  gf_exists || die "no goal exists."
  local map="$SCRIPT_DIR/../hooks/event_consumers.tsv" ev kind consumer note why n
  [ -f "$map" ] || die "event_consumers.tsv is missing -- the classification cannot be checked."
  echo "FORENSIC EVENTS -- every event classified 'forensic' must SURFACE here."
  echo "A classification that no report reads is the same decoration the consumer"
  echo "map was built to kill, one level up."
  echo
  echo "1.0.0 makes the classification a DECISION rather than a leftover: each row"
  echo "below states why acting on that event would be wrong, not merely that"
  echo "nothing acts on it. If a reason ever stops being true, the event should"
  echo "be promoted to 'decision' and given a consumer."
  echo
  while IFS="$(printf '\t')" read -r ev kind consumer note why; do
    case "$ev" in ''|'#'*) continue ;; esac
    [ "$kind" = "forensic" ] || continue
    n="$(grep -cE "EVENT $ev( |\$)" "$GF_JOURNAL" 2>/dev/null | head -n1)"
    printf '%-22s seen %-4s %s\n' "$ev" "${n:-0}" "$note"
    printf '%-22s      %-4s not decisional: %s\n' "" "" "${why:-UNSTATED -- this is a defect}"
  done < "$map"
  echo
  echo "decision events are consumed elsewhere: the gate (Stop), the guard"
  echo "(PreToolUse), freshness (PostToolUse/FileChanged), the snapshot"
  echo "(PreCompact) and the friction report (PermissionDenied,"
  echo "PostToolUseFailure, Elicitation). 'goal.sh events' shows raw counts."
}

cmd_timings() {
  gf_exists || die "no goal exists."
  local base id learned
  base="$(state_get CMD_TIMEOUT)"; base="${base:-120}"
  if [ ! -s "$GF_TIMINGS" ]; then
    echo "(no verify timings yet -- every criterion uses the configured ${base}s)"
    return 0
  fi
  echo "when                 criterion  allowed  took  outcome  gen"
  tail -n "${1:-20}" "$GF_TIMINGS" | while IFS=$'\t' read -r ts id allowed dur out gen; do
    [ "$ts" = "ts" ] && continue
    printf '%-20s %-10s %7s %5s  %-7s  %s\n' "$ts" "$id" "$allowed" "$dur" "$out" "${gen:-?}"
  done
  echo "(gen = seal generation. The flake window is generation-scoped, NOT time-scoped:"
  echo "'when' is for you, and a machine whose clock moves backwards cannot hide a flip.)"
  echo
  echo "next run would allow (configured CMD_TIMEOUT=${base}s, cap ${GF_TIMEOUT_MAX}s):"
  for id in $(crit_ids); do
    learned="$(gf_criterion_timeout "$id")"
    if [ "$learned" -gt "$base" ] 2>/dev/null; then
      printf '  %-10s %ss  (LEARNED -- grown from measured history)\n' "$id" "$learned"
    else
      printf '  %-10s %ss\n' "$id" "$learned"
    fi
  done
  echo
  echo "A learned timeout only ever GROWS: shrinking one could invent failures that"
  echo "are not real, and a verifier that manufactures failures is worse than a slow one."
}

cmd_status() {
  gf_exists || { echo "No goal. Start one with /goal <description>."; return 0; }
  local counts passed total
  counts="$(crit_counts)"; passed="${counts% *}"; total="${counts#* }"
  if [ "${1:-}" = "--brief" ]; then
    echo "[RoT DTD GOAL] $(gf_status) | $passed/$total criteria passed | iteration $(state_get ITERATION)/$(state_get MAX_ITERATIONS) | goal: $(state_get GOAL | head -c 100)"
    return 0
  fi
  echo "Goal:      $(state_get GOAL)"
  echo "Status:    $(gf_status)"
  echo "Progress:  $passed/$total criteria passed"
  echo "Iteration: $(state_get ITERATION)/$(state_get MAX_ITERATIONS)  (stall threshold $(state_get STALL_THRESHOLD))"
  local drift
  if drift="$(gf_ledger_audit)"; then
    echo "Integrity: ledger OK (all criteria match their sealed hashes)"
  else
    echo "Integrity: DRIFT -- $(printf '%s' "$drift" | tr '\n' ' ')"
  fi
  echo "Sharpened: $(state_get SHARPEN_COUNT || true)/$(state_get MAX_SHARPEN || true) criteria revisions used  (gate red team: $(state_get GATE_REDTEAM || true); gate mutation: $(state_get GATE_MUTATE || true))"
  [ -n "$(state_get NOTES || true)" ] && echo "Notes:     $(state_get NOTES)"
  echo "Criteria:"
  local id st mark
  for id in $(crit_ids); do
    st="$(crit_field "$id" status)"
    case "$st" in passed) mark="PASS";; failed) mark="FAIL";; *) mark="----";; esac
    echo "  [$mark] $id: $(crit_field "$id" desc)"
    echo "         verify: $(crit_field "$id" verify)"
    [ -n "$(crit_field "$id" deps || true)" ] && echo "         deps:   $(crit_field "$id" deps)"
    if [ "$st" = "failed" ] && [ -s "$GF_OUT/$id.log" ]; then
      echo "         last output: $(head -n1 "$GF_OUT/$id.log" | head -c 160)"
    fi
  done
}

cmd_verify() {
  local st; st="$(gf_status || true)"
  [ -n "$st" ] && [ "$st" != "draft" ] || die "no activated goal to verify."
  local res p f id
  res="$(gf_verify_all)"; p="${res% *}"; f="${res#* }"
  gf_journal "VERIFY manual pass=$p fail=$f"
  for id in $(gf_passed_ids); do echo "[PASS] $id: $(crit_field "$id" desc)"; done
  for id in $(gf_failed_ids); do
    echo "[FAIL] $id: $(crit_field "$id" desc)"
    gf_quarantine "$GF_OUT/$id.log" "output of $id"
  done
  echo
  echo "$p/$((p + f)) criteria passing."
  [ "$f" -eq 0 ]
}

cmd_journal() { tail -n "${1:-15}" "$GF_JOURNAL" 2>/dev/null || echo "(journal empty)"; }

cmd_transition() { # newstatus message
  gf_exists || die "no goal exists."
  case "$1" in aborted) gf_history_append aborted ;; esac
  state_set STATUS "$1"
  if [ "$1" = "active" ]; then state_set ITERATION 0; state_set SIG_STREAK 0; state_set LAST_SIG ""; fi
  gf_journal "STATUS -> $1"
  echo "$2"
}

cmd_set() {
  [ $# -eq 2 ] || die "usage: goal.sh set KEY VALUE"
  case "$1" in
    MAX_ITERATIONS|STALL_THRESHOLD|CMD_TIMEOUT|MAX_SHARPEN)
      printf '%s' "$2" | grep -Eq '^[0-9]+$' || die "$1 must be an integer."
      state_set "$1" "$2" ;;
    GATE_REDTEAM)
      case "$2" in off|warn|strict) state_set GATE_REDTEAM "$2" ;; *) die "GATE_REDTEAM must be off|warn|strict." ;; esac ;;
    GATE_MUTATE)
      case "$2" in off|warn|strict) state_set GATE_MUTATE "$2" ;; *) die "GATE_MUTATE must be off|warn|strict." ;; esac ;;
    GATE_FLAKY)
      case "$2" in off|warn|strict) state_set GATE_FLAKY "$2" ;; *) die "GATE_FLAKY must be off|warn|strict." ;; esac ;;
    NOTES) state_set NOTES "$(printf '%s' "$2" | tr '\n' ' ' | head -c 2000)" ;;
    *) die "key $1 is not settable. Criterion status is NEVER settable -- passes are earned by running the check." ;;
  esac
  gf_journal "SET $1=$2"
  echo "$1=$2"
}

cmd_version() {
  local pj="$SCRIPT_DIR/../.claude-plugin/plugin.json" v
  v="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$pj" 2>/dev/null | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
  # Machine name first so the version is always field 2 -- `awk '{print $2}'`
  # is how the suite and the attestation read it, and a display name with a
  # space in it would silently shift that field.
  echo "rot-dtd-goal ${v:-unknown}"
  echo "RoT DTD GOAL -- formerly goal-forge; the engine's lineage in CHANGELOG.md; published as 1.0.0"
  echo "capabilities: ledger-integrity redteam-negative-control mutation-probe content-mutation semantic-mutation gate-mutation compaction-snapshot criteria-sharpening deps-freshness cross-goal-learning learned-timeouts timings-rotation snapshot-ring flaky-detection gate-flaky event-consumer-map friction-feedback hostile-shell-suite event-rate-limit seal-scoped-flake attestation events-single-record forensic-surfacing inferred-deps-mutation generation-scoped-flake regression-flake-definition simultaneous-completion trust-contract untrusted-output-fencing goal-queue enforced-invariants 31-hook-events"
}

case "${1:-}" in
  init)     shift; cmd_init "$@" ;;
  add)      shift; cmd_add "$@" ;;
  activate) cmd_activate ;;
  status)   shift || true; cmd_status "${1:-}" ;;
  verify)   cmd_verify ;;
  journal)  shift || true; cmd_journal "${1:-15}" ;;
  audit)    cmd_audit ;;
  redteam)  shift || true; cmd_redteam "${1:-}" ;;
  mutate)   shift; cmd_mutate "$@" ;;
  sharpen)  shift; cmd_sharpen "$@" ;;
  seal)     shift; cmd_seal "$@" ;;
  learn)    cmd_learn ;;
  history)  shift || true; cmd_history "${1:-15}" ;;
  timings)  shift || true; cmd_timings "${1:-20}" ;;
  flaky)    cmd_flaky ;;
  events)   cmd_events ;;
  forensics) cmd_forensics ;;
  contract) shift || true; cmd_contract "$@" ;;
  schema)   shift || true; cmd_schema "$@" ;;
  queue)    shift || true; cmd_queue "$@" ;;
  attest)   shift || true; bash "$SCRIPT_DIR/attest.sh" "$@" ;;
  version|--version) cmd_version ;;
  pause)    cmd_transition paused "Goal paused. The stop-gate is dormant; /goal-resume to continue." ;;
  resume)   cmd_transition active "Goal resumed. Iteration budget and stall detector reset." ;;
  abort)    cmd_transition aborted "Goal aborted. State retained for post-mortem; /goal starts fresh." ;;
  set)      shift; cmd_set "$@" ;;
  *)        sed -n '2,31p' "$0"; exit 1 ;;
esac
