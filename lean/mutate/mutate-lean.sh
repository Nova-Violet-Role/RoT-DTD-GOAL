#!/usr/bin/env bash
# ============================================================================
# lean/mutate/mutate-lean.sh -- the suite that ATTACKS the proofs.
#
# WHY THIS EXISTS. `lake build` exiting 0 means the file elaborated. It does
# not mean the theorems say anything. A theorem that no mutation can kill is
# decorative: it is green because nothing binds it to the definition it claims
# to be about. So each of the eight mutations below breaks a DEFINITION on
# purpose, and the run passes only if the build then FAILS.
#
# Killed = the proofs caught it. Survived = a theorem that was decoration, and
# a defect in this specification. Discarded = the patch never applied, which is
# a defect in THIS HARNESS and is reported as its own outcome -- never folded
# into "survived", because those two read identically in a summary and mean
# opposite things.
#
# THREE RULES, each of which was learned by getting it wrong:
#   1. Count the needle in the file BEFORE building. A mutation that silently
#      failed to apply produces a green build that looks exactly like a robust
#      proof.
#   2. DELETE THE STALE .olean before rebuilding. Lake is incremental and will
#      happily not rebuild a module it believes is unchanged -- reporting the
#      PREVIOUS build's success for the mutant.
#   3. Restore and rebuild at the end. A mutation run that does not finish at a
#      verified-clean baseline has told you nothing about the final state.
#
# USAGE
#   bash lean/mutate/mutate-lean.sh                  # full run
#   GF_LEAN_WS=/path/to/mathlib/project bash lean/mutate/mutate-lean.sh
#
# EXIT CODES -- deliberately distinct, because they are different findings:
#   0  every mutation was applied and KILLED, tree restored, baseline green
#   1  a mutation SURVIVED -- a theorem is not load-bearing
#   2  a mutation could not be applied (DISCARDED) -- harness defect
#   3  no Lean workspace available -- NOT RUN, and not a pass
# ============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/../Proofs"

# The modules import Mathlib, so they need a Mathlib workspace with the cache
# already fetched. This is the author's; override it for yours.
WS="${GF_LEAN_WS:-D:/Lean/proofs}"
MODDIR="${GF_LEAN_MODDIR:-Proofs/GoalForge}"
NS="${GF_LEAN_NS:-Proofs.GoalForge}"

say() { printf '%s\n' "$*"; }

# ---------------------------------------------------------------- preflight
if ! command -v lake > /dev/null 2>&1; then
  say "NOT RUN: no \`lake\` on PATH."
  say "         This suite needs a Lean 4 toolchain and a Mathlib workspace."
  say "         Install elan, then re-run. Absence is reported, never passed."
  exit 3
fi
if [ ! -d "$WS/$MODDIR" ]; then
  say "NOT RUN: no module directory at $WS/$MODDIR"
  say "         Set GF_LEAN_WS to a Mathlib project and GF_LEAN_MODDIR to the"
  say "         directory the modules live in. Copy lean/Proofs/*.lean there"
  say "         first -- this harness mutates them in place and restores them."
  exit 3
fi

