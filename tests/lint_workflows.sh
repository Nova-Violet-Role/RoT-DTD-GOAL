#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR EUPL-1.2
# Copyright 2026 Saimonokuma. Part of RoT DTD GOAL.
#
# WORKFLOW LINT -- catches the class of defect that cost this repository six red
# CI runs, and one of them was a RELEASE run.
#
# The specific bug: a blanket rename rewrote a path inside ci.yml into
# `lean/Proofs-instruments.log`, a file that has never existed. Nothing on this
# machine could see it. The workflow is only parsed by GitHub, so the first
# instrument that could fail was a push -- the slowest, most public feedback
# loop available, and the one that burns a release tag if the tag is what
# triggered it.
#
# This runs BEFORE the matrix and is the cheapest job in the file.
#
#   bash tests/lint_workflows.sh;  echo "exit=$?"
#
# EXIT: 0 clean, 1 a defect was found, 3 NOT RUN (no workflows on disk).
#
# On the YAML parse: a real parser is used when one is present -- yq, then
# ruby's built-in psych. Deliberately NOT python. When neither exists the
# structural checks still run and the script SAYS the parse was skipped;
# set GF_REQUIRE_YAML_PARSER=1 (CI does) to turn that skip into a failure, so
# the parse cannot silently stop happening on the one machine that matters.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WFDIR="$ROOT/.github/workflows"
fail=0
checks=0

bad()  { printf 'FAIL  %s\n' "$*"; fail=$((fail + 1)); }
ok()   { printf 'ok    %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }
count(){ checks=$((checks + 1)); }

[ -d "$WFDIR" ] || { printf 'NOT RUN: %s does not exist\n' "$WFDIR"; exit 3; }
# NOT `ls "$WFDIR"/*.yml "$WFDIR"/*.yaml` -- ls exits non-zero when EITHER
# glob fails to match, so a repo with only .yml files reported NOT RUN and
# linted nothing. Caught on the first run of this file.
found=0
for wf in "$WFDIR"/*.yml "$WFDIR"/*.yaml; do [ -f "$wf" ] && found=$((found + 1)); done
[ "$found" -gt 0 ] || { printf 'NOT RUN: no workflow files in %s\n' "$WFDIR"; exit 3; }

for wf in "$WFDIR"/*.yml "$WFDIR"/*.yaml; do
  [ -f "$wf" ] || continue
  rel="${wf#$ROOT/}"
  printf '\n== %s ==\n' "$rel"

  # 1. TABS. YAML forbids them for indentation, and the error GitHub returns
  #    names a line number without saying why -- easy to stare past.
  count
  if [ "$(awk '/\t/ { n++ } END { print n+0 }' "$wf")" -eq 0 ]; then
    ok "no tab characters"
  else
    bad "$rel contains tab characters (illegal as YAML indentation)"
    awk '/\t/ { printf "      line %d\n", FNR }' "$wf"
  fi

  # 2. CR bytes. A workflow with CRLF runs, but every heredoc inside it ends
  #    up with a stray \r that breaks string comparisons in the shell steps.
  count
  crn=$(tr -dc '\r' < "$wf" | wc -c | tr -d ' ')
  [ "$crn" -eq 0 ] && ok "no CR bytes" || bad "$rel has $crn CR bytes"

  # 3. Every `uses:` must be version-pinned. An unpinned action is a supply
  #    chain hole AND a source of surprise breakage on someone else's release.
  count
  unpinned=$(awk '
    /^[[:space:]]*(- )?uses:[[:space:]]*[^ ]/ {
      line = $0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      if (line !~ /@/ && line !~ /^\.\//) printf "line %d: %s\n", FNR, line
    }' "$wf")
  [ -z "$unpinned" ] && ok "every uses: is pinned" \
    || { bad "$rel has unpinned action references"; printf '      %s\n' "$unpinned"; }

  # 4. Every job needs runs-on, or GitHub refuses the whole file at dispatch
  #    time -- which means the failure is invisible until push.
  count
  jobs_n=$(awk '/^jobs:/ { inj = 1; next } inj && /^  [a-zA-Z0-9_-]+:/ { n++ } END { print n+0 }' "$wf")
  runson_n=$(grep -c '^ *runs-on:' "$wf")
  [ "$jobs_n" -gt 0 ] && [ "$runson_n" -ge "$jobs_n" ] \
    && ok "$jobs_n jobs, $runson_n runs-on declarations" \
    || bad "$rel declares $jobs_n jobs but only $runson_n runs-on"

  # 5. THE ONE THAT ACTUALLY BIT. Every repo-relative path named in the file
  #    must exist. Globs, variables and expressions are skipped -- and the
  #    skip list is narrow on purpose, because a generous skip list turns this
  #    check into decoration.
  count
  missing=0; seen=0
  for p in $(grep -oE '(^|[^A-Za-z0-9_./-])(EVIDENCE|scripts|tests|hooks|lean|agents|commands|docs)/[A-Za-z0-9_./*-]+' "$wf" \
             | sed 's/^[^A-Za-z]*//' | sort -u); do
    case "$p" in
      *'*'*|*'$'*|*'{'*|*'..'*) continue ;;
    esac
    p="${p%.}"          # a path that ended a sentence in a comment
    seen=$((seen + 1))
    [ -e "$ROOT/$p" ] || { bad "$rel names a path that does not exist: $p"; missing=$((missing + 1)); }
  done
  [ "$missing" -eq 0 ] && ok "$seen repo paths named, all present"

  # 6. A step that reads an exit code through a pipe. This is the repo's own
  #    cardinal sin and CI is the last place it should appear.
  #    The rule is deliberately NARROW. A first version flagged
  #    `bash --version | head -1`, which reads nothing and decides nothing --
  #    a linter that cries wolf on printing a version gets switched off, and
  #    then it is not protecting anything. Only a command whose EXIT CODE is
  #    the verdict counts: the suite, the CLI, the attestation, a build.
  count
  piped=$(grep -nE '(run_tests\.sh|goal\.sh|attest\.sh|lake build)[^|]*\|' "$wf" | grep -v 'PIPESTATUS' || true)
  if [ -z "$piped" ]; then
    ok "no verdict-bearing command is piped"
  elif grep -qE '^ *shell: bash$' "$wf"; then
    # `shell: bash` in Actions is `bash --noprofile --norc -eo pipefail`, so a
    # pipe does not mask the left-hand exit code. That makes these lines safe
    # -- but safe BECAUSE OF a setting elsewhere in the file, which is exactly
    # the kind of coupling that breaks quietly. Reported, not failed.
    ok "verdict-bearing pipes exist but the file sets shell: bash (pipefail)"
    printf '      %s\n' "$piped"
    note "these are safe only while that default stands -- prefer PIPESTATUS"
  else
    bad "$rel pipes a verdict-bearing command with no pipefail default and no PIPESTATUS"
    printf '      %s\n' "$piped"
  fi