# ------------------------------------------------------- the mutation table
# FIVE LINES PER MUTATION: id, file, needle, replacement, description.
#
# Not a delimited table, and that is not fussiness: the obvious `id|file|...`
# form is UNPARSEABLE here, because the needles are Lean pattern matches and
# contain `|` themselves (`| none   => true`) and even `||`. A separator that
# occurs inside the data silently truncates every needle, every patch then
# fails to apply, and the run reports eight DISCARDED -- or worse, applies
# something other than what is written here. Records win over separators.
#
# The needle is a LITERAL substring. No regex, on purpose: escaping is exactly
# where a harness like this stops applying its own patches while still
# printing a reassuring summary.
mutations() {
  # SELF-TEST: one mutation that changes only a DOC COMMENT. It must SURVIVE,
  # and the run must then exit 1. This is the negative control for the harness
  # itself -- a mutation runner that has never reported a survivor is an
  # untested alarm, and would report "8/8 killed" just as cheerfully if it had
  # silently stopped building anything at all.
  #   GF_MUTATE_SELFTEST=1 bash lean/mutate/mutate-lean.sh   -> expect exit 1
  if [ -n "${GF_MUTATE_SELFTEST:-}" ]; then
    cat <<'SELFTEST'
S1
GoalQueue.lean
/-- The scheduler: the first eligible row, or nothing. -/
/-- The scheduler: the first eligible row, or none at all. -/
a doc comment is reworded -- nothing a theorem could possibly notice
SELFTEST
    return 0
  fi
  cat <<'TABLE'
L1
FlakyScope.lean
  | none   => true
  | none   => false
a row with no generation is DROPPED instead of kept
L2
FlakyScope.lean
      sawFail cid t || regressed cid t
      regressed cid t
the pass-then-fail check is removed
L3
FlakyScope.lean
  | some k => decide (g ≤ k)
  | some k => decide (k ≤ g)
the generation comparison is flipped
L4
FlakyScope.lean
  rows.filter (fun r => decide (cutoff ≤ r.ts))
  rows
the seal window is dropped entirely
L5
GoalQueue.lean
  | Status.pending, some d => statusOf q d == some Status.done
  | Status.pending, some _ => true
the dependency check is removed
L6
GoalQueue.lean
  q.find? (eligible q)
  q.head?
the scheduler ignores eligibility
L7
GoalQueue.lean
  | r :: t => (if r.status = Status.pending then 1 else 0) + pendingCount t
  | _ :: t => pendingCount t
the progress measure is flattened
L8
GoalQueue.lean
if r.name = n then { r with status := Status.active } else r
if r.name = n then { r with status := Status.pending } else r
starting a goal does not advance it
L9
FenceQuarantine.lean
def fence : List Char := [' ', ' ', '|', ' ']
def fence : List Char := ['R', ' ', '|', ' ']
the fence starts with the engine's own initial character
TABLE
}

# literal substring replacement, first occurrence per line, no regex anywhere
apply_needle() { # file needle replacement
  awk -v n="$2" -v r="$3" '
    { i = index($0, n)
      if (i > 0) { $0 = substr($0, 1, i - 1) r substr($0, i + length(n)) }
      print }' "$1" > "$1.mut" && mv "$1.mut" "$1"
}

count_needle() { # file needle -> integer, exactly one line
  # `grep -c` already prints 0 when there is no match -- and EXITS 1 while
  # doing it. The obvious `grep -c ... || echo 0` therefore prints TWO zeroes
  # on a clean file, and the caller's `[ "$n" -ne 0 ]` then dies with
  # "integer expression expected". Measured on the first real run of this
  # harness: it did not corrupt the verdict, but a numeric guard that throws
  # instead of comparing is one edit away from doing exactly that.
  local n
  n="$(grep -F -c -- "$2" "$1" 2>/dev/null)" || true
  printf '%s' "${n:-0}"
}

digest() { # file -> short hash, whichever tool exists
  if command -v sha256sum > /dev/null 2>&1; then sha256sum < "$1" | cut -c1-16
  elif command -v shasum   > /dev/null 2>&1; then shasum -a 256 < "$1" | cut -c1-16
  else openssl dgst -sha256 < "$1" | sed 's/.* //' | cut -c1-16; fi
}

# --------------------------------------------------------------- the baseline
say "LEAN MUTATION SUITE -- RoT DTD GOAL"
say "date: $(date '+%Y-%m-%d %H:%M:%S')"
say "workspace: $WS   modules: $NS.*"
say ""
say "rule: the needle is COUNTED before the build; the stale .olean is DELETED"
say "      before each rebuild; a patch that did not apply is DISCARDED, never"
say "      recorded as survived."
say ""