done

# 7. THE REAL PARSE. Structural checks above cannot catch a mis-indented key;
#    only a parser can. yq first, then ruby's built-in psych. Not python.
count
parser=""
if   command -v yq   >/dev/null 2>&1; then
  # Two unrelated tools ship under the name `yq`: mikefarah's Go yq, which
  # wants `yq eval '.' FILE`, and kislyuk's Python jq-wrapper, which reads
  # `eval` as the FILTER and `.` as a FILENAME -- so the Go invocation
  # "fails" on YAML that is fine. Found on a machine with the Python one.
  if yq --version 2>&1 | grep -qi mikefarah; then parser="yq-go"; else parser="yq-py"; fi
elif command -v ruby >/dev/null 2>&1; then parser="ruby"
fi
printf '\n== parse ==\n'
if [ -n "$parser" ]; then
  perr=0
  for wf in "$WFDIR"/*.yml "$WFDIR"/*.yaml; do
    [ -f "$wf" ] || continue
    case "$parser" in
      yq-go) yq eval '.' "$wf" >/dev/null 2>&1 || { bad "yq cannot parse ${wf#$ROOT/}"; perr=1; } ;;
      yq-py) yq '.' "$wf" >/dev/null 2>&1 || { bad "yq cannot parse ${wf#$ROOT/}"; perr=1; } ;;
      ruby) ruby -ryaml -e 'YAML.unsafe_load_file(ARGV[0]) rescue YAML.load_file(ARGV[0])' "$wf" >/dev/null 2>&1 \
              || { bad "ruby/psych cannot parse ${wf#$ROOT/}"; perr=1; } ;;
    esac
  done
  [ "$perr" -eq 0 ] && ok "every workflow parses as YAML (via $parser)"
else
  if [ "${GF_REQUIRE_YAML_PARSER:-0}" = "1" ]; then
    bad "no YAML parser found and GF_REQUIRE_YAML_PARSER=1 -- the parse did NOT happen"
  else
    note "SKIPPED: no yq and no ruby on this machine, so nothing PARSED the YAML."
    note "         The structural checks above still ran. CI sets"
    note "         GF_REQUIRE_YAML_PARSER=1, where this skip is a failure."
  fi
fi

printf '\n%d checks, %d failed\n' "$checks" "$fail"
[ "$fail" -eq 0 ] || exit 1
exit 0