BUILD_TARGETS=""
for f in "$SRC"/*.lean; do
  b="$(basename "$f" .lean)"
  BUILD_TARGETS="$BUILD_TARGETS $NS.$b"
done

build() { # -> exit code of lake, read DIRECTLY
  ( cd "$WS" && lake build $BUILD_TARGETS ) > /tmp/gf-lean-build.log 2>&1
  return $?
}

drop_olean() { # module-basename
  rm -f "$WS/.lake/build/lib/lean/${MODDIR}/$1.olean" \
        "$WS/.lake/build/lib/lean/${MODDIR}/$1.ilean" \
        "$WS/.lake/build/lib/${MODDIR}/$1.olean" 2>/dev/null
  return 0
}

say "baseline build ..."
if build; then
  say "  baseline: exit 0 -- the proofs are green before anything is broken"
else
  say "  BASELINE IS RED (exit non-zero). Nothing below would mean anything."
  tail -20 /tmp/gf-lean-build.log
  exit 2
fi
say ""

KILLED=0; SURVIVED=0; DISCARDED=0
SURVIVORS=""

while IFS= read -r id && IFS= read -r file && IFS= read -r needle \
      && IFS= read -r repl && IFS= read -r what; do
  [ -n "${id:-}" ] || continue
  target="$WS/$MODDIR/$file"
  base="$(basename "$file" .lean)"
  before_hash="$(digest "$target")"
  cp "$target" "$target.bak"

  n_before="$(count_needle "$target" "$needle")"
  if [ "$n_before" -ne 1 ]; then
    printf '%-4s %-34s DISCARDED (needle appears %s times, expected 1)\n' \
           "$id" "$(printf '%.34s' "$what")" "$n_before"
    DISCARDED=$((DISCARDED + 1))
    rm -f "$target.bak"
    continue
  fi

  apply_needle "$target" "$needle" "$repl"
  n_after="$(count_needle "$target" "$needle")"
  if [ "$n_after" -ne 0 ]; then
    printf '%-4s %-34s DISCARDED (patch did not land)\n' "$id" "$(printf '%.34s' "$what")"
    DISCARDED=$((DISCARDED + 1))
    mv "$target.bak" "$target"
    continue
  fi

  drop_olean "$base"
  if build; then
    printf '%-4s %-34s SURVIVED  <-- the proofs did not notice\n' "$id" "$(printf '%.34s' "$what")"
    SURVIVED=$((SURVIVED + 1))
    SURVIVORS="$SURVIVORS $id"
  else
    # WHICH theorem died. Attribution by DEPENDENCY, not by vibes: take the
    # first error location Lean reports, then walk backwards in the file for
    # the declaration that encloses it. A mutation report that says only
    # "the build failed" cannot tell a load-bearing theorem from a typo.
    # MEASURED format, not assumed: lake prints `error: <path>:LINE:COL: ...`
    # -- the word `error` comes FIRST. A pattern expecting `:LINE:COL: error`
    # matched nothing and silently produced no attribution at all, which is
    # the quiet way a report stops reporting.
    lines="$(awk -v f="$file" '
      /error: / && index($0, f) > 0 {
        s = $0; sub(/.*\.lean:/, "", s); sub(/:.*/, "", s); print s
      }' /tmp/gf-lean-build.log | sort -n -u)"
    decls="$(for ln in $lines; do
               awk -v n="$ln" 'NR <= n && /^(theorem|lemma|example) / { d = $2 } END { if (d != "") print d }' "$target"
             done | awk '!seen[$0]++' | head -4 | tr '\n' ' ' | sed 's/ $//')"
    printf '%-4s %-34s KILLED%s\n' "$id" "$(printf '%.34s' "$what")" \
           "${decls:+ -- broke: $decls}"
    KILLED=$((KILLED + 1))
  fi

  mv "$target.bak" "$target"
  drop_olean "$base"
  after_hash="$(digest "$target")"
  if [ "$before_hash" != "$after_hash" ]; then
    say "     RESTORE FAILED for $file -- tree is NOT as it was. Stopping."
    exit 2
  fi
done <<EOF
$(mutations)
EOF

say ""
say "restoring and rebuilding the clean tree ..."
if build; then
  say "  baseline restored: exit 0"
  RESTORED=0
else
  say "  RESTORED TREE IS RED -- the harness left damage behind"
  tail -20 /tmp/gf-lean-build.log
  RESTORED=1
fi

say ""
say "killed: $KILLED   survived: $SURVIVED   discarded: $DISCARDED"
[ -n "$SURVIVORS" ] && say "survivors:$SURVIVORS -- each is a theorem that is not load-bearing"
say ""
if [ "$RESTORED" -ne 0 ]; then say "VERDICT: HARNESS FAILURE (tree not restored)"; exit 2; fi
if [ "$DISCARDED" -ne 0 ]; then say "VERDICT: HARNESS FAILURE ($DISCARDED mutation(s) never applied)"; exit 2; fi
if [ "$SURVIVED"  -ne 0 ]; then say "VERDICT: SPECIFICATION TOO WEAK ($SURVIVED survived)"; exit 1; fi
say "VERDICT: every mutation was applied and killed."
exit 0
